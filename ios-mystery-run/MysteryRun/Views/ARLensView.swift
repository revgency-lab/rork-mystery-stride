//
//  ARLensView.swift
//  MysteryRun
//

import CoreLocation
import SwiftUI

/// The camera half of the live investigation: the real street through the lens
/// with unfound evidence pinned to its real-world spot, glowing in the dark.
/// Toggled freely against the map view during a run.
struct ARLensView: View {
    @Environment(InvestigationEngine.self) private var engine
    @Environment(LocationService.self) private var location

    @State private var camera = CameraService()
    @State private var attitude = AttitudeService()

    var body: some View {
        ZStack {
            ARCameraBackdrop(camera: camera)

            ARLensScene(
                anchors: anchors,
                userPoint: userPoint,
                matrix: attitude.matrix,
                declination: location.declination,
                fieldOfView: camera.fieldOfView,
                compassAvailable: attitude.isAvailable,
                collectRadius: 150,
                onCollect: { _ in engine.markNextClueFound() }
            )

            if !attitude.isAvailable {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "location.circle")
                        Text("Compass unavailable — evidence stays centred")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: .capsule)
                    .padding(.bottom, 10)
                }
            }
        }
        .ignoresSafeArea()
        .background(Theme.ink)
        .preferredColorScheme(.dark)
        .onAppear {
            camera.start()
            attitude.start()
        }
        .onDisappear {
            camera.stop()
            attitude.stop()
        }
    }

    private var anchors: [ARAnchor] {
        guard let clues = engine.mysteryCase?.clues else { return [] }
        let nextID = engine.nextClue?.id
        return clues.filter { !$0.isFound }.map { clue in
            ARAnchor(
                id: clue.id,
                index: clue.index,
                title: clue.title,
                symbolName: clue.symbolName,
                point: clue.point,
                isPrimary: clue.id == nextID
            )
        }
    }

    private var userPoint: GeoPoint? {
        if let fix = location.location {
            return GeoPoint(fix.coordinate)
        }
        return engine.currentPoint
    }
}

// MARK: - Camera backdrop

/// Graded camera feed used behind any AR overlay, with honest empty and denied
/// states. Shared by the live lens and the developer rehearsal.
struct ARCameraBackdrop: View {
    let camera: CameraService

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            switch camera.status {
            case .running, .requesting:
                CameraPreviewView(session: camera.session)
                    .overlay {
                        // Noir grade: sink the feed into the app's ink so HUD and
                        // glowing evidence stay readable even in daylight.
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
