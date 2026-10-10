// Built-in Kotlin is enabled (AGP 9.0+)
// Ref: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Suppression des avertissements de dépréciation AGP 9.0
// (BaseAppModuleExtension toujours fonctionnel en attendant AGP 10.0)
android {
    namespace = "com.example.flutter_streetphare"
    // Android 16 (API 36) — Baklava
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        // ── Core Library Desugaring ──────────────────────────────────────
        // Requis par flutter_local_notifications pour les APIs java.time.*
        // sur Android < API 26.
        // Note AGP 9+ : la propriété Kotlin DSL s'appelle
        // `isCoreLibraryDesugaringEnabled` (préfixe `is` pour les booléens).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.flutter_streetphare"
        // minSdk 24 requis par BLE, Nearby Connections.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        // Cible Android 16 (API 36)
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // Enable R8 minification with keep rules for OsmAnd/protobuf classes
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            // R8 applique les règles keep/dontwarn même sans minification.
            // Requis pour éviter le crash ClassNotFoundException au démarrage
            // quand une dépendance (ex: flutter_reactive_ble via ObjectBox,
            // ou graphhopper-core) référence javax.lang.model.SourceVersion.
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

}

// Configuration Kotlin via le bloc `kotlin { compilerOptions }` (AGP 9+)
// — remplace l'ancien bloc `kotlinOptions { jvmTarget }` qui est déprécié.
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
    // Version 2.1.4 compatible AGP 9.x + flutter_local_notifications 18.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // ── GraphHopper Core — Moteur de routage piéton embarqué ─────────────
    // Licence Apache 2.0 · https://github.com/graphhopper/graphhopper
    // Remplace l'appel externe OsmAnd pour un calcul 100% in-app & offline.
    // Lit les fichiers .osm.pbf ou .pbf (OpenStreetMap) fournis localement.
    // Version 7.0 testée et stable sur Android API 24+.
    implementation("com.graphhopper:graphhopper-core:7.0") {
        // ── Exclusions des dépendances lourdes inutiles sur Android ─────
        // xmlgraphics-commons : import élévation TIF (inutilisé)
        exclude(group = "org.apache.xmlgraphics")
        // jackson-dataformat-xml : lecture OSM XML via StAX (inutilisée, on lit du .pbf)
        exclude(group = "com.fasterxml.jackson.dataformat")
        //
        // ⚠️ protobuf-java et jts-core SONT CONSERVÉS (plus d'exclusion) :
        //   - protobuf-java : requis par osmosis-osm-binary (lecture des .pbf)
        //   - jts-core      : requis par GraphHopper (AreaIndex, custom model « zones »)
    }
    // SLF4J requis par GraphHopper (Android binding)
    implementation("org.slf4j:slf4j-android:1.7.36")
}

// ════════════════════════════════════════════════════════════════════════════
// Résolution du conflit protobuf-java (full) vs protobuf-javalite (lite)
// ════════════════════════════════════════════════════════════════════════════
// MLKit (via mobile_scanner) tire protobuf-javalite, qui partage ~360 classes
// avec protobuf-java (full) → « Duplicate class » sous R8. protobuf-java étant
// un sur-ensemble de protobuf-javalite, on exclut le variant lite : le code
// généré lite (MLKit) reste compatible avec le runtime complet.
configurations.all {
    exclude(group = "com.google.protobuf", module = "protobuf-javalite")
}
