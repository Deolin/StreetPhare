// lib/network/mesh_outbox.dart
//
// Outbox persistante (Hive) pour la livraison fiable des messages P2P.
//
// Découple le transport (volatile : BLE / Wi-Fi / relay) de la donnée et de
// son état (persistant, idempotent, acquitté) — architecture Store-and-Forward.
//
// Chaque message sortant reçoit :
//   - un identifiant unique `id` (mid) ;
//   - un numéro de séquence croissant par émetteur `seq` ;
//   - un statut de livraison (pending → sent → acknowledged / failed).
// Tant qu'un message n'est pas acquitté par un pair (ACK applicatif), il
// reste dans l'outbox et est réémis selon un backoff progressif, borné en
// tentatives.

import 'dart:convert';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Statut de livraison d'un message dans l'outbox.
enum MeshOutboxStatus {
  pending,
  sent,
  acknowledged,
  failed,
}

/// Entrée de l'outbox persistante.
class MeshOutboxEntry {
  MeshOutboxEntry({
    required this.id,
    required this.kind,
    required this.seq,
    required this.from,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.status = MeshOutboxStatus.pending,
    required this.nextAttemptAt,
  });

  factory MeshOutboxEntry.fromJson(Map<String, dynamic> j) {
    final statusName = j['status'] as String? ?? 'pending';
    return MeshOutboxEntry(
      id: j['id'] as String? ?? '',
      kind: j['kind'] as String? ?? '',
      seq: (j['seq'] as num?)?.toInt() ?? 0,
      from: j['from'] as String? ?? '',
      payload: j['payload'] as String? ?? '',
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      attempts: (j['attempts'] as num?)?.toInt() ?? 0,
      status: MeshOutboxStatus.values.firstWhere(
        (s) => s.name == statusName,
        orElse: () => MeshOutboxStatus.pending,
      ),
      nextAttemptAt:
          DateTime.tryParse(j['nextAttemptAt'] as String? ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
    );
  }

  final String id;
  final String kind;
  final int seq;
  final String from;

  /// JSON interne (résultat de `jsonEncode` du map applicatif).
  final String payload;

  final DateTime createdAt;
  int attempts;
  MeshOutboxStatus status;
  DateTime nextAttemptAt;

  bool get isFinal =>
      status == MeshOutboxStatus.acknowledged ||
      status == MeshOutboxStatus.failed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'seq': seq,
        'from': from,
        'payload': payload,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'attempts': attempts,
        'status': status.name,
        'nextAttemptAt': nextAttemptAt.toUtc().toIso8601String(),
      };
}

/// Outbox persistante singleton (box Hive de chaînes JSON).
class MeshOutbox {
  MeshOutbox._();
  static final MeshOutbox instance = MeshOutbox._();

  static const String _boxName = 'streetphare_mesh_outbox_v1';
  static const String _seqKey = '__seq_counter__';
  static const String _keyPrefix = 'out_';

  Box<String>? _box;
  int _seq = 0;

  bool get isReady => _box != null;

  Future<void> init() async {
    if (_box != null) return;
    _box = await Hive.openBox<String>(_boxName);
    final raw = _box!.get(_seqKey);
    _seq = raw == null ? 0 : (int.tryParse(raw) ?? 0);
  }

  /// Numéro de séquence croissant par émetteur, persistant entre lancements.
  int nextSeq() {
    _seq += 1;
    _box?.put(_seqKey, '$_seq');
    return _seq;
  }

  Future<void> enqueue(MeshOutboxEntry entry) async {
    await _box?.put(_key(entry.id), jsonEncode(entry.toJson()));
  }

  /// Entrées éligibles à une (ré)émission maintenant.
  List<MeshOutboxEntry> due({DateTime? now}) {
    final box = _box;
    if (box == null) return const [];
    final ref = (now ?? DateTime.now()).toUtc();
    final out = <MeshOutboxEntry>[];
    for (final k in box.keys) {
      final key = k.toString();
      if (!key.startsWith(_keyPrefix)) continue;
      final raw = box.get(key);
      if (raw == null) continue;
      try {
        final e =
            MeshOutboxEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (e.isFinal) continue;
        if (e.nextAttemptAt.isAfter(ref)) continue;
        out.add(e);
      } catch (_) {
        // Entrée corrompue — ignorée.
      }
    }
    out.sort((a, b) => a.seq.compareTo(b.seq));
    return out;
  }

  /// Acquitte un message : livraison next-hop confirmée → retrait.
  Future<void> acknowledge(String id) async {
    await _box?.delete(_key(id));
  }

  Future<void> markFailed(String id) async {
    final e = _get(id);
    if (e == null) return;
    e.status = MeshOutboxStatus.failed;
    await _box?.put(_key(id), jsonEncode(e.toJson()));
  }

  /// Met à jour la tentative et l'échéance de réémission.
  Future<void> touch(
    String id, {
    required int attempts,
    required DateTime nextAttemptAt,
  }) async {
    final e = _get(id);
    if (e == null) return;
    e.attempts = attempts;
    e.nextAttemptAt = nextAttemptAt;
    e.status = MeshOutboxStatus.sent;
    await _box?.put(_key(id), jsonEncode(e.toJson()));
  }

  /// Hygiène : retire les entrées finales ou trop anciennes.
  Future<void> prune({Duration maxAge = const Duration(hours: 24)}) async {
    final box = _box;
    if (box == null) return;
    final cutoff = DateTime.now().toUtc().subtract(maxAge);
    final toRemove = <String>[];
    for (final k in box.keys) {
      final key = k.toString();
      if (!key.startsWith(_keyPrefix)) continue;
      final raw = box.get(key);
      if (raw == null) continue;
      try {
        final e =
            MeshOutboxEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (e.isFinal || e.createdAt.isBefore(cutoff)) {
          toRemove.add(key);
        }
      } catch (_) {
        toRemove.add(key);
      }
    }
    await Future.wait(toRemove.map((k) => box.delete(k)));
  }

  /// Nombre d'entrées en attente (non finales).
  int get pendingCount => due().length;

  /// Curseur générique persistant (utilisé pour le rattrapage seq serveur).
  int getCursor(String key) {
    final raw = _box?.get('__kv_$key');
    return raw == null ? 0 : (int.tryParse(raw) ?? 0);
  }

  Future<void> setCursor(String key, int value) async {
    await _box?.put('__kv_$key', '$value');
  }

  MeshOutboxEntry? _get(String id) {
    final box = _box;
    if (box == null) return null;
    final raw = box.get(_key(id));
    if (raw == null) return null;
    try {
      return MeshOutboxEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  String _key(String id) => '$_keyPrefix$id';
}
