//
//  RoutePreviewMap.swift
//  MysteryRun
//

import MapKit
import SwiftUI

/// Case-file survey of the route: our own noir basemap, a glowing evidence
/// trail and numbered dossier nodes, framed like a photograph pinned to the file.
struct RoutePreviewMap: View {
    let route: [GeoPoint]
    let clues: [Clue]
    var surveyLabel: String? = nil

    private var markers: [NoirClueMarker] {
        clues.map { NoirClueMarker(clue: $0) }
    }

    var body: some View {
        NoirMapView(
            route: route,
            clues: markers,
            camera: .fit(route, padding: 46),
            isInteractive: false,
            showsAttribution: false
        )
        .overlay(alignment: .bottomLeading) {
            CompassRose()
                .frame(width: 46, height: 46)
                .padding(.leading, 14)
                .padding(.bottom, 14)
        }
        .overlay {
            // Vignette so the frame edges fall away into ink.
            RadialGradient(
                colors: [.clear, Theme.ink.opacity(0.25), Theme.ink.opacity(0.75)],
                center: .center,
                startRadius: 80,
                endRadius: 380
            )
            .allowsHitTesting(false)
        }
        .overlay {
            PaperGrain()
                .opacity(0.22)
                .allowsHitTesting(false)
        }
        .overlay {
            // Darkroom photograph border.
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.55), lineWidth: 5)
                .padding(1)
        }
        .overlay(alignment: .bottom) {
            if let surveyLabel {
                HStack(spacing: 8) {
                    Image(systemName: "airplane.departure")
                        .font(.system(size: 10, weight: .bold))
                    Text(surveyLabel.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .kerning(1.6)
                    Text("·")
                        .foregroundStyle(Theme.brass)
                    Text(coordinateCaption)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .kerning(0.5)
                }
                .foregroundStyle(Theme.textPrimary.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.black.opacity(0.55), in: .capsule)
                .overlay { Capsule().strokeBorder(Theme.brass.opacity(0.3), lineWidth: 1) }
                .padding(.bottom, 10)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text(NoirMapStyle.attribution)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Theme.textSecondary.opacity(0.55))
                .padding(.trailing, 8)
                .padding(.bottom, 5)
        }
        .clipShape(.rect(cornerRadius: 12))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var coordinateCaption: String {
        let center = RouteRegion.region(for: route, padding: 1.5).center
        let lat = String(format: "%.4f°%@", abs(center.latitude), center.latitude >= 0 ? "N" : "S")
        let lon = String(format: "%.4f°%@", abs(center.longitude), center.longitude >= 0 ? "E" : "W")
        return "\(lat) \(lon)"
    }
}

/// Hand-drawn compass rose, the one piece of map furniture we keep.
struct CompassRose: View {
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.paper.opacity(0.35), lineWidth: 1)

            ForEach(0..<8, id: \.self) { index in
                Capsule()
                    .fill(Theme.paper.opacity(index % 2 == 0 ? 0.75 : 0.35))
                    .frame(width: index % 2 == 0 ? 2.4 : 1.4, height: index % 2 == 0 ? 17 : 10)
                    .offset(y: index % 2 == 0 ? -6 : -9)
                    .rotationEffect(.degrees(Double(index) * 45))
            }

            Circle()
                .fill(Theme.brass)
                .frame(width: 4, height: 4)

            Text("N")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(Theme.paper.opacity(0.8))
                .offset(y: -26)
        }
        .shadow(color: .black.opacity(0.7), radius: 4)
        .accessibilityHidden(true)
    }
}

enum RouteRegion {
    /// Region that fits an entire route with a little breathing room.
    static func region(for points: [GeoPoint], padding: Double = 1.4) -> MKCoordinateRegion {
        guard let first = points.first else {
            return MKCoordinateRegion(
                center: RouteBuilder.fallbackOrigin.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }

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

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * padding, 0.004),
            longitudeDelta: max((maxLon - minLon) * padding, 0.004)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
