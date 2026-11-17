// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package scripture.viewer.demo

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import scripture.viewer.sample.SampleChapter

/**
 * Times the transpiled core parsing Psalm 119: the part of the Kotlin route that was slow before the core followed the speed rules in
 * Transpile/README.md.
 * Run the release build, since a debug build is several times slower:
 *
 *     ./gradlew :demo:installRelease
 *     adb shell am start -n scripture.viewer.demo/.ParseBenchmark [--ei runs 12] [--ei seconds 10] [--ei warm 3]
 *     adb logcat -s ScriptureViewerMeasure
 *
 * The first time of each line is a first parse in the process (code not yet compiled); the rest are warm. With `seconds`, it then
 * goes on parsing for that long, for a profiler to watch. With `warm`, it first runs `ScriptureModuleSource.warmUp` for that many rounds,
 * as an app would at launch, and logs how long that took: the first parse after it shows what the warm-up saves.
 */
class ParseBenchmark : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val runs = intent.getIntExtra("runs", 12)
        val seconds = intent.getIntExtra("seconds", 0)
        val warm = intent.getIntExtra("warm", 0)
        val entries = SampleChapter.rawEntries(assets)
        Thread {
            if (warm > 0) {
                val start = System.nanoTime()
                scripture.text.source.ScriptureModuleSource.warmUp(rounds = warm)
                Log.i("ScriptureViewerMeasure", "warm-up ($warm rounds): ${(System.nanoTime() - start) / 1_000_000} ms")
            }
            for (markers in listOf(false, true)) {
                val times = ArrayList<Long>()
                repeat(runs) {
                    val start = System.nanoTime()
                    SampleChapter.parse(entries, markers = markers)
                    times.add((System.nanoTime() - start) / 1_000_000)
                }
                val warm = times.drop(runs / 2).sorted()
                Log.i("ScriptureViewerMeasure", "parse Psalm 119 ${if (markers) "with markers" else "plain"}: first ${times.first()} ms, " +
                        "warm median ${warm[warm.size / 2]} ms; all $times")
            }
            val tfg = SampleChapter.rawEntries(assets, "tfg_matt1.json")
            val times = ArrayList<Long>()
            repeat(runs) {
                val start = System.nanoTime()
                SampleChapter.parseGBFCommentary(tfg)
                times.add((System.nanoTime() - start) / 1_000_000)
            }
            val warm = times.drop(runs / 2).sorted()
            Log.i("ScriptureViewerMeasure", "parse TFG Matthew 1 (GBF commentary): first ${times.first()} ms, warm median ${warm[warm.size / 2]} ms; all $times")
            val until = System.nanoTime() + seconds * 1_000_000_000L
            while (System.nanoTime() < until) SampleChapter.parse(entries, markers = false)
            Log.i("ScriptureViewerMeasure", "parse benchmark done")
        }.start()
    }
}
