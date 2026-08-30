//
//  RouteBuilder.swift
//  MysteryRun
//
//  Builds a loop route around the detective's current position. Waypoints are
//  snapped to real streets with MKDirections so clues land on pavement, not in
//  the middle of a block. Falls back to a geometric loop when routing is
//  unavailable (offline, or an unroutable area).
//

import CoreLocation
import Foundation
import MapKit

nonisolated struct GeneratedRoute: Sendable {
    var points: [GeoPoint]
    var distance: Double
    var snappedToStreets: Bool
}

nonisolated enum RouteBuilder {
    /// Fallback origin used when the device has no fix yet, so the app is always explorable.
    static let fallbackOrigin = GeoPoint(latitude: 42.3639, longitude: -71.0507)

    static func makeRoute(
        around origin: GeoPoint,
        targetDistance: Double,
        seed: UInt64 = UInt64.random(in: 0..<UInt64.max)
    ) async -> GeneratedRoute {
        var rng = SeededGenerator(seed: seed)
        let anchors = loopAnchors(around: origin, targetDistance: targetDistance, rng: &rng)

        if let snapped = await snapToStreets(anchors: anchors) {
            return snapped
        }

        let distance = pathLength(anchors)
        return GeneratedRoute(points: anchors, distance: distance, snappedToStreets: false)
    }

    /// Calibrates a freehand path the detective drew on the map onto real walkable
    /// streets. Each segment is routed with walking directions; any leg that can't be
    /// routed (or that would send them on an absurd detour) keeps the drawn shape,
    /// so a long or remote sketch still produces a usable route.
    static func makeRoute(fromDrawnPath drawn: [GeoPoint], maxLegs: Int = 14) async -> GeneratedRoute {
        let cleaned = thin(drawn, minSpacing: 12)
        guard cleaned.count > 1 else {
            return GeneratedRoute(points: cleaned, distance: 0, snappedToStreets: false)
        }

        let anchors = anchorIndices(in: cleaned, maxLegs: maxLegs)
        guard anchors.count > 1 else {
            return GeneratedRoute(points: cleaned, distance: pathLength(cleaned), snappedToStreets: false)
        }

        var stitched: [GeoPoint] = []
        var snappedLegs = 0
        var totalLegs = 0

        for index in 0..<(anchors.count - 1) {
            let startIndex = anchors[index]
            let endIndex = anchors[index + 1]
            let drawnLeg = Array(cleaned[startIndex...endIndex])
            guard drawnLeg.count > 1 else { continue }
            totalLegs += 1

            var legPoints = drawnLeg
            if let snapped = await walkingLeg(from: drawnLeg[0], to: drawnLeg[drawnLeg.count - 1]) {
                let drawnLength = pathLength(drawnLeg)
                let snappedLength = pathLength(snapped)
                // Keep the street version only when it stays close to what was drawn.
                if snappedLength <= max(drawnLength * 2.2, drawnLength + 400) {
                    legPoints = snapped
                    snappedLegs += 1
                }
            }

            if stitched.isEmpty {
                stitched.append(contentsOf: legPoints)
            } else {
                stitched.append(contentsOf: legPoints.dropFirst())
            }

            // Be gentle with the directions service on long sketches.
            try? await Task.sleep(for: .milliseconds(120))
        }

        guard stitched.count > 1 else {
            return GeneratedRoute(points: cleaned, distance: pathLength(cleaned), snappedToStreets: false)
        }

        return GeneratedRoute(
            points: stitched,
            distance: pathLength(stitched),
            snappedToStreets: totalLegs > 0 && snappedLegs * 2 >= totalLegs
        )
    }

    // MARK: - Path shaping

    /// Drops points closer together than `minSpacing` metres so a finger-drawn
    /// stroke becomes an evenly sampled path.
    static func thin(_ points: [GeoPoint], minSpacing: Double) -> [GeoPoint] {
        guard let first = points.first else { return [] }
        var result: [GeoPoint] = [first]
        for point in points.dropFirst() where point.distance(to: result[result.count - 1]) >= minSpacing {
            result.append(point)
        }
        if let last = points.last, last.distance(to: result[result.count - 1]) > 1 {
            result.append(last)
        }
        return result
    }

    /// Indices of evenly spaced routing anchors along a path, always including
    /// the first and last point.
    private static func anchorIndices(in points: [GeoPoint], maxLegs: Int) -> [Int] {
        let total = pathLength(points)
        guard total > 0 else { return [] }

        let desiredLegs = min(max(Int((total / 350).rounded()), 2), max(maxLegs, 2))
        let spacing = total / Double(desiredLegs)

        var indices: [Int] = [0]
        var travelled: Double = 0
        var nextThreshold = spacing

        for index in 0..<(points.count - 1) {
            travelled += points[index].distance(to: points[index + 1])
            if travelled >= nextThreshold, indices.last != index + 1 {
                indices.append(index + 1)
                nextThreshold += spacing
            }
        }

        if indices.last != points.count - 1 {
            indices.append(points.count - 1)
        }
        return indices
    }

    // MARK: - Geometry

    /// Places 6 anchor points on a jittered circle whose circumference matches the target distance.
    private static func loopAnchors(
        around origin: GeoPoint,
        targetDistance: Double,
        rng: inout SeededGenerator
    ) -> [GeoPoint] {
        let vertexCount = 6
        // Street routing is always longer than the straight-line polygon, so aim short.
        let radius = (targetDistance * 0.78) / (2 * .pi)
        let startAngle = Double.random(in: 0..<(2 * .pi), using: &rng)

        var points: [GeoPoint] = []
        for index in 0..<vertexCount {
            let angle = startAngle + (2 * .pi) * Double(index) / Double(vertexCount)
            let jitter = Double.random(in: 0.82...1.18, using: &rng)
            points.append(offset(origin, distance: radius * jitter, bearing: angle))
        }
        points.insert(origin, at: 0)
        points.append(origin)
        return points
    }

    /// Moves a coordinate `distance` metres along a bearing (radians).
    static func offset(_ point: GeoPoint, distance: Double, bearing: Double) -> GeoPoint {
        let earthRadius: Double = 6_371_000
        let latitude = point.latitude * .pi / 180
        let longitude = point.longitude * .pi / 180
        let angular = distance / earthRadius

        let newLatitude = asin(sin(latitude) * cos(angular) + cos(latitude) * sin(angular) * cos(bearing))
        let newLongitude = longitude + atan2(
            sin(bearing) * sin(angular) * cos(latitude),
            cos(angular) - sin(latitude) * sin(newLatitude)
        )
        return GeoPoint(latitude: newLatitude * 180 / .pi, longitude: newLongitude * 180 / .pi)
    }

    static func pathLength(_ points: [GeoPoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var total: Double = 0
        for index in 0..<(points.count - 1) {
            total += points[index].distance(to: points[index + 1])
        }
        return total
    }

    // MARK: - Street snapping

    private static func snapToStreets(anchors: [GeoPoint]) async -> GeneratedRoute? {
        guard anchors.count > 1 else { return nil }
        var stitched: [GeoPoint] = []

        for index in 0..<(anchors.count - 1) {
            guard let leg = await walkingLeg(from: anchors[index], to: anchors[index + 1]) else {
                return nil
            }
            if stitched.isEmpty {
                stitched.append(contentsOf: leg)
            } else {
                stitched.append(contentsOf: leg.dropFirst())
            }
        }

        guard stitched.count > 4 else { return nil }
        return GeneratedRoute(points: stitched, distance: pathLength(stitched), snappedToStreets: true)
    }

    private static func walkingLeg(from: GeoPoint, to: GeoPoint) async -> [GeoPoint]? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to.coordinate))
        request.transportType = .walking
        request.requestsAlternateRoutes = false

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return nil }
            let polyline = route.polyline
            var coordinates = [CLLocationCoordinate2D](
                repeating: CLLocationCoordinate2D(),
                count: polyline.pointCount
            )
            polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
            return coordinates.map(GeoPoint.init)
        } catch {
            return nil
        }
    }
}
