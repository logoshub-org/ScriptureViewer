// swift-tools-version: 6.1
// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// The portable scripture core, transpiled to Kotlin by Skip Lite (plan D158), for Android. It builds the same sources as the package
// above (../Sources), through symbolic links (see link-sources.sh); the iOS package does not depend on it and a user of that package
// never sees it (SwiftPM resolves only the package at the repository root).
// `swift test` runs the Psalm 119 parity test as Swift on macOS and, through Skip, as Kotlin on a JVM Android runtime (Gradle needed).
import PackageDescription

let skipstone: Target.PluginUsage = .plugin(name: "skipstone", package: "skip")
let foundation: Target.Dependency = .product(name: "SkipFoundation", package: "skip-foundation")

let package = Package(
    name: "ScriptureTranspile",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ScriptureText", type: .dynamic, targets: ["ScriptureText"]),
        .library(name: "ScriptureTextMarkup", type: .dynamic, targets: ["ScriptureTextMarkup"]),
        .library(name: "ScriptureTextBuilding", type: .dynamic, targets: ["ScriptureTextBuilding"]),
        .library(name: "ScriptureTextOSIS", type: .dynamic, targets: ["ScriptureTextOSIS"]),
        .library(name: "ScriptureTextPlain", type: .dynamic, targets: ["ScriptureTextPlain"]),
        .library(name: "ScriptureTextTEI", type: .dynamic, targets: ["ScriptureTextTEI"]),
        .library(name: "ScriptureTextThML", type: .dynamic, targets: ["ScriptureTextThML"]),
        .library(name: "ScriptureTextGBF", type: .dynamic, targets: ["ScriptureTextGBF"]),
        .library(name: "ScriptureTextSource", type: .dynamic, targets: ["ScriptureTextSource"]),
        .library(name: "ScriptureTextVersification", type: .dynamic, targets: ["ScriptureTextVersification"]),
        .library(name: "ScriptureTextUSFM", type: .dynamic, targets: ["ScriptureTextUSFM"]),
        .library(name: "ScriptureViewerSkip", type: .dynamic, targets: ["ScriptureViewerSkip"]),
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.20"),
        .package(url: "https://github.com/skiptools/skip-foundation.git", from: "1.4.9"),
        .package(url: "https://github.com/skiptools/skip-model.git", from: "1.8.1"),
        .package(url: "https://github.com/skiptools/skip-ui.git", from: "1.66.0"),
    ],
    targets: [
        .target(name: "ScriptureText", dependencies: [foundation, .product(name: "SkipModel", package: "skip-model")], plugins: [skipstone]),
        .target(name: "ScriptureTextMarkup", dependencies: ["ScriptureText", foundation], plugins: [skipstone]),
        .target(name: "ScriptureTextBuilding", dependencies: ["ScriptureText", foundation], plugins: [skipstone]),
        .target(name: "ScriptureTextOSIS", dependencies: ["ScriptureText", "ScriptureTextBuilding", "ScriptureTextMarkup", foundation], plugins: [skipstone]),
        .target(name: "ScriptureTextPlain", dependencies: ["ScriptureText", foundation], plugins: [skipstone]),
        .target(name: "ScriptureTextTEI", dependencies: ["ScriptureText", "ScriptureTextMarkup", foundation], plugins: [skipstone]),
        .target(name: "ScriptureTextThML", dependencies: ["ScriptureText", "ScriptureTextMarkup", foundation], plugins: [skipstone]),
        .target(name: "ScriptureTextGBF", dependencies: ["ScriptureText", "ScriptureTextOSIS", foundation], plugins: [skipstone]),
        .target(name: "ScriptureTextSource", dependencies: ["ScriptureText", "ScriptureTextOSIS", "ScriptureTextGBF", "ScriptureTextThML",
                                                            "ScriptureTextPlain", foundation], plugins: [skipstone]),
        .target(name: "ScriptureTextVersification", dependencies: ["ScriptureText", foundation], plugins: [skipstone]),
        .target(name: "ScriptureTextUSFM", dependencies: ["ScriptureText", "ScriptureTextBuilding", "ScriptureTextVersification", foundation],
                plugins: [skipstone]),
        // The SwiftUI `ScriptureViewer` for the Skip-built app, over the Compose viewer in ../Android (its Kotlin is linked into Skip/).
        .target(name: "ScriptureViewerSkip", dependencies: ["ScriptureText", foundation, .product(name: "SkipUI", package: "skip-ui")], plugins: [skipstone]),
        .testTarget(name: "ScriptureTextOSISTests", dependencies: ["ScriptureText", "ScriptureTextOSIS", .product(name: "SkipTest", package: "skip")],
                    resources: [.process("Resources")], plugins: [skipstone]),
        // The other parsers and the module source, as Swift and as Kotlin. A target of its own, named after the module at the top of the
        // graph: Skip builds a test target into the Gradle project of the module it is named after, so these in the OSIS tests made a cycle.
        .testTarget(name: "ScriptureTextSourceTests", dependencies: ["ScriptureText", "ScriptureTextSource", "ScriptureTextOSIS", "ScriptureTextGBF",
                                                                 "ScriptureTextThML", "ScriptureTextTEI", "ScriptureTextPlain",
                                                                 "ScriptureTextVersification", "ScriptureTextUSFM",
                                                                 .product(name: "SkipTest", package: "skip")],
                    resources: [.process("Resources")], plugins: [skipstone]),
    ]
)
