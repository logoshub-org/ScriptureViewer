// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import ScriptureText
import ScriptureTextVersification
@testable import ScriptureTextUSFM

/// A folder of USFM book files as a Bible (plan Track V5).
struct USFMBibleTests {

    /// A temporary folder holding `files`.
    private func folder(_ files: [String: String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("USFMBibleTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, text) in files { try text.write(to: url.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        return url
    }

    @Test func theCommittedKJVOpensAsABible() throws {
        let bible = try USFMBible(folder: KJVCrossCheckTests.folder)
        #expect(bible.name == "eng-kjv2006")
        #expect(bible.books.map(\.code) == ["GEN", "PSA", "JHN"])
        #expect(bible.books.map(\.name) == ["Genesis", "Psalms", "John"])
        #expect(bible.books[0].longName == "The First Book of Moses, called Genesis")
        #expect(bible.versification.name == "English" && bible.versificationSource == .bestFit)
        let psalms = try #require(bible.versification.books.first { $0.osisID == "Ps" })
        #expect(psalms.chapterCount == 150 && psalms.verseCount(ofChapter: 119) == 176)
        #expect(bible.hasBook("John") && !bible.hasBook("Exod"))

        var display = ScriptureDisplayOptions()
        display.redLetter = true
        let john3 = try #require(bible.chapter(book: "John", chapter: 3, display: display))
        #expect(john3.identity == PassageIdentity(work: "eng-kjv2006", versification: "English", book: "John", chapter: 3))
        #expect(john3.verses.count == 36)
        #expect(john3.spans.contains { $0.attribute == .redLetter })
        #expect(bible.chapter(book: "John", chapter: 22, display: display) == nil)
        #expect(bible.chapter(book: "Rev", chapter: 1, display: display) == nil)
    }

    @Test func theFeaturesOfTheTextAreFoundFromItsMarkers() throws {
        let plain = try folder(["a.usfm": "\\id GEN\n\\c 1\n\\p\n\\v 1 In the beginning."])
        let rich = try folder([
            "a.usfm": "\\id GEN\n\\c 1\n\\s1 A heading\n\\p\n\\v 1 In \\w the|strong=\"H1\" x-morph=\"He,R\"\\w* beginning.\\f + \\ft note\\f*",
            "b.usfm": "\\id MAT\n\\c 1\n\\p\n\\v 1 \\wj Follow me\\wj*\\x - \\xo 1:1 \\xt Gen 1:1\\x*",
        ])
        defer { for url in [plain, rich] { try? FileManager.default.removeItem(at: url) } }
        #expect(try USFMBible(folder: plain).features() == USFMBible.Features())
        let found = try USFMBible(folder: rich).features()
        #expect(found.headings && found.footnotes && found.crossReferences && found.redLetter && found.strongs && found.morphology,
                "features found across more than one book: \(found)")
    }

    @Test func booksGoInParatextOrderWhateverTheFilesAreCalled() throws {
        let url = try folder([
            "a.usfm": "\\id MAT\n\\c 1\n\\p\n\\v 1 The book.\n\\v 2 Abraham.",
            "b.SFM": "\\id GEN\n\\c 1\n\\p\n\\v 1 In the beginning.\n\\c 2\n\\p\n\\v 1-3 Thus.",
            "c.usfm": "\\id GEN\n\\c 1\n\\p\n\\v 1 A second Genesis is ignored.",
            "notes.txt": "not a book",
            "d.usfm": "no id here",
            "e.usfm": "\\id FRT\n\\mt Front matter",
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let bible = try USFMBible(folder: url, name: "Test")
        #expect(bible.name == "Test")
        #expect(bible.books.map(\.code) == ["GEN", "MAT"], "front matter is not a book")
        #expect(bible.books[0].lastVerses == [1: 1, 2: 3], "a bridge's end counts")
        #expect(bible.versification.books.map(\.versesPerChapter) == [[1, 3], [2]])
        #expect(bible.versification.books.map(\.testament) == [.old, .new])
        let empty = try folder(["x.txt": ""])
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(throws: USFMBible.OpenError.noBooks) { try USFMBible(folder: empty) }
    }

    @Test func aDeclaredVersificationWins() throws {
        let book = "\\id PSA\n\\c 3\n\\q1\n\\v 1 LORD.\n\\v 8 Salvation."
        let settings = try folder(["PSA.usfm": book, "Settings.xml": "<ScriptureText><Versification>2</Versification></ScriptureText>"])
        defer { try? FileManager.default.removeItem(at: settings) }
        let fromSettings = try USFMBible(folder: settings)
        #expect(fromSettings.versification.name == "Septuagint" && fromSettings.versificationSource == .settings)
        #expect(!fromSettings.versification.mappings.isEmpty, "the system's mappings come with it")

        let vrs = try folder(["PSA.usfm": book, "custom.vrs": "# Versification  \"Mine\"\nPSA 1:6 2:12 3:8\nPSA 3:1 = PSA 3:2\n"])
        defer { try? FileManager.default.removeItem(at: vrs) }
        let fromFile = try USFMBible(folder: vrs)
        #expect(fromFile.versification.name == "Mine" && fromFile.versificationSource == .vrsFile("custom.vrs"))
        #expect(fromFile.versification.mappings.count == 1)

        let forced = try USFMBible(folder: vrs, versification: .vulgate)
        #expect(forced.versification.name == "Vulgate" && forced.versificationSource == .host)
    }

    @Test func theBestFitFollowsTheVerseNumbers() throws {
        // Joel in Hebrew numbering has four chapters; in English, three.
        let hebrew = try folder(["JOL.usfm": "\\id JOL\n\\c 1\n\\v 20 x\n\\c 2\n\\v 27 x\n\\c 3\n\\v 5 x\n\\c 4\n\\v 21 x"])
        defer { try? FileManager.default.removeItem(at: hebrew) }
        #expect(try USFMBible(folder: hebrew).versification.name == "Original")
        let english = try folder(["JOL.usfm": "\\id JOL\n\\c 1\n\\v 20 x\n\\c 2\n\\v 32 x\n\\c 3\n\\v 21 x"])
        defer { try? FileManager.default.removeItem(at: english) }
        #expect(try USFMBible(folder: english).versification.name == "English")
    }

    @Test func booksAreReadOnceAndKept() throws {
        let bible = try USFMBible(folder: KJVCrossCheckTests.folder)
        let first = try #require(bible.book("Gen"))
        let again = try #require(bible.book("Gen"))
        #expect(first.chapters == again.chapters)
        #expect(bible.book("Exod") == nil)
    }
}
