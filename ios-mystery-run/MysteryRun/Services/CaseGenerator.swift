//
//  CaseGenerator.swift
//  MysteryRun
//
//  Combines an archetype, a setting, a token cast and a set of proof beats into a
//  unique case, then pins each clue to a point along the generated route.
//

import CoreLocation
import Foundation

nonisolated enum CaseGenerator {
    /// Builds a full case for a route. `route` must be ordered start → finish.
    static func makeCase(
        number: Int,
        mode: SessionMode,
        route: [GeoPoint],
        plannedDistance: Double,
        usesRealRoute: Bool,
        isCustomRoute: Bool = false,
        seed: UInt64 = UInt64.random(in: 0..<UInt64.max)
    ) -> MysteryCase {
        var rng = SeededGenerator(seed: seed)

        let archetype = CaseLibrary.archetypes.randomElement(using: &rng) ?? CaseLibrary.archetypes[0]
        let setting = CaseLibrary.settings.randomElement(using: &rng) ?? CaseLibrary.settings[0]
        let clueCount = clueCount(for: plannedDistance)
        let includeTwist = Double.random(in: 0...1, using: &rng) < 0.35

        var tokens = makeTokens(setting: setting, clueCount: clueCount, rng: &rng)

        var beats = selectBeats(
            archetype: archetype,
            count: clueCount,
            includeTwist: includeTwist,
            rng: &rng
        )
        // Keep the same evidence object from appearing twice in one case.
        var usedKinds = Set<String>()
        var clues: [Clue] = []
        let offsets = clueOffsets(count: beats.count, distance: plannedDistance)

        for (index, beat) in beats.enumerated() {
            let kindID = beat.kinds.first { !usedKinds.contains($0) }
                ?? beat.kinds.randomElement(using: &rng)
                ?? "note"
            usedKinds.insert(kindID)
            let kind = CaseLibrary.evidenceKind(id: kindID)

            var localTokens = tokens
            localTokens["spot"] = setting.spots.randomElement(using: &rng) ?? setting.spots[0]

            let offset = offsets[index]
            let point = pointAlong(route: route, distance: offset) ?? route.last ?? GeoPoint(latitude: 0, longitude: 0)

            let clue = Clue(
                index: index + 1,
                title: kind.title,
                symbolName: kind.symbolName,
                fragment: render(beat.fragments.randomElement(using: &rng) ?? "", tokens: localTokens),
                discovery: render(beat.discoveries.randomElement(using: &rng) ?? "", tokens: localTokens).sentenceCased,
                deduction: render(beat.deductions.randomElement(using: &rng) ?? "", tokens: localTokens),
                isPivotal: beat.isPivotal,
                isMisleading: beat.isMisleading,
                point: point,
                routeOffset: offset,
                xp: beat.isPivotal ? 75 : 50
            )
            clues.append(clue)
        }
        beats.removeAll()

        tokens["clueCount"] = clueCount.spelledOut

        let title = render(archetype.titles.randomElement(using: &rng) ?? "Untitled Case", tokens: tokens)
        let premise = render(archetype.premises.randomElement(using: &rng) ?? "", tokens: tokens)
        let conclusion = render(archetype.conclusions.randomElement(using: &rng) ?? "", tokens: tokens)
        var solution = render(archetype.narratives.randomElement(using: &rng) ?? "", tokens: tokens)
        if includeTwist {
            // The planted evidence only makes sense in hindsight, so the account
            // has to own up to it rather than quietly leave it out.
            solution += " One piece of what you recovered was never real. It was placed early on the trail to send the search the wrong way, and it worked for exactly as long as \(tokens["culprit"] ?? "the culprit") needed it to."
        }
        let twistNote: String? = includeTwist
            ? "One piece of evidence in this file was left to be found. Treat the first thing you see with suspicion."
            : nil

        return MysteryCase(
            number: number,
            title: title,
            premise: premise,
            photoAsset: setting.photoAsset,
            locationName: setting.name,
            mode: mode,
            clues: clues,
            conclusion: conclusion,
            solution: solution,
            twistNote: twistNote,
            route: route,
            plannedDistance: plannedDistance,
            usesRealRoute: usesRealRoute,
            isCustomRoute: isCustomRoute
        )
    }

    // MARK: - Composition helpers

    /// Metres of route per piece of evidence. Keeps clues proportionally scattered
    /// whether the route is a 2 km loop or a 50 mile trek.
    static let metresPerClue: Double = 620

    /// Evidence count scaled to route length: roughly one find every ~620 m,
    /// never fewer than 4 and never more than the story can carry.
    static func clueCount(for distance: Double) -> Int {
        let scaled = Int((distance / metresPerClue).rounded())
        return min(max(scaled, 4), 20)
    }

    /// Points where evidence will sit along a route — used for briefing previews.
    static func evidencePoints(route: [GeoPoint], distance: Double) -> [GeoPoint] {
        clueOffsets(count: clueCount(for: distance), distance: distance)
            .compactMap { pointAlong(route: route, distance: $0) }
    }

    private static func makeTokens(
        setting: CaseSetting,
        clueCount: Int,
        rng: inout SeededGenerator
    ) -> [String: String] {
        let name = CaseLibrary.names.randomElement(using: &rng) ?? "Alma Vester"
        let role = CaseLibrary.roles.randomElement(using: &rng) ?? "night courier"
        let culprit = CaseLibrary.culprits.randomElement(using: &rng) ?? "the harbourmaster"
        let item = CaseLibrary.items.randomElement(using: &rng) ?? "the payroll satchel"
        let motive = CaseLibrary.motives.randomElement(using: &rng) ?? "gambling debts"
        let landmark = setting.landmarks.randomElement(using: &rng) ?? "the pier"
        let time = CaseLibrary.times.randomElement(using: &rng) ?? "11:58 PM"
        let vehicle = CaseLibrary.vehicles.randomElement(using: &rng) ?? "a grey delivery van"

        return [
            "name": name,
            "role": role,
            "roleTitle": role.titleCased,
            "roleTitleUpper": role.uppercased(),
            "culprit": culprit,
            "culpritUpper": culprit.uppercased(),
            "item": item,
            "itemTitle": item.strippedArticle.titleCased,
            "itemUpper": item.uppercased(),
            "motive": motive,
            "place": setting.name,
            "landmark": landmark,
            "landmarkTitle": landmark.strippedArticle.titleCased,
            "landmarkTitleUpper": landmark.strippedArticle.uppercased(),
            "time": time,
            "vehicle": vehicle,
            "clueCount": clueCount.spelledOut,
            "spot": setting.spots.first ?? ""
        ]
    }

    private static func selectBeats(
        archetype: CaseArchetype,
        count: Int,
        includeTwist: Bool,
        rng: inout SeededGenerator
    ) -> [ProofBeat] {
        var core = archetype.beats
        guard let clincher = core.popLast() else { return [] }

        var chosen: [ProofBeat] = []
        if includeTwist, let herring = CaseLibrary.redHerringBeats.randomElement(using: &rng) {
            chosen.append(herring)
        }

        var pool = core
        while chosen.count < count - 1, !pool.isEmpty {
            chosen.append(pool.removeFirst())
        }

        // Long routes need more beats than the archetype carries, so the filler
        // pool is reshuffled and reused until the count is met.
        var fillers = CaseLibrary.fillerBeats.shuffled(using: &rng)
        while chosen.count < count - 1 {
            if fillers.isEmpty {
                fillers = CaseLibrary.fillerBeats.shuffled(using: &rng)
                guard !fillers.isEmpty else { break }
            }
            let filler = fillers.removeFirst()
            let insertAt = chosen.isEmpty ? 0 : Int.random(in: 1...chosen.count, using: &rng)
            chosen.insert(filler, at: insertAt)
        }

        chosen.append(clincher)
        return Array(chosen.prefix(count))
    }

    /// Spreads clues along the route, leaving a warm-up before the first and a
    /// short walk back after the last.
    static func clueOffsets(count: Int, distance: Double) -> [Double] {
        guard count > 0 else { return [] }
        let start = distance * 0.12
        let end = distance * 0.94
        guard count > 1 else { return [(start + end) / 2] }
        let step = (end - start) / Double(count - 1)
        return (0..<count).map { start + step * Double($0) }
    }

    /// Walks the polyline until `distance` metres have been covered.
    static func pointAlong(route: [GeoPoint], distance: Double) -> GeoPoint? {
        guard route.count > 1 else { return route.first }
        var travelled: Double = 0
        for index in 0..<(route.count - 1) {
            let a = route[index]
            let b = route[index + 1]
            let segment = a.distance(to: b)
            if travelled + segment >= distance, segment > 0 {
                let ratio = (distance - travelled) / segment
                return GeoPoint(
                    latitude: a.latitude + (b.latitude - a.latitude) * ratio,
                    longitude: a.longitude + (b.longitude - a.longitude) * ratio
                )
            }
            travelled += segment
        }
        return route.last
    }

    static func render(_ template: String, tokens: [String: String]) -> String {
        var output = template
        for (key, value) in tokens {
            output = output.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return output
    }
}

nonisolated extension String {
    var titleCased: String {
        split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    var sentenceCased: String {
        guard let first = self.first else { return self }
        return first.uppercased() + dropFirst()
    }

    /// Drops a leading article so a phrase can be used inside a title.
    var strippedArticle: String {
        for article in ["the ", "a ", "an "] where lowercased().hasPrefix(article) {
            return String(dropFirst(article.count))
        }
        return self
    }
}

nonisolated extension Int {
    var spelledOut: String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return indices.contains(self) ? words[self] : "\(self)"
    }

    private var indices: Range<Int> { 0..<11 }
}
