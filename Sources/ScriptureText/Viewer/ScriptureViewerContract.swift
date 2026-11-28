// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Observation

// The contract between a host app and a scripture viewer. Foundation only, so the same names can be implemented on iOS (UIKit,
// TextKit 2) and on Android (Compose): each platform supplies a `ScriptureViewer` view that takes these values, and the host is
// written once. The reader draws and scrolls text and reports; it opens no screen, resolves no lookup and keeps no preference.

/// How the text looks. A value, not a platform theme: each platform turns it into its own fonts and colours.
/// The page the text is on by day (0.2.8): white, sepia (a light brown) or grey. Night mode keeps its black page whatever is chosen. Each
/// page has its own text colour, and on sepia and grey the red letters, the markers and the links are a shade deeper, so that each reads
/// at least as well as it does on white. Colours are `#RRGGBB`, the same on every platform.
public enum ScriptureViewerPage: String, Sendable, CaseIterable {
    case white
    case sepia
    case grey

    public var backgroundHex: String {
        switch self {
        case .white: return "#FFFFFF"
        case .sepia: return "#F4ECD8"
        case .grey: return "#E6E6E6"
        }
    }

    public var textHex: String {
        switch self {
        case .white: return "#000000"
        case .sepia: return "#5B4636"
        case .grey: return "#1C1C1E"
        }
    }

    /// The words of Christ.
    public var redLetterHex: String { self == .white ? "#D03030" : "#B42828" }
    /// Strong's, morphology, footnote and cross-reference markers.
    public var markerHex: String { self == .white ? "#808080" : "#707070" }
    public var linkHex: String { self == .white ? "#FF00FF" : "#C000C0" }
}

public struct ScriptureViewerTheme: Equatable, Sendable {
    public var nightMode: Bool
    /// The page by day; night mode ignores it.
    public var page: ScriptureViewerPage
    public var fontName: String
    /// In CSS points, as the preference stores it.
    public var fontSize: Double
    /// The wider layout: an iPad, or a tablet.
    public var isWide: Bool
    public var rightToLeft: Bool
    /// Replaces the classic rules when set.
    public var styleSheet: ScriptureStyleSheet?

    public init(nightMode: Bool = false, fontName: String = "Helvetica Neue", fontSize: Double = 14, isWide: Bool = false,
                rightToLeft: Bool = false, styleSheet: ScriptureStyleSheet? = nil, page: ScriptureViewerPage = .white) {
        self.nightMode = nightMode
        self.page = page
        self.fontName = fontName
        self.fontSize = fontSize
        self.isWide = isWide
        self.rightToLeft = rightToLeft
        self.styleSheet = styleSheet
    }
}

/// What is marked in the text, apart from the selection.
public struct ScriptureHighlights: Equatable, Sendable {
    public struct Verse: Equatable, Sendable {
        public var verse: Int
        public var hexColour: String
        public init(verse: Int, hexColour: String) {
            self.verse = verse
            self.hexColour = hexColour
        }
    }
    /// A bookmark's verses, each in its folder's colour.
    public var bookmarks: [Verse]
    /// The words of the search a result was chosen from.
    public var searchTerms: [String]
    /// A Strong's number whose words are marked.
    public var strongs: String?

    public init(bookmarks: [Verse] = [], searchTerms: [String] = [], strongs: String? = nil) {
        self.bookmarks = bookmarks
        self.searchTerms = searchTerms
        self.strongs = strongs
    }
}

/// An item the host adds to the selection menu (Add Bookmark, Copy verses…). The reader shows it and reports the choice.
public struct ScriptureMenuItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// How the reader is set up. Everything has a sensible default.
public struct ScriptureViewerConfiguration: Equatable, Sendable {
    /// Space the host's bars cover, which the text scrolls under and keeps clear of.
    public var topInset: Double
    public var bottomInset: Double
    /// Scrolls itself (a chapter), or sizes to its text (a note in a pane).
    public var scrolls: Bool
    /// A pull past the top or the end asks for the previous or the next chapter.
    public var pullChangesChapter: Bool
    /// Items added to the selection menu, in order, where the platform puts its own.
    public var menuItems: [ScriptureMenuItem]
    /// Report `dragEnded` when the reader lets go of a drag that did not pull past an end (Automatic Fullscreen goes fullscreen on it).
    public var reportsDragEnd: Bool
    /// The host shows its own menu for a selection: the platform's selection menu (and `menuItems` in it) is not shown, and
    /// `onSelectionMenu` is sent when it would have been. iOS only so far; Android keeps its own menu.
    public var hostSelectionMenu: Bool

    public init(topInset: Double = 0, bottomInset: Double = 0, scrolls: Bool = true, pullChangesChapter: Bool = false,
                menuItems: [ScriptureMenuItem] = [], reportsDragEnd: Bool = false, hostSelectionMenu: Bool = false) {
        self.topInset = topInset
        self.bottomInset = bottomInset
        self.scrolls = scrolls
        self.pullChangesChapter = pullChangesChapter
        self.menuItems = menuItems
        self.reportsDragEnd = reportsDragEnd
        self.hostSelectionMenu = hostSelectionMenu
    }
}

/// What the reader has selected: UTF-16 offsets into the text, and the verses they touch.
public struct ScriptureSelection: Equatable, Sendable {
    public var start: Int
    public var length: Int
    public var verses: ClosedRange<Int>?
    public init(start: Int, length: Int, verses: ClosedRange<Int>?) {
        self.start = start
        self.length = length
        self.verses = verses
    }
}

/// Gestures the host may give a meaning to (fullscreen, next chapter, the module list). A plain tap is one on text that is not a
/// tap target; a tap on a verse number, a word or a link is `onTap`.
public enum ScriptureViewerGesture: Sendable {
    case plainTap, twoFingerTap, swipeLeft, swipeRight, threeFingerDrag
    /// The reader let go of a drag (only reported when the configuration asks for it).
    case dragEnded
}

public enum ScriptureViewerPull: Sendable {
    case previousChapter, nextChapter
}

/// The reader's wish for the host's bars: sent as the text scrolls (the rule that down hides and up shows), when a tap on the text sends
/// them away or a tap or a touch near the bottom brings them back. The host decides whether to obey.
public enum ScriptureViewerChromeRequest: Sendable {
    case show, hide
}

/// What the reader reports. Every one is optional; all run on the main actor.
public struct ScriptureViewerEvents: Sendable {
    /// Scrolled: the offset and the verse at the top.
    public var onScroll: (@MainActor @Sendable (_ offset: Double, _ verse: Int) -> Void)?
    /// The last of the text came into view (a reading plan counts a day as read from it).
    public var onReachedEnd: (@MainActor @Sendable () -> Void)?
    /// A tap on a verse number, a word, a note letter or a link, with where it was and what the markup said about it.
    public var onTap: (@MainActor @Sendable (TapTarget) -> Void)?
    public var onGesture: (@MainActor @Sendable (ScriptureViewerGesture) -> Void)?
    public var onPull: (@MainActor @Sendable (ScriptureViewerPull) -> Void)?
    public var onChromeRequest: (@MainActor @Sendable (ScriptureViewerChromeRequest) -> Void)?
    /// The selection changed (nil: nothing is selected).
    public var onSelectionChange: (@MainActor @Sendable (ScriptureSelection?) -> Void)?
    /// A menu item of the configuration was chosen, with the selection it was chosen on.
    public var onMenuItem: (@MainActor @Sendable (_ id: String, _ selection: ScriptureSelection) -> Void)?
    /// The platform would show its selection menu now (the reader has finished selecting), and the configuration's `hostSelectionMenu`
    /// asks the host to show its own: the selection it is for. On iOS the controller's `frameOfSelection()` says where it is.
    public var onSelectionMenu: (@MainActor @Sendable (_ selection: ScriptureSelection) -> Void)?

    /// Asked, not told: whether the bars may be sent away by a tap on the text (the host has bars, none is hidden for another reason such as full
    /// screen or an open pane). Without an answer the viewer never hides the bars by a tap; it still follows the scroll rule. The iOS viewer
    /// no longer asks (0.2.8): its bars follow the scroll and a push past the end, not a tap. The Android viewer still asks.
    public var canHideChrome: (@MainActor @Sendable () -> Bool)?
    /// The selection menu's Share was chosen: the text as the reader copies it. Without this the viewer shows its platform's own share sheet.
    public var onShare: (@MainActor @Sendable (_ text: String) -> Void)?

    /// Asked, not told: the reference line put above copied text for these verses ("John 3:16–18 (KJV)"), or nil for none.
    public var referenceLine: (@MainActor @Sendable (_ verses: ClosedRange<Int>) -> String?)?

    public init() {}
}

/// The platform view implements this; the controller forwards to it.
@MainActor
public protocol ScriptureViewerDriver: AnyObject {
    func scroll(toVerse verse: Int, animated: Bool)
    func scroll(toOffset offset: Double, animated: Bool)
    func focus(verse: Int)
    func clearFocus()
    func clearSelection()
}

/// What the host holds on to: commands for the reader, and what the reader last said, observable by the host's views.
///
/// A view applies a new text a moment after the host sets it (SwiftUI and Compose both update state on their next turn), so commands the host
/// sends in between would act on the old text. The host says `willShowNewText()` when it changes the text or the theme; commands are then held
/// until the view says `textWasShown()`, and run in order.
@MainActor
@Observable
public final class ScriptureViewerController {
    public private(set) var currentVerse = 0
    public private(set) var scrollOffset = 0.0
    public private(set) var selection: ScriptureSelection?
    public private(set) var focusedVerse: Int?
    public private(set) var isAtEnd = false

    /// Set by the platform view when it is made.
    public weak var driver: ScriptureViewerDriver?

    private var awaitingText = false
    private var held: [(ScriptureViewerDriver) -> Void] = []

    public init() {}

    public func scroll(toVerse verse: Int, animated: Bool = false) { send { $0.scroll(toVerse: verse, animated: animated) } }
    public func scroll(toOffset offset: Double, animated: Bool = false) { send { $0.scroll(toOffset: offset, animated: animated) } }
    public func focus(verse: Int) { focusedVerse = verse; send { $0.focus(verse: verse) } }
    public func clearFocus() { focusedVerse = nil; send { $0.clearFocus() } }
    public func clearSelection() { send { $0.clearSelection() } }

    private func send(_ command: @escaping (ScriptureViewerDriver) -> Void) {
        if awaitingText {
            held.append(command)
        } else if let driver {
            command(driver)
        }
    }

    /// The host is about to change the text or the theme: hold commands until it is on show. Commands held for an earlier text are dropped.
    public func willShowNewText() {
        awaitingText = true
        held.removeAll()
        focusedVerse = nil
    }

    /// The platform view has put the text on show: run what was held.
    public func textWasShown() {
        guard awaitingText else { return }
        awaitingText = false
        let commands = held
        held.removeAll()
        guard let driver else { return }
        for command in commands { command(driver) }
    }

    // The platform view reports through these.
    public func update(scrollOffset: Double, verse: Int, atEnd: Bool) {
        self.scrollOffset = scrollOffset
        currentVerse = verse
        isAtEnd = atEnd
    }
    public func update(selection: ScriptureSelection?) { self.selection = selection }
}
