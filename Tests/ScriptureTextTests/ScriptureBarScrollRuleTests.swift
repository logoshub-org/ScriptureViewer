// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
@testable import ScriptureText

/// When scrolling hides the host's bars and when it brings them back (plan D107, D165): the rule every platform's viewer applies.
struct ScriptureBarScrollRuleTests {

    @Test func theRuleCanBeToldTheBarWasHiddenAndScrollingUpBringsItBack() {
        var rule = ScriptureBarScrollRule()
        rule.forceHidden(at: 500)
        #expect(rule.hidden)
        #expect(rule.update(offset: 480, maxOffset: 2000) == nil, "a small move up does nothing")
        #expect(rule.update(offset: 440, maxOffset: 2000) == false, "more than 40 points up shows it")
    }

    @Test func scrollingDownHidesAfterTheThresholdAndUpShows() {
        var rule = ScriptureBarScrollRule()
        #expect(rule.update(offset: 0, maxOffset: 2000) == nil, "at the top: shown, nothing changes")
        #expect(rule.update(offset: 30, maxOffset: 2000) == nil, "under the threshold")
        #expect(rule.update(offset: 80, maxOffset: 2000) == true, "40 points down hides")
        #expect(rule.update(offset: 400, maxOffset: 2000) == nil, "already hidden")
        #expect(rule.update(offset: 380, maxOffset: 2000) == nil, "a wobble up does nothing")
        #expect(rule.update(offset: 350, maxOffset: 2000) == false, "more than 40 points up from the lowest shows")
        #expect(rule.update(offset: 360, maxOffset: 2000) == nil)
        #expect(rule.update(offset: 420, maxOffset: 2000) == true, "and down again hides")
    }

    @Test func scrollingBackToTheTopShowsTheBarButTheEndDoesNot() {
        var rule = ScriptureBarScrollRule()
        #expect(rule.update(offset: 100, maxOffset: 2000) == true)
        #expect(rule.update(offset: 500, maxOffset: 2000) == nil)
        #expect(rule.update(offset: 1999.5, maxOffset: 2000) == nil, "the end of the text leaves the bar hidden")
        #expect(rule.hidden)
        #expect(rule.update(offset: 0.5, maxOffset: 2000) == false, "back up to the top")
    }

    /// A long text starts with the bar away (0.2.9): being at the top does not bring it; scrolling up does, here a pull down at the top.
    @Test func aTextThatStartsWithTheBarAwayKeepsItAwayAtTheTop() {
        var rule = ScriptureBarScrollRule()
        rule.forceHidden(at: 0)
        #expect(rule.update(offset: 0.5, maxOffset: 2000) == nil, "the first touch at the top leaves it away")
        #expect(rule.update(offset: 0, maxOffset: 2000) == nil)
        #expect(rule.update(offset: 200, maxOffset: 2000) == nil, "reading down, still away")
        #expect(rule.update(offset: 150, maxOffset: 2000) == false, "scrolling up brings it")
        rule.forceHidden(at: 0)
        #expect(rule.update(offset: -45, maxOffset: 2000) == false, "and so does a pull down at the top")
    }

    @Test func textThatDoesNotScrollNeverHidesTheBar() {
        var rule = ScriptureBarScrollRule()
        #expect(rule.update(offset: 60, maxOffset: 0) == nil)
        #expect(!rule.hidden)
    }

    @Test func aTapShowsTheBarAndRestartsTheRule() {
        var rule = ScriptureBarScrollRule()
        _ = rule.update(offset: 100, maxOffset: 2000)
        _ = rule.update(offset: 300, maxOffset: 2000)
        #expect(rule.hidden)
        rule.reset(at: 300)
        #expect(!rule.hidden)
        #expect(rule.update(offset: 320, maxOffset: 2000) == nil)
        #expect(rule.update(offset: 400, maxOffset: 2000) == true)
    }

    @Test func aPushPastTheEndShowsOrHidesTheBarAndScrollingGoesOnFromThere() {
        var rule = ScriptureBarScrollRule()
        #expect(rule.pushedPastEnd(at: 1000) == true, "shown: the push hides it")
        #expect(rule.pushedPastEnd(at: 1000) == false, "hidden: the push shows it")
        #expect(rule.pushedPastEnd(at: 1000) == true)
        #expect(rule.update(offset: 980, maxOffset: 1000) == nil, "a wobble back does nothing")
        #expect(rule.update(offset: 950, maxOffset: 1000) == false, "scrolling back up from the end shows it")
    }

    @Test func aDifferentThresholdMovesTheBarSooner() {
        var rule = ScriptureBarScrollRule(threshold: 10)
        #expect(rule.update(offset: 5, maxOffset: 2000) == nil)
        #expect(rule.update(offset: 30, maxOffset: 2000) == true)
    }
}
