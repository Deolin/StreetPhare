// lib/services/app_share_service.dart
//
// Service d'extraction et de partage de l'APK de StreetPhare via la feuille
// de partage système (Bluetooth, Proximité, etc.) sans dépendance aux stores.
// v2.2.0 — Compatible Android 15+

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../features/events/domain/models/event_model.dart';
import '../features/events/presentation/event_manager.dart';
import 'apk_backup_service.dart';

/// Résultat du décodage d'un lien de partage ou payload QR StreetPhare.
class ParsedShareInvite {
  const ParsedShareInvite({
    this.code,
    this.session,
    this.eventData,
  });

  final String? code;
  final String? session;
  final Map<String, dynamic>? eventData;
}

/// Service responsable de la localisation de l'APK de l'application et de son
/// partage via la feuille de partage native Android.
///
/// Le service est instancié à la demande (lazy), sans impact sur le démarrage.
class AppShareService {
  AppShareService._();

  static final AppShareService instance = AppShareService._();

  static const String packageName = 'com.example.flutter_streetphare';
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=$packageName';
  static const String shareBaseUrl = String.fromEnvironment(
    'STREETPHARE_SHARE_BASE_URL',
    defaultValue: 'https://streetphare.ddns.net',
  );

  static const MethodChannel _deepLinkChannel =
      MethodChannel('streetphare/deeplink');

  bool _deepLinksInitialized = false;

  // --------------------------------------------------------------------------
  // Deep Linking & Liens d'invitation d'événement / session
  // --------------------------------------------------------------------------

  /// Construit le lien universel de partage d'un événement/session.
  /// Ce lien transmet l'intégralité des données de l'événement (`data` en base64url)
  /// et redirige vers le Google Play Store si l'application n'est pas installée.
  String buildEventShareUrl(
    EventModel event, {
    String? sessionId,
    String? baseUrlOverride,
  }) {
    final base = baseUrlOverride ?? shareBaseUrl;
    final jsonBytes = utf8.encode(jsonEncode(event.toJson()));
    final encodedData = base64Url.encode(jsonBytes);
    final queryParams = <String, String>{
      'code': event.code.toUpperCase(),
      'data': encodedData,
      if (sessionId != null && sessionId.isNotEmpty) 'session': sessionId,
    };
    final baseUri = Uri.parse(base);
    return baseUri
        .replace(
          path: '${baseUri.path.replaceAll(RegExp(r'/$'), '')}/invite',
          queryParameters: queryParams,
        )
        .toString();
  }

  /// Construit le Deep Link natif `streetphare://invite?code=...&data=...`.
  String buildEventDeepLink(EventModel event, {String? sessionId}) {
    final jsonBytes = utf8.encode(jsonEncode(event.toJson()));
    final encodedData = base64Url.encode(jsonBytes);
    final queryParams = <String, String>{
      'code': event.code.toUpperCase(),
      'data': encodedData,
      if (sessionId != null && sessionId.isNotEmpty) 'session': sessionId,
    };
    return Uri(
      scheme: 'streetphare',
      host: 'invite',
      queryParameters: queryParams,
    ).toString();
  }

  /// Construit l'URL de fallback Google Play Store avec le referrer contenant
  /// le code de l'événement/session pour récupération après installation.
  String buildPlayStoreFallbackUrl({String? eventCode, String? sessionId}) {
    final refParts = <String>[
      if (eventCode != null && eventCode.isNotEmpty)
        'code=${eventCode.toUpperCase()}',
      if (sessionId != null && sessionId.isNotEmpty) 'session=$sessionId',
      'utm_source=streetphare_share',
    ];
    final referrer = Uri.encodeComponent(refParts.join('&'));
    return '$playStoreUrl&referrer=$referrer';
  }

  /// Décode aussi bien :
  ///   - un JSON brut d'événement (`{ "code": "...", ... }`),
  ///   - une URL web d'invitation (`https://.../invite?code=...&data=...`),
  ///   - un Deep Link (`streetphare://invite?code=...&data=...`).
  ParsedShareInvite? parseSharedLinkOrPayload(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // 1. JSON brut (ex: QR Code direct)
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          return ParsedShareInvite(
            code: decoded['code']?.toString().toUpperCase(),
            session: decoded['session']?.toString(),
            eventData: decoded,
          );
        }
      } catch (_) {}
    }

    // 2. URI (streetphare://invite?... ou https://.../invite?...)
    final uri = Uri.tryParse(trimmed);
    if (uri != null &&
        (uri.scheme == 'streetphare' ||
            uri.scheme == 'http' ||
            uri.scheme == 'https')) {
      final code = uri.queryParameters['code']?.trim().toUpperCase();
      final session = uri.queryParameters['session']?.trim();
      final rawData = uri.queryParameters['data']?.trim();

      Map<String, dynamic>? eventData;
      if (rawData != null && rawData.isNotEmpty) {
        try {
          final normalized = base64Url.normalize(rawData);
          final jsonStr = utf8.decode(base64Url.decode(normalized));
          final parsed = jsonDecode(jsonStr);
          if (parsed is Map<String, dynamic>) {
            eventData = parsed;
          }
        } catch (_) {}
      }

      if (code != null || eventData != null) {
        return ParsedShareInvite(
          code: code ?? eventData?['code']?.toString().toUpperCase(),
          session: session,
          eventData: eventData,
        );
      }
    }

    return null;
  }

  /// Initialise l'écoute des Deep Links entrants (`streetphare/deeplink`).
  Future<void> initDeepLinks() async {
    if (_deepLinksInitialized) return;
    _deepLinksInitialized = true;

    _deepLinkChannel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink') {
        final link = call.arguments as String?;
        if (link != null && link.isNotEmpty) {
          await handleIncomingDeepLink(link);
        }
      }
    });

    try {
      final initialLink =
          await _deepLinkChannel.invokeMethod<String>('getInitialLink');
      if (initialLink != null && initialLink.isNotEmpty) {
        await handleIncomingDeepLink(initialLink);
      }
    } catch (_) {
      // Canal non disponible (Desktop / Web / Tests).
    }
  }

  /// Traite un lien d'invitation entrant et charge l'événement dans [EventManager].
  Future<bool> handleIncomingDeepLink(String rawLink) async {
    final parsed = parseSharedLinkOrPayload(rawLink);
    if (parsed == null) return false;

    if (parsed.eventData != null) {
      final ok = await EventManager.instance.addFromSource(parsed.eventData!);
      if (ok) return true;
    }
    if (parsed.code != null && parsed.code!.isNotEmpty) {
      return EventManager.instance.loadByCode(parsed.code!);
    }
    return false;
  }

  /// Partage un événement/session via la feuille de partage système avec lien
  /// d'invitation et fallback Google Play Store.
  Future<bool> shareEventInvite(
    EventModel event, {
    BuildContext? context,
    String? sessionId,
  }) async {
    try {
      final inviteUrl = buildEventShareUrl(event, sessionId: sessionId);
      final storeUrl = buildPlayStoreFallbackUrl(
        eventCode: event.code,
        sessionId: sessionId,
      );
      await SharePlus.instance.share(
        ShareParams(
          subject: 'StreetPhare — Rejoindre "${event.title}" (${event.code})',
          text: 'Rejoignez l\'événement "${event.title}" sur StreetPhare !\n'
              'Code d\'invitation : ${event.code}\n'
              'Lien direct : $inviteUrl\n'
              'Télécharger sur Google Play : $storeUrl',
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[AppShareService] Erreur partage événement : $e');
      if (context != null && context.mounted) {
        _showError(context, 'Erreur lors du partage du lien : $e');
      }
      return false;
    }
  }

  /// Partage le lien général de l'application (avec redirection Play Store).
  Future<bool> shareAppLink({BuildContext? context}) async {
    try {
      final activeEvent = EventManager.instance.activeEvent;
      if (activeEvent != null) {
        return shareEventInvite(activeEvent, context: context);
      }
      final storeUrl = buildPlayStoreFallbackUrl();
      await SharePlus.instance.share(
        ShareParams(
          subject: 'StreetPhare — Application de cartographie citoyenne',
          text:
              'Téléchargez StreetPhare (cartographie citoyenne collaborative) :\n'
              '$storeUrl',
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[AppShareService] Erreur partage lien app : $e');
      return false;
    }
  }

  // --------------------------------------------------------------------------
  // Partager l'APK
  // --------------------------------------------------------------------------

  /// Tente de localiser l'APK installé de l'application et l'ouvre dans la
  /// feuille de partage système.
  ///
  /// Retourne `true` si le partage a été déclenché avec succès, `false` sinon.
  /// Affiche un [SnackBar] en cas d'erreur si [context] est fourni.
  ///
  /// Stratégie de localisation (Android, par priorité) :
  ///   1. Canal natif `getSourceApkPath` → `ApplicationInfo.sourceDir`.
  ///      Fiable sur toutes les versions Android, ne nécessite pas root.
  ///   2. Sauvegarde locale via [ApkBackupService] (copie dans Documents).
  ///   3. Scan du répertoire `/data/app/` (fallback hérité, restreint sur
  ///      Android 13+).
  Future<bool> shareApk({BuildContext? context}) async {
    try {
      final apkPath = await _locateApk();
      if (apkPath == null) {
        if (context != null && context.mounted) {
          _showError(
            context,
            'Impossible de localiser le fichier APK sur cet appareil.\n'
            'Veuillez réessayer après avoir installé StreetPhare.',
          );
        }
        return false;
      }

      final apkFile = File(apkPath);
      if (!await apkFile.exists()) {
        if (context != null && context.mounted) {
          _showError(
            context,
            'Le fichier APK n\'est plus accessible.\n'
            'Cela peut arriver après une mise à jour système.',
          );
        }
        return false;
      }

      // Partage via la feuille de partage native (API share_plus v13+)
      final sharePlus = SharePlus.instance;
      await sharePlus.share(
        ShareParams(
          files: [XFile(apkPath)],
          subject: 'StreetPhare — Application de cartographie citoyenne',
          text: 'StreetPhare v${await _getAppVersion()} — '
              'Application de cartographie citoyenne collaborative et décentralisée.\n'
              'Plus d\'infos : https://github.com/Deolin/StreetPhare',
        ),
      );

      return true;
    } catch (e) {
      debugPrint('[AppShareService] Erreur lors du partage : $e');
      if (context != null && context.mounted) {
        _showError(
          context,
          'Erreur lors du partage : ${e.toString()}',
        );
      }
      return false;
    }
  }

  // --------------------------------------------------------------------------
  // Localisation de l'APK
  // --------------------------------------------------------------------------

  /// Retourne le chemin absolu vers le fichier APK de l'application, ou `null`
  /// si la localisation échoue.
  ///
  /// Stratégie multi-niveaux :
  ///   1. Canal natif `getSourceApkPath` (ApplicationInfo.sourceDir) :
  ///      fiable sur toutes les versions Android, insensible au scoped storage.
  ///   2. Sauvegarde locale via [ApkBackupService] : copie persistante dans
  ///      le répertoire Documents, effectuée au premier lancement.
  ///   3. Scan du répertoire `/data/app/` (fallback hérité, restreint sur
  ///      Android 13+ avec scoped storage).
  Future<String?> _locateApk() async {
    // ── Niveau 1 : Canal natif (ApplicationInfo.sourceDir) ─────────────────
    final nativePath = await _locateViaNativeChannel();
    if (nativePath != null) {
      debugPrint(
          '[AppShareService] APK localisé via canal natif : $nativePath');
      return nativePath;
    }

    // ── Niveau 2 : Sauvegarde locale ApkBackupService ──────────────────────
    final backupPath = await _locateViaBackup();
    if (backupPath != null) {
      debugPrint(
          '[AppShareService] APK localisé via sauvegarde locale : $backupPath');
      return backupPath;
    }

    debugPrint(
        '[AppShareService] Échec de toutes les stratégies de localisation.');
    return null;
  }

  /// Niveau 1 : utilise le canal natif `streetphare/apk_info` pour obtenir
  /// `ApplicationInfo.sourceDir`, le chemin exact de l'APK installé.
  Future<String?> _locateViaNativeChannel() async {
    try {
      const channel = MethodChannel('streetphare/apk_info');
      final String? path =
          await channel.invokeMethod<String>('getSourceApkPath');
      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          return path;
        }
        debugPrint(
            '[AppShareService] Canal natif a retourné un chemin inexistant : $path');
      }
    } on MissingPluginException {
      debugPrint('[AppShareService] Canal natif non enregistré côté Android.');
    } on PlatformException catch (e) {
      debugPrint('[AppShareService] Erreur canal natif : ${e.message}');
    } catch (e) {
      debugPrint('[AppShareService] Erreur inattendue canal natif : $e');
    }
    return null;
  }

  /// Niveau 2 : récupère le chemin de la sauvegarde locale effectuée par
  /// [ApkBackupService] dans le répertoire Documents.
  Future<String?> _locateViaBackup() async {
    try {
      // ignore: depend_on_referenced_packages
      final backupPath = await ApkBackupService.getSavedApkPath();
      if (backupPath != null && backupPath.isNotEmpty) {
        final file = File(backupPath);
        if (await file.exists()) {
          return backupPath;
        }
        debugPrint(
            '[AppShareService] Sauvegarde locale introuvable (fichier supprimé) : $backupPath');
      }
    } catch (e) {
      debugPrint('[AppShareService] Erreur récupération sauvegarde : $e');
    }
    return null;
  }

  // --------------------------------------------------------------------------
  // Version de l'application
  // --------------------------------------------------------------------------

  Future<String> _getAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return '2.2.0';
    }
  }

  // --------------------------------------------------------------------------
  // Affichage d'erreur
  // --------------------------------------------------------------------------

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }
}
