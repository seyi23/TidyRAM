//
//  Helpers.swift
//  TidyRAM
//
//  Kleine, reine Rechenfunktionen ohne Seiteneffekte. Sie stehen bewusst
//  getrennt, damit die automatischen Tests (Tests/TidyRAMTests) sie direkt
//  prüfen können.
//

import AppKit

// MARK: - Mini-Grafik für die Menüleiste

enum Sparkline {
    /// Rechnet Werte (0…1) in Punkte für eine Linie der Größe `size` um.
    /// x läuft gleichmäßig von links nach rechts, y von unten (0) nach oben (1).
    /// Ein kleiner Rand oben/unten verhindert, dass die Linie abgeschnitten wird.
    static func points(values: [Double], size: CGSize, inset: CGFloat = 1.5) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let usableHeight = size.height - 2 * inset
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let clamped = min(max(value, 0), 1)
            return CGPoint(x: CGFloat(index) * step, y: inset + CGFloat(clamped) * usableHeight)
        }
    }

    /// Zoomt auf den tatsächlichen Wertebereich, damit Schwankungen sichtbar
    /// werden (z. B. 60–75 % statt 0–100 %). Die Spanne ist mindestens
    /// `minimumSpan` groß, damit kleines Rauschen nicht wie ein Sprung aussieht.
    static func normalized(_ values: [Double], minimumSpan: Double = 0.2) -> [Double] {
        guard let lo = values.min(), let hi = values.max() else { return [] }
        var low = lo, high = hi
        if high - low < minimumSpan {
            let center = (low + high) / 2
            low = center - minimumSpan / 2
            high = center + minimumSpan / 2
        }
        // Im Bereich 0…1 halten, Spanne dabei beibehalten.
        if low < 0 { high -= low; low = 0 }
        if high > 1 { low -= high - 1; high = 1 }
        let span = high - low
        return values.map { span > 0 ? ($0 - low) / span : 0.5 }
    }

    /// Zeichnet die Mini-Grafik als Vorlagen-Bild ("Template"). macOS färbt es
    /// automatisch passend zur hellen oder dunklen Menüleiste.
    /// Dünne Grundlinie = Boden des Ausschnitts, Linie = belegter Speicher.
    static func image(values: [Double], size: CGSize = CGSize(width: 34, height: 15)) -> NSImage {
        let pts = points(values: normalized(values), size: size)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.withAlphaComponent(0.35).setStroke()
            let base = NSBezierPath()
            base.move(to: CGPoint(x: 0, y: 0.5))
            base.line(to: CGPoint(x: rect.width, y: 0.5))
            base.lineWidth = 1
            base.stroke()

            guard let first = pts.first else { return true }
            // Gefüllte Fläche unter der Linie (leicht transparent) …
            let area = NSBezierPath()
            area.move(to: CGPoint(x: first.x, y: 0))
            pts.forEach { area.line(to: $0) }
            area.line(to: CGPoint(x: pts.last!.x, y: 0))
            area.close()
            NSColor.black.withAlphaComponent(0.3).setFill()
            area.fill()
            // … und die Linie selbst.
            let line = NSBezierPath()
            line.move(to: first)
            pts.dropFirst().forEach { line.line(to: $0) }
            line.lineWidth = 1.5
            line.lineJoinStyle = .round
            NSColor.black.setStroke()
            line.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - Swap-Warnung

enum SwapWarning {
    /// true, wenn der Swap die Grenze gerade ÜBERSCHRITTEN hat (vorher darunter,
    /// jetzt darüber). So kommt pro Überschreitung nur eine Mitteilung.
    /// `thresholdGB == 0` heißt: Warnung ausgeschaltet.
    static func crossed(previous: UInt64, current: UInt64, thresholdGB: Int) -> Bool {
        guard thresholdGB > 0 else { return false }
        let threshold = UInt64(thresholdGB) * 1_073_741_824
        return previous < threshold && current >= threshold
    }
}

// MARK: - Eigenverbrauch

enum SelfUsage {
    /// CPU-Verbrauch der eigenen App in Sekunden (Benutzer- + Systemzeit) seit dem Start.
    static func cpuSeconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// Durchschnittliche CPU-Last in Prozent eines Kerns zwischen zwei Messungen.
    static func cpuPercent(cpuSecondsDelta: Double, wallSecondsDelta: Double) -> Double {
        guard wallSecondsDelta > 0, cpuSecondsDelta >= 0 else { return 0 }
        return cpuSecondsDelta / wallSecondsDelta * 100
    }
}

// MARK: - Link-Befehle

extension URLCommands {
    /// Liest den Befehl aus einem Link: "tidyram://free" → "free".
    /// Andere Schemata → nil. Groß-/Kleinschreibung egal.
    nonisolated static func command(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "tidyram" else { return nil }
        let raw = url.host ?? url.path
        let command = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return command.isEmpty ? nil : command
    }
}
