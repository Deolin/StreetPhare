// lib/features/messaging/domain/models/temp_thread.dart
//
// Modèle d'un fil de discussion temporaire (Hive Mesh).
// Durée de vie configurable, public filtré (non chiffré E2E).

class TempThread {
  TempThread({
    required this.id,
    required this.createdAt,
    required this.durationMinutes,
    required this.participantIds,
    required this.color,
    this.label,
  });

  /// Identifiant unique du fil.
  final String id;

  /// Date de création (UTC).
  final DateTime createdAt;

  /// Durée de vie en minutes (défaut : 30).
  final int durationMinutes;

  /// IDs éphémères des participants.
  final Set<String> participantIds;

  /// Couleur d'accentuation de ce fil.
  final int color;

  /// Label court (optionnel).
  final String? label;

  /// `true` si le fil est encore actif.
  bool get isActive =>
      DateTime.now().toUtc().difference(createdAt).inMinutes < durationMinutes;

  /// Temps restant.
  Duration get remaining {
    final elapsed = DateTime.now().toUtc().difference(createdAt);
    final total = Duration(minutes: durationMinutes);
    final rem = total - elapsed;
    return rem.isNegative ? Duration.zero : rem;
  }

  TempThread copyWith({
    Set<String>? participantIds,
    int? color,
    String? label,
    int? durationMinutes,
  }) {
    return TempThread(
      id: id,
      createdAt: createdAt,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      participantIds: participantIds ?? this.participantIds,
      color: color ?? this.color,
      label: label ?? this.label,
    );
  }
}
