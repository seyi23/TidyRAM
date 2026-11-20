#!/usr/bin/env swift
//
// make-icon.swift – zeichnet das TidyRAM-App-Symbol und erzeugt Resources/AppIcon.icns
//
// Aufruf:   swift scripts/make-icon.swift
//
// Das Symbol wird komplett per Code gezeichnet (keine Bilddateien, keine
// SF Symbols – deren Lizenz erlaubt keine Verwendung in App-Symbolen):
//   • abgerundetes Quadrat im macOS-Stil mit Blau→Türkis-Verlauf
//   • weißer Speicherchip mit Kontakten an allen vier Seiten
//   • ein Glitzer-Stern im Chip als Zeichen für "aufgeräumt"
//
// Ablauf: 1024-px-Master zeichnen → alle Größen in ein .iconset rendern →
// mit Apples `iconutil` zu einer .icns-Datei bündeln.
//

import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent().deletingLastPathComponent()
let outFile = root.appendingPathComponent("Resources/AppIcon.icns")

/// Zeichnet das Symbol in ein Quadrat der Kantenlänge `s` (Pixel).
func drawIcon(size s: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let u = s / 1024  // Einheit: alle Maße beziehen sich auf eine 1024er-Vorlage

    // 1. Hintergrund: abgerundetes Quadrat (Apple-Raster: 824 px mit 100 px Rand).
    let bg = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let bgPath = CGPath(roundedRect: bg, cornerWidth: 185 * u, cornerHeight: 185 * u, transform: nil)

    // Schlagschatten unter dem Quadrat.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * u), blur: 28 * u,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(bgPath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Verlauf oben-links Blau → unten-rechts Türkis.
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor(red: 0.20, green: 0.42, blue: 0.98, alpha: 1).cgColor,
                 NSColor(red: 0.10, green: 0.78, blue: 0.80, alpha: 1).cgColor] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: bg.minX, y: bg.maxY),
                           end: CGPoint(x: bg.maxX, y: bg.minY), options: [])
    ctx.restoreGState()

    // 2. Chip-Kontakte: je 4 an jeder Seite.
    let chip = CGRect(x: 312 * u, y: 312 * u, width: 400 * u, height: 400 * u)
    let pinLength = 70 * u, pinWidth = 34 * u
    let white = NSColor.white.withAlphaComponent(0.95).cgColor
    ctx.setFillColor(white)
    for i in 0..<4 {
        let offset = chip.minX + 60 * u + CGFloat(i) * 82 * u   // mittig: (400 − 3·82 − 34) / 2 = 60
        let pins = [
            CGRect(x: offset, y: chip.maxY - 4 * u, width: pinWidth, height: pinLength),                // oben
            CGRect(x: offset, y: chip.minY - pinLength + 4 * u, width: pinWidth, height: pinLength),    // unten
            CGRect(x: chip.minX - pinLength + 4 * u, y: offset, width: pinLength, height: pinWidth),    // links
            CGRect(x: chip.maxX - 4 * u, y: offset, width: pinLength, height: pinWidth),                // rechts
        ]
        for pin in pins {
            ctx.addPath(CGPath(roundedRect: pin, cornerWidth: 10 * u, cornerHeight: 10 * u, transform: nil))
        }
    }
    ctx.fillPath()

    // 3. Chip-Körper.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * u), blur: 16 * u,
                  color: NSColor.black.withAlphaComponent(0.25).cgColor)
    ctx.addPath(CGPath(roundedRect: chip, cornerWidth: 56 * u, cornerHeight: 56 * u, transform: nil))
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // 4. Glitzer-Stern (vierzackig) in der Chipmitte, plus kleiner Begleitstern.
    func sparkle(center c: CGPoint, radius r: CGFloat, color: CGColor) {
        let path = CGMutablePath()
        let inner = r * 0.26
        for k in 0..<8 {
            let angle = CGFloat(k) * .pi / 4 + .pi / 2
            let radius = k.isMultiple(of: 2) ? r : inner
            let p = CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius)
            k == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()
    }
    let blue = NSColor(red: 0.18, green: 0.50, blue: 0.95, alpha: 1).cgColor
    let teal = NSColor(red: 0.10, green: 0.72, blue: 0.78, alpha: 1).cgColor
    sparkle(center: CGPoint(x: 494 * u, y: 494 * u), radius: 130 * u, color: blue)
    sparkle(center: CGPoint(x: 618 * u, y: 618 * u), radius: 58 * u, color: teal)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// Alle von macOS erwarteten Größen in ein temporäres .iconset schreiben.
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(size: px).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}

// Zusätzlich eine große PNG-Vorschau für README/GitHub.
try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
try drawIcon(size: 512).representation(using: .png, properties: [:])!
    .write(to: root.appendingPathComponent("docs/icon.png"))

// .iconset → .icns
try FileManager.default.createDirectory(at: outFile.deletingLastPathComponent(), withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outFile.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)

guard iconutil.terminationStatus == 0 else { fatalError("iconutil fehlgeschlagen") }
print("Fertig: \(outFile.path)")
