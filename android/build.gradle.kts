// android/build.gradle.kts
//
// Script Gradle RACINE du projet Android (Modernisé Kotlin DSL).
//
// Responsabilités :
//   1. Définir un répertoire de build partagé.
//   2. === FORCER LE compileSdk DE TOUS LES PLUGINS ===
//      Essentiel pour AGP 9+ quand des plugins tiers (ex: flutter_reactive_ble)
//      déclarent un compileSdk obsolète (< 34).
//   3. Déclarer la tâche `clean`.

val targetCompileSdk: Int = 36

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

// ============================================================================
// === COMPATIBILITÉ : force compileSdk = 36 sur tous les plugins
// ============================================================================

gradle.beforeProject {
    if (project.name == "app") return@beforeProject

    // Injection via les propriétés d'extension (extra)
    project.extra["compileSdkVersion"] = targetCompileSdk
    project.extra["targetSdkVersion"] = targetCompileSdk
    project.extra["compileSdk"] = targetCompileSdk
    project.extra["targetSdk"] = targetCompileSdk
}

// ============================================================================
//  Forçage du compileSdk sur TOUS les projets (plugins Flutter inclus)
//  ---------------------------------------------------------------------------
//  Les plugins Flutter (objectbox_flutter_libs, etc.) sont chargés comme
//  projets composites par le Flutter Plugin Loader. On intercepte
//  l'application du plugin Android avec pluginManager.withPlugin()
//  pour garantir que le compileSdk est override AVANT évaluation.
// ============================================================================
gradle.rootProject.allprojects {
    // Intercepte tout projet (y compris composites) dès que le plugin
    // Android Library est appliqué.
    pluginManager.withPlugin("com.android.library") {
        try {
            extensions.configure<com.android.build.api.dsl.LibraryExtension> {
                compileSdk = targetCompileSdk
            }
            logger.lifecycle(
                "StreetPhare: forced compileSdk=${targetCompileSdk} on :${project.name} (Library)"
            )
        } catch (_: Exception) {
            // projet sans LibraryExtension
        }
    }

    // Même interception pour le plugin Android Application (au cas où un
    // plugin l'utiliserait — normalement seul :app le fait)
    pluginManager.withPlugin("com.android.application") {
        if (project.name == "app") return@withPlugin
        try {
            extensions.configure<com.android.build.api.dsl.ApplicationExtension> {
                compileSdk = targetCompileSdk
            }
            logger.lifecycle(
                "StreetPhare: forced compileSdk=${targetCompileSdk} on :${project.name} (App)"
            )
        } catch (_: Exception) { }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
