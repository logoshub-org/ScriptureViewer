// The versions are the ones Skip's generated projects use (see the settings file of the included build), so one Gradle run builds both.
plugins {
    id("com.android.library") version "9.2.0" apply false
    id("com.android.application") version "9.2.0" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.0" apply false
}
