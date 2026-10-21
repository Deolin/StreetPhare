// lib/core/services/report_service.dart
//
// Service d'envoi des signalements citoyens (alertes) vers l'API Node.js StreetPhare.
//
// Règle architecturale (cycle de vie lié à l'événement suivi) :
//   * Chaque signalement est obligatoirement rattaché à l'ID de l'événement
//     actuellement suivi par l'utilisateur (exposé par EventManager.instance.activeEvent).
//   * Si aucun événement n'est suivi, l'envoi est refusé avant l'appel réseau.
//
// Ce service est appelé par l'UI de signalement (report_bottom_sheet / placement
// sur la carte) une fois l'icône déposée. L'appelant fournit l'Alert complétée ;
// le service ajoute `userId` et `eventId` avant le POST /api/alerts.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../features/events/presentation/event_manager.dart';
import '../models/alert_model.dart';

/// Base URL de l'API StreetPhare (surchargeable via variable d'environnement).
const String _apiBase =
    String.fromEnvironment('STREETPHARE_API_BASE', defaultValue: 'http://10.0.2.2:3000');

/// Identifiant éphémère de l'utilisateur courant (injecté par la couche auth).
String? _currentUserId;

/// Token JWT optionnel (éclaireur / admin connecté).
String? _authToken;

/// Définit l'identifiant utilisateur utilisé pour les signalements.
void setCurrentUserId(String? userId) => _currentUserId = userId;

/// Retourne l'identifiant utilisateur courant.
String? get currentUserId => _currentUserId;

/// Définit le token JWT courant (pour privilèges éclaireur).
void setAuthToken(String? token) => _authToken = token;

/// Retourne le token JWT courant.
String? get authToken => _authToken;

/// Envoie un signalement à l'API, rattaché à l'événement suivi.
///
/// [type], [latitude], [longitude] sont obligatoires.
/// [userId] surcharge l'utilisateur courant si fourni.
/// [eventIdOverride] surcharge l'événement de l'EventManager si fourni.
///
/// Retourne l'[Alert] créée (ou fusionnée) parsée depuis la réponse JSON.
///
/// Lance une [Exception] si :
///   * aucun utilisateur n'est identifié,
///   * aucun événement n'est suivi (et pas de [eventIdOverride]),
///   * le serveur rejette (400 / 409) ou répond en erreur.
Future<Alert> submitReport({
  required AlertType type,
  required double latitude,
  required double longitude,
  String description = '',
  String? userId,
  String? eventIdOverride,
}) async {
  final uid = userId ?? _currentUserId;
  if (uid == null || uid.isEmpty) {
    throw Exception(
      'Aucun utilisateur identifié : impossible de rattacher le signalement.',
    );
  }

  // L'événement suivi est celui de l'EventManager (événement actif),
  // sauf surcharge explicite.
  final activeEvent = EventManager.instance.activeEvent;
  final effectiveEventId = eventIdOverride ?? activeEvent?.code;

  if (effectiveEventId == null || effectiveEventId.isEmpty) {
    throw Exception(
      'Aucun événement suivi — le signalement doit être rattaché à un événement avant d\'être émis.',
    );
  }

  final uri = Uri.parse('$_apiBase/api/alerts');
  final headers = <String, String>{
    'Content-Type': 'application/json',
    if (_authToken != null && _authToken!.isNotEmpty)
      'Authorization': 'Bearer $_authToken',
  };
  final response = await http.post(
    uri,
    headers: headers,
    body: jsonEncode({
      'type': type.name,
      'lat': latitude,
      'lng': longitude,
      'description': description,
      'userId': uid,
      'eventId': effectiveEventId,
    }),
  ).timeout(const Duration(seconds: 15));

  if (response.statusCode == 409) {
    throw Exception(
      'Aucun événement suivi — rattachement obligatoire avant de signaler.',
    );
  }
  if (response.statusCode == 400) {
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(decoded['error'] ?? 'ID d\'événement invalide ou inconnu.');
    } catch (_) {
      throw Exception('ID d\'événement invalide ou inconnu.');
    }
  }
  if (response.statusCode != 200 && response.statusCode != 201) {
    throw Exception(
      'Échec de l\'envoi du signalement (HTTP ${response.statusCode}).',
    );
  }

  final decoded = jsonDecode(response.body) as Map<String, dynamic>;
  final alertJson = decoded['alert'] as Map<String, dynamic>;
  return Alert.fromJson(alertJson);
}

/// Annule un faux signalement constaté sur le terrain (privilège Éclaireur).
/// Appelle `POST /api/alerts/:id/void` avec le token JWT éclaireur.
Future<void> voidReport(String alertId, {String? token}) async {
  final jwt = token ?? _authToken;
  if (jwt == null || jwt.isEmpty) {
    throw Exception('Authentification éclaireur requise pour annuler un signalement.');
  }

  final uri = Uri.parse('$_apiBase/api/alerts/$alertId/void');
  final response = await http.post(
    uri,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $jwt',
    },
  ).timeout(const Duration(seconds: 15));

  if (response.statusCode != 200) {
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(decoded['error'] ?? 'Échec de l\'annulation (HTTP ${response.statusCode}).');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Échec de l\'annulation (HTTP ${response.statusCode}).');
    }
  }
}

/// Lie (ou délie si [eventCode] est null) l'utilisateur courant à un événement suivi.
Future<void> followEvent({String? userId, String? eventCode}) async {
  final uid = userId ?? _currentUserId;
  if (uid == null || uid.isEmpty) {
    throw Exception('userId requis pour suivre un événement.');
  }

  final uri = Uri.parse('$_apiBase/api/user/follow-event');
  final response = await http.post(
    uri,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'userId': uid,
      'eventCode': eventCode,
    }),
  ).timeout(const Duration(seconds: 15));

  if (response.statusCode != 200) {
    throw Exception('Impossible de mettre à jour l\'événement suivi (HTTP ${response.statusCode}).');
  }
}
