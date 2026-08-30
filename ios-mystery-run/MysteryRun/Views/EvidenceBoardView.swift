//
//  EvidenceBoardView.swift
//  MysteryRun
//

import SwiftUI

/// Evidence tab: the corkboard of everything gathered on the open case.
struct EvidenceBoardView: View {
    @Environment(GameStore.self) private var store
    @State private var selectedClue: Clue?

    var body: some View {
        ZStack {
            InkBackground()

            if let mysteryCase = store.activeCase {
                board(for: mysteryCase)
            } else {
                ContentUnavailableView(
                    "No open case",
                    systemImage: "square.grid.2x2",
                    description: Text("Open a case from the Case tab and the evidence you find will be pinned here.")
                )
                .foregroundStyle(Theme.textSecondary)
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
        let found = mysteryCase.foundClues.count

        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    EyebrowLabel(text: "Case #\(mysteryCase.number)")
                    Text(mysteryCase.title)
                        .font(.system(.title2, design: .serif, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)

                    ProgressView(value: Double(found), total: Double(mysteryCase.clues.count))
                        .tint(Theme.brass)
                        .padding(.horizontal, 40)
                        .padding(.top, 6)

                    Text("\(found) of \(mysteryCase.clues.count) pieces recovered")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, 6)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(mysteryCase.clues) { clue in
                        Button {
                            if clue.isFound { selectedClue = clue }
                        } label: {
                            PinnedEvidenceCard(clue: clue)
                        }
                        .buttonStyle(.plain)
                        .disabled(!clue.isFound)
                    }
                }

                if mysteryCase.isSolved {
                    NavigationLink(value: ResolutionReport(mysteryCase: mysteryCase)) {
                        HStack {
                            Text("Reveal the Truth")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(.headline, weight: .bold))
                        .foregroundStyle(Color(red: 0.11, green: 0.08, blue: 0.02))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .background {
                            LinearGradient(colors: [Theme.brass, Theme.brassDeep], startPoint: .top, endPoint: .bottom)
                        }
                        .clipShape(.rect(cornerRadius: 14))
                        .shadow(color: Theme.brass.opacity(0.35), radius: 14, y: 6)
                    }
                    .padding(.top, 4)
                } else {
                    Text("The pieces don't connect yet. Recover the rest of the evidence on your route.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
}

/// One clue pinned to the board — a paper card when found, a silhouette when not.
private struct PinnedEvidenceCard: View {
    let clue: Clue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ClueBadge(index: clue.index, found: clue.isFound, diameter: 24)
                Spacer()
                Image(systemName: clue.isFound ? clue.symbolName : "questionmark")
                    .font(.system(size: 18))
                    .foregroundStyle(clue.isFound ? Theme.brassDeep : Theme.textSecondary.opacity(0.4))
            }

            if clue.isFound {
                Text(clue.fragment)
                    .font(.system(.caption, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.paperInk.opacity(0.85))
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Text(clue.title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1)
                    .foregroundStyle(Theme.paperInkSoft)
            } else {
                Text("Not yet recovered")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                Spacer(minLength: 0)
                Text("CLUE \(clue.index)")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1)
                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
            }
        }
        .padding(12)
        .frame(height: 152, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .background {
            if clue.isFound {
                PaperSurface().clipShape(.rect(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12).fill(Theme.inkElevated)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    clue.isFound ? Theme.paperInk.opacity(0.15) : Theme.inkStroke,
                    style: StrokeStyle(lineWidth: 1, dash: clue.isFound ? [] : [4, 4])
                )
        }
        .overlay(alignment: .top) {
            if clue.isFound {
                Circle()
                    .fill(Theme.evidenceRed)
                    .frame(width: 10, height: 10)
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
                    .offset(y: -4)
            }
        }
        .rotationEffect(.degrees(clue.isFound ? (clue.index % 2 == 0 ? 1.2 : -1.2) : 0))
        .shadow(color: .black.opacity(clue.isFound ? 0.5 : 0), radius: 10, y: 6)
    }
}

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
                            }
                            Text(clue.discovery + ".")
                                .font(.callout)
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
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
