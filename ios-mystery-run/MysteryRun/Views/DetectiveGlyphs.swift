//
//  DetectiveGlyphs.swift
//  MysteryRun
//
//  Hand-drawn vector marks used across the record screen. Everything here is a
//  unit-square Shape so it scales to any frame without going soft, and none of
//  it depends on the system symbol set.
//

import SwiftUI

/// Case-streak flame with an inner core.
struct FlameGlyph: Shape {
    /// Draws the smaller inner tongue instead of the outer body.
    var isCore: Bool = false

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        if isCore {
            path.move(to: p(0.50, 0.92))
            path.addCurve(to: p(0.34, 0.62), control1: p(0.34, 0.90), control2: p(0.32, 0.74))
            path.addCurve(to: p(0.52, 0.44), control1: p(0.36, 0.53), control2: p(0.48, 0.50))
            path.addCurve(to: p(0.66, 0.66), control1: p(0.56, 0.56), control2: p(0.66, 0.56))
            path.addCurve(to: p(0.50, 0.92), control1: p(0.68, 0.78), control2: p(0.62, 0.88))
            path.closeSubpath()
        } else {
            path.move(to: p(0.50, 0.95))
            path.addCurve(to: p(0.20, 0.58), control1: p(0.24, 0.93), control2: p(0.17, 0.74))
            path.addCurve(to: p(0.40, 0.30), control1: p(0.23, 0.44), control2: p(0.38, 0.42))
            path.addCurve(to: p(0.47, 0.06), control1: p(0.41, 0.20), control2: p(0.36, 0.14))
            path.addCurve(to: p(0.72, 0.40), control1: p(0.66, 0.14), control2: p(0.70, 0.28))
            path.addCurve(to: p(0.80, 0.58), control1: p(0.74, 0.47), control2: p(0.80, 0.49))
            path.addCurve(to: p(0.50, 0.95), control1: p(0.83, 0.74), control2: p(0.76, 0.93))
            path.closeSubpath()
        }
        return path
    }
}

/// Weekly-file hourglass frame.
struct HourglassGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        path.move(to: p(0.16, 0.08))
        path.addLine(to: p(0.84, 0.08))
        path.move(to: p(0.16, 0.92))
        path.addLine(to: p(0.84, 0.92))
        path.move(to: p(0.24, 0.08))
        path.addLine(to: p(0.24, 0.24))
        path.addLine(to: p(0.50, 0.50))
        path.addLine(to: p(0.76, 0.24))
        path.addLine(to: p(0.76, 0.08))
        path.move(to: p(0.24, 0.92))
        path.addLine(to: p(0.24, 0.76))
        path.addLine(to: p(0.50, 0.50))
        path.addLine(to: p(0.76, 0.76))
        path.addLine(to: p(0.76, 0.92))
        return path
    }
}

/// Sand settled in the bottom bulb of the hourglass, filling with progress.
struct HourglassSandGlyph: Shape {
    /// 0...1 — how full the lower bulb is.
    var fill: Double

    var animatableData: Double {
        get { fill }
        set { fill = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        let clamped = min(max(fill, 0), 1)
        guard clamped > 0.01 else { return Path() }
        // The bulb is a triangle, so the sand surface widens as it rises.
        let top = 0.88 - 0.36 * clamped
        let halfWidth = 0.26 * clamped
        var path = Path()
        path.move(to: p(0.50 - halfWidth, top))
        path.addLine(to: p(0.50 + halfWidth, top))
        path.addLine(to: p(0.74, 0.88))
        path.addLine(to: p(0.26, 0.88))
        path.closeSubpath()
        return path
    }
}

/// Ground-covered boot print — heel, sole and stud marks.
struct BootPrintGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        // Sole
        path.move(to: p(0.34, 0.60))
        path.addCurve(to: p(0.36, 0.16), control1: p(0.28, 0.44), control2: p(0.28, 0.22))
        path.addCurve(to: p(0.66, 0.16), control1: p(0.46, 0.06), control2: p(0.58, 0.06))
        path.addCurve(to: p(0.66, 0.60), control1: p(0.74, 0.24), control2: p(0.72, 0.46))
        path.closeSubpath()
        // Heel
        path.move(to: p(0.38, 0.70))
        path.addCurve(to: p(0.62, 0.70), control1: p(0.42, 0.66), control2: p(0.58, 0.66))
        path.addCurve(to: p(0.50, 0.96), control1: p(0.66, 0.82), control2: p(0.62, 0.96))
        path.addCurve(to: p(0.38, 0.70), control1: p(0.38, 0.96), control2: p(0.34, 0.82))
        path.closeSubpath()
        return path
    }
}

/// Fallback rank crest drawn in vector: a shield with a five-pointed star and a
/// fedora silhouette resting on top. Used whenever the rendered crest art is
/// unavailable, so the screen never shows a hole.
struct CrestFallbackGlyph: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                ShieldShape()
                    .fill(
                        LinearGradient(
                            colors: [Theme.brass.opacity(0.85), Theme.brassDeep.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                ShieldShape()
                    .stroke(Theme.brass, lineWidth: side * 0.02)
                StarShape(points: 5)
                    .fill(Theme.ink.opacity(0.55))
                    .frame(width: side * 0.34, height: side * 0.34)
                    .offset(y: side * 0.04)
                FedoraSilhouette()
                    .fill(Color(red: 0.14, green: 0.12, blue: 0.11))
                    .frame(width: side * 0.72, height: side * 0.30)
                    .offset(y: -side * 0.34)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

private struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        path.move(to: p(0.50, 0.94))
        path.addCurve(to: p(0.14, 0.42), control1: p(0.26, 0.82), control2: p(0.14, 0.64))
        path.addLine(to: p(0.18, 0.24))
        path.addCurve(to: p(0.82, 0.24), control1: p(0.40, 0.16), control2: p(0.60, 0.16))
        path.addLine(to: p(0.86, 0.42))
        path.addCurve(to: p(0.50, 0.94), control1: p(0.86, 0.64), control2: p(0.74, 0.82))
        path.closeSubpath()
        return path
    }
}

private struct StarShape: Shape {
    let points: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.42
        var path = Path()
        for index in 0..<(points * 2) {
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = Angle.degrees(Double(index) * 180.0 / Double(points) - 90).radians
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

private struct FedoraSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        path.move(to: p(0.22, 0.66))
        path.addLine(to: p(0.26, 0.28))
        path.addQuadCurve(to: p(0.50, 0.10), control: p(0.32, 0.12))
        path.addQuadCurve(to: p(0.74, 0.28), control: p(0.68, 0.12))
        path.addLine(to: p(0.78, 0.66))
        path.closeSubpath()
        path.addEllipse(in: CGRect(
            x: rect.minX + 0.02 * w,
            y: rect.minY + 0.56 * h,
            width: 0.96 * w,
            height: 0.40 * h
        ))
        return path
    }
}

/// Weathered progress bar: a recessed ink channel with a lit fill and a bright
/// leading edge, used for every meter on the record screen.
struct EvidenceMeter: View {
    let progress: Double
    var tint: Color = Theme.brass
    var height: CGFloat = 7

    var body: some View {
        GeometryReader { geometry in
            let clamped = min(max(progress, 0), 1)
            let width = geometry.size.width * clamped
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.45))
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    }

                if clamped > 0 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.75), tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(width, height))
                        .overlay(alignment: .top) {
                            // Thin highlight along the top edge sells the metal.
                            Capsule()
                                .fill(Color.white.opacity(0.30))
                                .frame(height: 1)
                                .padding(.horizontal, height * 0.4)
                                .padding(.top, 1)
                        }
                        .shadow(color: tint.opacity(0.55), radius: 5, y: 0)
                }
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.7), value: progress)
        .accessibilityHidden(true)
    }
}
