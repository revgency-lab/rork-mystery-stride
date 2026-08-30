//
//  MysteryRunApp.swift
//  MysteryRun
//

import SwiftUI

@main
struct MysteryRunApp: App {
    @State private var store: GameStore
    @State private var location: LocationService
    @State private var engine: InvestigationEngine

    init() {
        let store = GameStore()
        let location = LocationService()
        _store = State(initialValue: store)
        _location = State(initialValue: location)
        _engine = State(initialValue: InvestigationEngine(location: location, store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(location)
                .environment(engine)
        }
    }
}
