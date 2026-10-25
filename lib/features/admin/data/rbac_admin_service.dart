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

/// Modèle représentant un compte Modérateur.
class ModeratorAccount {
  const ModeratorAccount({
    required this.id,
    required this.username,
    required this.permissions,
    this.createdAt,
  });

  factory ModeratorAccount.fromJson(Map<String, dynamic> json) {
    return ModeratorAccount(
      id: (json['id'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      permissions: (json['permissions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      createdAt: json['createdAt']?.toString(),
    );
  }

  final String id;
  final String username;
  final List<String> permissions;
  final String? createdAt;
}

/// Modèle résumé d'un événement géré depuis le panneau d'administration.
class AdminEventSummary {
  const AdminEventSummary({
    required this.code,
    required this.title,
    required this.startAt,
    this.endAt,
    this.generalZone,
    this.status,
  });

  factory AdminEventSummary.fromJson(Map<String, dynamic> json) {
    return AdminEventSummary(
      code: (json['code'] ?? '').toString().toUpperCase(),
      title: (json['title'] ?? '').toString(),
      startAt: (json['startAt'] ?? '').toString(),
      endAt: json['endAt']?.toString(),
      generalZone: json['generalZone']?.toString(),
      status: json['status']?.toString(),
    );
  }

  final String code;
  final String title;
  final String startAt;
  final String? endAt;
  final String? generalZone;
  final String? status;
}

/// Statistiques temps réel du serveur pour le panneau d'administration.
class AdminServerStats {
  const AdminServerStats({
    required this.alertsActive,
    required this.alertsTotal,
    required this.eventsCount,
    required this.meshClients,
    required this.adminClients,
    required this.uptimeSeconds,
    required this.serverType,
  });

  factory AdminServerStats.fromJson(Map<String, dynamic> json) {
    final alerts = json['alerts'] as Map<String, dynamic>? ?? const {};
    return AdminServerStats(
      alertsActive: (alerts['active'] as num?)?.toInt() ?? 0,
      alertsTotal: (alerts['total'] as num?)?.toInt() ?? 0,
      eventsCount: (json['events'] as num?)?.toInt() ?? 0,
      meshClients: (json['meshClients'] as num?)?.toInt() ?? 0,
      adminClients: (json['adminClients'] as num?)?.toInt() ?? 0,
      uptimeSeconds: (json['uptime'] as num?)?.toInt() ?? 0,
      serverType: (json['serverType'] ?? 'PRIMARY').toString(),
    );
  }

  final int alertsActive;
  final int alertsTotal;
  final int eventsCount;
  final int meshClients;
  final int adminClients;
  final int uptimeSeconds;
  final String serverType;
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

  // ── GESTION DES ÉVÉNEMENTS (/api/admin/events) ───────────────────────────

  Future<List<AdminEventSummary>> listEvents() async {
    final uri = Uri.parse('$_baseUrl/api/admin/events');
    final res = await http
        .get(uri, headers: _authHeaders)
        .timeout(const Duration(seconds: 15));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Erreur lors du chargement des événements');
    }
    final list = (data['events'] as List<dynamic>?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(AdminEventSummary.fromJson)
        .toList();
  }

  Future<AdminEventSummary> createEvent({
    required String code,
    required String title,
    String? startAt,
    String? endAt,
    String? visibleAt,
    String? generalZone,
    double? destinationLatitude,
    double? destinationLongitude,
  }) async {
    if (_token == null || _token!.isEmpty) {
      throw Exception('Authentification admin requise (jeton Bearer manquant)');
    }
    final cleanCode = code.trim().toUpperCase();
    final cleanTitle = title.trim();
    if (cleanCode.isEmpty || cleanTitle.isEmpty) {
      throw Exception('Le code et le titre de l\'événement sont obligatoires');
    }
    final effectiveStart = (startAt != null && startAt.trim().isNotEmpty)
        ? startAt.trim()
        : DateTime.now().toUtc().toIso8601String();

    final uri = Uri.parse('$_baseUrl/api/admin/events');
    final res = await http
        .post(
          uri,
          headers: _authHeaders,
          body: jsonEncode({
            'code': cleanCode,
            'title': cleanTitle,
            'startAt': effectiveStart,
            if (endAt != null && endAt.isNotEmpty) 'endAt': endAt,
            if (visibleAt != null && visibleAt.isNotEmpty) 'visibleAt': visibleAt,
            if (generalZone != null && generalZone.trim().isNotEmpty)
              'generalZone': generalZone.trim(),
            if (destinationLatitude != null)
              'destinationLatitude': destinationLatitude,
            if (destinationLongitude != null)
              'destinationLongitude': destinationLongitude,
          }),
        )
        .timeout(const Duration(seconds: 15));

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception(
        data['error'] ?? 'Échec de la création de l\'événement (HTTP ${res.statusCode})',
      );
    }
    final evMap = (data['event'] as Map<String, dynamic>?) ?? data;
    return AdminEventSummary.fromJson(evMap);
  }

  Future<void> deleteEvent(String code) async {
    final cleanCode = Uri.encodeComponent(code.trim().toUpperCase());
    final uri = Uri.parse('$_baseUrl/api/admin/events/$cleanCode');
    final res = await http
        .delete(uri, headers: _authHeaders)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(data['error'] ?? 'Erreur lors de la suppression de l\'événement');
    }
  }

  // ── MODÉRATEURS (/api/admin/moderators) ──────────────────────────────────

  Future<List<ModeratorAccount>> listModerators() async {
    final uri = Uri.parse('$_baseUrl/api/admin/moderators');
    final res = await http
        .get(uri, headers: _authHeaders)
        .timeout(const Duration(seconds: 15));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Erreur lors du chargement des modérateurs');
    }
    final list = (data['moderators'] as List<dynamic>?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(ModeratorAccount.fromJson)
        .toList();
  }

  Future<ModeratorAccount> createModerator({
    required String username,
    required String password,
    List<String> permissions = const ['reportValidate', 'chatModerate'],
  }) async {
    final uri = Uri.parse('$_baseUrl/api/admin/moderators');
    final res = await http
        .post(
          uri,
          headers: _authHeaders,
          body: jsonEncode({
            'username': username.trim(),
            'password': password,
            'permissions': permissions,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Erreur lors de la création du modérateur');
    }
    return ModeratorAccount.fromJson(data['moderator'] as Map<String, dynamic>);
  }

  Future<void> deleteModerator(String id) async {
    final uri = Uri.parse('$_baseUrl/api/admin/moderators/$id');
    final res = await http
        .delete(uri, headers: _authHeaders)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(data['error'] ?? 'Erreur lors de la suppression du modérateur');
    }
  }

  // ── STATISTIQUES SERVEUR (/api/status) ───────────────────────────────────

  Future<AdminServerStats> fetchServerStats() async {
    final uri = Uri.parse('$_baseUrl/api/status');
    final res = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Impossible de récupérer les statistiques');
    }
    return AdminServerStats.fromJson(data);
  }
}
