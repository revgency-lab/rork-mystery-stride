//
//  SceneLabView.swift
//  MysteryRun
//
//  A developer-only shortcut into any screen state. Xcode's #Preview canvas isn't
//  visible when the app is driven from a simulator stream, so this is how design
//  work on moments like "a clue was just found" happens without walking a route.
//
//  Everything below the entry point compiles only in DEBUG, so none of it ships.
//

import SwiftUI

/// Row that opens the Scene Lab. Renders as nothing in release builds, which keeps
/// `ProfileView` free of conditional compilation.
struct SceneLabEntry: View {
    #if DEBUG
    @State private var isPresented: Bool = false
    #endif

    var body: some View {
        #if DEBUG
        VStack(alignment: .leading, spacing: 10) {
            EyebrowLabel(text: "Developer")
            Button {
                isPresented = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "theatermasks.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.violet)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scene Lab")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Jump to any screen without walking a route.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inkCard()
        .sheet(isPresented: $isPresented) {
            NavigationStack { SceneLabView() }
        }
        #else
        EmptyView()
        #endif
    }
}

#if DEBUG

// MARK: - Sample data

/// Deterministic stand-in case. Built from the real generator with a fixed seed so
/// the same evidence appears every time and design changes are comparable run to run.
enum SceneLabData {
    static let sampleCase: MysteryCase = makeSampleCase()

    private static func makeSampleCase() -> MysteryCase {
        let origin = RouteBuilder.fallbackOrigin
        let points: [GeoPoint] = (0...24).map { step in
            let bearing = (Double(step) / 24) * 360
            return RouteBuilder.offset(origin, distance: 400, bearing: bearing)
        }
        let distance = RouteBuilder.pathLength(points)
        return CaseGenerator.makeCase(
            number: 14,
            mode: .run,
            route: points,
            plannedDistance: distance,
            usesRealRoute: false,
            seed: 20_260_831
        )
    }

    /// The sample case with its first `count` clues already banked.
    static func caseWithFoundClues(_ count: Int) -> MysteryCase {
        var mysteryCase = sampleCase
        for index in mysteryCase.clues.indices where index < count {
            mysteryCase.clues[index].foundAt = Date().addingTimeInterval(Double(index - count) * 480)
        }
        return mysteryCase
    }

    static var solvedCase: MysteryCase {
        caseWithFoundClues(sampleCase.clues.count)
    }

    /// Index of the first pivotal clue, so the lab can show that variant of the reveal.
    static var pivotalClueNumber: Int {
        (sampleCase.clues.firstIndex(where: \.isPivotal) ?? 1) + 1
    }

    /// An indoor copy, which progresses on simulated distance instead of GPS —
    /// the only way to watch a live run play out at a desk.
    static var simulatedRunCase: MysteryCase {
        var mysteryCase = sampleCase
        mysteryCase.id = UUID()
        mysteryCase.mode = .indoor
        return mysteryCase
    }

    static func record(for mysteryCase: MysteryCase, duration: TimeInterval = 1_920) -> CaseRecord {
        let found = mysteryCase.foundClues
        let solved = found.count == mysteryCase.clues.count
        let xp = found.reduce(0) { $0 + $1.xp } + (solved ? 250 : 0)
        return CaseRecord(
            id: mysteryCase.id,
            number: mysteryCase.number,
            title: mysteryCase.title,
            photoAsset: mysteryCase.photoAsset,
            conclusion: mysteryCase.conclusion,
            closedAt: Date(),
            distance: solved ? mysteryCase.plannedDistance : mysteryCase.plannedDistance * 0.42,
            duration: solved ? duration : duration * 0.5,
            mode: mysteryCase.mode,
            cluesFound: found.count,
            clueTotal: mysteryCase.clues.count,
            xpEarned: xp,
            clues: mysteryCase.clues
        )
    }
}

// MARK: - Scene catalogue

enum LabScene: String, Identifiable, CaseIterable {
    case clueFirst
    case cluePivotal
    case clueFinal
    case resolutionSolved
    case resolutionPartial
    case summarySolved
    case summaryAbandoned
    case simulatedRun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clueFirst: "First clue found"
        case .cluePivotal: "Pivotal clue found"
        case .clueFinal: "Final clue found"
        case .resolutionSolved: "Case explained — solved"
        case .resolutionPartial: "Case explained — partial"
        case .summarySolved: "Session summary — solved"
        case .summaryAbandoned: "Session summary — abandoned"
        case .simulatedRun: "Simulated live run"
        }
    }

    var subtitle: String {
        switch self {
        case .clueFirst: "Opening reveal, 1 of \(SceneLabData.sampleCase.clues.count)."
        case .cluePivotal: "The starred variant with the violet badge."
        case .clueFinal: "Last piece — copy changes to send you to the case file."
        case .resolutionSolved: "Full narrated report with XP and streak."
        case .resolutionPartial: "Only two clues banked, so the report is incomplete."
        case .summarySolved: "Closing stats for a clean solve."
        case .summaryAbandoned: "Walked away early — partial distance and XP."
        case .simulatedRun: "Runs the real HUD indoors on simulated distance."
        }
    }

    var symbolName: String {
        switch self {
        case .clueFirst: "magnifyingglass"
        case .cluePivotal: "star.fill"
        case .clueFinal: "checkmark.seal.fill"
        case .resolutionSolved: "doc.text.fill"
        case .resolutionPartial: "doc.plaintext"
        case .summarySolved: "flag.checkered"
        case .summaryAbandoned: "flag.slash"
        case .simulatedRun: "play.circle.fill"
        }
    }

    /// Scenes that mutate saved state get flagged in the UI.
    var mutatesRecord: Bool { self == .simulatedRun }
}

private struct LabSection: Identifiable {
    let id: String
    let title: String
    let scenes: [LabScene]
}

// MARK: - Lab

struct SceneLabView: View {
    @Environment(InvestigationEngine.self) private var engine
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var activeScene: LabScene?

    private let sections: [LabSection] = [
        LabSection(id: "discovery", title: "Discovery", scenes: [.clueFirst, .cluePivotal, .clueFinal]),
        LabSection(id: "payoff", title: "Payoff", scenes: [.resolutionSolved, .resolutionPartial]),
        LabSection(id: "closing", title: "Closing", scenes: [.summarySolved, .summaryAbandoned]),
        LabSection(id: "live", title: "Live", scenes: [.simulatedRun])
    ]

    var body: some View {
        ZStack {
            InkBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Every screen below uses the same fixed sample case, so you can compare design changes run to run.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(2)

                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            EyebrowLabel(text: section.title)
                            VStack(spacing: 8) {
                                ForEach(section.scenes) { scene in
                                    sceneRow(scene)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Scene Lab")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ink, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .tint(Theme.brass)
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $activeScene) { scene in
            sceneView(for: scene)
        }
    }

    private func sceneRow(_ scene: LabScene) -> some View {
        Button {
            launch(scene)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: scene.symbolName)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.brass)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(scene.title)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if scene.mutatesRecord {
                            Text("FILES")
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(0.8)
                                .foregroundStyle(Theme.evidenceRed)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Theme.evidenceRed.opacity(0.14), in: .rect(cornerRadius: 4))
                        }
                    }
                    Text(scene.subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.inkStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func launch(_ scene: LabScene) {
        if scene == .simulatedRun {
            let simulated = SceneLabData.simulatedRunCase
            store.setActiveCase(simulated)
            engine.begin(simulated)
        }
        activeScene = scene
    }

    // MARK: - Scene construction

    @ViewBuilder
    private func sceneView(for scene: LabScene) -> some View {
        switch scene {
        case .clueFirst:
            clueReveal(foundCount: 1)
        case .cluePivotal:
            clueReveal(foundCount: SceneLabData.pivotalClueNumber)
        case .clueFinal:
            clueReveal(foundCount: SceneLabData.sampleCase.clues.count)
        case .resolutionSolved:
            resolution(solved: true)
        case .resolutionPartial:
            resolution(solved: false)
        case .summarySolved:
            summary(solved: true)
        case .summaryAbandoned:
            summary(solved: false)
        case .simulatedRun:
            LiveInvestigationView()
        }
    }

    private func clueReveal(foundCount: Int) -> some View {
        let mysteryCase = SceneLabData.caseWithFoundClues(foundCount)
        let index = min(max(foundCount - 1, 0), mysteryCase.clues.count - 1)
        return ClueRevealView(
            clue: mysteryCase.clues[index],
            total: mysteryCase.clues.count,
            found: foundCount,
            clues: mysteryCase.clues
        )
    }

    private func resolution(solved: Bool) -> some View {
        let mysteryCase = solved ? SceneLabData.solvedCase : SceneLabData.caseWithFoundClues(2)
        return CaseExplainedView(
            report: ResolutionReport(mysteryCase: mysteryCase, xpEarned: solved ? 520 : 140),
            streak: solved ? 4 : nil,
            onClose: { activeScene = nil }
        )
    }

    private func summary(solved: Bool) -> some View {
        let mysteryCase = solved ? SceneLabData.solvedCase : SceneLabData.caseWithFoundClues(2)
        return SessionSummaryView(
            record: SceneLabData.record(for: mysteryCase),
            mysteryCase: mysteryCase,
            onFinish: { activeScene = nil }
        )
    }
}

#endif
