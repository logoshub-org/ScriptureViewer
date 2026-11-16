// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import ScriptureText
import ScriptureTextTestSupport
@testable import ScriptureTextUSFM

/// USFM markup the KJV cross-check does not reach (plan Track V4).
struct USFMParserTests {

    private func parse(_ usfm: String, _ configure: (inout USFMParser.Options) -> Void = { _ in }) -> ScriptureText {
        var options = USFMParser.Options()
        configure(&options)
        return USFMParser(options: options).parse(usfm)
    }

    private func spans(_ text: ScriptureText, _ match: (ScriptureText.Attribute) -> Bool) -> [String] {
        text.spans.filter { match($0.attribute) }.compactMap { text.substring(utf16Start: $0.start, length: $0.length) }
    }

    private func verseText(_ text: ScriptureText, _ verse: Int) -> String? {
        text.verseRange(containing: verse).flatMap { text.substring(utf16Start: $0.start, length: $0.length) }
    }

    @Test func aPilcrowThatOpensAParagraphIsLeftOut() {
        let text = parse("\\c 1\n\\p\n\\v 5 Day.\n\\p\n\\v 6 \u{00B6} And God said. \u{00B6} Then more.")
        #expect(verseText(text, 6) == "6And God said. \u{00B6} Then more.", "\(verseText(text, 6).debugDescription): the break shows the paragraph; one inside a verse stays")
        #expect(verseText(text, 5) == "5Day.")
    }

    @Test func aQuotationByJesusIsRedLetterAcrossParagraphs() {
        let usfm = "\\c 1\n\\p\n\\v 1 He said \\qt-s |sid=\"qt_1\" who=\"Jesus\"\\*Follow me,\n\\p and live.\\qt-e |eid=\"qt_1\"\\* Then he went.\n\\v 2 Peter said \\qt-s |who=\"Peter\"\\*No.\\qt-e\\*"
        let text = parse(usfm)
        #expect(spans(text) { $0 == .redLetter } == ["Follow me,", "and live."], "\(spans(text) { $0 == .redLetter })")
        #expect(text.text.contains("He said Follow me,"), "\(text.text.debugDescription)")
        #expect(text.text.contains("No."), "the milestone's attributes are not text")
        #expect(!text.text.contains("who="))
        #expect(parse(usfm) { $0.redLetter = false }.spans.filter { $0.attribute == .redLetter }.isEmpty)
        #expect(text.isStructurallyConsistent)
    }

    @Test func aCrossReferenceTargetIsAReferenceTheNoteCites() {
        let usfm = "\\c 1\n\\p\n\\v 4 it was good\\x - \\xo 1:4 \\xt Ps 33:9; 2 Cor 4:6\\x* and \\x - \\xo 1:4 \\xt Gen 1:1|link-href=\"GEN 1:1\"\\xt*\\x*."
        let text = parse(usfm)
        #expect(text.notes.map(\.references) == [["Ps 33:9; 2 Cor 4:6"], ["Gen 1:1"]], "\(text.notes)")
        #expect(text.notes.map(\.text) == ["Ps 33:9; 2 Cor 4:6", "Gen 1:1"], "the attributes are not in the note's text: \(text.notes)")
        #expect(text.notes.allSatisfy { $0.kind == .crossReference })
    }

    @Test func tokensSplitMarkersEndMarkersAndText() {
        #expect(USFMTokenizer.tokens("\\p\n\\v 1 In \\+nd God\\+nd*\\qt-s |who=\"x\"\\* a\\b \\\\ c") == [
            .marker("p", nested: false), .marker("v", nested: false), .text("1 In "), .marker("nd", nested: true),
            .text("God"), .end("nd", nested: true), .marker("qt-s", nested: false), .text("|who=\"x\""), .end("", nested: false),
            .text(" a"), .marker("b", nested: false), .text("\\\\ c"),
        ])
    }

    @Test func versesParagraphsAndPoetry() {
        let text = parse("\\c 1\n\\p\n\\v 1 In the beginning.\n\\v 2 And the earth.\n\\q1\n\\v 3 A line,\n\\q2 and another.")
        #expect(text.text == "1In the beginning. 2And the earth.\n3A line,\nand another.", "as OSIS: no space after the number")
        #expect(text.verses.map(\.verse) == [1, 2, 3])
        #expect(verseText(text, 3) == "3A line,\nand another.")
        #expect(spans(text) { $0 == .block(.q1) } == ["3A line,"], "a poetry line holds its verse number")
        #expect(spans(text) { $0 == .block(.q2) } == ["and another."])
        #expect(spans(text) { if case .verseNumber = $0 { return true }; return false } == ["1", "2", "3"])
        #expect(text.isStructurallyConsistent)
    }

    @Test func bridgesPartsAndPrintedNumbers() {
        let text = parse("\\c 1\n\\p\n\\v 1-2 Two verses.\n\\v 3a Part.\n\\v 4 \\vp 4b\\vp* Printed.\n\\v 5 \\va 6\\va* Alternate.")
        #expect(text.verses.map(\.verse) == [1, 3, 4, 5])
        #expect(text.verses[0].lastVerse == 2)
        #expect(text.verses[1].label == "3a" && text.verses[2].label == "4b")
        #expect(text.text == "1-2Two verses. 3aPart. 4bPrinted. 5Alternate.", "the alternate number is not shown yet")
        #expect(verseText(text, 2) == "1-2Two verses.")
    }

    /// A verse in parts (the Nyangumarta English Bible's `\v 14a` … `\v 14b`): one verse whose words count on
    /// through both parts, so a saved word reference means one word; highlighting and copying take both parts.
    @Test func aVerseInPartsIsOneVerse() throws {
        let text = parse("\\c 1\n\\p\n\\v 13 Before.\n\\v 14a One two\n\\s1 Heading\n\\p\n\\v 14b three.\n\\v 15 After.")
        #expect(text.verses.map(\.verse) == [13, 14, 14, 15])
        #expect(text.verses.map(\.label) == [nil, "14a", "14b", nil])
        #expect(text.words.filter { $0.verse == 14 }.map(\.index) == [0, 1, 2])
        #expect(text.isStructurallyConsistent)
        let resolved = text.resolve([Highlight(.verse(14), style: .bookmark(colour: "#FF0000"))])
        #expect(resolved.compactMap { text.substring(utf16Start: $0.start, length: $0.length) } == ["One two", "three."])
        #expect(text.copiedText(verse: 14)?.text == "14a One two\nHeading\n14b three.")
    }

    /// A reader's edition that moves part of a verse later (`\v 15b` after verse 16): the word indexes go on.
    @Test func aMovedPartGoesOnCountingItsVerse() throws {
        var text = parse("\\c 2\n\\p\n\\v 15a Out of Egypt\n\\v 16 Then Herod.\n\\v 15b have I called.")
        #expect(text.verses.map(\.verse) == [15, 16, 15])
        #expect(text.words.filter { $0.verse == 15 }.map(\.index) == [0, 1, 2, 3, 4, 5])
        text.identity = PassageIdentity(work: "t", versification: "English", book: "Matt", chapter: 2)
        let called = try #require(text.words.last)
        #expect(text.anchor(for: try #require(text.reference(for: called))) == called)
    }

    @Test func headingsShowOrHideAndPsalmTitlesStay() {
        let usfm = "\\c 3\n\\s1 A Section\n\\d A Psalm of David.\n\\q1\n\\v 1 LORD, how are they increased!"
        let shown = parse(usfm)
        #expect(spans(shown) { $0 == .block(.s1) } == ["A Section"])
        #expect(spans(shown) { $0 == .block(.d) } == ["A Psalm of David."])
        let hidden = parse(usfm) { $0.headings = false }
        #expect(spans(hidden) { $0 == .block(.s1) }.isEmpty)
        #expect(spans(hidden) { $0 == .block(.d) } == ["A Psalm of David."], "a Psalm title is Bible text")
        #expect(hidden.text.hasPrefix("A Psalm of David.\n1LORD"))
    }

    @Test func aHeadingBeforeTheNextVerseIsNotPartOfTheVerseBefore() {
        let text = parse("\\c 119\n\\q1\n\\v 8 I will keep thy statutes.\n\\s1 \\tl BETH.\\tl*\n\\q1\n\\v 9 Wherewithal shall a young man.")
        #expect(verseText(text, 8) == "8I will keep thy statutes.")
        #expect(spans(text) { $0 == .block(.s1) } == ["BETH."])
    }

    @Test func wordsCarryStrongsAndShowMarkersWhenAsked() throws {
        let usfm = "\\c 1\n\\p\n\\v 1 In the \\w beginning|strong=\"H7225\"\\w* \\w God|strong=\"H0430,H1234\" x-morph=\"He,Ncmpa\"\\w* \\w created|lemma=\"bara\"\\w*."
        let text = parse(usfm)
        let words = text.spans.compactMap { span -> String? in
            if case .word(let lemma, _) = span.attribute { return lemma }
            return nil
        }
        #expect(words == ["strong:H7225", "strong:H0430 strong:H1234", "lemma.usfm:bara"])
        #expect(text.spans.contains { $0.attribute == .word(lemma: "strong:H0430 strong:H1234", morph: "He,Ncmpa") })
        #expect(text.text == "1In the beginning God created.")
        #expect(text.words.map { text.substring(utf16Start: $0.start, length: $0.length) } == ["In", "the", "beginning", "God", "created"])
        let marked = parse(usfm) { $0.strongsMarkers = true }
        #expect(marked.text == "1In the beginning<7225> God<0430><1234> created.", "a lexical form is not a Strong's marker")
    }

    /// The BSB with full Strong's tags writes an untranslated word as `\w -|strong="G2532"\w*`: no text, no word, but
    /// its number where it stands when Strong's numbers are shown.
    @Test func aPlaceholderWordShowsOnlyItsNumber() {
        let usfm = "\\c 1\n\\p\n\\v 16 \\w -|strong=\"G2532\"\\w* \\w Many|strong=\"G4183\"\\w* \\w of the|strong=\"G3588\"\\w* sons, \\w -|strong=\"G3588\"\\w* \\w God|strong=\"G2316\"\\w*."
        let plain = parse(usfm)
        #expect(plain.text == "16Many of the sons, God.")
        #expect(plain.words.map { plain.substring(utf16Start: $0.start, length: $0.length) } == ["Many", "of", "the", "sons", "God"])
        #expect(plain.spans.filter { if case .word = $0.attribute { return true }; return false }.count == 3)
        let marked = parse(usfm) { $0.strongsMarkers = true }
        #expect(marked.text == "16<2532> Many<4183> of the<3588> sons, <3588> God<2316>.")
        #expect(marked.isStructurallyConsistent)
    }

    @Test func nestedCharacterStylesRedLetterAndTheDivineName() {
        let text = parse("\\c 1\n\\p\n\\v 1 \\wj I am \\+nd the Lord\\+nd* \\+add thy\\+add* God.\\wj* Then \\bd bold\\bd* and \\sc small\\sc*.")
        #expect(spans(text) { $0 == .redLetter } == ["I am THE LORD thy God."])
        #expect(spans(text) { $0 == .divineName } == ["THE LORD"])
        #expect(spans(text) { $0 == .italic } == ["thy"])
        #expect(spans(text) { $0 == .bold } == ["bold"])
        #expect(spans(text) { $0 == .small } == ["small"])
        let plain = parse("\\c 1\n\\p\n\\v 1 \\wj Words.\\wj*") { $0.redLetter = false }
        #expect(spans(plain) { $0 == .redLetter }.isEmpty)
    }

    @Test func footnotesAndCrossReferences() throws {
        let usfm = "\\c 1\n\\p\n\\v 4 the light\\f + \\fr 1.4 \\ft the light from…: Heb. between\\f*, and \\x - \\xo 1.4 \\xt Ps 33:9\\x* it was good."
        let text = parse(usfm)
        #expect(text.notes.map(\.text) == ["the light from…: Heb. between", "Ps 33:9"], "the origin reference is dropped")
        #expect(text.notes.map(\.kind) == [.footnote, .crossReference])
        #expect(text.text == "4the light\u{2060}n\u{2060}, and x it was good.", "joined to the word and the comma after it (D37)")
        let none = parse(usfm) { $0.footnotes = false; $0.crossReferences = false }
        #expect(none.text == "4the light, and it was good." && none.notes.isEmpty)
    }

    @Test func breaksSkippedDataAndSpecialCharacters() {
        let text = parse("\\c 1\n\\q1\n\\v 1 One\n\\b\n\\q1 two~words // here\\qt-s |who=\"Jesus\"\\*\n\\p\n\\v 2 \\fig A picture|src=\"a.jpg\"\\fig* Text \\zaln-s |x-strong=\"G1\"\\*kept\\zaln-e\\*.")
        #expect(text.text == "1One\n\ntwo\u{00A0}words here\n2Text kept.")
    }

    @Test func linksNoBreakAndUnknownMarkers() {
        let text = parse("\\c 2\n\\nb\n\\v 1 See \\ref Gen 1:1|loc=\"GEN 1:1\"\\ref* and \\zzz odd\\zzz* \\jmp here|link-href=\"https://example.org\"\\jmp*.")
        #expect(text.text == "1See Gen 1:1 and odd here.")
        #expect(text.spans.contains { $0.attribute == .link(target: "passage:GEN 1:1") })
        #expect(text.spans.contains { $0.attribute == .link(target: "https://example.org") })
    }

    @Test func aBookIndexesItsChaptersAndNames() throws {
        let usfm = "\\id GEN Genesis\n\\usfm 3.0\n\\h Genesis\n\\toc1 The First Book of Moses\n\\toc2 Genesis\n\\toc3 Gen\n\\cl Chapter\n\\mt1 Genesis\n\\c 1\n\\p\n\\v 1 In the beginning.\n\\c 2\n\\cl Two\n\\p\n\\v 1 Thus.\n\\cls\n"
        let book = try #require(USFMBook(usfm))
        #expect(book.code == "GEN" && book.shortName == "Genesis" && book.longName == "The First Book of Moses")
        #expect(book.abbreviation == "Gen" && book.chapterLabel == "Chapter")
        #expect(book.chapters == [1, 2])
        let first = try #require(USFMParser().parse(book, chapter: 1))
        #expect(first.text == "Genesis\n1In the beginning.", "chapter 1 carries the title, not the label for every chapter")
        #expect(first.spans.first?.attribute == .block(.mt))
        let second = try #require(USFMParser().parse(book, chapter: 2))
        #expect(second.text == "Two\n1Thus.", "a chapter's own label is its heading")
        #expect(USFMParser().parse(book, chapter: 3) == nil)
        #expect(USFMBook("\\p no id") == nil)
    }

    @Test func identityIsCarried() throws {
        let book = try #require(USFMBook("\\id JHN\n\\c 3\n\\p\n\\v 16 For God so loved."))
        let identity = PassageIdentity(work: "KJV-USFM", versification: "English", book: "John", chapter: 3)
        let text = try #require(USFMParser().parse(book, chapter: 3, identity: identity))
        #expect(text.identity == identity)
        #expect(text.reference(for: text.words[0])?.osisVerse == "John.3.16")
    }
}
