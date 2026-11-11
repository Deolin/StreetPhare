// Script Gradle RACINE du projet Android (Modernisé Kotlin DSL).
//
// Responsabilités :
//   1. === FORCER LE compileSdk DE TOUS LES PLUGINS ===
//      Essentiel pour AGP 9+ quand des plugins tiers (ex: flutter_reactive_ble)
//      déclarent un compileSdk obsolète (< 34).
//   2. Déclarer la tâche `clean`.
//
// NOTE : on ne redirige PAS le répertoire de build vers un dossier partagé
// (`../../build`). Ce hack plaçait le build des plugins Flutter (dont le
// source vit dans le Pub Cache sur `C:`) sur un autre lecteur (`E:`),
// provoquant l'erreur Gradle/AGP « this and base files have different roots »
// sur `:flutter_secure_storage:compileDebugUnitTestSources`. Chaque projet
// conserve donc son répertoire de build par défaut, co-localisé avec son
// source (même lecteur) et il n'y a plus de franchissement de lecteurs.

val targetCompileSdk: Int = 37
val targetSdkVersion: Int = 36

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
