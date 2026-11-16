// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Testing
@testable import ScriptureText

@MainActor
struct ScriptureViewerContractTests {

    private final class RecordingDriver: ScriptureViewerDriver {
        var calls: [String] = []
        func scroll(toVerse verse: Int, animated: Bool) { calls.append("verse \(verse) \(animated)") }
        func scroll(toOffset offset: Double, animated: Bool) { calls.append("offset \(offset) \(animated)") }
        func focus(verse: Int) { calls.append("focus \(verse)") }
        func clearFocus() { calls.append("clearFocus") }
        func clearSelection() { calls.append("clearSelection") }
    }

    @Test func theControllerForwardsItsCommandsToThePlatformView() {
        let controller = ScriptureViewerController()
        let driver = RecordingDriver()
        controller.driver = driver
        controller.scroll(toVerse: 105)
        controller.scroll(toOffset: 120.5, animated: true)
        controller.focus(verse: 16)
        controller.clearFocus()
        controller.clearSelection()
        #expect(driver.calls == ["verse 105 false", "offset 120.5 true", "focus 16", "clearFocus", "clearSelection"])
    }

    @Test func theControllerKeepsWhatThePlatformViewLastSaid() {
        let controller = ScriptureViewerController()
        controller.update(scrollOffset: 16908, verse: 105, atEnd: false)
        controller.update(selection: ScriptureSelection(start: 751, length: 189, verses: 11...14))
        #expect(controller.currentVerse == 105)
        #expect(controller.scrollOffset == 16908)
        #expect(controller.selection?.verses == 11...14)
        controller.focus(verse: 7)
        #expect(controller.focusedVerse == 7)
        controller.clearFocus()
        #expect(controller.focusedVerse == nil)
    }

    @Test func commandsAfterNewTextWaitUntilItIsShownAndRunInOrder() {
        let controller = ScriptureViewerController()
        let driver = RecordingDriver()
        controller.driver = driver
        controller.willShowNewText()
        controller.scroll(toVerse: 30)
        controller.focus(verse: 31)
        controller.scroll(toOffset: 400)
        #expect(driver.calls.isEmpty)
        #expect(controller.focusedVerse == 31, "what the host asked for is visible at once")
        controller.textWasShown()
        #expect(driver.calls == ["verse 30 false", "focus 31", "offset 400.0 false"])
        controller.scroll(toVerse: 2)
        #expect(driver.calls.last == "verse 2 false", "once shown, commands go straight through")
        controller.textWasShown()   // no effect without a pending text
        #expect(driver.calls.count == 4)
    }

    @Test func aNewerTextDropsCommandsHeldForTheOlderOne() {
        let controller = ScriptureViewerController()
        let driver = RecordingDriver()
        controller.driver = driver
        controller.willShowNewText()
        controller.scroll(toVerse: 9)
        controller.willShowNewText()
        controller.scroll(toVerse: 4)
        controller.textWasShown()
        #expect(driver.calls == ["verse 4 false"])
    }

    @Test func commandsHeldBeforeTheViewExistsRunWhenItShowsTheText() {
        let controller = ScriptureViewerController()
        controller.willShowNewText()
        controller.scroll(toVerse: 12)
        let driver = RecordingDriver()
        controller.driver = driver
        controller.textWasShown()
        #expect(driver.calls == ["verse 12 false"])
    }

    @Test func nothingHappensWithoutAPlatformView() {
        let controller = ScriptureViewerController()
        controller.scroll(toVerse: 3)   // no driver: no crash, no effect
        #expect(controller.currentVerse == 0)
    }

    @Test func theHostNamesTheVersesOfCopiedText() {
        var events = ScriptureViewerEvents()
        #expect(events.referenceLine == nil)
        events.referenceLine = { verses in "Psalms 119:\(verses.lowerBound)–\(verses.upperBound) (KJV)" }
        #expect(events.referenceLine?(9...16) == "Psalms 119:9–16 (KJV)")
    }

    @Test func theDefaultsAreTheQuietOnes() {
        let configuration = ScriptureViewerConfiguration()
        #expect(configuration.scrolls)
        #expect(!configuration.pullChangesChapter)
        #expect(configuration.menuItems.isEmpty)
        #expect(ScriptureHighlights() == ScriptureHighlights(bookmarks: [], searchTerms: [], strongs: nil))
        #expect(ScriptureViewerTheme().fontSize == 14)
    }
}
