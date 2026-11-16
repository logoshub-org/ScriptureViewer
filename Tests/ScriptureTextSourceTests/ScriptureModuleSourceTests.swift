// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import XCTest
import ScriptureText
import ScriptureTextOSIS
import ScriptureTextSource

final class ScriptureModuleSourceTests: XCTestCase {

	private struct FakeReader: RawChapterReading {
		var moduleFacts: ScriptureModuleFacts?
		var entries: [ChapterEntries.Entry]?
		func facts(forModule name: String) -> ScriptureModuleFacts? { moduleFacts }
		func rawChapter(forModule name: String, reference: String) -> RawChapter? {
			entries.map { RawChapter(book: "Gen", chapter: 1, entries: $0) }
		}
		var plainEntries: [ChapterEntries.Entry]?
		func plainChapter(forModule name: String, reference: String) -> RawChapter? {
			(plainEntries ?? entries).map { RawChapter(book: "Gen", chapter: 1, entries: $0) }
		}
	}

	private func source(_ facts: ScriptureModuleFacts?, _ texts: [String]?) -> ScriptureModuleSource {
		ScriptureModuleSource(reader: FakeReader(
			moduleFacts: facts,
			entries: texts.map { $0.enumerated().map { .init(verse: $0.offset, text: $0.element) } }))
	}

	// MARK: Fake reader

	func testAnOSISChapterIsParsedWithItsIdentityAndSkipsRepeatedEntries() throws {
		let facts = ScriptureModuleFacts(name: "Test", versification: "NRSV")
		let model = try XCTUnwrap(source(facts, ["", "In the beginning", "In the beginning", "and the earth"])
			.chapter(module: "Test", reference: "Gen 1", display: .init()))
		XCTAssertEqual(model.identity, PassageIdentity(work: "Test", versification: "NRSV", book: "Gen", chapter: 1))
		XCTAssertEqual(model.verses.map(\.verse), [1, 3])
	}

	func testAThMLCommentaryChapterIsParsedWithEachVerseNumberedOnItsOwnLine() throws {
		let facts = ScriptureModuleFacts(name: "Wesley", sourceType: .thml)
		let model = try XCTUnwrap(source(facts, ["<p>Intro.</p>", "Divers <i>words</i>.", "See <scripRef passage=\"Ps 2:1\">Ps 2</scripRef>."])
			.chapter(module: "Wesley", reference: "Gen 1", display: .init(), commentary: true))
		XCTAssertEqual(model.text, "Intro.\n1\nDivers words.\n2\nSee Ps 2.")
		XCTAssertEqual(model.verses.map(\.verse), [1, 2])
		XCTAssertEqual(model.identity?.work, "Wesley")
		XCTAssertTrue(model.spans.contains { $0.attribute == .link(target: "passage:Ps 2:1") })
	}

	func testAThMLBibleChapterRunsTheNumbersIntoTheText() throws {
		let facts = ScriptureModuleFacts(name: "ISV", sourceType: .thml)
		let model = try XCTUnwrap(source(facts, ["", "In the beginning", "the earth"]).chapter(module: "ISV", reference: "Gen 1", display: .init()))
		XCTAssertEqual(model.text, "1In the beginning\n2the earth")
	}

	func testAModuleWithNoSourceTypeIsReadAsPlainText() throws {
		let facts = ScriptureModuleFacts(name: "MHCC", sourceType: .plain)
		let model = try XCTUnwrap(source(facts, ["Intro", "** Verse one\r\n comment", "second"])
			.chapter(module: "MHCC", reference: "Gen 1", display: .init(), commentary: true))
		XCTAssertEqual(model.verses.map(\.verse), [1, 2])
		XCTAssertTrue(model.text.contains("Verse one comment"), model.text)
		XCTAssertEqual(model.identity?.work, "MHCC")
	}

	func testAGBFChapterIsParsedFromItsOwnMarkupAndAMissingModuleIsNil() throws {
		let gbf = ScriptureModuleFacts(name: "YLT", sourceType: .gbf)
		let model = try XCTUnwrap(source(gbf, ["", "darkness <FI>is<Fi> on the face<CM>", "and the Spirit<WG4151> moving"])
			.chapter(module: "YLT", reference: "Gen 1", display: .init()))
		XCTAssertEqual(model.text, "1darkness is on the face\n2and the Spirit moving")
		XCTAssertEqual(model.identity?.work, "YLT")
		let italic = model.spans.filter { $0.attribute == .italic }.compactMap { model.substring(utf16Start: $0.start, length: $0.length) }
		XCTAssertEqual(italic, ["is"])
		XCTAssertTrue(model.spans.contains { $0.attribute == .strongs("strong:G4151") } == false, "markers are off by default")
		XCTAssertNil(source(nil, ["x"]).chapter(module: "T", reference: "Gen 1", display: .init()))
		XCTAssertNil(source(ScriptureModuleFacts(name: "T"), nil).chapter(module: "T", reference: "Gen 1", display: .init()))
	}

	func testGBFStrongsNumbersFollowThePreference() throws {
		let gbf = ScriptureModuleFacts(name: "RusVZh", sourceType: .gbf)
		var display = ScriptureDisplayOptions()
		display.strongs = true
		let model = try XCTUnwrap(source(gbf, ["", "Духа<WG4151> там"]).chapter(module: "RusVZh", reference: "Matt 1", display: display))
		XCTAssertEqual(model.text, "1Духа<4151> там")
		XCTAssertTrue(model.spans.contains { $0.attribute == .strongs("strong:G4151") })
	}

	func testOneVerseIsParsedByItsSourceTypeWithoutANumber() throws {
		let osis = ScriptureModuleFacts(name: "KJV", sourceType: .osis)
		let verse = try XCTUnwrap(source(osis, ["", "In the <w lemma=\"strong:H07225\">beginning</w> God", "and the earth"])
			.verse(module: "KJV", chapterReference: "Gen 1", verse: 2, display: .init()))
		XCTAssertEqual(verse.text, "and the earth")
		XCTAssertNil(source(osis, ["", "x"]).verse(module: "KJV", chapterReference: "Gen 1", verse: 9, display: .init()))
		let thml = ScriptureModuleFacts(name: "T", sourceType: .thml)
		XCTAssertEqual(source(thml, ["", "<i>Divers</i> words"]).verse(module: "T", chapterReference: "Gen 1", verse: 1, display: .init())?.text, "Divers words")
		let gbf = ScriptureModuleFacts(name: "YLT", sourceType: .gbf)
		XCTAssertEqual(source(gbf, ["", "a <FI>word<Fi>"]).verse(module: "YLT", chapterReference: "Gen 1", verse: 1, display: .init())?.text, "a word")
	}

	func testPreferencesBecomeParserOptions() {
		var display = ScriptureDisplayOptions()
		display.headings = true
		display.strongs = true
		display.versePerLine = true
		display.crossReferences = true
		let facts = ScriptureModuleFacts(name: "X", osisQToTick: false, declaresGreekAccents: true)
		let o = ScriptureModuleSource.parserOptions(facts: facts, display: display)
		XCTAssertTrue(o.headings && o.strongsMarkers && o.versePerLine && o.crossReferences)
		XCTAssertFalse(o.redLetter || o.footnotes || o.morphMarkers)
		XCTAssertFalse(o.quoteMarks, "OSISqToTick=false in the conf")
		XCTAssertFalse(o.greekAccents, "preference off and the module declares the filter")
		XCTAssertTrue(o.hebrewPoints && o.hebrewCantillation, "filters the module does not declare are never applied")
	}
}
