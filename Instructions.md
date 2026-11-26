# ScriptureViewer instructions

The details behind the [README](README.md): the products, how to feed the viewer text, the Skip build, Android, tests and versions. The
viewer's full boundary, input by input and event by event, is in [ScriptureViewerContract.md](ScriptureViewerContract.md).

## Contents

- [What the package does and does not do](#what-the-package-does-and-does-not-do)
- [Products](#products)
- [Installing](#installing)
- [Getting text into the viewer](#getting-text-into-the-viewer)
- [Showing it](#showing-it)
- [Skip and Android](#skip-and-android)
- [Tests](#tests)
- [Versions](#versions)
- [Licence](#licence)

## What the package does and does not do

The app that embeds it does the co-ordinating: it finds the scripture, decides what to show and what a tap should do. ScriptureViewer
turns a loaded text into a styled, scrollable, selectable text and reports what the reader does with it. It opens no screens, reads no
preferences, resolves no lookups and has no dependency on any Bible engine.

## Products

| Product | What it is | Needs |
|---|---|---|
| `ScriptureViewer` | The viewer, with the text model and the module reader. A SwiftUI view over a TextKit 2 text view. | iOS 17 |
| `ScriptureText` | The text model: text, styled spans, verse ranges, word anchors, paragraph roles, notes, passage identity. | Foundation |
| `ScriptureTextSource` | Chapters from a module's raw entries: picks the parser by the module's markup. | Foundation |
| `ScriptureTextOSIS` | The OSIS parser. | Foundation |
| `ScriptureTextGBF` | The GBF parser (CrossWire's older markup), for Bibles and commentaries. | Foundation |
| `ScriptureTextThML` | The ThML parser, for dictionaries, devotionals, commentaries and general books. | Foundation |
| `ScriptureTextTEI` | The TEI parser, for dictionary entries. | Foundation |
| `ScriptureTextPlain` | Text with no markup. | Foundation |
| `ScriptureTextUSFM` | USFM 3 Bibles: a folder of book files as a `ScriptureBible`. | Foundation |
| `ScriptureTextVersification` | Paratext's six standard versifications and a `.vrs` reader. | Foundation |
| `ScriptureTextMarkup` | The XML-shaped tokenizer under the OSIS, TEI and ThML parsers. | Foundation |

Everything but the viewer has no UI framework and builds on any platform Swift runs on. On macOS `ScriptureViewer` is a placeholder that
shows nothing, so code shared with iOS and Android still builds on a Mac.

## Installing

In Xcode: File, Add Package Dependencies, enter `https://github.com/logoshub-org/ScriptureViewer`, choose a version, and add the
**ScriptureViewer** library. Xcode asks you to trust the Skip build plugin the first time (Trust & Enable): see
[Skip and Android](#skip-and-android).

In a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/logoshub-org/ScriptureViewer.git", from: "0.2.1"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "ScriptureViewer", package: "ScriptureViewer"),
        // .product(name: "ScriptureTextUSFM", package: "ScriptureViewer"),   // for USFM Bibles
    ]),
]
```

## Getting text into the viewer

The viewer shows a `ScriptureText`. There are two ways to get one.

**From a module's raw entries (OSIS, GBF, ThML, TEI, plain text).** Your app implements `RawChapterReading` over whatever holds its
modules (a Bible engine such as SWORD, files, a server). It hands over a chapter's unrendered entries and the facts about the module;
`ScriptureModuleSource` picks the parser by the module's markup and applies the reader's display options:

```swift
import ScriptureViewer

struct MyReader: RawChapterReading {
    func facts(forModule name: String) -> ScriptureModuleFacts? { … }
    func rawChapter(forModule name: String, reference: String) -> RawChapter? { … }
    func plainChapter(forModule name: String, reference: String) -> RawChapter? { … }
}

let source = ScriptureModuleSource(reader: MyReader())
let chapter = source.chapter(module: "KJV", reference: "John 3", display: .init())   // ScriptureText?
```

**From a USFM Bible on disk.** Point `USFMBible` at a folder of USFM 3 book files; it reads the versification and parses a chapter on
request:

```swift
import ScriptureTextUSFM

let bible = try USFMBible(folder: bibleFolderURL)
let chapter = bible.chapter(book: "John", chapter: 3, display: .init())             // ScriptureText?
```

`ScriptureDisplayOptions` carries the reader's choices: headings, footnotes, cross-references, red letter, verse per line, Strong's
numbers and morphology, Greek accents and Hebrew points.

## Showing it

```swift
ScriptureViewer(text: chapter, theme: theme, highlights: marks, configuration: setup, controller: controller, events: events)
```

| Input | What it is |
|---|---|
| `ScriptureViewerTheme` | Night mode, font name and size, wide layout, right to left, an optional style sheet. |
| `ScriptureHighlights` | Bookmarked verses with their colours, search terms, a Strong's number. |
| `ScriptureViewerConfiguration` | Insets, whether it scrolls or sizes to its text, pull to change chapter, extra selection-menu items. |
| `ScriptureViewerController` | Your commands (scroll to a verse or offset, focus a verse, clear the selection) and what the reader last did (current verse, offset, selection), observable by your views. |
| `ScriptureViewerEvents` | The closures the viewer calls: `onScroll`, `onTap`, `onGesture`, `onSelectionChange`, `onMenuItem`, `onPull`, `onChromeRequest`, `onShare`, and the two questions it asks, `referenceLine` and `canHideChrome`. |

The viewer itself scrolls to an exact verse, knows which verse is at the top, dims all but a focused verse, selects and copies across
paragraphs, draws bookmark and search highlights, and finds what a tap landed on (a verse number, a word, a note letter, a link). Each
input and event is specified in [ScriptureViewerContract.md](ScriptureViewerContract.md).

## Skip and Android

It is a [Skip](https://skip.dev) package: when it is built, Skip's build plugin also writes the Kotlin of its library targets, for an
Android app built with Skip. Nothing of Skip runs in an iOS app.

- **Xcode asks you to trust the plugin** the first time (Trust & Enable). Command-line and CI builds pass
  `-skipPackagePluginValidation` to `xcodebuild`.
- **An iOS-only host can leave Skip out**: building with the environment variable `SKIP_ZERO=1` strips the plugin and the Skip
  dependencies, and the package is plain Swift.

One `ScriptureViewer`, two realisations behind the same contract. In an app built with Skip, the same SwiftUI code names the same view:
on iOS it is the UIKit text view; on Android (the `ScriptureViewerSkipUI` product) it is a Compose viewer over a `TextView`, whose
Kotlin is in [Android/](Android/README.md) and is linked into the target. Every library target goes through Skip, and the Kotlin is
checked against the Swift results by the parity tests in [Transpile/](Transpile/). A Skip app built from the package and the viewer's own
instrumented tests run on an Android emulator.

## Tests

The tests run against real module files in [TestModules/](TestModules/README.md) (public-domain texts, and the KJV).

- **Mac:** `swift test`, the quickest while working. The iOS viewer's tests are empty here (UIKit).
- **iOS simulator:** `xcodebuild test -scheme ScriptureViewer-Package -destination 'platform=iOS Simulator,name=…' -skipPackagePluginValidation`.
  This also runs `ScriptureViewerTests`, the iOS viewer in a window: scrolling to a verse, the verse at the top, a resize, a theme
  change, the end, gestures, the selection menu, and the styler against its golden file (`Tests/ScriptureViewerTests/Fixtures`).
- **Android:** the Kotlin parity tests in [Transpile/](Transpile/), and the viewer's instrumented tests on an emulator
  (see [Android/README.md](Android/README.md)).

CI runs the iOS, parity and Android emulator jobs.

## Versions

Semantic versioning. While the version starts with 0, the public API may still change between minor versions. The public surface of the
viewer target is kept small on purpose: what a host needs is `public`, and a test (`PackageGuardTests`) fails if it grows unnoticed.

## Licence

The package is MPL-2.0 (see [LICENSE](LICENSE)): each source file states it. It contains no GPL code, so a GPL, proprietary or other
application may use it, as the MPL allows. Embedded third-party data (SIL's Paratext versification files, the USFM marker grouping) and
the test modules keep their own licences: see [NOTICE](NOTICE).
