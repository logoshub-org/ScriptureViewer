// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import ScriptureText

/// The model keeps its spans in start order (the longer first where two start together, else as given), and its verse ranges and
/// word anchors in start order, so that a lookup by position searches instead of scanning (ScriptureTextModel.md).
@Suite("Span order")
struct SpanOrderTests {

    private func span(_ start: Int, _ length: Int, _ attribute: ScriptureText.Attribute = .bold) -> ScriptureText.Span {
        ScriptureText.Span(start: start, length: length, attribute: attribute)
    }

    @Test func spansGivenOutOfOrderAreKeptInOrder() {
        // what the ThML and TEI parsers give: a span is recorded when it closes, so an outer one comes after those inside it
        let model = ScriptureText(text: String(repeating: "x", count: 40),
                                  spans: [span(5, 3, .italic), span(20, 2), span(0, 30, .redLetter), span(5, 10, .small)])
        #expect(model.spans == [span(0, 30, .redLetter), span(5, 10, .small), span(5, 3, .italic), span(20, 2)])
        #expect(ScriptureText.isOrdered(model.spans))
    }

    @Test func spansThatStartAndEndTogetherKeepTheOrderGiven() {
        let model = ScriptureText(text: String(repeating: "x", count: 10),
                                  spans: [span(4, 2, .bold), span(1, 1), span(4, 2, .italic), span(4, 2, .small)])
        #expect(model.spans == [span(1, 1), span(4, 2, .bold), span(4, 2, .italic), span(4, 2, .small)])
    }

    @Test func assigningOrAppendingKeepsTheOrder() {
        var model = ScriptureText(text: String(repeating: "x", count: 40), spans: [span(10, 2)])
        model.spans.append(span(3, 4))
        #expect(model.spans == [span(3, 4), span(10, 2)])
        model.spans = [span(30, 1), span(0, 2), span(15, 5)]
        #expect(model.spans == [span(0, 2), span(15, 5), span(30, 1)])
        // a tap finds a span that was appended out of order
        model.spans.append(span(7, 2, .link(target: "osis:Gen.1.1")))
        #expect(model.tapTarget(atUTF16Offset: 8)?.kind == .scripture)
    }

    @Test func versesAndWordsGivenOutOfOrderAreKeptInOrder() {
        let model = ScriptureText(text: String(repeating: "x", count: 30),
                                  verses: [.init(verse: 2, start: 10, length: 10), .init(verse: 1, start: 0, length: 10)],
                                  words: [.init(verse: 1, index: 1, start: 5, length: 3), .init(verse: 1, index: 0, start: 1, length: 3)])
        #expect(model.verses.map(\.verse) == [1, 2])
        #expect(model.words.map(\.index) == [0, 1])
    }

    @Test func aRoundTripThroughJSONKeepsTheSpansAndTheirLookups() throws {
        let model = ScriptureText(text: "1In the beginning", spans: [span(3, 3, .word(lemma: "strong:H7225", morph: nil)), span(0, 1, .verseNumber(1))],
                                  verses: [.init(verse: 1, start: 0, length: 17)], words: [.init(verse: 1, index: 0, start: 3, length: 3)])
        let copy = try JSONDecoder().decode(ScriptureText.self, from: try JSONEncoder().encode(model))
        #expect(copy == model)
        #expect(copy.tapTarget(atUTF16Offset: 4) == model.tapTarget(atUTF16Offset: 4))
        #expect(copy.tapTarget(atUTF16Offset: 4)?.kind == .word)
    }

    /// Where several spans cover the offset the most specific wins (a marker over a link, a link over a verse number, a verse number
    /// over a word), then the shortest, then the first in order: as when every span was read.
    @Test func overlappingSpansAreFoundFromAnywhereInsideThem() throws {
        let text = String(repeating: "x", count: 60)
        let spans = [
            span(0, 60, .redLetter),                                  // long, not tappable: does not hold up the search
            span(2, 30, .link(target: "osis:Gen.1.1")),               // a long link over words
            span(4, 3, .word(lemma: "strong:H1", morph: nil)),
            span(8, 3, .word(lemma: "strong:H2", morph: nil)),
            span(9, 1, .strongs("strong:H2")),                        // a marker inside a word inside the link
            span(40, 2, .verseNumber(2)),
            span(40, 2, .verseNumber(3)),                             // a tie: the first in order wins
            span(50, 4, .word(lemma: "strong:H3", morph: nil)),
        ]
        let model = ScriptureText(text: text, spans: spans, verses: [.init(verse: 1, start: 0, length: 40), .init(verse: 2, start: 40, length: 20)])
        #expect(model.tapTarget(atUTF16Offset: 1) == nil)
        #expect(model.tapTarget(atUTF16Offset: 5)?.kind == .scripture)      // a link over a word
        #expect(model.tapTarget(atUTF16Offset: 9)?.kind == .strongs)        // a marker over a word and a link
        #expect(model.tapTarget(atUTF16Offset: 31)?.kind == .scripture)     // the link's last unit
        #expect(model.tapTarget(atUTF16Offset: 32) == nil)                  // just past it
        #expect(model.tapTarget(atUTF16Offset: 41)?.key == "2")
        #expect(model.tapTarget(atUTF16Offset: 52)?.key == "strong:H3")
        #expect(model.tapTarget(atUTF16Offset: 52)?.context.verse == 2)
        // every offset agrees with a model holding only the spans that cover it
        for offset in 0..<60 {
            let covering = spans.filter { $0.start <= offset && offset < $0.start + $0.length }
            let alone = ScriptureText(text: text, spans: covering, verses: model.verses)
            #expect(model.tapTarget(atUTF16Offset: offset) == alone.tapTarget(atUTF16Offset: offset), "offset \(offset)")
        }
    }

    // MARK: Copying and highlights search the spans too

    /// Two verses with a heading, Strong's and morphology markers, a footnote and red letter: what copying and highlights meet.
    private func versesWithMarkers() -> ScriptureText {
        let text = "Psalm\n1Blessed<H835> are<V-PAI> the undefiled.a 2Blessed are they."
        func at(_ piece: String, after: Int = 0) -> Int {
            let units = Array(text.utf16), needle = Array(piece.utf16)
            var i = after
            while i + needle.count <= units.count { if Array(units[i..<(i + needle.count)]) == needle { return i }; i += 1 }
            return -1
        }
        let one = at("1Blessed"), two = at("2Blessed")
        let spans: [ScriptureText.Span] = [
            span(0, 5, .block(.s1)),
            span(one, 1, .verseNumber(1)),
            span(one + 1, 7, .word(lemma: "strong:H835", morph: nil)),
            span(at("<H835>"), 6, .strongs("strong:H835")),
            span(at("<V-PAI>"), 7, .morph("robinson:V-PAI")),
            span(at("a 2"), 1, .footnote(id: "n1")),
            span(at("are<"), 3, .redLetter),
            span(two, 1, .verseNumber(2)),
        ]
        return ScriptureText(text: text, spans: spans,
                             verses: [.init(verse: 1, start: one, length: two - one - 1), .init(verse: 2, start: two, length: text.utf16.count - two)],
                             notes: [.init(id: "n1", text: "Or perfect")])
    }

    @Test func copyingAnyRangeLeavesOutTheSameMarkersAsReadingEverySpan() {
        let model = versesWithMarkers()
        let length = model.text.utf16.count
        for start in 0..<length {
            for end in (start + 1)...length {
                let copied = model.copiedText(utf16Start: start, length: end - start)
                #expect(copied.text == Self.copiedByReadingEverySpan(model, start, end), "range \(start)..<\(end)")
            }
        }
        #expect(model.copiedText(verse: 1)?.text == "1 Blessed are the undefiled.")
    }

    @Test func aVerseHighlightSkipsTheSameMarkerAsReadingEverySpan() {
        let model = versesWithMarkers()
        for verse in [1, 2, 3] {
            let style = HighlightStyle.bookmark(colour: "#3478F6")
            let painted = model.resolve([Highlight(Highlight.Target.verse(verse), style: style)])
            var expected: [Int] = []
            for range in model.verses where range.contains(verse: verse) {
                var start = range.start
                if let marker = model.spans.first(where: { span in
                    if case .verseNumber(let n) = span.attribute { return n == range.verse && span.start == range.start }
                    return false
                }) { start = marker.start + marker.length }
                expected.append(start)
            }
            #expect(painted.map(\.start) == expected, "verse \(verse)")
        }
    }

    /// What copying did before it searched: every span read, a marker's every unit dropped (the same rules as `copiedText`).
    private static func copiedByReadingEverySpan(_ model: ScriptureText, _ lower: Int, _ upper: Int) -> String {
        let units = Array(model.text.utf16)
        var dropped = [Bool](repeating: false, count: units.count)
        var numberStarts = Set<Int>(), numberEnds = Set<Int>()
        for span in model.spans {
            let end = min(span.start + span.length, units.count)
            guard span.start < end else { continue }
            switch span.attribute {
            case .footnote, .strongs, .morph: for i in span.start..<end { dropped[i] = true }
            case .verseNumber: numberStarts.insert(span.start); numberEnds.insert(end)
            default: break
            }
        }
        var out: [UInt16] = []
        func endsInSpace() -> Bool { out.last.map { $0 == 0x20 || $0 == 0x0A } ?? true }
        for i in lower..<upper {
            if numberEnds.contains(i), !dropped[i], units[i] != 0x20, units[i] != 0x0A, !endsInSpace() { out.append(0x20) }
            if dropped[i] || units[i] == 0x2060 { continue }
            if numberStarts.contains(i), !endsInSpace() { out.append(0x20) }
            out.append(units[i])
        }
        let joined = String(decoding: out, as: UTF16.self)
        let lines = joined.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        }
        var first = 0, last = lines.count
        while first < last, lines[first].isEmpty { first += 1 }
        while last > first, lines[last - 1].isEmpty { last -= 1 }
        return lines[first..<last].joined(separator: "\n")
    }
}
