//
//  LocationService.swift
//  MysteryRun
//

import CoreLocation
import Foundation
import Observation

/// Wraps CLLocationManager for briefing (one-shot fix) and live investigation
/// (continuous updates). Movement speed is never used for gameplay — only position.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private(set) var location: CLLocation?
    private(set) var heading: CLLocationDirection?
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var isTracking: Bool = false
    /// True once we've waited for a fix and given up, so the UI can explain itself.
    private(set) var didTimeOutWaitingForFix: Bool = false

    /// Called for every fresh fix while tracking. Push-based so the engine keeps
    /// scoring progress even when the app is suspended in the user's pocket.
    var onFix: ((CLLocation) -> Void)?

    /// Rolling GPS quality so the UI can warn about urban-canyon drift.
    private(set) var accuracy: CLLocationAccuracy?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        // iOS will otherwise pause updates when it thinks you've stopped, which
        // silently kills a session during a long traffic-light wait.
        manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// Best known origin, falling back to a demo district so the app is never dead-ended.
    var origin: GeoPoint {
        if let location { return GeoPoint(location.coordinate) }
        return RouteBuilder.fallbackOrigin
    }

    /// Magnetic declination (true − magnetic) in degrees, once the compass has
    /// reported. Lets the AR lens reconcile true bearings with the magnetometer's
    /// magnetic-north reference frame.
    private(set) var declination: Double?

    var hasRealFix: Bool { location != nil }

    func requestPermission() {
        guard authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func requestOneShotFix() {
        guard isAuthorized else { return }
        manager.requestLocation()
    }

    /// Quality bands used by the live HUD.
    enum SignalQuality {
        case good
        case fair
        case poor
        case none
    }

    var signalQuality: SignalQuality {
        guard let accuracy, accuracy >= 0 else { return .none }
        if accuracy <= 15 { return .good }
        if accuracy <= 35 { return .fair }
        return .poor
    }

    func startTracking() {
        guard isAuthorized else { return }
        isTracking = true
        // Keeps the fixes coming with the screen locked and the phone pocketed.
        // Safe to set only once we hold an authorization the system accepts.
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stopTracking() {
        isTracking = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        manager.allowsBackgroundLocationUpdates = false
    }

    /// Marks that we've stopped expecting a fix (used to fall back to the demo district).
    func markFixTimeout() {
        guard location == nil else { return }
        didTimeOutWaitingForFix = true
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.location = latest
            self.accuracy = latest.horizontalAccuracy
            self.didTimeOutWaitingForFix = false
            if self.isTracking {
                self.onFix?(latest)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            self.heading = value
            if newHeading.trueHeading >= 0 {
                var declination = newHeading.trueHeading - newHeading.magneticHeading
                if declination > 180 { declination -= 360 }
                if declination < -180 { declination += 360 }
                self.declination = declination
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.markFixTimeout()
        }
    }
}
