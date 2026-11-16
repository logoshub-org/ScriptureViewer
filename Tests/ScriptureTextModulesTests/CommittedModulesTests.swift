// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import ScriptureText
import ScriptureTextGBF
import ScriptureTextOSIS
import ScriptureTextSource
@testable import ScriptureTextTestSupport

// The parsers on real module data that is in the repository (plan D74): the KJV with Strong's numbers and
// morphology (OSIS), YLT and Weymouth (GBF Bibles), DTN and TFG (GBF commentaries). All are public domain.
// These run everywhere, with no SWORD and no local corpus; the larger local corpus (SCRIPTURE_CORPUS_DIR and
// the others) still exists for the modules that cannot be committed.

/// Words of a model with its verse numbers taken out, split on white space.
private func words(of model: ScriptureText) -> [String] {
    var text = Array(model.text.utf16)
    for span in model.spans.sorted(by: { $0.start > $1.start }) {
        if case .verseNumber = span.attribute, span.start + span.length <= text.count {
            text.removeSubrange(span.start..<(span.start + span.length))
        }
    }
    return String(decoding: text, as: UTF16.self).split(whereSeparator: { $0.isWhitespace }).map(String.init)
}

private func spans(_ model: ScriptureText, _ pick: (ScriptureText.Attribute) -> Bool) -> [String] {
    model.spans.filter { pick($0.attribute) }.compactMap { model.substring(utf16Start: $0.start, length: $0.length) }
}

// MARK: - The reader

struct ModuleFilesTests {

    @Test func everyModuleHasTheCountsItsVersificationSays() throws {
        let expected: [String: (chapters: Int, verses: Int)] = [
            "KJV": (1189, 31102), "YLT": (1189, 31102), "Weymouth": (260, 7957), "TFG": (260, 4227),
        ]
        for (name, counts) in expected {
            let chapters = try TestModules.files(name).chapters()
            #expect(chapters.count == counts.chapters, "\(name)")
            #expect(chapters.reduce(0) { $0 + $1.entries.dropFirst().filter { !$0.text.isEmpty }.count } == counts.verses, "\(name)")
        }
        #expect(try TestModules.files("DTN").chapters().count == 1189)
    }

    @Test func theConfIsReadForEachModule() throws {
        #expect(try TestModules.files("KJV").sourceType == .osis)
        for name in ["YLT", "Weymouth", "DTN", "TFG"] { #expect(try TestModules.files(name).sourceType == .gbf, "\(name)") }
        #expect(try TestModules.files("DTN").driver == "RawCom")
        #expect(try TestModules.files("YLT").facts.versification == "KJV")
    }

    @Test func knownVersesComeBackAsWritten() throws {
        let ylt = try #require(try TestModules.files("YLT").chapter(book: "Gen", 1))
        #expect(ylt.entries[1].text.hasPrefix("In the beginning of God's preparing the heavens and the earth"))
        let kjv = try #require(try TestModules.files("KJV").chapter(book: "Genesis", 1))
        #expect(kjv.entries[0].text.contains("<chapter "), "entry 0 is the chapter heading")
        #expect(kjv.entries[1].text.contains(#"<w lemma="strong:H07225">In the beginning</w>"#))
        #expect(kjv.entries.count == 32)
        let john = try #require(try TestModules.files("Weymouth").chapter(book: "John", 3))
        #expect(john.entries.count == 37)
    }
}

// MARK: - OSIS: the KJV

struct CommittedOSISTests {

    /// The count `export_corpus.py` makes independently: non-empty `<w>` elements outside variant readings and notes.
    private func expectedWords(_ raw: String) throws -> Int {
        var text = raw
        for pattern in [#"<seg[^>]*subType="x-2"[^>]*>.*?</seg>"#, #"<note\b[^>]*>.*?</note>"#] {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        let regex = try NSRegularExpression(pattern: #"<w\b[^>]*>(.*?)</w>"#, options: [.dotMatchesLineSeparators])
        var count = 0
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let inner = String(text[Range(match.range(at: 1), in: text)!])
            if !inner.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        }
        return count
    }

    @Test func everyChapterOfTheKJVParsesConsistentlyWithAndWithoutMarkers() throws {
        let chapters = try TestModules.files("KJV").chapters()
        var rich = OSISParser.Options()
        rich.strongsMarkers = true
        rich.morphMarkers = true
        for (label, options) in [("default", OSISParser.Options()), ("markers", rich)] {
            let parser = OSISParser(options: options)
            var problems: [String] = []
            for chapter in chapters {
                let model = parser.parse(chapter.entries.map { .init(verse: $0.verse, osis: $0.text) })
                let name = "\(chapter.book.osis) \(chapter.number)"
                if !model.isStructurallyConsistent { problems.append("\(name): inconsistent spans") }
                let wordSpans = model.spans.filter { if case .word = $0.attribute { true } else { false } }.count
                let expected = try expectedWords(chapter.entries.map(\.text).joined())
                if wordSpans != expected { problems.append("\(name): \(wordSpans) words, expected \(expected)") }
                if model.verses.map(\.verse) != Array(1...(chapter.entries.count - 1)) { problems.append("\(name): verse ranges") }
                for range in model.verses where range.length > 0 {
                    if model.substring(utf16Start: range.start, length: range.length)?.hasPrefix(String(range.verse)) != true {
                        problems.append("\(name):\(range.verse): range does not start with its number")
                    }
                }
                if model.text.hasPrefix(" ") || model.text.hasSuffix(" ") || model.text.hasSuffix("\n") { problems.append("\(name): edge white space") }
            }
            #expect(problems.isEmpty, "KJV [\(label)]: \(problems.prefix(5))")
        }
    }

    @Test func strongsAndMorphologyMarkersFollowTheirWords() throws {
        let genesis = try #require(try TestModules.files("KJV").chapter(book: "Gen", 1))
        var options = OSISParser.Options()
        options.strongsMarkers = true
        let model = OSISParser(options: options).parse(genesis.entries.map { .init(verse: $0.verse, osis: $0.text) })
        #expect(model.text.contains("In the beginning<"), "\(model.text.prefix(120))")
        let strongs = spans(model) { if case .strongs = $0 { true } else { false } }
        #expect(strongs.count > 50)
        #expect(strongs.first == "<07225>")
    }
}

// MARK: - GBF: Bibles and commentaries

struct CommittedGBFTests {

    private func expected(_ raw: String) -> [String] {
        // Reference marks (`#Mt 1:1|`) lose their `#` and `|`; the tags go; the words stay.
        raw.replacingOccurrences(of: #"#\s*([^#|<>\n]*\d[^#|<>\n]*?)\s*\|"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "<[^<>]*>", with: "", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Every chapter of a module: the model has the words of its entries, in order, and a range for each shown verse.
    private func check(_ name: String, profile: ScriptureContentProfile, atLeast minimum: Int) throws {
        let chapters = try TestModules.files(name).chapters()
        var options = OSISParser.Options()
        options.footnotes = false
        var problems: [String] = []
        var checked = 0
        for chapter in chapters {
            let shown = ChapterEntries.shown(chapter.entries)
            guard !shown.isEmpty else { continue }
            let model = GBFParser(options: options, profile: profile).parse(shown)
            let label = "\(chapter.book.osis) \(chapter.number)"
            checked += 1
            if !model.isStructurallyConsistent { problems.append("\(label): inconsistent spans") }
            if model.verses.count != shown.filter({ $0.verse > 0 }).count { problems.append("\(label): \(model.verses.count) verse ranges") }
            let want = shown.flatMap { expected($0.text) }
            let got = words(of: model)
            if got != want { problems.append("\(label): words differ at \(Array(zip(got, want)).firstIndex { $0 != $1 } ?? min(got.count, want.count))") }
        }
        #expect(checked >= minimum, "\(name) checked \(checked) chapters")
        #expect(problems.isEmpty, "\(name): \(problems.prefix(5))")
    }

    @Test func yltKeepsEveryWordOfEveryChapter() throws { try check("YLT", profile: .chapter, atLeast: 1180) }
    @Test func weymouthKeepsEveryWordOfEveryChapter() throws { try check("Weymouth", profile: .chapter, atLeast: 260) }
    @Test func dtnKeepsEveryWordOfEveryChapter() throws { try check("DTN", profile: .commentary, atLeast: 300) }
    @Test func tfgKeepsEveryWordOfEveryChapter() throws { try check("TFG", profile: .commentary, atLeast: 119) }

    private func parse(_ name: String, _ book: String, _ number: Int, profile: ScriptureContentProfile = .chapter) throws -> ScriptureText {
        let chapter = try #require(try TestModules.files(name).chapter(book: book, number))
        return GBFParser(profile: profile).parse(ChapterEntries.shown(chapter.entries))
    }

    @Test func yltMarksTheTranslatorsAddedWordsInItalics() throws {
        let model = try parse("YLT", "Gen", 1)
        let italic = spans(model) { $0 == .italic }
        #expect(italic.count > 5)
        #expect(italic.contains("is"), "Genesis 1:2 has darkness <FI>is<Fi>")
        #expect(model.text.hasPrefix("1In the beginning of God's preparing the heavens and the earth"))
    }

    @Test func weymouthMarksOldTestamentQuotes() throws {
        let model = try parse("Weymouth", "Matt", 1)
        #expect(spans(model) { $0 == .italic }.contains { $0.contains("Immanuel") })
    }

    @Test func dtnIsOneVersePerLineWithItsItalics() throws {
        let model = try parse("DTN", "Gen", 1, profile: .commentary)
        #expect(model.verses.count > 3)
        #expect(spans(model) { $0 == .italic }.contains("Elohim"))
        #expect(model.text.contains("Deity in the absolute sense"), "hard-wrapped lines are joined")
        #expect(!model.text.contains("sense. Elohim will,\n"), "no stray line ends inside a paragraph")
    }

    @Test func tfgKeepsItsBoldLeadsAndScriptureMarks() throws {
        let model = try parse("TFG", "Matt", 1, profile: .commentary)
        #expect(spans(model) { $0 == .bold }.contains("The book of the generation."))
        #expect(model.text.contains("Mt 1:1-17"), "a reference mark shows its reference")
        #expect(!model.text.contains("#Mt"), "without the # and |")
        let links = model.spans.compactMap { span -> String? in
            if case .link(let target) = span.attribute { return target }
            return nil
        }
        #expect(links.contains("passage:Mt 1:1-17"), "and is a link: \(links.prefix(3))")
    }
}

// MARK: - The module source on real data, with no SWORD

struct CommittedModuleSourceTests {

    @Test func aHostWithNoSWORDReadsEveryFormat() throws {
        let source = ScriptureModuleSource(reader: try TestModulesReader())
        let ylt = try #require(source.chapter(module: "YLT", reference: "Genesis 1", display: .init()))
        #expect(ylt.verses.map(\.verse) == Array(1...31))
        #expect(ylt.identity == PassageIdentity(work: "YLT", versification: "KJV", book: "Gen", chapter: 1))
        var display = ScriptureDisplayOptions()
        display.strongs = true
        let kjv = try #require(source.chapter(module: "KJV", reference: "Genesis 1", display: display))
        #expect(kjv.text.contains("<"), "Strong's markers are on")
        #expect(kjv.verses.count == 31)
        let dtn = try #require(source.chapter(module: "DTN", reference: "Genesis 1", display: .init(), commentary: true))
        #expect(dtn.identity?.work == "DTN")
        #expect(source.chapter(module: "Nope", reference: "Genesis 1", display: .init()) == nil)
        let verse = try #require(source.verse(module: "Weymouth", chapterReference: "John 3", verse: 16, display: .init()))
        #expect(verse.text.contains("God"), "\(verse.text)")
    }
}
