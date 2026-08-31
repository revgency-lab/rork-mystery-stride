//
//  GeoAR.swift
//  MysteryRun
//

import CoreGraphics
import CoreMotion
import Foundation
import simd

/// Camera geometry for the AR lens. Pure functions so the projection math stays
/// testable and free of view state.
///
/// Everything works in a local **east-north-up** frame measured in metres from a
/// session origin. Both tracking backends reduce to that frame, so the lens draws
/// identically whether position comes from ARKit's visual-inertial odometry or
/// from a bare GPS fix.
nonisolated enum GeoAR {
    /// Fallback field of view for the rear wide camera, degrees, measured across
    /// the sensor's long axis. Only used when no real intrinsics are available.
    static let defaultFieldOfView: Double = 68

    /// Assume the phone's eye is about this far above the ground, metres. Used
    /// only until ARKit finds a real floor plane.
    static let eyeHeight: Double = 1.6

    /// How high above the ground evidence hovers, metres.
    static let clueHeight: Double = 1.3

    /// Radius of the glowing ring painted on the ground, metres.
    static let groundRingRadius: Double = 1.1

    private static let earthRadius: Double = 6_371_000

    // MARK: - Camera pose

    /// Where the camera is and which way it looks, in the local east-north-up frame.
    ///
    /// This is the single input the lens needs. ARKit fills it from tracked
    /// odometry; the compass fallback fills it with a fixed origin and rotation
    /// only. Nothing downstream needs to know which produced it.
    struct CameraPose: Sendable, Equatable {
        /// Camera position in metres from the session origin: east, north, up.
        /// Always zero on the fallback path, which cannot sense translation.
        var position: SIMD3<Double>

        /// Maps a direction in the local frame into camera space, where +x is
        /// screen-right, +y is screen-up and −z is the way the lens points.
        var worldToCamera: simd_double3x3

        /// How to turn the viewport into a focal length.
        var lens: LensModel

        /// True when position is genuinely tracked, so distances react to walking.
        var tracksTranslation: Bool

        enum LensModel: Sendable, Equatable {
            /// Real camera intrinsics: focal in image pixels, plus the image size
            /// those intrinsics were measured against.
            case intrinsics(focalPixels: Double, imageSize: CGSize)
            /// Only a field of view is known, so focal is derived from the viewport.
            case fieldOfView(degrees: Double)
        }

        /// Focal length in screen points for a given viewport.
        func focal(viewport: CGSize) -> CGFloat {
            switch lens {
            case let .intrinsics(focalPixels, imageSize):
                // Intrinsics describe the landscape sensor image. Rotated into
                // portrait its long axis runs down the screen, and the preview
                // aspect-fills, so the larger of the two scale factors wins.
                let portraitWidth = max(imageSize.height, 1)
                let portraitHeight = max(imageSize.width, 1)
                let scale = max(viewport.width / portraitWidth, viewport.height / portraitHeight)
                return CGFloat(focalPixels) * scale
            case let .fieldOfView(degrees):
                return GeoAR.focalLength(viewport: viewport, fieldOfViewDegrees: degrees)
            }
        }
    }

    /// Builds a rotation-only pose from a north-referenced device attitude.
    ///
    /// The reference frame is `xMagneticNorthZVertical`: x = magnetic north,
    /// y = west, z = up. `matrix` maps device axes into that frame, so its
    /// transpose pulls world directions into camera space. Rewriting that
    /// transpose in east-north-up order gives the rows below.
    static func pose(attitude matrix: CMRotationMatrix, fieldOfViewDegrees: Double) -> CameraPose {
        let rows: [SIMD3<Double>] = [
            SIMD3(-matrix.m21, matrix.m11, matrix.m31),
            SIMD3(-matrix.m22, matrix.m12, matrix.m32),
            SIMD3(-matrix.m23, matrix.m13, matrix.m33)
        ]
        return CameraPose(
            position: .zero,
            worldToCamera: simd_double3x3(rows: rows),
            lens: .fieldOfView(degrees: fieldOfViewDegrees),
            tracksTranslation: false
        )
    }

    // MARK: - Projection

    /// Projects a point in the local frame into screen space.
    ///
    /// - Returns: the projected point, or `nil` when the target is behind the lens.
    static func project(
        _ target: SIMD3<Double>,
        pose: CameraPose,
        viewport: CGSize,
        focal: CGFloat
    ) -> CGPoint? {
        let device = pose.worldToCamera * (target - pose.position)
        let depth = -device.z
        guard depth > 0.05 else { return nil }

        return CGPoint(
            x: viewport.width / 2 + focal * CGFloat(device.x / depth),
            y: viewport.height / 2 - focal * CGFloat(device.y / depth)
        )
    }

    /// Ground distance from the camera to a point in the local frame, metres.
    static func groundDistance(from pose: CameraPose, to target: SIMD3<Double>) -> Double {
        let delta = target - pose.position
        return (delta.x * delta.x + delta.y * delta.y).squareRoot()
    }

    /// Focal length in screen points derived from a field of view.
    ///
    /// `AVCaptureDevice.Format.videoFieldOfView` is the **horizontal** angle across
    /// the sensor's long axis. The preview is rotated 90° into portrait, so that
    /// axis runs down the screen — and because every iPhone screen is narrower
    /// relative to its height than any capture format, `.resizeAspectFill` matches
    /// the video to the screen HEIGHT and crops the sides. So screen height, not
    /// width, is what the quoted angle spans.
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

    // MARK: - Geodesy

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

    /// Flat east/north offset in metres between two coordinates.
    ///
    /// Pass a declination to express the result against **magnetic** north, which
    /// the compass fallback needs. ARKit aligns to true north and must pass `nil`.
    ///
    /// A direction whose true bearing is `B` has magnetic bearing `B − declination`,
    /// so the vector rotates by `−declination` — clockwise-positive bearings turn
    /// into the counter-clockwise-positive rotation below.
    static func localOffset(
        from origin: GeoPoint,
        to target: GeoPoint,
        declinationDegrees: Double?
    ) -> (east: Double, north: Double) {
        let lat1 = origin.latitude * .pi / 180
        let dLat = (target.latitude - origin.latitude) * .pi / 180
        let dLon = (target.longitude - origin.longitude) * .pi / 180

        var east = dLon * earthRadius * cos(lat1)
        var north = dLat * earthRadius

        if let declinationDegrees {
            let radians = declinationDegrees * .pi / 180
            let cosD = cos(radians)
            let sinD = sin(radians)
            let rotatedEast = east * cosD - north * sinD
            let rotatedNorth = east * sinD + north * cosD
            east = rotatedEast
            north = rotatedNorth
        }
        return (east, north)
    }

    /// Moves a coordinate by a flat east/north offset in metres.
    static func offset(_ point: GeoPoint, east: Double, north: Double) -> GeoPoint {
        let latitude = point.latitude + (north / earthRadius) * 180 / .pi
        let cosLat = max(cos(point.latitude * .pi / 180), 0.000_001)
        let longitude = point.longitude + (east / (earthRadius * cosLat)) * 180 / .pi
        return GeoPoint(latitude: latitude, longitude: longitude)
    }

    // MARK: - Off-screen guidance

    /// Where the camera points, as a bearing in the local frame's north.
    static func cameraBearingDegrees(pose: CameraPose) -> Double {
        // Camera forward is −z in camera space; the transpose of the rotation
        // sends it back into the local frame, which is the negated third row.
        let m = pose.worldToCamera
        let forwardEast = -m[0][2]
        let forwardNorth = -m[1][2]
        let bearing = atan2(forwardEast, forwardNorth) * 180 / .pi
        return bearing < 0 ? bearing + 360 : bearing
    }

    /// Signed angle from the camera's centre line to a target, −180...180 degrees.
    static func relativeBearingDegrees(to target: SIMD3<Double>, pose: CameraPose) -> Double {
        let delta = target - pose.position
        var relative = atan2(delta.x, delta.y) * 180 / .pi - cameraBearingDegrees(pose: pose)
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
