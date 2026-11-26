// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import ScriptureText
import ScriptureTextOSIS
@testable import ScriptureTextGBF

// The text in these tests is invented; the shapes are those of the CrossWire GBF modules.
@Suite("GBFParser")
struct GBFParserTests {

    private func chapter(_ entries: [String], profile: ScriptureContentProfile = .chapter,
                         options: OSISParser.Options = .init()) -> ScriptureText {
        let list = entries.enumerated().map { ChapterEntries.Entry(verse: $0.offset + 1, text: $0.element) }
        return GBFParser(options: options, profile: profile).parse(list)
    }

    private func texts(_ m: ScriptureText, _ pick: (ScriptureText.Attribute) -> Bool) -> [String] {
        m.spans.filter { pick($0.attribute) }.compactMap { m.substring(utf16Start: $0.start, length: $0.length) }
    }

    @Test func italicsAreItalicAndDoNotSplitTheVerse() {
        let m = chapter(["and darkness <FI>is<Fi> on the face of the deep,<CM>", "and the Spirit <FI>was<Fi> moving."])
        #expect(m.text == "1and darkness is on the face of the deep,\n2and the Spirit was moving.")
        #expect(texts(m) { $0 == .italic } == ["is", "was"])
        #expect(m.verses.map(\.verse) == [1, 2])
    }

    @Test func aParagraphTagStartsANewLine() {
        let m = chapter(["First.<CM>", "Second."])
        #expect(m.text == "1First.\n2Second.", "\(m.text.debugDescription)")
    }

    @Test func oldTestamentQuotesAreItalic() {
        let m = chapter([#"<FO>"Mark! The maiden will conceive"<Fo> --a word."#])
        #expect(texts(m) { $0 == .italic }.count == 1)
    }

    @Test func wordsOfJesusAreRedAndStrongsNumbersAttachToTheirWord() {
        let entry = "ему<WG846> в ответ<WG611>: <FR>оставь<Fr><WG863> <FR>теперь<Fr><WG737>, и"
        let plain = chapter([entry])
        #expect(texts(plain) { $0 == .redLetter } == ["оставь", "теперь"])
        #expect(plain.text == "1ему в ответ: оставь теперь, и")
        var options = OSISParser.Options()
        options.strongsMarkers = true
        let m = chapter([entry], options: options)
        #expect(m.text == "1ему<846> в ответ<611>: оставь<863> теперь<737>, и", "\(m.text)")
        #expect(m.words.count == 6)
    }

    @Test func strongsMarkersAreOffByDefault() {
        let m = chapter(["ему<WG846> в ответ<WG611>"])
        #expect(m.text == "1ему в ответ")
        #expect(m.words.map(\.length).contains(3))
    }

    @Test func twoNumbersOnOneWordAndANumberBeforeItsWord() {
        var options = OSISParser.Options()
        options.strongsMarkers = true
        let a = chapter(["Родословие<WG976><WG1078> Иисуса"], options: options)
        #expect(a.text == "1Родословие<976><1078> Иисуса", "\(a.text)")
        let b = chapter(["Павел<WG 3972>, <WG 1223> волею<WG 2307>"], options: options)
        #expect(b.text == "1Павел<3972>, волею<1223><2307>", "\(b.text)")
        let strongs = b.spans.compactMap { if case .strongs(let s) = $0.attribute { s } else { nil } }
        #expect(strongs == ["strong:G3972", "strong:G1223", "strong:G2307"], "\(strongs)")
    }

    /// `<WTG5719>` is a Strong's tense number, labelled as OSIS modules label it (`strongMorph:TG5719`); it was once `robinson:5719`,
    /// which a Robinson lookup misread. Its marker still shows the number. `<WT…>` with a Robinson code stays Robinson's, whole.
    @Test func aTenseNumberIsStrongsMorphologyAndARobinsonCodeIsRobinsons() {
        var options = OSISParser.Options()
        options.morphMarkers = true
        let m = chapter(["λόγος<WG3056><WTG5719> καί<WTN-NSF> אָמַר<WTH 8804> עִבְרִי<WTHEB>"], options: options)
        let codes = m.spans.compactMap { if case .morph(let code) = $0.attribute { code } else { nil } }
        #expect(codes == ["strongMorph:TG5719", "robinson:N-NSF", "strongMorph:TH8804", "robinson:HEB"], "\(codes)")
        #expect(m.text.contains("λόγος(5719)"), "\(m.text)")
        #expect(m.text.contains("(HEB)"), "\(m.text)")
        let tap = m.spans.first { if case .morph("strongMorph:TG5719") = $0.attribute { true } else { false } }
        let target = try? #require(tap.flatMap { m.tapTarget(atUTF16Offset: $0.start + 1) })
        #expect(target?.attributes["scheme"] == "strongMorph")
    }

    @Test func aTitleIsAHeadingAndAFootnoteIsKeptApart() {
        let m = chapter(["<TT><JC>The Gospel<CM><Tt>In the beginning<RF>A study note.<Rf> was the Word."])
        #expect(m.text.contains("The Gospel"))
        #expect(m.notes.map(\.text) == ["A study note."], "\(m.notes)")
        #expect(!m.text.contains("A study note"))
    }

    @Test func footnotesCanBeSwitchedOff() {
        var options = OSISParser.Options()
        options.footnotes = false
        let m = chapter(["In the beginning<RF>A study note.<Rf> was the Word."], options: options)
        #expect(m.notes.isEmpty)
        #expect(!m.text.contains("study"))
    }

    @Test func characterTagsAndStrayAmpersands() {
        #expect(GBFParser.osis(from: "a<CA169>b <CT>c<CG> & d") == "a©b &lt;c&gt; &amp; d")
    }

    @Test func unknownTagsAreDroppedAndTheirTextKept() {
        let m = chapter(["see <I>this</I> and <JR>that<JL> <FN Arial>too<Fn>"])
        #expect(m.text == "1see this and that too")
    }

    @Test func anUnterminatedBracketIsText() {
        #expect(GBFParser.osis(from: "a < b <FI>c<Fi>") == "a &lt; b <transChange type=\"added\">c</transChange>")
    }

    @Test func aHardWrappedCommentaryReflowsAndABlankLineIsAParagraph() {
        let entry = "\n\n1:1\n  God (a-4)\n  Heb. <FI>Elohim<Fi>, the plural\n  of <FI>Eloah<Fi>.\n\n  Second paragraph\n  here.\n"
        let m = GBFParser(profile: .dictionary).parse(entry)
        #expect(m.text.contains("Heb. Elohim, the plural of Eloah."), "\(m.text.debugDescription)")
        #expect(m.text.contains("\nSecond paragraph here."), "\(m.text.debugDescription)")
        #expect(texts(m) { $0 == .italic } == ["Elohim", "Eloah"])
    }

    @Test func preserveKeepsEveryLine() {
        let m = GBFParser(lineBreaks: .preserve, profile: .dictionary).parse("one\ntwo\nthree")
        #expect(m.text.split(separator: "\n").map(String.init) == ["one", "two", "three"], "\(m.text.debugDescription)")
    }

    @Test func aBlankLineSplitByATagIsStillAParagraph() {
        let m = GBFParser(profile: .dictionary).parse("Intro line.\r\n \r\n    <FB>Bold lead.<Fb> Then text.\r\n \r\n (TFG 5)\r\n")
        #expect(m.text == "Intro line.\nBold lead. Then text.\n(TFG 5)", "\(m.text.debugDescription)")
        #expect(texts(m) { $0 == .bold } == ["Bold lead."])
    }

    @Test func aReferenceMarkIsALinkWithoutItsHashAndBar() {
        let m = GBFParser(profile: .dictionary).parse(" <FU>#Mt 4:12 Mr 1:14 Lu 3:19,20|<Fu>\r\n \r\n    Text <FU>#1 Co 3:4|<Fu> and #5 not a mark.\r\n")
        #expect(m.text == "Mt 4:12 Mr 1:14 Lu 3:19,20\nText 1 Co 3:4 and #5 not a mark.", "\(m.text.debugDescription)")
        let links = m.spans.compactMap { span -> String? in
            if case .link(let target) = span.attribute { return target }
            return nil
        }
        #expect(links == ["passage:Mt 4:12; Mr 1:14; Lu 3:19,20", "passage:1 Co 3:4"], "\(links)")
    }

    @Test func aCentredLineKeepsItsOwnLine() {
        let entry = "                       The Fourfold Gospel\r\n                       ~~~~~~~~~~~~~~~~~~~\r\n The Period of Christ's Life\r\n Beginning of the Ministry\r\n"
        let m = GBFParser(profile: .dictionary).parse(entry)
        #expect(m.text == "The Fourfold Gospel\n~~~~~~~~~~~~~~~~~~~\nThe Period of Christ's Life Beginning of the Ministry", "\(m.text.debugDescription)")
    }

    @Test func strayHTMLInAModuleHidesTheHeadAndKeepsItalics() {
        let m = GBFParser(profile: .dictionary).parse("and he went. </body> </html><html> <head> <meta Name=\"x\"> <title>Romans -- The Inspired Version</title> </head> <body background=\"back.gif\"> Then <em>he</em> came.")
        #expect(!m.text.contains("Inspired"), "\(m.text.debugDescription)")
        #expect(m.text.contains("Then he came."), "\(m.text.debugDescription)")
        #expect(texts(m) { $0 == .italic } == ["he"])
    }

    @Test func aCommentaryShowsOneVersePerLine() {
        let m = chapter(["First note.", "Second note."], profile: .commentary)
        #expect(m.text == "1First note.\n2Second note.", "\(m.text.debugDescription)")
    }

    @Test func emptyAndTagOnlyEntriesDoNotCrash() {
        #expect(chapter(["", "<CM>", "<WG12>", "<FI><Fi>"]).verses.count <= 4)
    }

    // MARK: Local corpus

    /// Every entry of the GBF modules in hand (YLT, Weymouth, RusVZh, DTN, TFG) parses to the words that
    /// are in it, found independently by taking the tags out with a regular expression.
    /// `SCRIPTURE_GBF_DIR=~/source/pocketsword-dumps/corpus/gbf`; the files come from `export_gbf.py`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCRIPTURE_GBF_DIR"] != nil))
    func everyEntryOfTheLocalModulesKeepsItsWords() throws {
        let dir = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["SCRIPTURE_GBF_DIR"]))
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".gbf.jsonl") }
        #expect(!files.isEmpty)
        var options = OSISParser.Options()
        options.footnotes = false
        for file in files {
            let line = try #require(String(contentsOf: file, encoding: .utf8).split(separator: "\n").first)
            let json = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            let entries = try #require(json["entries"] as? [String])
            var checked = 0, differing: [String] = []
            for raw in entries where !raw.isEmpty {
                // Entries with footnotes or character tags have text of their own; the others must match word for word.
                if raw.contains("<RF") || raw.contains("<CA") || raw.contains("<CT>") || raw.contains("<CG>") { continue }
                // Reference marks lose their `#` and `|`; a pasted HTML `<head>` (JST) is not text.
                let expected = raw.replacingOccurrences(of: "(?s)<head[^>]*>.*?</head>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"#\s*([^#|<>\n]*\d[^#|<>\n]*?)\s*\|"#, with: "$1", options: .regularExpression)
                    .replacingOccurrences(of: "<[^<>]*>", with: "", options: .regularExpression)
                    .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                let parsed = GBFParser(options: options, profile: .dictionary).parse(raw).text
                    .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                checked += 1
                if parsed != expected, differing.count < 3 { differing.append("\(expected.prefix(80)) | \(parsed.prefix(80))") }
            }
            #expect(differing.isEmpty, "\(file.lastPathComponent): \(differing)")
            #expect(checked > 100, "\(file.lastPathComponent) checked \(checked)")
        }
    }
}
