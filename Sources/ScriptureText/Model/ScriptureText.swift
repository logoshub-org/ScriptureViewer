// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// The portable scripture text model (plan §4, D31): one plain string plus
// semantic ranges. Spans carry meaning, never fonts or colours — the platform
// styler (ScriptureTextStyler on iOS; a Compose/Spannable mapping on Android)
// resolves them. All offsets are UTF-16 code units, which match both NSString
// and Kotlin String indexing.

import Foundation

public struct ScriptureText: Equatable, Sendable {
    /// The whole chapter or entry as plain text; "\n" separates paragraphs.
    public var text: String
    /// Half-open UTF-16 ranges carrying semantic attributes.
    public var spans: [Span]
    /// Verse number → range, for scroll-to-verse and position tracking.
    /// A verse's range starts at its verse-number marker and runs to the next
    /// verse's marker (trailing whitespace trimmed). Empty for content without
    /// verses (dictionary entries, "about" text …).
    public var verses: [VerseRange]
    /// Footnote bodies, referenced from `.footnote(id:)` spans. The body is
    /// not part of `text`; the span marks where its marker sits.
    public var notes: [Note]
    /// Every word of canonical text, in order (plan D35). Saved data
    /// (highlights, notes, selections) keys on `(verse, index)`, which does
    /// not move when display options change; offsets do.
    public var words: [WordAnchor]
    /// Which chapter this is, when the host said (plan D41). Needed to turn an
    /// anchor into a durable `WordReference`; nil for content that is not a
    /// chapter or when the host gave none.
    public var identity: PassageIdentity?

    public init(text: String = "", spans: [Span] = [], verses: [VerseRange] = [],
                notes: [Note] = [], words: [WordAnchor] = [], identity: PassageIdentity? = nil) {
        self.text = text
        self.spans = spans
        self.verses = verses
        self.notes = notes
        self.words = words
        self.identity = identity
    }

    public struct Note: Equatable, Sendable, Codable {
        public var id: String
        /// The note's text, whitespace-collapsed.
        public var text: String
        /// OSIS references the note cites (e.g. "Exod.25.5").
        public var references: [String]
        public var kind: Kind

        /// SWORD marks cross-reference notes "x" and everything else "n", and
        /// shows them under separate options.
        public enum Kind: String, Equatable, Sendable, Codable {
            case footnote, crossReference
        }

        public init(id: String, text: String, references: [String] = [], kind: Kind = .footnote) {
            self.id = id
            self.text = text
            self.references = references
            self.kind = kind
        }
    }

    public struct Span: Equatable, Sendable {
        public var start: Int
        public var length: Int
        public var attribute: Attribute

        public init(start: Int, length: Int, attribute: Attribute) {
            self.start = start
            self.length = length
            self.attribute = attribute
        }
    }

    public enum Attribute: Equatable, Sendable {
        /// A heading, poetry line, list item or other paragraph with a role.
        /// Ordinary prose paragraphs carry no span; "\n" alone separates them.
        case block(ParagraphRole)
        case verseNumber(Int)
        case redLetter
        case small
        case bold
        case italic
        /// A *marker* run showing a Strong's number (e.g. "<07225>"); the
        /// payload is the full lemma token ("strong:H07225").
        case strongs(String)
        /// A *marker* run showing a morphology code.
        case morph(String)
        /// A word carrying its lexical data (OSIS `<w lemma= morph=>`). The
        /// word's own text is styled normally; this makes it tappable.
        case word(lemma: String?, morph: String?)
        case footnote(id: String)
        case link(target: String)
        /// OSIS `<divineName>` — the divine name, conventionally small caps.
        case divineName
    }

    /// One verse of the text, or a bridge of several (USFM `\v 1-2`, plan D48, Track V2). `verse` is the first verse
    /// in either case, so word anchors, references, scrolling and highlights key on it as before.
    public struct VerseRange: Equatable, Sendable, Codable {
        public var verse: Int
        public var start: Int
        public var length: Int
        /// The last verse of a bridge (2 for `1-2`); nil for a single verse.
        public var lastVerse: Int?
        /// The number as printed where it is not just `verse` or the bridge: a published number (USFM `\vp`), or a part
        /// such as "3a". Nil to print the number.
        public var label: String?

        public init(verse: Int, start: Int, length: Int, lastVerse: Int? = nil, label: String? = nil) {
            self.verse = verse
            self.start = start
            self.length = length
            self.lastVerse = lastVerse.flatMap { $0 > verse ? $0 : nil }
            self.label = label
        }

        /// The last verse the range holds: `lastVerse` for a bridge, otherwise `verse`.
        public var endVerse: Int { lastVerse ?? verse }

        /// Whether the range holds this verse (any verse of a bridge).
        public func contains(verse number: Int) -> Bool {
            (verse...endVerse).contains(number)
        }

        /// The number to show: the label, the bridge ("1-2") or the verse.
        public var displayNumber: String {
            label ?? (lastVerse.map { "\(verse)-\($0)" } ?? String(verse))
        }
    }

    /// The verse range that holds this verse: the verse itself, the bridge it is part of, or its first part when it
    /// comes in parts (USFM `\v 14a` … `\v 14b`: two ranges with verse 14).
    public func verseRange(containing verse: Int) -> VerseRange? {
        verses.first { $0.contains(verse: verse) }
    }

    /// One word of canonical text: its verse, its position in the verse
    /// (from 0) and its UTF-16 range, without surrounding punctuation.
    public struct WordAnchor: Equatable, Sendable, Codable {
        public var verse: Int
        public var index: Int
        public var start: Int
        public var length: Int

        public init(verse: Int, index: Int, start: Int, length: Int) {
            self.verse = verse
            self.index = index
            self.start = start
            self.length = length
        }
    }

    /// The substring for a UTF-16 range, e.g. a verse's text.
    public func substring(utf16Start start: Int, length: Int) -> String? {
        #if SKIP
        // SKIP INSERT: if (start < 0 || length < 0 || start + length > text.length) return null
        // SKIP INSERT: return text.substring(start, start + length)
        return nil
        #else
        let u = text.utf16
        guard start >= 0, length >= 0, start + length <= u.count,
              let from = u.index(u.startIndex, offsetBy: start, limitedBy: u.endIndex),
              let to = u.index(from, offsetBy: length, limitedBy: u.endIndex)
        else { return nil }
        return String(text[from..<to])
        #endif
    }
}

extension ScriptureText {
    /// The text with `heading` on a line of its own above it, as a section heading: a dictionary entry under its word.
    /// Everything that points into the text moves down by the heading's length.
    public func prependingHeading(_ heading: String, role: ParagraphRole = .s1) -> ScriptureText {
        let heading = trimmedWhitespace(heading)
        guard !heading.isEmpty else { return self }
        let shift = heading.utf16.count + 1
        var result = self
        result.text = heading + "\n" + text
        result.spans = [Span(start: 0, length: heading.utf16.count, attribute: .block(role))]
            + spans.map { Span(start: $0.start + shift, length: $0.length, attribute: $0.attribute) }
        result.verses = verses.map { var verse = $0; verse.start += shift; return verse }
        result.words = words.map { WordAnchor(verse: $0.verse, index: $0.index, start: $0.start + shift, length: $0.length) }
        return result
    }
}

// Skip's transpiler synthesises Codable only for enums with raw values, so the model's Codable (a convenience of the iOS side) is
// compiled out of the transpiled build.
#if !SKIP
extension ScriptureText: Codable {}
extension ScriptureText.Span: Codable {}
extension ScriptureText.Attribute: Codable {}
#endif
