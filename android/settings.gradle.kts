// android/settings.gradle.kts
//
// Gestionnaire de plugins pour le projet Android Flutter.
//
// Mode actuel : android.builtInKotlin=false (gradle.properties)
// → Les plugins tiers (flutter_local_notifications 22.0.0, mobile_scanner 7.x,
//   reactive_ble_mobile 5.x) appliquent encore `kotlin-android` manuellement.
//   Avec builtInKotlin=true + AGP 9.0, cela provoque une IllegalStateException.
//   On maintient builtInKotlin=false et on déclare KGP ici pour épingler la version
//   globalement (tous les sous-projets utilisent KGP 2.4.0).
//
// Quand migrer vers builtInKotlin=true ?
//   Lorsque TOUS les plugins ci-dessus auront supprimé leur `apply 'kotlin-android'`
//   interne. Retirer alors la ligne id("org.jetbrains.kotlin.android") de ce fichier
//   ET de android/app/build.gradle.kts, puis passer builtInKotlin=true.
//
// Ref: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    // KGP déclaré ici pour épingler la version globalement (builtInKotlin=false).
    // apply false → le plugin est disponible sur le classpath mais non appliqué ici ;
    // il est appliqué explicitement dans android/app/build.gradle.kts.
    // Les plugins tiers (mobile_scanner, reactive_ble_mobile, etc.) utiliseront
    // cette version 2.4.0 quand ils feront leur propre `apply 'kotlin-android'`.
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
