//
//  ContentView.swift
//  MysteryRun
//

import SwiftUI

/// Root tab bar: the four surfaces of the detective's desk.
struct ContentView: View {
    @Environment(InvestigationEngine.self) private var engine

    var body: some View {
        TabView {
            Tab("Case", systemImage: "folder.fill") {
                NavigationStack {
                    CaseBriefingView()
                }
            }

            Tab("Evidence", systemImage: "magnifyingglass") {
                NavigationStack {
                    EvidenceBoardView()
                }
            }

            Tab("Progress", systemImage: "chart.bar.fill") {
                NavigationStack {
                    ProgressDashboardView()
                }
            }

            Tab("Profile", systemImage: "person.fill") {
                NavigationStack {
                    ProfileView()
                }
            }
        }
        .tint(Theme.brass)
        .preferredColorScheme(.dark)
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
