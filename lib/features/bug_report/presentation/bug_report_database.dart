// lib/features/bug_report/presentation/bug_report_database.dart
//
// Base de données locale Hive pour les rapports de bug.
//
// Stratégie "Zéro Perte" :
//   1. Chaque rapport est stocké LOCALEMENT avant toute tentative d'envoi.
//   2. La suppression du stockage local n'a lieu QU'après confirmation
//      HTTP 200/201 du serveur (principe store-then-delete).
//   3. Les écritures sont try-catch blindées : un crash Hive ne doit
//      JAMAIS crasher l'application.
//   4. La file d'attente (queue) permet de retenter l'envoi plus tard
//      (backoff exponentiel géré par BugReportService).

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../../../database/crypto_utils.dart';

// ============================================================================
// Modèle persisté — BugReportEntry
// ============================================================================

/// Entrée de rapport de bug stockée dans Hive.
///
/// Contient toutes les données nécessaires pour recréer un [BugReport]
/// et suivre son cycle de vie (tentatives, dernière erreur, etc.).
class BugReportEntry {

  factory BugReportEntry.fromJson(Map<String, dynamic> json) {
    return BugReportEntry(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      platform: json['platform'] as String? ?? 'unknown',
      appVersion: json['app_version'] as String? ?? '0.0.0',
      extraLogs: json['extra_logs'] as String?,
      category: json['category'] as String? ?? 'bug',
      submittedAt: json['submitted_at'] as String?,
      attempts: json['attempts'] as int? ?? 0,
      lastError: json['last_error'] as String?,
      lastAttemptAt: json['last_attempt_at'] as String?,
    );
  }
  BugReportEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.platform,
    required this.appVersion,
    this.extraLogs,
    this.category = 'bug',
    this.submittedAt,
    this.attempts = 0,
    this.lastError,
    this.lastAttemptAt,
  });

  final String id;
  final String title;
  final String description;
  final String platform;
  final String appVersion;
  final String? extraLogs;
  final String category; // 'bug', 'suggestion', 'crash', 'performance'
  final String? submittedAt;
  int attempts;
  String? lastError;
  String? lastAttemptAt;

  /// Convertit en Map pour Hive et pour le corps HTTP.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'platform': platform,
        'app_version': appVersion,
        'category': category,
        'extra_logs': extraLogs,
        'submitted_at':
            submittedAt ?? DateTime.now().toUtc().toIso8601String(),
        'attempts': attempts,
        'last_error': lastError,
        'last_attempt_at': lastAttemptAt,
      };
}

// ============================================================================
// BugReportDatabase — Persistance locale Hive
// ============================================================================

/// Base de données singleton pour les rapports de bug.
///
/// Garantit que TOUS les rapports sont stockés localement avant
/// toute tentative d'envoi réseau.
class BugReportDatabase {
  BugReportDatabase._internal();
  static final BugReportDatabase instance = BugReportDatabase._internal();

  static const String _boxName = 'streetphare_bug_reports_v1';

  Box<String>? _box; // Stocke le JSON stringifié
  bool _initialized = false;

  /// Expose l'état d'initialisation.
  bool get isInitialized => _initialized && _box != null;

  /// Nombre de rapports en attente.
  int get pendingCount {
    if (_box == null) return 0;
    return _box!.length;
  }

  /// Initialise la box Hive dédiée aux rapports de bug.
  ///
  /// Doit être appelée après `Hive.initFlutter()` (dans main.dart).
  Future<void> init() async {
    if (_initialized) return;
    try {
      _box = await Hive.openBox<String>(_boxName);
      _initialized = true;
      if (kDebugMode) {
        debugPrint(
            '[BugReportDB] initialisée — ${_box!.length} rapport(s) en attente');
      }
    } catch (e) {
      // Ne crashe JAMAIS l'application si Hive est indisponible.
      if (kDebugMode) {
        debugPrint('[BugReportDB] ⚠ Échec initialisation : $e');
      }
    }
  }

  /// Insère un rapport dans la file d'attente locale.
  ///
  /// Retourne l'ID du rapport (utile pour le suivi).
  Future<String> enqueue(BugReportEntry entry) async {
    try {
      _ensureOpen();
      final id = entry.id.isEmpty ? randomId() : entry.id;
      final e = BugReportEntry(
        id: id,
        title: entry.title,
        description: entry.description,
        platform: entry.platform,
        appVersion: entry.appVersion,
        extraLogs: entry.extraLogs,
        category: entry.category,
        submittedAt:
            entry.submittedAt ?? DateTime.now().toUtc().toIso8601String(),
        attempts: entry.attempts,
        lastError: entry.lastError,
        lastAttemptAt: entry.lastAttemptAt,
      );
      await _box!.put(id, _encode(e));
      if (kDebugMode) {
        debugPrint(
            '[BugReportDB] ✅ Rapport "${e.title}" stocké (id=$id, total=${_box!.length})');
      }
      return id;
    } catch (e) {
      // Blindage anti-crash : on loggue mais on ne relance pas.
      if (kDebugMode) {
        debugPrint('[BugReportDB] ❌ Échec stockage rapport : $e');
      }
      return '';
    }
  }

  /// Récupère tous les rapports en attente d'envoi.
  List<BugReportEntry> getAllPending() {
    try {
      _ensureOpen();
      final entries = <BugReportEntry>[];
      for (final key in _box!.keys) {
        try {
          final raw = _box!.get(key);
          if (raw != null) {
            entries.add(_decode(raw));
          }
        } catch (_) {
          // Ignore les entrées corrompues.
        }
      }
      return entries;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BugReportDB] ⚠ Erreur lecture rapports : $e');
      }
      return [];
    }
  }

  /// Met à jour les métadonnées d'un rapport après une tentative d'envoi.
  Future<void> updateAttempt(String id,
      {required int attempts, String? lastError}) async {
    try {
      _ensureOpen();
      final raw = _box!.get(id);
      if (raw == null) return;
      final entry = _decode(raw);
      entry.attempts = attempts;
      entry.lastError = lastError;
      entry.lastAttemptAt = DateTime.now().toUtc().toIso8601String();
      await _box!.put(id, _encode(entry));
    } catch (e) {
      // Silencieux — mise à jour non critique.
    }
  }

  /// Supprime un rapport du stockage local (UNIQUEMENT après envoi réussi).
  Future<void> remove(String id) async {
    try {
      _ensureOpen();
      await _box!.delete(id);
      if (kDebugMode) {
        debugPrint(
            '[BugReportDB] 🗑️ Rapport $id supprimé (restants=${_box!.length})');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BugReportDB] ⚠ Échec suppression rapport $id : $e');
      }
    }
  }

  /// Nettoie les rapports abandonnés (plus de N tentatives).
  /// Retourne le nombre de rapports supprimés.
  Future<int> purgeAbandoned({int maxAttempts = 10}) async {
    try {
      _ensureOpen();
      int purged = 0;
      final toRemove = <String>[];
      for (final key in _box!.keys) {
        try {
          final raw = _box!.get(key);
          if (raw != null) {
            final entry = _decode(raw);
            if (entry.attempts >= maxAttempts) {
              toRemove.add(key);
            }
          }
        } catch (_) {
          // Entrée corrompue → à supprimer aussi.
          toRemove.add(key);
        }
      }
      for (final key in toRemove) {
        await _box!.delete(key);
        purged++;
      }
      if (purged > 0 && kDebugMode) {
        debugPrint('[BugReportDB] 🧹 $purged rapport(s) abandonné(s) purgé(s)');
      }
      return purged;
    } catch (e) {
      return 0;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  void _ensureOpen() {
    if (_box == null) {
      throw StateError('BugReportDatabase non initialisé. Appelez init() d\'abord.');
    }
  }

  static String _encode(BugReportEntry entry) {
    // Utilise un encodage simple (pas de chiffrement) car les rapports
    // de bug ne contiennent pas de données sensibles.
    return '${entry.id}\n${entry.title}\n${entry.description}\n${entry.platform}\n${entry.appVersion}\n${entry.category}\n${entry.submittedAt ?? ''}\n${entry.attempts}\n${entry.lastError ?? ''}\n${entry.lastAttemptAt ?? ''}\n${entry.extraLogs ?? ''}';
  }

  static BugReportEntry _decode(String raw) {
    final parts = raw.split('\n');
    return BugReportEntry(
      id: parts.isNotEmpty ? parts[0] : '',
      title: parts.length > 1 ? parts[1] : '',
      description: parts.length > 2 ? parts[2] : '',
      platform: parts.length > 3 ? parts[3] : 'unknown',
      appVersion: parts.length > 4 ? parts[4] : '0.0.0',
      category: parts.length > 5 ? parts[5] : 'bug',
      submittedAt: parts.length > 6 ? parts[6] : '',
      attempts: parts.length > 7 ? int.tryParse(parts[7]) ?? 0 : 0,
      lastError: parts.length > 8 ? parts[8] : null,
      lastAttemptAt: parts.length > 9 ? parts[9] : null,
      extraLogs: parts.length > 10 ? parts.sublist(10).join('\n') : null,
    );
  }
}