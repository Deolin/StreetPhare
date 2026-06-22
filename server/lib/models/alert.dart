// server/lib/models/alert.dart
//
// Modèle d'alerte côté serveur pour la synchronisation client.


/// Statut d'une alerte côté serveur.
enum ServerAlertStatus {
  active, // En cours de validité
  expired, // TTL dépassé
  deleted, // Supprimé par l'admin
}

/// Type d'alerte supporté par le serveur.
enum ServerAlertType {
  barrage,
  nasse,
  controle,
  accident,
  rassemblement,
  pompier,
  danger,
  panicCollectif,
  zoneSafe,
  adminMessage,
}

/// Alerte gérée par le serveur.
class ServerAlert {
  ServerAlert({
    required this.id,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.description = '',
    required this.createdAt,
    this.expiresAt,
    this.status = ServerAlertStatus.active,
    this.eventCode,
    this.isAdmin = false,
  });

  final String id;
  final ServerAlertType type;
  final double latitude;
  final double longitude;
  final String description;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final ServerAlertStatus status;
  final String? eventCode;
  final bool isAdmin;

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().toUtc().isAfter(expiresAt!);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'lat': latitude,
        'lng': longitude,
        'description': description,
        'created_at': createdAt.toUtc().toIso8601String(),
        'expires_at': expiresAt?.toUtc().toIso8601String(),
        'status': status.name,
        'event_code': eventCode,
        'is_admin': isAdmin,
      };

  factory ServerAlert.fromJson(Map<String, dynamic> json) => ServerAlert(
        id: json['id'] as String,
        type: ServerAlertType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => ServerAlertType.danger,
        ),
        latitude: (json['lat'] as num).toDouble(),
        longitude: (json['lng'] as num).toDouble(),
        description: json['description'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
        expiresAt: json['expires_at'] != null
            ? DateTime.parse(json['expires_at'] as String)
            : null,
        status: ServerAlertStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => ServerAlertStatus.active,
        ),
        eventCode: json['event_code'] as String?,
        isAdmin: json['is_admin'] as bool? ?? false,
      );

  /// Format compact pour synchronisation client.
  Map<String, dynamic> toCompactJson() => {
        'id': id,
        'tp': type.name,
        'la': latitude,
        'lo': longitude,
        'ds': description,
        'ca': createdAt.toUtc().toIso8601String(),
        'ea': expiresAt?.toUtc().toIso8601String(),
        'st': status.name,
        'ec': eventCode,
        'ad': isAdmin,
      };
}