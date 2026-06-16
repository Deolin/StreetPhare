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

gradle.projectsEvaluated {
    rootProject.subprojects {
        if (project.name == "app") return@subprojects
        if (project.extensions.findByName("android") != null) {
            try {
                // Utilisation de l'API standard AGP (via réflexion pour la souplesse)
                val androidExt = project.extensions.getByName("android")
                androidExt.javaClass.methods.firstOrNull {
                    it.name == "setCompileSdkVersion" &&
                        it.parameterCount == 1 &&
                        it.parameterTypes[0] == Int::class.javaPrimitiveType
                }?.invoke(androidExt, targetCompileSdk)
            } catch (_: Throwable) { }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
