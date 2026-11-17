// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
import ScriptureText
@testable import ScriptureTextUSFM

/// The USFM warm-up's book holds what it is there to run.
@Suite("USFM warm-up")
struct USFMWarmUpTests {

    @Test func theBookParsesToWhatAChapterHas() throws {
        let book = try #require(USFMBook(USFMParser.warmUpBook))
        #expect(book.code == "PSA" && book.chapters == [1])
        var options = USFMParser.Options()
        options.strongsMarkers = true
        let model = try #require(USFMParser(options: options).parse(book, chapter: 1))
        #expect(model.verses.count == 3)
        #expect(model.verses.contains { $0.lastVerse == 3 })
        #expect(model.notes.count == 2)
        #expect(model.spans.contains { $0.attribute == .redLetter })
        #expect(model.spans.contains { $0.attribute == .divineName })
        #expect(model.spans.contains { if case .strongs = $0.attribute { true } else { false } })
        USFMParser.warmUp(rounds: 1)
    }
}
