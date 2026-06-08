// lib/debug/client_debug_logger.dart
//
// Module de journalisation "ultra-lisible" pour le client
// Flutter StreetPhare, en mode débogage.
//
// Génère et maintient à jour (de façon atomique) un fichier
// `CLIENT_DEBUG.md` à la racine du projet. Le fichier retrace
// en temps réel :
//   - le serveur courant considéré comme "principal",
//   - l'évolution de la chaîne de secours (déchiffrée),
//   - les décisions de basculement (déchiffrement de
//     l'adresse secondaire, promotion, etc.),
//   - les uploads d'alertes et leurs résultats.
//
// Le tableau de bord utilise des émojis et des tableaux
// pour rester lisible d'un seul coup d'œil (idem
// SERVER_STATUS.md côté serveur).
//
// IMPORTANT : ce module n'écrit QUE si Flutter tourne en
// mode `kDebugMode`. En release, toutes les méthodes sont
// des no-op (zéro coût, zéro fuite d'info).
//
// Plateforme :
//   * Windows / Linux / macOS : on écrit dans le répertoire
//     de travail courant (souvent la racine du projet).
//   * Android / iOS / Web : pas d'accès à la racine, le
//     module bascule en mode "in-memory" (le contenu reste
//     accessible via `getSnapshot()`).
//     Le répertoire peut être forcé via `setOutputDirectory()`.

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Évènement de basculement / débogage.
class _ClientEvent {
  _ClientEvent({
    required this.ts,
    required this.level,
    required this.emoji,
    required this.label,
    required this.details,
  });
  final DateTime ts;
  final String level;
  final String emoji;
  final String label;
  final String details;
}

/// Étape de basculement (changement de serveur principal).
class _FailoverStep {
  _FailoverStep({
    required this.ts,
    required this.summary,
    required this.detail,
  });
  final DateTime ts;
  final String summary;
  final String detail;
}

/// Logger Markdown côté client.
class ClientDebugLogger {
  ClientDebugLogger._();
  static final ClientDebugLogger instance = ClientDebugLogger._();

  static const int _maxEvents = 60;
  static const int _maxSteps = 30;

  final Queue<_ClientEvent> _events = Queue<_ClientEvent>();
  final List<_FailoverStep> _steps = <_FailoverStep>[];

  /// Adresse du serveur principal courant (null si pas init).
  String? _primaryAddress;

  /// Chaîne de secours en clair (dans l'ordre d'utilisation).
  final List<MapEntry<String, String>> _backupChain = [];

  /// 'init' | 'ok' | 'failover' | 'degraded' | 'stopped'.
  String _globalState = 'init';

  String _platform = 'unknown';

  Directory? _outputDir;
  bool _fileWriteEnabled = true;

  Future<void> _writeQueue = Future.value();

  bool _initialized = false;

  /// Initialise le logger. À appeler tôt dans `main()` après
  /// `WidgetsFlutterBinding.ensureInitialized()`.
  /// No-op total en release.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (!kDebugMode) return;

    try {
      _platform = Platform.operatingSystem;
    } catch (_) {
      _platform = 'web-or-unknown';
    }

    if (_outputDir == null && _isDesktopPlatform(_platform)) {
      try {
        _outputDir = Directory.current;
      } catch (_) {
        _outputDir = null;
      }
    }

    if (_outputDir != null) {
      _emit('INFO', '🟢', 'Logger client initialisé', _platform);
    } else {
      _fileWriteEnabled = false;
      _emit(
        'INFO',
        'ℹ️',
        'Logger client (mémoire seule)',
        'Plateforme $_platform : pas d\'écriture fichier',
      );
    }
  }

  /// Force un répertoire de sortie (à appeler AVANT init()).
  void setOutputDirectory(Directory dir) {
    _outputDir = dir;
  }

  // ---------- API publique ----------

  /// Bootstrap réseau terminé (primaire + chaîne déchiffrée).
  void bootstrapReady({
    required String primaryAddress,
    required List<String> decryptedBackupChain,
  }) {
    _primaryAddress = primaryAddress;
    _backupChain
      ..clear()
      ..addAll(decryptedBackupChain
          .map((e) => MapEntry(e, _classifyBackupState(e))));
    _globalState = 'ok';
    _emit(
      'BOOT',
      '🧭',
      'Bootstrap réseau',
      'Principal=$primaryAddress, '
      'chaîne de secours=${decryptedBackupChain.length} entrée(s)',
    );
    _addStep(
      'Bootstrap terminé',
      'Principal verrouillé sur `$primaryAddress`. '
      '${decryptedBackupChain.length} serveur(s) de secours déchiffré(s).',
    );
    _scheduleWrite();
  }

  /// Heartbeat effectué (résultat ok/ko).
  void heartbeat({required String address, required bool ok}) {
    _emit(
      'PING',
      ok ? '💓' : '❌',
      ok ? 'Heartbeat OK' : 'Heartbeat KO',
      address,
    );
    _scheduleWrite();
  }

  /// Serveur marqué défaillant pour la session.
  void serverMarkedDead(String address) {
    _emit(
      'DEAD',
      '💀',
      'Serveur marqué défaillant',
      '$address (plus jamais retenté pour cette session)',
    );
    _scheduleWrite();
  }

  /// Adresse de backup chiffrée venant d'être déchiffrée.
  void backupDecrypted({required String cipher, required String clear}) {
    _emit(
      'DECRYPT',
      '🔓',
      'Adresse de backup déchiffrée',
      '`${_short(cipher)}` → `$clear`',
    );
    _scheduleWrite();
  }

  /// Basculement réussi.
  void failoverSucceeded({
    required String fromAddress,
    required String toAddress,
  }) {
    _primaryAddress = toAddress;
    _globalState = 'failover';
    _emit(
      'FAILOVER',
      '🔁',
      'Basculement réussi',
      '$fromAddress → $toAddress',
    );
    _addStep(
      'Basculement réussi',
      'Nouveau principal = `$toAddress`. '
      'L\'ancien `$fromAddress` est marqué DÉFAILLANT pour la session.',
    );
    _scheduleWrite();
  }

  /// Basculement impossible (aucun secours dispo).
  void failoverFailed({required String fromAddress}) {
    _globalState = 'degraded';
    _emit(
      'FAILOVER',
      '🛑',
      'Basculement impossible',
      'Aucun serveur de secours disponible (perdu depuis `$fromAddress`)',
    );
    _addStep(
      'Basculement impossible',
      'Tous les secours sont injoignables. L\'app reste '
      'connectée à `$fromAddress` (marqué défaillant) jusqu\'à '
      'relance de la session.',
    );
    _scheduleWrite();
  }

  /// Nouveau backup reçu du serveur, ajouté à la chaîne.
  void backupEnqueued({required String cipher, required String clear}) {
    _backupChain.add(MapEntry(clear, 'En veille'));
    _emit(
      'CHAIN',
      '➕',
      'Nouveau backup en queue',
      '`${_short(cipher)}` (déchiffré: `$clear`). '
      'Chaîne: ${_backupChain.length} entrée(s).',
    );
    _scheduleWrite();
  }

  /// Upload d'alertes tenté.
  void uploadAttempted({
    required String address,
    required int alertCount,
    required bool success,
    String? error,
  }) {
    _emit(
      'UPLOAD',
      success ? '📤' : '📤❌',
      success ? 'Upload alertes OK' : 'Upload alertes KO',
      success
          ? '$alertCount alerte(s) → $address'
          : '$alertCount alerte(s) → $address (${error ?? "erreur inconnue"})',
    );
    _scheduleWrite();
  }

  /// Évènement libre.
  void log(String label, {String? details, String emoji = 'ℹ️'}) {
    _emit('INFO', emoji, label, details ?? '');
    _scheduleWrite();
  }

  /// Snapshot du Markdown (utile pour UI, debug en mémoire).
  String getSnapshot() => _render();

  /// Attend la fin des écritures en cours.
  Future<void> flush() async {
    await _writeQueue;
  }

  // ---------- internes ----------

  bool _isDesktopPlatform(String p) {
    return p == 'windows' || p == 'linux' || p == 'macos';
  }

  String _classifyBackupState(String address) {
    if (_primaryAddress == address) return 'Actif';
    return 'En veille';
  }

  String _short(String s) {
    if (s.length <= 16) return s;
    return '${s.substring(0, 8)}…${s.substring(s.length - 6)}';
  }

  void _emit(String level, String emoji, String label, String details) {
    _events.addLast(_ClientEvent(
      ts: DateTime.now(),
      level: level,
      emoji: emoji,
      label: label,
      details: details,
    ));
    while (_events.length > _maxEvents) {
      _events.removeFirst();
    }
  }

  void _addStep(String summary, String detail) {
    _steps.add(_FailoverStep(
      ts: DateTime.now(),
      summary: summary,
      detail: detail,
    ));
    if (_steps.length > _maxSteps) {
      _steps.removeRange(0, _steps.length - _maxSteps);
    }
  }

  void _scheduleWrite() {
    if (!kDebugMode) return;
    if (!_initialized) return;
    _writeQueue = _writeQueue.then((_) => _writeNow()).catchError((Object e) {
      if (kDebugMode) {
        debugPrint('[ClientDebugLogger] écriture échouée: $e');
      }
    });
  }

  Future<void> _writeNow() async {
    if (!_fileWriteEnabled || _outputDir == null) return;
    final body = _render();
    final f = File(
      '${_outputDir!.path}${Platform.pathSeparator}CLIENT_DEBUG.md',
    );
    final tmp = File('${f.path}.tmp');
    try {
      await tmp.writeAsString(body, flush: true);
      await tmp.rename(f.path);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ClientDebugLogger] rename/write échoué: $e');
      }
    }
  }

  String _render() {
    final now = DateTime.now();
    String pad(int n) => n.toString().padLeft(2, '0');
    final nowStr =
        '${now.year}-${pad(now.month)}-${pad(now.day)} '
        '${pad(now.hour)}:${pad(now.minute)}:${pad(now.second)}';

    final stateIcon = switch (_globalState) {
      'ok' => '🟢',
      'failover' => '🔁',
      'degraded' => '🛑',
      'stopped' => '⚫',
      _ => '⚪',
    };
    final stateLabel = switch (_globalState) {
      'ok' => 'Connecté au principal',
      'failover' => 'Basculement effectué',
      'degraded' => 'Mode dégradé',
      'stopped' => 'Arrêté',
      _ => 'Initialisation',
    };

    final buf = StringBuffer();
    buf.writeln('# 🐛 Tableau de bord de Débogage Client - StreetPhare');
    buf.writeln();
    buf.writeln(
      '> Dernière mise à jour : **$nowStr** (heure locale). '
      'Ce fichier est généré par `lib/debug/client_debug_logger.dart` '
      'uniquement en mode `kDebugMode`.',
    );
    buf.writeln();
    buf.writeln('---');
    buf.writeln();

    // Statut global
    buf.writeln('## 🎯 Statut Global');
    buf.writeln();
    buf.writeln('| Plateforme | État | Serveur Principal Courant |');
    buf.writeln('| --- | --- | --- |');
    buf.writeln(
      '| $_platform | $stateIcon **$stateLabel** | '
      '`${_primaryAddress ?? "—"}` |',
    );
    buf.writeln();

    // Chaîne de secours
    buf.writeln('## 🔐 Chaîne de Secours (déchiffrée en mémoire)');
    buf.writeln();
    buf.writeln('| Position | Adresse (en clair) | Rôle |');
    buf.writeln('| --- | --- | --- |');
    if (_primaryAddress != null) {
      buf.writeln(
        '| ⭐ 0 (Principal) | `$_primaryAddress` | 🟢 **Actif** |',
      );
    }
    for (var i = 0; i < _backupChain.length; i++) {
      final entry = _backupChain[i];
      final roleIcon = entry.value == 'Actif' ? '⭐ Actif' : '🟡 En veille';
      buf.writeln('| ${i + 1} | `${entry.key}` | $roleIcon |');
    }
    if (_backupChain.isEmpty && _primaryAddress == null) {
      buf.writeln('| — | _(aucune)_ | — |');
    }
    buf.writeln();

    // Étapes de basculement
    buf.writeln('## 🔁 Étapes de Basculement (Décisions Client)');
    buf.writeln();
    if (_steps.isEmpty) {
      buf.writeln('> _Aucun basculement enregistré pour le moment._');
    } else {
      buf.writeln('| Heure | Étape | Détail |');
      buf.writeln('| --- | --- | --- |');
      for (var i = _steps.length - 1; i >= 0; i--) {
        final s = _steps[i];
        final h = '${pad(s.ts.hour)}:${pad(s.ts.minute)}:${pad(s.ts.second)}';
        buf.writeln('| $h | ${s.summary} | ${s.detail} |');
      }
    }
    buf.writeln();

    // Journal d'évènements
    buf.writeln('## 📜 Journal Temps Réel (Debug Client)');
    buf.writeln();
    buf.writeln('| Heure | Niveau | Évènement | Détails |');
    buf.writeln('| --- | --- | --- | --- |');
    if (_events.isEmpty) {
      buf.writeln('| — | ℹ️ INFO | _Aucun évènement_ | — |');
    } else {
      for (final ev in _events) {
        final h =
            '${pad(ev.ts.hour)}:${pad(ev.ts.minute)}:${pad(ev.ts.second)}';
        buf.writeln(
          '| $h | ${ev.emoji} ${ev.level} | ${ev.label} | '
          '${ev.details.isEmpty ? "—" : ev.details} |',
        );
      }
    }
    buf.writeln();
    buf.writeln('---');
    buf.writeln();
    buf.writeln(
      '> ℹ️ Pour suivre en direct : `tail -f CLIENT_DEBUG.md` '
      '(le fichier est réécrit à chaque évènement).',
    );
    buf.writeln();
    return buf.toString();
  }
}
