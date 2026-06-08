// lib/features/settings/data/panic_contact_store.dart
//
// Stockage des contacts d'urgence StreetPhare.
//
// Persistance simple via `shared_preferences` (clé `streetphare.panic_contacts`).
// Le contenu est sérialisé en JSON. Le store expose un
// `ValueListenable<List<PanicContact>>` pour que l'UI se mette à
// jour en temps réel (ajout / modification / suppression).

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'panic_contact.dart';

/// Store singleton des contacts d'urgence.
class PanicContactStore extends ValueNotifier<List<PanicContact>> {
  PanicContactStore._() : super(const []);

  static final PanicContactStore instance = PanicContactStore._();

  static const String _prefsKey = 'streetphare.panic_contacts';

  /// Charge la liste persistée. À appeler une fois au démarrage.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      value = PanicContact.decodeList(raw);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PanicContactStore] impossible de charger : $e');
      }
      value = const [];
    }
  }

  /// Ajoute un nouveau contact et persiste.
  Future<PanicContact> add({required String name, required String phone}) async {
    final contact = PanicContact(
      id: _newId(),
      name: name.trim(),
      phoneNumber: phone.trim(),
    );
    final next = [...value, contact];
    value = next;
    await _persist(next);
    return contact;
  }

  /// Met à jour un contact existant (par id).
  Future<bool> update(
    String id, {
    required String name,
    required String phone,
  }) async {
    final index = value.indexWhere((c) => c.id == id);
    if (index < 0) return false;
    final updated = value[index].copyWith(name: name.trim(), phoneNumber: phone.trim());
    final next = [...value];
    next[index] = updated;
    value = next;
    await _persist(next);
    return true;
  }

  /// Supprime un contact par id.
  Future<bool> remove(String id) async {
    final next = value.where((c) => c.id != id).toList();
    if (next.length == value.length) return false;
    value = next;
    await _persist(next);
    return false;
  }

  /// Vide la liste (utile pour les tests / RGPD).
  Future<void> clear() async {
    value = const [];
    await _persist(const []);
  }

  // -------- Helpers --------

  Future<void> _persist(List<PanicContact> contacts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, PanicContact.encodeList(contacts));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PanicContactStore] impossible de persister : $e');
      }
    }
  }

  String _newId() {
    final rng = Random();
    final ts = DateTime.now().toUtc().millisecondsSinceEpoch.toRadixString(36);
    final rnd = (rng.nextInt(1 << 32)).toRadixString(36).padLeft(7, '0');
    return 'pc_$ts$rnd';
  }
}
