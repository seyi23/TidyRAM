# Changelog

Alle wichtigen Änderungen an TidyRAM. Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionen nach [Semantic Versioning](https://semver.org/lang/de/).

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
