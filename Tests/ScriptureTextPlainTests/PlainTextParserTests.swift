// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import ScriptureText
@testable import ScriptureTextPlain

@Suite("PlainTextParser")
struct PlainTextParserTests {

    // Strong's Hebrew H7225 as the RawLD module stores it (public domain): CRLF line ends, a leading
    // space on every line, hard wraps, a blank line after the headword line.
    private let strongs = " 7225  re'shiyth  ray-sheeth'\r\n\r\n from the same as 7218; the first, in place, time, order or\r\n rank (specifically, a firstfruit):--beginning, chief(-est),\r\n first(-fruits, part, time), principal thing.\r\n see HEBREW for 07218\r\n"

    @Test func aHardWrappedEntryReflowsIntoParagraphs() {
        let m = PlainTextParser().parse(strongs)
        #expect(m.text == "7225 re'shiyth ray-sheeth'\nfrom the same as 7218; the first, in place, time, order or rank (specifically, a firstfruit):--beginning, chief(-est), first(-fruits, part, time), principal thing. see HEBREW for 07218")
        #expect(m.spans.isEmpty && m.verses.isEmpty && m.words.isEmpty)
    }

    @Test func preserveKeepsEveryLine() {
        var o = PlainTextParser.Options(); o.lineBreaks = .preserve
        let m = PlainTextParser(options: o).parse("one\r\ntwo  words\r\n\r\nthree\r\n")
        #expect(m.text == "one\ntwo words\nthree")
    }

    @Test func lineEndsOfEveryKindAreOne() {
        #expect(PlainTextParser().parse("a\rb\n\r\nc").text == "a b\nc")
        #expect(PlainTextParser().parse("a\r\nb\r\n\r\n\r\n\r\nc").text == "a b\nc")
    }

    @Test func emptyAndWhitespaceOnlyEntriesAreEmpty() {
        #expect(PlainTextParser().parse("").text == "")
        #expect(PlainTextParser().parse("  \r\n \t\r\n").text == "")
    }

    @Test func nothingInTheTextIsInterpreted() {
        // MHCC's own reference marks, markup-looking text and non-Latin text pass through unchanged.
        let s = "see #Ex 7:20| and <b>not bold</b> \u{05E8}\u{05B5}\u{05D0}\u{05E9}\u{05C1}\u{05B4}\u{05D9}\u{05EA}"
        #expect(PlainTextParser().parse(s).text == s)
    }

    @Test func spacesInsideALineAreCollapsedButOtherWhitespaceKindsAreNot() {
        #expect(PlainTextParser().parse("a    b\t\tc\u{00A0}d").text == "a b c d")
        #expect(PlainTextParser().parse("a\u{3000}b").text == "a\u{3000}b")      // an ideographic space is a visible gap
    }

    // MARK: Verse-keyed text

    @Test func aCommentaryChapterPutsEachVerseNumberOnItsOwnLine() {
        let entries: [ChapterEntries.Entry] = [
            .init(verse: 0, text: "* The miracle at Cana. (1-11)\n"),
            .init(verse: 1, text: "1-11 It is very desirable\nwhen there is a marriage.\n\nSecond paragraph."),
            .init(verse: 2, text: "Next."),
        ]
        let m = PlainTextParser(profile: .commentary).parse(entries)
        #expect(m.text == "* The miracle at Cana. (1-11)\n1\n1-11 It is very desirable when there is a marriage.\nSecond paragraph.\n2\nNext.")
        #expect(m.verses.map(\.verse) == [1, 2])
        #expect(m.spans.map(\.attribute) == [.verseNumber(1), .verseNumber(2)])
        let v1 = m.verses[0]
        #expect(m.substring(utf16Start: v1.start, length: v1.length) == "1\n1-11 It is very desirable when there is a marriage.\nSecond paragraph.")
    }

    @Test func aPlainBibleChapterRunsTheNumberIntoTheText() {
        let entries: [ChapterEntries.Entry] = [.init(verse: 1, text: "In the beginning"), .init(verse: 2, text: "And the earth")]
        let m = PlainTextParser(profile: .chapter).parse(entries, identity: .init(work: "X", versification: "KJV", book: "Gen", chapter: 1))
        #expect(m.text == "1In the beginning\n2And the earth")
        #expect(m.identity?.book == "Gen")
    }

    @Test func entriesWithoutVersesIgnoreTheVerseNumbers() {
        let m = PlainTextParser(profile: .dictionary).parse([.init(verse: 3, text: "word")])
        #expect(m.text == "word")
        #expect(m.verses.isEmpty)
    }

    @Test func utf16OffsetsAreRightForNonBMPText() {
        let entries: [ChapterEntries.Entry] = [.init(verse: 1, text: "\u{1F600} hi"), .init(verse: 2, text: "yo")]
        let m = PlainTextParser(profile: .chapter).parse(entries)
        #expect(m.verses[1].start == ("1\u{1F600} hi\n").utf16.count)
        #expect(m.substring(utf16Start: m.verses[1].start, length: m.verses[1].length) == "2yo")
    }

    @Test func noSwiftSoupOrXMLIsNeededByThePlainParser() throws {
        let source = try String(contentsOfFile: #filePath.replacingOccurrences(
            of: "Tests/ScriptureTextPlainTests/PlainTextParserTests.swift", with: "Sources/ScriptureTextPlain/PlainTextParser.swift"))
        #expect(!source.contains("import SwiftSoup"))
        #expect(!source.contains("XMLParser"))
    }

    /// Every entry of the real Strong's Hebrew module reflows cleanly. Local only:
    /// `PLAIN_TEXT_DAT=<strongshebrew.dat from the dumps repo> swift test --filter everyEntryOfStrongsHebrew`
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PLAIN_TEXT_DAT"] != nil))
    func everyEntryOfStrongsHebrewReflowsCleanly() throws {
        let path = try #require(ProcessInfo.processInfo.environment["PLAIN_TEXT_DAT"])
        let data = try String(decoding: Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self)
        let chunks = data.components(separatedBy: "$$T").dropFirst()
        var count = 0, longest = 0
        for chunk in chunks {
            // "0007225\n\\07225\\\n<entry>": the first two lines are the key.
            let body = chunk.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false).dropFirst(2).joined(separator: "\n")
            let m = PlainTextParser().parse(body)
            count += 1
            #expect(!m.text.contains("\r") && !m.text.contains("  ") && !m.text.hasPrefix(" ") && !m.text.hasSuffix(" "), "entry \(count)")
            #expect(!m.text.isEmpty, "entry \(count)")
            longest = max(longest, m.text.utf16.count)
        }
        print("PLAIN: \(count) entries reflowed, longest \(longest) UTF-16 units")
        #expect(count > 8000)
    }
}
