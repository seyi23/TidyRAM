//
//  Notifier.swift
//  TidyRAM
//
//  Verschickt macOS-Mitteilungen (Mitteilungszentrale), z. B.
//  "Speicher knapp – Safari belegt 3,1 GB" oder das Ergebnis einer Freigabe
//  per Tastenkürzel.
//
//  Beim ersten Mal fragt macOS, ob TidyRAM Mitteilungen senden darf. Lehnt der
//  Benutzer ab, passiert einfach nichts – die App funktioniert normal weiter.
//  Erlauben/verbieten lässt sich das jederzeit in
//  Systemeinstellungen → Mitteilungen → TidyRAM.
//

import UserNotifications

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private var center: UNUserNotificationCenter { .current() }
    private var permissionRequested = false

    /// Einmal beim Start aufrufen: Wir sind "Delegate", damit Mitteilungen auch
    /// dann erscheinen, wenn TidyRAM gerade selbst im Vordergrund ist.
    func setUp() {
        center.delegate = self
    }

    /// Verschickt eine Mitteilung. Fragt beim ersten Mal nach der Erlaubnis.
    func post(title: String, body: String) async {
        if !permissionRequested {
            permissionRequested = true
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // trigger: nil = sofort zustellen
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }

    /// Mitteilungen auch im Vordergrund als Banner anzeigen.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
