// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
import ScriptureText
@testable import ScriptureTextOSIS

// All fixtures are synthetic, modelled on the markup the eight surveyed
// modules actually use (plan D32/D34). No module text is committed (D24).

private func parse(_ entries: [(Int, String)],
                   options: OSISParser.Options = .init(),
                   profile: ScriptureContentProfile = .chapter) -> ScriptureText {
    OSISParser(options: options, profile: profile)
        .parse(entries.map { OSISParser.VerseEntry(verse: $0.0, osis: $0.1) })
}

private func parse(_ osis: String, options: OSISParser.Options = .init()) -> ScriptureText {
    parse([(1, osis)], options: options)
}

extension ScriptureText {
    /// The text covered by every span carrying exactly this attribute.
    func texts(of attribute: ScriptureText.Attribute) -> [String] {
        spans.filter { $0.attribute == attribute }
            .compactMap { substring(utf16Start: $0.start, length: $0.length) }
    }

    func verseText(_ verse: Int) -> String? {
        guard let r = verses.first(where: { $0.verse == verse }) else { return nil }
        return substring(utf16Start: r.start, length: r.length)
    }

    /// Structural invariants every parse must satisfy.
    var isConsistent: Bool {
        let total = text.utf16.count
        for s in spans where s.start < 0 || s.length <= 0 || s.start + s.length > total { return false }
        var previousEnd = 0
        for v in verses {
            if v.start < previousEnd || v.length < 0 || v.start + v.length > total { return false }
            previousEnd = v.start + v.length
        }
        // Word anchors: in order, inside the text, non-empty, sequential per verse.
        var wordEnd = 0
        var next: [Int: Int] = [:]
        for w in words {
            if w.start < wordEnd || w.length <= 0 || w.start + w.length > total { return false }
            if w.index < next[w.verse, default: 0] { return false }
            next[w.verse] = w.index + 1
            wordEnd = w.start + w.length
        }
        return true
    }
}

// MARK: - Element mapping

struct OSISElementMappingTests {

    @Test func wordCarriesLexicalDataAndVerseMarkerIsSynthesised() {
        let m = parse(#"<w lemma="strong:H07225">In the beginning</w> <w lemma="strong:H0430">God</w>."#)
        #expect(m.text == "1In the beginning God.")
        #expect(m.texts(of: .verseNumber(1)) == ["1"])
        #expect(m.texts(of: .word(lemma: "strong:H07225", morph: nil)) == ["In the beginning"])
        #expect(m.texts(of: .word(lemma: "strong:H0430", morph: nil)) == ["God"])
        #expect(m.isConsistent)
    }

    @Test func multiLemmaWordKeepsTheWholeList() {
        let m = parse(#"<w lemma="strong:H0853 strong:H01254" morph="strongMorph:TH8804">created</w>"#)
        #expect(m.texts(of: .word(lemma: "strong:H0853 strong:H01254", morph: "strongMorph:TH8804")) == ["created"])
    }

    @Test func emptyWordMakesNoSpanAndDoesNotDisturbOffsets() {
        let m = parse(#"<w lemma="strong:G1161"></w><w lemma="strong:G846">耶稣对他</w><w lemma="strong:G2532 strong:G1722"></w>。"#)
        #expect(m.text == "1耶稣对他。")
        #expect(m.spans.filter { if case .word = $0.attribute { true } else { false } }.count == 1)
        #expect(m.isConsistent)
    }

    @Test func transChangeIsItalicAndDivineNameIsItsOwnAttribute() {
        let m = parse(#"the <transChange type="added">Lord</transChange> said <divineName>Lord</divineName>"#)
        #expect(m.texts(of: .italic) == ["Lord"])
        // SWORD sets the divine name in capitals; the styler draws all but the first letter smaller.
        #expect(m.texts(of: .divineName) == ["LORD"])
        #expect(m.text.hasSuffix("said LORD"))
    }

    @Test func divineNameCapitalsAreNotLeftOnAfterItsEnd() {
        let m = parse(#"<divineName>Lord</divineName> is my shepherd"#)
        #expect(m.text == "1LORD is my shepherd")
    }

    @Test func redLetterIsGatedByTheOption() {
        let osis = #"<q who="Jesus" marker="">Follow me</q> <q who="Peter">No</q>"#
        #expect(parse(osis).texts(of: .redLetter) == ["Follow me"])
        var off = OSISParser.Options(); off.redLetter = false
        #expect(parse(osis, options: off).texts(of: .redLetter).isEmpty)
        // text unchanged either way; the unmarked <q> gets SWORD's default quotation marks
        #expect(parse(osis, options: off).text == "1Follow me \"No\"")
    }

    @Test func hiVariants() {
        let m = parse(#"<hi type="italic">a</hi> <hi type="bold">b</hi> <hi type="small-caps">c</hi> <hi type="x">d</hi>"#)
        #expect(m.texts(of: .italic) == ["a"])
        #expect(m.texts(of: .bold) == ["b"])
        #expect(m.texts(of: .small) == ["c"])
        #expect(m.text == "1a b c d")
    }

    @Test func titlesBecomeHeadingsWithTypedRoles() {
        let m = parse([(0, #"<title type="main">GENESIS</title> <title type="chapter">CHAPTER 1.</title>"#),
                       (1, #"<title type="psalm">A Psalm</title> text"#)])
        #expect(m.texts(of: .block(.mt)) == ["GENESIS"])
        #expect(m.texts(of: .block(.cl)) == ["CHAPTER 1."])
        #expect(m.texts(of: .block(.d)) == ["A Psalm"])
        #expect(m.text == "GENESIS\nCHAPTER 1.\nA Psalm\n1text")
    }

    @Test func headingsOffDropsTheTitleText() {
        var off = OSISParser.Options(); off.headings = false
        let m = parse([(0, "<title type=\"main\">GENESIS</title>"), (1, "text")], options: off)
        #expect(m.text == "1text")
        #expect(m.spans.allSatisfy { if case .block(let role) = $0.attribute { !role.isHeading } else { true } })
    }

    @Test func paragraphMilestonesBreakAndTheGlyphIsDropped() {
        // KJV style
        let kjv = parse(#"one<milestone marker="¶" type="x-p"/>two"#)
        #expect(kjv.text == "1one\ntwo")
        // WEB/BSB/ASV style
        let web = parse(#"one<div sID="a" type="x-p"/>two<div eID="a" type="x-p"/>three"#)
        #expect(web.text == "1one\ntwo\nthree")
    }

    @Test func twoBreaksOfSWORDsHTMLInARowAreABlankLine() {
        // BSB Psalm 119:8-9: line end + </lg> (two <br />), then <lb/> + a paragraph start.
        let m = parse([(8, #"<lg sID="a"/><l level="1" sID="x"/>keep<l eID="x" level="1"/><lg eID="a"/>"#),
                       (9, #"<lb/><div type="x-p" sID="p"/>BETH<div type="x-p" eID="p"/><lb/><lg sID="b"/><l level="1" sID="y"/>How<l eID="y" level="1"/>"#)])
        #expect(m.text == "8keep\n\n9BETH\n\nHow")
    }

    @Test func textInAPreverseRegionIsAHeadingBeforeTheVerseNumber() {
        // The BSB's acrostic letters: a paragraph between x-preverse milestones, no <title>.
        let entry = #"<div type="x-milestone" subType="x-preverse" sID="pv"/><lb/> <div sID="p" type="x-p"/>BETH <div eID="p" type="x-p"/> <lb/> <div type="x-milestone" subType="x-preverse" eID="pv"/>How can a young man"#
        let on = parse([(8, "keep"), (9, entry)])
        #expect(on.text == "8keep\nBETH\n9How can a young man")
        #expect(on.texts(of: .block(.s1)) == ["BETH"])
        #expect(on.verses.map(\.verse) == [8, 9])
        #expect(on.words.filter { $0.verse == 9 }.count == 5)          // the heading takes no word indexes
        var off = OSISParser.Options(); off.headings = false
        #expect(parse([(8, "keep"), (9, entry)], options: off).text == "8keep\n9How can a young man")
    }

    @Test func aSectionTitleAndAnAcrosticLetterInOnePreverseRegion() {
        // BSB Psalm 119:1: a section title, then the letter as a paragraph.
        let entry = #"<div type="x-milestone" subType="x-preverse" sID="pv"/><div sID="s" type="section"/><title canonical="false" type="sub">Your Word Is a Lamp </title> <div sID="p" type="x-p"/>ALEPH <div eID="p" type="x-p"/> <lg sID="g"/><l level="1" sID="l"/> <div type="x-milestone" subType="x-preverse" eID="pv"/>Blessed are those"#
        var off = OSISParser.Options(); off.headings = false
        #expect(parse([(1, entry)], options: off).text == "1Blessed are those")
        let on = parse([(1, entry)])
        #expect(on.texts(of: .block(.s1)) == ["Your Word Is a Lamp", "ALEPH"])
        #expect(on.text.hasSuffix("1Blessed are those"))
    }

    @Test func aTitleInsideAPreverseRegionKeepsItsOwnRole() {
        let entry = #"<div type="x-milestone" subType="x-preverse" sID="pv"/><title canonical="true" type="acrostic">BETH.</title> <div type="x-milestone" subType="x-preverse" eID="pv"/>Wherewithal"#
        var off = OSISParser.Options(); off.headings = false
        let m = parse([(9, entry)], options: off)
        #expect(m.texts(of: .block(.qa)).isEmpty)                       // canonical, but filed with the headings (owner, web view, 2026-11-03)
        #expect(m.text == "9Wherewithal")
        let on = parse([(9, entry)])
        #expect(on.texts(of: .block(.qa)) == ["BETH."])
        #expect(on.text == "BETH.\n9Wherewithal")
    }

    @Test func aParagraphAfterAParagraphIsAGapButAParagraphAfterTextIsNot() {
        let two = parse(#"<p>one</p><p>two</p>"#)
        #expect(two.text == "1one\n\ntwo")
        let one = parse(#"one<div type="x-p" sID="a"/>two"#)
        #expect(one.text == "1one\ntwo")
    }

    @Test func noGapRightAfterAHeading() {
        let m = parse(#"<title>Heading</title><p>text</p>"#)
        #expect(m.text == "Heading\n1text")
    }

    @Test func structuralMarkersAreSkippedAndUnknownElementsDegradeToText() {
        let m = parse(#"<chapter osisID="Gen.1" sID="x"/><div type="book" osisID="Gen" sID="g"/><milestone type="x-usfm-h" n=""/><custom a="1">kept</custom>"#)
        #expect(m.text == "1kept")
    }

    @Test func entitiesDecodeIntoText() {
        let m = parse("Tom &amp; Jerry &lt;WAHb&gt; &#x5D0;")
        #expect(m.text == "1Tom & Jerry <WAHb> א")
    }
}

// MARK: - Quotations (SWORD's osisxhtml.cpp <q> rules)

struct OSISQuoteTests {

    @Test func anExplicitMarkerIsPrintedOnBothSidesAndAnEmptyOneMeansNone() {
        #expect(parse(#"<q marker="“">Hello</q> x"#).text == "1“Hello“ x")
        #expect(parse(#"<q marker="">Hello</q> x"#).text == "1Hello x")
    }

    @Test func withoutAMarkerQuoteMarksAlternateByLevel() {
        #expect(parse(#"<q>outer <q level="2">inner</q> end</q>"#).text == "1\"outer 'inner' end\"")
    }

    @Test func theConfSettingTurnsDefaultMarksOffButNotExplicitOnes() {
        var off = OSISParser.Options(); off.quoteMarks = false     // OSISqToTick=false
        #expect(parse(#"<q>plain</q> <q marker="«">kept</q>"#, options: off).text == "1plain «kept«")
    }

    @Test func containerWordsOfChristIncludeTheirQuoteMarks() {
        let m = parse(#"He said, <q who="Jesus">Follow me</q> and they went."#)
        #expect(m.text == "1He said, \"Follow me\" and they went.")
        #expect(m.texts(of: .redLetter) == ["\"Follow me\""])
    }

    @Test func milestoneWordsOfChristAreRedLetterAndMayCrossVerses() {
        let m = parse([(1, #"He said, <q sID="q1" who="Jesus" marker=""/>Follow me,"#),
                       (2, #"and I will make you<q eID="q1" who="Jesus" marker=""/> fishers."#)])
        #expect(m.text == "1He said, Follow me, 2and I will make you fishers.")
        #expect(m.texts(of: .redLetter) == ["Follow me, 2and I will make you"])
    }

    @Test func milestoneMarksFollowTheSameRules() {
        let m = parse(#"<q sID="a" who="Jesus"/>Come<q eID="a" who="Jesus"/> now"#)
        #expect(m.text == "1\"Come\" now")
        #expect(m.texts(of: .redLetter) == ["\"Come\""])
    }

    @Test func redLetterOffKeepsTheMarks() {
        var off = OSISParser.Options(); off.redLetter = false
        let m = parse(#"<q sID="a" who="Jesus"/>Come<q eID="a" who="Jesus"/>"#, options: off)
        #expect(m.text == "1\"Come\"")
        #expect(m.texts(of: .redLetter).isEmpty)
    }

    @Test func aBareSelfClosingQIsIgnored() {
        #expect(parse("a<q/>b").text == "1ab")
    }

    @Test func quotesInsideANoteMarkTheNoteText() {
        // WEB shape: milestone quotes inside a footnote (its conf sets OSISqToTick=false).
        let osis = #"them<note>Hebrew: <q sID="x" type="x-footnote" who="unknown"/>them<q eID="x" type="x-footnote" who="unknown"/></note>"#
        #expect(parse(osis).notes.first?.text == "Hebrew: \"them\"")
        var off = OSISParser.Options(); off.quoteMarks = false
        #expect(parse(osis, options: off).notes.first?.text == "Hebrew: them")
    }

    @Test func quoteMarksAreNotWords() {
        #expect(parse(#"<q who="Jesus">Follow me</q>."#).anchorTexts == ["Follow", "me"])
    }
}

// MARK: - Footnotes and references

struct OSISNoteTests {

    @Test func footnoteBodyLeavesTheTextAndAMarkerRemains() {
        let m = parse(#"earth<note type="study"><catchWord>the earth</catchWord> <rdg type="x-literal">land</rdg></note>."#)
        #expect(m.text == "1earth\u{2060}n\u{2060}.")       // D37 word joiners
        #expect(m.texts(of: .footnote(id: "1.1")) == ["n"])
        #expect(m.notes == [.init(id: "1.1", text: "the earth land", references: [])])
    }

    @Test func noteUsesItsOsisIDAndCollectsReferences() {
        let m = parse(#"skins<note osisID="Exod.25.5!note.1" osisRef="Exod.25.5" placement="foot" type="translation"><reference osisRef="Exod.25.5" type="source">25:5 </reference>or, fine leather</note>"#)
        #expect(m.notes == [.init(id: "Exod.25.5!note.1", text: "25:5 or, fine leather", references: ["Exod.25.5"])])
        #expect(m.texts(of: .footnote(id: "Exod.25.5!note.1")) == ["n"])
    }

    @Test func footnotesOffDropsMarkerAndNote() {
        var off = OSISParser.Options(); off.footnotes = false
        let m = parse("a<note>body</note>b", options: off)
        #expect(m.text == "1ab")
        #expect(m.notes.isEmpty)
    }

    @Test func referenceOutsideANoteIsALink() {
        let m = parse(#"see <reference osisRef="John.3.16">John 3:16</reference>"#)
        #expect(m.texts(of: .link(target: "osis:John.3.16")) == ["John 3:16"])
    }
}

// MARK: - Verse markers and ranges

struct OSISVerseTests {

    @Test func eachVerseGetsExactlyOneMarkerAndRangesAreOrdered() {
        let m = parse([(1, "In the beginning."), (2, "And the earth."), (3, "Let there be light.")])
        #expect(m.text == "1In the beginning. 2And the earth. 3Let there be light.")
        #expect(m.texts(of: .verseNumber(1)) == ["1"])
        #expect(m.texts(of: .verseNumber(2)) == ["2"])
        #expect(m.verses.map(\.verse) == [1, 2, 3])
        #expect(m.verseText(1) == "1In the beginning.")
        #expect(m.verseText(2) == "2And the earth.")
        #expect(m.verseText(3) == "3Let there be light.")
        #expect(m.isConsistent)
    }

    @Test func verseZeroIntroGetsNoMarkerAndNoRange() {
        let m = parse([(0, #"<chapter osisID="Gen.1" sID="c"/><title type="chapter">CHAPTER 1.</title>"#), (1, "text")])
        #expect(m.text == "CHAPTER 1.\n1text")
        #expect(m.verses.map(\.verse) == [1])
    }

    @Test func preVerseTitleAndParagraphBreakComeBeforeTheMarker() {
        // Azeri Genesis 1:1 shape: section, pre-verse title, paragraph, text.
        let m = parse([(1, #"<div sID="g6" type="section"/> <title subType="x-preverse">Heading</title> <div sID="g7" type="paragraph"/> Words"#)])
        #expect(m.text == "Heading\n1Words")
        #expect(m.texts(of: .block(.s1)) == ["Heading"])
        #expect(m.verseText(1) == "1Words")       // the range starts at the marker, not the title
    }

    @Test func emptyVerseKeepsAZeroLengthRangeAndNoMarker() {
        let m = parse([(1, "one"), (2, ""), (3, "three")])
        #expect(m.text == "1one 3three")
        #expect(m.verses.map(\.verse) == [1, 2, 3])
        #expect(m.verses[1].length == 0)
        #expect(m.isConsistent)
    }

    @Test func verseNumbersOffKeepsRangesButNoMarkerText() {
        var off = OSISParser.Options(); off.verseNumbers = false
        let m = parse([(1, "one"), (2, "two")], options: off)
        #expect(m.text == "one two")
        #expect(m.verseText(2) == "two")
    }

    @Test func profilesWithoutVersesBuildNoMarkersOrRanges() {
        for profile in [ScriptureContentProfile.dictionary, .devotional, .about] {
            let m = parse([(1, "entry text")], profile: profile)
            #expect(m.text == "entry text")
            #expect(m.verses.isEmpty)
        }
    }

    @Test func markerIsNotInsideAWordSpan() {
        let m = parse([(1, #"<w lemma="strong:G1">a</w>"#), (2, #"<w lemma="strong:G2">b</w>"#)])
        #expect(m.text == "1a 2b")
        #expect(m.texts(of: .word(lemma: "strong:G2", morph: nil)) == ["b"])
        #expect(m.texts(of: .verseNumber(2)) == ["2"])
    }
}

// MARK: - Whitespace and scripts

struct OSISWhitespaceTests {

    @Test func onlyXMLWhitespaceCollapses() {
        #expect(parse("a   \n\t  b").text == "1a b")
        #expect(parse("  leading and trailing  ").text == "1leading and trailing")
    }

    @Test func ideographicSpaceAndNoBreakSpaceAreContent() {
        #expect(parse("你的\u{3000}神").text == "1你的\u{3000}神")
        #expect(parse("a\u{00A0}\u{00A0}b").text == "1a\u{00A0}\u{00A0}b")
        // and they are not collapsed with their neighbours
        #expect(parse("a \u{3000} b").text == "1a \u{3000} b")
    }

    @Test func cjkWordsStayContiguous() {
        #expect(parse(#"<w lemma="a">耶稣</w><w lemma="b">对他</w><w lemma="c" morph="r:V">说</w>："#).text == "1耶稣对他说：")
    }

    @Test func formatCharactersAndCombiningMarksSurviveByteForByte() {
        let arabic = "پِرِص\u{200C}خِصرون \u{200F}آتاسي\u{200E}"
        #expect(parse(arabic).text == "1" + arabic)
        let hebrew = "בְּרֵאשִׁית\u{05C3}"
        #expect(parse(hebrew).text == "1" + hebrew)
    }

    @Test func spansUseUTF16OffsetsThroughSurrogatePairs() {
        let m = parse("𝔊 and <hi type=\"italic\">tail</hi> 😀 <hi type=\"bold\">end</hi>")
        #expect(m.texts(of: .italic) == ["tail"])
        #expect(m.texts(of: .bold) == ["end"])
        #expect(m.isConsistent)
    }
}

// MARK: - Poetry, lists and structure

struct OSISStructureTests {

    @Test func milestonePoetryBecomesIndentedParagraphsAndMissingLevelIsOne() {
        let m = parse(#"<lg sID="g"/><l level="1" sID="a"/>Line one<l eID="a"/> <l level="2" sID="b"/>Line two<l eID="b"/> <l sID="c"/>Line three<l eID="c"/><lg eID="g"/>"#)
        #expect(m.texts(of: .block(.q1)).contains("Line three"))
        #expect(m.texts(of: .block(.q2)) == ["Line two"])
        #expect(m.text == "1Line one\nLine two\nLine three")
    }

    @Test func firstPoetryLineIncludesItsVerseMarker() {
        let m = parse([(1, #"<l level="1" sID="a"/>Blessed is the man<l eID="a"/>"#)])
        #expect(m.texts(of: .block(.q1)) == ["1Blessed is the man"])
    }

    @Test func selahIsTheQrRoleInBothForms() {
        // A Selah follows text; at the very start of a verse it would (correctly)
        // include the verse marker, like any first line.
        let milestone = parse(#"praise <l type="selah" level="1" sID="s"/>Selah<l eID="s"/>"#)
        #expect(milestone.texts(of: .block(.qr)) == ["Selah"])
        let container = parse(#"praise <l type="selah">Selah</l>"#)
        #expect(container.texts(of: .block(.qr)) == ["Selah"])
    }

    @Test func containerFormLineAlsoWorks() {
        let m = parse(#"<lg><l level="3">deep</l><l>shallow</l></lg>"#)
        #expect(m.texts(of: .block(.q3)) == ["1deep"])
        #expect(m.texts(of: .block(.q1)) == ["shallow"])
    }

    @Test func listItemsSpanVerseEntriesAsOneStream() {
        // BSB shape: <list><item> opens in one verse and closes several later.
        let m = parse([(3, "<list><item> Alpha"), (4, "Beta"), (5, "Gamma </item></list>"), (6, "after")])
        #expect(m.verses.map(\.verse) == [3, 4, 5, 6])
        let item = m.spans.first { $0.attribute == .block(.li1) }
        #expect(item != nil)
        #expect(m.substring(utf16Start: item!.start, length: item!.length) == "3Alpha 4Beta 5Gamma")
        #expect(m.verseText(6) == "6after")
        #expect(m.isConsistent)
    }

    @Test func lineBreakIsABreak() {
        #expect(parse("a<lb/>b").text == "1a\nb")
    }

    @Test func unclosedContainersCloseAtTheEnd() {
        let m = parse(#"<hi type="italic">never closed <w lemma="x">word"#)
        #expect(m.texts(of: .italic) == ["never closed word"])
        #expect(m.isConsistent)
    }

    @Test func strayCloseTagsAreIgnored() {
        let m = parse("a</item></list>b</hi>")
        #expect(m.text == "1ab")
    }
}

// MARK: - Variants and markers (options)

struct OSISOptionTests {

    private let variantOSIS = #"before <seg type="x-variant" subType="x-1">primary</seg><seg type="x-variant" subType="x-2">secondary</seg> after"#

    @Test func variantsKeepThePrimaryReadingByDefault() {
        #expect(parse(variantOSIS).text == "1before primary after")
    }

    @Test func variantsSecondaryAndAll() {
        var o = OSISParser.Options(); o.variants = .secondary
        #expect(parse(variantOSIS, options: o).text == "1before secondary after")
        o.variants = .all
        #expect(parse(variantOSIS, options: o).text == "1before primarysecondary after")
    }

    @Test func aNoteInsideADroppedVariantIsDroppedToo() {
        let m = parse(#"x<seg type="x-variant" subType="x-2">y<note>gone</note></seg>"#)
        #expect(m.text == "1x")
        #expect(m.notes.isEmpty)
    }

    @Test func strongsMarkersAreInsertedAfterTheirWord() {
        var o = OSISParser.Options(); o.strongsMarkers = true
        let m = parse(#"<w lemma="strong:H07225 strong:H0430">In</w> <w lemma="strong:G1161">de</w>"#, options: o)
        #expect(m.text == "1In<07225><0430> de<1161>")
        #expect(m.texts(of: .strongs("strong:H07225")) == ["<07225>"])
        #expect(m.texts(of: .strongs("strong:H0430")) == ["<0430>"])
        #expect(m.texts(of: .word(lemma: "strong:H07225 strong:H0430", morph: nil)) == ["In"])
    }

    @Test func morphMarkersUseTheCodeAfterTheSchemeInParentheses() {
        // SWORD prints "(PREP)", not "<PREP>" (osisxhtml.cpp processMorph; checked against the Phase 0 dumps).
        var o = OSISParser.Options(); o.morphMarkers = true
        let m = parse(#"<w lemma="strong:G1" morph="robinson:V-AAI">say</w>"#, options: o)
        #expect(m.text == "1say(V-AAI)")
        #expect(m.texts(of: .morph("robinson:V-AAI")) == ["(V-AAI)"])
    }

    @Test func aTGOrTHPrefixIsDroppedFromMorphMarkersOnlyBeforeADigit() {
        var o = OSISParser.Options(); o.morphMarkers = true
        #expect(parse(#"<w morph="strongMorph:TH8799">a</w>"#, options: o).text == "1a(8799)")
        #expect(parse(#"<w morph="strongMorph:TG5656">a</w>"#, options: o).text == "1a(5656)")
        #expect(parse(#"<w morph="robinson:T-NSM">a</w>"#, options: o).text == "1a(T-NSM)")   // article, not a prefix
        #expect(parse(#"<w morph="packard:TH">a</w>"#, options: o).text == "1a(TH)")
    }

    @Test func lemmaTokensOfTheLemmasOptionAreNotMarkers() {
        // KJV carries "lemma.TR:" Greek lemmas next to the Strong's number. SWORD's OSISLemma
        // filter removes them while the "Lemmas" option is off (the app never turns it on),
        // so only the Strong's number is printed: `<3056>`, not `<3056><λόγος>`.
        var o = OSISParser.Options(); o.strongsMarkers = true
        let m = parse("<w lemma=\"strong:G3056 lemma.TR:\u{03BB}\u{03CC}\u{03B3}\u{03BF}\u{03C2}\">Word</w>", options: o)
        #expect(m.text == "1Word<3056>")
        // The data stays on the word, so a tap can still show the lemma.
        #expect(m.spans.contains { $0.attribute == .word(lemma: "strong:G3056 lemma.TR:\u{03BB}\u{03CC}\u{03B3}\u{03BF}\u{03C2}", morph: nil) })
    }

    @Test func aSelfClosingWordStillPrintsItsMarkers() {
        // The KJV's unplaced articles: <w lemma= morph=/> with no text of its own.
        var o = OSISParser.Options(); o.strongsMarkers = true; o.morphMarkers = true
        let m = parse(#"<w lemma="strong:G3588" morph="robinson:T-NSF" src="13"/><w lemma="strong:G2532" morph="robinson:CONJ">And</w>"#, options: o)
        #expect(m.text == "1<3588>(T-NSF)And<2532>(CONJ)")
        #expect(m.words.count == 1)                           // no word anchor for an empty word
    }

    @Test func aGOrHIsDroppedFromLemmaMarkersOnlyBeforeADigit() {
        var o = OSISParser.Options(); o.strongsMarkers = true
        #expect(parse(#"<w lemma="strong:H07225">a</w>"#, options: o).text == "1a<07225>")
        #expect(parse(#"<w lemma="x-Strongs:G1">a</w>"#, options: o).text == "1a<1>")
        #expect(parse(#"<w lemma="lemma:Hades">a</w>"#, options: o).text == "1a<Hades>")
        #expect(parse(#"<w lemma="G">a</w>"#, options: o).text == "1a")           // no scheme: the Lemmas option's
    }

    @Test func markersAreOffByDefault() {
        #expect(parse(#"<w lemma="strong:H1">x</w>"#).text == "1x")
    }
}

// MARK: - Robustness

struct OSISRobustnessTests {

    @Test func everyPrefixOfARealisticEntryParsesConsistently() {
        let entry = #"<milestone marker="¶" type="x-p"/><w lemma="strong:H0430">And God</w> <w lemma="strong:H0559" morph="strongMorph:TH8799">said</w>, <q who="Jesus"><transChange type="added">Let</transChange> there</q> <note type="study"><catchWord>x</catchWord> <rdg type="x-literal">y</rdg></note> &amp; <l level="2" sID="a"/>line<l eID="a"/>"#
        let scalars = Array(entry.unicodeScalars)
        for end in 0...scalars.count {
            var prefix = String.UnicodeScalarView()
            prefix.append(contentsOf: scalars[0..<end])
            let m = parse([(1, String(prefix)), (2, "tail")])
            #expect(m.isConsistent)
        }
    }

    @Test func anEntryCutOffMidTagLeaksNoMarkupAndLeavesTheNextVerseIntact() {
        // LXX shape: the entry's recorded length ends inside a tag.
        let m = parse([(1, #"<w lemma="strong:G1">Αἰγύπτου</w> <w lemm"#), (2, #"<w lemma="strong:G2">next</w>"#)])
        #expect(m.text == "1Αἰγύπτου 2next")
        #expect(!m.text.contains("<"))
        #expect(m.verseText(2) == "2next")
        #expect(m.isConsistent)
    }

    @Test func anUnclosedNoteTitleVariantOrWordCannotSwallowTheNextVerse() {
        for open in ["<note>unfinished", #"<title type="sub">unfinished"#,
                     #"<seg type="x-variant" subType="x-2">unfinished"#, #"<w lemma="strong:G1">unfinished"#] {
            let m = parse([(1, "first " + open), (2, "second verse text")])
            #expect(m.verseText(2) == "2second verse text", "\(open)")
            #expect(m.isConsistent, "\(open)")
        }
        // The note keeps what it had, and the text after it is back in the verse.
        let m = parse([(1, "a<note>body so far"), (2, "next")])
        #expect(m.notes.map(\.text) == ["body so far"])
        #expect(m.text == "1a\u{2060}n 2next")
    }

    @Test func containersThatReallySpanVersesStillDo() {
        let m = parse([(1, #"<hi type="italic">one"#), (2, "two</hi> three")])
        #expect(m.texts(of: .italic) == ["one 2two"])
    }

    @Test func anEmptyLemmaOrMorphAttributeIsNoLexicalDataAtAll() {
        let m = parse(#"<w lemma="" morph="">x</w>"#)
        #expect(m.texts(of: .word(lemma: nil, morph: nil)) == ["x"])
    }

    @Test func junkDoesNotCrash() {
        for junk in ["", "<", ">", "<<<>>>", "</>", "<a", "&", "&#;", "<![CDATA[", "<!--", "\u{0}\u{1}", "<l sID=/>", "<w lemma=>x</w>"] {
            #expect(parse(junk).isConsistent)
        }
    }
}
