//
//  LiveInvestigationView.swift
//  MysteryRun
//

import CoreLocation
import SwiftUI
import UIKit

/// Which way the detective is looking for the evidence right now.
enum RunLens: String, CaseIterable, Identifiable {
    case map
    case camera

    var id: String { rawValue }

    var title: String {
        switch self {
        case .map: "Map"
        case .camera: "Lens"
        }
    }

    var symbolName: String {
        switch self {
        case .map: "map.fill"
        case .camera: "camera.viewfinder"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .map: "Show the map"
        case .camera: "Show the camera lens"
        }
    }
}

/// Full-screen live investigation: dark map, live metrics, proximity to the next clue.
struct LiveInvestigationView: View {
    @Environment(InvestigationEngine.self) private var engine
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss

    @State private var isFollowing: Bool = true
    @State private var showStopConfirmation: Bool = false
    @State private var showOverrideConfirmation: Bool = false
    @State private var showSummary: Bool = false
    @State private var recenterTick: Int = 0
    @State private var northTick: Int = 0
    @State private var mapBearing: Double = 0
    @State private var selectedClue: Clue?
    @State private var lens: RunLens = .map

    var body: some View {
        @Bindable var engine = engine

        ZStack(alignment: .top) {
            Group {
                switch lens {
                case .map:
                    mapLayer
                case .camera:
                    ARLensView()
                }
            }
            .ignoresSafeArea()
            .transition(.opacity)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: lens)
        .animation(.easeInOut(duration: 0.2), value: mapBearing > 1)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 14) {
                LensToggle(selection: $lens)
                proximityCard
                controlRow
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            .background {
                LinearGradient(
                    colors: [Theme.ink.opacity(0), Theme.ink.opacity(0.92), Theme.ink],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
        .background(Theme.ink)
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .sensoryFeedback(.success, trigger: engine.discoveryTick)
        .sensoryFeedback(.impact(weight: .light), trigger: engine.proximityTick)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: lens)
        // A run is a long stretch of looking at a map; don't let the screen nap.
        .persistentSystemOverlays(.hidden)
        .onAppear {
            isFollowing = true
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .fullScreenCover(item: $engine.pendingClue) { clue in
            ClueRevealView(clue: clue, total: engine.clueTotal, found: engine.foundCount, clues: engine.mysteryCase?.clues ?? [])
        }
        .fullScreenCover(isPresented: $showSummary) {
            if let record = engine.lastRecord, let mysteryCase = engine.mysteryCase {
                SessionSummaryView(record: record, mysteryCase: mysteryCase) {
                    showSummary = false
                    engine.reset()
                    dismiss()
                }
            }
        }
        .noirPopup(item: $selectedClue) { clue in
            MapClueCard(
                clue: clue,
                distance: engine.currentPoint?.distance(to: clue.point),
                onClose: { selectedClue = nil }
            )
        }
        .noirPopup(isPresented: $showStopConfirmation) {
            NoirConfirmCard(
                stamp: "Case Status",
                title: "End this investigation?",
                message: "Evidence you've already found stays in your file. The rest of the trail goes cold.",
                symbolName: "xmark.seal.fill",
                confirmTitle: "Close the Case",
                onConfirm: {
                    showStopConfirmation = false
                    stop()
                },
                onCancel: { showStopConfirmation = false }
            )
        }
        .noirPopup(isPresented: $showOverrideConfirmation) {
            NoirConfirmCard(
                stamp: "Field Note",
                title: "Can't reach this evidence?",
                message: "Use this if the clue landed somewhere you can't get to, or the GPS is drifting.",
                symbolName: "hand.tap.fill",
                confirmTitle: "Collect It Anyway",
                isDestructive: false,
                onConfirm: {
                    showOverrideConfirmation = false
                    engine.markNextClueFound()
                },
                onCancel: { showOverrideConfirmation = false }
            )
        }
    }

    // MARK: - Map

    private var mapLayer: some View {
        NoirMapView(
            route: engine.mysteryCase?.route ?? [],
            traveled: engine.traveled,
            clues: clueMarkers,
            detective: engine.currentPoint,
            focusRing: focusRing,
            camera: camera,
            dimsPlannedRoute: true,
            allowsRotation: true,
            resetNorthToken: northTick,
            onUserGesture: {
                // Hands on the map means they're reading it themselves; stop
                // moving the camera under them until they ask us to.
                if isFollowing { isFollowing = false }
            },
            onBearingChange: { bearing in
                mapBearing = bearing
            },
            onClueTap: { id in
                selectedClue = engine.mysteryCase?.clues.first { $0.id == id }
            }
        )
        .overlay {
            // Just enough atmosphere to keep the floating cards readable.
            LinearGradient(
                colors: [Theme.ink.opacity(0.45), .clear, Theme.ink.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
    }

    private var clueMarkers: [NoirClueMarker] {
        guard let mysteryCase = engine.mysteryCase else { return [] }
        let nextID = engine.nextClue?.id
        return mysteryCase.clues.map { NoirClueMarker(clue: $0, isNext: $0.id == nextID) }
    }

    private var focusRing: NoirFocusRing? {
        guard let next = engine.nextClue else { return nil }
        return NoirFocusRing(
            center: next.point,
            approachRadius: 120,
            unlockRadius: engine.discoveryRadius
        )
    }

    /// Follows the detective while they haven't taken the map into their own
    /// hands. Follow never alters zoom or rotation — it only nudges the centre
    /// when they near the edge of the frame — so studying a junction is never
    /// interrupted by the camera reframing itself.
    private var camera: NoirMapCamera {
        guard isFollowing,
              let point = engine.currentPoint ?? engine.mysteryCase?.route.first else {
            return .free
        }
        return .follow(point, recenterToken: recenterTick)
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                showStopConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: .circle)
            }
            .accessibilityLabel("End investigation")

            StatCapsule(items: [
                (symbol: "stopwatch", text: engine.elapsed.clockString),
                (symbol: "location.fill", text: "\(engine.distance.shortKilometreString) km"),
                (symbol: "flag.fill", text: "\(engine.foundCount)/\(engine.clueTotal)")
            ])

            Spacer(minLength: 0)

            northButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    /// Appears only once the map has been turned off north, and puts it back.
    @ViewBuilder
    private var northButton: some View {
        if lens == .map, abs(mapBearing) > 1 {
            Button {
                northTick += 1
            } label: {
                Image(systemName: "location.north.line.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.brass)
                    .rotationEffect(.degrees(-mapBearing))
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: .circle)
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Face the map north")
        }
    }

    /// A healthy GPS fix is the normal case and doesn't deserve permanent
    /// chrome — the detective is only told about their signal when it's actually
    /// hurting them, in the card they're already reading.
    private var hasWeakSignal: Bool {
        switch location.signalQuality {
        case .poor, .none: return true
        case .good, .fair: return false
        }
    }

    @ViewBuilder
    private var proximityCard: some View {
        if let next = engine.nextClue {
            HStack(spacing: 14) {
                Circle()
                    .strokeBorder(Theme.brass.opacity(0.7), lineWidth: 1.5)
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: next.symbolName)
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.brass)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Clue \(next.index) · \(next.title)")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text(distanceText)
                        .font(.system(.title3, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.brass)
                        .contentTransition(.numericText())

                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(hasWeakSignal ? Theme.evidenceRed : Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ProgressView(value: engine.approachProgress)
                        .tint(Theme.brass)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)

                if canOverride {
                    Button {
                        showOverrideConfirmation = true
                    } label: {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.brass)
                            .frame(width: 44, height: 44)
                            .background(Theme.brass.opacity(0.12), in: .circle)
                    }
                    .accessibilityLabel("Collect this clue without reaching it")
                }
            }
            .padding(14)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
            .animation(.easeInOut, value: engine.approachProgress)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.brass)
                VStack(alignment: .leading, spacing: 2) {
                    Text("All evidence collected")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Close the case to read the full report.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
        }
    }

    /// The escape hatch only appears once you're genuinely near the clue, so it
    /// can't be used to skim the whole route from the sofa.
    private var canOverride: Bool {
        guard let distance = engine.distanceToNextClue else { return false }
        return distance <= 150
    }

    private var distanceText: String {
        guard let distance = engine.distanceToNextClue else { return "Searching…" }
        return "\(distance.proximityString) away"
    }

    private var statusLine: String {
        if engine.phase == .paused {
            return "Paused — resume when you're moving again"
        }
        // Takes priority over the generic warning: they are already standing
        // there, and the only thing between them and the evidence is the fix.
        if engine.isHoldingForBetterFix {
            return "Close enough — holding until the GPS settles. Collect it by hand if it won't."
        }
        if hasWeakSignal {
            return "Weak GPS — distances may drift until the fix settles"
        }
        return "Keep moving to examine the evidence"
    }

    private var controlRow: some View {
        HStack(alignment: .top) {
            RoundControlButton(
                symbol: engine.phase == .paused ? "play.fill" : "pause.fill",
                label: engine.phase == .paused ? "Resume" : "Pause"
            ) {
                engine.togglePause()
            }

            Spacer()

            RoundControlButton(
                symbol: "stop.fill",
                label: "Stop",
                tint: .white,
                background: Theme.evidenceRed,
                diameter: 84
            ) {
                showStopConfirmation = true
            }

            Spacer()

            // Fixed slot so the stop button stays centred whether or not
            // recentre applies to the current lens.
            Group {
                if lens == .map {
                    RoundControlButton(
                        symbol: "location.viewfinder",
                        label: "Recenter",
                        tint: isFollowing ? Theme.brass : Theme.textPrimary
                    ) {
                        isFollowing = true
                        recenterTick += 1
                    }
                }
            }
            .frame(width: 62)
        }
        .padding(.horizontal, 12)
    }

    private func stop() {
        engine.finish()
        showSummary = true
    }
}

// MARK: - Lens toggle

/// Map ⇄ Lens switch.
///
/// This sits directly above the proximity card because choosing *how* you hunt
/// is the second thing a detective does on this screen, after reading how far
/// away the evidence is. As one more unlabelled circle among the transport
/// controls it was effectively invisible.
private struct LensToggle: View {
    @Binding var selection: RunLens

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(RunLens.allCases) { option in
                Button {
                    guard selection != option else { return }
                    withAnimation(.snappy(duration: 0.26)) {
                        selection = option
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.symbolName)
                            .font(.system(size: 12, weight: .bold))
                        Text(option.title)
                            .font(.system(.footnote, weight: .semibold))
                    }
                    .foregroundStyle(selection == option ? Theme.ink : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background {
                        if selection == option {
                            Capsule(style: .continuous)
                                .fill(Theme.brass)
                                .matchedGeometryEffect(id: "lensPill", in: pill)
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.accessibilityLabel)
                .accessibilityAddTraits(selection == option ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .frame(maxWidth: 230)
    }
}


