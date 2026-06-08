// lib/features/settings/data/panic_contact.dart
//
// Modèle d'un contact d'urgence (Bouton PANIC).
//
// Représente une entrée saisie par l'utilisateur dans la section
// "Contacts d'urgence" de la page Paramètres. Chaque contact dispose
// d'un identifiant stable, d'un libellé (ex. "Maman", "Samu") et
// d'un numéro de téléphone au format E.164 de préférence.

import 'dart:convert';

/// Contact d'urgence StreetPhare.
class PanicContact {
  PanicContact({
    required this.id,
    required this.name,
    required this.phoneNumber,
  });

  /// Identifiant stable (UUID-like généré localement).
  final String id;

  /// Libellé humain (ex: "Maman", "Compagnon/Compagne", "112").
  final String name;

  /// Numéro de téléphone, idéalement au format E.164 (`+33...`).
  final String phoneNumber;

  PanicContact copyWith({String? name, String? phoneNumber}) {
    return PanicContact(
      id: id,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phoneNumber,
      };

  factory PanicContact.fromJson(Map<String, dynamic> j) => PanicContact(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        phoneNumber: (j['phone'] as String?) ?? '',
      );

  /// Sérialise la liste complète (utilisé par `PanicContactStore`).
  static String encodeList(List<PanicContact> contacts) =>
      jsonEncode(contacts.map((c) => c.toJson()).toList());

  /// Désérialise la liste complète. Retourne une liste vide en cas
  /// de JSON corrompu.
  static List<PanicContact> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(PanicContact.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
