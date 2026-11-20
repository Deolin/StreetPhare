// lib/features/trust_group/presentation/trust_group_screen.dart
//
// Écran de gestion du « groupe de confiance » :
//   - Affiche l'ID secondaire fixe de l'appareil (à partager hors-ligne).
//   - Active/désactive le partage de position.
//   - Ajoute/retire des amis de confiance (alias + ID fixe).

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../domain/models/follow_request.dart';
import '../domain/models/trust_group_member.dart';
import 'follow_request_dialog.dart';
import 'trust_group_service.dart';

class TrustGroupScreen extends StatefulWidget {
  const TrustGroupScreen({super.key});

  @override
  State<TrustGroupScreen> createState() => _TrustGroupScreenState();
}

class _TrustGroupScreenState extends State<TrustGroupScreen> {
  final _aliasController = TextEditingController();
  final _idController = TextEditingController();

  @override
  void dispose() {
    _aliasController.dispose();
    _idController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final service = TrustGroupService.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Groupe de confiance',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mon identifiant de groupe',
                  style:
                      TextStyle(color: onSurface, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Partagez cet ID (hors-ligne) avec vos amis pour qu\'ils '
                  'puissent vous ajouter à leur groupe.',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        service.myFixedId.isEmpty ? '…' : service.myFixedId,
                        style: TextStyle(
                          color: StreetPhareTheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copier',
                      icon: const Icon(Icons.copy, size: 20),
                      onPressed: () => _copyMyId(service.myFixedId),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: service.sharingEnabled,
            onChanged: (v) {
              setState(() {
                if (v) {
                  service.startSharing();
                } else {
                  service.stopSharing();
                }
              });
            },
            title: Text(
              'Partager ma position',
              style: TextStyle(color: onSurface, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              'Diffusée uniquement à vos amis de confiance',
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
            activeTrackColor: StreetPhareTheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Demandes en attente',
            style: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<List<FollowRequest>>(
            valueListenable: service.pendingFollowRequests,
            builder: (context, requests, _) {
              if (requests.isEmpty) {
                return _Card(
                  child: Text(
                    'Aucune demande en attente.',
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final r in requests)
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '« ${r.fromAlias} » souhaite suivre votre position',
                            style: TextStyle(
                              color: onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              OutlinedButton(
                                onPressed: () =>
                                    service.declineFollowRequest(r),
                                child: const Text('Refuser'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: StreetPhareTheme.primary,
                                  foregroundColor: Colors.black,
                                ),
                                onPressed: () => _acceptFromList(r),
                                child: const Text('Accepter'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Amis de confiance',
            style: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<List<TrustGroupMember>>(
            valueListenable: service.members,
            builder: (context, members, _) {
              if (members.isEmpty) {
                return _Card(
                  child: Text(
                    'Aucun ami ajouté.\n'
                    'Ajoutez un ami en saisissant son ID de groupe.',
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final m in members)
                    _Card(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading:
                            Icon(Icons.person, color: StreetPhareTheme.primary),
                        title: Text(
                          m.alias,
                          style: TextStyle(
                            color: onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          m.fixedId,
                          style: TextStyle(
                            color: onSurface.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => service.removeMember(m.fixedId),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _Card(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_outlined,
                    color: Color(0xFFF85149), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'En cas de PANIC, le groupe se dissout instantanément : '
                    'les positions des autres disparaissent et tous les '
                    'identifiants tournent vers de nouvelles valeurs.',
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.65),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: StreetPhareTheme.primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Ajouter un ami'),
      ),
    );
  }

  Future<void> _copyMyId(String id) async {
    if (id.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ID copié dans le presse-papiers.')),
    );
  }

  /// Accepte une demande depuis la liste : propose de suivre en retour
  /// puis accepte (avec ou sans suivi réciproque).
  Future<void> _acceptFromList(FollowRequest request) async {
    final followBack = await showFollowBackOffer(context, request);
    if (!mounted) return;
    await TrustGroupService.instance
        .acceptFollowRequest(request, followBack: followBack == true);
  }

  Future<void> _showAddDialog() async {
    _aliasController.clear();
    _idController.clear();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Text(
          'Ajouter un ami',
          style: TextStyle(color: onSurface, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _aliasController,
              style: TextStyle(color: onSurface),
              decoration: InputDecoration(
                labelText: 'Surnom (ex. Alice)',
                labelStyle: TextStyle(color: onSurface.withValues(alpha: 0.6)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _idController,
              style: TextStyle(color: onSurface),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'ID de groupe (ex. SP-ABCD-EFGH-JKLM-NPQR)',
                labelStyle: TextStyle(color: onSurface.withValues(alpha: 0.6)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: StreetPhareTheme.primary,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      final id = _idController.text.trim();
      if (id.isEmpty) return;
      await TrustGroupService.instance
          .addMember(_aliasController.text.trim(), id);
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}
