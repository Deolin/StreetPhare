// lib/features/messaging/presentation/hive_messaging_screen.dart
//
// Écran de messagerie décentralisée Hive P2P.
//
// Affiche les messages reçus filtrés et permet à l'utilisateur
// de diffuser (broadcaster) des messages textuels.

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../../settings/data/app_preferences_store.dart';
import '../domain/models/hive_message.dart';
import 'hive_messaging_service.dart';

class HiveMessagingScreen extends StatefulWidget {
  const HiveMessagingScreen({super.key, this.userPosition});

  /// Position GPS locale (pour le filtre "proches").
  final LatLng? userPosition;

  @override
  State<HiveMessagingScreen> createState() => _HiveMessagingScreenState();
}

class _HiveMessagingScreenState extends State<HiveMessagingScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    HiveMessagingService.instance.start();
    HiveMessagingService.instance.refreshFilter(
      userPosition: widget.userPosition,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    HiveMessagingService.instance.broadcast(
      content: text,
      userPosition: widget.userPosition,
    );
    _controller.clear();
    // Scroll en bas après envoi
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Messages Hive',
          style: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        iconTheme: IconThemeData(color: onSurface),
        actions: [
          // Sélecteur de filtre
          ValueListenableBuilder<AppPreferences>(
            valueListenable: AppPreferencesStore.instance,
            builder: (_, prefs, _) {
              return PopupMenuButton<MessageFilter>(
                icon: Icon(Icons.filter_list, color: StreetPhareTheme.primary),
                tooltip: 'Filtrer les messages',
                onSelected: (filter) async {
                  await AppPreferencesStore.instance.setMessageFilter(filter);
                  HiveMessagingService.instance
                      .refreshFilter(userPosition: widget.userPosition);
                },
                itemBuilder: (_) => MessageFilter.values
                    .map(
                      (f) => PopupMenuItem(
                        value: f,
                        child: Row(
                          children: [
                            Icon(
                              prefs.messageFilter == f
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: StreetPhareTheme.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(f.label),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Bandeau filtre actif ─────────────────────────────────
          ValueListenableBuilder<AppPreferences>(
            valueListenable: AppPreferencesStore.instance,
            builder: (_, prefs, _) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: StreetPhareTheme.primary.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    const Icon(Icons.filter_alt,
                        size: 14, color: StreetPhareTheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      prefs.messageFilter.label,
                      style: const TextStyle(
                        color: StreetPhareTheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      prefs.messageFilter.description,
                      style: TextStyle(
                        color: onSurface.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // ── Liste des messages ────────────────────────────────────
          Expanded(
            child: ValueListenableBuilder<List<HiveMessage>>(
              valueListenable: HiveMessagingService.instance,
              builder: (_, messages, _) {
                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.forum_outlined,
                          size: 48,
                          color: onSurface.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Aucun message reçu\n'
                          'Soyez le premier à diffuser un message !',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: onSurface.withValues(alpha: 0.5),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollCtrl,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (_, i) => _MessageTile(
                    message: messages[i],
                    isLocal: messages[i].senderEphemeralId ==
                        HiveMessagingService.instance.localEphemeralId,
                  ),
                );
              },
            ),
          ),

          // ── Zone de saisie ────────────────────────────────────────
          _buildInputBar(onSurface),
        ],
      ),
    );
  }

  Widget _buildInputBar(Color onSurface) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: 3,
                minLines: 1,
                maxLength: 500,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                style: TextStyle(color: onSurface, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Diffuser un message sur le réseau Hive…',
                  hintStyle: TextStyle(
                    color: onSurface.withValues(alpha: 0.4),
                    fontSize: 14,
                  ),
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: StreetPhareTheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(
                      color: StreetPhareTheme.primary,
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  filled: true,
                  fillColor: onSurface.withValues(alpha: 0.04),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: StreetPhareTheme.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _sendMessage,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.send, color: Colors.black, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Tuile de message
// ============================================================================

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message, required this.isLocal});

  final HiveMessage message;
  final bool isLocal;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color bubbleColor;
    Color textColor;
    CrossAxisAlignment alignment;

    if (isLocal) {
      bubbleColor = StreetPhareTheme.primary;
      textColor = Colors.black;
      alignment = CrossAxisAlignment.end;
    } else if (message.isFromAdmin) {
      bubbleColor = const Color(0xFF1565C0);
      textColor = Colors.white;
      alignment = CrossAxisAlignment.start;
    } else if (message.type == HiveMessageType.alert) {
      bubbleColor = StreetPhareTheme.danger;
      textColor = Colors.white;
      alignment = CrossAxisAlignment.start;
    } else {
      bubbleColor = isDark
          ? const Color(0xFF2A2A2A)
          : const Color(0xFFF0F0F0);
      textColor = onSurface;
      alignment = CrossAxisAlignment.start;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          // Méta-données (alias + type + heure)
          Padding(
            padding: const EdgeInsets.only(bottom: 2, left: 4, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.isFromAdmin)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.admin_panel_settings,
                        size: 12, color: Color(0xFF1565C0)),
                  ),
                if (message.type == HiveMessageType.alert)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.warning_amber,
                        size: 12, color: StreetPhareTheme.danger),
                  ),
                Text(
                  isLocal
                      ? 'Moi'
                      : '${message.type.label} · ${message.senderAlias}',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _formatTime(message.sentAt),
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.4),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          // Bulle de message
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              message.content,
              style: TextStyle(color: textColor, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
