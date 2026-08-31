//
//  GeoAR.swift
//  MysteryRun
//

import CoreGraphics
import CoreMotion
import Foundation

/// Camera-geometry helpers for the AR lens. Pure functions so the projection
/// math stays testable and free of view state.
enum GeoAR {
    /// Fallback field of view for the rear wide camera, degrees, measured across
    /// the sensor's long axis. Only used when the capture device won't report one.
    static let defaultFieldOfView: Double = 68

    /// Assume the phone's eye is about this far above the ground, metres.
    static let eyeHeight: Double = 1.6

    /// How high above the street evidence hovers, metres.
    static let clueHeight: Double = 1.3

    /// Radius of the glowing ring painted on the ground, metres.
    static let groundRingRadius: Double = 1.1

    /// Focal length in screen points for the live preview.
    ///
    /// `AVCaptureDevice.Format.videoFieldOfView` is the **horizontal** angle across
    /// the sensor's long axis. The preview is rotated 90° into portrait, so that
    /// axis runs down the screen — and because every iPhone screen is narrower
    /// relative to its height than any capture format, `.resizeAspectFill` matches
    /// the video to the screen HEIGHT and crops the sides.
    ///
    /// So screen height, not width, is what the quoted angle spans. Deriving the
    /// focal length from the width (as this once did) understates it by more than
    /// 2x, which makes pinned evidence drift across the frame as the phone turns
    /// instead of staying put.
    static func focalLength(viewport: CGSize, fieldOfViewDegrees: Double) -> CGFloat {
        let degrees = min(max(fieldOfViewDegrees, 30), 120)
        let radians = degrees * .pi / 180
        let height = max(viewport.height, 1)
        return (height / 2) / CGFloat(tan(radians / 2))
    }

    /// Half of the horizontal angle actually visible on screen, radians.
    static func horizontalHalfAngle(viewport: CGSize, focal: CGFloat) -> Double {
        atan(Double(max(viewport.width, 1) / 2 / max(focal, 1)))
    }

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
    /// - Returns: the projected point, or `nil` when the target sits behind the camera.
    static func project(
        from origin: GeoPoint,
        to target: GeoPoint,
        heightAboveGround: Double,
        matrix: CMRotationMatrix,
        viewport: CGSize,
        focal: CGFloat,
        declinationDegrees: Double?
    ) -> CGPoint? {
        let local = localOffset(from: origin, to: target, declinationDegrees: declinationDegrees)
        let up = heightAboveGround - eyeHeight

        // Reference frame (xMagneticNorthZVertical): x = magnetic north, y = west, z = up.
        let ref = SIMD3(local.north, -local.east, up)

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

        return CGPoint(
            x: viewport.width / 2 + focal * CGFloat(device.x / depth),
            y: viewport.height / 2 - focal * CGFloat(device.y / depth)
        )
    }

    /// Flat east/north offset in metres, rotated so the magnetometer's idea of
    /// north agrees with the true bearings used everywhere else in the app.
    static func localOffset(
        from origin: GeoPoint,
        to target: GeoPoint,
        declinationDegrees: Double?
    ) -> (east: Double, north: Double) {
        let lat1 = origin.latitude * .pi / 180
        let dLat = (target.latitude - origin.latitude) * .pi / 180
        let dLon = (target.longitude - origin.longitude) * .pi / 180

        var east = dLon * 6_371_000 * cos(lat1)
        var north = dLat * 6_371_000

        if let declinationDegrees {
            let radians = -declinationDegrees * .pi / 180
            let cosD = cos(radians)
            let sinD = sin(radians)
            let rotatedEast = east * cosD - north * sinD
            let rotatedNorth = east * sinD + north * cosD
            east = rotatedEast
            north = rotatedNorth
        }
        return (east, north)
    }

    /// Where the camera is pointing, as a magnetic bearing in degrees.
    static func cameraBearingDegrees(matrix: CMRotationMatrix) -> Double {
        // Camera forward is −z of the device, expressed in reference coordinates
        // (north, west, up) by the third column of the rotation matrix.
        let forwardNorth = -matrix.m13
        let forwardWest = -matrix.m23
        let bearing = atan2(-forwardWest, forwardNorth) * 180 / .pi
        return bearing < 0 ? bearing + 360 : bearing
    }

    /// Signed angle from the camera's centre line to a target, −180...180 degrees.
    ///
    /// The target bearing is true and the camera bearing is magnetic, so the
    /// declination has to come off one of them before they can be compared.
    static func relativeBearingDegrees(
        trueBearing: Double,
        matrix: CMRotationMatrix,
        declinationDegrees: Double?
    ) -> Double {
        let magneticTarget = trueBearing - (declinationDegrees ?? 0)
        var relative = magneticTarget - cameraBearingDegrees(matrix: matrix)
        while relative > 180 { relative -= 360 }
        while relative < -180 { relative += 360 }
        return relative
    }

    /// Parks an off-screen chevron on the horizontal edge nearest the target.
    static func edgePoint(
        relativeBearingDegrees relative: Double,
        viewport: CGSize,
        focal: CGFloat
    ) -> CGPoint {
        let half = horizontalHalfAngle(viewport: viewport, focal: focal)
        let clamped = max(-half + 0.02, min(half - 0.02, relative * .pi / 180))
        let fraction = tan(clamped) / tan(half)
        return CGPoint(
            x: viewport.width / 2 + CGFloat(fraction) * viewport.width / 2,
            y: viewport.height * 0.46
        )
    }

    /// On-screen size of something `metres` across sitting `distance` away.
    static func projectedSize(metres: Double, distance: Double, focal: CGFloat) -> CGFloat {
        CGFloat(metres) * focal / CGFloat(max(distance, 1.2))
    }
}
