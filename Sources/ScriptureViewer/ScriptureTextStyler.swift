// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if canImport(UIKit)

import UIKit
import ScriptureText

/// ScriptureText → NSAttributedString (plan Phase 3b): resolves the model's
/// semantic spans to fonts, colours and paragraph styles through ScriptureTextTheme,
/// and sets the custom keys tap routing and verse tracking need. The iOS half
/// of the `UniversalAttributedString` idea (D31); Android's counterpart maps
/// the same model to Spannable/AnnotatedString.
package struct ScriptureTextStyler {

	/// Custom attribute keys. `scriptureVerse` covers each verse's whole range (for
	/// current-verse tracking) and its number marker; the others mark tappable
	/// runs, routed in Phase 5 with `dataForLink:` semantics.
	package static let scriptureVerse = NSAttributedString.Key("scriptureVerse")
	package static let scriptureStrongs = NSAttributedString.Key("scriptureStrongs")
	package static let scriptureMorph = NSAttributedString.Key("scriptureMorph")
	package static let scriptureFootnoteID = NSAttributedString.Key("scriptureFootnoteID")
	package static let scriptureLink = NSAttributedString.Key("scriptureLink")

	package func attributedString(for scripture: ScriptureText, theme: ScriptureTextTheme) -> NSAttributedString {
		let result = NSMutableAttributedString(string: scripture.text, attributes: [
			.font: theme.bodyFont,
			.foregroundColor: theme.textColor,
			.paragraphStyle: theme.baseParagraphStyle(),
		])

		// Verse ranges first, so spans can refine inside them.
		for verse in scripture.verses {
			result.addAttribute(Self.scriptureVerse, value: verse.verse,
			                    range: NSRange(location: verse.start, length: verse.length))
		}

		// Paragraph roles resolve against the portable sheet (D41), once, for every platform.
		for block in theme.styleSheet.resolveBlocks(in: scripture) {
			let range = NSRange(location: block.start, length: block.length)
			result.addAttribute(.paragraphStyle, value: theme.paragraphStyle(for: block), range: range)
			if block.style.sizeScale != 1 {
				setFontSize((theme.fontSize * CGFloat(block.style.sizeScale)).rounded(), in: result, range: range)
			}
			var traits: UIFontDescriptor.SymbolicTraits = []
			if block.style.bold { traits.insert(.traitBold) }
			if block.style.italic { traits.insert(.traitItalic) }
			if !traits.isEmpty { addTraits(traits, to: result, range: range) }
		}

		// Marker runs set their own size from the body size, so they go last: SWORD's HTML wraps
		// a Strong's number in `<small>`, and a later `.small` span must not undo the marker size.
		let isMarker: (ScriptureText.Span) -> Bool = {
			switch $0.attribute {
			case .strongs, .morph, .footnote: return true
			default: return false
			}
		}
		for span in scripture.spans.filter({ !isMarker($0) }) + scripture.spans.filter(isMarker) {
			let range = NSRange(location: span.start, length: span.length)
			switch span.attribute {

			case .block:
				break    // applied above

			case .verseNumber(let verse):
				setFontSize(theme.fontSize(for: theme.styleSheet.verseNumber), in: result, range: range)
				result.addAttributes([
					.baselineOffset: theme.baselineOffset(for: theme.styleSheet.verseNumber),
					Self.scriptureVerse: verse,
				], range: range)

			case .redLetter:
				result.addAttribute(.foregroundColor, value: theme.redLetterColor, range: range)

			case .small:
				setFontSize(theme.smallFontSize, in: result, range: range)

			case .bold:
				addTraits(.traitBold, to: result, range: range)

			case .italic:
				addTraits(.traitItalic, to: result, range: range)

			case .strongs(let key):
				styleMarker(in: result, range: range, theme: theme, style: theme.styleSheet.lexicalMarker)
				result.addAttribute(Self.scriptureStrongs, value: key, range: range)

			case .morph(let key):
				styleMarker(in: result, range: range, theme: theme, style: theme.styleSheet.lexicalMarker)
				result.addAttribute(Self.scriptureMorph, value: key, range: range)

			case .footnote(let id):
				styleMarker(in: result, range: range, theme: theme, style: theme.styleSheet.footnoteMarker)
				result.addAttribute(Self.scriptureFootnoteID, value: id, range: range)

			case .word(let lemma, let morph):
				// A word's own lexical data: tappable, but styled as ordinary text.
				if let lemma { result.addAttribute(Self.scriptureStrongs, value: lemma, range: range) }
				if let morph { result.addAttribute(Self.scriptureMorph, value: morph, range: range) }

			case .divineName:
				setDivineNameSize(in: result, range: range, theme: theme)

			case .link(let target):
				// Not NSAttributedString's `.link`: UITextView would open the URL itself. The view
				// finds the tap and the host decides (D58); this key records the target for tests
				// and accessibility.
				result.addAttribute(Self.scriptureLink, value: target, range: range)
				result.addAttribute(.foregroundColor, value: theme.linkColor, range: range)
			}
		}
		return result
	}

	// MARK: Font helpers (trait- and size-preserving)

	/// Strong's, morph and footnote markers: a raised, smaller, coloured run, per the sheet.
	private func styleMarker(in text: NSMutableAttributedString, range: NSRange,
	                         theme: ScriptureTextTheme, style: ScriptureStyleSheet.Superscript) {
		setFontSize(theme.fontSize(for: style), in: text, range: range)
		if style.italic { addTraits(.traitItalic, to: text, range: range) }
		text.addAttributes([
			.foregroundColor: theme.color(for: style.color),
			.baselineOffset: theme.baselineOffset(for: style),
		], range: range)
	}

	/// OSIS `<divineName>`: the text is already capitals; the first letter keeps the body
	/// size and the rest is smaller, as SWORD's HTML sets it (L + smaller ORD). Real small
	/// capitals would need a font that has them; Helvetica Neue does not.
	private func setDivineNameSize(in text: NSMutableAttributedString, range: NSRange, theme: ScriptureTextTheme) {
		guard range.length > 0 else { return }
		let first = (text.string as NSString).rangeOfComposedCharacterSequence(at: range.location)
		let tailStart = min(first.location + first.length, range.location + range.length)
		let tail = NSRange(location: tailStart, length: range.location + range.length - tailStart)
		guard tail.length > 0 else { return }
		setFontSize(theme.divineNameFontSize, in: text, range: tail)
	}

	private func setFontSize(_ size: CGFloat, in text: NSMutableAttributedString, range: NSRange) {
		mutateFonts(in: text, range: range) { UIFont(descriptor: $0.fontDescriptor, size: size) }
	}

	private func addTraits(_ traits: UIFontDescriptor.SymbolicTraits,
	                       to text: NSMutableAttributedString, range: NSRange) {
		mutateFonts(in: text, range: range) { font in
			let merged = font.fontDescriptor.symbolicTraits.union(traits)
			guard let descriptor = font.fontDescriptor.withSymbolicTraits(merged) else { return font }
			return UIFont(descriptor: descriptor, size: font.pointSize)
		}
	}

	private func mutateFonts(in text: NSMutableAttributedString, range: NSRange,
	                         _ transform: (UIFont) -> UIFont) {
		text.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
			guard let font = value as? UIFont else { return }
			text.addAttribute(.font, value: transform(font), range: subrange)
		}
	}
}

#endif
