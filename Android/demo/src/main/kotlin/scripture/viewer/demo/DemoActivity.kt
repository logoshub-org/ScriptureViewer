// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package scripture.viewer.demo

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import scripture.text.ScriptureHighlights
import scripture.text.ScriptureMenuItem
import scripture.text.ScriptureViewerChromeRequest
import scripture.text.ScriptureViewerConfiguration
import scripture.text.ScriptureViewerController
import scripture.text.ScriptureViewerEvents
import scripture.text.ScriptureViewerTheme
import scripture.viewer.compose.ScriptureViewer
import scripture.viewer.sample.SampleChapter

/** Psalm 119 between two bars, to try the viewer by hand: scrolling, the bars, taps, the selection menu, highlights, TalkBack. */
class DemoActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { DemoScreen() }
    }
}

private val topBarHeight = 56.dp
private val bottomBarHeight = 44.dp

@Composable
fun DemoScreen() {
    val assets = LocalContext.current.assets
    var markers by remember { mutableStateOf(false) }
    var night by remember { mutableStateOf(false) }
    var search by remember { mutableStateOf(false) }
    var bookmarks by remember { mutableStateOf(false) }
    var barsHidden by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("Tap a verse number or a word; select text; scroll.") }
    val controller = remember { ScriptureViewerController() }

    val text = remember(markers) { SampleChapter.psalm119(assets, markers = markers) }
    val theme = remember(night) { ScriptureViewerTheme(nightMode = night) }
    val highlights = remember(search, bookmarks) {
        ScriptureHighlights(
            bookmarks = skip.lib.Array(if (bookmarks) listOf(ScriptureHighlights.Verse(verse = 105, hexColour = "#3478F6"),
                                                              ScriptureHighlights.Verse(verse = 11, hexColour = "#34C759")) else emptyList()),
            searchTerms = skip.lib.Array(if (search) listOf("word") else emptyList()))
    }
    val configuration = remember {
        ScriptureViewerConfiguration(topInset = topBarHeight.value.toDouble(), bottomInset = bottomBarHeight.value.toDouble(),
                                     menuItems = skip.lib.Array(listOf(ScriptureMenuItem(id = "bookmark", title = "Add Bookmark"))))
    }
    val events = remember {
        ScriptureViewerEvents().also { events ->
            events.onTap = { target -> status = "Tap: ${target.kind.rawValue} ${target.key} (verse ${target.context.verse})" }
            events.onGesture = { gesture -> status = "Gesture: $gesture" }
            events.onSelectionChange = { selection -> if (selection != null) status = "Selected ${selection.length} characters, verses ${selection.verses}" }
            events.onMenuItem = { id, selection ->
                status = "Menu: $id on verses ${selection.verses}"
                controller.clearSelection()
            }
            events.onReachedEnd = { status = "Reached the end" }
            events.onChromeRequest = { request -> barsHidden = request == ScriptureViewerChromeRequest.hide }
            events.canHideChrome = { true }
            events.referenceLine = { verses ->
                if (verses.start == verses.endInclusive) "Psalms 119:${verses.start} (KJV)" else "Psalms 119:${verses.start}–${verses.endInclusive} (KJV)"
            }
        }
    }

    val bar = if (night) Color(0xFF222222) else Color(0xFFEEEEEE)
    val ink = if (night) Color.White else Color.Black
    Box(Modifier.fillMaxSize().background(if (night) Color.Black else Color.White).windowInsetsPadding(WindowInsets.systemBars)) {
        ScriptureViewer(text = text, modifier = Modifier.fillMaxSize().testTag("viewer"), theme = theme, highlights = highlights,
                        configuration = configuration, controller = controller, events = events)

        if (!barsHidden) {
            Row(Modifier.align(Alignment.TopCenter).fillMaxWidth().height(topBarHeight).background(bar).padding(horizontal = 12.dp)
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                // The title reads the controller's observable state: it follows the verse at the top as the text scrolls.
                BasicText("Ps 119:${controller.currentVerse}", style = TextStyle(color = ink, fontSize = 18.sp, fontWeight = FontWeight.Bold))
                BarButton("105", ink) { controller.scroll(toVerse = 105) }
                BarButton("Focus 50", ink) { controller.focus(verse = 50) }
                BarButton(if (markers) "Plain" else "Strong's", ink) {
                    // A new text: the scroll back to the verse is held until the viewer has shown it.
                    val verse = controller.currentVerse
                    controller.willShowNewText()
                    markers = !markers
                    controller.scroll(toVerse = verse)
                }
                BarButton(if (search) "No search" else "Search", ink) { search = !search }
                BarButton(if (bookmarks) "No marks" else "Marks", ink) { bookmarks = !bookmarks }
                BarButton(if (night) "Day" else "Night", ink) {
                    val verse = controller.currentVerse
                    controller.willShowNewText()
                    night = !night
                    controller.scroll(toVerse = verse)
                }
            }
            Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(bottomBarHeight).background(bar).padding(horizontal = 12.dp),
                contentAlignment = Alignment.CenterStart) {
                BasicText(status, style = TextStyle(color = ink, fontSize = 13.sp), maxLines = 2)
            }
        }
    }
}

@Composable
private fun BarButton(label: String, ink: Color, action: () -> Unit) {
    BasicText(label, modifier = Modifier.clickable(onClick = action).padding(vertical = 12.dp), style = TextStyle(color = ink, fontSize = 15.sp))
}
