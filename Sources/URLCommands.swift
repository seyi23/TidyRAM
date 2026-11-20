//
//  URLCommands.swift
//  TidyRAM
//
//  Steuerung per Link. TidyRAM meldet bei macOS das Link-Schema `tidyram://`
//  an (Info.plist → CFBundleURLTypes, siehe build.sh). Damit kann man die App
//  von außen steuern – aus dem Terminal, aus Kurzbefehlen, Raycast, Alfred,
//  Skripten usw.:
//
//      open -g tidyram://free        RAM freigeben (Ergebnis als Mitteilung)
//
//  `-g` sorgt dafür, dass nichts in den Vordergrund springt. Läuft TidyRAM
//  noch nicht, startet macOS die App automatisch.
//
//  Technisch: macOS schickt beim Öffnen eines Links ein Apple Event
//  ("GetURL"). Der AppDelegate unten fängt es ab und reicht es weiter.
//

import AppKit

@MainActor
enum URLCommands {
    /// Das Datenmodell der laufenden App – wird beim Start gesetzt.
    static weak var monitor: MemoryMonitor?

    /// Führt einen Link-Befehl aus. Unbekannte Befehle werden ignoriert.
    static func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "tidyram" else { return }
        // Bei "tidyram://free" steht der Befehl im "host"-Teil.
        let command = (url.host ?? url.path).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        log.info("Link-Befehl empfangen: \(command, privacy: .public)")

        switch command {
        case "free", "purge", "clean":
            guard let monitor else { return }
            Task { await monitor.clean(trigger: .url) }
        default:
            log.error("Unbekannter Link-Befehl: \(command, privacy: .public)")
        }
    }
}

/// Fängt das "Link öffnen"-Ereignis von macOS ab.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Möglichst früh registrieren, damit auch der Link ankommt, mit dem
        // die App gerade erst gestartet wurde.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor,
                                    withReplyEvent reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: text) else { return }
        // Apple Events kommen auf dem Haupt-Thread an.
        MainActor.assumeIsolated { URLCommands.handle(url) }
    }
}
