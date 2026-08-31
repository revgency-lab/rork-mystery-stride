//
//  ProgressDashboardView.swift
//  MysteryRun
//

import SwiftUI

/// Record tab: the detective's standing, their active streaks, and the shelf of
/// past case files.
struct ProgressDashboardView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        ZStack {
            InkBackground()

            ScrollView {
                VStack(spacing: 20) {
                    RankCrestCard(profile: store.profile, solvedCount: store.solvedCount)

                    StandingsPanel(store: store)

                    pastCases
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .tabBarClearance()
        }
        .navigationTitle("Service Record")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ink, for: .navigationBar)
        .navigationDestination(for: ResolutionReport.self) { report in
            CaseExplainedView(report: report, streak: store.profile.streak)
        }
    }

    @ViewBuilder
    private var pastCases: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                EyebrowLabel(text: "Past case files")
                Rectangle()
                    .fill(Theme.brass.opacity(0.25))
                    .frame(height: 1)
                if !store.history.isEmpty {
                    Text("\(store.history.count)")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
            }

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

// MARK: - Rank crest

/// The hero of the record screen: the detective's badge under a progress ring,
/// mounted on a lit plaster wall.
private struct RankCrestCard: View {
    let profile: DetectiveProfile
    let solvedCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringProgress: Double = 0
    @State private var shimmer: Bool = false

    private var isMaxRank: Bool { profile.nextRank == nil }

    var body: some View {
        VStack(spacing: 0) {
            rankPlaque
                .padding(.top, 20)

            crest
                .padding(.top, 16)

            xpReadout
                .padding(.top, 14)
                .padding(.horizontal, 20)

            footnote
                .padding(.top, 16)
                .padding(.bottom, 20)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .background { wall }
        .clipShape(.rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Theme.brass.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.55), radius: 20, y: 12)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).delay(0.15)) {
                ringProgress = profile.rankProgress
            }
            if !reduceMotion { shimmer = true }
        }
        .onChange(of: profile.rankProgress) { _, newValue in
            withAnimation(.easeOut(duration: 0.8)) { ringProgress = newValue }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    /// Stamped brass nameplate carrying the rank.
    private var rankPlaque: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Theme.brass.opacity(0.5))
                .frame(width: 14, height: 1)
            Text("RANK")
                .font(.system(size: 10, weight: .heavy))
                .kerning(2)
                .foregroundStyle(Theme.brass.opacity(0.75))
            Text(profile.rank.title.uppercased())
                .font(.system(size: 15, weight: .black))
                .kerning(1.4)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Rectangle()
                .fill(Theme.brass.opacity(0.5))
                .frame(width: 14, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background {
            Capsule()
                .fill(Color.black.opacity(0.45))
                .overlay {
                    Capsule().strokeBorder(
                        LinearGradient(
                            colors: [Theme.brass.opacity(0.65), Theme.brassDeep.opacity(0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                }
        }
        .padding(.horizontal, 16)
    }

    /// Progress ring wrapped around the badge art.
    private var crest: some View {
        ZStack {
            // Warm pool of light behind the badge.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.brass.opacity(0.22), .clear],
                        center: .center,
                        startRadius: 4,
                        endRadius: 110
                    )
                )
                .frame(width: 210, height: 210)
                .blur(radius: 6)

            RingTicks()
                .stroke(Theme.brass.opacity(0.16), lineWidth: 1)
                .frame(width: 196, height: 196)

            Circle()
                .stroke(Color.black.opacity(0.55), lineWidth: 11)
                .frame(width: 176, height: 176)

            Circle()
                .trim(from: 0, to: max(ringProgress, 0.005))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Theme.violet,
                            Theme.violet,
                            Theme.brass,
                            Theme.brass
                        ]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 176, height: 176)
                .shadow(color: Theme.brass.opacity(0.45), radius: 8)

            badgeArt
                .frame(width: 128, height: 128)
        }
        .frame(height: 210)
    }

    @ViewBuilder
    private var badgeArt: some View {
        if AppAsset.exists(AppAsset.rankCrest) {
            Image(AppAsset.rankCrest)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .shadow(color: .black.opacity(0.6), radius: 10, y: 6)
                .overlay {
                    // A slow bar of light travelling across the metal.
                    if shimmer {
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.22), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .rotationEffect(.degrees(18))
                        .offset(x: shimmer ? 90 : -90)
                        .blendMode(.plusLighter)
                        .mask {
                            Image(AppAsset.rankCrest)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        }
                        .animation(
                            .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                            value: shimmer
                        )
                        .allowsHitTesting(false)
                    }
                }
        } else {
            CrestFallbackGlyph()
        }
    }

    /// Big XP figure against the next rank's threshold.
    private var xpReadout: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(profile.xp.formatted())
                    .font(.system(size: 27, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())

                if let next = profile.nextRank {
                    Text("/ \(next.threshold.formatted())")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }

                Text("XP")
                    .font(.system(size: 12, weight: .heavy))
                    .kerning(1.2)
                    .foregroundStyle(Theme.brass)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            Text(isMaxRank ? "TOP OF THE LADDER" : "TO NEXT RANK")
                .font(.system(size: 10, weight: .heavy))
                .kerning(2)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// One line of context under the numbers.
    private var footnote: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Theme.brass.opacity(0.2))
                .frame(height: 1)

            Text(footnoteText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            Rectangle()
                .fill(Theme.brass.opacity(0.2))
                .frame(height: 1)
        }
    }

    private var footnoteText: String {
        if let next = profile.nextRank {
            return "\(profile.xpToNextRank.formatted()) XP to \(next.title)"
        }
        return solvedCount == 0
            ? "Nothing left to prove"
            : "\(solvedCount) case\(solvedCount == 1 ? "" : "s") closed"
    }

    private var accessibilitySummary: String {
        var text = "Rank \(profile.rank.title). \(profile.xp) XP."
        if let next = profile.nextRank {
            text += " \(profile.xpToNextRank) XP to \(next.title)."
        } else {
            text += " Highest rank reached."
        }
        return text
    }

    /// Lit plaster wall behind the crest. The texture is an overlay on a colour
    /// anchor so a `.fill` image can't widen the card's layout frame.
    private var wall: some View {
        Theme.inkElevated
            .overlay {
                if AppAsset.exists(AppAsset.plasterTexture) {
                    Image(AppAsset.plasterTexture)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(0.55)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                RadialGradient(
                    colors: [Theme.brass.opacity(0.10), .clear],
                    center: .init(x: 0.5, y: 0.32),
                    startRadius: 10,
                    endRadius: 260
                )
            }
            .overlay {
                LinearGradient(
                    colors: [.clear, Theme.violet.opacity(0.14)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipped()
    }
}

/// Engraved tick marks around the rank ring.
private struct RingTicks: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        var path = Path()
        for index in 0..<60 {
            let isMajor = index.isMultiple(of: 5)
            let length: CGFloat = isMajor ? 7 : 3.5
            let angle = Angle.degrees(Double(index) * 6 - 90).radians
            let start = CGPoint(
                x: center.x + cos(angle) * (outer - length),
                y: center.y + sin(angle) * (outer - length)
            )
            let end = CGPoint(
                x: center.x + cos(angle) * outer,
                y: center.y + sin(angle) * outer
            )
            path.move(to: start)
            path.addLine(to: end)
        }
        return path
    }
}

// MARK: - Standings

/// The three running meters, filed together on one sheet.
private struct StandingsPanel: View {
    let store: GameStore

    var body: some View {
        VStack(spacing: 0) {
            StandingRow(
                glyph: .flame,
                tint: Theme.evidenceRed,
                title: "Daily case streak",
                value: "\(store.profile.streak)",
                unit: store.profile.streak == 1 ? "day" : "days",
                detail: streakDetail,
                progress: min(1, Double(store.profile.streak) / 7)
            )

            PanelDivider()

            StandingRow(
                glyph: .hourglass,
                tint: Theme.brass,
                title: "Weekly case file",
                value: "\(store.weeklySolves)",
                unit: "/ 5",
                detail: weeklyDetail,
                progress: min(1, Double(store.weeklySolves) / 5)
            )

            PanelDivider()

            StandingRow(
                glyph: .bootPrint,
                tint: Theme.violet,
                title: "Ground covered",
                value: store.totalDistance.shortKilometreString,
                unit: "km",
                detail: "Across every investigation you've walked",
                progress: min(1, store.totalDistance / 50_000)
            )
        }
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Theme.inkElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Theme.inkStroke, lineWidth: 1)
                }
        }
    }

    private var streakDetail: String {
        if store.profile.streak == 0 { return "Solve a case today to start a streak" }
        return store.isStreakAtRisk ? "Solve today to keep it alive" : "Kept alive today"
    }

    private var weeklyDetail: String {
        let remaining = max(0, 5 - store.weeklySolves)
        if remaining == 0 { return "Weekly file complete — nice work" }
        return "\(remaining) more case\(remaining == 1 ? "" : "s") to fill this week's file"
    }
}

private struct PanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }
}

private struct StandingRow: View {
    enum Glyph {
        case flame
        case hourglass
        case bootPrint
    }

    let glyph: Glyph
    let tint: Color
    let title: String
    let value: String
    let unit: String
    let detail: String
    let progress: Double

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            medallion

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title.uppercased())
                        .font(.system(size: 12, weight: .heavy))
                        .kerning(1.1)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 4)

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(value)
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                            .contentTransition(.numericText())
                        Text(unit)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .lineLimit(1)
                    .fixedSize()
                }

                EvidenceMeter(progress: progress, tint: tint)

                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(unit). \(detail)")
    }

    /// Drawn mark sitting in a lit brass coin.
    private var medallion: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.12))
            Circle()
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)

            switch glyph {
            case .flame:
                FlameGlyph()
                    .fill(tint.opacity(0.85))
                    .frame(width: 17, height: 17)
                FlameGlyph(isCore: true)
                    .fill(Theme.brass.opacity(0.95))
                    .frame(width: 17, height: 17)
            case .hourglass:
                HourglassSandGlyph(fill: min(1, max(0, progress)))
                    .fill(tint.opacity(0.85))
                    .frame(width: 17, height: 17)
                HourglassGlyph()
                    .stroke(tint, style: .init(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 17, height: 17)
            case .bootPrint:
                BootPrintGlyph()
                    .fill(tint.opacity(0.9))
                    .frame(width: 18, height: 18)
            }
        }
        .frame(width: 38, height: 38)
        .shadow(color: tint.opacity(0.35), radius: 6)
    }
}

// MARK: - History

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
