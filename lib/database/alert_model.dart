// lib/database/alert_model.dart
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
  })  : createdAt = createdAt ?? DateTime.now().toUtc(),
        confirmations = confirmations ?? <String>{};

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
  bool addConfirmation(String ephemeralUserId) {
    if (confirmations.add(ephemeralUserId)) {
      if (isValidatedByConsensus && status == AlertStatus.pending) {
        status = AlertStatus.active;
      }
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
        'lon': longitude,
        if (description.isNotEmpty) 'description': description,
        if (densityValue != null) 'density_value': densityValue,
        'timestamp': createdAt.toUtc().toIso8601String(),
        'ttl_hours': ttlHours,
        'status': status.name,
        'confirmations': confirmations.toList(),
        'signature': signature,
      };

  /// Désérialisation depuis le format JSON serveur Node.js
  /// (GET /v1/reports + POST /alerts).
  factory Alert.fromJson(Map<String, dynamic> json) {
    final statusStr = (json['status'] as String?) ?? 'pending';
    final typeStr = (json['type'] as String?) ?? 'autre';
    return Alert(
      id: json['id'] as String,
      ephemeralUserId: (json['reporter_id'] as String?) ?? '',
      signature: (json['signature'] as String?) ?? '',
      type: AlertType.values.firstWhere(
        (t) => t.name == typeStr,
        orElse: () => AlertType.autre,
      ),
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lon'] as num).toDouble(),
      description: (json['description'] as String?) ?? '',
      densityValue: json['density_value'] as int?,
      createdAt: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String).toUtc()
          : DateTime.now().toUtc(),
      ttlHours: (json['ttl_hours'] as int?) ?? 24,
      status: AlertStatus.values.firstWhere(
        (s) => s.name == statusStr,
        orElse: () => AlertStatus.pending,
      ),
      confirmations: ((json['confirmations'] as List?) ?? const [])
          .map((e) => e.toString())
          .toSet(),
      uploadedTo: (json['uploaded_to'] as String?) ?? '',
    );
  }

  /// Sérialisation compacte (string) pour transport BLE / Wi-Fi.
  String toCompact() => jsonEncode(toJson());

  factory Alert.fromCompact(String raw) =>
      Alert.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  @override
  String toString() =>
      'Alert(id=$id, type=${type.name}, status=${status.name}, '
      'confirmations=${confirmations.length}/3, expires=$expiresAt)';
}
