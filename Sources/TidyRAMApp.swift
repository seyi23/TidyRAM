//
//  TidyRAMApp.swift
//  TidyRAM
//
//  Einstiegspunkt der App.
//
//  TidyRAM ist eine reine Menüleisten-App: Es gibt kein Dock-Symbol und kein
//  Hauptfenster (dafür sorgt `LSUIElement = true` in der Info.plist, die
//  build.sh erzeugt). Die Oberfläche besteht aus
//    • dem `MenuBarExtra` – das Fenster unter dem Symbol in der Menüleiste,
//    • der `Settings`-Szene – das Einstellungsfenster (Zahnrad oder ⌘,).
//  Von außen lässt sich TidyRAM per Link steuern: `open -g tidyram://free`.
//

import SwiftUI

@main
struct TidyRAMApp: App {
    /// Nimmt Links wie tidyram://free entgegen (siehe URLCommands.swift).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Einstellungen (in UserDefaults gespeichert).
    @State private var settings: AppSettings
    /// Zentrales Datenmodell. Es liest alle 2 Sekunden die Speicherwerte und
    /// wird per `.environment` an die Oberfläche weitergereicht.
    @State private var monitor: MemoryMonitor

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        let monitor = MemoryMonitor(settings: settings)
        _monitor = State(initialValue: monitor)
        URLCommands.monitor = monitor
    }

    var body: some Scene {
        MenuBarExtra {
            // Inhalt des Fensters, das sich unter dem Menüleisten-Symbol öffnet.
            ContentView()
                .environment(monitor)
                .environment(settings)
        } label: {
            MenuBarLabel(stats: monitor.stats, history: monitor.history, style: settings.menuBarStyle)
        }
        // `.window` statt `.menu`, damit wir ein frei gestaltetes Fenster mit
        // Balken, Grafik, Liste und Buttons zeigen können.
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(monitor)
                .environment(settings)
        }
    }
}

/// Was dauerhaft in der Menüleiste steht – je nach Einstellung.
struct MenuBarLabel: View {
    let stats: MemoryStats
    let history: [HistoryPoint]
    let style: MenuBarStyle

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "memorychip")
            switch style {
            case .percent:
                // Gleiche Definition wie "Benutzter Speicher" in der Aktivitätsanzeige.
                Text(verbatim: "\(Int((stats.usedFraction * 100).rounded()))%")
            case .usedGB:
                Text(verbatim: String(format: "%.1f GB", Double(stats.used) / 1_073_741_824))
            case .pressureDot:
                // Menüleisten-Symbole werden normalerweise einfarbig dargestellt.
                // Ein NSImage mit isTemplate = false behält seine Farbe.
                Image(nsImage: dotImage(NSColor(pressureColor(stats.pressure))))
            case .sparkline:
                // Letzte 30 Minuten, verdichtet auf 1 Punkt pro Minute.
                let end = history.last?.date ?? Date()
                let values = history.filter { end.timeIntervalSince($0.date) <= 1800 }
                    .downsampled(bucket: 60).map(\.usedFraction)
                if values.count > 1 {
                    Image(nsImage: Sparkline.image(values: values))
                } else {
                    // Noch zu wenig Daten → vorerst Prozent anzeigen.
                    Text(verbatim: "\(Int((stats.usedFraction * 100).rounded()))%")
                }
            case .iconOnly:
                EmptyView()
            }
        }
    }

    /// Kleiner farbiger Punkt als Bild (bleibt in der Menüleiste farbig).
    private func dotImage(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
