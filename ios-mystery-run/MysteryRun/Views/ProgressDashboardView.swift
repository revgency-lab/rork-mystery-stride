//
//  ProgressDashboardView.swift
//  MysteryRun
//

import SwiftUI

/// Progress tab: rank, streaks and the shelf of past case files.
struct ProgressDashboardView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        ZStack {
            InkBackground()

            ScrollView {
                VStack(spacing: 18) {
                    RankCard(profile: store.profile)

                    VStack(spacing: 12) {
                        StreakRow(
                            symbol: "flame.fill",
                            tint: Theme.evidenceRed,
                            title: "Daily case streak",
                            detail: store.profile.streak == 0
                                ? "Solve a case today to start a streak"
                                : (store.isStreakAtRisk ? "Solve today to keep it alive" : "Kept alive today"),
                            value: "\(store.profile.streak)",
                            unit: store.profile.streak == 1 ? "day" : "days",
                            progress: min(1, Double(store.profile.streak) / 7)
                        )

                        StreakRow(
                            symbol: "folder.fill",
                            tint: Theme.brass,
                            title: "Weekly case file",
                            detail: "Cases closed in the last 7 days",
                            value: "\(store.weeklySolves)",
                            unit: "/ 5",
                            progress: min(1, Double(store.weeklySolves) / 5)
                        )

                        StreakRow(
                            symbol: "shoeprints.fill",
                            tint: Theme.violet,
                            title: "Ground covered",
                            detail: "Total distance across every investigation",
                            value: store.totalDistance.shortKilometreString,
                            unit: "km",
                            progress: min(1, store.totalDistance / 50_000)
                        )
                    }

                    pastCases
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Detective Progress")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ink, for: .navigationBar)
        .navigationDestination(for: ResolutionReport.self) { report in
            CaseExplainedView(report: report, streak: store.profile.streak)
        }
    }

    @ViewBuilder
    private var pastCases: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowLabel(text: "Past case files")

            if store.history.isEmpty {
                Text("No files yet. Close your first case and it lands here.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                ForEach(store.history) { record in
                    NavigationLink(value: ResolutionReport(record: record)) {
                        CaseFileRow(record: record)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Rank

private struct RankCard: View {
    let profile: DetectiveProfile

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: profile.rankProgress)
                    .stroke(
                        AngularGradient(
                            colors: [Theme.violet, Theme.brass, Theme.brass],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: profile.rankProgress)

                VStack(spacing: 2) {
                    Image(systemName: "person.bust.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.brass)
                    Text("\(profile.xp)")
                        .font(.system(.title3, weight: .black))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text("XP")
                        .font(.system(size: 10, weight: .bold))
                        .kerning(1.4)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 150, height: 150)
            .padding(.top, 20)

            VStack(spacing: 5) {
                EyebrowLabel(text: "Rank")
                Text(profile.rank.title)
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                if let next = profile.nextRank {
                    Text("\(profile.xpToNextRank) XP to \(next.title)")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Top of the ladder — nothing left to prove.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .inkCard()
        .accessibilityElement(children: .combine)
    }
}

private struct StreakRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let value: String
    let unit: String
    let progress: Double

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: .circle)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(value)
                            .font(.system(.subheadline, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        Text(unit)
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                ProgressView(value: progress)
                    .tint(tint)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14)
        .inkCard(cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(unit). \(detail)")
    }
}

private struct CaseFileRow: View {
    let record: CaseRecord

    var body: some View {
        HStack(spacing: 14) {
            CasePhoto(assetName: record.photoAsset, height: 62, showsClip: false)
                .frame(width: 78)

            VStack(alignment: .leading, spacing: 4) {
                Text("CASE #\(record.number)")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(Theme.textSecondary)
                Text(record.title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(record.distance.shortKilometreString + " km", systemImage: record.mode.symbolName)
                    Text("·")
                    Text(record.closedAt.formatted(date: .abbreviated, time: .omitted))
                }
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                Text(record.solved ? "SOLVED" : "PARTIAL")
                    .font(.system(size: 9, weight: .black))
                    .kerning(0.8)
                    .foregroundStyle(record.solved ? Theme.brass : Theme.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder((record.solved ? Theme.brass : Theme.textSecondary).opacity(0.6), lineWidth: 1)
                    }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .inkCard(cornerRadius: 16)
    }
}
