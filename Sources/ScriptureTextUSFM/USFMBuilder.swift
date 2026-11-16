// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// USFM tokens to a ScriptureText (plan D88, Track V4), written through the builder core OSIS uses
// (`ScriptureTextBuilder`), so both formats get the same breaks, verse markers, word anchors and notes.
//
// USFM is a stream of point markers, not a tree:
//  • a paragraph marker (`\p`, `\q1`, `\s1`) ends the paragraph before it and every character style still open in it;
//  • `\v` and `\c` are points too: a verse runs to the next `\v`, across paragraph boundaries, and its number is the
//    first word after the marker (`\v 1-2` is a bridge, `\v 3a` a part, `\vp 1b\vp*` the printed number);
//  • a character style runs to its end marker (`\nd …\nd*`); `\+nd` nests one inside another; attributes follow a
//    `|` before the end marker (`\w beginning|strong="H7225"\w*`);
//  • a note (`\f + \fr 1.4 \ft …\f*`) starts with a caller and is made of parts that end at the next part;
//  • milestones (`\ts\*`, `\zaln-s |…\*`) and figures carry data the reader does not show; a quotation milestone by
//    Jesus (`\qt-s |who="Jesus"\*` … `\qt-e\*`) is red letter, like `\wj`, and carries on across paragraphs;
//  • alternate and published chapter numbers (`\ca`, `\cp`) and alternate verse numbers (`\va`) have no place in a
//    ScriptureText (the reader shows one numbering) and are skipped; so are word glosses (`gloss="…"`).
//
// Spans open only for text that is shown: text inside a note goes to the note, and a hidden heading's text only
// counts its words, so no span waits there to start on the next shown text.

import Foundation
import ScriptureText
import ScriptureTextBuilding

struct USFMBuilder {

    private let options: USFMParser.Options
    private var out: ScriptureTextBuilder
    private let transforms: TextTransforms

    /// Reading the book's own lines before its first chapter: its titles and introduction, not its chapter label.
    var inPrelude = false

    private enum Expected { case verseNumber, chapterNumber, noteCaller }
    private var expected: Expected?

    private struct PendingVerse { var first: Int; var last: Int?; var label: String? }
    /// A `\v` whose marker waits for a `\vp` or for its first text.
    private var pendingVerse: PendingVerse?
    /// A paragraph has opened and no text has followed yet; an opening `¶` (KJV 2006 prints one) repeats the break.
    private var paragraphOpening = false

    private enum Skip: Equatable {
        /// Book metadata: text up to the next marker.
        case untilMarker
        /// Everything up to this end marker (a figure, an alternate number, a printed verse number).
        case until(String)
        /// A milestone's attributes, up to `\*`.
        case milestone
        /// A sidebar, up to `\esbe`.
        case sidebar
    }
    private var skip: Skip?
    private var publishedLabel = ""

    private var paragraph: (role: ParagraphRole?, handle: ScriptureTextBuilder.SpanHandle?)?
    private var heading: (role: ParagraphRole, handle: ScriptureTextBuilder.SpanHandle?, shown: Bool)?

    private struct CharacterFrame {
        var name: String
        var style: USFMMarker.CharacterStyle
        var handle: ScriptureTextBuilder.SpanHandle?
        /// Opened inside a note: closed with it.
        var inNote: Bool
        /// The attribute text after `|`, and whether text is going there now.
        var attributes = ""
        var inAttributes = false
        /// A tagged word has had text before its `|`.
        var sawText = false
        /// `\w -|strong="G2532"\w*`: a placeholder for a word the translation does not render. It shows nothing but
        /// keeps its number, as SWORD's empty `<w lemma="…"/>` does.
        var placeholder = false
        /// The shown text, for a link with no target attribute.
        var text = ""
    }
    private var characters: [CharacterFrame] = []
    private var divineNameDepth = 0

    /// Inside `\qt-s |who="Jesus"\*` … `\qt-e\*`: words of Jesus, red letter until the milestone ends.
    private var quotationByJesus = false
    private static let quotationFrame = "\u{0}qt"
    /// A milestone being read: its name and attribute text.
    private var milestoneName = ""
    private var milestoneAttributes = ""

    /// The text of a `\xt` (a cross-reference target) inside a note, and its attributes after `|`.
    private var targetText: String?
    private var targetAttributes = ""
    private var targetInAttributes = false

    private var noteName: String?
    private var noteID = ""
    private var noteIsCrossReference = false
    private var noteDropping = false
    private var noteOrdinal = 0

    init(options: USFMParser.Options) {
        self.options = options
        self.transforms = TextTransforms(greekAccents: options.greekAccents, hebrewPoints: options.hebrewPoints,
                                         hebrewCantillation: options.hebrewCantillation)
        var shared = ScriptureTextBuilder.Options()
        shared.verseNumbers = options.verseNumbers
        shared.versePerLine = options.versePerLine
        shared.strongsMarkers = options.strongsMarkers
        shared.morphMarkers = options.morphMarkers
        out = ScriptureTextBuilder(options: shared)
        out.beginVerse(0)                            // text before the first verse: headings, the introduction
    }

    // MARK: Tokens

    mutating func handle(_ token: USFMToken) {
        if skip != nil, consumeSkipped(token) { return }
        switch token {
        case .text(let text): self.text(text)
        case .marker(let name, _): marker(name)
        case .end(let name, _): end(name)
        }
    }

    mutating func finish() -> ScriptureText {
        if pendingVerse != nil { beginPendingVerse() }
        endBlock()
        return out.finish()
    }

    /// Whether a skipped region swallowed the token.
    private mutating func consumeSkipped(_ token: USFMToken) -> Bool {
        switch skip {
        case .untilMarker:
            if case .text = token { return true }
            skip = nil
            return false
        case .milestone:
            switch token {
            case .end(let name, _) where name.isEmpty: finishMilestone(); return true
            case .text(let text): milestoneAttributes += text; return true
            default: finishMilestone(); return false        // a milestone left open
            }
        case .until(let name):
            switch token {
            case .end(let ended, _) where ended == name:
                finishSkip(name)
                return true
            case .text(let text):
                if name == "vp" { publishedLabel += text }
                return true
            case .marker(let next, _) where Self.endsSkippedRun(USFMMarker.named(next)):
                finishSkip(name)                            // never closed: it ends where its paragraph or verse does
                return false
            default:
                return true
            }
        case .sidebar:
            if case .marker("esbe", _) = token { skip = nil }
            return true
        case nil:
            return false
        }
    }

    /// A milestone ended: a quotation by Jesus starts or ends red letter.
    private mutating func finishMilestone() {
        skip = nil
        let name = milestoneName
        defer { milestoneName = ""; milestoneAttributes = "" }
        guard name.hasPrefix("qt") else { return }
        if name.hasSuffix("-s") {
            let who = Self.attributes(milestoneAttributes)["who"] ?? ""
            guard who.localizedCaseInsensitiveContains("Jesus"), !quotationByJesus else { return }
            quotationByJesus = true
            if paragraph != nil, heading == nil { openCharacter(Self.quotationFrame, style: .redLetter) }
        } else if name.hasSuffix("-e") {
            quotationByJesus = false
            if let index = characters.lastIndex(where: { $0.name == Self.quotationFrame }) {
                while characters.count > index { closeTopCharacter() }
            }
        }
    }

    private mutating func finishSkip(_ name: String) {
        if name == "vp" {
            let label = publishedLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty { pendingVerse?.label = label }
            publishedLabel = ""
        }
        skip = nil
    }

    private static func endsSkippedRun(_ marker: USFMMarker) -> Bool {
        switch marker {
        case .verse, .chapter, .heading, .paragraph, .blankLine, .noBreak, .note: return true
        default: return false
        }
    }

    // MARK: Text

    private mutating func text(_ original: String) {
        var text = original
        if let expected {
            self.expected = nil
            let (word, rest) = Self.firstWord(of: text)
            switch expected {
            case .verseNumber:
                if let verse = Self.verseNumber(word) {
                    pendingVerse = verse
                    text = rest
                }
            case .chapterNumber, .noteCaller:
                text = rest
            }
            if text.isEmpty { return }
        }
        if paragraphOpening, let first = text.unicodeScalars.first(where: { !ScriptureTextBuilder.isMarkupSpace($0) }) {
            paragraphOpening = false
            if first == "\u{00B6}" {
                let rest = text.drop { ScriptureTextBuilder.isMarkupSpace($0.unicodeScalars.first!) }.dropFirst()
                text = String(rest.drop { ScriptureTextBuilder.isMarkupSpace($0.unicodeScalars.first!) })
                if text.isEmpty { return }
            }
        }
        if pendingVerse != nil, text.unicodeScalars.contains(where: { !ScriptureTextBuilder.isMarkupSpace($0) }) {
            beginPendingVerse()
        }
        if targetText != nil {
            if targetInAttributes { targetAttributes += text; return }
            if let bar = text.firstIndex(of: "|") {
                targetAttributes = String(text[text.index(after: bar)...])
                targetInAttributes = true
                text = String(text[..<bar])
            }
        }
        // Attributes: after `|` in a word or a link, up to its end marker.
        if let top = characters.indices.last, characters[top].style == .word || characters[top].style == .link {
            if characters[top].inAttributes {
                characters[top].attributes += text
                return
            }
            if let bar = text.firstIndex(of: "|") {
                characters[top].attributes = String(text[text.index(after: bar)...])
                characters[top].inAttributes = true
                text = String(text[..<bar])
                if characters[top].style == .word, !characters[top].sawText,
                   text.trimmingCharacters(in: .whitespacesAndNewlines) == "-" {
                    characters[top].placeholder = true
                    return
                }
            }
            if characters[top].style == .word, !text.isEmpty { characters[top].sawText = true }
        }
        content(text)
    }

    /// `//` is an optional line break in USFM: a place a line may be broken, which text that reflows does not need. It stays
    /// when a colon comes before it (a URL), and where it is the only thing between two words it leaves a space.
    static func withoutOptionalLineBreaks(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var result = String.UnicodeScalarView()
        var index = 0
        func isSpace(_ scalar: Unicode.Scalar) -> Bool { scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" }
        while index < scalars.count {
            guard scalars[index] == "/", index + 1 < scalars.count, scalars[index + 1] == "/" else {
                result.append(scalars[index])
                index += 1
                continue
            }
            let before = result.last
            if before == ":" {                                 // `https://…`
                result.append("/"); result.append("/")
                index += 2
                continue
            }
            index += 2
            let beforeIsSpace = before.map(isSpace) ?? true
            if beforeIsSpace {
                while index < scalars.count, isSpace(scalars[index]) { index += 1 }     // one space is enough
            } else if index < scalars.count, !isSpace(scalars[index]) {
                result.append(" ")                             // `praise//him` is two words
            }
        }
        return String(result)
    }

    private mutating func content(_ original: String) {
        guard !original.isEmpty else { return }
        // `~` is a no-break space; `//` an optional line break, which the reader does not use (but not after a colon: that is
        // the `//` of a URL).
        var raw = original.contains("~") ? original.replacingOccurrences(of: "~", with: "\u{00A0}") : original
        if raw.contains("//") { raw = Self.withoutOptionalLineBreaks(raw) }
        raw = transforms.apply(raw)
        // As OSIS: the divine name is capitals, and the styler draws all but the first letter smaller.
        if divineNameDepth > 0 { raw = raw.uppercased() }
        if out.inNote {
            if !noteDropping { out.appendToNote(raw) }
            if targetText != nil { targetText! += raw }
            return
        }
        for index in characters.indices where characters[index].style == .link && !characters[index].inAttributes {
            characters[index].text += raw
        }
        if heading?.shown == false {
            out.countHiddenWords(raw)
            return
        }
        out.emit(raw)
    }

    // MARK: Markers

    private mutating func marker(_ name: String) {
        let marker = USFMMarker.named(name)
        if pendingVerse != nil, marker != .publishedVerse { beginPendingVerse() }
        expected = nil
        flushTarget()
        switch marker {
        case .identification:
            skip = .untilMarker
        case .chapter:
            expected = .chapterNumber
        case .verse:
            if let current = heading, !current.role.isCanonical { closeHeading() }   // a verse ends a section heading
            closeShortLived()
            expected = .verseNumber
        case .heading(let role, let canonical):
            if inPrelude, role == .cl { skip = .untilMarker; return }   // the label for every chapter
            startHeading(role, canonical: canonical)
        case .paragraph(let role):
            startParagraph(role)
        case .noBreak:
            endBlock()
            paragraph = (role: nil, handle: nil)
        case .blankLine:
            endBlock()
            out.lineBreak()
            out.lineBreak()
        case .character(let style):
            openCharacter(name, style: style)
        case .note(let crossReference):
            openNote(name, crossReference: crossReference)
        case .notePart(let dropped):
            if out.inNote {
                noteDropping = dropped
                if name == "xt" { targetText = ""; targetAttributes = ""; targetInAttributes = false }
            }
        case .alternateVerse:
            skip = .until("va")
        case .alternateChapter:
            skip = .until("ca")
        case .publishedVerse:
            publishedLabel = ""
            skip = .until("vp")
        case .publishedChapter:
            skip = .untilMarker
        case .hiddenCharacter:
            skip = .until(name)
        case .milestone:
            milestoneName = name
            milestoneAttributes = ""
            skip = .milestone
        case .sidebarStart:
            skip = .sidebar
        case .sidebarEnd:
            break
        }
    }

    private mutating func end(_ name: String) {
        guard !name.isEmpty else { return }                 // a stray `\*`
        switch USFMMarker.named(name) {
        case .note:
            if out.inNote, name == noteName { closeNote() }
        case .notePart:
            if out.inNote { flushTarget(); noteDropping = false }
        default:
            guard let index = characters.lastIndex(where: { $0.name == name }) else { return }
            while characters.count > index { closeTopCharacter() }
        }
    }

    // MARK: Verses

    private mutating func beginPendingVerse() {
        guard let verse = pendingVerse else { return }
        pendingVerse = nil
        out.endVerse(at: out.contentEnd)                 // a heading before this verse is not the last one's
        out.beginVerse(verse.first, lastVerse: verse.last, label: verse.label)
    }

    /// Notes and tagged words belong to one verse: one left open is closed at the next `\v`.
    private mutating func closeShortLived() {
        closeNote()
        if let index = characters.firstIndex(where: { $0.style == .word }) {
            while characters.count > index { closeTopCharacter() }
        }
    }

    /// The first whitespace-separated word of `text`, and the text after the one space that ends it.
    private static func firstWord(of text: String) -> (String, String) {
        let scalars = text.unicodeScalars
        guard let start = scalars.firstIndex(where: { !ScriptureTextBuilder.isMarkupSpace($0) }) else { return ("", "") }
        let end = scalars[start...].firstIndex(where: { ScriptureTextBuilder.isMarkupSpace($0) }) ?? scalars.endIndex
        let word = String(scalars[start..<end])
        let rest = end < scalars.endIndex ? String(scalars[scalars.index(after: end)...]) : ""
        return (word, rest)
    }

    /// `5`, `1-2` (a bridge), `3a` or `12-13a` (printed as written).
    private static func verseNumber(_ word: String) -> PendingVerse? {
        let digits = word.prefix { $0.isASCII && $0.isNumber }
        guard let first = Int(digits) else { return nil }
        var rest = word.dropFirst(digits.count)
        var last: Int?
        if rest.first == "-" || rest.first == "\u{2013}" {
            let lastDigits = rest.dropFirst().prefix { $0.isASCII && $0.isNumber }
            if let value = Int(lastDigits), value > first {
                last = value
                rest = rest.dropFirst(1 + lastDigits.count)
            }
        }
        return PendingVerse(first: first, last: last, label: rest.isEmpty ? nil : word)
    }

    // MARK: Paragraphs and headings

    private mutating func startParagraph(_ role: ParagraphRole?) {
        endBlock()
        out.lineBreak()
        paragraphOpening = true
        paragraph = (role: role, handle: role == nil ? nil : out.openSpan(block: true))
        if quotationByJesus { openCharacter(Self.quotationFrame, style: .redLetter) }   // the quotation goes on
    }

    private mutating func startHeading(_ role: ParagraphRole, canonical: Bool) {
        paragraphOpening = false
        endBlock()
        out.blockBreak()
        // As OSIS: a canonical heading (a Psalm title) shows even with headings off.
        let shown = options.headings || canonical
        if shown { out.clearBreakCount() }               // a shown heading carries its own space
        out.headingDepth += 1
        if !role.isCanonical { out.editorialDepth += 1 }
        heading = (role: role, handle: shown ? out.openSpan(block: false) : nil, shown: shown)
    }

    private mutating func closeHeading() {
        guard let current = heading else { return }
        while !characters.isEmpty { closeTopCharacter() }
        if let handle = current.handle { out.closeSpan(handle, as: .block(current.role)) }
        out.markHeadingEnd()
        out.headingDepth -= 1
        if !current.role.isCanonical { out.editorialDepth -= 1 }
        heading = nil
        out.blockBreak()
    }

    private mutating func endParagraph() {
        while !characters.isEmpty { closeTopCharacter() }
        if let current = paragraph, let handle = current.handle, let role = current.role {
            out.closeSpan(handle, as: .block(role))
        }
        paragraph = nil
    }

    /// Everything a paragraph marker ends: a note left open, the character styles, the heading or paragraph.
    private mutating func endBlock() {
        closeNote()
        closeHeading()
        endParagraph()
    }

    // MARK: Character styles

    private mutating func openCharacter(_ name: String, style: USFMMarker.CharacterStyle) {
        let shown = !out.inNote && heading?.shown != false
        let spanned: Bool
        switch style {
        case .plain: spanned = false
        case .redLetter: spanned = options.redLetter
        default: spanned = true
        }
        if style == .word {
            out.wordBoundary()                           // a tagged word starts a word
            out.wordDepth += 1
        }
        if style == .divineName { divineNameDepth += 1 }
        characters.append(CharacterFrame(name: name, style: style, handle: shown && spanned ? out.openSpan(block: false) : nil,
                                         inNote: out.inNote))
    }

    private mutating func closeTopCharacter() {
        let frame = characters.removeLast()
        switch frame.style {
        case .word:
            out.wordDepth -= 1
            let (lemma, morph) = Self.wordAttributes(frame.attributes)
            if frame.placeholder {
                // No text and no word, but the markers where it stands, when the word would have been shown.
                if let handle = frame.handle {
                    out.closeSpan(handle, as: nil)
                    out.emitWordMarkers(lemma: lemma, morph: morph)
                }
                return
            }
            let started = frame.handle.flatMap { out.closeSpan($0, as: .word(lemma: lemma, morph: morph)) } != nil
            if started { out.emitWordMarkers(lemma: lemma, morph: morph) }
        case .link:
            let target = Self.linkTarget(frame.attributes, text: frame.text)
            if let handle = frame.handle { out.closeSpan(handle, as: target.map { .link(target: $0) }) }
        case .divineName:
            divineNameDepth -= 1
            if let handle = frame.handle { out.closeSpan(handle, as: .divineName) }
        case .plain:
            break
        case .italic, .bold, .small, .redLetter:
            if let handle = frame.handle { out.closeSpan(handle, as: Self.attribute(frame.style)) }
        }
    }

    private static func attribute(_ style: USFMMarker.CharacterStyle) -> ScriptureText.Attribute? {
        switch style {
        case .italic: return .italic
        case .bold: return .bold
        case .small: return .small
        case .redLetter: return .redLetter
        case .divineName: return .divineName
        case .plain, .word, .link: return nil
        }
    }

    /// `key="value"` pairs; text with no `=` is the default attribute (`lemma` for a word).
    static func attributes(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return result }
        guard trimmed.contains("=") else { return ["": trimmed] }
        var rest = Substring(trimmed)
        while let equals = rest.firstIndex(of: "=") {
            let key = rest[..<equals].trimmingCharacters(in: .whitespaces)
            rest = rest[rest.index(after: equals)...]
            guard let open = rest.firstIndex(of: "\"") else { break }
            let afterOpen = rest.index(after: open)
            let close = rest[afterOpen...].firstIndex(of: "\"") ?? rest.endIndex
            result[key] = String(rest[afterOpen..<close])
            rest = close < rest.endIndex ? rest[rest.index(after: close)...] : ""
        }
        return result
    }

    /// The word's lemma tokens as OSIS writes them: `strong:H0430` for each Strong's number (USFM separates them
    /// with commas), `lemma.usfm:…` for a lexical form, which SWORD's rules keep out of the Strong's markers; and its
    /// morphology.
    private static func wordAttributes(_ text: String) -> (lemma: String?, morph: String?) {
        let pairs = attributes(text)
        var tokens: [String] = []
        if let strong = pairs["strong"] {
            for number in strong.split(whereSeparator: { $0 == "," || $0 == " " }) {
                let value = number.trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { tokens.append(value.contains(":") ? value : "strong:" + value) }
            }
        }
        if let lemma = pairs["lemma"] ?? pairs[""], !lemma.isEmpty { tokens.append("lemma.usfm:" + lemma) }
        let morph = pairs["x-morph"] ?? pairs["morph"]
        return (tokens.isEmpty ? nil : tokens.joined(separator: " "), morph?.isEmpty == false ? morph : nil)
    }

    /// `\ref Gen 1:1|loc="GEN 1:1"\ref*` and `\jmp text|link-href="…"\jmp*`.
    private static func linkTarget(_ attributeText: String, text: String) -> String? {
        let pairs = attributes(attributeText)
        if let href = pairs["link-href"], !href.isEmpty { return href }
        let location = (pairs["loc"] ?? pairs[""] ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
        return location.isEmpty ? nil : "passage:" + location
    }

    // MARK: Notes

    private mutating func openNote(_ name: String, crossReference: Bool) {
        guard !out.inNote else { return }                // a note inside a note is its text
        noteOrdinal += 1
        noteName = name
        noteID = "\(out.currentVerse ?? 0).\(noteOrdinal)"
        noteIsCrossReference = crossReference
        noteDropping = false
        out.beginNote()
        expected = .noteCaller
    }

    /// A `\xt` ended: its text (or its `link-href`) is a reference the note cites.
    private mutating func flushTarget() {
        guard let text = targetText else { return }
        targetText = nil
        let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".;,:"))
        var reference = text.trimmingCharacters(in: trimSet)
        if reference.isEmpty { reference = (Self.attributes(targetAttributes)["link-href"] ?? "").trimmingCharacters(in: trimSet) }
        if !reference.isEmpty { out.addNoteReference(reference) }
    }

    private mutating func closeNote() {
        guard out.inNote else { return }
        flushTarget()
        while let last = characters.last, last.inNote { closeTopCharacter() }
        if heading?.shown == false {
            out.discardNote()                            // a hidden heading's note is hidden with it
        } else {
            out.finishNote(id: noteID, kind: noteIsCrossReference ? .crossReference : .footnote,
                           show: noteIsCrossReference ? options.crossReferences : options.footnotes)
        }
        noteName = nil
        noteDropping = false
    }
}
