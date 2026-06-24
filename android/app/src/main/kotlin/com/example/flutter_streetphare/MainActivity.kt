// MainActivity.kt — StreetPhare v1.4  (2026-06-17)
//
// Enregistre les canaux Flutter :
//   - "com.streetphare/routing"   : moteur de routage piéton GraphHopper embarqué.
//   - "streetphare/apk_info"      : expose le chemin source de l'APK installé
//                                   pour la sauvegarde locale et la distribution P2P.
package com.example.flutter_streetphare

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var bridge: OsmAndBridgePlugin? = null

    companion object {
        /// Canal exposant les informations de l'APK installé.
        private const val APK_INFO_CHANNEL = "streetphare/apk_info"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Configuration native des canaux de notification ──────────────────
        NotificationChannelSetup.createAllChannels(applicationContext)

        // ── Canal GraphHopper / OsmAnd routing ──────────────────────────────
        val plugin = OsmAndBridgePlugin(applicationContext)
        bridge = plugin

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        ).setMethodCallHandler(plugin)

        // ── Canal APK Info ───────────────────────────────────────────────────
        // Expose `ApplicationInfo.sourceDir` : chemin absolu de l'APK installé
        // (ex. /data/app/com.example.flutter_streetphare-<hash>/base.apk).
        // Utilisé par ApkBackupService (Dart) pour copier l'APK vers le
        // stockage Documents persistant lors du premier lancement.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APK_INFO_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSourceApkPath" -> {
                    try {
                        // Compatibilité API 33+ (Android 13) : getApplicationInfo(String, int)
                        // est déprécié → utiliser getApplicationInfo(String, ApplicationInfoFlags).
                        val appInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            applicationContext.packageManager.getApplicationInfo(
                                applicationContext.packageName,
                                PackageManager.ApplicationInfoFlags.of(0L)
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            applicationContext.packageManager.getApplicationInfo(
                                applicationContext.packageName, 0
                            )
                        }
                        result.success(appInfo.sourceDir)
                    } catch (e: Exception) {
                        result.error(
                            "APK_INFO_ERROR",
                            "Impossible de récupérer le chemin de l'APK : ${e.message}",
                            null
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        bridge?.dispose()
        bridge = null
        try {
            super.onDestroy()
        } catch (e: Exception) {
            // Le ProfileInstaller peut tenter d'écrire des profils de
            // performance au moment exact où l'activité est détruite,
            // provoquant une exception "BLASTBufferQueue" ou similaire.
            // On capture silencieusement l'exception pour éviter le crash.
            android.util.Log.w("StreetPhare", "onDestroy exception (non critique)", e)
        }
    }
}
