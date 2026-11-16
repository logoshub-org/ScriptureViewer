// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import ScriptureText
import ScriptureTextMarkup

/// Parses raw OSIS verse entries — as SWORD stores them — into a
/// `ScriptureText` (plan D32). Pure Swift, no dependencies, no platform code.
///
/// The parse never throws: the tokenizer is tolerant by design, and a
/// malformed module degrades to its text rather than failing.
public struct OSISParser: Sendable {

    /// One module entry. Verse 0 is the chapter or book introduction.
    public struct VerseEntry: Sendable, Equatable {
        public var verse: Int
        public var osis: String

        public init(verse: Int, osis: String) {
            self.verse = verse
            self.osis = osis
        }
    }

    /// Display options. SWORD used to apply these in its render filters; raw
    /// entries are unfiltered, so the parser does.
    public struct Options: Sendable, Equatable {
        public enum Variants: Sendable, Equatable {
            case primary, secondary, all
        }

        public var headings = true
        public var redLetter = true
        public var footnotes = true
        /// Notes of `type="crossReference"` (marker "x"). SWORD gates these by
        /// their own option, separate from `footnotes`.
        public var crossReferences = true
        /// Start every verse on its own line (the app's "verse per line").
        public var versePerLine = false
        /// Insert marker runs such as `<07225>` after Strong's-tagged words.
        public var strongsMarkers = false
        /// Insert marker runs for morphology codes.
        public var morphMarkers = false
        /// Which reading to keep where a module offers variants (LXX).
        /// Primary is what the app has always shown.
        public var variants: Variants = .primary
        /// Show the verse number at the start of each verse.
        public var verseNumbers = true
        /// Supply quotation marks for `<q>` elements that carry no `marker`
        /// attribute: `"` at odd levels, `'` at even ones. This is the module's
        /// `OSISqToTick` setting, which SWORD treats as on unless the conf says
        /// `false`; an explicit `marker` (even an empty one) always wins.
        public var quoteMarks = true

        /// Keep Greek accents, Hebrew vowel points and Hebrew cantillation
        /// (D47); false removes them from the text and from note text.
        public var greekAccents = true
        public var hebrewPoints = true
        public var hebrewCantillation = true

        var textTransforms: TextTransforms {
            TextTransforms(greekAccents: greekAccents, hebrewPoints: hebrewPoints,
                           hebrewCantillation: hebrewCantillation)
        }

        public init() {}
    }

    public var options: Options
    public var profile: ScriptureContentProfile

    public init(options: Options = Options(), profile: ScriptureContentProfile = .chapter) {
        self.options = options
        self.profile = profile
    }

    /// Parses one chapter (or one entry) as a **single stream**: the element
    /// stack carries across entries, because OSIS containers span verses.
    ///
    /// `identity` says which chapter this is (the host knows; the parser does
    /// not) and is carried on the result for word references (D41).
    public func parse(_ entries: [VerseEntry], identity: PassageIdentity? = nil) -> ScriptureText {
        var builder = OSISBuilder(options: options)
        for entry in entries {
            if profile.buildsVerseRanges { builder.beginVerse(entry.verse) }
            MarkupTokenizer.tokenize(entry.osis, into: &builder)
        }
        var result = builder.finish()
        result.identity = identity
        return result
    }

    /// Parses a single OSIS fragment (a dictionary entry, an "about" page).
    public func parse(osis: String) -> ScriptureText {
        var builder = OSISBuilder(options: options)
        MarkupTokenizer.tokenize(osis, into: &builder)
        return builder.finish()
    }
}
