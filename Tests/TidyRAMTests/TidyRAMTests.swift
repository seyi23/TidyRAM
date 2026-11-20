//
//  TidyRAMTests.swift
//  TidyRAM
//
//  Automatische Tests mit Swift Testing. Ausführen mit:
//
//      swift test
//
//  GitHub Actions führt sie bei jedem Push und Pull Request aus.
//  Getestet werden vor allem die Rechen- und Entscheidungsregeln – also genau
//  die Stellen, an denen sich ein Fehler unbemerkt einschleichen könnte.
//

import Foundation
import Testing
@testable import TidyRAM

// MARK: - Speicherwerte vom Kernel

@Suite("Speicherwerte")
struct MemoryStatsTests {
    @Test("Kernel liefert plausible Werte")
    func plausibleValues() throws {
        let s = try #require(MemoryStats.current())
        #expect(s.total == ProcessInfo.processInfo.physicalMemory)
        #expect(s.total > 0)
        #expect(s.used == s.appMemory + s.wired + s.compressed)
        #expect((0...1).contains(s.usedFraction))
        #expect(s.swapUsed <= s.swapTotal || s.swapTotal == 0)
        // Jeder einzelne Bereich muss in den RAM passen. (Die Summe aller Bereiche
        // wird bewusst NICHT geprüft: Die Kernel-Zähler sind nicht streng additiv –
        // manche Seiten zählen in zwei Bereichen. Auf virtuellen Macs, z. B. bei
        // GitHub Actions, liegt die Summe deshalb manchmal über dem RAM.)
        for value in [s.appMemory, s.wired, s.compressed, s.cachedFiles, s.free] {
            #expect(value <= s.total)
        }
    }

    @Test("Eigener Prozess hat einen Speicherverbrauch")
    func ownFootprint() throws {
        let fp = try #require(physicalFootprint(of: ProcessInfo.processInfo.processIdentifier))
        #expect(fp > 0)
    }

    @Test("Prozesse werden der verantwortlichen App zugeordnet")
    func responsibleGrouping() {
        let totals = footprintsByResponsibleApp()
        #expect(!totals.isEmpty)
        // Jede Gruppe hat mindestens einen Prozess und Speicher.
        #expect(totals.values.allSatisfy { $0.processCount >= 1 && $0.bytes > 0 })
    }

    @Test("Kompressionsfaktor")
    func compressionRatio() {
        var s = MemoryStats()
        #expect(s.compressionRatio == 0)          // nichts komprimiert → 0, kein Absturz
        s.compressed = 1_000
        s.compressedOriginal = 2_500
        #expect(s.compressionRatio == 2.5)
    }
}

// MARK: - Mitteilungen

@Suite("Mitteilungs-Regeln")
struct NotificationRuleTests {
    @Test("Speicherdruck-Stufen lösen wie eingestellt aus",
          arguments: [
            (NotifyLevel.off, MemoryPressure.critical, false),
            (.critical, .warning, false),
            (.critical, .critical, true),
            (.warning, .warning, true),
            (.warning, .critical, true),
            (.warning, .normal, false),
          ])
    func pressureTriggers(level: NotifyLevel, pressure: MemoryPressure, expected: Bool) {
        #expect(level.triggers(pressure) == expected)
    }

    @Test("Swap-Warnung nur beim Überschreiten der Grenze")
    func swapCrossing() {
        let gb: UInt64 = 1_073_741_824
        #expect(SwapWarning.crossed(previous: 3 * gb, current: 5 * gb, thresholdGB: 4))    // überschritten
        #expect(!SwapWarning.crossed(previous: 5 * gb, current: 6 * gb, thresholdGB: 4))   // war schon drüber
        #expect(!SwapWarning.crossed(previous: 1 * gb, current: 2 * gb, thresholdGB: 4))   // bleibt drunter
        #expect(!SwapWarning.crossed(previous: 0, current: 99 * gb, thresholdGB: 0))       // ausgeschaltet
        #expect(SwapWarning.crossed(previous: 4 * gb - 1, current: 4 * gb, thresholdGB: 4)) // genau auf der Grenze
    }
}

// MARK: - Verlauf

@Suite("Verlauf")
struct HistoryTests {
    private func point(_ seconds: TimeInterval, used: Double, pressure: MemoryPressure = .normal,
                       app: String? = nil, bytes: UInt64 = 0) -> HistoryPoint {
        HistoryPoint(date: Date(timeIntervalSince1970: seconds), usedFraction: used,
                     pressure: pressure, topApp: app, topAppBytes: bytes)
    }

    @Test("Verdichten: Durchschnitt, schlimmster Druck, größte App")
    func downsample() {
        let points = [
            point(0, used: 0.2, app: "A", bytes: 100),
            point(10, used: 0.4, pressure: .critical, app: "B", bytes: 300),
            point(20, used: 0.6, pressure: .warning, app: "C", bytes: 200),
            point(60, used: 0.9),                               // nächster Block
        ]
        let result = points.downsampled(bucket: 60)
        #expect(result.count == 2)
        #expect(abs(result[0].usedFraction - 0.4) < 0.0001)
        #expect(result[0].pressure == .critical)
        #expect(result[0].topApp == "B")
        #expect(result[0].topAppBytes == 300)
        #expect(result[1].usedFraction == 0.9)
    }

    @Test("Verdichten mit zu wenig Punkten ändert nichts")
    func downsampleTrivial() {
        let single = [point(0, used: 0.5)]
        #expect(single.downsampled(bucket: 60) == single)
        #expect([HistoryPoint]().downsampled(bucket: 60).isEmpty)
    }

    @Test("Zeiträume bleiben unter ~360 Anzeigepunkten", arguments: HistoryRange.allCases)
    func rangeBuckets(range: HistoryRange) {
        #expect(range.seconds / range.bucket <= 361)
    }

    @Test("Messpunkte überstehen Speichern und Laden (JSON)")
    func codableRoundTrip() throws {
        let original = [point(1_000, used: 0.5, pressure: .warning, app: "Safari", bytes: 42)]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([HistoryPoint].self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - Mini-Grafik, Eigenverbrauch, Links

@Suite("Hilfsfunktionen")
struct HelperTests {
    @Test("Mini-Grafik: Punkte füllen die Breite, 0 % unten, 100 % oben")
    func sparklinePoints() {
        let size = CGSize(width: 30, height: 10)
        let pts = Sparkline.points(values: [0, 0.5, 1], size: size, inset: 0)
        #expect(pts.count == 3)
        #expect(pts.first == CGPoint(x: 0, y: 0))
        #expect(pts[1] == CGPoint(x: 15, y: 5))
        #expect(pts.last == CGPoint(x: 30, y: 10))
        // Werte außerhalb 0…1 werden begrenzt, einzelne Werte ergeben keine Linie.
        #expect(Sparkline.points(values: [-1, 2], size: size, inset: 0).map(\.y) == [0, 10])
        #expect(Sparkline.points(values: [0.5], size: size).isEmpty)
    }

    @Test("Mini-Grafik zoomt auf den Wertebereich")
    func sparklineNormalize() {
        // Großer Bereich: min → 0, max → 1
        #expect(Sparkline.normalized([0.6, 0.9]) == [0, 1])
        // Kleiner Bereich: wird auf mindestens 0,2 gespreizt, Mitte bleibt Mitte
        let n = Sparkline.normalized([0.69, 0.71])
        // Spanne 0,6…0,8 → 0,69 liegt bei 45 %, 0,71 bei 55 %
        #expect(abs(n[0] - 0.45) < 0.0001 && abs(n[1] - 0.55) < 0.0001)
        // Am Rand (0 %) wird der Ausschnitt nach innen verschoben, nicht abgeschnitten
        #expect(Sparkline.normalized([0, 0.05]).allSatisfy { (0...1).contains($0) })
        #expect(Sparkline.normalized([]).isEmpty)
    }

    @Test("CPU-Last in Prozent")
    func cpuPercent() {
        #expect(SelfUsage.cpuPercent(cpuSecondsDelta: 0.02, wallSecondsDelta: 2) == 1)
        #expect(SelfUsage.cpuPercent(cpuSecondsDelta: 1, wallSecondsDelta: 0) == 0)   // keine Division durch 0
        #expect(SelfUsage.cpuSeconds() >= 0)
    }

    @Test("Link-Befehle werden erkannt",
          arguments: [
            ("tidyram://free", "free"),
            ("TIDYRAM://Free", "free"),
            ("tidyram:///free/", "free"),
            ("https://example.com/free", nil),
            ("tidyram://", nil),
          ] as [(String, String?)])
    func urlCommands(link: String, expected: String?) throws {
        let url = try #require(URL(string: link))
        #expect(URLCommands.command(from: url) == expected)
    }

    @Test("Byte-Anzeige")
    func bytes() {
        #expect(formatBytes(0).contains("0"))                // "0 KB", nicht "Zero KB"
        #expect(!formatBytes(0).lowercased().contains("zero"))
        #expect(formatBytes(1_073_741_824).contains("GB"))
    }
}
