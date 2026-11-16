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
        guard let range = book.chapterRanges[chapter] else { return nil }
        var builder = USFMBuilder(options: options)
        if chapter == book.chapters.first {
            builder.inPrelude = true
            for token in USFMTokenizer.tokens(book.source[book.prelude]) { builder.handle(token) }
            builder.inPrelude = false
        }
        for token in USFMTokenizer.tokens(book.source[range]) { builder.handle(token) }
        var result = builder.finish()
        result.identity = identity
        return result
    }

    /// USFM text with no book around it (a test, a fragment): every chapter in it, read as one.
    public func parse(_ text: String, identity: PassageIdentity? = nil) -> ScriptureText {
        var builder = USFMBuilder(options: options)
        for token in USFMTokenizer.tokens(Substring(text)) { builder.handle(token) }
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

    let source: String
    let prelude: Range<String.Index>
    let chapterRanges: [Int: Range<String.Index>]

    /// The book in `text`, or nil when it has no `\id`.
    public init?(_ text: String) {
        source = text
        // Each `\c N` and `\v N`: a backslash, the letter, whitespace and a number. `\cl`, `\cp`, `\cat`, `\va`,
        // `\vp` and the like are other markers.
        var starts: [(number: Int, index: String.Index)] = []
        var lastVerses: [Int: Int] = [:]
        let utf8 = text.utf8
        func number(at start: String.Index) -> (value: Int, end: String.Index)? {
            var cursor = start
            var value = 0
            var digits = 0
            while cursor < utf8.endIndex, utf8[cursor] >= UInt8(ascii: "0"), utf8[cursor] <= UInt8(ascii: "9") {
                value = value * 10 + Int(utf8[cursor] - UInt8(ascii: "0"))
                digits += 1
                cursor = utf8.index(after: cursor)
            }
            return digits > 0 ? (value, cursor) : nil
        }
        var index = utf8.startIndex
        while let slash = utf8[index...].firstIndex(of: UInt8(ascii: "\\")) {
            var cursor = utf8.index(after: slash)
            index = cursor
            guard cursor < utf8.endIndex else { continue }
            let letter = utf8[cursor]
            guard letter == UInt8(ascii: "c") || letter == UInt8(ascii: "v") else { continue }
            cursor = utf8.index(after: cursor)
            guard cursor < utf8.endIndex, Self.isSpace(utf8[cursor]) else { continue }
            while cursor < utf8.endIndex, Self.isSpace(utf8[cursor]) { cursor = utf8.index(after: cursor) }
            guard let (value, end) = number(at: cursor) else { continue }
            if letter == UInt8(ascii: "c") {
                starts.append((value, slash))
            } else if let chapter = starts.last?.number {
                var last = value
                // A bridge: `1-2`.
                if end < utf8.endIndex, utf8[end] == UInt8(ascii: "-"), let (to, _) = number(at: utf8.index(after: end)), to > value {
                    last = to
                }
                lastVerses[chapter] = max(lastVerses[chapter] ?? 0, last)
            }
        }
        self.lastVerses = lastVerses
        var ranges: [Int: Range<String.Index>] = [:]
        var order: [Int] = []
        for (position, start) in starts.enumerated() {
            let end = position + 1 < starts.count ? starts[position + 1].index : text.endIndex
            if ranges[start.number] == nil { order.append(start.number) }
            ranges[start.number] = start.index..<end
        }
        let preludeEnd = starts.first?.index ?? text.endIndex
        prelude = text.startIndex..<preludeEnd
        chapterRanges = ranges
        chapters = order

        // The book's own lines: what follows each identification marker, up to the next marker.
        var fields: [String: String] = [:]
        var current: String?
        for token in USFMTokenizer.tokens(text[prelude]) {
            switch token {
            case .marker(let name, _):
                current = ["id", "h", "toc1", "toc2", "toc3", "cl"].contains(name) && fields[name] == nil ? name : nil
                if let current { fields[current] = "" }
            case .text(let value):
                if let current { fields[current, default: ""] += value }
            case .end:
                current = nil
            }
        }
        func field(_ name: String) -> String? {
            let value = fields[name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }
        guard let id = field("id"), let code = id.split(separator: " ").first.map(String.init), !code.isEmpty else { return nil }
        self.code = code.uppercased()
        shortName = field("toc2") ?? field("h")
        longName = field("toc1")
        abbreviation = field("toc3")
        chapterLabel = field("cl")
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
    }
}
