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

/// A class: one per parse, changed in place (see the speed rules in Transpile/README.md).
final class USFMBuilder {

    private let options: USFMParser.Options
    private let out: ScriptureTextBuilder
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

    private struct ParagraphState { var role: ParagraphRole?; var handle: ScriptureTextBuilder.SpanHandle? }
    private struct HeadingState { var role: ParagraphRole; var handle: ScriptureTextBuilder.SpanHandle?; var shown: Bool }
    private var paragraph: ParagraphState?
    private var heading: HeadingState?

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
    private static let quotationFrame = "\u{0000}qt"
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

    func handle(_ token: USFMToken) {
        if skip != nil, consumeSkipped(token) { return }
        switch token {
        case .text(let text): self.text(text)
        case .marker(let name, _): marker(name)
        case .end(let name, _): end(name)
        }
    }

    func finish() -> ScriptureText {
        if pendingVerse != nil { beginPendingVerse() }
        endBlock()
        return out.finish()
    }

    /// Whether a skipped region swallowed the token.
    private func consumeSkipped(_ token: USFMToken) -> Bool {
        guard let current = skip else { return false }
        switch current {
        case .untilMarker:
            if case .text = token { return true }
            skip = nil
            return false
        case .milestone:
            switch token {
            case .end(let name, _):
                if name.isEmpty { finishMilestone(); return true }
                finishMilestone()                           // a milestone left open
                return false
            case .text(let text):
                milestoneAttributes += text
                return true
            case .marker:
                finishMilestone()                           // a milestone left open
                return false
            }
        case .until(let name):
            switch token {
            case .end(let ended, _):
                if ended == name { finishSkip(name) }
                return true
            case .text(let text):
                if name == "vp" { publishedLabel += text }
                return true
            case .marker(let next, _):
                if Self.endsSkippedRun(USFMMarker.named(next)) {
                    finishSkip(name)                        // never closed: it ends where its paragraph or verse does
                    return false
                }
                return true
            }
        case .sidebar:
            if case .marker(let name, _) = token, name == "esbe" { skip = nil }
            return true
        }
    }

    /// A milestone ended: a quotation by Jesus starts or ends red letter.
    private func finishMilestone() {
        skip = nil
        let name = milestoneName
        defer { milestoneName = ""; milestoneAttributes = "" }
        guard name.hasPrefix("qt") else { return }
        if name.hasSuffix("-s") {
            let who = Self.attributes(milestoneAttributes)["who"] ?? ""
            guard who.lowercased().contains("jesus"), !quotationByJesus else { return }
            quotationByJesus = true
            if paragraph != nil, heading == nil { openCharacter(Self.quotationFrame, style: USFMMarker.CharacterStyle.redLetter) }
        } else if name.hasSuffix("-e") {
            quotationByJesus = false
            if let index = characters.lastIndex(where: { $0.name == Self.quotationFrame }) {
                while characters.count > index { closeTopCharacter() }
            }
        }
    }

    private func finishSkip(_ name: String) {
        if name == "vp" {
            let label = Self.trimmed(publishedLabel)
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

    private func text(_ original: String) {
        var text = original
        if let expecting = expected {
            self.expected = nil
            let split = Self.firstWord(of: text)
            switch expecting {
            case .verseNumber:
                if let verse = Self.verseNumber(split.word) {
                    pendingVerse = verse
                    text = split.rest
                }
            case .chapterNumber, .noteCaller:
                text = split.rest
            }
            if text.isEmpty { return }
        }
        if paragraphOpening {
            let codes = CodePoints.of(text)
            var first = 0
            while first < codes.count && ScriptureTextBuilder.isMarkupSpace(codes[first]) { first += 1 }
            if first < codes.count {
                paragraphOpening = false
                if codes[first] == 0xB6 {                       // an opening pilcrow, and the space around it
                    var after = first + 1
                    while after < codes.count && ScriptureTextBuilder.isMarkupSpace(codes[after]) { after += 1 }
                    text = CodePoints.string(codes, after, codes.count)
                    if text.isEmpty { return }
                }
            }
        }
        if pendingVerse != nil, ScriptureTextBuilder.hasContent(text) {
            beginPendingVerse()
        }
        if targetText != nil {
            if targetInAttributes { targetAttributes += text; return }
            if let split = Self.splitAtBar(text) {
                targetAttributes = split.after
                targetInAttributes = true
                text = split.before
            }
        }
        // Attributes: after `|` in a word or a link, up to its end marker.
        let top = characters.count - 1
        if top >= 0, characters[top].style == USFMMarker.CharacterStyle.word || characters[top].style == USFMMarker.CharacterStyle.link {
            if characters[top].inAttributes {
                characters[top].attributes += text
                return
            }
            if let split = Self.splitAtBar(text) {
                characters[top].attributes = split.after
                characters[top].inAttributes = true
                text = split.before
                if characters[top].style == USFMMarker.CharacterStyle.word, !characters[top].sawText, Self.trimmed(text) == "-" {
                    characters[top].placeholder = true
                    return
                }
            }
            if characters[top].style == USFMMarker.CharacterStyle.word, !text.isEmpty { characters[top].sawText = true }
        }
        content(text)
    }

    /// Text before and after a `|`.
    private struct BarSplit {
        var before: String
        var after: String
    }

    /// `text` split at its first `|`, or nil when it has none.
    private static func splitAtBar(_ text: String) -> BarSplit? {
        let codes = CodePoints.of(text)
        var bar = 0
        while bar < codes.count && codes[bar] != 0x7C { bar += 1 }
        guard bar < codes.count else { return nil }
        return BarSplit(before: CodePoints.string(codes, 0, bar), after: CodePoints.string(codes, bar + 1, codes.count))
    }

    /// Without white space and line ends at its ends (Foundation's `CharacterSet.whitespacesAndNewlines`).
    private static func trimmed(_ text: String) -> String {
        CodePoints.trimmed(text, where: { CodePoints.isWhiteSpaceOrNewline($0) })
    }

    /// `//` is an optional line break in USFM: a place a line may be broken, which text that reflows does not need. It stays
    /// when a colon comes before it (a URL), and where it is the only thing between two words it leaves a space.
    static func withoutOptionalLineBreaks(_ text: String) -> String {
        let codes = CodePoints.of(text)
        var result: [Int] = []
        var index = 0
        while index < codes.count {
            guard codes[index] == 0x2F, index + 1 < codes.count, codes[index + 1] == 0x2F else {
                result.append(codes[index])
                index += 1
                continue
            }
            let before = result.last
            if before == 0x3A {                                 // `https://…`
                result.append(0x2F)
                result.append(0x2F)
                index += 2
                continue
            }
            index += 2
            let beforeIsSpace = before == nil || ScriptureTextBuilder.isMarkupSpace(before!)
            if beforeIsSpace {
                while index < codes.count, ScriptureTextBuilder.isMarkupSpace(codes[index]) { index += 1 }     // one space is enough
            } else if index < codes.count, !ScriptureTextBuilder.isMarkupSpace(codes[index]) {
                result.append(0x20)                             // `praise//him` is two words
            }
        }
        return CodePoints.string(result)
    }

    private func content(_ original: String) {
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
            if let target = targetText { targetText = target + raw }
            return
        }
        var index = 0
        while index < characters.count {
            if characters[index].style == USFMMarker.CharacterStyle.link && !characters[index].inAttributes { characters[index].text += raw }
            index += 1
        }
        if heading?.shown == false {
            out.countHiddenWords(raw)
            return
        }
        out.emit(raw)
    }

    // MARK: Markers

    private func marker(_ name: String) {
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
            if inPrelude, role == ParagraphRole.cl { skip = Skip.untilMarker; return }   // the label for every chapter
            startHeading(role, canonical: canonical)
        case .paragraph(let role):
            startParagraph(role)
        case .noBreak:
            endBlock()
            paragraph = ParagraphState(role: nil, handle: nil)
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

    private func end(_ name: String) {
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

    private func beginPendingVerse() {
        guard let verse = pendingVerse else { return }
        pendingVerse = nil
        out.endVerse(at: out.contentEnd)                 // a heading before this verse is not the last one's
        out.beginVerse(verse.first, lastVerse: verse.last, label: verse.label)
    }

    /// Notes and tagged words belong to one verse: one left open is closed at the next `\v`.
    private func closeShortLived() {
        closeNote()
        if let index = characters.firstIndex(where: { $0.style == .word }) {
            while characters.count > index { closeTopCharacter() }
        }
    }

    /// A word, and the text after it.
    private struct WordSplit {
        var word: String
        var rest: String
    }

    /// The first whitespace-separated word of `text`, and the text after the one space that ends it.
    private static func firstWord(of text: String) -> WordSplit {
        let codes = CodePoints.of(text)
        var start = 0
        while start < codes.count && ScriptureTextBuilder.isMarkupSpace(codes[start]) { start += 1 }
        guard start < codes.count else { return WordSplit(word: "", rest: "") }
        var end = start
        while end < codes.count && !ScriptureTextBuilder.isMarkupSpace(codes[end]) { end += 1 }
        let rest = end < codes.count ? CodePoints.string(codes, end + 1, codes.count) : ""
        return WordSplit(word: CodePoints.string(codes, start, end), rest: rest)
    }

    private static func isASCIIDigit(_ c: Int) -> Bool { c >= 0x30 && c <= 0x39 }

    /// `5`, `1-2` (a bridge), `3a` or `12-13a` (printed as written).
    private static func verseNumber(_ word: String) -> PendingVerse? {
        let codes = CodePoints.of(word)
        var digits = 0
        while digits < codes.count && isASCIIDigit(codes[digits]) { digits += 1 }
        guard let first = Int(CodePoints.string(codes, 0, digits)) else { return nil }
        var rest = digits
        var last: Int?
        if rest < codes.count && (codes[rest] == 0x2D || codes[rest] == 0x2013) {
            var end = rest + 1
            while end < codes.count && isASCIIDigit(codes[end]) { end += 1 }
            if let value = Int(CodePoints.string(codes, rest + 1, end)), value > first {
                last = value
                rest = end
            }
        }
        return PendingVerse(first: first, last: last, label: rest == codes.count ? nil : word)
    }

    // MARK: Paragraphs and headings

    private func startParagraph(_ role: ParagraphRole?) {
        endBlock()
        out.lineBreak()
        paragraphOpening = true
        paragraph = ParagraphState(role: role, handle: role == nil ? nil : out.openSpan(block: true))
        if quotationByJesus { openCharacter(Self.quotationFrame, style: USFMMarker.CharacterStyle.redLetter) }   // the quotation goes on
    }

    private func startHeading(_ role: ParagraphRole, canonical: Bool) {
        paragraphOpening = false
        endBlock()
        out.blockBreak()
        // As OSIS: a canonical heading (a Psalm title) shows even with headings off.
        let shown = options.headings || canonical
        if shown { out.clearBreakCount() }               // a shown heading carries its own space
        out.headingDepth += 1
        if !role.isCanonical { out.editorialDepth += 1 }
        heading = HeadingState(role: role, handle: shown ? out.openSpan(block: false) : nil, shown: shown)
    }

    private func closeHeading() {
        guard let current = heading else { return }
        while !characters.isEmpty { closeTopCharacter() }
        if let handle = current.handle { out.closeSpan(handle, as: ScriptureText.Attribute.block(current.role)) }
        out.markHeadingEnd()
        out.headingDepth -= 1
        if !current.role.isCanonical { out.editorialDepth -= 1 }
        heading = nil
        out.blockBreak()
    }

    private func endParagraph() {
        while !characters.isEmpty { closeTopCharacter() }
        if let current = paragraph, let handle = current.handle, let role = current.role {
            out.closeSpan(handle, as: ScriptureText.Attribute.block(role))
        }
        paragraph = nil
    }

    /// Everything a paragraph marker ends: a note left open, the character styles, the heading or paragraph.
    private func endBlock() {
        closeNote()
        closeHeading()
        endParagraph()
    }

    // MARK: Character styles

    private func openCharacter(_ name: String, style: USFMMarker.CharacterStyle) {
        let shown = !out.inNote && heading?.shown != false
        let spanned: Bool
        switch style {
        case .plain: spanned = false
        case .redLetter: spanned = options.redLetter
        default: spanned = true
        }
        if style == USFMMarker.CharacterStyle.word {
            out.wordBoundary()                           // a tagged word starts a word
            out.wordDepth += 1
        }
        if style == USFMMarker.CharacterStyle.divineName { divineNameDepth += 1 }
        characters.append(CharacterFrame(name: name, style: style, handle: shown && spanned ? out.openSpan(block: false) : nil,
                                         inNote: out.inNote))
    }

    private func closeTopCharacter() {
        let frame = characters.removeLast()
        switch frame.style {
        case .word:
            out.wordDepth -= 1
            let data = Self.wordAttributes(frame.attributes)
            if frame.placeholder {
                // No text and no word, but the markers where it stands, when the word would have been shown.
                if let handle = frame.handle {
                    out.closeSpan(handle, as: nil)
                    out.emitWordMarkers(lemma: data.lemma, morph: data.morph)
                }
                return
            }
            var started = false
            if let handle = frame.handle {
                started = out.closeSpan(handle, as: ScriptureText.Attribute.word(lemma: data.lemma, morph: data.morph)) != nil
            }
            if started { out.emitWordMarkers(lemma: data.lemma, morph: data.morph) }
        case .link:
            let target = Self.linkTarget(frame.attributes, text: frame.text)
            if let handle = frame.handle {
                if let target {
                    out.closeSpan(handle, as: ScriptureText.Attribute.link(target: target))
                } else {
                    out.closeSpan(handle, as: nil)
                }
            }
        case .divineName:
            divineNameDepth -= 1
            if let handle = frame.handle { out.closeSpan(handle, as: ScriptureText.Attribute.divineName) }
        case .plain:
            break
        case .italic, .bold, .small, .redLetter:
            if let handle = frame.handle { out.closeSpan(handle, as: Self.attribute(frame.style)) }
        }
    }

    private static func attribute(_ style: USFMMarker.CharacterStyle) -> ScriptureText.Attribute? {
        switch style {
        case .italic: return ScriptureText.Attribute.italic
        case .bold: return ScriptureText.Attribute.bold
        case .small: return ScriptureText.Attribute.small
        case .redLetter: return ScriptureText.Attribute.redLetter
        case .divineName: return ScriptureText.Attribute.divineName
        case .plain, .word, .link: return nil
        }
    }

    /// `key="value"` pairs; text with no `=` is the default attribute (`lemma` for a word).
    static func attributes(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        let whole = trimmed(text)
        guard !whole.isEmpty else { return result }
        guard whole.contains("=") else { return ["": whole] }
        let codes = CodePoints.of(whole)
        var rest = 0
        while true {
            var equals = rest
            while equals < codes.count && codes[equals] != 0x3D { equals += 1 }
            guard equals < codes.count else { break }
            let key = CodePoints.trimmed(CodePoints.string(codes, rest, equals), where: { CodePoints.isHorizontalWhiteSpace($0) })
            rest = equals + 1
            var open = rest
            while open < codes.count && codes[open] != 0x22 { open += 1 }
            guard open < codes.count else { break }
            var close = open + 1
            while close < codes.count && codes[close] != 0x22 { close += 1 }
            result[key] = CodePoints.string(codes, open + 1, close)
            rest = close < codes.count ? close + 1 : codes.count
        }
        return result
    }

    /// The word's lemma tokens as OSIS writes them: `strong:H0430` for each Strong's number (USFM separates them
    /// with commas), `lemma.usfm:…` for a lexical form, which SWORD's rules keep out of the Strong's markers; and its
    /// morphology.
    /// A word's lemma tokens and morphology.
    private struct WordData {
        var lemma: String?
        var morph: String?
    }

    private static func wordAttributes(_ text: String) -> WordData {
        let pairs = attributes(text)
        var tokens: [String] = []
        if let strong = pairs["strong"] {
            let codes = CodePoints.of(strong)
            var start = 0
            var k = 0
            while k <= codes.count {
                if k == codes.count || codes[k] == 0x2C || codes[k] == 0x20 {   // a comma or a space ends a number
                    if k > start {
                        let value = CodePoints.trimmed(CodePoints.string(codes, start, k), where: { CodePoints.isHorizontalWhiteSpace($0) })
                        if !value.isEmpty { tokens.append(value.contains(":") ? value : "strong:" + value) }
                    }
                    start = k + 1
                }
                k += 1
            }
        }
        if let lemma = pairs["lemma"] ?? pairs[""], !lemma.isEmpty { tokens.append("lemma.usfm:" + lemma) }
        let morph = pairs["x-morph"] ?? pairs["morph"]
        return WordData(lemma: tokens.isEmpty ? nil : tokens.joined(separator: " "), morph: morph?.isEmpty == false ? morph : nil)
    }

    /// `\ref Gen 1:1|loc="GEN 1:1"\ref*` and `\jmp text|link-href="…"\jmp*`.
    private static func linkTarget(_ attributeText: String, text: String) -> String? {
        let pairs = attributes(attributeText)
        if let href = pairs["link-href"], !href.isEmpty { return href }
        let location = trimmed(pairs["loc"] ?? pairs[""] ?? text)
        return location.isEmpty ? nil : "passage:" + location
    }

    // MARK: Notes

    private func openNote(_ name: String, crossReference: Bool) {
        guard !out.inNote else { return }                // a note inside a note is its text
        noteOrdinal += 1
        noteName = name
        noteID = String(out.currentVerse ?? 0) + "." + String(noteOrdinal)
        noteIsCrossReference = crossReference
        noteDropping = false
        out.beginNote()
        expected = .noteCaller
    }

    /// A `\xt` ended: its text (or its `link-href`) is a reference the note cites.
    private func flushTarget() {
        guard let text = targetText else { return }
        targetText = nil
        // White space, line ends and the punctuation that runs between references.
        let trim: (Int) -> Bool = { c in CodePoints.isWhiteSpaceOrNewline(c) || c == 0x2E || c == 0x3B || c == 0x2C || c == 0x3A }
        var reference = CodePoints.trimmed(text, where: trim)
        if reference.isEmpty { reference = CodePoints.trimmed(Self.attributes(targetAttributes)["link-href"] ?? "", where: trim) }
        if !reference.isEmpty { out.addNoteReference(reference) }
    }

    private func closeNote() {
        guard out.inNote else { return }
        flushTarget()
        while let last = characters.last, last.inNote { closeTopCharacter() }
        if heading?.shown == false {
            out.discardNote()                            // a hidden heading's note is hidden with it
        } else {
            out.finishNote(id: noteID, kind: noteIsCrossReference ? ScriptureText.Note.Kind.crossReference : ScriptureText.Note.Kind.footnote,
                           show: noteIsCrossReference ? options.crossReferences : options.footnotes)
        }
        noteName = nil
        noteDropping = false
    }
}
