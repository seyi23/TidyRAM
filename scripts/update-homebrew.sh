#!/bin/zsh
#
# update-homebrew.sh – aktualisiert die Homebrew-Formel (Cask) nach einem Release.
#
# Aufruf:   ./scripts/update-homebrew.sh 1.3.0
#
# Ablauf:
#   1. lädt TidyRAM-<version>.zip aus dem GitHub-Release
#   2. berechnet die SHA-256-Prüfsumme (Homebrew prüft damit den Download)
#   3. trägt Version + Prüfsumme in Casks/tidyram.rb im Tap-Repository
#      seyi23/homebrew-tidyram ein, committet und pusht
#
# Benötigt: gh (GitHub CLI, angemeldet), git.
#
set -euo pipefail

VERSION="${1:?Version angeben, z. B. ./scripts/update-homebrew.sh 1.3.0}"
REPO="seyi23/TidyRAM"
TAP="seyi23/homebrew-tidyram"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "Lade TidyRAM-$VERSION.zip …"
gh release download "v$VERSION" -R "$REPO" -p "TidyRAM-$VERSION.zip" -D "$WORK"
SHA=$(shasum -a 256 "$WORK/TidyRAM-$VERSION.zip" | awk '{print $1}')
echo "SHA-256: $SHA"

gh repo clone "$TAP" "$WORK/tap" -- --quiet
CASK="$WORK/tap/Casks/tidyram.rb"
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" \
          -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"

cd "$WORK/tap"
if git diff --quiet; then
  echo "Formel ist bereits aktuell."
  exit 0
fi
git commit -qam "tidyram $VERSION"
git push -q
echo "✅ Homebrew-Formel auf $VERSION aktualisiert."
