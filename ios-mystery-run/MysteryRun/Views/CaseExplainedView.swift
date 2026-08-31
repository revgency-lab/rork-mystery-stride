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
    /// The brief exactly as it was handed over before the run started.
    let premise: String?
    /// The narrated account of what actually happened.
    let solution: String?
    let locationName: String?
    let conclusion: String
    let clues: [Clue]
    let xpEarned: Int?

    init(mysteryCase: MysteryCase, xpEarned: Int? = nil) {
        id = mysteryCase.id
        number = mysteryCase.number
        title = mysteryCase.title
        premise = mysteryCase.premise.nilIfBlank
        solution = mysteryCase.solution?.nilIfBlank
        locationName = mysteryCase.locationName.nilIfBlank
        conclusion = mysteryCase.conclusion
        clues = mysteryCase.clues
        self.xpEarned = xpEarned
    }

    init(record: CaseRecord) {
        id = record.id
        number = record.number
        title = record.title
        premise = record.premise?.nilIfBlank
        solution = record.solution?.nilIfBlank
        locationName = record.locationName?.nilIfBlank
        conclusion = record.conclusion
        clues = record.clues
        xpEarned = record.xpEarned
    }

    var foundClues: [Clue] { clues.filter(\.isFound) }
    var missingCount: Int { clues.count - foundClues.count }
    var isComplete: Bool { missingCount == 0 }

    /// Plain-text report used for sharing.
    var shareText: String {
        var lines = ["Case #\(number): \(title)"]
        if let premise {
            lines.append("")
            lines.append(premise)
        }
        lines.append("")
        lines.append("THE EVIDENCE")
        for (index, clue) in foundClues.enumerated() {
            lines.append("\(index + 1). \(clue.title) — \(clue.deduction)")
        }
        if let solution {
            lines.append("")
            lines.append("WHAT HAPPENED")
            lines.append(solution)
        }
        lines.append("")
        lines.append(conclusion)
        lines.append("")
        lines.append("Solved on foot with Mystery Run.")
        return lines.joined(separator: "\n")
    }
}

/// The payoff screen: a typed detective report that reads start to finish — the
/// original brief, the evidence in the order it was recovered, then the full
/// account of what actually happened.
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

                    if let premise = report.premise {
                        DossierRule()
                            .padding(.top, 14)

                        SectionLabel(text: "THE BRIEF", systemImage: "envelope.open.fill")
                            .padding(.top, 16)

                        briefBlock(premise)
                    }

                    DossierRule()
                        .padding(.top, 18)

                    SectionLabel(text: "WHAT YOU RECOVERED", systemImage: "magnifyingglass")
                        .padding(.top, 16)

                    evidenceList

                    if !report.isComplete {
                        missingNote
                    }

                    if let solution = report.solution {
                        DossierRule()
                            .padding(.top, 18)

                        SectionLabel(text: "WHAT HAPPENED", systemImage: "text.book.closed.fill")
                            .padding(.top, 16)

                        solutionBlock(solution)
                    }

                    DossierRule()
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
        // Pushed inside a tab the bar is still on screen; presented from the
        // session summary it is not, and this collapses to nothing.
        .tabBarClearance()
        .onAppear { appeared = true }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 8) {
            Text("HOW IT HAPPENED")
                .font(.system(.title2, design: .serif, weight: .black))
                .kerning(2)
                .foregroundStyle(Theme.paperInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("Detective Report — Case #\(report.number): \(report.title)")
                .font(.system(.footnote, design: .serif))
                .foregroundStyle(Theme.paperInkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let locationName = report.locationName {
                Text(locationName.uppercased())
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(1.6)
                    .foregroundStyle(Theme.brassDeep)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.top, 26)
        .padding(.horizontal, 44)
        .overlay(alignment: .topTrailing) {
            Image(systemName: "paperclip")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.brassDeep)
                .rotationEffect(.degrees(16))
                .offset(x: -14, y: -16)
                .accessibilityHidden(true)
        }
    }

    /// The case as it was originally posed. Reprinted verbatim so the ending has
    /// something to actually resolve.
    private func briefBlock(_ premise: String) -> some View {
        Text(premise)
            .font(.system(.callout, design: .serif))
            .italic()
            .foregroundStyle(Theme.paperInk)
            .lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .background(Theme.brassDeep.opacity(0.07), in: .rect(cornerRadius: 8))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Theme.brassDeep.opacity(0.55))
                    .frame(width: 3)
                    .clipShape(.rect(cornerRadius: 1.5))
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
    }

    private var evidenceList: some View {
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
        .padding(.top, 16)
    }

    private var missingNote: some View {
        Text("\(report.missingCount) piece\(report.missingCount == 1 ? "" : "s") of evidence were never recovered. The account below fills in what you didn't reach.")
            .font(.system(.footnote, design: .serif))
            .italic()
            .foregroundStyle(Theme.paperInkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.top, 10)
    }

    /// The whole night, told straight through. Everything above is a fragment of
    /// this paragraph.
    private func solutionBlock(_ solution: String) -> some View {
        Text(solution)
            .font(.system(.callout, design: .serif))
            .foregroundStyle(Theme.paperInk)
            .lineSpacing(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.25), value: appeared)
    }

    private var conclusionBlock: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(report.conclusion)
                .font(.system(.title3, design: .serif, weight: .bold))
                .kerning(1)
                .foregroundStyle(Theme.brassDeep)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
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

/// Hairline divider between filed sections.
private struct DossierRule: View {
    var body: some View {
        Rectangle()
            .fill(Theme.paperInk.opacity(0.25))
            .frame(height: 1)
            .padding(.horizontal, 20)
    }
}

/// Typed section heading inside the dossier.
private struct SectionLabel: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .heavy))
                .kerning(1.8)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.brassDeep)
        .padding(.horizontal, 20)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One numbered deduction, printed with the evidence that produced it: what the
/// detective actually read in the field, where it turned up, and what it proved.
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
                titleRow

                // The evidence in its own words — the same line the detective
                // read when they found it, so the deduction has a source.
                Text("“\(clue.fragment)”")
                    .font(.system(.footnote, design: .serif))
                    .italic()
                    .foregroundStyle(Theme.paperInk.opacity(0.85))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.paperInk.opacity(0.28))
                            .frame(width: 2)
                    }

                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.top, 1)
                    Text(clue.discovery)
                        .font(.system(size: 11, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.paperInkSoft)

                VStack(alignment: .leading, spacing: 3) {
                    Text("WHAT IT PROVED")
                        .font(.system(size: 9, weight: .heavy))
                        .kerning(1.2)
                        .foregroundStyle(Theme.brassDeep)

                    Text(clue.deduction)
                        .font(.system(.callout, design: .serif))
                        .foregroundStyle(Theme.paperInk)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
            .padding(.bottom, isLast ? 0 : 24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Step \(step). \(clue.title). It read: \(clue.fragment). Found \(clue.discovery). It proved: \(clue.deduction)"
        )
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Image(systemName: clue.symbolName)
                .font(.footnote)
                .foregroundStyle(Theme.brassDeep)
            Text(clue.title.uppercased())
                .font(.system(.caption, weight: .bold))
                .kerning(1.2)
                .foregroundStyle(Theme.paperInkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if clue.isMisleading {
                Text("RED HERRING")
                    .font(.system(size: 9, weight: .black))
                    .kerning(0.8)
                    .foregroundStyle(Theme.evidenceRed)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Theme.evidenceRed.opacity(0.6), lineWidth: 1)
                    }
            }
            Spacer(minLength: 0)
        }
    }
}

nonisolated extension String {
    /// Treats whitespace-only strings as absent, so blank saved fields don't
    /// render an empty section.
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
