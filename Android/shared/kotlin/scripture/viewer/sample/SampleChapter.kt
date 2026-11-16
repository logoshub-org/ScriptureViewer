// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package scripture.viewer.sample

import android.content.res.AssetManager
import org.json.JSONArray
import scripture.text.ChapterEntries
import scripture.text.ScriptureContentProfile
import scripture.text.ScriptureDisplayOptions
import scripture.text.ScriptureModuleFacts
import scripture.text.ScriptureSourceType
import scripture.text.ScriptureText
import scripture.text.osis.OSISParser

/**
 * Psalm 119 of the KJV, parsed on the device from its raw OSIS by the transpiled core: the chapter the demo shows and the tests
 * measure. The entries are the file the core's parity test reads (`Transpile/Tests/ScriptureTextOSISTests/Resources/entries.json`).
 */
object SampleChapter {

    fun psalm119(assets: AssetManager, markers: Boolean = false, versePerLine: Boolean = false): ScriptureText {
        val strings = JSONArray(assets.open("entries.json").bufferedReader().use { it.readText() })
        val raw = ArrayList<ChapterEntries.Entry>()
        for (index in 0 until strings.length()) raw.add(ChapterEntries.Entry(verse = index, text = strings.getString(index)))

        val display = ScriptureDisplayOptions()
        display.headings = true
        display.strongs = markers
        display.morph = markers
        display.versePerLine = versePerLine

        val facts = ScriptureModuleFacts(name = "KJV", sourceType = ScriptureSourceType.osis, versification = "KJV")
        val options = OSISParser.Options()
        options.headings = display.headings
        options.redLetter = display.redLetter
        options.footnotes = display.footnotes
        options.crossReferences = display.crossReferences
        options.versePerLine = display.versePerLine
        options.strongsMarkers = display.strongs
        options.morphMarkers = display.morph
        options.quoteMarks = facts.osisQToTick
        val transforms = facts.textTransforms(greekAccents = display.greekAccents, hebrewPoints = display.hebrewPoints,
                                              hebrewCantillation = display.hebrewCantillation)
        options.greekAccents = transforms.greekAccents
        options.hebrewPoints = transforms.hebrewPoints
        options.hebrewCantillation = transforms.hebrewCantillation

        val entries = ArrayList<OSISParser.VerseEntry>()
        for (entry in ChapterEntries.shown(skip.lib.Array(raw))) entries.add(OSISParser.VerseEntry(verse = entry.verse, osis = entry.text))
        return OSISParser(options = options, profile = ScriptureContentProfile.chapter)
            .parse(skip.lib.Array(entries), identity = facts.identity(book = "Ps", chapter = 119))
    }
}
