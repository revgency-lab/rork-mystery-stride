//
//  ClueRevealView.swift
//  MysteryRun
//

import SwiftUI

/// Full-screen reward beat shown the moment a clue's waypoint is reached.
struct ClueRevealView: View {
    let clue: Clue
    let total: Int
    let found: Int
    let clues: [Clue]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed: Bool = false

    var body: some View {
        ZStack {
            SpotlightBackdrop()

            ScrollView {
                VStack(spacing: 20) {
                    EyebrowLabel(text: "Evidence found · Clue \(clue.index)")
                        .padding(.top, 8)

                    ZStack(alignment: .bottomTrailing) {
                        EvidenceNote(fragment: clue.fragment)
                            .rotationEffect(.degrees(-1.5))

                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 62, weight: .ultraLight))
                            .foregroundStyle(Theme.brass.opacity(0.9))
                            .rotationEffect(.degrees(38))
                            .shadow(color: .black.opacity(0.6), radius: 10, y: 6)
                            .offset(x: 14, y: 22)
                            .accessibilityHidden(true)
                    }
                    .scaleEffect(revealed ? 1 : 0.86)
                    .opacity(revealed ? 1 : 0)
                    .padding(.horizontal, 6)
                    .padding(.top, 6)

                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: clue.symbolName)
                                .foregroundStyle(Theme.brass)
                            Text(clue.title)
                                .font(.system(.title, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                        }

                        Text(clue.discovery + ".")
                            .font(.callout)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 12)

                        if clue.isPivotal {
                            Label("Pivotal evidence", systemImage: "star.fill")
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(Theme.violet)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Theme.violet.opacity(0.14), in: .capsule)
                                .overlay { Capsule().strokeBorder(Theme.violet.opacity(0.5), lineWidth: 1) }
                        }
                    }
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 14)

                    EvidenceTrackRow(clues: clues)
                        .padding(.top, 4)

                    HStack(spacing: 14) {
                        Text("\(found) of \(total) clues found")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Rectangle()
                            .fill(Theme.inkStroke)
                            .frame(width: 1, height: 16)
                        Text("+\(clue.xp) XP")
                            .font(.system(.subheadline, weight: .bold))
                            .foregroundStyle(Theme.violet)
                    }
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Continue Investigation") { dismiss() }
                .buttonStyle(BrassButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
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
}
