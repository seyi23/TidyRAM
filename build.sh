#!/bin/zsh
#
# build.sh – baut build/TidyRAM.app
#
# Benötigt: Xcode oder die Xcode Command Line Tools (swiftc, codesign, lipo).
# Kein Xcode-Projekt nötig: Die Quelldateien werden direkt mit swiftc
# kompiliert und von Hand zu einem .app-Bundle zusammengesetzt.
#
# Aufruf:
#   ./build.sh                 nur für die Architektur dieses Macs (schnell)
#   ./build.sh --universal     für Apple Silicon UND Intel (für Releases)
#
set -euo pipefail
cd "${0:A:h}"   # ins Verzeichnis dieses Skripts wechseln

VERSION="1.5.0"
APP=build/TidyRAM.app
BIN="$APP/Contents/MacOS/TidyRAM"

# Zielarchitekturen festlegen.
if [[ "${1:-}" == "--universal" ]]; then
  ARCHS=(arm64 x86_64)
else
  ARCHS=("$(uname -m)")
fi

# Altes Bundle entfernen und Ordnerstruktur anlegen:
#   TidyRAM.app/Contents/{MacOS,Resources,Info.plist}
rm -rf "$APP" build/obj
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

# Kompilieren – einmal pro Architektur:
#   -O                 optimiert
#   -swift-version 6   strikte Prüfung auf Datenrennen (Swift-6-Modus)
#   -parse-as-library  nötig, weil der Einstiegspunkt per @main kommt
#   -target            Architektur + Mindestversion macOS 14
for arch in $ARCHS; do
  echo "Kompiliere für $arch …"
  swiftc -O -swift-version 6 -parse-as-library \
    -target "$arch-apple-macos14.0" \
    Sources/*.swift \
    -o "build/obj/TidyRAM-$arch"
done

# Bei mehreren Architekturen zu einer "Universal Binary" zusammenfügen.
if (( ${#ARCHS} > 1 )); then
  lipo -create build/obj/TidyRAM-* -output "$BIN"
else
  cp "build/obj/TidyRAM-${ARCHS[1]}" "$BIN"
fi
rm -rf build/obj

# App-Symbol (erzeugt mit: swift scripts/make-icon.swift)
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Übersetzungen: de.lproj (Entwicklungssprache) und en.lproj (Englisch).
# macOS wählt automatisch die Sprache des Systems.
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# Info.plist – LSUIElement = true macht daraus eine reine Menüleisten-App
# (kein Dock-Symbol, kein App-Menü).
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>TidyRAM</string>
  <key>CFBundleDevelopmentRegion</key><string>de</string>
  <key>CFBundleLocalizations</key><array><string>de</string><string>en</string></array>
  <key>CFBundleDisplayName</key><string>TidyRAM</string>
  <key>CFBundleIdentifier</key><string>local.tidyram</string>
  <key>CFBundleExecutable</key><string>TidyRAM</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>local.tidyram</string>
      <key>CFBundleURLSchemes</key><array><string>tidyram</string></array>
    </dict>
  </array>
  <key>NSHumanReadableCopyright</key><string>MIT License – kostenlos und Open Source</string>
</dict>
</plist>
PLIST

# Ad-hoc-Signatur ("-"): reicht für den eigenen Mac und ist auf Apple Silicon
# Pflicht. Für eine Weitergabe ohne Gatekeeper-Warnung bräuchte man eine
# Developer-ID-Signatur + Notarisierung durch Apple (kostenpflichtig).
codesign --force --sign - "$APP"
echo "Fertig ($ARCHS): $PWD/$APP"
