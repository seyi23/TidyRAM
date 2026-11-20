//
//  AppSettings.swift
//  TidyRAM
//
//  Alle Einstellungen der App. Sie werden in den macOS-Benutzereinstellungen
//  (UserDefaults, Datei ~/Library/Preferences/local.tidyram.plist) gespeichert
//  und bleiben so über Neustarts erhalten.
//
//  Jede Eigenschaft schreibt ihren neuen Wert per `didSet` sofort zurück.
//  `@Observable` sorgt dafür, dass Menüleiste und Fenster sich sofort anpassen.
//

import Foundation
import Observation

/// Was neben dem Chip-Symbol in der Menüleiste steht.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case percent       // "68%"
    case usedGB        // "10,8 GB"
    case pressureDot   // farbiger Punkt: grün / gelb / rot
    case sparkline     // Mini-Verlauf der letzten 30 Minuten
    case iconOnly      // nur das Symbol

    var id: String { rawValue }

    var title: String {
        switch self {
        case .percent: String(localized: "Belegter Speicher in Prozent")
        case .usedGB: String(localized: "Belegter Speicher in GB")
        case .pressureDot: String(localized: "Farbpunkt für den Speicherdruck")
        case .sparkline: String(localized: "Mini-Grafik (letzte 30 Minuten)")
        case .iconOnly: String(localized: "Nur das Symbol")
        }
    }
}

/// Ab welchem Speicherdruck eine macOS-Mitteilung erscheint.
enum NotifyLevel: String, CaseIterable, Identifiable {
    case off, critical, warning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: String(localized: "Nie")
        case .critical: String(localized: "Bei kritischem Speicherdruck")
        case .warning: String(localized: "Schon bei erhöhtem Speicherdruck")
        }
    }

    /// Löst dieser Druck bei dieser Einstellung eine Mitteilung aus?
    func triggers(_ pressure: MemoryPressure) -> Bool {
        switch self {
        case .off: false
        case .critical: pressure == .critical
        case .warning: pressure == .warning || pressure == .critical
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    /// Schlüssel in den UserDefaults – an einer Stelle gesammelt.
    private enum Key {
        static let menuBarStyle = "menuBarStyle"
        static let notifyLevel = "notifyLevel"
        static let autoClean = "autoClean"
        static let autoCleanMinutes = "autoCleanMinutes"
        static let hotKeyEnabled = "hotKeyEnabled"
        static let refreshSeconds = "refreshSeconds"
        static let historyRange = "historyRange"
        static let swapWarningGB = "swapWarningGB"
    }

    /// Anzeige in der Menüleiste. Standard: Prozent.
    var menuBarStyle: MenuBarStyle {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: Key.menuBarStyle) }
    }

    /// Mitteilung bei Speicherknappheit. Standard: nur bei "Kritisch".
    var notifyLevel: NotifyLevel {
        didSet { defaults.set(notifyLevel.rawValue, forKey: Key.notifyLevel) }
    }

    /// Automatisch freigeben, wenn der Speicherdruck steigt. Standard: AUS.
    /// Funktioniert nur, wenn purge ohne Passwort eingerichtet ist – sonst
    /// würde plötzlich ein Passwortdialog aufpoppen.
    var autoClean: Bool {
        didSet { defaults.set(autoClean, forKey: Key.autoClean) }
    }

    /// Mindestabstand zwischen zwei automatischen Freigaben in Minuten.
    var autoCleanMinutes: Int {
        didSet { defaults.set(autoCleanMinutes, forKey: Key.autoCleanMinutes) }
    }

    /// Globales Tastenkürzel ⌃⌥⌘R zum Freigeben. Standard: an.
    var hotKeyEnabled: Bool {
        didSet { defaults.set(hotKeyEnabled, forKey: Key.hotKeyEnabled) }
    }

    /// Wie oft die Werte neu gelesen werden (Sekunden). Standard: 2.
    /// Größere Abstände sparen auf MacBooks ein wenig Akku.
    var refreshSeconds: Int {
        didSet { defaults.set(refreshSeconds, forKey: Key.refreshSeconds) }
    }

    /// Zeitraum der Verlaufsgrafik. Standard: 1 Stunde.
    var historyRange: HistoryRange {
        didSet { defaults.set(historyRange.rawValue, forKey: Key.historyRange) }
    }

    /// Mitteilung, wenn der Swap diese Grenze (GB) überschreitet. 0 = aus. Standard: 4.
    var swapWarningGB: Int {
        didSet { defaults.set(swapWarningGB, forKey: Key.swapWarningGB) }
    }

    init() {
        // Gespeicherte Werte laden, sonst die Standardwerte verwenden.
        menuBarStyle = MenuBarStyle(rawValue: defaults.string(forKey: Key.menuBarStyle) ?? "") ?? .percent
        notifyLevel = NotifyLevel(rawValue: defaults.string(forKey: Key.notifyLevel) ?? "") ?? .critical
        autoClean = defaults.bool(forKey: Key.autoClean)  // fehlt → false
        let minutes = defaults.integer(forKey: Key.autoCleanMinutes)
        autoCleanMinutes = minutes > 0 ? minutes : 30
        hotKeyEnabled = defaults.object(forKey: Key.hotKeyEnabled) as? Bool ?? true
        let seconds = defaults.integer(forKey: Key.refreshSeconds)
        refreshSeconds = [2, 5, 10].contains(seconds) ? seconds : 2
        historyRange = HistoryRange(rawValue: defaults.integer(forKey: Key.historyRange)) ?? .hour1
        swapWarningGB = defaults.object(forKey: Key.swapWarningGB) as? Int ?? 4
    }
}
