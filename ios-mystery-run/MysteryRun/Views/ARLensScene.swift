//
//  ARLensScene.swift
//  MysteryRun
//

import SwiftUI
import simd

/// One piece of evidence to pin in the world, independent of the investigation
/// engine so the developer lab can rehearse with fabricated anchors.
///
/// Deliberately not named `ARAnchor`: that name belongs to ARKit, and shadowing
/// it silently breaks every `ARSessionDelegate` callback that takes one.
struct EvidenceAnchor: Identifiable {
    let id: UUID
    let index: Int
    let title: String
    let symbolName: String
    let point: GeoPoint
    let isPrimary: Bool
}

/// Everything the lens needs to place evidence for one frame.
///
/// Both tracking backends collapse into this, so the scene never branches on
/// which one is running: ARKit fills in a tracked pose, a real floor height and
/// a true-north frame, while the compass fallback supplies rotation only and a
/// magnetic frame that needs the declination applied.
struct ARWorldFrame {
    /// Live camera pose, or `nil` when nothing can be placed yet.
    var pose: GeoAR.CameraPose?

    /// Geo coordinate of the local frame's origin.
    var origin: GeoPoint?

    /// Magnetic declination to apply, or `nil` when the frame is already
    /// true-north aligned (which ARKit's is).
    var declination: Double?

    /// Height of the real floor in the local frame. Falls back to an assumed eye
    /// height when ARKit hasn't found a plane yet.
    var floorHeight: Double?

    /// Local positions that outrank the frame's own geodesy whenever present —
    /// either resolved by the Visual Positioning System, or staged deliberately
    /// around the detective for an indoor case whose route is somewhere else.
    var overrides: [UUID: SIMD3<Double>] = [:]

    /// True when position is genuinely tracked, so walking changes the distance.
    var tracksTranslation: Bool { pose?.tracksTranslation ?? false }

    /// Overridden anchors need no geo origin at all: their position in the local
    /// frame is already known, so geodesy never runs for them.
    var canPlace: Bool { pose != nil && (origin != nil || !overrides.isEmpty) }

    /// Ground level in the local frame.
    var groundHeight: Double { floorHeight ?? -GeoAR.eyeHeight }
}

/// Draws evidence anchored to real ground positions over the camera feed.
///
/// Everything is sized by projection rather than fixed point values: the ring on
/// the street is a real 1.1 m circle and the artifact is a real 0.8 m object, so
/// they shrink with distance exactly as a physical object would. That is what
/// sells the illusion of something actually sitting on the pavement.
struct ARLensScene: View {
    let anchors: [EvidenceAnchor]
    let frame: ARWorldFrame
    var collectRadius: Double = 30
    var onCollect: ((EvidenceAnchor, Double) -> Void)?

    @State private var pulse: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let resolved = resolve(in: size)

            ZStack {
                ForEach(resolved) { item in
                    switch item.placement {
                    case let .world(ground, air, ringWidth, diameter):
                        AnchoredCluePin(
                            anchor: item.anchor,
                            distance: item.distance,
                            groundPoint: ground,
                            airPoint: air,
                            ringWidth: ringWidth,
                            diameter: diameter,
                            viewport: size,
                            pulse: pulse,
                            isCollectible: isCollectible(item),
                            onCollect: { onCollect?(item.anchor, item.distance) }
                        )
                    case let .edge(point, pointsRight):
                        EdgePointer(
                            anchor: item.anchor,
                            distance: item.distance,
                            point: point,
                            pointsRight: pointsRight
                        )
                    case let .centred(point, diameter):
                        CentredCluePin(
                            anchor: item.anchor,
                            distance: item.distance,
                            point: point,
                            diameter: diameter,
                            pulse: pulse,
                            isCollectible: isCollectible(item),
                            onCollect: { onCollect?(item.anchor, item.distance) }
                        )
                    }
                }
            }
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 1), value: resolved.count)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private func isCollectible(_ item: ResolvedAnchor) -> Bool {
        onCollect != nil && item.anchor.isPrimary && item.distance <= collectRadius
    }

    // MARK: - Placement

    private func resolve(in size: CGSize) -> [ResolvedAnchor] {
        guard size.width > 1 else { return [] }

        guard let pose = frame.pose, frame.canPlace else {
            return centredFallback(in: size)
        }
        let origin = frame.origin

        let focal = pose.focal(viewport: size)
        let ground = frame.groundHeight
        let air = ground + GeoAR.clueHeight

        return anchors.compactMap { anchor -> ResolvedAnchor? in
            guard let flat = groundOffset(for: anchor, origin: origin) else { return nil }
            let airTarget = SIMD3(flat.x, flat.y, air)
            let distance = GeoAR.groundDistance(from: pose, to: airTarget)

            let airPoint = GeoAR.project(airTarget, pose: pose, viewport: size, focal: focal)

            if let airPoint, size.horizontallyContains(airPoint) {
                let groundPoint = GeoAR.project(
                    SIMD3(flat.x, flat.y, ground),
                    pose: pose,
                    viewport: size,
                    focal: focal
                )
                return ResolvedAnchor(
                    anchor: anchor,
                    distance: distance,
                    placement: .world(
                        ground: groundPoint ?? CGPoint(x: airPoint.x, y: airPoint.y + 40),
                        air: airPoint,
                        ringWidth: GeoAR.projectedSize(
                            metres: GeoAR.groundRingRadius * 2,
                            distance: distance,
                            focal: focal
                        ),
                        diameter: clampedDiameter(distance: distance, focal: focal)
                    )
                )
            }

            // Behind you or outside the frame: only the clue you're hunting earns
            // a chevron. Secondary evidence simply isn't drawn.
            guard anchor.isPrimary else { return nil }
            let relative = GeoAR.relativeBearingDegrees(to: airTarget, pose: pose)
            return ResolvedAnchor(
                anchor: anchor,
                distance: distance,
                placement: .edge(
                    point: GeoAR.edgePoint(
                        relativeBearingDegrees: relative,
                        viewport: size,
                        focal: focal
                    ),
                    pointsRight: relative >= 0
                )
            )
        }
    }

    /// East/north position of an anchor in the local frame, preferring an
    /// explicit override when one exists. Returns `nil` for an anchor that has
    /// neither an override nor an origin to measure from — it simply isn't drawn
    /// rather than being guessed at.
    private func groundOffset(for anchor: EvidenceAnchor, origin: GeoPoint?) -> SIMD2<Double>? {
        if let override = frame.overrides[anchor.id] {
            return SIMD2(override.x, override.y)
        }
        guard let origin else { return nil }
        let offset = GeoAR.localOffset(
            from: origin,
            to: anchor.point,
            declinationDegrees: frame.declination
        )
        return SIMD2(offset.east, offset.north)
    }

    /// Nothing can be placed yet — park the clue being hunted in the middle so
    /// the approach still works, and hide the rest rather than lie about them.
    private func centredFallback(in size: CGSize) -> [ResolvedAnchor] {
        let focal = GeoAR.focalLength(viewport: size, fieldOfViewDegrees: GeoAR.defaultFieldOfView)
        return anchors.compactMap { anchor in
            guard anchor.isPrimary else { return nil }
            let distance = distanceWithoutTracking(to: anchor)
            return ResolvedAnchor(
                anchor: anchor,
                distance: distance,
                placement: .centred(
                    point: CGPoint(x: size.width / 2, y: size.height * 0.44),
                    diameter: clampedDiameter(distance: distance, focal: focal)
                )
            )
        }
    }

    private func distanceWithoutTracking(to anchor: EvidenceAnchor) -> Double {
        if let override = frame.overrides[anchor.id] {
            return (override.x * override.x + override.y * override.y).squareRoot()
        }
        guard let origin = frame.origin else { return 0 }
        return origin.distance(to: anchor.point)
    }

    /// Real-world sizing, floored so distant evidence stays tappable and capped so
    /// standing on top of a clue doesn't fill the whole screen.
    private func clampedDiameter(distance: Double, focal: CGFloat) -> CGFloat {
        let projected = GeoAR.projectedSize(metres: 0.8, distance: distance, focal: focal)
        return min(max(projected, 40), 190)
    }
}

// MARK: - Resolved model

private struct ResolvedAnchor: Identifiable {
    enum Placement {
        case world(ground: CGPoint, air: CGPoint, ringWidth: CGFloat, diameter: CGFloat)
        case edge(point: CGPoint, pointsRight: Bool)
        case centred(point: CGPoint, diameter: CGFloat)
    }

    let anchor: EvidenceAnchor
    let distance: Double
    let placement: Placement

    var id: UUID { anchor.id }
}

private extension CGSize {
    /// Vertical overflow is fine — a clue underfoot or high overhead still draws.
    /// Only horizontal misses mean you're facing the wrong way.
    func horizontallyContains(_ point: CGPoint) -> Bool {
        point.x > -width * 0.15 && point.x < width * 1.15
            && point.y > -height * 1.5 && point.y < height * 2.5
    }
}

// MARK: - Anchored pin

/// Evidence sitting on the street: a ring on the ground, a tether rising from it,
/// and the artifact hovering above. The ring is the thing that reads as "here".
private struct AnchoredCluePin: View {
    let anchor: EvidenceAnchor
    let distance: Double
    let groundPoint: CGPoint
    let airPoint: CGPoint
    let ringWidth: CGFloat
    let diameter: CGFloat
    let viewport: CGSize
    let pulse: Bool
    let isCollectible: Bool
    let onCollect: () -> Void

    private var tint: Color { anchor.isPrimary ? Theme.brass : Theme.violet }

    var body: some View {
        ZStack {
            groundRing
            tether
            artifact
            if anchor.isPrimary {
                label
            }
        }
    }

    private var groundRing: some View {
        let width = min(max(ringWidth, 26), viewport.width * 1.4)
        // Flattened by perspective: a circle on the ground seen from eye level.
        let height = width * 0.34

        return ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.32), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: width / 2
                    )
                )
                .frame(width: width, height: height)

            Ellipse()
                .strokeBorder(tint.opacity(0.85), lineWidth: 2)
                .frame(width: width, height: height)

            Ellipse()
                .strokeBorder(tint.opacity(0.4), lineWidth: 1.5)
                .frame(width: width, height: height)
                .scaleEffect(pulse ? 1.35 : 1)
                .opacity(pulse ? 0 : 0.8)
        }
        .shadow(color: tint.opacity(0.5), radius: 10)
        .position(groundPoint)
        .allowsHitTesting(false)
    }

    /// Line linking the artifact to its spot on the ground. Without it the glyph
    /// floats free and the eye can't tell where the evidence actually is.
    private var tether: some View {
        Path { path in
            path.move(to: groundPoint)
            path.addLine(to: airPoint)
        }
        .stroke(
            LinearGradient(
                colors: [tint.opacity(0.05), tint.opacity(0.65)],
                startPoint: .bottom,
                endPoint: .top
            ),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5])
        )
        .allowsHitTesting(false)
    }

    private var artifact: some View {
        Button {
            if isCollectible { onCollect() }
        } label: {
            ZStack {
                Circle()
                    .fill(Theme.ink.opacity(0.55))
                    .frame(width: diameter, height: diameter)

                Circle()
                    .fill(tint.opacity(0.16))
                    .frame(width: diameter, height: diameter)

                Circle()
                    .strokeBorder(tint.opacity(0.9), lineWidth: 2)
                    .frame(width: diameter, height: diameter)
                    .shadow(color: tint.opacity(0.9), radius: 12)

                Circle()
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(pulse ? 1.3 : 1)
                    .opacity(pulse ? 0 : 0.7)

                Image(systemName: anchor.symbolName)
                    .font(.system(size: diameter * 0.4, weight: .semibold))
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(0.9), radius: 6)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isCollectible)
        .position(airPoint)
        .accessibilityLabel(
            isCollectible
                ? "Collect \(anchor.title)"
                : "\(anchor.title), \(Int(distance)) metres away"
        )
    }

    /// Caption pinned just under the artifact, kept on screen and at a fixed size
    /// so it stays readable no matter how far away the evidence is.
    private var label: some View {
        VStack(spacing: 4) {
            Text("CLUE \(anchor.index) · \(anchor.title.uppercased())")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.4)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(isCollectible ? "TAP TO COLLECT" : "\(distanceText) AWAY")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isCollectible ? Theme.ink : tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(isCollectible ? tint : Theme.ink.opacity(0.7), in: .capsule)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.ink.opacity(0.6), in: .rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(tint.opacity(0.55), lineWidth: 1)
        }
        .fixedSize()
        .position(
            x: min(max(airPoint.x, 90), viewport.width - 90),
            y: min(max(airPoint.y + diameter / 2 + 30, 60), viewport.height - 60)
        )
        .allowsHitTesting(false)
    }

    /// Close range is where precision shows, so it earns a decimal.
    private var distanceText: String {
        distance < 10
            ? String(format: "%.1f M", distance)
            : "\(Int(distance.rounded())) M"
    }
}

// MARK: - Off-screen pointer

private struct EdgePointer: View {
    let anchor: EvidenceAnchor
    let distance: Double
    let point: CGPoint
    let pointsRight: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: pointsRight ? "arrow.right" : "arrow.left")
                .font(.system(size: 22, weight: .heavy))
            Text("\(Int(distance.rounded())) M")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("TURN")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.5)
                .opacity(0.7)
        }
        .foregroundStyle(Theme.brass)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.ink.opacity(0.7), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Theme.brass.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: Theme.brass.opacity(0.5), radius: 10)
        .position(point)
        .accessibilityLabel("\(anchor.title) is off screen, \(Int(distance)) metres away")
    }
}

// MARK: - Untracked fallback

private struct CentredCluePin: View {
    let anchor: EvidenceAnchor
    let distance: Double
    let point: CGPoint
    let diameter: CGFloat
    let pulse: Bool
    let isCollectible: Bool
    let onCollect: () -> Void

    var body: some View {
        VStack(spacing: 14) {
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
                        .shadow(color: Theme.brass.opacity(0.8), radius: 12)
                    Circle()
                        .strokeBorder(Theme.brass.opacity(0.3), lineWidth: 1)
                        .frame(width: diameter * 1.3, height: diameter * 1.3)
                        .scaleEffect(pulse ? 1.15 : 0.95)
                        .opacity(pulse ? 0.1 : 0.6)
                    Image(systemName: anchor.symbolName)
                        .font(.system(size: diameter * 0.4, weight: .semibold))
                        .foregroundStyle(Theme.brass)
                }
            }
            .buttonStyle(.plain)
            .disabled(!isCollectible)

            Text(isCollectible ? "TAP TO COLLECT" : "\(Int(distance.rounded())) M AWAY")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(isCollectible ? Theme.ink : Theme.brass)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isCollectible ? Theme.brass : Theme.ink.opacity(0.7), in: .capsule)
                .monospacedDigit()
        }
        .position(point)
    }
}
