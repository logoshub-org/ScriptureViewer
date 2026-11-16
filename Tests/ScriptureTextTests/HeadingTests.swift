// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
@testable import ScriptureText

@Suite struct HeadingTests {

    @Test func theHeadingGoesOnItsOwnLineAndEverythingElseMovesDown() {
        let entry = ScriptureText(text: "the article", spans: [.init(start: 4, length: 7, attribute: .italic)],
                                  verses: [.init(verse: 1, start: 0, length: 11)])
        let headed = entry.prependingHeading("3588 – ὁ")
        #expect(headed.text == "3588 – ὁ\nthe article")
        #expect(headed.spans.first == .init(start: 0, length: 8, attribute: .block(.s1)))
        #expect(headed.spans.last == .init(start: 13, length: 7, attribute: .italic))
        #expect(headed.substring(utf16Start: headed.spans.last!.start, length: 7) == "article")
        #expect(headed.verses == [.init(verse: 1, start: 9, length: 11)])
    }

    @Test func anEmptyHeadingChangesNothing() {
        let entry = ScriptureText(text: "x")
        #expect(entry.prependingHeading("  ") == entry)
    }
}
