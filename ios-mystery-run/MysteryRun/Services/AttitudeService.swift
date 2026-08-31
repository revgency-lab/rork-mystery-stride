//
//  AttitudeService.swift
//  MysteryRun
//

import CoreMotion
import Foundation
import Observation
import simd

/// Streams the device's rotation matrix relative to magnetic north, so the AR
/// lens can pin clues to their real-world bearings. Falls back gracefully on
/// hardware without a magnetometer (simulators) — the UI then centers clues.
@Observable
final class AttitudeService {
    private let motion = CMMotionManager()

    /// False when the device can't supply north-referenced attitude.
    private(set) var isAvailable: Bool = false

    /// How badly the magnetometer is being disturbed. Indoors, steel framing,
    /// wiring and speaker magnets routinely drag this down, which is what makes a
    /// bearing-based placement point at the wrong wall.
    private(set) var fieldAccuracy: CMMagneticFieldCalibrationAccuracy = .uncalibrated

    /// True when the compass is steady enough to be worth believing.
    var isFieldTrustworthy: Bool {
        fieldAccuracy == .high || fieldAccuracy == .medium
    }

    /// Device→reference-frame rotation, where the frame is x = magnetic north,
    /// y = west, z = up.
    ///
    /// Seeded with a real portrait, north-facing pose — screen-right east, screen
    /// up vertical, lens on north — so the first frame before motion data lands is
    /// sane rather than mirrored.
    private(set) var matrix = CMRotationMatrix(
        m11: 0, m12: 0, m13: -1,
        m21: -1, m22: 0, m23: 0,
        m31: 0, m32: 1, m33: 0
    )

    /// Smoothed pose. Raw magnetometer-fused attitude is noisy by a degree or two,
    /// which reads as pinned evidence shivering in place, so poses are slerped
    /// toward each new sample rather than snapped to it.
    private var smoothed: simd_quatd?

    /// Fraction of the way to each new sample. Low enough to kill jitter, high
    /// enough that fast turns don't visibly lag the camera.
    private let responsiveness: Double = 0.3

    func start() {
        guard !isAvailable else { return }
        guard motion.isDeviceMotionAvailable,
              CMMotionManager.availableAttitudeReferenceFrames()
                  .contains(.xMagneticNorthZVertical) else { return }

        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        isAvailable = true
        motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.fieldAccuracy = data.magneticField.accuracy
            self.ingest(data.attitude.quaternion)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        isAvailable = false
        smoothed = nil
    }

    private func ingest(_ quaternion: CMQuaternion) {
        let sample = simd_quatd(ix: quaternion.x, iy: quaternion.y, iz: quaternion.z, r: quaternion.w)
        let next: simd_quatd
        if let smoothed {
            // simd_slerp already takes the shortest arc, so the double-cover sign
            // flip can't send the pose spinning the long way round.
            next = simd_slerp(smoothed, sample, responsiveness)
        } else {
            next = sample
        }
        smoothed = next
        matrix = Self.rotationMatrix(from: next)
    }

    nonisolated private static func rotationMatrix(from quaternion: simd_quatd) -> CMRotationMatrix {
        let m = simd_matrix3x3(simd_normalize(quaternion))
        return CMRotationMatrix(
            m11: m.columns.0.x, m12: m.columns.1.x, m13: m.columns.2.x,
            m21: m.columns.0.y, m22: m.columns.1.y, m23: m.columns.2.y,
            m31: m.columns.0.z, m32: m.columns.1.z, m33: m.columns.2.z
        )
    }
}
