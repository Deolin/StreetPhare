// MainActivity.kt — StreetPhare v1.3  (2026-06-11)
//
// Enregistre le canal Flutter "com.streetphare/routing" pour
// le moteur de routage piéton GraphHopper embarqué.
package com.example.flutter_streetphare

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var bridge: OsmAndBridgePlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Crée le bridge GraphHopper et enregistre le canal MethodChannel
        val plugin = OsmAndBridgePlugin(applicationContext)
        bridge = plugin

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        ).setMethodCallHandler(plugin)
    }

    override fun onDestroy() {
        bridge?.dispose()
        bridge = null
        super.onDestroy()
    }
}
