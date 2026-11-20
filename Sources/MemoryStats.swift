//
//  MemoryStats.swift
//  TidyRAM
//
//  Liest den Arbeitsspeicher direkt beim macOS-Kernel aus (Mach-API und
//  sysctl). Es werden keine Rechte benötigt und nichts verändert – diese
//  Datei ist rein lesend.
//
//  Die Aufteilung entspricht der Aktivitätsanzeige von macOS:
//
//    Apps         = internal_page_count − purgeable_count
//                   (anonymer Speicher, den Programme selbst angelegt haben)
//    Reserviert   = wire_count
//                   (vom Kernel fest belegt, kann nie ausgelagert werden)
//    Komprimiert  = compressor_page_count
//                   (Platz, den der Speicherkompressor belegt)
//    Datei-Cache  = external_page_count + purgeable_count
//                   (Kopien von Dateien/Programmcode – jederzeit verwerfbar)
//    Frei         = free_count
//
//  Zum Abgleich im Terminal: `vm_stat` liefert dieselben Zähler in Seiten.
//  Eine Seite ist auf Apple-Silicon-Macs 16 KB groß, auf Intel-Macs 4 KB.
//

import Darwin
import Foundation

// MARK: - Speicherdruck

/// Speicherdruck, wie ihn der Kernel meldet (`kern.memorystatus_vm_pressure_level`).
///
/// Das ist der aussagekräftigste Wert überhaupt: Wenig "freier" RAM ist auf
/// macOS normal (freier RAM wird als Cache genutzt). Erst wenn der Druck
/// steigt, wird der Speicher tatsächlich knapp.
enum MemoryPressure: Sendable {
    case normal, warning, critical, unknown

    /// Deutscher Anzeigetext für das Badge in der Oberfläche.
    var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Erhöht"
        case .critical: "Kritisch"
        case .unknown: "Unbekannt"
        }
    }
}

// MARK: - Momentaufnahme

/// Momentaufnahme des RAM. Alle Werte in Bytes.
///
/// Der Typ ist `Sendable`, weil er nur aus einfachen Werten besteht und damit
/// gefahrlos zwischen Threads weitergereicht werden kann (Swift 6).
struct MemoryStats: Sendable {
    var total: UInt64 = 0        // physisch eingebauter RAM
    var free: UInt64 = 0         // komplett unbenutzt
    var appMemory: UInt64 = 0    // von Programmen belegt
    var wired: UInt64 = 0        // vom System fest reserviert
    var compressed: UInt64 = 0   // vom Kompressor belegt
    var cachedFiles: UInt64 = 0  // Datei-Cache (freigebbar)
    var swapUsed: UInt64 = 0     // auf die SSD ausgelagert
    var pressure: MemoryPressure = .unknown

    /// "Benutzter Speicher" laut Aktivitätsanzeige: Apps + Reserviert + Komprimiert.
    /// Der Datei-Cache zählt bewusst NICHT dazu, weil macOS ihn sofort
    /// freigeben kann, sobald ein Programm Speicher braucht.
    var used: UInt64 { appMemory + wired + compressed }

    /// Anteil von `used` am Gesamtspeicher (0…1) – für die Prozentanzeige.
    var usedFraction: Double {
        total == 0 ? 0 : min(1, Double(used) / Double(total))
    }

    /// Liest die aktuellen Werte vom Kernel. Gibt `nil` zurück, falls der
    /// Kernel-Aufruf fehlschlägt (in der Praxis nicht beobachtet).
    static func current() -> MemoryStats? {
        // Seitengröße ermitteln (16 KB auf Apple Silicon, 4 KB auf Intel).
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }

        // host_statistics64 füllt eine C-Struktur. Die API erwartet einen Zeiger
        // auf integer_t plus die Größe in integer_t-Einheiten – daher das
        // Umdeuten des Zeigers mit withMemoryRebound.
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        // Seiten in Bytes umrechnen.
        let page = UInt64(pageSize)
        var s = MemoryStats()
        s.total = ProcessInfo.processInfo.physicalMemory
        s.free = UInt64(info.free_count) * page
        // `&-` = Subtraktion ohne Absturz bei Unterlauf (Zähler werden nicht
        // atomar gelesen und können sich kurzzeitig überschneiden).
        s.appMemory = UInt64(info.internal_page_count &- info.purgeable_count) * page
        s.wired = UInt64(info.wire_count) * page
        s.compressed = UInt64(info.compressor_page_count) * page
        s.cachedFiles = UInt64(info.external_page_count + info.purgeable_count) * page
        s.swapUsed = swapUsed()
        s.pressure = pressureLevel()
        return s
    }

    /// Belegter Swap-Speicher (entspricht `sysctl vm.swapusage`).
    private static func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    /// Speicherdruck-Stufe des Kernels: 1 = normal, 2 = Warnung, 4 = kritisch.
    private static func pressureLevel() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0
        else { return .unknown }
        switch level {
        case 1: return .normal
        case 2: return .warning
        case 4: return .critical
        default: return .unknown
        }
    }
}

// MARK: - Hilfsfunktionen

/// Tatsächlicher Speicherverbrauch ("Footprint") eines einzelnen Prozesses –
/// derselbe Wert, den die Aktivitätsanzeige in der Spalte "Speicher" zeigt.
///
/// Gibt `nil` zurück, wenn der Prozess nicht (mehr) existiert oder einem
/// anderen Benutzer gehört.
func physicalFootprint(of pid: pid_t) -> UInt64? {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) {
        // proc_pid_rusage erwartet einen generischen rusage_info_t-Zeiger.
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
        }
    }
    return result == 0 ? info.ri_phys_footprint : nil
}

/// Speicherverbrauch einer App inklusive aller Hilfsprozesse.
struct AppFootprint {
    var bytes: UInt64 = 0
    var processCount = 0
}

/// Summiert den Speicher ALLER laufenden Prozesse, gruppiert nach der App,
/// die für sie "verantwortlich" ist.
///
/// Warum? Moderne Apps verteilen ihre Arbeit auf viele Prozesse: Safari startet
/// pro Tab einen "WebContent"-Prozess, Chrome/Firefox/Electron-Apps (z. B.
/// ChatGPT, Claude, VS Code) haben "Helper"-Prozesse. Zählt man nur den
/// Hauptprozess, wirkt Safari mit 300 MB harmlos, obwohl es inkl. Tabs 3 GB
/// belegt.
///
/// Wie? macOS merkt sich für jeden Prozess, welche App ihn verantwortet
/// ("responsible process") – dieselbe Information nutzt die Aktivitätsanzeige.
/// Die Funktion `responsibility_get_pid_responsible_for_pid` ist nicht offiziell
/// dokumentiert, deshalb wird sie zur Laufzeit per `dlsym` gesucht. Fehlt sie in
/// einer künftigen macOS-Version, zählt jeder Prozess einfach für sich selbst –
/// die App funktioniert dann weiter wie vorher.
///
/// Rückgabe: Wörterbuch "PID der verantwortlichen App → Summe". Prozesse anderer
/// Benutzer (z. B. root) sind nicht lesbar und werden übersprungen.
/// Laufzeit: ca. 5 ms für ~700 Prozesse.
func footprintsByResponsibleApp() -> [pid_t: AppFootprint] {
    typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    let responsible: ResponsibleFn? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), // RTLD_DEFAULT
                                            "responsibility_get_pid_responsible_for_pid")
        .map { unsafeBitCast($0, to: ResponsibleFn.self) }

    // Alle Prozess-IDs holen. Etwas Puffer, falls zwischendurch neue entstehen.
    let estimate = Int(proc_listallpids(nil, 0)) + 64
    var pids = [pid_t](repeating: 0, count: estimate)
    let count = pids.withUnsafeMutableBufferPointer {
        proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size))
    }
    guard count > 0 else { return [:] }

    var result: [pid_t: AppFootprint] = [:]
    for pid in pids.prefix(Int(count)) where pid > 0 {
        guard let bytes = physicalFootprint(of: pid) else { continue }
        // Verantwortliche App ermitteln; bei Fehler (≤ 0) zählt der Prozess für sich.
        let owner = responsible?(pid) ?? pid
        let key = owner > 0 ? owner : pid
        result[key, default: AppFootprint()].bytes += bytes
        result[key, default: AppFootprint()].processCount += 1
    }
    return result
}

/// Formatiert Bytes für die Anzeige, z. B. "4,2 GB" (Basis 1024, wie die
/// Aktivitätsanzeige; Dezimalzeichen nach Systemsprache).
func formatBytes(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
}
