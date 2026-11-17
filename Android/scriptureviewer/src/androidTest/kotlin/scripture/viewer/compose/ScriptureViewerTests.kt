// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package scripture.viewer.compose

import android.content.ClipboardManager
import android.content.Context
import android.text.Layout
import android.text.Spanned
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipe
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import scripture.text.ScriptureHighlights
import scripture.text.ScriptureMenuItem
import scripture.text.ScriptureSelection
import scripture.text.ScriptureText
import scripture.text.ScriptureViewerChromeRequest
import scripture.text.ScriptureViewerConfiguration
import scripture.text.ScriptureViewerController
import scripture.text.ScriptureViewerEvents
import scripture.text.ScriptureViewerGesture
import scripture.text.ScriptureViewerPull
import scripture.text.ScriptureViewerTheme
import scripture.text.TapKind
import scripture.text.TapTarget
import scripture.viewer.sample.SampleChapter
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * The Android viewer against the contract, on a device or an emulator, with Psalm 119 of the KJV parsed there by the transpiled
 * core. The list is the iOS `ScriptureViewerViewTests` plus what plan D185 asked to be proved for a `TextView` inside Compose.
 */
@RunWith(AndroidJUnit4::class)
class ScriptureViewerTests {

    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    /** What a host screen holds: the contract's values as state, the controller, and a record of every event. */
    private class Host {
        var text by mutableStateOf(ScriptureText())
        var theme by mutableStateOf(ScriptureViewerTheme())
        var highlights by mutableStateOf(ScriptureHighlights())
        var configuration by mutableStateOf(ScriptureViewerConfiguration())
        val controller = ScriptureViewerController()
        val events = ScriptureViewerEvents()

        val taps = ArrayList<TapTarget>()
        val gestures = ArrayList<ScriptureViewerGesture>()
        val pulls = ArrayList<ScriptureViewerPull>()
        val chrome = ArrayList<ScriptureViewerChromeRequest>()
        val scrolls = ArrayList<Pair<Double, Int>>()
        val selections = ArrayList<ScriptureSelection?>()
        val menu = ArrayList<Pair<String, ScriptureSelection>>()
        var ends = 0
        var mayHideChrome = false

        init {
            events.onTap = { taps.add(it) }
            events.onGesture = { gestures.add(it) }
            events.onPull = { pulls.add(it) }
            events.onScroll = { offset, verse -> scrolls.add(offset to verse) }
            events.onSelectionChange = { selections.add(it) }
            events.onMenuItem = { id, selection -> menu.add(id to selection) }
            events.onReachedEnd = { ends += 1 }
            events.referenceLine = { verses -> "Psalms 119:${verses.start}–${verses.endInclusive} (KJV)" }
        }

        fun listenForChrome() {
            events.onChromeRequest = { chrome.add(it) }
            events.canHideChrome = { mayHideChrome }
        }
    }

    private val assets get() = InstrumentationRegistry.getInstrumentation().context.assets
    private val psalm: ScriptureText by lazy { SampleChapter.psalm119(assets) }
    private val psalmWithMarkers: ScriptureText by lazy { SampleChapter.psalm119(assets, markers = true) }

    private fun show(host: Host) {
        compose.setContent {
            Box(Modifier.fillMaxSize()) {
                ScriptureViewer(text = host.text, modifier = Modifier.fillMaxSize().testTag("viewer"), theme = host.theme,
                                highlights = host.highlights, configuration = host.configuration, controller = host.controller, events = host.events)
                // A host view that reads the controller's observable state.
                BasicText(host.controller.currentVerse.toString(), Modifier.testTag("verse"))
            }
        }
        compose.waitForIdle()
    }

    private fun showPsalm(configure: Host.() -> Unit = {}): Host {
        val host = Host()
        host.text = psalm
        host.configure()
        show(host)
        return host
    }

    private fun viewer(): ScriptureTextView {
        fun find(view: View): ScriptureTextView? {
            if (view is ScriptureTextView) return view
            if (view is ViewGroup) for (index in 0 until view.childCount) find(view.getChildAt(index))?.let { return it }
            return null
        }
        return compose.runOnUiThread<ScriptureTextView> { find(compose.activity.window.decorView)!! }
    }

    private fun <T> onMain(block: () -> T): T {
        compose.waitForIdle()
        return compose.runOnUiThread<T> { block() }
    }

    /** The centre of a character of the text, as a point of the viewer on screen. */
    private fun pointOfCharacter(view: ScriptureTextView, offset: Int): Offset = onMain {
        val rect = view.rectOfCharacter(offset)!!
        Offset(rect.centerX() + view.textView.totalPaddingLeft + view.textView.left + view.scroll.left,
               rect.centerY() + view.textView.totalPaddingTop + view.textView.top + view.scroll.top - view.scroll.scrollY)
    }

    /** Waits until a fling has run out: the text has stopped moving. */
    private fun waitForRest(view: ScriptureTextView) {
        var last = -1
        compose.waitUntil(10_000) {
            Thread.sleep(250)
            val now = compose.runOnUiThread<Int> { view.scroll.scrollY }
            (now == last).also { last = now }
        }
        Thread.sleep(200)
    }

    private fun verseNumberStart(text: ScriptureText, verse: Int): Int {
        for (span in text.spans) {
            val attribute = span.attribute
            if (attribute is ScriptureText.Attribute.VerseNumberCase && attribute.associated0 == verse) return span.start
        }
        throw AssertionError("no verse number $verse")
    }

    // MARK: The text reaches the view

    @Test
    fun theTextAndTheThemeReachTheView() {
        val host = showPsalm { theme = ScriptureViewerTheme(nightMode = true, fontSize = 15.0) }
        val view = viewer()
        onMain {
            assertEquals(psalm.text, view.displayedText)
            assertEquals(psalm.text, view.textView.text.toString())
            assertTrue("a chapter of many lines", view.textView.layout.lineCount > 200)
            // The contract's size is in CSS points: 4/3 of a scaled pixel each.
            val metrics = view.resources.displayMetrics
            assertEquals(15.0f * 4 / 3 * metrics.density * view.resources.configuration.fontScale, view.textView.textSize, 0.5f)
            assertEquals(android.graphics.Color.WHITE, view.textView.currentTextColor)
            // The acrostic heading begins with a Hebrew letter and is still a left-to-right paragraph.
            val heading = psalm.text.indexOf("ALEPH")
            assertEquals(Layout.DIR_LEFT_TO_RIGHT, view.textView.layout.getParagraphDirection(view.textView.layout.getLineForOffset(heading)))
            assertEquals(1, host.controller.currentVerse)
        }
    }

    @Test
    fun aNewTextIsShownAndStartsAtItsTop() {
        val host = showPsalm()
        val view = viewer()
        host.controller.scroll(toVerse = 100)
        onMain { assertTrue(view.scroll.scrollY > 0) }
        host.text = ScriptureText(text = "Another entry.")
        onMain {
            assertEquals("Another entry.", view.displayedText)
            assertEquals(0, view.scroll.scrollY)
            assertEquals(0.0, host.controller.scrollOffset, 0.0)
        }
    }

    // MARK: Verses

    @Test
    fun scrollsToAnExactVerseAndKnowsTheVerseAtTheTop() {
        val host = showPsalm()
        val view = viewer()
        host.controller.scroll(toVerse = 105)
        val first = onMain {
            assertEquals(view.verseTop(105), view.scroll.scrollY)
            assertEquals(105, view.verseAtTop())
            assertEquals(105, host.controller.currentVerse)
            assertEquals(view.scroll.scrollY / view.resources.displayMetrics.density.toDouble(), host.controller.scrollOffset, 0.01)
            view.scroll.scrollY
        }
        // A host view that reads the controller follows it.
        compose.onNodeWithTag("verse").assertTextEquals("105")

        host.controller.scroll(toVerse = 1)
        onMain {
            assertEquals(view.verseTop(1), view.scroll.scrollY)
            assertEquals(1, view.verseAtTop())
        }
        // The last verse stops at the end of the chapter, as any scroll view does.
        host.controller.scroll(toVerse = 176)
        onMain { assertEquals(view.scroll.maxScroll, view.scroll.scrollY) }
        // And the same verse is the same place again.
        host.controller.scroll(toVerse = 105)
        onMain { assertEquals(first, view.scroll.scrollY) }

        // The offset the viewer reported brings the text back to where it was.
        val offset = host.controller.scrollOffset
        host.controller.scroll(toVerse = 1)
        host.controller.scroll(toOffset = offset)
        onMain {
            assertEquals(first, view.scroll.scrollY)
            assertEquals(105, host.controller.currentVerse)
        }
    }

    @Test
    fun commandsSentWithANewTextAreHeldUntilItIsShown() {
        val host = showPsalm()
        val view = viewer()
        // The host changes the text and asks for a verse in the same breath.
        compose.runOnUiThread {
            host.controller.willShowNewText()
            host.text = psalmWithMarkers
            host.controller.scroll(toVerse = 105)
        }
        onMain {
            assertEquals(psalmWithMarkers.text, view.displayedText)
            assertEquals(view.verseTop(105), view.scroll.scrollY)
            assertEquals(105, host.controller.currentVerse)
        }
    }

    @Test
    fun focusDimsTheTextAroundAVerseUntilTheReaderScrolls() {
        val host = showPsalm()
        val view = viewer()
        host.controller.focus(verse = 50)
        val verse = psalm.verseRange(containing = 50)!!
        onMain {
            assertEquals(50, view.focusedVerse)
            assertEquals(listOf(0 to verse.start, verse.start + verse.length to psalm.text.length - verse.start - verse.length), view.dimmedRanges)
            // Near the top, with a little space above it.
            val above = view.verseTop(50)!! - view.scroll.scrollY
            val density = view.resources.displayMetrics.density
            assertTrue("space above the verse: $above", above >= 24 * density - 1 && above <= 96 * density + 1)
        }
        compose.onNodeWithTag("viewer").performTouchInput { swipe(Offset(centerX, height * 0.7f), Offset(centerX, height * 0.4f), 200) }
        compose.waitUntil(5000) { compose.runOnUiThread<Boolean> { view.focusedVerse == null } }
        onMain { assertTrue(view.dimmedRanges.isEmpty()) }

        host.controller.focus(verse = 60)
        onMain { assertEquals(60, view.focusedVerse) }
        host.controller.clearFocus()
        onMain { assertNull(view.focusedVerse) }
    }

    // MARK: Highlights

    @Test
    fun highlightsArePaintedWithoutANewLayout() {
        val host = showPsalm()
        val view = viewer()
        host.controller.scroll(toVerse = 105)
        val before = onMain { Triple(view.textView.layout, view.scroll.scrollY, view.textView.height) }

        host.highlights = ScriptureHighlights(bookmarks = skip.lib.Array(listOf(ScriptureHighlights.Verse(verse = 105, hexColour = "#3478F6"))),
                                              searchTerms = skip.lib.Array(listOf("lamp")))
        onMain {
            assertSame("the layout the text had", before.first, view.textView.layout)
            assertFalse(view.textView.isLayoutRequested)
            assertEquals(before.second, view.scroll.scrollY)
            assertEquals(before.third, view.textView.height)
            val painted = view.paintedHighlights.map { (start, length) -> psalm.text.substring(start, start + length) }
            assertTrue("the verse without its number: $painted", painted.any { it.startsWith("Thy word") && it.contains("light unto my path") })
            assertTrue("the search word: $painted", painted.contains("lamp"))
            val spanned = view.textView.text as Spanned
            assertEquals(2, spanned.getSpans(0, spanned.length, HighlightBackgroundSpan::class.java).size)
            assertEquals(1, spanned.getSpans(0, spanned.length, HighlightTextSpan::class.java).size)
        }

        // A Strong's number marks the words that carry it; leading zeros do not matter.
        host.highlights = ScriptureHighlights(strongs = "H835")
        onMain {
            assertSame(before.first, view.textView.layout)
            val painted = view.paintedHighlights.map { (start, length) -> psalm.text.substring(start, start + length) }
            assertTrue("words with H0835: $painted", painted.isNotEmpty() && painted.all { it.startsWith("Blessed") })
        }

        host.highlights = ScriptureHighlights()
        onMain {
            assertTrue(view.paintedHighlights.isEmpty())
            val spanned = view.textView.text as Spanned
            assertEquals(0, spanned.getSpans(0, spanned.length, HighlightBackgroundSpan::class.java).size)
            assertSame(before.first, view.textView.layout)
        }
    }

    // MARK: Taps

    @Test
    fun findsTheTapTargetUnderAPoint() {
        showPsalm()
        val view = viewer()
        onMain {
            fun target(offset: Int): TapTarget? {
                val rect = view.rectOfCharacter(offset)!!
                return view.tapTarget(rect.centerX() + view.textView.totalPaddingLeft, rect.centerY() + view.textView.totalPaddingTop)
            }
            val number = target(verseNumberStart(psalm, 3))!!
            assertEquals(TapKind.verse, number.kind)
            assertEquals("3", number.key)

            // A word with a Strong's number of its own.
            val word = target(psalm.text.indexOf("Blessed") + 3)!!
            assertEquals(TapKind.word, word.kind)
            assertEquals(1, word.context.verse)
            assertTrue(word.key.contains("H0835"))

            // A word the translators added carries nothing.
            val added = psalm.text.indexOf(" are ") + 2
            assertNull(target(added))
        }
    }

    @Test
    fun aTapOnAVerseNumberIsReportedAndAPlainTapIsAGesture() {
        val host = showPsalm()
        val view = viewer()
        host.controller.scroll(toVerse = 100)
        val onNumber = pointOfCharacter(view, verseNumberStart(psalm, 105))
        compose.onNodeWithTag("viewer").performTouchInput { click(onNumber) }
        compose.waitUntil(3000) { host.taps.isNotEmpty() }
        assertEquals(TapKind.verse, host.taps.last().kind)
        assertEquals("105", host.taps.last().key)
        // A verse number is not plain text: no plain tap follows it.
        Thread.sleep(600)
        assertTrue(host.gestures.isEmpty())

        // A word the translators added ("are" in verse 2) is plain text.
        onMain { view.scroll.scrollTo(0, 0) }
        val onPlain = pointOfCharacter(view, psalm.text.indexOf("Blessed are they") + 9)
        compose.onNodeWithTag("viewer").performTouchInput { click(onPlain) }
        compose.waitUntil(3000) { host.gestures.isNotEmpty() }
        assertEquals(listOf(ScriptureViewerGesture.plainTap), host.gestures)
        assertEquals(1, host.taps.size)
    }

    // MARK: Selection, the menu and copy

    @Test
    fun theSelectionIsReportedAndCopiedAsTheReaderCopies() {
        val host = showPsalm { configuration = ScriptureViewerConfiguration(menuItems = skip.lib.Array(listOf(ScriptureMenuItem(id = "bookmark", title = "Add Bookmark")))) }
        val view = viewer()
        val from = psalm.verseRange(containing = 9)!!
        val to = psalm.verseRange(containing = 11)!!
        val length = to.start + to.length - from.start
        onMain { view.select(from.start, length) }
        onMain {
            val selection = host.controller.selection!!
            assertEquals(from.start, selection.start)
            assertEquals(length, selection.length)
            assertEquals(9..11, selection.verses)
            assertEquals(selection, host.selections.last())

            val copied = view.copiedSelection()!!
            assertEquals("Psalms 119:9–11 (KJV)\n" + psalm.copiedText(utf16Start = from.start, length = length).text, copied)
            assertTrue("the numbers set apart: $copied", copied.contains("\n9 Wherewithal") && copied.contains(" 10 With my whole heart"))

            // The system's Copy puts that text on the clipboard, not the characters on screen.
            assertTrue(view.textView.onTextContextMenuItem(android.R.id.copy))
            val clipboard = view.context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            assertEquals(copied, clipboard.primaryClip?.getItemAt(0)?.text?.toString())
        }

        // An item the host added to the menu, chosen on a selection.
        onMain { view.select(from.start, length) }
        onMain { view.chooseMenuItem("bookmark") }
        assertEquals("bookmark", host.menu.last().first)
        assertEquals(9..11, host.menu.last().second.verses)

        host.controller.clearSelection()
        onMain {
            assertNull(host.controller.selection)
            assertNull(host.selections.last())
            assertEquals(0, view.selectedRange.second)
        }
    }

    @Test
    fun aLongPressSelectsAndTheMenuHasTheHostsItemAndShare() {
        val shared = ArrayList<String>()
        val host = showPsalm {
            configuration = ScriptureViewerConfiguration(menuItems = skip.lib.Array(listOf(ScriptureMenuItem(id = "bookmark", title = "Add Bookmark"))))
            events.onShare = { shared.add(it) }
        }
        val view = viewer()
        // A press held in real time (the test clock of Compose does not make the text view wait): the device does it.
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        val onWord = pointOfCharacter(view, psalm.text.indexOf("undefiled") + 4)
        val onScreen = onMain { IntArray(2).also { view.getLocationOnScreen(it) } }
        val x = onScreen[0] + onWord.x.roundToInt()
        val y = onScreen[1] + onWord.y.roundToInt()
        device.swipe(x, y, x, y, 200)
        compose.waitUntil(5000) { host.selections.lastOrNull() != null }
        val selection = host.selections.last()!!
        assertEquals("undefiled", psalm.text.substring(selection.start, selection.start + selection.length))
        assertEquals(1..1, selection.verses)
        // No tap and no plain tap came of it.
        assertTrue(host.taps.isEmpty())

        val item = device.wait(Until.findObject(By.text("Add Bookmark")), 5000)
        assertNotNull("the host's item in the selection menu", item)
        assertNotNull("the system's Copy beside it", device.findObject(By.text("Copy")))
        item.click()
        compose.waitUntil(5000) { host.menu.isNotEmpty() }
        assertEquals("bookmark", host.menu.last().first)
        assertEquals(1..1, host.menu.last().second.verses)

        // Share hands the host the text as copied.
        onMain { assertTrue(view.textView.onTextContextMenuItem(android.R.id.shareText)) }
        assertEquals(listOf("Psalms 119:1–1 (KJV)\nundefiled"), shared)
    }

    // MARK: Scrolling by hand, the bars and the end

    @Test
    fun scrollingByHandReportsTheVerseAndAsksForTheBars() {
        val host = showPsalm {
            listenForChrome()
            configuration = ScriptureViewerConfiguration(topInset = 56.0, bottomInset = 44.0)
        }
        val view = viewer()
        onMain {
            // The insets are space the text rests clear of.
            val density = view.resources.displayMetrics.density
            assertEquals((56 * density).roundToInt(), view.scroll.paddingTop)
            assertEquals((44 * density).roundToInt(), view.scroll.paddingBottom)
            assertEquals(0, view.scroll.scrollY)
        }
        val node = compose.onNodeWithTag("viewer")
        node.performTouchInput { swipe(Offset(centerX, height * 0.6f), Offset(centerX, height * 0.2f), 300) }
        compose.waitUntil(5000) { host.chrome.isNotEmpty() }
        assertEquals("requests ${host.chrome}, scrolls ${host.scrolls}", ScriptureViewerChromeRequest.hide, host.chrome.first())
        compose.waitUntil(5000) { host.scrolls.isNotEmpty() && host.controller.currentVerse > 1 }
        onMain {
            assertEquals(view.verseAtTop(), host.controller.currentVerse)
            assertEquals(host.scrolls.last().second, host.controller.currentVerse)
        }
        compose.onNodeWithTag("verse").assertTextEquals(host.controller.currentVerse.toString())

        // Up again brings the bars back.
        Thread.sleep(400)
        node.performTouchInput { swipe(Offset(centerX, height * 0.3f), Offset(centerX, height * 0.6f), 300) }
        compose.waitUntil(5000) { host.chrome.last() == ScriptureViewerChromeRequest.show }

        // A tap on the text sends them away when the host allows it, and the next brings them back. (On a word: a word with
        // lexical data is reported as a tap and still counts as plain text.)
        waitForRest(view)
        host.mayHideChrome = true
        val requests = host.chrome.size
        host.controller.scroll(toVerse = 1)
        val onWord = pointOfCharacter(view, psalm.text.indexOf("undefiled") + 4)
        node.performTouchInput { click(onWord) }
        compose.waitUntil(3000) { host.chrome.size == requests + 1 }
        assertEquals(ScriptureViewerChromeRequest.hide, host.chrome.last())
        Thread.sleep(400)
        node.performTouchInput { click(onWord) }
        compose.waitUntil(3000) { host.chrome.size == requests + 2 }
        assertEquals(ScriptureViewerChromeRequest.show, host.chrome.last())
        assertEquals(TapKind.word, host.taps.last().kind)
    }

    @Test
    fun theEndIsReportedOnceWhenTheReaderScrollsThere() {
        val host = showPsalm()
        // Put there by the host: the reader has not read it.
        host.controller.scroll(toVerse = 174)
        onMain { assertEquals(0, host.ends) }
        assertFalse(host.controller.isAtEnd)
        val node = compose.onNodeWithTag("viewer")
        node.performTouchInput { swipe(Offset(centerX, height * 0.7f), Offset(centerX, height * 0.2f), 200) }
        compose.waitUntil(5000) { host.ends == 1 }
        assertTrue(host.controller.isAtEnd)
        node.performTouchInput { swipe(Offset(centerX, height * 0.4f), Offset(centerX, height * 0.6f), 200) }
        node.performTouchInput { swipe(Offset(centerX, height * 0.7f), Offset(centerX, height * 0.2f), 200) }
        Thread.sleep(800)
        onMain { assertEquals(1, host.ends) }
        // A new text is unread again.
        host.text = psalmWithMarkers
        onMain { assertFalse(host.controller.isAtEnd) }
    }

    @Test
    fun swipesPullsAndTheEndOfADragAreGestures() {
        val host = showPsalm { configuration = ScriptureViewerConfiguration(pullChangesChapter = true) }
        val node = compose.onNodeWithTag("viewer")
        node.performTouchInput { swipe(Offset(width * 0.8f, centerY), Offset(width * 0.2f, centerY + 10f), 120) }
        compose.waitUntil(3000) { host.gestures.contains(ScriptureViewerGesture.swipeLeft) }
        node.performTouchInput { swipe(Offset(width * 0.2f, centerY), Offset(width * 0.8f, centerY - 10f), 120) }
        compose.waitUntil(3000) { host.gestures.contains(ScriptureViewerGesture.swipeRight) }
        assertTrue(host.pulls.isEmpty())

        // At the top, a drag on down past it asks for the previous chapter.
        node.performTouchInput { swipe(Offset(centerX, height * 0.2f), Offset(centerX, height * 0.8f), 400) }
        compose.waitUntil(3000) { host.pulls.isNotEmpty() }
        assertEquals(listOf(ScriptureViewerPull.previousChapter), host.pulls)

        // With the pull off and the drag's end wanted (Automatic Fullscreen), letting go is reported.
        host.configuration = ScriptureViewerConfiguration(reportsDragEnd = true)
        compose.waitForIdle()
        node.performTouchInput { swipe(Offset(centerX, height * 0.6f), Offset(centerX, height * 0.4f), 300) }
        compose.waitUntil(3000) { host.gestures.contains(ScriptureViewerGesture.dragEnded) }
        assertEquals(1, host.pulls.size)

        // The three-finger drag's rule: once for each drag, from 100 dp.
        val view = viewer()
        onMain {
            val density = view.resources.displayMetrics.density
            view.resetThreeFingerDrag()
            view.reportThreeFingerDrag(verticalDistance = 60 * density)
            assertFalse(host.gestures.contains(ScriptureViewerGesture.threeFingerDrag))
            view.reportThreeFingerDrag(verticalDistance = -120 * density)
            view.reportThreeFingerDrag(verticalDistance = -160 * density)
            assertEquals(1, host.gestures.count { it == ScriptureViewerGesture.threeFingerDrag })
        }
    }

    // MARK: Sizing

    @Test
    fun aViewerThatDoesNotScrollTakesTheHeightOfItsText() {
        val host = Host()
        host.text = ScriptureText(text = "A note of two lines.\nThe second line.")
        host.configuration = ScriptureViewerConfiguration(topInset = 10.0, bottomInset = 6.0, scrolls = false)
        compose.setContent {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                ScriptureViewer(text = host.text, modifier = Modifier.fillMaxWidth().testTag("viewer"), configuration = host.configuration,
                                controller = host.controller, events = host.events)
                BasicText("below", Modifier.testTag("below"))
            }
        }
        val view = viewer()
        onMain {
            val density = view.resources.displayMetrics.density
            assertEquals(2, view.textView.layout.lineCount)
            assertEquals(view.textView.layout.height + (10 * density).roundToInt() + (6 * density).roundToInt(), view.height)
            assertTrue(view.height < compose.activity.window.decorView.height / 4)
        }
        // Text that fits has been read to its end as soon as it shows.
        compose.waitUntil(3000) { host.ends == 1 }
    }

    // MARK: Accessibility

    @Test
    fun theTextIsReadAsTextNotAsAnEditBox() {
        showPsalm()
        val view = viewer()
        onMain {
            val node = view.textView.createAccessibilityNodeInfo()
            assertEquals("android.widget.TextView", node.className.toString())
            assertFalse(node.isEditable)
            assertTrue(node.text.toString().contains("Blessed are the undefiled"))
            val granularities = node.movementGranularities
            for (wanted in listOf(AccessibilityNodeInfo.MOVEMENT_GRANULARITY_WORD, AccessibilityNodeInfo.MOVEMENT_GRANULARITY_LINE,
                                  AccessibilityNodeInfo.MOVEMENT_GRANULARITY_PARAGRAPH)) {
                assertTrue("moves by granularity $wanted", granularities and wanted != 0)
            }
        }
    }

    // MARK: Measurements (plan D185): logged, not asserted

    @Test
    fun measuresStylingAndFirstLayout() {
        val context = compose.activity
        val metrics = context.resources.displayMetrics
        for ((name, text) in listOf("plain" to psalm, "with Strong's and morphology" to psalmWithMarkers)) {
            onMain {
                val theme = ScriptureTextTheme(ScriptureViewerTheme(), metrics.density, context.resources.configuration.fontScale)
                var styling = 0L
                var layout = 0L
                var lines = 0
                val runs = 5
                repeat(runs) {
                    val view = ScriptureTextView(context)
                    val start = System.nanoTime()
                    view.display(text, theme)
                    val styled = System.nanoTime()
                    view.measure(View.MeasureSpec.makeMeasureSpec(metrics.widthPixels, View.MeasureSpec.EXACTLY),
                                 View.MeasureSpec.makeMeasureSpec(metrics.heightPixels, View.MeasureSpec.EXACTLY))
                    view.layout(0, 0, metrics.widthPixels, metrics.heightPixels)
                    val laidOut = System.nanoTime()
                    styling += styled - start
                    layout += laidOut - styled
                    lines = view.textView.layout.lineCount
                }
                val spans = (ScriptureTextStyler.spannable(text, theme) as Spanned).let { it.getSpans(0, it.length, Any::class.java).size }
                Log.i("ScriptureViewerMeasure", "Psalm 119 $name: ${text.text.length} characters, $spans spans, $lines lines; " +
                        "styling ${styling / runs / 1_000_000.0} ms, measure and layout ${layout / runs / 1_000_000.0} ms (mean of $runs)")
                assertTrue(lines > 200)
            }
        }
        // A highlight change: the time to repaint the spans, with no layout.
        val host = showPsalm()
        val view = viewer()
        onMain {
            val start = System.nanoTime()
            view.setBookmarkHighlights(verses = (1..176).toList(), hexColours = List(176) { "#3478F6" })
            view.highlightSearchTerms(listOf("thy", "word"))
            val elapsed = (System.nanoTime() - start) / 1_000_000.0
            Log.i("ScriptureViewerMeasure", "176 bookmark verses and ${view.paintedHighlights.size - 176} search hits painted in $elapsed ms, layout requested: ${view.textView.isLayoutRequested}")
            assertFalse(view.textView.isLayoutRequested)
        }
        assertTrue(abs(host.controller.scrollOffset) < 1)
    }
}
