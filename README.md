# ScriptureViewer

A native scripture reader view for SwiftUI apps on iOS, and on Android through [Skip](https://skip.dev).

Give it a chapter of scripture and it shows it as styled, scrollable, selectable text, then tells your app what the reader taps,
selects and scrolls to. Your app keeps control of everything else: screens, navigation, bookmarks, lookups and settings.

## Where the scripture comes from

You supply the text. ScriptureViewer parses the formats Bible modules use:

- **SWORD-style modules** (CrossWire): OSIS, GBF, ThML, TEI and plain text. Your app hands over a chapter's raw entries from whatever
  holds them (a Bible engine, files, a server), and the package picks the right parser.
- **USFM 3 Bibles**: point it at a folder of book files, as published by eBible.org and Paratext.

Versification is built in: Paratext's six standard systems, and a reader for `.vrs` files.

## What the viewer gives your app

- Scrolls to an exact verse and reports which verse is at the top
- Headings, poetry, footnotes, cross-references, red letter, Strong's numbers, right-to-left text
- Selection and copy across paragraphs, with a reference line on copied text
- Bookmark and search highlights, and focus on a single verse
- Events for taps on a verse number, word, note or link, and for scrolls, swipes, selections and menu items
- Night mode, fonts, sizes and insets set by your app

## Installing

In Xcode, choose **File > Add Package Dependencies**, enter the URL below, and add the **ScriptureViewer** library.

```swift
.package(url: "https://github.com/logoshub-org/ScriptureViewer.git", from: "0.2.1")
```

Requires iOS 17. The parsers and text model are also available as separate libraries with no UI framework.

## Quick look

```swift
import ScriptureViewer

let source = ScriptureModuleSource(reader: myReader)   // your RawChapterReading
let chapter = source.chapter(module: "KJV", reference: "John 3", display: .init())

ScriptureViewer(text: chapter, theme: theme, highlights: marks,
                configuration: setup, controller: controller, events: events)
```

## Learn more

- [Instructions.md](Instructions.md) covers every library, loading SWORD-style and USFM text, the viewer's inputs and events, the Skip
  build and Android, and the tests.
- [ScriptureViewerContract.md](ScriptureViewerContract.md) specifies the viewer's inputs and events one by one.

## Licence

MPL-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
