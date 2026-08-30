//
//  AttitudeService.swift
//  MysteryRun
//

import CoreMotion
import Foundation
import Observation

/// Streams the device's rotation matrix relative to magnetic north, so the AR
/// lens can pin clues to their real-world bearings. Falls back gracefully on
/// hardware without a magnetometer (simulators) — the UI then centers clues.
@Observable
final class AttitudeService {
    private let motion = CMMotionManager()

    /// False when the device can't supply north-referenced attitude.
    private(set) var isAvailable: Bool = false

    /// Device→reference-frame rotation. Identity is replaced by a portrait,
    /// north-facing pose so the first frame before motion data lands is sane.
    private(set) var matrix = CMRotationMatrix(
        m11: 0, m12: 0, m13: -1,
        m21: 1, m22: 0, m23: 0,
        m31: 0, m32: 1, m33: 0
    )

    func start() {
        guard !isAvailable else { return }
        guard motion.isDeviceMotionAvailable,
              CMMotionManager.availableAttitudeReferenceFrames()
                  .contains(.xMagneticNorthZVertical) else { return }

        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        isAvailable = true
        motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.matrix = data.attitude.rotationMatrix
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        isAvailable = false
    }
}
