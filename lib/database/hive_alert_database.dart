// lib/database/hive_alert_database.dart
//
// Gestionnaire de la mini-base de données locale "Hive".
//
// Responsabilités :
//   1. Stocker localement toutes les alertes (reçues ou créées).
//   2. Purger systématiquement les alertes dont le TTL de 24h est
//      dépassé, APRES tentative de synchronisation.
//   3. Exposer une API simple (CRUD) au reste de l'application.
//
// Choix techniques : `hive` est préféré à `sqflite` pour sa
// légèreté (NoSQL clé/valeur, parfait pour des objets Alert
// éphémères). Aucune dépendance native ne limite la portabilité.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../core/models/alert_model.dart';

/// Gestionnaire singleton de la base locale d'alertes.
class HiveAlertDatabase {
  HiveAlertDatabase._internal();
  static final HiveAlertDatabase instance = HiveAlertDatabase._internal();

  /// Nom de la box Hive où sont stockées les alertes.
  static const String _boxName = 'streetphare_alerts_v1';

  Box<Alert>? _box;

  /// Stream qui émet les alertes à chaque mutation.
  final _changesController = StreamController<List<Alert>>.broadcast();
  Stream<List<Alert>> get changes => _changesController.stream;

  bool _initialized = false;

  /// Expose l'état d'initialisation pour que les services dépendants
  /// (ex: GeofencingService) puissent vérifier avant d'appeler
  /// getAllValid() ou d'autres méthodes qui lèvent un StateError.
  bool get isInitialized => _initialized && _box != null;

  /// Initialise Hive. Doit être appelé une seule fois au démarrage
  /// de l'application (avant `runApp`).
  Future<void> init() async {
    if (_initialized) return;

    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(AlertAdapter());
    }
    _box = await Hive.openBox<Alert>(_boxName);
    _initialized = true;

    if (kDebugMode) {
      debugPrint('[HiveAlertDatabase] initialisée, '
          '${_box!.length} alertes en mémoire');
    }

    // Purge initiale pour nettoyer les entrées déjà expirées.
    await purgeExpired();
  }

  /// Liste toutes les alertes encore valides (TTL non dépassé).
  List<Alert> getAllValid() {
    _ensureOpen();
    final now = DateTime.now().toUtc();
    return _box!.values.where((a) => !a.isExpired(now)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Liste toutes les alertes, y compris expirées (debug / sync).
  List<Alert> getAll() {
    _ensureOpen();
    return _box!.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Récupère une alerte par id.
  Alert? getById(String id) {
    _ensureOpen();
    return _box!.get(id);
  }

  /// Insère ou met à jour une alerte.
  /// Retourne `true` si l'insertion est nouvelle (id inconnu).
  Future<bool> upsert(Alert alert) async {
    _ensureOpen();
    final isNew = !_box!.containsKey(alert.id);
    await _box!.put(alert.id, alert);
    _emit();
    return isNew;
  }

  /// Insère une alerte reçue du réseau P2P, en évitant les doublons.
  /// Si une alerte du même id existe déjà, on fusionne les
  /// confirmations (mécanisme de consensus).
  Future<bool> insertOrMerge(Alert incoming) async {
    _ensureOpen();
    final existing = _box!.get(incoming.id);
    if (existing == null) {
      await _box!.put(incoming.id, incoming);
      _emit();
      return true;
    }

    // Fusion des confirmations pour le consensus.
    for (final uid in incoming.confirmations) {
      existing.addConfirmation(uid);
    }
    // Re-pose l'objet mis à jour dans la box (Alert n'hérite pas
    // de HiveObject pour garder des champs final immutables).
    await _box!.put(existing.id, existing);
    _emit();
    return false;
  }

  /// Supprime une alerte par id.
  Future<void> delete(String id) async {
    _ensureOpen();
    await _box!.delete(id);
    _emit();
  }

  /// Purge les alertes dont le TTL de 24h est dépassé.
  ///
  /// Règle critique : la donnée est D'ABORD retournée via le
  /// callback [onBeforeDelete] pour permettre une dernière tentative
  /// de synchronisation avec le serveur central, puis effacée.
  ///
  /// Retourne la liste des alertes effectivement purgées.
  Future<List<Alert>> purgeExpired({
    DateTime? now,
    Future<void> Function(Alert alert)? onBeforeDelete,
  }) async {
    _ensureOpen();
    final reference = now ?? DateTime.now().toUtc();
    final expired = _box!.values.where((a) => a.isExpired(reference)).toList();

    for (final alert in expired) {
      try {
        if (onBeforeDelete != null) {
          await onBeforeDelete(alert);
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[HiveAlertDatabase] erreur callback purge ${alert.id} : $e\n$st');
        }
      }
      // Effacement systématique (règle de protection de la vie privée),
      // même si le callback onBeforeDelete a échoué.
      try {
        alert.status = AlertStatus.rejected;
        await _box!.delete(alert.id);
        if (kDebugMode) {
          debugPrint('[HiveAlertDatabase] alerte purgée : ${alert.id}');
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[HiveAlertDatabase] erreur purge ${alert.id} : $e\n$st');
        }
      }
    }
    if (expired.isNotEmpty) _emit();
    return expired;
  }

  /// Renvoie les alertes marquées `validated` et pas encore
  /// uploadées (utilisées par le coordinateur réseau).
  List<Alert> getPendingUpload() {
    _ensureOpen();
    return _box!.values
        .where((a) => a.status == AlertStatus.active && a.uploadedTo.isEmpty)
        .toList();
  }

  /// Marque une alerte comme uploadée sur un serveur donné.
  Future<void> markUploaded(String id, String server) async {
    _ensureOpen();
    final alert = _box!.get(id);
    if (alert == null) return;
    alert.status = AlertStatus.active;
    alert.uploadedTo = server;
    await _box!.put(alert.id, alert);
    _emit();
  }

  /// Vide complètement la base (debug / RGPD).
  Future<void> clearAll() async {
    _ensureOpen();
    await _box!.clear();
    _emit();
  }

  /// Retourne le [DateTime] de la dernière modification parmi toutes
  /// les alertes en base, ou `null` si la base est vide.
  /// Utilisé par [SyncService] pour la synchronisation différentielle.
  DateTime? lastModifiedTimestamp() {
    _ensureOpen();
    if (_box!.isEmpty) return null;
    return _box!.values
        .map((a) => a.lastModifiedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
  }

  void _emit() {
    if (!_changesController.isClosed) {
      _changesController.add(getAllValid());
    }
  }

  void _ensureOpen() {
    if (!_initialized || _box == null) {
      throw StateError(
        'HiveAlertDatabase non initialisée. Appelez HiveAlertDatabase.instance.init() '
        'au démarrage de l\'application.',
      );
    }
  }

  Future<void> close() async {
    await _changesController.close();
    await _box?.close();
    _initialized = false;
  }
}

/// Adapter Hive pour la classe [Alert].
///
/// Génère un identifiant d'adapter (1) unique dans le projet. Tout
/// changement de schéma doit utiliser un nouveau typeId pour
/// déclencher une migration propre.
class AlertAdapter extends TypeAdapter<Alert> {
  @override
  final int typeId = 1;

  @override
  Alert read(BinaryReader reader) {
    // Sécurisation : si la box Hive contient des données corrompues
    // ou d'une version antérieure du schéma, on évite le crash
    // (RangeError / TypeError) qui empêcherait toute l'app de démarrer.
    try {
      final fieldsCount = reader.readByte();
      final fields = <int, dynamic>{
        for (int i = 0; i < fieldsCount; i++) reader.readByte(): reader.read(),
      };

      // ── Lecture sécurisée de l'index AlertType ────────────────────
      AlertType safeAlertType(int? raw) {
        if (raw == null) return AlertType.danger; // fallback
        if (raw >= 0 && raw < AlertType.values.length) {
          return AlertType.values[raw];
        }
        return AlertType.danger;
      }

      // ── Lecture sécurisée de l'index AlertStatus ──────────────────
      AlertStatus safeAlertStatus(int? raw) {
        if (raw == null) return AlertStatus.active;
        if (raw >= 0 && raw < AlertStatus.values.length) {
          return AlertStatus.values[raw];
        }
        return AlertStatus.active;
      }

      return Alert(
        id: (fields[0] as String?) ?? '',
        ephemeralUserId: (fields[1] as String?) ?? '',
        signature: (fields[2] as String?) ?? '',
        type: safeAlertType(fields[3] as int?),
        latitude: (fields[4] as num?)?.toDouble() ?? 0.0,
        longitude: (fields[5] as num?)?.toDouble() ?? 0.0,
        description: (fields[6] as String?) ?? '',
        createdAt: (fields[7] as DateTime?) ?? DateTime.now().toUtc(),
        ttlHours: (fields[8] as int?) ?? 24,
        status: safeAlertStatus(fields[9] as int?),
        confirmations:
            ((fields[10] as List?) ?? const []).cast<String>().toSet(),
        uploadedTo: (fields[11] as String?) ?? '',
        lastModifiedAt: (fields[12] as DateTime?) ?? DateTime.now().toUtc(),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          '[AlertAdapter] Erreur de désérialisation : $e\n$st\n'
          '→ retour d\'une alerte vide (données corrompues).',
        );
      }
      // Retourne une alerte vide pour ne pas bloquer l'ouverture de la box.
      final now = DateTime.now().toUtc();
      return Alert(
        id: 'corrupted_${now.millisecondsSinceEpoch}',
        ephemeralUserId: 'corrupted',
        signature: 'corrupted',
        type: AlertType.danger,
        latitude: 0.0,
        longitude: 0.0,
        description: '⚠️ Données corrompues',
        createdAt: now,
        ttlHours: 1, // Expiration rapide pour auto-nettoyage
        status: AlertStatus.rejected,
        confirmations: const {},
        uploadedTo: '',
        lastModifiedAt: now,
      );
    }
  }

  @override
  void write(BinaryWriter writer, Alert obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.ephemeralUserId)
      ..writeByte(2)
      ..write(obj.signature)
      ..writeByte(3)
      ..write(obj.type.index)
      ..writeByte(4)
      ..write(obj.latitude)
      ..writeByte(5)
      ..write(obj.longitude)
      ..writeByte(6)
      ..write(obj.description)
      ..writeByte(7)
      ..write(obj.createdAt)
      ..writeByte(8)
      ..write(obj.ttlHours)
      ..writeByte(9)
      ..write(obj.status.index)
      ..writeByte(10)
      ..write(obj.confirmations.toList())
      ..writeByte(11)
      ..write(obj.uploadedTo)
      ..writeByte(12)
      ..write(obj.lastModifiedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlertAdapter && runtimeType == other.runtimeType;
}
