//
//  ContentView.swift
//  MysteryRun
//

import SwiftUI

/// Root shell. The system tab bar is hidden and replaced with `DetectiveTabBar`
/// so the palette holds all the way to the bottom edge; `TabView` is kept
/// underneath for its lazy loading and per-tab navigation state.
struct ContentView: View {
    @Environment(InvestigationEngine.self) private var engine
    @State private var selection: AppTab = .caseFile

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { CaseBriefingView() }
                .tag(AppTab.caseFile)
                .toolbar(.hidden, for: .tabBar)

            NavigationStack { EvidenceBoardView() }
                .tag(AppTab.evidence)
                .toolbar(.hidden, for: .tabBar)

            NavigationStack { ProgressDashboardView() }
                .tag(AppTab.progress)
                .toolbar(.hidden, for: .tabBar)

            NavigationStack { ProfileView() }
                .tag(AppTab.profile)
                .toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DetectiveTabBar(
                selection: $selection,
                evidenceBadge: evidenceBadge,
                isLive: engine.isLive
            )
        }
        .tint(Theme.brass)
        .preferredColorScheme(.dark)
    }

    /// Only shown while a case is open and at least one clue is in hand.
    private var evidenceBadge: String? {
        guard engine.isLive, engine.foundCount > 0 else { return nil }
        return "\(engine.foundCount)"
    }
}

#Preview {
    let store = GameStore()
    let location = LocationService()
    return ContentView()
        .environment(store)
        .environment(location)
        .environment(InvestigationEngine(location: location, store: store))
}
