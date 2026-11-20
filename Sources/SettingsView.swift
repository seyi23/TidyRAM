//
//  SettingsView.swift
//  TidyRAM
//
//  Das Einstellungsfenster (Zahnrad im TidyRAM-Fenster oder ⌘, ).
//  Alle Werte werden sofort gespeichert – es gibt keinen "Sichern"-Knopf.
//

import SwiftUI

struct SettingsView: View {
    @Environment(MemoryMonitor.self) private var monitor
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        @Bindable var monitor = monitor

        Form {
            // Menüleiste
            Section("Menüleiste") {
                Picker("Anzeige", selection: $settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            // Mitteilungen
            Section {
                Picker("Mitteilung senden", selection: $settings.notifyLevel) {
                    ForEach(NotifyLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                Picker("Warnen, wenn Swap über", selection: $settings.swapWarningGB) {
                    Text("Aus").tag(0)
                    ForEach([2, 4, 8, 16], id: \.self) { Text(verbatim: "\($0) GB").tag($0) }
                }
            } header: {
                Text("Mitteilungen")
            } footer: {
                Text("Speicherdruck: höchstens alle 10 Minuten. Swap: höchstens alle 30 Minuten. Jeweils mit der App, die gerade am meisten Speicher belegt.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Automatisch freigeben
            Section {
                Toggle("Datei-Cache bei erhöhtem Speicherdruck automatisch freigeben",
                       isOn: $settings.autoClean)
                    .disabled(!monitor.passwordless)
                Picker("Höchstens alle", selection: $settings.autoCleanMinutes) {
                    Text("15 Minuten").tag(15)
                    Text("30 Minuten").tag(30)
                    Text("60 Minuten").tag(60)
                }
                .disabled(!settings.autoClean || !monitor.passwordless)
            } header: {
                Text("Automatisch freigeben")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if !monitor.passwordless {
                        Label("Nur verfügbar, wenn das Freigeben ohne Passwort eingerichtet ist (siehe README).",
                              systemImage: "lock")
                    }
                    Text("Ehrlicher Hinweis: macOS verwaltet den Cache selbst sehr gut. Wirklich Platz schafft nur das Schließen großer Apps.")
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            // Tastenkürzel
            Section("Tastenkürzel") {
                Toggle(isOn: $settings.hotKeyEnabled) {
                    Text("\(GlobalHotKey.displayString) gibt RAM von überall frei")
                }
                .onChange(of: settings.hotKeyEnabled) { monitor.updateHotKey() }
            }

            // Steuerung per Link
            Section {
                LabeledContent("Im Terminal") {
                    Text(verbatim: "open -g tidyram://free").font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            } header: {
                Text("Steuerung per Link")
            } footer: {
                Text("Funktioniert auch in Kurzbefehlen (Aktion „URL öffnen“), Raycast, Alfred und Skripten. Das Ergebnis kommt als Mitteilung.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Allgemein
            Section("Allgemein") {
                Picker("Aktualisieren alle", selection: $settings.refreshSeconds) {
                    Text("2 Sekunden").tag(2)
                    Text("5 Sekunden").tag(5)
                    Text("10 Sekunden").tag(10)
                }
                Toggle("Bei Anmeldung starten", isOn: $monitor.launchAtLogin)
            }

            // Über
            Section("Über TidyRAM") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                LabeledContent("Lizenz") { Text("MIT – kostenlos & Open Source") }
                LabeledContent("Eigenverbrauch") {
                    Text(verbatim: "\(formatBytes(monitor.selfFootprint)) · \(monitor.selfCPUPercent.formatted(.number.precision(.fractionLength(1)))) % CPU")
                        .monospacedDigit()
                }
                .help("Speicher und durchschnittliche CPU-Last von TidyRAM selbst")
                Link(destination: URL(string: "https://github.com/seyi23/TidyRAM")!) {
                    Label { Text(verbatim: "github.com/seyi23/TidyRAM") } icon: { Image(systemName: "link") }
                }
                Text("Vibe-coded mit Claude")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
