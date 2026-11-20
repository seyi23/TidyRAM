//
//  History.swift
//  TidyRAM
//
//  Der Speicher-Verlauf: Messpunkte, Zeiträume (1 h / 6 h / 24 h),
//  Verdichten für die Anzeige und Speichern auf der Festplatte.
//
//  Gespeichert wird lokal in
//      ~/Library/Application Support/TidyRAM/history.json
//  (höchstens 24 Stunden, ein Punkt alle 10 Sekunden ≈ 8 640 Punkte, < 1 MB).
//  Die Datei enthält Uhrzeit, Belegung, Speicherdruck und den Namen der jeweils
//  größten App. Sie verlässt den Mac nie – TidyRAM hat keinen Netzwerkzugriff.
//

import Foundation

/// Ein Messpunkt für die Verlaufsgrafik.
struct HistoryPoint: Identifiable, Codable, Sendable, Equatable {
    let date: Date
    let usedFraction: Double      // 0…1
    let pressure: MemoryPressure
    let topApp: String?           // App mit dem größten Speicherverbrauch zu diesem Zeitpunkt
    let topAppBytes: UInt64       // … und ihr Verbrauch
    var id: Date { date }
}

/// Wählbarer Zeitraum der Verlaufsgrafik.
enum HistoryRange: Int, CaseIterable, Identifiable {
    case hour1 = 1, hour6 = 6, hour24 = 24

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) * 3600 }
    var title: String { "\(rawValue) h" }

    /// Zusammenfassung pro Anzeige-Punkt: Ziel sind höchstens ~360 Punkte,
    /// damit die Grafik flüssig bleibt (1 h: 10 s, 6 h: 1 min, 24 h: 4 min).
    var bucket: TimeInterval {
        switch self {
        case .hour1: 10
        case .hour6: 60
        case .hour24: 240
        }
    }
}

extension MemoryPressure {
    /// Rangfolge für "der schlimmste Druck im Zeitraum".
    var severity: Int {
        switch self {
        case .unknown: 0
        case .normal: 1
        case .warning: 2
        case .critical: 3
        }
    }
}

extension Array where Element == HistoryPoint {
    /// Fasst Messpunkte zu Zeitblöcken der Länge `bucket` zusammen:
    /// Belegung = Durchschnitt, Speicherdruck = schlimmster Wert,
    /// größte App = die mit dem höchsten Verbrauch im Block.
    /// Die Eingabe muss zeitlich sortiert sein (ist sie im Verlauf immer).
    func downsampled(bucket: TimeInterval) -> [HistoryPoint] {
        guard bucket > 0, count > 1 else { return self }
        var result: [HistoryPoint] = []
        var group: [HistoryPoint] = []
        var groupKey: Int?

        func flush() {
            guard let first = group.first else { return }
            let average = group.map(\.usedFraction).reduce(0, +) / Double(group.count)
            let worst = group.max { $0.pressure.severity < $1.pressure.severity }!.pressure
            let top = group.max { $0.topAppBytes < $1.topAppBytes }!
            result.append(HistoryPoint(date: first.date, usedFraction: average, pressure: worst,
                                       topApp: top.topApp, topAppBytes: top.topAppBytes))
            group.removeAll(keepingCapacity: true)
        }

        for point in self {
            let key = Int(point.date.timeIntervalSince1970 / bucket)
            if key != groupKey { flush(); groupKey = key }
            group.append(point)
        }
        flush()
        return result
    }
}

/// Laden und Speichern des Verlaufs.
enum HistoryStore {
    /// ~/Library/Application Support/TidyRAM/history.json
    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TidyRAM", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    /// Lädt den gespeicherten Verlauf. Fehlende oder kaputte Datei → leer.
    static func load(maxAge: TimeInterval, now: Date = Date()) -> [HistoryPoint] {
        guard let data = try? Data(contentsOf: fileURL),
              let points = try? JSONDecoder().decode([HistoryPoint].self, from: data) else { return [] }
        return points.filter { now.timeIntervalSince($0.date) <= maxAge }.sorted { $0.date < $1.date }
    }

    /// Schreibt den Verlauf atomar (erst in eine Hilfsdatei, dann umbenennen),
    /// damit bei einem Absturz nie eine halbe Datei übrig bleibt.
    static func save(_ points: [HistoryPoint]) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(points)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("Verlauf speichern fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }
}
