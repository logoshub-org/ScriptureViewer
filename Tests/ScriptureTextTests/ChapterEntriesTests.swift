// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
@testable import ScriptureText

@Suite("ChapterEntries and ScriptureModuleFacts (D50)")
struct ChapterEntriesTests {

    private func entries(_ texts: [String]) -> [ChapterEntries.Entry] {
        texts.enumerated().map { .init(verse: $0.offset, text: $0.element) }
    }

    @Test func emptyAndWhitespaceOnlyEntriesAreDropped() {
        let shown = ChapterEntries.shown(entries(["", "a", " \n\t", "b", ""]))
        #expect(shown.map(\.verse) == [1, 3])
    }

    @Test func aRepeatOfTheEntryJustReadIsDroppedAndTheVerseNumberLeftOut() {
        let shown = ChapterEntries.shown(entries(["intro", "x", "x", "x", "y"]))
        #expect(shown.map(\.verse) == [0, 1, 4])
    }

    @Test func leadingWhitespaceDoesNotHideARepeat() {
        let shown = ChapterEntries.shown(entries(["x", "  x", "\nx"]))
        #expect(shown.map(\.verse) == [0])
    }

    @Test func anEmptyEntryBetweenEqualOnesLetsBothThrough() {
        // The app's loop remembers the last entry read, empty or not.
        let shown = ChapterEntries.shown(entries(["x", "", "x"]))
        #expect(shown.map(\.verse) == [0, 2])
    }

    @Test func nonConsecutiveRepeatsAreKept() {
        let shown = ChapterEntries.shown(entries(["x", "y", "x"]))
        #expect(shown.map(\.verse) == [0, 1, 2])
    }

    @Test func entryTextIsPassedOnUntouched() {
        #expect(ChapterEntries.shown(entries(["  <w>a</w> "])).first?.text == "  <w>a</w> ")
    }

    // MARK: Facts

    @Test func sourceTypeFollowsTheConfValueCaseInsensitively() {
        #expect(ScriptureSourceType.from(conf: "OSIS") == .osis)
        #expect(ScriptureSourceType.from(conf: "ThML") == .thml)
        #expect(ScriptureSourceType.from(conf: " gbf ") == .gbf)
        #expect(ScriptureSourceType.from(conf: "TEI") == .tei)
        #expect(ScriptureSourceType.from(conf: nil) == .plain)
        #expect(ScriptureSourceType.from(conf: "") == .plain)
        #expect(ScriptureSourceType.from(conf: "plain") == .plain)
        #expect(ScriptureSourceType.from(conf: "Unheard") == .plain)
    }

    @Test func aTransformAppliesOnlyWhenThePreferenceIsOffAndTheModuleDeclaresTheFilter() {
        let lxx = ScriptureModuleFacts(name: "LXX", declaresGreekAccents: true)
        #expect(lxx.textTransforms(greekAccents: false, hebrewPoints: false, hebrewCantillation: false)
                == TextTransforms(greekAccents: false, hebrewPoints: true, hebrewCantillation: true))
        #expect(lxx.textTransforms(greekAccents: true, hebrewPoints: false, hebrewCantillation: false).isIdentity)
        let plainEnglish = ScriptureModuleFacts(name: "KJV")
        #expect(plainEnglish.textTransforms(greekAccents: false, hebrewPoints: false, hebrewCantillation: false).isIdentity)
    }

    @Test func identityCarriesTheModulesVersification() {
        let facts = ScriptureModuleFacts(name: "LXX", versification: "LXX")
        #expect(facts.identity(book: "Gen", chapter: 1)
                == PassageIdentity(work: "LXX", versification: "LXX", book: "Gen", chapter: 1))
    }
}
