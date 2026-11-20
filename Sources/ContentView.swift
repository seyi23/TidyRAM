//
//  ContentView.swift
//  TidyRAM
//
//  Die Oberfläche im Menüleisten-Fenster. Aufbau von oben nach unten:
//    1. Kopf: Titel, belegter Speicher, Badge für den Speicherdruck, Zahnrad
//    2. Farbiger Balken + Legende mit allen Speicherbereichen
//    3. Verlaufsgrafik der letzten Stunde
//    4. Button "Ungenutzten RAM freigeben" + Ergebnis + Passwort-Status
//    5. Liste der größten Apps mit Beenden-Knopf
//    6. Fußzeile: Autostart-Schalter und "Beenden"
//
//  Die View enthält keine Logik – alle Daten und Aktionen kommen aus
//  `MemoryMonitor`.
//
//  Übersetzung: Texte in Text("…"), Button("…") usw. werden automatisch in
//  Resources/<sprache>.lproj/Localizable.strings nachgeschlagen.
//

import Charts
import SwiftUI

// MARK: - Speicherbereiche

/// Die fünf Bereiche im Balken – in der Reihenfolge, in der sie gezeichnet
/// werden. Farbe und Titel stehen hier zentral, damit Balken und Legende
/// immer übereinstimmen.
private enum Segment: CaseIterable {
    case app, wired, compressed, cache, free

    var title: String {
        switch self {
        case .app: String(localized: "Apps")
        case .wired: String(localized: "Reserviert")
        case .compressed: String(localized: "Komprimiert")
        case .cache: String(localized: "Datei-Cache")
        case .free: String(localized: "Frei")
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

/// Farbe passend zum Speicherdruck – auch für Menüleiste und Grafik.
func pressureColor(_ p: MemoryPressure) -> Color {
    switch p {
    case .normal: .green
    case .warning: .yellow
    case .critical: .red
    case .unknown: .secondary
    }
}

// MARK: - Hauptansicht

struct ContentView: View {
    @Environment(MemoryMonitor.self) private var monitor
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // @Bindable erlaubt Zwei-Wege-Bindungen ($monitor.…) für den Toggle.
        @Bindable var monitor = monitor
        let s = monitor.stats

        VStack(alignment: .leading, spacing: 14) {
            header(s)
            usageBar(s)
            legend(s)

            Divider()
            historyChart

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
                Text(verbatim: "TidyRAM").font(.headline)
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
            // Zahnrad → Einstellungsfenster. Weil TidyRAM kein Dock-Symbol hat,
            // muss die App danach aktiviert werden, sonst liegt das Fenster hinten.
            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Einstellungen")
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

    // MARK: 3. Verlauf

    /// Fläche = belegter Speicher in %. Gelb/rot hinterlegt = Zeiten mit
    /// erhöhtem bzw. kritischem Speicherdruck.
    private var historyChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Verlauf (letzte Stunde)").font(.subheadline.weight(.semibold))
            if monitor.history.count < 2 {
                Text("Verlauf wird gesammelt …")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            } else {
                Chart {
                    // Hintergrund-Streifen für Zeiten mit Speicherdruck.
                    ForEach(pressureSpans) { span in
                        RectangleMark(xStart: .value("Start", span.start),
                                      xEnd: .value("Ende", span.end),
                                      yStart: .value("Min", 0),
                                      yEnd: .value("Max", 100))
                            .foregroundStyle(pressureColor(span.pressure).opacity(0.18))
                    }
                    ForEach(monitor.history) { point in
                        AreaMark(x: .value("Zeit", point.date),
                                 y: .value("Belegt", point.usedFraction * 100))
                            .foregroundStyle(.linearGradient(colors: [.blue.opacity(0.5), .blue.opacity(0.05)],
                                                             startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Zeit", point.date),
                                 y: .value("Belegt", point.usedFraction * 100))
                            .foregroundStyle(.blue)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
                .chartYScale(domain: 0...100)
                // Immer die ganze letzte Stunde zeigen – neue Werte erscheinen rechts.
                .chartXScale(domain: historyDomain)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel { Text(verbatim: "\(value.as(Int.self) ?? 0)%") }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .minute, count: 15)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .frame(height: 70)
            }
        }
    }

    /// Zeitraum der x-Achse: die Stunde bis zum neuesten Messpunkt.
    private var historyDomain: ClosedRange<Date> {
        let end = monitor.history.last?.date ?? Date()
        return end.addingTimeInterval(-3600)...end
    }

    /// Fasst aufeinanderfolgende Messpunkte mit erhöhtem/kritischem Druck zu
    /// Zeitspannen zusammen (für die farbigen Hintergrundstreifen).
    private var pressureSpans: [PressureSpan] {
        var spans: [PressureSpan] = []
        for (i, point) in monitor.history.enumerated()
        where point.pressure == .warning || point.pressure == .critical {
            let end = i + 1 < monitor.history.count ? monitor.history[i + 1].date : point.date.addingTimeInterval(10)
            if let last = spans.last, last.pressure == point.pressure, last.end == point.date {
                spans[spans.count - 1].end = end
            } else {
                spans.append(PressureSpan(start: point.date, end: end, pressure: point.pressure))
            }
        }
        return spans
    }

    // MARK: 4. Freigeben

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
            .help(monitor.settings.hotKeyEnabled
                  ? Text("Auch mit \(GlobalHotKey.displayString) von überall")
                  : Text("Ungenutzten RAM freigeben"))

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

    // MARK: 5. Größte Apps

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Größte Apps (inkl. Tabs & Hilfsprozesse)").font(.subheadline.weight(.semibold))
            ForEach(monitor.apps) { usage in
                HStack(spacing: 8) {
                    if let icon = usage.icon {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    }
                    Text(verbatim: usage.name).lineLimit(1)
                    if usage.isActive {
                        Text("aktiv").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Anzahl Prozesse (z. B. Safari-Tabs), nur wenn es mehr als einer ist.
                    if usage.processCount > 1 {
                        Label { Text(verbatim: "\(usage.processCount)") } icon: { Image(systemName: "square.stack") }
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

    // MARK: 6. Fußzeile

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
}

/// Zeitspanne mit gleichem (erhöhtem/kritischem) Speicherdruck.
private struct PressureSpan: Identifiable {
    let start: Date
    var end: Date
    let pressure: MemoryPressure
    var id: Date { start }
}
