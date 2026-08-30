//
//  GeoAR.swift
//  MysteryRun
//

import CoreMotion
import Foundation
import CoreGraphics

/// Camera-geometry helpers for the AR lens. Pure functions so the projection
/// math stays testable and free of view state.
enum GeoAR {
    /// Approximate horizontal field of view of the rear wide camera, radians.
    /// Close enough for pinning street-level evidence; exact intrinsics vary by model.
    static let horizontalFOV: Double = 65 * .pi / 180

    /// Assume the phone's eye is about this far above the ground, metres.
    static let eyeHeight: Double = 1.6

    /// True bearing in degrees from one point to another (0 = north, clockwise).
    static func bearingDegrees(from origin: GeoPoint, to target: GeoPoint) -> Double {
        let lat1 = origin.latitude * .pi / 180
        let lat2 = target.latitude * .pi / 180
        let dLon = (target.longitude - origin.longitude) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        return bearing < 0 ? bearing + 360 : bearing
    }

    /// Projects a point into screen space using the live device attitude.
    ///
    /// - Parameters:
    ///   - origin: the detective's current position.
    ///   - target: the point being pinned.
    ///   - heightAboveGround: how high above the street to hover, metres.
    ///   - declinationDegrees: magnetic declination so the magnetometer frame
    ///     (north-referenced) agrees with true bearings.
    /// - Returns: the projected point, or `nil` when the target sits behind the camera.
    static func project(
        from origin: GeoPoint,
        to target: GeoPoint,
        heightAboveGround: Double,
        matrix: CMRotationMatrix,
        viewport: CGSize,
        declinationDegrees: Double?
    ) -> CGPoint? {
        let lat1 = origin.latitude * .pi / 180
        let dLat = (target.latitude - origin.latitude) * .pi / 180
        let dLon = (target.longitude - origin.longitude) * .pi / 180

        var east = dLon * 6_371_000 * cos(lat1)
        var north = dLat * 6_371_000

        // The attitude reference frame is magnetic-north based; rotate the flat
        // components by declination so both sides of the math agree on "north".
        if let declinationDegrees {
            let radians = -declinationDegrees * .pi / 180
            let cosD = cos(radians)
            let sinD = sin(radians)
            let rotatedEast = east * cosD - north * sinD
            let rotatedNorth = east * sinD + north * cosD
            east = rotatedEast
            north = rotatedNorth
        }

        let up = heightAboveGround - eyeHeight
        // Reference frame (xMagneticNorthZAxis): x = magnetic north, y = west, z = up.
        let ref = SIMD3(north, -east, up)

        // v_device = Rᵗ · v_ref — the rotation matrix maps device axes into the
        // reference frame, so the transpose pulls world directions into camera space.
        let device = SIMD3(
            matrix.m11 * ref.x + matrix.m21 * ref.y + matrix.m31 * ref.z,
            matrix.m12 * ref.x + matrix.m22 * ref.y + matrix.m32 * ref.z,
            matrix.m13 * ref.x + matrix.m23 * ref.y + matrix.m33 * ref.z
        )

        // The back camera looks along −z; screen-right is +x, screen-up is +y.
        let depth = -device.z
        guard depth > 0.05 else { return nil }

        let focal = (viewport.width / 2) / tan(horizontalFOV / 2)
        return CGPoint(
            x: viewport.width / 2 + focal * device.x / depth,
            y: viewport.height / 2 - focal * device.y / depth
        )
    }

    /// Scale a marker by distance so far clues read small and close ones loom.
    static func markerScale(forDistance metres: Double) -> CGFloat {
        let raw = 38 / max(metres, 4)
        return CGFloat(min(max(raw, 0.45), 2.2))
    }

    /// Where to park an off-screen chevron pointing at a bearing: clamped to the
    /// horizontal edge of the view in the target's direction.
    static func edgePoint(
        bearingDegrees: Double,
        matrix: CMRotationMatrix,
        viewport: CGSize
    ) -> CGPoint {
        // Camera forward is the negative of the device z axis (third matrix column
        // in reference coordinates: north, west, up).
        let forwardNorth = -matrix.m13
        let forwardWest = -matrix.m23
        let forwardEast = -forwardWest
        var cameraBearing = atan2(forwardEast, forwardNorth) * 180 / .pi

        var relative = bearingDegrees - cameraBearing
        while relative > 180 { relative -= 360 }
        while relative < -180 { relative += 360 }

        let halfFOV = horizontalFOV / 2
        let clamped = max(-halfFOV + 0.05, min(halfFOV - 0.05, relative * .pi / 180))
        let fraction = tan(clamped) / tan(halfFOV)

        return CGPoint(
            x: viewport.width / 2 + fraction * viewport.width / 2,
            y: viewport.height * 0.42
        )
    }
}
