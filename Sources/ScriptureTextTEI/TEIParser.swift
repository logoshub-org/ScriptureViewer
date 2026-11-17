// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// TEI dictionary entries (plan D46, step 7): the Strong's Greek dictionary, the CBOL Chinese
// dictionaries and the Hebrew morphology parse explanations are stored as
// `<entryFree n="1"><orth>…</orth><lb/><pron>{…}</pron><def>…</def></entryFree>`. The vocabulary
// in the modules in hand is `entryFree`, `orth`, `pron`, `def`, `lb` and `ref`; the rules follow
// SWORD's own TEI filter (`teihtmlhref.cpp`) so the native view matches the web view:
//
//   entryFree n=…  the entry's number or name, bold, ahead of the content
//   orth, tr       bold, italic
//   pron, pos, gen, case, gram, number   italic
//   hi rend=       italic / bold / super / sub (overline is ignored)
//   lb             a line break;  p  a paragraph (two breaks in a row are a blank line)
//   sense n=…      a new line, the number in bold
//   ref target=    a link: "Work:Key" is the dictionary link `sword://Work/Key`, `osisRef` a
//                  scripture link `sword://Work/Ref`; without a work, the module's own name
//   note           a footnote marker; the body is kept apart from the text
//   list, item     one paragraph per item;  table, row, cell  one line per row, cells apart by a space
//   anything else  its text, unchanged
//
// Text is whitespace-collapsed as a browser would (the entries are hard-wrapped), so a line end
// is a space and only `lb`, `p` and `sense` break lines.

import Foundation
import ScriptureText
import ScriptureTextMarkup

public struct TEIParser: Sendable {

    public struct Options: Sendable, Equatable {
        /// The module the entry belongs to: the work of a link that names none.
        public var module: String?
        /// Greek accents, Hebrew points and cantillation (D47); the headwords of a dictionary
        /// are Greek and Hebrew.
        public var transforms = TextTransforms()
        public var footnotes = true

        public init(module: String? = nil) { self.module = module }
    }

    public var options: Options
    public var profile: ScriptureContentProfile

    public init(options: Options = Options(), profile: ScriptureContentProfile = .dictionary) {
        self.options = options
        self.profile = profile
    }

    /// One entry. Tolerant: unknown or unbalanced markup never fails the parse.
    public func parse(_ entry: String) -> ScriptureText {
        var builder = TEIBuilder(options: options)
        MarkupTokenizer.tokenize(entry.replacingOccurrences(of: "\u{0000}", with: ""), into: &builder)
        return builder.finish()
    }
}

// MARK: - Builder

struct TEIBuilder: MarkupEventSink {

    private struct Frame {
        enum Kind {
            case plain
            case span(ScriptureText.Attribute)
            case block(ParagraphRole)
            case note(id: String)
        }
        var name: String
        var kind: Kind
        var start: Int?
        var countsAsBreak = false
    }

    private let options: TEIParser.Options
    private let text = TextBuffer()
    private var length: Int { text.length }
    private let spans = GrowingList<ScriptureText.Span>()
    private let notes = GrowingList<ScriptureText.Note>()
    private var stack: [Frame] = []
    private var unstarted = 0

    private var endsWithNewline = true
    private var needsBreak = false
    private var brCount = 0
    private var pendingSpace = false
    private var activeNote: NoteDraft?

    init(options: TEIParser.Options) { self.options = options }

    // MARK: Events

    mutating func startElement(_ name: String, attributes a: [String: String], selfClosing: Bool) {
        switch name {
        case "entryFree":
            guard !selfClosing else { return }
            push(name, .plain)
            if let n = a["n"], !n.isEmpty {
                emitInline(n, ScriptureText.Attribute.bold)  // SWORD writes <b>n</b> ahead of the entry
            }
        case "orth", "tr":
            push(name, selfClosing ? Frame.Kind.plain : Frame.Kind.span(ScriptureText.Attribute.bold), selfClosing: selfClosing)
        case "pron", "pos", "gen", "case", "gram", "number":
            push(name, Frame.Kind.span(ScriptureText.Attribute.italic), selfClosing: selfClosing)
        case "hi":
            let kind: Frame.Kind
            switch a["rend"] {
            case "italic", "ital": kind = Frame.Kind.span(ScriptureText.Attribute.italic)
            case "bold": kind = Frame.Kind.span(ScriptureText.Attribute.bold)
            // super, sub, overline: the model has no raised-text attribute yet; the text stays plain.
            default: kind = .plain
            }
            push(name, kind, selfClosing: selfClosing)
        case "lb":
            lineBreak()
        case "p":
            paragraphBreak()
            push(name, .plain, selfClosing: selfClosing, countsAsBreak: true)
        case "sense":
            lineBreak()
            if !selfClosing { push(name, .plain) }
            if let n = a["n"], !n.isEmpty {
                emitInline(n, ScriptureText.Attribute.bold)
                pendingSpace = true
            }
        case "ref":
            if let target = linkTarget(a) {
                push(name, Frame.Kind.span(ScriptureText.Attribute.link(target: target)), selfClosing: selfClosing)
            } else {
                push(name, Frame.Kind.plain, selfClosing: selfClosing)
            }
        case "note":
            guard !selfClosing else { return }
            let id = String(notes.count + 1)
            activeNote = NoteDraft(id: id)
            push(name, Frame.Kind.note(id: id))
        case "list":
            lineBreak()
            push(name, .plain, selfClosing: selfClosing)
        case "item":
            lineBreak()
            let depth = stack.filter { $0.name == "list" }.count
            push(name, Frame.Kind.block(ParagraphRole.listItem(depth: max(depth, 1))), selfClosing: selfClosing)
        case "table":
            lineBreak()
            push(name, .plain, selfClosing: selfClosing)
        case "row":
            lineBreak()
            push(name, .plain, selfClosing: selfClosing)
        case "cell":
            pendingSpace = true
            push(name, .plain, selfClosing: selfClosing)
        default:
            push(name, .plain, selfClosing: selfClosing)
        }
    }

    mutating func endElement(_ name: String) {
        guard let index = stack.lastIndex(where: { $0.name == name }) else { return }
        while stack.count > index { closeTopFrame() }
    }

    mutating func characters(_ raw: String) {
        let t = options.transforms.apply(raw)
        if activeNote != nil {
            appendToNote(t)
            return
        }
        emit(t)
    }

    // MARK: Frames

    private mutating func push(_ name: String, _ kind: Frame.Kind, selfClosing: Bool = false, countsAsBreak: Bool = false) {
        guard !selfClosing else { return }
        switch kind {
        case .span, .block: unstarted += 1
        default: break
        }
        stack.append(Frame(name: name, kind: kind, start: nil, countsAsBreak: countsAsBreak))
    }

    private mutating func closeTopFrame() {
        let frame = stack.removeLast()
        switch frame.kind {
        case .span(let attribute):
            if frame.start == nil { unstarted -= 1 } else { addSpan(frame.start, attribute) }
        case .block(let role):
            if frame.start == nil { unstarted -= 1 } else { addSpan(frame.start, ScriptureText.Attribute.block(role)) }
            needsBreak = true
        case .note(let id):
            finishNote(id: id)
        case .plain:
            break
        }
        if frame.countsAsBreak { paragraphBreak() }
        if frame.name == "row" || frame.name == "list" || frame.name == "table" { needsBreak = true }
    }

    private mutating func addSpan(_ start: Int?, _ attribute: ScriptureText.Attribute) {
        guard let start, length > start else { return }
        spans.append(ScriptureText.Span(start: start, length: length - start, attribute: attribute))
    }

    // MARK: Breaks and text

    private mutating func lineBreak() {
        needsBreak = true
        brCount += 1
    }

    private mutating func paragraphBreak() {
        needsBreak = true
        brCount += 1
    }

    private mutating func append(_ s: String) {
        guard !s.isEmpty else { return }
        text.append(s)
        endsWithNewline = text.lastUnit == 0x0A
    }

    private mutating func flushPending() {
        if needsBreak {
            if length > 0 && !endsWithNewline { append("\n") }
            if brCount >= 2, length > 0 { append("\n") }
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

    /// A short run with its own attribute, e.g. an entry's number in bold.
    private mutating func emitInline(_ s: String, _ attribute: ScriptureText.Attribute) {
        beginContent()
        let start = length
        append(s)
        spans.append(ScriptureText.Span(start: start, length: length - start, attribute: attribute))
    }

    // MARK: Notes and links

    private mutating func appendToNote(_ raw: String) {
        guard let note = activeNote else { return }
        note.append(raw)
    }

    private mutating func finishNote(id: String) {
        guard let note = activeNote else { return }
        activeNote = nil
        guard options.footnotes else { return }
        let body = CodePoints.trimmed(note.text.text, where: { CodePoints.isHorizontalWhiteSpace($0) })
        guard !body.isEmpty else { return }
        notes.append(ScriptureText.Note(id: id, text: body, kind: ScriptureText.Note.Kind.footnote))
        beginContent()
        let start = length
        append("n")
        spans.append(ScriptureText.Span(start: start, length: 1, attribute: ScriptureText.Attribute.footnote(id: id)))
    }

    /// `Work:Key` is a dictionary link and `osisRef` a scripture link, both `sword://Work/Key`
    /// as SWORD writes them; a target with no work belongs to the entry's own module.
    private func linkTarget(_ a: [String: String]) -> String? {
        guard let target = a["osisRef"] ?? a["target"], !target.isEmpty else { return nil }
        let codes = CodePoints.of(target)
        var colon = -1
        var k = 0
        while k < codes.count {
            if codes[k] == 0x3A { colon = k; break }
            k += 1
        }
        var work = ""
        var key = target
        if colon >= 0 {
            work = CodePoints.string(codes, 0, colon)
            key = CodePoints.string(codes, colon + 1, codes.count)
        }
        let module = work.isEmpty ? (options.module ?? "") : work
        return "sword://" + CodePoints.percentEncoded(module) + "/" + CodePoints.percentEncoded(key)
    }

    // MARK: Finish

    mutating func finish() -> ScriptureText {
        while !stack.isEmpty { closeTopFrame() }
        // Trailing whitespace is never shown.
        text.dropTrailingASCII(where: { $0 == 0x20 || $0 == 0x0A })
        let total = length
        var kept: [ScriptureText.Span] = []
        for span in spans.elements() {
            let end = min(span.start + span.length, total)
            if end > span.start { kept.append(ScriptureText.Span(start: span.start, length: end - span.start, attribute: span.attribute)) }
        }
        return ScriptureText(text: text.text, spans: kept, verses: [], notes: notes.elements())
    }
}

/// A note's text as it is captured, whitespace-collapsed. A class, so it grows in place.
private final class NoteDraft {
    let id: String
    let text = TextBuffer()

    init(id: String) { self.id = id }

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
