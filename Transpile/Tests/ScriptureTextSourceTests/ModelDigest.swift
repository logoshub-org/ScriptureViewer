// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import ScriptureText

/// Everything about a model as lines of text, for the parity tests: the same lines from Swift and from Kotlin mean the same model.
enum ModelDigest {

    static func describe(_ attribute: ScriptureText.Attribute) -> String {
        switch attribute {
        case .block(let role): return "block:" + role.rawValue
        case .verseNumber(let number): return "verseNumber:" + String(number)
        case .redLetter: return "redLetter"
        case .small: return "small"
        case .bold: return "bold"
        case .italic: return "italic"
        case .strongs(let token): return "strongs:" + token
        case .morph(let code): return "morph:" + code
        case .word(let lemma, let morph): return "word:" + (lemma ?? "-") + ":" + (morph ?? "-")
        case .footnote(let id): return "footnote:" + id
        case .link(let target): return "link:" + target
        case .divineName: return "divineName"
        }
    }

    /// Everything about a model, as lines, under a label.
    static func of(_ label: String, _ model: ScriptureText) -> String {
        var out = "# " + label + "\n"
        out += "utf16=" + String(CodePoints.utf16Length(model.text)) + " verses=" + String(model.verses.count)
        out += " spans=" + String(model.spans.count) + " words=" + String(model.words.count) + " notes=" + String(model.notes.count) + "\n"
        for v in model.verses {
            out += "V " + String(v.verse) + " " + String(v.start) + " " + String(v.length) + " " + v.displayNumber + "\n"
        }
        for s in model.spans { out += "S " + describe(s.attribute) + " " + String(s.start) + " " + String(s.length) + "\n" }
        for w in model.words { out += "W " + String(w.verse) + " " + String(w.index) + " " + String(w.start) + " " + String(w.length) + "\n" }
        for n in model.notes {
            out += "N " + n.id + " " + n.kind.rawValue + " [" + n.references.joined(separator: "|") + "] " + n.text + "\n"
        }
        out += "T " + model.text + "\n"
        return out
    }
}
