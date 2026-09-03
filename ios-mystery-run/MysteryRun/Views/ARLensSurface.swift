//
//  ARLensSurface.swift
//  MysteryRun
//

import ARKit
import SceneKit
import SwiftUI
import UIKit
import simd

/// One piece of evidence to materialise in the room.
struct EvidenceEncounter: Equatable {
    let id: UUID
    let index: Int
    let title: String
    let symbolName: String
    /// East/north offset from the detective to the evidence, metres.
    let east: Double
    let north: Double
    /// Ground distance as geodesy reports it, metres.
    let distance: Double
    /// Position resolved by the Visual Positioning System, in ARKit world space.
    /// Accurate to about a metre, so it always outranks the geodesy above.
    let resolvedPosition: SIMD3<Float>?
}

/// The evidence, drawn by ARKit itself.
///
/// This is the whole reason the lens finally holds still. Projecting anchors in
/// SwiftUI meant the overlay was composited from a pose sampled on the main
/// thread, one or two frames behind the video it was drawn over — so every pan
/// of the phone slid the pin across the world and nothing ever looked welded to
/// the pavement. Here the evidence is a node in the AR scene graph: SceneKit
/// projects it with the exact camera transform of the frame it is composited
/// into, which is what makes a virtual object sit still on real ground.
///
/// Placement happens once. After that the node keeps a fixed world position and
/// ARKit's odometry does the rest, so walking around the evidence behaves the way
/// walking around a real object does.
struct ARLensSurface: UIViewRepresentable {
    let session: ARSession
    /// What to place, or `nil` when nothing is close enough to be worth placing.
    let encounter: EvidenceEncounter?
    /// True once tracking is solid enough that a placement won't be thrown away.
    let canPlace: Bool
    /// Live ground distance from the camera to the placed evidence, metres.
    let onDistanceChange: (Double?) -> Void
    /// The evidence itself was tapped.
    let onTap: () -> Void

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session = session
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = false
        view.rendersCameraGrain = false
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 60

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)

        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.onDistanceChange = onDistanceChange
        context.coordinator.onTap = onTap
        context.coordinator.update(encounter: encounter, canPlace: canPlace)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDistanceChange: onDistanceChange, onTap: onTap)
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        coordinator.detach()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {
        var onDistanceChange: (Double?) -> Void
        var onTap: () -> Void

        private weak var sceneView: ARSCNView?
        private var displayLink: CADisplayLink?

        private var evidenceNode: SCNNode?
        private var placedClueID: UUID?
        /// Distance last handed back to SwiftUI, so a 60 Hz loop doesn't fire a
        /// state update every single frame.
        private var reportedDistance: Double?

        init(onDistanceChange: @escaping (Double?) -> Void, onTap: @escaping () -> Void) {
            self.onDistanceChange = onDistanceChange
            self.onTap = onTap
        }

        func attach(to view: ARSCNView) {
            sceneView = view
            let link = CADisplayLink(target: self, selector: #selector(step))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func detach() {
            displayLink?.invalidate()
            displayLink = nil
            evidenceNode?.removeFromParentNode()
            evidenceNode = nil
            placedClueID = nil
        }

        // MARK: Placement

        func update(encounter: EvidenceEncounter?, canPlace: Bool) {
            guard let encounter else {
                clearPlacement()
                return
            }
            // A different clue means the last one was banked; retire its node.
            if placedClueID != encounter.id {
                clearPlacement()
            }
            guard canPlace, evidenceNode == nil else { return }
            place(encounter)
        }

        private func clearPlacement() {
            evidenceNode?.removeFromParentNode()
            evidenceNode = nil
            placedClueID = nil
            report(nil)
        }

        private func place(_ encounter: EvidenceEncounter) {
            guard let view = sceneView,
                  let frame = view.session.currentFrame else { return }

            let cameraColumn = frame.camera.transform.columns.3
            let camera = SIMD3<Float>(cameraColumn.x, cameraColumn.y, cameraColumn.z)

            let horizontal: SIMD3<Float>
            if let resolved = encounter.resolvedPosition {
                horizontal = SIMD3(resolved.x, 0, resolved.z)
            } else {
                // ARKit's gravity-and-heading world runs x = east, y = up,
                // z = south, so north is −z.
                var offset = SIMD3<Float>(Float(encounter.east), 0, Float(-encounter.north))
                let length = simd_length(offset)
                // Standing right on top of the evidence would put it inside the
                // camera. Push it out to arm's length and let the detective turn
                // around to find it.
                if length < 1.8 {
                    let direction = length > 0.01 ? offset / length : SIMD3<Float>(0, 0, -1)
                    offset = direction * 1.8
                }
                horizontal = SIMD3(camera.x + offset.x, 0, camera.z + offset.z)
            }

            let ground = groundHeight(atX: horizontal.x, z: horizontal.z, cameraY: camera.y, in: view)
            let node = Self.makeEvidenceNode(symbolName: encounter.symbolName)
            node.simdPosition = SIMD3(horizontal.x, ground, horizontal.z)

            view.scene.rootNode.addChildNode(node)
            evidenceNode = node
            placedClueID = encounter.id
        }

        /// Height of the real floor beneath a spot, found by casting straight down
        /// from above it. Detected plane geometry is tried first because it is
        /// measured rather than guessed; the estimated plane is the fallback for a
        /// surface ARKit hasn't fully mapped, and eye height is the last resort.
        private func groundHeight(atX x: Float, z: Float, cameraY: Float, in view: ARSCNView) -> Float {
            let origin = SIMD3<Float>(x, cameraY + 0.5, z)
            let direction = SIMD3<Float>(0, -1, 0)
            let targets: [ARRaycastQuery.Target] = [.existingPlaneGeometry, .estimatedPlane]

            for target in targets {
                let query = ARRaycastQuery(
                    origin: origin,
                    direction: direction,
                    allowing: target,
                    alignment: .horizontal
                )
                if let hit = view.session.raycast(query).first {
                    return hit.worldTransform.columns.3.y
                }
            }
            return cameraY - Float(GeoAR.eyeHeight)
        }

        // MARK: Per-frame readout

        @objc private func step() {
            guard let view = sceneView,
                  let node = evidenceNode,
                  let frame = view.session.currentFrame else {
                report(nil)
                return
            }
            let camera = frame.camera.transform.columns.3
            let dx = node.simdPosition.x - camera.x
            let dz = node.simdPosition.z - camera.z
            report(Double((dx * dx + dz * dz).squareRoot()))
        }

        private func report(_ distance: Double?) {
            if let distance, let reportedDistance {
                guard abs(distance - reportedDistance) > 0.15 else { return }
            } else if distance == nil && reportedDistance == nil {
                return
            }
            reportedDistance = distance
            onDistanceChange(distance)
        }

        // MARK: Tap

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = sceneView, let evidence = evidenceNode else { return }
            let point = gesture.location(in: view)
            let hits = view.hitTest(point, options: [
                SCNHitTestOption.boundingBoxOnly: true,
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue
            ])
            let touchedEvidence = hits.contains { hit in
                var candidate: SCNNode? = hit.node
                while let current = candidate {
                    if current === evidence { return true }
                    candidate = current.parent
                }
                return false
            }
            guard touchedEvidence else { return }
            onTap()
        }
    }
}

// MARK: - Evidence geometry

private extension ARLensSurface.Coordinator {
    /// The artifact itself: a brass ring burned into the pavement, a shaft of
    /// light rising out of it and the evidence glyph hanging in that light.
    ///
    /// Every part is unlit and additively blended, so it reads as glow rather
    /// than as a plastic object dropped into the scene — which is what keeps it
    /// inside the app's noir language instead of looking like a stock AR demo.
    static func makeEvidenceNode(symbolName: String) -> SCNNode {
        let brass = UIColor(Theme.brass)
        let root = SCNNode()

        root.addChildNode(groundGlow(color: brass))
        root.addChildNode(groundRing(color: brass))
        root.addChildNode(pulseRing(color: brass))
        root.addChildNode(lightShaft(color: brass))
        root.addChildNode(artifact(symbolName: symbolName, color: brass))

        // A slow drift stops the glyph reading as a decal stuck to the screen.
        let rise = SCNAction.moveBy(x: 0, y: 0.06, z: 0, duration: 2.4)
        rise.timingMode = .easeInEaseOut
        let fall = rise.reversed()
        root.runAction(.repeatForever(.sequence([rise, fall])))

        return root
    }

    private static func groundGlow(color: UIColor) -> SCNNode {
        let plane = SCNPlane(width: 2.6, height: 2.6)
        let material = plane.firstMaterial
        material?.diffuse.contents = radialGlow(color: color)
        material?.lightingModel = .constant
        material?.blendMode = .add
        material?.writesToDepthBuffer = false
        material?.isDoubleSided = true

        let node = SCNNode(geometry: plane)
        // SCNPlane stands upright by default; lay it on the floor.
        node.eulerAngles.x = -.pi / 2
        node.position.y = 0.01
        node.renderingOrder = -1
        return node
    }

    private static func groundRing(color: UIColor) -> SCNNode {
        let torus = SCNTorus(ringRadius: 0.62, pipeRadius: 0.014)
        let material = torus.firstMaterial
        material?.diffuse.contents = color
        material?.emission.contents = color
        material?.lightingModel = .constant
        material?.writesToDepthBuffer = false

        let node = SCNNode(geometry: torus)
        node.position.y = 0.02
        return node
    }

    /// The ring that keeps washing outward — the thing the eye catches from down
    /// the street when the evidence is otherwise just a small glow.
    private static func pulseRing(color: UIColor) -> SCNNode {
        let torus = SCNTorus(ringRadius: 0.62, pipeRadius: 0.008)
        let material = torus.firstMaterial
        material?.diffuse.contents = color
        material?.emission.contents = color
        material?.lightingModel = .constant
        material?.blendMode = .add
        material?.writesToDepthBuffer = false

        let node = SCNNode(geometry: torus)
        node.position.y = 0.02
        node.opacity = 0.85

        let expand = SCNAction.scale(to: 2.6, duration: 2.4)
        expand.timingMode = .easeOut
        let fade = SCNAction.fadeOut(duration: 2.4)
        let snapBack = SCNAction.group([
            .scale(to: 1, duration: 0),
            .fadeOpacity(to: 0.85, duration: 0)
        ])
        node.runAction(.repeatForever(.sequence([.group([expand, fade]), snapBack])))
        return node
    }

    private static func lightShaft(color: UIColor) -> SCNNode {
        let height: CGFloat = 1.25
        let cylinder = SCNCylinder(radius: 0.05, height: height)
        let material = cylinder.firstMaterial
        material?.diffuse.contents = shaftGradient(color: color)
        material?.lightingModel = .constant
        material?.blendMode = .add
        material?.writesToDepthBuffer = false
        material?.isDoubleSided = true

        let node = SCNNode(geometry: cylinder)
        node.position.y = Float(height / 2)
        node.opacity = 0.5
        return node
    }

    private static func artifact(symbolName: String, color: UIColor) -> SCNNode {
        let plane = SCNPlane(width: 0.44, height: 0.44)
        let material = plane.firstMaterial
        material?.diffuse.contents = symbolImage(symbolName, tint: color)
        material?.lightingModel = .constant
        material?.isDoubleSided = true
        material?.writesToDepthBuffer = false

        let node = SCNNode(geometry: plane)
        node.position.y = 1.32

        // Faces the detective wherever they walk, but stays upright rather than
        // tipping over to track the camera's pitch.
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .Y
        node.constraints = [billboard]
        return node
    }

    // MARK: Textures

    private static func symbolImage(_ name: String, tint: UIColor) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 180, weight: .semibold)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration)
            ?? UIImage(systemName: "questionmark", withConfiguration: configuration) else {
            return nil
        }
        let size = CGSize(width: 256, height: 256)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let tinted = symbol.withTintColor(tint, renderingMode: .alwaysOriginal)
            let scale = min(size.width / tinted.size.width, size.height / tinted.size.height) * 0.8
            let drawn = CGSize(width: tinted.size.width * scale, height: tinted.size.height * scale)
            tinted.draw(in: CGRect(
                x: (size.width - drawn.width) / 2,
                y: (size.height - drawn.height) / 2,
                width: drawn.width,
                height: drawn.height
            ))
        }
    }

    private static func radialGlow(color: UIColor) -> UIImage {
        let size = CGSize(width: 256, height: 256)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [
                color.withAlphaComponent(0.5).cgColor,
                color.withAlphaComponent(0.14).cgColor,
                color.withAlphaComponent(0).cgColor
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 0.45, 1]
            ) else { return }
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            context.cgContext.drawRadialGradient(
                gradient,
                startCenter: centre,
                startRadius: 0,
                endCenter: centre,
                endRadius: size.width / 2,
                options: []
            )
        }
    }

    private static func shaftGradient(color: UIColor) -> UIImage {
        let size = CGSize(width: 16, height: 256)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [
                color.withAlphaComponent(0).cgColor,
                color.withAlphaComponent(0.45).cgColor
            ] as CFArray
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) else { return }
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
    }
}
