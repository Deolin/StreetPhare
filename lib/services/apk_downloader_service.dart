// lib/services/apk_downloader_service.dart
//
// Service de distribution hybride — Mini-installer embarqué.
//
// StreetPhare embarque un mini-téléchargeur APK (~50 ko) dans ses assets.
// Lors du partage, ce mini-installer est extrait et partagé à la place
// de l'APK complet (20+ Mo). Le destinataire installe le mini-installer
// qui télécharge et installe automatiquement la dernière version de
// StreetPhare depuis GitHub Releases.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Service d'extraction et partage du mini-installer StreetPhare.
class ApkDownloaderService {
  ApkDownloaderService._();
  static final ApkDownloaderService instance = ApkDownloaderService._();

  /// Nom du fichier mini-downloader dans les assets.
  static const String _downloaderAssetPath =
      'assets/binaries/streetphare_downloader.apk';

  /// Nom du fichier temporaire extrait.
  static const String _tempFileName = 'streetphare_downloader.apk';

  /// Prépare le mini-installer pour partage :
  ///   1. Extrait le binaire depuis les assets Flutter via `rootBundle.load()`.
  ///   2. Écrit les octets dans le répertoire temporaire via `path_provider`.
  ///   3. Retourne le chemin absolu du fichier extrait, ou `null` si échec.
  ///
  /// Le fichier est supprimé après partage (appeler [cleanup] après usage).
  Future<String?> prepareDownloaderForShare() async {
    try {
      final timestamp = _nowStr();
      debugPrint('[$timestamp] [ApkDownloader] Extraction du mini-installer '
          'depuis les assets Flutter…');

      // 1. Charge le binaire depuis les assets.
      final ByteData data = await rootBundle.load(_downloaderAssetPath);

      if (data.lengthInBytes == 0) {
        debugPrint('[$timestamp] [ApkDownloader] ⚠ Asset vide : '
            '$_downloaderAssetPath');
        return null;
      }

      debugPrint('[$timestamp] [ApkDownloader] ✓ Asset chargé '
          '(${data.lengthInBytes} octets)');

      // 2. Écrit dans le répertoire temporaire (non persistant,
      //    nettoyé automatiquement par l'OS après un certain temps).
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$_tempFileName');

      // Écriture asynchrone pour ne pas bloquer le thread principal.
      await file.writeAsBytes(
        data.buffer.asUint8List(),
        flush: true,
      );

      if (!await file.exists()) {
        debugPrint(
            '[$timestamp] [ApkDownloader] ⚠ Échec écriture fichier temporaire');
        return null;
      }

      debugPrint('[$timestamp] [ApkDownloader] ✓ Fichier extrait : '
          '${file.path} (${await file.length()} octets)');

      return file.path;
    } catch (e) {
      final timestamp = _nowStr();
      debugPrint('[$timestamp] [ApkDownloader] ❌ Erreur extraction : $e');
      return null;
    }
  }

  /// Partage le mini-installer via la feuille de partage native Android.
  ///
  /// Extrait d'abord le fichier (appelle [prepareDownloaderForShare]),
  /// puis ouvre la feuille de partage système avec le mini-installer.
  ///
  /// Retourne `true` si le partage a été déclenché, `false` sinon.
  Future<bool> shareDownloader() async {
    final timestamp = _nowStr();

    try {
      final path = await prepareDownloaderForShare();
      if (path == null) {
        debugPrint('[$timestamp] [ApkDownloader] ❌ Impossible d\'extraire '
            'le mini-installer pour le partage.');
        return false;
      }

      final file = File(path);
      if (!await file.exists()) {
        debugPrint('[$timestamp] [ApkDownloader] ❌ Fichier extrait disparu '
            'avant partage.');
        return false;
      }

      debugPrint(
          '[$timestamp] [ApkDownloader] 🚀 Ouverture feuille de partage…');

      // Partage via share_plus.
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          subject: 'StreetPhare — Installation',
          text: 'StreetPhare — Application de cartographie citoyenne.\n'
              'Ce mini-installer téléchargera automatiquement la dernière version.\n'
              'Plus d\'infos : https://github.com/Deolin/StreetPhare',
        ),
      );

      debugPrint('[$timestamp] [ApkDownloader] ✅ Feuille de partage ouverte.');

      // Nettoie le fichier temporaire après partage (délai pour
      // laisser le temps au système de le lire).
      unawaited(Future.delayed(const Duration(seconds: 5), () {
        cleanup(path);
      }));

      return true;
    } catch (e) {
      debugPrint(
          '[$timestamp] [ApkDownloader] ❌ Erreur partage : $e');
      return false;
    }
  }

  /// Supprime le fichier temporaire extrait.
  void cleanup(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
        if (kDebugMode) {
          debugPrint('[$_nowStr()] [ApkDownloader] 🗑 Fichier temporaire '
              'nettoyé : $path');
        }
      }
    } catch (_) {
      // Silencieux — le fichier sera nettoyé par l'OS.
    }
  }

  /// Horodatage pour les logs.
  static String _nowStr() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')} '
        '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}';
  }
}