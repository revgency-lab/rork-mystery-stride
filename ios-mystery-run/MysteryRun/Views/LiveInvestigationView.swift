//
//  LiveInvestigationView.swift
//  MysteryRun
//

import CoreLocation
import SwiftUI
import UIKit

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

    var body: some View {
        @Bindable var engine = engine

        ZStack(alignment: .top) {
            mapLayer
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 16) {
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
        .confirmationDialog(
            "End this investigation?",
            isPresented: $showStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("Close the Case", role: .destructive) { stop() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Evidence you've already found stays in your file.")
        }
        .confirmationDialog(
            "Can't reach this evidence?",
            isPresented: $showOverrideConfirmation,
            titleVisibility: .visible
        ) {
            Button("Collect It Anyway") { engine.markNextClueFound() }
            Button("Keep Searching", role: .cancel) {}
        } message: {
            Text("Use this if the clue landed somewhere you can't get to, or the GPS is drifting.")
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
            onCameraIdle: { center in
                guard let point = engine.currentPoint else { return }
                // Stop chasing the detective if they've deliberately panned away.
                isFollowing = GeoPoint(center).distance(to: point) < 350
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

    /// Follows the detective while they haven't taken the camera themselves.
    /// `recenterTick` re-arms the follow after a manual pan.
    private var camera: NoirMapCamera {
        guard isFollowing,
              let point = engine.currentPoint ?? engine.mysteryCase?.route.first else {
            return .free
        }
        _ = recenterTick
        return .center(point, zoom: 15.4)
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
                (symbol: "location.fill", text: "\(engine.distance.kilometreString) km"),
                (symbol: "flag.fill", text: "\(engine.foundCount) / \(engine.clueTotal)")
            ])

            Spacer(minLength: 0)

            signalPip
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    /// Quiet GPS-health pip — amber when the fix is soft, red when it's unusable.
    @ViewBuilder
    private var signalPip: some View {
        if !engine.isIndoor {
            let quality = location.signalQuality
            HStack(spacing: 5) {
                Image(systemName: quality == .none ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
                    .font(.system(size: 11, weight: .semibold))
                Text(signalLabel(quality))
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(signalColor(quality))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.ultraThinMaterial, in: .capsule)
            .accessibilityLabel("GPS signal \(signalLabel(quality))")
        }
    }

    private func signalLabel(_ quality: LocationService.SignalQuality) -> String {
        switch quality {
        case .good: "GPS"
        case .fair: "Weak"
        case .poor: "Drifting"
        case .none: "No fix"
        }
    }

    private func signalColor(_ quality: LocationService.SignalQuality) -> Color {
        switch quality {
        case .good: Theme.textSecondary
        case .fair: Theme.brass
        case .poor, .none: Theme.evidenceRed
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

                    Text(engine.phase == .paused
                         ? "Paused — resume when you're moving again"
                         : "Keep moving to examine the evidence")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)

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

            RoundControlButton(symbol: "location.viewfinder", label: "Recenter", tint: Theme.brass) {
                isFollowing = true
                recenterTick += 1
            }
        }
        .padding(.horizontal, 12)
    }

    private func stop() {
        engine.finish()
        showSummary = true
    }
}


