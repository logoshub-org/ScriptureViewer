// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import ScriptureText
@testable import ScriptureTextOSIS

// Golden ("approved output") support for the OSIS parser (plan test group 5).
//
// A fixture is a small JSON file of synthetic OSIS entries (invented text only,
// plan D24) plus the option sets to run it under. Each run is rendered to a
// readable, lossless text dump and compared with a saved golden file next to
// the fixture. The dump is for people to review; a separate test proves it
// loses nothing by round-tripping the model through JSON.

struct GoldenFixture: Decodable {
    struct Run: Decodable {
        var name: String
        var headings: Bool?
        var redLetter: Bool?
        var footnotes: Bool?
        var crossReferences: Bool?
        var versePerLine: Bool?
        var strongsMarkers: Bool?
        var morphMarkers: Bool?
        var verseNumbers: Bool?
        var quoteMarks: Bool?
        var variants: String?
        var greekAccents: Bool?
        var hebrewPoints: Bool?
        var hebrewCantillation: Bool?

        var options: OSISParser.Options {
            var o = OSISParser.Options()
            if let headings { o.headings = headings }
            if let redLetter { o.redLetter = redLetter }
            if let footnotes { o.footnotes = footnotes }
            if let crossReferences { o.crossReferences = crossReferences }
            if let versePerLine { o.versePerLine = versePerLine }
            if let strongsMarkers { o.strongsMarkers = strongsMarkers }
            if let morphMarkers { o.morphMarkers = morphMarkers }
            if let verseNumbers { o.verseNumbers = verseNumbers }
            if let quoteMarks { o.quoteMarks = quoteMarks }
            if let greekAccents { o.greekAccents = greekAccents }
            if let hebrewPoints { o.hebrewPoints = hebrewPoints }
            if let hebrewCantillation { o.hebrewCantillation = hebrewCantillation }
            switch variants {
            case "secondary": o.variants = .secondary
            case "all": o.variants = .all
            default: break
            }
            return o
        }
    }

    var description: String
    var profile: String?
    var identity: PassageIdentity?
    var entries: [[JSONValue]]
    var runs: [Run]

    /// `[verse, osis]` pairs.
    var verseEntries: [OSISParser.VerseEntry] {
        entries.compactMap { row in
            guard row.count == 2, case .int(let verse) = row[0], case .string(let osis) = row[1] else { return nil }
            return .init(verse: verse, osis: osis)
        }
    }

    var contentProfile: ScriptureContentProfile {
        switch profile {
        case "dictionary": return .dictionary
        case "commentary": return .commentary
        case "devotional": return .devotional
        case "about": return .about
        default: return .chapter
        }
    }

    func parse(_ run: Run) -> ScriptureText {
        OSISParser(options: run.options, profile: contentProfile).parse(verseEntries, identity: identity)
    }
}

/// Just enough JSON to hold `[Int, String]` rows.
enum JSONValue: Decodable, Equatable {
    case int(Int), string(String)
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { self = .int(i) }
        else { self = .string(try c.decode(String.self)) }
    }
}

enum GoldenFiles {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("Fixtures/OSIS")

    static var recording: Bool { ProcessInfo.processInfo.environment["RECORD_GOLDEN"] == "1" }

    static func fixtureURLs() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".fixture.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func name(of fixture: URL) -> String {
        String(fixture.lastPathComponent.dropLast(".fixture.json".count))
    }

    static func goldenURL(fixture: String, run: String) -> URL {
        directory.appendingPathComponent("\(fixture).\(run).golden.txt")
    }
}

// MARK: - The dump

enum GoldenDump {

    /// Makes invisible and easily-confused characters visible so a reviewer can see them.
    static func visible(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x0A: out += "⏎"
            case 0x09: out += "⇥"
            case 0x2060: out += "‹WJ›"
            case 0x200C: out += "‹ZWNJ›"
            case 0x200D: out += "‹ZWJ›"
            case 0x200E: out += "‹LRM›"
            case 0x200F: out += "‹RLM›"
            case 0x3000: out += "‹IDSP›"
            case 0x00A0: out += "‹NBSP›"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    static func snippet(_ m: ScriptureText, _ start: Int, _ length: Int, limit: Int = 48) -> String {
        guard let s = m.substring(utf16Start: start, length: length) else { return "<out of range>" }
        let v = visible(s)
        return v.count > limit ? String(v.prefix(limit)) + "…" : v
    }

    static func describe(_ a: ScriptureText.Attribute) -> String {
        switch a {
        case .block(let role): return "block(\(role.rawValue))"
        case .verseNumber(let n): return "verseNumber(\(n))"
        case .redLetter: return "redLetter"
        case .small: return "small"
        case .bold: return "bold"
        case .italic: return "italic"
        case .divineName: return "divineName"
        case .strongs(let k): return "strongs(\(k))"
        case .morph(let k): return "morph(\(k))"
        case .word(let lemma, let morph):
            return "word(lemma: \(lemma ?? "nil"), morph: \(morph ?? "nil"))"
        case .footnote(let id): return "footnote(\(id))"
        case .link(let target): return "link(\(target))"
        }
    }

    /// Every field of the model, in a stable order.
    static func render(_ m: ScriptureText) -> String {
        var out: [String] = []
        if let id = m.identity {
            out.append("identity: work=\(id.work) versification=\(id.versification) book=\(id.book) chapter=\(id.chapter.map(String.init) ?? "nil")")
        } else {
            out.append("identity: none")
        }
        out.append("text: \(m.text.utf16.count) UTF-16 units")
        out.append("  " + visible(m.text))
        out.append("verses: \(m.verses.count)")
        for v in m.verses {
            out.append("  \(v.verse)  \(v.start)+\(v.length)  [\(snippet(m, v.start, v.length))]")
        }
        out.append("spans: \(m.spans.count)")
        for s in m.spans {
            out.append("  \(s.start)+\(s.length)  \(describe(s.attribute))  [\(snippet(m, s.start, s.length))]")
        }
        out.append("words: \(m.words.count)")
        for w in m.words {
            out.append("  \(w.verse).\(w.index)  \(w.start)+\(w.length)  \(snippet(m, w.start, w.length))")
        }
        out.append("notes: \(m.notes.count)")
        for n in m.notes {
            out.append("  \(n.id)  \(n.kind.rawValue)  \"\(visible(n.text))\"  refs=\(n.references)")
        }
        return out.joined(separator: "\n") + "\n"
    }
}
