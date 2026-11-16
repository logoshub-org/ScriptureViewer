# Transpile

The portable scripture core, transpiled to Kotlin by [Skip Lite](https://skip.dev) for Android (plan D158). It is a package of its own,
nested in the repository: it builds the **same sources** as the package at the repository root (`ScriptureText`, `ScriptureTextMarkup`,
`ScriptureTextBuilding`, `ScriptureTextOSIS`) through symbolic links to `../Sources`, so there is one copy of the code. The iOS package does
not depend on it, and a user of that package never sees it: SwiftPM resolves only the package at the repository root, so this one cannot
be added by URL. It is the repository's own test that the core still transpiles, and the place the Android library's Kotlin core is built.

## What runs

`ScriptureTextOSISTests`: the Psalm 119 parity test, below, and a test of what a viewer asks of the model beyond parsing (a verse found,
painted and copied alone, a search). (The app's own navigation model, `AppModel`, is tested the same way, in the app's repository.)

The Kotlin this package leaves in `.build` is also what the Android viewer builds on: see `../Android/README.md`.

## Run the parity test

```
cd Transpile
swift test
```

The test parses Psalm 119 of the KJV from its raw OSIS and compares a digest of the model (text length, verses, spans, words, every
offset, the text) with `Tests/ScriptureTextOSISTests/Resources/expected_*.txt`. It runs twice: as Swift on macOS, and, through Skip's
test harness, as Kotlin on a JVM Android runtime (needs Gradle, a JDK and the Android SDK, as for any Skip project). Both must pass.

To rewrite the expected files after a deliberate change of the core's output: `GENERATE_EXPECTED=1 swift test --filter testGenerateExpectedWhenAsked`
(the Swift run is the reference; the Kotlin run must then match it).

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

`link-sources.sh` recreates the links. Run it after a file is added, moved or removed in one of the four targets. The viewer contract
(`Sources/ScriptureText/Viewer`) is linked too: its controller uses Observation, which Skip carries to Compose state through SkipModel,
a dependency of the `ScriptureText` target here for that reason.

## Writing code the transpiler takes

The rules are in plan D158: `Int` only (no `UInt8`/`UInt32`/`Unicode.Scalar`), text as code point arrays through `CodePoints`, no
`Substring` or `String.Index`, no double optionals or mutated tuples, `Codable` under `#if !SKIP`, `public` (not `package`) where a type
crosses modules; and inside a function whose argument label is also a property's name (`contains(verse number:)`), write `self.verse`
for the property, because in Kotlin the parameter takes the label's name and hides it. When the Kotlin run fails to compile, the log names the Kotlin line; the Swift line is in the same message.
