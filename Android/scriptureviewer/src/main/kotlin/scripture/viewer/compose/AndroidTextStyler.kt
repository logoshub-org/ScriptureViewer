// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package scripture.viewer.compose

import android.graphics.Paint
import android.graphics.Typeface
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextPaint
import android.text.style.AbsoluteSizeSpan
import android.text.style.AlignmentSpan
import android.text.style.BackgroundColorSpan
import android.text.style.CharacterStyle
import android.text.style.ForegroundColorSpan
import android.text.style.LeadingMarginSpan
import android.text.style.LineHeightSpan
import android.text.style.MetricAffectingSpan
import android.text.style.StyleSpan
import android.text.style.UpdateAppearance
import scripture.text.ScriptureStyleSheet
import scripture.text.ScriptureText
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * ScriptureText to a `Spannable`: resolves the model's semantic spans to sizes, styles, colours and paragraph rules through a
 * [ScriptureTextTheme]. The Android half of the iOS `ScriptureTextStyler`. Taps are not marked in the text: the view finds the
 * character under a tap and asks the model what it is.
 */
internal object ScriptureTextStyler {

    fun spannable(scripture: ScriptureText, theme: ScriptureTextTheme): SpannableStringBuilder {
        val text = scripture.text
        val result = SpannableStringBuilder(text)
        val length = result.length
        if (length == 0) return result
        val sheet = theme.styleSheet

        // Paragraph roles resolve against the portable sheet, once, for every platform.
        val paragraphs = ArrayList<ParagraphMetricsSpan.Paragraph>()
        for (block in sheet.resolveBlocks(in_ = scripture)) {
            val start = block.start.coerceIn(0, length)
            val end = (block.start + block.length).coerceIn(start, length)
            // A paragraph rule covers whole paragraphs: from the line's start to past its line break.
            val paragraphStart = text.lastIndexOf('\n', start - 1) + 1
            val lineBreak = text.indexOf('\n', max(end, start))
            val paragraphEnd = if (lineBreak < 0) length else lineBreak + 1
            val style = block.style

            when (style.alignment) {
                ScriptureStyleSheet.Alignment.center ->
                    result.set(AlignmentSpan.Standard(Layout.Alignment.ALIGN_CENTER), paragraphStart, paragraphEnd)
                // The far side of the module's writing direction: right in a left-to-right Bible.
                ScriptureStyleSheet.Alignment.trailing ->
                    result.set(AlignmentSpan.Standard(Layout.Alignment.ALIGN_OPPOSITE), paragraphStart, paragraphEnd)
                ScriptureStyleSheet.Alignment.leading -> {}
            }
            val firstIndent = theme.indentPx(style.firstLineIndent)
            val wrapIndent = theme.indentPx(style.wrapIndent)
            if (firstIndent != 0 || wrapIndent != 0) {
                result.set(LeadingMarginSpan.Standard(firstIndent, wrapIndent), paragraphStart, paragraphEnd)
            }
            var sizePx = theme.bodyPx
            if (style.sizeScale != 1.0) {
                val scaled = theme.sizePx(style.sizeScale)
                sizePx = scaled.toFloat()
                result.set(AbsoluteSizeSpan(scaled), start, end)
            }
            if (style.bold) result.set(StyleSpan(Typeface.BOLD), start, end)
            if (style.italic) result.set(StyleSpan(Typeface.ITALIC), start, end)
            paragraphs.add(ParagraphMetricsSpan.Paragraph(paragraphStart, paragraphEnd, end, theme.lineMetrics(sizePx),
                                                          theme.emPx(block.spaceBefore), theme.emPx(block.spaceAfter)))
        }
        // One span sets every line's height and the space around the role paragraphs.
        result.set(ParagraphMetricsSpan(theme.lineMetrics(theme.bodyPx), paragraphs.sortedBy { it.start }), 0, length)

        // Marker runs set their own size from the body size, so they go last: a later `.small` span must not undo the marker size.
        val plain = ArrayList<ScriptureText.Span>()
        val markers = ArrayList<ScriptureText.Span>()
        for (span in scripture.spans) {
            when (span.attribute) {
                is ScriptureText.Attribute.StrongsCase, is ScriptureText.Attribute.MorphCase, is ScriptureText.Attribute.FootnoteCase -> markers.add(span)
                else -> plain.add(span)
            }
        }
        for (span in plain + markers) {
            val start = span.start.coerceIn(0, length)
            val end = (span.start + span.length).coerceIn(start, length)
            if (end <= start) continue
            when (span.attribute) {
                is ScriptureText.Attribute.BlockCase -> {}    // applied above
                // The number keeps the colour of the text it is in (red in the words of Christ), as on iOS.
                is ScriptureText.Attribute.VerseNumberCase ->
                    result.set(RaisedSpan(theme.sizePx(sheet.verseNumber.sizeScale), theme.emPx(sheet.verseNumber.raise), null, false), start, end)
                is ScriptureText.Attribute.RedLetterCase -> result.set(ForegroundColorSpan(theme.redLetterColor), start, end)
                is ScriptureText.Attribute.SmallCase -> result.set(AbsoluteSizeSpan(theme.smallPx), start, end)
                is ScriptureText.Attribute.BoldCase -> result.set(StyleSpan(Typeface.BOLD), start, end)
                is ScriptureText.Attribute.ItalicCase -> result.set(StyleSpan(Typeface.ITALIC), start, end)
                is ScriptureText.Attribute.StrongsCase, is ScriptureText.Attribute.MorphCase ->
                    styleMarker(result, start, end, theme, sheet.lexicalMarker)
                is ScriptureText.Attribute.FootnoteCase -> styleMarker(result, start, end, theme, sheet.footnoteMarker)
                // A word's own lexical data: tappable, but styled as ordinary text.
                is ScriptureText.Attribute.WordCase -> {}
                is ScriptureText.Attribute.DivineNameCase -> {
                    // The text is already capitals: the first letter keeps the body size and the rest is smaller (L + smaller ORD).
                    val tail = min(start + Character.charCount(Character.codePointAt(text, start)), end)
                    if (tail < end) result.set(AbsoluteSizeSpan(theme.divineNamePx), tail, end)
                }
                // Not a URLSpan: the view finds the tap and the host decides what a link does.
                is ScriptureText.Attribute.LinkCase -> result.set(ForegroundColorSpan(theme.linkColor), start, end)
            }
        }
        return result
    }

    /** Strong's, morphology and footnote markers: a raised, smaller, coloured run, per the sheet. */
    private fun styleMarker(text: SpannableStringBuilder, start: Int, end: Int, theme: ScriptureTextTheme, style: ScriptureStyleSheet.Superscript) {
        text.set(RaisedSpan(theme.sizePx(style.sizeScale), theme.emPx(style.raise), theme.color(style.color), style.italic), start, end)
    }

    private fun SpannableStringBuilder.set(span: Any, start: Int, end: Int) {
        if (end > start) setSpan(span, start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    }
}

/**
 * A raised, smaller run: a verse number or a marker. One span for its size, its raise above the baseline, its colour and its
 * slant, because a chapter with Strong's numbers has a couple of thousand of them and each span costs time to set and to lay out.
 */
internal class RaisedSpan(val sizePx: Int, val raisePx: Int, val colour: Int?, val italic: Boolean) : MetricAffectingSpan() {

    override fun updateDrawState(paint: TextPaint) {
        apply(paint)
        colour?.let { paint.color = it }
    }

    override fun updateMeasureState(paint: TextPaint) = apply(paint)

    private fun apply(paint: TextPaint) {
        paint.textSize = sizePx.toFloat()
        paint.baselineShift -= raisePx
        if (italic) {
            val current = paint.typeface ?: Typeface.DEFAULT
            val slanted = Typeface.create(current, current.style or Typeface.ITALIC)
            // A family with no italic face of its own is slanted by the paint, as `StyleSpan` does.
            if (!slanted.isItalic) paint.textSkewX = -0.25f
            paint.typeface = slanted
        }
    }
}

/** The text outside a focused verse: each run keeps its own colour, at a part of its strength. Changes no measurement. */
internal class DimSpan(private val alpha: Float) : CharacterStyle(), UpdateAppearance {
    override fun updateDrawState(paint: TextPaint) {
        val colour = paint.color
        paint.color = (colour and 0x00FFFFFF) or (((colour ushr 24) * alpha).roundToInt() shl 24)
    }
}

/** A highlight's background and text colour, as spans of their own class so they are told apart from the styled text's. */
internal class HighlightBackgroundSpan(colour: Int) : BackgroundColorSpan(colour)
internal class HighlightTextSpan(colour: Int) : ForegroundColorSpan(colour)

/**
 * The line height and the paragraph spacing of the whole text, as one span. Each line gets the ascent and descent its paragraph's
 * size asks for (the style sheet's line height, as CSS means it), so lines with a raised verse number or a marker are no higher than
 * the others; a role paragraph also gets its space above its first line and below its last.
 */
internal class ParagraphMetricsSpan(private val body: ScriptureTextTheme.LineMetrics, private val paragraphs: List<Paragraph>) : LineHeightSpan {

    /** A role paragraph: `start` to `end` with its line break, its text ending at `textEnd`. */
    class Paragraph(val start: Int, val end: Int, val textEnd: Int, val metrics: ScriptureTextTheme.LineMetrics,
                    val spaceBefore: Int, val spaceAfter: Int)

    override fun chooseHeight(text: CharSequence, start: Int, end: Int, spanstartv: Int, lineHeight: Int, fm: Paint.FontMetricsInt) {
        val paragraph = paragraph(at = start)
        val metrics = paragraph?.metrics ?: body
        if (fm.ascent > -metrics.ascent) fm.ascent = -metrics.ascent
        if (fm.descent < metrics.descent) fm.descent = metrics.descent
        if (paragraph != null) {
            if (start <= paragraph.start) fm.ascent -= paragraph.spaceBefore
            if (end >= paragraph.textEnd) fm.descent += paragraph.spaceAfter
        }
        if (fm.top > fm.ascent) fm.top = fm.ascent
        if (fm.bottom < fm.descent) fm.bottom = fm.descent
    }

    /** How far below a line's top its text begins: the space above a role paragraph's first line. */
    fun spaceAbove(lineStart: Int): Int {
        val paragraph = paragraph(at = lineStart) ?: return 0
        return if (lineStart <= paragraph.start) paragraph.spaceBefore else 0
    }

    private fun paragraph(at: Int): Paragraph? {
        var low = 0
        var high = paragraphs.size - 1
        while (low <= high) {
            val middle = (low + high) / 2
            val candidate = paragraphs[middle]
            when {
                at < candidate.start -> high = middle - 1
                at >= candidate.end -> low = middle + 1
                else -> return candidate
            }
        }
        return null
    }
}
