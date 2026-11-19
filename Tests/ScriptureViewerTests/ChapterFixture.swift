// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import ScriptureText
import ScriptureTextOSIS

/// A small invented chapter in OSIS with one of everything the styler and the view must handle: verse numbers, a Strong's marker,
/// italic, a footnote, red letter, a morphology marker, a character outside the Basic Multilingual Plane, a poetry line, nested
/// bold and italic, small text and a link. No module text (plan D24).
enum ChapterFixture {

	static let entries: [OSISParser.VerseEntry] = [
		.init(verse: 1, osis: "In the beginning <w lemma=\"strong:H07225\">God</w> created the heaven and the earth."),
		.init(verse: 2, osis: "And the earth was <transChange type=\"added\">without form</transChange>, and void;\u{00A0}darkness <note n=\"a\">A footnote.</note> was upon the deep."),
		.init(verse: 3, osis: "<q who=\"Jesus\" marker=\"\"><w morph=\"robinson:HNC\">Let there be light</w></q> \u{05D1}"),
		.init(verse: 4, osis: "<lg><l level=\"1\">Indented poetry line</l></lg>"),
		.init(verse: 5, osis: "Second paragraph \u{1D50A} with <hi type=\"bold\">bold<hi type=\"italic\">both</hi></hi><hi type=\"italic\">italic</hi> repair, <hi type=\"small\">small print</hi>, and a <reference osisRef=\"John.3.16\">link</reference>."),
	]

	static func options() -> OSISParser.Options {
		var options = OSISParser.Options()
		options.strongsMarkers = true
		options.morphMarkers = true
		options.footnotes = true
		options.redLetter = true
		return options
	}

	static func chapter() -> ScriptureText {
		OSISParser(options: options()).parse(entries)
	}
}
