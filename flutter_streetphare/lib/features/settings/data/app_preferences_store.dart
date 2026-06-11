// lib/features/settings/data/app_preferences_store.dart
//
// Store persistant des préférences applicatives générales.
//
// Couvre :
//   - Mode Économe (battery saver) : réduit la fréquence GPS/BLE
//   - Filtre de notifications en arrière-plan
//   - Événement actif sélectionné (index parmi les 3 max)
//   - Type de destination pour la Route Safe
//   - Mode Malvoyant (grand texte + interface adaptée)
//   - Filtre messagerie Hive P2P
//   - Cache cartes (durée max en jours)

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// Énumérations des préférences
// ============================================================================

/// Filtre de notifications reçues en arrière-plan.
enum NotificationFilter {
  /// Toutes les alertes du réseau.
  all,

  /// Uniquement les dangers confirmés (≥3 votes) à moins de 100 m.
  nearbyDangersOnly,

  /// Uniquement les changements de points de manif imminents (<3 min).
  manifestChangesOnly,
}

extension NotificationFilterExt on NotificationFilter {
  String get label {
    switch (this) {
      case NotificationFilter.all:
        return 'Toutes les alertes';
      case NotificationFilter.nearbyDangersOnly:
        return 'Dangers proches confirmés uniquement';
      case NotificationFilter.manifestChangesOnly:
        return 'Changements de points imminents';
    }
  }

  String get description {
    switch (this) {
      case NotificationFilter.all:
        return 'Notifie chaque micro-événement du réseau';
      case NotificationFilter.nearbyDangersOnly:
        return 'Filtre : danger ≥3 votes détecté à moins de 100 m';
      case NotificationFilter.manifestChangesOnly:
        return 'Notifie si le prochain point est révélé dans <3 min';
    }
  }
}

/// Type de destination pour l'algorithme "Route Safe".
enum RouteDestinationType {
  manifestPoint,
  careCenter,
  exitPoint,
  userPoint,
}

extension RouteDestinationTypeExt on RouteDestinationType {
  String get label {
    switch (this) {
      case RouteDestinationType.manifestPoint:
        return 'Suivre le point de manif actuel';
      case RouteDestinationType.careCenter:
        return 'Centre de soins le plus proche';
      case RouteDestinationType.exitPoint:
        return 'Point de sortie le plus proche';
      case RouteDestinationType.userPoint:
        return 'Point utilisateur';
    }
  }

  String get description {
    switch (this) {
      case RouteDestinationType.manifestPoint:
        return 'Destination par défaut de l\'événement actif';
      case RouteDestinationType.careCenter:
        return 'Street-medics ou secours de rue les plus proches';
      case RouteDestinationType.exitPoint:
        return 'Zone d\'évacuation définie dans le JSON de l\'événement';
      case RouteDestinationType.userPoint:
        return 'Point personnalisé placé manuellement (appui long 3s)';
    }
  }
}

/// Filtre des messages Hive P2P reçus.
enum MessageFilter {
  /// Tous les messages diffusés.
  all,

  /// Uniquement les messages émis depuis moins de 300 m.
  nearbyOnly,

  /// Uniquement les messages des administrateurs d'événement.
  adminOnly,

  /// Uniquement les messages d'alerte (type ALERT).
  alertOnly,
}

extension MessageFilterExt on MessageFilter {
  String get label {
    switch (this) {
      case MessageFilter.all:
        return 'Tous les messages';
      case MessageFilter.nearbyOnly:
        return 'Messages proches uniquement';
      case MessageFilter.adminOnly:
        return 'Administrateurs de l\'événement';
      case MessageFilter.alertOnly:
        return 'Messages d\'alerte uniquement';
    }
  }

  String get description {
    switch (this) {
      case MessageFilter.all:
        return 'Reçoit tous les messages diffusés sur le réseau';
      case MessageFilter.nearbyOnly:
        return 'Messages émis dans un rayon de 300 m';
      case MessageFilter.adminOnly:
        return 'Messages signés par un administrateur de l\'événement';
      case MessageFilter.alertOnly:
        return 'Uniquement les alertes critiques (type ALERT)';
    }
  }
}

// ============================================================================
// Modèle de snapshot des préférences
// ============================================================================

class AppPreferences {
  const AppPreferences({
    this.batterySaverEnabled = false,
    this.notificationFilter = NotificationFilter.nearbyDangersOnly,
    this.routeDestinationType = RouteDestinationType.manifestPoint,
    this.activeEventIndex = 0,
    this.userPointLatitude,
    this.userPointLongitude,
    this.lowVisionMode = false,
    this.messageFilter = MessageFilter.all,
    this.mapCacheMaxAgeDays = 7,
  });

  final bool batterySaverEnabled;
  final NotificationFilter notificationFilter;
  final RouteDestinationType routeDestinationType;
  final int activeEventIndex;
  final double? userPointLatitude;
  final double? userPointLongitude;

  /// Mode Malvoyant : grand texte, interface adaptée, signalement 2 colonnes.
  final bool lowVisionMode;

  /// Filtre des messages Hive P2P.
  final MessageFilter messageFilter;

  /// Durée de rétention du cache des tuiles (en jours). Défaut : 7 jours.
  final int mapCacheMaxAgeDays;

  AppPreferences copyWith({
    bool? batterySaverEnabled,
    NotificationFilter? notificationFilter,
    RouteDestinationType? routeDestinationType,
    int? activeEventIndex,
    double? userPointLatitude,
    double? userPointLongitude,
    bool? lowVisionMode,
    MessageFilter? messageFilter,
    int? mapCacheMaxAgeDays,
  }) {
    return AppPreferences(
      batterySaverEnabled: batterySaverEnabled ?? this.batterySaverEnabled,
      notificationFilter: notificationFilter ?? this.notificationFilter,
      routeDestinationType: routeDestinationType ?? this.routeDestinationType,
      activeEventIndex: activeEventIndex ?? this.activeEventIndex,
      userPointLatitude: userPointLatitude ?? this.userPointLatitude,
      userPointLongitude: userPointLongitude ?? this.userPointLongitude,
      lowVisionMode: lowVisionMode ?? this.lowVisionMode,
      messageFilter: messageFilter ?? this.messageFilter,
      mapCacheMaxAgeDays: mapCacheMaxAgeDays ?? this.mapCacheMaxAgeDays,
    );
  }

  Map<String, dynamic> toJson() => {
        'batterySaver': batterySaverEnabled,
        'notifFilter': notificationFilter.name,
        'routeDest': routeDestinationType.name,
        'activeEvent': activeEventIndex,
        'userLat': userPointLatitude,
        'userLng': userPointLongitude,
        'lowVisionMode': lowVisionMode,
        'messageFilter': messageFilter.name,
        'mapCacheMaxAgeDays': mapCacheMaxAgeDays,
      };

  factory AppPreferences.fromJson(Map<String, dynamic> json) {
    return AppPreferences(
      batterySaverEnabled: (json['batterySaver'] as bool?) ?? false,
      notificationFilter: NotificationFilter.values.firstWhere(
        (e) => e.name == json['notifFilter'],
        orElse: () => NotificationFilter.nearbyDangersOnly,
      ),
      routeDestinationType: RouteDestinationType.values.firstWhere(
        (e) => e.name == json['routeDest'],
        orElse: () => RouteDestinationType.manifestPoint,
      ),
      activeEventIndex: (json['activeEvent'] as int?) ?? 0,
      userPointLatitude: (json['userLat'] as num?)?.toDouble(),
      userPointLongitude: (json['userLng'] as num?)?.toDouble(),
      lowVisionMode: (json['lowVisionMode'] as bool?) ?? false,
      messageFilter: MessageFilter.values.firstWhere(
        (e) => e.name == json['messageFilter'],
        orElse: () => MessageFilter.all,
      ),
      mapCacheMaxAgeDays: (json['mapCacheMaxAgeDays'] as int?) ?? 7,
    );
  }
}

// ============================================================================
// Store singleton
// ============================================================================

/// Store singleton des préférences applicatives générales.
/// Écoutable via `ValueListenableBuilder<AppPreferences>`.
class AppPreferencesStore extends ValueNotifier<AppPreferences> {
  AppPreferencesStore._() : super(const AppPreferences());
  static final AppPreferencesStore instance = AppPreferencesStore._();

  static const String _prefsKey = 'streetphare_app_preferences_v2';
  SharedPreferences? _prefs;

  /// Charge depuis SharedPreferences. À appeler au démarrage.
  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_prefsKey);
    if (raw == null) {
      value = const AppPreferences();
      return;
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      value = AppPreferences.fromJson(json);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppPreferencesStore] erreur parsing: $e');
      }
      value = const AppPreferences();
    }
  }

  /// Met à jour les préférences et persiste.
  Future<void> update(AppPreferences prefs) async {
    value = prefs;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_prefsKey, jsonEncode(prefs.toJson()));
  }

  Future<void> setBatterySaver(bool enabled) =>
      update(value.copyWith(batterySaverEnabled: enabled));

  Future<void> setNotificationFilter(NotificationFilter filter) =>
      update(value.copyWith(notificationFilter: filter));

  Future<void> setRouteDestination(RouteDestinationType type) =>
      update(value.copyWith(routeDestinationType: type));

  Future<void> setActiveEventIndex(int index) =>
      update(value.copyWith(activeEventIndex: index.clamp(0, 2)));

  Future<void> setUserPoint(double lat, double lng) => update(
        value.copyWith(
          routeDestinationType: RouteDestinationType.userPoint,
          userPointLatitude: lat,
          userPointLongitude: lng,
        ),
      );

  /// Active/désactive le Mode Malvoyant.
  Future<void> setLowVisionMode(bool enabled) =>
      update(value.copyWith(lowVisionMode: enabled));

  /// Modifie le filtre messagerie Hive P2P.
  Future<void> setMessageFilter(MessageFilter filter) =>
      update(value.copyWith(messageFilter: filter));

  /// Modifie la durée de cache des tuiles (en jours).
  Future<void> setMapCacheMaxAgeDays(int days) =>
      update(value.copyWith(mapCacheMaxAgeDays: days.clamp(1, 30)));
}
