// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// When scrolling should hide the host's bar (the app's icon bar) and when it should bring it back (plan D107): down hides it, up shows it,
/// each after a few dozen points so a wobble does nothing, and the top of the text always shows it; a push past the end of the text
/// (or on a text too short to scroll) shows or hides it (`pushedPastEnd`, 0.2.8). A plain value
/// so the rule is tested without a scroll view, and so each platform's viewer applies the same one (plan D165).
public struct ScriptureBarScrollRule: Equatable {
    /// How far the text must move one way, in points, before the bar follows.
    public var threshold: Double = 40
    public private(set) var hidden = false
    private var anchor: Double = 0

    /// Feeds one scroll position (`offset` from the top of the text, `maxOffset` the furthest the text scrolls). Returns the
    /// new state when it changed, or nil.
    public mutating func update(offset: Double, maxOffset: Double) -> Bool? {
        let before = hidden
        if offset <= 1 || maxOffset <= 0 {
            hidden = false
            anchor = offset
        } else if !hidden {
            anchor = min(anchor, offset)
            if offset - anchor > threshold { hidden = true; anchor = offset }
        } else {
            anchor = max(anchor, offset)
            if anchor - offset > threshold { hidden = false; anchor = offset }
        }
        return hidden == before ? nil : hidden
    }

    /// How far past the end of the text, in points, a push must take it before the bar is shown or hidden.
    public static let pushPastEnd: Double = 40

    /// The reader pushed past the end of the text (on a text too short to scroll, any push up): the bar is shown if it was hidden and
    /// hidden if it was shown, and scrolling goes on from `offset`, the end. Returns whether the bar is now hidden.
    public mutating func pushedPastEnd(at offset: Double) -> Bool {
        hidden = !hidden
        anchor = offset
        return hidden
    }

    /// The bar was shown by something else: start again from here.
    public mutating func reset(at offset: Double) {
        hidden = false
        anchor = offset
    }

    /// The bar was hidden by something else (a tap on the text): scrolling up from here brings it back.
    public mutating func forceHidden(at offset: Double) {
        hidden = true
        anchor = offset
    }

    public init(threshold: Double = 40) {
        self.threshold = threshold
    }
}
