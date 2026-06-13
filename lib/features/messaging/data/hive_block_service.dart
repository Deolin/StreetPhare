// lib/features/messaging/data/hive_block_service.dart
//
// Gestion locale des utilisateurs bloqués et des fils temporaires.
// Les UUID bloqués sont filtrés côté client uniquement (filtre local).

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/temp_thread.dart';

// Palette de couleurs pour les fils temporaires.
const _kThreadColors = [
  0xFFE91E63, // Rose
  0xFF9C27B0, // Violet
  0xFF3F51B5, // Indigo
  0xFF009688, // Teal
  0xFFFF5722, // Deep Orange
  0xFF795548, // Brown
];

class HiveBlockService extends ChangeNotifier {
  HiveBlockService._();
  static final HiveBlockService instance = HiveBlockService._();

  static const _kBlockedKey = 'hive_blocked_ids_v1';
  static const _kThreadDurationKey = 'hive_thread_duration_min_v1';

  final Set<String> _blockedIds = {};
  final List<TempThread> _threads = [];

  /// Durée des fils temporaires en minutes (configurable).
  int _threadDurationMinutes = 30;
  int get threadDurationMinutes => _threadDurationMinutes;

  SharedPreferences? _prefs;

  // ---------------------------------------------------------------------------
  // Chargement
  // ---------------------------------------------------------------------------

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getStringList(_kBlockedKey) ?? [];
    _blockedIds
      ..clear()
      ..addAll(raw);
    _threadDurationMinutes = _prefs!.getInt(_kThreadDurationKey) ?? 30;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Blocage
  // ---------------------------------------------------------------------------

  /// Bloque un utilisateur par son UUID éphémère.
  Future<void> blockUser(String ephemeralId) async {
    if (_blockedIds.contains(ephemeralId)) return;
    _blockedIds.add(ephemeralId);
    await _persistBlocked();
    notifyListeners();
    if (kDebugMode) debugPrint('[HiveBlock] Bloqué : $ephemeralId');
  }

  /// Débloque un utilisateur.
  Future<void> unblockUser(String ephemeralId) async {
    if (!_blockedIds.remove(ephemeralId)) return;
    await _persistBlocked();
    notifyListeners();
  }

  /// `true` si l'utilisateur est bloqué.
  bool isBlocked(String ephemeralId) => _blockedIds.contains(ephemeralId);

  Future<void> _persistBlocked() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setStringList(_kBlockedKey, _blockedIds.toList());
  }

  // ---------------------------------------------------------------------------
  // Configuration durée des fils
  // ---------------------------------------------------------------------------

  Future<void> setThreadDuration(int minutes) async {
    _threadDurationMinutes = minutes.clamp(5, 240);
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt(_kThreadDurationKey, _threadDurationMinutes);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Fils temporaires
  // ---------------------------------------------------------------------------

  /// Liste des fils actifs uniquement.
  List<TempThread> get activeThreads =>
      _threads.where((t) => t.isActive).toList();

  /// Crée un nouveau fil temporaire et y ajoute un participant initial.
  TempThread createThread({required String initialParticipantId}) {
    _pruneExpired();
    final id = _generateThreadId();
    final colorIdx = _threads.length % _kThreadColors.length;
    final thread = TempThread(
      id: id,
      createdAt: DateTime.now().toUtc(),
      durationMinutes: _threadDurationMinutes,
      participantIds: {initialParticipantId},
      color: _kThreadColors[colorIdx],
    );
    _threads.add(thread);
    notifyListeners();
    if (kDebugMode) {
      debugPrint('[HiveBlock] Fil temporaire créé : $id '
          '($_threadDurationMinutes min)');
    }
    return thread;
  }

  /// Ajoute un participant à un fil existant ou au premier fil actif.
  /// Retourne le fil modifié ou null si aucun fil actif.
  TempThread? addParticipant(String ephemeralId) {
    _pruneExpired();
    final actives = activeThreads;
    if (actives.isEmpty) return null;
    final thread = actives.first;
    final idx = _threads.indexWhere((t) => t.id == thread.id);
    if (idx == -1) return null;
    final updated = thread.copyWith(
      participantIds: {...thread.participantIds, ephemeralId},
    );
    _threads[idx] = updated;
    notifyListeners();
    return updated;
  }

  /// Retourne le fil actif auquel appartient un utilisateur (ou null).
  TempThread? threadForUser(String ephemeralId) {
    return activeThreads
        .where((t) => t.participantIds.contains(ephemeralId))
        .firstOrNull;
  }

  /// `true` si l'utilisateur est dans un fil actif.
  bool isInActiveThread(String ephemeralId) =>
      threadForUser(ephemeralId) != null;

  void _pruneExpired() {
    final before = _threads.length;
    _threads.removeWhere((t) => !t.isActive);
    if (_threads.length != before) notifyListeners();
  }

  static String _generateThreadId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(6, (_) => rng.nextInt(256));
    return 'th_${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
}
