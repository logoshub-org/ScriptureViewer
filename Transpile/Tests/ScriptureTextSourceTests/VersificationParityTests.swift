// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest
import Foundation
import ScriptureText
import ScriptureTextVersification

/// The versifications as Swift and as Kotlin: Paratext's six systems read from their embedded files (every book, chapter, mapping and
/// excluded verse, and the mappings applied both ways and across systems), the book table, and the reader on a file with the cases the
/// six do not have (CRLF line ends, `&` and `*` lines, verse parts, a reversed range, an unknown book). The expected file was written
/// by the Swift run, before the reader was rewritten for the transpiler.
final class VersificationParityTests: XCTestCase {

    func testVersificationsMatchSwift() throws {
        let actual = digests()
        let url = try XCTUnwrap(Bundle.module.url(forResource: "expected_versification", withExtension: "txt"))
        let wanted = try String(contentsOf: url, encoding: .utf8)
        if actual != wanted {
            let a = actual.split(separator: "\n", omittingEmptySubsequences: false)
            let w = wanted.split(separator: "\n", omittingEmptySubsequences: false)
            var k = 0
            while k < a.count && k < w.count && a[k] == w[k] { k += 1 }
            print("DIFF versification at line " + String(k))
            print("DIFF actual: " + (k < a.count ? String(a[k]) : "<end>"))
            print("DIFF wanted: " + (k < w.count ? String(w[k]) : "<end>"))
        }
        XCTAssertTrue(actual == wanted, "the versifications differ from Swift's")
    }

    #if !SKIP
    /// macOS only: writes the expected file next to the test, when asked (GENERATE_EXPECTED=1).
    func testGenerateVersificationExpectedWhenAsked() throws {
        guard ProcessInfo.processInfo.environment["GENERATE_EXPECTED"] == "1" else { return }
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources")
        try digests().write(to: folder.appendingPathComponent("expected_versification.txt"), atomically: true, encoding: .utf8)
    }
    #endif

    /// A file with what the six standard ones lack.
    private let sample = "# Versification  \"Sample\" \r\n# Version=1\r\nGEN 1:31 2:25 3:24\r\nPSA 1:6 3:9\r\nxyz 1:5\r\nQQQ 1:4 2:3\r\n"
        + "\n\nGEN 1:1-3 = GEN 1:2-4\nPSA 3:1-8 = PSA 3:2-9 # a comment\nESG 4:17 = ESG 4:17a\nDAG 3:52-23 = DAG 3:53\n"
        + "-ACT 8:37\n-GEN 1:2b\n&GEN 1:1 = GEN 1:1\n*GEN 1:5,a,b\nnot a line at all\nGEN 1:x\nGEN 1:1 = GEN 1:9\n   \t\n"
        + "GEN 2:1-2 =GEN 2:3\nREV 1:20\r"

    private func reference(_ r: VerseReference) -> String { r.description }

    private func digest(_ system: Versification) -> String {
        var out = "# " + system.name + " books=" + String(system.books.count) + " mappings=" + String(system.mappings.count)
        out += " excluded=" + String(system.excludedVerses.count) + "\n"
        for book in system.books {
            var verses = ""
            for count in book.versesPerChapter { verses += (verses.isEmpty ? "" : ",") + String(count) }
            out += "B " + book.name + " | " + book.osisID + " " + book.testament.rawValue + " " + verses + "\n"
        }
        for mapping in system.mappings {
            out += "M " + reference(mapping.here) + " > " + reference(mapping.original) + " x" + String(mapping.count)
            out += " : " + reference(system.originalVerse(for: mapping.here)) + " < " + reference(system.verse(forOriginal: mapping.original))
            out += " ~ " + reference(system.verse(mapping.here, in: Versification.english)) + "\n"
        }
        for verse in system.excludedVerses {
            out += "X " + reference(verse) + " " + (system.contains(verse) ? "contained" : "not contained") + "\n"
        }
        return out
    }

    private func digests() -> String {
        var out = ""
        for system in Versification.paratextSystems { out += digest(system) }
        let codes: [String] = ["org", "ENG", "Septuagint", "vul", "rsc", "Russian Orthodox", "kjv"]
        for code in codes { out += "P " + code + " " + (Versification.paratext(code)?.name ?? "none") + "\n" }
        for book in ParatextBook.all {
            out += "T " + book.code + " " + book.osisID + " " + book.name + " " + book.testament.rawValue
            out += " " + (ParatextBook.book(code: book.code.lowercased())?.osisID ?? "-") + " " + (ParatextBook.book(osisID: book.osisID)?.code ?? "-") + "\n"
        }
        out += digest(VRSReader.versification(from: sample))
        out += digest(VRSReader.versification(from: sample, name: "Renamed"))
        out += digest(VRSReader.versification(from: "GEN 1:3\n"))
        return out
    }
}
