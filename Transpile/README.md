# Transpile

The portable scripture core, transpiled to Kotlin by [Skip Lite](https://skip.dev) for Android (plan D158). It is a package of its own,
nested in the repository: it builds the **same sources** as the package at the repository root through symbolic links to `../Sources`, so
there is one copy of the code. The iOS package does not depend on it, and a user of that package never sees it: SwiftPM resolves only the
package at the repository root, so this one cannot be added by URL. It is the repository's own test that the core still transpiles, and the
place the Android library's Kotlin core is built.

What goes through Skip: `ScriptureText` (the model, the viewer contract, the bar rule), `ScriptureTextMarkup`, `ScriptureTextBuilding`,
the parsers `ScriptureTextOSIS`, `ScriptureTextGBF`, `ScriptureTextThML`, `ScriptureTextTEI` and `ScriptureTextPlain`, and
`ScriptureTextSource` (which picks the parser for a module), `ScriptureTextVersification` (Paratext's six systems and the `.vrs`
reader) and `ScriptureTextUSFM` (USFM books and Bibles). That is every target of the portable core; only the iOS viewer is not.

## What runs

`swift test` runs each test target twice: as Swift on macOS, and, through Skip's test harness, as Kotlin on a JVM Android runtime (needs
Gradle, a JDK and the Android SDK, as for any Skip project). Both must pass.

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
  `ModelDigest.swift`. It found two Android bugs the Swift tests
  could not: a repeated entry was shown twice (`ChapterEntries.shown`), and `ScriptureText`'s `contains(verse:)` held every verse up to its own.

(The app's own navigation model, `AppModel`, is tested the same way, in the app's repository.) The Kotlin this package leaves in `.build`
is also what the Android viewer builds on: see `../Android/README.md`.

To rewrite the expected files after a deliberate change of the core's output: `GENERATE_EXPECTED=1 swift test --filter testGenerate` (the
Swift run is the reference; the Kotlin run must then match it).

## The SwiftUI viewer for the Skip-built app

`ScriptureViewerSkip` is the `ScriptureViewer` SwiftUI view for an app built by Skip: the same name and values as the iOS view in the
package, so the app's shared screens use it unchanged. On Android its body is Skip's `ComposeView` around the Compose viewer in
`../Android/scriptureviewer`, whose Kotlin files are linked into the module's `Skip/` folder (`link-sources.sh`), so there is one copy of the
viewer. On iOS the module builds but is empty: the app takes the iOS view from the package.

It compiles with the generated Gradle project, and `Checks/WrapperCheck.kt` ran on the emulator (it shows a chapter through the
SwiftUI view, checks the text on screen and that a controller command reaches the view). That check is not wired into `swift test` (it needs
an emulator and a few test dependencies the generated project does not have): to run it, build, add the file to
`.build/plugins/outputs/transpile/ScriptureViewerSkip/destination/skipstone/ScriptureViewerSkip/src/androidTest/kotlin/scripture/viewer/skip/`,
add `androidx.compose.ui:ui-test-junit4`, `androidx.test.espresso:espresso-core:3.7.0` and `ui-test-manifest` to its `build.gradle.kts`, and run
`gradle :ScriptureViewerSkip:connectedDebugAndroidTest`.

## Keep the links current

`link-sources.sh` recreates the links. Run it after a file is added, moved or removed in one of the linked targets. The viewer contract
(`Sources/ScriptureText/Viewer`) is linked too: its controller uses Observation, which Skip carries to Compose state through SkipModel,
a dependency of the `ScriptureText` target here for that reason.

A test target is built into the Gradle project of the module it is named after (`ScriptureTextOSISTests` into `ScriptureTextOSIS`), so a
test target may only use modules below that one: tests that need the whole graph belong in `ScriptureTextSourceTests`.

## Writing code the transpiler takes

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
