// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// What the host shows and does about a tap (plan D56, D58): the detail content, the response and the resolver.

import Foundation

/// Something to show beside the text: one or more sections, each text any parser produced.
public struct DetailContent: Equatable, Sendable {
    public struct Section: Equatable, Sendable {
        public var title: String?
        public var text: ScriptureText
        public init(title: String? = nil, text: ScriptureText) {
            self.title = title
            self.text = text
        }
    }

    public var title: String
    public var sections: [Section]

    public init(title: String, sections: [Section]) {
        self.title = title
        self.sections = sections
    }

    public init(title: String, text: ScriptureText) {
        self.init(title: title, sections: [Section(text: text)])
    }

    /// The sections as one text, for a view that shows one: each section's title (if any) as a
    /// bold line, then its text, a blank line between sections. Offsets, spans and note ids are
    /// shifted so that nothing collides; verses and word anchors are dropped, since the pane
    /// has no verse tracking.
    public var combined: ScriptureText {
        var result = ScriptureText()
        var noteCount = 0
        for (index, section) in sections.enumerated() {
            if index > 0 { result.text += "\n\n" }
            if let title = section.title, !title.isEmpty {
                let start = result.text.utf16.count
                result.text += title + "\n"
                result.spans.append(.init(start: start, length: title.utf16.count, attribute: .bold))
            }
            let shift = result.text.utf16.count
            result.text += section.text.text
            var renamed: [String: String] = [:]
            for note in section.text.notes {
                noteCount += 1
                let id = "d\(noteCount)"
                renamed[note.id] = id
                var copy = note
                copy.id = id
                result.notes.append(copy)
            }
            for span in section.text.spans {
                var attribute = span.attribute
                if case .footnote(let old) = attribute { attribute = .footnote(id: renamed[old] ?? old) }
                result.spans.append(.init(start: span.start + shift, length: span.length, attribute: attribute))
            }
        }
        return result
    }
}

/// What the host wants done about a tap.
public enum TapResponse: Equatable, Sendable {
    /// Show this beside the text (the detail pane, D56).
    case detail(DetailContent)
    /// Go to a passage; the host navigates and the viewer reloads.
    case navigate(PassageIdentity)
    /// Open a URL outside the viewer.
    case open(URL)
    /// Nothing to do; the host handled it itself.
    case none
}

/// The host's answer to taps. May look things up, so it is asynchronous; the viewer keeps
/// showing its current content while it waits.
public protocol TapResolver: Sendable {
    func resolve(_ target: TapTarget) async -> TapResponse
}
