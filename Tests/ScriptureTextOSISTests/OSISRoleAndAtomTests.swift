// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
import ScriptureText
@testable import ScriptureTextOSIS

// Paragraph roles (plan D36, test group 14) and footnote atoms (D37, test
// group 15). Synthetic fixtures only (D24).

private func parse(_ entries: [(Int, String)], options: OSISParser.Options = .init()) -> ScriptureText {
    OSISParser(options: options).parse(entries.map { OSISParser.VerseEntry(verse: $0.0, osis: $0.1) })
}

private func parse(_ osis: String, options: OSISParser.Options = .init()) -> ScriptureText {
    parse([(1, osis)], options: options)
}

private extension ScriptureText {
    /// Every block span as "role:text", in order.
    var blockDump: [String] {
        spans.compactMap { span in
            guard case .block(let role) = span.attribute else { return nil }
            return "\(role.rawValue):\(substring(utf16Start: span.start, length: span.length) ?? "?")"
        }
    }
}

struct OSISParagraphRoleTests {

    @Test func titleTypesMapToTheirRoles() {
        let m = parse([(0, #"<title type="main">GENESIS</title><title type="chapter">CHAPTER 1</title><title type="scope">1–41</title><title type="parallel">John 1:1</title><title type="acrostic">ALEPH</title>"#),
                       (1, #"<title type="psalm">Of David</title>text"#)])
        #expect(m.blockDump == ["mt:GENESIS", "cl:CHAPTER 1", "mr:1–41", "r:John 1:1", "qa:ALEPH", "d:Of David"])
    }

    @Test func untypedTitlesTakeTheirRoleFromTheEnclosingSectionDiv() {
        // Milestone divs (Azeri style) and a container div.
        let m = parse([(1, #"<div sID="a" type="majorSection"/><title>Book One</title><div sID="b" type="section"/><title>Creation</title> text"#),
                       (2, #"<div type="subSection"><title type="sub">Day one</title> more</div><title>Again</title> end"#)])
        #expect(m.blockDump == ["ms:Book One", "s1:Creation", "s2:Day one", "s1:Again"])
    }

    @Test func poetryLevelsSelahAndTheClamp() {
        let m = parse(#"<l level="1" sID="a"/>one<l eID="a"/><l level="2" sID="b"/>two<l eID="b"/><l level="3" sID="c"/>three<l eID="c"/><l level="7" sID="d"/>deep<l eID="d"/><l type="selah" sID="s"/>Selah<l eID="s"/>"#)
        #expect(m.blockDump == ["q1:1one", "q2:two", "q3:three", "q4:deep", "qr:Selah"])
    }

    @Test func nestedListsGiveListItemDepths() {
        let m = parse(#"<list><item>outer<list><item>inner</item></list></item></list>"#)
        #expect(m.blockDump.sorted() == ["li1:1outer\ninner", "li2:inner"])
    }

    @Test func speakerIntroductionAndOutline() {
        let m = parse([(0, #"<div sID="i" type="introduction"/>About this book.<div eID="i" type="introduction"/><div type="outline">An outline</div>"#),
                       (1, #"<speaker>Bride</speaker> text"#)])
        #expect(m.blockDump == ["ip:About this book.", "io:An outline", "sp:Bride"])
    }

    @Test func ordinaryProseHasNoBlockSpan() {
        #expect(parse(#"one<div sID="p" type="x-p"/>two"#).blockDump.isEmpty)
    }

    @Test func headingsOffDropsEditorialHeadingsButKeepsCanonicalTitlesAndSpeakers() {
        var off = OSISParser.Options(); off.headings = false
        let m = parse([(0, #"<title type="main">GENESIS</title>"#),
                       (1, #"<title type="sub">Editorial</title><title canonical="true" type="psalm">Of David</title><speaker>Bride</speaker>text"#)],
                      options: off)
        // SWORD keeps title canonical="true" (verse text) and never ties speaker labels to the headings option.
        #expect(m.text == "Of David\nBride\n1text")
        #expect(m.blockDump == ["d:Of David", "sp:Bride"])
    }

    @Test func canonicalAndHeadingFlags() {
        let canonical = ParagraphRole.allCases.filter(\.isCanonical)
        #expect(canonical == [.d, .q1, .q2, .q3, .q4, .qr, .li1, .li2])
        let headings = ParagraphRole.allCases.filter(\.isHeading)
        #expect(headings == [.mt, .cl, .ms, .mr, .s1, .s2, .r, .d, .qa, .sp])
    }

    @Test func rawValuesAreTheUSFMMarkerNames() throws {
        #expect(ParagraphRole(rawValue: "q2") == .q2)
        #expect(ParagraphRole.allCases.map(\.rawValue).joined(separator: " ")
                == "mt cl ms mr s1 s2 r d qa sp q1 q2 q3 q4 qr li1 li2 ip io")
    }
}

struct OSISFootnoteAtomTests {

    private let wj = "\u{2060}"

    @Test func markerIsJoinedToTheWordBeforeIt() {
        let m = parse("earth<note>body</note> and")
        #expect(m.text == "1earth\(wj)n and")
        #expect(m.texts(of: .footnote(id: "1.1")) == ["n"])  // the span is the marker alone
    }

    @Test func punctuationGluedAfterTheMarkerIsJoinedToo() {
        // ethnosdev/scripture's footnote-before-punctuation case.
        #expect(parse("shepherd<note>Rev 7:17</note>; I").text == "1shepherd\(wj)n\(wj); I")
        #expect(parse("word—<note>x</note>—word").text == "1word—\(wj)n\(wj)—word")
    }

    @Test func noJoinerAcrossWhitespace() {
        #expect(parse("earth <note>body</note> and").text == "1earth n and")
        #expect(parse("earth<note>body</note> , and").text == "1earth\(wj)n , and")
    }

    @Test func noJoinerAfterABreak() {
        #expect(parse("one<lb/><note>body</note>two").text == "1one\nntwo")
    }

    @Test func aWordAfterTheMarkerIsNotJoined() {
        #expect(parse("earth<note>body</note>two").text == "1earth\(wj)ntwo")
    }

    /// WEB apocrypha shape: the space after a note is kept inside it.
    @Test func whitespaceKeptInsideANoteBecomesTheSpaceAfterIt() {
        let osis = #"trumpets,<note type="translation">Gr. <rdg>trumpets of signals. </rdg></note>and cried"#
        #expect(parse(osis).text == "1trumpets,\(wj)n and cried")
        var off = OSISParser.Options(); off.footnotes = false
        #expect(parse(osis, options: off).text == "1trumpets, and cried")
        #expect(parse(osis).anchorTexts == ["trumpets", "and", "cried"])
        #expect(parse(osis, options: off).anchorTexts == ["trumpets", "and", "cried"])
    }

    @Test func butNotBeforePunctuation() {
        #expect(parse("hell<note>Lat. Gehenna. </note>, and").text == "1hell\(wj)n\(wj), and")
    }

    /// Azeri shape: a note between the parts of a compound (Abba-Father).
    @Test func aNoteIsAWordBoundary() {
        let osis = "آبّا<note n=\"31\">a note</note>-آتا، سنه"
        var off = OSISParser.Options(); off.footnotes = false
        #expect(parse(osis).anchorTexts == ["آبّا", "آتا", "سنه"])
        #expect(parse(osis, options: off).anchorTexts == ["آبّا", "آتا", "سنه"])
    }

    @Test func joinersDoNotMoveWordAnchorsOrOtherSpans() {
        var off = OSISParser.Options(); off.footnotes = false
        let with = parse(#"<w lemma="strong:H1">earth</w><note>body</note>. <w lemma="strong:H2">and</w>"#)
        let without = parse(#"<w lemma="strong:H1">earth</w><note>body</note>. <w lemma="strong:H2">and</w>"#, options: off)
        #expect(with.anchorTexts == without.anchorTexts)
        #expect(with.texts(of: .word(lemma: "strong:H2", morph: nil)) == ["and"])
        #expect(with.isConsistent)
    }
}
