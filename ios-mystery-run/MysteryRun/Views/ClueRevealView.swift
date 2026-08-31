//
//  ClueRevealView.swift
//  MysteryRun
//

import SwiftUI

/// Full-screen reward beat shown the moment a clue's waypoint is reached.
///
/// Content is sized entirely by what it contains: a one-line fragment centres in
/// the spotlight, a long one scrolls, and the evidence track adapts from four
/// clues to thirty without ever running past the screen edge.
struct ClueRevealView: View {
    let clue: Clue
    let total: Int
    let found: Int
    let clues: [Clue]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var revealed: Bool = false

    /// Keeps line lengths readable on iPad and wide phones.
    private let maxContentWidth: CGFloat = 460

    var body: some View {
        ZStack {
            SpotlightBackdrop()

            GeometryReader { proxy in
                ScrollView {
                    content
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                        .frame(maxWidth: maxContentWidth)
                        .frame(maxWidth: .infinity)
                        // Centres short content, scrolls long content.
                        .frame(minHeight: proxy.size.height, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Continue Investigation") { dismiss() }
                .buttonStyle(BrassButtonStyle())
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .frame(maxWidth: maxContentWidth + 40)
                .frame(maxWidth: .infinity)
                .background {
                    LinearGradient(
                        colors: [.clear, Theme.ink.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if reduceMotion {
                revealed = true
            } else {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.72).delay(0.1)) {
                    revealed = true
                }
            }
        }
    }

    private var content: some View {
        VStack(spacing: 22) {
            EyebrowLabel(text: "Evidence found · Clue \(clue.index)")
                .multilineTextAlignment(.center)

            note

            caption

            VStack(spacing: 12) {
                EvidenceTrackRow(clues: clues)
                progressLine
            }
            .opacity(revealed ? 1 : 0)
        }
    }

    private var note: some View {
        EvidenceNote(fragment: clue.fragment)
            .rotationEffect(.degrees(-1.5))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 54, weight: .ultraLight))
                    .foregroundStyle(Theme.brass.opacity(0.9))
                    .rotationEffect(.degrees(38))
                    .shadow(color: .black.opacity(0.6), radius: 10, y: 6)
                    .offset(x: 10, y: 18)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(.trailing, 12)
            .padding(.bottom, 10)
            .scaleEffect(revealed ? 1 : 0.86)
            .opacity(revealed ? 1 : 0)
    }

    private var caption: some View {
        VStack(spacing: 10) {
            // Icon and title share a baseline at normal sizes and stack once the
            // user scales text up, so a long title never squashes into a column.
            titleBlock

            Text(clue.discovery + ".")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.8), radius: 6)

            if clue.isPivotal {
                Label("Pivotal evidence", systemImage: "star.fill")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Theme.violet)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.violet.opacity(0.16), in: .capsule)
                    .overlay { Capsule().strokeBorder(Theme.violet.opacity(0.5), lineWidth: 1) }
            }
        }
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 14)
    }

    @ViewBuilder
    private var titleBlock: some View {
        let icon = Image(systemName: clue.symbolName)
            .font(.title3)
            .foregroundStyle(Theme.brass)

        let title = Text(clue.title)
            .font(.system(.title2, weight: .bold))
            .foregroundStyle(Theme.textPrimary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .shadow(color: .black.opacity(0.8), radius: 6)

        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 6) {
                icon
                title
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                icon
                title
            }
        }
    }

    /// Falls back to a stacked layout when the count and XP can't share a line.
    private var progressLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                foundLabel
                Rectangle()
                    .fill(Theme.inkStroke)
                    .frame(width: 1, height: 16)
                xpLabel
            }
            VStack(spacing: 6) {
                foundLabel
                xpLabel
            }
        }
    }

    private var foundLabel: some View {
        Text("\(found) of \(total) clues found")
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .monospacedDigit()
            .shadow(color: .black.opacity(0.8), radius: 6)
    }

    private var xpLabel: some View {
        Text("+\(clue.xp) XP")
            .font(.system(.subheadline, weight: .bold))
            .foregroundStyle(Theme.violet)
            .monospacedDigit()
            .shadow(color: .black.opacity(0.9), radius: 6)
    }
}
