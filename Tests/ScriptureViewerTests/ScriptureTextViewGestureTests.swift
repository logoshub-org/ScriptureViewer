// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if canImport(UIKit)
import UIKit
import XCTest
import ScriptureText
@testable import ScriptureViewer

/// The reader gestures of plan D76: what each reports, and when it stays quiet.
@MainActor
final class ScriptureTextViewGestureTests: XCTestCase {

	private final class Recorder: NSObject, ScriptureTextViewDelegate {
		var plainTaps = 0, twoFingerTaps = 0, lefts = 0, rights = 0, threeFingerDrags = 0
		func scriptureTextViewTopReloadTriggered(_ view: ScriptureTextView) {}
		func scriptureTextViewBottomReloadTriggered(_ view: ScriptureTextView) {}
		func scriptureTextViewScrollHappened(_ view: ScriptureTextView, newOffsetY: CGFloat) {}
		func switchToFullscreen() {}
		func scriptureTextViewDidTapPlainText(_ view: ScriptureTextView) { plainTaps += 1 }
		func scriptureTextViewDidTapWithTwoFingers(_ view: ScriptureTextView) { twoFingerTaps += 1 }
		func scriptureTextViewDidSwipeLeft(_ view: ScriptureTextView) { lefts += 1 }
		func scriptureTextViewDidSwipeRight(_ view: ScriptureTextView) { rights += 1 }
		func scriptureTextViewDidDragWithThreeFingers(_ view: ScriptureTextView) { threeFingerDrags += 1 }
	}

	private let recorder = Recorder()

	/// "1In the beginning…" with a verse-number span on the "1".
	private func sample() -> ScriptureText {
		let text = "1In the beginning God created the heaven and the earth."
		return ScriptureText(text: text, spans: [.init(start: 0, length: 1, attribute: .verseNumber(1))],
		                     verses: [.init(verse: 1, start: 0, length: text.utf16.count)])
	}

	private func makeView() -> ScriptureTextView {
		let model = sample()
		let view = ScriptureTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
		view.display(model, theme: ScriptureTextTheme())
		view.scriptureDelegate = recorder
		view.layoutIfNeeded()
		return view
	}

	private func centre(of offset: Int, in view: ScriptureTextView) throws -> CGPoint {
		let rect = try XCTUnwrap(view.rectOfCharacter(atUTF16Offset: offset))
		return CGPoint(x: rect.midX, y: rect.midY)
	}

	func testTheGesturesAreInstalledWithTheOriginalAppsShapes() throws {
		let gestures = makeView().readerGestures
		XCTAssertEqual(gestures.count, 5)
		XCTAssertEqual((gestures[1] as? UITapGestureRecognizer)?.numberOfTouchesRequired, 2)
		XCTAssertEqual((gestures[2] as? UISwipeGestureRecognizer)?.direction, .left)
		XCTAssertEqual((gestures[3] as? UISwipeGestureRecognizer)?.direction, .right)
		XCTAssertEqual((gestures[4] as? UIPanGestureRecognizer)?.minimumNumberOfTouches, 3)
		XCTAssertTrue(gestures.allSatisfy { !$0.cancelsTouchesInView }, "the text view keeps its own touches")
	}

	func testAPlainTapOnTextIsReportedButNotOneOnAVerseNumber() throws {
		let view = makeView()
		view.reportPlainTap(at: try centre(of: 8, in: view))
		XCTAssertEqual(recorder.plainTaps, 1)
		view.reportPlainTap(at: try centre(of: 0, in: view))
		XCTAssertEqual(recorder.plainTaps, 1, "the verse number opens the verse menu instead")
	}

	/// The bar follows the scroll and a push past the end, never a tap (0.2.8).
	func testATapLeavesTheBarAlone() throws {
		let view = makeView()
		var requests: [Bool] = []
		view.onChromeRequest = { requests.append($0) }
		view.hidesTabBarOnScroll = true
		view.reportPlainTap(at: try centre(of: 8, in: view))
		XCTAssertEqual(recorder.plainTaps, 1, "the tap is still the host's (Automatic Fullscreen)")
		XCTAssertEqual(requests, [], "but the bar does not move")
	}

	/// A long text: scrolling down hides the bar; at the end a push past it shows the bar, once per drag; the spring back does not
	/// undo it; the next push hides it again.
	func testAPushPastTheEndOfALongTextShowsOrHidesTheBar() {
		let view = makeView()
		var requests: [Bool] = []
		view.onChromeRequest = { requests.append($0) }
		view.hidesTabBarOnScroll = true
		view.followScrollWithBar(offset: 100, maxOffset: 1000, tracking: true)
		XCTAssertEqual(requests, [true], "scrolling down hides it")
		view.followScrollWithBar(offset: 1000, maxOffset: 1000, tracking: true)
		view.followScrollWithBar(offset: 1030, maxOffset: 1000, tracking: true)
		XCTAssertEqual(requests, [true], "a small push does nothing")
		view.followScrollWithBar(offset: 1050, maxOffset: 1000, tracking: true)
		view.followScrollWithBar(offset: 1090, maxOffset: 1000, tracking: true)
		XCTAssertEqual(requests, [true, false], "a push of more than 40 points shows it, once")
		view.followScrollWithBar(offset: 1020, maxOffset: 1000, tracking: false)
		view.followScrollWithBar(offset: 1000, maxOffset: 1000, tracking: false)
		XCTAssertEqual(requests, [true, false], "the spring back leaves it")
		view.scrollViewWillBeginDragging(view.scrollView)
		view.followScrollWithBar(offset: 1060, maxOffset: 1000, tracking: true)
		XCTAssertEqual(requests, [true, false, true], "the next push hides it")
		XCTAssertTrue(view.barHidden)
		view.scrollViewWillBeginDragging(view.scrollView)
		view.followScrollWithBar(offset: 950, maxOffset: 1000, tracking: true)
		XCTAssertEqual(requests, [true, false, true, false], "and scrolling back up shows it, as before")
	}

	/// A text too short to scroll (Psalm 117, a short devotional): any push up shows or hides the bar, and the spring back to the top
	/// does not count as reaching the top; a pull down from the top still shows it.
	func testAPushOnATextTooShortToScrollShowsOrHidesTheBar() {
		let view = makeView()
		var requests: [Bool] = []
		view.onChromeRequest = { requests.append($0) }
		view.hidesTabBarOnScroll = true
		view.followScrollWithBar(offset: 50, maxOffset: -400, tracking: true)
		XCTAssertEqual(requests, [true], "a push up hides it")
		view.followScrollWithBar(offset: 10, maxOffset: -400, tracking: false)
		view.followScrollWithBar(offset: 0, maxOffset: -400, tracking: false)
		XCTAssertEqual(requests, [true], "springing back to the top leaves it hidden")
		view.scrollViewWillBeginDragging(view.scrollView)
		view.followScrollWithBar(offset: 60, maxOffset: -400, tracking: true)
		XCTAssertEqual(requests, [true, false], "the next push shows it")
		view.scrollViewWillBeginDragging(view.scrollView)
		view.followScrollWithBar(offset: 50, maxOffset: -400, tracking: true)
		view.scrollViewWillBeginDragging(view.scrollView)
		view.followScrollWithBar(offset: -30, maxOffset: -400, tracking: true)
		XCTAssertEqual(requests, [true, false, true, false], "a pull down from the top shows it")
	}

	func testATapWhileTextIsSelectedOnlyClearsTheSelection() throws {
		let view = makeView()
		let textView = try XCTUnwrap(view.scrollView as? UITextView)
		textView.selectedRange = NSRange(location: 3, length: 5)
		view.reportPlainTap(at: try centre(of: 8, in: view))
		view.reportSwipe(left: true)
		XCTAssertEqual(recorder.plainTaps, 0)
		XCTAssertEqual(recorder.lefts, 0, "dragging a selection handle is not a swipe")
	}

	func testSwipesReportTheirDirection() {
		let view = makeView()
		view.reportSwipe(left: true)
		view.reportSwipe(left: false)
		view.reportSwipe(left: false)
		XCTAssertEqual(recorder.lefts, 1)
		XCTAssertEqual(recorder.rights, 2)
	}

	func testAThreeFingerDragIsReportedOnceAtOneHundredPoints() {
		let view = makeView()
		view.resetThreeFingerDrag()
		view.reportThreeFingerDrag(verticalDistance: 60)
		XCTAssertEqual(recorder.threeFingerDrags, 0)
		view.reportThreeFingerDrag(verticalDistance: -120)
		view.reportThreeFingerDrag(verticalDistance: -200)
		XCTAssertEqual(recorder.threeFingerDrags, 1, "once per drag")
		view.resetThreeFingerDrag()
		view.reportThreeFingerDrag(verticalDistance: 100)
		XCTAssertEqual(recorder.threeFingerDrags, 2)
	}

	// MARK: Copy (D76 item 2)

	func testCopyPutsTheHostsReferenceAboveTheWords() throws {
		let view = makeView()
		view.copyReference = { first, last in first == last ? "Genesis 1:\(first) (KJV)" : "Genesis 1:\(first)–\(last) (KJV)" }
		XCTAssertEqual(sample().copiedText(verse: 1, referenceLine: { view.copyReference?($0.lowerBound, $0.upperBound) }),
		               "Genesis 1:1 (KJV)\n1 In the beginning God created the heaven and the earth.")
		let textView = try XCTUnwrap(view.scrollView as? UITextView)
		textView.selectedRange = NSRange(location: 4, length: 9)
		XCTAssertEqual(view.copiedSelection(), "Genesis 1:1 (KJV)\nthe begin")
		textView.selectedRange = NSRange(location: 0, length: 0)
		XCTAssertNil(view.copiedSelection(), "nothing selected: the system copy is left alone")
	}

	func testWithoutAReferenceCopyIsTheWordsOnly() {
		XCTAssertEqual(sample().copiedText(verse: 1, referenceLine: { _ in nil }), "1 In the beginning God created the heaven and the earth.")
		XCTAssertNil(sample().copiedText(verse: 9, referenceLine: { _ in nil }))
	}

	func testTheSelectionMenusShareItemSharesTheCopiedTextAndOthersStay() throws {
		let view = makeView()
		let textView = try XCTUnwrap(view.scrollView as? UITextView)
		let copy = UICommand(title: "Copy", action: #selector(UIResponderStandardEditActions.copy(_:)))
		let share = UICommand(title: "Share…", action: Selector(("_share:")))
		XCTAssertNil(view.textView(textView, editMenuForTextIn: NSRange(location: 0, length: 0), suggestedActions: [copy, share]),
		             "nothing selected: the system menu is left alone")
		textView.selectedRange = NSRange(location: 4, length: 9)
		let menu = try XCTUnwrap(view.textView(textView, editMenuForTextIn: textView.selectedRange,
		                                       suggestedActions: [UIMenu(children: [copy]), share]))
		XCTAssertTrue((menu.children[0] as? UIMenu)?.children.first === copy, "Copy stays (ours is the text view's copy:)")
		let replaced = try XCTUnwrap(menu.children[1] as? UIAction)
		XCTAssertEqual(replaced.title, "Share…")
	}
}

#endif
