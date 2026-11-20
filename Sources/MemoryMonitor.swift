//
//  MemoryMonitor.swift
//  TidyRAM
//
//  Das Datenmodell der App. Es
//    • liest alle 2 Sekunden die Speicherwerte neu ein,
//    • ermittelt die Apps mit dem größten Speicherverbrauch,
//    • löst das Freigeben des Datei-Caches aus,
//    • beendet auf Wunsch einzelne Apps (regulär, wie ⌘Q),
//    • verwaltet "Bei Anmeldung starten".
//
//  `@Observable` sorgt dafür, dass sich die Oberfläche automatisch
//  aktualisiert, sobald sich eine Eigenschaft ändert. `@MainActor` stellt
//  sicher, dass alle Änderungen auf dem Haupt-Thread passieren (Pflicht für
//  UI-Daten, wird von Swift 6 zur Compile-Zeit geprüft).
//

import AppKit
import Observation
import ServiceManagement

/// Eine Zeile in der Liste "Größte Apps".
struct AppUsage: Identifiable {
    let id: pid_t                 // Prozess-ID, eindeutig für die Liste
    let name: String              // angezeigter App-Name
    let icon: NSImage?            // App-Symbol
    let footprint: UInt64         // Speicherverbrauch in Bytes
    let isActive: Bool            // ist das die App im Vordergrund?
    let app: NSRunningApplication // Referenz zum regulären Beenden
}

@MainActor
@Observable
final class MemoryMonitor {
    // Nur lesbar von außen – geändert wird ausschließlich hier im Modell.
    private(set) var stats = MemoryStats()
    private(set) var apps: [AppUsage] = []
    private(set) var isCleaning = false
    private(set) var lastResult: String?
    /// true, wenn die sudoers-Regel aktiv ist und purge ohne Passwort läuft.
    private(set) var passwordless = false

    /// Apps, die nie zum Beenden angeboten werden. Sie gehören zum System und
    /// würden sofort neu starten bzw. die Bedienoberfläche stören.
    private let protectedBundleIDs: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.loginwindow",
        "com.apple.systemuiserver", "com.apple.controlcenter",
    ]

    /// Hintergrund-Schleife für die regelmäßige Aktualisierung.
    private var refreshTask: Task<Void, Never>?

    init() {
        refresh()
        // Endlosschleife: alle 2 s neue Werte, alle 60 s (30 Durchläufe) wird
        // zusätzlich geprüft, ob die Passwort-Regel (noch) aktiv ist.
        // `[weak self]` verhindert einen Speicherzyklus zwischen Modell und Task.
        refreshTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                if tick % 30 == 0 { self?.passwordless = await Cleaner.isPasswordless() }
                tick += 1
                try? await Task.sleep(for: .seconds(2))
                self?.refresh()
            }
        }
    }

    /// Liest Speicherwerte und App-Liste neu ein.
    func refresh() {
        if let s = MemoryStats.current() { stats = s }

        let me = ProcessInfo.processInfo.processIdentifier
        apps = NSWorkspace.shared.runningApplications
            // Nur "richtige" Apps mit Dock-Symbol, nicht uns selbst, keine Systemprozesse.
            .filter {
                $0.activationPolicy == .regular
                    && $0.processIdentifier != me
                    && !protectedBundleIDs.contains($0.bundleIdentifier ?? "")
            }
            // Speicherverbrauch ermitteln; Apps ohne lesbaren Wert fallen raus.
            .compactMap { app in
                guard let fp = physicalFootprint(of: app.processIdentifier) else { return nil }
                return AppUsage(
                    id: app.processIdentifier,
                    name: app.localizedName ?? "?",
                    icon: app.icon,
                    footprint: fp,
                    isActive: app.isActive,
                    app: app)
            }
            // Größte zuerst, maximal 8 Einträge.
            .sorted { $0.footprint > $1.footprint }
            .prefix(8)
            .map { $0 }
    }

    /// Gibt den Datei-Cache frei und zeigt an, wie viel RAM dadurch frei wurde.
    func clean() async {
        guard !isCleaning else { return }   // Doppelklicks ignorieren
        isCleaning = true
        lastResult = nil
        let before = MemoryStats.current()?.free ?? 0
        do {
            try await Cleaner.purgeFileCache()
            // Kurz warten, bis der Kernel die Zähler aktualisiert hat.
            try? await Task.sleep(for: .milliseconds(500))
            refresh()
            let after = stats.free
            let freed = after > before ? after - before : 0
            lastResult = "\(formatBytes(freed)) freigegeben"
        } catch {
            lastResult = error.localizedDescription
        }
        passwordless = await Cleaner.isPasswordless()
        isCleaning = false
    }

    /// Beendet eine App regulär – genau wie ⌘Q. Die App bekommt die normale
    /// Beenden-Anfrage und kann bei ungesicherten Dokumenten nachfragen.
    /// Es wird bewusst NICHT `forceTerminate()` verwendet: Nichts wird erzwungen,
    /// es können keine Daten verloren gehen.
    func quit(_ usage: AppUsage) {
        usage.app.terminate()
        Task {
            try? await Task.sleep(for: .seconds(1))
            refresh()
        }
    }

    // MARK: - Autostart

    /// "Bei Anmeldung starten" über die offizielle macOS-API (SMAppService).
    /// Die App erscheint danach in Systemeinstellungen → Allgemein → Anmeldeobjekte.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                lastResult = "Autostart: \(error.localizedDescription)"
            }
        }
    }
}
