#!/bin/zsh
#
# install.sh – baut die App und installiert sie nach /Applications.
#
# Eine bereits laufende TidyRAM-Instanz wird beendet, ersetzt und
# danach neu gestartet. Admin-Rechte sind nicht nötig, solange dein
# Benutzer Schreibrechte auf /Applications hat (Standard für Admins).
#
set -euo pipefail
cd "${0:A:h}/.."

./build.sh

pkill -x TidyRAM 2>/dev/null && sleep 1 || true
rm -rf /Applications/TidyRAM.app
ditto build/TidyRAM.app /Applications/TidyRAM.app
open /Applications/TidyRAM.app

echo "Installiert: /Applications/TidyRAM.app (läuft jetzt in der Menüleiste)"
