// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// What a reader gets when they copy (plan D38, D76): the words, not the machinery. The text on screen carries
// things that mean nothing on a clipboard: footnote and cross-reference letters, Strong's and morphology markers,
// and U+2060 word joiners that keep a note letter on its word. Copying from the model drops those, keeps verse
// numbers as plain numbers set apart by a space ("1 In the beginning … 2 And the earth"), and says which verses
// the text came from, so the host can add a reference line.

extension ScriptureText {

    public struct CopiedText: Equatable, Sendable {
        public var text: String
        /// The first and last verse the copied text touches, or nil for text with no verses (a dictionary entry).
        public var verses: ClosedRange<Int>?

        public init(text: String, verses: ClosedRange<Int>?) {
            self.text = text
            self.verses = verses
        }
    }

    /// The text of a UTF-16 range, as copied.
    public func copiedText(utf16Start start: Int, length: Int) -> CopiedText {
        let units = CodePoints.utf16(text)
        let lower = max(0, min(start, units.count)), upper = max(lower, min(start + length, units.count))
        guard lower < upper else { return CopiedText(text: "", verses: nil) }

        var dropped = [Bool](repeating: false, count: units.count)
        var numberStarts = Set<Int>(), numberEnds = Set<Int>()
        for span in spans {
            let end = min(span.start + span.length, units.count)
            guard span.start < end else { continue }
            switch span.attribute {
            case .footnote, .strongs, .morph:
                for i in span.start..<end { dropped[i] = true }
            case .verseNumber:
                numberStarts.insert(span.start)
                numberEnds.insert(end)
            default:
                break
            }
        }

        var out: [Int] = []
        func endsInSpace() -> Bool { out.last.map { $0 == 0x20 || $0 == 0x0A } ?? true }
        for i in lower..<upper {
            if numberEnds.contains(i), !dropped[i], units[i] != 0x20, units[i] != 0x0A, !endsInSpace() { out.append(0x20) }
            if dropped[i] || units[i] == 0x2060 { continue }
            if numberStarts.contains(i), !endsInSpace() { out.append(0x20) }
            out.append(units[i])
        }

        // One space between words, none at the ends of a line or of the text.
        let joined = CodePoints.fromUTF16(out)
        let lines = joined.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        }
        var firstLine = 0
        var lastLine = lines.count
        while firstLine < lastLine, lines[firstLine].isEmpty { firstLine += 1 }
        while lastLine > firstLine, lines[lastLine - 1].isEmpty { lastLine -= 1 }
        var cleaned = ""
        var li = firstLine
        while li < lastLine {
            if li > firstLine { cleaned += "\n" }
            cleaned += lines[li]
            li += 1
        }

        let touched = verses.filter { $0.length > 0 && $0.start < upper && $0.start + $0.length > lower }
        let range = touched.map(\.verse).min().flatMap { first in touched.map(\.endVerse).max().map { first...$0 } }
        return CopiedText(text: cleaned, verses: range)
    }

    /// One whole verse, as copied, or nil when the text has no such verse. A verse of a bridge copies the bridge; a
    /// verse in parts (14a, 14b) copies from its first part to its last.
    public func copiedText(verse: Int) -> CopiedText? {
        let parts = verses.filter { $0.contains(verse: verse) }
        guard let first = parts.first, let last = parts.last else { return nil }
        return copiedText(utf16Start: first.start, length: last.start + last.length - first.start)
    }

    /// One whole verse as the reader copies and shares it: its words, with the host's reference line above them when the host gives one.
    public func copiedText(verse: Int, referenceLine: (ClosedRange<Int>) -> String?) -> String? {
        guard let copied = copiedText(verse: verse) else { return nil }
        guard let range = copied.verses, let line = referenceLine(range), !line.isEmpty else { return copied.text }
        return line + "\n" + copied.text
    }
}
