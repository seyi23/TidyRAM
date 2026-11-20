#!/bin/zsh
#
# enable-passwordless.sh – erlaubt NUR /usr/sbin/purge ohne Passwort.
#
# Legt die Datei /etc/sudoers.d/tidyram mit genau einer Zeile an:
#
#     <dein-benutzer> ALL=(root) NOPASSWD: /usr/sbin/purge
#
# Danach fragt TidyRAM beim Freigeben nicht mehr nach dem Passwort.
# Alle anderen sudo-Befehle verlangen weiterhin dein Passwort.
#
# Sicherheit: Die Regel wird vor der Installation mit `visudo -c` geprüft.
# Eine fehlerhafte Datei in /etc/sudoers.d könnte sonst sudo komplett
# lahmlegen. Du gibst hier ein letztes Mal dein Admin-Passwort ein.
#
# Rückgängig machen: scripts/disable-passwordless.sh
#
set -euo pipefail

RULE_FILE=/etc/sudoers.d/tidyram
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

echo "$(whoami) ALL=(root) NOPASSWD: /usr/sbin/purge" > "$TMP"

# Syntax prüfen, bevor irgendetwas installiert wird.
visudo -cf "$TMP"

# Mit den Rechten installieren, die sudo verlangt: root:wheel, 0440.
sudo install -m 440 -o root -g wheel "$TMP" "$RULE_FILE"

# Kontrolle: muss "/usr/sbin/purge" ausgeben.
if sudo -n -l /usr/sbin/purge >/dev/null 2>&1; then
  echo "✅ Eingerichtet: purge läuft jetzt ohne Passwort."
else
  echo "❌ Die Regel ist installiert, greift aber nicht. Siehe README → Fehlerbehebung." >&2
  exit 1
fi
