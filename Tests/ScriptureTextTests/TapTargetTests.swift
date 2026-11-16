// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import ScriptureText

@Suite("TapTarget (D58)")
struct TapTargetTests {

    private let passage = PassageIdentity(work: "KJV", versification: "KJV", book: "Ps", chapter: 7)

    /// "1In the beginning<H430> God" with spans laid over it by hand.
    private func model(_ spans: [ScriptureText.Span], notes: [ScriptureText.Note] = []) -> ScriptureText {
        ScriptureText(text: "1In the beginning<H430> God (T-NSF) n", spans: spans,
                      verses: [.init(verse: 1, start: 0, length: 37)], notes: notes,
                      words: [.init(verse: 1, index: 0, start: 1, length: 2), .init(verse: 1, index: 1, start: 4, length: 3)],
                      identity: passage)
    }

    @Test func plainTextHasNoTarget() {
        let m = model([])
        #expect(m.tapTarget(atUTF16Offset: 8) == nil)
        #expect(m.tapTarget(atUTF16Offset: -1) == nil)
        #expect(m.tapTarget(atUTF16Offset: 500) == nil)
    }

    @Test func aStrongsTokenFromOSISIsTheKeyAndTheContextSaysWhere() throws {
        let m = model([.init(start: 18, length: 6, attribute: .strongs("strong:H0430"))])
        let t = try #require(m.tapTarget(atUTF16Offset: 20))
        #expect(t.kind == .strongs)
        #expect(t.key == "H0430")
        #expect(t.attributes["language"] == "Hebrew")
        #expect(t.context.verse == 1)
        #expect(t.context.offset == 20)
        #expect(t.context.passage == passage)
    }

    @Test func morphKeepsItsScheme() throws {
        let osis = try #require(model([.init(start: 25, length: 8, attribute: .morph("robinson:T-NSF"))]).tapTarget(atUTF16Offset: 26))
        #expect(osis.kind == .morph && osis.key == "robinson:T-NSF")
        #expect(osis.attributes["code"] == "T-NSF" && osis.attributes["scheme"] == "robinson")
    }

    @Test func aFootnoteIsLookedUpInTheTextsNotes() throws {
        let notes: [ScriptureText.Note] = [
            .init(id: "1.1", text: "or, creeping", references: [], kind: .footnote),
            .init(id: "1.2", text: "see", references: ["Exod.25.5"], kind: .crossReference),
        ]
        let m = model([.init(start: 36, length: 1, attribute: .footnote(id: "1.2"))], notes: notes)
        let t = try #require(m.tapTarget(atUTF16Offset: 36))
        #expect(t.kind == .crossReference)
        #expect(t.key == "1.2")
        #expect(t.attributes["references"] == "Exod.25.5")
    }

    @Test func aSwordLinkIsAnEntryAndOtherLinksAreLinks() throws {
        let e = try #require(model([.init(start: 4, length: 5, attribute: .link(target: "sword://ChisStrongsHebrew/01893"))]).tapTarget(atUTF16Offset: 5))
        #expect(e.kind == .entry && e.key == "01893" && e.attributes["work"] == "ChisStrongsHebrew")
        let k = try #require(model([.init(start: 4, length: 5, attribute: .link(target: "sword://Robinson/HC%2FVvj3ms"))]).tapTarget(atUTF16Offset: 5))
        #expect(k.key == "HC/Vvj3ms")
        let web = try #require(model([.init(start: 4, length: 5, attribute: .link(target: "https://example.org/x"))]).tapTarget(atUTF16Offset: 5))
        #expect(web.kind == .link && web.key == "https://example.org/x")
    }

    @Test func aVerseNumberIsAVerseTarget() throws {
        let t = try #require(model([.init(start: 0, length: 1, attribute: .verseNumber(1))]).tapTarget(atUTF16Offset: 0))
        #expect(t.kind == .verse && t.key == "1")
    }

    @Test func aWordWithLexicalDataCarriesItAndItsReference() throws {
        let m = model([.init(start: 4, length: 3, attribute: .word(lemma: "strong:H1", morph: "x:y"))])
        let t = try #require(m.tapTarget(atUTF16Offset: 5))
        #expect(t.kind == .word && t.attributes["lemma"] == "strong:H1" && t.attributes["morph"] == "x:y")
        #expect(t.context.wordIndex == 1)
        #expect(t.context.wordReference == WordReference(passage: passage, verse: 1, index: 1))
    }

    @Test func theMostSpecificThingWins() throws {
        // A word, a verse number, a link and a marker all cover offset 5; the marker is chosen.
        let m = model([
            .init(start: 4, length: 3, attribute: .word(lemma: "strong:H1", morph: nil)),
            .init(start: 0, length: 8, attribute: .verseNumber(1)),
            .init(start: 3, length: 5, attribute: .link(target: "sword://A/b")),
            .init(start: 5, length: 1, attribute: .strongs("strong:H9")),
        ])
        #expect(m.tapTarget(atUTF16Offset: 5)?.kind == .strongs)
        #expect(m.tapTarget(atUTF16Offset: 4)?.kind == .entry)
        #expect(m.tapTarget(atUTF16Offset: 1)?.kind == .verse)
    }

    @Test func kindsAreOpenAndCodable() throws {
        let t = TapTarget(kind: "commentary", key: "John.3.16", attributes: ["work": "MHCC"], context: .init(offset: 3))
        let back = try JSONDecoder().decode(TapTarget.self, from: JSONEncoder().encode(t))
        #expect(back == t)
        #expect(TapKind.strongs.rawValue == "strongs")
    }

    @Test func aResolverAnswersWithAnAction() async {
        struct Commentary: TapResolver {
            func resolve(_ target: TapTarget) async -> TapResponse {
                switch target.kind {
                case .verse:
                    return .detail(DetailContent(title: "MHCC John 3:\(target.key)", text: ScriptureText(text: "commentary")))
                case .scripture:
                    return .navigate(PassageIdentity(work: "KJV", versification: "KJV", book: "Gen", chapter: 1))
                default:
                    return .none
                }
            }
        }
        let resolver = Commentary()
        let context = TapContext(offset: 0)
        let verse = await resolver.resolve(TapTarget(kind: .verse, key: "16", context: context))
        guard case .detail(let content) = verse else { Issue.record("expected a detail"); return }
        #expect(content.title == "MHCC John 3:16" && content.sections.count == 1)
        #expect(await resolver.resolve(TapTarget(kind: .morph, key: "x", context: context)) == .none)
    }
}

extension TapTargetTests {
    @Test func aFootnoteTargetCarriesTheNotesText() throws {
        let m = ScriptureText(text: "word n", spans: [.init(start: 5, length: 1, attribute: .footnote(id: "1.1"))],
                              notes: [.init(id: "1.1", text: "or, creeping", references: [], kind: .footnote)])
        #expect(m.tapTarget(atUTF16Offset: 5)?.attributes["text"] == "or, creeping")
    }

    @Test func sectionsCombineWithTitlesShiftedSpansAndUniqueNoteIds() throws {
        let a = ScriptureText(text: "first n", spans: [.init(start: 0, length: 5, attribute: .italic), .init(start: 6, length: 1, attribute: .footnote(id: "1"))],
                              notes: [.init(id: "1", text: "A")])
        let b = ScriptureText(text: "second n", spans: [.init(start: 7, length: 1, attribute: .footnote(id: "1"))],
                              notes: [.init(id: "1", text: "B")])
        let c = DetailContent(title: "T", sections: [.init(title: "One", text: a), .init(title: "Two", text: b)]).combined
        #expect(c.text == "One\nfirst n\n\nTwo\nsecond n")
        #expect(c.spans.map(\.attribute).contains(.bold))
        #expect(c.notes.map(\.id) == ["d1", "d2"] && c.notes.map(\.text) == ["A", "B"])
        let footnotes = c.spans.filter { if case .footnote = $0.attribute { true } else { false } }
        #expect(footnotes.map { c.substring(utf16Start: $0.start, length: $0.length) } == ["n", "n"])
        #expect(footnotes.map(\.attribute) == [.footnote(id: "d1"), .footnote(id: "d2")])
        for s in c.spans { #expect(s.start + s.length <= c.text.utf16.count) }
        #expect(c.tapTarget(atUTF16Offset: footnotes[1].start)?.attributes["text"] == "B")
    }

    @Test func scriptureReferencesFromOSISAndThMLAreScriptureTargets() throws {
        func target(_ link: String) throws -> TapTarget {
            let text = ScriptureText(text: "ref", spans: [.init(start: 0, length: 3, attribute: .link(target: link))])
            return try #require(text.tapTarget(atUTF16Offset: 1))
        }
        let osis = try target("osis:Bible:John.3.16")
        #expect(osis.kind == .scripture && osis.key == "John.3.16" && osis.attributes["work"] == "Bible")
        let bare = try target("osis:Gen.1.1-Gen.1.3")
        #expect(bare.kind == .scripture && bare.key == "Gen.1.1-Gen.1.3" && bare.attributes["work"] == nil)
        let thml = try target("passage:Rom 3:23")
        #expect(thml.kind == .scripture && thml.key == "Rom 3:23")
    }
}
