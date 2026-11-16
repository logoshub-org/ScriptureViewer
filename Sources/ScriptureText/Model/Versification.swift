// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// A versification as plain data: its books in canonical order, each with the number of verses in each chapter (plan D79, D81),
// and, for a Paratext system, where its verses are in the Original versification (plan D89). The app fills one from SWORD's
// versification systems; `ScriptureTextVersification` reads Paratext's `.vrs` files into one.
//
// Mapping goes through the Original, as Paratext does: a verse goes to the Original by this system's mappings and comes back
// into another system by that one's. A verse with no mapping keeps its number.

/// The books of a versification and the verses in each chapter.
public struct Versification: Equatable, Sendable, Codable {

    public enum Testament: String, Equatable, Sendable, Codable {
        case old, new
    }

    public struct Book: Equatable, Sendable, Codable {
        /// The name the reader sees ("Genesis").
        public var name: String
        /// The OSIS book id ("Gen").
        public var osisID: String
        /// The number of verses in each chapter, first chapter first; its count is the number of chapters.
        public var versesPerChapter: [Int]
        public var testament: Testament

        public init(name: String, osisID: String, versesPerChapter: [Int], testament: Testament) {
            self.name = name
            self.osisID = osisID
            self.versesPerChapter = versesPerChapter
            self.testament = testament
        }

        public var chapterCount: Int { versesPerChapter.count }

        /// The verses in a chapter (from 1); 0 for a chapter the book does not have.
        public func verseCount(ofChapter chapter: Int) -> Int {
            versesPerChapter.indices.contains(chapter - 1) ? versesPerChapter[chapter - 1] : 0
        }
    }

    /// A run of verses here and where they are in the Original: `count` verses from `here` are the same number of verses
    /// from `original` (a `.vrs` line such as `GEN 32:1-32 = GEN 32:2-33`).
    public struct Mapping: Equatable, Sendable, Codable {
        public var here: VerseReference
        public var original: VerseReference
        /// At least 1.
        public var count: Int

        public init(here: VerseReference, original: VerseReference, count: Int = 1) {
            self.here = here
            self.original = original
            self.count = max(count, 1)
        }

        func originalVerse(for reference: VerseReference) -> VerseReference? {
            Self.shift(reference, from: here, to: original, count: count)
        }

        func verseHere(for reference: VerseReference) -> VerseReference? {
            Self.shift(reference, from: original, to: here, count: count)
        }

        private static func shift(_ reference: VerseReference, from start: VerseReference, to target: VerseReference,
                                  count: Int) -> VerseReference? {
            guard reference.book == start.book, reference.chapter == start.chapter, reference.part == start.part,
                  reference.verse >= start.verse, reference.verse < start.verse + count else { return nil }
            var result = target
            result.verse += reference.verse - start.verse
            return result
        }
    }

    /// The system's name ("KJV", "NRSV", "English").
    public var name: String
    public var books: [Book]
    /// Where this system's verses are in the Original, in the order given; a later mapping of the same verse wins.
    /// Empty for a system that does not say. (The Original's own say where books it also holds inside another sit,
    /// such as the Song of the Three in Greek Daniel.)
    public var mappings: [Mapping]
    /// Verses inside this system's chapters that it does not have (a `.vrs` `-ACT 8:37`).
    public var excludedVerses: [VerseReference]

    public init(name: String, books: [Book], mappings: [Mapping] = [], excludedVerses: [VerseReference] = []) {
        self.name = name
        self.books = books
        self.mappings = mappings
        self.excludedVerses = excludedVerses
    }

    /// The index of the book with this name or OSIS id.
    public func bookIndex(named name: String) -> Int? {
        books.firstIndex { $0.name == name || $0.osisID == name }
    }

    /// Whether this system has the verse: its book, its chapter, a verse from 1 to the chapter's last (or 0, a Psalm
    /// title or other text before verse 1), and not excluded.
    public func contains(_ reference: VerseReference) -> Bool {
        guard let index = bookIndex(named: reference.book) else { return false }
        let last = books[index].verseCount(ofChapter: reference.chapter)
        guard last > 0, (0...last).contains(reference.verse) else { return false }
        return !excludedVerses.contains { $0.book == reference.book && $0.chapter == reference.chapter && $0.verse == reference.verse }
    }

    /// The verse in the Original that this system's verse is.
    public func originalVerse(for reference: VerseReference) -> VerseReference {
        for mapping in mappings.reversed() {
            if let original = mapping.originalVerse(for: reference) { return original }
        }
        return reference
    }

    /// The verse of this system that a verse of the Original is.
    public func verse(forOriginal reference: VerseReference) -> VerseReference {
        for mapping in mappings.reversed() {
            if let here = mapping.verseHere(for: reference) { return here }
        }
        return reference
    }

    /// The same verse numbered by `other`; check `other.contains` for whether that system has it.
    public func verse(_ reference: VerseReference, in other: Versification) -> VerseReference {
        guard other.name != name else { return reference }
        return other.verse(forOriginal: originalVerse(for: reference))
    }
}

/// One verse, numbered by some versification: the book's OSIS id, the chapter and the verse (0 for text before verse 1),
/// and a part letter where a system splits a verse ("ESG 4:17a").
public struct VerseReference: Hashable, Sendable, Codable, CustomStringConvertible {
    public var book: String
    public var chapter: Int
    public var verse: Int
    public var part: String?

    public init(book: String, chapter: Int, verse: Int, part: String? = nil) {
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.part = part
    }

    /// "Gen.32.1", or "Esth.4.17a".
    public var description: String { "\(book).\(chapter).\(verse)\(part ?? "")" }
}
