// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package scripture.viewer

import android.graphics.Rect
import android.view.ViewGroup
import androidx.compose.runtime.Composable
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import scripture.text.ScriptureHighlights
import scripture.text.ScriptureText
import scripture.text.ScriptureViewerChromeRequest
import scripture.text.ScriptureViewerConfiguration
import scripture.text.ScriptureViewerController
import scripture.text.ScriptureViewerDriver
import scripture.text.ScriptureViewerEvents
import scripture.text.ScriptureViewerTheme

/**
 * The scripture viewer, as a composable (plan D157 and D185, ScriptureViewerContract.md): the Android realisation of the contract.
 * It takes the text and the values of the contract and reports through its events; a `TextView` holding the chapter as one
 * `Spannable` ([ScriptureTextView]) does the drawing underneath. It opens no screen, resolves no lookup and reads no preference:
 * the host does.
 *
 * ```
 * ScriptureViewer(text = chapter, theme = theme, highlights = marks, configuration = setup, controller = controller, events = events)
 * ```
 *
 * A viewer that scrolls fills the space it is given; one that does not (`configuration.scrolls = false`) takes the height its text
 * needs at the width it is offered, plus its insets.
 */
@Composable
fun ScriptureViewer(
    text: ScriptureText,
    modifier: Modifier = Modifier,
    theme: ScriptureViewerTheme = ScriptureViewerTheme(),
    highlights: ScriptureHighlights = ScriptureHighlights(),
    configuration: ScriptureViewerConfiguration = ScriptureViewerConfiguration(),
    controller: ScriptureViewerController? = null,
    events: ScriptureViewerEvents = ScriptureViewerEvents(),
) {
    AndroidView(
        factory = { context -> ScriptureTextView(context).also { it.tag = ScriptureViewerBridge(it) } },
        modifier = modifier,
        update = { view ->
            // The bridge reads and writes the controller's observable state; none of that is a reason to run this block again.
            Snapshot.withoutReadObservation {
                (view.tag as ScriptureViewerBridge).apply(text, theme, highlights, configuration, controller, events)
            }
        },
        onRelease = { view -> (view.tag as ScriptureViewerBridge).release() },
    )
}

/**
 * Where a verse's first line is on screen, in the window's coordinates and in pixels, for a menu that comes from the verse. Null
 * before the viewer has shown the text, or when the text has no such verse.
 */
fun ScriptureViewerController.frameOfVerse(verse: Int): Rect? = (driver as? ScriptureViewerBridge)?.view?.frameOfVerse(verse)

/** Turns the text view's reports into the contract's events, and the controller's commands into the text view's calls. */
internal class ScriptureViewerBridge(val view: ScriptureTextView) : ScriptureViewerDriver {

    private var events = ScriptureViewerEvents()
    private var controller: ScriptureViewerController? = null
    private var shown: Shown? = null
    private var painted: ScriptureHighlights? = null
    private var insets: Pair<Double, Double>? = null

    /** What the text on show was styled from: a change of any of them styles it again. */
    private class Shown(val text: ScriptureText, val theme: ScriptureViewerTheme, val density: Float, val fontScale: Float) {
        fun matches(text: ScriptureText, theme: ScriptureViewerTheme, density: Float, fontScale: Float): Boolean =
            this.density == density && this.fontScale == fontScale && this.theme == theme && (this.text === text || this.text == text)
    }

    init {
        view.onTap = { target -> events.onTap?.invoke(target) }
        view.onSelectionChange = { start, length ->
            val selection = view.selection(start, length)
            controller?.update(selection = selection)
            events.onSelectionChange?.invoke(selection)
        }
        view.onMenuItem = { id, start, length -> view.selection(start, length)?.let { selection -> events.onMenuItem?.invoke(id, selection) } }
        view.copyReference = { first, last -> if (first <= last) events.referenceLine?.invoke(first..last) else null }
        view.onScrolled = { offset ->
            controller?.let { it.update(scrollOffset = offset, verse = view.currentVerse, atEnd = it.isAtEnd) }
            events.onScroll?.invoke(offset, view.currentVerse)
        }
        view.onReachedEnd = {
            controller?.let { it.update(scrollOffset = it.scrollOffset, verse = view.currentVerse, atEnd = true) }
            events.onReachedEnd?.invoke()
        }
        view.onGesture = { gesture -> events.onGesture?.invoke(gesture) }
        view.onPull = { pull -> events.onPull?.invoke(pull) }
    }

    fun apply(text: ScriptureText, theme: ScriptureViewerTheme, highlights: ScriptureHighlights, configuration: ScriptureViewerConfiguration,
              controller: ScriptureViewerController?, events: ScriptureViewerEvents) {
        this.events = events
        if (this.controller !== controller) {
            release()
            this.controller = controller
        }
        if (controller != null && controller.driver !== this) controller.driver = this

        view.pullChangesChapter = configuration.pullChangesChapter
        view.menuItems = kotlinList(configuration.menuItems)
        view.reportsDragEnd = configuration.reportsDragEnd
        view.onChromeRequest = events.onChromeRequest?.let { request ->
            { hide -> request(if (hide) ScriptureViewerChromeRequest.hide else ScriptureViewerChromeRequest.show) }
        }
        view.canHideChrome = events.canHideChrome
        view.onShare = events.onShare
        if (insets?.first != configuration.topInset || insets?.second != configuration.bottomInset) {
            insets = Pair(configuration.topInset, configuration.bottomInset)
            view.setInsets(top = configuration.topInset, bottom = configuration.bottomInset)
        }
        view.scrolls = configuration.scrolls
        // What the composable is measured by: all the height it is offered, or the height of its text.
        val height = if (configuration.scrolls) ViewGroup.LayoutParams.MATCH_PARENT else ViewGroup.LayoutParams.WRAP_CONTENT
        if (view.layoutParams?.height != height) view.layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, height)

        val metrics = view.resources.displayMetrics
        val fontScale = view.resources.configuration.fontScale
        var shownNow = false
        if (shown?.matches(text, theme, metrics.density, fontScale) != true) {
            shown = Shown(text, theme, metrics.density, fontScale)
            painted = null
            view.display(text, ScriptureTextTheme(theme, metrics.density, fontScale))
            // A new text starts at its top, unread.
            controller?.update(scrollOffset = 0.0, verse = view.currentVerse, atEnd = false)
            shownNow = true
        }
        if (painted != highlights) {
            painted = highlights
            paint(highlights)
        }
        if (shownNow) controller?.textWasShown()
    }

    private fun paint(highlights: ScriptureHighlights) {
        val bookmarks = kotlinList(highlights.bookmarks)
        view.setBookmarkHighlights(verses = bookmarks.map { it.verse }, hexColours = bookmarks.map { it.hexColour })
        view.highlightSearchTerms(kotlinList(highlights.searchTerms))
        highlights.strongs?.let { view.highlightStrongs(it) }
    }

    /** The view is going away, or has been given another controller: the old one no longer drives it. */
    fun release() {
        controller?.let { if (it.driver === this) it.driver = null }
    }

    // MARK: ScriptureViewerDriver

    override fun scroll(toVerse: Int, animated: Boolean) = view.scrollToVerse(toVerse, animated)
    override fun scroll(toOffset: Double, animated: Boolean) = view.scrollToOffset(toOffset, animated)
    override fun focus(verse: Int) = view.focusVerse(verse)
    override fun clearFocus() = view.clearVerseFocus()
    override fun clearSelection() = view.clearSelection()
}
