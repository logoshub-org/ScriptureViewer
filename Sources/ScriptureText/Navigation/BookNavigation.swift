// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// The rules of the book navigator (plan D79, D81), apart from any screen: a list of books whose chapters open as a grid
// under the book, then a grid of the chapter's verses. A platform layer (UIKit now; Compose, say, later) draws them.

/// What a tap on a book does, and which book is open.
public struct BookNavigatorState: Equatable, Sendable {

    public enum Action: Equatable, Sendable {
        case expand(book: Int)
        case collapse(book: Int)
        case showVerses(book: Int, chapter: Int)
    }

    public let books: [Versification.Book]
    /// The one book whose chapters are open, if any.
    public private(set) var expandedBook: Int?

    public init(books: [Versification.Book]) { self.books = books }

    /// Opening a book closes the one that was open; tapping the open book closes it; a book of one chapter goes straight
    /// to its verses and leaves the open book as it was.
    public mutating func tapBook(_ index: Int) -> Action {
        if books[index].chapterCount == 1 { return .showVerses(book: index, chapter: 1) }
        if expandedBook == index {
            expandedBook = nil
            return .collapse(book: index)
        }
        expandedBook = index
        return .expand(book: index)
    }

    /// The chapters shown under a book: all of them when it is open, none otherwise.
    public func chapterCount(ofBook index: Int) -> Int {
        index == expandedBook ? books[index].chapterCount : 0
    }

    /// The testament whose title heads this book: set on the first book of each testament, nil on the others.
    public func testamentStarting(atBook index: Int) -> Versification.Testament? {
        let testament = books[index].testament
        return index == 0 || books[index - 1].testament != testament ? testament : nil
    }
}

/// The number grids' geometry, in points: five columns on a phone, more where there is room; square cells.
public enum BookNavigatorGrid {
    public static let minimumColumns = 5
    public static let minimumCellWidth = 72.0
    public static let spacing = 8.0

    public static func columns(forWidth width: Double) -> Int {
        max(minimumColumns, Int(width / minimumCellWidth))
    }

    /// The side of a square cell when `columns` cells and the spaces between them fill `width`.
    public static func cellSide(forWidth width: Double, columns: Int) -> Double {
        max(1.0, ((width - spacing * Double(columns - 1)) / Double(columns)).rounded(.down))
    }

    public static func rows(forCount count: Int, columns: Int) -> Int {
        (count + columns - 1) / columns
    }
}
