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

import ScriptureText

enum USFMToken: Equatable {
    /// `\name`, or `\+name` (`nested`) inside another character style.
    case marker(String, nested: Bool)
    /// `\name*`; `\*` has the empty name.
    case end(String, nested: Bool)
    case text(String)
}

enum USFMTokenizer {

    /// Works on code points, so it reads the same on every platform (plan D158).
    static func tokens(_ source: String) -> [USFMToken] {
        var result: [USFMToken] = []
        let codes = CodePoints.of(source)
        let n = codes.count
        var index = 0
        var text: [Int] = []

        while index < n {
            let c = codes[index]
            guard c == 0x5C else {                               // a backslash
                text.append(c)
                index += 1
                continue
            }
            var cursor = index + 1
            var nested = false
            if cursor < n, codes[cursor] == 0x2B {               // `+`
                nested = true
                cursor += 1
            }
            let nameStart = cursor
            while cursor < n, isNameCode(codes[cursor]) { cursor += 1 }
            let name = CodePoints.string(codes, nameStart, cursor)
            if cursor < n, codes[cursor] == 0x2A {               // `*`
                if !text.isEmpty { result.append(USFMToken.text(CodePoints.string(text))); text = [] }
                result.append(USFMToken.end(name, nested: nested))
                index = cursor + 1
                continue
            }
            guard cursor > nameStart else {
                text.append(c)                                  // a lone backslash is text
                index += 1
                continue
            }
            if !text.isEmpty { result.append(USFMToken.text(CodePoints.string(text))); text = [] }
            result.append(USFMToken.marker(name, nested: nested))
            // The space or line end after a marker belongs to it.
            if cursor < n {
                let next = codes[cursor]
                if next == 0x20 || next == 0x09 || next == 0x0A {
                    cursor += 1
                } else if next == 0x0D {
                    cursor += 1
                    if cursor < n, codes[cursor] == 0x0A { cursor += 1 }
                }
            }
            index = cursor
        }
        if !text.isEmpty { result.append(USFMToken.text(CodePoints.string(text))) }
        return result
    }

    private static func isNameCode(_ c: Int) -> Bool {
        (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || (c >= 0x30 && c <= 0x39) || c == 0x2D
    }
}
