#!/bin/zsh
#
# disable-passwordless.sh – entfernt die sudo-Regel für purge wieder.
# Danach fragt TidyRAM beim Freigeben wieder nach dem Passwort.
#
set -euo pipefail

sudo rm -f /etc/sudoers.d/tidyram

if sudo -k -n -l /usr/sbin/purge >/dev/null 2>&1; then
  echo "⚠️  purge ist weiterhin ohne Passwort erlaubt (andere Regel aktiv?)." >&2
  exit 1
fi
echo "✅ Entfernt: purge verlangt wieder ein Passwort."
