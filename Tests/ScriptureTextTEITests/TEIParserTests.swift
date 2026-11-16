// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import ScriptureText
@testable import ScriptureTextTEI

@Suite("TEIParser")
struct TEIParserTests {

    // Strong's Greek G1, as the module stores it (public domain).
    private let alpha = "<entryFree n=\"1\">\n<orth>\u{1F08}\u{03BB}\u{03C6}\u{03B1}</orth><lb/>\n<orth type=\"writing\">a[lfa</orth> <orth rend=\"bold\" type=\"trans\">a</orth> <pron rend=\"italic\">{al'-fah}</pron>\n<def>\n\n of Hebrew origin; the first letter of the alphabet; figuratively, only\n (from its use as a numeral) the first: --Alpha. Often used (usually\n<lb/> see GREEK for 427\n</def>\n\n</entryFree>\u{0}"

    private func parse(_ s: String, module: String? = "StrongsGreek") -> ScriptureText {
        TEIParser(options: .init(module: module)).parse(s)
    }

    private func texts(_ m: ScriptureText, _ pick: (ScriptureText.Attribute) -> Bool) -> [String] {
        m.spans.filter { pick($0.attribute) }.compactMap { m.substring(utf16Start: $0.start, length: $0.length) }
    }

    @Test func aStrongsEntryReadsLikeTheWebView() {
        let m = parse(alpha)
        #expect(m.text == "1 \u{1F08}\u{03BB}\u{03C6}\u{03B1}\na[lfa a {al'-fah} of Hebrew origin; the first letter of the alphabet; figuratively, only (from its use as a numeral) the first: --Alpha. Often used (usually\nsee GREEK for 427")
        #expect(texts(m) { $0 == .bold } == ["1", "\u{1F08}\u{03BB}\u{03C6}\u{03B1}", "a[lfa", "a"])
        #expect(texts(m) { $0 == .italic } == ["{al'-fah}"])
    }

    @Test func theEntryNumberIsBoldAndAFollowingSpaceKeepsItApart() {
        let m = parse(#"<entryFree n="AAampa"> Aramaic: Adjective adjective masculine plural absolute</entryFree>"#)
        #expect(m.text == "AAampa Aramaic: Adjective adjective masculine plural absolute")
        #expect(texts(m) { $0 == .bold } == ["AAampa"])
    }

    @Test func aDictionaryRefIsASwordLinkWithTheWorkAndTheKey() {
        let m = parse(#"<entryFree n="6"><def>from <ref target="ChisStrongsHebrew:01893">SNH01893</ref>; x</def></entryFree>"#, module: "ChisStrongsGreek")
        #expect(texts(m) { if case .link = $0 { true } else { false } } == ["SNH01893"])
        let link = m.spans.first { if case .link = $0.attribute { true } else { false } }
        #expect(link?.attribute == .link(target: "sword://ChisStrongsHebrew/01893"))
    }

    @Test func aRefWithNoWorkBelongsToTheEntrysOwnModule() {
        let m = parse(#"<entryFree n="1">see <ref target="05400">5400</ref></entryFree>"#, module: "StrongsGreek")
        #expect(m.spans.last?.attribute == .link(target: "sword://StrongsGreek/05400"))
    }

    @Test func osisRefIsAScriptureLinkAndKeysAreEncoded() {
        let m = parse(#"<entryFree>a <ref osisRef="KJV:John.3.16">John 3:16</ref> <ref target="Robinson:HC/Vvj3ms">x</ref></entryFree>"#)
        let links = m.spans.compactMap { s -> String? in if case .link(let t) = s.attribute { t } else { nil } }
        #expect(links == ["sword://KJV/John.3.16", "sword://Robinson/HC%2FVvj3ms"])
    }

    @Test func lineBreaksAndParagraphsFollowSWORDsBreakCount() {
        #expect(parse("<entryFree>a<lb/>b</entryFree>").text == "a\nb")
        #expect(parse("<entryFree>a<lb/><lb/>b</entryFree>").text == "a\n\nb")
        #expect(parse("<entryFree><p>one</p><p>two</p></entryFree>").text == "one\n\ntwo")
        #expect(parse("<entryFree>text<lb/>\n<lb/> more</entryFree>").text == "text\n\nmore")
    }

    @Test func hardWrappedLinesCollapseToSpacesAndTheEndsAreTrimmed() {
        #expect(parse("<entryFree>\n  one\n  two   three \n</entryFree>\n").text == "one two three")
    }

    @Test func senseNumbersStartANewLine() {
        let m = parse(#"<entryFree>lead<sense n="1">first</sense><sense n="2">second</sense></entryFree>"#)
        #expect(m.text == "lead\n1 first\n2 second")
        #expect(texts(m) { $0 == .bold } == ["1", "2"])
    }

    @Test func hiAndFriendsAreStyled() {
        let m = parse(#"<entryFree><hi rend="italic">i</hi> <hi rend="bold">b</hi> <pos>n</pos> <hi rend="sup">s</hi></entryFree>"#)
        #expect(texts(m) { $0 == .italic } == ["i", "n"])
        #expect(texts(m) { $0 == .bold } == ["b"])
        #expect(m.text == "i b n s")
    }

    @Test func aNoteBecomesAFootnoteMarkerAndKeepsItsBodyApart() {
        let m = parse(#"<entryFree>word<note n="a"> a  remark </note> next</entryFree>"#)
        #expect(m.text == "wordn next")
        #expect(m.notes.map(\.text) == ["a remark"])
        #expect(texts(m) { if case .footnote = $0 { true } else { false } } == ["n"])
        var off = TEIParser.Options(); off.footnotes = false
        #expect(TEIParser(options: off).parse(#"<entryFree>word<note> a </note> next</entryFree>"#).text == "word next")
    }

    @Test func listItemsAreOneParagraphEach() {
        let m = parse("<entryFree><list><item>one</item><item>two</item></list></entryFree>")
        #expect(m.text == "one\ntwo")
        #expect(m.spans.compactMap { s -> ParagraphRole? in if case .block(let r) = s.attribute { r } else { nil } } == [.li1, .li1])
    }

    @Test func greekAccentsCanBeRemovedFromTheHeadword() {
        var o = TEIParser.Options(); o.transforms = TextTransforms(greekAccents: false)
        #expect(TEIParser(options: o).parse("<entryFree><orth>\u{1F08}\u{03BB}\u{03C6}\u{03B1}</orth></entryFree>").text == "\u{0391}\u{03BB}\u{03C6}\u{03B1}")
    }

    @Test func unknownTagsAndBrokenMarkupDegradeToText() {
        #expect(parse("<entryFree><weird>kept</weird> <unclosed>also</entryFree>").text == "kept also")
        #expect(parse("<entryFree>cut off <orth").text == "cut off")
        #expect(parse("").text == "")
        #expect(parse("no markup at all").text == "no markup at all")
    }

    @Test func entitiesAreDecoded() {
        #expect(parse("<entryFree>A&amp;bel &lt;1&gt;</entryFree>").text == "A&bel <1>")
    }

    @Test func spansStayInsideTheText() {
        let m = parse(alpha)
        for s in m.spans { #expect(s.start >= 0 && s.length > 0 && s.start + s.length <= m.text.utf16.count) }
    }

    @Test func theTEIParserUsesNoXMLOrHTMLLibrary() throws {
        let source = try String(contentsOfFile: #filePath.replacingOccurrences(
            of: "Tests/ScriptureTextTEITests/TEIParserTests.swift", with: "Sources/ScriptureTextTEI/TEIParser.swift"))
        #expect(!source.contains("import SwiftSoup"))
        #expect(!source.contains("XMLParser"))
    }

    // MARK: Real modules (local)

    /// Every entry of every TEI module in the dumps repo parses, with sane spans, and the
    /// vocabulary is the one this parser knows. `SCRIPTURE_DICT_DIR=~/source/pocketsword-dumps/corpus/dict`
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCRIPTURE_DICT_DIR"] != nil))
    func everyEntryOfEveryTEIModuleParses() throws {
        let dir = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["SCRIPTURE_DICT_DIR"]))
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
        var modules = 0
        for file in files {
            let line = try #require(String(contentsOf: file, encoding: .utf8).split(separator: "\n").first)
            let object = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            guard object["sourceType"] as? String == "TEI" else { continue }
            let name = object["module"] as? String ?? file.lastPathComponent
            let entries = try #require(object["entries"] as? [[String]])
            var empty = 0, links = 0
            for pair in entries {
                let m = TEIParser(options: .init(module: name)).parse(pair[1])
                if m.text.isEmpty { empty += 1 }
                for s in m.spans {
                    #expect(s.start >= 0 && s.length > 0 && s.start + s.length <= m.text.utf16.count, "\(name) \(pair[0])")
                    if case .link = s.attribute { links += 1 }
                }
                #expect(!m.text.contains("<") || pair[1].contains("&lt;"), "\(name) \(pair[0]): markup leaked: \(m.text.prefix(80))")
            }
            print("TEI \(name): \(entries.count) entries, \(empty) empty, \(links) links")
            #expect(empty == 0, "\(name)")
            modules += 1
        }
        #expect(modules >= 4)
    }
}
