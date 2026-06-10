plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutter_streetphare"
    // Android 16 (API 36) — Baklava
    // compileSdk 36 > 34 requis par les plugins (reactive_ble_mobile,
    // nearby_connections, geolocator_android, etc.) pour résoudre
    // l'erreur Gradle "CheckAarMetadataWorkAction".
    compileSdk = 36
    // NDK 28.2.13676358 = version la plus haute requise par les
    // plugins installés (rétrocompatible). Suppression du warning
    // Gradle "plugin requires a different NDK version".
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.flutter_streetphare"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdk 24 requis par plusieurs plugins (BLE, Nearby Connections) et
        // toujours compatible avec Android 16 (API 36).
        minSdk = maxOf(flutter.minSdkVersion, 24)
        // Cible Android 16 (API 36)
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
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
