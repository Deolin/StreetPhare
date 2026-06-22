// server/lib/event_manager.dart
//
// Gestionnaire central des événements côté serveur.
//
// Responsabilités :
//   - Stockage en mémoire des événements enrichis
//   - CRUD complet (créer, lire, mettre à jour, supprimer)
//   - Export/import JSON pour persistance fichier
//   - Génération de données compactes pour QR code

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';
import 'models/event.dart';

final _log = Logger('EventManager');

/// Singleton de gestion des événements serveur.
class EventManager {
  EventManager._();
  static final EventManager instance = EventManager._();

  final _uuid = const Uuid();
  final Map<String, ServerEvent> _events = {};
  final Random _rng = Random.secure();

  /// Tous les événements actifs.
  List<ServerEvent> get all => _events.values.toList();

  /// Récupère un événement par son code d'invitation.
  ServerEvent? findByCode(String code) {
    code = code.toUpperCase().trim();
    return _events.values.firstWhere(
      (e) => e.code.toUpperCase() == code,
    );
  }

  /// Récupère un événement par son ID.
  ServerEvent? findById(String id) => _events[id];

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  /// Crée un nouvel événement.
  ServerEvent create(ServerEvent event) {
    _events[event.id] = event;
    _log.info('Événement créé : ${event.code} — ${event.name}');
    return event;
  }

  /// Met à jour un événement existant.
  ServerEvent? update(ServerEvent updated) {
    if (!_events.containsKey(updated.id)) return null;
    _events[updated.id] = updated;
    _log.info('Événement mis à jour : ${updated.code}');
    return updated;
  }

  /// Supprime un événement.
  bool delete(String id) {
    final removed = _events.remove(id);
    if (removed != null) {
      _log.info('Événement supprimé : ${removed.code}');
    }
    return removed != null;
  }

  /// Génère un code d'invitation unique (6 caractères alphanumériques).
  String generateInviteCode() {
    const charset = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    for (int attempt = 0; attempt < 100; attempt++) {
      final code = List.generate(
          6, (_) => charset[_rng.nextInt(charset.length)]).join();
      if (findByCode(code) == null) return code;
    }
    // Fallback avec UUID tronqué
    return _uuid.v4().substring(0, 6).toUpperCase();
  }

  /// Crée un événement avec un code généré automatiquement.
  ServerEvent createWithGeneratedCode({
    required String name,
    String description = '',
    DateTime? startTime,
    DateTime? endTime,
    GpsPoint? startPoint,
  }) {
    final code = generateInviteCode();
    return create(ServerEvent(
      id: _uuid.v4(),
      code: code,
      name: name,
      description: description,
      createdAt: DateTime.now().toUtc(),
      startTime: startTime,
      endTime: endTime,
      startPoint: startPoint,
    ));
  }

  // ---------------------------------------------------------------------------
  // Persistance fichier
  // ---------------------------------------------------------------------------

  /// Sauvegarde tous les événements dans un fichier JSON.
  Future<void> saveToFile(String path) async {
    final list = _events.values.map((e) => e.toJson()).toList();
    final file = File(path);
    await file.writeAsString(jsonEncode(list), flush: true);
    _log.info('${list.length} événements sauvegardés dans $path');
  }

  /// Charge les événements depuis un fichier JSON.
  Future<int> loadFromFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      _log.info('Fichier $path inexistant — aucun événement chargé');
      return 0;
    }
    try {
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      _events.clear();
      for (final entry in list) {
        final event =
            ServerEvent.fromJson(entry as Map<String, dynamic>);
        _events[event.id] = event;
      }
      _log.info('${_events.length} événements chargés depuis $path');
      return _events.length;
    } catch (e) {
      _log.severe('Erreur chargement événements : $e');
      return 0;
    }
  }

  // ---------------------------------------------------------------------------
  // Statistiques
  // ---------------------------------------------------------------------------

  /// Nombre total d'événements.
  int get count => _events.length;

  /// Événements actuellement actifs (date courante entre startTime et endTime).
  List<ServerEvent> get currentlyActive {
    final now = DateTime.now().toUtc();
    return _events.values.where((e) {
      if (e.startTime == null && e.endTime == null) return true;
      if (e.startTime != null && now.isBefore(e.startTime!)) return false;
      if (e.endTime != null && now.isAfter(e.endTime!)) return false;
      return true;
    }).toList();
  }
}