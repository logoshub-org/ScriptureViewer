# Transpile

The Kotlin parity tests of the package at the repository root. That package is a [Skip](https://skip.dev) package: its library
targets are transpiled to Kotlin for Android when it is built (plan D158). This package holds only tests, so that the package above stays
free of Skip's test machinery; it depends on it by path (`..`), and a user of that package never sees this one (SwiftPM resolves only the
package at the repository root).

## What runs

`swift test` runs each test target twice: as Swift on macOS, and, through Skip's test harness, as Kotlin on a JVM Android runtime (needs
Gradle, a JDK 21 or later (Robolectric needs it for Android SDK 36) and the Android SDK, as for any Skip project). Both must pass.

- `ScriptureTextOSISTests`: Psalm 119 of the KJV parsed from its raw OSIS, compared as a digest (text length, verses, spans, words, every
  offset, the text) with `expected_*.txt`; a test of what a viewer asks of the model beyond parsing (a verse found, painted and copied
  alone, a search); copying characters outside the Basic Multilingual Plane.
- `ScriptureTextSourceTests`: every other parser and the module source's choice among them. Four GBF chapters from the committed test
  modules (YLT Genesis 1, Weymouth Matthew 5, and the commentaries DTN Genesis 1 and TFG Matthew 1, with notes and reference marks) are read
  through `ScriptureModuleSource` as each source type and with two sets of display options, and sample entries go through the ThML, TEI and
  plain-text parsers; the digests (notes included) are compared with `expected_parsers.txt`. Also the versifications: Paratext's six
  systems read from their embedded files (every book, chapter, mapping and excluded verse, with the mappings applied both ways and across
  systems), the book table, and the reader on a file with the cases the six lack; compared with `expected_versification.txt`. And USFM:
  excerpts of five real books (KJV 2006 Genesis 1–3 and Psalm 119, BSB John 1 with Strong's numbers, WEB Matthew 5 and Tobit 1, all
  public domain) with four sets of options, each parsed whole, read as one Bible from a folder (versification by fit, then declared in a
  `Settings.xml`), and fragments with the markers the excerpts lack; compared with `expected_usfm.txt`. The digest code they share is
  `ModelDigest.swift`. These tests found two Android bugs the Swift tests could not: a repeated entry was shown twice
  (`ChapterEntries.shown`), and `ScriptureText`'s `contains(verse:)` held every verse up to its own.

Three of the tests guard speed: OSIS (Psalm 119), GBF (TFG Matthew 1) and USFM (Psalm 119) each parse the same text eight times over
and once, and fail if the longer run takes more than 16 times as long. Growth in proportion to the text gives about 8; the copying the
Kotlin build once did, which grew with the square, gives up to 64 (put back on purpose, it failed the OSIS and USFM tests at 23 and 29). A
ratio holds on any machine where a fixed time limit would not. (GBF's main text in that chapter is too short for the old bug to show; GBF
writes through the same builder as OSIS.) The two warm-ups (`ScriptureModuleSource.warmUp`, `USFMParser.warmUp`) are also run as Kotlin.

(The app's own navigation model, `AppModel`, is tested the same way, in the app's repository.)

To rewrite the expected files after a deliberate change of the core's output: `GENERATE_EXPECTED=1 swift test --filter testGenerate` (the
Swift run is the reference; the Kotlin run must then match it).

A test target is built into the Gradle project of the module it is named after (`ScriptureTextOSISTests` into `ScriptureTextOSIS`), so a
test target may only use modules below that one: tests that need the whole graph belong in `ScriptureTextSourceTests`.

## The viewer's check on Android

`Checks/WrapperCheck.kt` shows a chapter through the package's SwiftUI `ScriptureViewer` on Android (the `ScriptureViewerSkipUI`
module, whose body is the Compose viewer), checks the text on screen, and that a controller command reaches the view. It ran on the emulator (2026-11-17). It is not
wired into `swift test` (it needs an emulator and test dependencies the generated project does not have): to run it, build the package at
the repository root, add the file to
`../.build/plugins/outputs/scriptureviewer/ScriptureViewerSkipUI/destination/skipstone/ScriptureViewerSkipUI/src/androidTest/kotlin/scripture/viewer/skip/ui/`, add
`androidx.compose.ui:ui-test-junit4`, `androidx.test.espresso:espresso-core:3.7.0` and `ui-test-manifest` to that module's
`build.gradle.kts`, and run `gradle :ScriptureViewerSkipUI:connectedDebugAndroidTest` in its `skipstone` folder.

## Writing code the transpiler takes

Every library target of the package at the root is transpiled, so all of its code must follow these.

**What it accepts** (plan D158): `Int` only (no `UInt8`/`UInt32`/`Unicode.Scalar`); text as code point arrays through `CodePoints`; no
`Substring` or `String.Index`; no double optionals, no mutated tuples, no tuples in arrays (two arrays side by side, or a small struct);
`Codable` under `#if !SKIP`; `public` (not `package`) where a type crosses modules. Where Swift infers a type through a closure or a generic
(`.span(.link(target: $0))`, `list.append(.init(…))`), write the type out (`Frame.Kind.span(ScriptureText.Attribute.link(target: $0))`).
Write the NUL character as `"\u{0000}"`: Skip writes `"\u{0}"` as `"\u0"`, which Kotlin rejects.

**What it accepts but gets wrong.** These compile and run, and give a different answer in Kotlin; the parity tests are what find them:
- Inside a function whose argument label is also a property's name (`contains(verse number:)`), write `self.verse` for the property: in
  Kotlin the parameter takes the label's name and hides it.
- Do not build a string from a sequence operation on a string (`String(text.drop { … })`, `prefix(while:)`): in Kotlin these give a list of
  characters, not a string. Walk the code points (`CodePoints.of`, `CodePoints.string`).
- Do not test text with `Character` properties (`isWhitespace`, `isPunctuation`, `isNumber`) or Foundation's `CharacterSet`: a Kotlin
  `Char` is one UTF-16 unit, and the platforms' sets differ (Skip's `CharacterSet.whitespaces` is a short fixed list). Use the classes in
  `CodePoints` (`isWhiteSpace`, `isHorizontalWhiteSpace`, `isPunctuation`, `isSymbol`, `isNumber`, `isDecimalDigit`), which give the
  same answer on both platforms.
- No regular expressions: write the match out (`GBFParser.separatedReferences` is one, with the expression it replaces in its comment).

**What it rejects that Swift takes**, found on the way: `contains` on an array of strings inside a condition (use a `switch`), a
ternary that assigns an optional (use an `if`), and `replacingOccurrences` in a file without `import Foundation` (Skip's Foundation
supplies it).

**What is slow in Kotlin** (measured: these made the parser ten times slower before they were fixed; Psalm 119 went from about 105 ms to
about 10–12 ms warm on the emulator): do not grow a string with `+=` in a loop (a Kotlin string is copied each time: use `TextBuffer`); do
not `append` to an array that is a stored property in a loop (each append copies the array: use a local array, or `GrowingList`); and do
not keep a struct that is changed often as another type's stored property (each read of the property copies it: make it a class if it has
one owner). `TextBuffer` and `GrowingList` are in `ScriptureText/Text/Growing.swift`. `Android/demo` has a `ParseBenchmark` to measure with.

When the Kotlin run fails to compile, the log names the Kotlin line; the Swift line is in the same message.
