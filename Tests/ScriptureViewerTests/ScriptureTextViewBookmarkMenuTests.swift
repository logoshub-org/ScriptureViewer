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

/// The selection menu's Add Bookmark (plan D108): the verses a selection touches, as one bookmark.
@MainActor
final class ScriptureTextViewBookmarkMenuTests: XCTestCase {

	private final class Host: NSObject, ScriptureTextViewDelegate {
		var offers = true
		var asked: [ClosedRange<Int>] = []
		func scriptureTextViewTopReloadTriggered(_ view: ScriptureTextView) {}
		func scriptureTextViewBottomReloadTriggered(_ view: ScriptureTextView) {}
		func scriptureTextViewScrollHappened(_ view: ScriptureTextView, newOffsetY: CGFloat) {}
		func switchToFullscreen() {}
		func scriptureTextViewOffersBookmark(_ view: ScriptureTextView) -> Bool { offers }
		func scriptureTextView(_ view: ScriptureTextView, bookmarkVersesFrom first: Int, to last: Int) { asked.append(first...last) }
	}

	private let host = Host()

	/// "1In the beginning. 2And the earth was empty. 3Then light came."
	private func makeView() -> ScriptureTextView {
		let one = "1In the beginning. ", two = "2And the earth was empty. ", three = "3Then light came."
		let text = one + two + three
		let model = ScriptureText(
			text: text,
			spans: [.init(start: 0, length: 1, attribute: .verseNumber(1)),
			        .init(start: one.utf16.count, length: 1, attribute: .verseNumber(2)),
			        .init(start: one.utf16.count + two.utf16.count, length: 1, attribute: .verseNumber(3))],
			verses: [.init(verse: 1, start: 0, length: one.utf16.count),
			         .init(verse: 2, start: one.utf16.count, length: two.utf16.count),
			         .init(verse: 3, start: one.utf16.count + two.utf16.count, length: three.utf16.count)])
		let view = ScriptureTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
		view.display(model, theme: ScriptureTextTheme())
		view.scriptureDelegate = host
		view.layoutIfNeeded()
		return view
	}

	private func textView(of view: ScriptureTextView) -> UITextView { view.scrollView as! UITextView }

	private func bookmarkAction(in view: ScriptureTextView) -> UIAction? {
		let text = textView(of: view)
		let menu = view.textView(text, editMenuForTextIn: text.selectedRange, suggestedActions: [])
		return menu?.children.compactMap { $0 as? UIAction }.first { $0.title == "Add Bookmark" }
	}

	func testASelectionAcrossVersesOffersABookmarkOfTheWholeRun() throws {
		let view = makeView()
		textView(of: view).selectedRange = NSRange(location: 5, length: 30)    // from verse 1 into verse 2
		XCTAssertEqual(view.selectedVerses(), 1...2)
		let action = try XCTUnwrap(bookmarkAction(in: view))
		action.performWithSender(nil, target: nil)
		XCTAssertEqual(host.asked, [1...2])
	}

	func testASelectionInOneVerseAsksForThatVerse() throws {
		let view = makeView()
		textView(of: view).selectedRange = NSRange(location: 22, length: 6)    // inside verse 2
		try XCTUnwrap(bookmarkAction(in: view)).performWithSender(nil, target: nil)
		XCTAssertEqual(host.asked, [2...2])
	}

	func testNoItemWhenTheHostDoesNotOfferIt() {
		let view = makeView()
		host.offers = false
		textView(of: view).selectedRange = NSRange(location: 5, length: 30)
		XCTAssertNil(bookmarkAction(in: view))
	}
}

#endif
