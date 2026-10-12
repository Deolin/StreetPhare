// lib/core/models/alert_model.dart
//
// Modèle de données d'une alerte StreetPhare.
//
// Chaque alerte possède une durée de vie (TTL) stricte de 24 heures
// calculée depuis son `createdAt`. Passé ce délai, l'alerte doit être
// synchronisée vers le serveur central (si possible) puis effacée
// localement pour protéger la vie privée de l'utilisateur.

import 'dart:convert';
import 'package:latlong2/latlong.dart';

/// Statut d'une alerte dans son cycle de vie local + réseau.
/// Doit correspondre au contrat serveur Node.js (reports_store).
enum AlertStatus {
  /// Alerte créée localement, pas encore confirmée.
  pending,

  /// Alerte confirmée par consensus (≥3 votes) et visible.
  active,

  /// Alerte rejetée (quorum insuffisant, TTL expiré avant validation).
  rejected,
}

/// Type d'alerte aligné sur le contrat serveur Node.js
/// (reports_store.js TTL_BY_TYPE).
enum AlertType {
  barrage,
  casseurs,
  danger,
  policiers,
  autopompes,
  filtre,
  panic,
  dangerCollectif,
  density,
  autre,
}

/// Modèle immuable d'une alerte. La sérialisation est volontairement
/// simple (JSON via `dart:convert`) pour rester compatible avec les
/// couches P2P (Bluetooth / Wi-Fi Direct) où la taille du payload
/// doit être minimale.
class Alert {
  Alert({
    required this.id,
    required this.ephemeralUserId,
    required this.signature,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.description = '',
    this.densityValue,
    DateTime? createdAt,
    this.ttlHours = 24,
    this.status = AlertStatus.pending,
    Set<String>? confirmations,
    this.uploadedTo = '',
    DateTime? lastModifiedAt,
  })  : createdAt = createdAt ?? DateTime.now().toUtc(),
        confirmations = Set<String>.from(confirmations ?? <String>{}),
        lastModifiedAt = lastModifiedAt ?? DateTime.now().toUtc();

  /// Désérialisation depuis le format JSON serveur Node.js
  /// (GET /v1/reports + POST /alerts).
  factory Alert.fromJson(Map<String, dynamic> json) {
    final statusStr = (json['status'] as String?) ?? 'pending';
    return Alert(
      id: (json['id'] as String?) ?? '',
      ephemeralUserId: (json['reporter_id'] as String?) ??
          (json['userId'] as String?) ??
          '',
      signature: (json['signature'] as String?) ?? '',
      type: alertTypeFromName(json['type'] as String?),
      latitude: _asDouble(json['lat']),
      longitude: _asDouble(json['lng'] ?? json['lon']),
      description: (json['description'] as String?) ?? '',
      densityValue: json['density_value'] as int?,
      createdAt: _parseDate(json['createdAt'] ?? json['timestamp']),
      ttlHours: (json['ttl_hours'] as int?) ?? 24,
      status: AlertStatus.values.firstWhere(
        (s) => s.name == statusStr,
        orElse: () => AlertStatus.pending,
      ),
      confirmations:
          ((json['votes'] ?? json['confirmations']) as List?)
                  ?.map((e) => e.toString())
                  .toSet() ??
              const <String>{},
      uploadedTo: (json['uploadedTo'] as String?) ??
          (json['uploaded_to'] as String?) ??
          '',
      lastModifiedAt:
          _parseDate(json['updatedAt'] ?? json['last_modified_at']),
    );
  }

  factory Alert.fromCompact(String raw) =>
      Alert.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  /// Lit une valeur numérique JSON de façon tolérante (num → double).
  static double _asDouble(Object? value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  /// Parse une date ISO, ou retombe sur `now` en cas d'absence/invalidité.
  static DateTime _parseDate(Object? value) {
    if (value == null) return DateTime.now().toUtc();
    final parsed = DateTime.tryParse(value.toString());
    return (parsed ?? DateTime.now()).toUtc();
  }

  /// Résout un [AlertType] à partir d'un identifiant texte, qu'il provienne
  /// du serveur Node.js (`filter`, `police`, `mobile_danger`, …) ou du
  /// modèle Dart local (`filtre`, `policiers`, `danger`, …).
  static AlertType alertTypeFromName(String? name) {
    switch (name) {
      // ── Contrat serveur Node.js ────────────────────────────────────
      case 'police':
        return AlertType.policiers;
      case 'fire_truck':
        return AlertType.autopompes;
      case 'filter':
        return AlertType.filtre;
      case 'mobile_danger':
        return AlertType.danger;
      case 'collective_danger':
        return AlertType.dangerCollectif;
      case 'panic':
        return AlertType.panic;
      // ── Noms locaux (round-trip P2P / anciens payloads) ────────────
      case 'barrage':
        return AlertType.barrage;
      case 'casseurs':
        return AlertType.casseurs;
      case 'danger':
        return AlertType.danger;
      case 'policiers':
        return AlertType.policiers;
      case 'autopompes':
        return AlertType.autopompes;
      case 'filtre':
        return AlertType.filtre;
      case 'dangerCollectif':
        return AlertType.dangerCollectif;
      case 'density':
        return AlertType.density;
      default:
        return AlertType.autre;
    }
  }

  /// Identifiant unique anonyme (hash court). Généré côté client.
  final String id;

  /// Identifiant éphémère de l'utilisateur ayant créé l'alerte.
  /// Rotatif, jamais réutilisé, sert au mécanisme de consensus.
  final String ephemeralUserId;

  /// Signature cryptographique anonyme de l'alerte par son créateur.
  /// Permet de prouver l'authenticité sans révéler l'identité.
  final String signature;

  /// Type d'alerte.
  final AlertType type;

  /// Latitude / longitude.
  final double latitude;
  final double longitude;

  /// Description textuelle libre (optionnelle).
  final String description;

  /// Valeur de densité (si type == density)
  final int? densityValue;

  /// Date de création (UTC).
  final DateTime createdAt;

  /// TTL en heures. Vaut 24 par défaut (règle stricte du projet).
  final int ttlHours;

  /// Timestamp de fin de vie (createdAt + ttlHours).
  DateTime get expiresAt => createdAt.add(Duration(hours: ttlHours));

  /// Statut courant de l'alerte dans le cycle de vie local.
  AlertStatus status;

  /// Set des identifiants éphémères qui ont confirmé l'alerte.
  /// Utilisé pour le mécanisme de consensus (3 validations).
  final Set<String> confirmations;

  /// Adresse du serveur central sur lequel l'alerte a été uploadée
  /// (vide tant que pas synchronisée).
  String uploadedTo;

  /// Horodatage de dernière modification.
  /// Mis à jour à chaque changement de statut, confirmation ou synchronisation.
  /// Utilisé pour la synchronisation différentielle Hive ↔ Serveur.
  DateTime lastModifiedAt;

  /// Coordonnées LatLng (utile pour flutter_map).
  LatLng get position => LatLng(latitude, longitude);

  /// Indique si l'alerte a atteint ou dépassé son TTL de 24h.
  bool isExpired([DateTime? now]) {
    final reference = now ?? DateTime.now().toUtc();
    return reference.isAfter(expiresAt);
  }

  /// Indique si l'alerte a atteint le seuil de consensus (≥3
  /// confirmations distinctes).
  bool get isValidatedByConsensus => confirmations.length >= 3;

  /// Ajoute une confirmation. Passe le statut à [AlertStatus.active]
  /// dès que le seuil de consensus est atteint.
  /// Met à jour [lastModifiedAt] à chaque ajout.
  bool addConfirmation(String ephemeralUserId) {
    if (confirmations.add(ephemeralUserId)) {
      if (isValidatedByConsensus && status == AlertStatus.pending) {
        status = AlertStatus.active;
      }
      lastModifiedAt = DateTime.now().toUtc();
      return isValidatedByConsensus;
    }
    return false;
  }

  /// Sérialisation alignée sur le contrat serveur Node.js
  /// (POST /v1/reports + POST /alerts).
  Map<String, dynamic> toJson() => {
        'id': id,
        'reporter_id': ephemeralUserId,
        'type': type.name,
        'lat': latitude,
        'lng': longitude,
        'lon': longitude,
        if (description.isNotEmpty) 'description': description,
        if (densityValue != null) 'density_value': densityValue,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'timestamp': createdAt.toUtc().toIso8601String(),
        'ttl_hours': ttlHours,
        'status': status.name,
        'votes': confirmations.toList(),
        'confirmations': confirmations.toList(),
        'signature': signature,
        'uploadedTo': uploadedTo,
        'updatedAt': lastModifiedAt.toUtc().toIso8601String(),
        'last_modified_at': lastModifiedAt.toUtc().toIso8601String(),
      };

  /// Sérialisation compacte (string) pour transport BLE / Wi-Fi.
  String toCompact() => jsonEncode(toJson());

  @override
  String toString() =>
      'Alert(id=$id, type=${type.name}, status=${status.name}, '
      'confirmations=${confirmations.length}/3, expires=$expiresAt)';
}
