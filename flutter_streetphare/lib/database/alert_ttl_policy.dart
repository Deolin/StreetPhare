// lib/database/alert_ttl_policy.dart
//
// Politique de TTL (Time To Live) différenciée selon la MOBILITÉ
// présumée du danger.
//
// Règles métier (Phase 2 - "Intelligence StreetPhare") :
//   * Dangers MOBILES (barrages, groupes de casseurs, dangers
//     spontanés) : durée de vie de 10 minutes. Ils peuvent
//     disparaître ou se déplacer très vite.
//   * Dangers STATIQUES (policiers, autopompes, zones filtrées) :
//     durée de vie de 1 minute. Ils bougent en général très peu
//     (un barrage filtrant reste en place longtemps) mais on veut
//     malgré tout un TTL court pour ne pas surcharger la carte
//     d'informations obsolètes.
//
// Cette politique est combinée à la règle de VISIBILITÉ : un point
// d'alerte n'apparaît sur la carte générale que s'il cumule au
// moins 3 signalements/votes actifs (de moins de 24h) ou s'il a
// été validé collectivement.

import 'alert_model.dart';

/// Politique de TTL différenciée par type d'alerte.
class AlertTtlPolicy {
  AlertTtlPolicy._();

  /// TTL par défaut (utilisé en cas de fallback) : 10 minutes
  /// (= valeur la plus conservatrice / "safest").
  static const Duration defaultTtl = Duration(minutes: 10);

  /// TTL pour les dangers MOBILES (barrages, casseurs, dangers).
  static const Duration mobileTtl = Duration(minutes: 10);

  /// TTL pour les dangers STATIQUES (policiers, autopompes, zones
  /// filtrées).
  static const Duration staticTtl = Duration(minutes: 1);

  /// Indique si un `ReportType` (UI) correspond à un danger MOBILE.
  ///
  /// On se base sur l'identifiant technique (`.id`) du `ReportType`
  /// pour ne pas coupler ce fichier à l'UI Flutter (couche pure
  /// métier, sans dépendance vers `package:flutter/material.dart`).
  static bool isMobileReport(String reportId) {
    switch (reportId) {
      case 'barrages':
      case 'groupes_casseurs':
      case 'dangers':
        return true;
      case 'zones_filtrees':
      case 'autopompes':
      case 'policiers':
      case 'nasses':
        return false;
      default:
        return true; // par défaut, on traite comme mobile
    }
  }

  /// Indique si un `AlertType` (modèle) correspond à un danger
  /// considéré comme MOBILE dans la politique de TTL.
  static bool isMobileAlertType(AlertType type) {
    switch (type) {
      case AlertType.barrage:
      case AlertType.manifestation:
      case AlertType.accident:
        return true;
      case AlertType.nasse:
      case AlertType.controle:
      case AlertType.autre:
        return false;
    }
  }

  /// Renvoie le TTL (Duration) à appliquer à un nouveau signalement,
  /// en se basant sur l'identifiant du `ReportType` (UI).
  static Duration ttlForReport(String reportId) =>
      isMobileReport(reportId) ? mobileTtl : staticTtl;

  /// Renvoie le TTL (Duration) à appliquer pour un `AlertType`.
  static Duration ttlForAlertType(AlertType type) =>
      isMobileAlertType(type) ? mobileTtl : staticTtl;

  /// Indique si une alerte (déjà stockée) est ENCORE VIVANTE à un
  /// instant `now`, en tenant compte du TTL choisi dynamiquement.
  ///
  /// Cette méthode est l'extension "Phase 2" de `Alert.isExpired` :
  /// elle prend en compte le `createdAt` ET le TTL du TYPE, sans
  /// dépendre du `ttlHours` (qui reste fixé à 24h pour la limite
  /// réglementaire / RGPD absolue).
  static bool isAlertAlive(Alert alert, {DateTime? now}) {
    final reference = now ?? DateTime.now().toUtc();
    final expiry = alert.createdAt.add(ttlForAlertType(alert.type));
    return reference.isBefore(expiry);
  }

  /// Renvoie l'instant exact d'expiration du TTL "Phase 2" pour
  /// une alerte donnée. Utile pour afficher un compte à rebours
  /// dans la feuille de validation de proximité.
  static DateTime expiryInstant(Alert alert) {
    return alert.createdAt.add(ttlForAlertType(alert.type));
  }
}
