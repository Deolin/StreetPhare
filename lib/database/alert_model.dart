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
enum AlertStatus {
  /// Alerte créée localement, pas encore confirmée.
  pending,

  /// Alerte reçue via P2P et en attente de consensus.
  propagated,

  /// Alerte confirmée par au moins 3 utilisateurs distincts.
  validated,

  /// Alerte téléversée avec succès sur le serveur central.
  uploaded,

  /// Alerte expirée (TTL > 24h) et purgée du stockage local.
  expired,
}

/// Type d'alerte (barrage, nasse, contrôle, accident, etc.).
enum AlertType {
  barrage,
  nasse,
  controle,
  accident,
  rassemblement,
  /// Zone safe signalée par un utilisateur. Sert de point de repli.
  zoneSafe,
  /// Alerte panic collective automatique (5 appareils / 2 min).
  panicCollectif,
  /// Rapport de densité Bluetooth locale.
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

  /// Indique si l'alerte a atteint le seuil de consensus (3
  /// utilisateurs uniques distincts).
  bool get isValidatedByConsensus => confirmations.length >= 3;

  /// Ajoute une confirmation d'un utilisateur éphémère. Retourne
  /// `true` si cette confirmation a fait passer le compteur à 3.
  bool addConfirmation(String ephemeralUserId) {
    if (confirmations.add(ephemeralUserId)) {
      if (isValidatedByConsensus && status == AlertStatus.propagated) {
        status = AlertStatus.validated;
      }
      return isValidatedByConsensus;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'euid': ephemeralUserId,
        'sig': signature,
        'type': type.name,
        'lat': latitude,
        'lng': longitude,
        'desc': description,
        if (densityValue != null) 'dv': densityValue,
        'ca': createdAt.toIso8601String(),
        'ttl': ttlHours,
        'st': status.name,
        'conf': confirmations.toList(),
        'up': uploadedTo,
      };

  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      id: json['id'] as String,
      ephemeralUserId: json['euid'] as String,
      signature: json['sig'] as String,
      type: AlertType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => AlertType.autre,
      ),
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      description: (json['desc'] as String?) ?? '',
      densityValue: json['dv'] as int?,
      createdAt: DateTime.parse(json['ca'] as String).toUtc(),
      ttlHours: (json['ttl'] as int?) ?? 24,
      status: AlertStatus.values.firstWhere(
        (s) => s.name == json['st'],
        orElse: () => AlertStatus.pending,
      ),
      confirmations: ((json['conf'] as List?) ?? const [])
          .map((e) => e.toString())
          .toSet(),
      uploadedTo: (json['up'] as String?) ?? '',
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
