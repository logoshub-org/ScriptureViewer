// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if canImport(UIKit)
import XCTest
import SwiftUI
import ScriptureText
@testable import ScriptureViewer

/// The SwiftUI `ScriptureViewer`, the iOS realisation of the viewer contract (plan D157): what goes in reaches the text view, and
/// what the text view reports comes out as the contract's events.
@MainActor
final class ScriptureViewerViewTests: XCTestCase {

	private func chapter(verses: Int = 3) -> ScriptureText {
		var text = ""
		var spans: [ScriptureText.Span] = []
		var ranges: [ScriptureText.VerseRange] = []
		for verse in 1...verses {
			let start = text.utf16.count
			let marker = String(verse)
			text += marker + "In the beginning God created the heavens and the earth, and the earth was without form and void. \n"
			spans.append(.init(start: start, length: marker.utf16.count, attribute: .verseNumber(verse)))
			ranges.append(.init(verse: verse, start: start, length: text.utf16.count - start))
		}
		return ScriptureText(text: text, spans: spans, verses: ranges,
		                     identity: PassageIdentity(work: "KJV", versification: "KJV", book: "Gen", chapter: 1))
	}

	private func show(_ viewer: ScriptureViewer, width: CGFloat = 320, height: CGFloat = 568) -> (UIHostingController<ScriptureViewer>, UIWindow) {
		let host = UIHostingController(rootView: viewer)
		let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
		window.rootViewController = host
		window.makeKeyAndVisible()
		host.view.frame = window.bounds
		host.view.layoutIfNeeded()
		return (host, window)
	}

	/// SwiftUI applies a new root view on the next turn of the run loop.
	private func settle(_ host: UIViewController) {
		RunLoop.main.run(until: Date().addingTimeInterval(0.15))
		host.view.layoutIfNeeded()
	}

	private func textView(in view: UIView) -> ScriptureTextView? {
		if let found = view as? ScriptureTextView { return found }
		for sub in view.subviews { if let found = textView(in: sub) { return found } }
		return nil
	}

	func testItShowsTheTextInTheTheme() throws {
		let text = chapter()
		var theme = ScriptureViewerTheme()
		theme.nightMode = true
		let (host, _) = show(ScriptureViewer(text: text, theme: theme))
		let view = try XCTUnwrap(textView(in: host.view))
		XCTAssertEqual(view.displayedText, text.text)
		XCTAssertEqual(view.backgroundColor, ScriptureTextTheme(nightMode: true).backgroundColor)
	}

	func testANewTextOrThemeIsShownAndTheSameOneIsLeftAlone() throws {
		let (host, _) = show(ScriptureViewer(text: chapter(verses: 2)))
		let view = try XCTUnwrap(textView(in: host.view))
		let second = chapter(verses: 4)
		host.rootView = ScriptureViewer(text: second)
		settle(host)
		XCTAssertEqual(view.displayedText, second.text)
		XCTAssertTrue(view === textView(in: host.view), "the text view is kept, not made again")
	}

	func testAScrollToAVerseFarDownReachesIt() throws {
		// Just shown, TextKit 2 has only estimated the height of the text below the screen; the scroll must not stop at the
		// end of the estimate.
		let controller = ScriptureViewerController()
		let (host, _) = show(ScriptureViewer(text: chapter(verses: 40), controller: controller))
		let view = try XCTUnwrap(textView(in: host.view))
		controller.scroll(toVerse: 30)
		XCTAssertEqual(view.scrollView.contentOffset.y, try XCTUnwrap(view.rectOfVerse(30)).minY - view.topLength, accuracy: 1)
		XCTAssertEqual(view.currentVerse, 30)
	}

	func testAnotherThemeKeepsTheReadersPlaceAndANewTextStartsAtItsTop() throws {
		let controller = ScriptureViewerController()
		let text = chapter(verses: 40)
		let (host, _) = show(ScriptureViewer(text: text, controller: controller))
		let view = try XCTUnwrap(textView(in: host.view))
		controller.scroll(toVerse: 30)
		let before = view.scrollView.contentOffset.y
		XCTAssertGreaterThan(before, 0)

		// Night mode: the same text, styled again where the reader is.
		host.rootView = ScriptureViewer(text: text, theme: ScriptureViewerTheme(nightMode: true), controller: controller)
		settle(host)
		XCTAssertEqual(view.backgroundColor, ScriptureTextTheme(nightMode: true).backgroundColor)
		XCTAssertEqual(view.scrollView.contentOffset.y, before, accuracy: 1)
		XCTAssertEqual(view.currentVerse, 30)
		XCTAssertEqual(controller.currentVerse, 30)
		XCTAssertEqual(controller.scrollOffset, Double(view.scrollView.contentOffset.y + view.topLength), accuracy: 1)

		// A bigger font moves every line, past what TextKit had estimated; the verse at the top is still the reader's.
		host.rootView = ScriptureViewer(text: text, theme: ScriptureViewerTheme(nightMode: true, fontSize: 24), controller: controller)
		settle(host)
		XCTAssertEqual(view.currentVerse, 30)
		XCTAssertEqual(view.scrollView.contentOffset.y, try XCTUnwrap(view.rectOfVerse(30)).minY - view.topLength, accuracy: 1)

		// At the very top, it stays at the very top.
		controller.scroll(toOffset: 0)
		host.rootView = ScriptureViewer(text: text, controller: controller)
		settle(host)
		XCTAssertEqual(view.scrollView.contentOffset.y, -view.topLength, accuracy: 1)

		// A new text still starts at its top.
		controller.scroll(toVerse: 20)
		host.rootView = ScriptureViewer(text: chapter(verses: 39), controller: controller)
		settle(host)
		XCTAssertEqual(view.scrollView.contentOffset.y, -view.topLength, accuracy: 1)
		XCTAssertEqual(view.currentVerse, 1)
	}

	func testGesturesPullsAndTheEndAreEvents() throws {
		var seen: [String] = []
		var events = ScriptureViewerEvents()
		events.onGesture = { seen.append("\($0)") }
		events.onPull = { seen.append("\($0)") }
		events.onReachedEnd = { seen.append("end") }
		let (host, _) = show(ScriptureViewer(text: chapter(verses: 1), events: events))
		let view = try XCTUnwrap(textView(in: host.view))
		let delegate = try XCTUnwrap(view.scriptureDelegate)
		delegate.scriptureTextViewDidTapPlainText(view)
		delegate.scriptureTextViewDidTapWithTwoFingers(view)
		delegate.scriptureTextViewDidSwipeLeft(view)
		delegate.scriptureTextViewDidSwipeRight(view)
		delegate.scriptureTextViewDidDragWithThreeFingers(view)
		delegate.scriptureTextViewTopReloadTriggered(view)
		delegate.scriptureTextViewBottomReloadTriggered(view)
		XCTAssertEqual(seen, ["plainTap", "twoFingerTap", "swipeLeft", "swipeRight", "threeFingerDrag", "previousChapter", "nextChapter"])
		view.reportEndIfAtBottom(userDriven: false)
		XCTAssertEqual(seen.last, "end", "a text that fits the screen has been read to its end")
	}

	func testATapOnATargetIsAnEventWithItsTarget() throws {
		var tapped: TapTarget?
		var events = ScriptureViewerEvents()
		events.onTap = { tapped = $0 }
		let (host, _) = show(ScriptureViewer(text: chapter(), events: events))
		let view = try XCTUnwrap(textView(in: host.view))
		let target = TapTarget(kind: .verse, key: "2", context: .init(offset: 5, verse: 2))
		view.onTap?(target)
		XCTAssertEqual(tapped, target)
	}

	func testTheSelectionMenuAndItsItemsAreReportedAsEvents() throws {
		var selections: [ScriptureSelection?] = []
		var chosen: (String, ScriptureSelection)?
		var events = ScriptureViewerEvents()
		events.onSelectionChange = { selections.append($0) }
		events.onMenuItem = { chosen = ($0, $1) }
		events.referenceLine = { "Genesis 1:\($0.lowerBound)–\($0.upperBound) (KJV)" }
		let controller = ScriptureViewerController()
		let configuration = ScriptureViewerConfiguration(menuItems: [ScriptureMenuItem(id: "bookmark", title: "Add Bookmark")])
		let text = chapter()
		let (host, _) = show(ScriptureViewer(text: text, configuration: configuration, controller: controller, events: events))
		let view = try XCTUnwrap(textView(in: host.view))
		XCTAssertEqual(view.menuItems, configuration.menuItems)

		let end = text.verses[1].start + 10
		view.onSelectionChange?(NSRange(location: 0, length: end))
		XCTAssertEqual(selections.last??.verses, 1...2)
		XCTAssertEqual(controller.selection?.length, end)
		view.onSelectionChange?(NSRange(location: 4, length: 0))
		XCTAssertNil(selections.last ?? nil)
		XCTAssertNil(controller.selection)

		view.onMenuItem?("bookmark", NSRange(location: 0, length: end))
		XCTAssertEqual(chosen?.0, "bookmark")
		XCTAssertEqual(chosen?.1.verses, 1...2)
		XCTAssertEqual(view.copyReference?(1, 2), "Genesis 1:1–2 (KJV)")
	}

	func testTheControllerScrollsTheTextAndHearsWhereItIs() throws {
		let controller = ScriptureViewerController()
		var offsets: [(Double, Int)] = []
		var events = ScriptureViewerEvents()
		events.onScroll = { offsets.append(($0, $1)) }
		let (host, _) = show(ScriptureViewer(text: chapter(verses: 40), controller: controller, events: events))
		let view = try XCTUnwrap(textView(in: host.view))
		XCTAssertNotNil(controller.driver)
		controller.scroll(toVerse: 30)
		XCTAssertEqual(view.currentVerse, 30)
		controller.focus(verse: 12)
		XCTAssertEqual(controller.focusedVerse, 12)
		XCTAssertEqual(view.focusedVerseNumber, 12)
		controller.clearFocus()
		XCTAssertNil(controller.focusedVerse)
		XCTAssertEqual(view.focusedVerseNumber, 0)

		view.scriptureDelegate?.scriptureTextViewScrollHappened(view, newOffsetY: 480)
		XCTAssertEqual(controller.scrollOffset, 480)
		XCTAssertEqual(offsets.last?.0, 480)
		controller.scroll(toOffset: 100)
		XCTAssertEqual(view.scrollView.contentOffset.y, 100 - view.topLength, accuracy: 0.5)
	}

	func testHighlightsAreMarkedAndTheirChangeRepaints() throws {
		var highlights = ScriptureHighlights(bookmarks: [.init(verse: 2, hexColour: "#FF0000")])
		let (host, _) = show(ScriptureViewer(text: chapter(), highlights: highlights))
		let view = try XCTUnwrap(textView(in: host.view))
		let bookmarked = view.paintedHighlightRanges.count
		XCTAssertGreaterThan(bookmarked, 0)
		highlights.searchTerms = ["created"]
		host.rootView = ScriptureViewer(text: chapter(), highlights: highlights)
		settle(host)
		XCTAssertGreaterThan(view.paintedHighlightRanges.count, bookmarked)
	}

	func testTheBarsAreLeftToTheHostWhenItAsksForChromeRequests() throws {
		var requests: [String] = []
		var events = ScriptureViewerEvents()
		events.onChromeRequest = { requests.append("\($0)") }
		let (host, _) = show(ScriptureViewer(text: chapter(), events: events))
		let view = try XCTUnwrap(textView(in: host.view))
		XCTAssertTrue(view.hidesTabBarOnScroll)
		view.onChromeRequest?(true)
		view.onChromeRequest?(false)
		XCTAssertEqual(requests, ["hide", "show"])

		let (plain, _) = show(ScriptureViewer(text: chapter()))
		let other = try XCTUnwrap(textView(in: plain.view))
		XCTAssertFalse(other.hidesTabBarOnScroll)
		XCTAssertNil(other.onChromeRequest)
	}

	func testTheInsetsAndTheScrollSettingReachTheTextView() throws {
		let configuration = ScriptureViewerConfiguration(topInset: 50, bottomInset: 80, scrolls: false, pullChangesChapter: true)
		let (host, _) = show(ScriptureViewer(text: chapter(), configuration: configuration))
		let view = try XCTUnwrap(textView(in: host.view))
		XCTAssertEqual(view.topLength, 50)
		XCTAssertEqual(view.bottomLength, 80)
		XCTAssertFalse(view.scrollView.isScrollEnabled)
		XCTAssertTrue(view.pullChangesChapter)
	}

	func testAViewerThatDoesNotScrollTakesTheHeightOfItsText() throws {
		let configuration = ScriptureViewerConfiguration(scrolls: false)
		let short = UIHostingController(rootView: ScriptureViewer(text: chapter(verses: 1), configuration: configuration))
		let long = UIHostingController(rootView: ScriptureViewer(text: chapter(verses: 12), configuration: configuration))
		for host in [short, long] {
			let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
			window.rootViewController = host
			window.makeKeyAndVisible()
			host.view.layoutIfNeeded()
		}
		let shortHeight = short.sizeThatFits(in: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height
		let longHeight = long.sizeThatFits(in: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)).height
		XCTAssertGreaterThan(shortHeight, 20)
		XCTAssertGreaterThan(longHeight, shortHeight * 4)
	}

	func testTheContractsFontSizeIsInCSSPointsAndTheUIKitThemeIsInPoints() {
		let theme = ScriptureTextTheme(ScriptureViewerTheme(nightMode: true, fontName: "Helvetica Neue", fontSize: 15, isWide: true))
		XCTAssertEqual(theme.fontSize, 15 * ScriptureTextTheme.cssPointToUIKitPoint, accuracy: 0.001)
		XCTAssertTrue(theme.nightMode)
		XCTAssertTrue(theme.isPad)
	}

	func testTheHostAnswersWhetherATapMayHideTheBarsAndReceivesTheShare() throws {
		var answer = false
		var shared: [String] = []
		var events = ScriptureViewerEvents()
		events.onChromeRequest = { _ in }
		events.canHideChrome = { answer }
		events.onShare = { shared.append($0) }
		let (host, _) = show(ScriptureViewer(text: chapter(verses: 2), events: events))
		let view = try XCTUnwrap(textView(in: host.view))
		XCTAssertEqual(view.canHideChrome?(), false)
		answer = true
		XCTAssertEqual(view.canHideChrome?(), true)
		view.onShare?("Genesis 1:1\nIn the beginning")
		XCTAssertEqual(shared, ["Genesis 1:1\nIn the beginning"])

		let (plain, _) = show(ScriptureViewer(text: chapter(verses: 2)))
		let other = try XCTUnwrap(textView(in: plain.view))
		XCTAssertNil(other.canHideChrome, "without an answer the viewer never hides the bars by a tap")
		XCTAssertNil(other.onShare, "and shares with the system's sheet")
	}

	func testAVerseIsCopiedByTheCoreWithTheHostsReferenceLine() {
		let text = chapter(verses: 3)
		let copied = text.copiedText(verse: 2, referenceLine: { "Genesis 1:\($0.lowerBound) (KJV)" })
		XCTAssertTrue(copied?.hasPrefix("Genesis 1:2 (KJV)\n") == true)
		XCTAssertNil(text.copiedText(verse: 9, referenceLine: { _ in "x" }))
		XCTAssertFalse(text.copiedText(verse: 1, referenceLine: { _ in nil })?.contains("(KJV)") ?? true)
	}
}

#endif
