// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import ScriptureText

@Suite("Highlights")
struct HighlightTests {

    // "1In the beginning<H430> God\n2And the Earth" with markers laid over the numbers and the Strong's token.
    private func sample() -> ScriptureText {
        let text = "1In the beginning<H430> God\n2And the Earth"
        let second = text.utf16.count - "2And the Earth".utf16.count
        return ScriptureText(
            text: text,
            spans: [.init(start: 0, length: 1, attribute: .verseNumber(1)),
                    .init(start: 17, length: 6, attribute: .strongs("strong:H0430")),
                    .init(start: second, length: 1, attribute: .verseNumber(2))],
            verses: [.init(verse: 1, start: 0, length: second - 1), .init(verse: 2, start: second, length: 14)])
    }

    @Test func aVerseHighlightSkipsItsNumber() {
        let m = sample()
        let resolved = m.resolve([Highlight(.verse(1), style: .bookmark(colour: "#FF0000"))])
        #expect(resolved.count == 1)
        #expect(m.substring(utf16Start: resolved[0].start, length: resolved[0].length) == "In the beginning<H430> God")
        #expect(resolved[0].style == .bookmark(colour: "#FF0000"))
        let second = m.resolve([Highlight(.verse(2), style: .search)])
        #expect(m.substring(utf16Start: second[0].start, length: second[0].length) == "And the Earth")
    }

    @Test func aMissingVerseOrAnOutOfRangeRangeIsIgnored() {
        let m = sample()
        #expect(m.resolve([Highlight(.verse(9), style: .search), Highlight(.range(start: 100, length: 5), style: .search),
                           Highlight(.range(start: -1, length: 2), style: .search)]).isEmpty)
        #expect(m.resolve([Highlight(.range(start: 1, length: 2), style: .search)]).first?.length == 2)
    }

    @Test func searchFindsEveryOccurrenceIgnoringCase() {
        let m = sample()
        let hits = m.searchHits(for: ["the"])
        let words = hits.compactMap { h -> String? in
            guard case .range(let s, let l) = h.target else { return nil }
            return m.substring(utf16Start: s, length: l)
        }
        #expect(words == ["the", "the"])         // "In the beginning" and "And the Earth": case kept as shown
        #expect(m.searchHits(for: ["EARTH"]).count == 1)
        #expect(m.searchHits(for: ["xyz", ""]).isEmpty)
    }

    @Test func markersAreNotSearched() {
        let m = sample()
        #expect(m.searchHits(for: ["H430"]).isEmpty)
        #expect(m.searchHits(for: ["1"]).isEmpty)
        #expect(m.searchHits(for: ["God"]).count == 1)
    }

    @Test func overlappingTermsMergeIntoOneHit() {
        let m = ScriptureText(text: "beginning")
        let hits = m.searchHits(for: ["begin", "ginn", "ning"])
        #expect(hits.count == 1)
        #expect(hits.first?.target == .range(start: 0, length: 9))
    }

    @Test func aPhraseIsOneTerm() {
        let m = sample()
        #expect(m.searchHits(for: ["the beginning"]).count == 1)
        #expect(m.searchHits(for: ["the earth"]).count == 1)
    }

    @Test func aStrongsSearchMarksTheWordsThatCarryTheNumber() {
        let text = "In the beginning God created"
        let u = { (s: String) in s.utf16.count }
        let model = ScriptureText(text: text, spans: [
            .init(start: 0, length: u("In the beginning"), attribute: .word(lemma: "strong:H07225", morph: nil)),
            .init(start: u("In the beginning "), length: 3, attribute: .word(lemma: "strong:H0430", morph: nil)),
            .init(start: u("In the beginning God "), length: 7, attribute: .word(lemma: "strong:H0853 strong:H01254", morph: nil)),
        ])
        #expect(model.strongsHits(for: "H07225") == [Highlight(.range(start: 0, length: 16), style: .search)])
        #expect(model.strongsHits(for: "H7225").count == 1, "leading zeros do not matter")
        #expect(model.strongsHits(for: "1254").count == 1, "bare digits match either language, and any token of the word")
        #expect(model.strongsHits(for: "G7225").isEmpty, "the language letter must agree")
        #expect(model.strongsHits(for: "love").isEmpty)
    }
}
