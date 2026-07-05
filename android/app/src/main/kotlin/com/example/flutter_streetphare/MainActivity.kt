// MainActivity.kt — StreetPhare v2.3  (2026-07-03)
//
// Enregistre les canaux Flutter :
//   - "com.streetphare/routing"            : moteur de routage piéton GraphHopper embarqué.
//   - "streetphare/apk_info"               : expose le chemin source de l'APK installé.
//   - "streetphare/ble_advertiser"         : publicité BLE (peripheral GATT).
//   - "streetphare/ble_gatt_server"        : serveur GATT natif pour échange P2P.
//   - "streetphare/map_tiles"              : DownloadManager tuiles cartographiques.
//   - "streetphare/map_tiles_status"       : EventChannel statut des téléchargements.
package com.example.flutter_streetphare

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class MainActivity : FlutterActivity() {

    private var bridge: OsmAndBridgePlugin? = null
    private var bleAdvertiser: BluetoothLeAdvertiser? = null
    private var bleGattServer: BluetoothGattServer? = null

    /// Plugin de téléchargement de tuiles via DownloadManager.
    private val mapTilesPlugin by lazy { MapTileDownloadPlugin(applicationContext) }

    /// Event channel for incoming BLE data from remote peers.
    private var incomingEventSink: EventChannel.EventSink? = null

    /// Handler to dispatch EventChannel calls onto the main thread.
    private val mainHandler = Handler(Looper.getMainLooper())

    /// Connected remote devices (MAC → device) tracked by the GATT server.
    private val connectedRemotes = ConcurrentHashMap<String, BluetoothDevice>()

    /// Pending send operations awaiting a connection.
    private data class PendingSend(val deviceId: String, val data: ByteArray)
    private val pendingSends = mutableListOf<PendingSend>()

    companion object {
        private const val APK_INFO_CHANNEL = "streetphare/apk_info"
        private const val BLE_ADVERTISER_CHANNEL = "streetphare/ble_advertiser"
        private const val BLE_GATT_CHANNEL = "streetphare/ble_gatt"
        private const val BLE_GATT_EVENT = "streetphare/ble_gatt_events"
        private const val MAP_TILES_CHANNEL = "streetphare/map_tiles"
        private const val MAP_TILES_EVENT = "streetphare/map_tiles_status"

        private val STREETPHARE_SERVICE_UUID: UUID =
            UUID.fromString("6e400001-b5a3-f393-e0a9-e50e24dcca9e")
        private val STREETPHARE_CHAR_UUID: UUID =
            UUID.fromString("6e400002-b5a3-f393-e0a9-e50e24dcca9e")
        private val CLIENT_CONFIG_UUID: UUID =
            UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        private const val TAG = "StreetPhareBLE"
    }

    // ═══════════════════════════════════════════════════════════════════════
    // FlutterEngine setup
    // ═══════════════════════════════════════════════════════════════════════

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        NotificationChannelSetup.createAllChannels(applicationContext)

        // ── Canal GraphHopper / OsmAnd routing ────────────────────────
        val plugin = OsmAndBridgePlugin(applicationContext)
        bridge = plugin
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        ).setMethodCallHandler(plugin)

        // ── Canal BLE Advertising ────────────────────────────────────
        setupBleAdvertiserChannel(flutterEngine)

        // ── Canal GATT Server (échange de données P2P) ───────────────
        setupBleGattServerChannel(flutterEngine)

        // ── Canal Map Tiles DownloadManager ──────────────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MAP_TILES_CHANNEL
        ).setMethodCallHandler(mapTilesPlugin)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MAP_TILES_EVENT
        ).setStreamHandler(mapTilesPlugin.streamHandler)

        mapTilesPlugin.registerReceiver()

        // ── Canal APK Info ───────────────────────────────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APK_INFO_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSourceApkPath" -> {
                    try {
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

    // ═══════════════════════════════════════════════════════════════════════
    // BLE Advertising
    // ═══════════════════════════════════════════════════════════════════════

    private fun setupBleAdvertiserChannel(flutterEngine: FlutterEngine) {
        val bluetoothManager =
            applicationContext.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val bluetoothAdapter = bluetoothManager?.adapter

        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled) {
            Log.w(TAG, "Bluetooth non disponible — advertising BLE désactivé")
        } else {
            bleAdvertiser = bluetoothAdapter.bluetoothLeAdvertiser
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BLE_ADVERTISER_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAdvertising" -> {
                    val peerId = call.argument<String>("peerId") ?: "unknown"
                    startBleAdvertising(peerId, result)
                }
                "stopAdvertising" -> {
                    stopBleAdvertising(result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startBleAdvertising(peerId: String, result: MethodChannel.Result) {
        if (bleAdvertiser == null) {
            Log.w(TAG, "BluetoothLeAdvertiser null")
            result.success(false)
            return
        }

        try {
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .setConnectable(true)
                .setTimeout(0)
                .build()

            val serviceUuid = ParcelUuid(STREETPHARE_SERVICE_UUID)
            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .addServiceUuid(serviceUuid)
                .build()

            bleAdvertiser!!.startAdvertising(settings, data, null, object : AdvertiseCallback() {
                override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                    Log.i(TAG, "BLE advertising démarré — peerId=$peerId")
                    result.success(true)
                }

                override fun onStartFailure(errorCode: Int) {
                    val err = when (errorCode) {
                        ADVERTISE_FAILED_DATA_TOO_LARGE -> "DATA_TOO_LARGE"
                        ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "TOO_MANY_ADVERTISERS"
                        ADVERTISE_FAILED_ALREADY_STARTED -> "ALREADY_STARTED"
                        ADVERTISE_FAILED_INTERNAL_ERROR -> "INTERNAL_ERROR"
                        ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "FEATURE_UNSUPPORTED"
                        else -> "UNKNOWN($errorCode)"
                    }
                    Log.e(TAG, "BLE advertising échec: $err")
                    result.success(false)
                }
            })
        } catch (e: SecurityException) {
            Log.e(TAG, "Permission BLE manquante: ${e.message}")
            result.success(false)
        } catch (e: Exception) {
            Log.e(TAG, "Erreur advertising: ${e.message}")
            result.success(false)
        }
    }

    private fun stopBleAdvertising(result: MethodChannel.Result) {
        try {
            bleAdvertiser?.stopAdvertising(null)
            Log.i(TAG, "BLE advertising arrêté")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Erreur stop advertising: ${e.message}")
            result.success(false)
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GATT Server (réception P2P)
    // ═══════════════════════════════════════════════════════════════════════

    private fun setupBleGattServerChannel(flutterEngine: FlutterEngine) {
        // ⚠️ NE PAS ouvrir le GATT server ici — openGattServer() appelle
        //     GattService.registerServer() qui déclenche SecurityException
        //     sur certains firmwares (Xiaomi/Poco 2201116SG) si la permission
        //     BLUETOOTH_CONNECT est révoquée après l'affichage de la popup.
        //     L'ouverture se fait dans startGattServer() avec try-catch.
        //     Voir : issue #42 — crash au démarrage sur 2201116SG
        bleGattServer = null

        // ── Method channel (Dart → natif) ────────────────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BLE_GATT_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startGattServer" -> {
                    startGattServer(result)
                }
                "stopGattServer" -> {
                    stopGattServer(result)
                }
                "sendTo" -> {
                    val deviceId = call.argument<String>("deviceId") ?: ""
                    val data = call.argument<ByteArray>("data")
                    if (data != null) sendBleMessage(deviceId, data)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // ── Event channel (natif → Dart) pour les données entrantes ──
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BLE_GATT_EVENT
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                incomingEventSink = events
                Log.i(TAG, "Event channel Dart connecté")
            }
            override fun onCancel(arguments: Any?) {
                incomingEventSink = null
                Log.i(TAG, "Event channel Dart déconnecté")
            }
        })
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    Log.i(TAG, "GATT server: device connecté ${device.address}")
                    connectedRemotes[device.address] = device
                    // Flush pending sends for this device
                    val iterator = pendingSends.iterator()
                    while (iterator.hasNext()) {
                        val pending = iterator.next()
                        if (pending.deviceId == device.address) {
                            sendBleMessage(pending.deviceId, pending.data)
                            iterator.remove()
                        }
                    }
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    Log.i(TAG, "GATT server: device déconnecté ${device.address}")
                    connectedRemotes.remove(device.address)
                }
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            if (characteristic.uuid == STREETPHARE_CHAR_UUID) {
                val raw = value.toString(Charsets.UTF_8)
                Log.d(TAG, "GATT write reçu de ${device.address}: $raw")

                // ⚠️ Ce callback est exécuté sur un thread Binder, PAS le
                //    thread UI. EventSink.success() DOIT être appelé sur le
                //    thread principal → on post sur le Handler main.
                mainHandler.post {
                    incomingEventSink?.success(mapOf(
                        "deviceId" to device.address,
                        "data" to raw
                    ))
                }

                if (responseNeeded) {
                    bleGattServer?.sendResponse(
                        device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null
                    )
                }
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            // Client a souscrit aux notifications → répond OK
            if (descriptor.uuid == CLIENT_CONFIG_UUID) {
                Log.i(TAG, "GATT: device ${device.address} a souscrit aux notifications")
                if (responseNeeded) {
                    bleGattServer?.sendResponse(
                        device, requestId, BluetoothGatt.GATT_SUCCESS, 0, value
                    )
                }
            }
        }
    }

    private fun startGattServer(result: MethodChannel.Result) {
        // ⚠️ Ouverture lazy du GATT server avec try-catch explicite
        //     pour éviter SecurityException sur les firmwares restrictifs.
        if (bleGattServer == null) {
            try {
                val bluetoothManager =
                    applicationContext.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                val bluetoothAdapter = bluetoothManager?.adapter

                if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled) {
                    Log.w(TAG, "GATT server: Bluetooth non disponible")
                    result.success(false)
                    return
                }

                bleGattServer = bluetoothManager.openGattServer(applicationContext, gattServerCallback)
                Log.i(TAG, "GATT server ouvert avec succès")
            } catch (e: SecurityException) {
                Log.e(TAG, "Permission BLUETOOTH_CONNECT refusée — GATT server désactivé : ${e.message}")
                result.success(false)
                return
            } catch (e: Exception) {
                Log.e(TAG, "Erreur ouverture GATT server : ${e.message}")
                result.success(false)
                return
            }
        }

        try {
            // ── Crée le service GATT StreetPhare ──────────────────────
            val service = BluetoothGattService(
                STREETPHARE_SERVICE_UUID,
                BluetoothGattService.SERVICE_TYPE_PRIMARY
            )

            val characteristic = BluetoothGattCharacteristic(
                STREETPHARE_CHAR_UUID,
                BluetoothGattCharacteristic.PROPERTY_WRITE or
                    BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE or
                    BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                BluetoothGattCharacteristic.PERMISSION_WRITE
            )

            // Ajoute le descriptor CCCD pour les notifications
            val cccd = BluetoothGattDescriptor(
                CLIENT_CONFIG_UUID,
                BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
            )
            characteristic.addDescriptor(cccd)

            service.addCharacteristic(characteristic)

            // Supprime l'ancien service s'il existe
            val existingService = bleGattServer?.getService(STREETPHARE_SERVICE_UUID)
            if (existingService != null) {
                bleGattServer?.removeService(existingService)
            }

            bleGattServer?.addService(service)
            Log.i(TAG, "GATT server démarré avec caractéristique ${STREETPHARE_CHAR_UUID}")
            result.success(true)
        } catch (e: SecurityException) {
            Log.e(TAG, "Permission GATT server manquante: ${e.message}")
            result.success(false)
        } catch (e: Exception) {
            Log.e(TAG, "Erreur GATT server: ${e.message}")
            result.success(false)
        }
    }

    private fun stopGattServer(result: MethodChannel.Result) {
        try {
            val service = bleGattServer?.getService(STREETPHARE_SERVICE_UUID)
            if (service != null) {
                bleGattServer?.removeService(service)
            }
            connectedRemotes.clear()
            Log.i(TAG, "GATT server arrêté")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Erreur stop GATT server: ${e.message}")
            result.success(false)
        }
    }

    /// Envoie des données vers un device connecté via notification GATT.
    private fun sendBleMessage(deviceId: String, data: ByteArray) {
        val device = connectedRemotes[deviceId]
        if (device == null) {
            Log.w(TAG, "sendBleMessage: device $deviceId non connecté — mise en file d'attente")
            pendingSends.add(PendingSend(deviceId, data))
            return
        }

        val service = bleGattServer?.getService(STREETPHARE_SERVICE_UUID) ?: return
        val characteristic = service.getCharacteristic(STREETPHARE_CHAR_UUID) ?: return

        characteristic.value = data
        try {
            val success = bleGattServer?.notifyCharacteristicChanged(device, characteristic, false)
            if (success == true) {
                Log.d(TAG, "Notification GATT envoyée à $deviceId (${data.size} octets)")
            } else {
                Log.w(TAG, "Échec notification GATT vers $deviceId")
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "Erreur sécurité notification: ${e.message}")
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Lifecycle
    // ═══════════════════════════════════════════════════════════════════════

    override fun onDestroy() {
        bridge?.dispose()
        bridge = null

        mapTilesPlugin.dispose()

        try { bleAdvertiser?.stopAdvertising(null) } catch (_: Exception) {}
        bleAdvertiser = null

        try {
            val service = bleGattServer?.getService(STREETPHARE_SERVICE_UUID)
            if (service != null) bleGattServer?.removeService(service)
            bleGattServer?.close()
        } catch (_: Exception) {}
        bleGattServer = null

        incomingEventSink = null

        try {
            super.onDestroy()
        } catch (e: Exception) {
            android.util.Log.w("StreetPhare", "onDestroy exception (non critique)", e)
        }
    }
}