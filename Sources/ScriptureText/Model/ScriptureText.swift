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
//
// Order (`ScriptureTextModel.md` at the repository root): `spans` are always in start order (the longer first where two
// start together, else the order they were given), and `verses` and `words` in start order. The model keeps the spans in order
// itself, on every assignment, so a lookup by position can search instead of scanning: `tapTarget(atUTF16Offset:)` and the verse
// and word lookups. `verses` and `words` are put in order when the text is made; whoever changes them afterwards keeps the order.

import Foundation

public struct ScriptureText: Equatable, Sendable {
    /// The whole chapter or entry as plain text; "\n" separates paragraphs.
    public var text: String
    /// Half-open UTF-16 ranges carrying semantic attributes, in start order (longer first where two start together). Assigning
    /// puts them in that order.
    public var spans: [Span] {
        get { orderedSpans }
        set {
            orderedSpans = ScriptureText.ordered(newValue)
            tapReach = ScriptureText.tapReach(of: orderedSpans)
        }
    }
    /// The spans, in order; `spans` reads and writes them.
    private var orderedSpans: [Span]
    /// For each span, the furthest end reached by a span a tap can land on (`isTappable`), among it and the spans before it; -1
    /// where there is none yet. A tap's search walks back from the spans that start before the offset only while this reaches
    /// past it, so spans that overlap (a link over words, a word under a marker) are all found without reading every span.
    private var tapReach: [Int]
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
        let ordered = ScriptureText.ordered(spans)
        self.orderedSpans = ordered
        self.tapReach = ScriptureText.tapReach(of: ordered)
        self.verses = ScriptureText.versesInStartOrder(verses)
        self.notes = notes
        self.words = ScriptureText.wordsInStartOrder(words)
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
            // `self.verse`, not `verse`: in the Kotlin Skip makes of this, the parameter is named after its label and would hide
            // the property, so every verse up to the range's last would count as held.
            (self.verse...endVerse).contains(number)
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

// MARK: Order

extension ScriptureText {

    /// The spans in the model's order: by start, the longer first where two start together (an outer span before the ones inside
    /// it), else as given. Spans already in that order (what the builder makes) come back as they are, after one pass to check.
    public static func ordered(_ spans: [Span]) -> [Span] {
        if isOrdered(spans) { return spans }
        return spans.enumerated().sorted { a, b in
            if a.element.start != b.element.start { return a.element.start < b.element.start }
            if a.element.length != b.element.length { return a.element.length > b.element.length }
            return a.offset < b.offset
        }.map { $0.element }
    }

    /// Whether the spans are in the model's order.
    public static func isOrdered(_ spans: [Span]) -> Bool {
        var index = 1
        while index < spans.count {
            let before = spans[index - 1]
            let span = spans[index]
            if span.start < before.start || (span.start == before.start && span.length > before.length) { return false }
            index += 1
        }
        return true
    }

    /// Whether a tap can land on a span of this kind (`tapTarget(atUTF16Offset:)`).
    static func isTappable(_ attribute: Attribute) -> Bool {
        switch attribute {
        case .strongs, .morph, .footnote, .link, .verseNumber, .word: return true
        default: return false
        }
    }

    static func tapReach(of spans: [Span]) -> [Int] {
        var reach: [Int] = []
        reach.reserveCapacity(spans.count)
        var furthest = -1
        for span in spans {
            if isTappable(span.attribute) { furthest = max(furthest, span.start + span.length) }
            reach.append(furthest)
        }
        return reach
    }

    /// The furthest end a tappable span reaches among the spans up to `index` (`tapReach`).
    func tapReach(at index: Int) -> Int { tapReach[index] }

    /// The verse ranges in start order (as given when they are already). Named apart from the words' one: the JVM, which Kotlin runs
    /// on, erases the element type, and two `inStartOrder` would clash there.
    static func versesInStartOrder(_ verses: [VerseRange]) -> [VerseRange] {
        var index = 1
        while index < verses.count {
            if verses[index].start < verses[index - 1].start {
                return verses.enumerated().sorted { a, b in
                    a.element.start != b.element.start ? a.element.start < b.element.start : a.offset < b.offset
                }.map { $0.element }
            }
            index += 1
        }
        return verses
    }

    /// The word anchors in start order (as given when they are already).
    static func wordsInStartOrder(_ words: [WordAnchor]) -> [WordAnchor] {
        var index = 1
        while index < words.count {
            if words[index].start < words[index - 1].start {
                return words.enumerated().sorted { a, b in
                    a.element.start != b.element.start ? a.element.start < b.element.start : a.offset < b.offset
                }.map { $0.element }
            }
            index += 1
        }
        return words
    }

    /// The index of the last of `count` items, in start order, that starts at or before `offset`; -1 when none does. A binary
    /// search: `start(i)` is the start of item `i`.
    static func lastIndex(startingAtOrBefore offset: Int, count: Int, start: (Int) -> Int) -> Int {
        var low = 0
        var high = count - 1
        var found = -1
        while low <= high {
            let middle = (low + high) / 2
            if start(middle) <= offset {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return found
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
extension ScriptureText: Codable {
    private enum CodingKeys: String, CodingKey { case text, spans, verses, notes, words, identity }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(text: try container.decode(String.self, forKey: .text),
                  spans: try container.decode([Span].self, forKey: .spans),
                  verses: try container.decode([VerseRange].self, forKey: .verses),
                  notes: try container.decode([Note].self, forKey: .notes),
                  words: try container.decode([WordAnchor].self, forKey: .words),
                  identity: try container.decodeIfPresent(PassageIdentity.self, forKey: .identity))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(spans, forKey: .spans)
        try container.encode(verses, forKey: .verses)
        try container.encode(notes, forKey: .notes)
        try container.encode(words, forKey: .words)
        try container.encodeIfPresent(identity, forKey: .identity)
    }
}
extension ScriptureText.Span: Codable {}
extension ScriptureText.Attribute: Codable {}
#endif
