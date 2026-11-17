// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
import ScriptureText

@Suite("Copying text")
struct CopyTextTests {

    /// "1In the beginning<07225> God⁠n created.\n2And the earth." with a verse number, a Strong's marker, a word
    /// joiner and a footnote letter, as the OSIS parser lays them out.
    private func model() -> ScriptureText {
        let first = "1In the beginning<07225> God\u{2060}n created."
        let second = "2And the earth."
        let text = first + "\n" + second
        let u = { (s: String) in s.utf16.count }
        let markerStart = u("1In the beginning")
        let noteStart = u("1In the beginning<07225> God\u{2060}")
        let secondStart = u(first) + 1
        return ScriptureText(
            text: text,
            spans: [
                .init(start: 0, length: 1, attribute: .verseNumber(1)),
                .init(start: markerStart, length: u("<07225>"), attribute: .strongs("strong:H07225")),
                .init(start: noteStart, length: 1, attribute: .footnote(id: "1.1")),
                .init(start: secondStart, length: 1, attribute: .verseNumber(2)),
            ],
            verses: [.init(verse: 1, start: 0, length: u(first)), .init(verse: 2, start: secondStart, length: u(second))])
    }

    @Test func aVerseCopiesAsItsWordsWithItsNumberApart() throws {
        let copied = try #require(model().copiedText(verse: 1))
        #expect(copied.text == "1 In the beginning God created.")
        #expect(copied.verses == 1...1)
    }

    @Test func aSelectionAcrossVersesKeepsBothNumbersAndSaysWhichVerses() {
        let m = model()
        let copied = m.copiedText(utf16Start: 0, length: m.text.utf16.count)
        #expect(copied.text == "1 In the beginning God created.\n2 And the earth.")
        #expect(copied.verses == 1...2)
    }

    @Test func aSelectionInsideAVerseHasNoNumberAndNoJoiner() {
        let m = model()
        let start = "1In the beginning<07225> ".utf16.count
        let copied = m.copiedText(utf16Start: start, length: "God\u{2060}n created".utf16.count)
        #expect(copied.text == "God created")
        #expect(!copied.text.unicodeScalars.contains("\u{2060}"))
        #expect(copied.verses == 1...1)
    }

    @Test func textWithNoVersesHasNoVerseRange() {
        let entry = ScriptureText(text: "agape: love")
        #expect(entry.copiedText(utf16Start: 0, length: 11) == .init(text: "agape: love", verses: nil))
        #expect(entry.copiedText(utf16Start: 50, length: 5).text == "")
        #expect(entry.copiedText(verse: 1) == nil)
    }

    /// A character outside the Basic Multilingual Plane is two UTF-16 units: copying must keep the pair together, not turn each half
    /// into a replacement character. Gothic (𐌰𐌹𐍅), a CJK Extension B ideograph (𠀀) and a mathematical letter (𝔄) are real cases:
    /// CrossWire has a Gothic Bible, and Chinese texts use Extension B.
    @Test func charactersOutsideTheBasicPlaneCopyWhole() throws {
        let words = "𐌰𐌹𐍅 𠀀 𝔄"
        let text = "1" + words
        let m = ScriptureText(text: text,
                              spans: [.init(start: 0, length: 1, attribute: .verseNumber(1))],
                              verses: [.init(verse: 1, start: 0, length: text.utf16.count)])
        let copied = try #require(m.copiedText(verse: 1))
        #expect(copied.text == "1 " + words)
        #expect(!copied.text.unicodeScalars.contains("\u{FFFD}"))
        // A selection that starts after the first of these characters.
        let start = "1𐌰".utf16.count
        #expect(m.copiedText(utf16Start: start, length: text.utf16.count - start).text == "𐌹𐍅 𠀀 𝔄")
    }
}
