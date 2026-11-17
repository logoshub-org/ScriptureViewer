// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// GBF (General Bible Format) entries (plan D71). GBF is the CrossWire-era plain-text markup: short,
// case-paired tags with no attributes (`<FI>…<Fi>`), not XML. Fourteen of the 428 modules on
// CrossWire use it: YLT, Weymouth, Murdock, JST, RusVZh and others, and the commentaries DTN and TFG.
//
// The parser does what SWORD's own GBF filter does (`gbfosis.cpp`): it rewrites the entry as OSIS and
// hands that to `OSISParser`, so GBF gets the same words, anchors, Strong's markers, red letter, notes
// and paragraph rules as an OSIS module without a second builder.
//
//   FI…Fi  italic (SWORD: added words)    FO…Fo  Old Testament quotation, italic    FB…Fb  bold
//   FR…Fr  words of Jesus (red letter)    FU…Fu  underline, FS/FV  sup/sub, PP  poetry: text only
//   #Mt 1:1-17|  a reference mark: the text is a link (several references may share one mark)
//   <head>…</head>, <I>, <em>  stray HTML some modules carry (JST): the head is hidden, the rest is text or italic
//   CM     a paragraph      CL  a line break        CT / CG  `<` / `>`        CA123  character 123
//   TT…Tt  book title       TH…Th  psalm title      TS…Ts  a heading
//   RF…Rf  a footnote       RX…Rx, RB…Rb  cross-reference marks: text only
//   WG976  a Strong's number for the word before it (`WH` Hebrew); WT…  a morphology code
//   JR JC JL FN Fn img  layout and fonts: not shown      any other tag: not shown, text kept
//
// A Strong's number follows its word (`Родословие<WG976>`). One that follows a space belongs to the
// word after it (`, <WG 1223> волею`). Entries of hard-wrapped commentaries (DTN, TFG) end their lines
// where the printed edition did: a blank line is a paragraph and a single line end is a space, as
// `PlainTextParser` reads such text, except beside a line indented eight spaces or more (a centred title, an
// indented list of references): those keep their own line.

import Foundation
import ScriptureText
import ScriptureTextOSIS

public struct GBFParser: Sendable {

    public enum LineBreaks: Sendable, Equatable {
        /// A blank line is a paragraph; a line end inside one is a space.
        case reflow
        /// Every line end is a line break.
        case preserve
    }

    public var options: OSISParser.Options
    public var lineBreaks: LineBreaks
    public var profile: ScriptureContentProfile

    public init(options: OSISParser.Options = OSISParser.Options(), lineBreaks: LineBreaks = .reflow,
                profile: ScriptureContentProfile = .chapter) {
        self.options = options
        self.lineBreaks = lineBreaks
        self.profile = profile
    }

    /// A chapter of verse-keyed entries, as one stream. Verse 0 is the introduction. A commentary
    /// shows one verse per line.
    public func parse(_ entries: [ChapterEntries.Entry], identity: PassageIdentity? = nil) -> ScriptureText {
        var chapterOptions = options
        if profile == .commentary { chapterOptions.versePerLine = true }
        let converted = entries.map { OSISParser.VerseEntry(verse: $0.verse, osis: Self.osis(from: $0.text, lineBreaks: lineBreaks)) }
        return OSISParser(options: chapterOptions, profile: profile).parse(converted, identity: identity)
    }

    /// One entry with no verse around it.
    public func parse(_ entry: String) -> ScriptureText {
        OSISParser(options: options, profile: profile).parse(osis: Self.osis(from: entry, lineBreaks: lineBreaks))
    }

    // MARK: GBF to OSIS

    /// The entry as OSIS. Tolerant: an unknown tag is dropped, an unterminated `<` is text.
    public static func osis(from gbf: String, lineBreaks: LineBreaks = .reflow) -> String {
        let converter = Converter()
        for token in tokens(in: gbf, lineBreaks: lineBreaks) {
            switch token {
            case .text(let s): converter.text(s)
            case .paragraph: converter.markup("<milestone type=\"x-p\"/>")
            case .lineBreak: converter.markup("<lb/>")
            case .tag(let t): converter.tag(t)
            }
        }
        return converter.render()
    }

    private enum Token {
        case text(String)
        case tag(String)
        case paragraph
        case lineBreak
    }

    /// Stands for a paragraph while lines are joined (a private-use code point no module uses).
    private static let paragraphMark = 0xE000

    /// A line indented this far is a centred title or an indented list, not a wrapped line.
    private static let centredIndent = 8

    /// Splits an entry into text and tags, and turns its line ends into paragraphs or spaces. Works on code points, so it reads
    /// the same on every platform.
    private static func tokens(in gbf: String, lineBreaks: LineBreaks) -> [Token] {
        // Line ends become marks first, so a blank line is found even where a tag sits between its halves.
        let lines = CodePoints.lines(gbf)
        var marked: [Int] = []
        var blank = 0
        var previousCentred = false
        var index = 0
        while index < lines.count {
            let line = CodePoints.of(lines[index]).filter { $0 != 0 }
            let isBlank = line.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0xA0 }
            var indent = 0
            while indent < line.count && line[indent] == 0x20 { indent += 1 }
            let centred = !isBlank && indent >= Self.centredIndent
            if isBlank, index > 0 { blank += 1 }
            if index > 0, !isBlank || index == lines.count - 1 {
                // Closing a run of line ends: one blank line or more is a paragraph, none is a line end.
                let keepsLine = lineBreaks == .preserve || centred || previousCentred
                marked.append(blank > 0 ? Self.paragraphMark : (keepsLine ? 0x0A : 0x20))
                blank = 0
            }
            if !isBlank {
                marked.append(contentsOf: line)
                previousCentred = centred
            }
            index += 1
        }
        var result: [Token] = []
        var run: [Int] = []
        var i = 0
        while i < marked.count {
            let c = marked[i]
            if c == 0x3C, let close = closingIndex(marked, from: i + 1) {
                if !run.isEmpty { result.append(Token.text(CodePoints.string(run))); run = [] }
                var tag: [Int] = []
                var k = i + 1
                while k < close {
                    if marked[k] != Self.paragraphMark && marked[k] != 0x0A { tag.append(marked[k]) }
                    k += 1
                }
                result.append(Token.tag(CodePoints.string(tag)))
                i = close + 1
                continue
            }
            if c == Self.paragraphMark {
                if !run.isEmpty { result.append(Token.text(CodePoints.string(run))); run = [] }
                result.append(Token.paragraph)
            } else if c == 0x0A {
                if !run.isEmpty { result.append(Token.text(CodePoints.string(run))); run = [] }
                result.append(Token.lineBreak)
            } else {
                run.append(c)
            }
            i += 1
        }
        if !run.isEmpty { result.append(Token.text(CodePoints.string(run))) }
        return result
    }

    /// The `>` that ends a tag opened just before `from`, or nil when another `<` comes first.
    private static func closingIndex(_ codes: [Int], from: Int) -> Int? {
        var j = from
        while j < codes.count {
            if codes[j] == 0x3E { return j }
            if codes[j] == 0x3C { return nil }
            j += 1
        }
        return nil
    }

    // MARK: Converter

    /// A reference mark found in text: where it is (the `#` to just past the `|`), its text, and its references as one list.
    struct ReferenceMark: Equatable {
        var start: Int
        var end: Int
        var display: String
        var passage: String
    }

    /// A word split out of text: what comes before it, the word itself, and what follows.
    struct WordSplit: Equatable {
        var prefix: String
        var core: String
        var suffix: String
    }

    /// Builds the OSIS. A class: its pieces grow in place (see `GrowingList`).
    private final class Converter {
        enum Piece {
            case text(String)
            case markup(String)
            case word(core: String, lemmas: [String], morphs: [String])
        }

        let pieces = GrowingList<Piece>()
        /// Numbers that followed a space: they belong to the next word.
        var carryLemmas: [String] = []
        var carryMorphs: [String] = []

        func markup(_ s: String) { pieces.append(Piece.markup(s)) }

        /// Inside `<head>`: nothing shown.
        var hidden = false

        func text(_ s: String) {
            guard !s.isEmpty, !hidden else { return }
            guard s.contains("#"), s.contains("|") else { plain(s); return }
            let codes = CodePoints.of(s)
            var rest = 0
            while let mark = GBFParser.nextReferenceMark(in: codes, from: rest) {
                if mark.start > rest { plain(CodePoints.string(codes, rest, mark.start)) }
                markup("<reference passage=\"" + Self.escaped(mark.passage) + "\">")
                pieces.append(Piece.text(mark.display))
                markup("</reference>")
                rest = mark.end
            }
            if rest < codes.count { plain(CodePoints.string(codes, rest, codes.count)) }
        }

        private func plain(_ s: String) {
            if !carryLemmas.isEmpty || !carryMorphs.isEmpty, let split = GBFParser.firstWord(in: s) {
                if !split.prefix.isEmpty { pieces.append(Piece.text(split.prefix)) }
                pieces.append(Piece.word(core: split.core, lemmas: carryLemmas, morphs: carryMorphs))
                carryLemmas = []
                carryMorphs = []
                if !split.suffix.isEmpty { pieces.append(Piece.text(split.suffix)) }
                return
            }
            pieces.append(Piece.text(s))
        }

        func tag(_ t: String) {
            switch t {
            case "FI", "Fi": markup(t == "FI" ? "<transChange type=\"added\">" : "</transChange>")
            case "FO": markup("<hi type=\"italic\">")
            case "FB": markup("<hi type=\"bold\">")
            case "Fo", "Fb": markup("</hi>")
            case "FR": markup("<q who=\"Jesus\" marker=\"\">")
            case "Fr": markup("</q>")
            case "TT": markup("<title type=\"main\">")
            case "Tt": markup("</title>")
            case "TH": markup("<title type=\"psalm\" canonical=\"true\">")
            case "Th": markup("</title>")
            case "Ts": markup("</title>")
            case "Rf": markup("</note>")
            case "CM": markup("<milestone type=\"x-p\"/>")
            case "CL": markup("<lb/>")
            case "I", "i", "em": markup("<hi type=\"italic\">")
            case "/I", "/i", "/em": markup("</hi>")
            case "B", "b": markup("<hi type=\"bold\">")
            case "/B", "/b": markup("</hi>")
            case "CT": text("<")
            case "CG": text(">")
            default:
                if t.hasPrefix("TS") { markup("<title>") }
                else if t == "RF" || t.hasPrefix("RF ") { markup("<note type=\"x-StudyNote\">") }
                else if t.hasPrefix("CA"), let character = Self.character(code: String(t.dropFirst(2))) { text(character) }
                else if t.hasPrefix("WTG") || t.hasPrefix("WTH") { number(String(t.dropFirst(3)), morph: true) }
                else if t.hasPrefix("WT") { number(String(t.dropFirst(2)), morph: true) }
                else if t.hasPrefix("WG") || t.hasPrefix("WH") { number(String(t.dropFirst(1)), morph: false) }
                else if t == "head" || t.hasPrefix("head ") { hidden = true }
                else if t == "/head" { hidden = false }
                // Everything else (layout, fonts, images, cross-reference marks): not shown.
            }
        }

        /// `CA123`: the character with that code, or nil when it is not a number or not a character.
        private static func character(code raw: String) -> String? {
            guard let code = Int(CodePoints.trimmed(raw, where: { CodePoints.isHorizontalWhiteSpace($0) })), code >= 0 else { return nil }
            let character = CodePoints.string(scalar: code)
            return character.isEmpty ? nil : character
        }

        /// A Strong's number (`G976`, `H7225`, with an optional space after the letter) or a morphology code.
        private func number(_ raw: String, morph: Bool) {
            var value = CodePoints.string(CodePoints.of(raw).filter { !CodePoints.isWhiteSpace($0) })
            guard !value.isEmpty else { return }
            if morph {
                value = "robinson:" + value
            } else {
                // "WG976" arrives here as "G976".
                value = "strong:" + value
            }
            // The word is the last text before any closing tags: `<FR>оставь<Fr><WG863>` numbers "оставь".
            var index = pieces.count - 1
            while index >= 0 && Self.isClosingMarkup(pieces[index]) { index -= 1 }
            if index >= 0 {
                switch pieces[index] {
                case .word(let core, let lemmas, let morphs):
                    var newLemmas = lemmas
                    var newMorphs = morphs
                    if morph { newMorphs.append(value) } else { newLemmas.append(value) }
                    pieces[index] = Piece.word(core: core, lemmas: newLemmas, morphs: newMorphs)
                    return
                case .text(let t):
                    if let split = GBFParser.lastWord(in: t) {
                        pieces.remove(at: index)
                        var at = index
                        if !split.prefix.isEmpty { pieces.insert(Piece.text(split.prefix), at: at); at += 1 }
                        let lemmas: [String] = morph ? [] : [value]
                        let morphs: [String] = morph ? [value] : []
                        pieces.insert(Piece.word(core: split.core, lemmas: lemmas, morphs: morphs), at: at)
                        at += 1
                        if !split.suffix.isEmpty { pieces.insert(Piece.text(split.suffix), at: at) }
                        return
                    }
                case .markup:
                    break
                }
            }
            if morph { carryMorphs.append(value) } else { carryLemmas.append(value) }
        }

        private static func isClosingMarkup(_ piece: Piece) -> Bool {
            switch piece {
            case .markup(let m): return m.hasPrefix("</")
            default: return false
            }
        }

        func render() -> String {
            let out = TextBuffer()
            for piece in pieces.elements() {
                switch piece {
                case .text(let s): out.append(Self.escaped(s))
                case .markup(let s): out.append(s)
                case .word(let core, let lemmas, let morphs):
                    out.append("<w")
                    if !lemmas.isEmpty { out.append(" lemma=\"" + Self.escaped(lemmas.joined(separator: " ")) + "\"") }
                    if !morphs.isEmpty { out.append(" morph=\"" + Self.escaped(morphs.joined(separator: " ")) + "\"") }
                    out.append(">" + Self.escaped(core) + "</w>")
                }
            }
            return out.text
        }

        static func escaped(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
    }

    // MARK: Reference marks

    /// `#Mt 4:12 Mr 1:14 Lu 3:19,20|`: the next reference mark at or after `from`, its text without the `#` and `|`, and the
    /// references as one list that SWORD's key parser reads (`Mt 4:12; Mr 1:14; Lu 3:19,20`). Nil when there is none.
    static func nextReferenceMark(in codes: [Int], from: Int) -> ReferenceMark? {
        var search = from
        while true {
            guard let hash = index(of: 0x23, in: codes, from: search) else { return nil }
            let after = hash + 1
            guard let bar = index(of: 0x7C, in: codes, from: after) else { return nil }
            var hasNumber = false
            var clean = true
            var k = after
            while k < bar {
                let c = codes[k]
                if CodePoints.isNumber(c) { hasNumber = true }
                if c == 0x23 || c == paragraphMark || c == 0x0A { clean = false }
                k += 1
            }
            if bar - after <= 80, hasNumber, clean {
                let display = CodePoints.trimmed(CodePoints.string(codes, after, bar), where: { CodePoints.isHorizontalWhiteSpace($0) })
                return ReferenceMark(start: hash, end: bar + 1, display: display, passage: separatedReferences(display))
            }
            search = after
        }
    }

    private static func index(of code: Int, in codes: [Int], from: Int) -> Int? {
        var k = from
        while k < codes.count {
            if codes[k] == code { return k }
            k += 1
        }
        return nil
    }

    /// The references of a mark, apart by "; " where the mark runs them together with a space: a space after a verse number
    /// (one to three digits after `:`, `,` or `-`) and before the next book's name ("Mr 1:14", "1 Co 3:4") becomes "; ". This is
    /// the regular expression `(?<=[:,\-]\d{1,3}) (?=(?:\d )?[A-Za-z]+\.? \d)` written out, since the transpiler takes none.
    static func separatedReferences(_ display: String) -> String {
        let c = CodePoints.of(display)
        var out: [Int] = []
        var i = 0
        while i < c.count {
            if c[i] == 0x20 && endsVerseNumber(c, before: i) && startsBookReference(c, at: i + 1) {
                out.append(0x3B)
                out.append(0x20)
            } else {
                out.append(c[i])
            }
            i += 1
        }
        return CodePoints.string(out)
    }

    /// One to three digits end just before `index`, and `:`, `,` or `-` comes just before them.
    private static func endsVerseNumber(_ c: [Int], before index: Int) -> Bool {
        var digits = 0
        var k = index - 1
        while k >= 0 && digits < 4 && CodePoints.isDecimalDigit(c[k]) { digits += 1; k -= 1 }
        guard digits >= 1 && digits <= 3 && k >= 0 else { return false }
        return c[k] == 0x3A || c[k] == 0x2C || c[k] == 0x2D
    }

    /// A book's name starts at `index` (optionally after a digit and a space: "1 Co"), then perhaps a dot, a space and a digit.
    private static func startsBookReference(_ c: [Int], at index: Int) -> Bool {
        if index + 1 < c.count && CodePoints.isDecimalDigit(c[index]) && c[index + 1] == 0x20 {
            return bookThenNumber(c, at: index + 2)
        }
        return bookThenNumber(c, at: index)
    }

    private static func bookThenNumber(_ c: [Int], at index: Int) -> Bool {
        var k = index
        while k < c.count && ((c[k] >= 0x41 && c[k] <= 0x5A) || (c[k] >= 0x61 && c[k] <= 0x7A)) { k += 1 }
        guard k > index else { return false }
        if k < c.count && c[k] == 0x2E { k += 1 }
        return k + 1 < c.count && c[k] == 0x20 && CodePoints.isDecimalDigit(c[k + 1])
    }

    // MARK: Words

    private static func isEdge(_ c: Int) -> Bool {
        CodePoints.isWhiteSpace(c) || CodePoints.isPunctuation(c) || CodePoints.isSymbol(c) || c == paragraphMark
    }

    private static func isBreak(_ c: Int) -> Bool { CodePoints.isWhiteSpace(c) || c == paragraphMark }

    /// The word that ends `s`, when `s` ends in the word itself or its punctuation but not in a space.
    static func lastWord(in s: String) -> WordSplit? {
        let c = CodePoints.of(s)
        guard let last = c.last, !isBreak(last) else { return nil }
        var end = c.count
        while end > 0 && isEdge(c[end - 1]) { end -= 1 }
        guard end > 0 else { return nil }
        var start = end
        while start > 0 && !isBreak(c[start - 1]) { start -= 1 }
        while start < end && isEdge(c[start]) { start += 1 }
        guard start < end else { return nil }
        return WordSplit(prefix: CodePoints.string(c, 0, start), core: CodePoints.string(c, start, end),
                         suffix: CodePoints.string(c, end, c.count))
    }

    /// The first word of `s`.
    static func firstWord(in s: String) -> WordSplit? {
        let c = CodePoints.of(s)
        var start = 0
        while start < c.count && isEdge(c[start]) { start += 1 }
        guard start < c.count else { return nil }
        var end = start
        while end < c.count && !isBreak(c[end]) { end += 1 }
        var core = end
        while core > start && isEdge(c[core - 1]) { core -= 1 }
        return WordSplit(prefix: CodePoints.string(c, 0, start), core: CodePoints.string(c, start, core),
                         suffix: CodePoints.string(c, core, c.count))
    }
}
