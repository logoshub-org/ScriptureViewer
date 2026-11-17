# ScriptureViewer for Android

The Android realisation of the [viewer contract](../ScriptureViewerContract.md): a composable named `ScriptureViewer` that takes the same
values as the iOS view and reports through the same events.

```kotlin
ScriptureViewer(text = chapter, theme = theme, highlights = marks, configuration = setup, controller = controller, events = events)
```

Underneath it is a selectable `TextView` holding the chapter as one `Spannable`, in a `NestedScrollView`, hosted by Compose's
`AndroidView` (plan D185). The text model, the contract types (`ScriptureViewerTheme`, `ScriptureViewerController`, `ScriptureViewerEvents`
and the rest) and the bar rule are not written again here: they are the Swift sources of `../Sources/ScriptureText`, transpiled to Kotlin by
Skip when the package at the repository root is built (package `scripture.text`). The viewer's own Kotlin is package
`scripture.viewer.compose`: the same files are this library and, linked into `../Sources/ScriptureViewer/Skip/`, the Android side of the
package's `ScriptureViewer` (which is `scripture.viewer.ScriptureViewer` in Kotlin, a SwiftUI view whose body is this composable).

## What is here

| | |
|---|---|
| `scriptureviewer/` | The library. `AndroidScriptureViewer.kt` (the composable and the bridge to the contract), `AndroidTextView.kt` (the view: scrolling, verse geometry, taps, gestures, selection menu, copy, highlights, focus), `AndroidTextStyler.kt` (the model to a `Spannable`), `AndroidTextTheme.kt` (colours, typeface and sizes in pixels). The files are named apart from the Swift ones, because Skip writes each Swift file as a Kotlin file of the same name beside them. |
| `scriptureviewer/src/androidTest/` | The tests, run on a device or an emulator. |
| `demo/` | An app to try it by hand: Psalm 119 between two Compose bars that come and go as the viewer asks. |
| `shared/` | Psalm 119 parsed on the device from its raw OSIS, for the demo and the tests. |

## Build and test

The Kotlin core must exist first, and again after any change to the Swift core:

```
cd .. && swift build                                     # or: swift build --target ScriptureTextSource (all this project needs)
```

Then, with `JAVA_HOME` (a JDK 21 or later, for example Android Studio's `jbr`; the Kotlin tests in `../Transpile` need 21) and the Android SDK (`ANDROID_HOME`, or `sdk.dir` in
`local.properties`):

```
./gradlew :scriptureviewer:assembleDebug
./gradlew :scriptureviewer:connectedDebugAndroidTest     # needs a running emulator or a device
./gradlew :demo:installDebug
```

CI runs the instrumented tests on every push: the job "Viewer on an Android emulator" (`.github/workflows/ci.yml`) transpiles the core
on a Linux runner and runs them on an API 34 emulator (ReactiveCircus/android-emulator-runner).

The settings file takes the core in as an included build (Skip's generated Gradle project for `ScriptureTextSource`, which holds
`ScriptureText`, the OSIS, GBF, ThML and plain-text parsers, the module source, `SkipModel`, `SkipFoundation` and `SkipLib`), under the
names `org.logoshub.scripture:<module>`. The library needs only `ScriptureText`; the demo and the tests also use the OSIS and GBF parsers.
The plugin versions are the ones Skip's generated projects use (Android Gradle plugin 9.2.0, Kotlin 2.3.0), so that one Gradle run builds both.

## How it differs from the iOS view

- **Units.** Offsets (`onScroll`, `scroll(toOffset:)`, the controller's `scrollOffset`) and insets are in dp, where iOS has points. The
  theme's font size is in CSS points on both; here one CSS point is 4/3 sp, so the text also follows the system's font size setting.
- **The verse at the top** is the first verse that begins on the top line, or the verse that line is part of. (iOS takes the verse at the
  start of the top paragraph.) A scroll to a verse reports that verse, and scrolling to the verse reported moves nothing.
- **A pull** past the top or the end is measured by how far the finger goes on (130 dp, 260 dp on the wide layout), since an Android
  scroll view does not follow a pull the way an iOS one does.
- **The end of the text** is also reported when the reader drags at the end, because nothing scrolls there to say so.
- **The controller's `isAtEnd`** goes back to false when a new text is shown.
- **The selection menu** shows the host's items first, then the system's Copy, Share and Select all; Copy and Share give the reader's
  copy (the core's `copiedText`, with the host's reference line).
- **Fonts.** The preference's font names come from the iOS list: serif and monospaced ones get Android's serif and monospace families,
  a family Android knows by name is used as it is, and anything else is the system's sans serif.

## Measured (2026-11-16)

On the Android 17 emulator (arm64, 1080 by 2400) on an M-series Mac, which is not a mid-range phone:

| | Psalm 119 | With Strong's and morphology markers |
|---|---|---|
| Text | 13,599 characters, 340 lines | 21,509 characters, 491 lines |
| Styling (model to `Spannable`) | 6 ms | 19 ms |
| Measure and layout | 7 ms | 17 ms |

Parsing that chapter from its raw OSIS in the transpiled core takes about 10–12 ms once warm (it was about 105 ms before the core was
changed for Kotlin: the rules are in `../Transpile/README.md`); the first parse in a process takes 310–420 ms as installed and 127–160 ms
when the app is compiled ahead of time. A GBF commentary chapter (TFG Matthew 1, 17 KB of entries with notes and reference marks) parses
in about 6 ms warm, and in 5–9 ms the first time, since GBF goes through the OSIS parser, already warm by then. `demo` has a
`ParseBenchmark` activity that measures these on a release build.

**The first parse in a process** is the slow one: the code is loaded and compiled as it first runs. A host should call
`ScriptureModuleSource.warmUp()` (and `USFMParser.warmUp()` if it reads USFM Bibles) at launch, off the main thread: it parses small
built-in samples in each format. Measured on the emulator, as installed: the first Psalm 119 parse took 340–570 ms with no warm-up, and
30–33 ms (the same as warm) after the default ten rounds, which took 340–470 ms themselves. `ParseBenchmark --ei warm 10` shows this.

Scrolling the chapter by hand for five seconds drew 351 frames with 1 janky (0.3%). A highlight change adds and removes spans and
requests no layout (the `Layout` object stays the same one); painting 176 bookmarked verses and 251 search hits at once took 125 ms.

## Not done yet

- **A real device and TalkBack.** The text is exposed to accessibility as one `TextView` (not an edit box) that can be moved through by
  word, line and paragraph, which a test checks; nobody has listened to it with TalkBack, and there is no navigation by verse.
- **Hosting in PocketSword.** The package's `ScriptureViewer` is this composable on Android, and a Skip app built from the package showed
  Psalm 119 through it on the emulator; no PocketSword screen uses it yet.
- **USFM in this project.** The demo and the tests take their Kotlin from the build of `ScriptureTextSource`, which does not hold
  USFM or TEI (nothing in that graph needs them); an app built with Skip gets every module it imports.
- **Publishing.** No AAR is published, and nothing here is in CI (the tests need an emulator).
- **Two- and three-finger gestures** are implemented and their rules tested, but not driven by real touches.
