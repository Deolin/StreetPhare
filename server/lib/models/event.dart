// server/lib/models/event.dart
//
// Modèle de données d'un Événement StreetPhare enrichi.
//
// Chaque événement contient :
//   - Métadonnées (nom, code, dates début/fin)
//   - Points GPS avec tranches horaires d'activation
//   - Centres médicaux, points de sortie
//   - Routes prévues et intermédiaires
//   - Alertes configurées


/// Représente un événement complet côté serveur.
class ServerEvent {
  ServerEvent({
    required this.id,
    required this.code,
    required this.name,
    this.description = '',
    required this.createdAt,
    this.startTime,
    this.endTime,
    this.startPoint,
    this.route = const [],
    this.waypoints = const [],
    this.blocks = const [],
    this.careCenters = const [],
    this.exitPoints = const [],
    this.safeZones = const [],
  });

  /// Identifiant unique (UUID v4).
  final String id;

  /// Code d'invitation (ex: MANIF-123).
  final String code;

  /// Nom lisible de l'événement.
  final String name;

  /// Description textuelle libre.
  final String description;

  /// Date de création serveur.
  final DateTime createdAt;

  /// Début de l'événement (nullable = non défini).
  final DateTime? startTime;

  /// Fin estimée de l'événement.
  final DateTime? endTime;

  /// Point de départ GPS de l'événement.
  final GpsPoint? startPoint;

  /// Points du tracé principal (polyligne).
  final List<GpsPoint> route;

  /// Points de passage intermédiaires (waypoints).
  final List<TimedWaypoint> waypoints;

  /// Segments de route bloqués.
  final List<BlockedSegment> blocks;

  /// Centres médicaux / street medics.
  final List<GpsPoint> careCenters;

  /// Points de sortie / évacuation.
  final List<GpsPoint> exitPoints;

  /// Zones de sécurité.
  final List<GpsPoint> safeZones;

  // ---------------------------------------------------------------------------
  // Sérialisation
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'description': description,
        'created_at': createdAt.toUtc().toIso8601String(),
        'start_time': startTime?.toUtc().toIso8601String(),
        'end_time': endTime?.toUtc().toIso8601String(),
        'start_point': startPoint?.toJson(),
        'route': route.map((p) => p.toJson()).toList(),
        'waypoints': waypoints.map((w) => w.toJson()).toList(),
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'care_centers': careCenters.map((c) => c.toJson()).toList(),
        'exit_points': exitPoints.map((e) => e.toJson()).toList(),
        'safe_zones': safeZones.map((s) => s.toJson()).toList(),
      };

  factory ServerEvent.fromJson(Map<String, dynamic> json) => ServerEvent(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
        startTime: json['start_time'] != null
            ? DateTime.parse(json['start_time'] as String)
            : null,
        endTime: json['end_time'] != null
            ? DateTime.parse(json['end_time'] as String)
            : null,
        startPoint: json['start_point'] != null
            ? GpsPoint.fromJson(json['start_point'] as Map<String, dynamic>)
            : null,
        route: (json['route'] as List<dynamic>?)
                ?.map((e) => GpsPoint.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        waypoints: (json['waypoints'] as List<dynamic>?)
                ?.map(
                    (e) => TimedWaypoint.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        blocks: (json['blocks'] as List<dynamic>?)
                ?.map(
                    (e) => BlockedSegment.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        careCenters: (json['care_centers'] as List<dynamic>?)
                ?.map((e) => GpsPoint.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        exitPoints: (json['exit_points'] as List<dynamic>?)
                ?.map((e) => GpsPoint.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        safeZones: (json['safe_zones'] as List<dynamic>?)
                ?.map((e) => GpsPoint.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  // ---------------------------------------------------------------------------
  // Export compact pour QR code
  // ---------------------------------------------------------------------------

  /// Exporte uniquement les champs nécessaires au client mobile
  /// (format compact pour QR code).
  Map<String, dynamic> toCompactJson() => {
        'v': 1,
        'code': code,
        'name': name,
        'desc': description,
        'st': startTime?.toUtc().toIso8601String(),
        'et': endTime?.toUtc().toIso8601String(),
        'sp': startPoint?.toCompactList(),
        'rt': route.map((p) => p.toCompactList()).toList(),
        'wp': waypoints.map((w) => w.toCompactJson()).toList(),
        'bl': blocks.map((b) => b.toCompactJson()).toList(),
        'cc': careCenters.map((c) => c.toCompactList()).toList(),
        'ex': exitPoints.map((e) => e.toCompactList()).toList(),
        'sz': safeZones.map((s) => s.toCompactList()).toList(),
      };

  @override
  String toString() => 'ServerEvent($code: $name)';
}

// ============================================================================
// Types GPS
// ============================================================================

/// Point GPS avec latitude, longitude et label optionnel.
class GpsPoint {
  const GpsPoint({
    required this.latitude,
    required this.longitude,
    this.label,
  });

  final double latitude;
  final double longitude;
  final String? label;

  Map<String, dynamic> toJson() => {
        'lat': latitude,
        'lng': longitude,
        if (label != null) 'label': label,
      };

  factory GpsPoint.fromJson(Map<String, dynamic> json) => GpsPoint(
        latitude: (json['lat'] as num).toDouble(),
        longitude: (json['lng'] as num).toDouble(),
        label: json['label'] as String?,
      );

  /// Format ultra-compact : [lat, lng]
  List<double> toCompactList() => [latitude, longitude];

  factory GpsPoint.fromCompactList(List<dynamic> list) => GpsPoint(
        latitude: (list[0] as num).toDouble(),
        longitude: (list[1] as num).toDouble(),
      );
}

// ============================================================================
// Waypoint avec tranche horaire d'activation
// ============================================================================

/// Point de passage avec heure d'activation stricte.
class TimedWaypoint {
  const TimedWaypoint({
    required this.position,
    required this.activationTime,
    required this.deactivationTime,
    this.label,
  });

  final GpsPoint position;
  final DateTime activationTime;
  final DateTime deactivationTime;
  final String? label;

  Map<String, dynamic> toJson() => {
        'pos': position.toJson(),
        'active_at': activationTime.toUtc().toIso8601String(),
        'deactive_at': deactivationTime.toUtc().toIso8601String(),
        if (label != null) 'label': label,
      };

  factory TimedWaypoint.fromJson(Map<String, dynamic> json) => TimedWaypoint(
        position:
            GpsPoint.fromJson(json['pos'] as Map<String, dynamic>),
        activationTime: DateTime.parse(json['active_at'] as String),
        deactivationTime: DateTime.parse(json['deactive_at'] as String),
        label: json['label'] as String?,
      );

  Map<String, dynamic> toCompactJson() => {
        'p': position.toCompactList(),
        'a': activationTime.toUtc().toIso8601String(),
        'd': deactivationTime.toUtc().toIso8601String(),
        if (label != null) 'l': label,
      };

  factory TimedWaypoint.fromCompactJson(Map<String, dynamic> json) =>
      TimedWaypoint(
        position: GpsPoint.fromCompactList(json['p'] as List<dynamic>),
        activationTime: DateTime.parse(json['a'] as String),
        deactivationTime: DateTime.parse(json['d'] as String),
        label: json['l'] as String?,
      );
}

// ============================================================================
// Segment de route bloqué
// ============================================================================

/// Segment de route bloqué avec tranche horaire.
class BlockedSegment {
  const BlockedSegment({
    required this.from,
    required this.to,
    required this.activeFrom,
    required this.activeUntil,
    this.reason,
  });

  final GpsPoint from;
  final GpsPoint to;
  final DateTime activeFrom;
  final DateTime activeUntil;
  final String? reason;

  Map<String, dynamic> toJson() => {
        'from': from.toJson(),
        'to': to.toJson(),
        'active_from': activeFrom.toUtc().toIso8601String(),
        'active_until': activeUntil.toUtc().toIso8601String(),
        if (reason != null) 'reason': reason,
      };

  factory BlockedSegment.fromJson(Map<String, dynamic> json) => BlockedSegment(
        from: GpsPoint.fromJson(json['from'] as Map<String, dynamic>),
        to: GpsPoint.fromJson(json['to'] as Map<String, dynamic>),
        activeFrom: DateTime.parse(json['active_from'] as String),
        activeUntil: DateTime.parse(json['active_until'] as String),
        reason: json['reason'] as String?,
      );

  Map<String, dynamic> toCompactJson() => {
        'f': from.toCompactList(),
        't': to.toCompactList(),
        'af': activeFrom.toUtc().toIso8601String(),
        'au': activeUntil.toUtc().toIso8601String(),
        if (reason != null) 'r': reason,
      };
}