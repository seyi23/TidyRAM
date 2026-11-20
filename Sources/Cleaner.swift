//
//  Cleaner.swift
//  TidyRAM
//
//  Die eigentliche "Aufräum"-Funktion.
//
//  WAS PASSIERT BEIM FREIGEBEN?
//  ----------------------------
//  Es wird `/usr/sbin/purge` ausgeführt – ein Werkzeug, das Apple mit macOS
//  ausliefert. purge verwirft den Datei-Cache: Seiten im RAM, die eine
//  identische Kopie auf der SSD haben (gelesene Dateien, Programmcode,
//  Bibliotheken).
//
//  WARUM IST DAS UNGEFÄHRLICH?
//  ---------------------------
//  • Daten, die Programme selbst erzeugt haben (offene Dokumente, Tabs,
//    ungesicherte Änderungen), liegen im "App-Speicher" bzw. im Kompressor –
//    diese Bereiche fasst purge NICHT an.
//  • Es wird kein Programm beendet und kein Prozess manipuliert.
//  • Schlimmster Fall: Eine Datei, die gerade aus dem Cache geflogen ist,
//    wird beim nächsten Zugriff einmal neu von der SSD geladen (kurz langsamer).
//
//  WARUM ADMIN-RECHTE?
//  -------------------
//  purge läuft nur als root. Es gibt zwei Wege, die nacheinander probiert werden:
//    1. `sudo -n /usr/sbin/purge` – klappt ohne Passwort, wenn eine sudoers-Regel
//       nur für purge eingerichtet ist (siehe README, scripts/enable-passwordless.sh).
//    2. Fallback: AppleScript "with administrator privileges" – macOS zeigt dann
//       seinen eigenen Passwort-/Touch-ID-Dialog.
//

import Foundation

/// Fehler, die beim Freigeben auftreten können.
enum CleanError: LocalizedError {
    /// Der Benutzer hat im Passwortdialog "Nicht erlauben" gewählt.
    case cancelled
    /// purge oder osascript ist mit einer Fehlermeldung gescheitert.
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: "Abgebrochen."
        case .failed(let msg): "Fehler: \(msg)"
        }
    }
}

/// Bündelt alle Aktionen, die Admin-Rechte brauchen.
/// Ein `enum` ohne Fälle dient hier nur als Namensraum für statische Funktionen.
enum Cleaner {
    /// Absoluter Pfad – bewusst fest im Code, damit nie ein anderes Programm
    /// gleichen Namens (z. B. aus $PATH) mit Admin-Rechten gestartet wird.
    static let purgePath = "/usr/sbin/purge"

    /// Gibt den Datei-Cache frei. Läuft auf einem Hintergrund-Thread, damit die
    /// Oberfläche nicht einfriert, während macOS nach dem Passwort fragt.
    static func purgeFileCache() async throws {
        try await Task.detached(priority: .userInitiated) {
            // Weg 1: ohne Passwort. `-n` (non-interactive) heißt: sudo fragt nie
            // nach einem Passwort, sondern scheitert sofort, wenn keine
            // passende NOPASSWD-Regel existiert.
            if run("/usr/bin/sudo", ["-n", purgePath]).status == 0 { return }

            // Weg 2: macOS-Dialog für Admin-Rechte über AppleScript.
            // Hinweis: Ab macOS 26/27 ersetzt das System den Text aus
            // "with prompt" durch eine eigene Warnung ("Apple konnte nicht
            // bestätigen …"), weil die App nicht von Apple notarisiert ist.
            let result = run("/usr/bin/osascript", [
                "-e",
                "do shell script \"\(purgePath)\" with prompt \"TidyRAM möchte ungenutzten Datei-Cache freigeben.\" with administrator privileges",
            ])
            guard result.status == 0 else {
                // AppleScript-Fehler -128 = "User canceled".
                if result.stderr.contains("-128") { throw CleanError.cancelled }
                throw CleanError.failed(result.stderr.isEmpty ? "purge fehlgeschlagen" : result.stderr)
            }
        }.value
    }

    /// Prüft, ob purge per sudoers-Regel ohne Passwort erlaubt ist.
    /// `sudo -n -l <befehl>` gibt Exit-Code 0 zurück, wenn der Befehl ohne
    /// Passwort ausgeführt werden darf – es wird dabei nichts ausgeführt.
    static func isPasswordless() async -> Bool {
        await Task.detached {
            run("/usr/bin/sudo", ["-n", "-l", purgePath]).status == 0
        }.value
    }

    /// Startet ein Programm, wartet auf das Ende und liefert Exit-Code und
    /// Fehlerausgabe. Es wird keine Shell benutzt – die Argumente werden
    /// direkt übergeben, damit nichts falsch interpretiert werden kann.
    private static func run(_ path: String, _ args: [String]) -> (status: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice  // sudo darf nie auf Eingabe warten
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        // Erst die Ausgabe lesen, dann warten – sonst kann ein voller
        // Pipe-Puffer den Prozess blockieren.
        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let msg = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus, msg)
    }
}
