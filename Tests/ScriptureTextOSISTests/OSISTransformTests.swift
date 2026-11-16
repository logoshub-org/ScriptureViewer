// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import ScriptureText
@testable import ScriptureTextOSIS

// The D47 transforms inside the OSIS parser. The goldens
// (Fixtures/OSIS/text_transforms.*) pin the exact output of each option; these
// tests pin the properties the goldens can't show at a glance.

struct OSISTransformTests {

    private func parse(_ osis: String, _ configure: (inout OSISParser.Options) -> Void) -> ScriptureText {
        var options = OSISParser.Options()
        configure(&options)
        return OSISParser(options: options).parse([.init(verse: 1, osis: osis)])
    }

    private func fixture() throws -> GoldenFixture {
        let url = try #require(try GoldenFiles.fixtureURLs().first { GoldenFiles.name(of: $0) == "text_transforms" })
        return try JSONDecoder().decode(GoldenFixture.self, from: Data(contentsOf: url))
    }

    @Test func wordIndexesDoNotChangeWithTheTransforms() throws {
        let f = try fixture()
        let models = f.runs.map { f.parse($0) }
        let reference = models[0].words.map { [$0.verse, $0.index] }
        #expect(reference.count == 27)
        for (run, model) in zip(f.runs, models) {
            #expect(model.words.map { [$0.verse, $0.index] } == reference, "\(run.name)")
            #expect(model.isConsistent, "\(run.name)")
        }
    }

    @Test func noteTextIsTransformedToo() {
        let on = parse("x<note n=\"a\">ἀλλ’ ἐγώ</note>") { _ in }
        let off = parse("x<note n=\"a\">ἀλλ’ ἐγώ</note>") { $0.greekAccents = false }
        #expect(on.notes.first?.text == "ἀλλ’ ἐγώ")
        #expect(off.notes.first?.text == "αλλ εγω")
    }

    @Test func offsetsAreRecordedAfterTheTransform() {
        let m = parse("בְּרֵאשִׁית אֱלֹהִים") { $0.hebrewPoints = false }
        #expect(m.isConsistent)
        let first = m.words.first!
        #expect(m.substring(utf16Start: first.start, length: first.length) == "בראשׁית")
    }

    @Test func strongsAndMorphKeysAreNeverTransformed() {
        let m = parse("<w lemma=\"lemma.LXX:καὶ strong:G2532\" morph=\"packard:C\">καὶ</w>") {
            $0.greekAccents = false
        }
        guard case .word(let lemma, _)? = m.spans.compactMap({ s -> ScriptureText.Attribute? in
            if case .word = s.attribute { return s.attribute } else { return nil }
        }).first else { Issue.record("no word span"); return }
        #expect(lemma == "lemma.LXX:καὶ strong:G2532")
        #expect(m.text.contains("και"))
    }

    @Test func aDictionaryEntryIsTransformedToo() {
        var options = OSISParser.Options()
        options.hebrewPoints = false
        let m = OSISParser(options: options, profile: .dictionary).parse([.init(verse: 0, osis: "<p>שָׁלוֹם</p>")])
        #expect(m.text.contains("שׁלום"))
    }
}
