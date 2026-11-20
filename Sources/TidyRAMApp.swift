//
//  TidyRAMApp.swift
//  TidyRAM
//
//  Einstiegspunkt der App.
//
//  TidyRAM ist eine reine Menüleisten-App: Es gibt kein Dock-Symbol und
//  kein Hauptfenster (dafür sorgt `LSUIElement = true` in der Info.plist, die
//  build.sh erzeugt). Die gesamte Oberfläche steckt in einem `MenuBarExtra`,
//  das sich beim Klick auf das Symbol in der Menüleiste als kleines Fenster
//  öffnet.
//

import SwiftUI

@main
struct TidyRAMApp: App {
    /// Zentrales Datenmodell. Es liest alle 2 Sekunden die Speicherwerte und
    /// wird per `.environment` an die Oberfläche weitergereicht.
    /// `@State` sorgt dafür, dass SwiftUI genau eine Instanz für die gesamte
    /// Laufzeit der App behält.
    @State private var monitor = MemoryMonitor()

    var body: some Scene {
        MenuBarExtra {
            // Inhalt des Fensters, das sich unter dem Menüleisten-Symbol öffnet.
            ContentView()
                .environment(monitor)
        } label: {
            // Was dauerhaft in der Menüleiste steht: Chip-Symbol + belegter
            // Speicher in Prozent (gleiche Definition wie "Benutzter Speicher"
            // in der Aktivitätsanzeige, siehe MemoryStats.used).
            HStack(spacing: 3) {
                Image(systemName: "memorychip")
                Text("\(Int((monitor.stats.usedFraction * 100).rounded()))%")
            }
        }
        // `.window` statt `.menu`, damit wir ein frei gestaltetes Fenster mit
        // Balken, Liste und Buttons zeigen können statt eines klassischen Menüs.
        .menuBarExtraStyle(.window)
    }
}
