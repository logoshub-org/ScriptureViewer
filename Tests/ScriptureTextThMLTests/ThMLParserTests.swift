// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import ScriptureText
@testable import ScriptureTextThML

@Suite("ThMLParser")
struct ThMLParserTests {

    // Strong's Real Greek G2 and Hebrew H101, as the modules store them (public domain).
    private let aaron = "00002\r\n<a name=\"00002\">2</a> <b>\u{1F08}\u{03B1}\u{03C1}\u{03CE}\u{03BD}</b> [*)AARW/N] {Aar\u{1E53}n} \\<i>ah-ar-ohn'</i>\\<br/> of Hebrew origin (<a href=\"sword://StrongsRealHebrew/00175\">0175</a>); Aaron, the brother of Moses:--Aaron. "
    private let aggan = "<a name=\"00101\"><b>101</b></a><br /> \u{05D0}\u{05D2}\u{05BC}\u{05DF}<br /> ['agg\u{00E2}n] \\<i>ag-gawn'</i>\\<br /> Probably from <a href=\"sword://StrongsRealHebrew/05059\">5059</a>; a <i>bowl</i> (as <i>pounded</i> out hollow): - {basin} {cup} goblet. "

    private func parse(_ s: String, module: String? = "StrongsRealGreek", profile: ScriptureContentProfile = .dictionary) -> ScriptureText {
        ThMLParser(options: .init(module: module), profile: profile).parse(s)
    }

    private func texts(_ m: ScriptureText, _ pick: (ScriptureText.Attribute) -> Bool) -> [String] {
        m.spans.filter { pick($0.attribute) }.compactMap { m.substring(utf16Start: $0.start, length: $0.length) }
    }

    private func links(_ m: ScriptureText) -> [String] {
        m.spans.compactMap { if case .link(let t) = $0.attribute { t } else { nil } }
    }

    @Test func aGreekStrongsEntryReadsLikeTheWebView() {
        let m = parse(aaron)
        #expect(m.text.hasSuffix("[*)AARW/N] {Aar\u{1E53}n} \\ah-ar-ohn'\\\nof Hebrew origin (0175); Aaron, the brother of Moses:--Aaron."), "\(m.text)")
        #expect(texts(m) { $0 == .bold } == ["\u{1F08}\u{03B1}\u{03C1}\u{03CE}\u{03BD}"])
        #expect(texts(m) { $0 == .italic } == ["ah-ar-ohn'"])
        #expect(links(m) == ["sword://StrongsRealHebrew/00175"])
    }

    @Test func aHebrewEntryPutsTheWordOnItsOwnLine() {
        let m = parse(aggan, module: "StrongsRealHebrew")
        let lines = m.text.split(separator: "\n").map(String.init)
        #expect(lines.first == "101")
        #expect(lines[1] == "\u{05D0}\u{05D2}\u{05BC}\u{05DF}")
        #expect(lines[2].hasPrefix("['agg\u{00E2}n]"))
        #expect(texts(m) { $0 == .bold } == ["101"])
        #expect(links(m) == ["sword://StrongsRealHebrew/05059"])
    }

    @Test func anAnchorWithoutAnHrefShowsItsTextAndIsNotALink() {
        let m = parse(#"<a name="x">7</a> seven"#)
        #expect(m.text == "7 seven")
        #expect(links(m).isEmpty)
    }

    @Test func webLinksAreKeptAndPageAnchorsAreNot() {
        let m = parse(##"<a href="https://example.org/x">site</a> <a href="#top">top</a>"##)
        #expect(links(m) == ["https://example.org/x"])
    }

    @Test func scripRefIsAScriptureLinkByOsisRefOrPassage() {
        let m = parse(#"<scripRef passage="Rom 3:23" version="KJV">Rom. 3:23</scripRef> and <scripRef osisRef="Bible:John.3.16" passage="John 3:16">Jn 3:16</scripRef> <scripRef>none</scripRef>"#)
        #expect(links(m) == ["passage:Rom 3:23", "osis:Bible:John.3.16", "passage:none"])   // a bare one reads its text, as SWORD does
        #expect(m.text == "Rom. 3:23 and Jn 3:16 none")
    }

    @Test func aScripRefWithNoAttributesNamesItsPassageInItsText() {
        // Treasury of Scripture Knowledge writes its cross-references this way.
        let m = parse("<br />all ye his hosts.<br /><scripRef>33:6; Ge 32:2; Jos 5:14</scripRef><br />ministers.", module: "TSK", profile: .commentary)
        #expect(m.text == "all ye his hosts.\n33:6; Ge 32:2; Jos 5:14\nministers.")
        #expect(links(m) == ["passage:33:6; Ge 32:2; Jos 5:14"])
    }

    @Test func aNotesBareScripRefsAreItsReferences() {
        let m = parse("x<note type=\"x\"><scripRef>Ge 1:1</scripRef>; <scripRef>Ps 2:1</scripRef></note>")
        #expect(m.notes.first?.references == ["Ge 1:1", "Ps 2:1"])
    }

    @Test func breaksFollowTheElements() {
        #expect(parse("a<br/>b").text == "a\nb")
        #expect(parse("a<br/><br/>b").text == "a\n\nb")
        #expect(parse("<p>one</p><p>two</p>").text == "one\n\ntwo")
        #expect(parse("<div>one</div><div>two</div>").text == "one\ntwo")
        #expect(parse("text <hr/> more").text == "text\nmore")
    }

    @Test func hardWrappedLinesCollapseToSpaces() {
        #expect(parse("<p>\n  one\n  two   three \n</p>\n").text == "one two three")
    }

    @Test func headingsGetRoles() {
        let m = parse("<h1>Book</h1><h2>Part</h2><h3>Sub</h3><p>text</p>")
        let roles = m.spans.compactMap { s -> ParagraphRole? in if case .block(let r) = s.attribute { r } else { nil } }
        #expect(roles == [.ms, .s1, .s2])
        #expect(m.text == "Book\nPart\nSub\n\ntext")
    }

    @Test func listItemsAreParagraphsByDepth() {
        let m = parse("<ul><li>one</li><li>two<ol><li>deep</li></ol></li></ul>")
        let roles = m.spans.compactMap { s -> ParagraphRole? in if case .block(let r) = s.attribute { r } else { nil } }
        #expect(roles == [.li1, .li1, .li2])
        #expect(m.text == "one\ntwo\ndeep")
    }

    @Test func theHeadIsNotShown() {
        let m = parse("<ThML><ThML.head><title>Secret</title><br/></ThML.head><ThML.body><p>Shown</p></ThML.body></ThML>")
        #expect(m.text == "Shown")
    }

    @Test func notesKeepTheirBodyApartAndCrossReferencesAreMarked() {
        let m = parse(#"word<note>A <i>footnote</i> body.</note> more<note type="x"><scripRef passage="Gen 1:1">Gen 1:1</scripRef></note>"#)
        #expect(m.text == "wordn morex")
        #expect(m.notes.count == 2)
        #expect(m.notes[0].text == "A footnote body.")
        #expect(m.notes[0].kind == .footnote)
        #expect(m.notes[1].kind == .crossReference)
        #expect(m.notes[1].references == ["Gen 1:1"])
        #expect(texts(m) { if case .footnote = $0 { true } else { false } } == ["n", "x"])
    }

    @Test func syncMarkersShowOnlyWhenAsked() {
        let src = #"In <sync type="Strongs" value="H7225"/>the beginning<sync type="morph" value="N-NSF"/>"#
        #expect(parse(src).text == "In the beginning")
        var options = ThMLParser.Options(module: "X")
        options.strongs = true
        options.morphology = true
        let m = ThMLParser(options: options).parse(src)
        #expect(m.text == "In <7225>the beginning(N-NSF)")
        #expect(m.spans.contains { $0.attribute == .strongs("strong:H7225") })
        #expect(m.spans.contains { $0.attribute == .morph("robinson:N-NSF") })
    }

    @Test func namedEntitiesAreDecodedAndUnknownOnesPassThrough() {
        #expect(parse("a&nbsp;b &mdash; c &amp; d &zzz; e").text == "a\u{00A0}b \u{2014} c & d &zzz; e")
    }

    @Test func theThMLEntityForEtceteraIsWrittenOut() {
        #expect(parse("boats, nets, &c; and so on").text == "boats, nets, &c. and so on")
    }

    @Test func malformedMarkupNeverFailsTheParse() {
        #expect(parse("<b>bold <i>both</b> after</i> end").text == "bold both after end")
        #expect(parse("</p>stray").text == "stray")
        #expect(parse("<a href=\"sword://X/1\">cut off").text == "cut off")
        #expect(parse("").text == "")
    }

    @Test func tablesAreOneLinePerRow() {
        let m = parse("<table><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>")
        #expect(m.text == "a b\nc d")
    }

    // MARK: Chapters of verse-keyed entries

    @Test func aCommentaryChapterNumbersEachVerseOnItsOwnLine() {
        let entries: [ChapterEntries.Entry] = [
            .init(verse: 0, text: "<p>Introduction.</p>"),
            .init(verse: 1, text: "<p>First <i>note</i>.</p>"),
            .init(verse: 2, text: "Second.<br/>More."),
        ]
        let m = ThMLParser(options: .init(module: "Barnes"), profile: .commentary).parse(entries)
        #expect(m.text == "Introduction.\n1\nFirst note.\n2\nSecond.\nMore.")
        #expect(m.verses.map(\.verse) == [1, 2])
        let first = m.verses[0]
        #expect(m.substring(utf16Start: first.start, length: first.length) == "1\nFirst note.")
        #expect(texts(m) { if case .verseNumber = $0 { true } else { false } } == ["1", "2"])
    }

    @Test func aBibleChapterRunsTheNumberIntoTheText() {
        let entries: [ChapterEntries.Entry] = [.init(verse: 1, text: "In the beginning"), .init(verse: 2, text: "And the earth")]
        let m = ThMLParser(profile: .chapter).parse(entries, identity: PassageIdentity(work: "W", versification: "KJV", book: "Gen", chapter: 1))
        #expect(m.text == "1In the beginning\n2And the earth")
        #expect(m.identity?.book == "Gen")
    }

    // MARK: Real modules (local)

    private func dictionaryFiles() throws -> [URL]? {
        guard let path = ProcessInfo.processInfo.environment["SCRIPTURE_DICT_DIR"] else { return nil }
        return try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
    }

    /// Every entry of every ThML dictionary in the dumps repo parses with sane spans and no
    /// markup left in the text. `SCRIPTURE_DICT_DIR=~/source/pocketsword-dumps/corpus/dict`
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCRIPTURE_DICT_DIR"] != nil))
    func everyEntryOfEveryThMLCommentaryParses() throws {
        var modules = 0
        for file in try #require(try dictionaryFiles()) where file.lastPathComponent.hasSuffix(".com.jsonl") {
            let line = try #require(String(contentsOf: file, encoding: .utf8).split(separator: "\n").first)
            let object = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            guard object["sourceType"] as? String == "ThML" else { continue }
            let name = object["module"] as? String ?? file.lastPathComponent
            let entries = try #require(object["entries"] as? [String])
            // A chapter's worth of entries at a time, as the reader gives them.
            var verses = 0, links = 0, empty = 0
            for chunk in stride(from: 0, to: entries.count, by: 40) {
                let batch = entries[chunk..<min(chunk + 40, entries.count)].enumerated().map { ChapterEntries.Entry(verse: $0.offset + 1, text: $0.element) }
                let m = ThMLParser(options: .init(module: name), profile: .commentary).parse(batch)
                verses += m.verses.count
                if m.text.isEmpty { empty += 1 }
                for s in m.spans {
                    #expect(s.start >= 0 && s.length > 0 && s.start + s.length <= m.text.utf16.count, "\(name)")
                    if case .link = s.attribute { links += 1 }
                }
                #expect(!m.text.contains("<scripRef") && !m.text.contains("<br") && !m.text.contains("<b>"), "\(name): markup leaked")
            }
            print("ThML commentary \(name): \(entries.count) entries, \(verses) verse ranges, \(links) links")
            modules += 1
        }
        #expect(modules >= 1)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCRIPTURE_DICT_DIR"] != nil))
    func everyEntryOfEveryThMLModuleParses() throws {
        var modules = 0
        for file in try #require(try dictionaryFiles()) where file.lastPathComponent.hasSuffix(".dict.jsonl") {
            let line = try #require(String(contentsOf: file, encoding: .utf8).split(separator: "\n").first)
            let object = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            guard object["sourceType"] as? String == "ThML" else { continue }
            let name = object["module"] as? String ?? file.lastPathComponent
            let entries = try #require(object["entries"] as? [[String]])
            var empty = 0, links = 0
            for pair in entries {
                let m = ThMLParser(options: .init(module: name)).parse(pair[1])
                if m.text.isEmpty { empty += 1 }
                for s in m.spans {
                    #expect(s.start >= 0 && s.length > 0 && s.start + s.length <= m.text.utf16.count, "\(name) \(pair[0])")
                    if case .link = s.attribute { links += 1 }
                }
                #expect(!m.text.contains("<a ") && !m.text.contains("<b>") && !m.text.contains("<br"), "\(name) \(pair[0]): markup leaked: \(m.text.prefix(80))")
            }
            print("ThML \(name): \(entries.count) entries, \(empty) empty, \(links) links")
            #expect(empty <= 1, "\(name)")   // the module's own preface entries may be empty
            modules += 1
        }
        #expect(modules >= 2)
    }

    /// The two CCEL works parse whole, in one go: the KJV (10 MB) and Barnes (32 MB). The
    /// text is not empty, no markup leaks and the spans stay in range.
    /// `SCRIPTURE_THML_DIR=~/source/pocketsword-dumps/sources/thml`
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCRIPTURE_THML_DIR"] != nil))
    func theCCELWorksParseWhole() throws {
        let dir = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["SCRIPTURE_THML_DIR"]))
        for name in ["kjv.xml", "ntnotes.xml"] {
            let xml = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            let start = Date()
            let m = ThMLParser(options: .init(module: name), profile: .about).parse(xml)
            let seconds = Date().timeIntervalSince(start)
            print("ThML \(name): \(xml.utf8.count) bytes -> \(m.text.utf16.count) UTF-16 units, \(m.spans.count) spans, \(m.notes.count) notes in \(String(format: "%.2f", seconds)) s")
            #expect(m.text.utf16.count > 1_000_000, "\(name)")
            for s in m.spans { #expect(s.start >= 0 && s.length > 0 && s.start + s.length <= m.text.utf16.count) }
            #expect(!m.text.contains("<scripRef"), "\(name)")
            #expect(!m.text.contains("<div"), "\(name)")
        }
    }
}
