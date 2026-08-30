//
//  InvestigationEngine.swift
//  MysteryRun
//
//  Drives a live investigation: elapsed time, distance covered, and GPS-proximity
//  clue unlocking. Pace is never part of the logic — walkers and runners progress
//  identically. Indoor sessions swap GPS for simulated progress along the route.
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
    private var virtualOffset: Double = 0
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

    var isIndoor: Bool { mysteryCase?.mode == .indoor }

    /// Radius in metres at which the next clue unlocks — shown as a map ring.
    var discoveryRadius: Double {
        isIndoor ? 8 : store.profile.discoveryRadius
    }

    // MARK: - Lifecycle

    func begin(_ mysteryCase: MysteryCase) {
        self.mysteryCase = mysteryCase
        phase = .active
        elapsed = 0
        distance = 0
        virtualOffset = 0
        traveled = []
        announcedClueIDs = []
        lastFix = nil
        pendingClue = nil
        lastRecord = nil
        didUseOverride = false
        runningSince = Date()
        accumulatedElapsed = 0
        currentPoint = mysteryCase.route.first

        store.markCaseStarted()
        store.clearSession()
        Task { await NotificationService.requestPermission() }
        if mysteryCase.mode.usesLiveLocation {
            location.startTracking()
        }
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
        virtualOffset = snapshot.virtualOffset
        announcedClueIDs = Set(mysteryCase.foundClues.map(\.id))
        lastFix = nil
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
        if mysteryCase?.mode.usesLiveLocation == true {
            location.startTracking()
        }
    }

    func togglePause() {
        phase == .paused ? resume() : pause()
    }

    /// Ends the session, files the case and produces the summary record.
    @discardableResult
    func finish() -> CaseRecord? {
        guard let mysteryCase else { return nil }
        ticker?.cancel()
        ticker = nil
        location.stopTracking()
        phase = .finished

        let record = store.closeCase(mysteryCase, distance: distance, duration: elapsed)
        lastRecord = record
        store.setActiveCase(mysteryCase)
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

        if isIndoor {
            advanceVirtualPosition()
            updateDistanceToNextClue()
            checkForDiscovery()
        }

        persistSnapshot()
    }

    /// Entry point for every GPS fix — runs in the foreground and background alike.
    private func ingest(_ fix: CLLocation) {
        guard phase == .active, !isIndoor else { return }
        if let runningSince {
            elapsed = accumulatedElapsed + Date().timeIntervalSince(runningSince)
        }
        consume(fix)
        updateDistanceToNextClue()
        checkForDiscovery()
        persistSnapshot()
    }

    /// Indoor / treadmill fallback: distance accrues at the session's assumed pace.
    private func advanceVirtualPosition() {
        guard let mysteryCase else { return }
        let speed = mysteryCase.mode.assumedSpeed
        virtualOffset = min(virtualOffset + speed, mysteryCase.plannedDistance)
        distance = virtualOffset
        if let point = CaseGenerator.pointAlong(route: mysteryCase.route, distance: virtualOffset) {
            currentPoint = point
            appendTraveled(point)
        }
    }

    private func consume(_ fix: CLLocation) {
        // Ignore inaccurate fixes so the distance stays honest.
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy < 60 else { return }
        // Ignore cached fixes handed over from before this session started.
        guard abs(fix.timestamp.timeIntervalSinceNow) < 30 else { return }

        let point = GeoPoint(fix.coordinate)
        if let lastFix {
            let delta = fix.distance(from: lastFix)
            if delta > 2, delta < 200 {
                distance += delta
                appendTraveled(point)
                self.lastFix = fix
            } else if delta >= 200 {
                // A GPS jump (tunnel, canyon, cold start). Don't credit the leap,
                // but re-anchor — otherwise every later fix looks like a jump too
                // and distance freezes for the rest of the run.
                self.lastFix = fix
                appendTraveled(point)
            }
        } else {
            lastFix = fix
            appendTraveled(point)
        }
        currentPoint = point
    }

    private func appendTraveled(_ point: GeoPoint) {
        if let last = traveled.last, last.distance(to: point) < 3 { return }
        traveled.append(point)
        if traveled.count > 3_000 { traveled.removeFirst(traveled.count - 3_000) }
    }

    private func updateDistanceToNextClue() {
        guard let mysteryCase, let next = mysteryCase.nextClue else {
            distanceToNextClue = nil
            return
        }
        if isIndoor {
            distanceToNextClue = max(0, next.routeOffset - virtualOffset)
        } else if let currentPoint {
            distanceToNextClue = currentPoint.distance(to: next.point)
        } else {
            distanceToNextClue = nil
        }
    }

    private func checkForDiscovery() {
        guard var mysteryCase, let next = mysteryCase.nextClue else { return }
        guard let distanceToNextClue else { return }

        if distanceToNextClue <= 120, !announcedClueIDs.contains(next.id) {
            announcedClueIDs.insert(next.id)
            proximityTick += 1
            NotificationService.closingIn(on: next, metres: distanceToNextClue)
        }

        let radius = isIndoor ? 8 : store.profile.discoveryRadius
        guard distanceToNextClue <= radius else { return }

        award(next, pinnedToCurrentPosition: !isIndoor)
    }

    /// Banks the next clue without GPS. The escape hatch for evidence that landed
    /// somewhere unreachable — behind a fence, inside a building, or lost to drift.
    func markNextClueFound() {
        guard phase == .active || phase == .paused, let next = nextClue else { return }
        didUseOverride = true
        award(next, pinnedToCurrentPosition: false)
    }

    private func award(_ clue: Clue, pinnedToCurrentPosition: Bool) {
        guard var mysteryCase,
              let index = mysteryCase.clues.firstIndex(where: { $0.id == clue.id }) else { return }

        mysteryCase.clues[index].foundAt = Date()
        // Outdoors the clue is pinned wherever the detective actually stood.
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
                virtualOffset: virtualOffset,
                savedAt: Date(),
                wasRunning: phase == .active
            )
        )
    }
}
