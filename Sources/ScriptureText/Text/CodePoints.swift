// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Unicode text as an array of code points held as `Int`. `Int` is the one integer type
/// that transpiles cleanly to Kotlin (no UInt8 / UInt32 / Unicode.Scalar idioms), so the
/// text-handling code that must run on Android works on these arrays.
public enum CodePoints {
    public static func of(_ s: String) -> [Int] {
        var out: [Int] = []
        #if SKIP
        var k = 0
        while k < s.length {
            let cp = s.codePointAt(k)
            out.append(cp)
            k += (cp > 0xFFFF) ? 2 : 1
        }
        #else
        for u in s.unicodeScalars { out.append(Int(u.value)) }
        #endif
        return out
    }

    /// The last code point of a string, or nil when it is empty, without making an array of them all.
    public static func last(_ s: String) -> Int? {
        #if SKIP
        if s.length == 0 { return nil }
        return s.codePointBefore(s.length)
        #else
        return s.unicodeScalars.last.map { Int($0.value) }
        #endif
    }

    public static func string(_ codes: [Int], _ from: Int, _ to: Int) -> String {
        #if SKIP
        // A Kotlin string cannot grow in place: gathered in a builder, not by `+=` a character at a time.
        let out = java.lang.StringBuilder(to - from)
        var k = from
        while k < to {
            let scalar = codes[k]
            if scalar >= 0 && scalar <= 0x10FFFF && !(scalar >= 0xD800 && scalar <= 0xDFFF) { out.appendCodePoint(scalar) }
            k += 1
        }
        return out.toString()
        #else
        var out = ""
        var k = from
        while k < to {
            out += string(scalar: codes[k])
            k += 1
        }
        return out
        #endif
    }

    public static func string(_ codes: [Int]) -> String { string(codes, 0, codes.count) }

    public static func string(scalar: Int) -> String {
        #if SKIP
        if scalar < 0 || scalar > 0x10FFFF || (scalar >= 0xD800 && scalar <= 0xDFFF) { return "" }
        return java.lang.Character.toString(scalar)
        #else
        guard let u = Unicode.Scalar(UInt32(scalar)) else { return "" }
        return String(Character(u))
        #endif
    }

    /// Canonical decomposition (NFD) of one code point.
    public static func decomposed(_ v: Int) -> [Int] {
        #if SKIP
        let d = java.text.Normalizer.normalize(string(scalar: v), java.text.Normalizer.Form.NFD)
        return of(d)
        #else
        return of(string(scalar: v).decomposedStringWithCanonicalMapping)
        #endif
    }

    /// The Unicode Alphabetic property (Kotlin: letter category, the same for Greek).
    public static func isAlphabetic(_ v: Int) -> Bool {
        #if SKIP
        return java.lang.Character.isLetter(v)
        #else
        guard let u = Unicode.Scalar(UInt32(v)) else { return false }
        return u.properties.isAlphabetic
        #endif
    }

    /// UTF-16 code units of a string, as Int.
    public static func utf16(_ s: String) -> [Int] {
        var out: [Int] = []
        #if SKIP
        var k = 0
        while k < s.length { out.append(s[k].code); k += 1 }
        #else
        for u in s.utf16 { out.append(Int(u)) }
        #endif
        return out
    }

    public static func fromUTF16(_ units: [Int]) -> String {
        #if SKIP
        let out = java.lang.StringBuilder(units.count)
        var k = 0
        while k < units.count {
            out.append(units[k].toChar())
            k += 1
        }
        return out.toString()
        #else
        // All at once: a character outside the Basic Multilingual Plane is two units, and decoding them one at a time made each half
        // a replacement character.
        var codes: [UInt16] = []
        codes.reserveCapacity(units.count)
        for unit in units { codes.append(UInt16(truncatingIfNeeded: unit)) }
        return String(decoding: codes, as: UTF16.self)
        #endif
    }

    /// `chars[from..<to]` as a String.
    public static func string(chars: [Character], _ from: Int, _ to: Int) -> String {
        var out = ""
        var k = from
        while k < to { out += String(chars[k]); k += 1 }
        return out
    }

    /// The characters of a string as an array.
    public static func characters(_ s: String) -> [Character] {
        var out: [Character] = []
        for ch in s { out.append(ch) }
        return out
    }

    public static func utf16Length(_ s: String) -> Int {
        #if SKIP
        return s.length
        #else
        return s.utf16.count
        #endif
    }

    public static func isIdeographic(_ v: Int) -> Bool {
        #if SKIP
        return java.lang.Character.isIdeographic(v)
        #else
        guard let u = Unicode.Scalar(UInt32(v)) else { return false }
        return u.properties.isIdeographic
        #endif
    }

    // MARK: Classes of code points
    //
    // Each written once, from the Unicode general category or an explicit table, so that iOS and Android give the same answer. (The
    // platforms' own helpers differ: Java's `isWhitespace` leaves out the no-break space; Skip's `CharacterSet.whitespaces` is a
    // short fixed list.)

    /// The Unicode White_Space property: what Swift's `Character.isWhitespace` tests.
    public static func isWhiteSpace(_ v: Int) -> Bool {
        if v >= 0x09 && v <= 0x0D { return true }
        if v >= 0x2000 && v <= 0x200A { return true }
        return v == 0x20 || v == 0x85 || v == 0xA0 || v == 0x1680 || v == 0x2028 || v == 0x2029 || v == 0x202F || v == 0x205F
            || v == 0x3000
    }

    /// Tab or a space separator (category Zs): what Foundation's `CharacterSet.whitespaces` holds.
    public static func isHorizontalWhiteSpace(_ v: Int) -> Bool { v == 0x09 || group(v) == groupSpaceSeparator }

    /// Tab, a space separator, or a line end (LF to CR, NEL, the Unicode line and paragraph separators): what Foundation's
    /// `CharacterSet.whitespacesAndNewlines` holds.
    public static func isWhiteSpaceOrNewline(_ v: Int) -> Bool {
        isHorizontalWhiteSpace(v) || (v >= 0x0A && v <= 0x0D) || v == 0x85 || v == 0x2028 || v == 0x2029
    }

    /// Category P (punctuation of any kind): what Swift's `Character.isPunctuation` tests.
    public static func isPunctuation(_ v: Int) -> Bool { group(v) == groupPunctuation }

    /// Category S (symbols): what Swift's `Character.isSymbol` tests.
    public static func isSymbol(_ v: Int) -> Bool { group(v) == groupSymbol }

    /// Category Zs.
    public static func isSpaceSeparator(_ v: Int) -> Bool { group(v) == groupSpaceSeparator }

    /// Category Cf (format characters: joiners, direction marks).
    public static func isFormat(_ v: Int) -> Bool { group(v) == groupFormat }

    /// Category Nd: what a regular expression's `\d` matches.
    public static func isDecimalDigit(_ v: Int) -> Bool { group(v) == groupDecimalDigit }

    /// Category N (Nd, Nl, No).
    public static func isNumber(_ v: Int) -> Bool {
        let g = group(v)
        return g == groupDecimalDigit || g == groupOtherNumber
    }

    private static let groupOther = 0, groupPunctuation = 1, groupSymbol = 2, groupSpaceSeparator = 3, groupFormat = 4
    private static let groupDecimalDigit = 5, groupOtherNumber = 6

    private static func group(_ v: Int) -> Int {
        #if SKIP
        // SKIP INSERT: if (v < 0 || v > 0x10FFFF) return groupOther
        // SKIP INSERT: val type = java.lang.Character.getType(v)
        // SKIP INSERT: if (type == java.lang.Character.SPACE_SEPARATOR.toInt()) return groupSpaceSeparator
        // SKIP INSERT: if (type == java.lang.Character.FORMAT.toInt()) return groupFormat
        // SKIP INSERT: if (type == java.lang.Character.DECIMAL_DIGIT_NUMBER.toInt()) return groupDecimalDigit
        // SKIP INSERT: if (type == java.lang.Character.LETTER_NUMBER.toInt() || type == java.lang.Character.OTHER_NUMBER.toInt()) return groupOtherNumber
        // SKIP INSERT: if (type == java.lang.Character.CONNECTOR_PUNCTUATION.toInt() || type == java.lang.Character.DASH_PUNCTUATION.toInt() || type == java.lang.Character.START_PUNCTUATION.toInt() || type == java.lang.Character.END_PUNCTUATION.toInt() || type == java.lang.Character.INITIAL_QUOTE_PUNCTUATION.toInt() || type == java.lang.Character.FINAL_QUOTE_PUNCTUATION.toInt() || type == java.lang.Character.OTHER_PUNCTUATION.toInt()) return groupPunctuation
        // SKIP INSERT: if (type == java.lang.Character.MATH_SYMBOL.toInt() || type == java.lang.Character.CURRENCY_SYMBOL.toInt() || type == java.lang.Character.MODIFIER_SYMBOL.toInt() || type == java.lang.Character.OTHER_SYMBOL.toInt()) return groupSymbol
        return groupOther
        #else
        guard v >= 0, let u = Unicode.Scalar(UInt32(v)) else { return groupOther }
        switch u.properties.generalCategory {
        case .spaceSeparator: return groupSpaceSeparator
        case .format: return groupFormat
        case .decimalNumber: return groupDecimalDigit
        case .letterNumber, .otherNumber: return groupOtherNumber
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation:
            return groupPunctuation
        case .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol: return groupSymbol
        default: return groupOther
        }
        #endif
    }

    // MARK: Text helpers

    /// `s` without leading and trailing code points that `trim` matches.
    public static func trimmed(_ s: String, where trim: (Int) -> Bool) -> String {
        let codes = of(s)
        var start = 0
        var end = codes.count
        while start < end && trim(codes[start]) { start += 1 }
        while end > start && trim(codes[end - 1]) { end -= 1 }
        if start == 0 && end == codes.count { return s }
        return string(codes, start, end)
    }

    /// The lines of `s`: CR LF, CR and LF each end one; empty lines are kept (Swift's `split(separator:omittingEmptySubsequences: false)`
    /// after turning CR LF and CR into LF).
    public static func lines(_ s: String) -> [String] {
        let codes = of(s)
        var out: [String] = []
        var start = 0
        var k = 0
        while k < codes.count {
            let c = codes[k]
            if c == 0x0A || c == 0x0D {
                out.append(string(codes, start, k))
                if c == 0x0D && k + 1 < codes.count && codes[k + 1] == 0x0A { k += 1 }
                start = k + 1
            }
            k += 1
        }
        out.append(string(codes, start, codes.count))
        return out
    }

    /// The pieces of `s` between consecutive UTF-16 offsets in `boundaries` (ascending, each on a character boundary): with
    /// boundaries a, b, c, the pieces a..<b and b..<c. One pass over the text.
    public static func pieces(_ s: String, utf16Boundaries boundaries: [Int]) -> [String] {
        var out: [String] = []
        guard boundaries.count >= 2 else { return out }
        #if SKIP
        var k = 0
        while k + 1 < boundaries.count {
            out.append(s.substring(boundaries[k], boundaries[k + 1]))
            k += 1
        }
        #else
        let u = s.utf16
        var index = u.index(u.startIndex, offsetBy: boundaries[0])
        var k = 0
        while k + 1 < boundaries.count {
            let next = u.index(index, offsetBy: boundaries[k + 1] - boundaries[k])
            out.append(String(u[index..<next]) ?? String(decoding: Array(u[index..<next]), as: UTF16.self))
            index = next
            k += 1
        }
        #endif
        return out
    }

    /// `s` percent-encoded as UTF-8, keeping only RFC 3986's unreserved characters (letters, digits, `-._~`) as they are, with
    /// upper-case hex: what `addingPercentEncoding` gives with that set.
    public static func percentEncoded(_ s: String) -> String {
        let hex = of("0123456789ABCDEF")
        var out: [Int] = []
        func byte(_ b: Int) {
            out.append(0x25)
            out.append(hex[b >> 4])
            out.append(hex[b & 0x0F])
        }
        for v in of(s) {
            let unreserved = (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) || (v >= 0x30 && v <= 0x39)
                || v == 0x2D || v == 0x2E || v == 0x5F || v == 0x7E
            if unreserved {
                out.append(v)
            } else if v < 0x80 {
                byte(v)
            } else if v < 0x800 {
                byte(0xC0 | (v >> 6)); byte(0x80 | (v & 0x3F))
            } else if v < 0x10000 {
                byte(0xE0 | (v >> 12)); byte(0x80 | ((v >> 6) & 0x3F)); byte(0x80 | (v & 0x3F))
            } else {
                byte(0xF0 | (v >> 18)); byte(0x80 | ((v >> 12) & 0x3F)); byte(0x80 | ((v >> 6) & 0x3F)); byte(0x80 | (v & 0x3F))
            }
        }
        return string(out)
    }

    /// The non-empty pieces of `s` between `separator`s (Swift's `split(separator:)`).
    public static func split(_ s: String, separator: Character) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in s {
            if ch == separator {
                if !current.isEmpty { out.append(current) }
                current = ""
            } else {
                current += String(ch)
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
