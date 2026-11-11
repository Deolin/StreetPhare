// Script Gradle RACINE du projet Android (Modernisé Kotlin DSL).
//
// Responsabilités :
//   1. Définir un répertoire de build partagé (comportement standard Flutter).
//   2. === FORCER LE compileSdk DE TOUS LES PLUGINS ===
//      Essentiel pour AGP 9+ quand des plugins tiers (ex: flutter_reactive_ble)
//      déclarent un compileSdk obsolète (< 34).
//   3. Déclarer la tâche `clean`.
//
// NOTE (répertoire de build) : l'outil Flutter cherche l'APK sous
// `<projet>/build/app/outputs/flutter-apk/`. On redirige donc le buildDir des
// MODULES LOCAUX (:app, :mini_downloader) vers le dossier partagé `../../build`.
// En revanche, on EXCLUT les plugins Flutter tiers (chargés en sous-projets via
// `settings.include`, sources dans le Pub Cache — souvent sur un autre lecteur
// `C:`), car les rediriger provoquait l'erreur Gradle/AGP « this and base files
// have different roots » sur `:flutter_secure_storage:compileDebugUnitTestSources`.

val targetCompileSdk: Int = 37
val targetSdkVersion: Int = 36

// ── Répertoire de build partagé (Flutter attend l'APK sous build/app/) ──────
val sharedBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()

val repoRoot: File = rootProject.projectDir.parentFile.canonicalFile

subprojects {
    // Redirige UNIQUEMENT les modules dont la source vit dans ce dépôt
    // (:app, :mini_downloader). Les plugins Flutter tiers (Pub Cache sur un
    // autre lecteur) conservent leur buildDir par défaut.
    if (project.projectDir.canonicalFile.path.startsWith(repoRoot.path)) {
        val newSubprojectBuildDir: Directory = sharedBuildDir.dir(project.name)
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

// ============================================================================
// === COMPATIBILITÉ : force compileSdk = 37 sur tous les plugins
// ============================================================================

gradle.beforeProject {
    if (project.name == "app") return@beforeProject

    // Injection via les propriétés d'extension (extra)
    project.extra["compileSdkVersion"] = targetCompileSdk
    project.extra["targetSdkVersion"] = targetSdkVersion
    project.extra["compileSdk"] = targetCompileSdk
    project.extra["targetSdk"] = targetSdkVersion
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
