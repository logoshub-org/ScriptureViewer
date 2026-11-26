// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest
import Foundation
import ScriptureText
import ScriptureTextOSIS

/// The KJV's Psalm 119, parsed from its raw OSIS by the portable core. The same test runs as Swift on macOS and, transpiled, as Kotlin;
/// the expected files were written by the Swift run.
final class ScriptureTextOSISTests: XCTestCase {

    private func loadEntries() throws -> [ChapterEntries.Entry] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "entries", withExtension: "json"))
        let strings = try JSONDecoder().decode([String].self, from: try Data(contentsOf: url))
        var result: [ChapterEntries.Entry] = []
        for (index, text) in strings.enumerated() { result.append(ChapterEntries.Entry(verse: index, text: text)) }
        return result
    }

    private func variants() -> [(String, ScriptureDisplayOptions)] {
        var plain = ScriptureDisplayOptions()
        plain.headings = true
        var markers = ScriptureDisplayOptions()
        markers.strongs = true
        markers.morph = true
        markers.headings = true
        var lines = ScriptureDisplayOptions()
        lines.versePerLine = true
        lines.crossReferences = true
        return [("default", plain), ("markers", markers), ("lines", lines)]
    }

    private func parse(_ display: ScriptureDisplayOptions) throws -> ScriptureText {
        try parse(display, entries: try loadEntries())
    }

    private func parse(_ display: ScriptureDisplayOptions, entries raw: [ChapterEntries.Entry]) throws -> ScriptureText {
        let facts = ScriptureModuleFacts(name: "KJV", sourceType: .osis, versification: "KJV")
        var options = OSISParser.Options()
        options.headings = display.headings
        options.redLetter = display.redLetter
        options.footnotes = display.footnotes
        options.crossReferences = display.crossReferences
        options.versePerLine = display.versePerLine
        options.strongsMarkers = display.strongs
        options.morphMarkers = display.morph
        options.quoteMarks = facts.osisQToTick
        let transforms = facts.textTransforms(greekAccents: display.greekAccents, hebrewPoints: display.hebrewPoints,
                                              hebrewCantillation: display.hebrewCantillation)
        options.greekAccents = transforms.greekAccents
        options.hebrewPoints = transforms.hebrewPoints
        options.hebrewCantillation = transforms.hebrewCantillation
        let shown = ChapterEntries.shown(raw)
        var entries: [OSISParser.VerseEntry] = []
        for entry in shown { entries.append(OSISParser.VerseEntry(verse: entry.verse, osis: entry.text)) }
        return OSISParser(options: options, profile: .chapter).parse(entries, identity: facts.identity(book: "Ps", chapter: 119))
    }

    private func describe(_ attribute: ScriptureText.Attribute) -> String {
        switch attribute {
        case .block(let role): return "block:" + role.rawValue
        case .verseNumber(let number): return "verseNumber:" + String(number)
        case .redLetter: return "redLetter"
        case .small: return "small"
        case .bold: return "bold"
        case .italic: return "italic"
        case .strongs(let token): return "strongs:" + token
        case .morph(let code): return "morph:" + code
        case .word(let lemma, let morph): return "word:" + (lemma ?? "-") + ":" + (morph ?? "-")
        case .footnote(let id): return "footnote:" + id
        case .link(let target): return "link:" + target
        case .divineName: return "divineName"
        }
    }

    /// Everything structural about a model, as lines, then the text itself.
    private func digest(_ model: ScriptureText) -> String {
        var out = "utf16=" + String(CodePoints.utf16Length(model.text)) + "\n"
        out += "verses=" + String(model.verses.count) + " spans=" + String(model.spans.count)
        out += " words=" + String(model.words.count) + " notes=" + String(model.notes.count) + "\n"
        for v in model.verses { out += "V " + String(v.verse) + " " + String(v.start) + " " + String(v.length) + "\n" }
        for s in model.spans { out += "S " + describe(s.attribute) + " " + String(s.start) + " " + String(s.length) + "\n" }
        for w in model.words { out += "W " + String(w.verse) + " " + String(w.index) + " " + String(w.start) + " " + String(w.length) + "\n" }
        out += "T " + model.text + "\n"
        return out
    }

    private func expected(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "expected_" + name, withExtension: "txt"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    #if !SKIP
    /// macOS only: writes the expected files next to the test, when asked.
    func testGenerateExpectedWhenAsked() throws {
        guard ProcessInfo.processInfo.environment["GENERATE_EXPECTED"] == "1" else { return }
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources")
        for (name, display) in variants() {
            try digest(try parse(display)).write(to: folder.appendingPathComponent("expected_" + name + ".txt"), atomically: true, encoding: .utf8)
        }
    }
    #endif

    /// Parse time grows in proportion to the text: Psalm 119 eight times over takes about eight times as long as once, not 64.
    /// This is what went wrong in Kotlin before the core followed the speed rules (each append copied all the text so far, so time
    /// grew with the square of the chapter), and a ratio holds on any machine where a fixed time limit would not.
    func testParseTimeGrowsInProportionToTheText() throws {
        let one = try loadEntries()
        var many: [ChapterEntries.Entry] = []
        var verse = 0
        for _ in 0..<ParseTiming.factor {
            for entry in one {
                many.append(ChapterEntries.Entry(verse: verse, text: entry.text))
                verse += 1
            }
        }
        var markers = ScriptureDisplayOptions()
        markers.strongs = true
        markers.morph = true
        let single = try ParseTiming.median { _ = try self.parse(markers, entries: one) }
        let longer = try ParseTiming.median { _ = try self.parse(markers, entries: many) }
        print("TIMING OSIS Psalm 119: " + ParseTiming.describe(single) + " once, " + ParseTiming.describe(longer) + " eight times")
        XCTAssertLessThan(longer / single, ParseTiming.limit, "eight times the text took " + String(longer / single) + " times as long")
    }

    func testDefault() throws { try check("default") }
    func testMarkers() throws { try check("markers") }
    func testVersePerLine() throws { try check("lines") }

    /// What a viewer asks of the model beyond parsing, which the digests do not show: a verse range holds its own verse and no other,
    /// a bookmark paints one verse, a verse is copied alone, and a search finds its word. (As Kotlin, `contains(verse:)` once held every
    /// verse up to its own, because the parameter hid the property: the Android viewer's tests found it.)
    func testAVerseIsFoundPaintedAndCopiedAlone() throws {
        var display = ScriptureDisplayOptions()
        display.headings = true
        let model = try parse(display)
        let range = try XCTUnwrap(model.verseRange(containing: 105))
        XCTAssertEqual(range.verse, 105)
        XCTAssertTrue(range.contains(verse: 105))
        XCTAssertFalse(range.contains(verse: 104))
        XCTAssertFalse(range.contains(verse: 106))

        let bookmark = Highlight(Highlight.Target.verse(105), style: HighlightStyle.bookmark(colour: "#3478F6"))
        let painted = model.resolve([bookmark])
        XCTAssertEqual(painted.count, 1)
        if painted.count == 1 {
            let words = try XCTUnwrap(model.substring(utf16Start: painted[0].start, length: painted[0].length))
            XCTAssertTrue(words.hasPrefix("Thy word is a lamp"), words)
        }

        let copied = try XCTUnwrap(model.copiedText(verse: 105))
        XCTAssertTrue(copied.text.hasPrefix("105 Thy word is a lamp"), copied.text)
        XCTAssertFalse(copied.text.contains("106"), copied.text)

        let terms: [String] = ["lamp"]
        XCTAssertEqual(model.searchHits(for: terms).count, 1)
        XCTAssertFalse(model.strongsHits(for: "H835").isEmpty)
    }

    /// The spans are in start order, and a tap's search finds what reading every span would (ScriptureTextModel.md): across Psalm 119
    /// with Strong's and morphology markers, at every seventh offset, the target is the one a model holding only the spans that cover
    /// the offset gives, and its verse and word are the ones that hold the offset.
    func testTheSpansAreInOrderAndATapFindsWhatAFullReadWould() throws {
        var display = ScriptureDisplayOptions()
        display.headings = true
        display.strongs = true
        display.morph = true
        let model = try parse(display)
        XCTAssertTrue(ScriptureText.isOrdered(model.spans))
        let spans = model.spans
        let length = CodePoints.utf16Length(model.text)
        var checked = 0
        var offset = 0
        while offset < length {
            var covering: [ScriptureText.Span] = []
            for span in spans where span.start <= offset && offset < span.start + span.length { covering.append(span) }
            let alone = ScriptureText(text: model.text, spans: covering, verses: model.verses, notes: model.notes, words: model.words,
                                      identity: model.identity)
            let found = model.tapTarget(atUTF16Offset: offset)
            XCTAssertEqual(found, alone.tapTarget(atUTF16Offset: offset), "offset \(offset)")
            if let found {
                var verse: Int? = nil
                for range in model.verses where range.start <= offset && offset < range.start + range.length { verse = range.verse; break }
                var word: Int? = nil
                for anchor in model.words where anchor.start <= offset && offset < anchor.start + anchor.length { word = anchor.index; break }
                XCTAssertEqual(found.context.verse, verse, "offset \(offset)")
                XCTAssertEqual(found.context.wordIndex, word, "offset \(offset)")
                checked += 1
            }
            offset += 7
        }
        XCTAssertGreaterThan(checked, 1000)
    }

    /// A character outside the Basic Multilingual Plane is two UTF-16 units; copying keeps the pair together (Gothic, a CJK Extension B
    /// ideograph, a mathematical letter). Swift once decoded the units one at a time and made each half a replacement character.
    func testCharactersOutsideTheBasicPlaneCopyWhole() throws {
        let words = "𐌰𐌹𐍅 𠀀 𝔄"
        let text = "1" + words
        let length = CodePoints.utf16Length(text)
        let model = ScriptureText(text: text,
                                  spans: [ScriptureText.Span(start: 0, length: 1, attribute: ScriptureText.Attribute.verseNumber(1))],
                                  verses: [ScriptureText.VerseRange(verse: 1, start: 0, length: length)])
        let copied = try XCTUnwrap(model.copiedText(verse: 1))
        XCTAssertEqual(copied.text, "1 " + words)
        let start = CodePoints.utf16Length("1𐌰")
        XCTAssertEqual(model.copiedText(utf16Start: start, length: length - start).text, "𐌹𐍅 𠀀 𝔄")
    }

    private func check(_ name: String) throws {
        var display = ScriptureDisplayOptions()
        for (variant, options) in variants() where variant == name { display = options }
        let model = try parse(display)
        XCTAssertEqual(model.verses.count, 176)
        let actual = digest(model)
        let wanted = try expected(name)
        if actual != wanted {
            let a = actual.split(separator: "\n", omittingEmptySubsequences: false)
            let w = wanted.split(separator: "\n", omittingEmptySubsequences: false)
            var k = 0
            while k < a.count && k < w.count && a[k] == w[k] { k += 1 }
            print("DIFF " + name + " at line " + String(k) + " of " + String(a.count) + "/" + String(w.count))
            print("DIFF actual: " + (k < a.count ? String(a[k]) : "<end>"))
            print("DIFF wanted: " + (k < w.count ? String(w[k]) : "<end>"))
            print("DIFF counts: " + (a.count > 1 ? String(a[1]) : "") + " | wanted " + (w.count > 1 ? String(w[1]) : ""))
            print("DIFF head: " + String(model.text.prefix(240)))
        }
        XCTAssertEqual(actual.count, wanted.count)
        XCTAssertTrue(actual == wanted, name + ": the model differs")
    }
}
