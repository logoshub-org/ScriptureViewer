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
    targets: [
        // UIKit, iOS only: on macOS and Linux the files are empty (`#if canImport(UIKit)`). Written in Swift 5 language mode.
        .target(
            name: "ScriptureViewer",
            dependencies: ["ScriptureText", "ScriptureTextSource"],
            swiftSettings: [.swiftLanguageMode(.v5)]
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
        .testTarget(
            name: "ScriptureTextModulesTests",
            dependencies: ["ScriptureTextTestSupport", "ScriptureTextSource", "ScriptureTextGBF", "ScriptureTextOSIS",
                           "ScriptureTextPlain", "ScriptureText"]
        ),
    ]
)
