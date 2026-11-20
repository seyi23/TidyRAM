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
# Link-Schema tidyram:// der installierten App zuordnen (nicht der Kopie im
# build-Ordner), damit `open tidyram://free` die richtige App anspricht.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u build/TidyRAM.app 2>/dev/null || true
"$LSREGISTER" -f /Applications/TidyRAM.app

open /Applications/TidyRAM.app

echo "Installiert: /Applications/TidyRAM.app (läuft jetzt in der Menüleiste)"
