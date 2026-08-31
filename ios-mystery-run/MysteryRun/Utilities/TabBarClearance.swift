//
//  TabBarClearance.swift
//  MysteryRun
//

import SwiftUI

private struct TabBarClearanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Height of the detective tab bar drawn over this view, or zero where there
    /// is no bar — inside full-screen covers and sheets.
    ///
    /// `ContentView` publishes the real height on the `TabView`. A `safeAreaInset`
    /// applied to a `TabView` is not carried into the tabs themselves, so each
    /// screen has to reserve the space it needs from this value.
    var tabBarClearance: CGFloat {
        get { self[TabBarClearanceKey.self] }
        set { self[TabBarClearanceKey.self] = newValue }
    }
}

private struct TabBarClearanceModifier: ViewModifier {
    @Environment(\.tabBarClearance) private var clearance

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: clearance)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Keeps content clear of the detective tab bar.
    ///
    /// Apply this to the outermost layer of a screen — after any bottom
    /// `safeAreaInset` carrying a call to action — so pinned buttons sit above
    /// the bar rather than behind it. Collapses to nothing where no bar is shown,
    /// so the same screen can be pushed inside a tab or presented as a cover.
    func tabBarClearance() -> some View {
        modifier(TabBarClearanceModifier())
    }
}
