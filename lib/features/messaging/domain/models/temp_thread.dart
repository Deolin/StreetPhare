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

  /// Sérialise le fil en chaîne JSON pour persistance SharedPreferences.
  String toJson() {
    final buffer = StringBuffer();
    buffer.write('{"id":"$id",');
    buffer.write('"createdAt":"${createdAt.toUtc().toIso8601String()}",');
    buffer.write('"durationMinutes":$durationMinutes,');
    buffer.write('"participantIds":[${participantIds.map((p) => '"$p"').join(',')}],');
    buffer.write('"color":$color');
    if (label != null) {
      buffer.write(',"label":"$label"');
    }
    buffer.write('}');
    return buffer.toString();
  }

  /// Restaure un fil depuis sa représentation JSON.
  factory TempThread.fromJson(String json) {
    // Utilise un parseur manuel simple et robuste (pas de dépendance dart:convert
    // pour éviter les erreurs de parsing sur des payloads corrompus).
    final map = _parseSimpleJson(json);
    return TempThread(
      id: map['id'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      durationMinutes: int.parse(map['durationMinutes'].toString()),
      participantIds: (map['participantIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toSet() ??
          <String>{},
      color: int.parse(map['color'].toString()),
      label: map['label'] as String?,
    );
  }

  /// Parseur JSON simpliste pour les structures plates.
  static Map<String, Object?> _parseSimpleJson(String src) {
    final map = <String, Object?>{};
    // Extrait les paires clé:valeur du JSON.
    final content = src.trim();
    if (!content.startsWith('{') || !content.endsWith('}')) return map;
    final inner = content.substring(1, content.length - 1);
    // Parse basique sans dépendance lourde.
    final parts = _splitJsonTopLevel(inner, ',');
    for (final part in parts) {
      final colon = part.indexOf(':');
      if (colon == -1) continue;
      final key = part.substring(0, colon).trim().replaceAll('"', '');
      final val = part.substring(colon + 1).trim();
      if (val.startsWith('[')) {
        // Liste de strings
        final listContent = val.substring(1, val.length - 1);
        final items = _splitJsonTopLevel(listContent, ',');
        map[key] = items
            .map((i) => i.trim().replaceAll('"', ''))
            .where((i) => i.isNotEmpty)
            .toList();
      } else if (val.startsWith('"')) {
        map[key] = val.replaceAll('"', '');
      } else {
        map[key] = val;
      }
    }
    return map;
  }

  static List<String> _splitJsonTopLevel(String src, String sep) {
    final result = <String>[];
    int depth = 0;
    int start = 0;
    for (int i = 0; i < src.length; i++) {
      final c = src[i];
      if (c == '{' || c == '[') depth++;
      if (c == '}' || c == ']') depth--;
      if (c == sep && depth == 0) {
        result.add(src.substring(start, i));
        start = i + 1;
      }
    }
    result.add(src.substring(start));
    return result;
  }
}
