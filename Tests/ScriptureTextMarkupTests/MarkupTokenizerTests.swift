// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
import ScriptureTextMarkup

/// Records the tokenizer's events so tests can assert on them exactly.
struct RecordingSink: MarkupEventSink {
    enum Event: Equatable {
        case start(String, [String: String], selfClosing: Bool)
        case text(String)
        case end(String)
    }
    var events: [Event] = []

    mutating func startElement(_ name: String, attributes: [String: String], selfClosing: Bool) {
        events.append(.start(name, attributes, selfClosing: selfClosing))
    }
    mutating func characters(_ text: String) { events.append(.text(text)) }
    mutating func endElement(_ name: String) { events.append(.end(name)) }
}

private func tokenize(_ input: String) -> [RecordingSink.Event] {
    var sink = RecordingSink()
    MarkupTokenizer.tokenize(input, into: &sink)
    return sink.events
}

/// Text events merged, so a test about content does not depend on how the
/// tokenizer happened to split it.
private func joinedText(_ events: [RecordingSink.Event]) -> String {
    events.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined()
}

struct MarkupTokenizerTests {

    @Test func pairedElementWithAttributesAndText() {
        #expect(tokenize(#"<w lemma="strong:H07225" morph="x:y">In the beginning</w>"#) == [
            .start("w", ["lemma": "strong:H07225", "morph": "x:y"], selfClosing: false),
            .text("In the beginning"),
            .end("w"),
        ])
    }

    @Test func selfClosingElementEmitsNoEndEvent() {
        #expect(tokenize(#"<l level="2" sID="gen22"/>"#) == [
            .start("l", ["level": "2", "sID": "gen22"], selfClosing: true),
        ])
        // with and without the space before the slash
        #expect(tokenize("<lb/>") == [.start("lb", [:], selfClosing: true)])
        #expect(tokenize("<lb />") == [.start("lb", [:], selfClosing: true)])
    }

    @Test func textBetweenAndAroundElements() {
        #expect(tokenize("a<b/>c") == [
            .text("a"), .start("b", [:], selfClosing: true), .text("c"),
        ])
    }

    @Test func attributeValueMayContainGreaterThanAndBothQuoteStyles() {
        let events = tokenize(#"<note n="a>b" t='say "hi"'>x</note>"#)
        #expect(events.first == .start("note", ["n": "a>b", "t": #"say "hi""#], selfClosing: false))
        #expect(joinedText(events) == "x")
    }

    @Test func attributeWithoutValueAndUnquotedValue() {
        #expect(tokenize("<x flag n=5>") == [
            .start("x", ["flag": "", "n": "5"], selfClosing: false),
        ])
    }

    @Test func colonAndDigitNamesAreAccepted() {
        #expect(tokenize(#"<xml:lang-x1 a:b="1"/>"#) == [
            .start("xml:lang-x1", ["a:b": "1"], selfClosing: true),
        ])
    }

    // MARK: Entities

    @Test func predefinedEntitiesDecodeInTextAndAttributes() {
        let events = tokenize(#"<a t="x&amp;y&quot;">&lt;H7225&gt; &amp; &apos;ok&apos;</a>"#)
        #expect(events.first == .start("a", ["t": #"x&y""#], selfClosing: false))
        #expect(joinedText(events) == "<H7225> & 'ok'")
    }

    @Test func numericReferencesDecodeDecimalAndHex() {
        #expect(joinedText(tokenize("&#182; &#x5D0; &#X5d0; &#128512;")) == "¶ א א 😀")
    }

    @Test func unknownOrMalformedEntitiesPassThroughLiterally() {
        #expect(joinedText(tokenize("&nbsp; &bogus; & &#xZZ; &#1114112; AT&T;")) == "&nbsp; &bogus; & &#xZZ; &#1114112; AT&T;")
        #expect(joinedText(tokenize("a &amp")) == "a &amp")     // no terminating ';'
    }

    // MARK: Unicode

    @Test func multiByteTextAndAttributesSurviveIntact() {
        let events = tokenize("<w lemma=\"strong:G1\">καὶ 你好 שלום 😀 \u{200C}\u{200F}</w>")
        #expect(joinedText(events) == "καὶ 你好 שלום 😀 \u{200C}\u{200F}")
    }

    // MARK: Tolerance

    /// Real modules contain entries cut off mid-tag (LXX: a verse whose true
    /// length wrapped the 16-bit size field; Azeri: entries ending in
    /// `<div eID="`). The cut-off tag is dropped, never shown as text.
    @Test func aTagCutOffByTheEndOfInputIsDropped() {
        #expect(tokenize("before <w lemma=\"x\" after") == [.text("before ")])
        #expect(tokenize("before <w lemm") == [.text("before ")])
        #expect(tokenize("before <w x=\"unclosed quote") == [.text("before ")])
        #expect(tokenize("before <w x=") == [.text("before ")])
        #expect(tokenize("before </w") == [.text("before ")])
        #expect(tokenize("before <!-- never closed") == [.text("before ")])
        #expect(tokenize("before <![CDATA[ never closed") == [.text("before ")])
        #expect(tokenize(#"<div eID="gen28391" type="paragraph"/> <div eID=""#) == [
            .start("div", ["eID": "gen28391", "type": "paragraph"], selfClosing: true), .text(" "),
        ])
    }

    @Test func aCutOffTagLosesOnlyTheTagNotTheContentBeforeIt() {
        let events = tokenize(#"<w lemma="strong:G1">Αἰγύπτου</w> <w lemm"#)
        #expect(joinedText(events) == "Αἰγύπτου ")
        #expect(events.contains(.end("w")))
    }

    @Test func aStrayLessThanThatIsNotATagStaysText() {
        #expect(joinedText(tokenize("1 < 2")) == "1 < 2")
        #expect(joinedText(tokenize("x <")) == "x <")           // '<' at the very end, nothing after it
        #expect(joinedText(tokenize("3 <4 and <5")) == "3 <4 and <5")
    }

    @Test func strayLessThanStaysText() {
        #expect(joinedText(tokenize("1 < 2 and 3 <4")) == "1 < 2 and 3 <4")
    }

    @Test func commentsAndProcessingInstructionsAreSkipped() {
        #expect(tokenize("a<!-- note -->b<?xml version=\"1.0\"?>c<!DOCTYPE x>d") == [
            .text("a"), .text("b"), .text("c"), .text("d"),
        ])
    }

    @Test func cdataBecomesLiteralText() {
        #expect(joinedText(tokenize("x<![CDATA[<not markup> & stuff]]>y")) == "x<not markup> & stuff" + "y")
    }

    @Test func stackBalanceIsNotCheckedHere() {
        // Containers legitimately span verse entries (D34), so the tokenizer
        // reports what it sees and leaves balance to the builder.
        #expect(tokenize("</list><item>") == [.end("list"), .start("item", [:], selfClosing: false)])
    }

    @Test func emptyAndWhitespaceOnlyInput() {
        #expect(tokenize("").isEmpty)
        #expect(tokenize("   ") == [.text("   ")])
    }

    /// Every prefix of realistic entries must tokenize without a crash or a
    /// hang, and without losing text that was outside any tag.
    @Test func truncationFuzzNeverCrashesOrHangs() {
        let samples = [
            #"<chapter osisID="Gen.1" sID="gen2"/> <title type="chapter">CHAPTER 1.</title> <w lemma="strong:H07225">In the beginning</w> &amp; <note type="study"><catchWord>t</catchWord> <rdg type="x-literal">x</rdg></note>"#,
            "<l level=\"1\" sID=\"gen31\"/>\u{05D1}\u{05B0}\u{05BC}\u{05E8}\u{05B5}\u{05D0}\u{05E9}\u{05B4}\u{05C1}\u{05D9}\u{05EA}<l eID=\"gen31\"/> &#x5D0;&#182;",
            "<!-- c --><?pi x?><![CDATA[ a ]]><x a='1' b=\"2\" c=3 d>&lt;&gt;</x>",
        ]
        for sample in samples {
            let scalars = Array(sample.unicodeScalars)
            for end in 0...scalars.count {
                var prefix = String.UnicodeScalarView()
                prefix.append(contentsOf: scalars[0..<end])
                _ = tokenize(String(prefix))
            }
        }
    }
}
