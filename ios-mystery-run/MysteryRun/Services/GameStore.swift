//
//  GameStore.swift
//  MysteryRun
//

import Foundation
import Observation

/// Owns persisted detective state: profile, XP, streak and closed case files.
@Observable
final class GameStore {
    private(set) var profile: DetectiveProfile
    private(set) var history: [CaseRecord]
    /// The case currently on the board — kept so an unfinished investigation survives a relaunch.
    var activeCase: MysteryCase?

    /// Progress of an investigation that was interrupted rather than closed.
    private(set) var savedSession: SessionSnapshot?

    private let profileURL: URL
    private let historyURL: URL
    private let activeCaseURL: URL
    private let sessionURL: URL

    init() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        profileURL = directory.appendingPathComponent("profile.json")
        historyURL = directory.appendingPathComponent("history.json")
        activeCaseURL = directory.appendingPathComponent("active-case.json")
        sessionURL = directory.appendingPathComponent("live-session.json")

        profile = GameStore.load(DetectiveProfile.self, from: profileURL) ?? DetectiveProfile()
        history = GameStore.load([CaseRecord].self, from: historyURL) ?? []
        activeCase = GameStore.load(MysteryCase.self, from: activeCaseURL)

        let session = GameStore.load(SessionSnapshot.self, from: sessionURL)
        // Only offer to resume a session that still matches the case on the board.
        if let session, session.isStale == false, session.caseID == activeCase?.id {
            savedSession = session
        } else {
            savedSession = nil
            try? FileManager.default.removeItem(at: sessionURL)
        }
    }

    // MARK: - Case numbering

    var nextCaseNumber: Int {
        (history.map(\.number).max() ?? 13) + 1
    }

    // MARK: - Mutations

    func setActiveCase(_ mysteryCase: MysteryCase?) {
        activeCase = mysteryCase
        persistActiveCase()
    }

    func updateActiveCase(_ mysteryCase: MysteryCase) {
        activeCase = mysteryCase
        persistActiveCase()
    }

    // MARK: - Live session recovery

    func saveSession(_ snapshot: SessionSnapshot) {
        savedSession = snapshot
        GameStore.save(snapshot, to: sessionURL)
    }

    func clearSession() {
        savedSession = nil
        try? FileManager.default.removeItem(at: sessionURL)
    }

    func markCaseStarted() {
        profile.casesStarted += 1
        persistProfile()
    }

    func updatePreferences(mode: SessionMode? = nil, distance: Double? = nil, radius: Double? = nil) {
        if let mode { profile.preferredMode = mode }
        if let distance { profile.preferredDistance = distance }
        if let radius { profile.discoveryRadius = radius }
        persistProfile()
    }

    /// Files a finished (or abandoned) investigation and awards XP.
    @discardableResult
    func closeCase(
        _ mysteryCase: MysteryCase,
        distance: Double,
        duration: TimeInterval
    ) -> CaseRecord {
        let found = mysteryCase.foundClues
        var xp = found.reduce(0) { $0 + $1.xp }
        let solved = found.count == mysteryCase.clues.count
        if solved { xp += 250 }

        if solved {
            applyStreak()
            if profile.streak >= 3 { xp += 50 }
        }

        profile.xp += xp
        let record = CaseRecord(
            id: mysteryCase.id,
            number: mysteryCase.number,
            title: mysteryCase.title,
            photoAsset: mysteryCase.photoAsset,
            conclusion: mysteryCase.conclusion,
            premise: mysteryCase.premise,
            solution: mysteryCase.solution,
            locationName: mysteryCase.locationName,
            closedAt: Date(),
            distance: distance,
            duration: duration,
            mode: mysteryCase.mode,
            cluesFound: found.count,
            clueTotal: mysteryCase.clues.count,
            xpEarned: xp,
            clues: mysteryCase.clues
        )
        history.insert(record, at: 0)
        if history.count > 60 { history.removeLast(history.count - 60) }

        persistProfile()
        persistHistory()
        return record
    }

    private func applyStreak() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        if let last = profile.lastSolvedDay {
            let lastDay = calendar.startOfDay(for: last)
            if calendar.isDate(lastDay, inSameDayAs: today) {
                // Already counted today.
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                      calendar.isDate(lastDay, inSameDayAs: yesterday) {
                profile.streak += 1
            } else {
                profile.streak = 1
            }
        } else {
            profile.streak = 1
        }
        profile.bestStreak = max(profile.bestStreak, profile.streak)
        profile.lastSolvedDay = today
    }

    /// Streak lapses if the last solve wasn't today or yesterday.
    var isStreakAtRisk: Bool {
        guard let last = profile.lastSolvedDay else { return false }
        let calendar = Calendar.current
        return !calendar.isDateInToday(last)
    }

    var solvedCount: Int { history.filter(\.solved).count }

    var totalDistance: Double { history.reduce(0) { $0 + $1.distance } }

    var weeklySolves: Int {
        let calendar = Calendar.current
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) else { return 0 }
        return history.filter { $0.solved && $0.closedAt >= weekAgo }.count
    }

    func resetEverything() {
        profile = DetectiveProfile()
        history = []
        activeCase = nil
        persistProfile()
        persistHistory()
        persistActiveCase()
    }

    // MARK: - Persistence

    private func persistProfile() { GameStore.save(profile, to: profileURL) }
    private func persistHistory() { GameStore.save(history, to: historyURL) }

    private func persistActiveCase() {
        if let activeCase {
            GameStore.save(activeCase, to: activeCaseURL)
        } else {
            try? FileManager.default.removeItem(at: activeCaseURL)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("[GameStore] Could not decode \(url.lastPathComponent); starting fresh.")
            return nil
        }
    }

    private static func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[GameStore] Could not save \(url.lastPathComponent).")
        }
    }
}
