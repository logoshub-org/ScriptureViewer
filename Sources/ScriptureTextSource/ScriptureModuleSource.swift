// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import ScriptureText
import ScriptureTextOSIS
import ScriptureTextPlain
import ScriptureTextGBF
import ScriptureTextThML

/// Where the native reader gets a chapter's unrendered entries and the facts
/// about the module they came from (plan D50). A host supplies its own
/// `RawChapterReading`: the app's is backed by SWORD, tests and other hosts
/// supply theirs.
public struct RawChapter: Sendable {
	/// OSIS book id, e.g. "Gen".
	public var book: String
	public var chapter: Int
	public var entries: [ChapterEntries.Entry]

	public init(book: String, chapter: Int, entries: [ChapterEntries.Entry]) {
		self.book = book
		self.chapter = chapter
		self.entries = entries
	}
}

public protocol RawChapterReading {
	func facts(forModule name: String) -> ScriptureModuleFacts?
	/// Every entry of the chapter, empty and repeated ones included; nil if the
	/// module is not installed or not verse-keyed.
	func rawChapter(forModule name: String, reference: String) -> RawChapter?
	/// The same chapter as the engine's own plain text (markup removed), for source types with no parser.
	func plainChapter(forModule name: String, reference: String) -> RawChapter?
}

/// Chapter text for the native reader, parsed from the module's own markup
/// rather than from the HTML SWORD renders. One read per chapter; the parser
/// takes the whole chapter as one stream and the view positions itself after.
public struct ScriptureModuleSource {

	public var reader: RawChapterReading

	public init(reader: RawChapterReading) {
		self.reader = reader
	}

	/// The parser options for a module and the user's preferences for it: SWORD's
	/// "On" options become parser flags, `OSISqToTick` comes from the conf, and
	/// the character transforms apply only where the module declares the filter (D47).
	public static func parserOptions(facts: ScriptureModuleFacts, display: ScriptureDisplayOptions) -> OSISParser.Options {
		var options = OSISParser.Options()
		options.headings = display.headings
		options.redLetter = display.redLetter
		options.footnotes = display.footnotes
		options.crossReferences = display.crossReferences
		options.versePerLine = display.versePerLine
		options.strongsMarkers = display.strongs
		options.morphMarkers = display.morph
		options.quoteMarks = facts.osisQToTick
		let transforms = facts.textTransforms(greekAccents: display.greekAccents,
		                                      hebrewPoints: display.hebrewPoints,
		                                      hebrewCantillation: display.hebrewCantillation)
		options.greekAccents = transforms.greekAccents
		options.hebrewPoints = transforms.hebrewPoints
		options.hebrewCantillation = transforms.hebrewCantillation
		return options
	}

	/// The chapter parsed natively, or nil when this module cannot be read (not installed, or not
	/// verse-keyed). OSIS, GBF and ThML go through their own parsers; modules with no `SourceType`
	/// through the plain-text parser; TEI, a dictionary format, as the engine's own plain text.
	/// A commentary's entries get the commentary profile (each verse's number on its own line).
	/// - Parameter reference: the SWORD reference, e.g. "Genesis 1"; the passage
	///   identity (OSIS book, chapter number) comes from SWORD's own parse of it.
	public func chapter(module name: String, reference: String, display: ScriptureDisplayOptions,
	             commentary: Bool = false) -> ScriptureText? {
		guard let facts = reader.facts(forModule: name) else { return nil }
		let profile: ScriptureContentProfile = commentary ? .commentary : .chapter
		if facts.sourceType == .plain || facts.sourceType == .tei {
			// TEI is a dictionary format; a verse-keyed module in it would be read as the plain text SWORD gives.
			let raw = facts.sourceType == .plain ? reader.rawChapter(forModule: name, reference: reference)
			                                     : reader.plainChapter(forModule: name, reference: reference)
			guard let raw else { return nil }
			let shown = ChapterEntries.shown(raw.entries)
			return PlainTextParser(profile: profile).parse(shown, identity: facts.identity(book: raw.book, chapter: raw.chapter))
		}
		guard let raw = reader.rawChapter(forModule: name, reference: reference) else { return nil }
		let identity = facts.identity(book: raw.book, chapter: raw.chapter)
		let shown = ChapterEntries.shown(raw.entries)
		if facts.sourceType == .thml {
			var options = ThMLParser.Options(module: name)
			options.footnotes = display.footnotes
			options.strongs = display.strongs
			options.morphology = display.morph
			let transforms = facts.textTransforms(greekAccents: display.greekAccents,
			                                      hebrewPoints: display.hebrewPoints,
			                                      hebrewCantillation: display.hebrewCantillation)
			options.transforms = transforms
			return ThMLParser(options: options, profile: profile).parse(shown, identity: identity)
		}
		if facts.sourceType == .gbf {
			return GBFParser(options: Self.parserOptions(facts: facts, display: display), profile: profile)
				.parse(shown, identity: identity)
		}
		let entries = shown.map { OSISParser.VerseEntry(verse: $0.verse, osis: $0.text) }
		let parser = OSISParser(options: Self.parserOptions(facts: facts, display: display), profile: profile)
		return parser.parse(entries, identity: identity)
	}

	/// One verse of a chapter, parsed by the module's source type, with no verse number or heading around it: for places that quote a
	/// verse (the unlock screen's test verses). Nil when the module or the verse is not there.
	public func verse(module name: String, chapterReference: String, verse: Int, display: ScriptureDisplayOptions) -> ScriptureText? {
		guard let facts = reader.facts(forModule: name) else { return nil }
		let viaPlainText = facts.sourceType == .tei
		guard let raw = viaPlainText ? reader.plainChapter(forModule: name, reference: chapterReference)
		                             : reader.rawChapter(forModule: name, reference: chapterReference),
		      let entry = raw.entries.first(where: { $0.verse == verse }),
		      !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
		switch facts.sourceType {
		case .osis:
			return OSISParser(options: Self.parserOptions(facts: facts, display: display))
				.parse([.init(verse: 0, osis: entry.text)])
		case .thml:
			var options = ThMLParser.Options(module: name)
			options.footnotes = display.footnotes
			return ThMLParser(options: options).parse(entry.text)
		case .gbf:
			return GBFParser(options: Self.parserOptions(facts: facts, display: display)).parse(entry.text)
		case .plain, .tei:
			return PlainTextParser().parse(entry.text)
		}
	}
}
