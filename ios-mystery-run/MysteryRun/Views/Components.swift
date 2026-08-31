//
//  Components.swift
//  MysteryRun
//

import SwiftUI

/// Sepia case photograph clipped into the dossier with a brass paperclip.
struct CasePhoto: View {
    let assetName: String
    var height: CGFloat = 150
    var showsClip: Bool = true

    var body: some View {
        Color(red: 0.12, green: 0.12, blue: 0.13)
            .frame(height: height)
            .overlay {
                if UIImage(named: assetName) != nil {
                    Image(assetName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                } else {
                    Image(systemName: "photo.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.brass.opacity(0.4))
                }
            }
            .clipShape(.rect(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.white.opacity(0.65), lineWidth: 5)
            }
            .overlay(alignment: .topLeading) {
                if showsClip {
                    Image(systemName: "paperclip")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Theme.brassDeep)
                        .rotationEffect(.degrees(-24))
                        .offset(x: -6, y: -12)
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 6, y: 4)
            .accessibilityHidden(true)
    }
}

/// Single labelled metric with a brass icon, used in briefing and summary rows.
struct MetricBlock: View {
    let symbol: String
    let value: String
    let label: String
    var unit: String?
    var onPaper: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(Theme.brass)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.title3, weight: .bold))
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(onPaper ? Theme.paperInkSoft : Theme.textSecondary)
                }
            }
            .foregroundStyle(onPaper ? Theme.paperInk : Theme.textPrimary)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(onPaper ? Theme.paperInkSoft : Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) \(unit ?? "")")
    }
}

/// Progress across a case's evidence. Short cases show icon chips; long ones
/// collapse to a tick bar, because twenty legible chips do not fit on a phone.
/// Both forms span exactly the width available at any clue count.
struct EvidenceTrackRow: View {
    let clues: [Clue]

    /// Past this count chips get too small to read, so the bar takes over.
    private var usesChips: Bool { clues.count <= 10 }

    var body: some View {
        Group {
            if usesChips {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 44, maximum: 60), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(clues) { clue in
                        EvidenceChip(clue: clue, side: 46)
                    }
                }
            } else {
                tickBar
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(clues.filter(\.isFound).count) of \(clues.count) clues found")
    }

    /// One flexible tick per clue: the row fits any count without overflowing,
    /// and pivotal evidence reads taller and violet.
    private var tickBar: some View {
        HStack(spacing: 3) {
            ForEach(clues) { clue in
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(tickColor(for: clue))
                    .frame(maxWidth: .infinity)
                    .frame(height: clue.isPivotal ? 16 : 10)
            }
        }
        .frame(height: 16)
    }

    private func tickColor(for clue: Clue) -> Color {
        if clue.isFound {
            return clue.isPivotal ? Theme.violet : Theme.brass
        }
        return Color.white.opacity(0.14)
    }
}

struct EvidenceChip: View {
    let clue: Clue
    var side: CGFloat = 48

    private var cornerRadius: CGFloat { side * 0.21 }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(clue.isFound ? Theme.brass.opacity(0.16) : Color.white.opacity(0.04))
            .frame(height: side)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        clue.isFound ? Theme.brass.opacity(0.8) : Color.white.opacity(0.12),
                        lineWidth: 1
                    )
            }
            .overlay {
                Image(systemName: clue.symbolName)
                    .font(.system(size: side * 0.38))
                    .foregroundStyle(clue.isFound ? Theme.brass : Theme.textSecondary.opacity(0.45))
            }
            .overlay(alignment: .topTrailing) {
                if clue.isFound {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: side * 0.31))
                        .foregroundStyle(Theme.brass)
                        .background(Circle().fill(Theme.ink))
                        .offset(x: side * 0.1, y: -side * 0.1)
                }
            }
    }
}

/// Floating capsule of live session metrics.
struct StatCapsule: View {
    let items: [(symbol: String, text: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 1, height: 18)
                }
                HStack(spacing: 5) {
                    Image(systemName: item.symbol)
                        .font(.caption2)
                        .foregroundStyle(Theme.brass)
                    Text(item.text)
                        .font(.system(.subheadline, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
    }
}

/// Circular control used in the live investigation bar.
struct RoundControlButton: View {
    let symbol: String
    let label: String
    var tint: Color = Theme.textPrimary
    var background: Color = Color.white.opacity(0.10)
    var diameter: CGFloat = 62
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Circle()
                    .fill(background)
                    .frame(width: diameter, height: diameter)
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: diameter * 0.34, weight: .bold))
                            .foregroundStyle(tint)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)

            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Torn paper note holding a clue's story fragment.
struct EvidenceNote: View {
    let fragment: String
    var compact: Bool = false

    var body: some View {
        Text(fragment)
            .font(.system(compact ? .callout : .title3, design: .serif))
            .italic()
            .foregroundStyle(Theme.paperInk)
            .multilineTextAlignment(.center)
            .lineSpacing(compact ? 3 : 6)
            .padding(.horizontal, compact ? 16 : 24)
            .padding(.vertical, compact ? 16 : 28)
            .frame(maxWidth: .infinity)
            .background {
                PaperSurface()
                    .clipShape(TornPaper())
            }
            .overlay {
                TornPaper()
                    .stroke(Theme.paperInk.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.65), radius: 16, y: 10)
    }
}

/// Rough torn-edge paper outline.
struct TornPaper: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var generator = SeededGenerator(seed: 7)
        let steps = 14
        let amplitude: CGFloat = 4

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        for step in 1...steps {
            let x = rect.minX + rect.width * CGFloat(step) / CGFloat(steps)
            let y = rect.minY + CGFloat(Double.random(in: -1...1, using: &generator)) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        for step in 1...steps {
            let y = rect.minY + rect.height * CGFloat(step) / CGFloat(steps)
            let x = rect.maxX + CGFloat(Double.random(in: -1...1, using: &generator)) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        for step in 1...steps {
            let x = rect.maxX - rect.width * CGFloat(step) / CGFloat(steps)
            let y = rect.maxY + CGFloat(Double.random(in: -1...1, using: &generator)) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        for step in 1...steps {
            let y = rect.maxY - rect.height * CGFloat(step) / CGFloat(steps)
            let x = rect.minX + CGFloat(Double.random(in: -1...1, using: &generator)) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.closeSubpath()
        return path
    }
}

/// Warm overhead spotlight used on reveal and resolution screens.
///
/// The ink colour is the size anchor: a `.fill` photograph reports a layout frame
/// wider than the screen, which previously stretched every sibling view and pushed
/// content off both edges. Keeping the image in a clipped overlay pins the frame.
struct SpotlightBackdrop: View {
    var body: some View {
        Theme.ink
            .overlay {
                if UIImage(named: AppAsset.deskSpotlight) != nil {
                    Image(AppAsset.deskSpotlight)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(0.5)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                LinearGradient(
                    colors: [Theme.brass.opacity(0.20), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
            .overlay {
                // Heavy vignette keeps body copy legible over the busy wood grain.
                RadialGradient(
                    colors: [Color.black.opacity(0.25), Color.black.opacity(0.86)],
                    center: .init(x: 0.5, y: 0.3),
                    startRadius: 60,
                    endRadius: 520
                )
            }
            .clipped()
            .ignoresSafeArea()
    }
}

/// Number pill used for clue markers and report steps.
struct ClueBadge: View {
    let index: Int
    var found: Bool = true
    var diameter: CGFloat = 30

    var body: some View {
        Circle()
            .fill(found ? Theme.brass : Theme.inkElevated)
            .frame(width: diameter, height: diameter)
            .overlay {
                Circle().strokeBorder(found ? Color.black.opacity(0.25) : Theme.brass.opacity(0.5), lineWidth: 1.5)
            }
            .overlay {
                Text("\(index)")
                    .font(.system(size: diameter * 0.46, weight: .bold))
                    .foregroundStyle(found ? Color(red: 0.11, green: 0.08, blue: 0.02) : Theme.brass.opacity(0.7))
            }
    }
}

extension TimeInterval {
    /// hh:mm:ss for live sessions and reports.
    var clockString: String {
        let total = Int(self)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension Double {
    /// Metres formatted as kilometres with one decimal.
    var kilometreString: String {
        String(format: "%.2f", self / 1000)
    }

    var shortKilometreString: String {
        String(format: "%.1f", self / 1000)
    }

    /// Metres formatted as miles with one decimal.
    var mileString: String {
        String(format: "%.1f", self / 1_609.34)
    }

    /// Distance to a clue: metres up close, kilometres far out.
    var proximityString: String {
        self < 950 ? "\(Int(self.rounded())) m" : "\(String(format: "%.1f", self / 1000)) km"
    }
}
