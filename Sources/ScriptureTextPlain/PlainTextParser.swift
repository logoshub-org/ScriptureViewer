// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Modules with no `SourceType` hold plain text: the bundled MHCC commentary,
// the Strong's Hebrew dictionary, and any other markup-free commentary,
// dictionary or devotional (plan D46, step 6). There is nothing to parse; the
// work is deciding where the paragraphs are.
//
// Such text is hard-wrapped (the Strong's entries break every ~60 columns, with
// CRLF line ends and a leading space), so a line end is not a paragraph end. The
// web view shows the raw text through HTML, which collapses every line end and
// blank line into one space, so entries run together. This parser reflows
// instead: a blank line ends a paragraph and a single line end is a space, which
// reads the way the author set it. `Options.lineBreaks = .preserve` keeps every
// line as its own paragraph, for text where line ends are meaningful.
//
// Nothing in the text is interpreted: MHCC's `#Ex 7:20|` reference marks, for
// example, stay as written, as they do in the web view.

import Foundation
import ScriptureText

public struct PlainTextParser: Sendable {

    public struct Options: Sendable, Equatable {
        public enum LineBreaks: Sendable, Equatable {
            /// A blank line separates paragraphs; a line end inside one is a space.
            case reflow
            /// Every line is its own paragraph.
            case preserve
        }

        public var lineBreaks = LineBreaks.reflow

        public init() {}
    }

    public var options: Options
    public var profile: ScriptureContentProfile

    public init(options: Options = Options(), profile: ScriptureContentProfile = .dictionary) {
        self.options = options
        self.profile = profile
    }

    /// One entry: a dictionary article, a devotional, an "about" text.
    public func parse(_ text: String) -> ScriptureText {
        let builder = Builder()
        builder.appendParagraphs(paragraphs(in: text))
        return builder.finish()
    }

    /// A chapter of verse-keyed entries (a plain-text commentary or Bible). Verse 0
    /// is the introduction. With the commentary profile each verse starts with its
    /// number on a line of its own, as the web view shows it; with the chapter
    /// profile the number runs into the text.
    public func parse(_ entries: [ChapterEntries.Entry], identity: PassageIdentity? = nil) -> ScriptureText {
        let builder = Builder()
        for entry in entries {
            let body = paragraphs(in: entry.text)
            if entry.verse > 0, profile.buildsVerseRanges {
                builder.appendVerse(entry.verse, paragraphs: body, numberOnOwnLine: profile == .commentary)
            } else {
                builder.appendParagraphs(body)
            }
        }
        var result = builder.finish()
        result.identity = identity
        return result
    }

    // MARK: Paragraphs

    func paragraphs(in raw: String) -> [String] {
        // CRLF and CR line ends are one line end each.
        let lines = CodePoints.lines(raw).map { Self.collapsed($0) }
        switch options.lineBreaks {
        case .preserve:
            return lines.filter { !$0.isEmpty }
        case .reflow:
            var result: [String] = []
            var current: [String] = []
            for line in lines {
                if line.isEmpty {
                    if !current.isEmpty { result.append(current.joined(separator: " ")); current = [] }
                } else {
                    current.append(line)
                }
            }
            if !current.isEmpty { result.append(current.joined(separator: " ")) }
            return result
        }
    }

    /// Runs of spaces and tabs become one space, and the ends are trimmed.
    private static func collapsed(_ line: String) -> String {
        var result: [Int] = []
        var pendingSpace = false
        for c in CodePoints.of(line) {
            if c == 0x20 || c == 0x09 || c == 0xA0 || c == 0x0C {
                pendingSpace = true
            } else {
                if pendingSpace, !result.isEmpty { result.append(0x20) }
                pendingSpace = false
                result.append(c)
            }
        }
        return CodePoints.string(result)
    }

    // MARK: Building

    /// A class: it grows in place (see `TextBuffer`).
    private final class Builder {
        let text = TextBuffer()
        let spans = GrowingList<ScriptureText.Span>()
        let verses = GrowingList<ScriptureText.VerseRange>()

        var length: Int { text.length }

        private func append(_ s: String) {
            text.append(s)
        }

        private func startParagraph() {
            if length > 0 { append("\n") }
        }

        func appendParagraphs(_ paragraphs: [String]) {
            for p in paragraphs {
                startParagraph()
                append(p)
            }
        }

        func appendVerse(_ verse: Int, paragraphs: [String], numberOnOwnLine: Bool) {
            startParagraph()
            let start = length
            let marker = String(verse)
            append(marker)
            spans.append(ScriptureText.Span(start: start, length: CodePoints.utf16Length(marker),
                                            attribute: ScriptureText.Attribute.verseNumber(verse)))
            for (index, p) in paragraphs.enumerated() {
                if index == 0, !numberOnOwnLine { append(p) } else { append("\n"); append(p) }
            }
            verses.append(ScriptureText.VerseRange(verse: verse, start: start, length: length - start))
        }

        func finish() -> ScriptureText {
            ScriptureText(text: text.text, spans: spans.elements(), verses: verses.elements())
        }
    }
}
