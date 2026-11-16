// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import ScriptureText

/// The scripture viewer for a Skip-built app: the same SwiftUI view, with the same name and values, as the iOS one in the
/// `ScriptureViewer` package (see ScriptureViewerContract.md), so the app's shared screens name it without a `#if SKIP` of their own.
/// On Android it shows the Compose viewer of `Android/scriptureviewer` (a `TextView` under a Compose wrapper, plan D185); on iOS this
/// module is not used (the app takes the iOS view from the package), and the view is empty so the module still builds there.
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
        #if SKIP
        ComposeView { context in
            scripture.viewer.ScriptureViewer(text: text, modifier: context.modifier, theme: theme, highlights: highlights,
                                             configuration: configuration, controller: controller, events: events)
        }
        #else
        EmptyView()
        #endif
    }
}
