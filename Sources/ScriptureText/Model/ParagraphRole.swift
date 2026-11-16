// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// What a paragraph *is*, named after the USFM paragraph markers (plan D36),
/// so each platform's styler can be a table and any source format can map
/// onto one vocabulary. Ordinary prose paragraphs have no role (no span).
/// The raw values are the USFM marker names and are stable for storage.
public enum ParagraphRole: String, Equatable, Sendable, Codable, CaseIterable {
    /// Book title (OSIS `<title type="main">`).
    case mt
    /// Chapter label (`<title type="chapter">`).
    case cl
    /// Major section heading (a title in a `majorSection` div).
    case ms
    /// Major section reference range (`<title type="scope">`).
    case mr
    /// Section heading.
    case s1
    /// Subsection heading (a title in a `subSection` div).
    case s2
    /// Parallel passage references (`<title type="parallel">`).
    case r
    /// Descriptive title, e.g. a Psalm superscription (`<title type="psalm">`).
    /// Canonical text.
    case d
    /// Acrostic heading, e.g. the Hebrew letters in Psalm 119.
    case qa
    /// Speaker identification (`<speaker>`).
    case sp
    /// Poetry lines by indent level (`<l level="1…4">`).
    case q1, q2, q3, q4
    /// A right-aligned poetic aside: Selah (`<l type="selah">`).
    case qr
    /// List items by nesting depth (`<item>`).
    case li1, li2
    /// Introduction paragraph (`<div type="introduction">`).
    case ip
    /// Outline entry (`<div type="outline">`).
    case io

    /// Bible text, as opposed to editorial additions. Only canonical text has
    /// word anchors and can be highlighted or selected for copying (D35, D38).
    public var isCanonical: Bool {
        switch self {
        case .d, .q1, .q2, .q3, .q4, .qr, .li1, .li2: return true
        case .mt, .cl, .ms, .mr, .s1, .s2, .r, .qa, .sp, .ip, .io: return false
        }
    }

    /// A title-like role: set apart from the text around it, and never the
    /// place for a verse-number marker.
    public var isHeading: Bool {
        switch self {
        case .mt, .cl, .ms, .mr, .s1, .s2, .r, .d, .qa, .sp: return true
        case .q1, .q2, .q3, .q4, .qr, .li1, .li2, .ip, .io: return false
        }
    }

    /// The poetry role for an OSIS `level` (missing or out of range clamps).
    public static func poetry(level: Int) -> ParagraphRole {
        switch level {
        case ...1: return .q1
        case 2: return .q2
        case 3: return .q3
        default: return .q4
        }
    }

    /// The list-item role for a nesting depth (1 = outermost list).
    public static func listItem(depth: Int) -> ParagraphRole {
        depth <= 1 ? .li1 : .li2
    }
}
