//
//  ARLensView.swift
//  MysteryRun
//

import ARKit
import CoreLocation
import SceneKit
import SwiftUI

/// The camera half of the live investigation: the real street through the lens
/// with unfound evidence pinned to its real-world spot, glowing in the dark.
/// Toggled freely against the map view during a run.
struct ARLensView: View {
    @Environment(InvestigationEngine.self) private var engine
    @Environment(LocationService.self) private var location

    @State private var tracker = ARWorldTracker()
    @State private var camera = CameraService()
    @State private var attitude = AttitudeService()

    /// How close you must be for the artifact to become tappable. Evidence you
    /// can't plausibly reach shouldn't be collectable from across a district.
    private let collectRadius: Double = 30

    var body: some View {
        ZStack {
            backdrop

            ARLensScene(
                anchors: anchors,
                frame: worldFrame,
                collectRadius: collectRadius,
                onCollect: collect
            )

            if let notice {
                VStack {
                    Spacer()
                    TrackingNotice(text: notice)
                        .padding(.bottom, 10)
                }
            }
        }
        .ignoresSafeArea()
        .background(Theme.ink)
        .preferredColorScheme(.dark)
        .onAppear { startTracking() }
        .onDisappear { stopTracking() }
        .onChange(of: location.location?.timestamp) { _, _ in
            if let fix = location.location {
                tracker.ingest(fix: fix)
            }
        }
        .onChange(of: anchors.map(\.id)) { _, _ in
            tracker.setGeoTargets(geoTargets)
        }
    }

    // MARK: - Backdrop

    @ViewBuilder
    private var backdrop: some View {
        if tracker.isRunning {
            // ARKit owns the camera while it is running; a second capture session
            // would fight it for the device.
            ARWorldBackdrop(session: tracker.session)
                .noirGrade()
        } else {
            ARCameraBackdrop(camera: camera)
        }
    }

    // MARK: - Tracking

    private func startTracking() {
        location.beginPreciseUpdates()

        if ARWorldTracker.isSupported {
            tracker.start()
            tracker.reset()
            if let fix = location.location {
                tracker.ingest(fix: fix)
            }
            tracker.setGeoTargets(geoTargets)
        } else {
            // No ARKit here (simulator, or older hardware): fall back to the
            // camera feed with compass-only orientation.
            camera.start()
            attitude.start()
        }
    }

    private func stopTracking() {
        location.endPreciseUpdates()
        tracker.stop()
        camera.stop()
        attitude.stop()
    }

    /// Where the world is, however well we currently know it.
    private var worldFrame: ARWorldFrame {
        if tracker.isRunning, let origin = tracker.origin {
            return ARWorldFrame(
                pose: tracker.pose,
                origin: origin,
                // ARKit aligns its world to true north, so no magnetic
                // correction applies on this path.
                declination: nil,
                floorHeight: tracker.floorHeight,
                overrides: tracker.geoAnchorPositions
            )
        }

        return ARWorldFrame(
            pose: attitude.isAvailable
                ? GeoAR.pose(attitude: attitude.matrix, fieldOfViewDegrees: camera.fieldOfView)
                : nil,
            origin: fallbackOrigin,
            declination: location.declination,
            floorHeight: nil
        )
    }

    /// Honest one-liner about why placement isn't perfect yet, or nothing at all
    /// once tracking is solid.
    private var notice: String? {
        guard tracker.isRunning else {
            return attitude.isAvailable
                ? "No spatial tracking here — evidence is placed by compass only"
                : "Compass unavailable — evidence stays centred"
        }

        switch tracker.quality {
        case .starting:
            return "Finding your surroundings — move the phone slowly"
        case let .limited(reason):
            return reason
        case .good:
            return tracker.origin == nil ? "Waiting for a position fix" : nil
        }
    }

    // MARK: - Anchors

    private var anchors: [EvidenceAnchor] {
        guard let clues = engine.mysteryCase?.clues else { return [] }
        let nextID = engine.nextClue?.id
        return clues.filter { !$0.isFound }.map { clue in
            EvidenceAnchor(
                id: clue.id,
                index: clue.index,
                title: clue.title,
                symbolName: clue.symbolName,
                point: clue.point,
                isPrimary: clue.id == nextID
            )
        }
    }

    private var geoTargets: [UUID: GeoPoint] {
        Dictionary(uniqueKeysWithValues: anchors.map { ($0.id, $0.point) })
    }

    private var fallbackOrigin: GeoPoint? {
        if let fix = location.location {
            return GeoPoint(fix.coordinate)
        }
        return engine.currentPoint
    }

    /// Banks a clue tapped through the lens.
    ///
    /// Collecting from within the normal discovery radius is a genuine find — you
    /// walked to the evidence and tapped it, which is exactly what GPS proximity
    /// would have credited. Only reaching further counts as an override.
    private func collect(_ anchor: EvidenceAnchor, distance: Double) {
        let walked = tracker.pose?.tracksTranslation == true
        let earned = walked && distance <= engine.discoveryRadius
        engine.markNextClueFound(asOverride: !earned)
    }
}

// MARK: - ARKit backdrop

/// Passthrough camera rendered by ARKit itself.
///
/// The AR session and an `AVCaptureSession` cannot both hold the camera, so
/// whenever tracking runs this is the feed — SceneKit is used purely to draw the
/// video, with an empty scene and all overlay work left to SwiftUI.
struct ARWorldBackdrop: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session = session
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = false
        view.rendersCameraGrain = false
        view.antialiasingMode = .none
        // Taps belong to the evidence pins layered above.
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: ()) {
        uiView.session.pause()
    }
}

// MARK: - Camera backdrop

/// Graded camera feed used behind any AR overlay, with honest empty and denied
/// states. Used wherever ARKit tracking isn't running.
struct ARCameraBackdrop: View {
    let camera: CameraService

    var body: some View {
        switch camera.status {
        case .running, .requesting:
            CameraPreviewView(session: camera.session)
                .noirGrade()
        case .denied:
            CameraDeniedView()
        default:
            // No camera on this device — keep the evidence visible over ink so
            // the approach flow still works, with an honest explanation.
            ZStack {
                Theme.ink
                VStack(spacing: 10) {
                    Image(systemName: "video.slash")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                    Text("No camera available here")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

/// Noir grade: sinks the live feed into the app's ink so the HUD and the glowing
/// evidence stay readable even in daylight.
private struct NoirGrade: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            let size = geometry.size
            content
                .overlay {
                    LinearGradient(
                        colors: [Theme.ink.opacity(0.42), .clear, Theme.ink.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
                .overlay {
                    RadialGradient(
                        colors: [.clear, Theme.ink.opacity(0.4)],
                        center: .center,
                        startRadius: 0.6 * min(size.width, size.height),
                        endRadius: 0.85 * max(size.width, size.height)
                    )
                    .allowsHitTesting(false)
                }
        }
    }
}

extension View {
    func noirGrade() -> some View {
        modifier(NoirGrade())
    }
}

// MARK: - Status

private struct TrackingNotice: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "viewfinder")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        }
        .font(.caption)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: .capsule)
        .padding(.horizontal, 24)
    }
}

// MARK: - Denied state

struct CameraDeniedView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Theme.ink
            VStack(spacing: 14) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.brass)
                Text("Camera access is off")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("The lens is only used to show evidence on the street. Nothing is recorded. Enable it in Settings to use the AR view.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brass)
            }
        }
    }
}
