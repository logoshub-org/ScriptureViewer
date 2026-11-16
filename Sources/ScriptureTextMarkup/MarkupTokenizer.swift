// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import ScriptureText

// A small hand-written tokenizer for the XML-shaped markup SWORD modules store: OSIS
// (plan D32), and the TEI and ThML of dictionaries, devotionals and books (D46): tags, quoted attributes, self-closing tags, text, and the
// predefined entities. Pure Swift over bytes — no Foundation XML, no libxml2,
// nothing platform-specific — so it runs unchanged on iOS, Android and Linux.
//
// It is *tolerant by design*: it never fails, never crashes and never loops.
// A `<` that does not start markup (`1 < 2`) stays text. A tag that is **cut
// off by the end of the input** is dropped, never shown: real modules contain
// entries truncated mid-tag (the LXX has a verse whose real length, 83,396
// bytes, wrapped the format's 16-bit size field; the Azeri module's last two
// entries end in `<div eID="`), and libsword reads them cut off too.
// Structure is not checked here; OSIS containers legitimately span verse
// entries (plan D34), so balance is the builder's concern.

/// Receives the events the tokenizer produces.
public protocol MarkupEventSink {
    /// An opening tag. For a self-closing tag (`<l sID="x"/>`) `selfClosing`
    /// is true and **no** matching `endElement` follows — OSIS uses these as
    /// milestones, and the builder treats them differently from containers.
    mutating func startElement(_ name: String, attributes: [String: String], selfClosing: Bool)
    mutating func characters(_ text: String)
    mutating func endElement(_ name: String)
}

public enum MarkupTokenizer {

    public static func tokenize<S: MarkupEventSink>(_ input: String, into sink: inout S) {
        var scanner = Scanner(codes: CodePoints.of(input))
        scanner.run(&sink)
    }
}

// MARK: - Code points
//
// The scanner works on an array of Unicode code points held as `Int`, not on UTF-8 bytes:
// every character the markup syntax uses is ASCII, `Int` is the one integer type that
// transpiles cleanly to Kotlin, and it needs no UInt8 / String(decoding:) idioms.

// MARK: - Scanner

private enum Markup {
    case start(name: String, attributes: [String: String], selfClosing: Bool, next: Int)
    case end(name: String, next: Int)
    case cdata(text: String, next: Int)
    case skipped(next: Int)      // comment, processing instruction, doctype
    case notMarkup               // a '<' that is just text
    case truncated               // markup cut off by the end of the input
}

private struct Entity {
    let scalar: Int
    let next: Int
}

private struct Scanner {
    let b: [Int]
    var i = 0

    init(codes: [Int]) { b = codes }

    private static let lt = 60, gt = 62, slash = 47, eq = 61
    private static let dq = 34, sq = 39, amp = 38, semi = 59
    private static let bang = 33, question = 63, dash = 45, dot = 46
    private static let hash = 35, lowerX = 120, upperX = 88, underscore = 95, colon = 58

    mutating func run<S: MarkupEventSink>(_ sink: inout S) {
        var textStart = 0
        let n = b.count
        while i < n {
            guard b[i] == Self.lt else { i += 1; continue }
            let markupAt = i
            let parsed = parseMarkup(at: markupAt)
            if case .notMarkup = parsed { i += 1; continue }   // a stray '<' stays text
            if case .truncated = parsed {
                // The input ended inside a tag: keep the text before it, drop the cut-off tail.
                flushText(from: textStart, to: markupAt, into: &sink)
                return
            }

            flushText(from: textStart, to: markupAt, into: &sink)
            switch parsed {
            case .start(let name, let attributes, let selfClosing, let next):
                sink.startElement(name, attributes: attributes, selfClosing: selfClosing)
                i = next
            case .end(let name, let next):
                sink.endElement(name)
                i = next
            case .cdata(let text, let next):
                if !text.isEmpty { sink.characters(text) }
                i = next
            case .skipped(let next):
                i = next
            case .notMarkup, .truncated:
                break
            }
            textStart = i
        }
        flushText(from: textStart, to: n, into: &sink)
    }

    private func flushText<S: MarkupEventSink>(from: Int, to: Int, into sink: inout S) {
        guard to > from else { return }
        sink.characters(decodeEntities(from, to))
    }

    private func indexOf(_ code: Int, from: Int) -> Int? {
        var k = from
        while k < b.count {
            if b[k] == code { return k }
            k += 1
        }
        return nil
    }

    private func matches(_ pattern: [Int], at k: Int) -> Bool {
        if k + pattern.count > b.count { return false }
        var m = 0
        while m < pattern.count {
            if b[k + m] != pattern[m] { return false }
            m += 1
        }
        return true
    }

    // MARK: Markup

    private func parseMarkup(at start: Int) -> Markup {
        let n = b.count
        guard start + 1 < n else { return .notMarkup }
        let c = b[start + 1]

        if c == Self.slash { return parseEndTag(at: start) }
        if c == Self.bang || c == Self.question { return parseDeclaration(at: start) }
        if Self.isNameStart(c) { return parseStartTag(at: start) }
        return .notMarkup
    }

    private func parseEndTag(at start: Int) -> Markup {
        let n = b.count
        var j = start + 2
        guard j < n, Self.isNameStart(b[j]) else { return .notMarkup }
        let nameStart = j
        while j < n, Self.isNameChar(b[j]) { j += 1 }
        let name = CodePoints.string(b, nameStart, j)
        while j < n, Self.isSpace(b[j]) { j += 1 }
        guard j < n else { return .truncated }                 // "</w" cut off by the end
        guard b[j] == Self.gt else { return .notMarkup }
        return .end(name: name, next: j + 1)
    }

    private func parseStartTag(at start: Int) -> Markup {
        let n = b.count
        var j = start + 1
        let nameStart = j
        while j < n, Self.isNameChar(b[j]) { j += 1 }
        let name = CodePoints.string(b, nameStart, j)
        var attributes: [String: String] = [:]

        while true {
            while j < n, Self.isSpace(b[j]) { j += 1 }
            guard j < n else { return .truncated }                 // tag cut off by the end
            if b[j] == Self.gt {
                return .start(name: name, attributes: attributes, selfClosing: false, next: j + 1)
            }
            if b[j] == Self.slash {
                if j + 1 < n, b[j + 1] == Self.gt {
                    return .start(name: name, attributes: attributes, selfClosing: true, next: j + 2)
                }
                j += 1                                              // stray '/', ignore it
                continue
            }
            // attribute name
            let attrStart = j
            while j < n, !Self.isSpace(b[j]), b[j] != Self.eq, b[j] != Self.gt, b[j] != Self.slash { j += 1 }
            guard j > attrStart else { j += 1; continue }
            let attrName = CodePoints.string(b, attrStart, j)
            while j < n, Self.isSpace(b[j]) { j += 1 }

            var value = ""
            if j < n, b[j] == Self.eq {
                j += 1
                while j < n, Self.isSpace(b[j]) { j += 1 }
                guard j < n else { return .truncated }
                if b[j] == Self.dq || b[j] == Self.sq {
                    let quote = b[j]
                    guard let close = indexOf(quote, from: j + 1) else { return .truncated }
                    value = decodeEntities(j + 1, close)  // a '>' inside quotes is fine
                    j = close + 1
                } else {
                    let valueStart = j
                    while j < n, !Self.isSpace(b[j]), b[j] != Self.gt { j += 1 }
                    value = decodeEntities(valueStart, j)
                }
            }
            attributes[attrName] = value
        }
    }

    /// `<!-- -->`, `<?...?>`, `<!DOCTYPE ...>` are skipped; `<![CDATA[...]]>`
    /// becomes literal text. OSIS modules use none of these; tolerance only.
    private func parseDeclaration(at start: Int) -> Markup {
        let n = b.count
        func find(_ pattern: [Int], from: Int) -> Int? {
            var k = from
            while k + pattern.count <= n {
                if matches(pattern, at: k) { return k }
                k += 1
            }
            return nil
        }
        if b[start + 1] == Self.question {
            guard let end = find([Self.question, Self.gt], from: start + 2) else { return .truncated }
            return .skipped(next: end + 2)
        }
        if start + 3 < n, b[start + 2] == Self.dash, b[start + 3] == Self.dash {
            guard let end = find([Self.dash, Self.dash, Self.gt], from: start + 4) else { return .truncated }
            return .skipped(next: end + 3)
        }
        let cdata = CodePoints.of("<![CDATA[")
        if matches(cdata, at: start) {
            guard let end = find(CodePoints.of("]]>"), from: start + cdata.count) else { return .truncated }
            let text = CodePoints.string(b, start + cdata.count, end)
            return .cdata(text: text, next: end + 3)
        }
        guard let end = indexOf(Self.gt, from: start + 2) else { return .truncated }
        return .skipped(next: end + 1)
    }

    // MARK: Entities

    /// Decodes `&amp; &lt; &gt; &quot; &apos;` and numeric references in `b[from..<to]`.
    /// Anything unrecognised passes through literally, `&` included.
    private func decodeEntities(_ from: Int, _ to: Int) -> String {
        var hasAmp = false
        var k = from
        while k < to {
            if b[k] == Self.amp { hasAmp = true; break }
            k += 1
        }
        guard hasAmp else { return CodePoints.string(b, from, to) }
        var out = ""
        var runStart = from
        k = from
        while k < to {
            if b[k] == Self.amp, let e = entity(at: k, end: to) {
                out += CodePoints.string(b, runStart, k)
                out += CodePoints.string(scalar: e.scalar)
                k = e.next
                runStart = k
            } else {
                k += 1
            }
        }
        out += CodePoints.string(b, runStart, to)
        return out
    }

    private func entity(at amp: Int, end: Int) -> Entity? {
        let limit = min(end, amp + 12)          // entities are short; don't scan far
        var semi = amp + 1
        while semi < limit, b[semi] != Self.semi { semi += 1 }
        guard semi < limit, b[semi] == Self.semi, semi > amp + 1 else { return nil }
        let bodyStart = amp + 1

        if b[bodyStart] == Self.hash {
            var digitsStart = bodyStart + 1
            var radix = 10
            if digitsStart < semi, b[digitsStart] == Self.lowerX || b[digitsStart] == Self.upperX {
                radix = 16
                digitsStart += 1
            }
            guard digitsStart < semi else { return nil }
            var value = 0
            var k = digitsStart
            while k < semi {
                let d = Self.digitValue(b[k])
                guard d >= 0, d < radix else { return nil }
                value = value * radix + d
                if value > 0x10FFFF { return nil }
                k += 1
            }
            guard !(value >= 0xD800 && value <= 0xDFFF) else { return nil }
            return Entity(scalar: value, next: semi + 1)
        }
        switch CodePoints.string(b, bodyStart, semi) {
        case "amp": return Entity(scalar: 38, next: semi + 1)
        case "lt": return Entity(scalar: 60, next: semi + 1)
        case "gt": return Entity(scalar: 62, next: semi + 1)
        case "quot": return Entity(scalar: 34, next: semi + 1)
        case "apos": return Entity(scalar: 39, next: semi + 1)
        default: return nil
        }
    }

    private static func digitValue(_ c: Int) -> Int {
        if c >= 0x30 && c <= 0x39 { return c - 0x30 }
        if c >= 0x41 && c <= 0x46 { return c - 0x41 + 10 }
        if c >= 0x61 && c <= 0x66 { return c - 0x61 + 10 }
        return -1
    }

    // MARK: Character classes

    private static func isSpace(_ c: Int) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D }

    private static func isNameStart(_ c: Int) -> Bool {
        (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == underscore || c == colon
    }

    private static func isNameChar(_ c: Int) -> Bool {
        isNameStart(c) || (c >= 0x30 && c <= 0x39) || c == dash || c == dot
    }
}
