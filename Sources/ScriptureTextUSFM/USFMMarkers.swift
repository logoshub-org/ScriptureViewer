// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// What each USFM 3 marker is (plan D88, Track V4). The grouping (identification, headings, verse-bearing paragraphs,
// character styles, notes and their parts, milestones, alternate numbers) follows usfm3's `data/markers.toml`
// (James Cuénod, MIT; credited in NOTICE); what each group becomes in a ScriptureText is ours. Numbered markers
// (`\q2`, `\s3`, `\li1`, `\imt2`) are looked up by their base name with the number as a level.

import ScriptureText

enum USFMMarker: Equatable {
    /// Book metadata (`\id`, `\h`, `\toc1`, `\rem` …): its text runs to the next marker and is not shown.
    case identification
    case chapter
    case verse
    /// A heading paragraph with its role; `canonical` for Bible text (a Psalm title).
    case heading(ParagraphRole, canonical: Bool)
    /// A paragraph of text: prose (no role), poetry, a list item, an introduction paragraph.
    case paragraph(ParagraphRole?)
    /// `\nb`: the paragraph goes on without a break.
    case noBreak
    /// `\b`: a blank line.
    case blankLine
    /// A character style: its attribute, or nil for one shown as plain text.
    case character(CharacterStyle)
    /// A note: a footnote (`\f`, `\fe`, `\ef`) or a cross-reference (`\x`, `\ex`).
    case note(crossReference: Bool)
    /// A part of a note; `dropped` for the origin reference (`\fr`, `\xo`), which the reader does not need.
    case notePart(dropped: Bool)
    /// `\va`, `\ca`: an alternate number, not shown yet. `\vp`: a verse's printed number. `\cp`: a chapter's.
    case alternateVerse, alternateChapter, publishedVerse, publishedChapter
    /// A figure (`\fig …\fig*`), a category (`\cat`): not shown.
    case hiddenCharacter
    /// A milestone (`\qt-s |who="Jesus"\*`, `\ts\*`): its attributes run to `\*`.
    case milestone
    /// A sidebar (`\esb … \esbe`): not shown.
    case sidebarStart, sidebarEnd

    enum CharacterStyle: Equatable {
        case plain, italic, bold, small, divineName, redLetter
        /// `\w`: a word with lexical attributes.
        case word
        /// `\ref`, `\jmp`: a link to the `loc` or `link-href` attribute, or to the text.
        case link
    }

    /// The marker for a name without its backslash, `+` or `*` (`q2`, `w`, `zaln-s`). Unknown markers are character
    /// styles shown as plain text, so their text is kept.
    static func named(_ name: String) -> USFMMarker {
        if name.hasSuffix("-s") || name.hasSuffix("-e") || name == "ts" || name == "zms" { return .milestone }
        let base = String(name.prefix { !$0.isNumber })
        let level = Int(name.dropFirst(base.count)) ?? 1
        switch base {
        case "id", "usfm", "ide", "sts", "rem", "h", "toc", "toca", "periph": return .identification
        case "c": return .chapter
        case "v": return .verse

        case "mt", "mte", "imt", "imte": return .heading(.mt, canonical: false)
        case "ms": return .heading(.ms, canonical: false)
        case "mr", "sr", "imr": return .heading(.mr, canonical: false)
        case "s", "is": return .heading(level <= 1 ? .s1 : .s2, canonical: false)
        case "iot": return .heading(.s1, canonical: false)
        case "r": return .heading(.r, canonical: false)
        case "sp": return .heading(.sp, canonical: true)
        case "d": return .heading(.d, canonical: true)
        case "qa": return .heading(.qa, canonical: false)
        case "cl": return .heading(.cl, canonical: false)
        case "cd": return .heading(.s2, canonical: false)
        case "sd": return .paragraph(nil)

        case "p", "m", "po", "pr", "cls", "pmo", "pm", "pmc", "pmr", "pi", "mi", "pc", "ph", "lit", "tr", "pb":
            return .paragraph(nil)
        case "nb": return .noBreak
        case "b", "ib": return .blankLine
        case "q", "qm", "qc", "qd": return .paragraph(.poetry(level: level))
        case "qr": return .paragraph(.qr)
        case "li", "lim", "lh", "lf", "ili": return .paragraph(.listItem(depth: level))
        case "ip", "ipi", "im", "imi", "ipq", "imq", "ipr", "iq", "ie", "iex": return .paragraph(.ip)
        case "io": return .paragraph(.io)

        case "add", "tl", "it", "em", "bk", "sig", "qs": return .character(.italic)
        case "bd", "bdit": return .character(.bold)
        case "sc": return .character(.small)
        case "nd": return .character(.divineName)
        case "wj": return .character(.redLetter)
        case "w", "wa", "wg", "wh": return .character(.word)
        case "ref", "jmp": return .character(.link)
        case "fig", "cat": return .hiddenCharacter

        case "f", "fe", "ef": return .note(crossReference: false)
        case "x", "ex": return .note(crossReference: true)
        case "fr", "xo": return .notePart(dropped: true)
        case "fk", "fq", "fqa", "fl", "fw", "fp", "ft", "fdc", "fm", "xk", "xq", "xt", "xta", "xop", "xot", "xnt", "xdc":
            return .notePart(dropped: false)

        case "va": return .alternateVerse
        case "ca": return .alternateChapter
        case "vp": return .publishedVerse
        case "cp": return .publishedChapter
        case "esb": return .sidebarStart
        case "esbe": return .sidebarEnd

        default: return .character(.plain)
        }
    }
}
