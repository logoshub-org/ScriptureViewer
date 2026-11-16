// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// What a tap on scripture text means, as data (plan D38, D56, D58). The viewer finds what lies
// under the finger and reports it as a `TapTarget`: a kind and a key, plus where it happened.
// It never decides what to do about it. The host's `TapResolver` does, and answers with a
// `TapResponse`: show a detail pane, go to a passage, open a URL, or nothing. The kind is an
// open string, so a Strong's number, a morphology code, a footnote, a verse number, a
// dictionary link or a commentary request all travel the same way and a new kind needs no change
// in the viewer.

import Foundation

/// What sort of thing was tapped. Open: any module or host may define its own.
public struct TapKind: RawRepresentable, Hashable, Sendable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// A Strong's number; the key is `G3056` or `H07225`.
    public static let strongs = TapKind(rawValue: "strongs")
    /// A morphology code; the key is `scheme:code`, e.g. `robinson:T-NSF`.
    public static let morph = TapKind(rawValue: "morph")
    /// A footnote; the key is the note's id (see `ScriptureText.notes`).
    public static let footnote = TapKind(rawValue: "footnote")
    /// A cross-reference note.
    public static let crossReference = TapKind(rawValue: "crossReference")
    /// A reference to scripture; the key is an OSIS or SWORD reference, `work` names the module.
    public static let scripture = TapKind(rawValue: "scripture")
    /// A link to another entry (`sword://Work/Key`); `work` and `entry` are in `attributes`.
    public static let entry = TapKind(rawValue: "entry")
    /// A verse number; the key is the verse.
    public static let verse = TapKind(rawValue: "verse")
    /// A word with lexical data of its own (`lemma`, `morph` in `attributes`).
    public static let word = TapKind(rawValue: "word")
    /// Any other link; the key is the target as written.
    public static let link = TapKind(rawValue: "link")
}

/// Where in the text a tap fell.
public struct TapContext: Equatable, Sendable {
    /// UTF-16 offset of the character tapped.
    public var offset: Int
    /// The verse the offset lies in, when the text has verses.
    public var verse: Int?
    /// The word (its index in the verse) the offset lies in, when it has anchors.
    public var wordIndex: Int?
    /// The chapter this text is, when the host said.
    public var passage: PassageIdentity?

    public init(offset: Int, verse: Int? = nil, wordIndex: Int? = nil, passage: PassageIdentity? = nil) {
        self.offset = offset
        self.verse = verse
        self.wordIndex = wordIndex
        self.passage = passage
    }

    /// The durable name of the word tapped.
    public var wordReference: WordReference? {
        guard let passage, let verse, let wordIndex else { return nil }
        return WordReference(passage: passage, verse: verse, index: wordIndex)
    }
}

public struct TapTarget: Equatable, Sendable {
    public var kind: TapKind
    public var key: String
    /// Everything else the markup said about it: a link's work and entry, a word's lemma and
    /// morphology.
    public var attributes: [String: String]
    public var context: TapContext

    public init(kind: TapKind, key: String, attributes: [String: String] = [:], context: TapContext) {
        self.kind = kind
        self.key = key
        self.attributes = attributes
        self.context = context
    }
}

#if !SKIP
extension TapKind: Codable, ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.rawValue = value }
}
extension TapContext: Codable {}
extension TapTarget: Codable {}
#endif
