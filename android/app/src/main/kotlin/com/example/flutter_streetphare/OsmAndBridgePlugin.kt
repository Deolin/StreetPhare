// ============================================================================
// OsmAndBridgePlugin.kt — StreetPhare v1.3  (2026-06-11)
// ============================================================================
//
// Moteur de routage piéton EMBARQUÉ pour StreetPhare.
// Implémenté via Flutter MethodChannel "com.streetphare/routing".
//
// Architecture :
//   Dart → MethodChannel → OsmAndBridgePlugin → GraphHopper Core (Apache 2.0)
//                                              → OsmAnd AIDL (si installé)
//
// LICENCE GRAPHHOPPER :
//   Copyright (C) 2012–2024 GraphHopper GmbH and contributors.
//   Licensed under the Apache License, Version 2.0.
//   Aucune restriction de redistribution ni obligation GPL.
//
// CONFORMITÉ OSM DATA :
//   Les données géographiques utilisées (fichiers .osm.pbf) sont issues
//   d'OpenStreetMap © OpenStreetMap contributors (ODbL 1.0).
//   Toute redistribution du jeu de données doit respecter l'ODbL.
//
// ============================================================================
package com.example.flutter_streetphare

import android.content.Context
import android.util.Log
import com.graphhopper.GHRequest
import com.graphhopper.GHResponse
import com.graphhopper.GraphHopper
import com.graphhopper.config.Profile
import com.graphhopper.util.Parameters
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean

// ════════════════════════════════════════════════════════════════════════════
// Constantes
// ════════════════════════════════════════════════════════════════════════════

private const val TAG = "StreetPhare.OsmAndBridge"

/// Nom du canal Flutter MethodChannel.
const val CHANNEL_NAME = "com.streetphare/routing"

/// Canal EventChannel pour la progression de l'initialisation du moteur.
const val ROUTING_PROGRESS_EVENT = "com.streetphare/routing_progress"

/// Fichiers OSM acceptés dans les assets Android, essayés dans l'ordre.
///   - .osm.pbf : PBF (Geofabrik + osmium) — recommandé
///   - .osm / .xml : XML (Overpass Turbo / JOSM) — plus simple sans osmium
private val OSM_ASSET_CANDIDATES = listOf(
    "osm/fleurus.osm.pbf",
    "osm/fleurus.osm",
    "osm/fleurus.osm.xml",
    "osm/fleurus.xml",
)

/// Profil de routage piéton (foot).
private const val FOOT_PROFILE = "foot"

/// Profil de routage véhicule (car) — respecte le code de la route.
private const val CAR_PROFILE = "car"

// ════════════════════════════════════════════════════════════════════════════
// OsmAndBridgePlugin
// ════════════════════════════════════════════════════════════════════════════

/**
 * Plugin Flutter qui expose le moteur de routage GraphHopper
 * via un MethodChannel Dart.
 *
 * Méthodes exposées :
 *   - `isEngineReady` → Boolean : moteur initialisé et prêt
 *   - `computeRoute`  → Map    : calcule 1 itinéraire piéton principal
 *   - `computeRouteWithAlternatives` → Map : calcule jusqu'à 3 alternatives
 *   - `initEngine`    → Boolean: initialise GraphHopper et renvoie `ready`
 *
 * Format de retour pour `computeRoute` :
 * ```json
 * {
 *   "source": "graphhopper_embedded",
 *   "routes": [{
 *     "id": "gh_embedded_0",
 *     "label": "Itinéraire piéton (embarqué)",
 *     "distanceMeters": 1234.5,
 *     "points": [[lat, lon], [lat, lon], ...]
 *   }]
 * }
 * ```
 */
class OsmAndBridgePlugin(
    private val context: Context
) : MethodCallHandler {

    // ── État du moteur ────────────────────────────────────────────────────

    @Volatile private var hopper: GraphHopper? = null
    @Volatile private var engineReady = false
    // AtomicBoolean garantit une opération compareAndSet atomique
    // (check-and-set en une instruction) — évite la race condition
    // que @Volatile seul ne peut pas prévenir (TOCTOU).
    private val engineInitializing = AtomicBoolean(false)

    // SupervisorJob : une coroutine enfant qui échoue ne tue pas le scope entier.
    // Le scope est annulé dans dispose() pour libérer les threads IO et éviter
    // les fuites mémoire (SIG:9 / Out-Of-Memory) lors de la destruction de l'activité.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // ── Initialisation au démarrage (LAZY) ────────────────────────────────

    init {
        // NE PAS pré-charger le moteur ici. Le constructeur est appelé
        // pendant configureFlutterEngine(), AVANT le démarrage de la VM
        // Dart/DDS. L'init de GraphHopper (lecture OSM PBF, construction
        // du graphe) est trop lourde (30+ sec, 100+ MB) et sature le
        // CoroutineScheduler → SIG:9 → « Lost connection to device ».
        //
        // Le moteur sera initialisé à la première demande (lazy init),
        // bien après la stabilisation du DDS et du cycle de vie Flutter.
    }

    // ── Progression de l'initialisation (EventChannel) ─────────────────────

    @Volatile private var progressEventSink: EventChannel.EventSink? = null

    /// StreamHandler exposé à MainActivity pour l'EventChannel de progression.
    val progressStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            progressEventSink = events
        }

        override fun onCancel(arguments: Any?) {
            progressEventSink = null
        }
    }

    /// Émet un événement de progression vers Dart (non bloquant, silencieux).
    private fun reportProgress(stage: String, message: String, progress: Double?) {
        try {
            progressEventSink?.success(
                mapOf(
                    "stage" to stage,
                    "message" to message,
                    "progress" to progress,
                )
            )
        } catch (_: Exception) {
            // Le reporting ne doit jamais faire échouer l'initialisation.
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // MethodCallHandler
    // ════════════════════════════════════════════════════════════════════════

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {

            "isEngineReady" -> {
                result.success(engineReady)
            }

            "initEngine" -> {
                scope.launch {
                    val ready = initEngineBlocking()
                    withContext(Dispatchers.Main) { result.success(ready) }
                }
            }

            "computeRoute" -> {
                val args = call.arguments as? Map<*, *>
                if (args == null) {
                    result.error("INVALID_ARGS", "Arguments manquants", null)
                    return
                }
                val startLat = (args["startLat"] as? Number)?.toDouble()
                val startLon = (args["startLon"] as? Number)?.toDouble()
                val endLat   = (args["endLat"]   as? Number)?.toDouble()
                val endLon   = (args["endLon"]   as? Number)?.toDouble()
                // Parsing sécurisé : MethodChannel renvoie Map<Object,Object> après
                // type erasure — on ne peut pas caster directement en Map<String, Double>.
                // On extrait chaque Map<*,*> et on re-construit Map<String, Any>.
                @Suppress("UNCHECKED_CAST")
                val avoidPoints: List<Map<String, Any>> =
                    (args["avoidPoints"] as? List<*> ?: emptyList<Any>())
                        .filterIsInstance<Map<*, *>>()
                        .map { m -> m.entries.associate { (k, v) -> k.toString() to (v ?: 0.0 as Any) } }

                if (startLat == null || startLon == null || endLat == null || endLon == null) {
                    result.error("INVALID_COORDS", "Coordonnées invalides", null)
                    return
                }
                val profile = (args["profile"] as? String) ?: "pedestrian"

                scope.launch {
                    val json = computeRoute(
                        startLat, startLon, endLat, endLon,
                        avoidPoints = avoidPoints,
                        alternatives = false,
                        profile = profile
                    )
                    withContext(Dispatchers.Main) { result.success(json) }
                }
            }

            "computeRouteWithAlternatives" -> {
                val args = call.arguments as? Map<*, *>
                if (args == null) {
                    result.error("INVALID_ARGS", "Arguments manquants", null)
                    return
                }
                val startLat = (args["startLat"] as? Number)?.toDouble()
                val startLon = (args["startLon"] as? Number)?.toDouble()
                val endLat   = (args["endLat"]   as? Number)?.toDouble()
                val endLon   = (args["endLon"]   as? Number)?.toDouble()
                // Idem : parsing sécurisé sans cast générique non vérifiable.
                @Suppress("UNCHECKED_CAST")
                val avoidPoints: List<Map<String, Any>> =
                    (args["avoidPoints"] as? List<*> ?: emptyList<Any>())
                        .filterIsInstance<Map<*, *>>()
                        .map { m -> m.entries.associate { (k, v) -> k.toString() to (v ?: 0.0 as Any) } }

                if (startLat == null || startLon == null || endLat == null || endLon == null) {
                    result.error("INVALID_COORDS", "Coordonnées invalides", null)
                    return
                }
                val profile = (args["profile"] as? String) ?: "pedestrian"

                scope.launch {
                    val json = computeRoute(
                        startLat, startLon, endLat, endLon,
                        avoidPoints = avoidPoints,
                        alternatives = true,
                        profile = profile
                    )
                    withContext(Dispatchers.Main) { result.success(json) }
                }
            }

            else -> result.notImplemented()
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // Initialisation GraphHopper
    // ════════════════════════════════════════════════════════════════════════

    /**
     * Initialise GraphHopper avec le fichier OSM PBF bundlé.
     *
     * Le fichier est copié une fois depuis les assets Android vers le
     * stockage interne de l'application, puis GraphHopper construit
     * son graphe de routage dans un cache persistant.
     *
     * Lors des lancements suivants, si le cache existe, GraphHopper le
     * charge directement (< 1 seconde pour la zone de Fleurus).
     */
    private suspend fun initEngineBlocking(): Boolean {
        // Déjà prêt → aucune initialisation nécessaire.
        if (engineReady) return true

        // compareAndSet(false, true) : revendique atomiquement l'initialisation.
        // Si un autre appel l'a déjà revendiquée, on attend sa fin.
        if (!engineInitializing.compareAndSet(false, true)) {
            withContext(Dispatchers.IO) {
                while (engineInitializing.get() && !engineReady) {
                    delay(200)
                }
            }
            return engineReady
        }

        try {
            Log.i(TAG, "Initialisation du moteur GraphHopper...")
            reportProgress("extract", "Copie du fichier OSM…", 0.05)

            // ── Copier le fichier OSM depuis les assets ──────────────
            val osmFile = extractOsmAsset()
            if (osmFile == null) {
                Log.w(TAG, "Fichier OSM absent — moteur désactivé. " +
                        "Placez un fichier parmi : " +
                        OSM_ASSET_CANDIDATES.joinToString(", ") { "assets/$it" })
                reportProgress("error", "Fichier OSM manquant", null)
                engineReady = false
                return false
            }

            // ── Dossier de cache du graphe ───────────────────────────
            // v2 : force la reconstruction du graphe avec les profils
            // foot + car (l'ancien cache v1 n'avait que le profil foot,
            // ce qui faisait retomber le mode voiture sur le piéton).
            val graphDir = File(context.filesDir, "graphhopper_cache_v2")

            // ── Configurer et initialiser GraphHopper ────────────────
            val gh = GraphHopper()
            gh.setOSMFile(osmFile.absolutePath)
            gh.graphHopperLocation = graphDir.absolutePath

            // Profils piéton (foot) et véhicule (car).
            // Note GH 7.0 : utilisation directe des strings "foot"/"car"
            // (FlagEncoderFactory supprimé dans GH 6+).
            // Le profil "car" respecte le code de la route (sens uniques,
            // restrictions) et n'emprunte que les routes carrossables.
            gh.profiles = listOf(
                Profile(FOOT_PROFILE)
                    .setVehicle("foot")
                    .setWeighting("fastest")
                    .setTurnCosts(false),
                Profile(CAR_PROFILE)
                    .setVehicle("car")
                    .setWeighting("fastest")
                    .setTurnCosts(false),
            )

            // Contraction Hierarchies désactivée pour réduire la mémoire
            // et le temps d'import sur appareil mobile (extrait petit :
            // le routage de base reste rapide sans CH).

            reportProgress("import", "Construction du graphe de routage…", null)
            gh.importOrLoad()

            hopper = gh
            engineReady = true
            reportProgress("ready", "Moteur de routage prêt", 1.0)
            Log.i(TAG, "✅ GraphHopper initialisé — profils piéton + véhicule prêts")
            return true

        } catch (e: Throwable) {
            // Catch Throwable (et non Exception) : un OutOfMemoryError
            // (Error, pas Exception) pendant l'import d'un gros fichier
            // OSM ferait sinon crasher l'app. On dégrade proprement :
            // moteur désactivé → la cascade bascule sur OSRM.
            Log.e(TAG, "❌ Erreur initialisation GraphHopper: ${e.message}", e)
            reportProgress("error", "Échec de l'initialisation du moteur", null)
            engineReady = false
            return false
        } finally {
            engineInitializing.set(false)
        }
    }

    /**
     * Extrait le fichier OSM PBF des assets Android vers le stockage interne.
     *
     * Ne copie que si le fichier n'existe pas encore (optimisation).
     * Retourne null si le fichier n'est pas dans les assets.
     */
    private fun extractOsmAsset(): File? {
        for (assetName in OSM_ASSET_CANDIDATES) {
            // On préserve l'extension (.pbf vs .osm/.xml) : GraphHopper
            // détecte le format à partir de l'extension du fichier.
            // v3 : force la ré-extraction — le fichier OSM a été réordonné
            // (nodes avant ways) ET dédupliqué (IDs de nœud uniques) ;
            // les caches "fleurus.osm" et "fleurus_v2.osm" sont obsolètes.
            val destName = if (assetName.endsWith(".pbf")) "fleurus_v3.osm.pbf" else "fleurus_v3.osm"
            val destFile = File(context.filesDir, destName)

            // Cache déjà présent et non vide → réutilisé.
            if (destFile.exists() && destFile.length() > 0) {
                Log.d(TAG, "OSM cache déjà extrait: ${destFile.absolutePath}")
                return destFile
            }

            val copied = try {
                context.assets.open(assetName).use { input ->
                    FileOutputStream(destFile).use { output -> input.copyTo(output) }
                }
                true
            } catch (e: Exception) {
                Log.v(TAG, "Asset OSM absent: $assetName")
                false
            }

            if (copied && destFile.length() > 0) {
                Log.i(TAG, "OSM extrait ($assetName) → ${destFile.absolutePath}")
                return destFile
            }
            // Fichier copié mais vide → nettoyage puis tentative suivante.
            if (destFile.exists()) destFile.delete()
        }

        Log.w(TAG, "Aucun asset OSM trouvé. Placez un fichier parmi : " +
                OSM_ASSET_CANDIDATES.joinToString(", ") { "assets/$it" })
        return null
    }

    // ════════════════════════════════════════════════════════════════════════
    // Calcul de route
    // ════════════════════════════════════════════════════════════════════════

    /**
     * Calcule un itinéraire piéton via GraphHopper (moteur local).
     *
     * @param avoidPoints  Zones à pondérer : liste de {lat, lon, radius, weight}
     *                     (signalements validés et densité HIVE)
     * @param alternatives Si true, calcule jusqu'à 2 routes alternatives.
     *
     * @return JSON Map compatible avec le format attendu par OsmAndRoutingService.
     */
    private fun computeRoute(
        startLat: Double, startLon: Double,
        endLat: Double,   endLon:   Double,
        avoidPoints: List<Map<String, Any>> = emptyList(),
        alternatives: Boolean = false,
        profile: String = "pedestrian"
    ): Map<String, Any> {

        val gh = hopper
        if (!engineReady || gh == null) {
            Log.w(TAG, "Moteur non prêt — fallback HTTP")
            return mapOf(
                "source" to "engine_not_ready",
                "routes" to emptyList<Any>(),
                "error" to "Moteur embarqué non initialisé. Fichier OSM manquant ?"
            )
        }

        return try {
            // Sélection du profil GraphHopper : "car" pour véhicule/urgence
            // (respect du code de la route, routes carrossables), "foot" sinon.
            val ghProfile = when (profile) {
                "vehicle", "emergency" -> CAR_PROFILE
                else -> FOOT_PROFILE
            }
            Log.i(TAG, "Profil routage sélectionné : $ghProfile (demandé : $profile)")
            val req = GHRequest(startLat, startLon, endLat, endLon)
                .setProfile(ghProfile)
                .setLocale(java.util.Locale.FRENCH)

            // ── Algorithme d'Évitement Dynamique (Pondération des Arcs) ───
            // Requirement #2 : n'exclus pas simplement la route, alourdis le poids.
            if (avoidPoints.isNotEmpty()) {
                Log.d(TAG, "Application de ${avoidPoints.size} zones de pondération dynamique")
                
                val priorityStatements = mutableListOf<Map<String, String>>()
                val areas = mutableMapOf<String, Any>()

                for (pt in avoidPoints) {
                    val lat    = (pt["lat"]    as? Number)?.toDouble() ?: continue
                    val lon    = (pt["lon"]    as? Number)?.toDouble() ?: continue
                    val radius = (pt["radius"] as? Number)?.toDouble() ?: 5.0
                    val weight = (pt["weight"] as? Number)?.toDouble() ?: 1e6

                    val areaId = "area_${lat.toString().replace(".", "_")}_${lon.toString().replace(".", "_")}"
                    
                    priorityStatements.add(mapOf(
                        "if" to "in_$areaId",
                        "multiply_by" to (1.0 / weight).toString()
                    ))
                    
                    // Définition de l'aire circulaire (format GraphHopper CustomModel)
                    areas[areaId] = mapOf(
                        "type" to "Feature",
                        "geometry" to mapOf(
                            "type" to "Point",
                            "coordinates" to listOf(lon, lat)
                        ),
                        "properties" to mapOf("radius" to radius)
                    )
                }
                
                val customModel = mapOf(
                    "priority" to priorityStatements,
                    "areas" to areas
                )
                
                req.putHint(Parameters.CH.DISABLE, true) 
                req.putHint("custom_model", customModel)
            }

            // ── Alternatives ─────────────────────────────────────────────
            if (alternatives) {
                req.putHint(Parameters.CH.DISABLE, true)
                req.algorithm = Parameters.Algorithms.ALT_ROUTE
                req.putHint("alternative_route.max_paths", 3)
                req.putHint("alternative_route.max_weight_factor", 1.6)
                req.putHint("alternative_route.max_share_factor", 0.6)
            }

            val rsp: GHResponse = gh.route(req)

            if (rsp.hasErrors()) {
                val errMsg = rsp.errors.joinToString("; ") { it.message ?: "?" }
                Log.w(TAG, "GraphHopper error: $errMsg")
                return mapOf(
                    "source" to "graphhopper_embedded",
                    "routes" to emptyList<Any>(),
                    "error" to errMsg
                )
            }

            // ── Sérialiser les itinéraires ────────────────────────────────
            val routes = mutableListOf<Map<String, Any>>()
            for (i in 0 until rsp.all.size) {
                val path = rsp.all[i]
                val pts  = path.points
                val pointsList = mutableListOf<List<Double>>()

                for (j in 0 until pts.size()) {
                    pointsList.add(listOf(pts.getLat(j), pts.getLon(j)))
                }

                routes.add(mapOf(
                    "id"              to if (i == 0) "gh_embedded_0" else "gh_embedded_alt$i",
                    "label"           to if (i == 0) "🧭 Itinéraire piéton (GraphHopper embarqué)"
                                         else "🛤 Alternative piétonne $i",
                    "distanceMeters"  to path.distance,
                    "durationSeconds" to (path.time / 1000L),
                    "points"          to pointsList
                ))
            }

            Log.i(TAG, "✅ GraphHopper embedded → ${routes.size} route(s), " +
                    "${routes.firstOrNull()?.let { (it["points"] as List<*>).size } ?: 0} pts")

            mapOf(
                "source" to "graphhopper_embedded",
                "routes" to routes
            )

        } catch (e: Exception) {
            Log.e(TAG, "Erreur calcul GraphHopper: ${e.message}", e)
            mapOf(
                "source" to "graphhopper_embedded",
                "routes" to emptyList<Any>(),
                "error"  to (e.message ?: "Erreur inconnue")
            )
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // Nettoyage
    // ════════════════════════════════════════════════════════════════════════

    fun dispose() {
        // Annule TOUTES les coroutines en cours avant de fermer le moteur.
        // Sans cet appel, les tâches GraphHopper continuent de tourner sur
        // Dispatchers.IO même après la destruction de l'activité → fuite
        // mémoire → SIG:9 (Kill forcé par l'OS).
        scope.cancel("MainActivity destroyed")
        hopper?.close()
        hopper = null
        engineReady = false
        engineInitializing.set(false)
        Log.i(TAG, "🧹 OsmAndBridgePlugin disposed — scope cancelled")
    }
}
