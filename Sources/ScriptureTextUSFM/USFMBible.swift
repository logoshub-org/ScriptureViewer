// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// A USFM Bible: a folder of book files (plan D48, Track V5), as eBible.org and Paratext publish them
// (`02-GENeng-kjv2006.usfm`, `01GENBSB.SFM`, `GEN.usfm`). USFM defines one book per file and no manifest, so the folder
// is the Bible:
//
//  • its books are its files, each known by its `\id` code, whatever the file is called; files that are not a Bible
//    book (front matter `FRT`, introductions `INT`, glossaries, codes Paratext does not number) are left out;
//  • their order is Paratext's book numbering (`ParatextBook.all`), which eBible's file names follow;
//  • their chapters and verses are what the files hold (each book is indexed once, when the Bible is opened);
//  • the versification is the one the folder declares (a Paratext `Settings.xml` `<Versification>` of 1–6, or a `.vrs`
//    file beside the books), else the Paratext system the text fits best: the fewest verses the system does not
//    have, then the fewest it has that the text lacks; English when they tie (the idea is Haiola's, reimplemented).
//    The best fit is only a guess for a text that follows no system exactly: eBible's Majority Text NT (EMTV) fits
//    Russian Protestant, which also puts the doxology at Romans 14:24–26; its LXX2012 fits none well. A host that
//    knows better passes the versification;
//  • book names are SWORD's English names (`ParatextBook`), as the app's references use; each book's own titles
//    (`\toc1`–`\toc3`, `\h`) are kept on `BookFile`.

import Foundation
import ScriptureText
import ScriptureTextVersification

public final class USFMBible: ScriptureBible, @unchecked Sendable {

    public struct BookFile: Sendable {
        /// The USFM code ("GEN") and the OSIS id ("Gen").
        public let code: String
        public let osisID: String
        /// The name the app shows ("Genesis"), and the book's own titles.
        public let name: String
        public let shortName: String?
        public let longName: String?
        public let abbreviation: String?
        public let url: URL
        public let chapters: [Int]
        /// Each chapter's highest verse number.
        public let lastVerses: [Int: Int]
    }

    /// Where the versification came from.
    public enum VersificationSource: Equatable, Sendable {
        /// A Paratext `Settings.xml`.
        case settings
        /// A `.vrs` file in the folder, by name.
        case vrsFile(String)
        /// None was declared: the Paratext system the text fits best.
        case bestFit
        /// The host passed it.
        case host
    }

    public enum OpenError: Error, Equatable {
        case noBooks
    }

    public let name: String
    public let folder: URL
    public let books: [BookFile]
    public let versification: Versification
    public let versificationSource: VersificationSource

    private let lock = NSLock()
    private var opened: [(osisID: String, book: USFMBook)] = []    // the last few books read, most recent last
    private var featuresFound: Features?

    /// The Bible in `folder`; `name` defaults to the folder's name without a trailing `_usfm` (eBible's downloads).
    /// `versification`, when given, is used instead of what the folder declares or the best fit.
    public init(folder: URL, name: String? = nil, versification declared: Versification? = nil) throws {
        self.folder = folder
        let folderName = folder.lastPathComponent
        self.name = name ?? (folderName.lowercased().hasSuffix("_usfm") ? String(folderName.dropLast(5)) : folderName)

        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        var found: [BookFile] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where ["usfm", "sfm"].contains(file.pathExtension.lowercased()) {
            guard let text = try? String(contentsOf: file, encoding: .utf8), let book = USFMBook(text),
                  let known = ParatextBook.book(code: book.code), !found.contains(where: { $0.code == book.code }) else { continue }
            found.append(BookFile(code: book.code, osisID: known.osisID, name: known.name,
                                  shortName: book.shortName, longName: book.longName, abbreviation: book.abbreviation,
                                  url: file, chapters: book.chapters, lastVerses: book.lastVerses))
        }
        guard !found.isEmpty else { throw OpenError.noBooks }
        let order = Dictionary(uniqueKeysWithValues: ParatextBook.all.enumerated().map { ($0.element.code, $0.offset) })
        found.sort { (order[$0.code] ?? Int.max, $0.code) < (order[$1.code] ?? Int.max, $1.code) }
        books = found

        let (system, source) = declared.map { ($0, VersificationSource.host) }
            ?? Self.declaredSystem(in: folder, files: files) ?? (Self.bestFit(found), .bestFit)
        versificationSource = source
        versification = Versification(
            name: system.name,
            books: found.map { book in
                let last = book.chapters.max() ?? 0
                return Versification.Book(name: book.name, osisID: book.osisID,
                                          versesPerChapter: (0..<last).map { book.lastVerses[$0 + 1] ?? 0 },
                                          testament: ParatextBook.book(code: book.code)?.testament ?? .old)
            },
            mappings: system.mappings, excludedVerses: system.excludedVerses)
    }

    // MARK: Features

    /// What the Bible's text carries, so a host can offer only the display options that do something (a Bible with no
    /// Strong's numbers has no Strong's switch).
    public struct Features: Equatable, Sendable {
        public var headings = false
        public var footnotes = false
        public var crossReferences = false
        public var redLetter = false
        public var strongs = false
        public var morphology = false

        var complete: Bool { headings && footnotes && crossReferences && redLetter && strongs && morphology }

        mutating func scan(_ text: String) {
            func has(_ needle: String) -> Bool { text.range(of: needle) != nil }
            if !headings { headings = ["\\s ", "\\s1", "\\s2", "\\ms", "\\mr ", "\\r "].contains(where: has) }
            if !footnotes { footnotes = ["\\f ", "\\fe ", "\\ef "].contains(where: has) }
            if !crossReferences { crossReferences = ["\\x ", "\\ex "].contains(where: has) }
            if !redLetter { redLetter = has("\\wj ") || has("who=\"Jesus\"") }
            if !strongs { strongs = has("strong=\"") }
            if !morphology { morphology = has("x-morph=\"") || has("morph=\"") }
        }
    }

    /// The features of the books' text, found by reading the files once (the result is kept).
    public func features() -> Features {
        lock.lock()
        defer { lock.unlock() }
        if let found = featuresFound { return found }
        var features = Features()
        for file in books {
            guard let text = try? String(contentsOf: file.url, encoding: .utf8) else { continue }
            features.scan(text)
            if features.complete { break }
        }
        featuresFound = features
        return features
    }

    // MARK: Chapters

    public func chapter(book osisID: String, chapter: Int, display: ScriptureDisplayOptions) -> ScriptureText? {
        self.chapter(book: osisID, chapter: chapter, options: USFMParser.Options(display: display))
    }

    /// One chapter with parser options of the caller's choosing.
    public func chapter(book osisID: String, chapter: Int, options: USFMParser.Options) -> ScriptureText? {
        guard let book = book(osisID) else { return nil }
        let identity = PassageIdentity(work: name, versification: versification.name, book: osisID, chapter: chapter)
        return USFMParser(options: options).parse(book, chapter: chapter, identity: identity)
    }

    /// A book's file, read and indexed; the last few are kept.
    public func book(_ osisID: String) -> USFMBook? {
        lock.lock()
        defer { lock.unlock() }
        if let index = opened.firstIndex(where: { $0.osisID == osisID }) {
            let entry = opened.remove(at: index)
            opened.append(entry)
            return entry.book
        }
        guard let file = books.first(where: { $0.osisID == osisID }),
              let text = try? String(contentsOf: file.url, encoding: .utf8), let book = USFMBook(text) else { return nil }
        opened.append((osisID, book))
        if opened.count > 3 { opened.removeFirst() }
        return book
    }

    // MARK: Versification

    /// A Paratext `Settings.xml` `<Versification>`, or a `.vrs` file, in the folder.
    private static func declaredSystem(in folder: URL, files: [URL]) -> (Versification, VersificationSource)? {
        if let vrs = files.first(where: { $0.pathExtension.lowercased() == "vrs" }),
           let text = try? String(contentsOf: vrs, encoding: .utf8) {
            let read = VRSReader.versification(from: text)
            if !read.books.isEmpty { return (read, .vrsFile(vrs.lastPathComponent)) }
        }
        if let settings = files.first(where: { $0.lastPathComponent.lowercased() == "settings.xml" }),
           let text = try? String(contentsOf: settings, encoding: .utf8),
           let open = text.range(of: "<Versification>"), let close = text.range(of: "</Versification>", range: open.upperBound..<text.endIndex),
           let number = Int(text[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)),
           (1...6).contains(number) {
            return (Versification.paratextSystems[number - 1], .settings)
        }
        return nil
    }

    /// The Paratext system the books fit best: the fewest verses the system does not have (a whole book it lacks
    /// counts every verse), then the fewest verses the system has that the books lack. English first, so it wins ties.
    static func bestFit(_ books: [BookFile]) -> Versification {
        let candidates: [Versification] = [.english, .original, .septuagint, .vulgate, .russianProtestant, .russianOrthodox]
        var best = candidates[0]
        var bestScore = (Int.max, Int.max)
        for system in candidates {
            var extra = 0, missing = 0
            for book in books {
                guard let index = system.bookIndex(named: book.osisID) else {
                    extra += book.lastVerses.values.reduce(0, +)
                    continue
                }
                let shape = system.books[index]
                for chapter in book.chapters {
                    let text = book.lastVerses[chapter] ?? 0
                    let expected = shape.verseCount(ofChapter: chapter)
                    extra += max(text - expected, 0)
                    missing += max(expected - text, 0)
                }
            }
            if (extra, missing) < bestScore {
                bestScore = (extra, missing)
                best = system
            }
        }
        return best
    }
}
