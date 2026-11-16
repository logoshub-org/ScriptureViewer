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
        let shown = ChapterEntries.shown(try loadEntries())
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

    func testDefault() throws { try check("default") }
    func testMarkers() throws { try check("markers") }
    func testVersePerLine() throws { try check("lines") }

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
