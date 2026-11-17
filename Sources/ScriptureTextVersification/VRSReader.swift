// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Paratext's versification files (`.vrs`) read into a `Versification` (plan D89). The format is line-based text:
//
//   # Versification  "English"                a comment; the first one names the system
//   GEN 1:31 2:25 3:24 …                       a book: each chapter and its last verse
//   GEN 32:1-32 = GEN 32:2-33                  verses here = the same verses in the Original
//   ESG 4:17 = ESG 4:17a                       a verse can map to part of a verse
//   -ACT 8:37                                  a verse this system does not have
//
// Mappings follow Paratext (libpalaso's `Versification.cs`): the left range sets how many verses map, the right side
// gives where the first one goes, and a later line for the same verse replaces an earlier one. A range whose end is
// before its start (vul's `DAG 3:52-23`) is one verse. Lines starting `&` (many verses to one) or `*` (verse
// segments) and anything unreadable are skipped; none of the six standard files has them.

import ScriptureText

public enum VRSReader {

    /// The system in `text`. `name` overrides the one in the file's first comment.
    public static func versification(from text: String, name: String? = nil) -> Versification {
        var books: [Versification.Book] = []
        var mappings: [Versification.Mapping] = []
        var excluded: [VerseReference] = []
        var fileName: String?

        for rawLine in lines(text) {
            if fileName == nil, let title = systemName(inComment: rawLine) { fileName = title }
            let line = trimmed(beforeComment(rawLine))
            guard !line.isEmpty else { continue }
            if line.hasPrefix("-") {
                if let range = reference(String(line.dropFirst())) { excluded.append(range.start) }
            } else if line.hasPrefix("&") || line.hasPrefix("*") {
                continue
            } else if line.contains("=") {
                if let mapping = mapping(line) { mappings.append(mapping) }
            } else if let book = book(line) {
                books.append(book)
            }
        }
        return Versification(name: name ?? fileName ?? "", books: books, mappings: mappings, excludedVerses: excluded)
    }

    // The text is handled as code points and pieces of `String`, not as `Substring`s and `Character`s, so that it transpiles (plan D158).

    /// The lines of `text`, empty ones left out. A line ends at any of the characters Swift's `Character.isNewline` names: LF, VT, FF,
    /// CR, NEL, and the Unicode line and paragraph separators (CR LF is one line end: the empty line between them is left out).
    private static func lines(_ text: String) -> [String] {
        let codes = CodePoints.of(text)
        var out: [String] = []
        var start = 0
        var k = 0
        while k < codes.count {
            let c = codes[k]
            if (c >= 0x0A && c <= 0x0D) || c == 0x85 || c == 0x2028 || c == 0x2029 {
                if k > start { out.append(CodePoints.string(codes, start, k)) }
                start = k + 1
            }
            k += 1
        }
        if codes.count > start { out.append(CodePoints.string(codes, start, codes.count)) }
        return out
    }

    /// The line up to its first `#`.
    private static func beforeComment(_ line: String) -> String {
        let codes = CodePoints.of(line)
        var end = 0
        while end < codes.count && codes[end] != 0x23 { end += 1 }
        return end == codes.count ? line : CodePoints.string(codes, 0, end)
    }

    /// Without tabs and space separators at its ends (Foundation's `CharacterSet.whitespaces`).
    private static func trimmed(_ s: String) -> String {
        CodePoints.trimmed(s, where: { CodePoints.isHorizontalWhiteSpace($0) })
    }

    /// The non-empty pieces of `s` between `separator`s; with `keepEmpty`, the empty ones too.
    private static func pieces(_ s: String, _ separator: Int, keepEmpty: Bool = false) -> [String] {
        let codes = CodePoints.of(s)
        var out: [String] = []
        var start = 0
        var k = 0
        while k <= codes.count {
            if k == codes.count || codes[k] == separator {
                if keepEmpty || k > start { out.append(CodePoints.string(codes, start, k)) }
                start = k + 1
            }
            k += 1
        }
        return out
    }

    private static func length(_ s: String) -> Int { CodePoints.of(s).count }

    /// `English` from `# Versification  "English"`.
    private static func systemName(inComment line: String) -> String? {
        guard line.hasPrefix("#"), line.contains("Versification") else { return nil }
        let parts = pieces(line, 0x22, keepEmpty: true)
        return parts.count >= 3 ? parts[1] : nil
    }

    /// `GEN 1:31 2:25 …`: the verses of each chapter; a chapter the line skips has none.
    private static func book(_ line: String) -> Versification.Book? {
        let fields = pieces(line, 0x20)
        guard fields.count >= 2, length(fields[0]) == 3 else { return nil }
        var verses: [Int] = []
        var f = 1
        while f < fields.count {
            let pair = pieces(fields[f], 0x3A)
            guard pair.count == 2, let chapter = Int(pair[0]), let last = Int(pair[1]), chapter >= 1 else { return nil }
            while verses.count < chapter { verses.append(0) }
            verses[chapter - 1] = last
            f += 1
        }
        let code = fields[0]
        let known = ParatextBook.book(code: code)
        return Versification.Book(name: known?.name ?? code, osisID: known?.osisID ?? code, versesPerChapter: verses,
                                  testament: known?.testament ?? Versification.Testament.old)
    }

    /// `GEN 32:1-32 = GEN 32:2-33`.
    private static func mapping(_ line: String) -> Versification.Mapping? {
        let sides = pieces(line, 0x3D, keepEmpty: true)
        guard sides.count == 2, let here = reference(sides[0]), let original = reference(sides[1]) else { return nil }
        return Versification.Mapping(here: here.start, original: original.start, count: here.count)
    }

    /// A range of verses: the first, and how many.
    private struct VerseRun {
        var start: VerseReference
        var count: Int
    }

    /// `GEN 32:1-32`, `ESG 4:17a`: the first verse and how many verses the range has.
    private static func reference(_ text: String) -> VerseRun? {
        let fields = pieces(text, 0x20)
        guard fields.count == 2, length(fields[0]) == 3 else { return nil }
        let chapterVerse = pieces(fields[1], 0x3A)
        guard chapterVerse.count == 2, let chapter = Int(chapterVerse[0]) else { return nil }
        let range = pieces(chapterVerse[1], 0x2D)
        // An empty range (`GEN 1:-`) is no reference. (It used to stop the reader: the first piece was read without a check.)
        guard !range.isEmpty, let first = verseAndPart(range[0]) else { return nil }
        var count = 1
        if range.count == 2, let last = verseAndPart(range[1]), last.verse > first.verse { count = last.verse - first.verse + 1 }
        let code = fields[0]
        let book = ParatextBook.book(code: code)?.osisID ?? code
        return VerseRun(start: VerseReference(book: book, chapter: chapter, verse: first.verse, part: first.part), count: count)
    }

    /// A verse number and the part after it.
    private struct VersePart {
        var verse: Int
        var part: String?
    }

    /// `17a` → 17, "a".
    private static func verseAndPart(_ text: String) -> VersePart? {
        let codes = CodePoints.of(text)
        var digits = 0
        while digits < codes.count && codes[digits] >= 0x30 && codes[digits] <= 0x39 { digits += 1 }
        guard let verse = Int(CodePoints.string(codes, 0, digits)) else { return nil }
        var k = digits
        while k < codes.count {
            let c = codes[k]
            guard (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) else { return nil }
            k += 1
        }
        return VersePart(verse: verse, part: digits == codes.count ? nil : CodePoints.string(codes, digits, codes.count))
    }
}

extension Versification {
    /// Paratext's Original: the Masoretic (BHS) Old Testament and the UBS / Nestle-Aland New Testament. Every other
    /// Paratext system maps onto it.
    public static let original = VRSReader.versification(from: StandardVersificationText.original)
    /// Paratext's English: most English (RSV) and Spanish Bibles; with the deuterocanon.
    public static let english = VRSReader.versification(from: StandardVersificationText.english)
    /// Paratext's Septuagint: the LXX and most Orthodox Bibles.
    public static let septuagint = VRSReader.versification(from: StandardVersificationText.septuagint)
    /// Paratext's Vulgate: the Latin Vulgate and mainly Catholic Bibles.
    public static let vulgate = VRSReader.versification(from: StandardVersificationText.vulgate)
    /// Paratext's Russian Protestant: the canonical edition of the Russian Synodal Bible.
    public static let russianProtestant = VRSReader.versification(from: StandardVersificationText.russianProtestant)
    /// Paratext's Russian Orthodox: the Orthodox edition of the Russian Synodal Bible.
    public static let russianOrthodox = VRSReader.versification(from: StandardVersificationText.russianOrthodox)

    /// Paratext's six systems, in Paratext's numbering (Original 1 … Russian Orthodox 6).
    public static var paratextSystems: [Versification] {
        [original, septuagint, vulgate, english, russianProtestant, russianOrthodox]
    }

    /// A Paratext system by its file code ("eng", "org", "lxx", "vul", "rsc", "rso") or its name ("English").
    public static func paratext(_ name: String) -> Versification? {
        switch name.lowercased() {
        case "org", "original": return original
        case "eng", "english": return english
        case "lxx", "septuagint": return septuagint
        case "vul", "vulgate": return vulgate
        case "rsc", "russian protestant", "russianprotestant": return russianProtestant
        case "rso", "russian orthodox", "russianorthodox": return russianOrthodox
        default: return nil
        }
    }
}
