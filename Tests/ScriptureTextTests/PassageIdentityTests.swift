// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import ScriptureText

// Passage identity and word references (plan D35, D41).

struct PassageIdentityTests {

    private let genesis1 = PassageIdentity(work: "KJV", versification: "KJV", book: "Gen", chapter: 1)

    private func text(identity: PassageIdentity?) -> ScriptureText {
        ScriptureText(text: "In the beginning God", words: [
            .init(verse: 1, index: 0, start: 0, length: 2),
            .init(verse: 1, index: 1, start: 3, length: 3),
            .init(verse: 1, index: 2, start: 7, length: 9),
            .init(verse: 2, index: 0, start: 17, length: 3),
        ], identity: identity)
    }

    @Test func anAnchorBecomesAReferenceWithThePassageItBelongsTo() throws {
        let m = text(identity: genesis1)
        let reference = try #require(m.reference(for: m.words[2]))
        #expect(reference == WordReference(passage: genesis1, verse: 1, index: 2))
        #expect(reference.osisVerse == "Gen.1.1")
    }

    @Test func aTextWithoutAnIdentityMakesNoReferences() {
        let m = text(identity: nil)
        #expect(m.reference(for: m.words[0]) == nil)
    }

    @Test func aReferenceFindsItsAnchor() throws {
        let m = text(identity: genesis1)
        let found = try #require(m.anchor(for: WordReference(passage: genesis1, verse: 2, index: 0)))
        #expect(found.start == 17)
        #expect(m.anchor(for: WordReference(passage: genesis1, verse: 1, index: 1))?.start == 3)
    }

    @Test func aReferenceToAWordThatIsNotThereFindsNothing() {
        let m = text(identity: genesis1)
        #expect(m.anchor(for: WordReference(passage: genesis1, verse: 1, index: 9)) == nil)
        #expect(m.anchor(for: WordReference(passage: genesis1, verse: 7, index: 0)) == nil)
    }

    @Test func aReferenceFromAnotherVersificationOrWorkIsNeverMatched() {
        let m = text(identity: genesis1)
        for other in [
            PassageIdentity(work: "KJV", versification: "LXX", book: "Gen", chapter: 1),
            PassageIdentity(work: "WEB", versification: "KJV", book: "Gen", chapter: 1),
            PassageIdentity(work: "KJV", versification: "KJV", book: "Exod", chapter: 1),
            PassageIdentity(work: "KJV", versification: "KJV", book: "Gen", chapter: 2),
        ] {
            #expect(m.anchor(for: WordReference(passage: other, verse: 1, index: 0)) == nil, "\(other)")
        }
    }

    @Test func everyAnchorIsFoundByItsOwnReference() throws {
        let m = text(identity: genesis1)
        for anchor in m.words {
            let reference = try #require(m.reference(for: anchor))
            #expect(m.anchor(for: reference) == anchor)
        }
    }

    @Test func referencesAreHashableCodableKeys() throws {
        let reference = WordReference(passage: genesis1, verse: 3, index: 4)
        let decoded = try JSONDecoder().decode(WordReference.self, from: JSONEncoder().encode(reference))
        #expect(decoded == reference)
        #expect(Set([reference, decoded]).count == 1)
    }

    @Test func aTextWithAnIdentityRoundTripsThroughJSON() throws {
        let m = text(identity: genesis1)
        #expect(try JSONDecoder().decode(ScriptureText.self, from: JSONEncoder().encode(m)) == m)
    }
}
