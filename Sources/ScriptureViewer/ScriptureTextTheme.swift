// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if canImport(UIKit)

import UIKit
import ScriptureText

/// Presentation settings for the native scripture reader.
///
/// Combines user preferences (font, size, night mode), device traits (iPad) and
/// the module's writing direction with a `ScriptureStyleSheet` to produce the
/// colours, fonts and paragraph styles used when rendering scripture text.
///
/// The defaults reproduce the look of the legacy HTML reader so the two renderers stay
/// visually consistent during migration.
///
/// This is a plain value type with no knowledge of the app: build one directly in tests, or let the host read its own
/// preferences into one (the app does this in `ScriptureThemePreferences.swift`, which is GPL; this file touches no
/// SWORD or app code, so it can move into the MPL-2.0 viewer package, plan §13).
public struct ScriptureTextTheme {

	// MARK: - Defaults

	/// Legacy default font (`PSDefaultFontName`).
	public static let defaultFontName = "Helvetica Neue"
	/// Legacy default body size, in CSS points.
	public static let defaultFontSize: CGFloat = 14
	/// Legacy line-height multiples: wider on iPad.
	package static let phoneLineHeight = 1.4
	package static let padLineHeight = 1.6
	/// The stored size preference is a CSS pt value. With `width=device-width`
	/// one CSS pixel equals one UIKit point and 1 CSS pt = 4/3 CSS px, so the
	/// same number used as UIKit points would render about 25 % smaller.
	public static let cssPointToUIKitPoint: CGFloat = 4.0 / 3.0

	// MARK: - Inputs

	package let nightMode: Bool
	/// The page by day (white, sepia, grey); night mode ignores it.
	public let page: ScriptureViewerPage
	package let fontName: String
	package let fontSize: CGFloat
	package let isPad: Bool
	/// The module is right-to-left (`Direction=RtoL`); trailing-aligned roles
	/// such as Selah then align left.
	public let rightToLeft: Bool
	/// When set, replaces the classic rules and is used as-is, including its
	/// own line height (the iPad line-height rule is not applied to it).
	package let customStyleSheet: ScriptureStyleSheet?

	// MARK: - Resolved values

	/// The portable rules this theme realises (plan D41): the custom sheet if
	/// given, otherwise the shared classic sheet with the legacy line height.
	package let styleSheet: ScriptureStyleSheet
	/// The body font, resolved once; falls back to the system font if
	/// `fontName` is not installed.
	public let bodyFont: UIFont

	public init(nightMode: Bool = false,
	     fontName: String = ScriptureTextTheme.defaultFontName,
	     fontSize: CGFloat = ScriptureTextTheme.defaultFontSize,
	     isPad: Bool = false,
	     rightToLeft: Bool = false,
	     customStyleSheet: ScriptureStyleSheet? = nil,
	     page: ScriptureViewerPage = .white) {
		self.nightMode = nightMode
		self.page = page
		self.fontName = fontName
		self.fontSize = fontSize
		self.isPad = isPad
		self.rightToLeft = rightToLeft
		self.customStyleSheet = customStyleSheet

		if let customStyleSheet {
			self.styleSheet = customStyleSheet
		} else {
			var sheet = ScriptureStyleSheet.classic
			sheet.lineHeight = isPad ? ScriptureTextTheme.padLineHeight : ScriptureTextTheme.phoneLineHeight
			self.styleSheet = sheet
		}
		self.bodyFont = UIFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
	}

	/// The theme a contract value describes (plan D157). Its font size is in CSS points, as the preference stores it, and is turned into
	/// UIKit points here.
	public init(_ theme: ScriptureViewerTheme) {
		self.init(nightMode: theme.nightMode, fontName: theme.fontName, fontSize: CGFloat(theme.fontSize) * Self.cssPointToUIKitPoint,
		          isPad: theme.isWide, rightToLeft: theme.rightToLeft, customStyleSheet: theme.styleSheet, page: theme.page)
	}

	// MARK: - Highlights

	/// How much of a folder's colour a bookmark highlight shows. Light enough to read the words through, in day and night mode.
	package static let bookmarkHighlightAlpha: CGFloat = 0.35

	/// What a highlight style looks like: yellow with black text for a search hit; for a bookmark, the folder's colour at
	/// `bookmarkHighlightAlpha`, with the text keeping its own colour (black by day, white at night).
	package func highlightAttributes(for style: HighlightStyle) -> [NSAttributedString.Key: Any] {
		if style.name == "bookmark", let hex = style.colour, let colour = Self.colour(fromHex: hex) {
			return [.backgroundColor: colour.withAlphaComponent(Self.bookmarkHighlightAlpha)]
		}
		return [.backgroundColor: UIColor.yellow, .foregroundColor: UIColor.black]
	}

	/// `#RRGGBB`; nil for anything else.
	package static func colour(fromHex hex: String) -> UIColor? {
		let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
		guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
		return UIColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
		               blue: CGFloat(value & 0xFF) / 255, alpha: 1)
	}

	// MARK: - Colours

	/// A sepia or grey page by day (`ScriptureViewerPage`); nil for the white page and at night, which keep the colours they always had.
	private var tintedPage: ScriptureViewerPage? { nightMode || page == .white ? nil : page }

	/// By day the page's colours (white, sepia or grey); at night white on black, whatever the page.
	public var textColor: UIColor { tintedPage.map { Self.colour(fromHex: $0.textHex)! } ?? (nightMode ? .white : .black) }
	public var backgroundColor: UIColor { tintedPage.map { Self.colour(fromHex: $0.backgroundHex)! } ?? (nightMode ? .black : .white) }
	/// `span.WordOfChrist { color: #D03030; }`; a shade deeper on a sepia or grey page.
	package var redLetterColor: UIColor {
		tintedPage.map { Self.colour(fromHex: $0.redLetterHex)! } ?? UIColor(red: 0xD0 / 255.0, green: 0x30 / 255.0, blue: 0x30 / 255.0, alpha: 1)
	}
	/// Strong's, morph, footnote and cross-reference markers; a shade deeper on a sepia or grey page.
	package var markerColor: UIColor { tintedPage.map { Self.colour(fromHex: $0.markerHex)! } ?? .gray }
	/// `a { color: fuchsia; }`, the legacy link colour, kept for parity; a shade deeper on a sepia or grey page.
	package var linkColor: UIColor { tintedPage.map { Self.colour(fromHex: $0.linkHex)! } ?? UIColor(red: 1, green: 0, blue: 1, alpha: 1) }

	/// The platform realisation of a colour role. Night mode is handled here,
	/// never in the style sheet rules.
	package func color(for role: ScriptureStyleSheet.ColorRole) -> UIColor {
		switch role {
		case .text: return textColor
		case .marker: return markerColor
		case .redLetter: return redLetterColor
		case .link: return linkColor
		}
	}

	// MARK: - Font sizes

	/// Small text: the sheet's scale of the body size, at least 1 pt.
	package var smallFontSize: CGFloat { max((fontSize * CGFloat(styleSheet.smallScale)).rounded(), 1) }

	/// The smaller capitals of the divine name (LORD), in whole points.
	package var divineNameFontSize: CGFloat { max((fontSize * CGFloat(styleSheet.divineNameScale)).rounded(), 1) }

	/// Verse numbers: the sheet's scale and raise, in whole points.
	package var superscriptFontSize: CGFloat { fontSize(for: styleSheet.verseNumber) }
	package var superscriptBaselineOffset: CGFloat { baselineOffset(for: styleSheet.verseNumber) }

	package func fontSize(for superscript: ScriptureStyleSheet.Superscript) -> CGFloat {
		(fontSize * CGFloat(superscript.sizeScale)).rounded()
	}

	package func baselineOffset(for superscript: ScriptureStyleSheet.Superscript) -> CGFloat {
		(fontSize * CGFloat(superscript.raise)).rounded()
	}

	// MARK: - Paragraphs

	/// The sheet's line height as the legacy CSS means it: `line-height: 1.4` is 1.4 times
	/// the font size. UIKit's `lineHeightMultiple` instead scales the font's own line height,
	/// which is already about 1.2 times its size, so the same number would look about 20 %
	/// looser than the web view. A minimum line height in points reproduces the CSS.
	package func lineHeight(forFontSize size: CGFloat) -> CGFloat {
		CGFloat(styleSheet.lineHeight) * size
	}

	package func baseParagraphStyle(fontSize size: CGFloat? = nil) -> NSMutableParagraphStyle {
		let style = NSMutableParagraphStyle()
		style.minimumLineHeight = lineHeight(forFontSize: size ?? fontSize)
		// The module's direction, not the first strong letter: Psalm 119's "א ALEPH." would otherwise make its paragraph
		// right-to-left and right-aligned in a left-to-right Bible.
		style.baseWritingDirection = rightToLeft ? .rightToLeft : .leftToRight
		return style
	}

	/// The paragraph style for one resolved block: em rules become points here,
	/// and trailing alignment becomes left or right by the module's writing
	/// direction.
	package func paragraphStyle(for block: ResolvedBlock) -> NSParagraphStyle {
		let style = baseParagraphStyle(fontSize: (fontSize * CGFloat(block.style.sizeScale)).rounded())
		switch block.style.alignment {
		case .leading: style.alignment = .natural
		case .center: style.alignment = .center
		case .trailing: style.alignment = rightToLeft ? .left : .right
		}
		style.firstLineHeadIndent = CGFloat(block.style.firstLineIndent) * fontSize
		style.headIndent = CGFloat(block.style.wrapIndent) * fontSize
		style.paragraphSpacingBefore = (CGFloat(block.spaceBefore) * fontSize).rounded()
		style.paragraphSpacing = (CGFloat(block.spaceAfter) * fontSize).rounded()
		return style
	}
}

#endif
