// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
import ScriptureText
@testable import ScriptureTextOSIS

/// The tokenizer must agree with Foundation's XMLParser on every well-formed
/// OSIS fragment (plan D32, test group 6). Synthetic fixtures here; the same
/// check runs over every real chapter in OSISCorpusTests.
struct OSISOracleTests {

    private func expectAgreement(_ fragment: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let ours = XMLParserOracle.tokenizerEvents(of: fragment)
        let theirs = try XMLParserOracle.events(of: fragment)
        if let difference = XMLParserOracle.firstDifference(ours, theirs) {
            Issue.record("tokenizer and XMLParser disagree on \(fragment.prefix(80))…: \(difference)",
                         sourceLocation: sourceLocation)
        }
    }

    // MARK: Shapes each surveyed module uses

    @Test func kjvStyleVerseWithLemmasMorphNotesAndMilestone() throws {
        try expectAgreement(#"<milestone marker="¶" type="x-p"/><w lemma="strong:H0430">And God</w> <w lemma="strong:H0559" morph="strongMorph:TH8799">said</w>, <q marker="" who="Jesus"><transChange type="added">Let</transChange> there</q><note type="study"><catchWord>t</catchWord> <rdg type="x-literal">x</rdg></note> <divineName>Lord</divineName>."#)
    }

    @Test func chapterAndBookMarkersAsSelfClosingElements() throws {
        try expectAgreement(#"<div canonical="true" osisID="Gen" sID="gen1" type="book"/> <title type="main">THE FIRST BOOK</title><chapter chapterTitle="CHAPTER 1." osisID="Gen.1" sID="gen2"/><title type="chapter">CHAPTER 1.</title>"#)
    }

    @Test func milestonePoetryWithLevelsAndSelah() throws {
        try expectAgreement(#"<lg sID="g1"/><l level="1" sID="a"/>Line one<l eID="a"/> <l level="2" sID="b"/>Line two<l eID="b"/><l type="selah" sID="s"/>Selah<l eID="s"/><lg eID="g1"/>"#)
    }

    @Test func containersSpanningVerseEntriesBalanceAsOneChapterStream() throws {
        // Entry boundaries disappear when entries are joined: <list><item> opens
        // in one verse and closes in a later one.
        try expectAgreement("<list><item> Alpha" + "Beta" + "Gamma </item></list>" + "after")
    }

    @Test func notesWithReferencesAndFootnoteAttributes() throws {
        try expectAgreement(#"skins<note osisID="Exod.25.5!note.1" osisRef="Exod.25.5" placement="foot" type="translation"><reference osisRef="Exod.25.5" type="source">25:5 </reference>or, fine leather</note>"#)
    }

    @Test func variantSegmentsAndEmptySeg() throws {
        try expectAgreement(#"<seg subType="x-1" type="x-variant"> <w lemma="strong:G2532" morph="packard:C" xlit="betacode:KAI\">καὶ</w> </seg><seg/>"#)
    }

    @Test func emptyWordsAndMultiLemmaAsInChineseUnionVersion() throws {
        try expectAgreement(#"<w lemma="strong:G1161"></w><w lemma="strong:G846">耶稣对他</w><w lemma="strong:G3650 strong:G4771">尽</w>：「你的　神」"#)
    }

    @Test func arabicScriptWithFormatCharacters() throws {
        try expectAgreement("<l sID=\"x\"/>پِرِص\u{200C}خِصرون \u{200F}آتاسي\u{200E}،<l eID=\"x\"/>")
    }

    @Test func hebrewAndGreekTextWithAttributes() throws {
        try expectAgreement("<chapter n=\"1\" osisID=\"Gen.1\" sID=\"Gen.1\"/>\u{05D1}\u{05B0}\u{05BC}\u{05E8}\u{05B5}\u{05D0}\u{05E9}\u{05B4}\u{05C1}\u{05D9}\u{05EA} \u{05C3}<w lemma=\"strong:G1\" xlit=\"betacode:E)N\">ἐν</w>")
    }

    // MARK: Lexical details

    @Test func entitiesAgree() throws {
        try expectAgreement(#"<a t="x&amp;y&quot;z&lt;">Tom &amp; Jerry &lt;WAHb&gt; &#x5D0; &#182; &apos;ok&apos;</a>"#)
    }

    @Test func attributeValueContainingGreaterThanAndBothQuoteStyles() throws {
        try expectAgreement(#"<note n="a>b" t='say "hi"'>x</note>"#)
    }

    @Test func surrogatePairsAndEmoji() throws {
        try expectAgreement("<hi type=\"italic\">𝔊 😀</hi> tail")
    }

    @Test func whitespaceIsReportedIdentically() throws {
        try expectAgreement("  <a> x \n\t y </a>\n  <b/> \u{3000} \u{00A0} ")
    }

    @Test func carriageReturnsAreNormalisedLikeXML() throws {
        // XML turns CRLF and CR into LF; the oracle applies the same rule to the tokenizer.
        try expectAgreement("<a>line one\r\nline two\rline three</a>")
    }

    @Test func emptyAndTextOnlyFragments() throws {
        try expectAgreement("")
        try expectAgreement("just text")
    }

    // MARK: The oracle must be able to fail

    /// A check that cannot fail proves nothing. These feed the comparison input
    /// the two parsers are *known* to read differently and require the oracle to
    /// notice, so a future change that made it vacuous would be caught.
    /// Pins what the XMLParser side actually produces, so "the two agree"
    /// cannot mean "both are empty".
    @Test func theOracleSideProducesRealEvents() throws {
        #expect(try XMLParserOracle.events(of: #"<a b="1">x<c/></a>"#) == [
            .start("a", ["b": "1"], selfClosing: false),
            .text("x"),
            .start("c", [:], selfClosing: false), .end("c"),
            .end("a"),
        ])
    }

    @Test func theOracleDetectsARealDifference() throws {
        let ours = XMLParserOracle.tokenizerEvents(of: "<a>x</a>")
        let different = XMLParserOracle.tokenizerEvents(of: "<a>y</a>")
        #expect(XMLParserOracle.firstDifference(ours, different) != nil)
    }

    @Test func malformedInputIsRejectedByXMLParserButNotLostByTheTokenizer() {
        // Documented, accepted divergence: the tokenizer is tolerant by design.
        // Linux's XMLParser (libxml2) is lenient about unclosed elements and does
        // not reject them, so the strict-rejection check only runs on Apple platforms.
        #if !os(Linux)
        #expect(throws: (any Error).self) { try XMLParserOracle.events(of: "<a>unclosed") }
        #endif
        #expect(XMLParserOracle.tokenizerEvents(of: "<a>unclosed").contains(.text("unclosed")))
    }

    @Test func aTagCutOffByTheEndOfInputIsAKnownDivergence() throws {
        // Real modules contain entries truncated mid-tag. XMLParser rejects the
        // document; the tokenizer keeps the content before the cut.
        // Linux's XMLParser (libxml2) is lenient about mid-tag truncation, so the
        // strict-rejection check only runs on Apple platforms.
        #if !os(Linux)
        #expect(throws: (any Error).self) { try XMLParserOracle.events(of: "ab<w lemm") }
        #endif
        #expect(XMLParserOracle.tokenizerEvents(of: "ab<w lemm") == [.text("ab")])
    }

    @Test func unknownEntitiesAreAKnownDivergence() throws {
        // XMLParser rejects &nbsp; (not predefined in XML); the tokenizer passes it through.
        #expect(throws: (any Error).self) { try XMLParserOracle.events(of: "a&nbsp;b") }
        #expect(XMLParserOracle.tokenizerEvents(of: "a&nbsp;b") == [.text("a&nbsp;b")])
    }
}
