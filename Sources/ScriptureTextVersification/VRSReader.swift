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

        for rawLine in text.split(whereSeparator: \.isNewline) {
            if fileName == nil, let title = systemName(inComment: rawLine) { fileName = title }
            let line = rawLine.prefix { $0 != "#" }.trimmingCharacters(in: .whitespaces)
            guard let first = line.first else { continue }
            switch first {
            case "-":
                if let verse = reference(line.dropFirst()).map({ $0.start }) { excluded.append(verse) }
            case "&", "*":
                continue
            default:
                if line.contains("=") {
                    if let mapping = mapping(line) { mappings.append(mapping) }
                } else if let book = book(line) {
                    books.append(book)
                }
            }
        }
        return Versification(name: name ?? fileName ?? "", books: books, mappings: mappings, excludedVerses: excluded)
    }

    /// `English` from `# Versification  "English"`.
    private static func systemName(inComment line: Substring) -> String? {
        guard line.hasPrefix("#"), line.contains("Versification") else { return nil }
        let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
        return parts.count >= 3 ? String(parts[1]) : nil
    }

    /// `GEN 1:31 2:25 …`: the verses of each chapter; a chapter the line skips has none.
    private static func book(_ line: String) -> Versification.Book? {
        let fields = line.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 2, fields[0].count == 3 else { return nil }
        var verses: [Int] = []
        for field in fields.dropFirst() {
            let pair = field.split(separator: ":")
            guard pair.count == 2, let chapter = Int(pair[0]), let last = Int(pair[1]), chapter >= 1 else { return nil }
            if verses.count < chapter { verses.append(contentsOf: repeatElement(0, count: chapter - verses.count)) }
            verses[chapter - 1] = last
        }
        let code = String(fields[0])
        let known = ParatextBook.book(code: code)
        return Versification.Book(name: known?.name ?? code, osisID: known?.osisID ?? code, versesPerChapter: verses,
                                  testament: known?.testament ?? .old)
    }

    /// `GEN 32:1-32 = GEN 32:2-33`.
    private static func mapping(_ line: String) -> Versification.Mapping? {
        let sides = line.split(separator: "=", omittingEmptySubsequences: false)
        guard sides.count == 2, let here = reference(sides[0]), let original = reference(sides[1]) else { return nil }
        return Versification.Mapping(here: here.start, original: original.start, count: here.count)
    }

    /// `GEN 32:1-32`, `ESG 4:17a`: the first verse and how many verses the range has.
    private static func reference(_ text: Substring) -> (start: VerseReference, count: Int)? {
        let fields = text.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count == 2, fields[0].count == 3 else { return nil }
        let chapterVerse = fields[1].split(separator: ":")
        guard chapterVerse.count == 2, let chapter = Int(chapterVerse[0]) else { return nil }
        let range = chapterVerse[1].split(separator: "-")
        guard let (verse, part) = verseAndPart(range[0]) else { return nil }
        var count = 1
        if range.count == 2, let (last, _) = verseAndPart(range[1]), last > verse { count = last - verse + 1 }
        let code = String(fields[0])
        let book = ParatextBook.book(code: code)?.osisID ?? code
        return (VerseReference(book: book, chapter: chapter, verse: verse, part: part), count)
    }

    /// `17a` → (17, "a").
    private static func verseAndPart(_ text: Substring) -> (Int, String?)? {
        let digits = text.prefix { $0.isASCII && $0.isNumber }
        guard let verse = Int(digits) else { return nil }
        let part = text.dropFirst(digits.count)
        guard part.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return (verse, part.isEmpty ? nil : String(part))
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
