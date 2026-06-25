// lib/services/app_share_service.dart
//
// Service d'extraction et de partage de l'APK de StreetPhare via la feuille
// de partage système (Bluetooth, Proximité, etc.) sans dépendance aux stores.
// v2.2.0 — Compatible Android 15+

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import 'apk_backup_service.dart';

/// Service responsable de la localisation de l'APK de l'application et de son
/// partage via la feuille de partage native Android.
///
/// Le service est instancié à la demande (lazy), sans impact sur le démarrage.
class AppShareService {
  AppShareService._();

  static final AppShareService instance = AppShareService._();

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

    // ── Niveau 3 : Scan du répertoire /data/app/ (fallback hérité) ─────────
    final scanPath = await _locateViaDataAppScan();
    if (scanPath != null) {
      debugPrint(
          '[AppShareService] APK localisé via scan /data/app/ : $scanPath');
      return scanPath;
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

  /// Niveau 3 : scan du répertoire `/data/app/` pour trouver l'APK.
  /// Cette approche peut échouer sur Android 13+ (API 33+) à cause du
  /// scoped storage qui restreint l'accès à ce répertoire.
  Future<String?> _locateViaDataAppScan() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final packageName = info.packageName;

      final candidates = <String>[];

      final appDir = Directory('/data/app');
      if (!await appDir.exists()) return null;

      await for (final entity in appDir.list()) {
        if (entity is Directory && entity.path.contains(packageName)) {
          final baseApk = File('${entity.path}/base.apk');
          if (await baseApk.exists()) {
            return baseApk.path;
          }
          await for (final sub in entity.list()) {
            if (sub is File && sub.path.endsWith('.apk')) {
              candidates.add(sub.path);
            }
          }
        }
      }

      if (candidates.isNotEmpty) {
        return candidates.firstWhere(
          (p) => p.endsWith('base.apk'),
          orElse: () => candidates.first,
        );
      }
    } catch (e) {
      debugPrint('[AppShareService] Erreur scan /data/app/ : $e');
    }

    // Fallback chemins fixes (dernier recours)
    try {
      final info = await PackageInfo.fromPlatform();
      final packageName = info.packageName;

      final fallbackPaths = [
        '/data/app/$packageName-1/base.apk',
        '/data/app/$packageName-2/base.apk',
        '/data/app/$packageName/base.apk',
      ];

      for (final path in fallbackPaths) {
        final file = File(path);
        if (await file.exists()) {
          return path;
        }
      }
    } catch (e) {
      debugPrint('[AppShareService] Fallback chemins fixes échoué : $e');
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
