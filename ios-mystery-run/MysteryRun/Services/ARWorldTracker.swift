//
//  ARWorldTracker.swift
//  MysteryRun
//

import ARKit
import CoreLocation
import Foundation
import Observation
import simd
import UIKit

/// Tracks where the detective is standing, precisely, using ARKit.
///
/// GPS alone cannot do this. A fix is accurate to roughly five metres outdoors
/// and thirty or more indoors, and it wanders continuously — so evidence pinned
/// to a fixed coordinate appears to drift away while you stand still. Worse,
/// nothing in a GPS-only pipeline can sense a three metre walk at all.
///
/// ARKit's visual-inertial odometry watches the room and tracks translation to a
/// few centimetres. This service runs that session and fuses it with GPS:
///
/// - **ARKit owns short-range motion.** Every step you take moves the camera in
///   the local frame immediately and exactly, so a clue three metres ahead stays
///   welded to its patch of floor and the distance readout counts down honestly.
/// - **GPS owns absolute placement.** Fixes only ever nudge the *origin* of the
///   local frame, never the anchors relative to you, and the nudge is weighted by
///   how good the fix is compared with what we already believe.
///
/// The result is that a bad fix can no longer throw a nearby anchor across the
/// room; it can only slowly correct where the whole world sits.
@Observable
final class ARWorldTracker: NSObject, ARSessionDelegate {
    /// Which tracking backend is actually running.
    enum Mode: Equatable {
        /// ARKit is unavailable (simulator, or an unsupported device).
        case unsupported
        /// Visual-inertial odometry aligned to gravity and compass heading.
        case world
        /// Apple's Visual Positioning System, accurate to about a metre, but only
        /// outdoors in supported cities.
        case geo
    }

    /// How much the placement can be trusted right now, in the user's terms.
    enum Quality: Equatable {
        case starting
        case limited(String)
        case good
    }

    let session = ARSession()

    private(set) var mode: Mode = .unsupported
    private(set) var quality: Quality = .starting
    private(set) var isRunning: Bool = false

    /// Live camera pose in the local east-north-up frame.
    private(set) var pose: GeoAR.CameraPose?

    /// Geo coordinate of the local frame's origin.
    private(set) var origin: GeoPoint?

    /// Standard deviation of the origin estimate, metres. Starts at the accuracy
    /// of the first usable fix and tightens as better ones arrive.
    private(set) var originAccuracy: Double = 0

    /// Height of the detected floor in the local frame, metres. `nil` until ARKit
    /// finds a horizontal plane, at which point the ground ring stops guessing.
    private(set) var floorHeight: Double?

    /// VPS-resolved positions, keyed by clue. Authoritative when present.
    private(set) var geoAnchorPositions: [UUID: SIMD3<Double>] = [:]

    /// Whether ARKit can run at all on this device.
    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    private var geoAnchorClueIDs: [UUID: UUID] = [:]
    private var requestedGeoPoints: [UUID: GeoPoint] = [:]
    private var didAttemptGeoUpgrade: Bool = false
    private var travelledSinceOriginUpdate: Double = 0
    private var lastPosition: SIMD3<Double>?

    /// Best estimate of where the detective is standing: the frame origin plus
    /// however far ARKit says the camera has moved from it.
    var trackedPoint: GeoPoint? {
        guard let origin, let pose else { return nil }
        return GeoAR.offset(origin, east: pose.position.x, north: pose.position.y)
    }

    /// True once anchors can be placed with real confidence.
    var isPlacing: Bool { pose != nil && origin != nil }

    // MARK: - Lifecycle

    func start() {
        guard Self.isSupported, !isRunning else { return }
        session.delegate = self
        session.delegateQueue = .main
        isRunning = true
        mode = .world
        runWorldConfiguration()
    }

    func stop() {
        guard isRunning else { return }
        session.pause()
        isRunning = false
        pose = nil
        quality = .starting
    }

    /// Wipes the tracked frame so a fresh one is built from the next fixes.
    /// Used when the lens is reopened somewhere completely different.
    func reset() {
        origin = nil
        originAccuracy = 0
        floorHeight = nil
        geoAnchorPositions.removeAll()
        geoAnchorClueIDs.removeAll()
        lastPosition = nil
        travelledSinceOriginUpdate = 0
        guard isRunning else { return }
        runWorldConfiguration(resetTracking: true)
    }

    private func runWorldConfiguration(resetTracking: Bool = true) {
        let configuration = ARWorldTrackingConfiguration()
        // True north alignment. This is why the ARKit path needs no magnetic
        // declination correction at all — the frame is already true-north.
        configuration.worldAlignment = .gravityAndHeading
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .none
        configuration.isLightEstimationEnabled = false

        var options: ARSession.RunOptions = []
        if resetTracking {
            options = [.resetTracking, .removeExistingAnchors]
        }
        session.run(configuration, options: options)
    }

    // MARK: - Absolute placement

    /// Folds a GPS fix into the origin estimate.
    ///
    /// The fix is not treated as "where you are" — ARKit already knows that far
    /// better. It is treated as evidence about where the *origin* sits, obtained
    /// by subtracting the tracked camera offset from the fix. Those estimates are
    /// then combined by inverse-variance weighting, so a sloppy indoor fix barely
    /// moves a well-established origin.
    func ingest(fix: CLLocation) {
        guard isRunning else { return }
        let accuracy = fix.horizontalAccuracy
        guard accuracy > 0, accuracy < 100 else { return }
        guard abs(fix.timestamp.timeIntervalSinceNow) < 10 else { return }

        let cameraOffset = pose?.position ?? .zero
        let implied = GeoAR.offset(
            GeoPoint(fix.coordinate),
            east: -cameraOffset.x,
            north: -cameraOffset.y
        )

        guard let current = origin else {
            origin = implied
            originAccuracy = accuracy
            return
        }

        // Inverse-variance (Kalman) blend of two independent position estimates.
        let variance = originAccuracy * originAccuracy
        let fixVariance = accuracy * accuracy
        let gain = variance / (variance + fixVariance)

        let delta = GeoAR.localOffset(from: current, to: implied, declinationDegrees: nil)
        var east = delta.east * gain
        var north = delta.north * gain

        // Even a well-weighted correction must never teleport the world. Cap each
        // step so the scene slides gently into place instead of jumping.
        let magnitude = (east * east + north * north).squareRoot()
        let maxStep: Double = 1.5
        if magnitude > maxStep {
            east *= maxStep / magnitude
            north *= maxStep / magnitude
        }

        origin = GeoAR.offset(current, east: east, north: north)
        originAccuracy = max((1 - gain).squareRoot() * originAccuracy, 1.5)

        upgradeToGeoTrackingIfAvailable(near: fix)
    }

    // MARK: - Geo anchors

    /// Registers the clues to resolve through the Visual Positioning System.
    /// Ignored entirely outside geo mode, where the local frame is used instead.
    func setGeoTargets(_ targets: [UUID: GeoPoint]) {
        requestedGeoPoints = targets
        guard mode == .geo else { return }

        let existing = Set(geoAnchorClueIDs.values)
        for (id, point) in targets where !existing.contains(id) {
            let anchor = ARGeoAnchor(coordinate: point.coordinate)
            geoAnchorClueIDs[anchor.identifier] = id
            session.add(anchor: anchor)
        }
    }

    /// Switches to VPS tracking when Apple supports it at this location.
    ///
    /// Kept as a runtime upgrade rather than a requirement: geo tracking only
    /// works outdoors, in supported cities, with a network connection.
    private func upgradeToGeoTrackingIfAvailable(near fix: CLLocation) {
        guard !didAttemptGeoUpgrade, ARGeoTrackingConfiguration.isSupported else { return }
        didAttemptGeoUpgrade = true

        ARGeoTrackingConfiguration.checkAvailability(at: fix.coordinate) { [weak self] available, _ in
            guard available else { return }
            Task { @MainActor [weak self] in
                self?.startGeoTracking()
            }
        }
    }

    private func startGeoTracking() {
        guard isRunning, mode != .geo else { return }
        mode = .geo

        let configuration = ARGeoTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .none
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        geoAnchorClueIDs.removeAll()
        geoAnchorPositions.removeAll()
        setGeoTargets(requestedGeoPoints)
    }

    // MARK: - ARSessionDelegate

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Only Sendable values cross into the actor: the ARFrame itself is never
        // captured, so its image buffers are released immediately.
        let camera = frame.camera
        let sample = Self.sample(from: camera)
        let state = Self.quality(for: camera.trackingState)

        MainActor.assumeIsolated {
            apply(sample: sample, quality: state)
        }
    }

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        ingest(anchors: anchors)
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        ingest(anchors: anchors)
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            quality = .limited("Tracking stopped — reopen the lens")
            isRunning = false
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        MainActor.assumeIsolated {
            quality = .limited("Interrupted")
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        MainActor.assumeIsolated {
            guard isRunning else { return }
            // Relocalisation after an interruption is unreliable indoors; a clean
            // frame beats a wrongly restored one.
            runWorldConfiguration(resetTracking: true)
        }
    }

    private nonisolated func ingest(anchors: [ARAnchor]) {
        var floors: [Double] = []
        var geo: [(UUID, SIMD3<Double>)] = []

        for anchor in anchors {
            let translation = anchor.transform.columns.3
            if let plane = anchor as? ARPlaneAnchor, plane.alignment == .horizontal {
                floors.append(Double(translation.y))
            }
            if anchor is ARGeoAnchor {
                geo.append((
                    anchor.identifier,
                    SIMD3(Double(translation.x), Double(-translation.z), Double(translation.y))
                ))
            }
        }

        guard !floors.isEmpty || !geo.isEmpty else { return }
        let lowestFloor = floors.min()

        MainActor.assumeIsolated {
            if let lowestFloor {
                // The lowest horizontal plane is the floor; higher ones are desks
                // and worktops, which must not host the evidence ring.
                floorHeight = min(floorHeight ?? .greatestFiniteMagnitude, lowestFloor)
            }
            for (anchorID, position) in geo {
                guard let clueID = geoAnchorClueIDs[anchorID] else { continue }
                geoAnchorPositions[clueID] = position
            }
        }
    }

    // MARK: - Sampling

    private func apply(sample: PoseSample, quality state: Quality) {
        pose = sample.pose
        quality = state

        if let last = lastPosition {
            travelledSinceOriginUpdate += simd_distance(last, sample.pose.position)
        }
        lastPosition = sample.pose.position

        // Odometry drifts by roughly a percent of distance covered, so confidence
        // in the origin has to decay as you walk or later fixes are ignored.
        if travelledSinceOriginUpdate > 10, origin != nil {
            let drift = 0.01 * travelledSinceOriginUpdate
            originAccuracy = (originAccuracy * originAccuracy + drift * drift).squareRoot()
            travelledSinceOriginUpdate = 0
        }
    }

    private nonisolated struct PoseSample: Sendable {
        var pose: GeoAR.CameraPose
    }

    private nonisolated static func sample(from camera: ARCamera) -> PoseSample {
        // `viewMatrix` already accounts for the interface orientation, so this is
        // the portrait-correct world-to-camera rotation.
        let view = camera.viewMatrix(for: .portrait)
        let rotation = simd_double3x3(
            SIMD3(Double(view.columns.0.x), Double(view.columns.0.y), Double(view.columns.0.z)),
            SIMD3(Double(view.columns.1.x), Double(view.columns.1.y), Double(view.columns.1.z)),
            SIMD3(Double(view.columns.2.x), Double(view.columns.2.y), Double(view.columns.2.z))
        )

        // ARKit's gravity-and-heading world is x = east, y = up, z = south, so
        // this sends an east-north-up vector into ARKit's axes before rotating.
        let eastNorthUpToARKit = simd_double3x3(
            SIMD3(1, 0, 0),
            SIMD3(0, 0, -1),
            SIMD3(0, 1, 0)
        )

        let translation = camera.transform.columns.3
        let intrinsics = camera.intrinsics
        let resolution = camera.imageResolution

        return PoseSample(
            pose: GeoAR.CameraPose(
                position: SIMD3(
                    Double(translation.x),
                    Double(-translation.z),
                    Double(translation.y)
                ),
                worldToCamera: rotation * eastNorthUpToARKit,
                lens: .intrinsics(
                    focalPixels: Double(intrinsics[0][0]),
                    imageSize: resolution
                ),
                tracksTranslation: true
            )
        )
    }

    private nonisolated static func quality(for state: ARCamera.TrackingState) -> Quality {
        switch state {
        case .normal:
            return .good
        case .notAvailable:
            return .starting
        case let .limited(reason):
            switch reason {
            case .initializing:
                return .starting
            case .relocalizing:
                return .limited("Finding your place again")
            case .excessiveMotion:
                return .limited("Moving too fast — slow down")
            case .insufficientFeatures:
                return .limited("Too dark or too bare — point at detail")
            @unknown default:
                return .limited("Tracking is unsteady")
            }
        }
    }
}
