//
//  RouteDrawingView.swift
//  MysteryRun
//

import CoreLocation
import SwiftUI

/// Lets the detective trace their own route on the map with one finger. The
/// sketch is then calibrated onto real walkable streets and evidence is
/// scattered proportionally along whatever length they drew.
struct RouteDrawingView: View {
    let origin: GeoPoint
    let onConfirm: (GeneratedRoute) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var camera: NoirMapCamera
    @State private var proxy = NoirMapProxy()
    @State private var isDrawingArmed: Bool = false
    @State private var isStroking: Bool = false
    @State private var screenPoints: [CGPoint] = []
    @State private var drawnPath: [GeoPoint] = []
    @State private var calibrated: GeneratedRoute?
    @State private var isCalibrating: Bool = false
    @State private var calibrationFailed: Bool = false

    init(origin: GeoPoint, onConfirm: @escaping (GeneratedRoute) -> Void) {
        self.origin = origin
        self.onConfirm = onConfirm
        _camera = State(initialValue: .center(origin, zoom: 13.2))
    }

    private enum Phase {
        case positioning
        case drawing
        case drawn
        case calibrating
        case ready
    }

    private var phase: Phase {
        if isCalibrating { return .calibrating }
        if calibrated != nil { return .ready }
        if drawnPath.count > 1 { return .drawn }
        return isDrawingArmed ? .drawing : .positioning
    }

    private var rawDistance: Double {
        RouteBuilder.pathLength(drawnPath)
    }

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
                .ignoresSafeArea()

            hintPill
                .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) {
            controlCard
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
                .background {
                    LinearGradient(
                        colors: [Theme.ink.opacity(0), Theme.ink.opacity(0.94), Theme.ink],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                }
        }
        .background(Theme.ink)
        .navigationTitle("Draw Your Route")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ink, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
                    .tint(Theme.textSecondary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    recenter()
                } label: {
                    Image(systemName: "location.viewfinder")
                }
                .tint(Theme.brass)
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.impact(weight: .light), trigger: isDrawingArmed)
        .sensoryFeedback(.success, trigger: calibrated?.points.count ?? 0)
    }

    // MARK: - Map

    private var mapLayer: some View {
        NoirMapView(
            route: calibrated?.points ?? [],
            sketch: (calibrated == nil && !isStroking) ? drawnPath : [],
            clues: previewMarkers,
            detective: calibrated == nil ? origin : nil,
            camera: camera,
            isInteractive: !isLocked,
            showsStartPin: calibrated != nil,
            proxy: proxy
        )
        .overlay {
            // Live chalk stroke while the finger is down.
            Canvas { context, _ in
                guard screenPoints.count > 1 else { return }
                var path = Path()
                path.move(to: screenPoints[0])
                for point in screenPoints.dropFirst() {
                    path.addLine(to: point)
                }
                context.stroke(
                    path,
                    with: .color(Theme.violet.opacity(0.35)),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round)
                )
                context.stroke(
                    path,
                    with: .color(Theme.violet),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                )
            }
            .allowsHitTesting(false)
        }
        .overlay {
            if isLocked {
                // Transparent canvas that swallows touches so the map holds still.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(drawGesture)
            }
        }
        .overlay {
            if isLocked {
                Rectangle()
                    .strokeBorder(Theme.violet.opacity(0.55), lineWidth: 3)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }

    /// True while the map is frozen for drawing.
    private var isLocked: Bool {
        isDrawingArmed && calibrated == nil
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !isStroking {
                    isStroking = true
                    screenPoints = []
                    drawnPath = []
                    calibrationFailed = false
                }

                if let last = screenPoints.last,
                   hypot(value.location.x - last.x, value.location.y - last.y) < 5 {
                    return
                }

                screenPoints.append(value.location)
                if let coordinate = proxy.coordinate(at: value.location) {
                    drawnPath.append(GeoPoint(coordinate))
                }
            }
            .onEnded { _ in
                isStroking = false
                screenPoints = []
                if drawnPath.count < 2 { drawnPath = [] }
            }
    }

    private var previewMarkers: [NoirClueMarker] {
        guard let calibrated else { return [] }
        let points = CaseGenerator.evidencePoints(route: calibrated.points, distance: calibrated.distance)
        return points.enumerated().map { index, point in
            NoirClueMarker(index: index + 1, symbolName: "magnifyingglass", point: point)
        }
    }

    private func recenter() {
        if let calibrated, calibrated.points.count > 1 {
            camera = .fit(calibrated.points, padding: 56)
        } else {
            camera = .center(origin, zoom: 13.2)
        }
    }

    // MARK: - Chrome

    private var hintPill: some View {
        HStack(spacing: 8) {
            Image(systemName: hintSymbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.brass)
            Text(hintText)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
    }

    private var hintSymbol: String {
        switch phase {
        case .positioning: "hand.draw"
        case .drawing: "scribble.variable"
        case .drawn: "checkmark.circle"
        case .calibrating: "point.topleft.down.to.point.bottomright.curvepath"
        case .ready: "map"
        }
    }

    private var hintText: String {
        switch phase {
        case .positioning: "Pan and zoom to your patch of the city"
        case .drawing: "Trace the route with one finger"
        case .drawn: "Sketch captured — calibrate it to real streets"
        case .calibrating: "Pulling your sketch onto walkable streets"
        case .ready: "Evidence scattered along your route"
        }
    }

    @ViewBuilder
    private var controlCard: some View {
        VStack(spacing: 14) {
            switch phase {
            case .positioning:
                VStack(spacing: 10) {
                    Text("Move the map so your route fits on screen, then start drawing. Any length works — a short loop or a fifty mile trek.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)

                    Button {
                        isDrawingArmed = true
                    } label: {
                        HStack {
                            Image(systemName: "scribble.variable")
                            Text("Start Drawing")
                        }
                    }
                    .buttonStyle(BrassButtonStyle())
                }

            case .drawing:
                VStack(spacing: 10) {
                    Text("Drag across the map to trace where you want to go. Lift your finger to finish.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)

                    Button("Move the map instead") { isDrawingArmed = false }
                        .buttonStyle(VioletOutlineButtonStyle())
                }

            case .drawn:
                VStack(spacing: 12) {
                    sketchStats

                    if rawDistance < 400 {
                        Text("That sketch is a little short — draw at least 0.4 km.")
                            .font(.caption)
                            .foregroundStyle(Theme.evidenceRed)
                    }

                    Button {
                        Task { await calibrate() }
                    } label: {
                        HStack {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            Text("Calibrate to Streets")
                        }
                    }
                    .buttonStyle(BrassButtonStyle())
                    .disabled(rawDistance < 400)
                    .opacity(rawDistance < 400 ? 0.5 : 1)

                    Button("Clear and Redraw") { clear() }
                        .buttonStyle(VioletOutlineButtonStyle())
                }

            case .calibrating:
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(Theme.brass)
                    Text("Tracing walkable streets…")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Matching your sketch to pavement, block by block.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 8)

            case .ready:
                if let calibrated {
                    VStack(spacing: 12) {
                        HStack(spacing: 0) {
                            MetricBlock(
                                symbol: "shoeprints.fill",
                                value: calibrated.distance.shortKilometreString,
                                label: "Distance",
                                unit: "km"
                            )
                            Divider().frame(height: 34).overlay(Theme.inkStroke)
                            MetricBlock(
                                symbol: "point.topleft.down.to.point.bottomright.curvepath",
                                value: calibrated.distance.mileString,
                                label: "Distance",
                                unit: "mi"
                            )
                            Divider().frame(height: 34).overlay(Theme.inkStroke)
                            MetricBlock(
                                symbol: "magnifyingglass",
                                value: "\(CaseGenerator.clueCount(for: calibrated.distance))",
                                label: "Clues"
                            )
                        }

                        Text(calibrated.snappedToStreets
                             ? "Evidence is spread evenly across the whole route — one find roughly every \(spacingText)."
                             : "Some stretches couldn't be matched to streets, so those parts follow your sketch exactly.")
                            .font(.caption)
                            .foregroundStyle(calibrated.snappedToStreets ? Theme.textSecondary : Theme.brass)
                            .multilineTextAlignment(.center)

                        Button {
                            onConfirm(calibrated)
                            dismiss()
                        } label: {
                            HStack {
                                Text("Use This Route")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .padding(.horizontal, 8)
                        }
                        .buttonStyle(BrassButtonStyle())

                        Button("Draw a Different Route") { clear() }
                            .buttonStyle(VioletOutlineButtonStyle())
                    }
                }
            }

            if calibrationFailed {
                Text("We couldn't read that sketch. Try drawing a longer, smoother line.")
                    .font(.caption)
                    .foregroundStyle(Theme.evidenceRed)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .inkCard()
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: phase == .ready)
    }

    private var sketchStats: some View {
        HStack(spacing: 0) {
            MetricBlock(
                symbol: "scribble.variable",
                value: rawDistance.shortKilometreString,
                label: "Sketched",
                unit: "km"
            )
            Divider().frame(height: 34).overlay(Theme.inkStroke)
            MetricBlock(
                symbol: "point.topleft.down.to.point.bottomright.curvepath",
                value: rawDistance.mileString,
                label: "Sketched",
                unit: "mi"
            )
            Divider().frame(height: 34).overlay(Theme.inkStroke)
            MetricBlock(
                symbol: "magnifyingglass",
                value: "~\(CaseGenerator.clueCount(for: rawDistance))",
                label: "Clues"
            )
        }
    }

    private var spacingText: String {
        guard let calibrated else { return "half a kilometre" }
        let count = CaseGenerator.clueCount(for: calibrated.distance)
        guard count > 1 else { return "half a kilometre" }
        let spacing = calibrated.distance / Double(count)
        return spacing < 950 ? "\(Int((spacing / 50).rounded()) * 50) m" : "\(spacing.shortKilometreString) km"
    }

    // MARK: - Actions

    private func calibrate() async {
        isCalibrating = true
        calibrationFailed = false
        defer { isCalibrating = false }

        let result = await RouteBuilder.makeRoute(fromDrawnPath: drawnPath)
        guard result.points.count > 1, result.distance > 200 else {
            calibrationFailed = true
            return
        }
        calibrated = result
        isDrawingArmed = false
        recenter()
    }

    private func clear() {
        calibrated = nil
        drawnPath = []
        screenPoints = []
        calibrationFailed = false
        isDrawingArmed = true
    }
}
