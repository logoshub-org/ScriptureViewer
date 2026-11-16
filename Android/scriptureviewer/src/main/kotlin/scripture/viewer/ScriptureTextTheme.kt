// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package scripture.viewer

import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import scripture.text.HighlightStyle
import scripture.text.ScriptureStyleSheet
import scripture.text.ScriptureViewerTheme
import skip.lib.sref
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * The Android realisation of a [ScriptureViewerTheme]: the colours, the typeface and the sizes in pixels that the styler and the
 * view use. The counterpart of the iOS `ScriptureTextTheme`; the rules themselves (scales, indents, spacing) stay in the portable
 * style sheet.
 *
 * Sizes follow the iOS theme: the contract's font size is in CSS points, one CSS point is 4/3 of a density-independent unit, and
 * every derived size is rounded to a whole unit before it becomes pixels. The unit is the scaled pixel (sp), so the text also follows
 * the system's font size setting.
 */
internal class ScriptureTextTheme(theme: ScriptureViewerTheme, density: Float, fontScale: Float) {

    val nightMode: Boolean = theme.nightMode
    val isWide: Boolean = theme.isWide
    val rightToLeft: Boolean = theme.rightToLeft

    /** The custom sheet as given, or the classic sheet with the legacy line height (wider on a tablet). */
    val styleSheet: ScriptureStyleSheet = theme.styleSheet ?: ScriptureStyleSheet.classic.sref().also {
        it.lineHeight = if (theme.isWide) wideLineHeight else phoneLineHeight
    }

    /** The body size in scaled pixels (sp). */
    val fontSize: Double = theme.fontSize * cssPointToSp
    private val pixelsPerUnit: Double = density.toDouble() * fontScale
    val typeface: Typeface = typeface(named = theme.fontName)

    // Colours: the legacy reader's, as on iOS.
    val textColor: Int = if (nightMode) Color.WHITE else Color.BLACK
    val backgroundColor: Int = if (nightMode) Color.BLACK else Color.WHITE
    val redLetterColor: Int = Color.rgb(0xD0, 0x30, 0x30)
    val markerColor: Int = Color.rgb(0x80, 0x80, 0x80)
    val linkColor: Int = Color.rgb(0xFF, 0x00, 0xFF)

    fun color(role: ScriptureStyleSheet.ColorRole): Int = when (role) {
        ScriptureStyleSheet.ColorRole.text -> textColor
        ScriptureStyleSheet.ColorRole.marker -> markerColor
        ScriptureStyleSheet.ColorRole.redLetter -> redLetterColor
        ScriptureStyleSheet.ColorRole.link -> linkColor
    }

    // Sizes

    val bodyPx: Float = (fontSize * pixelsPerUnit).toFloat()

    /** A size that is `scale` times the body size, in whole units, as pixels. */
    fun sizePx(scale: Double): Int = max((Math.round(fontSize * scale) * pixelsPerUnit).roundToInt(), 1)

    /** A length given in em (multiples of the body size), in whole units, as pixels: a raise, a space above or below. */
    fun emPx(em: Double): Int = (Math.round(fontSize * em) * pixelsPerUnit).roundToInt()

    /** An indent in em, as pixels (not rounded to a unit, as on iOS). */
    fun indentPx(em: Double): Int = (fontSize * em * pixelsPerUnit).roundToInt()

    val smallPx: Int get() = sizePx(styleSheet.smallScale)
    val divineNamePx: Int get() = sizePx(styleSheet.divineNameScale)

    /**
     * The ascent and descent a line of text at `sizePx` is given, so that the line is `lineHeight` times the size high, as CSS means
     * it (half the extra above, half below). A font whose own line is higher keeps its own height.
     */
    fun lineMetrics(sizePx: Float): LineMetrics {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.typeface = typeface
        paint.textSize = sizePx
        val font = paint.fontMetricsInt
        val ascent = -font.ascent
        val descent = font.descent
        val wanted = (styleSheet.lineHeight * sizePx).roundToInt()
        val extra = wanted - (ascent + descent)
        if (extra <= 0) return LineMetrics(ascent, descent)
        val above = ascent + (extra + 1) / 2
        return LineMetrics(above, wanted - above)
    }

    // Highlights

    /** The background and, for a search hit, the text colour of a highlight (the text keeps its own colour on a bookmark). */
    fun highlightColors(style: HighlightStyle): HighlightColors {
        val hex = style.colour
        if (style.name == "bookmark" && hex != null) {
            colour(fromHex = hex)?.let { colour ->
                return HighlightColors(background = (colour and 0x00FFFFFF) or ((bookmarkHighlightAlpha * 255).roundToInt() shl 24), text = null)
            }
        }
        return HighlightColors(background = Color.YELLOW, text = Color.BLACK)
    }

    class LineMetrics(val ascent: Int, val descent: Int)
    class HighlightColors(val background: Int, val text: Int?)

    companion object {
        /** The stored size preference is a CSS point value; one CSS point is 4/3 CSS pixels, and a CSS pixel is one sp here. */
        const val cssPointToSp = 4.0 / 3.0
        const val phoneLineHeight = 1.4
        const val wideLineHeight = 1.6
        /** How much of a folder's colour a bookmark highlight shows. */
        const val bookmarkHighlightAlpha = 0.35f
        /** How much of its colour the text outside a focused verse keeps. */
        const val dimmedAlpha = 0.35f

        /** The text's margin from each side, in dp: 10 on the wide layout, 16 on a phone, as on iOS. */
        fun sideMarginDp(isWide: Boolean): Float = if (isWide) 10f else 16f

        /** `#RRGGBB` as an opaque colour; null for anything else. */
        fun colour(fromHex: String): Int? {
            val digits = if (fromHex.startsWith("#")) fromHex.substring(1) else fromHex
            if (digits.length != 6) return null
            val value = digits.toIntOrNull(16) ?: return null
            return value or (0xFF shl 24)
        }

        /**
         * The typeface for a font name of the preference. The names come from the iOS font list; the ones that are serif or
         * monospaced there get Android's serif or monospace family, a family Android knows by that name is used as it is, and
         * anything else is the system's sans serif.
         */
        fun typeface(named: String): Typeface {
            val name = named.lowercase()
            val serif = listOf("times", "georgia", "palatino", "baskerville", "didot", "cochin", "hoefler", "charter", "iowan", "bodoni")
            val mono = listOf("courier", "menlo", "mono")
            return when {
                mono.any { name.contains(it) } -> Typeface.MONOSPACE
                serif.any { name.contains(it) } || (name.contains("serif") && !name.contains("sans")) -> Typeface.SERIF
                else -> Typeface.create(named, Typeface.NORMAL) ?: Typeface.DEFAULT
            }
        }
    }
}
