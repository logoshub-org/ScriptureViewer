// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if canImport(UIKit)

import UIKit
import ScriptureText

/// What the reading view reports to its host: scrolling, the end of the chapter, taps and swipes, and the
/// selection menu's choices.
@MainActor
public protocol ScriptureTextViewDelegate: AnyObject {
	func scriptureTextViewTopReloadTriggered(_ view: ScriptureTextView)
	func scriptureTextViewBottomReloadTriggered(_ view: ScriptureTextView)
	func scriptureTextViewScrollHappened(_ view: ScriptureTextView, newOffsetY: CGFloat)
	func switchToFullscreen()

	// The reader's own gestures (plan D76): what the original app's gesture layer did, as reports. The host decides.
	/// A single tap on text that is not a marker, link or verse number, with no text selected and not stopping a scroll.
	/// A tap on a word that only carries lexical data counts as plain.
	func scriptureTextViewDidTapPlainText(_ view: ScriptureTextView)
	/// A two-finger tap anywhere on the text.
	func scriptureTextViewDidTapWithTwoFingers(_ view: ScriptureTextView)
	/// A quick one-finger horizontal swipe, with no text selected. Left and right are the directions on screen.
	func scriptureTextViewDidSwipeLeft(_ view: ScriptureTextView)
	func scriptureTextViewDidSwipeRight(_ view: ScriptureTextView)
	/// Whether the selection menu offers Add Bookmark (the Bible tab does), and the call for it: the first and last verse
	/// the selection touches, which are the same for one verse.
	func scriptureTextViewOffersBookmark(_ view: ScriptureTextView) -> Bool
	func scriptureTextView(_ view: ScriptureTextView, bookmarkVersesFrom first: Int, to last: Int)
	/// A three-finger vertical drag of at least 100 points; reported once per drag.
	func scriptureTextViewDidDragWithThreeFingers(_ view: ScriptureTextView)
	/// The reader has scrolled to the end of the text, or the text fits the screen and all of it is showing. Reported once
	/// for each text shown (a devotional or a reading plan counts a day as read from it).
	func scriptureTextViewReachedEnd(_ view: ScriptureTextView)
}

/// The reports a host does not care about are ignored.
extension ScriptureTextViewDelegate {
	public func scriptureTextViewDidTapPlainText(_ view: ScriptureTextView) {}
	public func scriptureTextViewDidTapWithTwoFingers(_ view: ScriptureTextView) {}
	public func scriptureTextViewDidSwipeLeft(_ view: ScriptureTextView) {}
	public func scriptureTextViewDidSwipeRight(_ view: ScriptureTextView) {}
	public func scriptureTextViewOffersBookmark(_ view: ScriptureTextView) -> Bool { false }
	public func scriptureTextView(_ view: ScriptureTextView, bookmarkVersesFrom first: Int, to last: Int) {}
	public func scriptureTextViewDidDragWithThreeFingers(_ view: ScriptureTextView) {}
	public func scriptureTextViewReachedEnd(_ view: ScriptureTextView) {}
	public func switchToFullscreen() {}
}

/// The native reading surface (plan Phase 4): a TextKit 2 UITextView showing a
/// styled ScriptureText, with verse-exact scrolling, current-verse tracking,
/// the legacy pull-to-navigate thresholds and auto-fullscreen behaviour.
///
/// Layout rules (plan U2): no UIScreen/status-bar/orientation APIs; the view
/// pins to its container, reads its own insets, and re-anchors to the current
/// verse when its bounds change.
///
/// TextKit 2 only: text layout is accessed exclusively through
/// `textLayoutManager`. Never touch `UITextView.layoutManager` — doing so
/// silently and permanently downgrades the view to TextKit 1.

public final class ScriptureTextView: UIView {

	public weak var scriptureDelegate: ScriptureTextViewDelegate?
	public var autoFullscreenMode = false
	/// The iPad's icon bar hides as the text scrolls down and comes back scrolling up, at the top and at the end, and on a tap
	/// (plan D107). The reader turns it on; the detail pane and the lists do not.
	public var hidesTabBarOnScroll = false
	/// The selection menu's Add Bookmark, in the app's language (the host sets it: this file has no strings of its own).
	public var bookmarkMenuTitle = "Add Bookmark"
	/// Whether pulling past the top or bottom of the text goes to the previous or next chapter. The reader turns it off:
	/// a swipe left or right does that, and the pull fought with the bar hiding at the end of the text.
	public var pullChangesChapter = true
	private var barScrollRule = ScriptureBarScrollRule()
	public private(set) var topLength: CGFloat = 0
	public private(set) var bottomLength: CGFloat = 0

	/// The verse at the top of the visible area; starts at 1 per chapter.
	public private(set) var currentVerse = 1

	/// The underlying scroll view.
	public var scrollView: UIScrollView { textView }

	private let textView: ReaderTextView
	private let styler = ScriptureTextStyler()
	private var scripture: ScriptureText?
	private var currentTheme = ScriptureTextTheme()
	/// The styled text before any highlight, to put back what a highlight covered.
	private var baseText: NSAttributedString?
	/// The text on show (tests, and hosts that need to know what the screen holds).
	package var displayedText: String { scripture?.text ?? "" }

	/// Called for a tap on something interactive (a marker, a link, a verse number, a word with
	/// lexical data); plain text and taps while text is selected do not call it (plan D58).
	package var onTap: ((TapTarget) -> Void)?
	/// The SwiftUI `ScriptureViewer` listens through these (the contract's events, plan D157): the selection changed, an item the
	/// host added to the selection menu was chosen, and the scroll rule's wish for the host's bars (true: hide). The
	/// bars are the host's business: the view only asks.
	package var onSelectionChange: ((NSRange) -> Void)?
	package var menuItems: [ScriptureMenuItem] = []
	package var onMenuItem: ((String, NSRange) -> Void)?
	package var onChromeRequest: ((Bool) -> Void)?
	/// Asked before a tap on the text sends the bars away (see `ScriptureViewerEvents.canHideChrome`).
	package var canHideChrome: (() -> Bool)?
	/// The selection menu's Share (see `ScriptureViewerEvents.onShare`); without it the system's share sheet.
	package var onShare: ((String) -> Void)?
	private var lastLayoutSize = CGSize.zero
	private var lastReportedOffsetY: CGFloat = 0

	// The pull-to-navigate thresholds.
	private var pullThreshold: CGFloat {
		UIDevice.current.userInterfaceIdiom == .pad ? -130 : -65
	}

	public override init(frame: CGRect) {
		textView = ReaderTextView(usingTextLayoutManager: true)
		super.init(frame: frame)
		assert(textView.textLayoutManager != nil, "TextKit 2 unavailable — see plan §3")
		textView.isEditable = false
		textView.isSelectable = true
		textView.contentInsetAdjustmentBehavior = .never
		textView.textContainer.lineFragmentPadding = 0
		textView.delegate = self
		textView.accessibilityIdentifier = "scriptureText"   // for the UI tests, and for anything that must find the reading text
		textView.copyText = { [weak self] in self?.copiedSelection() }
		textView.frame = bounds
		textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		addSubview(textView)

		let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
		tap.delegate = self
		tap.cancelsTouchesInView = false
		textView.addGestureRecognizer(tap)
		installReaderGestures()
	}

	/// The tap target under a point of the text view's content, or nil.
	package func tapTarget(at point: CGPoint) -> TapTarget? {
		guard let scripture, !scripture.text.isEmpty else { return nil }
		let position = textView.closestPosition(to: point)
		guard let position else { return nil }
		let offset = textView.offset(from: textView.beginningOfDocument, to: position)
		// closestPosition snaps to the nearest character; only accept a tap that is on one, give or take a few points.
		// The caret may sit before or after the character tapped, and a tap in the slack beside a narrow character can snap
		// one further along, so try the characters around it.
		// A verse number or a note marker is a character or two wide and sits against a word, which may itself be
		// tappable (a word with Strong's numbers): within the slack the small target wins, so "1In" opens verse 1's menu.
		var word: TapTarget?
		for candidate in [offset, offset - 1, offset - 2, offset + 1] where candidate >= 0 && candidate < scripture.text.utf16.count {
			guard let rect = rectOfCharacter(atUTF16Offset: candidate), rect.insetBy(dx: -6, dy: -6).contains(point),
			      let target = scripture.tapTarget(atUTF16Offset: candidate) else { continue }
			if target.kind != .word { return target }
			// A word is taken as before (the caret's character or the one before it); others only when tapped squarely.
			if word == nil, candidate == offset || candidate == offset - 1 || rect.contains(point) { word = target }
		}
		return word
	}

	/// The rect of one character in the text view's content coordinates (tests and hit testing).
	package func rectOfCharacter(atUTF16Offset offset: Int) -> CGRect? {
		guard let start = textView.position(from: textView.beginningOfDocument, offset: offset),
		      let end = textView.position(from: start, offset: 1),
		      let range = textView.textRange(from: start, to: end) else { return nil }
		let rect = textView.firstRect(for: range)
		return rect.isNull || rect.isInfinite ? nil : rect
	}

	@objc private func handleTap(_ gesture: UITapGestureRecognizer) {
		guard gesture.state == .ended, textView.selectedRange.length == 0, let onTap else { return }
		if let target = tapTarget(at: gesture.location(in: textView)) {
			clearVerseFocus()          // a tap is as much a sign the reader is reading as a scroll is
			onTap(target)
		}
	}

	// MARK: Copy (plan D38, D76)

	/// The reference line for copied text: given the first and last verse, the host's name for them, e.g.
	/// "John 3:16–18 (KJV)", put above the copied text. Without it, copied text has no reference line.
	public var copyReference: ((Int, Int) -> String?)?

	/// The selected text as the reader copies it: the reference line, then the words without note letters, markers or
	/// joiners. Nil when nothing is selected.
	package func copiedSelection() -> String? {
		let range = textView.selectedRange
		guard let scripture, range.length > 0 else { return nil }
		return formatted(scripture.copiedText(utf16Start: range.location, length: range.length))
	}

	/// The first and last verse the selection touches, or nil when nothing is selected or it holds no verse.
	package func selectedVerses() -> ClosedRange<Int>? {
		let range = textView.selectedRange
		guard let scripture, range.length > 0, let verses = scripture.copiedText(utf16Start: range.location, length: range.length).verses
		else { return nil }
		return verses.lowerBound...verses.upperBound
	}

	private func formatted(_ copied: ScriptureText.CopiedText) -> String {
		guard let verses = copied.verses, let reference = copyReference?(verses.lowerBound, verses.upperBound),
		      !reference.isEmpty else { return copied.text }
		return reference + "\n" + copied.text
	}

	// MARK: Reader gestures (plan D76)

	/// The reader's gestures, in the order they are checked: a plain tap (which waits for a double tap to fail, so
	/// double-tapping a word still selects it), a two-finger tap, left and right swipes, a three-finger drag.
	package private(set) var readerGestures: [UIGestureRecognizer] = []
	private let doubleTapGuard = UITapGestureRecognizer()
	private let bottomEdgeTouch = UILongPressGestureRecognizer()
	private lazy var bottomEdgeHover = UIHoverGestureRecognizer()
	/// How far up from the bottom edge of the reader a touch brings the bar back, in points.
	package static let bottomEdgeZone: CGFloat = 120
	/// Whether the touch that started the current gesture began with text selected, or while the text was scrolling.
	private var touchBeganWithSelection = false
	private var touchBeganWhileScrolling = false
	private var threeFingerDragReported = false

	private func installReaderGestures() {
		doubleTapGuard.numberOfTapsRequired = 2
		doubleTapGuard.cancelsTouchesInView = false
		doubleTapGuard.delegate = self

		let plain = UITapGestureRecognizer(target: self, action: #selector(handlePlainTap(_:)))
		plain.require(toFail: doubleTapGuard)
		let twoFinger = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
		twoFinger.numberOfTouchesRequired = 2
		let left = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
		left.direction = .left
		let right = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
		right.direction = .right
		let threeFinger = UIPanGestureRecognizer(target: self, action: #selector(handleThreeFingerDrag(_:)))
		threeFinger.minimumNumberOfTouches = 3
		threeFinger.maximumNumberOfTouches = 3

		readerGestures = [plain, twoFinger, left, right, threeFinger]
		// A finger down near the bottom edge brings back a bar that scrolling hid; it only watches, the touch carries on.
		bottomEdgeTouch.minimumPressDuration = 0
		bottomEdgeTouch.cancelsTouchesInView = false
		bottomEdgeTouch.delegate = self
		bottomEdgeTouch.addTarget(self, action: #selector(handleBottomEdgeTouch(_:)))
		textView.addGestureRecognizer(bottomEdgeTouch)
		// A pointer (mouse or trackpad on the iPad) moving into the same zone does the same, with no touch.
		bottomEdgeHover.addTarget(self, action: #selector(handleBottomEdgeHover(_:)))
		bottomEdgeHover.delegate = self
		textView.addGestureRecognizer(bottomEdgeHover)
		for gesture in [doubleTapGuard] + readerGestures {
			gesture.delegate = self
			gesture.cancelsTouchesInView = false
			textView.addGestureRecognizer(gesture)
		}
	}

	@objc private func handlePlainTap(_ gesture: UITapGestureRecognizer) {
		guard gesture.state == .ended else { return }
		reportPlainTap(at: gesture.location(in: textView))
	}

	/// The rule for a plain tap, apart from the gesture so that tests can drive it.
	package func reportPlainTap(at point: CGPoint) {
		guard !touchBeganWithSelection, !touchBeganWhileScrolling, textView.selectedRange.length == 0 else { return }
		clearVerseFocus()          // a short chapter cannot scroll, so a tap on the text ends the focus too
		if let target = tapTarget(at: point), target.kind != .word { return }
		if hidesTabBarOnScroll, let onChromeRequest {
			let offset = Double(textView.contentOffset.y + textView.adjustedContentInset.top)
			if barScrollRule.hidden {
				// a tap brings the bar back
				barScrollRule.reset(at: offset)
				onChromeRequest(false)
			} else if CACurrentMediaTime() - barShownByTouchAt < Self.tapAfterShowWindow {
				// the same touch has just brought the bar back: leave it
			} else if !autoFullscreenMode, canHideChrome?() == true {
				// and a tap on the text sends it away (Automatic Fullscreen has its own tap, and a tap out of full
				// screen only leaves it: the host says so through `canHideChrome`)
				barScrollRule.forceHidden(at: offset)
				onChromeRequest(true)
			}
		}
		scriptureDelegate?.scriptureTextViewDidTapPlainText(self)
	}

	@objc private func handleBottomEdgeTouch(_ gesture: UILongPressGestureRecognizer) {
		guard gesture.state == .began else { return }
		showBarAfterEdgeTouch()
	}

	@objc private func handleBottomEdgeHover(_ gesture: UIHoverGestureRecognizer) {
		guard gesture.state == .began || gesture.state == .changed, isInBottomZone(gesture.location(in: self)) else { return }
		showBarAfterEdgeTouch()
	}

	private func isInBottomZone(_ point: CGPoint) -> Bool { point.y > bounds.height - Self.bottomEdgeZone }

	/// The rule for a touch in the bottom zone, apart from the gesture so that tests can drive it.
	package func showBarAfterEdgeTouch() {
		guard hidesTabBarOnScroll, barScrollRule.hidden, let onChromeRequest else { return }
		barScrollRule.reset(at: Double(textView.contentOffset.y + textView.adjustedContentInset.top))
		onChromeRequest(false)
		barShownByTouchAt = CACurrentMediaTime()
	}

	/// When a touch near the bottom brought the bar back as it went down. The tap that follows the same touch (it is
	/// recognised a moment after the finger lifts) must not hide the bar it just showed.
	package var barShownByTouchAt: CFTimeInterval = 0
	private static let tapAfterShowWindow: CFTimeInterval = 1.0

	@objc private func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
		guard gesture.state == .ended else { return }
		scriptureDelegate?.scriptureTextViewDidTapWithTwoFingers(self)
	}

	@objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
		guard gesture.state == .ended else { return }
		reportSwipe(left: gesture.direction == .left)
	}

	package func reportSwipe(left: Bool) {
		// A drag that started a selection, or one that moves selection handles, is not a swipe.
		guard !touchBeganWithSelection, textView.selectedRange.length == 0 else { return }
		if left { scriptureDelegate?.scriptureTextViewDidSwipeLeft(self) } else { scriptureDelegate?.scriptureTextViewDidSwipeRight(self) }
	}

	@objc private func handleThreeFingerDrag(_ gesture: UIPanGestureRecognizer) {
		switch gesture.state {
		case .began: threeFingerDragReported = false
		case .changed: reportThreeFingerDrag(verticalDistance: gesture.translation(in: textView).y)
		default: break
		}
	}

	package func reportThreeFingerDrag(verticalDistance: CGFloat) {
		guard !threeFingerDragReported, abs(verticalDistance) >= 100 else { return }
		threeFingerDragReported = true
		scriptureDelegate?.scriptureTextViewDidDragWithThreeFingers(self)
	}

	/// Starts a new three-finger drag (tests; the gesture does this itself).
	package func resetThreeFingerDrag() { threeFingerDragReported = false }

	@available(*, unavailable)
	package required init?(coder: NSCoder) { fatalError("not used") }

	// MARK: Content

	public func display(_ scripture: ScriptureText, theme: ScriptureTextTheme) {
		self.scripture = scripture
		style(theme)
		currentVerse = 1
		lastReportedOffsetY = 0
		// A new chapter starts at its top. Without this, text laid out before the view had
		// its final size (zero width wraps every character) leaves the offset part-way down.
		textView.layoutIfNeeded()
		textView.setContentOffset(CGPoint(x: 0, y: -topLength), animated: false)
		reportedEnd = false
		// Text that fits the screen has been read to its end as soon as it shows. The text view measures its text as it is laid
		// out (laying it out here would move the offset), so look again shortly after, for text not yet measured.
		for delay in [0.0, 0.15, 0.5] {
			DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.reportEndIfAtBottom(userDriven: false) }
		}
	}

	/// The text on show in another theme (night mode, a font, a size): styled again where the reader is, not from its top. The
	/// verse at the top stays at the top, the very top (heading and all) stays the very top, and an end once reached stays
	/// reached. The focus, the selection and the highlights go, as for a new text; the host paints its highlights again.
	package func restyle(theme: ScriptureTextTheme) {
		guard scripture != nil else { return }
		let atTop = textView.contentOffset.y <= -topLength + 1
		let verse = currentVerse
		style(theme)
		measureWholeText()
		if atTop {
			textView.setContentOffset(CGPoint(x: 0, y: -topLength), animated: false)
		} else {
			scrollToVerse(verse, animated: false)
		}
		currentVerse = verse
		// Report the place even when the offset did not move (the scroll callback only reports a move).
		lastReportedOffsetY = max(textView.contentOffset.y + topLength, 0)
		scriptureDelegate?.scriptureTextViewScrollHappened(self, newOffsetY: lastReportedOffsetY)
	}

	/// Styles the text on show in a theme's fonts and colours, with nothing marked until the host says so. The scroll is the caller's.
	private func style(_ theme: ScriptureTextTheme) {
		guard let scripture else { return }
		currentTheme = theme
		bookmarkHighlights = []
		searchHighlights = []
		highlights = []
		paintedHighlights = []
		focusedVerse = nil
		dimmedRanges = []
		let styled = styler.attributedString(for: scripture, theme: theme)
		baseText = styled
		textView.attributedText = styled
		textView.backgroundColor = theme.backgroundColor
		backgroundColor = theme.backgroundColor
		applySideInsets()
	}

	// MARK: Reaching the end

	/// Whether the end of the current text has been reported; cleared by `display`.
	private var reportedEnd = false
	/// How close to the bottom counts as the end, in points: the last line is in view.
	private static let endSlack: CGFloat = 40

	/// Reports the end of the text once: when the text fits the view, or when the reader has scrolled to the bottom
	/// (`userDriven`: a scroll by the reader, not the view putting the text in place).
	package func reportEndIfAtBottom(userDriven: Bool) {
		guard !reportedEnd, scripture != nil, textView.bounds.height > 0 else { return }
		let content = textView.contentSize.height
		guard content > 0 else { return }
		let visibleBottom = textView.contentOffset.y + textView.bounds.height - textView.adjustedContentInset.bottom
		let fits = content + textView.adjustedContentInset.top + textView.adjustedContentInset.bottom <= textView.bounds.height + 1
		guard fits || (userDriven && visibleBottom >= content - Self.endSlack) else { return }
		reportedEnd = true
		scriptureDelegate?.scriptureTextViewReachedEnd(self)
	}

	// MARK: Highlights (plan D38)

	/// What is marked now, kept so a restyle can paint it again.
	private var highlights: [Highlight] = []
	private var paintedHighlights: [ResolvedHighlight] = []
	/// Whatever the host last asked for, by source, so bookmarks and a search can come and go separately.
	private var bookmarkHighlights: [Highlight] = []
	private var searchHighlights: [Highlight] = []

	/// Bookmarked verses, each in its folder's colour (`#RRGGBB`, or empty for none). Replaces the
	/// previous bookmark highlights; search highlights stay.
	public func setBookmarkHighlights(verses: [NSNumber], hexColours: [String]) {
		bookmarkHighlights = zip(verses, hexColours).map { verse, hex in
			Highlight(.verse(verse.intValue), style: .bookmark(colour: hex.isEmpty ? nil : hex))
		}
		applyHighlights()
	}

	/// Marks every occurrence of the words of a search, ignoring case. An empty list clears it.
	public func highlightSearchTerms(_ terms: [String]) {
		searchHighlights = scripture?.searchHits(for: terms) ?? []
		applyHighlights()
	}

	/// Marks the words that carry a Strong's number, after a Strong's search (plan D76).
	public func highlightStrongs(_ number: String) {
		searchHighlights = scripture?.strongsHits(for: number) ?? []
		applyHighlights()
	}

	package func clearHighlights() {
		bookmarkHighlights = []
		searchHighlights = []
		applyHighlights()
	}

	/// Paints the highlights as a background and a text colour on the text storage: the text and
	/// its layout are untouched, so nothing is rebuilt and the selection and scroll position stay
	/// as they are. (TextKit 2's rendering attributes were tried first: the layout manager drops
	/// them whenever it invalidates and UITextView does not redraw when they are added.)
	private func applyHighlights() {
		highlights = bookmarkHighlights + searchHighlights
		guard let scripture, let base = baseText else { return }
		let storage = textView.textStorage
		let length = storage.length
		storage.beginEditing()
		// Undim, then dim again around the verse in focus (plan D78): the text outside it at a third of its colour.
		for range in dimmedRanges where NSMaxRange(range) <= length {
			base.enumerateAttribute(.foregroundColor, in: range) { value, run, _ in
				storage.addAttribute(.foregroundColor, value: value ?? currentTheme.textColor, range: run)
			}
		}
		dimmedRanges = []
		if let focused = focusedVerse, let verse = scripture.verseRange(containing: focused) {
			let end = min(verse.start + verse.length, length)
			dimmedRanges = [NSRange(location: 0, length: min(verse.start, length)), NSRange(location: end, length: length - end)]
				.filter { $0.length > 0 }
			for range in dimmedRanges {
				base.enumerateAttribute(.foregroundColor, in: range) { value, run, _ in
					let colour = (value as? UIColor) ?? currentTheme.textColor
					storage.addAttribute(.foregroundColor, value: colour.withAlphaComponent(0.35), range: run)
				}
			}
		}
		// Back to the styled text where the last highlights were, then the new ones.
		for old in paintedHighlights where old.start + old.length <= length {
			let range = NSRange(location: old.start, length: old.length)
			storage.removeAttribute(.backgroundColor, range: range)
			base.enumerateAttribute(.foregroundColor, in: range) { value, run, _ in
				storage.addAttribute(.foregroundColor, value: value ?? currentTheme.textColor, range: run)
			}
		}
		paintedHighlights = scripture.resolve(highlights)
		for highlight in paintedHighlights where highlight.start + highlight.length <= length {
			storage.addAttributes(currentTheme.highlightAttributes(for: highlight.style),
			                      range: NSRange(location: highlight.start, length: highlight.length))
		}
		storage.endEditing()
	}

	/// The text that will be drawn on a highlight background (tests).
	package func highlightedStrings() -> [String] {
		guard let scripture else { return [] }
		return paintedHighlights.sorted { $0.start < $1.start }
			.compactMap { scripture.substring(utf16Start: $0.start, length: $0.length) }
	}

	/// The ranges painted now (tests).
	package var paintedHighlightRanges: [ResolvedHighlight] { paintedHighlights }

	/// RTL modules: flipped layout direction (plan Phase 4).
	public var rightToLeft = false {
		didSet {
			semanticContentAttribute = rightToLeft ? .forceRightToLeft : .unspecified
			textView.semanticContentAttribute = semanticContentAttribute
			textView.textAlignment = .natural
		}
	}

	// MARK: Verse geometry (TextKit 2)

	/// The rect of a verse's first line, in the text view's content
	/// coordinates, after ensuring layout up to the verse (plan §3).
	package func rectOfVerse(_ verse: Int) -> CGRect? {
		guard let scripture,
		      let range = scripture.verseRange(containing: verse),   // a verse of a bridge scrolls to the bridge
		      let layoutManager = textView.textLayoutManager,
		      let contentManager = layoutManager.textContentManager
		else { return nil }
		let documentStart = contentManager.documentRange.location
		guard let start = contentManager.location(documentStart, offsetBy: range.start),
		      let end = contentManager.location(start, offsetBy: range.length),
		      let textRange = NSTextRange(location: start, end: end),
		      let fromStart = NSTextRange(location: documentStart, end: end)
		else { return nil }

		layoutManager.ensureLayout(for: fromStart)
		var rect: CGRect?
		layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
			rect = frame
			return false   // the first segment is the verse's first line
		}
		guard var result = rect else { return nil }
		result.origin.y += textView.textContainerInset.top
		result.origin.x += textView.textContainerInset.left
		return result
	}

	/// Where a verse's first line is on screen, in `view`'s coordinates (the window's when nil): for a menu or a share sheet that
	/// comes from the verse. Nil when the text has no such verse.
	package func frameOfVerse(_ verse: Int, in view: UIView?) -> CGRect? {
		rectOfVerse(verse).map { textView.convert($0, to: view) }
	}

	/// Scrolls so the verse's first line sits at the top of the visible area
	/// (under any bars described by `topLength`).
	// MARK: Verse focus (plan D78)

	/// The verse brought into view by navigation, shown at full strength with the rest dimmed until the reader
	/// scrolls. Nil when nothing is in focus.
	package private(set) var focusedVerse: Int?
	private var dimmedRanges: [NSRange] = []

	/// Goes to a verse the reader asked for: near the top with a little space above it (as far as the text allows,
	/// so a short chapter does not scroll past its end), and dims the text around it until the reader scrolls.
	public func focusVerse(_ verse: Int) {
		measureWholeText()
		guard let rect = rectOfVerse(verse) else { return }
		let visible = textView.bounds.height - topLength - bottomLength
		let spacing = min(max(visible * 0.12, 24), 96)
		var y = rect.minY - topLength - spacing
		let maxY = max(textView.contentSize.height - textView.bounds.height + bottomLength, -topLength)
		y = min(max(y, -topLength), maxY)
		textView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
		currentVerse = verse
		focusedVerse = verse
		applyHighlights()
	}

	/// The verse in focus, or 0 (Objective-C).
	public var focusedVerseNumber: Int { focusedVerse ?? 0 }

	/// Ends the focus: everything back to its own colour.
	package func clearVerseFocus() {
		guard focusedVerse != nil else { return }
		focusedVerse = nil
		applyHighlights()
	}

	/// The ranges dimmed now (tests).
	package var dimmedTextRanges: [NSRange] { dimmedRanges }

	public func scrollToVerse(_ verse: Int, animated: Bool) {
		measureWholeText()
		guard let rect = rectOfVerse(verse) else { return }
		var y = rect.minY - topLength
		let maxY = max(textView.contentSize.height - textView.bounds.height + bottomLength, -topLength)
		y = min(max(y, -topLength), maxY)
		textView.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
		currentVerse = verse
	}

	/// Lays out the whole text, so `contentSize` is its real height. TextKit 2 otherwise estimates the height of what it has not
	/// laid out, and a scroll further down than the estimate stops at its end: a jump to verse 30 of a 40-verse chapter stopped
	/// about a third of the way short while reporting verse 30. Called before every scroll the host asks for; the layout is
	/// kept, so a second call costs next to nothing.
	private func measureWholeText() {
		// A layout still pending (new text, a new width) first: run after the measuring, it would put the estimate back.
		textView.layoutIfNeeded()
		guard let layoutManager = textView.textLayoutManager, let contentManager = layoutManager.textContentManager else { return }
		layoutManager.ensureLayout(for: contentManager.documentRange)
		// The text view does not always take the measured height (after new text it keeps the estimate until the reader scrolls),
		// so it is given it.
		let height = (layoutManager.usageBoundsForTextContainer.maxY + textView.textContainerInset.top + textView.textContainerInset.bottom).rounded(.up)
		if textView.contentSize.height < height {
			textView.contentSize = CGSize(width: textView.contentSize.width, height: height)
		}
	}

	/// The verse whose text crosses the top of the visible area.
	package func verseAtTop() -> Int {
		guard let scripture, !scripture.verses.isEmpty,
		      let layoutManager = textView.textLayoutManager,
		      let contentManager = layoutManager.textContentManager
		else { return 1 }
		let topPoint = CGPoint(x: 1, y: max(textView.contentOffset.y + topLength - textView.textContainerInset.top, 0))
		guard let fragment = layoutManager.textLayoutFragment(for: topPoint) else { return scripture.verses.last!.verse }
		let offset = contentManager.offset(from: contentManager.documentRange.location,
		                                   to: fragment.rangeInElement.location)
		var verse = scripture.verses.first!.verse
		for range in scripture.verses where range.start <= offset {
			verse = range.verse
		}
		return verse
	}

	// MARK: For the SwiftUI viewer

	/// What is selected, as UTF-16 offsets and the verses it touches, or nil when nothing is.
	package func selection(for range: NSRange) -> ScriptureSelection? {
		guard let scripture, range.length > 0 else { return nil }
		let verses = scripture.copiedText(utf16Start: range.location, length: range.length).verses
		return ScriptureSelection(start: range.location, length: range.length, verses: verses)
	}

	package var selectedRange: NSRange { textView.selectedRange }

	package func clearSelection() { textView.selectedRange = NSRange(location: 0, length: 0) }

	/// Scrolls so that `offset` (as `onScroll` reports it) is at the top.
	package func scroll(toOffset offset: CGFloat, animated: Bool) {
		measureWholeText()
		let maxY = max(-topLength, textView.contentSize.height - textView.bounds.size.height + bottomLength)
		textView.setContentOffset(CGPoint(x: 0, y: min(offset - topLength, maxY)), animated: animated)
	}

	/// The height the text needs at `width`: for a viewer that sizes to its text (a note in a pane) instead of scrolling.
	package func fittingHeight(width: CGFloat) -> CGFloat {
		textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
	}

	// MARK: Refresh insets

	public func setupRefreshViews(_ top: CGFloat, bottom: CGFloat) {
		topLength = top
		bottomLength = bottom
		let insets = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
		textView.contentInset = insets
		textView.scrollIndicatorInsets = insets
	}

	package func removeRefreshViews() {
		topLength = 0
		bottomLength = 0
		textView.contentInset = .zero
		textView.scrollIndicatorInsets = .zero
	}

	// MARK: Side margins (plan D83)

	/// The text's margin from each side: the old web view's 10 pt on iPad, and 16 pt on iPhone, where it had none and
	/// the text ran to the screen's edge.
	package static func sideMargin(isPad: Bool) -> CGFloat { isPad ? 10 : 16 }

	/// The margin plus the side safe area, so that in landscape the text also clears the sensor housing.
	private func applySideInsets() {
		let margin = Self.sideMargin(isPad: currentTheme.isPad)
		let insets = UIEdgeInsets(top: 0, left: margin + safeAreaInsets.left, bottom: 0, right: margin + safeAreaInsets.right)
		if textView.textContainerInset != insets { textView.textContainerInset = insets }
	}

	public override func safeAreaInsetsDidChange() {
		super.safeAreaInsetsDidChange()
		applySideInsets()
	}

	// MARK: Re-anchor on bounds change (plan U2)

	public override func layoutSubviews() {
		super.layoutSubviews()
		if bounds.size != lastLayoutSize {
			let hadLaidOut = lastLayoutSize != .zero
			lastLayoutSize = bounds.size
			// At the very top, stay there: verse 1's first line lies below any chapter or
			// psalm heading, so re-anchoring to verse 1 would scroll the heading away.
			let atTop = textView.contentOffset.y <= -topLength + 1
			if hadLaidOut && scripture != nil && atTop {
				textView.layoutIfNeeded()
				textView.setContentOffset(CGPoint(x: 0, y: -topLength), animated: false)
			} else if hadLaidOut && scripture != nil {
				// The text view re-wraps its text (and updates contentSize) in
				// its own layout pass; without that the verse rect and the
				// scroll clamp would both come from the old geometry.
				textView.layoutIfNeeded()
				scrollToVerse(currentVerse, animated: false)
			}
		}
	}
}

extension ScriptureTextView: UIGestureRecognizerDelegate {
	/// Alongside the text view's own selection and scrolling gestures, never instead of them.
	public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
	                       shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

	/// Notes, as each touch starts, whether text was selected or the text was moving (a tap that stops a scroll, or
	/// one that clears a selection, is not a plain tap).
	public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
		if gestureRecognizer === bottomEdgeTouch {
			return hidesTabBarOnScroll && barScrollRule.hidden && isInBottomZone(touch.location(in: self))
		}
		if readerGestures.contains(gestureRecognizer) {
			touchBeganWithSelection = textView.selectedRange.length > 0
			touchBeganWhileScrolling = textView.isDecelerating
		}
		return true
	}
}

// MARK: - Scroll reporting

extension ScriptureTextView: UITextViewDelegate {

	/// The selection menu, with the system's Share item replaced by one that shares the text as copied (the words
	/// and the reference line, plan D77), not the raw characters with their joiners and markers.
	public func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
	              suggestedActions: [UIMenuElement]) -> UIMenu? {
		guard copiedSelection() != nil else { return nil }
		var actions = replacingShare(in: suggestedActions)
		if scriptureDelegate?.scriptureTextViewOffersBookmark(self) == true, let verses = selectedVerses() {
			actions.insert(UIAction(title: bookmarkMenuTitle, image: UIImage(systemName: "bookmark")) { [weak self] _ in
				guard let self else { return }
				self.scriptureDelegate?.scriptureTextView(self, bookmarkVersesFrom: verses.lowerBound, to: verses.upperBound)
			}, at: 0)
		}
		for item in menuItems.reversed() {
			actions.insert(UIAction(title: item.title) { [weak self] _ in
				guard let self else { return }
				self.onMenuItem?(item.id, self.textView.selectedRange)
			}, at: 0)
		}
		return UIMenu(children: actions)
	}

	public func textViewDidChangeSelection(_ textView: UITextView) {
		onSelectionChange?(textView.selectedRange)
	}

	package func replacingShare(in elements: [UIMenuElement]) -> [UIMenuElement] {
		elements.map { element in
			if let menu = element as? UIMenu {
				return menu.replacingChildren(replacingShare(in: menu.children))
			}
			if let command = element as? UICommand, NSStringFromSelector(command.action).lowercased().contains("share") {
				return UIAction(title: command.title, image: command.image) { [weak self] _ in self?.shareSelection() }
			}
			return element
		}
	}

	private func shareSelection() {
		guard let text = copiedSelection() else { return }
		if let onShare {
			onShare(text)
			return
		}
		var responder: UIResponder? = self
		while let next = responder?.next, !(next is UIViewController) { responder = next }
		guard let controller = responder?.next as? UIViewController else { return }
		let share = UIActivityViewController(activityItems: [text], applicationActivities: nil)
		if let popover = share.popoverPresentationController {
			popover.sourceView = textView
			if let range = textView.selectedTextRange {
				popover.sourceRect = textView.firstRect(for: range)
			}
		}
		controller.present(share, animated: true)
	}

	public func scrollViewDidScroll(_ scrollView: UIScrollView) {
		var newOffsetY = scrollView.contentOffset.y + topLength
		if newOffsetY < 0 { newOffsetY = 0 }
		if hidesTabBarOnScroll, scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating {
			let maxOffset = Double(scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
			if scrollView.isTracking, isInBottomZone(scrollView.panGestureRecognizer.location(in: self)) {
				// A finger dragged down into the bar's area wants the bar, not the scroll rule.
				showBarAfterEdgeTouch()
			} else if let hide = barScrollRule.update(offset: Double(scrollView.contentOffset.y + scrollView.adjustedContentInset.top), maxOffset: maxOffset) {
				onChromeRequest?(hide)
			}
		}
		reportEndIfAtBottom(userDriven: scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating)
		if abs(lastReportedOffsetY - newOffsetY) > 2 {
			lastReportedOffsetY = newOffsetY
			// Only user-driven scrolling moves the tracked verse. Geometry
			// changes (rotation, resize) also fire this callback, and reading
			// the verse mid-relayout would clobber the re-anchor target.
			if scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating {
				currentVerse = verseAtTop()
				clearVerseFocus()          // the reader moved the text: the focus has done its job
			}
			scriptureDelegate?.scriptureTextViewScrollHappened(self, newOffsetY: newOffsetY)
		}
	}

	public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
		if pullChangesChapter, scrollView.contentOffset.y < pullThreshold {
			scriptureDelegate?.scriptureTextViewTopReloadTriggered(self)
		} else {
			let bottomMax = scrollView.contentSize.height - scrollView.frame.size.height
			if pullChangesChapter, scrollView.contentOffset.y > bottomMax - pullThreshold {
				scriptureDelegate?.scriptureTextViewBottomReloadTriggered(self)
			} else if autoFullscreenMode {
				scriptureDelegate?.switchToFullscreen()
			}
		}
	}
}

/// The text view behind the reader: Copy takes the text from the model, not the characters on screen.
package final class ReaderTextView: UITextView {
	package var copyText: (() -> String?)?

	package override func copy(_ sender: Any?) {
		guard let text = copyText?() else { return super.copy(sender) }
		UIPasteboard.general.string = text
	}
}

#endif
