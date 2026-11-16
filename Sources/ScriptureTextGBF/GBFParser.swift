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
        var converter = Converter()
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

    private static let paragraphMark: Character = "\u{E000}"

    /// A line indented this far is a centred title or an indented list, not a wrapped line.
    private static let centredIndent = 8

    /// Splits an entry into text and tags, and turns its line ends into paragraphs or spaces.
    private static func tokens(in gbf: String, lineBreaks: LineBreaks) -> [Token] {
        let unified = gbf.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{0}", with: "")
        // Line ends become marks first, so a blank line is found even where a tag sits between its halves.
        var marked = ""
        let lines = unified.split(separator: "\n", omittingEmptySubsequences: false)
        var blank = 0
        var previousCentred = false
        for (index, line) in lines.enumerated() {
            let isBlank = line.allSatisfy { $0 == " " || $0 == "\t" || $0 == "\u{00A0}" }
            let centred = !isBlank && line.prefix(while: { $0 == " " }).count >= Self.centredIndent
            if isBlank, index > 0 { blank += 1 }
            if index > 0, !isBlank || index == lines.count - 1 {
                // Closing a run of line ends: one blank line or more is a paragraph, none is a line end.
                let keepsLine = lineBreaks == .preserve || centred || previousCentred
                marked.append(blank > 0 ? paragraphMark : (keepsLine ? "\n" : " "))
                blank = 0
            }
            if !isBlank { marked.append(contentsOf: line); previousCentred = centred }
        }
        var result: [Token] = []
        var run = ""
        func flush() { if !run.isEmpty { result.append(.text(run)); run = "" } }
        let chars = Array(marked)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "<", let close = closingIndex(chars, from: i + 1) {
                flush()
                result.append(.tag(String(chars[(i + 1)..<close]).filter { $0 != paragraphMark && $0 != "\n" }))
                i = close + 1
                continue
            }
            if c == paragraphMark { flush(); result.append(.paragraph) }
            else if c == "\n" { flush(); result.append(.lineBreak) }
            else { run.append(c) }
            i += 1
        }
        flush()
        return result
    }

    /// The `>` that ends a tag opened just before `from`, or nil when another `<` comes first.
    private static func closingIndex(_ chars: [Character], from: Int) -> Int? {
        var j = from
        while j < chars.count {
            if chars[j] == ">" { return j }
            if chars[j] == "<" { return nil }
            j += 1
        }
        return nil
    }

    // MARK: Converter

    private struct Converter {
        enum Piece {
            case text(String)
            case markup(String)
            case word(core: String, lemmas: [String], morphs: [String])
        }

        var pieces: [Piece] = []
        /// Numbers that followed a space: they belong to the next word.
        var carryLemmas: [String] = []
        var carryMorphs: [String] = []

        mutating func markup(_ s: String) { pieces.append(.markup(s)) }

        /// Inside `<head>`: nothing shown.
        var hidden = false

        mutating func text(_ s: String) {
            guard !s.isEmpty, !hidden else { return }
            guard s.contains("#"), s.contains("|") else { plain(s); return }
            var rest = Substring(s)
            while let mark = Self.nextReferenceMark(in: rest) {
                if mark.range.lowerBound > rest.startIndex { plain(String(rest[..<mark.range.lowerBound])) }
                markup("<reference passage=\"" + Self.escaped(mark.passage) + "\">")
                pieces.append(.text(mark.display))
                markup("</reference>")
                rest = rest[mark.range.upperBound...]
            }
            if !rest.isEmpty { plain(String(rest)) }
        }

        /// `#Mt 4:12 Mr 1:14 Lu 3:19,20|`: a reference mark, its text without the `#` and `|`, and the references
        /// as one list that SWORD's key parser reads (`Mt 4:12; Mr 1:14; Lu 3:19,20`).
        static func nextReferenceMark(in s: Substring) -> (range: Range<Substring.Index>, display: String, passage: String)? {
            var search = s.startIndex
            while let hash = s[search...].firstIndex(of: "#") {
                let after = s.index(after: hash)
                guard let bar = s[after...].firstIndex(of: "|") else { return nil }
                let body = s[after..<bar]
                if body.count <= 80, body.contains(where: \.isNumber), !body.contains("#"), !body.contains("\u{E000}"),
                   !body.contains("\n") {
                    let display = body.trimmingCharacters(in: .whitespaces)
                    let passage = display.replacingOccurrences(
                        of: #"(?<=[:,\-]\d{1,3}) (?=(?:\d )?[A-Za-z]+\.? \d)"#, with: "; ", options: .regularExpression)
                    return (hash..<s.index(after: bar), display, passage)
                }
                search = after
            }
            return nil
        }

        private mutating func plain(_ s: String) {
            if !carryLemmas.isEmpty || !carryMorphs.isEmpty, let split = Self.firstWord(in: s) {
                if !split.prefix.isEmpty { pieces.append(.text(split.prefix)) }
                pieces.append(.word(core: split.core, lemmas: carryLemmas, morphs: carryMorphs))
                carryLemmas = []
                carryMorphs = []
                if !split.suffix.isEmpty { pieces.append(.text(split.suffix)) }
                return
            }
            pieces.append(.text(s))
        }

        mutating func tag(_ t: String) {
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
                else if t.hasPrefix("CA"), let code = Int(t.dropFirst(2).trimmingCharacters(in: .whitespaces)),
                        let scalar = Unicode.Scalar(code) { text(String(Character(scalar))) }
                else if t.hasPrefix("WTG") || t.hasPrefix("WTH") { number(String(t.dropFirst(3)), morph: true) }
                else if t.hasPrefix("WT") { number(String(t.dropFirst(2)), morph: true) }
                else if t.hasPrefix("WG") || t.hasPrefix("WH") { number(String(t.dropFirst(1)), morph: false) }
                else if t == "head" || t.hasPrefix("head ") { hidden = true }
                else if t == "/head" { hidden = false }
                // Everything else (layout, fonts, images, cross-reference marks): not shown.
            }
        }

        /// A Strong's number (`G976`, `H7225`, with an optional space after the letter) or a morphology code.
        private mutating func number(_ raw: String, morph: Bool) {
            var value = raw.filter { !$0.isWhitespace }
            guard !value.isEmpty else { return }
            if morph {
                value = "robinson:" + value
            } else {
                // "WG976" arrives here as "G976".
                value = "strong:" + value
            }
            // The word is the last text before any closing tags: `<FR>оставь<Fr><WG863>` numbers "оставь".
            var index = pieces.count - 1
            while index >= 0, case .markup(let m) = pieces[index], m.hasPrefix("</") { index -= 1 }
            if index >= 0 {
                if case .word(let core, var lemmas, var morphs) = pieces[index] {
                    if morph { morphs.append(value) } else { lemmas.append(value) }
                    pieces[index] = .word(core: core, lemmas: lemmas, morphs: morphs)
                    return
                }
                if case .text(let t) = pieces[index], let split = Self.lastWord(in: t) {
                    var replacement: [Piece] = []
                    if !split.prefix.isEmpty { replacement.append(.text(split.prefix)) }
                    replacement.append(.word(core: split.core, lemmas: morph ? [] : [value], morphs: morph ? [value] : []))
                    if !split.suffix.isEmpty { replacement.append(.text(split.suffix)) }
                    pieces.replaceSubrange(index...index, with: replacement)
                    return
                }
            }
            if morph { carryMorphs.append(value) } else { carryLemmas.append(value) }
        }

        func render() -> String {
            var out = ""
            for piece in pieces {
                switch piece {
                case .text(let s): out += Self.escaped(s)
                case .markup(let s): out += s
                case .word(let core, let lemmas, let morphs):
                    out += "<w"
                    if !lemmas.isEmpty { out += " lemma=\"" + Self.escaped(lemmas.joined(separator: " ")) + "\"" }
                    if !morphs.isEmpty { out += " morph=\"" + Self.escaped(morphs.joined(separator: " ")) + "\"" }
                    out += ">" + Self.escaped(core) + "</w>"
                }
            }
            return out
        }

        static func escaped(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }

        private static func isEdge(_ c: Character) -> Bool {
            c.isWhitespace || c.isPunctuation || c.isSymbol || c == "\u{E000}"
        }

        /// The word that ends `s`, when `s` ends in the word itself or its punctuation but not in a space.
        static func lastWord(in s: String) -> (prefix: String, core: String, suffix: String)? {
            let chars = Array(s)
            guard let last = chars.last, !last.isWhitespace, last != "\u{E000}" else { return nil }
            var end = chars.count
            while end > 0, isEdge(chars[end - 1]) { end -= 1 }
            guard end > 0 else { return nil }
            var start = end
            while start > 0, !chars[start - 1].isWhitespace, chars[start - 1] != "\u{E000}" { start -= 1 }
            while start < end, isEdge(chars[start]) { start += 1 }
            guard start < end else { return nil }
            return (String(chars[..<start]), String(chars[start..<end]), String(chars[end...]))
        }

        /// The first word of `s`.
        static func firstWord(in s: String) -> (prefix: String, core: String, suffix: String)? {
            let chars = Array(s)
            var start = 0
            while start < chars.count, isEdge(chars[start]) { start += 1 }
            guard start < chars.count else { return nil }
            var end = start
            while end < chars.count, !chars[end].isWhitespace, chars[end] != "\u{E000}" { end += 1 }
            var core = end
            while core > start, isEdge(chars[core - 1]) { core -= 1 }
            return (String(chars[..<start]), String(chars[start..<core]), String(chars[core...]))
        }
    }
}
