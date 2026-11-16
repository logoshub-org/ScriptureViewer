// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
import ScriptureText
@testable import ScriptureTextOSIS

// Word anchors (plan D35, test group 13). Synthetic fixtures only (D24).

private func parse(_ entries: [(Int, String)], options: OSISParser.Options = .init()) -> ScriptureText {
    OSISParser(options: options).parse(entries.map { OSISParser.VerseEntry(verse: $0.0, osis: $0.1) })
}

private func parse(_ osis: String, options: OSISParser.Options = .init()) -> ScriptureText {
    parse([(1, osis)], options: options)
}

extension ScriptureText {
    /// Each anchor as "verse.index:text".
    var anchorDump: [String] {
        words.map { "\($0.verse).\($0.index):\(substring(utf16Start: $0.start, length: $0.length) ?? "?")" }
    }

    /// Anchor texts only.
    var anchorTexts: [String] {
        words.map { substring(utf16Start: $0.start, length: $0.length) ?? "?" }
    }
}

struct OSISWordAnchorTests {

    // MARK: Numbering and ranges

    @Test func wordsAreNumberedFromZeroWithinEachVerse() {
        let m = parse([(1, "In the beginning."), (2, "And the earth.")])
        #expect(m.anchorDump == ["1.0:In", "1.1:the", "1.2:beginning", "2.0:And", "2.1:the", "2.2:earth"])
        #expect(m.isConsistent)
    }

    @Test func rangesExcludeTheVerseMarkerMarkersAndEdgePunctuation() {
        var o = OSISParser.Options(); o.strongsMarkers = true
        let m = parse(#""<w lemma="strong:H0430">God</w>," he said."#, options: o)
        #expect(m.text == "1\"God<0430>,\" he said.")
        #expect(m.anchorTexts == ["God", "he", "said"])
    }

    @Test func aWordElementHoldingSeveralWordsGivesSeveralAnchors() {
        let m = parse(#"<w lemma="strong:H0430">And God</w> <w lemma="strong:H0559">said</w>"#)
        #expect(m.anchorTexts == ["And", "God", "said"])
    }

    // MARK: Segmentation

    @Test func textGluedAfterAWordExtendsIt() {
        let m = parse(#"<w lemma="strong:G2316">God</w>'s <hi type="italic">un</hi>believing"#)
        #expect(m.anchorTexts == ["God's", "unbelieving"])
    }

    @Test func emAndEnDashesSplitWords() {
        #expect(parse("word—word and 1–2").anchorTexts == ["word", "word", "and", "1", "2"])
    }

    @Test func hyphensAndApostrophesInsideAWordDoNot() {
        #expect(parse("well-known don't").anchorTexts == ["well-known", "don't"])
    }

    @Test func adjacentCJKWordElementsAreSeparateWords() {
        let m = parse(#"<w lemma="a">耶稣</w><w lemma="b">对他</w><w lemma="c">说</w>："#)
        #expect(m.anchorTexts == ["耶稣", "对他", "说"])
    }

    @Test func bareCJKIsOneWordPerIdeographAndIdeographicSpaceSplits() {
        let m = parse("你的\u{3000}神。")
        #expect(m.text == "1你的\u{3000}神。")
        #expect(m.anchorTexts == ["你", "的", "神"])
    }

    @Test func emptyWordElementHasNoAnchorAndTakesNoIndex() {
        let m = parse(#"<w lemma="strong:G1161"></w><w lemma="strong:G846">耶稣</w>"#)
        #expect(m.anchorDump == ["1.0:耶稣"])
    }

    @Test func formatCharactersStayInsideWordsButNotAtTheirEdges() {
        let m = parse("پِرِص\u{200C}خِصرون \u{200F}آتاسي\u{200E}،")
        #expect(m.anchorTexts == ["پِرِص\u{200C}خِصرون", "آتاسي"])
    }

    @Test func aMaqafSeparatesWordsLikeADash() {
        #expect(parse("\u{05E9}\u{05B8}\u{05C1}\u{05DC}\u{05D5}\u{05B9}\u{05DD}\u{05BE}\u{05DC}\u{05B8}\u{05DB}\u{05B6}\u{05DD}").anchorTexts.count == 2)
    }

    @Test func hebrewSofPasuqIsNotPartOfTheWord() {
        #expect(parse("בְּרֵאשִׁית בָּרָא\u{05C3}").anchorTexts == ["בְּרֵאשִׁית", "בָּרָא"])
    }

    @Test func punctuationOnlyRunsAreNotWords() {
        #expect(parse("a , ; — b").anchorTexts == ["a", "b"])
    }

    // MARK: What is canonical

    @Test func headingsNotesAndVerseZeroHaveNoAnchors() {
        let m = parse([(0, #"<title type="chapter">CHAPTER 1.</title>"#),
                       (1, #"<title subType="x-preverse">Section</title> earth<note type="study">a note body</note> here"#)])
        #expect(m.anchorDump == ["1.0:earth", "1.1:here"])
    }

    @Test func aPsalmSuperscriptionIsCanonicalAndPrecedesTheVerseMarker() {
        // ethnosdev/scripture's Psalm 23 case: the descriptive title and the
        // first poetry line share verse 1 and number sequentially.
        let m = parse([(1, #"<title canonical="true" type="psalm">A Psalm of David.</title><l level="1" sID="a"/>The LORD is my shepherd;<l eID="a"/>"#)])
        #expect(m.text == "A Psalm of David.\n1The LORD is my shepherd;")
        #expect(m.anchorDump == ["1.0:A", "1.1:Psalm", "1.2:of", "1.3:David",
                                 "1.4:The", "1.5:LORD", "1.6:is", "1.7:my", "1.8:shepherd"])
    }

    @Test func dictionaryProfilesHaveNoAnchors() {
        let m = OSISParser(profile: .dictionary).parse([.init(verse: 1, osis: "entry text")])
        #expect(m.words.isEmpty)
    }

    // MARK: Independence from display options

    private static let chapter: [(Int, String)] = [
        (0, #"<title type="chapter">PSALM 3.</title>"#),
        (1, #"<title canonical="true" type="psalm">A Psalm of David.</title><l level="1" sID="a"/><w lemma="strong:H3068">LORD</w>, how are they increased<note type="study">Heb. multiplied</note>!<l eID="a"/>"#),
        (2, #"<l level="2" sID="b"/><q who="Jesus">Many</q> say <seg type="x-variant" subType="x-1">of my soul</seg><seg type="x-variant" subType="x-2">to me</seg>.<l eID="b"/> <l type="selah" sID="s"/>Selah<l eID="s"/>"#),
        (3, #"<w lemma="strong:G2316" morph="robinson:N-NSM">God</w>'s <transChange type="added">own</transChange> shield—glory."#),
    ]

    private static func optionCombinations() -> [OSISParser.Options] {
        var all: [OSISParser.Options] = []
        for bits in 0..<(1 << 6) {
            var o = OSISParser.Options()
            o.verseNumbers = bits & 1 != 0
            o.strongsMarkers = bits & 2 != 0
            o.morphMarkers = bits & 4 != 0
            o.footnotes = bits & 8 != 0
            o.headings = bits & 16 != 0
            o.redLetter = bits & 32 != 0
            all.append(o)
        }
        return all
    }

    /// "verse.index" → word text.
    private static func anchorMap(_ m: ScriptureText) -> [String: String] {
        var map: [String: String] = [:]
        for w in m.words { map["\(w.verse).\(w.index)"] = m.substring(utf16Start: w.start, length: w.length) }
        return map
    }

    @Test func indexesAndWordTextDoNotDependOnDisplayOptions() {
        // Every word shown: all variants, headings on, no markers.
        let everything = Self.anchorMap(parse(Self.chapter, options: { var o = OSISParser.Options(); o.variants = .all; return o }()))
        #expect(everything.count == 21)
        let primaryKeys = Set(Self.anchorMap(parse(Self.chapter)).keys)
        #expect(primaryKeys.count == 19)                     // the x-2 reading's two words are hidden

        for options in Self.optionCombinations() {
            for variants in [OSISParser.Options.Variants.primary, .secondary, .all] {
                var o = options; o.variants = variants
                let m = parse(Self.chapter, options: o)
                #expect(m.isConsistent)
                for (key, text) in Self.anchorMap(m) {
                    guard let expected = everything[key] else { Issue.record("\(key) unknown under \(o)"); continue }
                    if o.strongsMarkers || o.morphMarkers {
                        // A marker inside a word ends its range: "God<2316>'s" → "God".
                        #expect(expected.hasPrefix(text), "\(key): \(text) vs \(expected) under \(o)")
                    } else {
                        #expect(text == expected, "\(key) under \(o)")
                    }
                }
                if o.headings, variants == .primary {
                    #expect(Set(Self.anchorMap(m).keys) == primaryKeys, "\(o)")
                }
            }
        }
    }

    @Test func aMarkerInsideAWordEndsTheRangeButKeepsTheIndex() {
        var o = OSISParser.Options(); o.strongsMarkers = true
        let m = parse(#"<w lemma="strong:G2316">God</w>'s own"#, options: o)
        #expect(m.text == "1God<2316>'s own")
        #expect(m.anchorDump == ["1.0:God", "1.1:own"])
    }

    @Test func aHiddenVariantKeepsItsWordIndexes() {
        let primary = parse(Self.chapter).anchorDump.filter { $0.hasPrefix("2.") }
        let secondary = parse(Self.chapter, options: { var o = OSISParser.Options(); o.variants = .secondary; return o }())
            .anchorDump.filter { $0.hasPrefix("2.") }
        // "Many say [of my soul | to me]. Selah": "to me" are 2.5 and 2.6 in both
        // parses; only the readings shown differ.
        #expect(primary == ["2.0:Many", "2.1:say", "2.2:of", "2.3:my", "2.4:soul", "2.7:Selah"])
        #expect(secondary == ["2.0:Many", "2.1:say", "2.5:to", "2.6:me", "2.7:Selah"])
    }

    @Test func aCanonicalTitleSurvivesTheHeadingsOptionSoItsWordsKeepTheirIndexes() {
        // SWORD keeps title canonical="true" (a Psalm superscription is verse text) when headings are off.
        var off = OSISParser.Options(); off.headings = false
        let verse1 = parse(Self.chapter, options: off).anchorDump.filter { $0.hasPrefix("1.") }
        #expect(verse1.first == "1.0:A")
        #expect(verse1.contains("1.4:LORD"))
    }

    @Test func aNonCanonicalTitleHasNoWordsWhetherShownOrNot() {
        let osis = #"<title type="sub">Editorial heading</title>text here"#
        var off = OSISParser.Options(); off.headings = false
        #expect(parse(osis).anchorTexts == ["text", "here"])
        #expect(parse(osis, options: off).anchorTexts == ["text", "here"])
    }
}
