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

import CoreLocation
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

    /// Stable identity for the rehearsal pin, so re-dropping it doesn't restart
    /// the pulse animation and make a still anchor look like it moved.
    static let rehearsalAnchorID = UUID()

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
    case arRehearsal

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
        case .arRehearsal: "AR anchor rehearsal"
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
        case .arRehearsal: "Drop a clue in your room and check it stays put."
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
        case .arRehearsal: "camera.viewfinder"
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
        LabSection(id: "live", title: "Live", scenes: [.simulatedRun]),
        LabSection(id: "camera", title: "Camera", scenes: [.arRehearsal])
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
        case .arRehearsal:
            ARRehearsalView(onClose: { activeScene = nil })
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

// MARK: - AR rehearsal

/// Drops a fake clue a few metres away so the AR projection can be checked from
/// a living room instead of halfway along a real route.
///
/// The whole point is the anchor test: once dropped, the ring should stay welded
/// to one patch of floor while you pan, tilt and walk around it. If it slides
/// with the phone, the projection is wrong — not the GPS.
struct ARRehearsalView: View {
    let onClose: () -> Void

    @Environment(LocationService.self) private var location

    @State private var camera = CameraService()
    @State private var attitude = AttitudeService()
    @State private var anchorOrigin: GeoPoint?
    @State private var dropDistance: Double = 8
    @State private var showsDiagnostics: Bool = true

    private let distanceChoices: [Double] = [3, 8, 25, 100]

    var body: some View {
        ZStack {
            ARCameraBackdrop(camera: camera)

            ARLensScene(
                anchors: anchors,
                userPoint: userPoint,
                matrix: attitude.matrix,
                declination: location.declination,
                fieldOfView: camera.fieldOfView,
                compassAvailable: attitude.isAvailable,
                collectRadius: 0,
                onCollect: nil
            )

            VStack {
                topBar
                if showsDiagnostics { diagnostics }
                Spacer()
                controls
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .ignoresSafeArea()
        .background(Theme.ink)
        .preferredColorScheme(.dark)
        .onAppear {
            camera.start()
            attitude.start()
            location.requestPermission()
            if anchorOrigin == nil { dropAnchor() }
        }
        .onDisappear {
            camera.stop()
            attitude.stop()
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: .circle)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("AR ANCHOR REHEARSAL")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Theme.brass)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: .capsule)

            Spacer()

            Button {
                showsDiagnostics.toggle()
            } label: {
                Image(systemName: showsDiagnostics ? "info.circle.fill" : "info.circle")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 44)
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 5) {
            diagnosticRow("Compass", attitude.isAvailable ? "live" : "unavailable", ok: attitude.isAvailable)
            diagnosticRow("Heading", headingText, ok: location.heading != nil)
            diagnosticRow("Declination", declinationText, ok: location.declination != nil)
            diagnosticRow("Camera FOV", String(format: "%.1f°", camera.fieldOfView), ok: camera.status == .running)
            diagnosticRow("GPS accuracy", accuracyText, ok: location.location != nil)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
        .padding(.top, 10)
    }

    private func diagnosticRow(_ label: String, _ value: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ok ? Theme.brass : Theme.evidenceRed)
                .frame(width: 6, height: 6)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Text(instruction)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            HStack(spacing: 8) {
                ForEach(distanceChoices, id: \.self) { choice in
                    Button {
                        dropDistance = choice
                        dropAnchor()
                    } label: {
                        Text("\(Int(choice)) m")
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(dropDistance == choice ? Theme.ink : Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                dropDistance == choice ? Theme.brass : Color.white.opacity(0.12),
                                in: .rect(cornerRadius: 9)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("Drop clue ahead of me") { dropAnchor() }
                .buttonStyle(BrassButtonStyle())
        }
        .padding(14)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .padding(.bottom, 24)
    }

    private var instruction: String {
        guard anchorOrigin != nil else {
            return "Waiting for a position fix. Step near a window if this doesn't clear."
        }
        return "A clue is pinned \(Int(dropDistance)) m ahead of where you stood. Pan around: the ring should stay welded to one spot on the floor. If it slides with the phone, the projection is off."
    }

    // MARK: Anchor

    /// Plants the clue in the direction the camera is currently facing, so it
    /// lands in view the moment it appears.
    private func dropAnchor() {
        guard let user = userPoint else { return }
        let bearing = attitude.isAvailable
            ? GeoAR.cameraBearingDegrees(matrix: attitude.matrix) + (location.declination ?? 0)
            : (location.heading ?? 0)
        anchorOrigin = RouteBuilder.offset(user, distance: dropDistance, bearing: bearing)
    }

    private var anchors: [ARAnchor] {
        guard let anchorOrigin else { return [] }
        return [
            ARAnchor(
                id: SceneLabData.rehearsalAnchorID,
                index: 1,
                title: "Test Anchor",
                symbolName: "scope",
                point: anchorOrigin,
                isPrimary: true
            )
        ]
    }

    private var userPoint: GeoPoint? {
        if let fix = location.location {
            return GeoPoint(fix.coordinate)
        }
        return RouteBuilder.fallbackOrigin
    }

    private var headingText: String {
        guard let heading = location.heading else { return "—" }
        return String(format: "%.0f°", heading)
    }

    private var declinationText: String {
        guard let declination = location.declination else { return "—" }
        return String(format: "%+.1f°", declination)
    }

    private var accuracyText: String {
        guard let fix = location.location else { return "no fix" }
        return String(format: "±%.0f m", fix.horizontalAccuracy)
    }
}

#endif
