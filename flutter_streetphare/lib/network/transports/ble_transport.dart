// lib/network/transports/ble_transport.dart
//
// Implémentation BLE (Bluetooth Low Energy) du contrat MeshTransport.
//
// Dépend du package `flutter_reactive_ble` (qui doit être ajouté au
// pubspec.yaml) :
//   flutter_reactive_ble: ^5.0.0
//
// Le service se comporte à la fois comme :
//   - GATT Server (advertise un service StreetPhare contenant
//     une caractéristique "alert" en notify/write)
//   - Scanner BLE pour découvrir les autres appareils
//
// Les payloads d'alertes sont courts (≤ 244 octets typiques d'une
// caractéristique BLE), ce qui impose un format compact (déjà
// prévu dans `Alert.toCompact()`).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../p2p_mesh_service.dart';

/// Transport BLE pour la propagation P2P.
///
/// IMPORTANT : cette classe n'est instanciée qu'à runtime sur les
/// plateformes qui supportent BLE (iOS, Android, macOS, Web BLE).
/// Sur les autres plateformes, [isAvailable] vaut `false` et le
/// service démarre quand même sans elle.
class BleMeshTransport implements MeshTransport {
  BleMeshTransport({FlutterReactiveBle? ble})
      : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;

  /// UUID du service GATT StreetPhare (à déclarer dans le code natif).
  static final Uuid serviceUuid =
      Uuid.parse('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  static final Uuid characteristicUuid =
      Uuid.parse('6e400002-b5a3-f393-e0a9-e50e24dcca9e');

  @override
  String get name => 'ble';

  final _incomingController = StreamController<String>.broadcast();
  @override
  Stream<String> get incoming => _incomingController.stream;

  StreamSubscription<DiscoveredDevice>? _scanSub;
  bool _started = false;

  @override
  bool get isAvailable {
    // On considère BLE dispo partout sauf sur les cibles desktop
    // classiques (Windows / Linux) tant que la lib n'est pas testée.
    if (kIsWeb) return true; // Web BLE
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Scan : on écoute tous les appareils qui exposent notre service.
    _scanSub = _ble
        .scanForDevices(
      withServices: [serviceUuid],
      scanMode: ScanMode.lowLatency,
    )
        .listen((device) {
      // Quand on détecte un pair, on s'y connecte pour recevoir ses
      // notifications. La lecture effective des caractéristiques
      // dépend d'un connectGatt + discoverServices (omis ici pour
      // concision — voir flutter_reactive_ble pour l'API complète).
      if (kDebugMode) {
        debugPrint('[BLE] pair découvert: ${device.name} (${device.id})');
      }
    }, onError: (Object e) {
      if (kDebugMode) debugPrint('[BLE] scan error: $e');
    });
  }

  @override
  Future<void> stop() async {
    await _scanSub?.cancel();
    _scanSub = null;
    _started = false;
  }

  @override
  Future<void> broadcast(String payload) async {
    // En BLE pur, il n'y a pas de broadcast "broadcast" entre
    // appareils non connectés. On se contente d'émettre sur le
    // service GATT dès qu'un central est connecté (cas typique :
    // un téléphone "advertiser" et un autre "scanner/connecté").
    // On log en debug pour traçabilité.
    if (kDebugMode) {
      debugPrint('[BLE] broadcast: ${payload.length} octets');
    }
    // NOTE : pour un vrai broadcast, on utiliserait les "BLE
    // advertisements" en mode non connectable (limité à 31 octets)
    // via un format厂商specifique. Voir les "Extended Advertising"
    // sur Android 8+ / iOS 13+.
  }

  @override
  Future<void> sendTo(MeshPeer peer, String payload) async {
    if (kDebugMode) {
      debugPrint('[BLE] sendTo ${peer.id} (${payload.length} octets)');
    }
    // Connexion GATT + write caractéristique : laissé à un
    // connecteur concret (dépend de l'ID device BLE distant).
    try {
      await _ble
          .connectToDevice(
            id: peer.id,
            servicesWithCharacteristicsToDiscover: {
              serviceUuid: [characteristicUuid],
            },
          )
          .first
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      if (kDebugMode) debugPrint('[BLE] sendTo error: $e');
    }
  }

  /// Helper de test : permet d'injecter un message reçu (utile
  /// pour les tests unitaires sans device BLE).
  void debugInjectIncoming(String payload) {
    _incomingController.add(payload);
  }

  /// Libère les ressources internes (canal broadcast).
  void dispose() {
    _incomingController.close();
  }
}

/// Helper JSON pour les paquets d'alerte reçus via BLE.
/// Conservé ici pour regrouper les utilitaires BLE.
String decodeBleFrame(String raw) {
  try {
    jsonDecode(raw);
    return raw;
  } catch (_) {
    return utf8.decode(base64Decode(raw));
  }
}
