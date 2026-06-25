// lib/services/apk_backup_service.dart
//
// Service de Persistance de l'APK Source (Sauvegarde Locale).
//
// Lors du premier démarrage de l'application, ce service :
//   1. Détecte si la copie de sauvegarde a déjà été effectuée (via SharedPreferences).
//   2. Localise le chemin de l'APK installé via le canal natif Android (sourceDir).
//   3. Copie l'APK vers le répertoire Documents persistant de l'application.
//   4. Enregistre le chemin final dans les préférences pour la fonctionnalité P2P.
//
// Ce service est non-bloquant : toute erreur est silencieuse en production.
// Il n'est actif que sur Android (iOS ne permet pas l'accès à l'APK source).

import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Clé SharedPreferences pour le chemin de l'APK sauvegardé.
const String _kApkBackupPathKey = 'streetphare_apk_backup_path_v1';

/// Nom du fichier APK de sauvegarde (correspond au nom Gradle).
const String _kApkFileName = 'Streetphare.apk';

/// Canal natif Android pour récupérer le sourceDir de l'APK installé.
const MethodChannel _kChannel = MethodChannel('streetphare/apk_info');

/// Service singleton de sauvegarde de l'APK source.
///
/// Usage dans main.dart :
/// ```dart
/// await ApkBackupService.instance.init();
/// ```
class ApkBackupService {
  ApkBackupService._();
  static final ApkBackupService instance = ApkBackupService._();

  /// Chemin vers l'APK sauvegardé, disponible après [init].
  /// Null si la sauvegarde n'a pas encore été effectuée ou si non-Android.
  String? _backupPath;
  String? get backupPath => _backupPath;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Initialise le service : vérifie si la sauvegarde est nécessaire
  /// et l'effectue si c'est le premier lancement.
  ///
  /// Non-bloquant : les erreurs sont loguées mais n'interrompent pas le démarrage.
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Ce service n'est pertinent que sur Android.
    if (kIsWeb || !io.Platform.isAndroid) {
      debugPrint('[ApkBackup] Non-Android : service ignoré.');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      // Vérifier si une sauvegarde existe déjà et est valide.
      final existingPath = prefs.getString(_kApkBackupPathKey);
      if (existingPath != null && existingPath.isNotEmpty) {
        final existingFile = io.File(existingPath);
        if (await existingFile.exists()) {
          _backupPath = existingPath;
          debugPrint('[ApkBackup] APK déjà sauvegardé : $_backupPath');
          return;
        }
        // Le fichier n'existe plus (désinstallation partielle, nettoyage) → on refait.
        debugPrint(
            '[ApkBackup] Fichier de sauvegarde introuvable, re-copie...');
      }

      // Premier lancement ou sauvegarde invalide : effectuer la copie.
      await _performBackup(prefs);
    } catch (e, st) {
      // Erreur non-critique : on ne bloque pas le démarrage.
      debugPrint('[ApkBackup] Erreur lors de l\'initialisation : $e\n$st');
    }
  }

  /// Effectue la copie de l'APK source vers le stockage persistant.
  Future<void> _performBackup(SharedPreferences prefs) async {
    // 1. Récupérer le chemin source de l'APK installé via le canal natif.
    final String? sourceApkPath = await _getSourceApkPath();
    if (sourceApkPath == null || sourceApkPath.isEmpty) {
      debugPrint('[ApkBackup] Impossible de localiser l\'APK source.');
      return;
    }

    final sourceFile = io.File(sourceApkPath);
    if (!await sourceFile.exists()) {
      debugPrint('[ApkBackup] Fichier APK source introuvable : $sourceApkPath');
      return;
    }

    // 2. Déterminer le répertoire de destination (Documents persistant).
    final destDir = await _getBackupDirectory();
    if (destDir == null) {
      debugPrint(
          '[ApkBackup] Impossible d\'accéder au répertoire de sauvegarde.');
      return;
    }

    // 3. Copier l'APK vers la destination.
    final destPath = '${destDir.path}/$_kApkFileName';
    final destFile = io.File(destPath);

    debugPrint('[ApkBackup] Copie en cours : $sourceApkPath → $destPath');
    await sourceFile.copy(destPath);

    if (!await destFile.exists()) {
      debugPrint('[ApkBackup] Échec de la copie : fichier destination absent.');
      return;
    }

    // 4. Persister le chemin pour les accès futurs (partage P2P).
    await prefs.setString(_kApkBackupPathKey, destPath);
    _backupPath = destPath;

    final sizeKb = (await destFile.length()) ~/ 1024;
    debugPrint(
        '[ApkBackup] ✅ APK sauvegardé avec succès : $destPath ($sizeKb Ko)');
  }

  /// Récupère le chemin de l'APK installé via le canal natif Android.
  ///
  /// Utilise `ApplicationInfo.sourceDir` côté Java/Kotlin.
  /// Retourne null en cas d'erreur ou si non-Android.
  Future<String?> _getSourceApkPath() async {
    try {
      final String? path =
          await _kChannel.invokeMethod<String>('getSourceApkPath');
      return path;
    } on MissingPluginException {
      // Canal natif non encore implémenté : fallback via path connu.
      debugPrint(
          '[ApkBackup] Canal natif non disponible, tentative de fallback...');
      return _fallbackApkPath();
    } on PlatformException catch (e) {
      debugPrint('[ApkBackup] PlatformException canal natif : ${e.message}');
      return _fallbackApkPath();
    }
  }

  /// Fallback : tente de localiser l'APK via les chemins Android standards.
  ///
  /// Sur Android, les APK installés se trouvent généralement dans
  /// `/data/app/<package>/base.apk` ou `/data/app/<package>-<hash>/base.apk`.
  String? _fallbackApkPath() {
    // Sans le canal natif, on ne peut pas localiser l'APK de façon fiable.
    // Le canal natif doit être implémenté dans MainActivity.kt.
    debugPrint('[ApkBackup] Fallback impossible sans canal natif. '
        'Implémenter getSourceApkPath() dans MainActivity.kt.');
    return null;
  }

  /// Retourne le répertoire de sauvegarde persistant de l'application.
  ///
  /// Utilise `getApplicationDocumentsDirectory()` (path_provider) qui
  /// correspond au répertoire Documents interne de l'app, non effacé
  /// lors des mises à jour.
  Future<io.Directory?> _getBackupDirectory() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      // Sous-répertoire dédié pour éviter de polluer la racine Documents.
      final backupDir = io.Directory('${docsDir.path}/apk_backup');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      return backupDir;
    } catch (e) {
      debugPrint('[ApkBackup] Erreur accès répertoire Documents : $e');
      return null;
    }
  }

  /// Retourne le chemin de l'APK sauvegardé depuis les préférences.
  ///
  /// Utile pour récupérer le chemin sans réinitialiser le service.
  static Future<String?> getSavedApkPath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kApkBackupPathKey);
    } catch (_) {
      return null;
    }
  }
}
