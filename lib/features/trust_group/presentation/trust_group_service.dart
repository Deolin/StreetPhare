// lib/features/trust_group/presentation/trust_group_service.dart
//
// Service de « groupe de confiance ».
//
// Permet à un groupe d'amis de se repérer dans la foule :
//   - Chaque membre possède un « ID secondaire fixe » (stable, partagé
//     hors-ligne) distinct de l'ID éphémère rotatif du réseau P2P.
//   - Chaque membre diffuse périodiquement sa position sur le maillage
//     P2P LOCAL (BLE / Wi-Fi Direct), sans passer par un serveur.
//   - La position n'est affichée que si l'ID fixe émetteur figure dans
//     la liste de confiance de l'appareil récepteur.
//
// PANIC : dissout instantanément le groupe (protection, pas punition) :
//   1. Efface localement les IDs fixes des autres → leurs positions
//      disparaissent immédiatement de la carte.
//   2. Diffuse un signal `trust_rotate` : chaque ami fait tourner son
//      propre ID fixe vers un nouveau.
//   3. Fait également tourner l'ID fixe local (anti-pistage).

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../network/network_coordinator.dart';
import '../../../services/notification_service.dart';
import '../../messaging/presentation/hive_messaging_service.dart';
import '../domain/models/follow_request.dart';
import '../domain/models/friend_position.dart';
import '../domain/models/trust_group_member.dart';

/// Types de signaux du groupe de confiance diffusés sur le maillage.
class TrustSignalKind {
  static const String position = 'trust_position';
  static const String rotate = 'trust_rotate';
  static const String followRequest = 'trust_follow_request';
  static const String followAccept = 'trust_follow_accept';
}

/// Service singleton de groupe de confiance.
class TrustGroupService {
  TrustGroupService._();
  static final TrustGroupService instance = TrustGroupService._();

  static const String _kMyFixedId = 'trust_group_my_fixed_id';
  static const String _kMembers = 'trust_group_members';
  static const String _kMyAlias = 'trust_group_my_alias';
  static const String _kPendingFollowRequests =
      'trust_group_pending_follow_requests';

  /// Intervalle de diffusion de la position locale.
  static const Duration broadcastInterval = Duration(seconds: 15);

  String _myFixedId = '';
  String _myAlias = 'Ami';
  bool _loaded = false;

  /// Liste de confiance (alias + ID fixe de chaque ami).
  final ValueNotifier<List<TrustGroupMember>> members =
      ValueNotifier<List<TrustGroupMember>>(const []);

  /// Positions reçues des amis de confiance (fixedId → position).
  final ValueNotifier<Map<String, FriendPosition>> positions =
      ValueNotifier<Map<String, FriendPosition>>({});

  /// `true` si le partage de position est actif.
  bool sharingEnabled = false;

  Timer? _broadcastTimer;

  /// ID secondaire fixe de CET appareil (à partager avec ses amis).
  String get myFixedId => _myFixedId;
  bool get isLoaded => _loaded;

  /// Pseudonyme local affiché aux autres lors d'une demande de suivi.
  String get myAlias => _myAlias;

  /// Demandes de suivi reçues, en attente d'acceptation/refus (persistées).
  final ValueNotifier<List<FollowRequest>> pendingFollowRequests =
      ValueNotifier<List<FollowRequest>>(const []);

  /// Dernière demande reçue (one-shot) : déclenche le dialogue de
  /// consentement quand l'application est au premier plan.
  final ValueNotifier<FollowRequest?> lastIncomingRequest =
      ValueNotifier<FollowRequest?>(null);

  /// Charge l'ID fixe et la liste de confiance depuis SharedPreferences.
  Future<void> init() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _myFixedId = prefs.getString(_kMyFixedId) ?? '';
      if (_myFixedId.isEmpty) {
        _myFixedId = _generateFixedId();
        await prefs.setString(_kMyFixedId, _myFixedId);
      }
      _myAlias = prefs.getString(_kMyAlias) ?? 'Ami';

      final rawMembers = prefs.getString(_kMembers);
      if (rawMembers != null && rawMembers.isNotEmpty) {
        final list = jsonDecode(rawMembers) as List<dynamic>;
        members.value = list
            .whereType<Map<String, dynamic>>()
            .map(TrustGroupMember.fromJson)
            .where((m) => m.fixedId.isNotEmpty)
            .toList();
      }

      final rawPending = prefs.getString(_kPendingFollowRequests);
      if (rawPending != null && rawPending.isNotEmpty) {
        final list = jsonDecode(rawPending) as List<dynamic>;
        pendingFollowRequests.value = list
            .whereType<Map<String, dynamic>>()
            .map(FollowRequest.fromJson)
            .where((r) => r.fromFixedId.isNotEmpty)
            .toList();
      }
      _loaded = true;
      debugPrint('[TrustGroup] chargé — myFixedId=$_myFixedId '
          '(${members.value.length} membres)');
    } catch (e) {
      debugPrint('[TrustGroup] échec chargement : $e');
    }
  }

  /// Génère un ID secondaire fixe lisible (ex: SP-ABCD-EFGH-JKLM-NPQR).
  String _generateFixedId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sans I/O/0/1
    final rng = Random.secure();
    final buf = StringBuffer('SP-');
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        buf.write(chars[rng.nextInt(chars.length)]);
      }
      if (i < 3) buf.write('-');
    }
    return buf.toString();
  }

  /// Normalise un ID fixe saisi (majuscules, sans espaces).
  String _normalizeFixedId(String input) =>
      input.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  // --------------------------------------------------------------------------
  // Gestion des membres
  // --------------------------------------------------------------------------

  /// Ajoute un ami de confiance (alias local + ID fixe partagé hors-ligne).
  Future<void> addMember(String alias, String fixedId) async {
    final cleaned = _normalizeFixedId(fixedId);
    if (cleaned.isEmpty || cleaned == _myFixedId) return;
    final list = List<TrustGroupMember>.from(members.value)
      ..removeWhere((m) => m.fixedId == cleaned)
      ..add(TrustGroupMember(
        alias: alias.trim().isEmpty ? 'Ami' : alias.trim(),
        fixedId: cleaned,
      ));
    members.value = list;
    await _persist();
  }

  /// Retire un ami de confiance.
  Future<void> removeMember(String fixedId) async {
    members.value = members.value.where((m) => m.fixedId != fixedId).toList();
    _removePosition(fixedId);
    await _persist();
  }

  /// Vide toute la liste de confiance (utilisé par PANIC).
  Future<void> clearMembers() async {
    members.value = const [];
    positions.value = {};
    await _persist();
  }

  /// Fait tourner l'ID fixe local vers une nouvelle valeur.
  Future<void> rotateMyFixedId() async {
    _myFixedId = _generateFixedId();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMyFixedId, _myFixedId);
    debugPrint('[TrustGroup] ID fixe roté → $_myFixedId');
  }

  /// Définit le pseudonyme local (affiché aux autres lors d'une demande).
  Future<void> setAlias(String alias) async {
    _myAlias = alias.trim().isEmpty ? 'Ami' : alias.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMyAlias, _myAlias);
  }

  /// Retire une position reçue (et purge les obsolètes).
  void _removePosition(String fixedId) {
    final map = Map<String, FriendPosition>.from(positions.value)
      ..remove(fixedId);
    positions.value = map;
  }

  /// Persiste la liste de confiance dans SharedPreferences.
  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(members.value.map((m) => m.toJson()).toList());
      await prefs.setString(_kMembers, raw);
    } catch (e) {
      debugPrint('[TrustGroup] échec persistance : $e');
    }
  }

  // --------------------------------------------------------------------------
  // Partage de position
  // --------------------------------------------------------------------------

  /// Démarre la diffusion périodique de la position locale.
  void startSharing() {
    if (sharingEnabled) return;
    sharingEnabled = true;
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer.periodic(broadcastInterval, (_) {
      unawaited(_broadcastCurrentPosition());
    });
    unawaited(_broadcastCurrentPosition());
  }

  /// Arrête la diffusion périodique.
  void stopSharing() {
    sharingEnabled = false;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
  }

  /// Diffuse immédiatement la position courante sur le maillage P2P local.
  Future<void> _broadcastCurrentPosition() async {
    if (!sharingEnabled || _myFixedId.isEmpty) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      await broadcastPosition(pos.latitude, pos.longitude);
    } catch (e) {
      debugPrint('[TrustGroup] position indisponible : $e');
    }
  }

  /// Diffuse explicitement une position (lat/lng) au groupe de confiance.
  Future<void> broadcastPosition(double lat, double lng) async {
    if (_myFixedId.isEmpty) return;
    final payload = <String, dynamic>{
      'fid': _myFixedId,
      'lat': lat,
      'lng': lng,
      'ts': DateTime.now().toUtc().toIso8601String(),
    };
    await _broadcastSignal(TrustSignalKind.position, payload);
  }

  /// Diffuse un signal du groupe de confiance sur le maillage P2P local.
  Future<void> _broadcastSignal(
      String kind, Map<String, dynamic> payload) async {
    try {
      await NetworkCoordinator.instance
          .broadcastTrustSignal(payload, kind: kind);
    } catch (e) {
      debugPrint('[TrustGroup] échec diffusion $kind : $e');
    }
  }

  // --------------------------------------------------------------------------
  // Réception & PANIC
  // --------------------------------------------------------------------------

  /// Traite un signal entrant (`trust_position` ou `trust_rotate`).
  /// Appelé par [NetworkCoordinator] lors de la réception d'un payload.
  void handleIncoming(Map<String, dynamic> json) {
    final kind = json['kind'] as String?;
    final payload = json['payload'] as Map<String, dynamic>?;
    if (payload == null) return;

    if (kind == TrustSignalKind.position) {
      _handlePosition(payload);
    } else if (kind == TrustSignalKind.rotate) {
      // Un ami a déclenché PANIC → on fait tourner notre propre ID fixe.
      unawaited(rotateMyFixedId());
    } else if (kind == TrustSignalKind.followRequest) {
      _handleFollowRequest(payload);
    } else if (kind == TrustSignalKind.followAccept) {
      _handleFollowAccept(payload);
    }
  }

  // --------------------------------------------------------------------------
  // Demandes de suivi (consentement)
  // --------------------------------------------------------------------------

  /// Envoie une demande de suivi à un utilisateur identifié par son ID
  /// éphémère (celui vu dans le chat P2P).
  Future<void> sendFollowRequest({
    required String toEphemeralId,
    required String fromEphemeralId,
  }) async {
    if (_myFixedId.isEmpty || toEphemeralId.isEmpty) return;
    await _broadcastSignal(TrustSignalKind.followRequest, {
      'fid': _myFixedId,
      'alias': _myAlias,
      'fromEph': fromEphemeralId,
      'toEph': toEphemeralId,
    });
  }

  /// Répond à une demande de suivi : accepte (et suit éventuellement en
  /// retour), puis envoie son propre ID pour que le demandeur puisse suivre.
  Future<void> acceptFollowRequest(
    FollowRequest request, {
    required bool followBack,
  }) async {
    _removePendingRequest(request.fromFixedId);
    lastIncomingRequest.value = null;
    if (followBack) {
      await addMember(request.fromAlias, request.fromFixedId);
    }
    await _broadcastSignal(TrustSignalKind.followAccept, {
      'fid': _myFixedId,
      'alias': _myAlias,
      'toEph': request.fromEphemeralId,
    });
  }

  /// Refuse une demande de suivi (aucune réponse envoyée).
  void declineFollowRequest(FollowRequest request) {
    _removePendingRequest(request.fromFixedId);
    lastIncomingRequest.value = null;
  }

  /// Traite une demande de suivi reçue : ne la traite que si elle nous est
  /// adressée (via notre ID éphémère), puis l'ajoute à la file d'attente.
  void _handleFollowRequest(Map<String, dynamic> payload) {
    final toEph = (payload['toEph'] as String?) ?? '';
    if (toEph.isEmpty ||
        toEph != HiveMessagingService.instance.localEphemeralId) {
      return; // Pas pour nous.
    }
    final fid = (payload['fid'] as String?) ?? '';
    final alias = (payload['alias'] as String?) ?? 'Ami';
    final fromEph = (payload['fromEph'] as String?) ?? '';
    if (fid.isEmpty) return;

    // Dédoublonne : un utilisateur = une seule demande en attente.
    if (pendingFollowRequests.value.any((r) => r.fromFixedId == fid)) return;

    final request = FollowRequest(
      fromFixedId: fid,
      fromAlias: alias,
      fromEphemeralId: fromEph,
    );
    pendingFollowRequests.value = [...pendingFollowRequests.value, request];
    unawaited(_persistPending());

    // Premier plan → dialogue de consentement ; arrière-plan → notification.
    if (_isInForeground) {
      lastIncomingRequest.value = request;
    } else {
      unawaited(NotificationService.instance.showAlertNotification(
        title: 'Groupe de confiance',
        body: '« $alias » souhaite suivre votre position.',
        id: 45,
      ));
    }
  }

  /// Retire une demande de la file d'attente et persiste.
  void _removePendingRequest(String fromFixedId) {
    pendingFollowRequests.value = pendingFollowRequests.value
        .where((r) => r.fromFixedId != fromFixedId)
        .toList();
    unawaited(_persistPending());
  }

  /// Persiste la file des demandes en attente.
  Future<void> _persistPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(
          pendingFollowRequests.value.map((r) => r.toJson()).toList());
      await prefs.setString(_kPendingFollowRequests, raw);
    } catch (e) {
      debugPrint('[TrustGroup] échec persistance demandes : $e');
    }
  }

  /// `true` si l'application est au premier plan (état `resumed`).
  bool get _isInForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  /// Traite une acceptation : ajoute l'acceptant à la liste de confiance
  /// (on suit alors sa position), si la réponse nous est adressée.
  void _handleFollowAccept(Map<String, dynamic> payload) {
    final toEph = (payload['toEph'] as String?) ?? '';
    if (toEph.isEmpty ||
        toEph != HiveMessagingService.instance.localEphemeralId) {
      return;
    }
    final fid = (payload['fid'] as String?) ?? '';
    final alias = (payload['alias'] as String?) ?? 'Ami';
    if (fid.isEmpty) return;
    unawaited(addMember(alias, fid));
  }

  /// Filtre et enregistre une position reçue (uniquement si l'émetteur
  /// figure dans la liste de confiance).
  void _handlePosition(Map<String, dynamic> payload) {
    final fid = (payload['fid'] as String?) ?? '';
    if (fid.isEmpty) return;
    final lat = (payload['lat'] as num?)?.toDouble();
    final lng = (payload['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    final isTrusted = members.value.any((m) => m.fixedId == fid);
    if (!isTrusted) return; // Aucune autre carte ne doit afficher la position.

    final map = Map<String, FriendPosition>.from(positions.value)
      ..[fid] = FriendPosition(
        fixedId: fid,
        lat: lat,
        lng: lng,
        updatedAt: DateTime.now().toUtc(),
      );
    // Purge les positions obsolètes.
    map.removeWhere((_, p) => p.isStale);
    positions.value = map;
  }

  /// PANIC : dissout le groupe de confiance (protection, pas punition).
  ///
  /// 1. Efface les IDs fixes des autres → leurs positions disparaissent.
  /// 2. Diffuse `trust_rotate` pour que chaque ami fasse tourner son ID.
  /// 3. Fait tourner l'ID fixe local.
  Future<void> panicWipe() async {
    debugPrint('[TrustGroup] PANIC — dissolution du groupe de confiance');
    await clearMembers();
    await _broadcastSignal(TrustSignalKind.rotate, {
      'ts': DateTime.now().toUtc().toIso8601String(),
    });
    await rotateMyFixedId();
  }

  /// Libère les ressources (timer).
  void dispose() {
    stopSharing();
  }
}
