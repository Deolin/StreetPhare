// server/lib/api/admin_handlers.dart
//
// Endpoints d'administration des comptes et des permissions.
//
// Routes (montées sous /api/ dans server.dart) :
//   GET  /api/health       — Health check public.
//   POST /api/setup        — Création du Master Admin (setup run).
//   POST /api/login        — Connexion, retourne un token.
//   POST /api/logout       — Déconnexion.
//   GET  /api/accounts     — Liste des comptes (admin only).
//   POST /api/accounts     — Créer un modérateur (admin only).
//   DELETE /api/accounts/<id> — Supprimer un compte (admin only).
//   PUT  /api/accounts/<id>/password — Changer mot de passe (admin only).
//   GET  /api/permissions  — Liste des permissions.
//   PUT  /api/permissions  — Modifier une permission (admin only).
//   POST /api/permissions/reset — Réinitialiser les permissions (admin only).
//   *    /api/*            — Fallback 404 JSON pour toute route non trouvée.

import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/auth_manager.dart';
import '../core/command_router.dart';

/// Construit le routeur d'administration.
Router buildAdminRouter() {
  final router = Router();

  // ── Health check (public) ──────────────────────────────────────────
  router.get('/health', (request) {
    return Response.ok(
      jsonEncode({'status': 'ok', 'setup': AuthManager.instance.isSetupComplete}),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  });

  // ── Setup Master Admin (public, une seule fois) ────────────────────
  router.post('/setup', (request) async {
    if (AuthManager.instance.isSetupComplete) {
      return Response.forbidden(
        jsonEncode({'error': 'Le setup est déjà terminé.'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final username = data['username'] as String? ?? '';
      final password = data['password'] as String? ?? '';
      final account = await AuthManager.instance.setupMasterAdmin(username, password);
      return Response.ok(
        jsonEncode({'success': true, 'username': account.username}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on StateError catch (e) {
      return Response.forbidden(
        jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on ArgumentError catch (e) {
      return Response(400,
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Erreur interne : $e'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  });

  // ── Login (public) ────────────────────────────────────────────────
  router.post('/login', (request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final username = data['username'] as String? ?? '';
      final password = data['password'] as String? ?? '';
      final token = await AuthManager.instance.login(username, password);
      return Response.ok(
        jsonEncode({'token': token}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on AuthException catch (e) {
      return Response.forbidden(
        jsonEncode({'error': e.message}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Erreur interne : $e'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  });

  // ── Logout ────────────────────────────────────────────────────────
  router.post('/logout', (request) async {
    final token = _extractBearer(request);
    if (token != null) {
      await AuthManager.instance.logout(token);
    }
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  });

  // ── Liste des comptes (admin only) ────────────────────────────────
  router.get('/accounts', (request) {
    final role = request.context['auth_role'] as String?;
    if (role != 'admin') {
      return Response.forbidden(
        jsonEncode({'error': 'Admin uniquement.'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
    final accounts = AuthManager.instance.listAccounts().map((a) => {
          'id': a.id,
          'username': a.username,
          'role': a.role.jsonValue,
          'created_at': a.createdAt.toIso8601String(),
        }).toList();
    return Response.ok(
      jsonEncode(accounts),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  });

  // ── Créer un modérateur (admin only) ──────────────────────────────
  router.post('/accounts', (request) async {
    final role = request.context['auth_role'] as String?;
    if (role != 'admin') {
      return Response.forbidden(
        jsonEncode({'error': 'Admin uniquement.'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final username = data['username'] as String? ?? '';
      final password = data['password'] as String? ?? '';
      final account = await AuthManager.instance.createModerator(username, password);
      return Response.ok(
        jsonEncode({'success': true, 'id': account.id, 'username': account.username}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on ArgumentError catch (e) {
      return Response(400,
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  });

  // ── Supprimer un compte (admin only) ──────────────────────────────
  router.delete('/accounts/<id>', (request, String id) async {
    final role = request.context['auth_role'] as String?;
    if (role != 'admin') {
      return Response.forbidden(
        jsonEncode({'error': 'Admin uniquement.'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
    try {
      await AuthManager.instance.deleteAccount(id);
      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on StateError catch (e) {
      return Response.forbidden(
        jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Compte introuvable.'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  });

  // ── Changer mot de passe (admin only) ─────────────────────────────
  router.put('/accounts/<id>/password', (request, String id) async {
    final role = request.context['auth_role'] as String?;
    if (role != 'admin') {
      return Response.forbidden(
        jsonEncode({'error': 'Admin uniquement.'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final password = data['password'] as String? ?? '';
      await AuthManager.instance.updateAccountPassword(id, password);
      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } on ArgumentError catch (e) {
      return Response(400,
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  });

  // ── Liste des permissions ─────────────────────────────────────────
  router.get('/permissions', (request) {
    final perms = CommandRouter.instance.permissions.toJson();
    return Response.ok(
      jsonEncode(perms),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  });

  // ── Modifier une permission (admin only) ──────────────────────────
  router.put('/permissions', (request) async {
    final role = request.context['auth_role'] as String?;
    if (role != 'admin') {
      return Response.forbidden(
        jsonEncode({'error': 'Admin uniquement.'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final commandName = data['command'] as String? ?? '';
      final targetRole = data['role'] as String? ?? '';
      final allowed = data['allowed'] as bool? ?? false;
      final command = ServerCommand.values.firstWhere(
        (c) => c.jsonValue == commandName,
        orElse: () => throw ArgumentError('Commande inconnue : $commandName'),
      );
      await CommandRouter.instance.setPermission(command, targetRole, allowed);
      return Response.ok(
        jsonEncode({'success': true}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response(400,
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
  });

  // ── Réinitialiser les permissions (admin only) ────────────────────
  router.post('/permissions/reset', (request) async {
    final role = request.context['auth_role'] as String?;
    if (role != 'admin') {
      return Response.forbidden(
        jsonEncode({'error': 'Admin uniquement.'}),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    }
    await CommandRouter.instance.resetToDefaults();
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  });

  // ── Fallback 404 JSON pour toute route /api/* non trouvée ─────────
  router.all('/<ignored|.*>', (request) {
    return Response.notFound(
      jsonEncode({'error': 'Route not found', 'code': 404}),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  });

  return router;
}

/// Extrait le token Bearer d'une requête.
String? _extractBearer(Request request) {
  final authHeader = request.headers['authorization'];
  if (authHeader != null && authHeader.startsWith('Bearer ')) {
    return authHeader.substring(7).trim();
  }
  final cookie = request.headers['cookie'];
  if (cookie != null) {
    final match = RegExp(r'sp_auth_token=([^;]+)').firstMatch(cookie);
    if (match != null) return match.group(1)!.trim();
  }
  return null;
}