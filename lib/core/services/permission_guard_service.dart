// lib/core/services/permission_guard_service.dart
//
// Service de garde des permissions indispensables au démarrage.
//
// Responsabilités :
//   1. Vérifier strictement les permissions critiques pour le maillage P2P
//      (BLE, Wi-Fi Direct, Localisation) avant d'autoriser l'accès à la carte.
//   2. Bloquer le flux de démarrage si une permission indispensable manque.
//   3. Fournir une méthode de demande groupée avec fallback openAppSettings()
//      pour les permissions marquées permanentlyDenied.
//
// Permissions vérifiées :
//   - Permission.locationWhenInUse  (scan BLE + Geofencing)
//   - Permission.bluetoothScan       (maillage P2P BLE)
//   - Permission.bluetoothConnect    (connexion aux pairs BLE)
//   - Permission.nearbyWifiDevices   (Wi-Fi Direct P2P, Android 13+)

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Résultat de la vérification groupée des permissions.
class PermissionGuardResult {
  const PermissionGuardResult({
    required this.allGranted,
    required this.missingPermissions,
    required this.permanentlyDeniedPermissions,
  });

  /// `true` si toutes les permissions indispensables sont accordées.
  final bool allGranted;

  /// Liste des permissions actuellement refusées (denied).
  final List<Permission> missingPermissions;

  /// Liste des permissions définitivement refusées (permanentlyDenied).
  final List<Permission> permanentlyDeniedPermissions;

  /// Libellé localisé pour une permission.
  static String labelFor(Permission p) {
    switch (p) {
      case Permission.locationWhenInUse:
        return 'Localisation';
      case Permission.bluetoothScan:
        return 'Scan Bluetooth';
      case Permission.bluetoothConnect:
        return 'Connexion Bluetooth';
      case Permission.nearbyWifiDevices:
        return 'Appareils Wi-Fi à proximité';
      default:
        return p.toString();
    }
  }

  /// Description de l'impact pour l'utilisateur.
  static String impactFor(Permission p) {
    switch (p) {
      case Permission.locationWhenInUse:
        return 'Requis pour le scan BLE et la détection de votre position.';
      case Permission.bluetoothScan:
        return 'Requis pour détecter les appareils StreetPhare à proximité via le maillage P2P.';
      case Permission.bluetoothConnect:
        return 'Requis pour échanger des alertes avec les pairs BLE.';
      case Permission.nearbyWifiDevices:
        return 'Requis pour le réseau Wi-Fi Direct P2P entre appareils proches.';
      default:
        return 'Permission indispensable au fonctionnement du réseau décentralisé.';
    }
  }
}

/// Service singleton de garde des permissions au démarrage.
///
/// Utilisation typique dans le flux de démarrage :
/// ```dart
/// final guardResult = await PermissionGuardService.instance.checkAll();
/// if (!guardResult.allGranted) {
///   // Rediriger vers PermissionGuardScreen
/// }
/// ```
class PermissionGuardService {
  PermissionGuardService._();
  static final PermissionGuardService instance = PermissionGuardService._();

  /// Liste des permissions indispensables au maillage P2P.
  /// L'ordre est important : on vérifie d'abord les permissions
  /// les plus susceptibles d'être déjà accordées.
  static const List<Permission> indispensablePermissions = [
    Permission.locationWhenInUse,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.nearbyWifiDevices,
  ];

  /// Vérifie l'état de toutes les permissions indispensables.
  ///
  /// Retourne un [PermissionGuardResult] avec le statut détaillé
  /// de chaque permission. N'effectue aucune demande — uniquement
  /// une vérification passive.
  Future<PermissionGuardResult> checkAll() async {
    final missing = <Permission>[];
    final permanentlyDenied = <Permission>[];

    for (final permission in indispensablePermissions) {
      try {
        final status = await permission.status;
        if (status.isGranted || status.isLimited) {
          continue;
        }
        if (status.isPermanentlyDenied) {
          permanentlyDenied.add(permission);
        } else {
          missing.add(permission);
        }
      } catch (e) {
        // Si la permission n'est pas supportée par la plateforme,
        // on la considère comme manquante (sécurité par défaut).
        if (kDebugMode) {
          debugPrint('[PermissionGuard] $permission non supporté: $e');
        }
        missing.add(permission);
      }
    }

    final allMissing = [...missing, ...permanentlyDenied];

    return PermissionGuardResult(
      allGranted: allMissing.isEmpty,
      missingPermissions: missing,
      permanentlyDeniedPermissions: permanentlyDenied,
    );
  }

  /// Demande toutes les permissions manquantes une par une.
  ///
  /// Pour les permissions [permanentlyDenied], ne tente pas de
  /// `request()` (qui échouerait silencieusement) mais les ajoute
  /// directement à la liste des refus définitifs.
  ///
  /// Retourne un [PermissionGuardResult] mis à jour après les demandes.
  Future<PermissionGuardResult> requestMissing() async {
    final stillMissing = <Permission>[];
    final stillPermanentlyDenied = <Permission>[];

    // On recalcule l'état actuel pour être à jour.
    final initial = await checkAll();
    if (initial.allGranted) return initial;

    // Pour les permissions permanentlyDenied, on ne tente pas request()
    // car le dialogue natif ne s'affichera pas.
    stillPermanentlyDenied.addAll(initial.permanentlyDeniedPermissions);

    // On demande les permissions encore en statut "denied" simple.
    for (final permission in initial.missingPermissions) {
      try {
        final status = await permission.request();
        if (status.isGranted || status.isLimited) {
          continue;
        }
        if (status.isPermanentlyDenied) {
          stillPermanentlyDenied.add(permission);
        } else {
          stillMissing.add(permission);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[PermissionGuard] Échec demande $permission: $e');
        }
        stillMissing.add(permission);
      }
    }

    final allStillMissing = [...stillMissing, ...stillPermanentlyDenied];

    return PermissionGuardResult(
      allGranted: allStillMissing.isEmpty,
      missingPermissions: stillMissing,
      permanentlyDeniedPermissions: stillPermanentlyDenied,
    );
  }

  /// Ouvre les paramètres système de l'application.
  ///
  /// À utiliser lorsque des permissions sont [permanentlyDenied],
  /// car seul l'utilisateur peut les réactiver manuellement.
  Future<void> openAppSettings() async {
    await openAppSettings();
  }
}
