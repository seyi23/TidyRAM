//
//  MemoryMonitor.swift
//  TidyRAM
//
//  Das Datenmodell der App. Es
//    • liest alle 2 Sekunden die Speicherwerte neu ein,
//    • merkt sich den Verlauf der letzten Stunde (für die Grafik),
//    • ermittelt die Apps mit dem größten Speicherverbrauch,
//    • löst das Freigeben des Datei-Caches aus (Knopf, Tastenkürzel, automatisch),
//    • verschickt Mitteilungen bei Speicherknappheit,
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
    let footprint: UInt64         // Speicherverbrauch in Bytes, inkl. Hilfsprozesse
    let processCount: Int         // Anzahl Prozesse (Hauptprozess + Helfer/Tabs)
    let isActive: Bool            // ist das die App im Vordergrund?
    let app: NSRunningApplication // Referenz zum regulären Beenden
}

/// Ein Messpunkt für die Verlaufsgrafik.
struct HistoryPoint: Identifiable {
    let date: Date
    let usedFraction: Double      // 0…1
    let pressure: MemoryPressure
    var id: Date { date }
}

/// Wodurch eine Freigabe ausgelöst wurde – steuert, ob eine Mitteilung kommt.
enum CleanTrigger {
    case button   // Klick im Fenster: Ergebnis steht im Fenster
    case hotKey   // ⌃⌥⌘R: Fenster ist zu, daher Ergebnis als Mitteilung
    case auto     // automatisch bei Speicherdruck
}

@MainActor
@Observable
final class MemoryMonitor {
    // Nur lesbar von außen – geändert wird ausschließlich hier im Modell.
    private(set) var stats = MemoryStats()
    private(set) var apps: [AppUsage] = []
    private(set) var history: [HistoryPoint] = []
    private(set) var isCleaning = false
    private(set) var lastResult: String?
    /// true, wenn die sudoers-Regel aktiv ist und purge ohne Passwort läuft.
    private(set) var passwordless = false

    let settings: AppSettings

    /// Apps, die nie zum Beenden angeboten werden. Sie gehören zum System und
    /// würden sofort neu starten bzw. die Bedienoberfläche stören.
    private let protectedBundleIDs: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.loginwindow",
        "com.apple.systemuiserver", "com.apple.controlcenter",
    ]

    // Verlauf: alle 10 s ein Punkt, maximal 1 Stunde → höchstens 360 Punkte.
    private let historyInterval: TimeInterval = 10
    private let historyWindow: TimeInterval = 3600

    // Mindestabstand zwischen zwei Mitteilungen wegen Speicherdruck.
    private let alertCooldown: TimeInterval = 10 * 60

    private var refreshTask: Task<Void, Never>?
    private var previousPressure: MemoryPressure = .unknown
    private var lastAlert = Date.distantPast
    private var lastAutoClean = Date.distantPast
    private let hotKey = GlobalHotKey()

    init(settings: AppSettings) {
        self.settings = settings
        Notifier.shared.setUp()
        updateHotKey()
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

    // MARK: - Aktualisieren

    /// Liest Speicherwerte und App-Liste neu ein und reagiert auf Speicherdruck.
    func refresh() {
        if let s = MemoryStats.current() { stats = s }
        updateApps()
        recordHistory()
        handlePressure()
    }

    private func updateApps() {
        let me = ProcessInfo.processInfo.processIdentifier
        // Speicher aller Prozesse, summiert pro verantwortlicher App
        // (Safari + alle Tab-Prozesse, Chrome + alle Helper usw.).
        let totals = footprintsByResponsibleApp()
        apps = NSWorkspace.shared.runningApplications
            // Nur "richtige" Apps mit Dock-Symbol, nicht uns selbst, keine Systemprozesse.
            .filter {
                $0.activationPolicy == .regular
                    && $0.processIdentifier != me
                    && !protectedBundleIDs.contains($0.bundleIdentifier ?? "")
            }
            // Speicherverbrauch zuordnen; Apps ohne lesbaren Wert fallen raus.
            .compactMap { app in
                guard let total = totals[app.processIdentifier], total.bytes > 0 else { return nil }
                return AppUsage(
                    id: app.processIdentifier,
                    name: app.localizedName ?? "?",
                    icon: app.icon,
                    footprint: total.bytes,
                    processCount: total.processCount,
                    isActive: app.isActive,
                    app: app)
            }
            // Größte zuerst, maximal 8 Einträge.
            .sorted { $0.footprint > $1.footprint }
            .prefix(8)
            .map { $0 }
    }

    /// Hängt alle 10 s einen Messpunkt an und wirft Punkte älter als 1 h weg.
    private func recordHistory() {
        let now = Date()
        guard now.timeIntervalSince(history.last?.date ?? .distantPast) >= historyInterval else { return }
        history.append(HistoryPoint(date: now, usedFraction: stats.usedFraction, pressure: stats.pressure))
        history.removeAll { now.timeIntervalSince($0.date) > historyWindow }
    }

    /// Mitteilung und (optional) automatisches Freigeben bei Speicherdruck.
    private func handlePressure() {
        let pressure = stats.pressure
        defer { previousPressure = pressure }
        let now = Date()

        // 1. Mitteilung – nur beim ÜBERGANG in den kritischen Bereich und
        //    höchstens alle 10 Minuten, damit es nicht nervt.
        let level = settings.notifyLevel
        if level.triggers(pressure), !level.triggers(previousPressure),
           now.timeIntervalSince(lastAlert) > alertCooldown {
            lastAlert = now
            let title = pressure == .critical
                ? String(localized: "Arbeitsspeicher kritisch knapp")
                : String(localized: "Arbeitsspeicher wird knapp")
            var body = String(localized: "\(formatBytes(stats.used)) von \(formatBytes(stats.total)) belegt.")
            if let top = apps.first {
                body += " " + String(localized: "\(top.name) belegt \(formatBytes(top.footprint)). Große Apps zu schließen hilft am meisten.")
            }
            Task { await Notifier.shared.post(title: title, body: body) }
        }

        // 2. Automatisch freigeben – nur wenn eingeschaltet, ohne Passwort
        //    möglich und der letzte automatische Lauf lange genug her ist.
        if settings.autoClean, passwordless, !isCleaning,
           pressure == .warning || pressure == .critical,
           now.timeIntervalSince(lastAutoClean) > Double(settings.autoCleanMinutes) * 60 {
            lastAutoClean = now
            Task { await clean(trigger: .auto) }
        }
    }

    // MARK: - Freigeben

    /// Gibt den Datei-Cache frei und zeigt an, wie viel RAM dadurch frei wurde.
    func clean(trigger: CleanTrigger = .button) async {
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
            lastResult = trigger == .auto
                ? String(localized: "Automatisch: \(formatBytes(freed)) freigegeben")
                : String(localized: "\(formatBytes(freed)) freigegeben")
        } catch {
            lastResult = error.localizedDescription
        }
        passwordless = await Cleaner.isPasswordless()
        isCleaning = false

        // Bei Tastenkürzel ist das Fenster zu → Ergebnis als Mitteilung.
        // Bei automatischer Freigabe nur, wenn Mitteilungen eingeschaltet sind.
        if trigger == .hotKey || (trigger == .auto && settings.notifyLevel != .off),
           let lastResult {
            await Notifier.shared.post(title: "TidyRAM", body: lastResult)
        }
    }

    /// Tastenkürzel je nach Einstellung an- oder abmelden.
    func updateHotKey() {
        if settings.hotKeyEnabled {
            hotKey.register { [weak self] in
                guard let self else { return }
                Task { await self.clean(trigger: .hotKey) }
            }
        } else {
            hotKey.unregister()
        }
    }

    // MARK: - Apps beenden

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
                lastResult = String(localized: "Autostart: \(error.localizedDescription)")
            }
        }
    }
}
