# Changelog

Alle wichtigen Änderungen an TidyRAM. Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionen nach [Semantic Versioning](https://semver.org/lang/de/).

## [1.3.0] – 2026-11-20

### Neu
- **Verlaufsgrafik:** belegter Speicher der letzten Stunde. Zeiten mit erhöhtem oder kritischem Speicherdruck sind farbig hinterlegt
- **Mitteilungen bei Speicherknappheit:** mit der App, die gerade am meisten belegt, höchstens alle 10 Minuten
- **Einstellungsfenster** (Zahnrad im TidyRAM-Fenster) mit allen Optionen
- **Anzeige in der Menüleiste wählbar:** Prozent, GB, Farbpunkt für den Speicherdruck oder nur das Symbol
- **Tastenkürzel ⌃⌥⌘R:** RAM von überall freigeben, Ergebnis als Mitteilung
- **Automatisch freigeben (optional, standardmäßig aus):** bei erhöhtem Speicherdruck, höchstens alle 15, 30 oder 60 Minuten. Nur mit eingerichtetem Freigeben ohne Passwort
- **Englische Übersetzung:** App folgt der Systemsprache. Dazu README und PDF auf Englisch
- **Homebrew:** eigenes Tap [seyi23/homebrew-tidyram](https://github.com/seyi23/homebrew-tidyram), Installation mit `brew tap seyi23/tidyram`, `brew trust seyi23/tidyram` (ab Homebrew 7) und `brew install --cask tidyram`
- **CONTRIBUTING.md**, Vorlagen für Issues und Pull Requests

### Geändert
- Git-Verlauf bereinigt: Commits verwenden die anonyme GitHub-Adresse statt einer privaten E-Mail

### New (English summary)
History chart, low-memory notifications, settings window, selectable menu bar display, global shortcut ⌃⌥⌘R, optional automatic freeing, English localization, Homebrew cask, contribution guide and issue templates.

## [1.2.0] – 2026-11-20

### Neu
- **Eigenes App-Symbol**: ein Speicherchip mit Glitzer-Stern, komplett per Code gezeichnet (`scripts/make-icon.swift`)
- **Browser und Electron-Apps richtig gezählt**: *Größte Apps* summiert jetzt alle Hilfsprozesse einer App, also Safari samt aller Tabs und Chrome, Firefox, ChatGPT oder Claude samt Helpern. Die Anzahl der Prozesse steht neben dem Wert
- **Universal-Build** für Apple Silicon und Intel: `./build.sh --universal`
- **GitHub Actions**: automatischer Build bei jedem Push, fertige Downloads als GitHub-Release bei jedem Versions-Tag

## [1.1.0] – 2026-11-20

### Neu
- Freigeben ohne Passwort über eine eng begrenzte sudo-Regel nur für `/usr/sbin/purge` (`scripts/enable-passwordless.sh`)
- Anzeige in der App, ob die Regel aktiv ist
- Ausführliche Dokumentation als README und PDF, kommentierter Quellcode

## [1.0.0] – 2026-11-20

### Neu
- Menüleisten-App mit Speicherübersicht wie in der Aktivitätsanzeige, Speicherdruck und Swap
- Datei-Cache freigeben mit `/usr/sbin/purge`
- Liste der größten Apps mit regulärem Beenden (wie ⌘Q)
- Bei Anmeldung starten
