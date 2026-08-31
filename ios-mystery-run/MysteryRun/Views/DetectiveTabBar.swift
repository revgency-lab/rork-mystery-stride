//
//  DetectiveTabBar.swift
//  MysteryRun
//

import SwiftUI
import UIKit

/// The four surfaces of the detective's desk.
enum AppTab: Int, CaseIterable, Identifiable, Hashable {
    case caseFile
    case evidence
    case progress
    case profile

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .caseFile: "Case"
        case .evidence: "Evidence"
        case .progress: "Record"
        case .profile: "Detective"
        }
    }
}

// MARK: - Hand-drawn glyphs

/// Manila case folder with a raised index tab.
private struct FolderGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        path.move(to: p(0.06, 0.86))
        path.addLine(to: p(0.06, 0.26))
        path.addLine(to: p(0.40, 0.26))
        path.addLine(to: p(0.49, 0.40))
        path.addLine(to: p(0.94, 0.40))
        path.addLine(to: p(0.94, 0.86))
        path.closeSubpath()
        return path
    }
}

/// The single filed sheet peeking out of the folder.
private struct FolderSheetGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        path.move(to: p(0.20, 0.40))
        path.addLine(to: p(0.20, 0.16))
        path.addLine(to: p(0.80, 0.16))
        path.addLine(to: p(0.80, 0.40))
        return path
    }
}

/// Magnifier ring and handle.
private struct MagnifierGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        path.addEllipse(in: CGRect(
            x: rect.minX + 0.10 * w,
            y: rect.minY + 0.10 * h,
            width: 0.58 * w,
            height: 0.58 * h
        ))
        path.move(to: p(0.64, 0.64))
        path.addLine(to: p(0.90, 0.90))
        return path
    }
}

/// Fingerprint ridges seen through the lens.
private struct FingerprintGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let center = CGPoint(x: rect.minX + 0.39 * w, y: rect.minY + 0.39 * h)
        var path = Path()
        for (index, radius) in [0.09, 0.16, 0.23].enumerated() {
            let r = radius * min(w, h)
            // Broken arcs read as ridges rather than concentric rings.
            let start = Angle.degrees(index % 2 == 0 ? 200 : 20)
            path.addArc(
                center: center,
                radius: r,
                startAngle: start,
                endAngle: start + .degrees(280),
                clockwise: false
            )
        }
        return path
    }
}

/// Ascending case-record bars.
private struct LedgerBarsGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        let heights: [CGFloat] = [0.30, 0.48, 0.68]
        for (index, barHeight) in heights.enumerated() {
            let x = rect.minX + (0.16 + CGFloat(index) * 0.26) * w
            let top = rect.minY + (0.82 - barHeight) * h
            path.addRoundedRect(
                in: CGRect(x: x, y: top, width: 0.16 * w, height: barHeight * h),
                cornerSize: CGSize(width: 0.03 * w, height: 0.03 * w)
            )
        }
        return path
    }
}

/// Baseline rule under the record bars.
private struct LedgerBaselineGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 0.10 * rect.width, y: rect.minY + 0.88 * rect.height))
        path.addLine(to: CGPoint(x: rect.minX + 0.92 * rect.width, y: rect.minY + 0.88 * rect.height))
        return path
    }
}

/// Fedora crown — the detective.
private struct FedoraCrownGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        path.move(to: p(0.24, 0.62))
        path.addLine(to: p(0.27, 0.38))
        path.addQuadCurve(to: p(0.50, 0.24), control: p(0.32, 0.26))
        path.addQuadCurve(to: p(0.73, 0.38), control: p(0.68, 0.26))
        path.addLine(to: p(0.76, 0.62))
        path.closeSubpath()
        return path
    }
}

/// Fedora brim.
private struct FedoraBrimGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.addEllipse(in: CGRect(
            x: rect.minX + 0.04 * w,
            y: rect.minY + 0.56 * h,
            width: 0.92 * w,
            height: 0.22 * h
        ))
        return path
    }
}

/// Renders one tab's custom glyph. Inactive tabs are drawn as thin ink lines;
/// the active tab fills in, as if the file had been pulled and opened.
private struct TabGlyph: View {
    let tab: AppTab
    let isSelected: Bool

    private var tint: Color { isSelected ? Theme.brass : Theme.textSecondary }
    private var lineWidth: CGFloat { isSelected ? 2.0 : 1.6 }

    var body: some View {
        ZStack {
            switch tab {
            case .caseFile:
                FolderSheetGlyph()
                    .stroke(tint.opacity(isSelected ? 0.95 : 0.75), style: .init(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                FolderGlyph()
                    .fill(tint.opacity(isSelected ? 0.22 : 0))
                FolderGlyph()
                    .stroke(tint, style: .init(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            case .evidence:
                Circle()
                    .fill(tint.opacity(isSelected ? 0.18 : 0))
                    .frame(width: 0.58 * 26, height: 0.58 * 26)
                    .offset(x: -0.11 * 26, y: -0.11 * 26)
                FingerprintGlyph()
                    .stroke(tint.opacity(isSelected ? 0.9 : 0.55), style: .init(lineWidth: 1.2, lineCap: .round))
                MagnifierGlyph()
                    .stroke(tint, style: .init(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            case .progress:
                LedgerBarsGlyph()
                    .fill(tint.opacity(isSelected ? 0.9 : 0.28))
                LedgerBarsGlyph()
                    .stroke(tint, style: .init(lineWidth: 1.3, lineJoin: .round))
                LedgerBaselineGlyph()
                    .stroke(tint, style: .init(lineWidth: lineWidth, lineCap: .round))

            case .profile:
                FedoraCrownGlyph()
                    .fill(tint.opacity(isSelected ? 0.85 : 0.20))
                FedoraCrownGlyph()
                    .stroke(tint, style: .init(lineWidth: lineWidth, lineJoin: .round))
                FedoraBrimGlyph()
                    .fill(tint.opacity(isSelected ? 0.95 : 0.28))
                FedoraBrimGlyph()
                    .stroke(tint, style: .init(lineWidth: lineWidth))
            }
        }
        .frame(width: 26, height: 26)
    }
}

// MARK: - Bar

/// Custom bottom bar built from hand-drawn case-file glyphs. Replaces the system
/// tab bar so the app keeps its noir palette all the way to the screen edge.
struct DetectiveTabBar: View {
    @Binding var selection: AppTab
    /// Live clue progress for the active case, shown as a brass count on Evidence.
    var evidenceBadge: String?
    /// Whether a case is currently being run, which pulses the Case tab.
    var isLive: Bool = false

    @Namespace private var spotlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var livePulse: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background { barBackground }
        .overlay(alignment: .top) { brassHairline }
        .onAppear {
            guard isLive, !reduceMotion else { return }
            livePulse = true
        }
        .onChange(of: isLive) { _, newValue in
            livePulse = newValue && !reduceMotion
        }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            guard selection != tab else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    if selection == tab {
                        // Interrogation-lamp pool behind the active glyph.
                        Ellipse()
                            .fill(
                                RadialGradient(
                                    colors: [Theme.brass.opacity(0.30), .clear],
                                    center: .center,
                                    startRadius: 1,
                                    endRadius: 26
                                )
                            )
                            .frame(width: 52, height: 40)
                            .matchedGeometryEffect(id: "spotlight", in: spotlight)
                            .allowsHitTesting(false)
                    }

                    TabGlyph(tab: tab, isSelected: selection == tab)
                        .scaleEffect(selection == tab ? 1.06 : 1)
                        .shadow(
                            color: selection == tab ? Theme.brass.opacity(0.5) : .clear,
                            radius: 7
                        )
                }
                .frame(height: 30)
                .overlay(alignment: .topTrailing) { badge(for: tab) }

                Text(tab.title.uppercased())
                    .font(.system(size: 9, weight: selection == tab ? .heavy : .semibold))
                    .kerning(1.1)
                    .foregroundStyle(selection == tab ? Theme.brass : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(.rect)
        }
        .buttonStyle(TabPressStyle())
        .accessibilityLabel(tab.title)
        .accessibilityValue(tab == .evidence ? (evidenceBadge.map { "\($0) clues" } ?? "") : "")
        .accessibilityAddTraits(selection == tab ? [.isSelected, .isButton] : .isButton)
    }

    /// Brass evidence count, plus a red pulse when a case is actively running.
    @ViewBuilder
    private func badge(for tab: AppTab) -> some View {
        if tab == .evidence, let evidenceBadge {
            Text(evidenceBadge)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color(red: 0.11, green: 0.08, blue: 0.02))
                .lineLimit(1)
                .padding(.horizontal, 4)
                .frame(minWidth: 15, minHeight: 15)
                .background(Theme.brass, in: .capsule)
                .overlay { Capsule().strokeBorder(Theme.ink, lineWidth: 1.5) }
                .offset(x: 11, y: -3)
                .transition(.scale.combined(with: .opacity))
        } else if tab == .caseFile, isLive {
            Circle()
                .fill(Theme.evidenceRed)
                .frame(width: 7, height: 7)
                .overlay { Circle().strokeBorder(Theme.ink, lineWidth: 1.5) }
                .scaleEffect(livePulse ? 1.35 : 1)
                .opacity(livePulse ? 0.65 : 1)
                .animation(
                    livePulse
                        ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                        : .default,
                    value: livePulse
                )
                .offset(x: 9, y: -1)
        }
    }

    /// Smoked-glass slab with a warm lift under the bar.
    private var barBackground: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(Theme.ink.opacity(0.72))
            LinearGradient(
                colors: [Theme.brass.opacity(0.055), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea(edges: .bottom)
    }

    /// Filed-edge rule: brass at the centre, fading to nothing at the corners.
    private var brassHairline: some View {
        LinearGradient(
            colors: [.clear, Theme.brass.opacity(0.55), Theme.brassDeep.opacity(0.75), Theme.brass.opacity(0.55), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
    }
}

/// Tabs dip slightly when pressed, matching the map affordances.
private struct TabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
