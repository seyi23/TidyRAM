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
import OSLog
import ServiceManagement

/// Protokoll für Fehlersuche: im Terminal mit
/// `/usr/bin/log stream --info --predicate 'subsystem == "local.tidyram"'` mitlesen
/// (voller Pfad nötig: in der zsh ist `log` ein eingebauter Befehl).
let log = Logger(subsystem: "local.tidyram", category: "app")

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

/// Wodurch eine Freigabe ausgelöst wurde – steuert, ob eine Mitteilung kommt.
enum CleanTrigger {
    case button   // Klick im Fenster: Ergebnis steht im Fenster
    case hotKey   // ⌃⌥⌘R: Fenster ist zu, daher Ergebnis als Mitteilung
    case auto     // automatisch bei Speicherdruck
    case url      // per Link tidyram://free (Terminal, Kurzbefehle, Raycast …)
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
    /// Eigenverbrauch von TidyRAM: Speicher und CPU-Last (% eines Kerns).
    private(set) var selfFootprint: UInt64 = 0
    private(set) var selfCPUPercent: Double = 0

    let settings: AppSettings

    /// Apps, die nie zum Beenden angeboten werden. Sie gehören zum System und
    /// würden sofort neu starten bzw. die Bedienoberfläche stören.
    private let protectedBundleIDs: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.loginwindow",
        "com.apple.systemuiserver", "com.apple.controlcenter",
    ]

    // Verlauf: alle 10 s ein Punkt, maximal 24 Stunden → höchstens 8 640 Punkte.
    // Gespeichert wird höchstens einmal pro Minute und beim Beenden.
    private let historyInterval: TimeInterval = 10
    private let historyWindow: TimeInterval = 24 * 3600
    private var lastHistorySave = Date()

    // Mindestabstand zwischen zwei Mitteilungen wegen Speicherdruck.
    private let alertCooldown: TimeInterval = 10 * 60

    private var refreshTask: Task<Void, Never>?
    private var previousPressure: MemoryPressure = .unknown
    private var lastAlert = Date.distantPast
    private var lastAutoClean = Date.distantPast
    private var previousSwap: UInt64?           // nil bis zur ersten Messung
    private var lastSwapAlert = Date.distantPast
    private var lastCPUSample = (cpu: SelfUsage.cpuSeconds(), wall: Date())
    private var cpuSamples = 0
    private let hotKey = GlobalHotKey()

    init(settings: AppSettings) {
        self.settings = settings
        // Gespeicherten Verlauf der letzten 24 h laden – so übersteht die
        // Grafik einen Neustart von TidyRAM.
        history = HistoryStore.load(maxAge: historyWindow)
        // Beim Beenden den aktuellen Stand sichern.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self.map { HistoryStore.save($0.history) } }
        }
        Notifier.shared.setUp()
        updateHotKey()
        refresh()
        // CPU-Messung erst NACH dem Start beginnen – der Start selbst kostet
        // kurz viel Rechenzeit und soll nicht in den Eigenverbrauch einfließen.
        lastCPUSample = (cpu: SelfUsage.cpuSeconds(), wall: Date())
        // Endlosschleife: alle 2/5/10 s (Einstellung) neue Werte, höchstens
        // einmal pro Minute wird zusätzlich geprüft, ob die Passwort-Regel
        // (noch) aktiv ist. `[weak self]` verhindert einen Speicherzyklus.
        refreshTask = Task { [weak self] in
            var lastPasswordCheck = Date.distantPast
            while !Task.isCancelled {
                if Date().timeIntervalSince(lastPasswordCheck) >= 60 {
                    lastPasswordCheck = Date()
                    self?.passwordless = await Cleaner.isPasswordless()
                }
                let seconds = self?.settings.refreshSeconds ?? 2
                try? await Task.sleep(for: .seconds(seconds))
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
        handleSwap()
        measureSelf()
    }

    /// Mitteilung, wenn der Swap die eingestellte Grenze überschreitet –
    /// höchstens alle 30 Minuten. Beim Start wird nur gemessen, nicht gewarnt.
    private func handleSwap() {
        let current = stats.swapUsed
        defer { previousSwap = current }
        guard let previous = previousSwap,
              SwapWarning.crossed(previous: previous, current: current, thresholdGB: settings.swapWarningGB),
              Date().timeIntervalSince(lastSwapAlert) > 30 * 60 else { return }
        lastSwapAlert = Date()
        var body = String(localized: "\(formatBytes(current)) sind auf die SSD ausgelagert. Der Arbeitsspeicher reicht gerade nicht aus.")
        if let top = apps.first {
            body += " " + String(localized: "\(top.name) belegt \(formatBytes(top.footprint)). Große Apps zu schließen hilft am meisten.")
        }
        let title = String(localized: "Swap über \(settings.swapWarningGB) GB")
        Task { await Notifier.shared.post(title: title, body: body) }
    }

    /// Misst, wie viel Speicher und CPU TidyRAM selbst braucht.
    /// Die CPU-Last wird geglättet (gleitender Mittelwert), damit kurze Spitzen –
    /// etwa direkt nach dem Start – nicht als Dauerlast erscheinen.
    private func measureSelf() {
        selfFootprint = physicalFootprint(of: ProcessInfo.processInfo.processIdentifier) ?? 0
        let now = (cpu: SelfUsage.cpuSeconds(), wall: Date())
        let wall = now.wall.timeIntervalSince(lastCPUSample.wall)
        guard wall >= 1 else { return }   // zu kurzer Abstand → keine sinnvolle Messung
        let current = SelfUsage.cpuPercent(cpuSecondsDelta: now.cpu - lastCPUSample.cpu, wallSecondsDelta: wall)
        selfCPUPercent = cpuSamples == 0 ? current : 0.7 * selfCPUPercent + 0.3 * current
        cpuSamples += 1
        lastCPUSample = now
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
        history.append(HistoryPoint(date: now, usedFraction: stats.usedFraction, pressure: stats.pressure,
                                    topApp: apps.first?.name, topAppBytes: apps.first?.footprint ?? 0))
        history.removeAll { now.timeIntervalSince($0.date) > historyWindow }

        // Höchstens einmal pro Minute auf die Festplatte schreiben – im
        // Hintergrund, damit die Oberfläche nicht stockt.
        if now.timeIntervalSince(lastHistorySave) >= 60 {
            lastHistorySave = now
            let snapshot = history
            Task.detached(priority: .utility) { HistoryStore.save(snapshot) }
        }
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
        log.info("Freigeben gestartet (\(String(describing: trigger), privacy: .public))")
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
        log.info("Freigeben beendet: \(self.lastResult ?? "-", privacy: .public)")

        // Bei Tastenkürzel ist das Fenster zu → Ergebnis als Mitteilung.
        // Bei automatischer Freigabe nur, wenn Mitteilungen eingeschaltet sind.
        if trigger == .hotKey || trigger == .url || (trigger == .auto && settings.notifyLevel != .off),
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
