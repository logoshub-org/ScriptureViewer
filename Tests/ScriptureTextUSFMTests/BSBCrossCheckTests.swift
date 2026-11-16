// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import ScriptureText
import ScriptureTextOSIS
import ScriptureTextTestSupport
import ScriptureTextVersification
@testable import ScriptureTextUSFM

// LOCAL-ONLY (plan Track V4, test group 7): the Berean Standard Bible twice, the USFM set in SCRIPTURE_USFM_DIR
// (`bsb_usfm`) against CrossWire's BSB module as exported in SCRIPTURE_CORPUS_DIR (`BSB.jsonl`). The BSB is not
// committed: its licence is not the KJV's.
//
// Found 2026-10-26: the two are different revisions of the BSB, not one edition twice. Of 31,086 verses, 2,273 read
// differently ("so angry and furious" against "so furious with anger", Dan 2:12), 77 chapters differ in which verses
// they have, SWORD's notes start with their reference ("1:2 That is, Babylonia"), and SWORD's Acts has no red letter.
// So the text is reported, not asserted; what both revisions share is asserted: the divine name in every verse.

private let usfmDirectory = ProcessInfo.processInfo.environment["SCRIPTURE_USFM_DIR"]
private let corpusDirectory = ProcessInfo.processInfo.environment["SCRIPTURE_CORPUS_DIR"]

@Suite(.enabled(if: usfmDirectory != nil && corpusDirectory != nil, "set SCRIPTURE_USFM_DIR and SCRIPTURE_CORPUS_DIR"))
struct BSBCrossCheckTests {

    @Test func comparedWithSWORDsBSB() throws {
        // The module's chapters, in canon order, one line each.
        let lines = try Data(contentsOf: URL(fileURLWithPath: try #require(corpusDirectory)).appendingPathComponent("BSB.jsonl"))
            .split(separator: UInt8(ascii: "\n"))
        let canon = (KJVVersification.oldTestament + KJVVersification.newTestament)
            .flatMap { book in (1...book.verses.count).map { "\(book.osis) \($0)" } }
        try #require(lines.count == canon.count)
        var sword: [String: [OSISParser.VerseEntry]] = [:]
        for (key, line) in zip(canon, lines) {
            let object = try #require(try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
            let rows = try #require(object["entries"] as? [[Any]])
            sword[key] = rows.compactMap { row in
                guard row.count == 2, let verse = row[0] as? Int, let osis = row[1] as? String else { return nil }
                return .init(verse: verse, osis: osis)
            }
        }

        let folder = URL(fileURLWithPath: try #require(usfmDirectory)).appendingPathComponent("bsb_usfm")
        var compared = 0
        var differences: [String: [String]] = [:]
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            where file.pathExtension.lowercased() == "usfm" {
            let book = try #require(USFMBook(try String(contentsOf: file, encoding: .utf8)))
            let osis = try #require(ParatextBook.book(code: book.code)?.osisID)
            for number in book.chapters {
                let usfm = KJVCrossCheckTests.facts(try #require(USFMParser().parse(book, chapter: number)))
                let other = KJVCrossCheckTests.facts(OSISParser().parse(try #require(sword["\(osis) \(number)"])))
                if Set(usfm.keys) != Set(other.keys) { differences["verses", default: []].append("\(osis) \(number)") }
                for verse in other.keys.sorted() {
                    guard let a = usfm[verse], let b = other[verse] else { continue }
                    compared += 1
                    let reference = "\(osis) \(number):\(verse)"
                    for (kind, x, y) in [("text", a.text, b.text), ("red letter", a.redLetter, b.redLetter),
                                         ("divine name", a.divineName, b.divineName), ("italic", a.italic, b.italic),
                                         ("notes", a.notes.joined(separator: " | "), b.notes.joined(separator: " | "))] where x != y {
                        differences[kind, default: []].append("\(reference)\n  usfm:  \(x)\n  sword: \(y)")
                    }
                }
            }
        }
        print("BSB: \(compared) verses compared")
        for (kind, list) in differences.sorted(by: { $0.key < $1.key }) {
            print("BSB \(kind): \(list.count) differ; first:\n\(list.prefix(5).joined(separator: "\n"))")
        }
        #expect(compared == 31_086)
        #expect(differences["divine name"] == nil)
    }
}
