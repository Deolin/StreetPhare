// lib/features/messaging/domain/models/hive_message.dart
//
// Modèle d'un message P2P Hive décentralisé.
//
// Les messages sont identifiés par un UUID éphémère (jamais lié à
// une identité permanente) et diffusés sur le réseau maillé.

import 'package:latlong2/latlong.dart';

/// Type de message Hive P2P.
enum HiveMessageType {
  /// Message textuel ordinaire.
  text,

  /// Message d'alerte critique (ex: danger confirmé).
  alert,

  /// Message d'un administrateur de l'événement (signé).
  admin,
}

extension HiveMessageTypeExt on HiveMessageType {
  String get label {
    switch (this) {
      case HiveMessageType.text:
        return 'Message';
      case HiveMessageType.alert:
        return 'Alerte';
      case HiveMessageType.admin:
        return 'Admin';
    }
  }
}

/// Représente un message diffusé sur le réseau P2P Hive.
class HiveMessage {
  const HiveMessage({
    required this.id,
    required this.senderEphemeralId,
    required this.content,
    required this.type,
    required this.sentAt,
    this.latitude,
    this.longitude,
    this.isFromAdmin = false,
    this.threadId,
  });

  /// Identifiant unique (UUID v4 éphémère).
  final String id;

  /// Identifiant éphémère de l'émetteur (UUID session anonyme).
  final String senderEphemeralId;

  /// Contenu textuel du message.
  final String content;

  /// Type du message (text / alert / admin).
  final HiveMessageType type;

  /// Horodatage d'émission (UTC).
  final DateTime sentAt;

  /// Coordonnée GPS de l'émetteur au moment de l'envoi (optionnel).
  final double? latitude;
  final double? longitude;

  /// `true` si le message provient d'un administrateur d'événement.
  final bool isFromAdmin;

  /// ID du fil de discussion temporaire (null = fil principal).
  final String? threadId;

  /// Position GPS de l'émetteur (null si non disponible).
  LatLng? get position =>
      latitude != null && longitude != null ? LatLng(latitude!, longitude!) : null;

  /// Alias court de l'émetteur (6 premiers chars de l'UUID).
  String get senderAlias =>
      senderEphemeralId.length >= 6 ? senderEphemeralId.substring(0, 6) : senderEphemeralId;

  /// Sérialisation JSON.
  Map<String, dynamic> toJson() => {
        'id': id,
        'sender': senderEphemeralId,
        'content': content,
        'type': type.name,
        'sentAt': sentAt.toIso8601String(),
        'lat': latitude,
        'lng': longitude,
        'isAdmin': isFromAdmin,
        'threadId': threadId,
      };

  /// Désérialisation depuis JSON.
  factory HiveMessage.fromJson(Map<String, dynamic> json) {
    return HiveMessage(
      id: json['id'] as String? ?? '',
      senderEphemeralId: json['sender'] as String? ?? '??????',
      content: json['content'] as String? ?? '',
      type: HiveMessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => HiveMessageType.text,
      ),
      sentAt: DateTime.tryParse(json['sentAt'] as String? ?? '') ?? DateTime.now().toUtc(),
      latitude: (json['lat'] as num?)?.toDouble(),
      longitude: (json['lng'] as num?)?.toDouble(),
      isFromAdmin: (json['isAdmin'] as bool?) ?? false,
      threadId: json['threadId'] as String?,
    );
  }

  HiveMessage copyWith({
    String? id,
    String? senderEphemeralId,
    String? content,
    HiveMessageType? type,
    DateTime? sentAt,
    double? latitude,
    double? longitude,
    bool? isFromAdmin,
    String? threadId,
  }) {
    return HiveMessage(
      id: id ?? this.id,
      senderEphemeralId: senderEphemeralId ?? this.senderEphemeralId,
      content: content ?? this.content,
      type: type ?? this.type,
      sentAt: sentAt ?? this.sentAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isFromAdmin: isFromAdmin ?? this.isFromAdmin,
      threadId: threadId ?? this.threadId,
    );
  }

  @override
  String toString() =>
      'HiveMessage(id=$id, type=${type.name}, sender=$senderAlias, content=$content)';
}
