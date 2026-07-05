// ============================================================================
// MapTileDownloadPlugin.kt — StreetPhare v2.3  (2026-07-03)
// ============================================================================
//
// Plugin natif de téléchargement de tuiles cartographiques via
// l'API DownloadManager d'Android.
//
// Stratégie de fallback :
//   1. Télécharge depuis l'URL du serveur privé StreetPhare.
//   2. Si le download échoue (erreur HTTP, timeout, réseau), retente
//      automatiquement via l'URL publique OpenStreetMap.
//
// Le statut final est renvoyé au Dart via un EventChannel.
// Le DownloadManager garantit reprise sur perte réseau, notification
// système, et gestion optimisée de la batterie.
//
// Sécurité TLS : DownloadManager utilise le trust store système
// Android (Certificats racine CA globaux + certificats utilisateur).
// Aucune validation manuelle nécessaire.
//
// ============================================================================
package com.example.flutter_streetphare

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.Cursor
import android.net.Uri
import android.os.Environment
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.ConcurrentHashMap

/**
 * Plugin Flutter exposant le DownloadManager Android pour le
 * téléchargement résilient de tuiles cartographiques.
 *
 * Canaux :
 *   - MethodChannel "streetphare/map_tiles"        (Dart → natif)
 *   - EventChannel  "streetphare/map_tiles_status"  (natif → Dart)
 */
class MapTileDownloadPlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "StreetPhare.MapTiles"

        const val METHOD_CHANNEL = "streetphare/map_tiles"
        const val EVENT_CHANNEL  = "streetphare/map_tiles_status"

        /// Sous-dossier dans le cache externe pour les tuiles.
        const val TILES_SUBDIR = "map_tiles_cache"

        /// Base URL du serveur privé StreetPhare pour les tuiles.
        const val PRIVATE_TILE_BASE = "https://streetphare.ddns.net/tiles"

        /// Base URL publique OpenStreetMap (fallback).
        const val OSM_TILE_BASE = "https://tile.openstreetmap.org"
    }

    // ── Gestion des téléchargements en cours ────────────────────────────────

    private data class DownloadContext(
        val privateUrl: String,
        val fallbackUrl: String,
        val destPath: String,
        val attempt: Int = 0 // 0 = privée, 1 = fallback OSM
    )

    private val pendingDownloads = ConcurrentHashMap<Long, DownloadContext>()

    private var eventSink: EventChannel.EventSink? = null
    private var receiverRegistered = false

    private val downloadManager: DownloadManager by lazy {
        context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    }

    // ── BroadcastReceiver ─────────────────────────────────────────────────────

    private val downloadReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val action = intent.action ?: return
            if (action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return

            val downloadId = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1)
            if (downloadId == -1L) return

            val ctx = pendingDownloads.remove(downloadId) ?: run {
                Log.w(TAG, "Download $downloadId inconnu")
                return
            }

            val query = DownloadManager.Query().setFilterById(downloadId)
            val cursor: Cursor = try {
                downloadManager.query(query)
            } catch (e: Exception) {
                Log.e(TAG, "Query échouée: ${e.message}")
                sendStatus(ctx.destPath, "error", "Cursor query failed", null)
                return
            }

            if (!cursor.moveToFirst()) {
                cursor.close()
                sendStatus(ctx.destPath, "error", "Download vanished", null)
                return
            }

            val statusIdx = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS)
            val reasonIdx = cursor.getColumnIndex(DownloadManager.COLUMN_REASON)
            val uriIdx    = cursor.getColumnIndex(DownloadManager.COLUMN_LOCAL_URI)

            val status = if (statusIdx >= 0) cursor.getInt(statusIdx) else DownloadManager.STATUS_FAILED
            val reason = if (reasonIdx >= 0) cursor.getInt(reasonIdx) else 0
            val localUri = if (uriIdx >= 0) cursor.getString(uriIdx) else null
            cursor.close()

            // Supprime le record du DownloadManager (ne garde pas l'historique).
            downloadManager.remove(downloadId)

            when (status) {
                DownloadManager.STATUS_SUCCESSFUL -> {
                    Log.i(TAG, "✅ Download OK → ${ctx.destPath}")
                    val copied = copyFromDownloadUri(localUri, ctx.destPath)
                    if (copied) {
                        sendStatus(ctx.destPath, "completed", null, ctx.attempt)
                    } else {
                        sendStatus(ctx.destPath, "error", "Copy failed", null)
                    }
                }

                DownloadManager.STATUS_FAILED -> {
                    val reasonStr = reasonToString(reason)
                    Log.w(TAG, "❌ Échec (essai #${ctx.attempt + 1}) reason=$reasonStr")

                    if (ctx.attempt == 0 && ctx.fallbackUrl.isNotBlank()) {
                        Log.i(TAG, "↪ Fallback OSM: ${ctx.fallbackUrl}")
                        val fbId = enqueueDownload(ctx.fallbackUrl, ctx.destPath)
                        if (fbId != -1L) {
                            pendingDownloads[fbId] = ctx.copy(attempt = 1)
                            return
                        }
                    }
                    sendStatus(ctx.destPath, "failed", reasonStr, null)
                }

                DownloadManager.STATUS_PAUSED,
                DownloadManager.STATUS_PENDING,
                DownloadManager.STATUS_RUNNING -> {
                    pendingDownloads[downloadId] = ctx
                    sendStatus(ctx.destPath, "downloading", null, null)
                }
            }
        }
    }

    // ── Enregistrement / Nettoyage ───────────────────────────────────────────

    fun registerReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(downloadReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            context.registerReceiver(downloadReceiver, filter)
        }
        receiverRegistered = true
        Log.i(TAG, "Receiver enregistré")
    }

    fun dispose() {
        if (receiverRegistered) {
            try { context.unregisterReceiver(downloadReceiver) }
            catch (_: IllegalArgumentException) {}
            receiverRegistered = false
        }
        pendingDownloads.clear()
        eventSink = null
        Log.i(TAG, "🧹 Plugin disposed")
    }

    // ── EventChannel StreamHandler ───────────────────────────────────────────

    val streamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
            Log.i(TAG, "EventChannel connecté")
        }
        override fun onCancel(arguments: Any?) {
            eventSink = null
            Log.i(TAG, "EventChannel déconnecté")
        }
    }

    // ── MethodChannel Handler ────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "downloadTile" -> {
                val z = call.argument<Int>("z") ?: run { result.error("ARGS", "z missing", null); return }
                val x = call.argument<Int>("x") ?: run { result.error("ARGS", "x missing", null); return }
                val y = call.argument<Int>("y") ?: run { result.error("ARGS", "y missing", null); return }
                val ext = call.argument<String>("ext") ?: "png"

                val tilePath = "$z/$x/$y.$ext"
                val privateUrl = "$PRIVATE_TILE_BASE/$tilePath"
                val fallbackUrl = "$OSM_TILE_BASE/$tilePath"

                val cacheDir = File(context.externalCacheDir ?: context.cacheDir, TILES_SUBDIR)
                val destDir = File(cacheDir, "$z/$x")
                destDir.mkdirs()
                val destFile = File(destDir, "$y.$ext")

                val downloadId = enqueueDownload(privateUrl, destFile.absolutePath)
                if (downloadId != -1L) {
                    pendingDownloads[downloadId] = DownloadContext(
                        privateUrl = privateUrl,
                        fallbackUrl = fallbackUrl,
                        destPath = destFile.absolutePath
                    )
                }
                result.success(downloadId)
            }

            "cancelTile" -> {
                val downloadId = call.argument<Long>("downloadId") ?: run { result.error("ARGS", "downloadId missing", null); return }
                pendingDownloads.remove(downloadId)
                downloadManager.remove(downloadId)
                result.success(true)
            }

            "getTilePath" -> {
                val z = call.argument<Int>("z") ?: run { result.error("ARGS", "z missing", null); return }
                val x = call.argument<Int>("x") ?: run { result.error("ARGS", "x missing", null); return }
                val y = call.argument<Int>("y") ?: run { result.error("ARGS", "y missing", null); return }
                val ext = call.argument<String>("ext") ?: "png"

                val cacheDir = File(context.externalCacheDir ?: context.cacheDir, TILES_SUBDIR)
                val tile = File(File(cacheDir, "$z/$x"), "$y.$ext")
                if (tile.exists() && tile.length() > 0) {
                    result.success(tile.absolutePath)
                } else {
                    result.success(null)
                }
            }

            else -> result.notImplemented()
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private fun enqueueDownload(url: String, destPath: String): Long {
        return try {
            val request = DownloadManager.Request(Uri.parse(url)).apply {
                setTitle("Tuile cartographique")
                setDescription("Téléchargement tuile StreetPhare")
                setNotificationVisibility(DownloadManager.Request.VISIBILITY_HIDDEN)
                setDestinationUri(Uri.fromFile(File(destPath)))
                setAllowedOverMetered(true)
                setAllowedOverRoaming(true)
                // Pas de réseau mobile restreint (le cache peut faire
                // plusieurs Mo — on laisse le DownloadManager gérer).
            }
            downloadManager.enqueue(request)
        } catch (e: Exception) {
            Log.e(TAG, "Échec enqueue download: ${e.message}", e)
            -1L
        }
    }

    /**
     * Copie le fichier depuis l'URI content:// retournée par le
     * DownloadManager vers le chemin de destination absolu.
     *
     * DownloadManager peut retourner une URI de type file:// ou
     * content://. Les deux sont gérées.
     */
    private fun copyFromDownloadUri(uriString: String?, destPath: String): Boolean {
        if (uriString.isNullOrBlank()) return false
        return try {
            val uri = Uri.parse(uriString)
            val destFile = File(destPath)

            // Si l'URI est déjà un chemin fichier, déplacement direct.
            if (uri.scheme == "file") {
                val src = File(uri.path ?: return false)
                if (src.absolutePath == destFile.absolutePath) return true
                src.copyTo(destFile, overwrite = true)
                // Supprime le fichier source (DownloadManager le nettoiera
                // dans tous les cas, mais on évite les doublons).
                src.delete()
                return true
            }

            // Sinon, content:// → on lit le flux.
            context.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(destFile).use { output ->
                    input.copyTo(output)
                }
            } ?: return false
            true
        } catch (e: Exception) {
            Log.e(TAG, "Échec copie fichier: ${e.message}", e)
            false
        }
    }

    private fun sendStatus(
        path: String,
        status: String,
        error: String?,
        attempt: Int?
    ) {
        val data = mutableMapOf<String, Any?>(
            "path" to path,
            "status" to status
        )
        if (error != null) data["error"] = error
        if (attempt != null) data["attempt"] = attempt
        eventSink?.success(data)
    }

    private fun reasonToString(reason: Int): String = when (reason) {
        DownloadManager.ERROR_CANNOT_RESUME           -> "CANNOT_RESUME"
        DownloadManager.ERROR_DEVICE_NOT_FOUND        -> "DEVICE_NOT_FOUND"
        DownloadManager.ERROR_FILE_ALREADY_EXISTS     -> "FILE_EXISTS"
        DownloadManager.ERROR_FILE_ERROR              -> "FILE_ERROR"
        DownloadManager.ERROR_HTTP_DATA_ERROR         -> "HTTP_DATA_ERROR"
        DownloadManager.ERROR_INSUFFICIENT_SPACE      -> "INSUFFICIENT_SPACE"
        DownloadManager.ERROR_TOO_MANY_REDIRECTS      -> "TOO_MANY_REDIRECTS"
        DownloadManager.ERROR_UNHANDLED_HTTP_CODE     -> "HTTP_${reason}"
        DownloadManager.ERROR_UNKNOWN                 -> "UNKNOWN"
        else                                          -> "CODE_$reason"
    }
}