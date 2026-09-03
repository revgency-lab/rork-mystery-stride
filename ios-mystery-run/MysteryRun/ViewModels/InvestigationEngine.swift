//
//  InvestigationEngine.swift
//  MysteryRun
//
//  Drives a live investigation: elapsed time, distance covered, and GPS-proximity
//  clue unlocking. Pace is never part of the logic — walkers and runners progress
//  identically. Progress always comes from real position; nothing is simulated.
//

import CoreLocation
import Foundation
import Observation

@Observable
final class InvestigationEngine {
    enum Phase: Equatable {
        case idle
        case active
        case paused
        case finished
    }

    private let location: LocationService
    private let store: GameStore

    private(set) var phase: Phase = .idle
    private(set) var mysteryCase: MysteryCase?
    private(set) var elapsed: TimeInterval = 0
    private(set) var distance: Double = 0
    private(set) var traveled: [GeoPoint] = []
    private(set) var currentPoint: GeoPoint?
    private(set) var distanceToNextClue: Double?
    /// Counter used to drive haptics/sound when a clue unlocks.
    private(set) var discoveryTick: Int = 0
    private(set) var proximityTick: Int = 0
    /// Clue awaiting its reveal screen.
    var pendingClue: Clue?
    private(set) var lastRecord: CaseRecord?

    /// True when the last clue was banked by hand rather than by GPS.
    private(set) var didUseOverride: Bool = false

    private var ticker: Task<Void, Never>?
    private var lastFix: CLLocation?
    /// Set when a fix lands impossibly far from the last one. The leap is almost
    /// always the receiver re-acquiring rather than the detective teleporting, so
    /// evidence stays locked until a second fix agrees with the new position.
    private var awaitingReanchorConfirmation: Bool = false
    private var announcedClueIDs: Set<UUID> = []
    /// Wall-clock anchors so time stays honest while the app is suspended.
    private var runningSince: Date?
    private var accumulatedElapsed: TimeInterval = 0
    private var lastSnapshotSave: Date = .distantPast

    init(location: LocationService, store: GameStore) {
        self.location = location
        self.store = store
        // Score every fix the moment it lands, including in the background.
        location.onFix = { [weak self] fix in
            self?.ingest(fix)
        }
    }

    var isRunning: Bool { phase == .active }
    var isLive: Bool { phase == .active || phase == .paused }

    var nextClue: Clue? { mysteryCase?.nextClue }

    var foundCount: Int { mysteryCase?.foundClues.count ?? 0 }
    var clueTotal: Int { mysteryCase?.clues.count ?? 0 }

    /// 0...1 approach progress toward the next clue, for the proximity bar.
    var approachProgress: Double {
        guard let distanceToNextClue else { return 0 }
        let window: Double = 400
        return min(1, max(0.02, 1 - (distanceToNextClue / window)))
    }

    /// Radius in metres at which the next clue unlocks — shown as a map ring.
    var discoveryRadius: Double {
        store.profile.discoveryRadius
    }

    // MARK: - Lifecycle

    func begin(_ mysteryCase: MysteryCase) {
        self.mysteryCase = mysteryCase
        phase = .active
        elapsed = 0
        distance = 0
        traveled = []
        announcedClueIDs = []
        lastFix = nil
        awaitingReanchorConfirmation = false
        pendingClue = nil
        lastRecord = nil
        didUseOverride = false
        runningSince = Date()
        accumulatedElapsed = 0
        currentPoint = mysteryCase.route.first

        store.markCaseStarted()
        store.clearSession()
        Task { await NotificationService.requestPermission() }
        location.startTracking()
        startTicker()
        updateDistanceToNextClue()
    }

    /// Restores an investigation that was interrupted by a crash, a reboot or iOS
    /// reclaiming memory. Comes back paused so the detective opts back in.
    func restore(_ mysteryCase: MysteryCase, from snapshot: SessionSnapshot) {
        self.mysteryCase = mysteryCase
        phase = .paused
        elapsed = snapshot.elapsed
        accumulatedElapsed = snapshot.elapsed
        runningSince = nil
        distance = snapshot.distance
        traveled = snapshot.traveled
        announcedClueIDs = Set(mysteryCase.foundClues.map(\.id))
        lastFix = nil
        awaitingReanchorConfirmation = false
        pendingClue = nil
        lastRecord = nil
        didUseOverride = false
        currentPoint = snapshot.traveled.last ?? mysteryCase.route.first
        startTicker()
        updateDistanceToNextClue()
    }

    func pause() {
        guard phase == .active else { return }
        phase = .paused
        accumulatedElapsed = elapsed
        runningSince = nil
        lastFix = nil
        location.stopTracking()
        persistSnapshot(force: true)
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .active
        runningSince = Date()
        lastFix = nil
        awaitingReanchorConfirmation = false
        location.startTracking()
    }

    func togglePause() {
        phase == .paused ? resume() : pause()
    }

    /// Ends the session, files the case and produces the summary record.
    @discardableResult
    func finish() -> CaseRecord? {
        guard let mysteryCase else { return nil }
        // Filing is a one-way door. A second tap on the confirmation before it
        // dismisses, or any other re-entry, hands back the record already filed
        // instead of closing the same investigation twice.
        guard phase != .finished else { return lastRecord }

        ticker?.cancel()
        ticker = nil
        location.stopTracking()
        phase = .finished

        let record = store.closeCase(mysteryCase, distance: distance, duration: elapsed)
        lastRecord = record
        // The case now lives in the history; leaving it on the board as well is
        // what allowed a closed case to be walked and filed all over again.
        store.setActiveCase(nil)
        store.clearSession()
        return record
    }

    func reset() {
        ticker?.cancel()
        ticker = nil
        location.stopTracking()
        phase = .idle
        mysteryCase = nil
        pendingClue = nil
        elapsed = 0
        distance = 0
        traveled = []
        runningSince = nil
        accumulatedElapsed = 0
        store.clearSession()
    }

    // MARK: - Ticking

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard phase == .active else { return }
        // Derived from wall-clock rather than counted ticks, so time spent with the
        // app suspended in a pocket still counts toward the session.
        if let runningSince {
            elapsed = accumulatedElapsed + Date().timeIntervalSince(runningSince)
        }
        persistSnapshot()
    }

    /// Entry point for every GPS fix — runs in the foreground and background alike.
    private func ingest(_ fix: CLLocation) {
        guard phase == .active else { return }
        if let runningSince {
            elapsed = accumulatedElapsed + Date().timeIntervalSince(runningSince)
        }
        consume(fix)
        updateDistanceToNextClue()
        checkForDiscovery()
        persistSnapshot()
    }

    private func consume(_ fix: CLLocation) {
        // Ignore inaccurate fixes so the distance stays honest.
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy < 60 else { return }
        // Ignore cached fixes handed over from before this session started.
        guard abs(fix.timestamp.timeIntervalSinceNow) < 30 else { return }

        let point = GeoPoint(fix.coordinate)
        guard let lastFix else {
            self.lastFix = fix
            currentPoint = point
            appendTraveled(point)
            return
        }

        let delta = fix.distance(from: lastFix)
        let noiseFloor = Self.noiseFloor(fix, lastFix)

        // A GPS jump (tunnel, canyon, cold start). Don't credit the leap, but
        // re-anchor — otherwise every later fix looks like a jump too and
        // distance freezes for the rest of the run.
        if delta >= 200 {
            self.lastFix = fix
            awaitingReanchorConfirmation = true
            currentPoint = point
            appendTraveled(point)
            return
        }

        // Two fixes taken while standing still differ by roughly their error
        // radius, and that difference is a fresh random direction every second.
        // Credited as travel it accumulates without bound: the dot wanders, the
        // trail scribbles, and the distance climbs while the phone sits on a
        // table. Below the noise floor nothing moved.
        guard delta > noiseFloor else {
            awaitingReanchorConfirmation = false
            // Keep whichever fix the receiver is more confident about, so the
            // anchor sharpens while standing still instead of drifting.
            if fix.horizontalAccuracy < lastFix.horizontalAccuracy {
                self.lastFix = fix
            }
            return
        }

        awaitingReanchorConfirmation = false
        distance += delta
        self.lastFix = fix
        currentPoint = point
        appendTraveled(point)
    }

    /// Movement smaller than this is indistinguishable from receiver noise.
    ///
    /// Scaled by the worse of the two fixes: a clean 5 m fix registers a genuine
    /// few steps, while a 40 m urban-canyon fix has to show real travel before it
    /// counts. Capped so a terrible fix can't freeze tracking outright.
    private static func noiseFloor(_ a: CLLocation, _ b: CLLocation) -> Double {
        let worst = max(a.horizontalAccuracy, b.horizontalAccuracy)
        return min(max(worst * 0.75, 3), 30)
    }

    private func appendTraveled(_ point: GeoPoint) {
        if let last = traveled.last, last.distance(to: point) < 3 { return }
        traveled.append(point)
        if traveled.count > 3_000 { traveled.removeFirst(traveled.count - 3_000) }
    }

    /// Whether the current fix is good enough to unlock evidence.
    ///
    /// A fix accurate to 50 m that claims you are 20 m from the clue is really
    /// saying you are somewhere in a city block — unlocking on that is how
    /// evidence gets collected from a sofa.
    private func isFixTrustworthy(for radius: Double) -> Bool {
        if awaitingReanchorConfirmation { return false }
        guard let accuracy = location.accuracy, accuracy >= 0 else { return false }
        return accuracy <= max(radius, 20)
    }

    /// True when the detective is standing inside the discovery radius but the
    /// fix is too vague to prove it, so the UI can say why nothing unlocked.
    var isHoldingForBetterFix: Bool {
        guard phase == .active, nextClue != nil else { return false }
        guard let distanceToNextClue else { return false }
        let radius = store.profile.discoveryRadius
        guard distanceToNextClue <= radius else { return false }
        return !isFixTrustworthy(for: radius)
    }

    private func updateDistanceToNextClue() {
        guard let mysteryCase, let next = mysteryCase.nextClue else {
            distanceToNextClue = nil
            return
        }
        if let currentPoint {
            distanceToNextClue = currentPoint.distance(to: next.point)
        } else {
            distanceToNextClue = nil
        }
    }

    private func checkForDiscovery() {
        guard let mysteryCase, let next = mysteryCase.nextClue else { return }
        guard let distanceToNextClue else { return }

        if distanceToNextClue <= 120, !announcedClueIDs.contains(next.id) {
            announcedClueIDs.insert(next.id)
            proximityTick += 1
            NotificationService.closingIn(on: next, metres: distanceToNextClue)
        }

        let radius = store.profile.discoveryRadius
        guard distanceToNextClue <= radius else { return }
        // Reaching the evidence has to be something we actually observed, not
        // something a drifting or freshly re-acquired fix implied.
        guard isFixTrustworthy(for: radius) else { return }

        award(next, pinnedToCurrentPosition: true)
    }

    /// Banks the next clue without waiting for GPS proximity.
    ///
    /// The escape hatch for evidence that landed somewhere unreachable — behind a
    /// fence, inside a building, or lost to drift. Pass `asOverride: false` when
    /// the detective demonstrably reached the evidence by another means, such as
    /// tapping it through the AR lens from inside the discovery radius: that is a
    /// real find and shouldn't stain the record.
    func markNextClueFound(asOverride: Bool = true) {
        guard phase == .active || phase == .paused, let next = nextClue else { return }
        if asOverride { didUseOverride = true }
        award(next, pinnedToCurrentPosition: !asOverride)
    }

    private func award(_ clue: Clue, pinnedToCurrentPosition: Bool) {
        guard var mysteryCase,
              let index = mysteryCase.clues.firstIndex(where: { $0.id == clue.id }) else { return }

        mysteryCase.clues[index].foundAt = Date()
        // The clue is pinned wherever the detective actually stood.
        if pinnedToCurrentPosition, let currentPoint {
            mysteryCase.clues[index].point = currentPoint
        }
        announcedClueIDs.insert(clue.id)
        self.mysteryCase = mysteryCase
        store.updateActiveCase(mysteryCase)

        let found = mysteryCase.foundClues.count
        pendingClue = mysteryCase.clues[index]
        discoveryTick += 1
        NotificationService.clueDiscovered(
            mysteryCase.clues[index],
            found: found,
            total: mysteryCase.clues.count
        )
        updateDistanceToNextClue()
        persistSnapshot(force: true)
    }

    // MARK: - Crash recovery

    /// Called at launch: revives an investigation that never got closed.
    func resumeInterruptedSessionIfNeeded() {
        guard phase == .idle,
              let snapshot = store.savedSession,
              let active = store.activeCase,
              active.id == snapshot.caseID,
              !active.isSolved else { return }
        restore(active, from: snapshot)
    }

    /// Writes the live session to disk, throttled to once every few seconds.
    private func persistSnapshot(force: Bool = false) {
        guard let mysteryCase, isLive else { return }
        if !force, Date().timeIntervalSince(lastSnapshotSave) < 5 { return }
        lastSnapshotSave = Date()
        store.saveSession(
            SessionSnapshot(
                caseID: mysteryCase.id,
                elapsed: elapsed,
                distance: distance,
                traveled: traveled,
                savedAt: Date(),
                wasRunning: phase == .active
            )
        )
    }
}
