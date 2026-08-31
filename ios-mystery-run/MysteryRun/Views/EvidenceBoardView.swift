//
//  EvidenceBoardView.swift
//  MysteryRun
//

import SwiftUI

/// Evidence tab: everything gathered on the open case, strung together in the
/// order it turns up on the route.
///
/// Every card sizes to its own content — no fixed heights anywhere — so a
/// three-clue case and a twenty-clue case both read as a finished board, and a
/// long quotation grows the card instead of being cut off.
struct EvidenceBoardView: View {
    @Environment(GameStore.self) private var store
    @State private var selectedClue: Clue?

    var body: some View {
        ZStack {
            InkBackground()

            if let mysteryCase = store.activeCase {
                board(for: mysteryCase)
            } else {
                EmptyBoardState()
            }
        }
        .navigationTitle("Evidence Board")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ink, for: .navigationBar)
        .navigationDestination(for: ResolutionReport.self) { report in
            CaseExplainedView(report: report, streak: store.profile.streak)
        }
        .sheet(item: $selectedClue) { clue in
            ClueDetailSheet(clue: clue)
        }
    }

    @ViewBuilder
    private func board(for mysteryCase: MysteryCase) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                BoardHeader(mysteryCase: mysteryCase)

                if mysteryCase.isSolved {
                    NavigationLink(value: ResolutionReport(mysteryCase: mysteryCase)) {
                        RevealBanner()
                    }
                    .buttonStyle(PressableCardStyle())
                }

                EvidenceThread(clues: mysteryCase.clues) { clue in
                    selectedClue = clue
                }

                if !mysteryCase.isSolved {
                    ClosingNote(remaining: mysteryCase.clues.count - mysteryCase.foundClues.count)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 36)
        }
    }
}

// MARK: - Header

/// Case title and recovery progress, filed on one card.
private struct BoardHeader: View {
    let mysteryCase: MysteryCase

    private var found: Int { mysteryCase.foundClues.count }
    private var total: Int { mysteryCase.clues.count }
    private var progress: Double {
        total > 0 ? Double(found) / Double(total) : 0
    }

    var body: some View {
        VStack(spacing: 12) {
            EyebrowLabel(text: "Case #\(mysteryCase.number)")

            Text(mysteryCase.title)
                .font(.system(.title2, design: .serif, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.72)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                EvidenceMeter(progress: progress, tint: Theme.brass, height: 8)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("EVIDENCE RECOVERED")
                        .font(.system(size: 10, weight: .heavy))
                        .kerning(1.4)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 4)

                    Text("\(found) / \(total)")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(found == total ? Theme.brass : Theme.textPrimary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .inkCard(cornerRadius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Case \(mysteryCase.number), \(mysteryCase.title). \(found) of \(total) pieces of evidence recovered.")
    }
}

// MARK: - Reveal banner

/// Brass call to action shown the moment the last clue lands.
private struct RevealBanner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowing: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("EVERY PIECE IN HAND")
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(1.4)
                    .foregroundStyle(Color(red: 0.11, green: 0.08, blue: 0.02).opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("Reveal the Truth")
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(Color(red: 0.11, green: 0.08, blue: 0.02))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(red: 0.11, green: 0.08, blue: 0.02))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [Theme.brass, Theme.brassDeep], startPoint: .top, endPoint: .bottom)
        }
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
        }
        .shadow(color: Theme.brass.opacity(glowing ? 0.55 : 0.3), radius: glowing ? 20 : 12, y: 6)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                glowing = true
            }
        }
    }
}

// MARK: - Thread

/// The clues themselves, strung on a red investigator's thread in route order.
private struct EvidenceThread: View {
    let clues: [Clue]
    let onSelect: (Clue) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(clues) { clue in
                ThreadRow(
                    clue: clue,
                    isLast: clue.id == clues.last?.id,
                    onSelect: { onSelect(clue) }
                )
            }
        }
    }
}

/// One clue on the thread: a numbered pin in the rail, its card alongside.
private struct ThreadRow: View {
    let clue: Clue
    let isLast: Bool
    let onSelect: () -> Void

    /// Gap under each card that the thread runs through to the next pin.
    private let rowSpacing: CGFloat = 14

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            rail

            Group {
                if clue.isFound {
                    Button(action: onSelect) {
                        RecoveredEvidenceCard(clue: clue)
                    }
                    .buttonStyle(PressableCardStyle())
                } else {
                    SealedEvidenceCard(clue: clue)
                }
            }
            .padding(.bottom, isLast ? 0 : rowSpacing)
        }
    }

    /// Badge pinned at the top, thread falling from it to the next row.
    private var rail: some View {
        VStack(spacing: 0) {
            ClueBadge(index: clue.index, found: clue.isFound, diameter: 28)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)

            if !isLast {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                clue.isFound ? Theme.evidenceRed.opacity(0.75) : Color.white.opacity(0.16),
                                Color.white.opacity(0.10)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 4)
            }
        }
        .frame(width: 28)
    }
}

/// A recovered clue: paper, a stamped heading, the fragment in full.
private struct RecoveredEvidenceCard: View {
    let clue: Clue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading

            Rectangle()
                .fill(Theme.paperInk.opacity(0.16))
                .frame(height: 1)

            Text(clue.fragment)
                .font(.system(.subheadline, design: .serif))
                .italic()
                .lineSpacing(4)
                .foregroundStyle(Theme.paperInk.opacity(0.92))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            PaperSurface()
                .clipShape(.rect(cornerRadius: 14))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.paperInk.opacity(0.16), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            // Strip of tape holding the sheet to the board.
            TapeStrip()
                .padding(.leading, 10)
                .offset(y: -5)
        }
        .shadow(color: .black.opacity(0.5), radius: 10, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Clue \(clue.index), \(clue.title). \(clue.fragment)")
        .accessibilityHint("Opens the full evidence file")
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: clue.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.brassDeep)
                .frame(width: 18)

            Text(clue.title.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .kerning(1.2)
                .foregroundStyle(Theme.paperInk)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            if clue.isPivotal {
                Text("KEY")
                    .font(.system(size: 8, weight: .black))
                    .kerning(1)
                    .foregroundStyle(Theme.violet)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Theme.violet.opacity(0.7), lineWidth: 1)
                    }
                    .fixedSize()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let foundAt = clue.foundAt {
                Text(foundAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.paperInkSoft)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text("OPEN FILE")
                .font(.system(size: 9, weight: .heavy))
                .kerning(1)
                .foregroundStyle(Theme.paperInkSoft)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.paperInkSoft)
        }
    }
}

/// A clue still out on the route. Says nothing about its contents.
private struct SealedEvidenceCard: View {
    let clue: Clue

    var body: some View {
        HStack(spacing: 12) {
            EvidenceSealGlyph()
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text("EVIDENCE \(clue.index) · SEALED")
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(1.2)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("Reach the marker on your route to recover it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.03))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    Theme.inkStroke,
                    style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Evidence \(clue.index), not yet recovered")
    }
}

/// Wax seal drawn in vector: a disc with a pressed ring and a slash.
private struct EvidenceSealGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.evidenceRed.opacity(0.16))
            Circle()
                .strokeBorder(Theme.evidenceRed.opacity(0.45), lineWidth: 1)
            Circle()
                .strokeBorder(Theme.evidenceRed.opacity(0.3), lineWidth: 1)
                .padding(4)
            Rectangle()
                .fill(Theme.evidenceRed.opacity(0.4))
                .frame(width: 1.5, height: 9)
                .rotationEffect(.degrees(38))
        }
        .accessibilityHidden(true)
    }
}

/// Strip of aged tape used to fix a sheet to the board.
private struct TapeStrip: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.34), Color.white.opacity(0.18)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 46, height: 14)
            .overlay {
                Rectangle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
            }
            .rotationEffect(.degrees(-4))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Line under the board while evidence is still missing.
private struct ClosingNote: View {
    let remaining: Int

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Theme.brass.opacity(0.2))
                .frame(height: 1)

            Text("\(remaining) piece\(remaining == 1 ? "" : "s") still out there")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)

            Rectangle()
                .fill(Theme.brass.opacity(0.2))
                .frame(height: 1)
        }
        .padding(.top, 6)
    }
}

// MARK: - Empty state

/// Shown when no case is open: an empty board, not a system placeholder.
private struct EmptyBoardState: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        Theme.inkStroke,
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 6])
                    )
                    .frame(width: 116, height: 92)

                EvidenceSealGlyph()
                    .frame(width: 34, height: 34)
            }

            VStack(spacing: 8) {
                Text("THE BOARD IS BARE")
                    .font(.system(size: 12, weight: .heavy))
                    .kerning(1.6)
                    .foregroundStyle(Theme.brass)

                Text("Open a case from the Case tab. Everything you turn up on the route gets pinned here.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 44)
        }
        .padding(.bottom, 40)
    }
}

// MARK: - Interaction

/// Cards dip slightly on press instead of flashing a system highlight.
private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Detail

/// Tap-through detail for a recovered clue.
private struct ClueDetailSheet: View {
    let clue: Clue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                InkBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        EvidenceNote(fragment: clue.fragment, compact: true)
                            .padding(.top, 8)

                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: clue.symbolName)
                                    .foregroundStyle(Theme.brass)
                                Text(clue.title)
                                    .font(.system(.title3, weight: .bold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(clue.discovery + ".")
                                .font(.callout)
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let foundAt = clue.foundAt {
                            Label(foundAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Clue \(clue.index)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(Theme.brass)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        .preferredColorScheme(.dark)
    }
}
