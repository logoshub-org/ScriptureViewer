// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Which of a chapter's stored entries are shown (plan D50). SWORD has no
// "read a chapter" call: a host steps the module's key through the chapter and
// gets one entry per verse. The app's reader has always dropped two kinds, so a
// native reader fed from the same entries must too, or it would differ from the
// web view for reasons that have nothing to do with rendering:
//
//   - an entry with no content (nothing but whitespace);
//   - an entry identical to the one before it. Verse numbers are not renumbered:
//     the verse that was dropped simply has no marker, as in the web view.

public enum ChapterEntries {

    public struct Entry: Equatable, Sendable {
        public var verse: Int
        public var text: String

        public init(verse: Int, text: String) {
            self.verse = verse
            self.text = text
        }
    }

    /// The entries to parse, in order. The comparison is on the entry text after its
    /// leading whitespace is removed, and "previous" means the previous entry read,
    /// shown or not (so an empty entry between two equal ones lets both through,
    /// as in the app's loop).
    public static func shown(_ entries: [Entry]) -> [Entry] {
        var result: [Entry] = []
        var previous = ""
        for entry in entries {
            // Over code points, not `String(text.drop { $0.isWhitespace })`: in the Kotlin Skip makes of that, `drop` gives a list
            // of characters, not a string, so a repeated entry was never found and Android showed it twice.
            let codes = CodePoints.of(entry.text)
            var first = 0
            while first < codes.count && CodePoints.isWhiteSpace(codes[first]) { first += 1 }
            let trimmed = first == 0 ? entry.text : CodePoints.string(codes, first, codes.count)
            defer { previous = trimmed }
            guard !trimmed.isEmpty, trimmed != previous else { continue }
            result.append(.init(verse: entry.verse, text: entry.text))
        }
        return result
    }
}
