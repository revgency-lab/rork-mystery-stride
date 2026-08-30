//
//  ARLensView.swift
//  MysteryRun
//

import CoreLocation
import SwiftUI

/// The camera half of the live investigation: the real street through the lens
/// with unfound evidence pinned to its real-world spot, glowing in the dark.
/// Toggled freely against the map view during a run.
struct ARLensView: View {
    @Environment(InvestigationEngine.self) private var engine
    @Environment(LocationService.self) private var location

    @State private var camera = CameraService()
    @State private var attitude = AttitudeService()
    @State private var viewport: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                cameraFeed
                lensOverlay(in: geometry.size)
            }
            .onAppear {
                viewport = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                viewport = newSize
            }
        }
        .ignoresSafeArea()
        .background(Theme.ink)
        .preferredColorScheme(.dark)
        .onAppear {
            camera.start()
            attitude.start()
        }
        .onDisappear {
            camera.stop()
            attitude.stop()
        }
    }

    // MARK: - Feed

    @ViewBuilder
    private var cameraFeed: some View {
        switch camera.status {
        case .running, .requesting:
            CameraPreviewView(session: camera.session)
                .overlay {
                    // Noir grade: sink the feed into the app's ink so HUD and
                    // glowing evidence stay readable even in daylight.
                    LinearGradient(
                        colors: [Theme.ink.opacity(0.42), .clear, Theme.ink.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
                .overlay {
                    RadialGradient(
                        colors: [.clear, Theme.ink.opacity(0.4)],
                        center: .center,
                        startRadius: 0.6 * min(viewport.width, viewport.height),
                        endRadius: 0.85 * max(viewport.width, viewport.height)
                    )
                    .allowsHitTesting(false)
                }
        case .denied:
            CameraDeniedView()
        default:
            // No camera on this device — keep the evidence visible over ink so
            // the approach flow still works, with an honest explanation.
            ZStack {
                Theme.ink
                VStack(spacing: 10) {
                    Image(systemName: "video.slash")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                    Text("No camera available here")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    // MARK: - Evidence overlay

    @ViewBuilder
    private func lensOverlay(in size: CGSize) -> some View {
        let targets = arTargets(in: size)

        ZStack {
            ForEach(targets.secondary) { target in
                PinDot(target: target)
            }

            if let primary = targets.primary {
                PrimaryCluePin(
                    target: primary,
                    isCollectible: canCollect,
                    compassAvailable: attitude.isAvailable,
                    onCollect: { engine.markNextClueFound() }
                )
            }

            if !attitude.isAvailable {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "location.circle")
                        Text("Compass unavailable — evidence stays centred")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: .capsule)
                    .padding(.bottom, 10)
                }
            }
        }
    }

    private var canCollect: Bool {
        guard let distance = engine.distanceToNextClue else { return false }
        return distance <= 150
    }

    private func arTargets(in size: CGSize) -> TargetSet {
        guard size.width > 1 else { return TargetSet(primary: nil, secondary: []) }

        var primary: ARTarget?
        var secondary: [ARTarget] = []

        for clue in engine.mysteryCase?.clues ?? [] where !clue.isFound {
            let isNext = clue.id == engine.nextClue?.id
            let distance = arDistance(to: clue.point)

            guard isNext else {
                if attitude.isAvailable,
                   let point = project(clue.point, heightAboveGround: 1.0, in: size),
                   size.boundsContains(point) {
                    secondary.append(
                        ARTarget(
                            clue: clue,
                            screenPoint: point,
                            groundPoint: nil,
                            state: .onScreen,
                            scale: 0.6,
                            distance: distance
                        )
                    )
                }
                continue
            }

            guard let user = userPoint else { continue }

            if attitude.isAvailable {
                if let point = project(clue.point, heightAboveGround: 1.0, in: size),
                   size.boundsContains(point) {
                    let ground = project(clue.point, heightAboveGround: 0, in: size)
                    primary = ARTarget(
                        clue: clue,
                        screenPoint: point,
                        groundPoint: size.boundsContains(ground ?? point) ? ground : nil,
                        state: .onScreen,
                        scale: GeoAR.markerScale(forDistance: distance),
                        distance: distance
                    )
                } else {
                    // Behind you or out of frame: clamp to the edge and point.
                    let edge = GeoAR.edgePoint(
                        bearingDegrees: GeoAR.bearingDegrees(from: user, to: clue.point),
                        matrix: attitude.matrix,
                        viewport: size
                    )
                    primary = ARTarget(
                        clue: clue,
                        screenPoint: edge,
                        groundPoint: nil,
                        state: .offScreen,
                        scale: 1,
                        distance: distance
                    )
                }
            } else {
                // No compass (simulator, magnetometer-less hardware): centre the
                // evidence so the approach flow still works.
                primary = ARTarget(
                    clue: clue,
                    screenPoint: CGPoint(x: size.width / 2, y: size.height * 0.42),
                    groundPoint: nil,
                    state: .centred,
                    scale: GeoAR.markerScale(forDistance: distance),
                    distance: distance
                )
            }
        }

        return TargetSet(primary: primary, secondary: secondary)
    }

    private func project(_ point: GeoPoint, heightAboveGround: Double, in size: CGSize) -> CGPoint? {
        guard let user = userPoint else { return nil }
        return GeoAR.project(
            from: user,
            to: point,
            heightAboveGround: heightAboveGround,
            matrix: attitude.matrix,
            viewport: size,
            declinationDegrees: location.declination
        )
    }

    private func arDistance(to point: GeoPoint) -> Double {
        if let next = engine.nextClue, next.point == point, let nextDistance = engine.distanceToNextClue {
            return nextDistance
        }
        guard let user = userPoint else { return 0 }
        return user.distance(to: point)
    }

    private var userPoint: GeoPoint? {
        if let fix = location.location {
            return GeoPoint(fix.coordinate)
        }
        return engine.currentPoint
    }
}

private extension CGSize {
    func boundsContains(_ point: CGPoint?) -> Bool {
        guard let point else { return false }
        return point.x > 20 && point.x < width - 20 && point.y > 40 && point.y < height - 40
    }
}

// MARK: - Target model

/// One piece of evidence resolved into screen space.
private struct ARTarget: Identifiable {
    enum State {
        case onScreen
        case offScreen
        case centred
    }

    let clue: Clue
    let screenPoint: CGPoint
    let groundPoint: CGPoint?
    let state: State
    let scale: CGFloat
    let distance: Double

    var id: UUID { clue.id }
}

private struct TargetSet {
    var primary: ARTarget?
    var secondary: [ARTarget]
}

// MARK: - Primary clue pin

/// The glowing evidence: distance readout, artifact glyph, summoning ring and
/// the stamped clue title. Tappable to collect once you're genuinely close.
private struct PrimaryCluePin: View {
    let target: ARTarget
    let isCollectible: Bool
    let compassAvailable: Bool
    let onCollect: () -> Void

    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            switch target.state {
            case .onScreen:
                onScreenPin
            case .offScreen:
                edgePointer
            case .centred:
                onScreenPin
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var onScreenPin: some View {
        let diameter = max(64, 78 * target.scale)

        return ZStack {
            if let ground = target.groundPoint {
                SummoningRing(point: ground, pulse: pulse)
            }

            VStack(spacing: 12) {
                distanceReadout
                glyph(diameter: diameter)
                titleLabel
            }
            .position(target.screenPoint)
        }
    }

    private var distanceReadout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(Int(target.distance.rounded()), format: .number)
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .monospacedDigit()
            Text("M")
                .font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .foregroundStyle(Theme.brass)
        .shadow(color: Theme.brass.opacity(0.6), radius: 12)
        .contentTransition(.numericText())
    }

    private func glyph(diameter: CGFloat) -> some View {
        Button {
            if isCollectible { onCollect() }
        } label: {
            ZStack {
                Circle()
                    .fill(Theme.brass.opacity(0.14))
                    .frame(width: diameter, height: diameter)

                Circle()
                    .strokeBorder(Theme.brass.opacity(0.85), lineWidth: 2)
                    .frame(width: diameter, height: diameter)
                    .shadow(color: Theme.brass.opacity(0.8), radius: 14)

                Circle()
                    .strokeBorder(Theme.brass.opacity(0.35), lineWidth: 1)
                    .frame(width: diameter * 1.28, height: diameter * 1.28)
                    .scaleEffect(pulse ? 1.12 : 0.95)
                    .opacity(pulse ? 0.15 : 0.7)

                Image(systemName: target.clue.symbolName)
                    .font(.system(size: diameter * 0.38, weight: .semibold))
                    .foregroundStyle(Theme.brass)
                    .shadow(color: Theme.brass.opacity(0.9), radius: 8)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isCollectible)
        .accessibilityLabel(
            isCollectible
                ? "Collect \(target.clue.title)"
                : "\(target.clue.title) is \(Int(target.distance)) metres away"
        )
    }

    private var titleLabel: some View {
        Text("Clue \(target.clue.index) · \(target.clue.title)".uppercased())
            .font(.system(size: 13, weight: .heavy, design: .monospaced))
            .tracking(2)
            .foregroundStyle(Theme.brass)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.ink.opacity(0.75), in: .rect(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.brass.opacity(0.8), lineWidth: 1.5)
            }
    }

    /// Chevrons hugging the screen edge in the clue's direction.
    private var edgePointer: some View {
        VStack(spacing: 6) {
            distanceReadout.font(.system(size: 22, weight: .heavy, design: .rounded))
            Image(systemName: "chevron.right")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Theme.brass)
                .shadow(color: Theme.brass.opacity(0.8), radius: 8)
        }
        .position(target.screenPoint)
        .accessibilityLabel("\(target.clue.title) is off screen, \(Int(target.distance)) metres away")
    }
}

// MARK: - Summoning ring

/// Glowing ellipse on the street where the evidence sits.
private struct SummoningRing: View {
    let point: CGPoint
    let pulse: Bool

    var body: some View {
        ZStack {
            Ellipse()
                .strokeBorder(Theme.brass.opacity(pulse ? 0.2 : 0.6), lineWidth: 2)
                .frame(width: 96, height: 30)
            Ellipse()
                .strokeBorder(Theme.brass.opacity(0.25), lineWidth: 1)
                .frame(width: 150, height: 46)
                .scaleEffect(pulse ? 1.15 : 0.9)
                .opacity(pulse ? 0.2 : 0.55)
        }
        .shadow(color: Theme.brass.opacity(0.5), radius: 10)
        .position(point)
    }
}

// MARK: - Secondary pin

/// Dim dot for evidence further along the route that happens to be in frame.
private struct PinDot: View {
    let target: ARTarget

    var body: some View {
        Circle()
            .fill(Theme.violet.opacity(0.55))
            .frame(width: 14, height: 14)
            .overlay {
                Circle().strokeBorder(Theme.violet.opacity(0.9), lineWidth: 1.5)
            }
            .shadow(color: Theme.violet.opacity(0.7), radius: 6)
            .position(target.screenPoint)
            .accessibilityLabel("Clue \(target.clue.index), \(Int(target.distance)) metres away")
    }
}

// MARK: - Denied state

private struct CameraDeniedView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Theme.ink
            VStack(spacing: 14) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.brass)
                Text("Camera access is off")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("The lens is only used to show evidence on the street. Nothing is recorded. Enable it in Settings to use the AR view.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brass)
            }
        }
    }
}
