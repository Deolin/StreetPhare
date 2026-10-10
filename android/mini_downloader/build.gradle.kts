// android/mini_downloader/build.gradle.kts
//
// Mini-installer StreetPhare — APK ultra-léger (~80 ko) distribué en P2P.
// Le destinataire installe ce mini-APK qui télécharge la dernière version
// complète depuis GitHub Releases et l'installe automatiquement.

import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.streetphare.mini_downloader"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.streetphare.downloader"
        minSdk = 24
        targetSdk = 36
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
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    // FileProvider pour ACTION_VIEW (Android 7+).
    implementation("androidx.core:core:1.15.0")
}

tasks.withType<KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}