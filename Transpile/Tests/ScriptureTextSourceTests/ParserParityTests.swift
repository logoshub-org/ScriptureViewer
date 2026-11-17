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

    /// The warm-up runs as Kotlin (it is for Android).
    func testWarmUpRuns() throws {
        ScriptureModuleSource.warmUp(rounds: 2)
    }

    /// GBF parse time grows in proportion to the text (see `ParseTiming`): a commentary chapter eight times over.
    func testGBFParseTimeGrowsInProportionToTheText() throws {
        let texts = try strings("tfg_matt1")
        var one: [ChapterEntries.Entry] = []
        var many: [ChapterEntries.Entry] = []
        var verse = 0
        for round in 0..<ParseTiming.factor {
            for text in texts {
                if round == 0 { one.append(ChapterEntries.Entry(verse: verse, text: text)) }
                many.append(ChapterEntries.Entry(verse: verse, text: text))
                verse += 1
            }
        }
        var options = OSISParser.Options()
        options.footnotes = true
        let parser = GBFParser(options: options, profile: ScriptureContentProfile.commentary)
        let single = try ParseTiming.median { _ = parser.parse(one) }
        let longer = try ParseTiming.median { _ = parser.parse(many) }
        print("TIMING GBF TFG Matthew 1: " + ParseTiming.describe(single) + " once, " + ParseTiming.describe(longer) + " eight times")
        XCTAssertLessThan(longer / single, ParseTiming.limit, "eight times the text took " + String(longer / single) + " times as long")
    }

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
                        out += ModelDigest.of(label, model)
                    } else {
                        out += "# " + label + " nil\n"
                    }
                    if let verse = source.verse(module: "Sample", chapterReference: "", verse: 1, display: display) {
                        out += ModelDigest.of(label + " verse 1", verse)
                    }
                    d += 1
                }
            }
            // The GBF parser with its other line rule.
            out += ModelDigest.of(pick.file + " gbf preserve", GBFParser(lineBreaks: GBFParser.LineBreaks.preserve).parse(ChapterEntries.shown(entries)))
        }
        var k = 0
        for sample in try strings("tei_samples") {
            out += ModelDigest.of("tei " + String(k), TEIParser(options: TEIParser.Options(module: "StrongsGreek")).parse(sample))
            k += 1
        }
        k = 0
        for sample in try strings("thml_samples") {
            var options = ThMLParser.Options(module: "TSK")
            options.strongs = true
            options.morphology = true
            out += ModelDigest.of("thml " + String(k), ThMLParser(options: options).parse(sample))
            out += ModelDigest.of("thml commentary " + String(k),
                          ThMLParser(options: options, profile: ScriptureContentProfile.commentary)
                              .parse([ChapterEntries.Entry(verse: 1, text: sample), ChapterEntries.Entry(verse: 2, text: sample)]))
            k += 1
        }
        k = 0
        for sample in try strings("plain_samples") {
            out += ModelDigest.of("plain " + String(k), PlainTextParser().parse(sample))
            var preserve = PlainTextParser.Options()
            preserve.lineBreaks = PlainTextParser.Options.LineBreaks.preserve
            out += ModelDigest.of("plain preserve " + String(k), PlainTextParser(options: preserve).parse(sample))
            k += 1
        }
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
