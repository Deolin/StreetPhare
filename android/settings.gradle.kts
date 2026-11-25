// android/settings.gradle.kts
//
// Gestionnaire de plugins pour le projet Android Flutter.
// Ref: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin

pluginManagement {
    val flutterSdkPath = resolveFlutterSdk()
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lecture robuste de local.properties (généré par Flutter en local).
//
// Absent sur un runner CI frais (CodeQL, etc.) : on replie sur l'environnement
// au lieu de planter sur FileNotFoundException. Le comportement local est
// inchangé quand le fichier existe.
//
// NB : sdk.dir n'est PAS lu ici — le plugin Android Gradle (AGP) le résout
// lui-même depuis local.properties, puis ANDROID_HOME / ANDROID_SDK_ROOT.
// ─────────────────────────────────────────────────────────────────────────────
fun resolveFlutterSdk(): String {
    val localFile = java.io.File(rootDir, "local.properties")
    if (localFile.exists()) {
        runCatching {
            localFile.inputStream().use { input ->
                val properties = java.util.Properties()
                properties.load(input)
                properties.getProperty("flutter.sdk")
            }
        }.getOrNull()?.takeIf { it.isNotBlank() }?.let { return it }
    }

    for (env in listOf("FLUTTER_ROOT", "FLUTTER_HOME")) {
        val value = System.getenv(env)
        if (!value.isNullOrBlank()) return value
    }

    error(
        "flutter.sdk introuvable : ajoutez-le dans android/local.properties " +
            "ou définissez FLUTTER_ROOT (ou FLUTTER_HOME) dans l'environnement."
    )
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)

    repositories {
        google()
        mavenCentral()
        // Remote Flutter engine artifacts repository for io.flutter:* dependencies.
        maven("https://storage.googleapis.com/download.flutter.io")
        // Local Flutter engine artifacts (AARs) so Gradle can resolve io.flutter:* artifacts
        maven(uri("${resolveFlutterSdk()}/bin/cache/artifacts/engine/android"))
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.3.1" apply false
    id("org.jetbrains.kotlin.android") version "2.4.20" apply false
}

include(":app")
include(":mini_downloader")