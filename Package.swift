// swift-tools-version: 6.0
// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
import PackageDescription

let package = Package(
    name: "ScriptureViewer",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // The component: the reading surface in UIKit (iOS) with the portable core under it. `import ScriptureViewer` gives the text
        // view, the viewer, the book navigator and the model they show; the library products below are for the portable parts alone.
        .library(name: "ScriptureViewer", targets: ["ScriptureViewer"]),
        // Android only: the viewer as a SwiftUI view, for a Skip app whose shared screens are SwiftUI (its body is the Compose viewer).
        // The only product that needs SkipUI; empty on iOS and macOS, where `ScriptureViewer` is the SwiftUI view.
        .library(name: "ScriptureViewerSkipUI", targets: ["ScriptureViewerSkipUI"]),
        // The model: text, spans, verse ranges, word anchors, paragraph roles, style sheet, passage identity.
        .library(name: "ScriptureText", targets: ["ScriptureText"]),
        // The OSIS source format: tokenizer, builder and OSISParser (plan D32, D39). Foundation only.
        .library(name: "ScriptureTextOSIS", targets: ["ScriptureTextOSIS"]),
        // The shared XML-shaped tokenizer under the OSIS, TEI and ThML parsers. Foundation only.
        .library(name: "ScriptureTextMarkup", targets: ["ScriptureTextMarkup"]),
        // The TEI source format: dictionary entries (plan D46). Foundation only.
        .library(name: "ScriptureTextTEI", targets: ["ScriptureTextTEI"]),
        // The ThML source format: dictionaries, devotionals, commentaries, general books. Foundation only.
        .library(name: "ScriptureTextThML", targets: ["ScriptureTextThML"]),
        // The GBF source format: Bibles and commentaries in CrossWire's older markup (plan D71). Foundation only.
        .library(name: "ScriptureTextGBF", targets: ["ScriptureTextGBF"]),
        // Plain text (no SourceType): commentaries, dictionaries and devotionals with no markup. Foundation only.
        .library(name: "ScriptureTextPlain", targets: ["ScriptureTextPlain"]),
        // Chapters from a module's raw entries: picks the parser by source type and builds its options. A host
        // supplies the `RawChapterReading` that reads its engine (plan D72). Foundation only.
        .library(name: "ScriptureTextSource", targets: ["ScriptureTextSource"]),
        // Paratext's six standard versifications (SIL's .vrs files, MIT, embedded) and a .vrs reader (plan D89).
        // Foundation only.
        .library(name: "ScriptureTextVersification", targets: ["ScriptureTextVersification"]),
        // USFM Bibles: a book file's chapters straight to ScriptureText (plan D88, Track V4), and a folder of book
        // files as a `ScriptureBible` (Track V5). Foundation only.
        .library(name: "ScriptureTextUSFM", targets: ["ScriptureTextUSFM"]),
    ],
    // Skip (https://skip.dev) transpiles the library targets to Kotlin for Android at build time (plan D158): see the end of this file.
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.20"),
        .package(url: "https://github.com/skiptools/skip-foundation.git", from: "1.4.9"),
        .package(url: "https://github.com/skiptools/skip-model.git", from: "1.8.1"),
        .package(url: "https://github.com/skiptools/skip-ui.git", from: "1.66.0"),
    ],
    targets: [
        // UIKit, iOS only: on macOS and Linux the files are empty (`#if canImport(UIKit)`). Written in Swift 5 language mode.
        .target(
            name: "ScriptureViewer",
            dependencies: ["ScriptureText", "ScriptureTextSource"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "ScriptureViewerSkipUI",
            dependencies: ["ScriptureViewer", "ScriptureText"]
        ),
        .target(
            name: "ScriptureText"
        ),
        .target(
            name: "ScriptureTextMarkup",
            dependencies: ["ScriptureText"]   // CodePoints: the tokenizer scans Int code points (plan D158)
        ),
        // The format-neutral half of building a ScriptureText (text, breaks, verse markers, word anchors, notes),
        // shared by the OSIS and USFM builders (plan Track V3). Not a product: `package` access only.
        .target(
            name: "ScriptureTextBuilding",
            dependencies: ["ScriptureText"]
        ),
        .target(
            name: "ScriptureTextOSIS",
            dependencies: ["ScriptureText", "ScriptureTextBuilding", "ScriptureTextMarkup"]
        ),
        .target(
            name: "ScriptureTextTEI",
            dependencies: ["ScriptureText", "ScriptureTextMarkup"]
        ),
        .target(
            name: "ScriptureTextThML",
            dependencies: ["ScriptureText", "ScriptureTextMarkup"]
        ),
        .target(
            name: "ScriptureTextGBF",
            dependencies: ["ScriptureText", "ScriptureTextOSIS"]
        ),
        .target(
            name: "ScriptureTextVersification",
            dependencies: ["ScriptureText"]
        ),
        .target(
            name: "ScriptureTextUSFM",
            dependencies: ["ScriptureText", "ScriptureTextBuilding", "ScriptureTextVersification"]
        ),
        // Test support, not a product: reads the committed test modules (TestModules/) straight from disk.
        .target(
            name: "ScriptureTextTestSupport",
            dependencies: ["ScriptureText", "ScriptureTextSource"]
        ),
        .target(
            name: "ScriptureTextPlain",
            dependencies: ["ScriptureText"]
        ),
        .target(
            name: "ScriptureTextSource",
            dependencies: ["ScriptureText", "ScriptureTextOSIS", "ScriptureTextGBF", "ScriptureTextThML", "ScriptureTextPlain"]
        ),
        .testTarget(
            name: "ScriptureTextTests",
            dependencies: ["ScriptureText"]
        ),
        .testTarget(
            name: "ScriptureTextOSISTests",
            dependencies: ["ScriptureTextOSIS", "ScriptureText", "ScriptureTextMarkup"],
            exclude: ["Fixtures"]   // golden files, read by path
        ),
        .testTarget(
            name: "ScriptureTextTEITests",
            dependencies: ["ScriptureTextTEI", "ScriptureText", "ScriptureTextMarkup"]
        ),
        .testTarget(
            name: "ScriptureTextThMLTests",
            dependencies: ["ScriptureTextThML", "ScriptureText", "ScriptureTextMarkup"]
        ),
        .testTarget(
            name: "ScriptureTextGBFTests",
            dependencies: ["ScriptureTextGBF", "ScriptureText", "ScriptureTextOSIS"]
        ),
        .testTarget(
            name: "ScriptureTextSourceTests",
            dependencies: ["ScriptureTextSource", "ScriptureText", "ScriptureTextOSIS"]
        ),
        .testTarget(
            name: "ScriptureTextPlainTests",
            dependencies: ["ScriptureTextPlain", "ScriptureText"]
        ),
        .testTarget(
            name: "ScriptureTextMarkupTests",
            dependencies: ["ScriptureTextMarkup"]
        ),
        .testTarget(
            name: "ScriptureTextVersificationTests",
            dependencies: ["ScriptureTextVersification", "ScriptureText", "ScriptureTextTestSupport"]
        ),
        .testTarget(
            name: "ScriptureTextUSFMTests",
            dependencies: ["ScriptureTextUSFM", "ScriptureText", "ScriptureTextOSIS", "ScriptureTextTestSupport",
                           "ScriptureTextVersification"]
        ),
        // Keeps the package what it claims to be: a small public surface, MPL-2.0 headers, no engine or app names.
        .testTarget(
            name: "PackageGuardTests"
        ),
        // The iOS viewer in a window: scrolling to a verse, the verse at the top, a resize, a theme change, the end, gestures, the
        // selection menu, the styler against its golden file. UIKit, so the files are empty on macOS and Linux (`#if canImport(UIKit)`);
        // they run on the iOS simulator.
        .testTarget(
            name: "ScriptureViewerTests",
            dependencies: ["ScriptureViewer", "ScriptureText", "ScriptureTextOSIS"],
            exclude: ["Fixtures"],   // the styler's golden file, read by path
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ScriptureTextModulesTests",
            dependencies: ["ScriptureTextTestSupport", "ScriptureTextSource", "ScriptureTextGBF", "ScriptureTextOSIS",
                           "ScriptureTextPlain", "ScriptureText"]
        ),
    ]
)

// MARK: Skip
//
// Every library target but the test support is a Skip module: the skipstone plugin writes its Kotlin and a Gradle project when the
// package is built (nothing of Skip runs in an iOS app: on iOS the Skip libraries are the platform's own types). Each target's `Skip/`
// folder holds its skip.yml; the viewer's also links the Android viewer's Kotlin (`../Android/scriptureviewer`), which its
// `#if SKIP` branch shows. The model needs SkipModel for the viewer controller's Observation; only the SwiftUI wrapper (ScriptureViewerSkipUI) needs SkipUI.
for target in package.targets where target.type == .regular && target.name != "ScriptureTextTestSupport" {
    target.dependencies.append(Target.Dependency.product(name: "SkipFoundation", package: "skip-foundation"))
    if target.name == "ScriptureText" { target.dependencies.append(Target.Dependency.product(name: "SkipModel", package: "skip-model")) }
    if target.name == "ScriptureViewerSkipUI" { target.dependencies.append(Target.Dependency.product(name: "SkipUI", package: "skip-ui")) }
    var plugins: [Target.PluginUsage] = target.plugins ?? []
    plugins.append(Target.PluginUsage.plugin(name: "skipstone", package: "skip"))
    target.plugins = plugins
}

// Setting the SKIP_ZERO=1 environment strips out the Skip plugin and all Skip dependencies: a plain Swift package, for builds that
// need no Android (an iOS-only host may set it). Skip's own pattern (`skip init --zero`).
if Context.environment["SKIP_ZERO"] ?? "0" != "0" {
    package.targets.forEach { target in
        target.plugins?.removeAll(where: {
            if case .plugin(let name, _) = $0 { return name == "skipstone" } else { return false }
        })
        target.dependencies.removeAll(where: { dependency in
            if case .productItem(_, let package, _, _) = dependency {
                return package == "skip" || package?.hasPrefix("skip-") == true
            } else {
                return false
            }
        })
    }
    package.dependencies.removeAll(where: { dependency in
        if case .sourceControl(_, let url, _) = dependency.kind { return url.hasPrefix("https://github.com/skiptools/") } else { return false }
    })
}
