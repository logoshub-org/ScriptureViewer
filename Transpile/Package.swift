// swift-tools-version: 6.1
// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// The Kotlin parity tests of the package above (..), which is a Skip package: its library targets are transpiled to Kotlin (plan
// D158). This package holds only tests, so that the package above stays free of Skip's test machinery; a user of that package never
// sees it (SwiftPM resolves only the package at the repository root). `swift test` runs each test as Swift on macOS and, through Skip,
// as Kotlin on a JVM Android runtime (Gradle, a JDK and the Android SDK needed).
import PackageDescription

let skipstone: Target.PluginUsage = .plugin(name: "skipstone", package: "skip")

func core(_ name: String) -> Target.Dependency { .product(name: name, package: "ScriptureViewer") }

let package = Package(
    name: "ScriptureTranspile",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.20"),
    ],
    targets: [
        .testTarget(name: "ScriptureTextOSISTests", dependencies: [core("ScriptureText"), core("ScriptureTextOSIS"),
                                                               .product(name: "SkipTest", package: "skip")],
                    resources: [.process("Resources")], plugins: [skipstone]),
        // The other parsers, the module source, the versifications and USFM.
        .testTarget(name: "ScriptureTextSourceTests", dependencies: [core("ScriptureText"), core("ScriptureTextSource"), core("ScriptureTextOSIS"),
                                                                 core("ScriptureTextGBF"), core("ScriptureTextThML"), core("ScriptureTextTEI"),
                                                                 core("ScriptureTextPlain"), core("ScriptureTextVersification"),
                                                                 core("ScriptureTextUSFM"), .product(name: "SkipTest", package: "skip")],
                    resources: [.process("Resources")], plugins: [skipstone]),
    ]
)
