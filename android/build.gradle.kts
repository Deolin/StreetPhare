// android/build.gradle.kts
//
// Script Gradle RACINE du projet Android.
//
// Responsabilités :
//   1. Déclarer les dépôts (Google, Maven Central) pour TOUS
//      les sous-projets (app + plugins Flutter).
//   2. Définir un répertoire de build partagé (à la racine du
//      repo Flutter, pas dans `android/build/`).
//   3. === FORCER LE compileSdk DE TOUS LES PLUGINS === pour
//      contourner le bug de `flutter_reactive_ble` (et autres)
//      qui déclarent compileSdk = 33 dans leur build.gradle
//      interne, ce qui déclenche l'erreur Gradle
//      `CheckAarMetadataWorkAction` quand les dépendances
//      AndroidX modernes (core, lifecycle, fragment, activity,
//      annotation-experimental, exifinterface…) exigent
//      compileSdk >= 34. Le script ci-dessous injecte une
//      propriété `compileSdkVersion` (et `targetSdkVersion`)
//      DÈS LE DÉBUT de l'évaluation de chaque sous-projet,
//      AVANT que le bloc `android { ... }` du plugin ne soit
//      parsé. C'est le seul timing qui marche : la valeur est
//      lue par AGP pendant la phase de configuration du plugin.
//   4. Déclarer la tâche `clean`.
//
// NOTE Java 8 → warning non-bloquant : nearby_connections 4.3.0 déclare
// encore `sourceCompatibility JavaVersion.VERSION_1_8`. Surcharger
// compileOptions via réflexion post-évaluation est impossible sans
// casser AGP 8+ (état gelé) — le warning javac est inhérent au plugin.

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

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
// === COMPATIBILITÉ : force compileSdk/targetSdk = 36 sur tous les plugins
// ============================================================================
//
// Le hook `gradle.beforeProject` s'exécute AVANT que le
// `build.gradle` du sous-projet ne soit évalué. À ce stade, on
// peut injecter des propriétés que les blocs `android { ... }`
// liront. C'est l'astuce documentée par la team Flutter pour
// gérer les plugins qui n'ont pas encore migré leur compileSdk.
//
// Référence : https://docs.gradle.org/current/dsl/org.gradle.api.invocation.Gradle.html
//             + ticket flutter/flutter#138297 (compileSdk plugins)
// ============================================================================

val targetCompileSdk: Int = 36

gradle.beforeProject {
    // Ne s'applique qu'aux sous-projets qui NE SONT PAS l'app
    // principale (`:app`), pour ne pas écraser la config
    // Kotlin DSL explicite de notre `app/build.gradle.kts`.
    if (project.name == "app") return@beforeProject

    // Injecte les propriétés Gradle qui seront lues par le
    // bloc `android { compileSdk = <valeur> }` de chaque
    // plugin. Si le plugin utilise `compileSdk project.property(...)`
    // ou `compileSdk rootProject.ext.compileSdkVersion`, ces
    // valeurs seront prises en compte.
    project.ext.set("compileSdkVersion", targetCompileSdk)
    project.ext.set("targetSdkVersion", targetCompileSdk)
    project.ext.set("compileSdk", targetCompileSdk)
    project.ext.set("targetSdk", targetCompileSdk)
}

// Variante "post-evaluation" : pour les plugins qui ne lisent
// pas les propriétés `ext.*` (la plupart, malheureusement, ont
// une valeur en dur dans leur `build.gradle`), on force aussi
// compileSdkVersion via réflexion sur l'extension `android`.
//
// NOTE : la surcharge de compileOptions.sourceCompatibility via
// réflexion post-évaluation est intentionnellement OMISE ici.
// AGP 8+ gèle l'état de CompileOptions après l'évaluation ; toute
// modification réflexive déclenche un "Failed to notify project
// evaluation listener" non rattrapable qui casse le build.
// Le warning javac "source value 8 is obsolete" de nearby_connections
// est un avertissement non-bloquant inhérent au plugin 4.3.0 lui-même.
gradle.projectsEvaluated {
    rootProject.subprojects {
        if (project.name == "app") return@subprojects
        if (project.extensions.findByName("android") != null) {
            try {
                val androidExt = project.extensions.getByName("android")

                // ── Force compileSdkVersion ──────────────────────────────
                androidExt.javaClass.methods.firstOrNull {
                    it.name == "setCompileSdkVersion" &&
                        it.parameterCount == 1 &&
                        it.parameterTypes[0] == Int::class.javaPrimitiveType
                }?.invoke(androidExt, targetCompileSdk)
            } catch (_: Throwable) {
                // Ignorer : un plugin peut utiliser un DSL exotique.
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
