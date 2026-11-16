// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import ScriptureText
import ScriptureTextTestSupport
@testable import ScriptureTextUSFM

// LOCAL-ONLY run over whole USFM Bibles (plan Track V4): every chapter of every folder of book files under
// SCRIPTURE_USFM_DIR (for example the eBible.org downloads in pocketsword-dumps/modules, `*_usfm`). Skipped without it.

private let usfmDirectory: String? = ProcessInfo.processInfo.environment["SCRIPTURE_USFM_DIR"]

@Suite(.enabled(if: usfmDirectory != nil, "set SCRIPTURE_USFM_DIR to run the local USFM Bibles"))
struct USFMCorpusTests {

    @Test func everyChapterOfEveryBibleParsesCleanly() throws {
        let root = URL(fileURLWithPath: try #require(usfmDirectory))
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var rich = USFMParser.Options()
        rich.strongsMarkers = true; rich.morphMarkers = true; rich.versePerLine = true
        var bare = USFMParser.Options()
        bare.headings = false; bare.footnotes = false; bare.crossReferences = false; bare.redLetter = false; bare.verseNumbers = false

        var summary: [String] = []
        for folder in folders {
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { ["usfm", "sfm"].contains($0.pathExtension.lowercased()) }
            guard !files.isEmpty else { continue }
            var chapters = 0, verses = 0, bridges = 0, labels = 0, words = 0, notes = 0, reordered = 0
            let clock = ContinuousClock()
            let elapsed = try clock.measure {
                for file in files {
                    let text = try String(contentsOf: file, encoding: .utf8)
                    let book = try #require(USFMBook(text), "\(file.lastPathComponent): no \\id")
                    for number in book.chapters {
                        for options in [USFMParser.Options(), rich, bare] {
                            let parsed = try #require(USFMParser(options: options).parse(book, chapter: number))
                            let place = "\(folder.lastPathComponent) \(book.code) \(number)"
                            #expect(parsed.isStructurallyConsistent, "\(place)")
                            #expect(!parsed.text.contains("\\"), "\(place): a marker leaked")
                            #expect(!parsed.text.contains("strong=\"") && !parsed.text.contains("|"), "\(place): attributes leaked")
                            // Each word of a verse has one index, even where verses are reordered or in parts.
                            let keys = parsed.words.map { "\($0.verse).\($0.index)" }
                            #expect(Set(keys).count == keys.count, "\(place): a word index used twice")
                            var identified = parsed
                            identified.identity = PassageIdentity(work: "t", versification: "English", book: book.code, chapter: number)
                            #expect(identified.words.allSatisfy { identified.reference(for: $0).flatMap(identified.anchor(for:)) == $0 },
                                    "\(place): a word reference does not come back")
                            if options == USFMParser.Options() {
                                chapters += 1
                                verses += parsed.verses.count
                                bridges += parsed.verses.filter { $0.lastVerse != nil }.count
                                labels += parsed.verses.filter { $0.label != nil }.count
                                reordered += zip(parsed.verses, parsed.verses.dropFirst()).filter { $0.verse > $1.verse }.count
                                words += parsed.words.count
                                notes += parsed.notes.count
                            }
                        }
                    }
                }
            }
            var bible: USFMBible?
            let opening = try clock.measure { bible = try USFMBible(folder: folder) }
            let system = bible.map { "\($0.versification.name) (\($0.versificationSource))" } ?? "none"
            summary.append("\(folder.lastPathComponent): \(system), opened in \(opening); \(files.count) books, \(chapters) chapters, \(verses) verses (\(bridges) bridges, \(labels) labelled, \(reordered) out of order), \(words) words, \(notes) notes, \(elapsed) for three parses of each")
        }
        #expect(!summary.isEmpty)
        print(summary.joined(separator: "\n"))
    }
}
