// android/mini_downloader/build.gradle.kts
//
// Mini-installer StreetPhare — APK ultra-léger (~80 ko) distribué en P2P.
// Le destinataire installe ce mini-APK qui télécharge la dernière version
// complète depuis GitHub Releases et l'installe automatiquement.

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.streetphare.downloader"

    compileSdk = 35

    defaultConfig {
        applicationId = "com.streetphare.downloader"
        minSdk = 21
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        release {
            // Minification et shrink désactivés temporairement —
            // la combinaison isMinifyEnabled + isShrinkResources sur
            // un APK sans ressources XML de layout peut produire
            // un APK vide. À réactiver après validation du build.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }
}

dependencies {
    // FileProvider pour ACTION_VIEW (Android 7+).
    implementation("androidx.core:core:1.15.0")
}