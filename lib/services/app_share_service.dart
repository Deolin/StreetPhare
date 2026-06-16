// lib/services/app_share_service.dart
//
// Service d'extraction et de partage de l'APK de StreetPhare via la feuille
// de partage système (Bluetooth, Proximité, etc.) sans dépendance aux stores.
// v2.2.0 — Compatible Android 15+

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

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
  /// Stratégie de localisation (Android) :
  ///   1. Tente d'utiliser le chemin standard `/data/app/.../base.apk`
  ///      accessible en lecture sur la plupart des appareils Android.
  ///   2. Si le fichier n'existe pas, parcourt les sources alternatives.
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
  Future<String?> _locateApk() async {
    // Approche 1 : chemin standard Android via le packageName
    try {
      final info = await PackageInfo.fromPlatform();
      final packageName = info.packageName;

      // On essaie de scanner les répertoires d'installation
      final candidates = <String>[];

      // Parcours du répertoire /data/app/ pour trouver le package
      final appDir = Directory('/data/app');
      if (await appDir.exists()) {
        await for (final entity in appDir.list()) {
          if (entity is Directory && entity.path.contains(packageName)) {
            // Cherche base.apk dans ce répertoire
            final baseApk = File('${entity.path}/base.apk');
            if (await baseApk.exists()) {
              return baseApk.path;
            }
            // Cherche aussi dans les sous-répertoires
            await for (final sub in entity.list()) {
              if (sub is File && sub.path.endsWith('.apk')) {
                candidates.add(sub.path);
              }
            }
          }
        }
      }

      if (candidates.isNotEmpty) {
        // Priorité au fichier base.apk
        final baseApk = candidates.firstWhere(
          (p) => p.endsWith('base.apk'),
          orElse: () => candidates.first,
        );
        return baseApk;
      }
    } catch (e) {
      debugPrint('[AppShareService] Erreur lors de la localisation : $e');
    }

    // Approche 2 : fallback via la variable d'environnement ou chemin fixe
    try {
      final info = await PackageInfo.fromPlatform();
      final packageName = info.packageName;

      // Tente les chemins de fallback courants
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
      debugPrint('[AppShareService] Fallback échoué : $e');
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