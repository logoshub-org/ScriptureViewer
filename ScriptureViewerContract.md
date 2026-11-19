# The scripture viewer contract

The viewer is the one part of PocketSword that cannot be written once: it must scroll to an exact verse, know which verse is at the
top, select and copy across paragraphs, and mark words and verses. On iOS that is UIKit (a TextKit 2 `UITextView`); on Android it is a
`TextView` holding a `Spannable`, under a thin Jetpack Compose wrapper (plan D185; Compose's own text, plan D155 and D156, is the
fallback). Everything around it (screens, navigation, lookups, bookmarks,
history, search, downloads) is the host app, written once in Swift and SwiftUI.

This file is the agreed boundary. The code is `Sources/ScriptureText/Viewer/ScriptureViewerContract.swift`: Foundation and
Observation only, no UIKit, so both platforms can implement it. Each platform supplies a `ScriptureViewer` view that takes these
values and reports through these events.

**Names.** One component, one name: `ScriptureViewer`. The package, the SwiftUI view and the contract types (`ScriptureViewerTheme`,
`ScriptureViewerConfiguration`, `ScriptureViewerController`, `ScriptureViewerEvents`, …) all use it. The UIKit class that is called
`ScriptureViewer` today is the old container; it is renamed out of the way when the new view arrives, then removed. `ScriptureTextView`
(the UIKit text view) stays as the iOS implementation underneath.

## The viewer takes

| Input | Type | What it is |
|---|---|---|
| text | `ScriptureText` | The chapter or entry, already parsed (the portable core does that). |
| theme | `ScriptureViewerTheme` | night mode, font name and size (CSS points), wide layout, right to left, an optional style sheet. |
| highlights | `ScriptureHighlights` | bookmark verses with their colours, search terms, a Strong's number. |
| configuration | `ScriptureViewerConfiguration` | top and bottom inset, scrolls or sizes to its text, pull changes chapter, the selection menu's extra items. |
| controller | `ScriptureViewerController` | commands the host sends (held until a new text is on show: the host says `willShowNewText()` when it changes the text or the theme, the view says `textWasShown()`, because a view applies state a turn after it is set) (`scroll(toVerse:)`, `scroll(toOffset:)`, `focus(verse:)`, `clearFocus()`, `clearSelection()`) and what the reader last said (`currentVerse`, `scrollOffset`, `selection`, `focusedVerse`, `isAtEnd`), observable by the host's views. |
| events | `ScriptureViewerEvents` | the closures below. |

## The viewer reports

`onScroll(offset, verse)`, `onReachedEnd`, `onTap(TapTarget)` (a verse number, a word, a note letter or a link, with where it was and
what the markup said), `onGesture(.plainTap | .twoFingerTap | .swipeLeft | .swipeRight | .threeFingerDrag | .dragEnded)` (`.dragEnded` only when the configuration sets `reportsDragEnd`: Automatic Fullscreen goes fullscreen on it),
`onPull(.previousChapter | .nextChapter)`, `onChromeRequest(.show | .hide)` (the scroll rule for the host's bars, and a tap or a touch near the bottom; the host decides), and asks `canHideChrome()` before a tap on the text sends them away; `onShare(text)` replaces the platform's own share sheet,
`onSelectionChange(ScriptureSelection?)` (UTF-16 start and length, and the verses touched), `onMenuItem(id, selection)`.
It asks two questions: `referenceLine(verses)`, the line put above copied text, and `canHideChrome()`.

## What the viewer does itself

Draws the text and its styles; scrolls; keeps the verse at the top; dims all but a focused verse; draws highlights and the selection;
finds the tap target at a point; copies the selection as the reader's copy (the core's `copiedText`: markers and note letters dropped,
verse numbers set apart, plus the reference line). A new text starts at its top; the same text in another theme (night mode, a font,
a size) keeps the reader's place: the verse at the top stays at the top, and the very top stays the very top. The focus, the selection
and the highlights go in both cases, and the host's highlights are painted again. It opens no screen, resolves no lookup, reads no
preference, and posts no notification.

## What leaves the component, and where it goes

| Today (iOS component) | Becomes |
|---|---|
| The old UIKit `ScriptureViewer` class (the container) and its detail pane (`DetailPaneView`, Back history) | The host: a SwiftUI sheet or pane showing a `ScriptureViewer` with `scrolls = false`. |
| `ScriptureHost.content` (`EBStudyResolver` as the content source), `openLink`, `labels` | The host handles `onTap`, builds the `ScriptureText` for the pane with the core, opens links itself, and supplies the menu item titles. |
| `ScriptureHost.barControl`, `hidesTabBarOnScroll`, `ScriptureBarScrollRule` | Done (plan D165): `onChromeRequest` and `canHideChrome`; the rule is in the portable core, and `ScriptureHost` is gone. |
| `autoFullscreenMode`, `scriptureTextViewDidTapPlainText` | The host's meaning for `.plainTap`. |
| `bookmarkMenuTitle`, `scriptureTextViewOffersBookmark`, `bookmarkVersesFrom` | `menuItems` and `onMenuItem`. |
| `copyReference` closure | `referenceLine`. |
| `setupRefreshViews(top, bottom)` | `topInset` and `bottomInset`. |
| `setBookmarkHighlights`, `highlightSearchTerms`, `highlightStrongs` | `ScriptureHighlights`. |
| `scrollToVerse`, `focusVerse`, `clearVerseFocus`, `verseAtTop`, offsets | The controller and `onScroll`. |
| `ScriptureTextTheme` (UIKit fonts and colours) | Stays as the iOS realisation of `ScriptureViewerTheme`. |
| `ScriptureBookNavigator` (UIKit collection view) | Done (plan D165): `EBBookNavigator` in the app, SwiftUI over the core's `BookNavigatorState` and `BookNavigatorGrid`. |

## Implementations

- **iOS (built 2026-11-14):** `Sources/ScriptureViewer/ScriptureViewer.swift`, a SwiftUI `UIViewRepresentable` named `ScriptureViewer` over
  `ScriptureTextView`. A coordinator turns the text view's delegate calls into the contract's events and the controller's commands into
  the text view's calls; `ScriptureTextTheme(_: ScriptureViewerTheme)` realises the theme (the contract's font size is in CSS points).
  The old UIKit container, with its detail pane, is gone: the host shows its own pane (plan D160, D161, D162). The dictionary entry, the
  devotional and the Bible and Commentary readers all use the view.
- **Android (built 2026-11-16):** `Android/scriptureviewer`, a composable named `ScriptureViewer` (package `scripture.viewer.compose`) over
  `ScriptureTextView`, a selectable `TextView` holding the chapter as one `Spannable` in a `NestedScrollView`, hosted by `AndroidView`
  (plan D185). A bridge does what the iOS coordinator does. The contract types and the bar rule are this folder's Swift, transpiled by
  Skip (package `scripture.text`), so both platforms and the Skip-built host use the same ones. Sixteen instrumented tests run it against
  Psalm 119 on an emulator; what differs from iOS, what was measured and what is left is in `Android/README.md`. The package is a Skip
  package, so the SwiftUI view a Skip-built app names is this package's `ScriptureViewer`: `ScriptureViewer.swift` has an `#if SKIP` branch,
  the same struct with a `ComposeView` around the composable as its body, beside the UIKit branch (and a placeholder on macOS).

## Open points

1. **Android accessibility:** with the `TextView` the chapter is one text node, not an edit box, and can be moved through by word, line
   and paragraph. Still open: listening to it with TalkBack, and navigation by verse.
2. **Android taps:** settled with the `TextView`: the view watches the touches without taking them, finds the character from the
   layout and asks the model for the tap target; selection and scrolling carry on beside it.
3. **iOS navigation bar:** `setContentScrollView` ties the bar's scroll-edge effect to the text view; a SwiftUI wrapper needs a
   view-controller representable, or accepts the plainer bar.
4. **Observation:** settled: with SkipModel the controller transpiles, its properties become Compose state, and a composable that
   reads `currentVerse` follows the scroll (tested). The SwiftUI view a Skip-built app's shared code names is the `#if SKIP` branch of
   `ScriptureViewer.swift`, a `ComposeView` around the composable.
5. **Sizing:** done on both: `scrolls = false` takes the text's height (SwiftUI `sizeThatFits` on iOS, the view's measured height on
   Android).
6. **The detail pane in the host:** history and Back inside the pane become the host's job.

## Order of work

1. This contract (done), then the SwiftUI `ScriptureViewer` view on iOS over the current text view (done 2026-11-14).
2. Move the portable pieces into the core (`ScriptureBarScrollRule`, a portable theme conversion): not yet.
3. Convert one screen that hosts a viewer (the dictionary entry) to the reader, as the proof (done 2026-11-14, with its own SwiftUI detail pane).
4. The other screens that host viewers: devotional and the Bible and Commentary readers done 2026-11-14 (the container is removed); module info and unlock were not on the container. The presenter and the shell remain UIKit.
