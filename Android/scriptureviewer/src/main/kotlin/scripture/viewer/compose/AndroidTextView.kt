// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package scripture.viewer.compose

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Rect
import android.graphics.RectF
import android.os.SystemClock
import android.text.Layout
import android.text.Selection
import android.text.Spannable
import android.text.TextDirectionHeuristic
import android.text.TextDirectionHeuristics
import android.util.TypedValue
import android.view.ActionMode
import android.view.GestureDetector
import android.view.Menu
import android.view.MenuItem
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.widget.NestedScrollView
import scripture.text.Highlight
import scripture.text.HighlightStyle
import scripture.text.ScriptureBarScrollRule
import scripture.text.ScriptureMenuItem
import scripture.text.ScriptureSelection
import scripture.text.ScriptureText
import scripture.text.ScriptureViewerGesture
import scripture.text.ScriptureViewerPull
import scripture.text.TapKind
import scripture.text.TapTarget
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The native reading surface on Android (plan D185): a selectable `TextView` holding the chapter as one `Spannable`, in a scroll
 * view. It scrolls to an exact verse, knows the verse at the top, dims all but a focused verse, paints highlights without a new
 * layout, finds the tap target under a finger, copies the selection as the reader's copy and reports the reader's gestures. The
 * counterpart of the iOS `ScriptureTextView`; the Compose `ScriptureViewer` sits on top of it and speaks the contract.
 *
 * Offsets it reports and takes are in density-independent units (dp), measured from the top of the text, as the iOS view's are in
 * points. It opens no screen and reads no preference: everything it is told comes through the properties below.
 */
@SuppressLint("ViewConstructor")
internal class ScriptureTextView(context: Context) : FrameLayout(context) {

    // What the host listens to (the Compose viewer turns these into the contract's events).

    /** A tap on something interactive: a marker, a link, a verse number, a word with lexical data. */
    var onTap: ((TapTarget) -> Unit)? = null
    /** The selection changed: its start and length in UTF-16 units (length 0: nothing is selected). */
    var onSelectionChange: ((Int, Int) -> Unit)? = null
    /** Items the host adds to the selection menu, and the choice of one with the selection it was chosen on. */
    var menuItems: List<ScriptureMenuItem> = emptyList()
    var onMenuItem: ((String, Int, Int) -> Unit)? = null
    /** The scroll rule's wish for the host's bars (true: hide). When set, the view follows the rule; the host decides. */
    var onChromeRequest: ((Boolean) -> Unit)? = null
    /** Asked before a tap on the text sends the bars away. */
    var canHideChrome: (() -> Boolean)? = null
    /** The selection menu's Share; without it, the system's share sheet. */
    var onShare: ((String) -> Unit)? = null
    /** The reference line for copied text, given its first and last verse ("John 3:16–18 (KJV)"). */
    var copyReference: ((Int, Int) -> String?)? = null
    /** The text moved: the new offset in dp. `currentVerse` is already up to date. */
    var onScrolled: ((Double) -> Unit)? = null
    /** The end of the text came into view; once for each text shown. */
    var onReachedEnd: (() -> Unit)? = null
    var onGesture: ((ScriptureViewerGesture) -> Unit)? = null
    var onPull: ((ScriptureViewerPull) -> Unit)? = null

    /** A pull past the top or the end asks for the previous or the next chapter. */
    var pullChangesChapter = false
    /** Report `dragEnded` when the reader lets go of a drag that was not a pull (Automatic Fullscreen). */
    var reportsDragEnd = false
    /** Scrolls itself (a chapter), or takes the height of its text (a note in a pane). */
    var scrolls = true
        set(value) {
            if (field == value) return
            field = value
            scroll.scrollingEnabled = value
            scroll.isNestedScrollingEnabled = value
            scroll.layoutParams = LayoutParams(MATCH_PARENT, if (value) MATCH_PARENT else WRAP_CONTENT)
        }

    /** The verse at the top of the visible area; starts at 1 for each text. */
    var currentVerse = 1
        private set
    /** The verse brought into view by navigation and shown at full strength, the rest dimmed, until the reader scrolls. */
    var focusedVerse: Int? = null
        private set

    internal val scroll = ReaderScrollView(context)
    internal val textView = ReaderTextView(context)

    private val density = resources.displayMetrics.density
    private var scripture: ScriptureText? = null
    private var theme: ScriptureTextTheme? = null
    private var metricsSpan: ParagraphMetricsSpan? = null
    private var barScrollRule = ScriptureBarScrollRule()
    private var lastReportedOffset = 0.0
    private var lastLayoutWidth = 0
    /** Commands that need the text laid out (a scroll to a verse sent in the same breath as the text), run after the next layout. */
    private val afterLayout = ArrayList<() -> Unit>()
    private var actionMode: ActionMode? = null

    init {
        textView.setTextIsSelectable(true)
        textView.includeFontPadding = false
        textView.breakStrategy = Layout.BREAK_STRATEGY_SIMPLE
        textView.hyphenationFrequency = Layout.HYPHENATION_FREQUENCY_NONE
        // The text view shows the very Spannable it is given, so highlights are added to and taken from the text on show.
        textView.setSpannableFactory(object : Spannable.Factory() {
            override fun newSpannable(source: CharSequence): Spannable = source as? Spannable ?: super.newSpannable(source)
        })
        textView.customSelectionActionModeCallback = SelectionMenu()
        textView.onSelection = { start, end -> selectionChanged(start, end - start) }
        textView.copyText = { copiedSelection() }
        textView.afterCopy = { actionMode?.finish() }
        textView.share = { text -> shareSelection(text) }

        scroll.clipToPadding = false
        scroll.isSaveEnabled = false
        scroll.addView(textView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        scroll.onScroll = { scrolled() }
        // The scroll view follows the cursor only while text is selected (a handle dragged to an edge); otherwise a
        // selectable text view in a scroll view jumps to its cursor whenever it is laid out.
        scroll.followsCursor = { textView.hasSelection() }
        addView(scroll, LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    // MARK: Content

    /** The text on show (tests, and hosts that need to know what the screen holds). */
    val displayedText: String get() = scripture?.text ?: ""

    fun display(scripture: ScriptureText, theme: ScriptureTextTheme) {
        this.scripture = scripture
        style(theme)

        currentVerse = 1
        lastReportedOffset = 0.0
        reportedEnd = false
        // A new chapter starts at its top.
        scrollTo(y = 0, animated = false)
        // Text that fits the screen has been read to its end as soon as it shows.
        whenLaidOut { post { reportEndIfAtBottom(userDriven = false) } }
    }

    /**
     * The text on show in another theme (night mode, a font, a size): styled again where the reader is, not from its top. The verse at
     * the top stays at the top, the very top (heading and all) stays the very top, and an end once reached stays reached. The focus,
     * the selection and the highlights go, as for a new text; the host paints its highlights again.
     */
    fun restyle(theme: ScriptureTextTheme) {
        if (scripture == null) return
        val atTop = scroll.scrollY <= density
        val verse = currentVerse
        style(theme)
        whenLaidOut {
            if (atTop) scrollTo(y = 0, animated = false) else verseTop(verse)?.let { scrollTo(y = it, animated = false) }
            currentVerse = verse
            reportScroll()
        }
    }

    /** Styles the text on show in a theme's fonts and colours, with nothing marked until the host says so. The scroll is the caller's. */
    private fun style(theme: ScriptureTextTheme) {
        val scripture = scripture ?: return
        this.theme = theme
        bookmarkHighlights = emptyList()
        searchHighlights = emptyList()
        paintedSpans.clear()
        paintedHighlights = emptyList()
        focusedVerse = null
        dimSpans.clear()
        afterLayout.clear()
        actionMode?.finish()

        val styled = ScriptureTextStyler.spannable(scripture, theme)
        metricsSpan = styled.getSpans(0, styled.length, ParagraphMetricsSpan::class.java).firstOrNull()
        textView.typeface = theme.typeface
        textView.setTextSize(TypedValue.COMPLEX_UNIT_PX, theme.bodyPx)
        textView.setTextColor(theme.textColor)
        // The module's direction, not the first strong letter: Psalm 119's "א ALEPH." would otherwise make its paragraph
        // right-to-left in a left-to-right Bible. Said twice: the view's text direction only counts in an app that declares
        // `supportsRtl`, and the heuristic is what the layout asks for (Android 10 and later).
        textView.paragraphDirection = if (theme.rightToLeft) TextDirectionHeuristics.RTL else TextDirectionHeuristics.LTR
        textView.textDirection = if (theme.rightToLeft) View.TEXT_DIRECTION_RTL else View.TEXT_DIRECTION_LTR
        val margin = (ScriptureTextTheme.sideMarginDp(theme.isWide) * density).roundToInt()
        textView.setPadding(margin, 0, margin, 0)
        setBackgroundColor(theme.backgroundColor)
        textView.setText(styled, TextView.BufferType.SPANNABLE)
    }

    // MARK: Insets

    /** Space the host's bars cover, in dp: the text scrolls under them and rests clear of them. */
    fun setInsets(top: Double, bottom: Double) {
        scroll.setPadding(0, (top * density).roundToInt(), 0, (bottom * density).roundToInt())
    }

    // MARK: Layout

    private val isTextLaidOut: Boolean
        get() = scripture != null && width > 0 && textView.layout != null && !textView.isLayoutRequested

    /** Runs `action` now when the text is laid out, otherwise after the layout that is on its way. */
    private fun whenLaidOut(action: () -> Unit) {
        if (isTextLaidOut) action() else afterLayout.add(action)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        if (width != lastLayoutWidth) {
            val hadLaidOut = lastLayoutWidth != 0
            lastLayoutWidth = width
            // A new width wraps the text again. At the very top, stay there: verse 1's first line lies below any chapter or psalm
            // heading, so re-anchoring to verse 1 would scroll the heading away. Otherwise keep the verse that was at the top.
            if (hadLaidOut && scripture != null && textView.layout != null) {
                if (scroll.scrollY <= density) scrollTo(y = 0, animated = false) else verseTop(currentVerse)?.let { scrollTo(y = it, animated = false) }
            }
        }
        if (afterLayout.isNotEmpty() && scripture != null && textView.layout != null) {
            val actions = ArrayList(afterLayout)
            afterLayout.clear()
            for (action in actions) action()
        }
    }

    // MARK: Verse geometry

    /** The top of a verse's first line, in pixels from the top of the text, or null when the text has no such verse. */
    internal fun verseTop(verse: Int): Int? {
        val scripture = scripture ?: return null
        val layout = textView.layout ?: return null
        // A verse of a bridge scrolls to the bridge.
        val range = scripture.verseRange(containing = verse) ?: return null
        val line = layout.getLineForOffset(range.start.coerceIn(0, layout.text.length))
        return textView.totalPaddingTop + layout.getLineTop(line) + (metricsSpan?.spaceAbove(layout.getLineStart(line)) ?: 0)
    }

    /** Where a verse's first line is, in the window's coordinates (for a menu that comes from the verse), or null. */
    fun frameOfVerse(verse: Int): Rect? {
        val scripture = scripture ?: return null
        val layout = textView.layout ?: return null
        val range = scripture.verseRange(containing = verse) ?: return null
        val line = layout.getLineForOffset(range.start.coerceIn(0, layout.text.length))
        val origin = IntArray(2)
        textView.getLocationInWindow(origin)
        val left = origin[0] + textView.totalPaddingLeft
        val top = origin[1] + textView.totalPaddingTop
        return Rect(left + layout.getLineLeft(line).toInt(), top + layout.getLineTop(line),
                    left + layout.getLineRight(line).toInt(), top + layout.getLineBottom(line))
    }

    /**
     * The verse at the top of the visible area: the first verse that begins on the top line, or, when none begins there, the verse
     * the line is part of. So the verse a scroll went to is the verse reported, and scrolling to the verse reported moves nothing.
     */
    internal fun verseAtTop(): Int {
        val scripture = scripture ?: return 1
        val layout = textView.layout ?: return 1
        if (scripture.verses.isEmpty) return 1
        val line = layout.getLineForVertical(max(scroll.scrollY - textView.totalPaddingTop, 0))
        val lineStart = layout.getLineStart(line)
        val lineEnd = layout.getLineEnd(line)
        var verse = scripture.verses.first!!.verse
        for (range in scripture.verses) {
            if (range.start <= lineStart) {
                verse = range.verse
            } else {
                if (range.start < lineEnd) verse = range.verse
                break
            }
        }
        return verse
    }

    // MARK: Scrolling

    /** The offset the reader is at, in dp from the top of the text. */
    val scrollOffset: Double get() = scroll.scrollY / density.toDouble()

    private var programmaticScroll = false

    private fun scrollTo(y: Int, animated: Boolean) {
        val target = y.coerceIn(0, scroll.maxScroll)
        // A scroll the host asks for ends the reader's own: what follows is not the reader moving the text.
        if (flinging) scroll.fling(0)
        removeCallbacks(settled)
        flinging = false
        programmaticScroll = true
        if (animated) scroll.smoothScrollTo(0, target) else scroll.scrollTo(0, target)
        programmaticScroll = false
    }

    /** Scrolls so the verse's first line sits at the top of the visible area, under any bar the insets describe. */
    fun scrollToVerse(verse: Int, animated: Boolean) = whenLaidOut {
        val top = verseTop(verse) ?: return@whenLaidOut
        currentVerse = verse
        scrollTo(y = top, animated = animated)
        reportScroll()
    }

    /** Scrolls so that `offset` (as `onScrolled` reports it, in dp) is at the top. */
    fun scrollToOffset(offset: Double, animated: Boolean) = whenLaidOut {
        scrollTo(y = (offset * density).roundToInt(), animated = animated)
        // The verse follows the position here: an offset says nothing about which verse was meant.
        currentVerse = verseAtTop()
        reportScroll()
    }

    /**
     * Goes to a verse the reader asked for: near the top with a little space above it (as far as the text allows), and dims the
     * text around it until the reader scrolls or taps.
     */
    fun focusVerse(verse: Int) = whenLaidOut {
        val top = verseTop(verse) ?: return@whenLaidOut
        val visible = (scroll.height - scroll.paddingTop - scroll.paddingBottom) / density
        val spacing = min(max(visible * 0.12f, 24f), 96f) * density
        currentVerse = verse
        focusedVerse = verse
        scrollTo(y = top - spacing.roundToInt(), animated = false)
        applyHighlights()
        reportScroll()
    }

    /** Ends the focus: everything back to its own colour. */
    fun clearVerseFocus() {
        if (focusedVerse == null) return
        focusedVerse = null
        applyHighlights()
    }

    private fun reportScroll() {
        lastReportedOffset = scrollOffset
        onScrolled?.invoke(lastReportedOffset)
    }

    private val userDriven: Boolean get() = !programmaticScroll && (touching || flinging)

    private fun scrolled() {
        val offset = scrollOffset
        val byReader = userDriven
        if (onChromeRequest != null && byReader) {
            if (touching && isInBottomZone(lastTouchY)) {
                // A finger dragged down into the bar's area wants the bar, not the scroll rule.
                showBarAfterEdgeTouch()
            } else {
                barScrollRule.update(offset = offset, maxOffset = scroll.maxScroll / density.toDouble())?.let { hide -> onChromeRequest?.invoke(hide) }
            }
        }
        reportEndIfAtBottom(userDriven = byReader)
        if (abs(lastReportedOffset - offset) > 2) {
            // Only the reader's own scrolling moves the tracked verse: a scroll the host asked for has named its verse.
            if (byReader) {
                currentVerse = verseAtTop()
                clearVerseFocus()          // the reader moved the text: the focus has done its job
            }
            reportScroll()
        }
        if (flinging) settleSoon()
    }

    // MARK: Reaching the end

    private var reportedEnd = false

    /**
     * Reports the end of the text once: when the text fits the view, or when the reader has scrolled to the bottom (`userDriven`:
     * a scroll by the reader, not the view putting the text in place).
     */
    internal fun reportEndIfAtBottom(userDriven: Boolean) {
        if (reportedEnd || scripture == null || scroll.height <= 0 || textView.height <= 0) return
        val fits = scroll.maxScroll <= density
        if (!fits && !(userDriven && scroll.scrollY >= scroll.maxScroll - endSlackDp * density)) return
        reportedEnd = true
        onReachedEnd?.invoke()
    }

    // MARK: Highlights

    private var bookmarkHighlights: List<Highlight> = emptyList()
    private var searchHighlights: List<Highlight> = emptyList()
    private val paintedSpans = ArrayList<Any>()
    private val dimSpans = ArrayList<Any>()
    /** The ranges painted now, as start and length (tests). */
    internal var paintedHighlights: List<Pair<Int, Int>> = emptyList()
        private set
    /** The ranges dimmed now, as start and length (tests). */
    internal var dimmedRanges: List<Pair<Int, Int>> = emptyList()
        private set

    /** Bookmarked verses, each in its folder's colour (`#RRGGBB`, or empty for none). Search highlights stay. */
    fun setBookmarkHighlights(verses: List<Int>, hexColours: List<String>) {
        bookmarkHighlights = verses.zip(hexColours).map { (verse, hex) ->
            Highlight(Highlight.Target.verse(verse), style = HighlightStyle.bookmark(colour = hex.ifEmpty { null }))
        }
        applyHighlights()
    }

    /** Marks every occurrence of the words of a search, ignoring case. An empty list clears it. */
    fun highlightSearchTerms(terms: List<String>) {
        searchHighlights = scripture?.searchHits(for_ = skip.lib.Array(terms))?.let { kotlinList(it) } ?: emptyList()
        applyHighlights()
    }

    /** Marks the words that carry a Strong's number, after a Strong's search. */
    fun highlightStrongs(number: String) {
        searchHighlights = scripture?.strongsHits(for_ = number)?.let { kotlinList(it) } ?: emptyList()
        applyHighlights()
    }

    /**
     * Paints the focus and the highlights as spans on the text on show. None of them changes a measurement, so the text view only
     * draws again: the layout, the selection and the scroll position stay as they are.
     */
    private fun applyHighlights() {
        val scripture = scripture ?: return
        val theme = theme ?: return
        val text = textView.text as? Spannable ?: return
        val length = text.length
        for (span in dimSpans) text.removeSpan(span)
        for (span in paintedSpans) text.removeSpan(span)
        dimSpans.clear()
        paintedSpans.clear()

        // The focus: the text outside the verse at a third of its colour.
        val dimmed = ArrayList<Pair<Int, Int>>()
        focusedVerse?.let { focused -> scripture.verseRange(containing = focused) }?.let { verse ->
            val start = min(verse.start, length)
            val end = min(verse.start + verse.length, length)
            if (start > 0) dimmed.add(0 to start)
            if (end < length) dimmed.add(end to length - end)
        }
        for ((start, count) in dimmed) {
            val span = DimSpan(ScriptureTextTheme.dimmedAlpha)
            text.setSpan(span, start, start + count, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
            dimSpans.add(span)
        }
        dimmedRanges = dimmed

        val painted = ArrayList<Pair<Int, Int>>()
        for (highlight in scripture.resolve(highlights = skip.lib.Array(bookmarkHighlights + searchHighlights))) {
            val start = highlight.start
            val end = highlight.start + highlight.length
            if (start < 0 || end > length || end <= start) continue
            val colours = theme.highlightColors(highlight.style)
            val spans = listOfNotNull(HighlightBackgroundSpan(colours.background), colours.text?.let { HighlightTextSpan(it) })
            for (span in spans) {
                text.setSpan(span, start, end, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
                paintedSpans.add(span)
            }
            painted.add(start to highlight.length)
        }
        paintedHighlights = painted
    }

    // MARK: Taps

    /** The tap target under a point of the text view, or null. */
    internal fun tapTarget(x: Float, y: Float): TapTarget? {
        val scripture = scripture ?: return null
        val layout = textView.layout ?: return null
        val length = min(scripture.text.length, layout.text.length)
        if (length == 0) return null
        val pointX = x - textView.totalPaddingLeft
        val pointY = y - textView.totalPaddingTop
        if (pointY < 0 || pointY > layout.height) return null
        val line = layout.getLineForVertical(pointY.toInt())
        val offset = layout.getOffsetForHorizontal(line, pointX)
        // The offset is the nearest caret position; only accept a tap that is on a character, give or take a few dp. The caret may
        // sit before or after the character tapped, so try the characters around it. A verse number or a note marker is a character
        // or two wide and sits against a word, which may itself be tappable: within the slack the small target wins, so "1In"
        // opens verse 1's menu.
        val slack = tapSlackDp * density
        var word: TapTarget? = null
        for (candidate in intArrayOf(offset, offset - 1, offset - 2, offset + 1)) {
            if (candidate < 0 || candidate >= length) continue
            val rect = rectOfCharacter(candidate) ?: continue
            val squarely = rect.contains(pointX, pointY)
            rect.inset(-slack, -slack)
            if (!rect.contains(pointX, pointY)) continue
            val target = scripture.tapTarget(atUTF16Offset = candidate) ?: continue
            if (target.kind != TapKind.word) return target
            // A word is taken as before (the caret's character or the one before it); others only when tapped squarely.
            if (word == null && (candidate == offset || candidate == offset - 1 || squarely)) word = target
        }
        return word
    }

    /** The rectangle of one character in the layout's coordinates (tests and hit testing). */
    internal fun rectOfCharacter(offset: Int): RectF? {
        val layout = textView.layout ?: return null
        if (offset < 0 || offset >= layout.text.length) return null
        val line = layout.getLineForOffset(offset)
        val near = layout.getPrimaryHorizontal(offset)
        val far = if (offset + 1 < layout.getLineEnd(line)) {
            layout.getPrimaryHorizontal(offset + 1)
        } else if (layout.getParagraphDirection(line) == Layout.DIR_RIGHT_TO_LEFT) {
            layout.getLineLeft(line)
        } else {
            layout.getLineRight(line)
        }
        return RectF(min(near, far), layout.getLineTop(line).toFloat(), max(near, far), layout.getLineBottom(line).toFloat())
    }

    /** A point of this view in the text view's coordinates. */
    private fun pointInText(x: Float, y: Float): Pair<Float, Float> =
        Pair(x - scroll.left - textView.left + scroll.scrollX, y - scroll.top - textView.top + scroll.scrollY)

    /** A single tap: reports what was tapped, if it is something interactive and no text is selected. */
    internal fun reportTap(x: Float, y: Float) {
        if (textView.hasSelection() || touchBeganWhileScrolling) return
        val onTap = onTap ?: return
        val target = tapTarget(x, y) ?: return
        clearVerseFocus()          // a tap is as much a sign the reader is reading as a scroll is
        onTap(target)
    }

    /**
     * The rule for a plain tap: one on text that is not a marker, a link or a verse number, with no text selected and not stopping
     * a scroll. A tap on a word that only carries lexical data counts as plain.
     */
    internal fun reportPlainTap(x: Float, y: Float) {
        if (touchBeganWithSelection || touchBeganWhileScrolling || textView.hasSelection()) return
        clearVerseFocus()          // a short chapter cannot scroll, so a tap on the text ends the focus too
        tapTarget(x, y)?.let { target -> if (target.kind != TapKind.word) return }
        onChromeRequest?.let { request ->
            if (barScrollRule.hidden) {
                // a tap brings the bar back
                barScrollRule.reset(at = scrollOffset)
                request(false)
            } else if (SystemClock.uptimeMillis() - barShownByTouchAt < tapAfterShowWindow) {
                // the same touch has just brought the bar back: leave it
            } else if (!reportsDragEnd && canHideChrome?.invoke() == true) {
                // and a tap on the text sends it away (Automatic Fullscreen has its own tap: the host says through `canHideChrome`)
                barScrollRule.forceHidden(at = scrollOffset)
                request(true)
            }
        }
        onGesture?.invoke(ScriptureViewerGesture.plainTap)
    }

    private fun isInBottomZone(y: Float): Boolean = y > height - bottomEdgeZoneDp * density

    /** The rule for a touch in the bottom zone: it brings back a bar that scrolling hid. */
    internal fun showBarAfterEdgeTouch() {
        val request = onChromeRequest ?: return
        if (!barScrollRule.hidden) return
        barScrollRule.reset(at = scrollOffset)
        request(false)
        barShownByTouchAt = SystemClock.uptimeMillis()
    }

    /** When a touch near the bottom brought the bar back: the tap that follows the same touch must not hide the bar it showed. */
    internal var barShownByTouchAt = 0L

    internal fun reportSwipe(left: Boolean) {
        // A drag that started a selection, or one that moves selection handles, is not a swipe.
        if (touchBeganWithSelection || textView.hasSelection()) return
        onGesture?.invoke(if (left) ScriptureViewerGesture.swipeLeft else ScriptureViewerGesture.swipeRight)
    }

    // MARK: Touches

    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private var touching = false
    private var flinging = false
    private var lastTouchY = 0f
    private var downX = 0f
    private var downY = 0f
    private var pointers = 0
    private var movedPastSlop = false
    private var dragging = false
    private var touchBeganWithSelection = false
    private var touchBeganWhileScrolling = false
    private var topEdgeY: Float? = null
    private var bottomEdgeY: Float? = null
    private var pulledDown = 0f
    private var pulledUp = 0f
    private var threeFingerStartY: Float? = null
    private var threeFingerDragReported = false
    private val settled = Runnable { flinging = false }

    private fun settleSoon() {
        removeCallbacks(settled)
        postDelayed(settled, settleMillis)
    }

    private val gestures = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
        override fun onSingleTapUp(event: MotionEvent): Boolean {
            val (x, y) = pointInText(event.x, event.y)
            reportTap(x, y)
            return false
        }

        // Waits for a second tap not to come, so double-tapping a word still selects it.
        override fun onSingleTapConfirmed(event: MotionEvent): Boolean {
            val (x, y) = pointInText(event.x, event.y)
            reportPlainTap(x, y)
            return false
        }
    })

    /** Watches every touch on its way to the text and the scroll view; it takes none of them. */
    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        watch(event)
        return super.dispatchTouchEvent(event)
    }

    private fun watch(event: MotionEvent) {
        lastTouchY = event.y
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                touching = true
                downX = event.x
                downY = event.y
                pointers = 1
                movedPastSlop = false
                dragging = false
                topEdgeY = null
                bottomEdgeY = null
                pulledDown = 0f
                pulledUp = 0f
                threeFingerStartY = null
                // Whether text was selected or the text was moving as the touch began: a tap that stops a scroll, or one that
                // clears a selection, is not a plain tap.
                touchBeganWithSelection = textView.hasSelection()
                touchBeganWhileScrolling = flinging
                removeCallbacks(settled)
                flinging = false
                if (isInBottomZone(event.y)) showBarAfterEdgeTouch()
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                pointers = max(pointers, event.pointerCount)
                if (event.pointerCount == 3) {
                    threeFingerStartY = centreY(event)
                    threeFingerDragReported = false
                }
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = event.x - downX
                val dy = event.y - downY
                if (abs(dx) > touchSlop || abs(dy) > touchSlop) movedPastSlop = true
                if (event.pointerCount == 1 && !dragging && abs(dy) > touchSlop && abs(dy) > abs(dx)) dragging = true
                if (dragging && event.pointerCount == 1) trackPull(event.y)
                if (event.pointerCount == 3) {
                    threeFingerStartY?.let { start -> reportThreeFingerDrag(verticalDistance = centreY(event) - start) }
                }
            }
            MotionEvent.ACTION_UP -> {
                touching = false
                if (pointers == 2 && !movedPastSlop && event.eventTime - event.downTime < twoFingerTapMillis) {
                    onGesture?.invoke(ScriptureViewerGesture.twoFingerTap)
                }
                if (dragging && pointers == 1 && !touchBeganWithSelection && !textView.hasSelection()) dragEnded()
                // A swipe is decided when the finger lifts, by how far it went and which way, at any speed: a fling's speed was the
                // rule, and an unhurried swipe (or a mouse's drag in the emulator) changed nothing.
                val dx = event.x - downX
                val dy = event.y - downY
                if (pointers == 1 && !dragging && abs(dx) >= swipeDistanceDp * density && abs(dx) > 2 * abs(dy)) reportSwipe(left = dx < 0)
            }
            MotionEvent.ACTION_CANCEL -> {
                // A parent took the touch (a pager, a sheet): nothing of it is a gesture of the reader's.
                touching = false
                pointers = 0
            }
        }
        gestures.onTouchEvent(event)
    }

    private fun centreY(event: MotionEvent): Float {
        var sum = 0f
        for (index in 0 until event.pointerCount) sum += event.getY(index)
        return sum / event.pointerCount
    }

    /** How far the finger has gone on dragging after the text reached its top or its end. */
    private fun trackPull(y: Float) {
        if (!scroll.canScrollVertically(-1)) {
            val edge = topEdgeY ?: y.also { topEdgeY = it }
            pulledDown = y - edge
        } else {
            topEdgeY = null
            pulledDown = 0f
        }
        if (!scroll.canScrollVertically(1)) {
            val edge = bottomEdgeY ?: y.also { bottomEdgeY = it }
            pulledUp = edge - y
        } else {
            bottomEdgeY = null
            pulledUp = 0f
        }
    }

    private fun dragEnded() {
        val threshold = (if (theme?.isWide == true) widePullDp else phonePullDp) * density
        if (scrolls) {
            flinging = true
            settleSoon()
        }
        if (pullChangesChapter && pulledDown >= threshold) {
            onPull?.invoke(ScriptureViewerPull.previousChapter)
        } else if (pullChangesChapter && pulledUp >= threshold) {
            onPull?.invoke(ScriptureViewerPull.nextChapter)
        } else if (reportsDragEnd) {
            onGesture?.invoke(ScriptureViewerGesture.dragEnded)
        }
        // A drag at the end of the text moves nothing here, so no scroll says the reader is there: the drag does.
        reportEndIfAtBottom(userDriven = true)
    }

    /** A three-finger vertical drag of at least 100 dp; reported once for each drag. */
    internal fun reportThreeFingerDrag(verticalDistance: Float) {
        if (threeFingerDragReported || abs(verticalDistance) < threeFingerDragDp * density) return
        threeFingerDragReported = true
        onGesture?.invoke(ScriptureViewerGesture.threeFingerDrag)
    }

    /** Starts a new three-finger drag (tests; the touches do this themselves). */
    internal fun resetThreeFingerDrag() { threeFingerDragReported = false }

    /** A pointer (a mouse or a trackpad) moving into the bottom zone brings the bar back, with no touch. */
    override fun dispatchHoverEvent(event: MotionEvent): Boolean {
        if ((event.actionMasked == MotionEvent.ACTION_HOVER_ENTER || event.actionMasked == MotionEvent.ACTION_HOVER_MOVE) && isInBottomZone(event.y)) {
            showBarAfterEdgeTouch()
        }
        return super.dispatchHoverEvent(event)
    }

    // MARK: Selection and copy

    private var selectedLength = 0

    private fun selectionChanged(start: Int, length: Int) {
        // A long press beside the end of a line selects its line break and nothing else: that is no selection to the reader.
        // (Only as a selection begins: while a handle is dragged, the selection may pass through a space.)
        val text = textView.text
        if (selectedLength == 0 && length > 0 && start + length <= text.length && text.subSequence(start, start + length).isBlank()) {
            post { if (textView.hasSelection() && selectedRange == Pair(start, length)) clearSelection() }
            return
        }
        if (length == selectedLength && length == 0) return
        selectedLength = length
        onSelectionChange?.invoke(start, length)
    }

    /** What is selected, as UTF-16 offsets and the verses it touches, or null when nothing is. */
    fun selection(start: Int, length: Int): ScriptureSelection? {
        val scripture = scripture ?: return null
        if (length <= 0) return null
        return ScriptureSelection(start = start, length = length, verses = scripture.copiedText(utf16Start = start, length = length).verses)
    }

    val selectedRange: Pair<Int, Int>
        get() {
            val start = max(min(textView.selectionStart, textView.selectionEnd), 0)
            val end = max(max(textView.selectionStart, textView.selectionEnd), 0)
            return Pair(start, end - start)
        }

    /** Selects a range of the text (tests, and hosts that select a verse). */
    internal fun select(start: Int, length: Int) {
        val text = textView.text as? Spannable ?: return
        Selection.setSelection(text, start.coerceIn(0, text.length), (start + length).coerceIn(0, text.length))
    }

    fun clearSelection() {
        actionMode?.finish()
        val text = textView.text as? Spannable ?: return
        if (textView.hasSelection()) Selection.setSelection(text, max(textView.selectionEnd, 0))
    }

    /**
     * The selected text as the reader copies it: the reference line, then the words without note letters, markers or joiners.
     * Null when nothing is selected.
     */
    internal fun copiedSelection(): String? {
        val scripture = scripture ?: return null
        val (start, length) = selectedRange
        if (length <= 0) return null
        val copied = scripture.copiedText(utf16Start = start, length = length)
        val verses = copied.verses ?: return copied.text
        val reference = copyReference?.invoke(verses.start, verses.endInclusive)
        return if (reference.isNullOrEmpty()) copied.text else reference + "\n" + copied.text
    }

    private fun shareSelection(text: String) {
        onShare?.let { share ->
            share(text)
            return
        }
        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
        context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /** The selection menu: the host's items first, then the system's. Copy and Share take the text from the model (see `ReaderTextView`). */
    private inner class SelectionMenu : ActionMode.Callback {
        override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean {
            actionMode = mode
            menuItems.forEachIndexed { index, item ->
                // Before the system's own (Copy, Share, Select all), in the host's order: the toolbar puts items that must show first.
                menu.add(hostMenuGroup, hostMenuFirstId + index, 0, item.title).setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS)
            }
            return true
        }

        override fun onPrepareActionMode(mode: ActionMode, menu: Menu): Boolean = false

        override fun onActionItemClicked(mode: ActionMode, item: MenuItem): Boolean {
            if (item.groupId != hostMenuGroup) return false
            val chosen = menuItems.getOrNull(item.itemId - hostMenuFirstId) ?: return false
            val (start, length) = selectedRange
            onMenuItem?.invoke(chosen.id, start, length)
            return true
        }

        override fun onDestroyActionMode(mode: ActionMode) {
            if (actionMode === mode) actionMode = null
        }
    }

    /** The host's items as the selection menu would show them, and the choice of one (tests). */
    internal fun chooseMenuItem(id: String) {
        val (start, length) = selectedRange
        if (menuItems.any { it.id == id }) onMenuItem?.invoke(id, start, length)
    }

    companion object {
        /** How close to the bottom counts as the end, in dp: the last line is in view. */
        const val endSlackDp = 40f
        /** How far up from the bottom edge a touch brings the bar back, in dp. */
        const val bottomEdgeZoneDp = 120f
        /** How far beside a character a tap still counts as on it, in dp. */
        const val tapSlackDp = 6f
        const val tapAfterShowWindow = 1000L
        /** A swipe left or right is at least this far, and more than twice as far sideways as up or down, at any speed. */
        const val swipeDistanceDp = 64f
        const val threeFingerDragDp = 100f
        const val twoFingerTapMillis = 400L
        /**
         * How far the finger must go on past the top or the end for a pull, in dp. Twice the iOS thresholds (65 and 130 points of
         * overscroll), because there the text follows a pull at about half the finger's speed and here it does not move at all.
         */
        const val phonePullDp = 130f
        const val widePullDp = 260f
        /** A fling is over when the text has not moved for this long. */
        const val settleMillis = 120L
        private const val hostMenuGroup = 0x5356
        private const val hostMenuFirstId = 0x53560000
    }
}

/** A Kotlin list of what a collection of the core holds. */
internal fun <Element> kotlinList(elements: Iterable<Element>): List<Element> {
    val list = ArrayList<Element>()
    for (element in elements) list.add(element)
    return list
}

/** The scroll view behind the reader. */
internal class ReaderScrollView(context: Context) : NestedScrollView(context) {

    var scrollingEnabled = true
    var onScroll: (() -> Unit)? = null
    var followsCursor: () -> Boolean = { false }

    /** The furthest the text scrolls, in pixels. */
    val maxScroll: Int
        get() {
            val child = getChildAt(0) ?: return 0
            return max(0, child.height + paddingTop + paddingBottom - height)
        }

    override fun onScrollChanged(left: Int, top: Int, oldLeft: Int, oldTop: Int) {
        super.onScrollChanged(left, top, oldLeft, oldTop)
        onScroll?.invoke()
    }

    // A viewer that sizes to its text leaves every drag to whatever scrolls around it.
    override fun onInterceptTouchEvent(event: MotionEvent): Boolean = scrollingEnabled && super.onInterceptTouchEvent(event)

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean = scrollingEnabled && super.onTouchEvent(event)

    override fun computeScrollDeltaToGetChildRectOnScreen(rect: Rect): Int =
        if (scrollingEnabled && followsCursor()) super.computeScrollDeltaToGetChildRectOnScreen(rect) else 0
}

/** The text view behind the reader: Copy and Share take the text from the model, not the characters on screen. */
@SuppressLint("AppCompatCustomView", "ViewConstructor")
internal class ReaderTextView(context: Context) : TextView(context) {

    var onSelection: ((Int, Int) -> Unit)? = null
    var copyText: (() -> String?)? = null
    /** Puts copied text on the system clipboard. A test replaces it to see what Copy put there: an app may read the clipboard only
     *  while its window has focus, which a test cannot count on. */
    var putOnClipboard: (String) -> Unit = { text ->
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText(null, text))
    }
    var afterCopy: (() -> Unit)? = null
    var share: ((String) -> Unit)? = null
    /** The direction of every paragraph, whatever its first letter is. */
    var paragraphDirection: TextDirectionHeuristic? = null

    @Suppress("UNNECESSARY_SAFE_CALL", "USELESS_ELVIS")
    override fun getTextDirectionHeuristic(): TextDirectionHeuristic = paragraphDirection ?: super.getTextDirectionHeuristic()

    override fun onSelectionChanged(selStart: Int, selEnd: Int) {
        super.onSelectionChanged(selStart, selEnd)
        // Also called while the superclass is being made, before this class's properties exist.
        @Suppress("UNNECESSARY_SAFE_CALL")
        onSelection?.invoke(max(min(selStart, selEnd), 0), max(max(selStart, selEnd), 0))
    }

    override fun onTextContextMenuItem(id: Int): Boolean {
        when (id) {
            android.R.id.copy -> copyText?.invoke()?.let { text ->
                putOnClipboard(text)
                afterCopy?.invoke()
                return true
            }
            android.R.id.shareText -> copyText?.invoke()?.let { text ->
                share?.invoke(text)
                afterCopy?.invoke()
                return true
            }
        }
        return super.onTextContextMenuItem(id)
    }
}
