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
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.20"),
        .package(url: "https://github.com/skiptools/skip-foundation.git", from: "1.4.9"),
    ],
    targets: [
        .target(name: "ScriptureText", dependencies: [foundation], plugins: [skipstone]),
        .target(name: "ScriptureTextMarkup", dependencies: ["ScriptureText", foundation], plugins: [skipstone]),
        .target(name: "ScriptureTextBuilding", dependencies: ["ScriptureText", foundation], plugins: [skipstone]),
        .target(name: "ScriptureTextOSIS", dependencies: ["ScriptureText", "ScriptureTextBuilding", "ScriptureTextMarkup", foundation], plugins: [skipstone]),
        .testTarget(name: "ScriptureTextOSISTests", dependencies: ["ScriptureText", "ScriptureTextOSIS", .product(name: "SkipTest", package: "skip")],
                    resources: [.process("Resources")], plugins: [skipstone]),
    ]
)
