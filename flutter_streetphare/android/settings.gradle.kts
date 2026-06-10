// android/settings.gradle.kts
//
// Gestionnaire de plugins pour le projet Android Flutter.
//
// Avec android.builtInKotlin=true (gradle.properties), le plugin Flutter
// applique automatiquement le plugin Kotlin dans le sous-projet :app.
// La déclaration ci-dessous (`apply false`) permet de :
//   1. Fixer une version GLOBALE de Kotlin pour tous les sous-projets
//      (évite les warnings "KGP incompatible version" des plugins tiers).
//   2. Laisser chaque sous-projet décider d'appliquer ou non le plugin
//      via son propre build.gradle.
//
// Version Kotlin 2.3.20 = dernière stable compatible AGP 9.x + Flutter 3.x
// (Kotlin 2.x est requis pour les nouvelles API Compose Compiler).

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
    // Version Kotlin globale — alignée sur tous les sous-projets (flutter_reactive_ble,
    // mobile_scanner, nearby_connections, geolocator_android, etc.)
    // Supprime les avertissements "Built-in Kotlin / KGP incompatible version".
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
