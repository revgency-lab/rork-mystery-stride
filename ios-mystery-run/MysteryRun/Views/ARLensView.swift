//
//  ARLensView.swift
//  MysteryRun
//

import ARKit
import CoreLocation
import SceneKit
import SwiftUI
import simd

/// The camera half of the live investigation.
///
/// The lens works in two clearly separate states, and keeping them separate is
/// what stopped it looking broken:
///
/// - **Approach.** Further out than `encounterRadius`, nothing is pinned to the
///   world at all. GPS is accurate to a handful of metres and the compass to
///   twenty-odd degrees, and at two hundred metres those errors put a "precisely
///   placed" clue against the wrong building entirely. A screen-space bearing
///   marker is honest about being a direction rather than a location, and can't
///   be wrong in a way the eye can catch.
/// - **Encounter.** Once the evidence is close enough for the same errors to be
///   small next to the distance itself, it materialises as a real object welded
///   to the pavement by ARKit, and stays there while you walk around it.
struct ARLensView: View {
    @Environment(InvestigationEngine.self) private var engine
    @Environment(LocationService.self) private var location

    @State private var tracker = ARWorldTracker()
    @State private var camera = CameraService()
    @State private var attitude = AttitudeService()
    /// Live distance to the placed object, straight from the AR scene.
    @State private var placedDistance: Double?

    /// Inside this range the evidence is placed in the world. Chosen to sit just
    /// outside the default unlock radius, so the artifact appears on the ground
    /// ahead of you and you walk the last stretch to it in view.
    private static let encounterRadius: Double = 30

    var body: some View {
        ZStack {
            backdrop

            if let notice {
                VStack {
                    Spacer()
                    TrackingNotice(text: notice)
                        .padding(.bottom, 10)
                }
            }

            hud
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
        .onChange(of: engine.nextClue?.id) { _, _ in
            placedDistance = nil
            tracker.setGeoTargets(geoTargets)
        }
    }

    // MARK: - Backdrop

    @ViewBuilder
    private var backdrop: some View {
        if tracker.isRunning {
            // ARKit owns the camera while it runs; a second capture session would
            // fight it for the device.
            ARLensSurface(
                session: tracker.session,
                encounter: encounter,
                canPlace: tracker.quality == .good,
                onDistanceChange: { placedDistance = $0 },
                onTap: collect
            )
            .noirGrade()
        } else {
            ARCameraBackdrop(camera: camera)
        }
    }

    // MARK: - HUD

    @ViewBuilder
    private var hud: some View {
        if let clue = engine.nextClue {
            if let placedDistance {
                EvidenceCaption(
                    title: clue.title,
                    index: clue.index,
                    distance: placedDistance,
                    isCollectible: isWithinReach
                )
            } else if let relativeBearing {
                BearingMarker(
                    title: clue.title,
                    index: clue.index,
                    distance: engine.distanceToNextClue,
                    relativeBearing: relativeBearing,
                    isCollectible: isWithinReach,
                    onCollect: collect
                )
            }
        }
    }

    // MARK: - Tracking

    private func startTracking() {
        location.beginPreciseUpdates()
        placedDistance = nil

        if ARWorldTracker.isSupported {
            tracker.start()
            tracker.reset()
            if let fix = location.location {
                tracker.ingest(fix: fix)
            }
            tracker.setGeoTargets(geoTargets)
        } else {
            // No ARKit here (simulator, or older hardware): the camera feed with
            // compass-only bearing is all that can honestly be offered.
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

    // MARK: - Placement

    /// Best available idea of where the detective is standing: ARKit's fused
    /// position when tracking, otherwise the raw fix.
    private var detectivePoint: GeoPoint? {
        tracker.trackedPoint
            ?? location.location.map { GeoPoint($0.coordinate) }
            ?? engine.currentPoint
    }

    private var encounter: EvidenceEncounter? {
        guard let clue = engine.nextClue, let here = detectivePoint else { return nil }
        let distance = here.distance(to: clue.point)
        guard distance <= Self.encounterRadius else { return nil }

        let offset = GeoAR.localOffset(from: here, to: clue.point, declinationDegrees: nil)
        return EvidenceEncounter(
            id: clue.id,
            index: clue.index,
            title: clue.title,
            symbolName: clue.symbolName,
            east: offset.east,
            north: offset.north,
            distance: distance,
            resolvedPosition: resolvedPosition(for: clue.id)
        )
    }

    /// VPS positions are stored east/north/up; ARKit's world is east/up/south.
    private func resolvedPosition(for id: UUID) -> SIMD3<Float>? {
        guard let local = tracker.geoAnchorPositions[id] else { return nil }
        return SIMD3(Float(local.x), Float(local.z), Float(-local.y))
    }

    /// Where the evidence sits relative to the middle of the frame, in degrees,
    /// or `nil` when nothing can say which way the phone is pointing.
    private var relativeBearing: Double? {
        guard let clue = engine.nextClue, let here = detectivePoint else { return nil }
        let target = GeoAR.bearingDegrees(from: here, to: clue.point)

        let facing: Double
        if tracker.isRunning, let pose = tracker.pose {
            facing = GeoAR.cameraBearingDegrees(pose: pose)
        } else if let heading = location.heading {
            facing = heading
        } else {
            return nil
        }

        var relative = target - facing
        while relative > 180 { relative -= 360 }
        while relative < -180 { relative += 360 }
        return relative
    }

    private var geoTargets: [UUID: GeoPoint] {
        guard let clues = engine.mysteryCase?.clues else { return [:] }
        return Dictionary(uniqueKeysWithValues: clues.filter { !$0.isFound }.map { ($0.id, $0.point) })
    }

    // MARK: - Status

    /// Honest one-liner about why placement isn't perfect yet, or nothing at all
    /// once tracking is solid.
    private var notice: String? {
        guard tracker.isRunning else {
            return attitude.isAvailable || location.heading != nil
                ? "No spatial tracking here — this is a bearing, not a fixed position"
                : "Compass unavailable — follow the map instead"
        }

        switch tracker.quality {
        case .starting:
            return "Finding your surroundings — move the phone slowly"
        case let .limited(reason):
            return reason
        case .good:
            if placedDistance != nil { return nil }
            guard let distance = engine.distanceToNextClue else { return "Waiting for a position fix" }
            return distance > Self.encounterRadius
                ? "Too far to place — head that way and it'll appear"
                : nil
        }
    }

    // MARK: - Collecting

    /// True when the engine's own GPS proximity says the detective genuinely
    /// reached the evidence, which is the same test the map view unlocks on.
    private var isWithinReach: Bool {
        guard let distance = engine.distanceToNextClue else { return false }
        return distance <= engine.discoveryRadius
    }

    /// Banks a clue tapped through the lens.
    ///
    /// Tapping from within the normal discovery radius is a genuine find — you
    /// walked to the evidence, which is exactly what GPS proximity would have
    /// credited. Reaching further counts as an override.
    private func collect() {
        engine.markNextClueFound(asOverride: !isWithinReach)
    }
}

// MARK: - Encounter caption

/// Text for evidence that is actually placed in the world.
///
/// Deliberately flat screen chrome rather than something anchored in 3D: legible
/// type at any distance is worth more than a label that scales into a smudge,
/// and the object itself is already carrying the sense of place.
private struct EvidenceCaption: View {
    let title: String
    let index: Int
    let distance: Double
    let isCollectible: Bool

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 6) {
                Text("CLUE \(index) · \(title.uppercased())")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Theme.brass)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(isCollectible ? "TAP THE EVIDENCE" : "\(distanceText) AWAY")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(isCollectible ? Theme.ink : Theme.brass)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                    .background(isCollectible ? Theme.brass : Theme.ink.opacity(0.72), in: .capsule)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.brass.opacity(0.45), lineWidth: 1)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            .padding(.bottom, 78)
        }
        .allowsHitTesting(false)
    }

    private var distanceText: String {
        distance < 10
            ? String(format: "%.1f M", distance)
            : "\(Int(distance.rounded())) M"
    }
}

// MARK: - Approach marker

/// Which way to walk, when the evidence is too far away to place honestly.
private struct BearingMarker: View {
    let title: String
    let index: Int
    let distance: Double?
    let relativeBearing: Double
    let isCollectible: Bool
    let onCollect: () -> Void

    @State private var pulse: Bool = false

    /// Beyond this the evidence is behind you and the chevron parks on the edge
    /// of the frame rather than pretending to point off into the distance.
    private var isAhead: Bool { abs(relativeBearing) < 32 }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                Circle()
                    .strokeBorder(Theme.brass.opacity(0.25), lineWidth: 1)
                    .frame(width: 128, height: 128)
                    .scaleEffect(pulse ? 1.18 : 0.94)
                    .opacity(pulse ? 0 : 0.9)

                Circle()
                    .fill(Theme.ink.opacity(0.55))
                    .frame(width: 96, height: 96)

                Circle()
                    .strokeBorder(Theme.brass.opacity(0.8), lineWidth: 1.5)
                    .frame(width: 96, height: 96)

                Image(systemName: "location.north.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.brass)
                    .rotationEffect(.degrees(relativeBearing))
                    .shadow(color: Theme.brass.opacity(0.7), radius: 10)
            }
            .animation(.easeOut(duration: 0.25), value: relativeBearing)

            VStack(spacing: 6) {
                Text("CLUE \(index) · \(title.uppercased())")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(1.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Theme.brass)

                Text(headline)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Theme.textPrimary)

                Text(isAhead ? "Straight ahead" : turnHint)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.brass.opacity(0.35), lineWidth: 1)
            }

            if isCollectible {
                Button("Collect It Here", action: onCollect)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(Theme.brass, in: .capsule)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 60)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var headline: String {
        guard let distance else { return "Searching…" }
        return distance >= 1_000
            ? String(format: "%.1f km away", distance / 1_000)
            : "\(Int(distance.rounded())) m away"
    }

    private var turnHint: String {
        abs(relativeBearing) > 140
            ? "Turn around"
            : (relativeBearing > 0 ? "Turn right" : "Turn left")
    }
}

// MARK: - ARKit backdrop

/// Passthrough camera rendered by ARKit, with nothing drawn over it.
///
/// The gameplay lens uses `ARLensSurface` instead, which owns its own scene. This
/// remains for the developer lab, where the evidence is projected in SwiftUI on
/// purpose so the two placement paths can be compared side by side.
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
        .allowsHitTesting(false)
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
