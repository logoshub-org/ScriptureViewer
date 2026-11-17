# ScriptureViewer

A native reading surface for scripture, and the portable text model and parsers under it, for iOS (and for Android through the same
contract, see below).

The app that embeds it does the co-ordinating: it finds the scripture, decides what to show and what a tap should do. ScriptureViewer
turns a module's text into a styled, scrollable, selectable text and reports what the reader does with it. It opens no screens, reads no
preferences, resolves no lookups and has no dependency on any Bible engine.

## What you get

- **The viewer (iOS 17 and later):** `ScriptureViewer`, a SwiftUI view over a TextKit 2 text view. It scrolls to an exact verse, knows which verse is at the
  top, dims all but a focused verse, selects and copies across paragraphs, draws bookmark and search highlights, and reports taps (a verse
  number, a word, a note letter, a link), scrolls, gestures and selections as events.
- **The text model:** `ScriptureText` (text, styled spans, verse ranges, word anchors, paragraph roles, notes, passage identity), with no UI
  framework. It builds on any platform Swift runs on.
- **Parsers for module markup:** OSIS, TEI, ThML, GBF (CrossWire's older markup), plain text, and USFM 3 (a Bible as a folder of book
  files). Foundation only.
- **Versification:** Paratext's six standard versifications and a `.vrs` reader.

## Adding it

In Xcode: File, Add Package Dependencies, enter `https://github.com/logoshub-org/ScriptureViewer`, choose a version, and add the
**ScriptureViewer** library (the viewer, with the text model and the module reader). Or in a `Package.swift`:

```swift
.package(url: "https://github.com/logoshub-org/ScriptureViewer.git", from: "0.1.0")
// then: .product(name: "ScriptureViewer", package: "ScriptureViewer")
```

The other products are the portable parts alone, for code that does not draw anything: `ScriptureText`, `ScriptureTextOSIS`,
`ScriptureTextTEI`, `ScriptureTextThML`, `ScriptureTextGBF`, `ScriptureTextPlain`, `ScriptureTextSource`, `ScriptureTextUSFM`,
`ScriptureTextVersification` and `ScriptureTextMarkup`.

## Using it

Your app gives the package the unrendered entries of a chapter, by implementing `RawChapterReading` over whatever holds your modules
(an engine, files, a server). The package parses them by the module's markup:

```swift
import ScriptureViewer

let source = ScriptureModuleSource(reader: myReader)                 // your RawChapterReading
let chapter = source.chapter(module: "KJV", reference: "John 3", display: .init())   // a ScriptureText?

ScriptureViewer(text: chapter, theme: theme, highlights: marks, configuration: setup, controller: controller, events: events)
```

`ScriptureViewerEvents` holds the closures the viewer calls (`onScroll`, `onTap`, `onSelectionChange`, `onMenuItem`, `onPull`,
`onChromeRequest`, and the two questions it asks, `referenceLine` and `canHideChrome`). `ScriptureViewerController` carries your commands
to it (scroll to a verse, focus a verse). The full boundary, input by input and event by event, is in
[ScriptureViewerContract.md](ScriptureViewerContract.md).

## Android

The contract is written so that each platform supplies its own `ScriptureViewer`: on iOS it is this package's UIKit-backed view; on
Android it is a composable of the same name over a `TextView`, in [Android/](Android/README.md), taking the same values and reporting
the same events. It is built and tested on an emulator; it is not yet published as a library or hosted in an app. The portable core
(`ScriptureText` with the viewer contract, the markup tokenizer, the OSIS, GBF, ThML, TEI, plain-text and USFM parsers, the module
source and the versifications) is transpiled to Kotlin by [Skip](https://skip.dev) in `Transpile/` and checked against the Swift results.

## Tests

`swift test` runs the portable tests on macOS or Linux, against real module files in `TestModules/` (public-domain texts, and the KJV,
see its README). The viewer target is UIKit and builds for iOS only (on other platforms its files are empty).

## Versions

Semantic versioning. While the version starts with 0, the public API may still change between minor versions. The public surface of the
viewer target is kept small on purpose: what a host needs is `public`, and a test (`PackageGuardTests`) fails if it grows unnoticed.

## Licence

The package is MPL-2.0 (see [LICENSE](LICENSE)): each source file states it. It is portable by design and contains no GPL code, so a
GPL, proprietary or other application may use it, as the MPL allows. Embedded third-party data (SIL's Paratext versification files, the
USFM marker grouping) and the test modules keep their own licences: see [NOTICE](NOTICE).
