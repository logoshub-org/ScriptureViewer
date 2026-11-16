// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Highlights as data (plan D38): the host says *what* is marked and *how it is named*; the
// platform view decides how a style looks. A highlight never changes the text or its offsets, so
// it can be added and removed without rebuilding the attributed string. Two things are marked
// today: a bookmarked verse (in the colour of the bookmark's folder, which is the user's data, not
// the theme's) and the words of a search.

import Foundation

/// How a highlight is named. `name` is semantic ("search", "bookmark"); `colour` is set only
/// where the user chose one (a bookmark folder's `#RRGGBB`).
public struct HighlightStyle: Hashable, Sendable, Codable {
    public var name: String
    public var colour: String?

    public init(name: String, colour: String? = nil) {
        self.name = name
        self.colour = colour
    }

    public static let search = HighlightStyle(name: "search")
    public static func bookmark(colour: String?) -> HighlightStyle { HighlightStyle(name: "bookmark", colour: colour) }
}

public struct Highlight: Equatable, Sendable {

    public enum Target: Equatable, Sendable {
        /// The text of a verse, after its number.
        case verse(Int)
        /// A range of UTF-16 offsets in the text on show (search hits, which are not saved).
        case range(start: Int, length: Int)
    }

    public var target: Target
    public var style: HighlightStyle

    public init(_ target: Target, style: HighlightStyle) {
        self.target = target
        self.style = style
    }
}

/// A highlight resolved against one text: where to paint, in UTF-16 offsets.
public struct ResolvedHighlight: Equatable, Sendable {
    public var start: Int
    public var length: Int
    public var style: HighlightStyle

    public init(start: Int, length: Int, style: HighlightStyle) {
        self.start = start
        self.length = length
        self.style = style
    }
}

extension ScriptureText {

    /// The ranges to paint for `highlights`. A verse highlight covers the verse's text without
    /// its number (the number is a superscript the highlight would have to be drawn behind);
    /// a verse the text does not hold, and a range outside the text, are ignored.
    public func resolve(_ highlights: [Highlight]) -> [ResolvedHighlight] {
        let count = text.utf16.count
        var result: [ResolvedHighlight] = []
        for highlight in highlights {
            switch highlight.target {
            case .verse(let number):
                // A verse of a bridge highlights the whole bridge, whose marker carries its first verse; a verse in
                // parts (14a, 14b) highlights every part.
                for verse in verses where verse.contains(verse: number) {
                    var start = verse.start
                    let end = verse.start + verse.length
                    // Past the verse number marker, and the space after it.
                    if let marker = spans.first(where: { span in
                        if case .verseNumber(let n) = span.attribute { return n == verse.verse && span.start == verse.start }
                        return false
                    }) {
                        start = marker.start + marker.length
                    }
                    while start < end, isBreakOrSpace(atUTF16Offset: start) { start += 1 }
                    if end > start { result.append(.init(start: start, length: end - start, style: highlight.style)) }
                }
            case .range(let start, let length):
                guard start >= 0, length > 0, start + length <= count else { continue }
                result.append(.init(start: start, length: length, style: highlight.style))
            }
        }
        return result
    }

    /// Every place any of `terms` occurs in the text, ignoring case, as search highlights. Markers
    /// (verse numbers, Strong's numbers, morphology, footnote letters) are not searched, so
    /// looking for "love" does not light up half of `<03068>`.
    public func searchHits(for terms: [String]) -> [Highlight] {
        let units = CodePoints.utf16(text)
        guard !units.isEmpty else { return [] }
        let markers = spans.filter {
            switch $0.attribute {
            case .strongs, .morph, .footnote, .verseNumber: return true
            default: return false
            }
        }
        var ranges: [HitRange] = []
        let lowered = text.lowercased()
        // Lowercasing can change the length (a few letters expand), so only a text whose
        // lowercase form has the same length is searched by offset; any other is searched as is.
        let loweredUnits = CodePoints.utf16(lowered)
        let haystack = loweredUnits.count == units.count ? loweredUnits : units
        for raw in terms {
            let term = CodePoints.utf16(trimmedWhitespace(raw).lowercased())
            guard !term.isEmpty else { continue }
            var start = 0
            while start + term.count <= haystack.count {
                var m = 0
                while m < term.count && haystack[start + m] == term[m] { m += 1 }
                if m < term.count { start += 1; continue }
                let length = term.count
                let hitStart = start
                start += length
                if markers.contains(where: { hitStart < $0.start + $0.length && $0.start < hitStart + length }) { continue }
                ranges.append(HitRange(start: hitStart, length: length))
            }
        }
        // Overlapping hits (two terms that share letters) become one.
        ranges.sort { $0.start < $1.start }
        var merged: [HitRange] = []
        for r in ranges {
            if let last = merged.last, r.start <= last.start + last.length {
                merged[merged.count - 1] = HitRange(start: last.start, length: max(last.length, r.start + r.length - last.start))
            } else {
                merged.append(r)
            }
        }
        return merged.map { Highlight(.range(start: $0.start, length: $0.length), style: .search) }
    }

    /// Every word that carries Strong's number `number` (`G3056`, `H07225`, `H7225`, or bare digits for either
    /// language), as search highlights: what a Strong's search found, marked in the chapter (plan D76). Leading
    /// zeros do not matter, so `H07225` and `H7225` are the same number.
    public func strongsHits(for number: String) -> [Highlight] {
        guard let wanted = Self.strongsKey(number) else { return [] }
        var hits: [Highlight] = []
        for span in spans {
            guard case .word(let lemmaOpt, _) = span.attribute, let lemma = lemmaOpt else { continue }
            var matched = false
            for token in CodePoints.split(lemma, separator: " ") {
                guard let key = Self.strongsKey(token) else { continue }
                if key.digits == wanted.digits && (wanted.language == nil || key.language == nil || key.language == wanted.language) {
                    matched = true
                    break
                }
            }
            if matched { hits.append(Highlight(.range(start: span.start, length: span.length), style: .search)) }
        }
        return hits
    }

    /// A Strong's token reduced to its language letter (if any) and its number without leading zeros.
    /// Accepts `strong:G3056`, `G3056`, `H07225`, `3056`; anything else (a `lemma.TR:` token, a word) is nil.
    private static func strongsKey(_ raw: String) -> StrongsKey? {
        let chars = CodePoints.characters(trimmedSpaces(raw))
        var start = 0
        var colon = -1
        var k = 0
        while k < chars.count {
            if chars[k] == ":" { colon = k; break }
            k += 1
        }
        if colon >= 0 {
            guard CodePoints.string(chars: chars, 0, colon) == "strong" else { return nil }
            start = colon + 1
        }
        var language: String? = nil
        if start < chars.count, chars[start] == "G" || chars[start] == "H" {
            language = String(chars[start])
            start += 1
        }
        var end = start
        while end < chars.count, isDigit(chars[end]) { end += 1 }
        guard end > start else { return nil }
        var z = start
        while z < end, chars[z] == "0" { z += 1 }
        return StrongsKey(language: language, digits: z == end ? "0" : CodePoints.string(chars: chars, z, end))
    }

    private func isBreakOrSpace(atUTF16Offset offset: Int) -> Bool {
        #if SKIP
        // SKIP INSERT: return offset >= 0 && offset < text.length && (text[offset] == ' ' || text[offset] == '\n')
        return false
        #else
        let u = text.utf16
        guard let index = u.index(u.startIndex, offsetBy: offset, limitedBy: u.endIndex), index < u.endIndex else { return false }
        let unit = u[index]
        return unit == 0x20 || unit == 0x0A
        #endif
    }
}

struct HitRange {
    var start: Int
    var length: Int
}

struct StrongsKey {
    var language: String?
    var digits: String
}
