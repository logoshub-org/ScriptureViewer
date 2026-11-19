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

/// The reader reaching the end of a text: a devotional day or a reading plan chapter is read from it.
@MainActor
final class ScriptureTextViewEndTests: XCTestCase {

	private final class Recorder: NSObject, ScriptureTextViewDelegate {
		var ends = 0
		func scriptureTextViewTopReloadTriggered(_ view: ScriptureTextView) {}
		func scriptureTextViewBottomReloadTriggered(_ view: ScriptureTextView) {}
		func scriptureTextViewScrollHappened(_ view: ScriptureTextView, newOffsetY: CGFloat) {}
		func switchToFullscreen() {}
		func scriptureTextViewReachedEnd(_ view: ScriptureTextView) { ends += 1 }
	}

	private let recorder = Recorder()

	private func makeView(words: Int) -> ScriptureTextView {
		let text = Array(repeating: "In the beginning God created the heaven and the earth.", count: words).joined(separator: " ")
		let model = ScriptureText(text: text)
		let view = ScriptureTextView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
		view.scriptureDelegate = recorder
		view.display(model, theme: ScriptureTextTheme())
		view.layoutIfNeeded()
		return view
	}

	private func scrollView(of view: ScriptureTextView) -> UIScrollView { view.scrollView }

	func testTextThatFitsTheScreenIsReportedAsReadAtOnce() async throws {
		let view = makeView(words: 1)
		try await Task.sleep(nanoseconds: 200_000_000)
		XCTAssertEqual(recorder.ends, 1)
		withExtendedLifetime(view) {}
	}

	func testLongTextIsReportedOnlyWhenTheReaderScrollsToTheBottom() async throws {
		let view = makeView(words: 60)
		try await Task.sleep(nanoseconds: 200_000_000)
		XCTAssertEqual(recorder.ends, 0, "the top of a long text is not its end")

		let scroll = scrollView(of: view)
		scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height / 2), animated: false)
		view.reportEndIfAtBottom(userDriven: true)
		XCTAssertEqual(recorder.ends, 0, "half way")

		scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom), animated: false)
		view.reportEndIfAtBottom(userDriven: false)
		XCTAssertEqual(recorder.ends, 0, "the view putting the text in place is not the reader getting there")
		view.reportEndIfAtBottom(userDriven: true)
		XCTAssertEqual(recorder.ends, 1)
		view.reportEndIfAtBottom(userDriven: true)
		XCTAssertEqual(recorder.ends, 1, "once")
	}

	func testNewTextCanBeReportedAgain() async throws {
		let view = makeView(words: 1)
		try await Task.sleep(nanoseconds: 200_000_000)
		view.display(ScriptureText(text: "Another short text."), theme: ScriptureTextTheme())
		view.layoutIfNeeded()
		try await Task.sleep(nanoseconds: 200_000_000)
		XCTAssertEqual(recorder.ends, 2)
	}
}

#endif
