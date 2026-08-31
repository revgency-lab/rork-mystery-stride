//
//  NoirMapView.swift
//  MysteryRun
//

import CoreLocation
import MapLibre
import SwiftUI
import UIKit

// MARK: - Style

/// The hand-authored noir basemap. Every colour on the map comes from
/// `noir-style.json`, so the map obeys the same palette as the rest of the app.
enum NoirMapStyle {
    static let url: URL? = Bundle.main.url(forResource: "noir-style", withExtension: "json")

    /// Required OpenStreetMap credit for the vector tile data.
    static let attribution = "© OpenStreetMap"
}

// MARK: - Inputs

/// A clue rendered as a glowing dossier node on the map.
struct NoirClueMarker: Identifiable, Equatable {
    let id: UUID
    let index: Int
    let symbolName: String
    let point: GeoPoint
    var isFound: Bool = false
    var isNext: Bool = false

    init(
        id: UUID = UUID(),
        index: Int,
        symbolName: String,
        point: GeoPoint,
        isFound: Bool = false,
        isNext: Bool = false
    ) {
        self.id = id
        self.index = index
        self.symbolName = symbolName
        self.point = point
        self.isFound = isFound
        self.isNext = isNext
    }

    init(clue: Clue, isNext: Bool = false) {
        id = clue.id
        index = clue.index
        symbolName = clue.symbolName
        point = clue.point
        isFound = clue.isFound
        self.isNext = isNext
    }

    /// Cache key for the baked node image.
    var imageName: String {
        "clue-\(index)-\(symbolName)-\(isFound ? "found" : isNext ? "next" : "open")"
    }
}

/// Concentric search rings drawn around the clue currently being hunted.
struct NoirFocusRing: Equatable {
    let center: GeoPoint
    let approachRadius: Double
    let unlockRadius: Double
}

/// How the map frames its content.
enum NoirMapCamera: Equatable {
    /// Leave the camera wherever the detective left it.
    case free
    /// Fit the whole set of points on screen.
    case fit([GeoPoint], padding: CGFloat)
    /// Centre on one point at a fixed zoom.
    case center(GeoPoint, zoom: Double)
    /// Keep a moving point in view **without ever touching zoom or bearing**.
    ///
    /// Re-centring on every GPS tick is what made the map feel like it was
    /// yanking itself around, and re-stating a zoom level threw away whatever
    /// the detective had pinched to. This nudges the camera only when the point
    /// drifts towards the edge of the screen; bumping `recenterToken` forces one.
    case follow(GeoPoint, recenterToken: Int)
}

/// Bridge that lets SwiftUI turn a touch location into a map coordinate, used by
/// the route drawing canvas.
@MainActor
final class NoirMapProxy {
    fileprivate weak var mapView: MLNMapView?

    func coordinate(at point: CGPoint) -> CLLocationCoordinate2D? {
        guard let mapView, mapView.bounds.contains(point) else { return nil }
        return mapView.convert(point, toCoordinateFrom: mapView)
    }
}

// MARK: - Map view

/// The app's one and only map surface: a MapLibre renderer driving our custom
/// noir style, with a glowing evidence trail drawn as real blurred style layers.
struct NoirMapView: UIViewRepresentable {
    /// The planned course of the case.
    var route: [GeoPoint] = []
    /// Ground the detective has actually covered.
    var traveled: [GeoPoint] = []
    /// A freehand sketch being drawn before it is snapped to streets.
    var sketch: [GeoPoint] = []
    var clues: [NoirClueMarker] = []
    var detective: GeoPoint? = nil
    var focusRing: NoirFocusRing? = nil
    var camera: NoirMapCamera = .free
    var isInteractive: Bool = true
    /// Dims the planned route so the traveled trail reads as the live one.
    var dimsPlannedRoute: Bool = false
    var showsStartPin: Bool = true
    var showsAttribution: Bool = true
    /// Lets the detective turn the map to match the street they're facing.
    var allowsRotation: Bool = false
    /// Bumping this snaps the map back to north-up.
    var resetNorthToken: Int = 0
    /// Bumping this re-applies the current framing, e.g. to fit a route again
    /// after the detective has wandered off across the city.
    var refitToken: Int = 0
    var proxy: NoirMapProxy? = nil
    /// Fires with the map centre once the detective stops moving the camera.
    var onCameraIdle: ((CLLocationCoordinate2D) -> Void)? = nil
    /// Fires only for camera moves the detective made with their hands, so an
    /// automatic follow nudge can't be mistaken for "they panned away".
    var onUserGesture: (() -> Void)? = nil
    /// Current map rotation, in degrees clockwise from north.
    var onBearingChange: ((Double) -> Void)? = nil
    /// A clue node was tapped.
    var onClueTap: ((UUID) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: NoirMapStyle.url)
        mapView.delegate = context.coordinator
        mapView.backgroundColor = UIColor(Theme.ink)
        mapView.tintColor = UIColor(Theme.brass)
        mapView.logoView.isHidden = true
        mapView.compassView.isHidden = true
        mapView.showsScale = false
        mapView.showsUserLocation = false
        mapView.allowsRotating = isInteractive && allowsRotation
        mapView.allowsTilting = false
        mapView.attributionButton.isHidden = !showsAttribution
        mapView.attributionButton.tintColor = UIColor(Theme.brass).withAlphaComponent(0.55)

        // Start somewhere sane so the first frame is never mid-ocean.
        let start = route.first ?? detective ?? RouteBuilder.fallbackOrigin
        mapView.setCenter(start.coordinate, zoomLevel: 14, animated: false)

        context.coordinator.mapView = mapView
        context.coordinator.config = self
        context.coordinator.attachTapHandling(to: mapView)
        proxy?.mapView = mapView
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        proxy?.mapView = mapView
        mapView.allowsScrolling = isInteractive
        mapView.allowsZooming = isInteractive
        mapView.allowsRotating = isInteractive && allowsRotation
        mapView.attributionButton.isHidden = !showsAttribution
        context.coordinator.apply(config: self)
    }

    static func dismantleUIView(_ mapView: MLNMapView, coordinator: Coordinator) {
        mapView.delegate = nil
        coordinator.mapView = nil
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        weak var mapView: MLNMapView?
        var config: NoirMapView?

        private var style: MLNStyle?
        private var registeredImages: Set<String> = []
        private var appliedCamera: NoirMapCamera?
        private var hasFramedOnce: Bool = false
        private var appliedRecenterToken: Int = 0
        private var appliedNorthToken: Int = 0
        private var appliedRefitToken: Int = 0
        private var reportedBearing: Double = 0
        /// Programmatic camera moves fire the region delegate too. Anything that
        /// lands before this instant is our move, not the detective's.
        private var programmaticMoveEnds: Date = .distantPast

        private enum SourceID {
            static let route = "mr-route"
            static let traveled = "mr-traveled"
            static let sketch = "mr-sketch"
            static let rings = "mr-rings"
            static let clues = "mr-clues"
            static let detective = "mr-detective"
        }

        // MARK: Delegate

        nonisolated func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            MainActor.assumeIsolated {
                self.style = style
                self.registeredImages.removeAll()
                self.install(on: style)
                if let config { self.apply(config: config) }
            }
        }

        nonisolated func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            MainActor.assumeIsolated {
                config?.onCameraIdle?(mapView.centerCoordinate)

                let bearing = mapView.direction
                if abs(bearing - reportedBearing) > 0.5 {
                    reportedBearing = bearing
                    config?.onBearingChange?(bearing)
                }

                guard Date() > programmaticMoveEnds else { return }
                config?.onUserGesture?()
            }
        }

        // MARK: Tap handling

        /// Adds evidence-node tapping without stealing the map's own gestures.
        func attachTapHandling(to mapView: MLNMapView) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.delegate = self
            // Let the map's double-tap zoom win when the tap is a double.
            for existing in mapView.gestureRecognizers ?? [] {
                guard let existing = existing as? UITapGestureRecognizer,
                      existing.numberOfTapsRequired > 1 else { continue }
                tap.require(toFail: existing)
            }
            mapView.addGestureRecognizer(tap)
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView, let onClueTap = config?.onClueTap else { return }
            let tapPoint = recognizer.location(in: mapView)
            // Fingertip-sized hit area — the nodes are small at low zoom.
            let slop: CGFloat = 26
            let rect = CGRect(
                x: tapPoint.x - slop,
                y: tapPoint.y - slop,
                width: slop * 2,
                height: slop * 2
            )
            let features = mapView.visibleFeatures(in: rect, styleLayerIdentifiers: ["mr-clues"])

            // With overlapping nodes, the one closest to the finger wins.
            var bestID: UUID?
            var bestDistance = CGFloat.greatestFiniteMagnitude
            for feature in features {
                guard let raw = feature.attribute(forKey: "clue") as? String,
                      let id = UUID(uuidString: raw),
                      let pointFeature = feature as? MLNPointFeature else { continue }
                let screen = mapView.convert(pointFeature.coordinate, toPointTo: mapView)
                let distance = hypot(screen.x - tapPoint.x, screen.y - tapPoint.y)
                if distance < bestDistance {
                    bestDistance = distance
                    bestID = id
                }
            }

            guard let bestID else { return }
            onClueTap(bestID)
        }

        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        // MARK: Layer installation

        private func install(on style: MLNStyle) {
            let routeSource = MLNShapeSource(identifier: SourceID.route, shape: nil, options: nil)
            let traveledSource = MLNShapeSource(identifier: SourceID.traveled, shape: nil, options: nil)
            let sketchSource = MLNShapeSource(identifier: SourceID.sketch, shape: nil, options: nil)
            let ringSource = MLNShapeSource(identifier: SourceID.rings, shape: nil, options: nil)
            let clueSource = MLNShapeSource(identifier: SourceID.clues, shape: nil, options: nil)
            let detectiveSource = MLNShapeSource(identifier: SourceID.detective, shape: nil, options: nil)

            for source in [routeSource, traveledSource, sketchSource, ringSource, clueSource, detectiveSource] {
                style.addSource(source)
            }

            // Search rings sit under everything else.
            let ringFill = MLNFillStyleLayer(identifier: "mr-ring-fill", source: ringSource)
            ringFill.fillColor = NSExpression(forConstantValue: UIColor(Theme.brass))
            ringFill.fillOpacity = NSExpression(forConstantValue: 0.07)
            style.addLayer(ringFill)

            let ringStroke = MLNLineStyleLayer(identifier: "mr-ring-stroke", source: ringSource)
            ringStroke.lineColor = NSExpression(forConstantValue: UIColor(Theme.brass))
            ringStroke.lineOpacity = NSExpression(forConstantValue: 0.45)
            ringStroke.lineWidth = NSExpression(forConstantValue: 1.2)
            ringStroke.lineDashPattern = NSExpression(forConstantValue: [3, 3])
            style.addLayer(ringStroke)

            // Planned route: three stacked blurred lines make the sodium bloom.
            addGlowLine(
                to: style,
                source: routeSource,
                prefix: "mr-route",
                color: UIColor(Theme.brass),
                dashed: true
            )

            // Traveled trail: the same recipe, hotter and solid.
            addGlowLine(
                to: style,
                source: traveledSource,
                prefix: "mr-traveled",
                color: UIColor(Theme.brass),
                dashed: false
            )

            // Freehand sketch in investigator violet.
            let sketchGlow = MLNLineStyleLayer(identifier: "mr-sketch-glow", source: sketchSource)
            sketchGlow.lineCap = NSExpression(forConstantValue: "round")
            sketchGlow.lineJoin = NSExpression(forConstantValue: "round")
            sketchGlow.lineColor = NSExpression(forConstantValue: UIColor(Theme.violet))
            sketchGlow.lineOpacity = NSExpression(forConstantValue: 0.35)
            sketchGlow.lineBlur = NSExpression(forConstantValue: 12)
            sketchGlow.lineWidth = NSExpression(forConstantValue: 20)
            style.addLayer(sketchGlow)

            let sketchCore = MLNLineStyleLayer(identifier: "mr-sketch-core", source: sketchSource)
            sketchCore.lineCap = NSExpression(forConstantValue: "round")
            sketchCore.lineJoin = NSExpression(forConstantValue: "round")
            sketchCore.lineColor = NSExpression(forConstantValue: UIColor(Theme.violet))
            sketchCore.lineWidth = NSExpression(forConstantValue: 5)
            style.addLayer(sketchCore)

            // Evidence nodes and the detective, always on top.
            let clueLayer = MLNSymbolStyleLayer(identifier: "mr-clues", source: clueSource)
            clueLayer.iconImageName = NSExpression(forKeyPath: "icon")
            clueLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            clueLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            clueLayer.iconAnchor = NSExpression(forConstantValue: "center")
            clueLayer.iconScale = NSExpression(forConstantValue: 1)
            style.addLayer(clueLayer)

            let detectiveLayer = MLNSymbolStyleLayer(identifier: "mr-detective", source: detectiveSource)
            detectiveLayer.iconImageName = NSExpression(forConstantValue: NoirMapImages.detectiveName)
            detectiveLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            detectiveLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            detectiveLayer.iconAnchor = NSExpression(forConstantValue: "center")
            style.addLayer(detectiveLayer)

            if let image = NoirMapImages.detectiveMarker() {
                style.setImage(image, forName: NoirMapImages.detectiveName)
                registeredImages.insert(NoirMapImages.detectiveName)
            }
            if let image = NoirMapImages.startMarker() {
                style.setImage(image, forName: NoirMapImages.startName)
                registeredImages.insert(NoirMapImages.startName)
            }
        }

        /// Halo + bloom + hot core, which is what sells the glowing-trail look.
        private func addGlowLine(
            to style: MLNStyle,
            source: MLNShapeSource,
            prefix: String,
            color: UIColor,
            dashed: Bool
        ) {
            let halo = MLNLineStyleLayer(identifier: "\(prefix)-halo", source: source)
            halo.lineCap = NSExpression(forConstantValue: "round")
            halo.lineJoin = NSExpression(forConstantValue: "round")
            halo.lineColor = NSExpression(forConstantValue: color)
            halo.lineOpacity = NSExpression(forConstantValue: 0.16)
            halo.lineBlur = Self.zoomStops([10: 10, 14: 20, 17: 30, 20: 44])
            halo.lineWidth = Self.zoomStops([10: 10, 14: 20, 17: 34, 20: 56])
            style.addLayer(halo)

            let bloom = MLNLineStyleLayer(identifier: "\(prefix)-bloom", source: source)
            bloom.lineCap = NSExpression(forConstantValue: "round")
            bloom.lineJoin = NSExpression(forConstantValue: "round")
            bloom.lineColor = NSExpression(forConstantValue: color)
            bloom.lineOpacity = NSExpression(forConstantValue: 0.42)
            bloom.lineBlur = Self.zoomStops([10: 4, 14: 8, 17: 13, 20: 20])
            bloom.lineWidth = Self.zoomStops([10: 4, 14: 8, 17: 14, 20: 24])
            style.addLayer(bloom)

            let core = MLNLineStyleLayer(identifier: "\(prefix)-core", source: source)
            core.lineCap = NSExpression(forConstantValue: "round")
            core.lineJoin = NSExpression(forConstantValue: "round")
            core.lineColor = NSExpression(forConstantValue: UIColor(red: 1.0, green: 0.88, blue: 0.62, alpha: 1))
            core.lineBlur = NSExpression(forConstantValue: 0.6)
            core.lineWidth = Self.zoomStops([10: 1.2, 14: 2.6, 17: 4.2, 20: 7])
            if dashed {
                core.lineDashPattern = NSExpression(forConstantValue: [1.4, 1.8])
            }
            style.addLayer(core)
        }

        private static func zoomStops(_ stops: [Int: Double]) -> NSExpression {
            NSExpression(
                forMLNInterpolating: NSExpression.zoomLevelVariable,
                curveType: MLNExpressionInterpolationMode.linear,
                parameters: nil,
                stops: NSExpression(forConstantValue: stops)
            )
        }

        // MARK: Content updates

        func apply(config: NoirMapView) {
            self.config = config
            guard let style, let mapView else { return }

            updateLine(style: style, id: SourceID.route, points: config.route)
            updateLine(style: style, id: SourceID.traveled, points: config.traveled)
            updateLine(style: style, id: SourceID.sketch, points: config.sketch)

            let plannedOpacity = config.dimsPlannedRoute ? 0.45 : 1.0
            setOpacityMultiplier(style: style, prefix: "mr-route", multiplier: plannedOpacity)

            updateRings(style: style, ring: config.focusRing)
            updateClues(style: style, config: config)
            updateDetective(style: style, point: config.detective)

            applyNorthReset(token: config.resetNorthToken, on: mapView)
            if config.refitToken != appliedRefitToken {
                appliedRefitToken = config.refitToken
                // Forget what we last applied so an unchanged framing re-runs.
                appliedCamera = nil
            }
            applyCamera(config.camera, on: mapView)
        }

        private func updateLine(style: MLNStyle, id: String, points: [GeoPoint]) {
            guard let source = style.source(withIdentifier: id) as? MLNShapeSource else { return }
            guard points.count > 1 else {
                source.shape = nil
                return
            }
            var coordinates = points.map(\.coordinate)
            source.shape = MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
        }

        private func setOpacityMultiplier(style: MLNStyle, prefix: String, multiplier: Double) {
            let base: [String: Double] = ["halo": 0.16, "bloom": 0.42, "core": 1.0]
            for (suffix, value) in base {
                guard let layer = style.layer(withIdentifier: "\(prefix)-\(suffix)") as? MLNLineStyleLayer else { continue }
                layer.lineOpacity = NSExpression(forConstantValue: value * multiplier)
            }
        }

        private func updateRings(style: MLNStyle, ring: NoirFocusRing?) {
            guard let source = style.source(withIdentifier: SourceID.rings) as? MLNShapeSource else { return }
            guard let ring else {
                source.shape = nil
                return
            }
            let shapes = [
                Self.circle(center: ring.center.coordinate, radius: ring.approachRadius),
                Self.circle(center: ring.center.coordinate, radius: ring.unlockRadius)
            ]
            source.shape = MLNShapeCollectionFeature(shapes: shapes)
        }

        private func updateClues(style: MLNStyle, config: NoirMapView) {
            guard let source = style.source(withIdentifier: SourceID.clues) as? MLNShapeSource else { return }

            var features: [MLNPointFeature] = []

            if config.showsStartPin, let start = config.route.first {
                let feature = MLNPointFeature()
                feature.coordinate = start.coordinate
                feature.attributes = ["icon": NoirMapImages.startName]
                features.append(feature)
            }

            for clue in config.clues {
                let name = clue.imageName
                if !registeredImages.contains(name) {
                    if let image = NoirMapImages.clueNode(
                        index: clue.index,
                        symbolName: clue.symbolName,
                        found: clue.isFound,
                        isNext: clue.isNext
                    ) {
                        style.setImage(image, forName: name)
                        registeredImages.insert(name)
                    } else {
                        continue
                    }
                }
                let feature = MLNPointFeature()
                feature.coordinate = clue.point.coordinate
                feature.attributes = ["icon": name, "clue": clue.id.uuidString]
                features.append(feature)
            }

            source.shape = features.isEmpty ? nil : MLNShapeCollectionFeature(shapes: features)
        }

        private func updateDetective(style: MLNStyle, point: GeoPoint?) {
            guard let source = style.source(withIdentifier: SourceID.detective) as? MLNShapeSource else { return }
            guard let point else {
                source.shape = nil
                return
            }
            let feature = MLNPointFeature()
            feature.coordinate = point.coordinate
            source.shape = feature
        }

        // MARK: Camera

        private func applyCamera(_ camera: NoirMapCamera, on mapView: MLNMapView) {
            // Follow has to be evaluated every update, since the point keeps moving.
            if case let .follow(point, token) = camera {
                follow(point, recenterToken: token, on: mapView)
                appliedCamera = camera
                return
            }

            guard camera != appliedCamera else { return }

            switch camera {
            case .free, .follow:
                break

            case let .fit(points, padding):
                guard let bounds = Self.bounds(for: points) else { return }
                let inset = UIEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)
                beginProgrammaticMove(animated: hasFramedOnce)
                mapView.setVisibleCoordinateBounds(
                    bounds,
                    edgePadding: inset,
                    animated: hasFramedOnce,
                    completionHandler: nil
                )
                hasFramedOnce = true

            case let .center(point, zoom):
                beginProgrammaticMove(animated: hasFramedOnce)
                mapView.setCenter(point.coordinate, zoomLevel: zoom, animated: hasFramedOnce)
                hasFramedOnce = true
            }

            appliedCamera = camera
        }

        /// Keeps the detective on screen with the lightest touch possible: no zoom
        /// change, no bearing change, and no movement at all while they're inside
        /// the frame. Reading a street corner should never be interrupted by the
        /// camera deciding to reframe itself.
        private func follow(_ point: GeoPoint, recenterToken: Int, on mapView: MLNMapView) {
            // First frame of a run: establish a sensible street-level zoom once.
            guard hasFramedOnce else {
                beginProgrammaticMove(animated: false)
                mapView.setCenter(point.coordinate, zoomLevel: 15.4, animated: false)
                hasFramedOnce = true
                appliedRecenterToken = recenterToken
                return
            }

            // They asked for it: always oblige, preserving their zoom.
            if recenterToken != appliedRecenterToken {
                appliedRecenterToken = recenterToken
                beginProgrammaticMove(animated: true)
                mapView.setCenter(point.coordinate, animated: true)
                return
            }

            let bounds = mapView.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }

            let screen = mapView.convert(point.coordinate, toPointTo: mapView)
            // Generous dead zone, biased upward because the proximity card and
            // controls cover the bottom third of the map.
            let comfort = CGRect(
                x: bounds.minX + bounds.width * 0.22,
                y: bounds.minY + bounds.height * 0.18,
                width: bounds.width * 0.56,
                height: bounds.height * 0.42
            )
            guard !comfort.contains(screen) else { return }

            beginProgrammaticMove(animated: true)
            mapView.setCenter(point.coordinate, animated: true)
        }

        private func beginProgrammaticMove(animated: Bool) {
            programmaticMoveEnds = Date().addingTimeInterval(animated ? 1.0 : 0.25)
        }

        private func applyNorthReset(token: Int, on mapView: MLNMapView) {
            guard token != appliedNorthToken else { return }
            appliedNorthToken = token
            beginProgrammaticMove(animated: true)
            mapView.setDirection(0, animated: true)
        }

        private static func bounds(for points: [GeoPoint]) -> MLNCoordinateBounds? {
            guard let first = points.first else { return nil }
            var minLat = first.latitude
            var maxLat = first.latitude
            var minLon = first.longitude
            var maxLon = first.longitude
            for point in points {
                minLat = min(minLat, point.latitude)
                maxLat = max(maxLat, point.latitude)
                minLon = min(minLon, point.longitude)
                maxLon = max(maxLon, point.longitude)
            }
            // Never hand MapLibre a zero-area box.
            let pad = 0.0009
            return MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: minLat - pad, longitude: minLon - pad),
                ne: CLLocationCoordinate2D(latitude: maxLat + pad, longitude: maxLon + pad)
            )
        }

        /// Metre-radius circle approximated as a polygon, used for search rings.
        private static func circle(
            center: CLLocationCoordinate2D,
            radius: Double,
            segments: Int = 72
        ) -> MLNPolygonFeature {
            let earthRadius = 6_378_137.0
            let latRadians = center.latitude * .pi / 180
            var coordinates: [CLLocationCoordinate2D] = []
            coordinates.reserveCapacity(segments + 1)

            for step in 0...segments {
                let angle = Double(step) / Double(segments) * 2 * .pi
                let dx = radius * cos(angle)
                let dy = radius * sin(angle)
                let deltaLat = (dy / earthRadius) * 180 / .pi
                let deltaLon = (dx / (earthRadius * max(cos(latRadians), 0.000001))) * 180 / .pi
                coordinates.append(
                    CLLocationCoordinate2D(
                        latitude: center.latitude + deltaLat,
                        longitude: center.longitude + deltaLon
                    )
                )
            }

            return MLNPolygonFeature(coordinates: &coordinates, count: UInt(coordinates.count))
        }
    }
}

// MARK: - Baked marker artwork

/// Marker artwork is designed in SwiftUI and baked into images so MapLibre can
/// place it as real symbol geometry that stays pinned while the map moves.
@MainActor
enum NoirMapImages {
    static let detectiveName = "mr-detective-node"
    static let startName = "mr-start-node"

    private static let renderScale: CGFloat = 3

    static func clueNode(index: Int, symbolName: String, found: Bool, isNext: Bool) -> UIImage? {
        render(ClueNodeGlyph(index: index, symbolName: symbolName, found: found, isNext: isNext))
    }

    static func detectiveMarker() -> UIImage? {
        render(DetectiveGlyph())
    }

    static func startMarker() -> UIImage? {
        render(StartGlyph())
    }

    private static func render<Content: View>(_ content: Content) -> UIImage? {
        let renderer = ImageRenderer(content: content)
        renderer.scale = renderScale
        renderer.isOpaque = false
        return renderer.uiImage
    }
}

/// Circular evidence node: dark lens, brass ring, stamped number badge.
private struct ClueNodeGlyph: View {
    let index: Int
    let symbolName: String
    let found: Bool
    let isNext: Bool

    private var ringColor: Color {
        found ? Theme.brass : isNext ? Theme.brass.opacity(0.9) : Color(red: 0.62, green: 0.65, blue: 0.71)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [ringColor.opacity(found || isNext ? 0.38 : 0.16), .clear],
                        center: .center,
                        startRadius: 18,
                        endRadius: 46
                    )
                )
                .frame(width: 94, height: 94)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.094, green: 0.106, blue: 0.145),
                            Color(red: 0.031, green: 0.039, blue: 0.063)
                        ],
                        center: .init(x: 0.35, y: 0.3),
                        startRadius: 2,
                        endRadius: 34
                    )
                )
                .frame(width: 54, height: 54)
                .overlay {
                    Circle()
                        .strokeBorder(ringColor.opacity(found || isNext ? 0.95 : 0.55), lineWidth: found || isNext ? 2 : 1.3)
                }
                .overlay {
                    Image(systemName: found ? "checkmark" : symbolName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(found ? Theme.brass : Theme.paper.opacity(0.92))
                }

            Circle()
                .fill(Color(red: 0.035, green: 0.043, blue: 0.067))
                .frame(width: 26, height: 26)
                .overlay { Circle().strokeBorder(Theme.brass, lineWidth: 1.7) }
                .overlay {
                    Text("\(index)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                }
                .offset(x: -27, y: -27)
        }
        .frame(width: 100, height: 100)
    }
}

/// The detective's own position: a hot brass bead in a soft pool of light.
private struct DetectiveGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.brass.opacity(0.5), .clear],
                        center: .center,
                        startRadius: 3,
                        endRadius: 30
                    )
                )
                .frame(width: 66, height: 66)

            Circle()
                .strokeBorder(Theme.brass.opacity(0.75), lineWidth: 1.5)
                .frame(width: 30, height: 30)

            Circle()
                .fill(Theme.brass)
                .frame(width: 14, height: 14)
                .overlay { Circle().strokeBorder(Theme.ink, lineWidth: 3) }
        }
        .frame(width: 70, height: 70)
    }
}

/// Trailhead marker where the route begins.
private struct StartGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.brass.opacity(0.3), .clear],
                        center: .center,
                        startRadius: 8,
                        endRadius: 32
                    )
                )
                .frame(width: 70, height: 70)

            Circle()
                .fill(Theme.brass)
                .frame(width: 32, height: 32)
                .overlay { Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1) }
                .overlay {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(red: 0.11, green: 0.08, blue: 0.02))
                }
        }
        .frame(width: 74, height: 74)
    }
}
