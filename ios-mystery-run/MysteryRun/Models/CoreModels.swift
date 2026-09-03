//
//  CoreModels.swift
//  MysteryRun
//

import CoreLocation
import Foundation

/// Codable coordinate used for cases, routes and saved history.
nonisolated struct GeoPoint: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    func distance(to other: GeoPoint) -> CLLocationDistance {
        location.distance(from: other.location)
    }
}

/// How the detective is covering the route. Purely a tracking tag — gameplay is
/// identical either way, and every case unlocks its clues from live position.
nonisolated enum SessionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case run
    case walk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .run: "Run"
        case .walk: "Walk"
        }
    }

    var symbolName: String {
        switch self {
        case .run: "figure.run"
        case .walk: "figure.walk"
        }
    }

    /// Metres per second used for time estimates.
    var assumedSpeed: Double {
        switch self {
        case .run: 2.6
        case .walk: 1.4
        }
    }

    /// Cases saved before indoor mode was withdrawn still carry it on disk.
    /// Decoding them as a walk keeps those files readable instead of throwing
    /// away the detective's history.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SessionMode(rawValue: raw) ?? .walk
    }
}

/// A physical piece of evidence, its story fragment and how it cracks the case.
nonisolated struct Clue: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var index: Int
    var title: String
    var symbolName: String
    /// What the evidence itself says or shows.
    var fragment: String
    /// Where along the route it turned up.
    var discovery: String
    /// Plain-language explanation of what it proved, used in the resolution.
    var deduction: String
    var isPivotal: Bool
    var isMisleading: Bool
    var point: GeoPoint
    /// Distance along the planned route where this clue sits, in metres.
    var routeOffset: Double
    var xp: Int
    var foundAt: Date?

    var isFound: Bool { foundAt != nil }
}

/// A single generated mystery, its route and its resolution.
nonisolated struct MysteryCase: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var number: Int
    var title: String
    var premise: String
    var photoAsset: String
    var locationName: String
    var mode: SessionMode
    var clues: [Clue]
    var conclusion: String
    /// The narrated account of what actually happened, shown once the case is
    /// closed. Optional so files saved before it existed still decode.
    var solution: String?
    var twistNote: String?
    var route: [GeoPoint]
    var plannedDistance: Double
    var usesRealRoute: Bool
    /// True when the detective drew this route themselves instead of taking the
    /// generated patrol loop. Optional so older saved files still decode.
    var isCustomRoute: Bool?
    var createdAt: Date = Date()

    var isDrawnRoute: Bool { isCustomRoute == true }

    var estimatedMinutes: Int {
        max(6, Int((plannedDistance / mode.assumedSpeed) / 60))
    }

    var foundClues: [Clue] { clues.filter(\.isFound) }
    var isSolved: Bool { clues.allSatisfy(\.isFound) }

    var nextClue: Clue? {
        clues.first { !$0.isFound }
    }
}

/// A live investigation frozen to disk so a crash, a call, or iOS reclaiming
/// memory mid-run doesn't cost the detective their progress.
nonisolated struct SessionSnapshot: Codable, Sendable {
    var caseID: UUID
    var elapsed: TimeInterval
    var distance: Double
    var traveled: [GeoPoint]
    var savedAt: Date
    var wasRunning: Bool

    /// Sessions older than this are treated as abandoned rather than resumable.
    var isStale: Bool {
        Date().timeIntervalSince(savedAt) > 6 * 3_600
    }
}

/// A closed case kept in the detective's history.
nonisolated struct CaseRecord: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var number: Int
    var title: String
    var photoAsset: String
    var conclusion: String
    /// The brief as it was originally handed over, kept so a closed file can
    /// still be read from the beginning.
    var premise: String?
    /// The narrated resolution. Optional for records filed before it existed.
    var solution: String?
    var locationName: String?
    var closedAt: Date
    var distance: Double
    var duration: TimeInterval
    var mode: SessionMode
    var cluesFound: Int
    var clueTotal: Int
    var xpEarned: Int
    var clues: [Clue]

    var solved: Bool { cluesFound == clueTotal }

    var averagePace: String {
        guard distance > 200, duration > 0 else { return "—" }
        let secondsPerKm = duration / (distance / 1000)
        let minutes = Int(secondsPerKm) / 60
        let seconds = Int(secondsPerKm) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Detective rank ladder driven by lifetime XP.
nonisolated struct DetectiveRank: Hashable, Sendable {
    let title: String
    let threshold: Int

    static let ladder: [DetectiveRank] = [
        DetectiveRank(title: "Recruit", threshold: 0),
        DetectiveRank(title: "Beat Detective", threshold: 400),
        DetectiveRank(title: "Investigator", threshold: 1_000),
        DetectiveRank(title: "Senior Investigator", threshold: 1_900),
        DetectiveRank(title: "Inspector", threshold: 3_200),
        DetectiveRank(title: "Chief Inspector", threshold: 5_000),
        DetectiveRank(title: "Nightwatch Legend", threshold: 7_500)
    ]

    static func current(for xp: Int) -> DetectiveRank {
        ladder.last { xp >= $0.threshold } ?? ladder[0]
    }

    static func next(for xp: Int) -> DetectiveRank? {
        ladder.first { xp < $0.threshold }
    }
}

/// Persisted player state.
nonisolated struct DetectiveProfile: Codable, Sendable {
    var xp: Int = 0
    var streak: Int = 0
    var bestStreak: Int = 0
    var lastSolvedDay: Date?
    var casesStarted: Int = 0
    var preferredMode: SessionMode = .run
    var preferredDistance: Double = 2_400
    var discoveryRadius: Double = 20

    var rank: DetectiveRank { DetectiveRank.current(for: xp) }
    var nextRank: DetectiveRank? { DetectiveRank.next(for: xp) }

    /// 0...1 progress towards the next rank.
    var rankProgress: Double {
        let current = rank.threshold
        guard let next = nextRank else { return 1 }
        let span = Double(next.threshold - current)
        guard span > 0 else { return 1 }
        return min(1, max(0, Double(xp - current) / span))
    }

    var xpToNextRank: Int {
        guard let next = nextRank else { return 0 }
        return max(0, next.threshold - xp)
    }
}
