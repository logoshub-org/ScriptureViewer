// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// The scripture viewer as a SwiftUI view on Android, for a Skip app whose shared screens are SwiftUI: the one thing in the package that
// needs SkipUI, so it is a product of its own and an app that calls the Compose viewer directly does not carry SkipUI. On iOS and macOS
// this module is empty: `import ScriptureViewer` gives the SwiftUI view there.

#if SKIP

import SwiftUI
import ScriptureText

/// The scripture viewer on Android (plan D157, D185, ScriptureViewerContract.md): the same SwiftUI view, with the same name and values,
/// as the iOS one (the ScriptureViewer module), so an app's shared screens name it without a `#if SKIP` of their own. Skip carries this
/// to Kotlin, where its body is the Compose viewer in `Android/scriptureviewer` (package `scripture.viewer.compose`, its Kotlin linked
/// into the ScriptureViewer module's `Skip/`): a `TextView` holding the chapter as one `Spannable`.
public struct ScriptureViewer: View {

    let text: ScriptureText
    let theme: ScriptureViewerTheme
    let highlights: ScriptureHighlights
    let configuration: ScriptureViewerConfiguration
    let controller: ScriptureViewerController?
    let events: ScriptureViewerEvents

    public init(text: ScriptureText, theme: ScriptureViewerTheme = ScriptureViewerTheme(), highlights: ScriptureHighlights = ScriptureHighlights(),
                configuration: ScriptureViewerConfiguration = ScriptureViewerConfiguration(), controller: ScriptureViewerController? = nil,
                events: ScriptureViewerEvents = ScriptureViewerEvents()) {
        self.text = text
        self.theme = theme
        self.highlights = highlights
        self.configuration = configuration
        self.controller = controller
        self.events = events
    }

    public var body: some View {
        ComposeView { context in
            scripture.viewer.compose.ScriptureViewer(text: text, modifier: context.modifier, theme: theme, highlights: highlights,
                                                     configuration: configuration, controller: controller, events: events)
        }
    }
}

#endif
