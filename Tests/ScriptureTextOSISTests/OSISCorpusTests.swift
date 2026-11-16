// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Testing
import ScriptureText
@testable import ScriptureTextOSIS

// LOCAL-ONLY corpus run (plan test group 6/7, D24).
//
// Parses every chapter of every locally exported module through OSISParser and
// checks invariants plus an independent word count. Module text is never
// committed, so the export lives outside the repo and this test is skipped
// unless SCRIPTURE_CORPUS_DIR points at a folder of `<Module>.jsonl` files,
// one chapter per line: {"module", "entries": [[verse, osis], …],
// "expectedWords"}.

private let corpusDirectory: String? = ProcessInfo.processInfo.environment["SCRIPTURE_CORPUS_DIR"]

@Suite(.enabled(if: corpusDirectory != nil, "set SCRIPTURE_CORPUS_DIR to run the local corpus"))
struct OSISCorpusTests {

    private struct Chapter {
        var entries: [OSISParser.VerseEntry]
        var expectedWords: Int
    }

    private func chapters(in file: URL) throws -> [Chapter] {
        let data = try Data(contentsOf: file)
        var result: [Chapter] = []
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let object = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let rows = object["entries"] as? [[Any]] else { continue }
            let entries = rows.compactMap { row -> OSISParser.VerseEntry? in
                guard row.count == 2, let verse = row[0] as? Int, let osis = row[1] as? String else { return nil }
                return .init(verse: verse, osis: osis)
            }
            result.append(.init(entries: entries, expectedWords: object["expectedWords"] as? Int ?? -1))
        }
        return result
    }

    @Test func everyChapterOfEveryModuleParsesConsistently() throws {
        let directory = URL(fileURLWithPath: try #require(corpusDirectory))
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try #require(!files.isEmpty, "no .jsonl files in \(directory.path)")

        var optionVariants: [(String, OSISParser.Options)] = [("default", .init())]
        var rich = OSISParser.Options()
        rich.strongsMarkers = true; rich.morphMarkers = true; rich.variants = .all
        optionVariants.append(("markers+all variants", rich))

        for file in files {
            let module = file.deletingPathExtension().lastPathComponent
            let all = try chapters(in: file)
            #expect(!all.isEmpty, "\(module): no chapters")

            for (label, options) in optionVariants {
                let parser = OSISParser(options: options)
                var problems: [String] = []
                var wordMismatches = 0, doubleSpaces = 0, brokenMarkers = 0
                var maxChapterMillis = 0.0, totalWords = 0, totalVerses = 0
                let clock = ContinuousClock()
                let started = clock.now

                for (index, chapter) in all.enumerated() {
                    let t0 = clock.now
                    let model = parser.parse(chapter.entries)
                    let millis = Double((clock.now - t0).components.attoseconds) / 1e15
                        + Double((clock.now - t0).components.seconds) * 1000
                    maxChapterMillis = max(maxChapterMillis, millis)

                    if !model.isConsistent { problems.append("chapter \(index): inconsistent spans/verses") }

                    let words = model.spans.filter { if case .word = $0.attribute { true } else { false } }.count
                    totalWords += words
                    // The word count is only exact when no variants are dropped differently
                    // from the independent count, which assumes the primary reading.
                    if options.variants == .primary, chapter.expectedWords >= 0, words != chapter.expectedWords {
                        wordMismatches += 1
                        if wordMismatches <= 3 {
                            problems.append("chapter \(index): \(words) word spans, expected \(chapter.expectedWords)")
                        }
                    }

                    // Every verse range that has content starts with its own number.
                    totalVerses += model.verses.count
                    for range in model.verses where range.length > 0 && options.markersAreVerseNumbers {
                        if let text = model.substring(utf16Start: range.start, length: range.length),
                           !text.hasPrefix(String(range.verse)) {
                            brokenMarkers += 1
                            if brokenMarkers <= 3 { problems.append("chapter \(index) verse \(range.verse): range does not start with its number") }
                        }
                    }

                    if model.text.contains("  ") || model.text.contains(" \n") || model.text.contains("\n ") {
                        doubleSpaces += 1
                        if doubleSpaces <= 3 { problems.append("chapter \(index): unexpected ASCII whitespace run") }
                    }
                    if model.text.hasPrefix(" ") || model.text.hasSuffix(" ") || model.text.hasSuffix("\n") {
                        problems.append("chapter \(index): leading/trailing whitespace")
                    }
                }

                let elapsed = clock.now - started
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                print("CORPUS \(module) [\(label)]: \(all.count) chapters, \(totalVerses) verses, \(totalWords) word spans, "
                      + "\(String(format: "%.2f", seconds)) s total, worst chapter \(String(format: "%.1f", maxChapterMillis)) ms")
                #expect(problems.isEmpty, "\(module) [\(label)]: \(problems.prefix(6).joined(separator: "; "))")
                #expect(wordMismatches == 0, "\(module) [\(label)]: \(wordMismatches) chapters with a word-count mismatch")
            }
        }
    }
}

// MARK: - Tokenizer vs XMLParser over every real chapter

extension OSISCorpusTests {

    /// True when the string ends inside a tag (the module entry was cut off).
    private static func endsInsideATag(_ s: String) -> Bool {
        guard let lt = s.lastIndex(of: "<") else { return false }
        return !s[lt...].contains(">")
    }

    /// The string with a cut-off final tag removed — a deliberately independent
    /// operation, so it does not borrow the tokenizer's own tolerance logic.
    private static func droppingCutOffTail(_ s: String) -> String {
        guard endsInsideATag(s), let lt = s.lastIndex(of: "<") else { return s }
        return String(s[..<lt])
    }

    /// The oracle (plan D32, test group 6) on real data: the whole chapter is
    /// one XML stream (D34), so XMLParser can read it, and its events must match
    /// the tokenizer's exactly — zero divergence is the expected result.
    ///
    /// One legitimate exception: real modules contain entries cut off mid-tag
    /// (the LXX has a verse whose true length wrapped the 16-bit index size
    /// field; the Azeri module's last two entries end in `<div eID="`), and
    /// XMLParser rightly rejects such a chapter. Those chapters are accepted
    /// only if an entry really is cut off, and then everything *else* in them
    /// must still agree once the cut-off tails are removed.
    @Test func tokenizerAgreesWithXMLParserOnEveryChapter() throws {
        let directory = URL(fileURLWithPath: try #require(corpusDirectory))
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try #require(!files.isEmpty)

        for file in files {
            let module = file.deletingPathExtension().lastPathComponent
            let data = try Data(contentsOf: file)
            var chapters = 0, divergent = 0, rejected = 0, truncatedChapters = 0, events = 0
            var examples: [String] = []

            for line in data.split(separator: UInt8(ascii: "\n")) {
                guard let object = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      let rows = object["entries"] as? [[Any]] else { continue }
                let entries = rows.compactMap { $0.count == 2 ? $0[1] as? String : nil }
                chapters += 1

                func compare(_ chapter: String) -> String? {
                    let ours = XMLParserOracle.tokenizerEvents(of: chapter)
                    events += ours.count
                    do {
                        let theirs = try XMLParserOracle.events(of: chapter)
                        return XMLParserOracle.firstDifference(ours, theirs)
                    } catch {
                        return "REJECTED: \(error)"
                    }
                }

                let whole = entries.joined()
                guard let problem = compare(whole) else { continue }

                if problem.hasPrefix("REJECTED"), entries.contains(where: Self.endsInsideATag) {
                    // Expected: a cut-off entry. Everything else must still agree.
                    truncatedChapters += 1
                    let repaired = entries.map(Self.droppingCutOffTail).joined()
                    if let again = compare(repaired) {
                        divergent += 1
                        if examples.count < 3 { examples.append("chapter \(chapters) (repaired): \(again)") }
                    }
                } else if problem.hasPrefix("REJECTED") {
                    rejected += 1
                    if examples.count < 3 { examples.append("chapter \(chapters): \(problem)") }
                } else {
                    divergent += 1
                    if examples.count < 3 { examples.append("chapter \(chapters): \(problem)") }
                }
            }
            print("ORACLE \(module): \(chapters) chapters, \(events) events, \(divergent) divergent, "
                  + "\(rejected) unexplained rejections, \(truncatedChapters) chapters with a cut-off entry")
            #expect(rejected == 0, "\(module): XMLParser rejected \(rejected) chapters with no cut-off entry: \(examples.joined(separator: "; "))")
            #expect(divergent == 0, "\(module): \(divergent) chapters disagree: \(examples.joined(separator: "; "))")
        }
    }
}

// MARK: - Word anchors over every real chapter (D35, test group 13)

extension OSISCorpusTests {

    /// Anchors must be clean and must not depend on display options: every
    /// (verse, index) shown under any option set names the same word as with
    /// every reading visible and no markers (a marker inside a word may only
    /// shorten the range, never change the index).
    @Test func wordAnchorsAreCleanAndOptionIndependentOnEveryChapter() throws {
        let directory = URL(fileURLWithPath: try #require(corpusDirectory))
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try #require(!files.isEmpty)

        var reference = OSISParser.Options(); reference.variants = .all
        var bare = OSISParser.Options()
        bare.verseNumbers = false; bare.footnotes = false; bare.headings = false; bare.redLetter = false
        var rich = OSISParser.Options()
        rich.strongsMarkers = true; rich.morphMarkers = true
        let variants: [(String, OSISParser.Options, Bool)] = [
            ("default", .init(), false), ("bare", bare, false), ("markers", rich, true),
        ]

        for file in files {
            let module = file.deletingPathExtension().lastPathComponent
            var anchors = 0, problems: [String] = []
            for (index, chapter) in try chapters(in: file).enumerated() {
                let full = OSISParser(options: reference).parse(chapter.entries)
                var expected: [String: String] = [:]
                for w in full.words {
                    let text = full.substring(utf16Start: w.start, length: w.length) ?? ""
                    expected["\(w.verse).\(w.index)"] = text
                    if text.isEmpty || text.unicodeScalars.contains(where: { " \t\n\r\u{2060}".unicodeScalars.contains($0) }) {
                        if problems.count < 6 { problems.append("chapter \(index) \(w.verse).\(w.index): bad anchor text '\(text)'") }
                    }
                }
                anchors += full.words.count

                for (label, options, markers) in variants {
                    let m = OSISParser(options: options).parse(chapter.entries)
                    for w in m.words {
                        let key = "\(w.verse).\(w.index)"
                        let text = m.substring(utf16Start: w.start, length: w.length) ?? ""
                        guard let want = expected[key] else {
                            if problems.count < 6 { problems.append("chapter \(index) [\(label)] \(key): not in the reference") }
                            continue
                        }
                        let ok = markers ? want.hasPrefix(text) && !text.isEmpty : text == want
                        if !ok, problems.count < 6 {
                            problems.append("chapter \(index) [\(label)] \(key): '\(text)' vs '\(want)'")
                        }
                    }
                }
            }
            print("ANCHORS \(module): \(anchors) word anchors (all readings)")
            #expect(problems.isEmpty, "\(module): \(problems.joined(separator: "; "))")
        }
    }

    /// D47: with every transform on, the same (verse, index) words exist as with none, and
    /// each word's text is the reference text run through the transform. Catches a word made
    /// only of removed marks, and any offset drift the transform could cause.
    @Test func textTransformsKeepEveryWordAndItsIndexOnEveryChapter() throws {
        let directory = URL(fileURLWithPath: try #require(corpusDirectory))
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try #require(!files.isEmpty)

        var reference = OSISParser.Options(); reference.variants = .all
        var stripped = reference
        stripped.greekAccents = false; stripped.hebrewPoints = false; stripped.hebrewCantillation = false
        let transforms = stripped.textTransforms

        for file in files {
            let module = file.deletingPathExtension().lastPathComponent
            var words = 0, changed = 0, problems: [String] = []
            for (index, chapter) in try chapters(in: file).enumerated() {
                let a = OSISParser(options: reference).parse(chapter.entries)
                let b = OSISParser(options: stripped).parse(chapter.entries)
                guard a.words.map({ [$0.verse, $0.index] }) == b.words.map({ [$0.verse, $0.index] }) else {
                    if problems.count < 6 { problems.append("chapter \(index): word indexes differ (\(a.words.count) vs \(b.words.count))") }
                    continue
                }
                #expect(b.isConsistent, "\(module) chapter \(index)")
                for (x, y) in zip(a.words, b.words) {
                    let before = a.substring(utf16Start: x.start, length: x.length) ?? ""
                    let after = b.substring(utf16Start: y.start, length: y.length) ?? ""
                    words += 1
                    if before != after { changed += 1 }
                    if after.isEmpty || after != transforms.apply(before), problems.count < 6 {
                        problems.append("chapter \(index) \(x.verse).\(x.index): '\(before)' became '\(after)'")
                    }
                }
            }
            print("TRANSFORMS \(module): \(words) words, \(changed) changed by stripping")
            #expect(problems.isEmpty, "\(module): \(problems.joined(separator: "; "))")
        }
    }
}

private extension OSISParser.Options {
    /// Verse markers are present unless the option is turned off.
    var markersAreVerseNumbers: Bool { verseNumbers }
}
