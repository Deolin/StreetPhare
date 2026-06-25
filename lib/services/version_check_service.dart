// lib/services/version_check_service.dart
//
// Système d'Audit et de Forçage des Mises à Jour (Kill Switch Applicatif).
//
// Ce service interroge l'endpoint /api/version/check du serveur pour
// vérifier si l'application est à jour ou si elle doit être bloquée
// pour des raisons de compatibilité ou de sécurité.

import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../network/network_config.dart';

class VersionCheckService {
  VersionCheckService._();
  static final VersionCheckService instance = VersionCheckService._();

  /// Version et build number lus depuis le package natif au démarrage.
  String _version = '';
  String _buildNumber = '';

  /// Version actuelle de l'application (format X.Y.Z).
  String get currentVersion => _version;

  /// Numéro de build (provenant de pubspec.yaml ou du build natif).
  String get buildNumber => _buildNumber;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  bool _isObsolete = false;
  bool get isObsolete => _isObsolete;

  String _updateUrl = 'https://streetphare.org/download';

  /// Charge la version et le build number depuis [PackageInfo.fromPlatform].
  /// Doit être appelé une fois au démarrage, avant tout appel à [checkVersion].
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
      _buildNumber = info.buildNumber;
      _isInitialized = true;
      debugPrint('[VersionCheck] version=$_version build=$_buildNumber');
    } catch (e) {
      debugPrint('[VersionCheck] Échec lecture PackageInfo : $e');
      // Fallback : on garde les chaînes vides, le checkVersion ignorera.
    }
  }

  /// Vérifie la version auprès du serveur principal.
  Future<void> checkVersion(BuildContext context) async {
    try {
      final response = await http
          .get(
            Uri.parse('${NetworkConfig.primaryServer}/api/version/check'),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final minRequired = data['min_required'] as String;
        _updateUrl = data['url'] as String;

        if (_isVersionLower(currentVersion, minRequired)) {
          _isObsolete = true;
          if (context.mounted) {
            _showKillSwitchDialog(context, minRequired);
          }
        }
      }
    } catch (e) {
      debugPrint('[VersionCheck] Échec de la vérification de version : $e');
      // En cas d'échec de connexion, on laisse l'utilisateur continuer
      // (la déconnexion critique prendra le relais si besoin).
    }
  }

  /// Compare deux chaînes de version (format X.Y.Z).
  /// Retourne true si [current] < [required].
  bool _isVersionLower(String current, String required) {
    List<int> currentParts = current.split('.').map(int.parse).toList();
    List<int> requiredParts = required.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      if (currentParts[i] < requiredParts[i]) return true;
      if (currentParts[i] > requiredParts[i]) return false;
    }
    return false;
  }

  /// Affiche le dialogue modal disruptif (Kill Switch).
  void _showKillSwitchDialog(BuildContext context, String minVersion) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false, // Empêche le retour arrière
          child: AlertDialog(
            backgroundColor: const Color(0xFF161B22),
            title: const Text(
              'Mise à jour obligatoire',
              style: TextStyle(
                  color: Color(0xFFF85149), fontWeight: FontWeight.bold),
            ),
            content: Text(
              'Votre version actuelle ($currentVersion) est obsolète et ne permet plus '
              'de garantir la sécurité ou la compatibilité avec le réseau Hive.\n\n'
              'La version $minVersion ou supérieure est requise pour continuer.',
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => _quitApp(),
                child: const Text('Quitter l\'application',
                    style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB300)),
                onPressed: () => _launchUpdateUrl(),
                child: const Text('Mettre à jour manuellement',
                    style: TextStyle(color: Colors.black)),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _launchUpdateUrl() async {
    final uri = Uri.parse(_updateUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _quitApp() {
    if (kIsWeb) return;
    if (io.Platform.isAndroid) {
      SystemNavigator.pop();
    } else {
      io.exit(0);
    }
  }
}
