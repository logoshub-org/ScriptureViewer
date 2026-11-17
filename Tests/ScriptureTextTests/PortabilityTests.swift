// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing

struct PortabilityTests {

    /// The portable targets must stay free of UIKit/AppKit, NSAttributedString and any third-party library
    /// (plan §4 layering rule): they import Foundation only, so they can move to any platform Swift runs on. The one UIKit target,
    /// `ScriptureViewer`, is the iOS renderer and is left out; nothing portable may depend on it.
    @Test func sourcesImportNoPlatformUIFrameworks() throws {
        let sourcesDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ScriptureTextTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Sources")
        let files = try #require(FileManager.default.enumerator(at: sourcesDirectory, includingPropertiesForKeys: nil))
        var checked = 0
        for case let url as URL in files where url.pathExtension == "swift" && !url.path.contains("/Sources/ScriptureViewer/") {
            let source = try String(contentsOf: url, encoding: .utf8)
            #expect(!source.contains("import UIKit"), "\(url.lastPathComponent)")
            #expect(!source.contains("import AppKit"), "\(url.lastPathComponent)")
            #expect(!source.contains("NSAttributedString"), "\(url.lastPathComponent)")
            #expect(!source.contains("import SwiftSoup"), "\(url.lastPathComponent)")
            checked += 1
        }
        #expect(checked >= 3)
    }

    /// No portable target depends on the UIKit one.
    @Test func noPortableTargetDependsOnTheViewer() throws {
        let manifest = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Package.swift"), encoding: .utf8)
        // each `.target(` or `.testTarget(` block, up to the next one; the targets end where the manifest's Skip section starts (which
        // names the viewer target to give it SkipUI, not as a dependency)
        let targets = manifest.components(separatedBy: "// MARK: Skip")[0]
        let blocks = targets.components(separatedBy: ".target(").dropFirst().flatMap { $0.components(separatedBy: ".testTarget(") }
        var checked = 0
        for block in blocks where !block.contains("name: \"ScriptureViewer\"") {
            #expect(!block.contains("\"ScriptureViewer\""), "a portable target depends on the viewer")
            checked += 1
        }
        #expect(checked > 10)
    }

    /// The tokenizer and the format targets (OSIS, TEI, ThML, GBF, plain text, the module source) are plain Swift over bytes (D32): no SwiftSoup, no
    /// FoundationXML, no XMLParser.
    @Test func theSourceFormatTargetsUseNoXMLOrHTMLLibraries() throws {
        var checked = 0
        for target in ["ScriptureTextMarkup", "ScriptureTextBuilding", "ScriptureTextOSIS", "ScriptureTextTEI", "ScriptureTextThML", "ScriptureTextGBF", "ScriptureTextPlain", "ScriptureTextSource", "ScriptureTextUSFM", "ScriptureTextVersification"] {
            let directory = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Sources/\(target)")
            let files = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
            for case let url as URL in files where url.pathExtension == "swift" {
                let source = try String(contentsOf: url, encoding: .utf8)
                for forbidden in ["import SwiftSoup", "import FoundationXML", "XMLParser"] {
                    #expect(!source.contains(forbidden), "\(url.lastPathComponent) mentions \(forbidden)")
                }
                checked += 1
            }
        }
        #expect(checked == 18)      // the tokenizer, the shared builder, the OSIS parser and builder, the TEI, ThML, GBF, plain-text and module-source files, the module source's warm-up, the five USFM files and the three versification files
    }
}
