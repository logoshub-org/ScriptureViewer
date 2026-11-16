// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import ScriptureText

extension ScriptureText {

    /// Structural invariants every parse must satisfy: spans and verse ranges inside the text, verse ranges in
    /// order, word anchors in order, non-empty and sequential within a verse.
    public var isStructurallyConsistent: Bool {
        let total = text.utf16.count
        for s in spans where s.start < 0 || s.length <= 0 || s.start + s.length > total { return false }
        var previousEnd = 0
        for v in verses {
            if v.start < previousEnd || v.length < 0 || v.start + v.length > total { return false }
            previousEnd = v.start + v.length
        }
        var wordEnd = 0
        var next: [Int: Int] = [:]
        for w in words {
            if w.start < wordEnd || w.length <= 0 || w.start + w.length > total { return false }
            if w.index < next[w.verse, default: 0] { return false }
            next[w.verse] = w.index + 1
            wordEnd = w.start + w.length
        }
        return true
    }
}
