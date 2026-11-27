// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if SKIP

// On Android the viewer is the Compose one, `scripture.viewer.compose.ScriptureViewer` (`Android/scriptureviewer`, its Kotlin linked into
// `Skip/`), which a native Android app calls directly. This module needs no SkipUI for it. A Skip app whose shared screens are SwiftUI
// names the viewer through the `ScriptureViewerSkipUI` product, the same SwiftUI view as the iOS one below.

#elseif canImport(UIKit)

import SwiftUI
import UIKit
import ScriptureText

/// The scripture viewer, as a SwiftUI view (plan D157, ScriptureViewerContract.md): the iOS realisation of the contract. It takes the text
/// and the values of the contract and reports through its events; the TextKit 2 text view (`ScriptureTextView`) does the drawing
/// underneath. It opens no screen, resolves no lookup and reads no preference: the host does.
///
/// ```
/// ScriptureViewer(text: chapter, theme: theme, highlights: marks, configuration: setup, controller: controller, events: events)
/// ```
public struct ScriptureViewer: UIViewRepresentable {

    var text: ScriptureText
    var theme: ScriptureViewerTheme
    var highlights: ScriptureHighlights
    var configuration: ScriptureViewerConfiguration
    var controller: ScriptureViewerController?
    var events: ScriptureViewerEvents

    public init(text: ScriptureText, theme: ScriptureViewerTheme = ScriptureViewerTheme(), highlights: ScriptureHighlights = ScriptureHighlights(),
                configuration: ScriptureViewerConfiguration = ScriptureViewerConfiguration(), controller: ScriptureViewerController? = nil,
                events: ScriptureViewerEvents = ScriptureViewerEvents()) {
        self.text = text
        self.theme = theme
        self.highlights = highlights
        self.configuration = configuration
        self.controller = controller
        self.events = events
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeUIView(context: Context) -> ScriptureTextView {
        let view = ScriptureTextView(frame: .zero)
        context.coordinator.bridge.attach(view)
        return view
    }

    public func updateUIView(_ view: ScriptureTextView, context: Context) {
        context.coordinator.bridge.apply(self, to: view)
    }

    /// A viewer that does not scroll takes the height its text needs at the width it is offered.
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView view: ScriptureTextView, context: Context) -> CGSize? {
        guard !configuration.scrolls, let width = proposal.width else { return nil }
        return CGSize(width: width, height: view.fittingHeight(width: width) + configuration.topInset + configuration.bottomInset)
    }

    /// Holds what turns the text view's reports into the contract's events, and the controller's commands into the text view's calls.
    @MainActor
    public final class Coordinator {
        fileprivate let bridge = Bridge()
    }

    @MainActor
    fileprivate final class Bridge: NSObject, ScriptureTextViewDelegate, ScriptureViewerDriver {

        fileprivate weak var view: ScriptureTextView?
        private var events = ScriptureViewerEvents()
        private var controller: ScriptureViewerController?
        private var shown: (text: ScriptureText, theme: ScriptureViewerTheme)?
        private var painted: ScriptureHighlights?
        private var insets: (top: Double, bottom: Double)?
        private var shownNow = false

        func attach(_ view: ScriptureTextView) {
            self.view = view
            view.scriptureDelegate = self
            view.onTap = { [weak self] target in self?.events.onTap?(target) }
            view.onSelectionChange = { [weak self] range in self?.selectionChanged(range) }
            view.onMenuItem = { [weak self] id, range in
                guard let self, let selection = self.view?.selection(for: range) else { return }
                self.events.onMenuItem?(id, selection)
            }
            view.onSelectionMenu = { [weak self] range in
                guard let self, let selection = self.view?.selection(for: range) else { return }
                self.events.onSelectionMenu?(selection)
            }
            view.copyReference = { [weak self] first, last in
                guard let self, first <= last else { return nil }
                return self.events.referenceLine?(first...last)
            }
        }

        func apply(_ viewer: ScriptureViewer, to view: ScriptureTextView) {
            events = viewer.events
            controller = viewer.controller
            viewer.controller?.driver = self

            let configuration = viewer.configuration
            view.pullChangesChapter = configuration.pullChangesChapter
            view.menuItems = configuration.menuItems
            view.hostsSelectionMenu = configuration.hostSelectionMenu
            view.autoFullscreenMode = configuration.reportsDragEnd
            view.hidesTabBarOnScroll = events.onChromeRequest != nil
            view.onChromeRequest = events.onChromeRequest.map { request in { hide in request(hide ? .hide : .show) } }
            view.canHideChrome = events.canHideChrome.map { ask in { ask() } }
            view.onShare = events.onShare.map { share in { text in share(text) } }
            if insets?.top != configuration.topInset || insets?.bottom != configuration.bottomInset {
                insets = (configuration.topInset, configuration.bottomInset)
                view.setupRefreshViews(CGFloat(configuration.topInset), bottom: CGFloat(configuration.bottomInset))
            }
            view.scrollView.isScrollEnabled = configuration.scrolls

            if shown?.text != viewer.text || shown?.theme != viewer.theme {
                let sameText = shown?.text == viewer.text
                shown = (viewer.text, viewer.theme)
                painted = nil
                if sameText {
                    // The same text in another theme keeps the reader's place.
                    view.restyle(theme: ScriptureTextTheme(viewer.theme))
                } else {
                    view.display(viewer.text, theme: ScriptureTextTheme(viewer.theme))
                }
                shownNow = true
            }
            if painted != viewer.highlights {
                painted = viewer.highlights
                paint(viewer.highlights, on: view)
            }
            if shownNow {
                shownNow = false
                viewer.controller?.textWasShown()
            }
        }

        private func paint(_ highlights: ScriptureHighlights, on view: ScriptureTextView) {
            view.setBookmarkHighlights(verses: highlights.bookmarks.map { NSNumber(value: $0.verse) }, hexColours: highlights.bookmarks.map(\.hexColour))
            view.highlightSearchTerms(highlights.searchTerms)
            if let strongs = highlights.strongs { view.highlightStrongs(strongs) }
        }

        private func selectionChanged(_ range: NSRange) {
            let selection = view?.selection(for: range)
            controller?.update(selection: selection)
            events.onSelectionChange?(selection)
        }

        // MARK: ScriptureTextViewDelegate

        func scriptureTextViewScrollHappened(_ view: ScriptureTextView, newOffsetY: CGFloat) {
            controller?.update(scrollOffset: Double(newOffsetY), verse: view.currentVerse, atEnd: controller?.isAtEnd ?? false)
            events.onScroll?(Double(newOffsetY), view.currentVerse)
        }

        func scriptureTextViewReachedEnd(_ view: ScriptureTextView) {
            controller?.update(scrollOffset: controller?.scrollOffset ?? 0, verse: view.currentVerse, atEnd: true)
            events.onReachedEnd?()
        }

        func switchToFullscreen() { events.onGesture?(.dragEnded) }
        func scriptureTextViewTopReloadTriggered(_ view: ScriptureTextView) { events.onPull?(.previousChapter) }
        func scriptureTextViewBottomReloadTriggered(_ view: ScriptureTextView) { events.onPull?(.nextChapter) }
        func scriptureTextViewDidTapPlainText(_ view: ScriptureTextView) { events.onGesture?(.plainTap) }
        func scriptureTextViewDidTapWithTwoFingers(_ view: ScriptureTextView) { events.onGesture?(.twoFingerTap) }
        func scriptureTextViewDidSwipeLeft(_ view: ScriptureTextView) { events.onGesture?(.swipeLeft) }
        func scriptureTextViewDidSwipeRight(_ view: ScriptureTextView) { events.onGesture?(.swipeRight) }
        func scriptureTextViewDidDragWithThreeFingers(_ view: ScriptureTextView) { events.onGesture?(.threeFingerDrag) }

        // MARK: ScriptureViewerDriver

        func scroll(toVerse verse: Int, animated: Bool) { view?.scrollToVerse(verse, animated: animated) }
        func scroll(toOffset offset: Double, animated: Bool) { view?.scroll(toOffset: CGFloat(offset), animated: animated) }
        func focus(verse: Int) { view?.focusVerse(verse) }
        func clearFocus() { view?.clearVerseFocus() }
        func clearSelection() { view?.clearSelection() }
    }
}

extension ScriptureViewerController {
    /// Where a verse's first line is on screen, in the window's coordinates, for a menu or a share sheet that comes from the verse (iOS).
    /// Nil before the viewer has shown the text, or when the text has no such verse.
    @MainActor
    public func frameOfVerse(_ verse: Int) -> CGRect? {
        (driver as? ScriptureViewer.Bridge)?.view?.frameOfVerse(verse, in: nil)
    }

    /// Where the selection is on screen, in the window's coordinates, for the host's own selection menu (iOS). Nil with nothing selected.
    @MainActor
    public func frameOfSelection() -> CGRect? {
        (driver as? ScriptureViewer.Bridge)?.view?.frameOfSelection(in: nil)
    }
}

#elseif canImport(SwiftUI)

import SwiftUI
import ScriptureText

/// A placeholder on macOS, where there is no viewer yet: the same name and values as on iOS and Android, so that code shared between
/// them builds on a Mac (Skip builds an app's Swift there to transpile it, and a Mac test run builds it too). It shows nothing.
public struct ScriptureViewer: View {
    public init(text: ScriptureText, theme: ScriptureViewerTheme = ScriptureViewerTheme(), highlights: ScriptureHighlights = ScriptureHighlights(),
                configuration: ScriptureViewerConfiguration = ScriptureViewerConfiguration(), controller: ScriptureViewerController? = nil,
                events: ScriptureViewerEvents = ScriptureViewerEvents()) {}

    public var body: some View { EmptyView() }
}

#endif
