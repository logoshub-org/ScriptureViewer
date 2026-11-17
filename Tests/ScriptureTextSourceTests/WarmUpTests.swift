// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
import ScriptureText
import ScriptureTextOSIS
import ScriptureTextGBF
@testable import ScriptureTextSource

/// The warm-up's samples hold what they are there to run: a sample that parsed to nothing would warm nothing, and nothing else
/// would notice.
@Suite("Warm-up")
struct WarmUpTests {

    @Test func theSamplesParseToWhatAChapterHas() {
        var options = OSISParser.Options()
        options.strongsMarkers = true
        let osis = OSISParser(options: options).parse([OSISParser.VerseEntry(verse: 1, osis: WarmUpSamples.osis)])
        #expect(osis.verses.count == 1)
        #expect(osis.notes.count == 1)
        #expect(osis.words.count > 5)
        #expect(osis.spans.contains { $0.attribute == .redLetter })
        #expect(osis.spans.contains { $0.attribute == .divineName })
        #expect(osis.spans.contains { if case .strongs = $0.attribute { true } else { false } })

        let gbf = GBFParser(options: options, profile: .commentary).parse([ChapterEntries.Entry(verse: 1, text: WarmUpSamples.gbf)])
        #expect(gbf.notes.count == 1)
        #expect(gbf.spans.contains { $0.attribute == .redLetter })
        #expect(gbf.spans.contains { if case .word = $0.attribute { true } else { false } })
    }

    @Test func itRunsAndChangesNothing() {
        ScriptureModuleSource.warmUp(rounds: 1)
        ScriptureModuleSource.warmUp(rounds: 1)
    }
}
