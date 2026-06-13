// lib/database/alert_visibility_policy.dart
//
// Politique de VISIBILITÉ d'une alerte sur la carte générale.
//
// Règle métier (Phase 2 - "Intelligence StreetPhare") :
//   Un point d'alerte ne s'affiche sur la carte que s'il cumule
//   AU MOINS 3 signalements / votes ACTIFS (de moins de 24h) ou
//   s'il a été validé collectivement. S'il tombe en dessous de
//   3 signalements/votes actifs, le marqueur disparaît.
//
// Cette politique se combine avec la politique de TTL (lib/database/
// alert_ttl_policy.dart) : un signalement "actif" est un signalement
// dont le TTL "Phase 2" n'est pas encore expiré. La fenêtre de
// 24h reste la limite dure (RGPD) pour la persistance en BDD locale.

import 'alert_model.dart';
import 'alert_ttl_policy.dart';

/// Politique de visibilité (filtrage 3-votes + TTL).
class AlertVisibilityPolicy {
  AlertVisibilityPolicy._();

  /// Nombre minimum de confirmations distinctes pour qu'une alerte
  /// apparaisse sur la carte générale.
  static const int minConfirmationsToShow = 3;

  /// Indique si une alerte doit être visible sur la carte
  /// (carte générale) en appliquant les deux règles :
  ///   1. Au moins [minConfirmationsToShow] confirmations ACTIVES
  ///      (TTL Phase 2 non expiré).
  ///   2. OU statut `validated` par consensus.
  static bool isVisible(Alert alert, {DateTime? now}) {
    // Règle 1 : consensus collectif atteint.
    if (alert.status == AlertStatus.validated) return true;
    if (alert.isValidatedByConsensus) return true;

    // Règle 2 : seuil de 3 votes atteint.
    if (alert.confirmations.length >= minConfirmationsToShow) {
      return true;
    }

    return false;
  }

  /// Filtre une liste d'alertes pour ne garder que celles qui
  /// doivent être visibles.
  static List<Alert> filterVisible(Iterable<Alert> alerts, {DateTime? now}) {
    return alerts
        .where((a) => !a.isExpired(now)) // RGPD 24h hard
        .where((a) => AlertTtlPolicy.isAlertAlive(a, now: now))
        .where((a) => isVisible(a, now: now))
        .toList();
  }
}
