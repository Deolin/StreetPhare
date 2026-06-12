// lib/services/kick_check_service.dart
//
// [6] Service de vérification du statut Kick/Ban du client.
//
// Interroge périodiquement le serveur d'administration pour savoir
// si cet appareil a été kické ou banni.
//
// Si l'appareil est kické 3 fois en 30 minutes :
//   → L'application déclenche un verrouillage automatique de l'interface.
//
// Le UUID éphémère de l'appareil est généré une fois par session
// et partagé avec le réseau Hive via le NetworkCoordinator.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Résultat d'un check kick.
class KickStatus {
  const KickStatus({
    this.kicked = false,
    this.banned = false,
    this.autoLock = false,
  });
  final bool kicked;
  final bool banned;
  final bool autoLock;

  bool get isRestricted => kicked || banned || autoLock;
}

/// [6] Service de vérification kick/ban — singleton.
class KickCheckService extends ChangeNotifier {
  KickCheckService._();
  static final KickCheckService instance = KickCheckService._();

  static const String _adminBase = 'http://192.168.31.18:4000';
  static const String _uuidKey = 'streetphare_ephemeral_uuid';
  static const Duration _checkInterval = Duration(minutes: 5);

  String? _ephemeralUuid;
  KickStatus _status = const KickStatus();
  bool _interfaceLocked = false;
  Timer? _timer;

  KickStatus get status => _status;
  bool get interfaceLocked => _interfaceLocked;
  String? get ephemeralUuid => _ephemeralUuid;

  // --------------------------------------------------------------------------
  // Initialisation
  // --------------------------------------------------------------------------

  Future<void> init() async {
    await _loadOrGenerateUuid();
    await _check();
    _timer = Timer.periodic(_checkInterval, (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Vérification
  // --------------------------------------------------------------------------

  Future<void> _check() async {
    final uuid = _ephemeralUuid;
    if (uuid == null) return;

    try {
      final response = await http
          .get(Uri.parse('$_adminBase/api/kick-status/$uuid'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final newStatus = KickStatus(
          kicked: data['kicked'] as bool? ?? false,
          banned: data['banned'] as bool? ?? false,
          autoLock: data['autoLock'] as bool? ?? false,
        );

        final wasLocked = _interfaceLocked;
        _status = newStatus;

        // [6] Si autoLock → verrouiller l'interface locale.
        if (newStatus.autoLock && !wasLocked) {
          _interfaceLocked = true;
          debugPrint('[KickCheck] ⚠️ VERROUILLAGE AUTOMATIQUE déclenché !');
        }

        notifyListeners();
      }
    } on SocketException {
      // Pas de connexion — silencieux (on ne punit pas le hors-ligne).
    } on TimeoutException {
      // Timeout — silencieux.
    } catch (e) {
      debugPrint('[KickCheck] erreur: $e');
    }
  }

  // --------------------------------------------------------------------------
  // Déverrouillage
  // --------------------------------------------------------------------------

  /// Déverrouille l'interface (après timeout ou action admin).
  void unlock() {
    _interfaceLocked = false;
    _status = const KickStatus();
    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // UUID éphémère
  // --------------------------------------------------------------------------

  Future<void> _loadOrGenerateUuid() async {
    final prefs = await SharedPreferences.getInstance();
    var uuid = prefs.getString(_uuidKey);
    if (uuid == null) {
      uuid = _generateUuid();
      await prefs.setString(_uuidKey, uuid);
    }
    _ephemeralUuid = uuid;
    debugPrint('[KickCheck] UUID éphémère: $uuid');
  }

  static String _generateUuid() {
    // UUID v4 simplifié compatible Dart web + mobile.
    const chars = '0123456789abcdef';
    final buf = StringBuffer();
    final parts = [8, 4, 4, 4, 12];
    for (final len in parts) {
      if (buf.isNotEmpty) buf.write('-');
      for (var i = 0; i < len; i++) {
        final idx = DateTime.now().microsecondsSinceEpoch % chars.length;
        buf.write(chars[(idx + i * 7) % chars.length]);
      }
    }
    return buf.toString();
  }
}

// ============================================================================
// Widget de verrouillage automatique
// ============================================================================

/// [6] Écran de verrouillage déclenché après 3 kicks en 30 minutes.
///
/// Se superpose à toute l'interface via un Overlay et bloque l'interaction.
class AutoLockOverlay extends StatefulWidget {
  const AutoLockOverlay({super.key, required this.child});
  final Widget child;

  @override
  State<AutoLockOverlay> createState() => _AutoLockOverlayState();
}

class _AutoLockOverlayState extends State<AutoLockOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    KickCheckService.instance.addListener(_onKickStatus);
    if (KickCheckService.instance.interfaceLocked) _anim.forward();
  }

  @override
  void dispose() {
    KickCheckService.instance.removeListener(_onKickStatus);
    _anim.dispose();
    super.dispose();
  }

  void _onKickStatus() {
    if (KickCheckService.instance.interfaceLocked) {
      _anim.forward();
    } else {
      _anim.reverse();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _anim,
          builder: (context, _) {
            if (_anim.value == 0) return const SizedBox.shrink();
            return Opacity(
              opacity: _anim.value,
              child: _buildLockScreen(context),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLockScreen(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.92),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock, color: Colors.redAccent, size: 80),
            const SizedBox(height: 24),
            const Text(
              '⚠️ Application verrouillée',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Votre appareil a été identifié comme source de comportements '
                'malveillants et a été automatiquement verrouillé par '
                'le système de modération.\n\n'
                'Cette mesure est temporaire. Si vous pensez qu\'il s\'agit '
                'd\'une erreur, contactez un administrateur de l\'événement.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Affiche un compte à rebours de 30 minutes.
            const _LockCountdown(durationMinutes: 30),
          ],
        ),
      ),
    );
  }
}

class _LockCountdown extends StatefulWidget {
  const _LockCountdown({required this.durationMinutes});
  final int durationMinutes;

  @override
  State<_LockCountdown> createState() => _LockCountdownState();
}

class _LockCountdownState extends State<_LockCountdown> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.durationMinutes * 60;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _remaining--);
      if (_remaining <= 0) {
        _timer?.cancel();
        KickCheckService.instance.unlock();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = _remaining ~/ 60;
    final s = _remaining % 60;
    return Text(
      'Déverrouillage dans ${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 18,
        fontFamily: 'monospace',
        fontWeight: FontWeight.w300,
      ),
    );
  }
}
