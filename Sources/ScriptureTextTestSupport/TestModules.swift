// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// The modules committed under `Packages/ScriptureViewer/TestModules` (plan D74): public-domain texts, kept in their
// real on-disk form so that every parser is tested on real data without SWORD and without a local corpus.

import Foundation
import ScriptureText
import ScriptureTextSource

public enum TestModules {

    /// KJV (OSIS, with Strong's numbers and morphology), YLT, Weymouth (GBF Bibles), DTN and TFG (GBF commentaries).
    public static let names = ["KJV", "YLT", "Weymouth", "DTN", "TFG"]

    public static var folder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // ScriptureTextTestSupport
            .deletingLastPathComponent()      // Sources
            .deletingLastPathComponent()      // package root
            .appendingPathComponent("TestModules", isDirectory: true)
    }

    public static func files(_ name: String) throws -> ModuleFiles {
        try ModuleFiles(directory: folder.appendingPathComponent(name, isDirectory: true))
    }
}

/// A `RawChapterReading` over the committed test modules: what a host with no SWORD would write. References are
/// "Genesis 1" or "Gen 1" (the last word is the chapter). There is no plain-text form of a chapter without SWORD.
public struct TestModulesReader: RawChapterReading {

    private let modules: [String: ModuleFiles]
    private let chapters: [String: [ModuleFiles.Chapter]]

    public init(names: [String] = TestModules.names) throws {
        var modules: [String: ModuleFiles] = [:]
        var chapters: [String: [ModuleFiles.Chapter]] = [:]
        for name in names {
            let files = try TestModules.files(name)
            modules[name] = files
            chapters[name] = try files.chapters()
        }
        self.modules = modules
        self.chapters = chapters
    }

    public func facts(forModule name: String) -> ScriptureModuleFacts? { modules[name]?.facts }

    public func rawChapter(forModule name: String, reference: String) -> RawChapter? {
        guard let facts = modules[name]?.facts, let list = chapters[name] else { return nil }
        let words = reference.split(separator: " ")
        guard words.count >= 2, let number = Int(words[words.count - 1]) else { return nil }
        let book = words.dropLast().joined(separator: " ")
        guard let chapter = list.first(where: {
            $0.number == number && ($0.book.name.caseInsensitiveCompare(book) == .orderedSame
                                    || $0.book.osis.caseInsensitiveCompare(book) == .orderedSame)
        }) else { return nil }
        _ = facts
        return RawChapter(book: chapter.book.osis, chapter: chapter.number, entries: chapter.entries)
    }

    public func plainChapter(forModule name: String, reference: String) -> RawChapter? { nil }
}
