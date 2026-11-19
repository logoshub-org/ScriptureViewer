// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#if canImport(UIKit)
import UIKit
import XCTest
import ScriptureText
import ScriptureTextOSIS
@testable import ScriptureViewer

/// Phase 3b exit: the attribute dump of the styled fixture matches its golden
/// file, and the semantic → visual mapping holds (legacy CSS contract).
final class ScriptureTextStylerTests: XCTestCase {

	private static let fixturesDirectory = URL(fileURLWithPath: #filePath)
		.deletingLastPathComponent()
		.appendingPathComponent("Fixtures")

	private func styledFixture(theme: ScriptureTextTheme) throws -> (ScriptureText, NSAttributedString) {
		let model = ChapterFixture.chapter()
		return (model, ScriptureTextStyler().attributedString(for: model, theme: theme))
	}

	func testDayThemeDumpMatchesGolden() throws {
		let (_, styled) = try styledFixture(theme: ScriptureTextTheme())
		let dump = Self.dump(styled)
		let goldenURL = Self.fixturesDirectory.appendingPathComponent("chapter_basic.attributes.golden.txt")
		if ProcessInfo.processInfo.environment["RECORD_GOLDEN"] == "1" {
			try FileManager.default.createDirectory(at: Self.fixturesDirectory, withIntermediateDirectories: true)
			try dump.write(to: goldenURL, atomically: true, encoding: .utf8)
		}
		XCTAssertEqual(dump, try String(contentsOf: goldenURL, encoding: .utf8))
	}

	func testLegacyCSSContractHolds() throws {
		let theme = ScriptureTextTheme()   // day, Helvetica Neue 14, iPhone
		let (model, styled) = try styledFixture(theme: theme)

		// Verse 2's whole range carries scriptureVerse for tracking…
		let v2 = model.verses[1]
		var attrs = styled.attributes(at: v2.start + 5, effectiveRange: nil)
		XCTAssertEqual(attrs[ScriptureTextStyler.scriptureVerse] as? Int, 2)

		// …and its number marker is 70% superscript in the text colour.
		attrs = styled.attributes(at: v2.start, effectiveRange: nil)
		XCTAssertEqual((attrs[.font] as? UIFont)?.pointSize, theme.superscriptFontSize)
		XCTAssertEqual(attrs[.baselineOffset] as? CGFloat, theme.superscriptBaselineOffset)
		XCTAssertEqual(attrs[.foregroundColor] as? UIColor, theme.textColor)

		// Strong's marker: gray, italic, superscript, with its key payload.
		let strongs = model.spans.first { if case .strongs = $0.attribute { return true }; return false }!
		attrs = styled.attributes(at: strongs.start, effectiveRange: nil)
		XCTAssertEqual(attrs[ScriptureTextStyler.scriptureStrongs] as? String, "strong:H07225")
		XCTAssertEqual(attrs[.foregroundColor] as? UIColor, theme.markerColor)
		let strongsFont = try XCTUnwrap(attrs[.font] as? UIFont)
		XCTAssertTrue(strongsFont.fontDescriptor.symbolicTraits.contains(.traitItalic))

		// Red letter.
		let red = model.spans.first { $0.attribute == .redLetter }!
		attrs = styled.attributes(at: red.start, effectiveRange: nil)
		XCTAssertEqual(attrs[.foregroundColor] as? UIColor, theme.redLetterColor)

		// Misnesting repair: "both" ends up bold AND italic.
		let both = model.spans.first { $0.attribute == .bold }!
		let bothFont = try XCTUnwrap(
			styled.attributes(at: both.start + 4, effectiveRange: nil)[.font] as? UIFont)
		XCTAssertTrue(bothFont.fontDescriptor.symbolicTraits.contains(.traitBold))
		XCTAssertTrue(bothFont.fontDescriptor.symbolicTraits.contains(.traitItalic))

		// Link: fuchsia, scriptureLink carries the target (not .link, which would make UITextView open it).
		let link = model.spans.first { if case .link = $0.attribute { return true }; return false }!
		attrs = styled.attributes(at: link.start, effectiveRange: nil)
		XCTAssertEqual(attrs[ScriptureTextStyler.scriptureLink] as? String, "osis:John.3.16")
		XCTAssertNil(attrs[.link])
		XCTAssertEqual(attrs[.foregroundColor] as? UIColor, theme.linkColor)

		// A q1 poetry line: indented 1em, and wrapped lines flush with its first line.
		let poetry = model.spans.first { $0.attribute == .block(.q1) }!
		let para = try XCTUnwrap(
			styled.attributes(at: poetry.start, effectiveRange: nil)[.paragraphStyle] as? NSParagraphStyle)
		XCTAssertEqual(para.firstLineHeadIndent, theme.fontSize)
		XCTAssertEqual(para.headIndent, theme.fontSize)
	}

	func testNightModeFlipsTheColours() throws {
		let (model, styled) = try styledFixture(theme: ScriptureTextTheme(nightMode: true))
		let attrs = styled.attributes(at: model.verses[0].start + 3, effectiveRange: nil)
		XCTAssertEqual(attrs[.foregroundColor] as? UIColor, .white)
	}

	// MARK: Attribute dump

	private static func dump(_ text: NSAttributedString) -> String {
		var lines: [String] = []
		text.enumerateAttributes(in: NSRange(location: 0, length: text.length), options: []) { attrs, range, _ in
			let snippet = (text.string as NSString).substring(with: range)
				.replacingOccurrences(of: "\n", with: "⏎")
			var parts: [String] = []
			for (key, value) in attrs.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
				parts.append("\(key.rawValue)=\(describe(value))")
			}
			lines.append("\(range.location)+\(range.length) [\(snippet)] \(parts.joined(separator: " "))")
		}
		return lines.joined(separator: "\n") + "\n"
	}

	private static func describe(_ value: Any) -> String {
		switch value {
		case let font as UIFont:
			let traits = font.fontDescriptor.symbolicTraits
			let suffix = (traits.contains(.traitBold) ? "B" : "") + (traits.contains(.traitItalic) ? "I" : "")
			return "\(font.fontName)@\(font.pointSize)\(suffix.isEmpty ? "" : "+" + suffix)"
		case let color as UIColor:
			var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
			color.getRed(&r, green: &g, blue: &b, alpha: &a)
			return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
		case let style as NSParagraphStyle:
			return "para(lh:\(String(format: "%.2f", style.minimumLineHeight)),head:\(style.headIndent),first:\(style.firstLineHeadIndent))"
		case let url as URL:
			return url.absoluteString
		default:
			return String(describing: value)
		}
	}
}

extension ScriptureTextStylerTests {
	/// Chapter and psalm titles from raw OSIS are styled by role: the legacy web view
	/// shows both as bold paragraphs.
	func testRawOSISTitlesAreBold() {
		let osis = "<chapter osisID=\"Ps.23\" sID=\"c\"/><title type=\"chapter\">PSALM 23.</title><title type=\"psalm\" canonical=\"true\">A Psalm of David.</title>"
		let model = OSISParser().parse([.init(verse: 0, osis: osis), .init(verse: 1, osis: "The LORD is my shepherd.")])
		let styled = ScriptureTextStyler().attributedString(for: model, theme: ScriptureTextTheme())
		for (needle, label) in [("PSALM 23.", "chapter title"), ("A Psalm of David.", "psalm title")] {
			let at = (styled.string as NSString).range(of: needle).location
			XCTAssertNotEqual(at, NSNotFound, label)
			let font = styled.attribute(.font, at: at, effectiveRange: nil) as? UIFont
			XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true, "\(label) is not bold: \(String(describing: font))")
		}
	}
}

extension ScriptureTextStylerTests {
	/// The legacy CSS says `line-height: 1.4`: 1.4 times the font size, not 1.4 times the
	/// font's own (taller) line height.
	func testBodyLineHeightIsTheCSSMultipleOfTheFontSize() {
		let phone = ScriptureTextTheme(fontSize: 20)
		XCTAssertEqual(phone.baseParagraphStyle().minimumLineHeight, 28, accuracy: 0.01)
		XCTAssertEqual(phone.baseParagraphStyle().lineHeightMultiple, 0, "UIKit's own multiple is not used")
		XCTAssertEqual(ScriptureTextTheme(fontSize: 20, isPad: true).baseParagraphStyle().minimumLineHeight, 32, accuracy: 0.01)
	}

	/// Psalm 119's "א ALEPH." starts with a Hebrew letter; a left-to-right Bible still sets it left to right (owner, 2026-11-03).
	func testParagraphDirectionFollowsTheModuleNotTheFirstLetter() {
		XCTAssertEqual(ScriptureTextTheme().baseParagraphStyle().baseWritingDirection, .leftToRight)
		XCTAssertEqual(ScriptureTextTheme(rightToLeft: true).baseParagraphStyle().baseWritingDirection, .rightToLeft)
	}
}

#endif
