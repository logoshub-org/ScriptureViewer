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
        MarkupTokenizer.tokenize(entry.replacingOccurrences(of: "\u{0}", with: ""), into: &builder)
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
    private var text = ""
    private var length = 0
    private var spans: [ScriptureText.Span] = []
    private var notes: [ScriptureText.Note] = []
    private var stack: [Frame] = []
    private var unstarted = 0

    private var endsWithNewline = true
    private var needsBreak = false
    private var brCount = 0
    private var pendingSpace = false
    private var activeNote: (id: String, text: String)?

    init(options: TEIParser.Options) { self.options = options }

    // MARK: Events

    mutating func startElement(_ name: String, attributes a: [String: String], selfClosing: Bool) {
        switch name {
        case "entryFree":
            guard !selfClosing else { return }
            push(name, .plain)
            if let n = a["n"], !n.isEmpty {
                emitInline(n, .bold)                        // SWORD writes <b>n</b> ahead of the entry
            }
        case "orth", "tr":
            push(name, selfClosing ? .plain : .span(.bold), selfClosing: selfClosing)
        case "pron", "pos", "gen", "case", "gram", "number":
            push(name, .span(.italic), selfClosing: selfClosing)
        case "hi":
            let kind: Frame.Kind
            switch a["rend"] {
            case "italic", "ital": kind = .span(.italic)
            case "bold": kind = .span(.bold)
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
                emitInline(n, .bold)
                pendingSpace = true
            }
        case "ref":
            let target = linkTarget(a)
            push(name, target.map { .span(.link(target: $0)) } ?? .plain, selfClosing: selfClosing)
        case "note":
            guard !selfClosing else { return }
            let id = String(notes.count + 1)
            activeNote = (id, "")
            push(name, .note(id: id))
        case "list":
            lineBreak()
            push(name, .plain, selfClosing: selfClosing)
        case "item":
            lineBreak()
            let depth = stack.filter { $0.name == "list" }.count
            push(name, .block(.listItem(depth: max(depth, 1))), selfClosing: selfClosing)
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
            if frame.start == nil { unstarted -= 1 } else { addSpan(frame.start, .block(role)) }
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
        spans.append(.init(start: start, length: length - start, attribute: attribute))
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
        length += s.utf16.count
        endsWithNewline = s.hasSuffix("\n")
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
        var run = ""
        for scalar in raw.unicodeScalars {
            if scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" {
                if !run.isEmpty { beginContent(); append(run); run = "" }
                pendingSpace = true
            } else {
                run.unicodeScalars.append(scalar)
            }
        }
        if !run.isEmpty { beginContent(); append(run) }
    }

    /// A short run with its own attribute, e.g. an entry's number in bold.
    private mutating func emitInline(_ s: String, _ attribute: ScriptureText.Attribute) {
        beginContent()
        let start = length
        append(s)
        spans.append(.init(start: start, length: length - start, attribute: attribute))
    }

    // MARK: Notes and links

    private mutating func appendToNote(_ raw: String) {
        guard activeNote != nil else { return }
        for scalar in raw.unicodeScalars {
            if scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" {
                if !(activeNote!.text.isEmpty || activeNote!.text.hasSuffix(" ")) { activeNote!.text.append(" ") }
            } else {
                activeNote!.text.unicodeScalars.append(scalar)
            }
        }
    }

    private mutating func finishNote(id: String) {
        guard let note = activeNote else { return }
        activeNote = nil
        guard options.footnotes else { return }
        let body = note.text.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return }
        notes.append(.init(id: id, text: body, kind: .footnote))
        beginContent()
        let start = length
        append("n")
        spans.append(.init(start: start, length: 1, attribute: .footnote(id: id)))
    }

    /// `Work:Key` is a dictionary link and `osisRef` a scripture link, both `sword://Work/Key`
    /// as SWORD writes them; a target with no work belongs to the entry's own module.
    private func linkTarget(_ a: [String: String]) -> String? {
        guard let target = a["osisRef"] ?? a["target"], !target.isEmpty else { return nil }
        let work: String?
        let key: String
        if let colon = target.firstIndex(of: ":") {
            work = String(target[..<colon])
            key = String(target[target.index(after: colon)...])
        } else {
            work = nil
            key = target
        }
        let module = (work?.isEmpty == false ? work : options.module) ?? ""
        return "sword://\(Self.encode(module))/\(Self.encode(key))"
    }

    private static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? s
    }

    // MARK: Finish

    mutating func finish() -> ScriptureText {
        while !stack.isEmpty { closeTopFrame() }
        // Trailing whitespace is never shown.
        while text.last == " " || text.last == "\n" {
            text.removeLast()
            length -= 1
        }
        spans = spans.compactMap { span in
            let end = min(span.start + span.length, length)
            return end > span.start ? .init(start: span.start, length: end - span.start, attribute: span.attribute) : nil
        }
        return ScriptureText(text: text, spans: spans, verses: [], notes: notes)
    }
}
