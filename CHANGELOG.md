# Changelog

Alle wichtigen Änderungen an TidyRAM. Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionen nach [Semantic Versioning](https://semver.org/lang/de/).

## [1.5.0] – 2026-11-20

### Neu
- **Verlauf über 24 Stunden:** umschaltbar zwischen 1 h, 6 h und 24 h, lokal gespeichert (`~/Library/Application Support/TidyRAM/history.json`), übersteht Neustarts
- **Mini-Grafik in der Menüleiste:** Verlauf der letzten 30 Minuten als weitere Anzeige-Option
- **Swap-Warnung:** Mitteilung, wenn der Swap 2, 4, 8 oder 16 GB überschreitet
- **Eigenverbrauch** von TidyRAM (Speicher und CPU) unter *Über TidyRAM*
- **Automatische Tests** (Swift Testing, `swift test`) und **Swift Package**: Projekt lässt sich direkt in Xcode öffnen. Tests laufen bei jedem Push
- **Homebrew automatisch:** Der Release-Workflow aktualisiert das Tap selbst (Secret `HOMEBREW_TAP_TOKEN`)
- **Projektseite** auf GitHub Pages: [seyi23.github.io/TidyRAM](https://seyi23.github.io/TidyRAM/)

### Behoben
- „Zero KB freigegeben“ → „0 KB freigegeben“ (von den Tests gefunden)
- Hinweistext unter dem Freigeben-Knopf wurde abgeschnitten
- `update-homebrew.sh` verwendet für Commits immer die anonyme GitHub-Adresse

### New (English summary)
24-hour history with 1/6/24 h ranges, saved locally; mini chart in the menu bar; swap warning; own usage display; automated tests and Swift package; automatic Homebrew updates on release; project website on GitHub Pages.

## [1.4.0] – 2026-11-20

### Neu
- **Details per Klick:** Jeder Bereich der Legende lässt sich aufklappen, mit Erklärung in einfachen Worten und Detailwerten: Grafikspeicher (GPU) bei *Reserviert*, Kompressionsfaktor bei *Komprimiert*, sofort verwerfbarer Cache, Swap-Dateien und ausgelagerte Datenmenge
- **„Wer frisst Speicher?“:** Der Verlauf merkt sich zu jedem Zeitpunkt die größte App. Mit der Maus über die Grafik siehst du Uhrzeit, Belegung, Speicherdruck und Spitzenreiter. Darunter steht, wer bei Speicherdruck vorne lag
- **Steuerung per Link:** `open -g tidyram://free` gibt RAM aus Terminal, Kurzbefehlen, Raycast, Alfred oder Skripten frei
- **Aktualisierungs-Intervall wählbar:** 2, 5 oder 10 Sekunden
- **Protokoll** für die Fehlersuche: `/usr/bin/log stream --info --predicate 'subsystem == "local.tidyram"'`

### New (English summary)
Expandable legend with explanations and details (GPU memory, compression ratio, swap), "who's eating memory?" hover details in the history chart, control via `tidyram://free` link, selectable refresh interval, logging.

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
