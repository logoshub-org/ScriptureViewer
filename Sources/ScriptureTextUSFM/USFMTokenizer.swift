// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// USFM's backslash markup as tokens (plan D88, Track V4): plain Swift over the text, no library.
//
//   \p  \q2  \v  \+w      a marker; one space or line end after it is part of the marker, not text
//   \w*  \+nd*            an end marker
//   \*                    the end of a milestone (`\qt-s |who="Jesus"\*`)
//   anything else         text, up to the next backslash
//
// A backslash not followed by a marker name is text. The tokenizer never fails: what it cannot read is text.

enum USFMToken: Equatable {
    /// `\name`, or `\+name` (`nested`) inside another character style.
    case marker(String, nested: Bool)
    /// `\name*`; `\*` has the empty name.
    case end(String, nested: Bool)
    case text(String)
}

enum USFMTokenizer {

    static func tokens(_ source: Substring) -> [USFMToken] {
        var result: [USFMToken] = []
        let scalars = source.unicodeScalars
        var index = scalars.startIndex
        var text = String.UnicodeScalarView()

        func flushText() {
            if !text.isEmpty { result.append(.text(String(text))); text = String.UnicodeScalarView() }
        }

        while index < scalars.endIndex {
            let scalar = scalars[index]
            guard scalar == "\\" else {
                text.append(scalar)
                index = scalars.index(after: index)
                continue
            }
            var cursor = scalars.index(after: index)
            var nested = false
            if cursor < scalars.endIndex, scalars[cursor] == "+" {
                nested = true
                cursor = scalars.index(after: cursor)
            }
            var name = String.UnicodeScalarView()
            while cursor < scalars.endIndex, isNameScalar(scalars[cursor]) {
                name.append(scalars[cursor])
                cursor = scalars.index(after: cursor)
            }
            if cursor < scalars.endIndex, scalars[cursor] == "*" {
                flushText()
                result.append(.end(String(name), nested: nested))
                index = scalars.index(after: cursor)
                continue
            }
            guard !name.isEmpty else {
                text.append(scalar)                          // a lone backslash is text
                index = scalars.index(after: index)
                continue
            }
            flushText()
            result.append(.marker(String(name), nested: nested))
            // The space or line end after a marker belongs to it.
            if cursor < scalars.endIndex {
                let next = scalars[cursor]
                if next == " " || next == "\t" || next == "\n" {
                    cursor = scalars.index(after: cursor)
                } else if next == "\r" {
                    cursor = scalars.index(after: cursor)
                    if cursor < scalars.endIndex, scalars[cursor] == "\n" { cursor = scalars.index(after: cursor) }
                }
            }
            index = cursor
        }
        flushText()
        return result
    }

    private static func isNameScalar(_ s: Unicode.Scalar) -> Bool {
        (s >= "a" && s <= "z") || (s >= "A" && s <= "Z") || (s >= "0" && s <= "9") || s == "-"
    }
}
