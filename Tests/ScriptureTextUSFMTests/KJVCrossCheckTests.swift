// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import ScriptureText
import ScriptureTextOSIS
import ScriptureTextTestSupport
@testable import ScriptureTextUSFM

/// The KJV twice (plan Track V4): eBible.org's USFM (`TestModules/USFM/eng-kjv2006`, public domain) through
/// `USFMParser`, and CrossWire's SWORD module (`TestModules/KJV`) through `OSISParser`. They are two encodings of one
/// text, so every verse must agree: its words, its Strong's numbers, its red letter, divine name and added words,
/// and its notes. Four differences are the sources', not the parsers', and are allowed (counted below):
///  • eBible keeps the pilcrow as a character ("¶ And God said"); SWORD marks it `<milestone type="x-p" marker="¶"/>`,
///    which the OSIS path does not print;
///  • eBible puts punctuation after an added word inside `\add` (`\add of:\add*`), SWORD outside it;
///  • eBible writes hyphens in names (Beth-el, El-paran), SWORD en dashes (Beth–el);
///  • SWORD tags more Strong's numbers on some words (mostly H853, the untranslated object marker, joined to the
///    next word), so the USFM's numbers are a subsequence of SWORD's.
/// And a few verses are tagged or marked differently in the two editions; they are listed by name
/// (`editionDifferences`), so any other difference fails.
struct KJVCrossCheckTests {

    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("TestModules/USFM/eng-kjv2006")
    static let books = [("02-GENeng-kjv2006.usfm", "Gen"), ("20-PSAeng-kjv2006.usfm", "Ps"), ("73-JHNeng-kjv2006.usfm", "John")]

    /// What a verse is, independent of how either format encodes it.
    struct VerseFacts: Equatable {
        var text = ""
        var strongs: [String] = []
        var redLetter = ""
        var divineName = ""
        var italic = ""
        var notes: [String] = []
    }

    static func normalised(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2060}", with: "")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// `strong:H0430` → `H430`; other lemma tokens are not Strong's numbers.
    static func strongs(_ lemma: String?) -> [String] {
        (lemma ?? "").split(separator: " ").compactMap { token in
            guard token.hasPrefix("strong:") else { return nil }
            let value = token.dropFirst("strong:".count)
            guard let letter = value.first, let number = Int(value.dropFirst().prefix { $0.isNumber }) else { return String(value) }
            return "\(letter)\(number)"
        }
    }

    static func facts(_ chapter: ScriptureText) -> [Int: VerseFacts] {
        let units = Array(chapter.text.utf16)
        func string(_ start: Int, _ end: Int, dropping hidden: [Range<Int>]) -> String {
            var kept: [UInt16] = []
            for i in max(start, 0)..<min(end, units.count) where !hidden.contains(where: { $0.contains(i) }) { kept.append(units[i]) }
            return normalised(String(decoding: kept, as: UTF16.self))
        }
        let hidden = chapter.spans.compactMap { span -> Range<Int>? in
            switch span.attribute {
            case .verseNumber, .footnote, .strongs, .morph: return span.start..<(span.start + span.length)
            default: return nil
            }
        }
        var result: [Int: VerseFacts] = [:]
        for verse in chapter.verses {
            let range = verse.start..<(verse.start + verse.length)
            var facts = VerseFacts(text: string(range.lowerBound, range.upperBound, dropping: hidden))
            for span in chapter.spans where range.contains(span.start) {
                let end = span.start + span.length
                switch span.attribute {
                case .word(let lemma, _): facts.strongs += strongs(lemma)
                case .redLetter: facts.redLetter += " " + string(span.start, end, dropping: hidden)
                case .divineName: facts.divineName += " " + string(span.start, end, dropping: hidden)
                case .italic: facts.italic += " " + string(span.start, end, dropping: hidden)
                case .footnote(let id):
                    if let note = chapter.notes.first(where: { $0.id == id }) { facts.notes.append(normalised(note.text)) }
                default: break
                }
            }
            facts.redLetter = normalised(facts.redLetter)
            facts.divineName = normalised(facts.divineName)
            facts.italic = normalised(facts.italic)
            result[verse.verse] = facts
        }
        return result
    }

    /// Verses where the editions themselves differ, checked by eye on 2026-10-26.
    static let editionDifferences: Set<String> = [
        // Spelling and capitals: "Abidah" against SWORD's "Abida"; "and Joseph" against "And Joseph".
        "text Gen 25:4", "text Gen 41:56",
        // SWORD italicises "that" (than *that* of John); eBible has no \add there.
        "italic John 5:36",
        // SWORD's note reads "me :(by an irony)".
        "notes Ps 60:8",
        // Strong's tagging: SWORD tags the Greek article (G3588), orders some numbers differently, or tags a word
        // with another number.
        "strongs Gen 44:23", "strongs Gen 45:16", "strongs John 3:3", "strongs John 3:5", "strongs John 4:14",
        "strongs John 6:21", "strongs John 7:26", "strongs John 8:6", "strongs John 9:29", "strongs John 10:12",
        "strongs John 10:27", "strongs John 10:35", "strongs John 12:29", "strongs John 13:10", "strongs John 20:1",
    ]

    static func isSubsequence(_ small: [String], of large: [String]) -> Bool {
        var iterator = large.makeIterator()
        return small.allSatisfy { item in
            while let next = iterator.next() { if next == item { return true } }
            return false
        }
    }

    @Test func everyVerseAgreesWithSWORDsKJV() throws {
        // Read the module once: each `chapter(book:_:)` would inflate all of it.
        var swordChapters: [String: [ChapterEntries.Entry]] = [:]
        for chapter in try TestModules.files("KJV").chapters() { swordChapters["\(chapter.book.osis) \(chapter.number)"] = chapter.entries }
        var options = OSISParser.Options()
        options.headings = true; options.footnotes = true; options.redLetter = true
        var usfmOptions = USFMParser.Options()
        usfmOptions.headings = true; usfmOptions.footnotes = true; usfmOptions.redLetter = true

        var compared = 0
        var differences: [String: [String]] = [:]
        var known: [String: Int] = [:]
        for (file, osis) in Self.books {
            let text = try String(contentsOf: Self.folder.appendingPathComponent(file), encoding: .utf8)
            let book = try #require(USFMBook(text))
            for number in book.chapters {
                let usfm = Self.facts(try #require(USFMParser(options: usfmOptions).parse(book, chapter: number)))
                let entries = try #require(swordChapters["\(osis) \(number)"])
                let swordFacts = Self.facts(OSISParser(options: options).parse(entries.map { .init(verse: $0.verse, osis: $0.text) }))
                #expect(Set(usfm.keys) == Set(swordFacts.keys), "\(osis) \(number): verses")
                for verse in swordFacts.keys.sorted() {
                    guard let a = usfm[verse], let b = swordFacts[verse] else { continue }
                    compared += 1
                    let reference = "\(osis) \(number):\(verse)"
                    func check(_ kind: String, _ x: String, _ y: String, allowed: (String) -> String = { $0 }) {
                        guard x != y else { return }
                        if allowed(x) == allowed(y) { known[kind, default: 0] += 1; return }
                        if Self.editionDifferences.contains("\(kind) \(reference)") { known["edition", default: 0] += 1; return }
                        differences[kind, default: []].append("\(reference)\n  usfm:  \(x)\n  sword: \(y)")
                    }
                    let noPilcrow = { (s: String) in
                        Self.normalised(s.replacingOccurrences(of: "¶", with: "").replacingOccurrences(of: "–", with: "-"))
                    }
                    check("text", a.text, b.text, allowed: noPilcrow)
                    check("red letter", a.redLetter, b.redLetter, allowed: noPilcrow)
                    check("divine name", a.divineName, b.divineName)
                    check("italic", a.italic, b.italic) { Self.normalised(String($0.unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) })) }
                    check("notes", a.notes.joined(separator: " | "), b.notes.joined(separator: " | ")) { $0.replacingOccurrences(of: "–", with: "-") }
                    if a.strongs != b.strongs {
                        if Self.isSubsequence(a.strongs, of: b.strongs) { known["strongs", default: 0] += 1 }
                        else if Self.editionDifferences.contains("strongs \(reference)") { known["edition", default: 0] += 1 }
                        else { differences["strongs", default: []].append("\(reference)\n  usfm:  \(a.strongs.joined(separator: " "))\n  sword: \(b.strongs.joined(separator: " "))") }
                    }
                }
            }
        }
        #expect(compared == 1533 + 2461 + 879)
        // The sources' own differences, as counted when this test was written (2026-10-26). A pilcrow that opens a paragraph is
        // no longer in the USFM text (2026-11-03), so 256 "text" and 8 "red letter" differences became exact matches.
        #expect(known == ["text": 52, "italic": 66, "notes": 17, "strongs": 990, "edition": 19], "\(known)")
        for (kind, list) in differences.sorted(by: { $0.key < $1.key }) {
            Issue.record("\(kind): \(list.count) verses differ; first:\n\(list.prefix(4).joined(separator: "\n"))")
        }
    }
}
