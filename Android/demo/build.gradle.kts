// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Logos Hub Ltd
//
// A screen to try the viewer by hand: Psalm 119 between two Compose bars that come and go as the viewer asks.
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "scripture.viewer.demo"
    compileSdk = 36
    defaultConfig {
        applicationId = "scripture.viewer.demo"
        minSdk = 28
        targetSdk = 36
        versionCode = 1
        versionName = "0.1"
    }
    buildFeatures { compose = true }
    buildTypes {
        // A release build to measure with (ParseBenchmark): optimised and not debuggable, signed with the debug key.
        release {
            isMinifyEnabled = true
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    sourceSets {
        named("main") {
            assets.directories.add("../../Transpile/Tests/ScriptureTextOSISTests/Resources")
            assets.directories.add("../../Transpile/Tests/ScriptureTextSourceTests/Resources")
            kotlin.directories.add("../shared/kotlin")
        }
    }
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
    compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 }
}

dependencies {
    implementation(project(":scriptureviewer"))
    implementation("org.logoshub.scripture:ScriptureTextOSIS")
    implementation("org.logoshub.scripture:ScriptureTextGBF")
    implementation(platform("androidx.compose:compose-bom:2026.05.01"))
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.activity:activity-compose:1.13.0")
}
