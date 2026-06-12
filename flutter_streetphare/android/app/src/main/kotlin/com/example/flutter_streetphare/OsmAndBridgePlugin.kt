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
import com.graphhopper.config.CHProfile
import com.graphhopper.config.Profile
import com.graphhopper.util.Parameters
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
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

/// Nom du fichier OSM PBF bundlé dans les assets Android.
/// À placer dans : android/app/src/main/assets/osm/fleurus.osm.pbf
private const val OSM_ASSET_NAME = "osm/fleurus.osm.pbf"

/// Profil de routage piéton (foot).
private const val FOOT_PROFILE = "foot"

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
 *   - `initEngine`    → void   : (ré)initialise GraphHopper en background
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

    private val scope = CoroutineScope(Dispatchers.IO)

    // ── Initialisation au démarrage ───────────────────────────────────────

    init {
        // Pré-charge le moteur dès l'instanciation pour éviter la latence
        // au premier calcul de route.
        initEngineAsync()
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
                    initEngineAsync()
                    withContext(Dispatchers.Main) { result.success(engineReady) }
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

                scope.launch {
                    val json = computeRoute(
                        startLat, startLon, endLat, endLon,
                        avoidPoints = avoidPoints,
                        alternatives = false
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

                scope.launch {
                    val json = computeRoute(
                        startLat, startLon, endLat, endLon,
                        avoidPoints = avoidPoints,
                        alternatives = true
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
    private fun initEngineAsync() {
        // compareAndSet(false, true) : atomiquement vérifie que la valeur
        // est false PUIS la passe à true. Retourne false si déjà true.
        // Combiné avec le check engineReady, évite toute double-init.
        if (engineReady || !engineInitializing.compareAndSet(false, true)) return

        scope.launch {
            try {
                Log.i(TAG, "Initialisation du moteur GraphHopper...")

                // ── Copier le fichier OSM depuis les assets ──────────────
                val osmFile = extractOsmAsset()
                if (osmFile == null) {
                    Log.w(TAG, "Fichier OSM absent — moteur désactivé. " +
                            "Placez le fichier dans assets/$OSM_ASSET_NAME")
                    engineReady = false
                    engineInitializing.set(false)
                    return@launch
                }

                // ── Dossier de cache du graphe ───────────────────────────
                val graphDir = File(context.filesDir, "graphhopper_cache")

                // ── Configurer et initialiser GraphHopper ────────────────
                val gh = GraphHopper()
                gh.setOSMFile(osmFile.absolutePath)
                gh.graphHopperLocation = graphDir.absolutePath

                // Profil piéton strict (foot) — sans voiture/vélo
                // Note GH 7.0 : utilisation directe du string "foot"
                // (FlagEncoderFactory supprimé dans GH 6+)
                gh.profiles = listOf(
                    Profile(FOOT_PROFILE)
                        .setVehicle("foot")
                        .setWeighting("fastest")
                        .setTurnCosts(false)
                )

                // Contraction Hierarchies pour accélérer les calculs
                gh.chPreparationHandler.setCHProfiles(
                    CHProfile(FOOT_PROFILE)
                )

                gh.importOrLoad()

                hopper = gh
                engineReady = true
                Log.i(TAG, "✅ GraphHopper initialisé — profil piéton prêt")

            } catch (e: Exception) {
                Log.e(TAG, "❌ Erreur initialisation GraphHopper: ${e.message}", e)
                engineReady = false
            } finally {
                engineInitializing.set(false)
            }
        }
    }

    /**
     * Extrait le fichier OSM PBF des assets Android vers le stockage interne.
     *
     * Ne copie que si le fichier n'existe pas encore (optimisation).
     * Retourne null si le fichier n'est pas dans les assets.
     */
    private fun extractOsmAsset(): File? {
        val destFile = File(context.filesDir, "fleurus.osm.pbf")
        if (destFile.exists() && destFile.length() > 0) {
            Log.d(TAG, "OSM cache déjà extrait: ${destFile.absolutePath}")
            return destFile
        }

        return try {
            context.assets.open(OSM_ASSET_NAME).use { input ->
                FileOutputStream(destFile).use { output ->
                    input.copyTo(output)
                }
            }
            Log.i(TAG, "OSM extrait vers: ${destFile.absolutePath}")
            destFile
        } catch (e: Exception) {
            Log.w(TAG, "Asset OSM introuvable: $OSM_ASSET_NAME — ${e.message}")
            null
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // Calcul de route
    // ════════════════════════════════════════════════════════════════════════

    /**
     * Calcule un itinéraire piéton via GraphHopper.
     *
     * @param avoidPoints  Zones à éviter : liste de {lat, lon, radiusM}
     *                     (signalements validés ≥3 votes, <30m)
     * @param alternatives Si true, calcule jusqu'à 2 routes alternatives.
     *
     * @return JSON Map compatible avec le format attendu par OsmAndRoutingService.
     */
    private fun computeRoute(
        startLat: Double, startLon: Double,
        endLat: Double,   endLon:   Double,
        avoidPoints: List<Map<String, Any>> = emptyList(),
        alternatives: Boolean = false
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
            val req = GHRequest(startLat, startLon, endLat, endLon)
                .setProfile(FOOT_PROFILE)
                .setLocale(java.util.Locale.FRENCH)

            // ── Zones interdites (dangers validés P2P) ───────────────────
            // GraphHopper block_area : "lat,lon,radiusM|lat2,lon2,radiusM2|..."
            // Accès sécurisé via (as? Number)?.toDouble() pour tolérer
            // Integer ou Double indifféremment (type erasure JVM).
            if (avoidPoints.isNotEmpty()) {
                val blockArea = avoidPoints.joinToString("|") { pt ->
                    val lat    = (pt["lat"]    as? Number)?.toDouble() ?: return@joinToString ""
                    val lon    = (pt["lon"]    as? Number)?.toDouble() ?: return@joinToString ""
                    val radius = (pt["radius"] as? Number)?.toDouble() ?: 30.0
                    "${lat},${lon},${radius.toInt()}"
                }.trim('|')

                if (blockArea.isNotEmpty()) {
                    // "block_area" est le nom de hint GraphHopper 7.0
                    // (Parameters.Routing.BLOCK_AREA n'est pas exporté en 7.0)
                    req.putHint("block_area", blockArea)
                    Log.d(TAG, "Zones bloquées: $blockArea")
                }
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
        hopper?.close()
        hopper = null
        engineReady = false
    }
}
