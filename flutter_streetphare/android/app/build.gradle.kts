plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutter_streetphare"
    // Android 16 (API 36) — Baklava
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        // ── Core Library Desugaring ──────────────────────────────────────
        // Requis par flutter_local_notifications pour les TimezoneAware
        // APIs (java.time.*) sur Android < 26 (Oreo).
        // Sans cela : build error "D8: Program type already present:
        //   j$.time.zone.ZoneRulesProvider"
        coreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.flutter_streetphare"
        // minSdk 24 requis par BLE, Nearby Connections.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ── Core Library Desugaring ──────────────────────────────────────────
    // Fournit les implémentations Java 8+ (java.time, streams, etc.)
    // pour les appareils Android < API 26.
    // Version 2.1.4 = dernière compatible avec AGP 8.x + flutter_local_notifications 18.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
