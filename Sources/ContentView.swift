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

/// Die Bereiche in Balken und Legende. Farbe, Titel und Erklärung stehen hier
/// zentral, damit Balken, Legende und Details immer übereinstimmen.
/// Swap liegt auf der SSD (nicht im RAM) und erscheint daher nur in der Legende.
enum Segment: CaseIterable {
    case app, wired, compressed, cache, free, swap

    /// Bereiche, die im RAM liegen und im Balken gezeichnet werden.
    static let barCases: [Segment] = [.app, .wired, .compressed, .cache, .free]

    var title: String {
        switch self {
        case .app: String(localized: "Apps")
        case .wired: String(localized: "Reserviert")
        case .compressed: String(localized: "Komprimiert")
        case .cache: String(localized: "Datei-Cache")
        case .free: String(localized: "Frei")
        case .swap: String(localized: "Swap")
        }
    }

    var color: Color {
        switch self {
        case .app: .blue
        case .wired: .orange
        case .compressed: .purple
        case .cache: .gray.opacity(0.6)
        case .free: .green.opacity(0.5)
        case .swap: .secondary
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
        case .swap: s.swapUsed
        }
    }

    /// Erklärung in einfachen Worten – erscheint beim Aufklappen.
    var explanation: String {
        switch self {
        case .app:
            String(localized: "Speicher, den Programme selbst angelegt haben: offene Dokumente, Browser-Tabs, Bilder, Daten. Er wird nur frei, wenn du die App schließt.")
        case .wired:
            String(localized: "Vom macOS-Kernel fest gesperrt: Kernel, Treiber und auf Apple Silicon vor allem Grafikspeicher. Kann weder ausgelagert noch freigegeben werden.")
        case .compressed:
            String(localized: "Selten genutzte App-Daten, die macOS zusammenpresst, statt sie auf die SSD auszulagern. Das ist schneller als Swap, kostet aber etwas Rechenzeit.")
        case .cache:
            String(localized: "Kopien von Dateien und Programmcode, die ohnehin auf der SSD liegen. macOS gibt sie sofort her, wenn Programme Speicher brauchen. Genau diesen Bereich leert der Button.")
        case .free:
            String(localized: "Komplett ungenutzt. Wenig freier Speicher ist normal, denn macOS nutzt freien RAM als Cache.")
        case .swap:
            String(localized: "Auf die SSD ausgelagerter Speicher. Wächst er bei erhöhtem Speicherdruck, reicht der RAM nicht aus.")
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

    /// Welcher Bereich der Legende gerade aufgeklappt ist (nil = keiner).
    @State private var expanded: Segment?
    /// Messpunkt unter dem Mauszeiger in der Verlaufsgrafik.
    @State private var hoverPoint: HistoryPoint?

    init(initiallyExpanded: Segment? = nil) {
        _expanded = State(initialValue: initiallyExpanded)
    }

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
            let total = max(1, Double(Segment.barCases.reduce(0) { $0 + $1.value(s) }))
            HStack(spacing: 1) {
                ForEach(Segment.barCases, id: \.self) { seg in
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

    /// Legende: Jede Zeile lässt sich per Klick aufklappen und zeigt dann eine
    /// Erklärung und – wo macOS sie liefert – Detailwerte.
    private func legend(_ s: MemoryStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Segment.allCases, id: \.self) { seg in
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { expanded = expanded == seg ? nil : seg }
                    } label: {
                        HStack(spacing: 8) {
                            if seg == .swap {
                                Image(systemName: "arrow.left.arrow.right").font(.caption2).frame(width: 8)
                            } else {
                                Circle().fill(seg.color).frame(width: 8, height: 8)
                            }
                            Text(seg.title)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(expanded == seg ? 90 : 0))
                            Spacer()
                            Text(formatBytes(seg.value(s))).monospacedDigit()
                        }
                        .contentShape(Rectangle())  // ganze Zeile klickbar
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(seg == .swap ? .secondary : .primary)
                    .help("Klicken für Details")

                    if expanded == seg {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(seg.explanation).foregroundStyle(.secondary)
                            ForEach(details(seg, s), id: \.self) { line in
                                Text(line).monospacedDigit()
                            }
                        }
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .font(.callout)
    }

    /// Detailwerte pro Bereich. Leere Liste = nur die Erklärung anzeigen.
    private func details(_ seg: Segment, _ s: MemoryStats) -> [String] {
        switch seg {
        case .app:
            guard let top = monitor.apps.first else { return [] }
            return [String(localized: "Größte App: \(top.name) mit \(formatBytes(top.footprint))")]
        case .wired:
            guard let gpu = s.gpuInUse else { return [] }
            return [String(localized: "Grafik (GPU) nutzt gerade \(formatBytes(gpu)) – das meiste davon zählt hierzu.")]
        case .compressed:
            guard s.compressed > 0, s.compressedOriginal > s.compressed else { return [] }
            let ratio = s.compressionRatio.formatted(.number.precision(.fractionLength(1)))
            return [
                String(localized: "\(formatBytes(s.compressedOriginal)) App-Daten auf \(formatBytes(s.compressed)) gepresst"),
                String(localized: "Ersparnis: \(formatBytes(s.compressedOriginal - s.compressed)) (Faktor \(ratio))"),
            ]
        case .cache:
            guard s.purgeable > 0 else { return [] }
            return [String(localized: "Davon von Apps als sofort verwerfbar markiert: \(formatBytes(s.purgeable))")]
        case .free:
            return [String(localized: "Eingebauter Arbeitsspeicher insgesamt: \(formatBytes(s.total))")]
        case .swap:
            var lines = [String(localized: "Swap-Dateien auf der SSD: \(formatBytes(s.swapUsed)) von \(formatBytes(s.swapTotal)) belegt")]
            if s.swappedOut > 0 {
                lines.append(String(localized: "Seit dem Start ausgelagert: \(formatBytes(s.swappedOut)), zurückgeholt: \(formatBytes(s.swappedIn))"))
            }
            return lines
        }
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
                    // Markierung des Messpunkts unter dem Mauszeiger.
                    if let hoverPoint {
                        RuleMark(x: .value("Zeit", hoverPoint.date))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        PointMark(x: .value("Zeit", hoverPoint.date),
                                  y: .value("Belegt", hoverPoint.usedFraction * 100))
                            .foregroundStyle(pressureColor(hoverPoint.pressure) == .secondary ? .blue : pressureColor(hoverPoint.pressure))
                            .symbolSize(30)
                    }
                }
                // Mausbewegung über der Grafik → nächstgelegenen Messpunkt merken.
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    hoverPoint = nearestPoint(at: location, proxy: proxy, geo: geo)
                                case .ended:
                                    hoverPoint = nil
                                }
                            }
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

                // Unter der Grafik: Details zum Punkt unter der Maus, sonst eine
                // Zusammenfassung "Wer frisst Speicher?".
                Group {
                    if let hoverPoint {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(hoverLine(hoverPoint))
                            if let name = hoverPoint.topApp {
                                Text(String(localized: "Größte App: \(name) mit \(formatBytes(hoverPoint.topAppBytes))"))
                            }
                        }
                    } else if let summary = historySummary {
                        Text(summary)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Findet den Messpunkt, der dem Mauszeiger am nächsten liegt (max. 30 s Abstand).
    private func nearestPoint(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) -> HistoryPoint? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let x = location.x - geo[plotFrame].origin.x
        guard let date: Date = proxy.value(atX: x),
              let nearest = monitor.history.min(by: {
                  abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
              }),
              abs(nearest.date.timeIntervalSince(date)) <= 30 else { return nil }
        return nearest
    }

    /// "19:42 · 68% belegt · Erhöht"
    private func hoverLine(_ point: HistoryPoint) -> String {
        let time = point.date.formatted(date: .omitted, time: .shortened)
        let percent = "\(Int((point.usedFraction * 100).rounded()))%"
        return String(localized: "\(time) · \(percent) belegt · \(point.pressure.label)")
    }

    /// "Wer frisst Speicher?" – welche App bei Speicherdruck am häufigsten vorne
    /// lag, sonst der größte Verbraucher der letzten Stunde.
    private var historySummary: String? {
        let pressured = monitor.history.filter { $0.pressure == .warning || $0.pressure == .critical }
        let counts = Dictionary(grouping: pressured.compactMap(\.topApp), by: { $0 }).mapValues(\.count)
        if let name = counts.max(by: { $0.value < $1.value })?.key {
            return String(localized: "Bei Speicherdruck vorne: \(name)")
        }
        if let peak = monitor.history.max(by: { $0.topAppBytes < $1.topAppBytes }),
           let name = peak.topApp, peak.topAppBytes > 0 {
            return String(localized: "Größter Verbraucher der letzten Stunde: \(name) (bis \(formatBytes(peak.topAppBytes)))")
        }
        return nil
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
