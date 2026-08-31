//
//  CaseBriefingView.swift
//  MysteryRun
//

import SwiftUI

/// Case tab root: tonight's generated mystery, its route, and the way in.
struct CaseBriefingView: View {
    @Environment(GameStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(InvestigationEngine.self) private var engine

    @State private var isGenerating: Bool = false
    @State private var showInvestigation: Bool = false
    @State private var showRouteDrawing: Bool = false
    @State private var showRouteSurvey: Bool = false
    @State private var selectedMode: SessionMode = .run

    var body: some View {
        ZStack {
            InkBackground()

            if let mysteryCase = store.activeCase, !isGenerating {
                briefing(for: mysteryCase)
            } else {
                GeneratingCaseView(isGenerating: isGenerating) {
                    Task { await generateCase() }
                }
            }
        }
        .navigationTitle("Case File")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ink, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await generateCase() }
                } label: {
                    Label("New Case", systemImage: "arrow.triangle.2.circlepath")
                }
                .tint(Theme.brass)
                .disabled(isGenerating)
            }
        }
        .task {
            location.requestPermission()
            selectedMode = store.profile.preferredMode
            // An investigation that survived a crash or a reboot goes straight back
            // on screen, paused, so nothing is lost mid-run.
            engine.resumeInterruptedSessionIfNeeded()
            if engine.isLive {
                showInvestigation = true
                return
            }
            if store.activeCase == nil {
                // Give the GPS a moment to produce a fix before routing.
                try? await Task.sleep(for: .seconds(1.5))
                location.markFixTimeout()
                await generateCase()
            }
        }
        .fullScreenCover(isPresented: $showInvestigation) {
            LiveInvestigationView()
        }
        .fullScreenCover(isPresented: $showRouteSurvey) {
            if let mysteryCase = store.activeCase {
                RouteSurveyView(
                    mysteryCase: mysteryCase,
                    ctaTitle: mysteryCase.foundClues.isEmpty ? "Begin Investigation" : "Continue Investigation",
                    onStart: {
                        showRouteSurvey = false
                        start(mysteryCase)
                    },
                    onClose: { showRouteSurvey = false }
                )
            }
        }
        .fullScreenCover(isPresented: $showRouteDrawing) {
            NavigationStack {
                RouteDrawingView(origin: location.origin) { drawn in
                    generateCase(from: drawn)
                }
            }
        }
    }

    // MARK: - Briefing

    @ViewBuilder
    private func briefing(for mysteryCase: MysteryCase) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                DossierCard(mysteryCase: mysteryCase)

                VStack(spacing: 0) {
                    HStack {
                        EyebrowLabel(text: mysteryCase.isDrawnRoute ? "Your Route" : "Route Overview")
                        Spacer()
                        if mysteryCase.isDrawnRoute {
                            Label("Hand drawn", systemImage: "scribble.variable")
                                .font(.caption2)
                                .foregroundStyle(Theme.brass)
                        } else if !mysteryCase.usesRealRoute {
                            Label("Estimated loop", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                    Button {
                        showRouteSurvey = true
                    } label: {
                        RoutePreviewMap(
                            route: mysteryCase.route,
                            clues: mysteryCase.clues,
                            surveyLabel: mysteryCase.isDrawnRoute
                                ? "Your Route · Case #\(mysteryCase.number)"
                                : "Aerial Survey · Case #\(mysteryCase.number)"
                        )
                        .frame(height: 230)
                        .overlay(alignment: .topTrailing) {
                            // The survey is a photograph until you pick it up.
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 9, weight: .bold))
                                Text("EXPLORE")
                                    .font(.system(size: 9, weight: .heavy))
                                    .kerning(1.2)
                            }
                            .foregroundStyle(Theme.brass)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.6), in: .capsule)
                            .overlay { Capsule().strokeBorder(Theme.brass.opacity(0.35), lineWidth: 1) }
                            .padding(12)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(MapPreviewButtonStyle())
                    .accessibilityLabel("Explore the route on a full map")

                    Divider().overlay(Theme.inkStroke)

                    HStack(spacing: 0) {
                        MetricBlock(
                            symbol: "shoeprints.fill",
                            value: mysteryCase.plannedDistance.kilometreString,
                            label: "Distance",
                            unit: "km"
                        )
                        Divider().frame(height: 34).overlay(Theme.inkStroke)
                        MetricBlock(
                            symbol: "clock.fill",
                            value: "\(estimatedMinutes(for: mysteryCase))",
                            label: "Est. Time",
                            unit: "min"
                        )
                        Divider().frame(height: 34).overlay(Theme.inkStroke)
                        MetricBlock(
                            symbol: "magnifyingglass",
                            value: "\(mysteryCase.clues.count)",
                            label: "Clues"
                        )
                    }
                    .padding(.vertical, 16)
                }
                .inkCard()

                RouteSourceCard(
                    isCustom: mysteryCase.isDrawnRoute,
                    preferredDistance: store.profile.preferredDistance,
                    onStandard: { Task { await generateCase() } },
                    onDraw: { showRouteDrawing = true }
                )

                ModePicker(selection: $selectedMode)

                if let twist = mysteryCase.twistNote {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "eye.trianglebadge.exclamationmark.fill")
                            .foregroundStyle(Theme.evidenceRed)
                        Text(twist)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.evidenceRed.opacity(0.10), in: .rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Theme.evidenceRed.opacity(0.35), lineWidth: 1)
                    }
                }

                if selectedMode.usesLiveLocation, location.isDenied {
                    LocationDeniedNotice()
                }

                Color.clear.frame(height: 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button {
                    start(mysteryCase)
                } label: {
                    HStack {
                        Text(mysteryCase.foundClues.isEmpty ? "Begin Investigation" : "Continue Investigation")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(.horizontal, 8)
                }
                .buttonStyle(BrassButtonStyle())

                Text("Move at any pace — clues unlock by location, not speed.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)
            .background {
                LinearGradient(colors: [Theme.ink.opacity(0), Theme.ink], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
        }
    }

    private func estimatedMinutes(for mysteryCase: MysteryCase) -> Int {
        max(6, Int((mysteryCase.plannedDistance / selectedMode.assumedSpeed) / 60))
    }

    // MARK: - Actions

    private func start(_ mysteryCase: MysteryCase) {
        var updated = mysteryCase
        updated.mode = selectedMode
        store.updatePreferences(mode: selectedMode)
        store.updateActiveCase(updated)
        engine.begin(updated)
        showInvestigation = true
    }

    /// Opens a case on a route the detective drew themselves. Evidence count
    /// scales with whatever distance they traced.
    private func generateCase(from drawn: GeneratedRoute) {
        let mysteryCase = CaseGenerator.makeCase(
            number: store.nextCaseNumber,
            mode: selectedMode,
            route: drawn.points,
            plannedDistance: max(drawn.distance, 400),
            usesRealRoute: drawn.snappedToStreets,
            isCustomRoute: true
        )
        store.setActiveCase(mysteryCase)
    }

    private func generateCase() async {
        isGenerating = true
        defer { isGenerating = false }

        if location.isAuthorized { location.requestOneShotFix() }
        let origin = location.origin
        let target = store.profile.preferredDistance
        let route = await RouteBuilder.makeRoute(around: origin, targetDistance: target)
        let mysteryCase = CaseGenerator.makeCase(
            number: store.nextCaseNumber,
            mode: selectedMode,
            route: route.points,
            plannedDistance: max(route.distance, 600),
            usesRealRoute: route.snappedToStreets
        )
        store.setActiveCase(mysteryCase)
    }
}

// MARK: - Dossier card

private struct DossierCard: View {
    let mysteryCase: MysteryCase

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CASE #\(mysteryCase.number)")
                        .font(.system(.title3, weight: .black))
                        .kerning(2)
                        .foregroundStyle(Theme.evidenceRed.opacity(0.85))

                    Text(mysteryCase.title)
                        .font(.system(.title, design: .serif, weight: .bold))
                        .foregroundStyle(Theme.paperInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 22)
            .padding(.horizontal, 20)

            CasePhoto(assetName: mysteryCase.photoAsset, height: 132)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Rectangle()
                .fill(Theme.paperInk.opacity(0.18))
                .frame(height: 1)
                .padding(.horizontal, 20)
                .padding(.top, 18)

            Text(mysteryCase.premise)
                .font(.system(.callout, design: .serif))
                .foregroundStyle(Theme.paperInk.opacity(0.85))
                .lineSpacing(4)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 26)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dossierSheet()
        .overlay(alignment: .bottomTrailing) {
            RubberStamp(text: "CONFIDENTIAL")
                .padding(.trailing, 12)
                .padding(.bottom, 10)
        }
        .overlay(alignment: .topTrailing) {
            Rectangle()
                .fill(Color(red: 0.85, green: 0.78, blue: 0.60).opacity(0.55))
                .frame(width: 80, height: 24)
                .rotationEffect(.degrees(18))
                .offset(x: 22, y: -8)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Route source

/// Lets the detective take the generated patrol loop or trace their own route.
private struct RouteSourceCard: View {
    let isCustom: Bool
    let preferredDistance: Double
    let onStandard: () -> Void
    let onDraw: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowLabel(text: "Where the trail runs")

            HStack(spacing: 10) {
                RouteSourceTile(
                    symbol: "point.forward.to.point.capsulepath",
                    title: "Standard Patrol",
                    detail: "\(preferredDistance.shortKilometreString) km loop from where you are",
                    isSelected: !isCustom,
                    action: onStandard
                )

                RouteSourceTile(
                    symbol: "scribble.variable",
                    title: "Draw My Route",
                    detail: "Trace any distance — we place the evidence",
                    isSelected: isCustom,
                    action: onDraw
                )
            }

            Text(isCustom
                 ? "This case follows the route you drew. Tap Draw My Route again to trace a new one."
                 : "Draw your own and we'll snap it to walkable streets, then scatter clues evenly across the whole distance.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inkCard()
    }
}

private struct RouteSourceTile: View {
    let symbol: String
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.brass : Theme.textSecondary)

                Text(title)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(12)
            .background(
                isSelected ? Theme.brass.opacity(0.12) : Color.white.opacity(0.04),
                in: .rect(cornerRadius: 13)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(
                        isSelected ? Theme.brass.opacity(0.75) : Color.white.opacity(0.10),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Mode picker

private struct ModePicker: View {
    @Binding var selection: SessionMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(SessionMode.allCases) { mode in
                    Button {
                        selection = mode
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.symbolName)
                            Text(mode.title)
                        }
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(selection == mode ? Color(red: 0.11, green: 0.08, blue: 0.02) : Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            if selection == mode {
                                LinearGradient(colors: [Theme.brass, Theme.brassDeep], startPoint: .top, endPoint: .bottom)
                            } else {
                                Color.clear
                            }
                        }
                        .clipShape(.rect(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(5)
            .inkCard(cornerRadius: 15)

            Text(selection == .indoor
                 ? "Indoor mode unlocks clues on distance covered instead of GPS — treadmill friendly."
                 : "Tagged as a \(selection.title.lowercased()) for your stats only. Gameplay is identical.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 4)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Supporting states

private struct GeneratingCaseView: View {
    let isGenerating: Bool
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 46))
                .foregroundStyle(Theme.brass)
                .symbolEffect(.pulse, options: .repeating, isActive: isGenerating)

            Text(isGenerating ? "Assembling the case file…" : "No open case")
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(isGenerating
                 ? "Placing evidence along the streets around you."
                 : "Open a new investigation to get started.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            if !isGenerating {
                Button("Open a New Case", action: retry)
                    .buttonStyle(BrassButtonStyle())
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
            }
        }
        .padding(32)
    }
}

private struct LocationDeniedNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Location access is off", systemImage: "location.slash.fill")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Outdoor cases need your position to unlock clues. Turn it on in Settings, or switch to Indoor mode.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(.caption, weight: .semibold))
            .tint(Theme.brass)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inkCard(cornerRadius: 14)
    }
}
