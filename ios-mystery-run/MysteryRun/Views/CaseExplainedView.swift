//
//  CaseExplainedView.swift
//  MysteryRun
//

import SwiftUI

/// Everything needed to render the narrated resolution, from a live case or a filed record.
nonisolated struct ResolutionReport: Identifiable, Hashable, Sendable {
    let id: UUID
    let number: Int
    let title: String
    let conclusion: String
    let clues: [Clue]
    let xpEarned: Int?

    init(mysteryCase: MysteryCase, xpEarned: Int? = nil) {
        id = mysteryCase.id
        number = mysteryCase.number
        title = mysteryCase.title
        conclusion = mysteryCase.conclusion
        clues = mysteryCase.clues
        self.xpEarned = xpEarned
    }

    init(record: CaseRecord) {
        id = record.id
        number = record.number
        title = record.title
        conclusion = record.conclusion
        clues = record.clues
        xpEarned = record.xpEarned
    }

    var foundClues: [Clue] { clues.filter(\.isFound) }
    var isComplete: Bool { foundClues.count == clues.count }

    /// Plain-text report used for sharing.
    var shareText: String {
        var lines = ["Case #\(number): \(title)", ""]
        for (index, clue) in foundClues.enumerated() {
            lines.append("\(index + 1). \(clue.deduction)")
        }
        lines.append("")
        lines.append(conclusion)
        lines.append("")
        lines.append("Solved on foot with Mystery Run.")
        return lines.joined(separator: "\n")
    }
}

/// The payoff screen: a typed detective report explaining how each clue solved the case.
struct CaseExplainedView: View {
    let report: ResolutionReport
    var streak: Int?
    var onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var appeared: Bool = false

    var body: some View {
        ZStack {
            InkBackground()

            ScrollView {
                VStack(spacing: 0) {
                    header

                    Rectangle()
                        .fill(Theme.paperInk.opacity(0.25))
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(report.foundClues.enumerated()), id: \.element.id) { index, clue in
                            DeductionRow(
                                step: index + 1,
                                clue: clue,
                                isLast: index == report.foundClues.count - 1
                            )
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 12)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.07),
                                value: appeared
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                    if !report.isComplete {
                        Text("\(report.clues.count - report.foundClues.count) piece(s) of evidence were never recovered. The file closes on what you found.")
                            .font(.system(.footnote, design: .serif))
                            .italic()
                            .foregroundStyle(Theme.paperInkSoft)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                    }

                    Rectangle()
                        .fill(Theme.paperInk.opacity(0.25))
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)

                    conclusionBlock

                    rewardRow
                        .padding(.bottom, 26)
                }
                .frame(maxWidth: .infinity)
                .dossierSheet()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("How It Happened")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ink, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button("Close the Case") {
                    if let onClose { onClose() } else { dismiss() }
                }
                .buttonStyle(BrassButtonStyle())

                ShareLink(item: report.shareText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(Theme.violet)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.violet.opacity(0.10), in: .rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Theme.violet.opacity(0.7), lineWidth: 1.5)
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background {
                LinearGradient(colors: [Theme.ink.opacity(0), Theme.ink], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
        }
        .onAppear { appeared = true }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("HOW IT HAPPENED")
                .font(.system(.title2, design: .serif, weight: .black))
                .kerning(2)
                .foregroundStyle(Theme.paperInk)

            Text("Detective Report — Case #\(report.number): \(report.title)")
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(Theme.paperInkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 26)
        .padding(.horizontal, 24)
        .overlay(alignment: .topTrailing) {
            Image(systemName: "paperclip")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.brassDeep)
                .rotationEffect(.degrees(16))
                .offset(x: -14, y: -16)
                .accessibilityHidden(true)
        }
    }

    private var conclusionBlock: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(report.conclusion)
                .font(.system(.title3, design: .serif, weight: .bold))
                .kerning(1)
                .foregroundStyle(Theme.brassDeep)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 30)

            if report.isComplete {
                RubberStamp(text: "CASE CLOSED", angle: -8)
                    .padding(.trailing, 16)
            }
        }
    }

    private var rewardRow: some View {
        HStack(spacing: 18) {
            if let xp = report.xpEarned {
                Label {
                    Text("+\(xp) XP earned")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.paperInk)
                } icon: {
                    Image(systemName: "star.circle.fill")
                        .foregroundStyle(Theme.violet)
                }
            }
            if let streak, streak > 0 {
                Label {
                    Text("Streak: \(streak) day\(streak == 1 ? "" : "s")")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.paperInk)
                } icon: {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Theme.evidenceRed)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}

/// One numbered deduction, tied to the evidence that produced it.
private struct DeductionRow: View {
    let step: Int
    let clue: Clue
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ClueBadge(index: step, diameter: 28)
                if !isLast {
                    Rectangle()
                        .fill(Theme.evidenceRed.opacity(0.45))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 4)
                }
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: clue.symbolName)
                        .font(.footnote)
                        .foregroundStyle(Theme.brassDeep)
                    Text(clue.title.uppercased())
                        .font(.system(.caption, weight: .bold))
                        .kerning(1.2)
                        .foregroundStyle(Theme.paperInkSoft)
                    if clue.isMisleading {
                        Text("RED HERRING")
                            .font(.system(size: 9, weight: .black))
                            .kerning(0.8)
                            .foregroundStyle(Theme.evidenceRed)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay {
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(Theme.evidenceRed.opacity(0.6), lineWidth: 1)
                            }
                    }
                }

                Text(clue.deduction)
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(Theme.paperInk)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 22)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(step). \(clue.title). \(clue.deduction)")
    }
}
