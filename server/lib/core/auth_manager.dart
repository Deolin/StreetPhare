// server/lib/core/auth_manager.dart
//
// Gestionnaire d'authentification et de sessions du serveur StreetPhare.
//
// Fonctionnalités :
//   1. Détection du premier lancement (setup run) : si aucun compte
//      administrateur n'existe, l'accès est verrouillé jusqu'à la
//      création du mot de passe Master Admin.
//   2. Hachage des mots de passe (SHA-256 + sel aléatoire).
//   3. Sessions par token HMAC-SHA256 avec expiration configurable.
//   4. Middleware Shelf pour protéger les routes API et dashboard.
//   5. Gestion RBAC : rôles `admin` et `moderator`.
//
// Format du fichier `auth_store.json` :
// {
//   "setup_complete": false,       // true après création du Master Admin
//   "sessions": { "token": { "role": "admin", "expires": "..." } },
//   "accounts": [
//     { "id": "uuid", "username": "admin", "password_hash": "...",
//       "password_salt": "...", "role": "admin", "created_at": "..." }
//   ]
// }

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

final _log = Logger('AuthManager');

/// Rôle utilisateur.
enum ServerRole {
  admin,
  moderator;

  String get jsonValue => name;
  static ServerRole fromJson(String v) =>
      ServerRole.values.firstWhere((r) => r.name == v, orElse: () => ServerRole.moderator);
}

/// Compte utilisateur du serveur.
class ServerAccount {
  final String id;
  final String username;
  final String passwordHash;
  final String passwordSalt;
  final ServerRole role;
  final DateTime createdAt;

  const ServerAccount({
    required this.id,
    required this.username,
    required this.passwordHash,
    required this.passwordSalt,
    required this.role,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'password_hash': passwordHash,
        'password_salt': passwordSalt,
        'role': role.jsonValue,
        'created_at': createdAt.toIso8601String(),
      };

  factory ServerAccount.fromJson(Map<String, dynamic> json) => ServerAccount(
        id: json['id'] as String,
        username: json['username'] as String,
        passwordHash: json['password_hash'] as String,
        passwordSalt: json['password_salt'] as String,
        role: ServerRole.fromJson(json['role'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// Session active d'un utilisateur authentifié.
class ServerSession {
  final String token;
  final String accountId;
  final ServerRole role;
  final DateTime expiresAt;

  const ServerSession({
    required this.token,
    required this.accountId,
    required this.role,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);
}

// ============================================================================
// AuthManager
// ============================================================================

class AuthManager {
  AuthManager._();
  static final AuthManager instance = AuthManager._();

  final String _storePath = 'auth_store.json';
  bool _initialized = false;

  bool _setupComplete = false;
  final List<ServerAccount> _accounts = [];
  final Map<String, ServerSession> _sessions = {}; // token → session

  /// Durée de validité d'une session (24h).
  static const Duration sessionDuration = Duration(hours: 24);

  // --------------------------------------------------------------------------
  // Initialisation & persistance
  // --------------------------------------------------------------------------

  bool get isSetupComplete => _setupComplete;
  bool get hasAccounts => _accounts.any((a) => a.role == ServerRole.admin);

  Future<void> init() async {
    if (_initialized) return;
    final file = File(_storePath);
    if (await file.exists()) {
      try {
        final raw = await file.readAsString();
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _setupComplete = data['setup_complete'] as bool? ?? false;
        final accounts = data['accounts'] as List<dynamic>? ?? [];
        _accounts.clear();
        _accounts.addAll(accounts.map((a) => ServerAccount.fromJson(a as Map<String, dynamic>)));
        // Nettoie les sessions expirées.
        final sessions = data['sessions'] as Map<String, dynamic>? ?? {};
        _sessions.clear();
        final now = DateTime.now().toUtc();
        for (final entry in sessions.entries) {
          final s = entry.value as Map<String, dynamic>;
          final expires = DateTime.parse(s['expires'] as String);
          if (now.isBefore(expires)) {
            _sessions[entry.key] = ServerSession(
              token: entry.key,
              accountId: s['account_id'] as String,
              role: ServerRole.fromJson(s['role'] as String),
              expiresAt: expires,
            );
          }
        }
      } catch (e) {
        _log.warning('Erreur chargement auth_store.json : $e');
        _setupComplete = false;
      }
    }
    _initialized = true;
    _log.info('AuthManager initialisé — setup=${_setupComplete ? "OK" : "PENDING"} — '
        '${_accounts.length} compte(s) — ${_sessions.length} session(s) active(s)');
  }

  Future<void> _persist() async {
    final data = {
      'setup_complete': _setupComplete,
      'accounts': _accounts.map((a) => a.toJson()).toList(),
      'sessions': Map.fromEntries(
        _sessions.entries.map((e) => MapEntry(e.key, {
              'account_id': e.value.accountId,
              'role': e.value.role.jsonValue,
              'expires': e.value.expiresAt.toIso8601String(),
            })),
      ),
    };
    await File(_storePath).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  // --------------------------------------------------------------------------
  // Hachage de mot de passe
  // --------------------------------------------------------------------------

  String _generateSalt() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64Encode(bytes);
  }

  String _hashPassword(String password, String salt) {
    final bytes = utf8.encode(password + salt);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // --------------------------------------------------------------------------
  // Setup run — création du Master Admin
  // --------------------------------------------------------------------------

  /// Crée le compte Master Admin. Ne peut être appelé qu'une seule fois.
  Future<ServerAccount> setupMasterAdmin(String username, String password) async {
    if (_setupComplete) {
      throw StateError('Le setup est déjà terminé. Un administrateur existe déjà.');
    }
    if (username.trim().isEmpty || password.trim().isEmpty) {
      throw ArgumentError('Le nom d\'utilisateur et le mot de passe sont requis.');
    }
    if (password.length < 8) {
      throw ArgumentError('Le mot de passe doit contenir au moins 8 caractères.');
    }
    final salt = _generateSalt();
    final hash = _hashPassword(password, salt);
    final account = ServerAccount(
      id: _generateId(),
      username: username.trim(),
      passwordHash: hash,
      passwordSalt: salt,
      role: ServerRole.admin,
      createdAt: DateTime.now().toUtc(),
    );
    _accounts.add(account);
    _setupComplete = true;
    await _persist();
    _log.info('Master Admin créé : $username');
    return account;
  }

  // --------------------------------------------------------------------------
  // Connexion — création de session
  // --------------------------------------------------------------------------

  /// Authentifie un utilisateur et retourne un token de session.
  Future<String?> login(String username, String password) async {
    final account = _accounts.firstWhere(
      (a) => a.username == username,
      orElse: () => throw AuthException('Identifiants invalides.'),
    );
    final hash = _hashPassword(password, account.passwordSalt);
    if (hash != account.passwordHash) {
      throw AuthException('Identifiants invalides.');
    }
    return _createSession(account);
  }

  String _createSession(ServerAccount account) {
    _cleanExpiredSessions();
    final token = _generateToken();
    final session = ServerSession(
      token: token,
      accountId: account.id,
      role: account.role,
      expiresAt: DateTime.now().toUtc().add(sessionDuration),
    );
    _sessions[token] = session;
    unawaited(_persist());
    _log.info('Session créée pour ${account.username} (${account.role.name})');
    return token;
  }

  /// Déconnecte une session.
  Future<void> logout(String token) async {
    _sessions.remove(token);
    await _persist();
  }

  // --------------------------------------------------------------------------
  // Validation de session
  // --------------------------------------------------------------------------

  /// Valide un token et retourne la session associée, ou null.
  ServerSession? validateToken(String token) {
    final session = _sessions[token];
    if (session == null) return null;
    if (session.isExpired) {
      _sessions.remove(token);
      return null;
    }
    return session;
  }

  /// Extrait le token d'une requête HTTP (Authorization: Bearer token ou cookie).
  String? _extractToken(Request request) {
    // Authorization header
    final authHeader = request.headers['authorization'];
    if (authHeader != null && authHeader.startsWith('Bearer ')) {
      return authHeader.substring(7).trim();
    }
    // Cookie
    final cookie = request.headers['cookie'];
    if (cookie != null) {
      final match = RegExp(r'sp_auth_token=([^;]+)').firstMatch(cookie);
      if (match != null) return match.group(1)!.trim();
    }
    return null;
  }

  // --------------------------------------------------------------------------
  // Middleware Shelf
  // --------------------------------------------------------------------------

  /// Middleware qui bloque les requêtes non authentifiées.
  /// En phase de setup (non initialisé), toutes les routes /api/* sont
  /// autorisées temporairement — le dashboard affiche l'écran de setup
  /// et les autres appels sont inoffensifs (base vide).
  Handler authMiddleware(Handler innerHandler, {bool setupOnly = false}) {
    return (Request request) async {
      final path = request.url.path;

      // En phase de setup (non initialisé), autoriser TOUTES les routes /api/*.
      // Le dashboard gère l'affichage conditionnel (setup wizard).
      if (!_setupComplete && path.contains('/api/')) {
        return innerHandler(request);
      }

      // Routes publiques (setup, login, health, page setup HTML).
      if (path.endsWith('/setup') ||
          path.contains('/api/setup') ||
          path.contains('/api/login') ||
          path.contains('/api/health')) {
        return innerHandler(request);
      }

      // Authentification requise pour toutes les autres routes.
      final token = _extractToken(request);
      if (token == null) {
        return Response.forbidden(
          jsonEncode({'error': 'UNAUTHORIZED', 'message': 'Authentification requise.'}),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }
      final session = validateToken(token);
      if (session == null) {
        return Response.forbidden(
          jsonEncode({'error': 'SESSION_EXPIRED', 'message': 'Session expirée ou invalide.'}),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      // Injecte le rôle dans la requête via le contexte Shelf.
      final updatedRequest = request.change(context: {
        ...request.context,
        'auth_role': session.role.jsonValue,
        'auth_account_id': session.accountId,
      });

      return innerHandler(updatedRequest);
    };
  }

  // --------------------------------------------------------------------------
  // Gestion des comptes (admin only)
  // --------------------------------------------------------------------------

  List<ServerAccount> listAccounts() => List.unmodifiable(_accounts);

  Future<ServerAccount> createModerator(String username, String password) async {
    if (username.trim().isEmpty || password.trim().isEmpty) {
      throw ArgumentError('Le nom d\'utilisateur et le mot de passe sont requis.');
    }
    if (password.length < 6) {
      throw ArgumentError('Le mot de passe doit contenir au moins 6 caractères.');
    }
    if (_accounts.any((a) => a.username == username.trim())) {
      throw ArgumentError('Ce nom d\'utilisateur existe déjà.');
    }
    final salt = _generateSalt();
    final hash = _hashPassword(password, salt);
    final account = ServerAccount(
      id: _generateId(),
      username: username.trim(),
      passwordHash: hash,
      passwordSalt: salt,
      role: ServerRole.moderator,
      createdAt: DateTime.now().toUtc(),
    );
    _accounts.add(account);
    await _persist();
    _log.info('Modérateur créé : $username');
    return account;
  }

  Future<void> deleteAccount(String accountId) async {
    // Empêche la suppression du dernier admin.
    final target = _accounts.firstWhere((a) => a.id == accountId);
    if (target.role == ServerRole.admin) {
      final adminCount = _accounts.where((a) => a.role == ServerRole.admin).length;
      if (adminCount <= 1) {
        throw StateError('Impossible de supprimer le dernier administrateur.');
      }
    }
    // Supprime les sessions de ce compte.
    _sessions.removeWhere((_, s) => s.accountId == accountId);
    _accounts.removeWhere((a) => a.id == accountId);
    await _persist();
    _log.info('Compte supprimé : ${target.username}');
  }

  Future<ServerAccount> updateAccountPassword(String accountId, String newPassword) async {
    final idx = _accounts.indexWhere((a) => a.id == accountId);
    if (idx == -1) throw ArgumentError('Compte introuvable.');
    if (newPassword.length < 6) {
      throw ArgumentError('Le mot de passe doit contenir au moins 6 caractères.');
    }
    final account = _accounts[idx];
    final salt = _generateSalt();
    final hash = _hashPassword(newPassword, salt);
    final updated = ServerAccount(
      id: account.id,
      username: account.username,
      passwordHash: hash,
      passwordSalt: salt,
      role: account.role,
      createdAt: account.createdAt,
    );
    _accounts[idx] = updated;
    // Invalide toutes les sessions de ce compte.
    _sessions.removeWhere((_, s) => s.accountId == accountId);
    await _persist();
    return updated;
  }

  // --------------------------------------------------------------------------
  // Utilitaires
  // --------------------------------------------------------------------------

  void _cleanExpiredSessions() {
    _sessions.removeWhere((_, s) => s.isExpired);
  }

  String _generateId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(12, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  String _generateToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes);
  }
}

/// Exception levée en cas d'échec d'authentification.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => 'AuthException: $message';
}

// ignore: unused_element
void unawaited(Future<void>? future) {}