// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// Per-screen parsing rules. One parser serves every SWORD source; the profile
/// says what the content is, so chapter-only behaviour (verse ranges) does not
/// leak into entries that have no verses.
public enum ScriptureContentProfile: Sendable {
    case chapter      // Bible
    case commentary
    case dictionary
    case devotional
    case about        // module "about" / info pages; author-supplied, varies widely

    /// Only Bible chapters and commentary entries carry verse markers.
    public var buildsVerseRanges: Bool {
        switch self {
        case .chapter, .commentary: return true
        case .dictionary, .devotional, .about: return false
        }
    }
}
