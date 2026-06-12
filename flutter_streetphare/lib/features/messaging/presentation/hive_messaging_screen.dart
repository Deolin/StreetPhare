// lib/features/messaging/presentation/hive_messaging_screen.dart
//
// Écran de messagerie décentralisée Hive P2P — v3.0
//
// [2] Nouvelles fonctionnalités :
//   - Menu contextuel (long press) sur les bulles :
//       1. "Bloquer cet utilisateur" → filtre local par UUID éphémère.
//       2. "Créer une discussion temporaire" → fil de 30 min (configurable).
//       3. "Ajouter à une discussion" → ajoute à un fil actif ou change la
//          couleur de fond si déjà présent dans ce fil.
//   - Transparence : bandeau "⚠️ Espace public non chiffré" dans les fils.
//   - Indication visuelle colorée : fond de bulle coloré si l'émetteur
//     est dans un fil temporaire actif.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/streetphare_theme.dart';
import '../../settings/data/app_preferences_store.dart';
import '../data/hive_block_service.dart';
import '../domain/models/hive_message.dart';
import '../domain/models/temp_thread.dart';
import 'hive_messaging_service.dart';

// ============================================================================
// Écran Hive Messaging
// ============================================================================

class HiveMessagingScreen extends StatefulWidget {
  const HiveMessagingScreen({super.key, this.userPosition, this.threadId});

  /// Position GPS locale (pour le filtre "proches").
  final LatLng? userPosition;

  /// Si non null, affiche uniquement les messages du fil temporaire.
  final String? threadId;

  @override
  State<HiveMessagingScreen> createState() => _HiveMessagingScreenState();
}

class _HiveMessagingScreenState extends State<HiveMessagingScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  // Fil temporaire actif (pour ce contexte).
  TempThread? _activeThread;
  Timer? _threadTimer;

  @override
  void initState() {
    super.initState();
    HiveMessagingService.instance.start();
    HiveMessagingService.instance.refreshFilter(
      userPosition: widget.userPosition,
    );
    _startThreadTimer();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    _threadTimer?.cancel();
    super.dispose();
  }

  void _startThreadTimer() {
    _threadTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    HiveMessagingService.instance.broadcast(
      content: text,
      userPosition: widget.userPosition,
      threadId: widget.threadId ?? _activeThread?.id,
    );
    _controller.clear();
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

  // --------------------------------------------------------------------------
  // [2] Menu contextuel — long press sur une bulle
  // --------------------------------------------------------------------------

  void _onLongPressBubble(BuildContext ctx, HiveMessage message) {
    if (message.senderEphemeralId ==
        HiveMessagingService.instance.localEphemeralId) {
      return; // Pas de menu sur ses propres messages.
    }

    final blockSvc = HiveBlockService.instance;
    final isAlreadyBlocked =
        blockSvc.isBlocked(message.senderEphemeralId);
    final isInThread =
        blockSvc.isInActiveThread(message.senderEphemeralId);
    final hasActiveThread = blockSvc.activeThreads.isNotEmpty;

    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (_) => _MessageContextMenu(
        message: message,
        isBlocked: isAlreadyBlocked,
        isInThread: isInThread,
        hasActiveThread: hasActiveThread,
        onBlock: () => _blockUser(message.senderEphemeralId),
        onCreateThread: () => _createTempThread(message.senderEphemeralId),
        onAddToThread: () => _addToThread(message.senderEphemeralId),
      ),
    );
  }

  Future<void> _blockUser(String senderId) async {
    await HiveBlockService.instance.blockUser(senderId);
    HiveMessagingService.instance.refreshFilter(
      userPosition: widget.userPosition,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.block, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                'Utilisateur ${senderId.substring(0, 6)} bloqué. '
                'Ses messages ne seront plus affichés.',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
          backgroundColor: StreetPhareTheme.danger,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _createTempThread(String senderId) {
    final thread = HiveBlockService.instance.createThread(
      initialParticipantId: senderId,
    );
    if (mounted) {
      setState(() => _activeThread = thread);
      _openThreadScreen(thread);
    }
  }

  void _addToThread(String senderId) {
    final updated = HiveBlockService.instance.addParticipant(senderId);
    if (updated == null) {
      // Pas de fil actif → créer un nouveau.
      _createTempThread(senderId);
      return;
    }
    if (mounted) {
      setState(() => _activeThread = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.group_add,
                  color: Color(updated.color).withValues(alpha: 0.9), size: 16),
              const SizedBox(width: 8),
              Text(
                'Utilisateur ${senderId.substring(0, 6)} '
                'ajouté à la discussion temporaire.',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
          backgroundColor: Color(updated.color),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openThreadScreen(TempThread thread) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HiveMessagingScreen(
          userPosition: widget.userPosition,
          threadId: thread.id,
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isThreadView = widget.threadId != null;

    // Récupère la couleur du fil courant.
    Color? threadColor;
    if (isThreadView) {
      final thread = HiveBlockService.instance.activeThreads
          .where((t) => t.id == widget.threadId)
          .firstOrNull;
      if (thread != null) {
        threadColor = Color(thread.color);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isThreadView ? 'Discussion temporaire' : 'Messages Hive',
          style: TextStyle(
            color: threadColor ?? onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        iconTheme: IconThemeData(color: threadColor ?? onSurface),
        actions: [
          if (!isThreadView)
            ValueListenableBuilder<AppPreferences>(
              valueListenable: AppPreferencesStore.instance,
              builder: (_, prefs, _) {
                return PopupMenuButton<MessageFilter>(
                  icon:
                      Icon(Icons.filter_list, color: StreetPhareTheme.primary),
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
          // ── Bandeau transparence (fil temporaire) ────────────────────
          if (isThreadView) _ThreadTransparencyBanner(color: threadColor),

          // ── Bandeau compte à rebours (fil temporaire) ────────────────
          if (isThreadView)
            _ThreadCountdownBanner(
              threadId: widget.threadId!,
              color: threadColor,
            ),

          // ── Bandeau filtre actif (fil principal) ─────────────────────
          if (!isThreadView)
            ValueListenableBuilder<AppPreferences>(
              valueListenable: AppPreferencesStore.instance,
              builder: (_, prefs, _) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
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

          // ── Fil de discussion actif (indicateur) ─────────────────────
          if (!isThreadView && _activeThread != null && _activeThread!.isActive)
            _ActiveThreadChip(
              thread: _activeThread!,
              onTap: () => _openThreadScreen(_activeThread!),
            ),

          // ── Liste des messages ────────────────────────────────────────
          Expanded(
            child: ValueListenableBuilder<List<HiveMessage>>(
              valueListenable: HiveMessagingService.instance,
              builder: (_, allMessages, _) {
                // Filtre par threadId si on est dans un fil.
                final messages = isThreadView
                    ? allMessages
                        .where((m) => m.threadId == widget.threadId)
                        .toList()
                    : allMessages
                        .where((m) => m.threadId == null)
                        .toList();

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isThreadView
                              ? Icons.chat_bubble_outline
                              : Icons.forum_outlined,
                          size: 48,
                          color: (threadColor ?? onSurface)
                              .withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isThreadView
                              ? 'Aucun message dans ce fil.\n'
                                  'Soyez le premier à écrire ici !'
                              : 'Aucun message reçu\n'
                                  'Soyez le premier à diffuser !',
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
                  itemBuilder: (ctx, i) {
                    final msg = messages[i];
                    return GestureDetector(
                      onLongPress: () => _onLongPressBubble(ctx, msg),
                      child: _MessageTile(
                        message: msg,
                        isLocal: msg.senderEphemeralId ==
                            HiveMessagingService.instance.localEphemeralId,
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // ── Zone de saisie ────────────────────────────────────────────
          _buildInputBar(onSurface, threadColor),
        ],
      ),
    );
  }

  Widget _buildInputBar(Color onSurface, Color? accentColor) {
    final accent = accentColor ?? StreetPhareTheme.primary;
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
                  hintText: widget.threadId != null
                      ? 'Écrire dans ce fil temporaire…'
                      : 'Diffuser un message sur le réseau Hive…',
                  hintStyle: TextStyle(
                    color: onSurface.withValues(alpha: 0.4),
                    fontSize: 14,
                  ),
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: accent.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: accent, width: 1.5),
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
              color: accent,
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
// Bannière de transparence — Fils temporaires
// ============================================================================

class _ThreadTransparencyBanner extends StatelessWidget {
  const _ThreadTransparencyBanner({this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: (color ?? const Color(0xFF9C27B0)).withValues(alpha: 0.12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: color ?? const Color(0xFF9C27B0),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '⚠️ Cette discussion temporaire est un espace PUBLIC FILTRÉ. '
              'Elle n\'est PAS chiffrée de bout en bout. '
              'N\'y partagez aucune information sensible.',
              style: TextStyle(
                color: (color ?? const Color(0xFF9C27B0)),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Compte à rebours du fil temporaire
// ============================================================================

class _ThreadCountdownBanner extends StatefulWidget {
  const _ThreadCountdownBanner({required this.threadId, this.color});
  final String threadId;
  final Color? color;

  @override
  State<_ThreadCountdownBanner> createState() => _ThreadCountdownBannerState();
}

class _ThreadCountdownBannerState extends State<_ThreadCountdownBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thread = HiveBlockService.instance.activeThreads
        .where((t) => t.id == widget.threadId)
        .firstOrNull;

    if (thread == null) {
      return Container(
        color: Colors.red.withValues(alpha: 0.15),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: const Row(
          children: [
            Icon(Icons.timer_off, size: 14, color: Colors.red),
            SizedBox(width: 6),
            Text(
              'Ce fil temporaire a expiré.',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final rem = thread.remaining;
    final mins = rem.inMinutes;
    final secs = rem.inSeconds % 60;
    final accent = widget.color ?? const Color(0xFF9C27B0);

    return Container(
      color: accent.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.timer, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            'Fil actif — expire dans ${mins}m ${secs}s',
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            '${thread.participantIds.length} participant(s)',
            style: TextStyle(
              color: accent.withValues(alpha: 0.7),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Chip du fil actif (fil principal)
// ============================================================================

class _ActiveThreadChip extends StatelessWidget {
  const _ActiveThreadChip({required this.thread, required this.onTap});
  final TempThread thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(thread.color);
    final rem = thread.remaining;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              'Discussion active — ${rem.inMinutes}m restantes',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, color: color, size: 14),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Menu contextuel
// ============================================================================

class _MessageContextMenu extends StatelessWidget {
  const _MessageContextMenu({
    required this.message,
    required this.isBlocked,
    required this.isInThread,
    required this.hasActiveThread,
    required this.onBlock,
    required this.onCreateThread,
    required this.onAddToThread,
  });

  final HiveMessage message;
  final bool isBlocked;
  final bool isInThread;
  final bool hasActiveThread;
  final VoidCallback onBlock;
  final VoidCallback onCreateThread;
  final VoidCallback onAddToThread;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Poignée
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // En-tête : alias de l'émetteur
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      StreetPhareTheme.primary.withValues(alpha: 0.2),
                  radius: 18,
                  child: Text(
                    message.senderAlias.substring(0, 2).toUpperCase(),
                    style: const TextStyle(
                      color: StreetPhareTheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Utilisateur ${message.senderAlias}',
                      style: TextStyle(
                        color: onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      'UUID éphémère · ${message.senderEphemeralId}',
                      style: TextStyle(
                        color: onSurface.withValues(alpha: 0.5),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 24),

          // Action 1 : Bloquer
          ListTile(
            leading: Icon(
              isBlocked ? Icons.block_flipped : Icons.block,
              color: StreetPhareTheme.danger,
            ),
            title: Text(
              isBlocked
                  ? 'Débloquer cet utilisateur'
                  : 'Bloquer cet utilisateur',
              style: TextStyle(
                color: StreetPhareTheme.danger,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              isBlocked
                  ? 'Rend ses messages à nouveau visibles'
                  : 'Rend tous ses messages passés et futurs invisibles '
                      'sur cet appareil (UUID éphémère local)',
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
            onTap: () {
              Navigator.of(context).pop();
              if (isBlocked) {
                HiveBlockService.instance
                    .unblockUser(message.senderEphemeralId);
              } else {
                onBlock();
              }
            },
          ),

          // Action 2 : Créer une discussion temporaire
          ListTile(
            leading: const Icon(Icons.add_comment, color: Color(0xFF9C27B0)),
            title: const Text(
              'Créer une discussion temporaire',
              style: TextStyle(
                color: Color(0xFF9C27B0),
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              'Initialise un fil parallèle de '
              '${HiveBlockService.instance.threadDurationMinutes} min '
              '(configurable dans les options)',
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
            onTap: () {
              Navigator.of(context).pop();
              onCreateThread();
            },
          ),

          // Action 3 : Ajouter / indicateur de fil actif
          ListTile(
            leading: Icon(
              isInThread ? Icons.group : Icons.group_add,
              color: isInThread
                  ? const Color(0xFF388E3C)
                  : const Color(0xFF1976D2),
            ),
            title: Text(
              isInThread
                  ? 'Messages copiés dans ce fil (déjà ajouté)'
                  : hasActiveThread
                      ? 'Ajouter à la discussion active'
                      : 'Créer un fil et y ajouter',
              style: TextStyle(
                color: isInThread
                    ? const Color(0xFF388E3C)
                    : const Color(0xFF1976D2),
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              isInThread
                  ? 'La bulle de cet utilisateur est colorée '
                      'pour indiquer que ses messages sont dans le fil actif'
                  : 'Ajoute l\'utilisateur au fil temporaire en cours',
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
            onTap: isInThread
                ? null
                : () {
                    Navigator.of(context).pop();
                    onAddToThread();
                  },
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ============================================================================
// Tuile de message — avec indicateur de fil temporaire
// ============================================================================

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message, required this.isLocal});

  final HiveMessage message;
  final bool isLocal;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Vérifie si l'émetteur est dans un fil actif (indicateur visuel).
    final threadForSender = isLocal
        ? null
        : HiveBlockService.instance
            .threadForUser(message.senderEphemeralId);

    Color bubbleColor;
    Color textColor;
    CrossAxisAlignment alignment;

    if (isLocal) {
      bubbleColor = StreetPhareTheme.primary;
      textColor = Colors.black;
      alignment = CrossAxisAlignment.end;
    } else if (threadForSender != null) {
      // [2] Bulle colorée si l'émetteur est dans un fil temporaire.
      bubbleColor = Color(threadForSender.color).withValues(alpha: 0.85);
      textColor = Colors.white;
      alignment = CrossAxisAlignment.start;
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
            padding:
                const EdgeInsets.only(bottom: 2, left: 4, right: 4),
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
                if (threadForSender != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.group,
                        size: 12,
                        color: Color(threadForSender.color)),
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
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(18),
              // Bordure colorée si dans un fil temporaire.
              border: threadForSender != null
                  ? Border.all(
                      color: Color(threadForSender.color),
                      width: 2,
                    )
                  : null,
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
