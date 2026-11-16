// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Character-level content transforms (plan D47): Greek accents, Hebrew vowel
// points and Hebrew cantillation. They change which characters are in the text,
// so by D41's rule they are parser options, not style rules; every parser
// applies the same struct to the text it emits, before offsets are recorded.
//
// Each flag says what to KEEP (true = leave the text alone), matching the
// "On" state of the matching SWORD option. A host sets one to false only when
// the preference is off and the module declares the filter, as SWORD does.
//
// The rules are written from the Unicode properties of the characters, one
// scalar at a time (no string-wide normalisation, so unrelated text is never
// recomposed), and are checked against SWORD's own tables by a local script.

import Foundation

public struct TextTransforms: Equatable, Sendable {
    /// Keep Greek accents, breathings, diaeresis and iota subscript.
    public var greekAccents = true
    /// Keep Hebrew vowel points.
    public var hebrewPoints = true
    /// Keep Hebrew cantillation (accent) marks.
    public var hebrewCantillation = true

    public init(greekAccents: Bool = true, hebrewPoints: Bool = true, hebrewCantillation: Bool = true) {
        self.greekAccents = greekAccents
        self.hebrewPoints = hebrewPoints
        self.hebrewCantillation = hebrewCantillation
    }

    /// True when `apply` returns its input unchanged.
    public var isIdentity: Bool { greekAccents && hebrewPoints && hebrewCantillation }

    public func apply(_ text: String) -> String {
        guard !isIdentity else { return text }
        var result: [Int] = []
        var afterGreek = false      // the previous scalar was Greek or Coptic (or an accent dropped after one)
        for v in CodePoints.of(text) {
            if v >= 0x0590, v <= 0x05C4 {
                if !hebrewPoints, Self.isHebrewPoint(v) { continue }
                if !hebrewCantillation, Self.isHebrewCantillation(v) { continue }
            }
            guard !greekAccents else { result.append(v); continue }

            // Marks that only mean "accent" when they sit on a Greek letter: a
            // Latin é, or an apostrophe in English text, must survive.
            if Self.isCombiningAccent(v) || v == 0x2019 {
                if afterGreek { continue }
                result.append(v)
                continue
            }
            // Characters that exist only as Greek accents.
            if Self.isStandaloneAccent(v) { continue }

            if Self.isPrecomposedGreek(v) {
                result.append(Self.baseLetter(of: v))
            } else {
                result.append(v)
            }
            afterGreek = Self.isGreekish(v)
        }
        return CodePoints.string(result)
    }

    // MARK: Hebrew

    /// U+05B0–05BF except the maqaf (U+05BE), which joins words and is
    /// punctuation. The shin and sin dots (U+05C1–05C2) are left in, as SWORD
    /// leaves them.
    static func isHebrewPoint(_ v: Int) -> Bool {
        v >= 0x05B0 && v <= 0x05BF && v != 0x05BE
    }

    /// U+0590–05AF and the nun hafukha (U+05C4).
    static func isHebrewCantillation(_ v: Int) -> Bool {
        (v >= 0x0590 && v <= 0x05AF) || v == 0x05C4
    }

    // MARK: Greek

    static func isGreekish(_ v: Int) -> Bool {
        (v >= 0x0370 && v <= 0x03FF) || (v >= 0x1F00 && v <= 0x1FFF) || (v >= 0x2C80 && v <= 0x2CFF)
    }

    /// Precomposed letters worth decomposing: Greek and Coptic, Greek Extended.
    private static func isPrecomposedGreek(_ v: Int) -> Bool {
        (v >= 0x0370 && v <= 0x03FF) || (v >= 0x1F00 && v <= 0x1FFF)
    }

    /// Combining accents: grave, acute, circumflex, macron, breve, diaeresis,
    /// comma above, reversed comma above, perispomeni, koronis, iota subscript,
    /// and the Coptic combining macron halves.
    static func isCombiningAccent(_ v: Int) -> Bool {
        switch v {
        case 0x0300, 0x0301, 0x0302, 0x0304, 0x0306, 0x0308, 0x0313, 0x0314, 0x0342, 0x0343, 0x0345,
             0xFE24, 0xFE25, 0xFE26: true
        default: false
        }
    }

    /// Spacing characters that are accents and nothing else: psili, koronis,
    /// ypogegrammeni, and the Coptic morphological divider.
    private static func isStandaloneAccent(_ v: Int) -> Bool {
        v == 0x1FBF || v == 0x1FBD || v == 0x037A || v == 0x2CFF
    }

    /// A precomposed letter becomes its base when it decomposes to a letter plus
    /// accents only; anything else is kept. U+03D3 and U+03D4 (hook-upsilon
    /// symbols, not letters of running text) are left alone, as SWORD leaves them.
    private static func baseLetter(of v: Int) -> Int {
        let parts = CodePoints.decomposed(v)
        if parts.count > 1, v != 0x03D3, v != 0x03D4, CodePoints.isAlphabetic(parts[0]) {
            var k = 1
            while k < parts.count {
                if !isCombiningAccent(parts[k]) { return v }
                k += 1
            }
            return parts[0]
        }
        return v
    }
}
