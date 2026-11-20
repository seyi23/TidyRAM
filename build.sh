#!/bin/zsh
#
# build.sh – baut build/TidyRAM.app
#
# Benötigt: Xcode oder die Xcode Command Line Tools (swiftc, codesign).
# Kein Xcode-Projekt nötig: Die Quelldateien werden direkt mit swiftc
# kompiliert und von Hand zu einem .app-Bundle zusammengesetzt.
#
# Aufruf (von überall):   ./build.sh   bzw.   /pfad/zum/repo/build.sh
#
set -euo pipefail
cd "${0:A:h}"   # ins Verzeichnis dieses Skripts wechseln

VERSION="1.1.0"
APP=build/TidyRAM.app

# Altes Bundle entfernen und Ordnerstruktur anlegen:
#   TidyRAM.app/Contents/{MacOS,Resources,Info.plist}
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Kompilieren:
#   -O                 optimiert
#   -swift-version 6   strikte Prüfung auf Datenrennen (Swift-6-Modus)
#   -parse-as-library  nötig, weil der Einstiegspunkt per @main kommt
#   -target            native Architektur (arm64 oder x86_64), ab macOS 14
swiftc -O -swift-version 6 -parse-as-library \
  -target "$(uname -m)-apple-macos14.0" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/TidyRAM"

# Info.plist – LSUIElement = true macht daraus eine reine Menüleisten-App
# (kein Dock-Symbol, kein App-Menü).
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>TidyRAM</string>
  <key>CFBundleDisplayName</key><string>TidyRAM</string>
  <key>CFBundleIdentifier</key><string>local.tidyram</string>
  <key>CFBundleExecutable</key><string>TidyRAM</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc-Signatur ("-"): reicht für den eigenen Mac. Für die Weitergabe an
# andere bräuchte man eine Developer-ID-Signatur + Notarisierung durch Apple.
codesign --force --sign - "$APP"
echo "Fertig: $PWD/$APP"
