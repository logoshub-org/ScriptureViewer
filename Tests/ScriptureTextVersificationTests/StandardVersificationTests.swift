// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
import ScriptureText
import ScriptureTextTestSupport
@testable import ScriptureTextVersification

/// Paratext's six versifications, embedded from SIL's `.vrs` files and read by `VRSReader` (plan D89).
struct StandardVersificationTests {

    /// Each embedded file is byte-identical to SIL's (libpalaso b4f7a6d): the sizes and FNV-1a 64 hashes were taken
    /// from the upstream files when they were embedded.
    @Test func theEmbeddedFilesAreUpstreamsBytes() {
        let expected: [(String, String, Int, UInt64)] = [
            ("org", StandardVersificationText.original, 11817, 0x790f92f53590e677),
            ("eng", StandardVersificationText.english, 18787, 0x713e9241b4dba7e3),
            ("lxx", StandardVersificationText.septuagint, 29247, 0x48d4a9c763747a54),
            ("vul", StandardVersificationText.vulgate, 30174, 0x1d6e09cd71cde6ad),
            ("rsc", StandardVersificationText.russianProtestant, 14322, 0xc6b295000dbe9a8a),
            ("rso", StandardVersificationText.russianOrthodox, 19635, 0x98e1289ad233056e),
        ]
        for (code, text, size, hash) in expected {
            let bytes = Array(text.utf8)
            #expect(bytes.count == size, "\(code)")
            #expect(bytes.reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 } == hash, "\(code)")
        }
    }

    @Test func eachSystemHasItsNameAndBooks() {
        let systems: [(Versification, String, Int)] = [
            (.original, "Original", 95), (.english, "English", 92), (.septuagint, "Septuagint", 89),
            (.vulgate, "Vulgate", 89), (.russianProtestant, "Russian Protestant", 66), (.russianOrthodox, "Russian Orthodox", 79),
        ]
        for (system, name, books) in systems {
            #expect(system.name == name)
            #expect(system.books.count == books, "\(name)")
            #expect(system.books.prefix(66).map(\.osisID) == ParatextBook.all.prefix(66).map(\.osisID) || name == "Septuagint",
                    "\(name): the 66 in Paratext's order")
        }
        #expect(Versification.english.mappings.count == 269)
        #expect(Versification.septuagint.excludedVerses.count == 304)
        #expect(Versification.paratext("eng") == .english)
        #expect(Versification.paratext("Russian Orthodox") == .russianOrthodox)
        #expect(Versification.paratextSystems.map(\.name) == ["Original", "Septuagint", "Vulgate", "English", "Russian Protestant", "Russian Orthodox"])
    }

    @Test func booksCarryTheirOSISIdsNamesAndTestaments() throws {
        let english = Versification.english
        let genesis = try #require(english.books.first)
        #expect(genesis.osisID == "Gen")
        #expect(genesis.name == "Genesis")
        #expect(genesis.versesPerChapter.count == 50)
        #expect(genesis.verseCount(ofChapter: 1) == 31)
        let matthew = try #require(english.bookIndex(named: "Matt").map { english.books[$0] })
        #expect(matthew.testament == .new)
        #expect(english.bookIndex(named: "Tob") != nil, "English includes the deuterocanon")
        #expect(Versification.russianProtestant.bookIndex(named: "Tob") == nil)
    }

    /// SWORD's KJV is Paratext's English without RSV's 3 John 1:15 and Revelation 12:18, and nothing else differs in
    /// the 66 books.
    @Test func englishDiffersFromSWORDsKJVInTwoChapters() throws {
        var differences: [String] = []
        for book in KJVVersification.oldTestament + KJVVersification.newTestament {
            let index = try #require(Versification.english.bookIndex(named: book.osis), "\(book.osis)")
            let english = Versification.english.books[index].versesPerChapter
            #expect(english.count == book.verses.count, "\(book.osis) chapters")
            for (chapter, (kjv, eng)) in zip(book.verses, english).enumerated() where kjv != eng {
                differences.append("\(book.osis) \(chapter + 1): \(kjv) against \(eng)")
            }
        }
        #expect(differences == ["3John 1: 14 against 15", "Rev 12: 17 against 18"])
    }

    @Test func versesMapToTheOriginalAndBack() {
        let english = Versification.english
        func v(_ book: String, _ chapter: Int, _ verse: Int) -> VerseReference {
            VerseReference(book: book, chapter: chapter, verse: verse)
        }
        #expect(english.originalVerse(for: v("Gen", 31, 55)) == v("Gen", 32, 1))
        #expect(english.originalVerse(for: v("Gen", 32, 1)) == v("Gen", 32, 2))
        #expect(english.originalVerse(for: v("Gen", 32, 32)) == v("Gen", 32, 33))
        #expect(english.originalVerse(for: v("Mal", 4, 1)) == v("Mal", 3, 19))
        #expect(english.originalVerse(for: v("Joel", 2, 28)) == v("Joel", 3, 1))
        #expect(english.originalVerse(for: v("Gen", 1, 1)) == v("Gen", 1, 1), "an unmapped verse keeps its number")
        // `PSA 51:0 = PSA 51:1` then `PSA 51:0 = PSA 51:2`: the later line wins one way, both come back the other.
        #expect(english.originalVerse(for: v("Ps", 51, 0)) == v("Ps", 51, 2))
        #expect(english.verse(forOriginal: v("Ps", 51, 1)) == v("Ps", 51, 0))
        #expect(english.verse(forOriginal: v("Ps", 51, 3)) == v("Ps", 51, 1))
        #expect(english.verse(forOriginal: v("Gen", 32, 1)) == v("Gen", 31, 55))
        #expect(english.verse(forOriginal: v("Mal", 3, 19)) == v("Mal", 4, 1))
    }

    @Test func versesMapBetweenSystemsThroughTheOriginal() {
        func v(_ book: String, _ chapter: Int, _ verse: Int) -> VerseReference {
            VerseReference(book: book, chapter: chapter, verse: verse)
        }
        // English Psalm 23 is Hebrew Psalm 23 and Synodal Psalm 22.
        #expect(Versification.english.verse(v("Ps", 23, 1), in: .russianOrthodox) == v("Ps", 22, 1))
        #expect(Versification.russianOrthodox.verse(v("Ps", 22, 1), in: .english) == v("Ps", 23, 1))
        // English Malachi 4 is Hebrew Malachi 3:19-24.
        #expect(Versification.english.verse(v("Mal", 4, 6), in: .original) == v("Mal", 3, 24))
        #expect(Versification.english.verse(v("Gen", 31, 55), in: .english) == v("Gen", 31, 55))
    }

    @Test func containsKnowsChaptersVerseZeroAndExcludedVerses() {
        let english = Versification.english
        #expect(english.contains(VerseReference(book: "Gen", chapter: 1, verse: 31)))
        #expect(!english.contains(VerseReference(book: "Gen", chapter: 1, verse: 32)))
        #expect(!english.contains(VerseReference(book: "Gen", chapter: 51, verse: 1)))
        #expect(english.contains(VerseReference(book: "Ps", chapter: 3, verse: 0)), "a Psalm title")
        #expect(!english.contains(VerseReference(book: "Nope", chapter: 1, verse: 1)))
        let septuagint = Versification.septuagint
        let excluded = septuagint.excludedVerses[0]
        #expect(!septuagint.contains(excluded), "\(excluded)")
    }
}

/// The reader on small inline files: the format's edge cases.
struct VRSReaderTests {

    private let text = #"""
    # Versification  "Test"
    # a comment line
    GEN 1:31 2:25
    PSA 1:6 3:9   # chapter 2 is missing
    -GEN 2:25
    GEN 2:1-3 = GEN 2:2-4
    ESG 4:17 = ESG 4:17a
    PSA 3:0-8 = PSA 3:1-9
    DAG 3:52-23 = S3Y 1:30-31
    &NUM 17:1-3 = NUM 17:1
    *GEN 1:22,-,a,b
    XYZ nonsense = here
    """#

    @Test func readsBooksMappingsAndExclusions() throws {
        let system = VRSReader.versification(from: text)
        #expect(system.name == "Test")
        #expect(system.books.map(\.osisID) == ["Gen", "Ps"])
        #expect(system.books[1].versesPerChapter == [6, 0, 9], "a chapter the line skips has no verses")
        #expect(system.excludedVerses == [VerseReference(book: "Gen", chapter: 2, verse: 25)])
        #expect(system.mappings.count == 4, "the & and * lines and the unreadable one are skipped")
        #expect(system.mappings[0] == Versification.Mapping(here: VerseReference(book: "Gen", chapter: 2, verse: 1),
                                                            original: VerseReference(book: "Gen", chapter: 2, verse: 2),
                                                            count: 3))
        #expect(system.mappings[1].original == VerseReference(book: "EsthGr", chapter: 4, verse: 17, part: "a"))
        #expect(system.mappings[2].count == 9, "verse 0 to 8")
        #expect(system.mappings[3].count == 1, "an end before the start is one verse")
        #expect(VRSReader.versification(from: text, name: "Mine").name == "Mine")
    }

    @Test func aVerseCanMapToPartOfAVerse() {
        let system = VRSReader.versification(from: text)
        #expect(system.originalVerse(for: VerseReference(book: "EsthGr", chapter: 4, verse: 17)).description == "EsthGr.4.17a")
        #expect(system.verse(forOriginal: VerseReference(book: "EsthGr", chapter: 4, verse: 17, part: "a"))
                == VerseReference(book: "EsthGr", chapter: 4, verse: 17))
        #expect(!system.contains(VerseReference(book: "Gen", chapter: 2, verse: 25)), "excluded")
    }

    @Test func paratextBooksLookUpByCodeAndOSISId() {
        #expect(ParatextBook.book(code: "1sa")?.osisID == "1Sam")
        #expect(ParatextBook.book(osisID: "Rev")?.code == "REV")
        #expect(ParatextBook.all.count == Set(ParatextBook.all.map(\.code)).count)
        #expect(ParatextBook.all.count == Set(ParatextBook.all.map(\.osisID)).count)
        #expect(ParatextBook.all.prefix(66).last?.code == "REV")
    }
}
