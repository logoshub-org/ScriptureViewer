// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Turns OSIS events into a ScriptureText (plan D32, D34–D37). This file decides what OSIS means; writing the text,
// breaks, verse markers, word anchors and notes is `ScriptureTextBuilder`'s, shared with USFM (Track V3):
//
//  • one element stack for the whole chapter — containers span verse entries
//    (BSB lists run up to 11 verses), so verses are boundaries, not resets;
//  • raw entries carry NO verse numbers, so the builder synthesises the
//    marker at each verse, after any leading headings and breaks;
//  • poetry is milestones (`<l sID/>…<l eID/>`), not a tree;
//  • paragraphs carry USFM-named roles (D36);
//  • SWORD's rules for titles, pre-verse headings, quotations, variants and
//    notes (osisxhtml.cpp) are kept here.

import Foundation
import ScriptureText
import ScriptureTextBuilding
import ScriptureTextMarkup

struct OSISBuilder: MarkupEventSink {

    private let options: OSISParser.Options
    private var out: ScriptureTextBuilder

    /// Between `<div subType="x-preverse" sID/>` and its `eID`: a heading SWORD files under
    /// "pre-verse" and prints before the verse number. When it holds text outside a `<title>`
    /// (the BSB's acrostic letters), that text becomes a heading of its own, opened lazily.
    private var preverseOpen = false
    private var preverseHeadingOpen = false

    private var noteOrdinal = 0

    // Element stack
    private struct Frame {
        enum Kind {
            case plain
            case span(ScriptureText.Attribute, block: Bool)
            case title(ParagraphRole)
            case word(lemma: String?, morph: String?)
            case note(id: String)
            case skip
        }
        var name: String
        var kind: Kind
        var breakAfter: Bool
        /// The span this frame writes, started at its first content.
        var handle: ScriptureTextBuilder.SpanHandle?
        /// Editorial content (a non-canonical heading): no word anchors.
        var editorial = false
        /// Variant readings are word boundaries on both sides.
        var wordBoundary = false
        /// A container div restores the section context it replaced.
        var savedSection: String?
        var hasSavedSection = false
        /// Text emitted just before the frame closes (a `</q>` quotation mark).
        var closingText: String?
        /// A paragraph or line group: each boundary is one of SWORD's `<br />`.
        var paragraph = false
    }
    private var stack: [Frame] = []
    private var skipDepth = 0

    /// The kind of the last section-like div opened, which decides the role of
    /// an untyped title: `majorSection` → ms, `subSection` → s2, else s1.
    private var sectionKind: String?

    // Blocks written as milestones: <l sID/> … <l eID/>, <div sID/> … <div eID/>
    private struct MilestoneBlock { var id: String?; var role: ParagraphRole; var handle: ScriptureTextBuilder.SpanHandle }
    private var line: MilestoneBlock?
    private var division: MilestoneBlock?

    // Words of Christ written as milestones: <q sID who="Jesus"/> … <q eID/>
    private var redQuote: (id: String?, handle: ScriptureTextBuilder.SpanHandle)?

    /// The `type` of the note being captured.
    private var noteType = ""
    private var divineNameDepth = 0              // inside <divineName>

    private let transforms: TextTransforms

    init(options: OSISParser.Options) {
        self.options = options
        self.transforms = options.textTransforms
        var shared = ScriptureTextBuilder.Options()
        shared.verseNumbers = options.verseNumbers
        shared.versePerLine = options.versePerLine
        shared.strongsMarkers = options.strongsMarkers
        shared.morphMarkers = options.morphMarkers
        self.out = ScriptureTextBuilder(options: shared)
    }

    // MARK: Verses

    /// Starts a verse entry. Verse 0 (the chapter or book introduction) gets
    /// no marker and no range.
    mutating func beginVerse(_ number: Int) {
        closeShortLivedFrames()
        out.beginVerse(number)
    }

    /// Notes, titles, hidden variant readings and words belong to one verse
    /// entry. Real modules never leave one open across a verse (checked on all
    /// 9,649 chapters of the eight surveyed modules), so an unclosed one is
    /// closed at the boundary instead of swallowing the next verse's text.
    /// Containers that really do span verses (lists, poetry, quotations,
    /// italics) are untouched (D34).
    private mutating func closeShortLivedFrames() {
        let first = stack.firstIndex { frame in
            switch frame.kind {
            case .note, .skip, .title, .word: return true
            default: return false
            }
        }
        guard let first else { return }
        while stack.count > first { closeTopFrame() }
    }

    // MARK: Events

    mutating func startElement(_ name: String, attributes a: [String: String], selfClosing: Bool) {
        switch name {

        case "milestone":
            if a["type"] == "x-p" { out.blockBreak() }      // the ¶ glyph is dropped; SWORD adds no <br />
            return

        case "div":
            startDiv(a, selfClosing: selfClosing)
            return

        case "p":
            paragraphBreak()
            if !selfClosing { push(Frame(name: name, kind: .plain, breakAfter: true, paragraph: true)) }
            return

        case "lg":
            paragraphBreak()
            if !selfClosing { push(Frame(name: name, kind: .plain, breakAfter: true, paragraph: true)) }
            return

        case "l":
            startLine(a, selfClosing: selfClosing)
            return

        case "list":
            out.blockBreak()
            if !selfClosing { push(Frame(name: name, kind: .plain, breakAfter: true)) }
            return

        case "item":
            out.blockBreak()
            guard !selfClosing else { return }
            let depth = stack.filter { $0.name == "list" }.count
            push(Frame(name: name, kind: .span(.block(.listItem(depth: depth)), block: true), breakAfter: true))
            return

        case "lb":
            lineBreak()
            return

        case "title":
            guard !selfClosing else { return }
            startTitle(name, role: titleRole(a), canonical: a["canonical"] == "true")
            return

        case "speaker":
            guard !selfClosing else { return }
            // SWORD does not tie speaker labels to the headings option; they are always shown.
            startTitle(name, role: .sp, canonical: true)
            return

        case "w":
            if selfClosing {
                // `<w lemma= morph=/>` carries data for a word the text does not repeat (the
                // KJV's unplaced articles); SWORD still prints its markers (osisxhtml.cpp).
                if skipDepth == 0, !out.inNote {
                    out.emitWordMarkers(lemma: Self.nonEmpty(a["lemma"]), morph: Self.nonEmpty(a["morph"]))
                }
                return
            }
            out.wordBoundary()                               // a <w> starts a word
            out.wordDepth += 1
            push(Frame(name: name, kind: .word(lemma: Self.nonEmpty(a["lemma"]), morph: Self.nonEmpty(a["morph"])),
                       breakAfter: false))
            return

        case "transChange", "foreign":
            if !selfClosing { push(Frame(name: name, kind: .span(.italic, block: false), breakAfter: false)) }
            return

        case "hi":
            guard !selfClosing else { return }
            let kind: Frame.Kind
            switch a["type"] {
            case "italic", "emphasis": kind = .span(.italic, block: false)
            case "bold": kind = .span(.bold, block: false)
            case "small-caps", "small": kind = .span(.small, block: false)
            default: kind = .plain
            }
            push(Frame(name: name, kind: kind, breakAfter: false))
            return

        case "divineName":
            if !selfClosing {
                divineNameDepth += 1
                push(Frame(name: name, kind: .span(.divineName, block: false), breakAfter: false))
            }
            return

        case "q":
            startQuote(a, selfClosing: selfClosing)
            return

        case "seg":
            guard !selfClosing else { return }
            if a["type"] == "x-variant" {
                let sub = a["subType"] ?? ""
                let drop: Bool
                switch options.variants {
                case .primary: drop = sub == "x-2"
                case .secondary: drop = sub == "x-1"
                case .all: drop = false
                }
                push(Frame(name: name, kind: drop ? .skip : .plain, breakAfter: false, wordBoundary: true))
            } else {
                push(Frame(name: name, kind: .plain, breakAfter: false))
            }
            return

        case "note":
            guard !selfClosing else { return }
            if !out.inNote {
                noteOrdinal += 1
                let id = a["osisID"] ?? "\(out.currentVerse ?? 0).\(noteOrdinal)"
                noteType = a["type"] ?? ""
                out.beginNote()                              // a note is a word boundary
                push(Frame(name: name, kind: .note(id: id), breakAfter: false))
            } else {
                push(Frame(name: name, kind: .plain, breakAfter: false))   // nested note: just its text
            }
            return

        case "reference":
            guard !selfClosing else { return }
            let target = a["osisRef"] ?? ""
            // `passage` is not OSIS: the GBF converter's way to say "a reference as printed" ("Lu 1:1-4"), which the
            // reader resolves with the module's own key parser, as ThML's `passage` links are.
            let printed = a["passage"] ?? ""
            if out.inNote {
                if !target.isEmpty || !printed.isEmpty { out.addNoteReference(target.isEmpty ? printed : target) }
                push(Frame(name: name, kind: .plain, breakAfter: false))
            } else if !target.isEmpty {
                push(Frame(name: name, kind: .span(.link(target: "osis:" + target), block: false), breakAfter: false))
            } else if !printed.isEmpty {
                push(Frame(name: name, kind: .span(.link(target: "passage:" + printed), block: false), breakAfter: false))
            } else {
                push(Frame(name: name, kind: .plain, breakAfter: false))
            }
            return

        case "chapter", "verse":
            return                                           // markers only

        default:
            // Unknown elements degrade to their text.
            if !selfClosing { push(Frame(name: name, kind: .plain, breakAfter: false)) }
        }
    }

    mutating func endElement(_ name: String) {
        // Close back to the nearest matching frame; anything above it was never
        // closed and is closed now. A close tag with no match is ignored.
        guard let index = stack.lastIndex(where: { $0.name == name }) else { return }
        while stack.count > index {
            closeTopFrame()
        }
    }

    /// Text of a pre-verse region that is not inside a `<title>`: SWORD prints it as a heading
    /// before the verse number, and only when headings are on.
    private mutating func openPreverseHeadingIfNeeded(for raw: String) {
        guard preverseOpen, !preverseHeadingOpen, !out.inNote, !stack.contains(where: { $0.name == "title" }),
              ScriptureTextBuilder.hasContent(raw) else { return }
        startTitle("x-preverse", role: .s1)
        preverseHeadingOpen = true
    }

    private mutating func closePreverseHeading() {
        guard preverseHeadingOpen else { return }
        preverseHeadingOpen = false
        if let index = stack.lastIndex(where: { $0.name == "x-preverse" }) {
            while stack.count > index { closeTopFrame() }
        }
    }

    mutating func characters(_ original: String) {
        var raw = transforms.apply(original)     // before offsets, word counts and notes (D47)
        openPreverseHeadingIfNeeded(for: raw)
        // SWORD sets the divine name in capitals (osishtmlhref.cpp), so the text is capitals; the
        // styler draws everything after the first letter smaller (LORD, not Lord).
        if divineNameDepth > 0 { raw = raw.uppercased() }
        if out.inNote {
            out.appendToNote(raw)
            return
        }
        if skipDepth > 0 {
            out.countHiddenWords(raw)            // a hidden reading keeps its word indexes
            return
        }
        out.emit(raw)
    }

    // MARK: Finish

    mutating func finish() -> ScriptureText {
        out.endVerse()
        while !stack.isEmpty { closeTopFrame() }
        endRedQuote()
        endLine()
        endDivision()
        return out.finish()
    }

    // MARK: Element helpers

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static let breakingDivTypes: Set<String> =
        ["x-p", "paragraph", "section", "subSection", "majorSection", "introduction", "outline"]
    private static let sectionDivTypes: Set<String> = ["section", "subSection", "majorSection"]

    private func titleRole(_ a: [String: String]) -> ParagraphRole {
        switch a["type"] {
        case "main": return .mt
        case "chapter": return .cl
        case "scope": return .mr
        case "parallel": return .r
        case "psalm": return .d
        case "acrostic": return .qa
        default:                                             // sub, untyped
            switch sectionKind {
            case "majorSection": return .ms
            case "subSection": return .s2
            default: return .s1
            }
        }
    }

    private mutating func startTitle(_ name: String, role: ParagraphRole, canonical: Bool = false) {
        out.blockBreak()
        // SWORD's heading filter keeps a title marked canonical (a Psalm
        // superscription is verse text) even when headings are off.
        // An acrostic letter (Psalm 119's "ALEPH") is marked canonical too, but SWORD files it with the headings (it sits
        // in an `x-preverse` block), so it follows the Headings preference like any other.
        let shown = options.headings || (canonical && role != .qa)
        if shown { out.clearBreakCount() }                  // a shown heading carries its own space
        let kind: Frame.Kind = shown ? .title(role) : .skip
        push(Frame(name: name, kind: kind, breakAfter: true, editorial: !role.isCanonical))
    }

    private mutating func startDiv(_ a: [String: String], selfClosing: Bool) {
        let type = a["type"] ?? ""
        let breaks = Self.breakingDivTypes.contains(type)
        let paragraph = type == "x-p" || type == "paragraph"
        let role: ParagraphRole? = type == "introduction" ? .ip : type == "outline" ? .io : nil

        if selfClosing, a["subType"] == "x-preverse" || a["subtype"] == "x-preverse" {
            if a["sID"] != nil {
                preverseOpen = true
            } else if a["eID"] != nil {
                closePreverseHeading()
                preverseOpen = false
            }
            return
        }

        if selfClosing {
            if let eID = a["eID"] {
                if division?.id == eID { endDivision() }
                if breaks { paragraph ? paragraphBreak() : out.blockBreak() }
                return
            }
            if breaks { paragraph ? paragraphBreak() : out.blockBreak() }
            if Self.sectionDivTypes.contains(type) { sectionKind = type }
            if let role {
                endDivision()
                division = MilestoneBlock(id: a["sID"], role: role, handle: out.openSpan(block: true))
            }
            return
        }

        if breaks { paragraph ? paragraphBreak() : out.blockBreak() }
        var frame = Frame(name: "div", kind: role.map { Frame.Kind.span(ScriptureText.Attribute.block($0), block: true) } ?? Frame.Kind.plain, breakAfter: breaks,
                          paragraph: paragraph)
        if Self.sectionDivTypes.contains(type) {
            frame.savedSection = sectionKind
            frame.hasSavedSection = true
            sectionKind = type
        }
        push(frame)
    }

    private mutating func push(_ frame: Frame) {
        var frame = frame
        switch frame.kind {
        case .span(_, let block): frame.handle = out.openSpan(block: block)
        case .title, .word: frame.handle = out.openSpan(block: false)
        case .skip: skipDepth += 1
        case .plain, .note: break
        }
        if case .title = frame.kind { out.headingDepth += 1 }
        if frame.editorial { out.editorialDepth += 1 }
        if frame.wordBoundary { out.wordBoundary() }
        stack.append(frame)
    }

    private mutating func closeTopFrame() {
        // The closing quotation mark belongs inside the frame (and so inside
        // the red letter), as SWORD renders it.
        if let closing = stack.last?.closingText {
            stack[stack.count - 1].closingText = nil
            characters(closing)
        }
        let frame = stack.removeLast()
        switch frame.kind {
        case .plain:
            break

        case .span(let attribute, _):
            if attribute == ScriptureText.Attribute.divineName { divineNameDepth -= 1 }
            if let handle = frame.handle { out.closeSpan(handle, as: attribute) }

        case .title(let role):
            out.headingDepth -= 1
            if let handle = frame.handle { out.closeSpan(handle, as: .block(role)) }
            out.markHeadingEnd()

        case .word(let lemma, let morph):
            out.wordDepth -= 1
            let started = frame.handle.flatMap { out.closeSpan($0, as: .word(lemma: lemma, morph: morph)) } != nil
            if started { out.emitWordMarkers(lemma: lemma, morph: morph) }

        case .skip:
            skipDepth -= 1

        case .note(let id):
            finishNote(id: id)
        }
        if frame.name == "x-preverse" { preverseHeadingOpen = false }
        if frame.editorial { out.editorialDepth -= 1 }
        if frame.wordBoundary { out.wordBoundary() }
        if frame.hasSavedSection { sectionKind = frame.savedSection }
        if frame.breakAfter { frame.paragraph ? paragraphBreak() : out.blockBreak() }
    }

    // MARK: Quotations

    /// SWORD's `<q>` rules (osisxhtml.cpp): an opening `<q>` or `<q sID/>`
    /// starts the words of Christ when `who="Jesus"`, then prints its mark; a
    /// closing `</q>` (using the opening tag's attributes) or `<q eID/>` prints
    /// its mark, then ends them. The mark is the `marker` attribute when there
    /// is one, even empty; otherwise `"` or `'` by level when `quoteMarks` is
    /// on. A self-closing `<q/>` with neither sID nor eID is ignored.
    private mutating func startQuote(_ a: [String: String], selfClosing: Bool) {
        let red = a["who"] == "Jesus" && options.redLetter
        let mark = quoteMark(a)

        if !selfClosing {
            push(Frame(name: "q", kind: red ? .span(.redLetter, block: false) : .plain,
                       breakAfter: false, closingText: mark))
            if let mark { characters(mark) }
            return
        }
        if a["sID"] != nil {
            if red {
                endRedQuote()
                redQuote = (id: a["sID"], handle: out.openSpan(block: false))
            }
            if let mark { characters(mark) }
        } else if a["eID"] != nil {
            if let mark { characters(mark) }
            if a["who"] == "Jesus" || (redQuote != nil && redQuote?.id == a["eID"]) { endRedQuote() }
        }
    }

    private func quoteMark(_ a: [String: String]) -> String? {
        if let marker = a["marker"] { return marker.isEmpty ? nil : marker }
        guard options.quoteMarks else { return nil }
        let level = Int(a["level"] ?? "") ?? 1
        return level % 2 == 1 ? "\"" : "'"
    }

    private mutating func endRedQuote() {
        guard let q = redQuote else { return }
        out.closeSpan(q.handle, as: .redLetter)
        redQuote = nil
    }

    // MARK: Milestone blocks (poetry lines, introductions)

    private mutating func startLine(_ a: [String: String], selfClosing: Bool) {
        let role: ParagraphRole = a["type"] == "selah"
            ? .qr
            : .poetry(level: Int(a["level"] ?? "") ?? 1)     // a missing level is level 1
        if selfClosing {
            if a["eID"] != nil {
                endLine()
            } else if a["sID"] != nil {
                endLine()
                out.blockBreak()
                line = MilestoneBlock(id: a["sID"], role: role, handle: out.openSpan(block: true))
            }
        } else {
            // container form <l>…</l>
            out.blockBreak()
            push(Frame(name: "l", kind: .span(.block(role), block: true), breakAfter: true, paragraph: true))
        }
    }

    private mutating func endLine() {
        guard let l = line else { return }
        out.closeSpan(l.handle, as: .block(l.role))
        line = nil
        lineBreak()
    }

    private mutating func endDivision() {
        guard let d = division else { return }
        out.closeSpan(d.handle, as: .block(d.role))
        division = nil
        out.blockBreak()
    }

    // MARK: Breaks

    /// A paragraph or line-group boundary: SWORD writes `<!P><br />` or `<!/P><br />`.
    private mutating func paragraphBreak() {
        out.lineBreak(counted: brCounts)
    }

    /// A line end or `<lb/>`: SWORD writes `<br />`.
    private mutating func lineBreak() {
        out.lineBreak(counted: brCounts)
    }

    /// A `<br />` of SWORD's counts only where its text is shown: SWORD removes a hidden
    /// heading, tags and all, before rendering.
    private var brCounts: Bool {
        !(skipDepth > 0 || (preverseOpen && !options.headings))
    }

    // MARK: Footnotes

    private mutating func finishNote(id: String) {
        guard out.inNote else { return }
        // A note inside a dropped variant reading is dropped with it.
        guard skipDepth == 0 else { out.discardNote(); return }
        // "x-strongsMarkup" notes are Strong's data, never shown (osisxhtml.cpp).
        let isCross = noteType == "crossReference"
        let show = noteType != "x-strongsMarkup" && noteType != "strongsMarkup"
            && (isCross ? options.crossReferences : options.footnotes)
        out.finishNote(id: id, kind: isCross ? .crossReference : .footnote, show: show)
    }
}
