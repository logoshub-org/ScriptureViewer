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
import ScriptureTextGBF
import ScriptureTextThML
import ScriptureTextTEI
import ScriptureTextPlain
import ScriptureTextSource

/// The parsers other than OSIS, and the module source's choice among them, run as Swift and as Kotlin over the same input: four GBF
/// chapters from the committed test modules (YLT Genesis 1, Weymouth Matthew 5, and the commentaries DTN Genesis 1 and TFG Matthew 1,
/// with reference marks and notes), each read as every source type, and sample entries for ThML, TEI and plain text. The expected
/// file was written by the Swift run; the Kotlin run must give the same.
final class ParserParityTests: XCTestCase {

    func testEveryParserMatchesSwift() throws {
        let actual = try digests()
        let url = try XCTUnwrap(Bundle.module.url(forResource: "expected_parsers", withExtension: "txt"))
        let wanted = try String(contentsOf: url, encoding: .utf8)
        if actual != wanted {
            let a = actual.split(separator: "\n", omittingEmptySubsequences: false)
            let w = wanted.split(separator: "\n", omittingEmptySubsequences: false)
            var k = 0
            while k < a.count && k < w.count && a[k] == w[k] { k += 1 }
            var label = ""
            var j = 0
            while j <= k && j < a.count {
                if a[j].hasPrefix("# ") { label = String(a[j]) }
                j += 1
            }
            print("DIFF parsers at line " + String(k) + " in " + label)
            print("DIFF actual: " + (k < a.count ? String(a[k]) : "<end>"))
            print("DIFF wanted: " + (k < w.count ? String(w[k]) : "<end>"))
        }
        XCTAssertTrue(actual == wanted, "the parsers' output differs from Swift's")
    }

    #if !SKIP
    /// macOS only: writes the expected file next to the test, when asked (GENERATE_EXPECTED=1).
    func testGenerateParserExpectedWhenAsked() throws {
        guard ProcessInfo.processInfo.environment["GENERATE_EXPECTED"] == "1" else { return }
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources")
        try digests().write(to: folder.appendingPathComponent("expected_parsers.txt"), atomically: true, encoding: .utf8)
    }
    #endif

    // MARK: Input

    private func strings(_ name: String) throws -> [String] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try JSONDecoder().decode([String].self, from: try Data(contentsOf: url))
    }

    private func digests() throws -> String {
        var out = ""
        let chapters: [Pick] = [Pick(file: "ylt_gen1", book: "Gen", chapter: 1, commentary: false),
                                Pick(file: "weymouth_matt5", book: "Matt", chapter: 5, commentary: false),
                                Pick(file: "dtn_gen1", book: "Gen", chapter: 1, commentary: true),
                                Pick(file: "tfg_matt1", book: "Matt", chapter: 1, commentary: true)]
        var full = ScriptureDisplayOptions()
        full.strongs = true
        full.morph = true
        full.footnotes = true
        full.crossReferences = true
        full.headings = true
        full.redLetter = true
        let displays: [ScriptureDisplayOptions] = [ScriptureDisplayOptions(), full]
        let types: [ScriptureSourceType] = [ScriptureSourceType.gbf, ScriptureSourceType.thml, ScriptureSourceType.plain,
                                            ScriptureSourceType.tei, ScriptureSourceType.osis]
        for pick in chapters {
            let texts = try strings(pick.file)
            var entries: [ChapterEntries.Entry] = []
            var index = 0
            for text in texts {
                entries.append(ChapterEntries.Entry(verse: index, text: text))
                index += 1
            }
            for type in types {
                let reader = SampleReader(facts: ScriptureModuleFacts(name: "Sample", sourceType: type),
                                          chapter: RawChapter(book: pick.book, chapter: pick.chapter, entries: entries))
                let source = ScriptureModuleSource(reader: reader)
                var d = 0
                for display in displays {
                    let label = pick.file + " " + type.rawValue + " display" + String(d)
                    if let model = source.chapter(module: "Sample", reference: pick.book + " " + String(pick.chapter), display: display,
                                                  commentary: pick.commentary) {
                        out += digest(label, model)
                    } else {
                        out += "# " + label + " nil\n"
                    }
                    if let verse = source.verse(module: "Sample", chapterReference: "", verse: 1, display: display) {
                        out += digest(label + " verse 1", verse)
                    }
                    d += 1
                }
            }
            // The GBF parser with its other line rule.
            out += digest(pick.file + " gbf preserve", GBFParser(lineBreaks: GBFParser.LineBreaks.preserve).parse(ChapterEntries.shown(entries)))
        }
        var k = 0
        for sample in try strings("tei_samples") {
            out += digest("tei " + String(k), TEIParser(options: TEIParser.Options(module: "StrongsGreek")).parse(sample))
            k += 1
        }
        k = 0
        for sample in try strings("thml_samples") {
            var options = ThMLParser.Options(module: "TSK")
            options.strongs = true
            options.morphology = true
            out += digest("thml " + String(k), ThMLParser(options: options).parse(sample))
            out += digest("thml commentary " + String(k),
                          ThMLParser(options: options, profile: ScriptureContentProfile.commentary)
                              .parse([ChapterEntries.Entry(verse: 1, text: sample), ChapterEntries.Entry(verse: 2, text: sample)]))
            k += 1
        }
        k = 0
        for sample in try strings("plain_samples") {
            out += digest("plain " + String(k), PlainTextParser().parse(sample))
            var preserve = PlainTextParser.Options()
            preserve.lineBreaks = PlainTextParser.Options.LineBreaks.preserve
            out += digest("plain preserve " + String(k), PlainTextParser(options: preserve).parse(sample))
            k += 1
        }
        return out
    }

    // MARK: Digest

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

    /// Everything about a model, as lines, under a label.
    private func digest(_ label: String, _ model: ScriptureText) -> String {
        var out = "# " + label + "\n"
        out += "utf16=" + String(CodePoints.utf16Length(model.text)) + " verses=" + String(model.verses.count)
        out += " spans=" + String(model.spans.count) + " words=" + String(model.words.count) + " notes=" + String(model.notes.count) + "\n"
        for v in model.verses {
            out += "V " + String(v.verse) + " " + String(v.start) + " " + String(v.length) + " " + v.displayNumber + "\n"
        }
        for s in model.spans { out += "S " + describe(s.attribute) + " " + String(s.start) + " " + String(s.length) + "\n" }
        for w in model.words { out += "W " + String(w.verse) + " " + String(w.index) + " " + String(w.start) + " " + String(w.length) + "\n" }
        for n in model.notes {
            out += "N " + n.id + " " + n.kind.rawValue + " [" + n.references.joined(separator: "|") + "] " + n.text + "\n"
        }
        out += "T " + model.text + "\n"
        return out
    }
}

/// A chapter to read, by its file of raw entries.
struct Pick {
    var file: String
    var book: String
    var chapter: Int
    var commentary: Bool
}

/// One module with one chapter: what the module source reads through.
struct SampleReader: RawChapterReading {
    var facts: ScriptureModuleFacts
    var chapter: RawChapter

    func facts(forModule name: String) -> ScriptureModuleFacts? { facts }
    func rawChapter(forModule name: String, reference: String) -> RawChapter? { chapter }
    func plainChapter(forModule name: String, reference: String) -> RawChapter? { chapter }
}
