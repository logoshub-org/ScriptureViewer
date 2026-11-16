// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import ScriptureTextMarkup

/// Records the tokenizer's events so tests can assert on them exactly.
struct RecordingSink: MarkupEventSink {
    enum Event: Equatable {
        case start(String, [String: String], selfClosing: Bool)
        case text(String)
        case end(String)
    }
    var events: [Event] = []

    mutating func startElement(_ name: String, attributes: [String: String], selfClosing: Bool) {
        events.append(.start(name, attributes, selfClosing: selfClosing))
    }
    mutating func characters(_ text: String) { events.append(.text(text)) }
    mutating func endElement(_ name: String) { events.append(.end(name)) }
}
