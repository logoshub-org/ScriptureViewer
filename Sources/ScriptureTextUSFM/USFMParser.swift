// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// USFM chapters to ScriptureText, directly (plan D88, Track V4). USFM defines one book per file (`\id GEN …`);
// `USFMBook` indexes a file's chapters once, and `USFMParser` parses one chapter when it is asked for. Chapter 1
// also carries the book's titles and introduction, as verse 0.

import ScriptureText

public struct USFMParser: Sendable {

    /// What to show, as for OSIS (`OSISParser.Options`).
    public struct Options: Sendable, Equatable {
        public var headings = true
        public var redLetter = true
        public var footnotes = true
        public var crossReferences = true
        /// Start every verse on its own line.
        public var versePerLine = false
        /// Insert marker runs such as `<07225>` after Strong's-tagged words.
        public var strongsMarkers = false
        /// Insert marker runs for morphology codes.
        public var morphMarkers = false
        public var verseNumbers = true
        /// Keep Greek accents, Hebrew vowel points and Hebrew cantillation (D47).
        public var greekAccents = true
        public var hebrewPoints = true
        public var hebrewCantillation = true

        public init() {}

        /// The reader's preferences. USFM has no conf to say which marks a text has, so the character options apply
        /// as chosen.
        public init(display: ScriptureDisplayOptions) {
            headings = display.headings
            redLetter = display.redLetter
            footnotes = display.footnotes
            crossReferences = display.crossReferences
            versePerLine = display.versePerLine
            strongsMarkers = display.strongs
            morphMarkers = display.morph
            greekAccents = display.greekAccents
            hebrewPoints = display.hebrewPoints
            hebrewCantillation = display.hebrewCantillation
        }
    }

    public var options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    /// One chapter of a book, or nil when the book has no such chapter. `identity` is carried on the result for word
    /// references (D41).
    public func parse(_ book: USFMBook, chapter: Int, identity: PassageIdentity? = nil) -> ScriptureText? {
        guard let text = book.chapterTexts[chapter] else { return nil }
        let builder = USFMBuilder(options: options)
        if chapter == book.chapters.first {
            builder.inPrelude = true
            for token in USFMTokenizer.tokens(book.preludeText) { builder.handle(token) }
            builder.inPrelude = false
        }
        for token in USFMTokenizer.tokens(text) { builder.handle(token) }
        var result = builder.finish()
        result.identity = identity
        return result
    }

    /// USFM text with no book around it (a test, a fragment): every chapter in it, read as one.
    public func parse(_ text: String, identity: PassageIdentity? = nil) -> ScriptureText {
        let builder = USFMBuilder(options: options)
        for token in USFMTokenizer.tokens(text) { builder.handle(token) }
        var result = builder.finish()
        result.identity = identity
        return result
    }
}

/// One USFM book file, indexed: its code and names, and where each chapter starts.
public struct USFMBook: Sendable {
    /// The book's code from `\id` ("GEN").
    public let code: String
    /// `\toc2`, else `\h`: the name for a list of books.
    public let shortName: String?
    /// `\toc1`: the book's full title.
    public let longName: String?
    /// `\toc3`: its abbreviation.
    public let abbreviation: String?
    /// The chapter label for every chapter (`\cl Psalm` before `\c 1`), if the book has one.
    public let chapterLabel: String?
    /// The chapter numbers in the order the file has them.
    public let chapters: [Int]
    /// Each chapter's highest verse number (the end of a bridge counts), from the `\v` markers.
    public let lastVerses: [Int: Int]

    /// The text before the first chapter (the book's titles and introduction), and each chapter's text from its `\c`. Cut from
    /// the file once, when it is indexed. A chapter number the file repeats keeps its last text and its first place in `chapters`.
    let preludeText: String
    let chapterTexts: [Int: String]

    /// The book in `text`, or nil when it has no `\id`.
    public init?(_ text: String) {
        // Each `\c N` and `\v N`: a backslash, the letter, whitespace and a number. `\cl`, `\cp`, `\cat`, `\va`,
        // `\vp` and the like are other markers. Read as UTF-16 code units (every character looked for is ASCII), so the
        // chapters can be cut at their offsets.
        let units = CodePoints.utf16(text)
        let n = units.count
        var startNumbers: [Int] = []
        var startOffsets: [Int] = []
        var lastVerses: [Int: Int] = [:]
        var index = 0
        while index < n {
            guard units[index] == 0x5C else { index += 1; continue }    // a backslash
            let slash = index
            var cursor = slash + 1
            index = cursor
            guard cursor < n else { continue }
            let letter = units[cursor]
            guard letter == 0x63 || letter == 0x76 else { continue }     // c, v
            cursor += 1
            guard cursor < n, Self.isSpace(units[cursor]) else { continue }
            while cursor < n, Self.isSpace(units[cursor]) { cursor += 1 }
            guard let value = Self.number(units, at: cursor) else { continue }
            if letter == 0x63 {
                startNumbers.append(value.value)
                startOffsets.append(slash)
            } else if let chapter = startNumbers.last {
                var last = value.value
                // A bridge: `1-2`.
                if value.end < n, units[value.end] == 0x2D, let to = Self.number(units, at: value.end + 1), to.value > value.value {
                    last = to.value
                }
                lastVerses[chapter] = max(lastVerses[chapter] ?? 0, last)
            }
        }
        self.lastVerses = lastVerses
        var boundaries: [Int] = [0]
        for offset in startOffsets { boundaries.append(offset) }
        boundaries.append(n)
        let pieces = CodePoints.pieces(text, utf16Boundaries: boundaries)
        var texts: [Int: String] = [:]
        var order: [Int] = []
        var k = 0
        while k < startNumbers.count {
            let number = startNumbers[k]
            if texts[number] == nil { order.append(number) }
            texts[number] = pieces[k + 1]
            k += 1
        }
        preludeText = pieces[0]
        chapterTexts = texts
        chapters = order

        // The book's own lines: what follows each identification marker, up to the next marker.
        var fields: [String: String] = [:]
        var current: String?
        for token in USFMTokenizer.tokens(preludeText) {
            switch token {
            case .marker(let name, _):
                if Self.isBookField(name) && fields[name] == nil {
                    current = name
                    fields[name] = ""
                } else {
                    current = nil
                }
            case .text(let value):
                if let current { fields[current] = (fields[current] ?? "") + value }
            case .end:
                current = nil
            }
        }
        func field(_ name: String) -> String? {
            let value = CodePoints.trimmed(fields[name] ?? "", where: { CodePoints.isWhiteSpaceOrNewline($0) })
            return value.isEmpty ? nil : value
        }
        guard let id = field("id") else { return nil }
        let words = CodePoints.split(id, separator: " ")
        guard let code = words.first, !code.isEmpty else { return nil }
        self.code = code.uppercased()
        shortName = field("toc2") ?? field("h")
        longName = field("toc1")
        abbreviation = field("toc3")
        chapterLabel = field("cl")
    }

    /// The identification markers whose text is the book's own: its code, its names, its chapter label.
    private static func isBookField(_ name: String) -> Bool {
        switch name {
        case "id", "h", "toc1", "toc2", "toc3", "cl": return true
        default: return false
        }
    }

    /// A number in ASCII digits at `start`, and where it ends.
    private struct Number {
        var value: Int
        var end: Int
    }

    private static func number(_ units: [Int], at start: Int) -> Number? {
        var cursor = start
        var value = 0
        while cursor < units.count, units[cursor] >= 0x30, units[cursor] <= 0x39 {
            // Eighteen digits at most: more would overflow, and no chapter or verse has them.
            if cursor - start < 18 { value = value * 10 + (units[cursor] - 0x30) }
            cursor += 1
        }
        return cursor > start ? Number(value: value, end: cursor) : nil
    }

    private static func isSpace(_ unit: Int) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D
    }
}
