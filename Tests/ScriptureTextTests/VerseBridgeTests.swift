// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import ScriptureText

/// Verse bridges and printed labels in the model (plan D48, Track V2): a USFM `\v 1-2` is one range whose `verse` is 1.
@Suite("Verse bridges")
struct VerseBridgeTests {

    // "1-2 In the beginning\n3 And the earth": verses 1 and 2 bridged, then verse 3.
    private func sample() -> ScriptureText {
        let text = "1-2 In the beginning\n3 And the earth"
        let third = text.utf16.count - "3 And the earth".utf16.count
        return ScriptureText(
            text: text,
            spans: [.init(start: 0, length: 3, attribute: .verseNumber(1)),
                    .init(start: third, length: 1, attribute: .verseNumber(3))],
            verses: [.init(verse: 1, start: 0, length: third - 1, lastVerse: 2),
                     .init(verse: 3, start: third, length: 15)])
    }

    @Test func aRangeKnowsItsVersesAndNumber() {
        let bridge = ScriptureText.VerseRange(verse: 1, start: 0, length: 10, lastVerse: 2)
        #expect(bridge.endVerse == 2)
        #expect(bridge.contains(verse: 1) && bridge.contains(verse: 2) && !bridge.contains(verse: 3))
        #expect(bridge.displayNumber == "1-2")
        let single = ScriptureText.VerseRange(verse: 5, start: 0, length: 10)
        #expect(single.lastVerse == nil && single.endVerse == 5 && single.displayNumber == "5")
        #expect(ScriptureText.VerseRange(verse: 5, start: 0, length: 1, lastVerse: 5).lastVerse == nil, "not a bridge")
        #expect(ScriptureText.VerseRange(verse: 5, start: 0, length: 1, lastVerse: 3).lastVerse == nil, "a backwards bridge is ignored")
        #expect(ScriptureText.VerseRange(verse: 3, start: 0, length: 1, label: "3a").displayNumber == "3a")
        #expect(ScriptureText.VerseRange(verse: 1, start: 0, length: 1, lastVerse: 2, label: "1–2").displayNumber == "1–2")
    }

    @Test func anyVerseOfABridgeFindsTheBridge() {
        let m = sample()
        #expect(m.verseRange(containing: 1)?.verse == 1)
        #expect(m.verseRange(containing: 2)?.verse == 1)
        #expect(m.verseRange(containing: 3)?.verse == 3)
        #expect(m.verseRange(containing: 4) == nil)
    }

    @Test func highlightingAVerseOfABridgeHighlightsTheBridgeWithoutItsNumber() {
        let m = sample()
        let resolved = m.resolve([Highlight(.verse(2), style: .bookmark(colour: "#FF0000"))])
        #expect(resolved.count == 1)
        #expect(resolved.first.flatMap { m.substring(utf16Start: $0.start, length: $0.length) } == "In the beginning")
    }

    @Test func copyingABridgeReportsAllItsVerses() {
        let m = sample()
        let verse = m.copiedText(verse: 2)
        #expect(verse?.text == "1-2 In the beginning")
        #expect(verse?.verses == 1...2)
        let all = m.copiedText(utf16Start: 0, length: m.text.utf16.count)
        #expect(all.verses == 1...3)
        let start = m.copiedText(utf16Start: 4, length: 5)
        #expect(start.verses == 1...2, "part of a bridge is still the bridge")
    }

    @Test func aHeadingAboveKeepsTheBridge() {
        let headed = sample().prependingHeading("Creation")
        #expect(headed.verses[0].lastVerse == 2)
        #expect(headed.verses[0].start == "Creation\n".utf16.count)
        let labelled = ScriptureText(text: "3a x", verses: [.init(verse: 3, start: 0, length: 4, label: "3a")]).prependingHeading("H")
        #expect(labelled.verses[0].label == "3a")
    }

    @Test func rangesSavedBeforeBridgesStillDecode() throws {
        let old = Data(#"{"verse":4,"start":10,"length":20}"#.utf8)
        let range = try JSONDecoder().decode(ScriptureText.VerseRange.self, from: old)
        #expect(range == ScriptureText.VerseRange(verse: 4, start: 10, length: 20))
        let bridge = ScriptureText.VerseRange(verse: 1, start: 0, length: 5, lastVerse: 2, label: "1–2")
        #expect(try JSONDecoder().decode(ScriptureText.VerseRange.self, from: JSONEncoder().encode(bridge)) == bridge)
    }
}
