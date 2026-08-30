//
//  SessionSummaryView.swift
//  MysteryRun
//

import SwiftUI

/// Post-session investigation report: distance, time, evidence and XP.
struct SessionSummaryView: View {
    let record: CaseRecord
    let mysteryCase: MysteryCase
    let onFinish: () -> Void

    @Environment(GameStore.self) private var store
    @State private var path: [ResolutionReport] = []

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                InkBackground()

                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 6) {
                            Text("INVESTIGATION REPORT")
                                .font(.system(.headline, design: .serif, weight: .black))
                                .kerning(1.6)
                                .foregroundStyle(Theme.paperInk)
                            Text("Case #\(record.number): \(record.title)")
                                .font(.system(.footnote, design: .serif))
                                .foregroundStyle(Theme.paperInkSoft)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 24)
                        .padding(.horizontal, 20)

                        HStack(spacing: 0) {
                            MetricBlock(
                                symbol: "shoeprints.fill",
                                value: record.distance.kilometreString,
                                label: "Distance",
                                unit: "km",
                                onPaper: true
                            )
                            Divider().frame(height: 36).overlay(Theme.paperInk.opacity(0.2))
                            MetricBlock(
                                symbol: "clock.fill",
                                value: record.duration.clockString,
                                label: "Time",
                                onPaper: true
                            )
                            Divider().frame(height: 36).overlay(Theme.paperInk.opacity(0.2))
                            MetricBlock(
                                symbol: "speedometer",
                                value: record.averagePace,
                                label: record.mode == .walk ? "Pace" : "Avg Pace",
                                unit: "/km",
                                onPaper: true
                            )
                        }
                        .padding(.vertical, 20)
                        .padding(.horizontal, 8)

                        Rectangle()
                            .fill(Theme.paperInk.opacity(0.22))
                            .frame(height: 1)
                            .padding(.horizontal, 20)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("CLUES COLLECTED")
                                .font(.system(.caption, weight: .bold))
                                .kerning(1.4)
                                .foregroundStyle(Theme.paperInkSoft)

                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                                ForEach(record.clues) { clue in
                                    VStack(spacing: 6) {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(clue.isFound ? Theme.brass.opacity(0.22) : Theme.paperInk.opacity(0.06))
                                            .frame(height: 52)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .strokeBorder(
                                                        clue.isFound ? Theme.brassDeep.opacity(0.8) : Theme.paperInk.opacity(0.18),
                                                        lineWidth: 1
                                                    )
                                            }
                                            .overlay {
                                                Image(systemName: clue.symbolName)
                                                    .font(.system(size: 18))
                                                    .foregroundStyle(clue.isFound ? Theme.brassDeep : Theme.paperInk.opacity(0.25))
                                            }
                                        Text(clue.isFound ? "+\(clue.xp) XP" : "Missed")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(clue.isFound ? Theme.paperInkSoft : Theme.paperInk.opacity(0.3))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 18)

                        if let pivotal = record.clues.first(where: { $0.isFound && $0.isPivotal }) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(Theme.violet)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("PIVOTAL CLUE FOUND")
                                        .font(.system(.caption, weight: .black))
                                        .kerning(1)
                                        .foregroundStyle(Theme.violet)
                                    Text("The \(pivotal.title.lowercased()) was essential to closing this case.")
                                        .font(.footnote)
                                        .foregroundStyle(Theme.paperInk.opacity(0.8))
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.violet.opacity(0.10), in: .rect(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Theme.violet.opacity(0.35), lineWidth: 1)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 18)
                        }

                        VStack(spacing: 4) {
                            Text("TOTAL XP EARNED")
                                .font(.system(.caption, weight: .bold))
                                .kerning(1.4)
                                .foregroundStyle(Theme.paperInkSoft)
                            Text("\(record.xpEarned)")
                                .font(.system(size: 44, weight: .black))
                                .monospacedDigit()
                                .foregroundStyle(Theme.violet)
                        }
                        .padding(.top, 22)
                        .padding(.bottom, 26)
                    }
                    .frame(maxWidth: .infinity)
                    .dossierSheet()
                    .overlay(alignment: .topTrailing) {
                        if record.solved {
                            RubberStamp(text: "SOLVED", angle: 10)
                                .padding(.trailing, 14)
                                .padding(.top, 12)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Session Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.ink, for: .navigationBar)
            .navigationDestination(for: ResolutionReport.self) { report in
                CaseExplainedView(report: report, streak: store.profile.streak, onClose: onFinish)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if record.solved {
                        Button("Read How It Happened") {
                            path.append(ResolutionReport(mysteryCase: mysteryCase, xpEarned: record.xpEarned))
                        }
                        .buttonStyle(BrassButtonStyle())
                    }

                    Button(record.solved ? "Back to HQ" : "Close the File", action: onFinish)
                        .buttonStyle(VioletOutlineButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background {
                    LinearGradient(colors: [Theme.ink.opacity(0), Theme.ink], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                }
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.success, trigger: record.id)
    }
}
