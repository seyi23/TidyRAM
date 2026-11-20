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

## Pull Request

1. Repository forken, Branch anlegen
2. Änderung machen, mit `./build.sh` bauen, App ausprobieren
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
   git tag -a v1.3.0 -m "TidyRAM 1.3.0"
   ```
   ```bash
   git push origin v1.3.0
   ```
4. Nach dem Release die Homebrew-Formel aktualisieren:
   ```bash
   ./scripts/update-homebrew.sh 1.3.0
   ```

---

## English

Thanks for helping to improve TidyRAM! Bug reports, ideas, translations and pull requests are welcome.

**Ground rule: nothing may damage apps or put data at risk.** No force-quitting, read-only access to other processes, admin rights only for hard-coded Apple tools (currently only `/usr/sbin/purge`), no network access, no tracking.

- **Report a bug / suggest an idea:** [open an issue](https://github.com/seyi23/TidyRAM/issues/new/choose) and pick a template. Please include your macOS version, Mac model and TidyRAM version (Settings → About TidyRAM).
- **Build:** `./build.sh`, then `open build/TidyRAM.app`. Only Xcode or the Command Line Tools are needed. Code comments are in German.
- **Pull request:** fork, branch, build and test, add English strings to `Resources/en.lproj/Localizable.strings` for any new text, open the PR. GitHub Actions builds it automatically.
- **Add a language:** copy `Resources/en.lproj` to e.g. `Resources/fr.lproj`, translate the **right-hand** side (keep `%@` and `%lld`), add the language code to `CFBundleLocalizations` in `build.sh`, test with `build/TidyRAM.app/Contents/MacOS/TidyRAM -AppleLanguages "(fr)"`.
- **Release (maintainers):** bump `VERSION` in `build.sh`, add a `CHANGELOG.md` section, commit, push a `vX.Y.Z` tag, then run `./scripts/update-homebrew.sh X.Y.Z`.
