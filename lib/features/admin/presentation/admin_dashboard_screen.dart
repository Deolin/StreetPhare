// lib/features/admin/presentation/admin_dashboard_screen.dart
//
// Panneau d'administration StreetPhare (version consolidée) :
//   1. Authentification Admin (Bearer Token)
//   2. Section Statistiques en temps réel
//   3. Section Gestion des événements (Formulaire validé + Liste & Suppression)
//   4. Section Liste des modérateurs & Comptes RBAC
//   5. Section Contrôles Sandbox & Simulation

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../../../database/alert_visibility_policy.dart';
import '../../sandbox/sandbox_controller.dart';
import '../data/rbac_admin_service.dart';

/// Écran d'administration principal de StreetPhare.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, this.service});

  final RbacAdminService? service;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final RbacAdminService _service;

  final TextEditingController _loginUserCtrl =
      TextEditingController(text: 'admin');
  final TextEditingController _loginPassCtrl = TextEditingController();

  final GlobalKey<FormState> _eventFormKey = GlobalKey<FormState>();
  final TextEditingController _evCodeCtrl = TextEditingController();
  final TextEditingController _evTitleCtrl = TextEditingController();
  final TextEditingController _evZoneCtrl = TextEditingController();
  DateTime _evStartAt = DateTime.now().add(const Duration(hours: 1));

  bool _loggingIn = false;
  bool _loadingDashboard = false;
  bool _creatingEvent = false;

  AdminServerStats? _stats;
  List<AdminEventSummary> _events = const [];
  List<ModeratorAccount> _moderators = const [];
  List<MedicEmergency> _emergencies = const [];
  List<SimulatedStreetMedic> _simMedics = const [];
  List<SimulatedMedicMission> _simMissions = const [];

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? RbacAdminService();
    if (kIsWeb) {
      SandboxController.instance.connect();
    }
  }

  @override
  void dispose() {
    _loginUserCtrl.dispose();
    _loginPassCtrl.dispose();
    _evCodeCtrl.dispose();
    _evTitleCtrl.dispose();
    _evZoneCtrl.dispose();
    SandboxController.instance.disconnect();
    super.dispose();
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF2E7D32),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message.replaceFirst('Exception: ', ''))),
          ],
        ),
        backgroundColor: StreetPhareTheme.danger,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _refreshStatsOnly() async {
    try {
      final stats = await _service.fetchServerStats();
      if (mounted) setState(() => _stats = stats);
    } catch (_) {}
  }

  Future<void> _handleLogin() async {
    final user = _loginUserCtrl.text.trim();
    final pass = _loginPassCtrl.text;
    if (user.isEmpty || pass.isEmpty) {
      _showErrorSnackBar(
          "Veuillez renseigner l'identifiant et le mot de passe.");
      return;
    }
    setState(() => _loggingIn = true);
    try {
      final res = await _service.login(username: user, password: pass);
      _showSuccessSnackBar(
          'Connecté en tant que ${res.username} (${res.role})');
      await _refreshAllAdminData();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  Future<void> _refreshAllAdminData() async {
    setState(() => _loadingDashboard = true);
    try {
      final statsFuture = _service.fetchServerStats();
      final eventsFuture = _service.listEvents();
      List<ModeratorAccount> mods = const [];
      List<MedicEmergency> emergencies = const [];
      List<SimulatedStreetMedic> simMedics = const [];
      List<SimulatedMedicMission> simMissions = const [];
      try {
        mods = await _service.listModerators();
      } catch (_) {}
      try {
        emergencies = await _service.listMedicEmergencies();
      } catch (_) {}
      try {
        final sim = await _service.loadSimulatedStreetMedics();
        simMedics = ((sim['medics'] as List<dynamic>?) ?? const [])
            .whereType<SimulatedStreetMedic>()
            .toList();
        simMissions = ((sim['missions'] as List<dynamic>?) ?? const [])
            .whereType<SimulatedMedicMission>()
            .toList();
      } catch (_) {}
      final results = await Future.wait([statsFuture, eventsFuture]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as AdminServerStats;
        _events = results[1] as List<AdminEventSummary>;
        _moderators = mods;
        _emergencies = emergencies;
        _simMedics = simMedics;
        _simMissions = simMissions;
      });
    } catch (e) {
      _showErrorSnackBar(e.toString());
    } finally {
      if (mounted) setState(() => _loadingDashboard = false);
    }
  }

  Future<void> _handleAcknowledgeEmergency(MedicEmergency e) async {
    setState(() => _loadingDashboard = true);
    try {
      await _service.acknowledgeMedicEmergency(e.id);
      _showSuccessSnackBar('Alerte 112 acquittée.');
      await _refreshAllAdminData();
    } catch (err) {
      _showErrorSnackBar(err.toString());
    } finally {
      if (mounted) setState(() => _loadingDashboard = false);
    }
  }

  Future<void> _handleDeleteEmergency(MedicEmergency e) async {
    setState(() => _loadingDashboard = true);
    try {
      await _service.deleteMedicEmergency(e.id);
      _showSuccessSnackBar('Alerte 112 supprimée.');
      await _refreshAllAdminData();
    } catch (err) {
      _showErrorSnackBar(err.toString());
    } finally {
      if (mounted) setState(() => _loadingDashboard = false);
    }
  }

  /// Ouvre un sélecteur de date + heure pour définir le début de l'événement.
  Future<void> _pickEventStart() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _evStartAt,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_evStartAt),
    );
    if (!mounted) return;
    setState(() {
      _evStartAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _evStartAt.hour,
        time?.minute ?? _evStartAt.minute,
      );
    });
  }

  String _formatDateTime(DateTime d) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${d.day}/${pad(d.month)}/${d.year} ${pad(d.hour)}:${pad(d.minute)}';
  }

  Future<void> _handleCreateEvent() async {
    if (!_service.isAuthenticated) {
      _showErrorSnackBar(
          "Veuillez d'abord vous authentifier en tant qu'administrateur.");
      return;
    }
    if (_eventFormKey.currentState?.validate() != true) {
      _showErrorSnackBar(
          "Veuillez compléter tous les champs obligatoires de l'événement.");
      return;
    }
    setState(() => _creatingEvent = true);
    try {
      final created = await _service.createEvent(
        code: _evCodeCtrl.text.trim().toUpperCase(),
        title: _evTitleCtrl.text.trim(),
        startAt: _evStartAt.toUtc().toIso8601String(),
        generalZone:
            _evZoneCtrl.text.trim().isEmpty ? null : _evZoneCtrl.text.trim(),
      );
      _evCodeCtrl.clear();
      _evTitleCtrl.clear();
      _evZoneCtrl.clear();
      _showSuccessSnackBar(
          'Événement "${created.title}" (${created.code}) créé avec succès !');
      await _refreshAllAdminData();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    } finally {
      if (mounted) setState(() => _creatingEvent = false);
    }
  }

  Future<void> _handleDeleteEvent(String code) async {
    setState(() => _loadingDashboard = true);
    try {
      await _service.deleteEvent(code);
      _showSuccessSnackBar(
          'Événement $code supprimé (signalements liés purgés).');
      await _refreshAllAdminData();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    } finally {
      if (mounted) setState(() => _loadingDashboard = false);
    }
  }

  Future<void> _handleDeleteModerator(ModeratorAccount mod) async {
    setState(() => _loadingDashboard = true);
    try {
      await _service.deleteModerator(mod.id);
      _showSuccessSnackBar('Modérateur @${mod.username} supprimé.');
      await _refreshAllAdminData();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    } finally {
      if (mounted) setState(() => _loadingDashboard = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StreetPhareTheme.darkBackground,
      appBar: AppBar(
        title: const Text('StreetPhare — Panneau d’Administration'),
        backgroundColor: StreetPhareTheme.darkSurface,
        actions: [
          if (_loadingDashboard)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualiser les données',
              onPressed: _service.isAuthenticated
                  ? _refreshAllAdminData
                  : _refreshStatsOnly,
            ),
          ValueListenableBuilder<SandboxConnectionState>(
            valueListenable: SandboxController.instance.connectionState,
            builder: (context, state, _) {
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_statusIcon(state),
                        size: 12, color: _statusColor(state)),
                    const SizedBox(width: 6),
                    Text(_statusLabel(state),
                        style: TextStyle(
                            fontSize: 12, color: _statusColor(state))),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildAuthCard(),
                const SizedBox(height: 16),
                _buildStatsSectionCard(),
                const SizedBox(height: 16),
                _buildMedicEmergencySectionCard(),
                const SizedBox(height: 16),
                _buildEventSectionCard(),
                const SizedBox(height: 12),
                _buildModeratorsSectionCard(),
                const SizedBox(height: 12),
                _buildSandboxSectionCard(),
                const SizedBox(height: 12),
                _buildSimulatedStreetMedicsCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthCard() {
    if (_service.isAuthenticated) {
      return Card(
        color: StreetPhareTheme.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.tealAccent, width: 1),
        ),
        child: ListTile(
          leading: const Icon(Icons.verified_user, color: Colors.tealAccent),
          title: Text(
            'Session Admin active (rôle : ${_service.role ?? 'admin'})',
            style: const TextStyle(
                color: StreetPhareTheme.darkTextPrimary,
                fontWeight: FontWeight.bold),
          ),
          subtitle: const Text(
            'Jeton Bearer actif — Toutes les actions d’administration sont déverrouillées.',
            style: TextStyle(
                color: StreetPhareTheme.darkTextSecondary, fontSize: 12),
          ),
          trailing: OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _service.logout();
              });
              _showSuccessSnackBar('Session administrateur déconnectée.');
            },
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('Déconnexion'),
          ),
        ),
      );
    }

    return Card(
      color: StreetPhareTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.lock_outline, color: Colors.amberAccent),
                SizedBox(width: 8),
                Text(
                  'Authentification Administrateur',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: StreetPhareTheme.darkTextPrimary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: TextField(
                        controller: _loginUserCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Identifiant', isDense: true))),
                const SizedBox(width: 12),
                Expanded(
                    child: TextField(
                        controller: _loginPassCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText: 'Mot de passe', isDense: true),
                        onSubmitted: (_) => _handleLogin())),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _loggingIn ? null : _handleLogin,
                  icon: _loggingIn
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login, size: 18),
                  label: Text(_loggingIn ? 'Connexion…' : 'Connexion'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSectionCard() {
    final stats = _stats;
    return Card(
      color: StreetPhareTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics_outlined, color: Colors.lightBlueAccent),
                SizedBox(width: 8),
                Text(
                  'Statistiques & Paramètres de Densité',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: StreetPhareTheme.darkTextPrimary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildStatTile(
                    label: 'Alertes actives',
                    value: stats != null
                        ? '${stats.alertsActive} / ${stats.alertsTotal}'
                        : '—',
                    icon: Icons.warning_amber,
                    color: Colors.orangeAccent),
                _buildStatTile(
                    label: 'Événements',
                    value: stats != null
                        ? '${stats.eventsCount}'
                        : '${_events.length}',
                    icon: Icons.event_available,
                    color: Colors.greenAccent),
                _buildStatTile(
                    label: 'Clients Mesh',
                    value: stats != null ? '${stats.meshClients}' : '—',
                    icon: Icons.hub_outlined,
                    color: Colors.cyanAccent),
                _buildStatTile(
                    label: 'Seuil Densité Foule',
                    value:
                        '≥ ${AlertVisibilityPolicy.minCrowdDensityThreshold} pers.',
                    icon: Icons.groups,
                    color: Colors.purpleAccent),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicEmergencySectionCard() {
    if (!_service.isAuthenticated) return const SizedBox.shrink();
    final pending =
        _emergencies.where((e) => !e.emergencyAcknowledged).toList();
    final acknowledged =
        _emergencies.where((e) => e.emergencyAcknowledged).toList();
    return Card(
      color: StreetPhareTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emergency, color: Color(0xFFD32F2F)),
                const SizedBox(width: 8),
                const Text(
                  'Alertes street-medic (112)',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: StreetPhareTheme.darkTextPrimary),
                ),
                const SizedBox(width: 8),
                if (pending.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD32F2F),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${pending.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_emergencies.isEmpty)
              const Text(
                'Aucune alerte de détresse en cours.',
                style: TextStyle(
                    fontSize: 13, color: StreetPhareTheme.darkTextSecondary),
              )
            else ...[
              ...pending.map(_buildEmergencyTile),
              ...acknowledged.map(_buildEmergencyTile),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyTile(MedicEmergency e) {
    final ack = e.emergencyAcknowledged;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.local_hospital,
        color: ack ? Colors.grey : const Color(0xFFD32F2F),
      ),
      title: Text(
        'Victime non soignable sur place',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: ack
              ? StreetPhareTheme.darkTextSecondary
              : StreetPhareTheme.darkTextPrimary,
        ),
      ),
      subtitle: Text(
        '📍 ${e.injuredLatitude.toStringAsFixed(5)}, '
        '${e.injuredLongitude.toStringAsFixed(5)}'
        '${e.note.isNotEmpty ? ' — ${e.note}' : ''}',
        style: const TextStyle(
            fontSize: 12, color: StreetPhareTheme.darkTextSecondary),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ack)
            const Text('Acquittée',
                style: TextStyle(fontSize: 12, color: Colors.grey))
          else
            TextButton(
              onPressed: () => _handleAcknowledgeEmergency(e),
              child: const Text('Acquitter'),
            ),
          TextButton(
            onPressed: () => _handleDeleteEmergency(e),
            child: const Text('Supprimer',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile(
      {required String label,
      required String value,
      required IconData icon,
      required Color color}) {
    return Container(
      width: 175,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: StreetPhareTheme.darkTextPrimary)),
                Text(label,
                    style: const TextStyle(
                        fontSize: 11,
                        color: StreetPhareTheme.darkTextSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventSectionCard() {
    return Card(
      color: StreetPhareTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.event_note, color: Colors.amberAccent),
                SizedBox(width: 8),
                Text(
                  'Gestion des Événements',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: StreetPhareTheme.darkTextPrimary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Form(
              key: _eventFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _evCodeCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                              labelText: 'Code *',
                              hintText: 'MANIF-2026',
                              isDense: true),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Code requis'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _evTitleCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Titre *',
                              hintText: 'Cortège citoyen',
                              isDense: true),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Titre requis'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickEventStart,
                          icon: const Icon(Icons.schedule, size: 18),
                          label: Text(
                            'Début : ${_formatDateTime(_evStartAt)}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                          child: TextFormField(
                              controller: _evZoneCtrl,
                              decoration: const InputDecoration(
                                  labelText: 'Zone (optionnel)',
                                  hintText: 'Fleurus',
                                  isDense: true))),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _creatingEvent ? null : _handleCreateEvent,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amberAccent,
                            foregroundColor: Colors.black),
                        icon: _creatingEvent
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black))
                            : const Icon(Icons.add, size: 18),
                        label: Text(
                            _creatingEvent ? 'Création…' : 'Créer l’événement'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            if (!_service.isAuthenticated)
              const Text('Authentifiez-vous pour gérer les événements.',
                  style: TextStyle(
                      color: StreetPhareTheme.darkTextSecondary, fontSize: 12))
            else if (_events.isEmpty)
              const Text('Aucun événement enregistré.',
                  style: TextStyle(
                      color: StreetPhareTheme.darkTextSecondary, fontSize: 12))
            else
              for (final ev in _events)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading:
                      const Icon(Icons.flag_circle, color: Colors.greenAccent),
                  title: Text('${ev.title} (${ev.code})',
                      style: const TextStyle(
                          color: StreetPhareTheme.darkTextPrimary,
                          fontWeight: FontWeight.w600)),
                  subtitle: Text('Début : ${ev.startAt}',
                      style: const TextStyle(
                          color: StreetPhareTheme.darkTextSecondary,
                          fontSize: 11)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent, size: 20),
                    onPressed: _loadingDashboard
                        ? null
                        : () => _handleDeleteEvent(ev.code),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeratorsSectionCard() {
    return Card(
      color: StreetPhareTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.people_outline, color: Colors.lightBlueAccent),
                SizedBox(width: 8),
                Text(
                  'Gestion des Modérateurs',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: StreetPhareTheme.darkTextPrimary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!_service.isAuthenticated)
              const Text('Authentifiez-vous pour gérer les modérateurs.',
                  style: TextStyle(
                      color: StreetPhareTheme.darkTextSecondary, fontSize: 12))
            else if (_moderators.isEmpty)
              const Text('Aucun modérateur enregistré.',
                  style: TextStyle(
                      color: StreetPhareTheme.darkTextSecondary, fontSize: 12))
            else
              for (final mod in _moderators)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person, color: Colors.greenAccent),
                  title: Text(mod.username,
                      style: const TextStyle(
                          color: StreetPhareTheme.darkTextPrimary,
                          fontWeight: FontWeight.w600)),
                  subtitle: Text('Rôles : ${mod.permissions.join(', ')}',
                      style: const TextStyle(
                          color: StreetPhareTheme.darkTextSecondary,
                          fontSize: 11)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent, size: 20),
                    onPressed: _loadingDashboard
                        ? null
                        : () => _handleDeleteModerator(mod),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshSimMedics() async {
    try {
      final sim = await _service.loadSimulatedStreetMedics();
      if (!mounted) return;
      setState(() {
        _simMedics = ((sim['medics'] as List<dynamic>?) ?? const [])
            .whereType<SimulatedStreetMedic>()
            .toList();
        _simMissions = ((sim['missions'] as List<dynamic>?) ?? const [])
            .whereType<SimulatedMedicMission>()
            .toList();
      });
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _handleCreateFakeMedic({bool busy = false}) async {
    try {
      await _service.createFakeStreetMedic(busy: busy);
      _showSuccessSnackBar(
          busy ? 'Faux medic « occupé » créé.' : 'Faux medic créé.');
      await _refreshSimMedics();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _handleSimMedicAction(SimulatedStreetMedic m,
      {String? status, bool? sharing, bool? busy}) async {
    try {
      await _service.setFakeStreetMedicState(m.userId,
          status: status, sharing: sharing, busy: busy);
      await _refreshSimMedics();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _handleDeleteFakeMedic(String userId) async {
    try {
      await _service.deleteFakeStreetMedic(userId);
      _showSuccessSnackBar('Faux medic supprimé.');
      await _refreshSimMedics();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _handleCreateFakeMission(String medicId,
      {bool accept = false}) async {
    try {
      await _service.createFakeMission(medicId: medicId, accept: accept);
      await _refreshSimMedics();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _handleFakeMissionState(String missionId, String status) async {
    try {
      await _service.setFakeMissionState(missionId, status);
      await _refreshSimMedics();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  bool _isMedicBusy(String userId) =>
      _simMissions.any((m) => m.medicId == userId && m.status == 'accepted');

  Widget _buildSimulatedStreetMedicsCard() {
    if (!_service.isAuthenticated) return const SizedBox.shrink();
    return Card(
      color: StreetPhareTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.medical_services, color: Color(0xFF26A69A)),
                const SizedBox(width: 8),
                const Text(
                  'Street-medics simulés',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: StreetPhareTheme.darkTextPrimary),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => _handleCreateFakeMedic(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Disponible'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _handleCreateFakeMedic(busy: true),
                  icon: const Icon(Icons.local_hospital, size: 16),
                  label: const Text('Occupé'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_simMedics.isEmpty)
              const Text(
                'Aucun faux medic. Ajoutez-en un pour tester le flux '
                'd\'intervention complet.',
                style: TextStyle(
                    fontSize: 13, color: StreetPhareTheme.darkTextSecondary),
              )
            else
              ..._simMedics.map(_buildSimMedicTile),
            if (_simMissions.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Missions simulées',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: StreetPhareTheme.darkTextSecondary)),
              const SizedBox(height: 4),
              ..._simMissions.map(_buildSimMissionTile),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSimMedicTile(SimulatedStreetMedic m) {
    final busy = _isMedicBusy(m.userId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                busy ? Icons.local_hospital : Icons.person_pin,
                color: busy ? const Color(0xFFFFB300) : const Color(0xFF26A69A),
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${m.userId} — ${busy ? 'occupé' : 'disponible'} '
                  '${m.sharing ? '(partage actif)' : '(partage coupé)'}',
                  style: TextStyle(
                      fontSize: 13,
                      color: m.sharing
                          ? StreetPhareTheme.darkTextPrimary
                          : StreetPhareTheme.darkTextSecondary),
                ),
              ),
              IconButton(
                tooltip: 'Supprimer',
                icon: const Icon(Icons.delete_outline, size: 18),
                color: StreetPhareTheme.danger,
                onPressed: () => _handleDeleteFakeMedic(m.userId),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (busy)
                ActionChip(
                  label: const Text('Libérer'),
                  onPressed: () => _handleSimMedicAction(m, busy: false),
                )
              else
                ActionChip(
                  label: const Text('Occuper'),
                  onPressed: () => _handleSimMedicAction(m, busy: true),
                ),
              ActionChip(
                label: Text(m.sharing ? 'Couper partage' : 'Activer partage'),
                onPressed: () => _handleSimMedicAction(m, sharing: !m.sharing),
              ),
              ActionChip(
                label: const Text('Mission (blessé)'),
                onPressed: () => _handleCreateFakeMission(m.userId),
              ),
              ActionChip(
                label: const Text('Mission + accept.'),
                onPressed: () =>
                    _handleCreateFakeMission(m.userId, accept: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSimMissionTile(SimulatedMedicMission m) {
    final label = m.status == 'accepted'
        ? 'en intervention'
        : m.status == 'completed'
            ? (m.outcome == 'emergency' ? 'urg. 112' : 'terminée')
            : m.status;
    final pending = m.status == 'pending';
    final accepted = m.status == 'accepted';
    final finished = m.status == 'completed' || m.status == 'cancelled';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emergency, size: 16, color: Color(0xFFD32F2F)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${m.id.substring(0, m.id.length > 8 ? 8 : m.id.length)} '
                  '→ medic ${m.medicId.substring(0, m.medicId.length > 10 ? 10 : m.medicId.length)} '
                  '[$label]',
                  style: const TextStyle(
                      fontSize: 12, color: StreetPhareTheme.darkTextSecondary),
                ),
              ),
            ],
          ),
          if (!finished)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (pending)
                  ActionChip(
                    label: const Text('Accepter'),
                    onPressed: () => _handleFakeMissionState(m.id, 'accepted'),
                  ),
                if (pending)
                  ActionChip(
                    label: const Text('Refuser'),
                    onPressed: () => _handleFakeMissionState(m.id, 'refused'),
                  ),
                if (accepted)
                  ActionChip(
                    label: const Text('Terminer (soignée)'),
                    onPressed: () => _handleFakeMissionState(m.id, 'completed'),
                  ),
                if (accepted)
                  ActionChip(
                    label: const Text('Urgence 112'),
                    onPressed: () => _handleFakeMissionState(m.id, 'emergency'),
                  ),
                if (pending || accepted)
                  ActionChip(
                    label: const Text('Annuler'),
                    onPressed: () => _handleFakeMissionState(m.id, 'cancelled'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSandboxSectionCard() {
    return Card(
      color: StreetPhareTheme.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.security, color: Colors.deepOrangeAccent),
                SizedBox(width: 8),
                Text(
                  'Contrôles Sandbox',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: StreetPhareTheme.darkTextPrimary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SandboxButton(
                    label: 'Connexion au sandbox',
                    icon: Icons.link,
                    color: Colors.blueAccent,
                    onTap: _toggleSandboxConnection),
                const SizedBox(height: 8),
                _SandboxButton(
                    label: 'Lancer une simulation',
                    icon: Icons.play_circle_fill,
                    color: Colors.greenAccent,
                    onTap: _runSandboxSimulation),
                const SizedBox(height: 8),
                _SandboxButton(
                    label: 'Recharger le sandbox',
                    icon: Icons.refresh,
                    color: Colors.amberAccent,
                    onTap: _reloadSandbox),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleSandboxConnection() async {
    try {
      final controller = SandboxController.instance;
      if (controller.isBackendConnected) {
        controller.disconnect();
        _showSuccessSnackBar('Sandbox déconnecté.');
      } else {
        await controller.connect();
        _showSuccessSnackBar('Sandbox connecté.');
      }
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _runSandboxSimulation() async {
    try {
      await SandboxController.instance.simulateUsers();
      _showSuccessSnackBar('Simulation sandbox lancée.');
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _reloadSandbox() async {
    try {
      await SandboxController.instance.injectAlerts();
      _showSuccessSnackBar('Sandbox rechargé.');
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  IconData _statusIcon(SandboxConnectionState state) {
    switch (state) {
      case SandboxConnectionState.connected:
        return Icons.cloud_done;
      case SandboxConnectionState.connecting:
        return Icons.cloud_queue;
      case SandboxConnectionState.disconnected:
        return Icons.cloud_off;
      case SandboxConnectionState.error:
        return Icons.error_outline;
    }
  }

  Color _statusColor(SandboxConnectionState state) {
    switch (state) {
      case SandboxConnectionState.connected:
        return Colors.greenAccent;
      case SandboxConnectionState.connecting:
        return Colors.amberAccent;
      case SandboxConnectionState.disconnected:
        return Colors.grey;
      case SandboxConnectionState.error:
        return Colors.redAccent;
    }
  }

  String _statusLabel(SandboxConnectionState state) {
    switch (state) {
      case SandboxConnectionState.connected:
        return 'Connecté';
      case SandboxConnectionState.connecting:
        return 'Connexion…';
      case SandboxConnectionState.disconnected:
        return 'Déconnecté';
      case SandboxConnectionState.error:
        return 'Erreur';
    }
  }
}

/// Bouton d’injection sandbox avec effet de pression.
class _SandboxButton extends StatefulWidget {
  const _SandboxButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_SandboxButton> createState() => _SandboxButtonState();
}

class _SandboxButtonState extends State<_SandboxButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _pressed
              ? widget.color.withValues(alpha: 0.25)
              : widget.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: widget.color.withValues(alpha: _pressed ? 0.7 : 0.35),
            width: _pressed ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.icon, color: widget.color, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                widget.label,
                style: TextStyle(
                  color: widget.color,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
