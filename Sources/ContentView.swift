//
//  ContentView.swift
//  TidyRAM
//
//  Die Oberfläche im Menüleisten-Fenster. Aufbau von oben nach unten:
//    1. Kopf: Titel, belegter Speicher, Badge für den Speicherdruck
//    2. Farbiger Balken + Legende mit allen Speicherbereichen
//    3. Button "Ungenutzten RAM freigeben" + Ergebnis + Passwort-Status
//    4. Liste der größten Apps mit Beenden-Knopf
//    5. Fußzeile: Autostart-Schalter und "Beenden"
//
//  Die View enthält keine Logik – alle Daten und Aktionen kommen aus
//  `MemoryMonitor`.
//

import SwiftUI

// MARK: - Speicherbereiche

/// Die fünf Bereiche im Balken – in der Reihenfolge, in der sie gezeichnet
/// werden. Farbe und Titel stehen hier zentral, damit Balken und Legende
/// immer übereinstimmen.
private enum Segment: CaseIterable {
    case app, wired, compressed, cache, free

    var title: String {
        switch self {
        case .app: "Apps"
        case .wired: "Reserviert"
        case .compressed: "Komprimiert"
        case .cache: "Datei-Cache"
        case .free: "Frei"
        }
    }

    var color: Color {
        switch self {
        case .app: .blue
        case .wired: .orange
        case .compressed: .purple
        case .cache: .gray.opacity(0.6)
        case .free: .green.opacity(0.5)
        }
    }

    /// Zugehöriger Wert aus der Momentaufnahme.
    func value(_ s: MemoryStats) -> UInt64 {
        switch self {
        case .app: s.appMemory
        case .wired: s.wired
        case .compressed: s.compressed
        case .cache: s.cachedFiles
        case .free: s.free
        }
    }
}

// MARK: - Hauptansicht

struct ContentView: View {
    @Environment(MemoryMonitor.self) private var monitor

    var body: some View {
        // @Bindable erlaubt Zwei-Wege-Bindungen ($monitor.…) für den Toggle.
        @Bindable var monitor = monitor
        let s = monitor.stats

        VStack(alignment: .leading, spacing: 14) {
            header(s)
            usageBar(s)
            legend(s)

            Divider()
            cleanSection

            Divider()
            appsSection

            Divider()
            footer(launchAtLogin: $monitor.launchAtLogin)
        }
        .padding(16)
        .frame(width: 340)
    }

    // MARK: 1. Kopf

    private func header(_ s: MemoryStats) -> some View {
        HStack {
            Image(systemName: "memorychip").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("TidyRAM").font(.headline)
                Text("\(formatBytes(s.used)) von \(formatBytes(s.total)) belegt")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            // Badge: Normal (grün) / Erhöht (gelb) / Kritisch (rot)
            Text(s.pressure.label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(pressureColor(s.pressure).opacity(0.2), in: Capsule())
                .foregroundStyle(pressureColor(s.pressure))
                .help("Speicherdruck laut macOS")
        }
    }

    // MARK: 2. Balken und Legende

    /// Gestapelter Balken: Jeder Bereich bekommt eine Breite proportional zu
    /// seinem Anteil an der Summe aller Bereiche.
    private func usageBar(_ s: MemoryStats) -> some View {
        GeometryReader { geo in
            let total = max(1, Double(Segment.allCases.reduce(0) { $0 + $1.value(s) }))
            HStack(spacing: 1) {
                ForEach(Segment.allCases, id: \.self) { seg in
                    Rectangle()
                        .fill(seg.color)
                        .frame(width: max(0, geo.size.width * Double(seg.value(s)) / total - 1))
                }
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .animation(.easeOut(duration: 0.4), value: s.free)  // sanfter Übergang nach dem Freigeben
    }

    private func legend(_ s: MemoryStats) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            ForEach(Segment.allCases, id: \.self) { seg in
                GridRow {
                    Circle().fill(seg.color).frame(width: 8, height: 8)
                    Text(seg.title)
                    Spacer()
                    Text(formatBytes(seg.value(s))).monospacedDigit()
                }
            }
            // Swap liegt auf der SSD, nicht im RAM – daher nur grau in der Legende.
            GridRow {
                Image(systemName: "arrow.left.arrow.right").font(.caption2)
                Text("Swap")
                Spacer()
                Text(formatBytes(s.swapUsed)).monospacedDigit()
            }
            .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    // MARK: 3. Freigeben

    private var cleanSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await monitor.clean() }
            } label: {
                HStack {
                    if monitor.isCleaning {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(monitor.isCleaning ? "Wird freigegeben …" : "Ungenutzten RAM freigeben")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(monitor.isCleaning)

            // Ergebnis des letzten Laufs, z. B. "1,9 GB freigegeben".
            if let result = monitor.lastResult {
                Text(result).font(.caption).foregroundStyle(.secondary)
            }
            Text("Leert nur den Datei-Cache. Programme und ihre Daten bleiben unberührt.")
                .font(.caption2).foregroundStyle(.tertiary)
            // Zeigt, ob die sudoers-Regel aktiv ist (siehe README).
            Label(monitor.passwordless ? "Ohne Passwort eingerichtet" : "Fragt nach Passwort",
                  systemImage: monitor.passwordless ? "checkmark.shield" : "lock")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: 4. Größte Apps

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Größte Apps (inkl. Tabs & Hilfsprozesse)").font(.subheadline.weight(.semibold))
            ForEach(monitor.apps) { usage in
                HStack(spacing: 8) {
                    if let icon = usage.icon {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    }
                    Text(usage.name).lineLimit(1)
                    if usage.isActive {
                        Text("aktiv").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Anzahl Prozesse (z. B. Safari-Tabs), nur wenn es mehr als einer ist.
                    if usage.processCount > 1 {
                        Label("\(usage.processCount)", systemImage: "square.stack")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2).foregroundStyle(.tertiary)
                            .help("\(usage.processCount) Prozesse inkl. Tabs und Hilfsprozesse")
                    }
                    Text(formatBytes(usage.footprint))
                        .monospacedDigit().foregroundStyle(.secondary)
                        .help("Speicher von \(usage.name) inkl. aller Hilfsprozesse")
                    // Reguläres Beenden (wie ⌘Q) – siehe MemoryMonitor.quit.
                    Button {
                        monitor.quit(usage)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("\(usage.name) regulär beenden (wie ⌘Q – fragt bei ungesicherten Daten nach)")
                }
                .font(.callout)
            }
        }
    }

    // MARK: 5. Fußzeile

    private func footer(launchAtLogin: Binding<Bool>) -> some View {
        HStack {
            Toggle("Bei Anmeldung starten", isOn: launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.caption)
            Spacer()
            Button("Beenden") { NSApplication.shared.terminate(nil) }
                .font(.caption)
        }
    }

    // MARK: Hilfen

    private func pressureColor(_ p: MemoryPressure) -> Color {
        switch p {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        case .unknown: .secondary
        }
    }
}
