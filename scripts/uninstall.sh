#!/bin/zsh
#
# uninstall.sh – entfernt TidyRAM vollständig.
#
#   • beendet die laufende App
#   • löscht /Applications/TidyRAM.app
#   • entfernt die sudo-Regel für purge (falls vorhanden; fragt nach Passwort)
#
# Den Autostart-Eintrag am besten VOR dem Deinstallieren in der App
# ausschalten ("Bei Anmeldung starten"). Sonst: Systemeinstellungen →
# Allgemein → Anmeldeobjekte → TidyRAM entfernen.
#
set -euo pipefail

pkill -x TidyRAM 2>/dev/null || true
rm -rf /Applications/TidyRAM.app
echo "App entfernt."

if [[ -e /etc/sudoers.d/tidyram ]]; then
  sudo rm -f /etc/sudoers.d/tidyram
  echo "sudo-Regel entfernt."
fi
