// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Plain-Swift helpers for what `CharacterSet` and `Character.isNumber` did, so that the portable core stays inside what Skip's
// transpiler supports. Package-visible: the parsers use them too.

public func isDigit(_ character: Character?) -> Bool {
    guard let character else { return false }
    return "0123456789".contains(character)
}

public func trimmedSpaces(_ text: String) -> String { trimmed(text, newlines: false) }

public func trimmedWhitespace(_ text: String) -> String { trimmed(text, newlines: true) }

private func trimmed(_ text: String, newlines: Bool) -> String {
    func isSpace(_ c: Character) -> Bool { c == " " || c == "\t" || (newlines && (c == "\n" || c == "\r")) }
    var start = text.startIndex
    var end = text.endIndex
    while start < end && isSpace(text[start]) { start = text.index(after: start) }
    while end > start && isSpace(text[text.index(before: end)]) { end = text.index(before: end) }
    return String(text[start..<end])
}
