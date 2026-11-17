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
        var out = ""
        var k = 0
        while k < units.count {
            out += String(decoding: [UInt16(units[k])], as: UTF16.self)
            k += 1
        }
        return out
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
