// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Reads the files of a SWORD module straight from disk, so the package's tests can run real module data
// without SWORD, on any platform (plan D74). Test support only: it reads the two layouts the committed test
// modules use, zText (compressed Bibles) and RawCom (plain commentaries), for modules on the KJV
// versification. It is a reader for tests, not a product.
//
//   zText   <t>.bzv  10-byte records: uint32 block, uint32 offset, uint16 size (little endian)
//           <t>.bzs  12-byte records: uint32 offset, uint32 compressed size, uint32 size, per block of <t>.bzz
//           <t>.bzz  the blocks, each a zlib stream
//   RawCom  <t>.vss  6-byte records: uint32 offset, uint16 size, into the file <t>
//
// <t> is "ot" or "nt". Each testament file holds, in order: one spare entry, the testament heading, then for
// each book its heading and for each chapter its heading followed by the chapter's verses.

import Foundation
import ScriptureText

public struct ModuleFiles {

    public enum Testament: String, CaseIterable, Sendable {
        case old = "ot"
        case new = "nt"
    }

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
        init(_ description: String) { self.description = description }
    }

    /// One chapter as the app's reader sees it: entry 0 is the chapter heading, then verses 1…n.
    public struct Chapter: Sendable {
        public let book: KJVBook
        public let number: Int
        public let entries: [ChapterEntries.Entry]
    }

    public let directory: URL
    public let name: String
    /// The first value of each key in the module's conf.
    public let conf: [String: String]

    public var driver: String { conf["ModDrv"] ?? "" }
    public var sourceType: ScriptureSourceType { ScriptureSourceType.from(conf: conf["SourceType"]) }

    /// - Parameter directory: a folder holding `mods.d/<module>.conf` and `modules/…`.
    public init(directory: URL) throws {
        self.directory = directory
        let modsD = directory.appendingPathComponent("mods.d")
        let confs = try FileManager.default.contentsOfDirectory(at: modsD, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "conf" }
        guard let confURL = confs.first, confs.count == 1 else { throw Failure("expected one .conf in \(modsD.path)") }
        let text = String(decoding: try Data(contentsOf: confURL), as: UTF8.self)
        var conf: [String: String] = [:]
        var section = ""
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("[") { section = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] \r")); continue }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if conf[key] == nil { conf[key] = value }
        }
        self.name = section
        self.conf = conf
    }

    /// The facts the module source needs, from the conf.
    public var facts: ScriptureModuleFacts {
        ScriptureModuleFacts(name: name, sourceType: sourceType, versification: conf["Versification"] ?? "KJV",
                             osisQToTick: conf["OSISqToTick"] != "false")
    }

    // MARK: Entries

    private var dataFolder: URL {
        var path = conf["DataPath"] ?? ""
        if path.hasPrefix("./") { path.removeFirst(2) }
        return directory.appendingPathComponent(path, isDirectory: true)
    }

    /// Every entry of one testament file in file order, the empty ones as "". Empty when the module has no such testament.
    public func entries(_ testament: Testament) throws -> [String] {
        let base = dataFolder.appendingPathComponent(testament.rawValue)
        switch driver {
        case "zText": return try zTextEntries(base)
        case "RawCom": return try rawComEntries(base)
        default: throw Failure("unsupported driver \(driver)")
        }
    }

    private func zTextEntries(_ base: URL) throws -> [String] {
        let fm = FileManager.default
        let paths = ["bzv", "bzs", "bzz"].map { base.appendingPathExtension($0) }
        guard paths.allSatisfy({ fm.fileExists(atPath: $0.path) }) else { return [] }
        let index = try Data(contentsOf: paths[0]), blocksIndex = try Data(contentsOf: paths[1]), compressed = try Data(contentsOf: paths[2])
        var cache: [Int: Data] = [:]
        var result: [String] = []
        for i in 0..<(index.count / 10) {
            let block = Int(index.uint32(at: i * 10)), offset = Int(index.uint32(at: i * 10 + 4)), size = Int(index.uint16(at: i * 10 + 8))
            if size == 0 { result.append(""); continue }
            if cache[block] == nil {
                let start = Int(blocksIndex.uint32(at: block * 12)), length = Int(blocksIndex.uint32(at: block * 12 + 4))
                cache[block] = try Inflate.zlib(compressed.subdata(in: start..<(start + length)))
            }
            let data = cache[block]!
            guard offset + size <= data.count else { throw Failure("entry \(i) runs past its block") }
            result.append(Self.decode(data.subdata(in: offset..<(offset + size))))
        }
        return result
    }

    private func rawComEntries(_ base: URL) throws -> [String] {
        let index = base.appendingPathExtension("vss")
        guard FileManager.default.fileExists(atPath: index.path) else { return [] }
        let vss = try Data(contentsOf: index), data = try Data(contentsOf: base)
        var result: [String] = []
        for i in 0..<(vss.count / 6) {
            let offset = Int(vss.uint32(at: i * 6)), size = Int(vss.uint16(at: i * 6 + 4))
            guard size > 0, offset + size <= data.count else { result.append(""); continue }
            result.append(Self.decode(data.subdata(in: offset..<(offset + size))))
        }
        return result
    }

    private static func decode(_ data: Data) -> String {
        var bytes = data
        while bytes.last == 0 { bytes.removeLast() }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: Chapters

    /// Every chapter of the module, in canon order, from the entries and the KJV versification. A testament the
    /// module lacks gives none.
    public func chapters() throws -> [Chapter] {
        var result: [Chapter] = []
        for (testament, books) in [(Testament.old, KJVVersification.oldTestament), (Testament.new, KJVVersification.newTestament)] {
            let all = try entries(testament)
            guard !all.isEmpty else { continue }
            var index = 1                                   // the spare entry is 0; the testament heading is 1
            for book in books {
                index += 1                                  // the book heading
                for (chapterIndex, verseCount) in book.verses.enumerated() {
                    index += 1                              // the chapter heading
                    guard index + verseCount < all.count else { throw Failure("\(name) ends inside \(book.name)") }
                    var entries = [ChapterEntries.Entry(verse: 0, text: all[index])]
                    for verse in 1...verseCount { entries.append(.init(verse: verse, text: all[index + verse])) }
                    result.append(Chapter(book: book, number: chapterIndex + 1, entries: entries))
                    index += verseCount
                }
            }
        }
        return result
    }

    public func chapter(book osisOrName: String, _ number: Int) throws -> Chapter? {
        try chapters().first {
            $0.number == number && ($0.book.osis.caseInsensitiveCompare(osisOrName) == .orderedSame
                                    || $0.book.name.caseInsensitiveCompare(osisOrName) == .orderedSame)
        }
    }
}

private extension Data {
    func uint16(at i: Int) -> UInt16 { UInt16(self[startIndex + i]) | UInt16(self[startIndex + i + 1]) << 8 }
    func uint32(at i: Int) -> UInt32 {
        UInt32(self[startIndex + i]) | UInt32(self[startIndex + i + 1]) << 8
            | UInt32(self[startIndex + i + 2]) << 16 | UInt32(self[startIndex + i + 3]) << 24
    }
}
