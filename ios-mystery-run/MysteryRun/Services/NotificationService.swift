//
//  NotificationService.swift
//  MysteryRun
//

import Foundation
import UIKit
import UserNotifications

/// Local notifications for a phone that spends the run in a pocket or armband.
/// Everything is delivered on-device — there is no server and no push token.
enum NotificationService {
    /// Asked for once, right before the first investigation begins.
    static func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            print("[Notifications] Authorization request failed.")
        }
    }

    /// Fires only when the app isn't on screen — otherwise the in-app reveal covers it.
    private static func deliver(title: String, body: String, sound: UNNotificationSound) {
        guard UIApplication.shared.applicationState != .active else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if error != nil { print("[Notifications] Could not schedule alert.") }
        }
    }

    static func clueDiscovered(_ clue: Clue, found: Int, total: Int) {
        deliver(
            title: "Evidence found — \(clue.title)",
            body: found == total
                ? "That's the last piece. Open the case file to name your suspect."
                : "Clue \(found) of \(total) recovered. Keep moving.",
            sound: .default
        )
    }

    static func closingIn(on clue: Clue, metres: Double) {
        deliver(
            title: "Something's nearby",
            body: "\(clue.title) is about \(Int(metres)) m ahead.",
            sound: .default
        )
    }

    /// Warns that the case is still open if the app got killed mid-run.
    static func sessionInterrupted() {
        deliver(
            title: "Investigation paused",
            body: "Mystery Run lost tracking. Reopen the app to pick the trail back up.",
            sound: .default
        )
    }
}
