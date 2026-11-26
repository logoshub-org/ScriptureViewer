// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// The format-neutral half of building a ScriptureText (plan Track V3), shared by the OSIS and USFM builders, which
// decide what their markup means and call this to write it:
//
//  • whitespace collapses over the four markup whitespace characters only; U+3000, U+00A0, ZWNJ, RLM and combining
//    marks are content and are never touched;
//  • breaks are settled lazily, at the next content: a block break is a new line, and two counted line breaks in a
//    row (SWORD's `<br />`) make a blank line, except straight after a heading, which carries its own space;
//  • a verse's marker is written at its first content, after any headings and breaks, as its printed number (a
//    bridge prints "1-2", plan D48);
//  • spans start lazily, at the first content, so a span never swallows a pending break or the verse marker; block
//    spans start before the verse marker (a poetry line holds its number), inline spans after it;
//  • every canonical word gets a (verse, index) anchor whose index does not depend on display options (D35);
//  • a footnote marker is joined to its word, and to punctuation glued after it, with U+2060 WORD JOINER (D37).

import ScriptureText

///
/// A class, not a struct: each parse has one builder, owned by its format's builder and never copied. As a struct it cost nothing in
/// Swift, but in the Kotlin that Skip makes of this every read of a struct-typed property is a copy, so each call from the OSIS
/// builder copied this whole value there and back (found by profiling the transpiled parser; see the speed rules in Transpile/README.md).
public final class ScriptureTextBuilder {

    public struct Options: Sendable, Equatable {
        /// Show the verse number at the start of each verse.
        public var verseNumbers = true
        /// Start every verse on its own line.
        public var versePerLine = false
        /// Insert marker runs such as `<07225>` after Strong's-tagged words.
        public var strongsMarkers = false
        /// Insert marker runs for morphology codes.
        public var morphMarkers = false

        public init() {}
    }

    /// A span opened with `openSpan`, which starts at the next content.
    public struct SpanHandle: Hashable, Sendable {
        fileprivate let id: Int
    }

    public let options: Options

    // Output
    private let text = TextBuffer()
    /// The text written so far, in UTF-16 code units.
    public private(set) var length = 0
    /// Where the last text outside a heading ended: a verse that a heading follows ends here (USFM puts a section
    /// heading before the next `\v`, so the heading is not part of the verse before it).
    public private(set) var contentEnd = 0
    private let spans = GrowingList<ScriptureText.Span>()
    private let verses = GrowingList<ScriptureText.VerseRange>()
    private let notes = GrowingList<ScriptureText.Note>()
    private let words = GrowingList<ScriptureText.WordAnchor>()

    // Whitespace and breaks
    private var endsWithNewline = true
    private var lastScalar: Int?
    private var needsBreak = false
    /// Counted line breaks since the last content; two or more make a blank line.
    private var breakCount = 0
    /// Where the last heading ended: no blank line is added right after one.
    private var lastHeadingEnd = -1
    private var pendingSpace = false
    private var lastAppendWasFootnoteMarker = false
    /// The note just closed ended in whitespace: some modules (the WEB apocrypha, 65 notes) keep the space after a
    /// note *inside* it.
    private var spaceAfterNote = false

    // Verses
    private var pendingVerse: Int?               // marker not yet written
    /// The verse being written; nil before the first and after `endVerse`. Verse 0 is an introduction.
    public private(set) var currentVerse: Int?
    private var currentLastVerse: Int?
    private var currentLabel: String?
    private var verseStart: Int?
    /// The next word index of each verse begun so far: a later part of a verse (USFM `\v 14b`, wherever it comes
    /// after `\v 14a`) goes on counting its words.
    private var nextWordIndex: [Int: Int] = [:]

    // Lazily started spans
    private var nextSpan = 0
    private var waitingBlock: [Int] = []
    private var waitingInline: [Int] = []
    private var spanStarts: [Int: Int] = [:]

    // What the format is inside
    /// Inside a heading: a verse's marker waits until after it.
    public var headingDepth = 0
    /// Inside editorial content (a heading that is not Bible text): no word anchors.
    public var editorialDepth = 0
    /// Inside a tagged word (`<w>`, `\w`): an ideograph there is not a word of its own.
    public var wordDepth = 0

    // The footnote being captured; its text never enters the main text.
    private var activeNote: ActiveNote?

    // Word anchors (D35)
    private var wordIndex = 0                    // next index in the current verse
    private var extendable: Int?                 // the anchor glued text extends
    private var glue = false                     // no word boundary since the last word

    public init(options: Options) {
        self.options = options
    }

    // MARK: Verses

    /// Starts a verse: `number` to `lastVerse` for a bridge, printed as `label` when given. Verse 0 (an
    /// introduction) gets no marker and no range. A later part of a verse already begun (`14b` after `14a`, even with
    /// other verses between, as reader's editions reorder them) gets a range of its own, and its words go on from the
    /// earlier part's, so each word of the verse has one index.
    public func beginVerse(_ number: Int, lastVerse: Int? = nil, label: String? = nil) {
        endVerse()
        currentVerse = number
        currentLastVerse = lastVerse
        currentLabel = label
        verseStart = nil
        pendingVerse = number > 0 ? number : nil
        if length > 0 {
            // Verses are separated by a space, or by a line when "verse per line" is on.
            if options.versePerLine { needsBreak = true; glue = false } else { pendingSpace = true }
        }
        wordIndex = number > 0 ? nextWordIndex[number] ?? 0 : 0
        extendable = nil
        glue = false
    }

    /// Ends the current verse's range at the text written so far, or at `end` (see `contentEnd`).
    public func endVerse(at end: Int? = nil) {
        guard let verse = currentVerse, verse > 0 else { currentVerse = nil; return }
        let start = verseStart ?? length         // an empty verse still gets a (zero-length) range
        let finish = max(min(end ?? length, length), start)
        verses.append(ScriptureText.VerseRange(verse: verse, start: start, length: finish - start,
                            lastVerse: currentLastVerse, label: currentLabel))
        nextWordIndex[verse] = wordIndex
        currentVerse = nil
        currentLastVerse = nil
        currentLabel = nil
        pendingVerse = nil
        verseStart = nil
    }

    // MARK: Spans

    /// Opens a span that starts at the next content: a block span (a paragraph role) before the verse marker, an
    /// inline one after it.
    public func openSpan(block: Bool) -> SpanHandle {
        nextSpan += 1
        if block { waitingBlock.append(nextSpan) } else { waitingInline.append(nextSpan) }
        return SpanHandle(id: nextSpan)
    }

    /// Closes a span and records it with `attribute`, unless it is empty or `attribute` is nil. Returns where it
    /// started, or nil if no content was written inside it.
    @discardableResult
    public func closeSpan(_ handle: SpanHandle, as attribute: ScriptureText.Attribute?) -> Int? {
        guard let start = spanStarts.removeValue(forKey: handle.id) else {
            if let index = waitingInline.lastIndex(of: handle.id) { waitingInline.remove(at: index) }
            else if let index = waitingBlock.lastIndex(of: handle.id) { waitingBlock.remove(at: index) }
            return nil
        }
        if let attribute, length > start {          // empty elements make no span
            spans.append(ScriptureText.Span(start: start, length: length - start, attribute: attribute))
        }
        return start
    }

    // MARK: Breaks

    /// The next content starts on a new line.
    public func blockBreak() {
        needsBreak = true
        glue = false
    }

    /// A line break that counts towards a blank line when `counted` (a paragraph boundary or a line end; SWORD's
    /// `<br />`); two in a row make one.
    public func lineBreak(counted: Bool = true) {
        blockBreak()
        if counted { breakCount += 1 }
    }

    /// A shown heading carries its own space: the breaks counted before it make no blank line.
    public func clearBreakCount() {
        breakCount = 0
    }

    /// A heading ended here.
    public func markHeadingEnd() {
        lastHeadingEnd = length
    }

    // MARK: Text

    /// Whitespace that markup ignores: space, tab, CR, LF.
    public static func isMarkupSpace(_ s: Int) -> Bool {
        s == 0x20 || s == 0x09 || s == 0x0A || s == 0x0D
    }


    /// Whether `raw` has anything but markup whitespace.
    public static func hasContent(_ raw: String) -> Bool {
        for scalar in CodePoints.of(raw) where !isMarkupSpace(scalar) { return true }
        return false
    }

    /// The next text starts a new word.
    public func wordBoundary() {
        glue = false
    }

    /// Appends text, collapsing runs of markup whitespace (space, tab, CR, LF) and nothing else.
    public func emit(_ raw: String) {
        var run: [Int] = []
        for scalar in CodePoints.of(raw) {
            if Self.isMarkupSpace(scalar) {
                if !run.isEmpty { appendRun(&run) }
                pendingSpace = true
                glue = false
            } else {
                run.append(scalar)
            }
        }
        if !run.isEmpty { appendRun(&run) }
    }

    /// Words inside a hidden reading (a dropped variant, a canonical title with headings off) still take their
    /// indexes, so indexes do not depend on display options. They get no range.
    public func countHiddenWords(_ raw: String) {
        var run: [Int] = []
        for scalar in CodePoints.of(raw) {
            if Self.isMarkupSpace(scalar) {
                if !run.isEmpty { consumeWords(run, at: nil); run = [] }
                glue = false
            } else {
                run.append(scalar)
            }
        }
        if !run.isEmpty { consumeWords(run, at: nil) }
    }

    /// Marker runs after a word, exactly as SWORD's OSIS filters print them (osisxhtml.cpp `processLemma` /
    /// `processMorph`): one `<n>` per lemma token, with a leading G/H dropped when a digit follows; one `(code)` per
    /// morph token, with a leading TG/TH dropped when a digit follows (`strongMorph:TH8799` → `(8799)`). Lemma
    /// tokens with no scheme or a `lemma.` scheme (`lemma.TR:και`) are the "Lemmas" option's, which the app leaves
    /// off, so SWORD's `OSISLemma` filter removes them first.
    public func emitWordMarkers(lemma: String?, morph: String?) {
        if options.strongsMarkers, let lemma {
            for token in CodePoints.split(lemma, separator: " ") where Self.isStrongsLemma(token) {
                var value = Self.valueAfterScheme(token)
                let chars = CodePoints.characters(value)
                if chars.count > 1, chars[0] == "G" || chars[0] == "H", isDigit(chars[1]) {
                    value = CodePoints.string(chars: chars, 1, chars.count)
                }
                emitMarker("<\(value)>", .strongs(token))
            }
        }
        if options.morphMarkers, let morph {
            for token in CodePoints.split(morph, separator: " ") {
                var value = Self.valueAfterScheme(token)
                let chars = CodePoints.characters(value)
                if chars.count >= 3, chars[0] == "T", chars[1] == "G" || chars[1] == "H", isDigit(chars[2]) {
                    value = CodePoints.string(chars: chars, 2, chars.count)
                }
                emitMarker("(\(value))", .morph(token))
            }
        }
    }

    // MARK: Footnotes

    /// Inside a note: text goes to the note, not the main text.
    public var inNote: Bool { activeNote != nil }

    /// Starts capturing a note. A note is a word boundary.
    public func beginNote() {
        glue = false
        activeNote = ActiveNote(text: "", references: [], spaced: false)
    }

    /// Note text, whitespace-collapsed.
    public func appendToNote(_ raw: String) {
        guard let note = activeNote else { return }
        // Gathered a run of non-space at a time, not a character at a time (each `+=` on a Kotlin string copies it).
        var run: [Int] = []
        for scalar in CodePoints.of(raw) {
            if Self.isMarkupSpace(scalar) {
                if !run.isEmpty { note.text += CodePoints.string(run); run = [] }
                note.spaced = true
            } else {
                if run.isEmpty, note.spaced, !note.text.isEmpty { note.text += " " }
                note.spaced = false
                run.append(scalar)
            }
        }
        if !run.isEmpty { note.text += CodePoints.string(run) }
    }

    /// A reference the note cites (e.g. "Exod.25.5").
    public func addNoteReference(_ reference: String) {
        activeNote?.references.append(reference)
    }

    /// Ends the note. When `show` is true and it has text or references, it is recorded and its marker ("n", or "x"
    /// for a cross-reference) is written, joined to the word before it.
    public func finishNote(id: String, kind: ScriptureText.Note.Kind, show: Bool) {
        guard let note = activeNote else { return }
        activeNote = nil
        glue = false                             // a note is a word boundary
        defer { spaceAfterNote = note.spaced }   // set last: writing the marker clears it
        guard show, !note.text.isEmpty || !note.references.isEmpty else { return }
        notes.append(ScriptureText.Note(id: id, text: note.text, references: note.references, kind: kind))

        beginContent(allowVerseMarker: true)
        // D37: the marker is joined to the word before it, never after a space.
        if length > 0, let last = lastScalar, !Self.isMarkupSpace(last) {
            append("\u{2060}")
        }
        let start = length
        append(kind == .crossReference ? "x" : "n")
        spans.append(ScriptureText.Span(start: start, length: length - start, attribute: ScriptureText.Attribute.footnote(id: id)))
        lastAppendWasFootnoteMarker = true
        extendable = nil
    }

    /// Drops the note being captured (it was inside a hidden reading).
    public func discardNote() {
        activeNote = nil
        glue = false
    }

    // MARK: Finish

    public func finish() -> ScriptureText {
        endVerse()
        // The model puts the spans in its order (outer spans first where two start together, ScriptureText.ordered).
        return ScriptureText(text: text.text, spans: spans.elements(), verses: verses.elements(), notes: notes.elements(), words: words.elements())
    }

    // MARK: Writing

    private func append(_ s: String) {
        guard !s.isEmpty else { return }
        text.append(s)
        length += CodePoints.utf16Length(s)
        lastScalar = CodePoints.last(s)
        endsWithNewline = lastScalar == 0x0A
        if headingDepth == 0 { contentEnd = length }
        lastAppendWasFootnoteMarker = false
        spaceAfterNote = false
    }

    private func flushPending() {
        if needsBreak {
            let afterHeading = length == lastHeadingEnd
            if length > 0 && !endsWithNewline { append("\n") }
            if breakCount >= 2, length > 0, !afterHeading { append("\n") }
            needsBreak = false
            breakCount = 0
            pendingSpace = false
        } else if pendingSpace {
            if length > 0 && !endsWithNewline { append(" ") }
            pendingSpace = false
        }
    }

    /// Called before any content is appended. Settles breaks, starts block spans (so a poetry line or list item
    /// includes its verse marker), writes the pending verse marker, then starts inline spans (so words do not).
    private func beginContent(allowVerseMarker: Bool) {
        flushPending()
        startWaiting(block: true)
        if allowVerseMarker && headingDepth == 0 { emitVerseMarkerIfPending() }
        startWaiting(block: false)
    }

    private func startWaiting(block: Bool) {
        if block {
            guard !waitingBlock.isEmpty else { return }
            for id in waitingBlock { spanStarts[id] = length }
            waitingBlock.removeAll(keepingCapacity: true)
        } else {
            guard !waitingInline.isEmpty else { return }
            for id in waitingInline { spanStarts[id] = length }
            waitingInline.removeAll(keepingCapacity: true)
        }
    }

    private func emitVerseMarkerIfPending() {
        guard let verse = pendingVerse else { return }
        pendingVerse = nil
        verseStart = length
        guard options.verseNumbers else { return }
        let marker = currentLabel ?? (currentLastVerse.map { "\(verse)-\($0)" } ?? String(verse))
        let start = length
        append(marker)
        spans.append(ScriptureText.Span(start: start, length: length - start, attribute: ScriptureText.Attribute.verseNumber(verse)))
    }

    private func appendRun(_ run: inout [Int]) {
        if spaceAfterNote, let first = run.first, !Self.isPunctuation(first) {
            pendingSpace = true                  // the space that was kept inside the note
        }
        spaceAfterNote = false
        beginContent(allowVerseMarker: true)
        // D37: punctuation glued after a footnote marker stays with it.
        if lastAppendWasFootnoteMarker, let first = run.first, Self.isPunctuation(first) {
            append("\u{2060}")
        }
        let start = length
        append(CodePoints.string(run))
        consumeWords(run, at: start)
        run = []
    }

    /// A marker run (Strong's number, morph code) with its own span. A marker inside a word ends its anchor's range:
    /// text glued after the marker (`God<2316>'s`) keeps the word's index but is not covered, so a range never
    /// includes marker text and the index stays option-independent.
    private func emitMarker(_ marker: String, _ attribute: ScriptureText.Attribute) {
        beginContent(allowVerseMarker: true)
        let start = length
        append(marker)
        spans.append(ScriptureText.Span(start: start, length: length - start, attribute: attribute))
        extendable = nil
    }

    // MARK: Word anchors (D35)

    /// Canonical text in a numbered verse: not a heading, not a note.
    private var anchorsWords: Bool {
        (currentVerse ?? 0) > 0 && editorialDepth == 0 && activeNote == nil
    }

    /// Segments one run of non-whitespace text into words and records an anchor for each (or only counts them,
    /// when `start` is nil). A run glued to the previous word extends it, unless it starts with an ideograph;
    /// Unicode space separators and em/en dashes split words; an ideograph outside a tagged word is a word of its
    /// own; punctuation, symbols and format characters at a word's edges are not part of it.
    private func consumeWords(_ run: [Int], at start: Int?) {
        guard anchorsWords else { glue = false; return }
        var position = start ?? 0
        var coreStart: Int?                  // first core scalar of the current segment
        var coreEnd = 0
        var continuing = glue                // only the first segment may continue a word
        var endedOnBoundary = false

        func closeSegment() {
            defer { coreStart = nil; continuing = false }
            guard let from = coreStart else { return }       // punctuation only: no word
            if continuing {
                if start != nil, let e = extendable {
                    var word = words[e]
                    word.length = coreEnd - word.start
                    words[e] = word
                }
                return                                       // same word, same index
            }
            if start != nil, let verse = currentVerse {
                words.append(ScriptureText.WordAnchor(verse: verse, index: wordIndex, start: from, length: coreEnd - from))
                extendable = words.count - 1
            } else {
                extendable = nil
            }
            wordIndex += 1
        }

        for scalar in run {
            let width = scalar > 0xFFFF ? 2 : 1
            if Self.isWordSeparator(scalar) {
                closeSegment()
                endedOnBoundary = true
            } else if wordDepth == 0, CodePoints.isIdeographic(scalar) {
                closeSegment()
                coreStart = position
                coreEnd = position + width
                closeSegment()
                endedOnBoundary = true
            } else {
                endedOnBoundary = false
                if !Self.isEdgeTrimmed(scalar) {
                    if coreStart == nil { coreStart = position }
                    coreEnd = position + width
                }
            }
            position += width
        }
        let lastWasWord = coreStart != nil || (continuing && !endedOnBoundary)
        closeSegment()
        glue = lastWasWord && !endedOnBoundary
    }

    /// Splits words without being part of one: Unicode space separators (U+3000, U+00A0 …), em/en dashes and the
    /// Hebrew maqaf.
    private static func isWordSeparator(_ s: Int) -> Bool {
        switch s {
        case 0x2012...0x2015, 0x2E3A, 0x2E3B: return true
        case 0x05BE: return true            // Hebrew maqaf: joins words in speech, but each is its own word
        default: return CodePoints.isSpaceSeparator(s)
        }
    }

    /// Punctuation, symbols and format characters: trimmed from a word's edges.
    private static func isEdgeTrimmed(_ s: Int) -> Bool {
        CodePoints.isPunctuation(s) || CodePoints.isSymbol(s) || CodePoints.isFormat(s)
    }

    private static func isPunctuation(_ s: Int) -> Bool { CodePoints.isPunctuation(s) }

    /// Kept by SWORD's OSISLemma filter when the Lemmas option is off: a token with a scheme that does not start
    /// with "lemma.".
    private static func isStrongsLemma(_ token: String) -> Bool {
        guard colonIndex(token) != nil else { return false }
        return !token.hasPrefix("lemma.")
    }

    /// The part of a `scheme:value` token after the first colon, or the whole token.
    private static func valueAfterScheme(_ token: String) -> String {
        guard let colon = colonIndex(token) else { return token }
        let chars = CodePoints.characters(token)
        return CodePoints.string(chars: chars, colon + 1, chars.count)
    }

    private static func colonIndex(_ token: String) -> Int? {
        var k = 0
        for ch in token {
            if ch == ":" { return k }
            k += 1
        }
        return nil
    }
}

/// The note being captured. A class for the reason the builder is one: it is changed in place, a character run at a time.
private final class ActiveNote {
    var text: String
    var references: [String]
    var spaced: Bool

    init(text: String, references: [String], spaced: Bool) {
        self.text = text
        self.references = references
        self.spaced = spaced
    }
}
