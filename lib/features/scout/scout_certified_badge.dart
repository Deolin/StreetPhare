// lib/features/scout/scout_certified_badge.dart
//
// Badge « Éclaireur certifié » + état global du mode Éclaireur.
//
// Le badge s'affiche par-dessus l'interface principale lorsque l'app
// tourne en mode Éclaireur (session éclaireur active). Il est déplaçable
// par glisser-déposer : sa position est mémorisée entre les lancements pour
// ne jamais gêner l'utilisateur.

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/report_service.dart' as report;
import '../admin/data/rbac_admin_service.dart';

/// État global du mode Éclaireur — synchronisé automatiquement avec la
/// session d'authentification unifiée (`RbacAdminService.instance.role ==
/// 'scout'`), avec un repli manuel persisté pour les éclaireurs identifiés
/// par userId sans connexion.
class ScoutModeService extends ChangeNotifier {
  ScoutModeService._();
  static final ScoutModeService instance = ScoutModeService._();

  static const String _activeKey = 'scout_mode_active_v1';
  static const String _tokenKey = 'scout_token_v1';

  bool _active = false; // repli manuel persistant
  String? _token;
  bool _loaded = false;

  /// Vrai si le mode Éclaireur est actif : soit l'utilisateur est authentifié
  /// en tant qu'éclaireur (`role == 'scout'`), soit le mode manuel est activé.
  bool get isActive => RbacAdminService.instance.role == 'scout' || _active;

  /// Token JWT éclaireur courant : celui de la session si connecté en tant que
  /// scout, sinon le token manuel persisté.
  String? get token {
    if (RbacAdminService.instance.role == 'scout') {
      return RbacAdminService.instance.token;
    }
    return _token;
  }

  /// Charge l'état persisté et s'abonne à l'authentification (idempotent).
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;

    // Synchronisation automatique : à chaque connexion/déconnexion, on
    // réévalue le mode Éclaireur et on notifie le badge.
    RbacAdminService.instance.addListener(_onAuthChanged);

    try {
      final prefs = await SharedPreferences.getInstance();
      _active = prefs.getBool(_activeKey) ?? false;
      _token = prefs.getString(_tokenKey);
    } catch (_) {}

    _syncReportToken();
    notifyListeners();
  }

  void _onAuthChanged() {
    _syncReportToken();
    notifyListeners();
  }

  /// Branche le token éclaireur effectif sur les signalements.
  void _syncReportToken() {
    report.setAuthToken(token);
  }

  /// Active manuellement le mode Éclaireur (repli userId sans connexion).
  Future<void> activate({String? token}) async {
    _active = true;
    _token = token;
    _syncReportToken();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_activeKey, true);
      if (token != null && token.isNotEmpty) {
        await prefs.setString(_tokenKey, token);
      } else {
        await prefs.remove(_tokenKey);
      }
    } catch (_) {}
  }

  /// Désactive le mode manuel (une session scout connectée reste prioritaire).
  Future<void> deactivate() async {
    _active = false;
    _token = null;
    _syncReportToken();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_activeKey);
      await prefs.remove(_tokenKey);
    } catch (_) {}
  }
}

/// Badge flottant « Éclaireur certifié », déplaçable par glisser-déposer.
///
/// Doit être un enfant direct d'un [Stack]. Retourne un [Positioned] dont la
/// position est persistée (SharedPreferences) et bornée à l'écran.
class ScoutCertifiedBadge extends StatefulWidget {
  const ScoutCertifiedBadge({super.key});

  static const double _badgeWidth = 158.0;
  static const double _badgeHeight = 34.0;

  @override
  State<ScoutCertifiedBadge> createState() => _ScoutCertifiedBadgeState();
}

class _ScoutCertifiedBadgeState extends State<ScoutCertifiedBadge> {
  static const String _offsetXKey = 'scout_badge_offset_x_v1';
  static const String _offsetYKey = 'scout_badge_offset_y_v1';

  Offset _position = const Offset(24, 128);

  @override
  void initState() {
    super.initState();
    ScoutModeService.instance.ensureLoaded();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final x = prefs.getDouble(_offsetXKey);
      final y = prefs.getDouble(_offsetYKey);
      if (x != null && y != null && mounted) {
        setState(() => _position = Offset(x, y));
      }
    } catch (_) {}
  }

  Future<void> _persistPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_offsetXKey, _position.dx);
      await prefs.setDouble(_offsetYKey, _position.dy);
    } catch (_) {}
  }

  void _move(Offset delta, num maxX, num maxY) {
    setState(() {
      _position = Offset(
        (_position.dx + delta.dx).clamp(0.0, maxX).toDouble(),
        (_position.dy + delta.dy).clamp(0.0, maxY).toDouble(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final maxX = (size.width - ScoutCertifiedBadge._badgeWidth)
        .clamp(0.0, double.infinity);
    final maxY = (size.height - ScoutCertifiedBadge._badgeHeight)
        .clamp(0.0, double.infinity);
    final left = _position.dx.clamp(0.0, maxX).toDouble();
    final top = _position.dy.clamp(0.0, maxY).toDouble();

    return Positioned(
      left: left,
      top: top,
      child: ListenableBuilder(
        listenable: ScoutModeService.instance,
        builder: (context, _) {
          if (!ScoutModeService.instance.isActive) {
            return const SizedBox.shrink();
          }
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) => _move(details.delta, maxX, maxY),
            onPanEnd: (_) => _persistPosition(),
            child: _buildBadge(),
          );
        },
      ),
    );
  }

  Widget _buildBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF00695C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, color: Colors.white, size: 14),
          SizedBox(width: 5),
          Text(
            'Éclaireur certifié',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: 6),
          Icon(Icons.drag_indicator, color: Colors.white70, size: 12),
        ],
      ),
    );
  }
}
