# Mitmachen / Contributing

**Deutsch** | [English](#english)

Danke, dass du TidyRAM besser machen willst! Fehlermeldungen, Ideen, Übersetzungen und Pull Requests sind willkommen.

## Grundsatz

**Nichts darf Programme beschädigen oder Daten gefährden.** Konkret:

- kein erzwungenes Beenden (`kill -9`, `forceTerminate`),
- kein Eingriff in den Speicher fremder Prozesse (nur lesen),
- mit Admin-Rechten nur fest eingetragene Apple-Werkzeuge (derzeit nur `/usr/sbin/purge`),
- keine Netzwerkzugriffe, kein Tracking.

## Fehler melden oder Idee vorschlagen

[Issue öffnen](https://github.com/seyi23/TidyRAM/issues/new/choose) und die passende Vorlage wählen. Bei Fehlern helfen macOS-Version, Mac-Modell (Apple Silicon oder Intel) und TidyRAM-Version (Einstellungen → Über TidyRAM).

## Bauen und testen

```bash
git clone https://github.com/seyi23/TidyRAM.git
```
```bash
cd TidyRAM
```
```bash
./build.sh
```
```bash
open build/TidyRAM.app
```

Benötigt nur Xcode oder die Command Line Tools (`xcode-select --install`). Es gibt kein Xcode-Projekt, `build.sh` ruft `swiftc` direkt auf. Der Code ist auf Deutsch kommentiert. Einstieg: [`Sources/TidyRAMApp.swift`](Sources/TidyRAMApp.swift).

Mit `./scripts/install.sh` landet dein Build in `/Applications` und startet neu.

## Tests

```bash
swift test
```

Die Tests (Swift Testing, Ordner `Tests/TidyRAMTests`) prüfen u. a. die Kernel-Werte, die Prozess-Zuordnung, die Regeln für Mitteilungen und Swap-Warnung, das Verdichten und Speichern des Verlaufs, die Mini-Grafik und die Link-Befehle. GitHub Actions führt sie bei jedem Push und Pull Request aus. Neue Logik bitte möglichst als reine Funktion schreiben (siehe `Sources/Helpers.swift`) und einen Test ergänzen.

In Xcode öffnen: `open Package.swift`, dann ⌘U für die Tests.

## Pull Request

1. Repository forken, Branch anlegen
2. Änderung machen, mit `./build.sh` bauen, App ausprobieren, `swift test` ausführen
3. Bei neuen Texten: Übersetzung in `Resources/en.lproj/Localizable.strings` ergänzen
4. Pull Request öffnen. GitHub Actions baut ihn automatisch

## Weitere Sprache hinzufügen

Deutsch ist die Entwicklungssprache: Die deutschen Texte im Code sind zugleich die Schlüssel.

1. `Resources/en.lproj` kopieren, z. B. nach `Resources/fr.lproj`
2. In `Localizable.strings` jeweils die **rechte** Seite übersetzen (Platzhalter `%@` und `%lld` stehen lassen)
3. In `build.sh` bei `CFBundleLocalizations` den Sprachcode ergänzen, z. B. `<string>fr</string>`
4. Testen: `build/TidyRAM.app/Contents/MacOS/TidyRAM -AppleLanguages "(fr)"`

## Neue Version veröffentlichen (Maintainer)

1. `VERSION` in `build.sh` erhöhen und Abschnitt in `CHANGELOG.md` ergänzen
2. Committen und pushen
3. Tag setzen und pushen. GitHub Actions baut und veröffentlicht das Release:
   ```bash
   git tag -a v1.5.0 -m "TidyRAM 1.5.0"
   ```
   ```bash
   git push origin v1.5.0
   ```
4. Homebrew aktualisiert der Release-Workflow selbst, **wenn** das Secret `HOMEBREW_TAP_TOKEN` hinterlegt ist (siehe unten). Sonst von Hand:
   ```bash
   ./scripts/update-homebrew.sh 1.5.0
   ```

### Homebrew-Token einrichten (einmalig, Maintainer)

1. Auf GitHub: *Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token*
2. **Repository access:** *Only select repositories* → nur `homebrew-tidyram`
3. **Permissions → Repository permissions → Contents:** *Read and write* (sonst nichts)
4. Ablaufdatum setzen (z. B. 1 Jahr), Token erzeugen und kopieren
5. Als Secret im Haupt-Repository hinterlegen. Der Befehl fragt nach dem Wert, der Token landet so nicht in der Shell-Historie:
   ```bash
   gh secret set HOMEBREW_TAP_TOKEN -R seyi23/TidyRAM
   ```

Der Token kann ausschließlich das Tap-Repository ändern. Läuft er ab, überspringt der Workflow den Schritt mit einem Hinweis, und das Release funktioniert trotzdem.

---

## English

Thanks for helping to improve TidyRAM! Bug reports, ideas, translations and pull requests are welcome.

**Ground rule: nothing may damage apps or put data at risk.** No force-quitting, read-only access to other processes, admin rights only for hard-coded Apple tools (currently only `/usr/sbin/purge`), no network access, no tracking.

- **Report a bug / suggest an idea:** [open an issue](https://github.com/seyi23/TidyRAM/issues/new/choose) and pick a template. Please include your macOS version, Mac model and TidyRAM version (Settings → About TidyRAM).
- **Build:** `./build.sh`, then `open build/TidyRAM.app`. Only Xcode or the Command Line Tools are needed. Code comments are in German.
- **Tests:** `swift test` (Swift Testing). Or `open Package.swift` and press ⌘U in Xcode. They run on every push and pull request.
- **Pull request:** fork, branch, build and test, add English strings to `Resources/en.lproj/Localizable.strings` for any new text, open the PR. GitHub Actions builds it automatically.
- **Add a language:** copy `Resources/en.lproj` to e.g. `Resources/fr.lproj`, translate the **right-hand** side (keep `%@` and `%lld`), add the language code to `CFBundleLocalizations` in `build.sh`, test with `build/TidyRAM.app/Contents/MacOS/TidyRAM -AppleLanguages "(fr)"`.
- **Release (maintainers):** bump `VERSION` in `build.sh`, add a `CHANGELOG.md` section, commit, push a `vX.Y.Z` tag. The workflow builds, tests, publishes and updates Homebrew (if the `HOMEBREW_TAP_TOKEN` secret is set: fine-grained token, only `homebrew-tidyram`, *Contents: Read and write*; add it with `gh secret set HOMEBREW_TAP_TOKEN -R seyi23/TidyRAM`).
