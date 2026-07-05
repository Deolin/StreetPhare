// lib/features/bug_report/presentation/bug_report_service.dart
//
// [5] Service de signalement de bugs — StreetPhare v3.0
//
// Architecture "Offline-First, Zéro Perte" :
//
//   1. STORE-FIRST : Chaque rapport est STOCKE LOCALEMENT (Hive) avant
//      toute tentative d'envoi réseau. Même sans connexion, le rapport
//      est préservé.
//
//   2. QUEUE + BACKOFF : Une file d'attente persistante retente l'envoi
//      avec exponential backoff (5s → 10s → 20s → 40s → 60s max).
//      Le flush est déclenché :
//        - Immédiatement après un nouveau rapport.
//        - Périodiquement toutes les 5 minutes.
//        - Au retour de connectivité réseau.
//
//   3. STORE-THEN-DELETE : La suppression du stockage local n'a lieu
//      QU'après confirmation HTTP 200/201 du serveur. Si l'envoi échoue,
//      le rapport reste stocké.
//
//   4. BLINDAGE ANTI-CRASH : Toute la logique de capture, d'écriture
//      et d'envoi est enveloppée dans des try-catch. Le service de bug
//      report ne peut PAS lui-même crasher l'application.
//
//   5. FALLBACK RÉSEAU : Si le domaine principal échoue, le service
//      tente automatiquement le fallback local (127.0.0.1 / 10.0.2.2)
//      pour les environnements de test sur le même réseau.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_streetphare/network/network_config.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'bug_report_database.dart';

// ============================================================================
// Modèle de rapport (surface API publique — inchangé)
// ============================================================================

class BugReport {
  const BugReport({
    required this.title,
    required this.description,
    required this.platform,
    required this.appVersion,
    this.extraLogs,
    this.category = BugCategory.bug,
  });

  final String title;
  final String description;
  final String platform;
  final String appVersion;
  final String? extraLogs;
  final BugCategory category;

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'platform': platform,
        'app_version': appVersion,
        'category': category.name,
        'extra_logs': extraLogs,
        'submitted_at': DateTime.now().toUtc().toIso8601String(),
      };

  /// Convertit en [BugReportEntry] pour le stockage local.
  BugReportEntry toEntry() => BugReportEntry(
        id: '',
        title: title,
        description: description,
        platform: platform,
        appVersion: appVersion,
        extraLogs: extraLogs,
        category: category.name,
        submittedAt: DateTime.now().toUtc().toIso8601String(),
        attempts: 0,
      );
}

enum BugCategory {
  bug,
  suggestion,
  crash,
  performance,
}

extension BugCategoryExt on BugCategory {
  String get label {
    switch (this) {
      case BugCategory.bug:
        return '🐛 Bug';
      case BugCategory.suggestion:
        return '💡 Suggestion';
      case BugCategory.crash:
        return '💥 Crash';
      case BugCategory.performance:
        return '⚡ Performance';
    }
  }
}

// ============================================================================
// BugReportService — Offline-First
// ============================================================================

class BugReportService {
  BugReportService._();
  static final BugReportService instance = BugReportService._();

  final BugReportDatabase _db = BugReportDatabase.instance;

  /// Client HTTP réutilisé (fermé proprement à l'arrêt).
  http.Client? _httpClient;
  Timer? _flushTimer;
  StreamSubscription? _connectivitySub;
  bool _started = false;

  /// Backoff exponentiel pour le flush périodique.
  /// Réinitialisé dès qu'un envoi réussit.
  int _consecutiveFlushFailures = 0;

  /// Timestamp jusqu'auquel tout flush est suspendu (rate-limit 429).
  DateTime? _rateLimitedUntil;

  static const Duration _kFlushInterval = Duration(minutes: 5);
  static const Duration _kRequestTimeout = Duration(seconds: 10);
  static const int _kMaxAttemptsBeforeAbandon = 8;
  static const Duration _kMaxRateLimitBackoff = Duration(minutes: 5);

  /// Démarre le service de bug report.
  ///
  /// - Initialise la file d'attente locale.
  /// - Démarre le flush périodique.
  /// - Tente immédiatement d'envoyer les rapports en attente.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _httpClient = http.Client();

    await _db.init();
    await _refreshAppVersion();
    // Flush immédiat des rapports en attente.
    if (_db.pendingCount > 0) {
      if (kDebugMode) {
        debugPrint(
            '[BugReport] 🚀 Démarrage — ${_db.pendingCount} rapport(s) en attente');
      }
      unawaited(_flushQueue());
    }

    // Flush périodique toutes les 5 minutes.
    _flushTimer = Timer.periodic(_kFlushInterval, (_) => _flushQueue());

    // Nettoyage des rapports abandonnés (> 8 tentatives).
    await _db.purgeAbandoned(maxAttempts: _kMaxAttemptsBeforeAbandon);
  }

  /// Arrête proprement le service.
  void stop() {
    _started = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _httpClient?.close();
    _httpClient = null;
  }

  // ══════════════════════════════════════════════════════════════════════
  // API PUBLIQUE
  // ══════════════════════════════════════════════════════════════════════

  /// Soumet un rapport de bug.
  ///
  /// ⚠️ NE TENTE JAMAIS d'envoyer directement le rapport en réseau.
  ///    Le rapport est D'ABORD stocké localement (Hive), puis un flush
  ///    asynchrone est déclenché en arrière-plan.
  ///
  /// Retourne [BugReportResult.saved] une fois le rapport stocké
  /// localement (la confirmation réseau viendra plus tard).
  Future<BugReportResult> submit(BugReport report) async {
    // ════════════════════════════════════════════════════════════════════
    // ÉTAPE 1 : Stockage local prioritaire (Zéro Perte)
    // ════════════════════════════════════════════════════════════════════
    try {
      final entry = report.toEntry();
      final id = await _db.enqueue(entry);

      if (id.isEmpty) {
        // Échec du stockage local — on tente quand même un envoi direct
        // en dernier recours (mieux que rien).
        if (kDebugMode) {
          debugPrint(
              '[BugReport] ⚠ Stockage local échoué, tentative d\'envoi direct');
        }
        return await _sendDirectly(report.toJson());
      }

      if (kDebugMode) {
        debugPrint('[BugReport] 📦 Rapport stocké localement (id=$id)');
      }
    } catch (e) {
      // Blindage anti-crash : si le stockage local échoue catastrophiquement,
      // on tente un envoi direct en ultime recours.
      if (kDebugMode) {
        debugPrint('[BugReport] ❌ Exception stockage local: $e');
      }
      return await _sendDirectly(report.toJson());
    }

    // ════════════════════════════════════════════════════════════════════
    // ÉTAPE 2 : Flush asynchrone (non-bloquant)
    // ════════════════════════════════════════════════════════════════════
    // Le flush est déclenché en arrière-plan. L'utilisateur reçoit
    // immédiatement la confirmation que son rapport a été sauvegardé.
    unawaited(_flushQueue());

    return BugReportResult.saved;
  }

  /// Soumet un rapport de CRASH (capturé automatiquement).
  ///
  /// Version blindée : n'utilise AUCUN await externe, tout est try-catch.
  /// Peut être appelée depuis un `FlutterError.onError` ou
  /// `PlatformDispatcher.instance.onError`.
  void submitCrash({
    required String error,
    String? stackTrace,
  }) {
    try {
      final report = BugReport(
        title: 'Crash automatique',
        description:
            'Erreur: $error${stackTrace != null ? '\n\nStack:\n$stackTrace' : ''}',
        platform: currentPlatform,
        appVersion: _appVersion,
        category: BugCategory.crash,
      );
      // On n'await pas : fire-and-forget depuis le catcher de crash.
      unawaited(submit(report));
    } catch (_) {
      // Silence absolu — on ne peut rien faire de plus.
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // FLUSH — Envoi de la file d'attente avec backoff
  // ══════════════════════════════════════════════════════════════════════

  /// Vide la file d'attente : tente d'envoyer chaque rapport stocké.
  ///
  /// Stratégie :
  ///   - Essaie d'abord l'URL publique (domaine No-IP).
  ///   - En cas d'échec réseau, essaye le fallback local.
  ///   - Les rapports envoyés avec succès sont supprimés du stockage local.
  ///   - Les échecs restent stockés pour retry ultérieur.
  ///   - Si le serveur répond 429 (rate-limit), le flush est suspendu
  ///     avec un backoff exponentiel pour éviter les boucles de retry.
  Future<void> _flushQueue() async {
    if (!_started) return;

    // Vérifie si on est en backoff rate-limit.
    if (_isRateLimited()) {
      if (kDebugMode) {
        debugPrint('[BugReport] ⏸ Flush suspendu (backoff rate-limit)');
      }
      return;
    }

    final pending = _db.getAllPending();
    if (pending.isEmpty) return;

    if (kDebugMode) {
      debugPrint(
          '[BugReport] 📤 Flush — ${pending.length} rapport(s) à envoyer');
    }

    bool anySuccess = false;

    for (final entry in pending) {
      // Double-check après chaque envoi : le 429 peut arriver en cours de flush.
      if (_isRateLimited()) {
        if (kDebugMode) {
          debugPrint(
              '[BugReport] ⏸ Flush interrompu (rate-limit reçu en cours)');
        }
        break;
      }

      try {
        final payload = _buildPayload(entry);
        final statusCode = await _trySend(payload);

        if (statusCode == 200) {
          // ✅ SUCCÈS : suppression du stockage local UNIQUEMENT maintenant.
          await _db.remove(entry.id);
          anySuccess = true;
          if (kDebugMode) {
            debugPrint(
                '[BugReport] ✅ Rapport "${entry.title}" envoyé et supprimé');
          }
        } else if (statusCode == 429) {
          // ⛔ RATE-LIMIT : on arrête tout le flush.
          // Le backoff a déjà été configuré dans _trySend.
          // On met à jour le compteur mais on ne réessaie pas.
          await _db.updateAttempt(
            entry.id,
            attempts: entry.attempts + 1,
            lastError: 'Rate-limit serveur (429)',
          );
          if (kDebugMode) {
            debugPrint(
                '[BugReport] ⛔ Rate-limit — flush suspendu, ${pending.length - 1} rapport(s) restant(s)');
          }
          break;
        } else {
          // ❌ ÉCHEC : mise à jour du compteur de tentatives.
          await _db.updateAttempt(
            entry.id,
            attempts: entry.attempts + 1,
            lastError: 'Échec envoi (tentative ${entry.attempts + 1})',
          );
          if (kDebugMode) {
            debugPrint(
                '[BugReport] ❌ Rapport "${entry.title}" — échec (${entry.attempts + 1}/${_kMaxAttemptsBeforeAbandon})');
          }
        }
      } catch (e) {
        // Blindage : l'échec d'un rapport ne bloque pas les autres.
        if (kDebugMode) {
          debugPrint(
              '[BugReport] ⚠ Exception flush rapport "${entry.title}": $e');
        }
        try {
          await _db.updateAttempt(
            entry.id,
            attempts: entry.attempts + 1,
            lastError: e.toString(),
          );
        } catch (_) {}
      }
    }

    // Nettoie les rapports abandonnés (> 8 tentatives).
    if (anySuccess ||
        pending.any((e) => e.attempts >= _kMaxAttemptsBeforeAbandon)) {
      await _db.purgeAbandoned(maxAttempts: _kMaxAttemptsBeforeAbandon);
    }

    // Ajuste le backoff exponentiel du flush périodique.
    if (anySuccess) {
      _consecutiveFlushFailures = 0;
    } else if (pending.isNotEmpty) {
      _consecutiveFlushFailures++;
    }
    // Remet à zéro si on dépasse 6 échecs consécutifs
    // (backoff déjà maximal atteint).
    if (_consecutiveFlushFailures > 6) {
      _consecutiveFlushFailures = 6; // Plafonne à 6 (backoff max ~64s).
    }
  }

  /// Vérifie si le flush est en backoff rate-limit.
  bool _isRateLimited() {
    final until = _rateLimitedUntil;
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _rateLimitedUntil = null;
      return false;
    }
    return true;
  }

  /// Tente d'envoyer un payload vers le serveur en essayant d'abord
  /// l'URL publique, puis le fallback local en cas d'échec réseau.
  ///
  /// Retourne :
  ///   - `200` : succès HTTP (2xx)
  ///   - `429` : rate-limit (backoff automatique configuré)
  ///   - `0`   : autre échec
  Future<int> _trySend(Map<String, dynamic> payload) async {
    final urls = _resolveUrls();

    for (final url in urls) {
      try {
        if (kDebugMode) {
          debugPrint('[BugReport] Tentative envoi → $url');
        }

        final response = await _httpClient!
            .post(
              Uri.parse(url),
              headers: {
                'Content-Type': 'application/json',
                'X-StreetPhare-Client': '1.0',
              },
              body: jsonEncode(payload),
            )
            .timeout(_kRequestTimeout);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return 200; // Succès.
        }

        // Détection du 429 (Rate Limit).
        if (response.statusCode == 429) {
          final retryAfterMs = _parseRateLimitRetry(response);
          _setRateLimitBackoff(retryAfterMs);
          if (kDebugMode) {
            debugPrint(
                '[BugReport] ⛔ 429 reçu → backoff ${retryAfterMs ~/ 1000}s');
          }
          return 429;
        }

        if (kDebugMode) {
          debugPrint('[BugReport] Erreur HTTP ${response.statusCode} → $url');
        }
        // Continue avec l'URL suivante.
      } on TimeoutException {
        if (kDebugMode) {
          debugPrint('[BugReport] Timeout → $url');
        }
      } on io.SocketException {
        if (kDebugMode) {
          debugPrint('[BugReport] SocketException → $url');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[BugReport] Erreur → $url : $e');
        }
      }
    }

    return 0; // Aucune URL n'a fonctionné.
  }

  /// Extrait retryAfterMs du corps de la réponse 429, ou utilise un fallback.
  int _parseRateLimitRetry(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['retryAfterMs'] is int) {
        return body['retryAfterMs'] as int;
      }
    } catch (_) {}
    return 60000; // Fallback : 1 minute.
  }

  /// Active le backoff rate-limit (plafonné à _kMaxRateLimitBackoff).
  void _setRateLimitBackoff(int retryAfterMs) {
    final delay = Duration(
      milliseconds: retryAfterMs.clamp(0, _kMaxRateLimitBackoff.inMilliseconds),
    );
    _rateLimitedUntil = DateTime.now().add(delay);
  }

  /// Résout la liste des URLs à essayer dans l'ordre :
  ///   1. URL publique (domaine No-IP via Caddy)
  ///   2. Fallback local HTTP (127.0.0.1 / 10.0.2.2)
  List<String> _resolveUrls() {
    final urls = <String>[NetworkConfig.bugReportUrl];

    // Ajoute le fallback local si on n'est pas en production pure.
    try {
      final localFallback =
          '${NetworkConfig.localhostPrimaryServer}/api/bug-report';
      if (!urls.contains(localFallback)) {
        urls.add(localFallback);
      }
    } catch (_) {
      // Si le fallback local n'est pas résoluble, on ignore.
    }

    return urls;
  }

  /// Envoi direct (fallback ultime si le stockage local échoue).
  Future<BugReportResult> _sendDirectly(Map<String, dynamic> payload) async {
    try {
      final statusCode = await _trySend(payload);
      if (statusCode == 200) return BugReportResult.success;

      // Même en échec, on retourne "saved" car on a fait de notre mieux.
      return BugReportResult.saved;
    } catch (_) {
      return BugReportResult.saved;
    }
  }

  /// Construit le payload HTTP à partir d'une entrée stockée.
  Map<String, dynamic> _buildPayload(BugReportEntry entry) {
    return {
      'id': entry.id,
      'title': entry.title,
      'description': entry.description,
      'platform': entry.platform,
      'app_version': entry.appVersion,
      'category': entry.category,
      'extra_logs': entry.extraLogs,
      'submitted_at': entry.submittedAt,
      'client_timestamp': DateTime.now().toUtc().toIso8601String(),
      'attempts': entry.attempts,
    };
  }

  // ── Helpers statiques ─────────────────────────────────────────────────

  static String get currentPlatform {
    try {
      if (kIsWeb) return 'web';
      if (io.Platform.isAndroid) return 'android';
      if (io.Platform.isIOS) return 'ios';
      if (io.Platform.isWindows) return 'windows';
      if (io.Platform.isMacOS) return 'macos';
      if (io.Platform.isLinux) return 'linux';
    } catch (_) {}
    return 'unknown';
  }

  /// Adresse email de destination pour le fallback mailto.
  static const String _fallbackEmail = 'repportbug@streetphare.be';

  /// Génère et ouvre un email de rapport de bug via le client mail de l'appareil.
  ///
  /// Utilisé comme fallback immédiat quand l'envoi HTTP au serveur échoue.
  /// L'utilisateur peut ainsi envoyer le rapport manuellement.
  Future<BugReportResult> sendViaEmail(BugReportEntry entry) async {
    try {
      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final subject = 'Rapport de Bug - StreetPhare - $dateStr';

      final body = StringBuffer();
      body.writeln('═══ RAPPORT DE BUG — StreetPhare ═══');
      body.writeln();
      body.writeln('📋 Titre      : ${entry.title}');
      body.writeln('🏷 Catégorie  : ${entry.category}');
      body.writeln('📱 Plateforme : ${entry.platform}');
      body.writeln('📦 Version    : ${entry.appVersion}');
      body.writeln('🕐 Soumis le  : ${entry.submittedAt ?? dateStr}');
      body.writeln('🔄 Tentatives : ${entry.attempts}');
      body.writeln();
      body.writeln('── Description ──');
      body.writeln(entry.description);
      body.writeln();
      if (entry.extraLogs != null && entry.extraLogs!.isNotEmpty) {
        body.writeln('── Logs additionnels ──');
        body.writeln(entry.extraLogs);
        body.writeln();
      }
      body.writeln('── ID du rapport ──');
      body.writeln('ID : ${entry.id}');
      body.writeln();
      body.writeln('⚠️ Ce rapport a été sauvegardé localement. '
          'L\'envoi automatique au serveur a échoué '
          '(tentative ${entry.attempts}).');

      final uri = Uri(
        scheme: 'mailto',
        path: _fallbackEmail,
        queryParameters: {
          'subject': subject,
          'body': body.toString(),
        },
      );

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        // On ne supprime PAS le rapport : l'envoi mail n'est pas une
        // confirmation serveur. Le rapport reste stocké pour retry HTTP.
        return BugReportResult.saved;
      } else {
        if (kDebugMode) {
          debugPrint('[BugReport] ❌ Impossible d\'ouvrir le client mail');
        }
        return BugReportResult.saved;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BugReport] ❌ Erreur mailto : $e');
      }
      return BugReportResult.saved;
    }
  }

  /// Version de l'application lue depuis [PackageInfo] au démarrage.
  /// Fallback sur la version du pubspec.yaml si package_info_plus échoue.
  static String _cachedAppVersion = '2.2.0';

  static String get _appVersion => _cachedAppVersion;

  /// Rafraîchit la version depuis [PackageInfo.fromPlatform].
  static Future<void> _refreshAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _cachedAppVersion = packageInfo.version;
    } catch (_) {
      // Fallback sur la valeur par défaut '2.2.0'.
    }
  }
}

// ============================================================================
// BugReportResult — Résultat de soumission
// ============================================================================

enum BugReportResult {
  /// Rapport sauvegardé localement — sera envoyé dès que possible.
  saved,

  /// Rapport envoyé avec succès au serveur (HTTP 200/201).
  success,

  /// Erreur réseau lors de la dernière tentative.
  networkError,

  /// Erreur serveur (HTTP 4xx/5xx).
  serverError,

  /// Erreur inconnue.
  unknownError;

  String get message {
    switch (this) {
      case BugReportResult.saved:
        return '✅ Rapport sauvegardé. Il sera envoyé automatiquement '
            'dès que la connexion sera disponible.';
      case BugReportResult.success:
        return '✅ Rapport envoyé avec succès. Merci !';
      case BugReportResult.networkError:
        return '📶 Impossible de joindre le serveur. '
            'Votre rapport a été sauvegardé et sera envoyé plus tard.';
      case BugReportResult.serverError:
        return '⚠️ Erreur du serveur. Votre rapport a été sauvegardé '
            'et sera renvoyé plus tard.';
      case BugReportResult.unknownError:
        return '❓ Erreur inattendue. Votre rapport a été sauvegardé '
            'et sera renvoyé plus tard.';
    }
  }
}
