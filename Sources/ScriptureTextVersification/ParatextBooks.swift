// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// The books USFM and Paratext name by three-letter code (`\id GEN`), with the OSIS id the package uses everywhere else
// and an English name. The order is Paratext's book numbering, which is also how USFM Bibles number their files
// (`02-GEN…`, `70-MAT…`) and the default order of a USFM Bible's books.
//
// Names and OSIS ids are SWORD's (its `canon*.h`) where SWORD has the book, so a USFM Bible and a SWORD module name a
// book alike. The Paratext-only books (JSA … BLT, EZA, 5EZ, 6EZ, DAG, JUB) have no SWORD id; their ids follow OSIS's
// naming style and their names are Paratext's.

import ScriptureText

/// A book by its USFM code.
public struct ParatextBook: Equatable, Sendable {
    /// The three-letter code ("GEN", "1SA").
    public let code: String
    public let osisID: String
    public let name: String
    public let testament: Versification.Testament

    /// The books in Paratext's order: the 66, then the deuterocanon and the other books the standard versifications use.
    public static let all: [ParatextBook] = [
        old("GEN", "Gen", "Genesis"), old("EXO", "Exod", "Exodus"), old("LEV", "Lev", "Leviticus"),
        old("NUM", "Num", "Numbers"), old("DEU", "Deut", "Deuteronomy"), old("JOS", "Josh", "Joshua"),
        old("JDG", "Judg", "Judges"), old("RUT", "Ruth", "Ruth"), old("1SA", "1Sam", "I Samuel"),
        old("2SA", "2Sam", "II Samuel"), old("1KI", "1Kgs", "I Kings"), old("2KI", "2Kgs", "II Kings"),
        old("1CH", "1Chr", "I Chronicles"), old("2CH", "2Chr", "II Chronicles"), old("EZR", "Ezra", "Ezra"),
        old("NEH", "Neh", "Nehemiah"), old("EST", "Esth", "Esther"), old("JOB", "Job", "Job"),
        old("PSA", "Ps", "Psalms"), old("PRO", "Prov", "Proverbs"), old("ECC", "Eccl", "Ecclesiastes"),
        old("SNG", "Song", "Song of Solomon"), old("ISA", "Isa", "Isaiah"), old("JER", "Jer", "Jeremiah"),
        old("LAM", "Lam", "Lamentations"), old("EZK", "Ezek", "Ezekiel"), old("DAN", "Dan", "Daniel"),
        old("HOS", "Hos", "Hosea"), old("JOL", "Joel", "Joel"), old("AMO", "Amos", "Amos"),
        old("OBA", "Obad", "Obadiah"), old("JON", "Jonah", "Jonah"), old("MIC", "Mic", "Micah"),
        old("NAM", "Nah", "Nahum"), old("HAB", "Hab", "Habakkuk"), old("ZEP", "Zeph", "Zephaniah"),
        old("HAG", "Hag", "Haggai"), old("ZEC", "Zech", "Zechariah"), old("MAL", "Mal", "Malachi"),
        new("MAT", "Matt", "Matthew"), new("MRK", "Mark", "Mark"), new("LUK", "Luke", "Luke"),
        new("JHN", "John", "John"), new("ACT", "Acts", "Acts"), new("ROM", "Rom", "Romans"),
        new("1CO", "1Cor", "I Corinthians"), new("2CO", "2Cor", "II Corinthians"), new("GAL", "Gal", "Galatians"),
        new("EPH", "Eph", "Ephesians"), new("PHP", "Phil", "Philippians"), new("COL", "Col", "Colossians"),
        new("1TH", "1Thess", "I Thessalonians"), new("2TH", "2Thess", "II Thessalonians"),
        new("1TI", "1Tim", "I Timothy"), new("2TI", "2Tim", "II Timothy"), new("TIT", "Titus", "Titus"),
        new("PHM", "Phlm", "Philemon"), new("HEB", "Heb", "Hebrews"), new("JAS", "Jas", "James"),
        new("1PE", "1Pet", "I Peter"), new("2PE", "2Pet", "II Peter"), new("1JN", "1John", "I John"),
        new("2JN", "2John", "II John"), new("3JN", "3John", "III John"), new("JUD", "Jude", "Jude"),
        new("REV", "Rev", "Revelation of John"),
        old("TOB", "Tob", "Tobit"), old("JDT", "Jdt", "Judith"), old("ESG", "EsthGr", "Esther (Greek)"),
        old("WIS", "Wis", "Wisdom"), old("SIR", "Sir", "Sirach"), old("BAR", "Bar", "Baruch"),
        old("LJE", "EpJer", "Epistle of Jeremiah"), old("S3Y", "PrAzar", "Prayer of Azariah"),
        old("SUS", "Sus", "Susanna"), old("BEL", "Bel", "Bel and the Dragon"), old("1MA", "1Macc", "I Maccabees"),
        old("2MA", "2Macc", "II Maccabees"), old("3MA", "3Macc", "III Maccabees"), old("4MA", "4Macc", "IV Maccabees"),
        old("1ES", "1Esd", "I Esdras"), old("2ES", "2Esd", "II Esdras"), old("MAN", "PrMan", "Prayer of Manasses"),
        old("PS2", "AddPs", "Additional Psalm"), old("ODA", "Odes", "Odes"), old("PSS", "PssSol", "Psalms of Solomon"),
        old("JSA", "JoshA", "Joshua A"), old("JDB", "JudgB", "Judges B"), old("TBS", "TobS", "Tobit S"),
        old("SST", "SusTh", "Susanna (Theodotion)"), old("DNT", "DanTh", "Daniel (Theodotion)"),
        old("BLT", "BelTh", "Bel (Theodotion)"), old("EZA", "4Ezra", "Apocalypse of Ezra"),
        old("5EZ", "5Ezra", "5 Ezra"), old("6EZ", "6Ezra", "6 Ezra"), old("DAG", "DanGr", "Daniel (Greek)"),
        old("JUB", "Jub", "Jubilees"), old("ENO", "1En", "I Enoch"), new("LAO", "EpLao", "Laodiceans"),
    ]

    // Built with a loop, not `Dictionary(uniqueKeysWithValues:)` over pairs: the transpiler takes no tuples in arrays.
    private static let byCode: [String: ParatextBook] = {
        var books: [String: ParatextBook] = [:]
        for book in all { books[book.code] = book }
        return books
    }()
    private static let byOSIS: [String: ParatextBook] = {
        var books: [String: ParatextBook] = [:]
        for book in all { books[book.osisID] = book }
        return books
    }()

    /// The book with this USFM code, in any case.
    public static func book(code: String) -> ParatextBook? { byCode[code.uppercased()] }

    /// The book with this OSIS id.
    public static func book(osisID: String) -> ParatextBook? { byOSIS[osisID] }

    private static func old(_ code: String, _ osis: String, _ name: String) -> ParatextBook {
        ParatextBook(code: code, osisID: osis, name: name, testament: Versification.Testament.old)
    }

    private static func new(_ code: String, _ osis: String, _ name: String) -> ParatextBook {
        ParatextBook(code: code, osisID: osis, name: name, testament: Versification.Testament.new)
    }
}
