// lib/services/github_update_service.dart
//
// Gestionnaire de mises à jour GitHub.
//
// Interroge l'API GitHub Releases pour détecter une nouvelle version
// de StreetPhare, compare avec la version installée (package_info_plus)
// et prévient l'utilisateur via une boîte de dialogue non bloquante.
//
// Le dépôt cible est : https://github.com/Deolin/StreetPhare
// (les tags de release sont au format `vX.Y.Z`, ex: `v2.2.0`).

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// ============================================================================
// GithubRelease
// ============================================================================

/// Représente une release GitHub.
class GithubRelease {
  const GithubRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.publishedAt,
    required this.apkUrl,
  });

  /// Tag Git brut (ex: `v2.3.0`).
  final String tagName;

  /// Titre de la release (ex: `StreetPhare v2.3.0`).
  final String name;

  /// Notes de version (Markdown).
  final String body;

  /// URL de la page de la release sur github.com.
  final String htmlUrl;

  /// Date de publication (format ISO 8601).
  final String publishedAt;

  /// URL de téléchargement direct de l'APK, vide si absent des assets.
  final String apkUrl;

  /// Version normalisée sans préfixe `v` (ex: `2.3.0`).
  String get version => tagName.replaceFirst(RegExp(r'^[vV]'), '');
}

// ============================================================================
// GithubUpdateService
// ============================================================================

/// Service singleton de vérification des mises à jour GitHub.
class GithubUpdateService {
  GithubUpdateService._();
  static final GithubUpdateService instance = GithubUpdateService._();

  /// Dépôt GitHub cible.
  static const String owner = 'Deolin';
  static const String repo = 'StreetPhare';
  static const String _apiBase = 'https://api.github.com';

  /// Clé SharedPreferences mémorisant la dernière version déjà signalée.
  static const String _lastNotifiedKey = 'github_update_last_notified_tag';

  String _currentVersion = '';
  bool _isInitialized = false;

  /// Version installée (ex: `2.2.0`).
  String get currentVersion => _currentVersion;
  bool get isInitialized => _isInitialized;

  /// Charge la version installée depuis [PackageInfo.fromPlatform].
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
      _isInitialized = true;
      debugPrint('[GithubUpdate] version installée=$_currentVersion');
    } catch (e) {
      debugPrint('[GithubUpdate] Échec lecture PackageInfo : $e');
    }
  }

  /// Interroge l'API GitHub et renvoie la dernière release si elle est
  /// plus récente que la version installée.
  ///
  /// Retourne `null` si l'application est à jour, si le réseau échoue,
  /// ou si la réponse GitHub est invalide (ne doit jamais faire planter).
  Future<GithubRelease?> checkForUpdate() async {
    try {
      final uri = Uri.parse('$_apiBase/repos/$owner/$repo/releases/latest');
      final response = await http.get(
        uri,
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        debugPrint('[GithubUpdate] API GitHub → HTTP ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return null;

      final tagName = (data['tag_name'] as String?)?.trim() ?? '';
      if (tagName.isEmpty) return null;

      final name = data['name'] as String?;
      final release = GithubRelease(
        tagName: tagName,
        name: (name != null && name.trim().isNotEmpty) ? name.trim() : tagName,
        body: (data['body'] as String?) ?? '',
        htmlUrl: (data['html_url'] as String?) ?? '',
        publishedAt: (data['published_at'] as String?) ?? '',
        apkUrl: _extractApkUrl(data),
      );

      if (!_isInitialized) await init();
      if (_currentVersion.isEmpty) return null;

      if (_isVersionGreater(release.version, _currentVersion)) {
        return release;
      }
      return null;
    } catch (e) {
      debugPrint('[GithubUpdate] Échec de la vérification GitHub : $e');
      return null;
    }
  }

  /// Vérifie les mises à jour et mémorise la version signalée (anti-spam).
  ///
  /// Retourne la release si elle est nouvelle et n'a pas encore été
  /// signalée, sinon `null`.
  Future<GithubRelease?> checkAndRemember() async {
    final release = await checkForUpdate();
    if (release == null) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastNotified = prefs.getString(_lastNotifiedKey);
      if (lastNotified == release.tagName) {
        return null; // Déjà signalée pour cette version.
      }
      await prefs.setString(_lastNotifiedKey, release.tagName);
    } catch (e) {
      debugPrint('[GithubUpdate] Échec mémorisation : $e');
    }
    return release;
  }

  /// Extrait l'URL de téléchargement de l'APK depuis les assets de la release.
  String _extractApkUrl(Map<String, dynamic> data) {
    final assets = data['assets'];
    if (assets is! List) return '';
    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) continue;
      final name = (asset['name'] as String?) ?? '';
      if (name.toLowerCase().endsWith('.apk')) {
        return (asset['browser_download_url'] as String?) ?? '';
      }
    }
    return '';
  }

  /// Compare deux versions `X.Y.Z` : renvoie `true` si [a] > [b].
  bool _isVersionGreater(String a, String b) {
    final pa = _parseVersion(a);
    final pb = _parseVersion(b);
    for (int i = 0; i < 3; i++) {
      if (pa[i] > pb[i]) return true;
      if (pa[i] < pb[i]) return false;
    }
    return false;
  }

  /// Extrait les 3 premières composantes numériques d'une version
  /// (ex: `v2.3.0-beta.1` → [2, 3, 0]).
  List<int> _parseVersion(String input) {
    final parts = <int>[];
    final matches = RegExp(r'\d+').allMatches(input);
    for (final m in matches) {
      parts.add(int.tryParse(m.group(0)!) ?? 0);
      if (parts.length == 3) break;
    }
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts;
  }

  /// Ouvre l'URL de téléchargement (APK direct si dispo, sinon page release).
  Future<void> _openDownload(GithubRelease release) async {
    final target = release.apkUrl.isNotEmpty ? release.apkUrl : release.htmlUrl;
    if (target.isEmpty) return;
    final uri = Uri.parse(target);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Affiche la boîte de dialogue « Mise à jour disponible ».
  ///
  /// Non bloquante : l'utilisateur peut la fermer avec « Plus tard ».
  Future<void> showUpdateDialog(
    BuildContext context,
    GithubRelease release,
  ) async {
    final notes = release.body.trim();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: const Row(
            children: [
              Icon(Icons.system_update_alt, color: Color(0xFFFFB300)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Mise à jour disponible',
                  style: TextStyle(
                    color: Color(0xFFFFB300),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              'La version ${release.version} de StreetPhare est disponible. '
              'Vous utilisez actuellement la version $_currentVersion.\n\n'
              '${notes.isEmpty ? 'Rendez-vous sur la page GitHub pour la télécharger.' : notes}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Plus tard',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB300),
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _openDownload(release);
              },
              child: const Text('Télécharger'),
            ),
          ],
        );
      },
    );
  }
}
