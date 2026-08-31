//
//  ProfileView.swift
//  MysteryRun
//

import SwiftUI

/// Profile tab: identity, session preferences, permissions and lifetime stats.
struct ProfileView: View {
    @Environment(GameStore.self) private var store
    @Environment(LocationService.self) private var location

    @State private var showResetConfirmation: Bool = false

    private let distanceOptions: [Double] = [1_200, 1_800, 2_400, 3_200, 4_200]

    var body: some View {
        ZStack {
            InkBackground()

            ScrollView {
                VStack(spacing: 18) {
                    identityCard
                    statsCard
                    preferencesCard
                    permissionCard
                    SceneLabEntry()

                    Button("Reset detective record") {
                        showResetConfirmation = true
                    }
                    .font(.system(.subheadline, weight: .semibold))
                    .tint(Theme.evidenceRed)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .tabBarClearance()
        }
        .navigationTitle("Detective Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.ink, for: .navigationBar)
        .alert("Reset everything?", isPresented: $showResetConfirmation) {
            Button("Reset", role: .destructive) { store.resetEverything() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your rank, XP, streak and every filed case will be erased. This can't be undone.")
        }
    }

    private var identityCard: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Theme.brass.opacity(0.15))
                .frame(width: 66, height: 66)
                .overlay { Circle().strokeBorder(Theme.brass.opacity(0.6), lineWidth: 1.5) }
                .overlay {
                    Image(systemName: "person.bust.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.brass)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(store.profile.rank.title)
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(store.profile.xp) XP · \(store.solvedCount) cases closed")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .inkCard()
    }

    private var statsCard: some View {
        HStack(spacing: 0) {
            MetricBlock(
                symbol: "flame.fill",
                value: "\(store.profile.bestStreak)",
                label: "Best Streak",
                unit: "days"
            )
            Divider().frame(height: 34).overlay(Theme.inkStroke)
            MetricBlock(
                symbol: "folder.fill",
                value: "\(store.profile.casesStarted)",
                label: "Cases Opened"
            )
            Divider().frame(height: 34).overlay(Theme.inkStroke)
            MetricBlock(
                symbol: "shoeprints.fill",
                value: store.totalDistance.shortKilometreString,
                label: "Total",
                unit: "km"
            )
        }
        .padding(.vertical, 16)
        .inkCard()
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            EyebrowLabel(text: "Case preferences")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Route length")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(store.profile.preferredDistance.shortKilometreString) km · \(CaseGenerator.clueCount(for: store.profile.preferredDistance)) clues")
                        .font(.footnote)
                        .foregroundStyle(Theme.brass)
                }
                HStack(spacing: 8) {
                    ForEach(distanceOptions, id: \.self) { option in
                        Button {
                            store.updatePreferences(distance: option)
                        } label: {
                            Text(option.shortKilometreString)
                                .font(.system(.footnote, weight: .semibold))
                                .foregroundStyle(
                                    store.profile.preferredDistance == option
                                    ? Color(red: 0.11, green: 0.08, blue: 0.02)
                                    : Theme.textSecondary
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    store.profile.preferredDistance == option ? Theme.brass : Color.white.opacity(0.05),
                                    in: .rect(cornerRadius: 9)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Longer routes carry more evidence. New cases use this length.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Divider().overlay(Theme.inkStroke)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Discovery radius")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(Int(store.profile.discoveryRadius)) m")
                        .font(.footnote)
                        .foregroundStyle(Theme.brass)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { store.profile.discoveryRadius },
                        set: { store.updatePreferences(radius: $0.rounded()) }
                    ),
                    in: 10...40,
                    step: 5
                )
                .tint(Theme.brass)
                Text("How close you need to get before a clue unlocks. Widen it if GPS is patchy in your area.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Divider().overlay(Theme.inkStroke)

            VStack(alignment: .leading, spacing: 8) {
                Text("Default session type")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Picker("Default session type", selection: Binding(
                    get: { store.profile.preferredMode },
                    set: { store.updatePreferences(mode: $0) }
                )) {
                    ForEach(SessionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(16)
        .inkCard()
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowLabel(text: "Location")
            HStack(spacing: 10) {
                Image(systemName: location.isAuthorized ? "location.fill" : "location.slash.fill")
                    .foregroundStyle(location.isAuthorized ? Theme.brass : Theme.evidenceRed)
                Text(permissionText)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            if !location.isAuthorized {
                Button(location.isDenied ? "Open Settings" : "Allow location access") {
                    if location.isDenied {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } else {
                        location.requestPermission()
                    }
                }
                .font(.system(.caption, weight: .semibold))
                .tint(Theme.brass)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inkCard()
    }

    private var permissionText: String {
        if location.isAuthorized {
            return location.hasRealFix
                ? "Location on. Outdoor cases will route around where you are."
                : "Location on, waiting for a fix."
        }
        if location.isDenied {
            return "Location denied. Indoor cases still work, outdoor ones can't unlock clues."
        }
        return "Location not requested yet."
    }
}
