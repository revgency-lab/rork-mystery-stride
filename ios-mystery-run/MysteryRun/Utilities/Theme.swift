//
//  Theme.swift
//  MysteryRun
//

import SwiftUI
import UIKit

/// Names of the bundled noir art assets.
enum AppAsset {
    static let paperTexture = "aged_manila_paper_texture"
    static let deskSpotlight = "detective_desk_spotlight"
    static let rankCrest = "detective_badge_fedora"
    static let plasterTexture = "noir_plaster_texture_bg"

    /// True when the named art actually shipped in the bundle, so every screen
    /// can fall back to drawn artwork instead of rendering an empty frame.
    static func exists(_ name: String) -> Bool {
        UIImage(named: name) != nil
    }
}

/// Central noir case-file palette and shared metrics used across every screen.
enum Theme {
    // Dark canvas
    static let ink = Color(red: 0.043, green: 0.051, blue: 0.078)
    static let inkElevated = Color(red: 0.082, green: 0.102, blue: 0.149)
    static let inkStroke = Color.white.opacity(0.08)

    // Aged paper
    static let paper = Color(red: 0.937, green: 0.890, blue: 0.784)
    static let paperShade = Color(red: 0.851, green: 0.796, blue: 0.678)
    static let paperInk = Color(red: 0.169, green: 0.141, blue: 0.098)
    static let paperInkSoft = Color(red: 0.420, green: 0.369, blue: 0.282)

    // Accents
    static let brass = Color(red: 0.878, green: 0.639, blue: 0.180)
    static let brassDeep = Color(red: 0.706, green: 0.478, blue: 0.098)
    static let evidenceRed = Color(red: 0.753, green: 0.224, blue: 0.169)
    static let violet = Color(red: 0.424, green: 0.294, blue: 0.820)

    // Text on dark
    static let textPrimary = Color(red: 0.957, green: 0.937, blue: 0.894)
    static let textSecondary = Color(red: 0.604, green: 0.631, blue: 0.698)

    static let cardRadius: CGFloat = 18
}

/// Vignetted ink background used behind every dark screen.
struct InkBackground: View {
    var body: some View {
        ZStack {
            Theme.ink
            RadialGradient(
                colors: [Theme.brass.opacity(0.10), .clear],
                center: .init(x: 0.5, y: 0.08),
                startRadius: 8,
                endRadius: 420
            )
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.55)],
                center: .center,
                startRadius: 180,
                endRadius: 620
            )
        }
        .ignoresSafeArea()
    }
}

/// Aged dossier paper surface. Uses the generated paper texture when bundled and
/// falls back to a procedural grain so the UI never depends on the asset.
struct PaperSurface: View {
    var body: some View {
        // The flat colour is the size anchor. The texture is measured against the
        // real card size and clipped inside its own layer: a `.fill` image reports
        // a frame wider and taller than it was given, and because it also carries a
        // blend mode it composites into the parent layer, escaping an outer clip and
        // painting over whatever sits next to the card.
        Rectangle()
            .fill(Theme.paper)
            .overlay { texture }
            .overlay {
                LinearGradient(
                    colors: [Color.black.opacity(0.10), .clear, Color.black.opacity(0.14)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.multiply)
            }
            .compositingGroup()
            .clipped()
            .allowsHitTesting(false)
    }

    private var texture: some View {
        GeometryReader { geometry in
            if UIImage(named: AppAsset.paperTexture) != nil {
                Image(AppAsset.paperTexture)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .opacity(0.85)
                    .blendMode(.multiply)
            } else {
                PaperGrain()
            }
        }
        .allowsHitTesting(false)
    }
}

/// Deterministic speckled grain drawn with Canvas — the procedural paper fallback.
struct PaperGrain: View {
    var body: some View {
        Canvas { context, size in
            var generator = SeededGenerator(seed: 42)
            let count = Int(size.width * size.height / 900)
            for _ in 0..<max(count, 40) {
                let x = Double.random(in: 0...size.width, using: &generator)
                let y = Double.random(in: 0...size.height, using: &generator)
                let r = Double.random(in: 0.4...1.9, using: &generator)
                let alpha = Double.random(in: 0.02...0.09, using: &generator)
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                    with: .color(Theme.paperInk.opacity(alpha))
                )
            }
        }
        .allowsHitTesting(false)
    }
}

/// Small reproducible RNG so procedural texture and case generation stay stable.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        if state == 0 { state = 0x9E3779B97F4A7C15 }
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

extension View {
    /// Wraps content in a torn dossier sheet with taped corners and a drop shadow.
    func dossierSheet(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        self
            .background {
                PaperSurface()
                    .clipShape(.rect(cornerRadius: cornerRadius))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.paperInk.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.6), radius: 18, x: 0, y: 10)
    }

    /// Dark elevated card used for map panels and stat blocks.
    func inkCard(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        self
            .background(Theme.inkElevated, in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.inkStroke, lineWidth: 1)
            }
    }
}

/// Rotated rubber-stamp mark ("CONFIDENTIAL", "CASE CLOSED").
struct RubberStamp: View {
    let text: String
    var color: Color = Theme.evidenceRed
    var angle: Double = -12

    var body: some View {
        Text(text)
            .font(.system(.title3, weight: .heavy))
            .kerning(3)
            .foregroundStyle(color.opacity(0.78))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(color.opacity(0.7), lineWidth: 3)
            }
            .rotationEffect(.degrees(angle))
            .opacity(0.9)
            .accessibilityLabel(text)
    }
}

/// Uppercase brass eyebrow label.
struct EyebrowLabel: View {
    let text: String
    var color: Color = Theme.brass

    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption, weight: .bold))
            .kerning(1.8)
            .foregroundStyle(color)
    }
}

/// Primary brass action button.
struct BrassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, weight: .bold))
            .foregroundStyle(Color(red: 0.11, green: 0.08, blue: 0.02))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                LinearGradient(
                    colors: [Theme.brass, Theme.brassDeep],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipShape(.rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
            }
            .shadow(color: Theme.brass.opacity(configuration.isPressed ? 0.15 : 0.35), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Secondary outlined button in investigator violet.
struct VioletOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, weight: .semibold))
            .foregroundStyle(Theme.violet)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.violet.opacity(configuration.isPressed ? 0.18 : 0.08), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.violet.opacity(0.7), lineWidth: 1.5)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
