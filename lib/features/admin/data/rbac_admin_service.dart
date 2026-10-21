// lib/features/admin/data/rbac_admin_service.dart
//
// Service client HTTP pour l'administration RBAC StreetPhare :
//   - Authentification unifiée (/api/auth/login)
//   - Gestion des éclaireurs (/api/admin/scouts)
//   - Gestion des administrateurs d'événements (/api/admin/event-admins)

import 'dart:convert';
import 'package:http/http.dart' as http;

const String _defaultApiBase = String.fromEnvironment(
  'STREETPHARE_API_BASE',
  defaultValue: 'http://10.0.2.2:3000',
);

/// Modèle représentant un compte Éclaireur (Trusted User).
class ScoutAccount {
  const ScoutAccount({
    required this.id,
    required this.username,
    required this.displayName,
    required this.permissions,
    this.createdAt,
  });

  factory ScoutAccount.fromJson(Map<String, dynamic> json) {
    return ScoutAccount(
      id: (json['id'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      displayName: (json['displayName'] ?? json['username'] ?? '').toString(),
      permissions: (json['permissions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['scoutValidate', 'scoutVoid'],
      createdAt: json['createdAt']?.toString(),
    );
  }

  final String id;
  final String username;
  final String displayName;
  final List<String> permissions;
  final String? createdAt;
}

/// Modèle représentant un compte Administrateur d'Événement.
class EventAdminAccount {
  const EventAdminAccount({
    required this.id,
    required this.username,
    required this.displayName,
    required this.permissions,
    required this.managedEventCodes,
    this.createdAt,
  });

  factory EventAdminAccount.fromJson(Map<String, dynamic> json) {
    return EventAdminAccount(
      id: (json['id'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      displayName: (json['displayName'] ?? json['username'] ?? '').toString(),
      permissions: (json['permissions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['manageEvents', 'reportValidate'],
      managedEventCodes: (json['managedEventCodes'] as List<dynamic>?)
              ?.map((e) => e.toString().toUpperCase())
              .toList() ??
          const [],
      createdAt: json['createdAt']?.toString(),
    );
  }

  final String id;
  final String username;
  final String displayName;
  final List<String> permissions;
  final List<String> managedEventCodes;
  final String? createdAt;
}

/// Résultat d'une authentification RBAC.
class AuthLoginResult {
  const AuthLoginResult({
    required this.token,
    required this.role,
    required this.username,
  });

  final String token;
  final String role;
  final String username;
}

/// Service d'administration des comptes RBAC (Superadmin).
class RbacAdminService {
  RbacAdminService({String? baseUrl}) : _baseUrl = baseUrl ?? _defaultApiBase;

  final String _baseUrl;
  String? _token;
  String? _role;

  String? get token => _token;
  String? get role => _role;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;

  void setSession({required String token, String? role}) {
    _token = token;
    _role = role;
  }

  void logout() {
    _token = null;
    _role = null;
  }

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  /// Authentifie un compte (admin, scout, event_admin).
  Future<AuthLoginResult> login({
    required String username,
    required String password,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/auth/login');
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(const Duration(seconds: 15));

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || data['token'] == null) {
      throw Exception(data['error'] ?? 'Identifiants invalides');
    }

    _token = data['token'].toString();
    _role = (data['role'] ?? 'admin').toString();
    return AuthLoginResult(
      token: _token!,
      role: _role!,
      username: username,
    );
  }

  // ── ÉCLAIREURS (SCOUTS) ──────────────────────────────────────────────────

  Future<List<ScoutAccount>> listScouts() async {
    final uri = Uri.parse('$_baseUrl/api/admin/scouts');
    final res = await http
        .get(uri, headers: _authHeaders)
        .timeout(const Duration(seconds: 15));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Erreur lors du chargement des éclaireurs');
    }
    final list = (data['scouts'] as List<dynamic>?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(ScoutAccount.fromJson)
        .toList();
  }

  Future<ScoutAccount> createScout({
    required String username,
    required String password,
    String? displayName,
    List<String>? permissions,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/admin/scouts');
    final res = await http
        .post(
          uri,
          headers: _authHeaders,
          body: jsonEncode({
            'username': username,
            'password': password,
            if (displayName != null && displayName.isNotEmpty)
              'displayName': displayName,
            if (permissions != null) 'permissions': permissions,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Erreur lors de la création de l\'éclaireur');
    }
    return ScoutAccount.fromJson(data['scout'] as Map<String, dynamic>);
  }

  Future<ScoutAccount> updateScout({
    required String id,
    String? displayName,
    List<String>? permissions,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/admin/scouts/$id');
    final res = await http
        .put(
          uri,
          headers: _authHeaders,
          body: jsonEncode({
            if (displayName != null) 'displayName': displayName,
            if (permissions != null) 'permissions': permissions,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Erreur lors de la modification de l\'éclaireur');
    }
    return ScoutAccount.fromJson(data['scout'] as Map<String, dynamic>);
  }

  Future<void> deleteScout(String id) async {
    final uri = Uri.parse('$_baseUrl/api/admin/scouts/$id');
    final res = await http
        .delete(uri, headers: _authHeaders)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(data['error'] ?? 'Erreur lors de la suppression de l\'éclaireur');
    }
  }

  // ── ADMINS D'ÉVÉNEMENTS (EVENT ADMINS) ───────────────────────────────────

  Future<List<EventAdminAccount>> listEventAdmins() async {
    final uri = Uri.parse('$_baseUrl/api/admin/event-admins');
    final res = await http
        .get(uri, headers: _authHeaders)
        .timeout(const Duration(seconds: 15));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Erreur lors du chargement des admins d\'événements');
    }
    final list = (data['admins'] as List<dynamic>?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(EventAdminAccount.fromJson)
        .toList();
  }

  Future<EventAdminAccount> createEventAdmin({
    required String username,
    required String password,
    String? displayName,
    List<String>? managedEventCodes,
    List<String>? permissions,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/admin/event-admins');
    final res = await http
        .post(
          uri,
          headers: _authHeaders,
          body: jsonEncode({
            'username': username,
            'password': password,
            if (displayName != null && displayName.isNotEmpty)
              'displayName': displayName,
            if (managedEventCodes != null)
              'managedEventCodes': managedEventCodes,
            if (permissions != null) 'permissions': permissions,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Erreur lors de la création de l\'admin d\'événement');
    }
    return EventAdminAccount.fromJson(data['admin'] as Map<String, dynamic>);
  }

  Future<EventAdminAccount> updateEventAdmin({
    required String id,
    String? displayName,
    List<String>? managedEventCodes,
    List<String>? permissions,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/admin/event-admins/$id');
    final res = await http
        .put(
          uri,
          headers: _authHeaders,
          body: jsonEncode({
            if (displayName != null) 'displayName': displayName,
            if (managedEventCodes != null)
              'managedEventCodes': managedEventCodes,
            if (permissions != null) 'permissions': permissions,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Erreur lors de la modification de l\'admin d\'événement');
    }
    return EventAdminAccount.fromJson(data['admin'] as Map<String, dynamic>);
  }

  Future<void> deleteEventAdmin(String id) async {
    final uri = Uri.parse('$_baseUrl/api/admin/event-admins/$id');
    final res = await http
        .delete(uri, headers: _authHeaders)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(data['error'] ?? 'Erreur lors de la suppression de l\'admin d\'événement');
    }
  }
}
