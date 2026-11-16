// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
import ScriptureText
@testable import ScriptureTextOSIS

// Passage identity (D41) and the style sheet (D41) against parsed chapters.

struct OSISIdentityAndStyleTests {

    private let psalm = PassageIdentity(work: "WEB", versification: "NRSVA", book: "Ps", chapter: 3)

    private func entries(_ pairs: [(Int, String)]) -> [OSISParser.VerseEntry] {
        pairs.map { OSISParser.VerseEntry(verse: $0.0, osis: $0.1) }
    }

    @Test func theParserCarriesTheHostsIdentityAndNeverInventsOne() {
        let e = entries([(1, "LORD, how many")])
        #expect(OSISParser().parse(e).identity == nil)
        #expect(OSISParser().parse(e, identity: psalm).identity == psalm)
    }

    @Test func savedReferencesSurviveEveryDisplayOption() throws {
        let e = entries([(1, #"<title type="psalm">A Psalm</title><w lemma="strong:H3068">LORD</w>, how <note>n</note>many"#),
                         (2, #"Many say <q who="Jesus">of</q> my soul."#)])
        let saved = WordReference(passage: psalm, verse: 2, index: 3)       // "my"

        var bare = OSISParser.Options()
        bare.verseNumbers = false; bare.footnotes = false; bare.headings = false
        var rich = OSISParser.Options()
        rich.strongsMarkers = true; rich.morphMarkers = true
        for options in [OSISParser.Options(), bare, rich] {
            let m = OSISParser(options: options).parse(e, identity: psalm)
            let anchor = try #require(m.anchor(for: saved), "\(options)")
            #expect(m.substring(utf16Start: anchor.start, length: anchor.length) == "my")
        }
    }

    @Test func aSavedReferenceIsNotFoundInADifferentVersificationOfTheSameChapter() {
        let e = entries([(1, "LORD, how many")])
        let saved = WordReference(passage: psalm, verse: 1, index: 0)
        let lxx = PassageIdentity(work: "LXX", versification: "LXX", book: "Ps", chapter: 3)
        #expect(OSISParser().parse(e, identity: psalm).anchor(for: saved) != nil)
        #expect(OSISParser().parse(e, identity: lxx).anchor(for: saved) == nil)
    }

    @Test func resolvingAParsedChapterGivesRoleRulesAndNoGapBetweenSameRoleHeadings() {
        let e = entries([(0, #"<title type="main">PSALMS</title>"#),
                         (1, #"<title>First</title><title>Second</title><l level="1" sID="a"/>LORD<l eID="a"/>"#)])
        let m = OSISParser().parse(e, identity: psalm)
        let sheet = ScriptureStyleSheet.classic
        let blocks = sheet.resolveBlocks(in: m)
        #expect(blocks.map(\.role) == [.mt, .s1, .s1, .q1])
        // mt then s1 directly: one gap, carried below the mt; the two s1 headings touch.
        #expect(blocks[0].spaceAfter == sheet.block(for: .mt).spaceAfter)
        #expect(blocks[1].spaceBefore == 0)
        #expect(blocks[1].spaceAfter == 0)
        #expect(blocks[2].spaceBefore == 0)
        #expect(blocks[3].style == sheet.block(for: .q1))
    }

    @Test func theSheetNeverChangesTheParsedText() {
        // Presentation rules cannot reach the content: parsing takes no sheet, and
        // resolving leaves the model alone (the layer boundary in D41).
        let m = OSISParser().parse(entries([(1, #"<l level="2" sID="a"/>deep<l eID="a"/>"#)]))
        let before = m
        _ = ScriptureStyleSheet.classic.resolveBlocks(in: m)
        #expect(m == before)
    }
}
