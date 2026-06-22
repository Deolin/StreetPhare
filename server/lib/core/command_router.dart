// server/lib/core/command_router.dart
//
// Routeur de commandes avec matrice de permissions et blocage sélectif.
//
// Fonctionnalités :
//   1. Dictionnaire de toutes les commandes système énumérées.
//   2. Matrice de permissions : admin peut verrouiller/déverrouiller
//      sélectivement chaque commande pour les modérateurs.
//   3. Middleware Shelf qui intercepte chaque requête d'API, vérifie
//      l'état de verrouillage pour le rôle du demandeur, et lève
//      une 403 Forbidden si la commande est restreinte.
//
// Format du fichier `command_permissions.json` :
// {
//   "permissions": {
//     "send_alert": { "moderator": true, "admin": true },
//     "create_event": { "moderator": false, "admin": true },
//     ...
//   }
// }

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

final _log = Logger('CommandRouter');

/// Liste exhaustive des commandes système.
enum ServerCommand {
  sendAlert,
  createEvent,
  updateEvent,
  deleteEvent,
  purgeMessages,
  kickPeer,
  broadcastMessage,
  manageAccounts,
  managePermissions,
  viewStats,
  exportData;

  String get jsonValue => name;
}

/// Matrice de permissions : commande → rôle → autorisé.
class CommandPermissions {
  final Map<String, Map<String, bool>> _permissions;

  CommandPermissions._(this._permissions);

  /// Retourne true si [role] peut exécuter [command].
  bool isAllowed(ServerCommand command, String role) {
    final cmdPerms = _permissions[command.jsonValue];
    if (cmdPerms == null) return false;
    // L'admin a toujours tous les droits.
    if (role == 'admin') return true;
    return cmdPerms[role] ?? false;
  }

  /// Active/désactive une commande pour un rôle donné.
  void setPermission(ServerCommand command, String role, bool allowed) {
    _permissions[command.jsonValue] ??= {};
    _permissions[command.jsonValue]![role] = allowed;
  }

  Map<String, dynamic> toJson() => {
        'permissions': _permissions.map((k, v) => MapEntry(k, Map<String, bool>.from(v))),
      };

  factory CommandPermissions.fromJson(Map<String, dynamic> json) {
    final raw = json['permissions'] as Map<String, dynamic>? ?? {};
    final perms = <String, Map<String, bool>>{};
    for (final entry in raw.entries) {
      final inner = entry.value as Map<String, dynamic>? ?? {};
      perms[entry.key] = inner.map((k, v) => MapEntry(k, v as bool));
    }
    return CommandPermissions._(perms);
  }

  /// Crée une matrice par défaut (admin tout, modérateur limité).
  factory CommandPermissions.defaultMatrix() {
    final p = CommandPermissions._({});
    for (final cmd in ServerCommand.values) {
      p._permissions[cmd.jsonValue] = {
        'admin': true,
        'moderator': cmd != ServerCommand.manageAccounts &&
            cmd != ServerCommand.managePermissions &&
            cmd != ServerCommand.exportData,
      };
    }
    return p;
  }
}

// ============================================================================
// CommandRouter
// ============================================================================

class CommandRouter {
  CommandRouter._();
  static final CommandRouter instance = CommandRouter._();

  final String _storePath = 'command_permissions.json';
  late CommandPermissions _permissions;

  Future<void> init() async {
    final file = File(_storePath);
    if (await file.exists()) {
      try {
        final raw = await file.readAsString();
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _permissions = CommandPermissions.fromJson(data);
      } catch (e) {
        _log.warning('Erreur chargement permissions : $e — utilisation défaut.');
        _permissions = CommandPermissions.defaultMatrix();
      }
    } else {
      _permissions = CommandPermissions.defaultMatrix();
    }
    _log.info('CommandRouter initialisé — ${ServerCommand.values.length} commandes');
  }

  Future<void> _persist() async {
    await File(_storePath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(_permissions.toJson()),
    );
  }

  CommandPermissions get permissions => _permissions;

  /// Met à jour la permission d'une commande pour un rôle.
  Future<void> setPermission(ServerCommand command, String role, bool allowed) async {
    if (role == 'admin') return; // Admin toujours tout autorisé.
    _permissions.setPermission(command, role, allowed);
    await _persist();
    _log.info('Permission mise à jour : ${command.jsonValue} → $role=$allowed');
  }

  /// Réinitialise aux valeurs par défaut.
  Future<void> resetToDefaults() async {
    _permissions = CommandPermissions.defaultMatrix();
    await _persist();
  }

  // --------------------------------------------------------------------------
  // Middleware d'autorisation
  // --------------------------------------------------------------------------

  /// Middleware Shelf qui vérifie les permissions pour une commande donnée.
  ///
  /// [command] : la commande requise. Si null, vérifie uniquement
  /// l'authentification (sans vérification de permission).
  Handler requirePermission(Handler innerHandler, {ServerCommand? command}) {
    return (Request request) async {
      final role = request.context['auth_role'] as String?;
      if (role == null) {
        return Response.forbidden(
          jsonEncode({'error': 'UNAUTHORIZED'}),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      if (command != null && !_permissions.isAllowed(command, role)) {
        _log.warning('Permission refusée : $role → ${command.jsonValue}');
        return Response(
          403,
          body: jsonEncode({
            'error': 'FORBIDDEN',
            'command': command.jsonValue,
            'message': 'Vous n\'avez pas la permission d\'exécuter cette commande.',
          }),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
        );
      }

      return innerHandler(request);
    };
  }
}