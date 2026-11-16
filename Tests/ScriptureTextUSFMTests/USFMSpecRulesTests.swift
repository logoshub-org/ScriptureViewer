// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import ScriptureText
@testable import ScriptureTextUSFM

/// The USFM rules a Bible-text expert pointed to (eBible.org, 2026-11-11): white space around markers, `//`, nested character
/// styles, word-level markup and figures.
struct USFMSpecRulesTests {

    private func parse(_ usfm: String) -> ScriptureText { USFMParser(options: USFMParser.Options()).parse(usfm) }

    /// The lemmas the tagged words carry.
    private func lemmas(_ text: ScriptureText) -> [String] {
        text.spans.compactMap { span -> String? in if case .word(let lemma, _) = span.attribute { return lemma }; return nil }
    }

    private func verseText(_ text: ScriptureText, _ verse: Int) -> String? {
        text.verseRange(containing: verse).flatMap { text.substring(utf16Start: $0.start, length: $0.length) }
    }

    private func spans(_ text: ScriptureText, _ match: (ScriptureText.Attribute) -> Bool) -> [String] {
        text.spans.filter { match($0.attribute) }.compactMap { text.substring(utf16Start: $0.start, length: $0.length) }
    }

    // MARK: White space

    @Test func theFirstSpaceAfterAnOpeningMarkerIsTheMarkersButASpaceAfterAClosingMarkerIsText() {
        let text = parse("\\c 1\n\\p\n\\v 1 In the \\wj beginning\\wj* God \\wj created\\wj*, the earth.")
        #expect(verseText(text, 1) == "1In the beginning God created, the earth.", "\(verseText(text, 1).debugDescription)")
        // two spaces after an opening marker: the first is the marker's, the second is text (a single space once shown)
        let two = parse("\\c 1\n\\p\n\\v 1 He \\wj  said\\wj* it.")
        #expect(verseText(two, 1) == "1He said it.")
        // a closing marker with no space after it joins what follows
        #expect(verseText(parse("\\c 1\n\\p\n\\v 1 the \\em Lord\\em*'s word"), 1) == "1the Lord's word")
    }

    @Test func aLineEndAfterAnOpeningMarkerIsTheMarkersAndOneAfterAClosingMarkerIsASpace() {
        let text = parse("\\c 1\n\\p\n\\v 1 He said \\wj\nFollow me\\wj*\nand they did.")
        #expect(verseText(text, 1) == "1He said Follow me and they did.", "\(verseText(text, 1).debugDescription)")
    }

    // MARK: //

    @Test func aDoubleSlashIsAnOptionalLineBreakExceptAfterAColon() {
        let url = parse("\\c 1\n\\p\n\\v 1 See https://ebible.org/find and http://example.org/x for more.")
        #expect(verseText(url, 1) == "1See https://ebible.org/find and http://example.org/x for more.", "a URL keeps its slashes: \(verseText(url, 1).debugDescription)")
        let broken = parse("\\c 1\n\\q1\n\\v 1 Blessed is the man // who walks\n\\q2 not //in the way")
        #expect(verseText(broken, 1)?.contains("//") == false, "\(verseText(broken, 1).debugDescription)")
        #expect(verseText(broken, 1)?.contains("man who walks") == true, "the break leaves one space: \(verseText(broken, 1).debugDescription)")
        // no space either side: the words do not run together
        let tight = parse("\\c 1\n\\p\n\\v 1 praise//him")
        #expect(verseText(tight, 1) == "1praise him", "\(verseText(tight, 1).debugDescription)")
    }

    // MARK: Nesting

    @Test func aStyleNestedInAnotherWorksWithOrWithoutThePlus() {
        let withPlus = parse("\\c 1\n\\p\n\\v 1 He said \\wj Follow \\+w me|strong=\"G3427\"\\+w* now\\wj* and left.")
        let without = parse("\\c 1\n\\p\n\\v 1 He said \\wj Follow \\w me|strong=\"G3427\"\\w* now\\wj* and left.")
        for text in [withPlus, without] {
            #expect(verseText(text, 1) == "1He said Follow me now and left.", "\(verseText(text, 1).debugDescription)")
            #expect(spans(text) { $0 == .redLetter } == ["Follow me now"], "\(spans(text) { $0 == .redLetter })")
            #expect(lemmas(text).count == 1 && lemmas(text)[0].contains("G3427"), "\(lemmas(text))")
            #expect(text.isStructurallyConsistent)
        }
    }

    @Test func aStyleOpenedInsideAnotherDoesNotCloseIt() {
        let text = parse("\\c 1\n\\p\n\\v 1 the \\add words of \\em Lord\\em* to us\\add* here")
        #expect(verseText(text, 1) == "1the words of Lord to us here", "\(verseText(text, 1).debugDescription)")
        #expect(text.isStructurallyConsistent)
    }

    // MARK: Word-level markup

    @Test func wordLevelMarkupGivesItsAttributesAndLeavesTheWordsAlone() {
        let text = parse("\\c 1\n\\p\n\\v 1 \\w In|lemma=\"in\" strong=\"H0001\"\\w* the \\wg λόγος|strong=\"G3056\"\\wg* and \\wh דבר|strong=\"H1697\"\\wh* and \\wa מלך|strong=\"H4428\"\\wa*.")
        #expect(verseText(text, 1) == "1In the λόγος and דבר and מלך.", "\(verseText(text, 1).debugDescription)")
        let tagged = lemmas(text)
        #expect(tagged.count == 4, "\(tagged)")
        #expect(tagged.contains { $0.contains("G3056") } && tagged.contains { $0.contains("H1697") } && tagged.contains { $0.contains("H4428") }, "\(tagged)")
        #expect(!text.text.contains("strong="))
    }

    @Test func aWordAttributeNeedsItsBarAndAWordWithoutOneIsPlain() {
        let text = parse("\\c 1\n\\p\n\\v 1 \\w grace\\w* and \\w truth|x-custom=\"1\"\\w*")
        #expect(verseText(text, 1) == "1grace and truth", "\(verseText(text, 1).debugDescription)")
    }

    // MARK: Figures

    @Test func aFigureInEitherFormIsNotShownAndDoesNotEatTheTextAroundIt() {
        let new = parse("\\c 1\n\\p\n\\v 1 Before \\fig Caption here|src=\"a.jpg\" size=\"col\" ref=\"1.1\"\\fig* after.")
        let old = parse("\\c 1\n\\p\n\\v 1 Before \\fig DESC|a.jpg|col|1.1|COPY|Caption here|1.1\\fig* after.")
        for text in [new, old] {
            #expect(verseText(text, 1) == "1Before after.", "\(verseText(text, 1).debugDescription)")
            #expect(!text.text.contains("a.jpg"))
        }
    }
}
