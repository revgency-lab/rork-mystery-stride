//
//  CameraService.swift
//  MysteryRun
//

import AVFoundation
import Foundation
import Observation
import SwiftUI

/// Runs the rear (or external, on the simulator) camera for the AR lens view.
/// Preview-only: no frames are captured, recorded or sent anywhere.
@Observable
final class CameraService {
    enum Status: Equatable {
        case idle
        case requesting
        case running
        case denied
        case unavailable
    }

    private(set) var status: Status = .idle

    /// Horizontal field of view of the active format, degrees, measured across the
    /// sensor's long axis. The AR projection needs the real value — guessing it
    /// wrong is what makes pinned evidence slide instead of staying anchored.
    private(set) var fieldOfView: Double = GeoAR.defaultFieldOfView

    let session = AVCaptureSession()

    func start() {
        switch status {
        case .running, .requesting, .denied, .unavailable:
            return
        case .idle:
            break
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            status = .requesting
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if granted {
                        self.configureAndRun()
                    } else {
                        self.status = .denied
                    }
                }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        guard status == .running else { return }
        if session.isRunning { session.stopRunning() }
        status = .idle
    }

    private func configureAndRun() {
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }

        // `.external` picks up the webcam the cloud simulator injects; on real
        // devices the wide-angle rear camera is the one that matters.
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )

        guard let device = discovery.devices.first,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            status = .unavailable
            return
        }

        session.addInput(input)
        session.commitConfiguration()

        // Externally injected cameras often report 0 here, so keep the fallback.
        let reported = Double(device.activeFormat.videoFieldOfView)
        fieldOfView = reported > 1 ? reported : GeoAR.defaultFieldOfView

        if !session.isRunning { session.startRunning() }
        status = .running
    }
}

/// Layer-backed preview of the capture session, aspect-filled full screen.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection,
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}
