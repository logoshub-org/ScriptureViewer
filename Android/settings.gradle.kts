// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// The Android scripture viewer (plan D185): a hand-written `TextView` surface under a thin Compose wrapper, over the portable core
// as Kotlin. The core is not copied here: it is what `swift build` in ../Transpile leaves (Skip Lite, plan D158), taken in as an
// included build, so there is one copy of the model, the contract and the parsers.
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositories { google(); mavenCentral() }
}
rootProject.name = "ScriptureViewerAndroid"

val core = file("../Transpile/.build/plugins/outputs/transpile/ScriptureTextOSIS/destination/skipstone")
require(core.resolve("settings.gradle.kts").exists()) {
    "The Kotlin core is not built: run `swift build` in ../Transpile first (looked in $core)."
}
// Kotlin's incremental compilation goes wrong in the core when a file is transpiled again (it compiles the changed file without the
// rest of its module, which Skip's linked module folders seem to cause), so it is off for this build and the one it includes.
gradle.startParameter.projectProperties = gradle.startParameter.projectProperties + mapOf("kotlin.incremental" to "false")
includeBuild(core) {
    name = "scripture-core"
    dependencySubstitution {
        substitute(module("org.logoshub.scripture:ScriptureText")).using(project(":ScriptureText"))
        substitute(module("org.logoshub.scripture:ScriptureTextOSIS")).using(project(":ScriptureTextOSIS"))
    }
}

include(":scriptureviewer")
include(":demo")
