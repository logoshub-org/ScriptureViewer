// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Which passage a ScriptureText is, and a durable name for one word of it
// (plan D35, D41). The package knows no versification rules and does not look
// anything up: the host, which owns the module and its scheme, says what it
// loaded, and the identity travels with the text into every callback so saved
// highlights and notes cannot be attached to the wrong verse numbering.

/// The chapter a `ScriptureText` was built from.
public struct PassageIdentity: Hashable, Sendable, Codable {
    /// The work or module id, e.g. "KJV".
    public var work: String
    /// The verse numbering scheme the verse numbers follow, e.g. "KJV", "LXX",
    /// "NRSVA". The same chapter number can hold different verses under
    /// different schemes, so saved data must carry this.
    public var versification: String
    /// OSIS book id, e.g. "Gen".
    public var book: String
    /// The chapter, or nil for content that is not a chapter (an introduction).
    public var chapter: Int?

    public init(work: String, versification: String, book: String, chapter: Int?) {
        self.work = work
        self.versification = versification
        self.book = book
        self.chapter = chapter
    }
}

/// A durable name for one word: where saved highlights, notes and word
/// selections point. Independent of display options, fonts and offsets.
public struct WordReference: Hashable, Sendable, Codable {
    public var passage: PassageIdentity
    public var verse: Int
    /// Position in the verse, counted from 0 (`ScriptureText.WordAnchor.index`).
    public var index: Int

    public init(passage: PassageIdentity, verse: Int, index: Int) {
        self.passage = passage
        self.verse = verse
        self.index = index
    }

    /// The verse as an OSIS reference, e.g. "Gen.1.1". Nil without a chapter.
    public var osisVerse: String? {
        passage.chapter.map { "\(passage.book).\($0).\(verse)" }
    }
}

extension ScriptureText {

    /// The reference for an anchor of this text, or nil if the text has no
    /// identity (it was parsed without one).
    public func reference(for anchor: WordAnchor) -> WordReference? {
        identity.map { WordReference(passage: $0, verse: anchor.verse, index: anchor.index) }
    }

    /// The anchor a saved reference points at in this text, or nil if the
    /// reference belongs to another passage (different work, versification,
    /// book or chapter) or the word is not present under the current options.
    public func anchor(for reference: WordReference) -> WordAnchor? {
        guard reference.passage == identity else { return nil }
        // Anchors are usually in verse order with ascending indexes: binary search by (verse, index).
        var low = 0, high = words.count
        while low < high {
            let mid = (low + high) / 2
            let w = words[mid]
            if (w.verse, w.index) < (reference.verse, reference.index) { low = mid + 1 } else { high = mid }
        }
        if low < words.count, words[low].verse == reference.verse, words[low].index == reference.index {
            return words[low]
        }
        // A text whose verses are not in order (a reader's edition that moves a verse, USFM `\v 15b` after 21).
        return words.first { $0.verse == reference.verse && $0.index == reference.index }
    }
}
