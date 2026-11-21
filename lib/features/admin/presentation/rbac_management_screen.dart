// lib/features/admin/presentation/rbac_management_screen.dart
//
// Écran d'administration RBAC :
//   - Connexion Superadmin / Admin Principal
//   - Création, édition et suppression des Éclaireurs (Scouts)
//   - Création, édition et suppression des Administrateurs d'Événements (Event Admins)

import 'package:material_ui/material_ui.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../data/rbac_admin_service.dart';

class RbacManagementScreen extends StatefulWidget {
  const RbacManagementScreen({super.key, this.service});

  final RbacAdminService? service;

  @override
  State<RbacManagementScreen> createState() => _RbacManagementScreenState();
}

class _RbacManagementScreenState extends State<RbacManagementScreen>
    with SingleTickerProviderStateMixin {
  late final RbacAdminService _service;
  late final TabController _tabController;

  final TextEditingController _userCtrl = TextEditingController(text: 'admin');
  final TextEditingController _passCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  List<ScoutAccount> _scouts = const [];
  List<EventAdminAccount> _eventAdmins = const [];
  List<GlobalAdminAccount> _admins = const [];
  List<PendingEvent> _pendingEvents = const [];

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? RbacAdminService.instance;
    _tabController = TabController(length: 4, vsync: this);
    if (_service.isAuthenticated) {
      _refreshAll();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _service.login(
        username: _userCtrl.text.trim(),
        password: _passCtrl.text,
      );
      await _refreshAll();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.listScouts(),
        _service.listEventAdmins(),
        _service.listAdmins(),
        _service.listPendingEvents(),
      ]);
      if (!mounted) return;
      setState(() {
        _scouts = results[0] as List<ScoutAccount>;
        _eventAdmins = results[1] as List<EventAdminAccount>;
        _admins = results[2] as List<GlobalAdminAccount>;
        _pendingEvents = results[3] as List<PendingEvent>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showCreateScoutDialog() async {
    final usernameCtrl = TextEditingController();
    final displayCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StreetPhareTheme.darkSurface,
        title: const Text(
          'Nouvel Éclaireur (Scout)',
          style: TextStyle(color: StreetPhareTheme.darkTextPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: usernameCtrl,
              decoration:
                  const InputDecoration(labelText: 'Identifiant (username)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: displayCtrl,
              decoration:
                  const InputDecoration(labelText: 'Nom affiché (optionnel)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mot de passe'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Créer'),
          ),
        ],
      ),
    );

    if (confirmed == true && usernameCtrl.text.trim().isNotEmpty) {
      try {
        await _service.createScout(
          username: usernameCtrl.text.trim(),
          password: passwordCtrl.text,
          displayName: displayCtrl.text.trim(),
        );
        await _refreshAll();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _showCreateOrEditEventAdminDialog(
      {EventAdminAccount? existing}) async {
    final usernameCtrl = TextEditingController(text: existing?.username ?? '');
    final displayCtrl =
        TextEditingController(text: existing?.displayName ?? '');
    final codesCtrl = TextEditingController(
      text: existing?.managedEventCodes.join(', ') ?? '',
    );
    final passwordCtrl = TextEditingController();
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StreetPhareTheme.darkSurface,
        title: Text(
          existing == null
              ? 'Nouvel Admin d\'Événement'
              : 'Modifier ${existing.username}',
          style: const TextStyle(color: StreetPhareTheme.darkTextPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (existing == null) ...[
              TextField(
                controller: usernameCtrl,
                decoration:
                    const InputDecoration(labelText: 'Identifiant (username)'),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: displayCtrl,
              decoration:
                  const InputDecoration(labelText: 'Nom affiché / pseudo'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email (obligatoire)',
                hintText: 'admin@exemple.be',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Téléphone (obligatoire)',
                hintText: '+32 470 12 34 56',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codesCtrl,
              decoration: const InputDecoration(
                labelText: 'Codes événements (séparés par virgule)',
                hintText: 'MANIF-01, FLEURUS-2026',
              ),
            ),
            if (existing == null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Mot de passe'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(existing == null ? 'Créer' : 'Enregistrer'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final codes = codesCtrl.text
          .split(',')
          .map((s) => s.trim().toUpperCase())
          .where((s) => s.isNotEmpty)
          .toList();

      try {
        if (existing == null) {
          await _service.createEventAdmin(
            username: usernameCtrl.text.trim(),
            password: passwordCtrl.text,
            displayName: displayCtrl.text.trim(),
            email: emailCtrl.text.trim(),
            phone: phoneCtrl.text.trim(),
            managedEventCodes: codes,
          );
        } else {
          await _service.updateEventAdmin(
            id: existing.id,
            displayName: displayCtrl.text.trim(),
            email: emailCtrl.text.trim(),
            phone: phoneCtrl.text.trim(),
            managedEventCodes: codes,
          );
        }
        await _refreshAll();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StreetPhareTheme.darkBackground,
      appBar: AppBar(
        title: const Text('Administration RBAC'),
        backgroundColor: StreetPhareTheme.darkSurface,
        bottom: _service.isAuthenticated
            ? TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(
                      icon: Icon(Icons.verified_user),
                      text: 'Éclaireurs (Scouts)'),
                  Tab(
                      icon: Icon(Icons.event_available),
                      text: 'Admins d\'Événements'),
                  Tab(
                      icon: Icon(Icons.admin_panel_settings),
                      text: 'Administrateurs'),
                  Tab(
                      icon: Icon(Icons.pending_actions),
                      text: 'Événements à valider'),
                ],
              )
            : null,
        actions: [
          if (_service.isAuthenticated) ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _refreshAll,
              tooltip: 'Actualiser',
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => setState(() => _service.logout()),
              tooltip: 'Déconnexion',
            ),
          ],
        ],
      ),
      body: !_service.isAuthenticated ? _buildLoginView() : _buildRbacTabs(),
      floatingActionButton: _service.isAuthenticated
          ? FloatingActionButton.extended(
              onPressed: () {
                if (_tabController.index == 0) {
                  _showCreateScoutDialog();
                } else if (_tabController.index == 1) {
                  _showCreateOrEditEventAdminDialog();
                } else if (_tabController.index == 2) {
                  _showCreateOrEditAdminDialog();
                }
              },
              icon: const Icon(Icons.person_add),
              label: const Text('Ajouter'),
            )
          : null,
    );
  }

  Widget _buildLoginView() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Card(
          color: StreetPhareTheme.darkSurface,
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Connexion Superadmin',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: StreetPhareTheme.darkTextPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _userCtrl,
                  decoration: const InputDecoration(labelText: 'Utilisateur'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Mot de passe'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loading ? null : _handleLogin,
                  child: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Se connecter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRbacTabs() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return TabBarView(
      controller: _tabController,
      children: [
        _buildScoutsList(),
        _buildEventAdminsList(),
        _buildAdminsList(),
        _buildPendingEventsList(),
      ],
    );
  }

  Widget _buildScoutsList() {
    if (_scouts.isEmpty) {
      return const Center(
        child: Text(
          'Aucun éclaireur enregistré.',
          style: TextStyle(color: StreetPhareTheme.darkTextSecondary),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _scouts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final scout = _scouts[index];
        return Card(
          color: StreetPhareTheme.darkSurface,
          child: ListTile(
            leading: const Icon(Icons.verified_user, color: Colors.tealAccent),
            title: Text(
              '${scout.displayName} (@${scout.username})',
              style: const TextStyle(color: StreetPhareTheme.darkTextPrimary),
            ),
            subtitle: Text(
              'Privilèges : ${scout.permissions.join(', ')}',
              style: const TextStyle(color: StreetPhareTheme.darkTextSecondary),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () async {
                await _service.deleteScout(scout.id);
                await _refreshAll();
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildEventAdminsList() {
    if (_eventAdmins.isEmpty) {
      return const Center(
        child: Text(
          'Aucun administrateur d\'événement enregistré.',
          style: TextStyle(color: StreetPhareTheme.darkTextSecondary),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _eventAdmins.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final admin = _eventAdmins[index];
        final eventsLabel = admin.managedEventCodes.isEmpty
            ? 'Aucun événement assigné'
            : 'Événements : ${admin.managedEventCodes.join(', ')}';
        return Card(
          color: StreetPhareTheme.darkSurface,
          child: ListTile(
            leading:
                const Icon(Icons.event_available, color: Colors.amberAccent),
            title: Text(
              '${admin.displayName} (@${admin.username})',
              style: const TextStyle(color: StreetPhareTheme.darkTextPrimary),
            ),
            subtitle: Text(
              eventsLabel,
              style: const TextStyle(color: StreetPhareTheme.darkTextSecondary),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      color: Colors.lightBlueAccent),
                  onPressed: () =>
                      _showCreateOrEditEventAdminDialog(existing: admin),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () async {
                    await _service.deleteEventAdmin(admin.id);
                    await _refreshAll();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── ADMINISTRATEURS GLOBAUX ─────────────────────────────────────────────

  Future<void> _showCreateOrEditAdminDialog(
      {GlobalAdminAccount? existing}) async {
    final usernameCtrl = TextEditingController(text: existing?.username ?? '');
    final displayCtrl =
        TextEditingController(text: existing?.displayName ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final passwordCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StreetPhareTheme.darkSurface,
        title: Text(
          existing == null
              ? 'Nouvel Administrateur Global'
              : 'Modifier l\'Administrateur',
          style: const TextStyle(color: StreetPhareTheme.darkTextPrimary),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (existing == null) ...[
                TextField(
                  controller: usernameCtrl,
                  decoration: const InputDecoration(labelText: 'Identifiant'),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: displayCtrl,
                decoration: const InputDecoration(labelText: 'Nom affiché'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email (obligatoire)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Téléphone (obligatoire)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: existing == null
                      ? 'Mot de passe (min. 8)'
                      : 'Nouveau mot de passe (optionnel)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (existing == null) {
        await _service.createAdmin(
          username: usernameCtrl.text.trim(),
          displayName: displayCtrl.text.trim(),
          email: emailCtrl.text.trim(),
          phone: phoneCtrl.text.trim(),
          password: passwordCtrl.text,
        );
      } else {
        await _service.updateAdmin(
          id: existing.id,
          displayName: displayCtrl.text.trim(),
          email: emailCtrl.text.trim(),
          phone: phoneCtrl.text.trim(),
          password: passwordCtrl.text.isNotEmpty ? passwordCtrl.text : null,
        );
      }
      await _refreshAll();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildAdminsList() {
    if (_admins.isEmpty) {
      return const Center(
        child: Text(
          'Aucun administrateur global.',
          style: TextStyle(color: StreetPhareTheme.darkTextSecondary),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _admins.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final admin = _admins[index];
        final status = admin.emailConfirmed
            ? '✅ Email confirmé'
            : '⏳ En attente de confirmation email';
        return Card(
          color: StreetPhareTheme.darkSurface,
          child: ListTile(
            leading: const Icon(Icons.admin_panel_settings,
                color: Colors.purpleAccent),
            title: Text(
              '${admin.displayName} (@${admin.username})',
              style: const TextStyle(color: StreetPhareTheme.darkTextPrimary),
            ),
            subtitle: Text(
              '${admin.email} · ${admin.phone}\n$status',
              style: const TextStyle(color: StreetPhareTheme.darkTextSecondary),
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      color: Colors.lightBlueAccent),
                  onPressed: () =>
                      _showCreateOrEditAdminDialog(existing: admin),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () async {
                    await _service.deleteAdmin(admin.id);
                    await _refreshAll();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── ÉVÉNEMENTS EN ATTENTE DE VALIDATION ─────────────────────────────────

  Widget _buildPendingEventsList() {
    if (_pendingEvents.isEmpty) {
      return const Center(
        child: Text(
          'Aucun événement en attente de validation.',
          style: TextStyle(color: StreetPhareTheme.darkTextSecondary),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingEvents.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final pending = _pendingEvents[index];
        return Card(
          color: StreetPhareTheme.darkSurface,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pending.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: StreetPhareTheme.darkTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${pending.city} · ${pending.startDate}',
                  style: const TextStyle(
                      color: StreetPhareTheme.darkTextSecondary),
                ),
                Text(
                  '${pending.pseudo} — ${pending.email} — ${pending.phone}',
                  style: const TextStyle(
                      color: StreetPhareTheme.darkTextSecondary, fontSize: 12),
                ),
                if (pending.summary.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    pending.summary,
                    style: const TextStyle(
                        color: StreetPhareTheme.darkTextSecondary,
                        fontSize: 13),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check),
                        label: const Text('Accepter'),
                        onPressed: () async {
                          await _service.acceptPendingEvent(pending.id);
                          await _refreshAll();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.close),
                        label: const Text('Rejeter'),
                        onPressed: () async {
                          await _service.rejectPendingEvent(pending.id);
                          await _refreshAll();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
