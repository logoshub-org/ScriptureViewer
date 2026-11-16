// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Finding the tap target in a text, and reading the token forms the parsers store in spans.

import Foundation

// MARK: - Finding the target in a text

extension ScriptureText {

    /// The interactive thing at a UTF-16 offset, or nil for ordinary text. Where several lie
    /// together the most specific wins: a marker (Strong's, morphology, footnote) over a link,
    /// a link over a verse number, a verse number over a word.
    public func tapTarget(atUTF16Offset offset: Int) -> TapTarget? {
        guard offset >= 0, offset < text.utf16.count else { return nil }
        let context = TapContext(offset: offset, verse: verse(at: offset), wordIndex: wordIndex(at: offset), passage: identity)

        var best: (rank: Int, span: Span)?
        for span in spans where span.start <= offset && offset < span.start + span.length {
            let rank: Int
            switch span.attribute {
            case .strongs, .morph, .footnote: rank = 4
            case .link: rank = 3
            case .verseNumber: rank = 2
            case .word: rank = 1
            default: continue
            }
            if best == nil || rank > best!.rank || (rank == best!.rank && span.length < best!.span.length) {
                best = (rank, span)
            }
        }
        guard let span = best?.span else { return nil }

        switch span.attribute {
        case .strongs(let token):
            return TapLinks.strongs(token, context)
        case .morph(let token):
            return TapLinks.morph(token, context)
        case .footnote(let id):
            return TapLinks.footnote(id, in: self, context)
        case .link(let target):
            return TapLinks.link(target, context)
        case .verseNumber(let verse):
            return TapTarget(kind: .verse, key: String(verse), context: context)
        case .word(let lemma, let morph):
            var attributes: [String: String] = [:]
            if let lemma { attributes["lemma"] = lemma }
            if let morph { attributes["morph"] = morph }
            return TapTarget(kind: .word, key: lemma ?? morph ?? "", attributes: attributes, context: context)
        default:
            return nil
        }
    }

    private func verse(at offset: Int) -> Int? {
        verses.first { $0.start <= offset && offset < $0.start + $0.length }?.verse
    }

    private func wordIndex(at offset: Int) -> Int? {
        words.first { $0.start <= offset && offset < $0.start + $0.length }?.index
    }
}

// MARK: - Reading the forms the parsers store

/// The tokens and links the parsers leave in spans, turned into targets: the markup's own tokens
/// (`strong:G3056`, `robinson:T-NSF`, a note's id), `osis:` and `passage:` scripture links, and
/// `sword://Work/Key` entry links.
enum TapLinks {

    static func strongs(_ token: String, _ context: TapContext) -> TapTarget {
        let afterwards = afterScheme(token)
        let chars = CodePoints.characters(afterwards)
        var attributes: [String: String] = [:]
        if chars.count > 1, chars[0] == "G" || chars[0] == "H", isDigit(chars[1]) {
            attributes["language"] = chars[0] == "G" ? "Greek" : "Hebrew"
        } else if let scheme = scheme(of: token) {
            attributes["scheme"] = scheme
        }
        return TapTarget(kind: .strongs, key: trimmedSpaces(afterwards), attributes: attributes, context: context)
    }

    static func morph(_ token: String, _ context: TapContext) -> TapTarget {
        var attributes: [String: String] = [:]
        if let scheme = scheme(of: token) { attributes["scheme"] = scheme }
        attributes["code"] = afterScheme(token)
        return TapTarget(kind: .morph, key: token, attributes: attributes, context: context)
    }

    static func footnote(_ id: String, in text: ScriptureText, _ context: TapContext) -> TapTarget {
        var attributes: [String: String] = [:]
        var kind = TapKind.footnote
        if let note = text.notes.first(where: { $0.id == id }) {
            if note.kind == .crossReference { kind = .crossReference }
            if !note.references.isEmpty { attributes["references"] = note.references.joined(separator: " ") }
            attributes["text"] = note.text
        }
        return TapTarget(kind: kind, key: id, attributes: attributes, context: context)
    }

    static func link(_ target: String, _ context: TapContext) -> TapTarget {
        // A scripture reference from OSIS (`osis:Work:Ref` or `osis:Ref`) or ThML (`passage:Rom 3:23`).
        if target.hasPrefix("osis:") || target.hasPrefix("passage:") {
            var reference = afterScheme(target)
            var attributes: [String: String] = [:]
            if target.hasPrefix("osis:"), let colon = colonIndex(reference) {
                let chars = CodePoints.characters(reference)
                attributes["work"] = CodePoints.string(chars: chars, 0, colon)
                reference = CodePoints.string(chars: chars, colon + 1, chars.count)
            }
            return TapTarget(kind: .scripture, key: reference, attributes: attributes, context: context)
        }
        if target.hasPrefix("sword://"), let url = URL(string: target) {
            // sword://Work/Key, both percent-encoded
            let work = url.host.map { $0.removingPercentEncoding ?? $0 } ?? ""
            let key = String(url.path.dropFirst()).removingPercentEncoding ?? String(url.path.dropFirst())
            return TapTarget(kind: .entry, key: key, attributes: ["work": work, "entry": key], context: context)
        }
        return TapTarget(kind: .link, key: target, context: context)
    }

    // MARK: Helpers

    private static func colonIndex(_ token: String) -> Int? {
        var k = 0
        for ch in token {
            if ch == ":" { return k }
            k += 1
        }
        return nil
    }

    private static func scheme(of token: String) -> String? {
        guard let i = colonIndex(token) else { return nil }
        return CodePoints.string(chars: CodePoints.characters(token), 0, i)
    }

    private static func afterScheme(_ token: String) -> String {
        guard let i = colonIndex(token) else { return token }
        let chars = CodePoints.characters(token)
        return CodePoints.string(chars: chars, i + 1, chars.count)
    }
}
