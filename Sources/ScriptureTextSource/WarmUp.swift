// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import ScriptureText
import ScriptureTextOSIS
import ScriptureTextGBF
import ScriptureTextThML
import ScriptureTextPlain

extension ScriptureModuleSource {

    /// Runs the parsers once over small samples, so that the first chapter a reader opens is not also the first time their code runs.
    /// On Android the first parse in a process is several times slower than the next ones (the classes are loaded and the code is
    /// compiled as it goes); a host calls this at launch, off the main thread, and the chapter the reader opens is parsed warm. It
    /// does nothing a host can see, and on iOS there is no need for it (it costs a few milliseconds there).
    ///
    /// Measured on the Android emulator (release build, as installed): with no warm-up the first parse of Psalm 119 took 340–570 ms;
    /// after one round 100–110 ms, after three 50–70 ms, after ten 30–33 ms, the same as a warm parse. Ten rounds took 340–470 ms
    /// themselves, off the main thread. Hence ten.
    ///
    /// The samples go through what reading a chapter uses: the OSIS, GBF, ThML and plain-text parsers with their markers, notes, red
    /// letter and links, and then what the viewer asks of a model (copying, the target of a tap, search and Strong's highlights).
    public static func warmUp(rounds: Int = 10) {
        var options = OSISParser.Options()
        options.strongsMarkers = true
        options.morphMarkers = true
        let osis = OSISParser(options: options, profile: ScriptureContentProfile.chapter)
        let gbf = GBFParser(options: options, profile: ScriptureContentProfile.commentary)
        var thmlOptions = ThMLParser.Options(module: "WarmUp")
        thmlOptions.strongs = true
        let thml = ThMLParser(options: thmlOptions, profile: ScriptureContentProfile.commentary)
        let plain = PlainTextParser(profile: ScriptureContentProfile.chapter)
        var round = 0
        while round < rounds {
            var osisEntries: [OSISParser.VerseEntry] = []
            var gbfEntries: [ChapterEntries.Entry] = []
            var verse = 1
            while verse <= 8 {
                osisEntries.append(OSISParser.VerseEntry(verse: verse, osis: WarmUpSamples.osis))
                gbfEntries.append(ChapterEntries.Entry(verse: verse, text: WarmUpSamples.gbf))
                verse += 1
            }
            let model = osis.parse(osisEntries, identity: PassageIdentity(work: "WarmUp", versification: "KJV", book: "Ps", chapter: 1))
            exercise(model)
            exercise(gbf.parse(ChapterEntries.shown(gbfEntries)))
            exercise(thml.parse(WarmUpSamples.thml))
            exercise(plain.parse(WarmUpSamples.plain))
            round += 1
        }
    }

    /// What the viewer does with a model: copy a verse and a range, find what is under a tap, mark a search and a Strong's number.
    private static func exercise(_ model: ScriptureText) {
        let length = CodePoints.utf16Length(model.text)
        _ = model.copiedText(utf16Start: 0, length: length)
        if let first = model.verses.first { _ = model.copiedText(verse: first.verse) }
        var offset = 0
        while offset < length {
            _ = model.tapTarget(atUTF16Offset: offset)
            offset += 7
        }
        _ = model.resolve(model.searchHits(for: ["the", "word"]) + model.strongsHits(for: "H1697"))
    }
}

/// The samples: one verse each, with what a real chapter has (a title, tagged words, a note, red letter, poetry, the divine name).
enum WarmUpSamples {
    static let osis = "<title type=\"psalm\" canonical=\"true\">A Psalm.</title><l level=\"1\"><w lemma=\"strong:H0835\" "
        + "morph=\"strongMorph:TH8802\">Blessed</w> <transChange type=\"added\">is</transChange> the <w lemma=\"strong:H0376\">man</w>"
        + "<note type=\"x-StudyNote\" n=\"a\">Or, <hi type=\"italic\">happy</hi>.</note> that <divineName>Lord</divineName> "
        + "<q who=\"Jesus\" marker=\"\">keeps the <w lemma=\"strong:H1697\">word</w></q>;</l><lb/><milestone type=\"x-p\"/>"
        + "<reference osisRef=\"Ps.1.1\">1:1</reference> &amp; more.<div type=\"x-milestone\" subType=\"x-preverse\" sID=\"pv1\"/>"
    static let gbf = "<FI>Blessed<Fi> is the man<WH0376> that <FR>keeps the word<WG3056><Fr>.<RF>A note, #Mt 4:12 Mr 1:14|<Rf>\n\n"
        + "  Another paragraph <CM>with a mark."
    static let thml = "<p><b>Blessed</b> is the <sync type=\"Strongs\" value=\"H0376\"/>man <scripRef passage=\"Ps 1:1\">Ps 1:1</scripRef>"
        + "<note>A note &mdash; <i>here</i>.</note></p><ul><li>one</li></ul>"
    static let plain = "Blessed is the man\r\nthat keeps the word.\r\n\r\nAnother paragraph."
}
