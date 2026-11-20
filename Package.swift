// swift-tools-version: 6.0
//
// Package.swift – macht TidyRAM zu einem Swift Package.
//
// Wofür?
//   • `swift test`  führt die automatischen Tests aus (Tests/TidyRAMTests).
//   • `swift build` prüft, ob alles kompiliert.
//   • `open Package.swift` öffnet das Projekt direkt in Xcode.
//
// Die fertige App (TidyRAM.app mit Symbol, Übersetzungen und Info.plist) baut
// weiterhin `./build.sh` – SwiftPM erzeugt nur das nackte Programm.
//

import PackageDescription

let package = Package(
    name: "TidyRAM",
    defaultLocalization: "de",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TidyRAM",
            path: "Sources"
        ),
        .testTarget(
            name: "TidyRAMTests",
            dependencies: ["TidyRAM"],
            path: "Tests/TidyRAMTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
