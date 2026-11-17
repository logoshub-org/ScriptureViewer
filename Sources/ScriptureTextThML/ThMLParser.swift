// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// ThML (Theological Markup Language, CCEL) entries (plan D46, step 8): the bundled Strong's
// "Real" dictionaries, devotionals, commentaries and general books are stored as an HTML-like
// dialect. The vocabulary in the modules in hand is `a b i br font sup sub q latin greek` and
// SWORD's own additions; the CCEL works add `div1`–`div3`, `h1`–`h6`, `p`, `scripRef`, `scripCom`,
// `note`, `table`, `pre`. The rules follow SWORD's ThML filter (`thmlhtml.cpp`) so the native
// view matches the web view:
//
//   b, strong      bold;  i, em, added  italic;  small  small text
//   br, hr         a line break;  p, blockquote, div, ul, ol, center  a break before and after
//   h1…h6          a heading (h1 major, h2 section, h3 and below subsection)
//   li             one paragraph per item (indented by nesting depth)
//   a href=        a link: `sword://Work/Key` is a dictionary link, `http(s)` a web link;
//                  `a name=` is an anchor and shows its text
//   scripRef       a scripture link: `osisRef` if given, otherwise `passage`
//   note           a footnote marker; the body is kept apart from the text; `type="x"` is a
//                  cross-reference note
//   sync           a Strong's or morphology marker, when those options are on
//   table, tr, td  one line per row, cells apart by a space
//   head, script, style, ThML.head   not shown
//   anything else  its text, unchanged
//
// Text is whitespace-collapsed as a browser would, so a line end is a space and only the
// elements above break lines.

import Foundation
import ScriptureText
import ScriptureTextMarkup

public struct ThMLParser: Sendable {

    public struct Options: Sendable, Equatable {
        /// The module the entry belongs to: the work of a link that names none.
        public var module: String?
        public var transforms = TextTransforms()
        public var footnotes = true
        public var strongs = false
        public var morphology = false

        public init(module: String? = nil) { self.module = module }
    }

    public var options: Options
    public var profile: ScriptureContentProfile

    public init(options: Options = Options(), profile: ScriptureContentProfile = .dictionary) {
        self.options = options
        self.profile = profile
    }

    /// One entry: a dictionary article, a devotional, an "about" text, a whole work.
    /// Tolerant: unknown or unbalanced markup never fails the parse.
    public func parse(_ entry: String) -> ScriptureText {
        var builder = ThMLBuilder(options: options)
        MarkupTokenizer.tokenize(Self.clean(entry), into: &builder)
        return builder.finish()
    }

    /// A chapter of verse-keyed entries (a ThML commentary or Bible). Verse 0 is the
    /// introduction. With the commentary profile each verse starts with its number on a line of
    /// its own, as the web view shows it; with the chapter profile the number runs into the text.
    public func parse(_ entries: [ChapterEntries.Entry], identity: PassageIdentity? = nil) -> ScriptureText {
        var builder = ThMLBuilder(options: options)
        for entry in entries {
            if entry.verse > 0, profile.buildsVerseRanges {
                builder.beginVerse(entry.verse, numberOnOwnLine: profile == .commentary)
            }
            MarkupTokenizer.tokenize(Self.clean(entry.text), into: &builder)
        }
        var result = builder.finish()
        result.identity = identity
        return result
    }

    private static func clean(_ s: String) -> String { s.replacingOccurrences(of: "\u{0000}", with: "") }
}

// MARK: - Builder

struct ThMLBuilder: MarkupEventSink {

    private struct Frame {
        enum Kind {
            case plain
            case span(ScriptureText.Attribute)
            case block(ParagraphRole)
            case note(id: String, kind: ScriptureText.Note.Kind)
            case skipped
        }
        var name: String
        var kind: Kind
        var start: Int?
        var breaksAfter = false
        var paragraphAfter = false
        /// A `scripRef` with no `osisRef` or `passage` names its passage in its own text
        /// ("33:6; Ge 32:2"), as SWORD reads it.
        var passageFromText = false
        /// Where in an open note's text such a reference began.
        var noteOffset: Int?
    }

    private let options: ThMLParser.Options
    private let text = TextBuffer()
    private var length: Int { text.length }
    private let spans = GrowingList<ScriptureText.Span>()
    private let verses = GrowingList<ScriptureText.VerseRange>()
    private var openVerse: OpenVerse?
    private let notes = GrowingList<ScriptureText.Note>()
    private var stack: [Frame] = []
    private var unstarted = 0
    private var skipDepth = 0

    private var endsWithNewline = true
    private var needsBreak = false
    private var brCount = 0
    private var pendingSpace = false
    /// Just after a verse number: the first content follows it directly, or on the next line,
    /// whatever paragraph markup comes first.
    /// (true when the number is on a line of its own).
    private var holdBreaks: Bool?
    private var activeNote: NoteDraft?
    private var noteCount = 0

    init(options: ThMLParser.Options) { self.options = options }

    // MARK: Chapters

    mutating func beginVerse(_ verse: Int, numberOnOwnLine: Bool) {
        closeVerse()
        needsBreak = true
        brCount = min(brCount, 1)
        holdBreaks = nil
        beginContent()
        let start = length
        let marker = String(verse)
        append(marker)
        spans.append(ScriptureText.Span(start: start, length: CodePoints.utf16Length(marker),
                                        attribute: ScriptureText.Attribute.verseNumber(verse)))
        openVerse = OpenVerse(verse: verse, start: start)
        needsBreak = false
        brCount = 0
        pendingSpace = false
        holdBreaks = numberOnOwnLine
    }

    private mutating func closeVerse() {
        guard let open = openVerse else { return }
        openVerse = nil
        // A verse ends at its last visible character, not at the break before the next one.
        var end = length
        while end > open.start {
            let unit = text.unit(at: end - 1)
            guard unit == 0x20 || unit == 0x0A else { break }
            end -= 1
        }
        verses.append(ScriptureText.VerseRange(verse: open.verse, start: open.start, length: end - open.start))
    }

    // MARK: Events

    mutating func startElement(_ name: String, attributes a: [String: String], selfClosing: Bool) {
        if skipDepth > 0 {
            if !selfClosing { push(name, .skipped) }
            return
        }
        switch name {
        case "head", "ThML.head", "script", "style", "insertIndex":
            if !selfClosing { push(name, .skipped) }
        case "b", "strong":
            push(name, .span(.bold), selfClosing: selfClosing)
        case "i", "em", "added":
            push(name, .span(.italic), selfClosing: selfClosing)
        case "small":
            push(name, .span(.small), selfClosing: selfClosing)
        case "br", "hr":
            lineBreak()
        case "p":
            paragraphBreak()
            push(name, .plain, selfClosing: selfClosing, paragraphAfter: true)
        case "div", "div1", "div2", "div3", "div4", "div5", "div6", "blockquote", "center", "ul", "ol", "pre", "address":
            blockEdge()
            push(name, .plain, selfClosing: selfClosing, breaksAfter: true)
        case "h1":
            heading(name, .ms, selfClosing)
        case "h2":
            heading(name, .s1, selfClosing)
        case "h3", "h4", "h5", "h6":
            heading(name, .s2, selfClosing)
        case "li":
            blockEdge()
            splitOpenListItem()
            let depth = stack.filter { $0.name == "ul" || $0.name == "ol" }.count
            push(name, Frame.Kind.block(ParagraphRole.listItem(depth: max(depth, 1))), selfClosing: selfClosing)
        case "table", "tr":
            blockEdge()
            push(name, .plain, selfClosing: selfClosing, breaksAfter: true)
        case "td", "th":
            pendingSpace = true
            push(name, .plain, selfClosing: selfClosing)
        case "a":
            if let target = anchorTarget(a) {
                push(name, Frame.Kind.span(ScriptureText.Attribute.link(target: target)), selfClosing: selfClosing)
            } else {
                push(name, Frame.Kind.plain, selfClosing: selfClosing)
            }
        case "scripRef":
            let target = scriptureTarget(a)
            if let note = activeNote, let reference = a["osisRef"] ?? a["passage"], !reference.isEmpty {
                note.references.append(reference)
            }
            if let target {
                push(name, Frame.Kind.span(ScriptureText.Attribute.link(target: target)), selfClosing: selfClosing)
            } else if !selfClosing {
                push(name, Frame.Kind.span(ScriptureText.Attribute.link(target: "passage:")), passageFromText: true)
            } else {
                push(name, Frame.Kind.plain, selfClosing: selfClosing)
            }
        case "note":
            guard !selfClosing else { return }
            noteCount += 1
            let id = String(noteCount)
            let isCross = a["type"] == "x" || a["type"] == "crossReference"
            let kind = isCross ? ScriptureText.Note.Kind.crossReference : ScriptureText.Note.Kind.footnote
            activeNote = NoteDraft(id: id, kind: kind)
            push(name, Frame.Kind.note(id: id, kind: kind))
        case "sync":
            sync(a)
        default:
            // font, sup, sub, q, latin, greek, span, scripture, scripCom … show their text.
            push(name, .plain, selfClosing: selfClosing)
        }
    }

    mutating func endElement(_ name: String) {
        guard let index = stack.lastIndex(where: { $0.name == name }) else { return }
        while stack.count > index { closeTopFrame() }
    }

    mutating func characters(_ raw: String) {
        guard skipDepth == 0 else { return }
        let t = options.transforms.apply(Self.decodeNamedEntities(raw))
        if activeNote != nil {
            appendToNote(t)
            return
        }
        emit(t)
    }

    // MARK: Frames

    private mutating func heading(_ name: String, _ role: ParagraphRole, _ selfClosing: Bool) {
        blockEdge()
        push(name, .block(role), selfClosing: selfClosing, breaksAfter: true)
    }

    private mutating func push(_ name: String, _ kind: Frame.Kind, selfClosing: Bool = false,
                               breaksAfter: Bool = false, paragraphAfter: Bool = false, passageFromText: Bool = false) {
        guard !selfClosing else { return }
        switch kind {
        case .span, .block: unstarted += 1
        case .skipped: skipDepth += 1
        default: break
        }
        stack.append(Frame(name: name, kind: kind, start: nil, breaksAfter: breaksAfter, paragraphAfter: paragraphAfter,
                           passageFromText: passageFromText, noteOffset: passageFromText ? activeNote?.text.length : nil))
    }

    /// A list item inside a list item: the outer item's paragraph ends here, so the two
    /// paragraphs do not overlap.
    private mutating func splitOpenListItem() {
        guard let index = stack.lastIndex(where: { $0.name == "li" }) else { return }
        switch stack[index].kind {
        case .block(let role):
            if let start = stack[index].start { addSpan(start, ScriptureText.Attribute.block(role)) } else { unstarted -= 1 }
            stack[index].kind = Frame.Kind.plain
        default:
            break
        }
    }

    private mutating func closeTopFrame() {
        let frame = stack.removeLast()
        switch frame.kind {
        case .span(var attribute):
            if frame.start == nil {
                unstarted -= 1
            } else {
                if frame.passageFromText, let start = frame.start, length > start {
                    attribute = ScriptureText.Attribute.link(target: "passage:" + text.substring(from: start, to: length))
                }
                addSpan(frame.start, attribute)
            }
            if frame.passageFromText, let offset = frame.noteOffset, let note = activeNote {
                let reference = CodePoints.trimmed(note.text.substring(from: offset, to: note.text.length),
                                                   where: { CodePoints.isHorizontalWhiteSpace($0) })
                if !reference.isEmpty { note.references.append(reference) }
            }
        case .block(let role):
            if frame.start == nil { unstarted -= 1 } else { addSpan(frame.start, ScriptureText.Attribute.block(role)) }
            needsBreak = true
        case .note(let id, let kind):
            finishNote(id: id, kind: kind)
        case .skipped:
            skipDepth -= 1
        case .plain:
            break
        }
        if frame.paragraphAfter { paragraphBreak() } else if frame.breaksAfter { blockEdge() }
    }

    private mutating func addSpan(_ start: Int?, _ attribute: ScriptureText.Attribute) {
        guard let start, length > start else { return }
        spans.append(ScriptureText.Span(start: start, length: length - start, attribute: attribute))
    }

    // MARK: Breaks and text

    /// A `<br>`: counts towards a blank line (two in a row).
    private mutating func lineBreak() {
        needsBreak = true
        brCount += 1
    }

    /// The edge of a block (div, heading, list item, table row): a new line, which meeting
    /// another block edge does not double.
    private mutating func blockEdge() {
        needsBreak = true
    }

    private mutating func paragraphBreak() {
        needsBreak = true
        brCount += 2
    }

    private mutating func append(_ s: String) {
        guard !s.isEmpty else { return }
        text.append(s)
        endsWithNewline = text.lastUnit == 0x0A
    }

    private mutating func flushPending() {
        if let ownLine = holdBreaks {
            holdBreaks = nil
            if ownLine {
                needsBreak = true
                brCount = min(brCount, 1)
            } else {
                needsBreak = false
                brCount = 0
                pendingSpace = false
            }
        }
        if needsBreak {
            if length > 0 && !endsWithNewline { append("\n") }
            if brCount >= 2, length > 0, !text.hasSuffix("\n\n") { append("\n") }
            needsBreak = false
            brCount = 0
            pendingSpace = false
        } else if pendingSpace {
            if length > 0 && !endsWithNewline { append(" ") }
            pendingSpace = false
        }
    }

    private mutating func beginContent() {
        flushPending()
        if unstarted > 0 {
            for index in stack.indices where stack[index].start == nil {
                switch stack[index].kind {
                case .span, .block:
                    stack[index].start = length
                    unstarted -= 1
                default: break
                }
            }
        }
    }

    /// Text with HTML's whitespace rules: a run of white space is one space, ignored at a
    /// line's start.
    private mutating func emit(_ raw: String) {
        var run: [Int] = []
        for c in CodePoints.of(raw) {
            if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D {
                if !run.isEmpty { beginContent(); append(CodePoints.string(run)); run = [] }
                pendingSpace = true
            } else {
                run.append(c)
            }
        }
        if !run.isEmpty { beginContent(); append(CodePoints.string(run)) }
    }

    // MARK: Markers, notes and links

    private mutating func sync(_ a: [String: String]) {
        guard let value = a["value"], !value.isEmpty else { return }
        switch a["type"]?.lowercased() {
        case "strongs", "lemma":
            guard options.strongs else { return }
            let codes = CodePoints.of(value)
            var first = 0
            while first < codes.count && (codes[first] == 0x47 || codes[first] == 0x48) { first += 1 }   // leading G and H
            let digits = CodePoints.string(codes, first, codes.count)
            beginContent()
            let start = length
            let marker = "<" + digits + ">"
            append(marker)
            spans.append(ScriptureText.Span(start: start, length: CodePoints.utf16Length(marker),
                                            attribute: ScriptureText.Attribute.strongs("strong:" + value)))
        case "morph":
            guard options.morphology else { return }
            beginContent()
            let start = length
            let marker = "(" + value + ")"
            append(marker)
            spans.append(ScriptureText.Span(start: start, length: CodePoints.utf16Length(marker),
                                            attribute: ScriptureText.Attribute.morph("robinson:" + value)))
        default:
            return
        }
    }

    private mutating func appendToNote(_ raw: String) {
        guard let note = activeNote else { return }
        note.append(raw)
    }

    private mutating func finishNote(id: String, kind: ScriptureText.Note.Kind) {
        guard let note = activeNote else { return }
        activeNote = nil
        guard options.footnotes else { return }
        let body = CodePoints.trimmed(note.text.text, where: { CodePoints.isHorizontalWhiteSpace($0) })
        guard !body.isEmpty || !note.references.isEmpty else { return }
        notes.append(ScriptureText.Note(id: id, text: body, references: note.references, kind: kind))
        beginContent()
        let start = length
        append(kind == ScriptureText.Note.Kind.crossReference ? "x" : "n")
        spans.append(ScriptureText.Span(start: start, length: 1, attribute: ScriptureText.Attribute.footnote(id: id)))
    }

    /// `sword://Work/Key` and web links are kept as written; `#anchor` and `name=` anchors
    /// are not links.
    private func anchorTarget(_ a: [String: String]) -> String? {
        guard let href = a["href"], !href.isEmpty, !href.hasPrefix("#") else { return nil }
        let lower = href.lowercased()
        if lower.hasPrefix("sword://") || lower.hasPrefix("http://") || lower.hasPrefix("https://") { return href }
        return nil
    }

    /// `osisRef` where the author gave one, otherwise the human `passage` ("Rom 3:23"), which
    /// SWORD parses itself.
    private func scriptureTarget(_ a: [String: String]) -> String? {
        if let osis = a["osisRef"], !osis.isEmpty { return "osis:" + osis }
        if let passage = a["passage"], !passage.isEmpty { return "passage:" + passage }
        return nil
    }

    /// The HTML entities ThML authors use beyond XML's five (which the tokenizer decodes).
    static func decodeNamedEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var result = s
        var k = 0
        while k < entityNames.count {
            result = result.replacingOccurrences(of: entityNames[k], with: entityValues[k])
            k += 1
        }
        return result
    }

    // Two lists side by side, not a list of pairs: the transpiler takes no tuples in arrays. Applied in this order.
    private static let entityNames: [String] = [
        "&nbsp;", "&mdash;", "&ndash;", "&hellip;", "&lsquo;", "&rsquo;", "&ldquo;", "&rdquo;", "&middot;", "&bull;", "&copy;",
        "&deg;", "&c;", "&laquo;", "&raquo;", "&sect;", "&para;",
    ]
    private static let entityValues: [String] = [
        "\u{00A0}", "\u{2014}", "\u{2013}", "\u{2026}", "\u{2018}", "\u{2019}", "\u{201C}", "\u{201D}", "\u{00B7}", "\u{2022}",
        "\u{00A9}", "\u{00B0}", "&c.", "\u{00AB}", "\u{00BB}", "\u{00A7}", "\u{00B6}",
    ]

    // MARK: Finish

    mutating func finish() -> ScriptureText {
        while !stack.isEmpty { closeTopFrame() }
        closeVerse()
        // Trailing whitespace is never shown.
        text.dropTrailingASCII(where: { $0 == 0x20 || $0 == 0x0A })
        let total = length
        var keptSpans: [ScriptureText.Span] = []
        for span in spans.elements() {
            let end = min(span.start + span.length, total)
            if end > span.start {
                keptSpans.append(ScriptureText.Span(start: span.start, length: end - span.start, attribute: span.attribute))
            }
        }
        var keptVerses: [ScriptureText.VerseRange] = []
        for verse in verses.elements() {
            let end = min(verse.start + verse.length, total)
            if end > verse.start { keptVerses.append(ScriptureText.VerseRange(verse: verse.verse, start: verse.start, length: end - verse.start)) }
        }
        return ScriptureText(text: text.text, spans: keptSpans, verses: keptVerses, notes: notes.elements())
    }
}

/// The verse being written: its number and where its marker starts.
private struct OpenVerse {
    let verse: Int
    let start: Int
}

/// A note as it is captured: its text whitespace-collapsed, and the passages it cites. A class, so it grows in place.
private final class NoteDraft {
    let id: String
    let kind: ScriptureText.Note.Kind
    let text = TextBuffer()
    var references: [String] = []

    init(id: String, kind: ScriptureText.Note.Kind) {
        self.id = id
        self.kind = kind
    }

    func append(_ raw: String) {
        var run: [Int] = []
        for c in CodePoints.of(raw) {
            if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D {
                if !run.isEmpty { text.append(CodePoints.string(run)); run = [] }
                if !(text.isEmpty || text.lastUnit == 0x20) { text.append(" ") }
            } else {
                run.append(c)
            }
        }
        if !run.isEmpty { text.append(CodePoints.string(run)) }
    }
}
