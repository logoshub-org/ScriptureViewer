// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// A Bible as the viewer sees it, whatever stores it (plan Track V6): a SWORD module, through the app's adapter, or a
// folder of USFM book files (`USFMBible`). The viewer asks for chapters by OSIS book id and number, and lays out its
// book navigator from the versification; it never learns where the text came from.

/// A Bible the viewer can read.
public protocol ScriptureBible {
    /// The name the host knows it by: a SWORD module's name, a USFM Bible's folder name.
    var name: String { get }
    /// Its books in order, with their chapters and verses, and its versification system's name and mappings.
    var versification: Versification { get }
    /// One chapter, parsed with the reader's options and carrying its `PassageIdentity`; nil when the Bible does not
    /// have it.
    func chapter(book osisID: String, chapter: Int, display: ScriptureDisplayOptions) -> ScriptureText?
}

extension ScriptureBible {
    /// Whether the Bible has this book.
    public func hasBook(_ osisID: String) -> Bool {
        versification.books.contains { $0.osisID == osisID }
    }
}
