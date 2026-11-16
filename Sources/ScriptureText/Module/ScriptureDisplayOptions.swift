// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// The display options of a module as one value: the choices a reader makes about what to show (Strong's
/// numbers, notes, headings, red letter and so on). Where a host keeps them is its own business; the
/// parsers see them through `ScriptureModuleSource.parserOptions`.
public struct ScriptureDisplayOptions: Equatable, Sendable {
    public var strongs = false
    public var morph = false
    public var crossReferences = false
    public var footnotes = false
    public var headings = false
    public var redLetter = false
    public var versePerLine = false
    public var greekAccents = false
    public var hebrewPoints = false
    public var hebrewCantillation = false
    public var glosses = false

    public init() {}
}
