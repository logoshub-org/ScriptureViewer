// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
@testable import ScriptureText

@Suite struct BookNavigationTests {

    private let books: [Versification.Book] = [
        .init(name: "Genesis", osisID: "Gen", versesPerChapter: [31, 25, 24], testament: .old),
        .init(name: "Obadiah", osisID: "Obad", versesPerChapter: [21], testament: .old),
        .init(name: "Matthew", osisID: "Matt", versesPerChapter: [25, 23], testament: .new),
        .init(name: "Jude", osisID: "Jude", versesPerChapter: [25], testament: .new),
    ]

    @Test func fiveColumnsOnAPhoneAndMoreWhereThereIsRoom() {
        #expect(BookNavigatorGrid.columns(forWidth: 288) == 5) // iPhone SE, less the margins
        #expect(BookNavigatorGrid.columns(forWidth: 398) == 5) // iPhone Pro Max
        #expect(BookNavigatorGrid.columns(forWidth: 448) == 6) // the iPad popover
        #expect(BookNavigatorGrid.columns(forWidth: 736) == 10) // a full iPad
        #expect(BookNavigatorGrid.rows(forCount: 150, columns: 5) == 30)
        #expect(BookNavigatorGrid.rows(forCount: 3, columns: 5) == 1)
    }

    @Test func cellsAreSquareAndFitAcrossTheWidth() {
        let side = BookNavigatorGrid.cellSide(forWidth: 448, columns: 6)
        #expect(side * 6 + BookNavigatorGrid.spacing * 5 <= 448)
        #expect(side == 68)
    }

    @Test func oneBookIsOpenAtATime() {
        var state = BookNavigatorState(books: books)
        #expect(state.tapBook(0) == .expand(book: 0))
        #expect(state.chapterCount(ofBook: 0) == 3)
        #expect(state.tapBook(2) == .expand(book: 2))
        #expect(state.expandedBook == 2)
        #expect(state.chapterCount(ofBook: 0) == 0, "opening Matthew closes Genesis")
        #expect(state.tapBook(2) == .collapse(book: 2))
        #expect(state.expandedBook == nil)
    }

    @Test func aBookOfOneChapterGoesStraightToItsVerses() {
        var state = BookNavigatorState(books: books)
        _ = state.tapBook(0)
        #expect(state.tapBook(1) == .showVerses(book: 1, chapter: 1))
        #expect(state.expandedBook == 0, "the open book stays open")
    }

    @Test func testamentTitlesHeadTheFirstBookOfEachTestament() {
        let state = BookNavigatorState(books: books)
        #expect((0..<4).map(state.testamentStarting(atBook:)) == [.old, nil, .new, nil])
    }

    @Test func booksAreFoundByNameOrOSISId() {
        let kjv = Versification(name: "KJV", books: books)
        #expect(kjv.bookIndex(named: "Matthew") == 2)
        #expect(kjv.bookIndex(named: "Matt") == 2)
        #expect(kjv.bookIndex(named: "Tobit") == nil)
        #expect(books[0].verseCount(ofChapter: 2) == 25)
        #expect(books[0].verseCount(ofChapter: 4) == 0)
    }
}
