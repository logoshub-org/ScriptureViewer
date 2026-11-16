// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
@testable import ScriptureText

@Suite("TextTransforms (D47)")
struct TextTransformsTests {

    private func scalars(_ s: String) -> String {
        s.unicodeScalars.map { String($0.value, radix: 16, uppercase: true) }.joined(separator: " ")
    }

    @Test func keepingEverythingChangesNothing() {
        let t = TextTransforms()
        #expect(t.isIdentity)
        let s = "בְּרֵאשִׁ֖ית ἐν ἀρχῇ ἦν ὁ λόγος"
        #expect(t.apply(s) == s)
    }

    @Test func hebrewPointsAreRemovedButNotMaqafOrShinDot() {
        let t = TextTransforms(hebrewPoints: false)
        // sheva, hiriq, patah, qamats, holam, dagesh, rafe go; maqaf and the shin dot stay.
        #expect(scalars(t.apply("\u{05D1}\u{05B0}\u{05B4}\u{05B7}\u{05B8}\u{05B9}\u{05BC}\u{05BF}")) == "5D1")
        #expect(scalars(t.apply("\u{05D0}\u{05BE}\u{05D1}")) == "5D0 5BE 5D1")
        #expect(scalars(t.apply("\u{05E9}\u{05C1}\u{05B8}")) == "5E9 5C1")
    }

    @Test func cantillationIsRemovedIndependentlyOfPoints() {
        let t = TextTransforms(hebrewCantillation: false)
        // etnahta (0591) and sof pasuq's neighbour nun hafukha (05C4) go; the qamats stays.
        #expect(scalars(t.apply("\u{05D1}\u{05B8}\u{0591}\u{05C4}")) == "5D1 5B8")
        #expect(scalars(TextTransforms(hebrewPoints: false).apply("\u{05D1}\u{0591}")) == "5D1 591")
    }

    @Test func precomposedPolytonicGreekLosesAccents() {
        let t = TextTransforms(greekAccents: false)
        #expect(t.apply("Ἐν ἀρχῇ ἦν ὁ λόγος") == "Εν αρχη ην ο λογος")
        #expect(t.apply("τῷ Θεῷ") == "τω Θεω")                  // iota subscript goes with the base
        #expect(t.apply("ΐ") == "ι")
        #expect(t.apply("Ἅιδης") == "Αιδης")
    }

    @Test func combiningAndSpacingGreekMarksAreDropped() {
        let t = TextTransforms(greekAccents: false)
        #expect(t.apply("α\u{0301}\u{0313}") == "α")
        #expect(t.apply("\u{1FBF}\u{037A}\u{1FBD}x") == "x")
        #expect(t.apply("\u{2019}x") == "\u{2019}x")             // not after a Greek letter: an ordinary apostrophe
    }

    @Test func otherTextIsNeverTouched() {
        let t = TextTransforms(greekAccents: false, hebrewPoints: false, hebrewCantillation: false)
        let s = "café — déjà vu, 日本語 \u{0301}x God\u{2019}s"
        #expect(t.apply(s) == s)                                  // Latin accents, CJK, a stray mark, an apostrophe
        #expect(t.apply("e\u{0301}") == "e\u{0301}")             // no recomposition of unrelated text
    }

    @Test func accentsAreDroppedOnlyAfterGreekLetters() {
        let t = TextTransforms(greekAccents: false)
        #expect(t.apply("ἀλλ\u{2019} ἐγώ") == "αλλ εγω")          // elision mark follows a Greek letter
        #expect(t.apply("α\u{0313}\u{0301}e\u{0301}") == "αe\u{0301}")
        #expect(t.apply("\u{2C81}\u{FE24}") == "\u{2C81}")      // Coptic: a macron half follows a Coptic letter
    }

    // MARK: SWORD parity (local; the table is GPL, so it is read from a file, never committed)

    /// Checks the rule against every entry of SWORD's utf8greekaccents.cpp and sweeps the
    /// Greek ranges for characters the rule changes but SWORD leaves alone.
    /// `python3 -I export_greek_table.py <utf8greekaccents.cpp> <out.json>`; then
    /// `SWORD_GREEK_TABLE=<out.json> swift test --filter greekRuleMatchesSwordTable`
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SWORD_GREEK_TABLE"] != nil))
    func greekRuleMatchesSwordTable() throws {
        let path = try #require(ProcessInfo.processInfo.environment["SWORD_GREEK_TABLE"])
        let table = try JSONDecoder().decode([String: [UInt32]].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let t = TextTransforms(greekAccents: false)
        var wrong: [String] = []
        for (key, values) in table {
            let v = UInt32(key, radix: 16)!
            let expected = String(String.UnicodeScalarView(values.compactMap(Unicode.Scalar.init)))
            // Each character is tried after a Greek letter, where the contextual marks apply.
            let actual = String(String.UnicodeScalarView(t.apply("α" + String(Unicode.Scalar(v)!)).unicodeScalars.dropFirst()))
            if actual != expected { wrong.append("\(key): SWORD \(scalars(expected)) rule \(scalars(actual))") }
        }
        // Characters SWORD leaves alone must stay.
        var extra: [String] = []
        for v in Array(0x0300...0x03FF) + Array(0x1F00...0x1FFF) + [0x2019, 0x2CFF, 0xFE24, 0xFE25, 0xFE26] {
            guard let u = Unicode.Scalar(UInt32(v)), table[String(format: "%04X", v)] == nil else { continue }
            let actual = String(String.UnicodeScalarView(t.apply("α" + String(u)).unicodeScalars.dropFirst()))
            if actual != String(u) { extra.append("\(String(format: "%04X", v)): rule \(scalars(actual)), SWORD unchanged") }
        }
        print("table entries: \(table.count); rule differs on \(wrong.count); rule changes \(extra.count) SWORD leaves")
        for line in (wrong.sorted() + extra.sorted()) { print(line) }

        // Known, deliberate differences, pinned so any new one fails.
        // 1. SWORD's table has entries for eight code points Unicode has not assigned
        //    (it looks like an off-by-one in the extended block); no text contains them.
        let unassigned = wrong.filter { line in
            Unicode.Scalar(UInt32(line.prefix(4), radix: 16)!)!.properties.generalCategory == .unassigned
        }
        #expect(unassigned.count == 8)
        #expect(wrong.count == unassigned.count)
        // 2. SWORD omits U+0390 and U+03B0 (iota/upsilon with dialytika and tonos), the two
        //    precomposed letters whose accents it forgot; the rule strips them like their siblings.
        // 3. The combining macron, breve and iota subscript (U+0304, U+0306, U+0345) are not in
        //    SWORD's list, although it strips them from the precomposed letters (ᾱ, ᾰ, ᾳ); after a
        //    Greek letter the rule treats the decomposed spelling the same way.
        #expect(extra.map { String($0.prefix(4)) }.sorted() == ["0304", "0306", "0345", "0390", "03B0"])
    }
}
