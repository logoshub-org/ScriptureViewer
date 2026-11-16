# Transpile

The portable scripture core, transpiled to Kotlin by [Skip Lite](https://skip.dev) for Android (plan D158). It is a package of its own,
nested in the repository: it builds the **same sources** as the package at the repository root (`ScriptureText`, `ScriptureTextMarkup`,
`ScriptureTextBuilding`, `ScriptureTextOSIS`) through symbolic links to `../Sources`, so there is one copy of the code. The iOS package does
not depend on it, and a user of that package never sees it: SwiftPM resolves only the package at the repository root, so this one cannot
be added by URL. It is the repository's own test that the core still transpiles, and the place the Android library's Kotlin core is built.

## What runs

`ScriptureTextOSISTests`: the Psalm 119 parity test, below. (The app's own navigation model, `AppModel`, is tested the same way, in the
app's repository.)

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

## Keep the links current

`link-sources.sh` recreates the links. Run it after a file is added, moved or removed in one of the four targets. The viewer contract
(`Sources/ScriptureText/Viewer`) is left out because it uses Observation, which the transpiler does not take: the Android viewer needs its own
Kotlin versions of those types.

## Writing code the transpiler takes

The rules are in plan D158: `Int` only (no `UInt8`/`UInt32`/`Unicode.Scalar`), text as code point arrays through `CodePoints`, no
`Substring` or `String.Index`, no double optionals or mutated tuples, `Codable` under `#if !SKIP`, `public` (not `package`) where a type
crosses modules. When the Kotlin run fails to compile, the log names the Kotlin line; the Swift line is in the same message.
