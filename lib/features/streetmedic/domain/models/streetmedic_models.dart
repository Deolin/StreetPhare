// lib/features/streetmedic/domain/models/streetmedic_models.dart
//
// Modèles de données du module Street-medic :
//   - StreetMedic : statut d'autorisation + position d'un médecin de rue.
//   - MedicMission : mission d'intervention (appel d'un blessé → soin).

/// Statut d'un street-medic côté serveur.
enum StreetMedicStatus {
  /// Demande en attente d'autorisation admin.
  pending,

  /// Autorisé par un admin, mais partage de position désactivé.
  authorized,

  /// Autorisé et partage de position actif.
  active,

  /// Statut révoqué par un admin.
  disabled;

  static StreetMedicStatus parse(String? s) =>
      StreetMedicStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => StreetMedicStatus.pending,
      );

  bool get isAuthorized =>
      this == StreetMedicStatus.authorized || this == StreetMedicStatus.active;
}

/// Représente un street-medic (tel que renvoyé par le serveur).
class StreetMedic {
  const StreetMedic({
    required this.id,
    required this.userId,
    required this.status,
    this.latitude,
    this.longitude,
    this.sharing = false,
    this.eventId,
    this.authorizedBy,
    this.requestedAt,
    this.authorizedAt,
    this.stale = false,
  });

  factory StreetMedic.fromJson(Map<String, dynamic> json) => StreetMedic(
        id: (json['id'] ?? '').toString(),
        userId: (json['userId'] ?? '').toString(),
        status: StreetMedicStatus.parse(json['status'] as String?),
        latitude: (json['lat'] as num?)?.toDouble(),
        longitude: (json['lng'] as num?)?.toDouble(),
        sharing: (json['sharing'] as bool?) ?? false,
        eventId: json['eventId'] as String?,
        authorizedBy: json['authorizedBy'] as String?,
        requestedAt: json['requestedAt'] as String?,
        authorizedAt: json['authorizedAt'] as String?,
        stale: (json['stale'] as bool?) ?? false,
      );

  final String id;
  final String userId;
  final StreetMedicStatus status;
  final double? latitude;
  final double? longitude;
  final bool sharing;
  final String? eventId;
  final String? authorizedBy;
  final String? requestedAt;
  final String? authorizedAt;
  final bool stale;

  bool get isAuthorized => status.isAuthorized;

  /// `true` si le street-medic est visible sur la carte (autorisation + partage).
  bool get isOnMap => isAuthorized && sharing;
}

/// Statut d'une mission d'intervention.
enum MedicMissionStatus {
  pending,
  accepted,
  refused,
  completed,
  cancelled;

  static MedicMissionStatus parse(String? s) => MedicMissionStatus.values
      .firstWhere((e) => e.name == s, orElse: () => MedicMissionStatus.pending);
}

/// Représente une mission d'intervention (blessé → street-medic).
class MedicMission {
  const MedicMission({
    required this.id,
    required this.callerUserId,
    required this.medicId,
    required this.status,
    required this.injuredLatitude,
    required this.injuredLongitude,
    this.note = '',
    this.refusedBy = const [],
    this.acceptedAt,
    this.completedAt,
    this.createdAt,
  });

  factory MedicMission.fromJson(Map<String, dynamic> json) => MedicMission(
        id: (json['id'] ?? '').toString(),
        callerUserId: (json['callerUserId'] ?? '').toString(),
        medicId: (json['medicId'] ?? '').toString(),
        status: MedicMissionStatus.parse(json['status'] as String?),
        injuredLatitude: (json['injuredLat'] as num?)?.toDouble() ?? 0,
        injuredLongitude: (json['injuredLng'] as num?)?.toDouble() ?? 0,
        note: (json['note'] ?? '').toString(),
        refusedBy: (json['refusedBy'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        acceptedAt: json['acceptedAt'] as String?,
        completedAt: json['completedAt'] as String?,
        createdAt: json['createdAt'] as String?,
      );

  final String id;
  final String callerUserId;
  final String medicId;
  final MedicMissionStatus status;
  final double injuredLatitude;
  final double injuredLongitude;
  final String note;
  final List<String> refusedBy;
  final String? acceptedAt;
  final String? completedAt;
  final String? createdAt;

  bool get isActive => status == MedicMissionStatus.accepted;
  bool get isPending => status == MedicMissionStatus.pending;
}