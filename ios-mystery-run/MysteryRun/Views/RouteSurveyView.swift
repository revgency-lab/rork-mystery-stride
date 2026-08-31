//
//  RouteSurveyView.swift
//  MysteryRun
//
//  The briefing's route photograph, opened up. Tapping the survey on the case
//  file shouldn't be a dead end — this is where the detective actually studies
//  the ground before committing to it: pan, zoom, turn the map, and tap any
//  node to see what's known about it.
//

import CoreLocation
import SwiftUI

struct RouteSurveyView: View {
    let mysteryCase: MysteryCase
    let ctaTitle: String
    let onStart: () -> Void
    let onClose: () -> Void

    @Environment(LocationService.self) private var location

    @State private var selectedClue: Clue?
    @State private var northTick: Int = 0
    @State private var refitTick: Int = 0
    @State private var mapBearing: Double = 0

    var body: some View {
        ZStack(alignment: .top) {
            map
                .ignoresSafeArea()

            topBar
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .background(Theme.ink)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: abs(mapBearing) > 1)
        .noirPopup(item: $selectedClue) { clue in
            MapClueCard(
                clue: clue,
                distance: detectivePoint?.distance(to: clue.point),
                onClose: { selectedClue = nil }
            )
        }
    }

    // MARK: - Map

    private var map: some View {
        NoirMapView(
            route: mysteryCase.route,
            clues: mysteryCase.clues.map { NoirClueMarker(clue: $0) },
            detective: detectivePoint,
            camera: .fit(mysteryCase.route, padding: 64),
            allowsRotation: true,
            resetNorthToken: northTick,
            refitToken: refitTick,
            onBearingChange: { mapBearing = $0 },
            onClueTap: { id in
                selectedClue = mysteryCase.clues.first { $0.id == id }
            }
        )
        .overlay {
            LinearGradient(
                colors: [Theme.ink.opacity(0.55), .clear, Theme.ink.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
    }

    private var detectivePoint: GeoPoint? {
        guard let fix = location.location else { return nil }
        return GeoPoint(fix.coordinate)
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close route survey")

            Text("CASE #\(mysteryCase.number) · ROUTE")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .kerning(1.4)
                .foregroundStyle(Theme.brass)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(.ultraThinMaterial, in: .capsule)
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }

            Spacer(minLength: 0)

            if abs(mapBearing) > 1 {
                circleButton(symbol: "location.north.line.fill", label: "Face the map north") {
                    northTick += 1
                }
                .rotationEffect(.degrees(-mapBearing))
                .transition(.scale.combined(with: .opacity))
            }

            circleButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Fit the whole route") {
                refitTick += 1
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private func circleButton(
        symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.brass)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: .circle)
                .overlay { Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                MetricBlock(
                    symbol: "shoeprints.fill",
                    value: mysteryCase.plannedDistance.kilometreString,
                    label: "Distance",
                    unit: "km"
                )
                Divider().frame(height: 30).overlay(Theme.inkStroke)
                MetricBlock(
                    symbol: "magnifyingglass",
                    value: "\(mysteryCase.foundClues.count)/\(mysteryCase.clues.count)",
                    label: "Evidence"
                )
                Divider().frame(height: 30).overlay(Theme.inkStroke)
                MetricBlock(
                    symbol: "hand.tap.fill",
                    value: "Tap",
                    label: "Any Node"
                )
            }
            .padding(.vertical, 12)
            .inkCard()

            Button {
                onStart()
            } label: {
                HStack {
                    Text(ctaTitle)
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding(.horizontal, 8)
            }
            .buttonStyle(BrassButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background {
            LinearGradient(
                colors: [Theme.ink.opacity(0), Theme.ink.opacity(0.9), Theme.ink],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}
