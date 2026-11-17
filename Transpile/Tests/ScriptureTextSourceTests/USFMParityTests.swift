// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest
import Foundation
import ScriptureText
import ScriptureTextUSFM

/// USFM as Swift and as Kotlin. Excerpts of real books (each the book's opening lines and some chapters): Genesis 1–3 and Psalm 119
/// of the KJV 2006 (eBible.org, public domain), John 1 of the Berean Standard Bible with Strong's numbers (public domain), and
/// Matthew 5 and Tobit 1 of the World English Bible (public domain): every chapter with four sets of options, each file parsed whole,
/// the books' names and verse counts, and the five read as one Bible from a folder (its versification found by fit, then declared by
/// a Paratext `Settings.xml`). And fragments with the markers the excerpts lack. The expected file was written by the Swift run.
final class USFMParityTests: XCTestCase {

    private static let files: [String] = ["usfm_kjv_gen", "usfm_kjv_psa", "usfm_bsb_jhn", "usfm_web_mat", "usfm_web_tob"]

    func testUSFMMatchesSwift() throws {
        let actual = try digests()
        let url = try XCTUnwrap(Bundle.module.url(forResource: "expected_usfm", withExtension: "txt"))
        let wanted = try String(contentsOf: url, encoding: .utf8)
        if actual != wanted {
            let a = actual.split(separator: "\n", omittingEmptySubsequences: false)
            let w = wanted.split(separator: "\n", omittingEmptySubsequences: false)
            var k = 0
            while k < a.count && k < w.count && a[k] == w[k] { k += 1 }
            var label = ""
            var j = 0
            while j <= k && j < a.count {
                if a[j].hasPrefix("# ") { label = String(a[j]) }
                j += 1
            }
            print("DIFF usfm at line " + String(k) + " in " + label)
            print("DIFF actual: " + (k < a.count ? String(a[k]) : "<end>"))
            print("DIFF wanted: " + (k < w.count ? String(w[k]) : "<end>"))
        }
        XCTAssertTrue(actual == wanted, "the USFM output differs from Swift's")
    }

    #if !SKIP
    /// macOS only: writes the expected file next to the test, when asked (GENERATE_EXPECTED=1).
    func testGenerateUSFMExpectedWhenAsked() throws {
        guard ProcessInfo.processInfo.environment["GENERATE_EXPECTED"] == "1" else { return }
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources")
        try digests().write(to: folder.appendingPathComponent("expected_usfm.txt"), atomically: true, encoding: .utf8)
    }
    #endif

    private func text(_ name: String, _ ext: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func optionSets() -> [USFMParser.Options] {
        var rich = USFMParser.Options()
        rich.strongsMarkers = true
        rich.morphMarkers = true
        rich.versePerLine = true
        var bare = USFMParser.Options()
        bare.headings = false
        bare.footnotes = false
        bare.crossReferences = false
        bare.redLetter = false
        bare.verseNumbers = false
        var noMarks = USFMParser.Options()
        noMarks.greekAccents = false
        noMarks.hebrewPoints = false
        noMarks.hebrewCantillation = false
        return [USFMParser.Options(), rich, bare, noMarks]
    }

    private func joined(_ values: [Int]) -> String {
        var out = ""
        for value in values { out += (out.isEmpty ? "" : ",") + String(value) }
        return out
    }

    private func describe(_ bible: USFMBible) -> String {
        var source = ""
        switch bible.versificationSource {
        case .settings: source = "settings"
        case .vrsFile(let file): source = "vrs " + file
        case .bestFit: source = "bestFit"
        case .host: source = "host"
        }
        let f = bible.features()
        var out = "# bible " + bible.name + " " + bible.versification.name + " " + source + " books=" + String(bible.books.count) + "\n"
        out += "F " + String(f.headings) + " " + String(f.footnotes) + " " + String(f.crossReferences) + " " + String(f.redLetter) + " "
        out += String(f.strongs) + " " + String(f.morphology) + "\n"
        for book in bible.versification.books { out += "B " + book.osisID + " " + joined(book.versesPerChapter) + "\n" }
        for file in bible.books { out += "K " + file.code + " " + file.osisID + " " + file.name + " " + joined(file.chapters) + "\n" }
        return out
    }

    private func digests() throws -> String {
        var out = ""
        let options = optionSets()
        var texts: [String] = []
        for name in Self.files {
            let text = try text(name, "usfm")
            texts.append(text)
            guard let book = USFMBook(text) else {
                out += "# " + name + " no book\n"
                continue
            }
            var lasts = ""
            for chapter in book.chapters { lasts += " " + String(chapter) + ":" + String(book.lastVerses[chapter] ?? 0) }
            out += "# book " + name + " " + book.code + " | " + (book.shortName ?? "-") + " | " + (book.longName ?? "-") + " | "
            out += (book.abbreviation ?? "-") + " | " + (book.chapterLabel ?? "-") + " |" + lasts + "\n"
            for chapter in book.chapters {
                var o = 0
                for option in options {
                    if let model = USFMParser(options: option).parse(book, chapter: chapter) {
                        out += ModelDigest.of(name + " " + String(chapter) + " options" + String(o), model)
                    }
                    o += 1
                }
            }
            out += ModelDigest.of(name + " whole", USFMParser().parse(text))
        }
        var k = 0
        for fragment in try JSONDecoder().decode([String].self, from: Data(try text("usfm_fragments", "json").utf8)) {
            var o = 0
            for option in options {
                out += ModelDigest.of("fragment " + String(k) + " options" + String(o), USFMParser(options: option).parse(fragment))
                o += 1
            }
            k += 1
        }

        // The five as one Bible, from a folder: by fit, then with a Paratext Settings.xml that declares English.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("usfm-parity-" + UUID().uuidString + "_usfm")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var i = 0
        while i < texts.count {
            try texts[i].write(to: folder.appendingPathComponent(String(i + 1) + "-" + Self.files[i] + ".usfm"), atomically: true,
                               encoding: .utf8)
            i += 1
        }
        try "not a book".write(to: folder.appendingPathComponent("00-FRT.usfm"), atomically: true, encoding: .utf8)
        let bible = try USFMBible(folder: folder, name: "Parity")
        out += describe(bible)
        var display = ScriptureDisplayOptions()
        display.headings = true
        display.footnotes = true
        display.redLetter = true
        if let john = bible.chapter(book: "John", chapter: 1, display: display) { out += ModelDigest.of("bible John 1", john) }
        try "<ScriptureText><Versification>4</Versification></ScriptureText>".write(
            to: folder.appendingPathComponent("Settings.xml"), atomically: true, encoding: .utf8)
        out += describe(try USFMBible(folder: folder, name: "Declared"))
        return out
    }
}
