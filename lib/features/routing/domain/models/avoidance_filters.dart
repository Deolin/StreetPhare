// lib/features/routing/domain/models/avoidance_filters.dart
//
// Préférences utilisateur pour le moteur de routage "Safe Path".
//
// L'utilisateur peut, dans les paramètres, cocher/décocher quels
// types de dangers il ACCEPTE de traverser ou veut ABSOLUMENT ÉVITER.
// L'algorithme adapte son calcul en fonction de ces booléens.
//
// Par défaut, tous les dangers sont évités (barrages, nasses, contrôles,
// accidents/autopompes, rassemblements). Seuls les dangers « autres »
// (non catégorisés) sont acceptés par défaut, et peuvent être évités
// via le filtre dédié.

import 'package:flutter/foundation.dart';

import '../../../../core/models/alert_model.dart';

/// Préférences d'évitement persistées.
@immutable
class AvoidanceFilters {
  factory AvoidanceFilters.fromJson(Map<String, dynamic> json) {
    return AvoidanceFilters(
      avoidBarrages: (json['avoidBarrages'] as bool?) ?? true,
      avoidNasses: (json['avoidNasses'] as bool?) ?? true,
      avoidControles: (json['avoidControles'] as bool?) ?? true,
      avoidAccidents: (json['avoidAccidents'] as bool?) ?? true,
      avoidRassemblements: (json['avoidRassemblements'] as bool?) ?? true,
      avoidAutres: (json['avoidAutres'] as bool?) ?? false,
      masterSwitch: json['masterSwitch'] as bool?,
    );
  }
  const AvoidanceFilters({
    this.avoidBarrages = true,
    this.avoidNasses = true,
    this.avoidControles = true,
    this.avoidAccidents = true,
    this.avoidRassemblements = true,
    this.avoidAutres = false,
    this.masterSwitch = true,
  });

  final bool avoidBarrages;
  final bool avoidNasses;
  final bool avoidControles;
  final bool avoidAccidents;
  final bool avoidRassemblements;
  final bool avoidAutres;

  /// Switch maître : si true, tous les sous-filtres sont activés.
  /// Si false, tous les sous-filtres sont désactivés.
  /// Reflète l'état cohérent : true si TOUS les sous-filtres sont activés,
  /// false si TOUS sont désactivés, null si mixte.
  final bool? masterSwitch;

  /// Vrai si tous les sous-filtres sont activés (état cohérent).
  bool get allEnabled =>
      avoidBarrages &&
      avoidNasses &&
      avoidControles &&
      avoidAccidents &&
      avoidRassemblements &&
      avoidAutres;

  /// Vrai si tous les sous-filtres sont désactivés.
  bool get allDisabled =>
      !avoidBarrages &&
      !avoidNasses &&
      !avoidControles &&
      !avoidAccidents &&
      !avoidRassemblements &&
      !avoidAutres;

  AvoidanceFilters copyWith({
    bool? avoidBarrages,
    bool? avoidNasses,
    bool? avoidControles,
    bool? avoidAccidents,
    bool? avoidRassemblements,
    bool? avoidAutres,
    bool? masterSwitch,
  }) {
    return AvoidanceFilters(
      avoidBarrages: avoidBarrages ?? this.avoidBarrages,
      avoidNasses: avoidNasses ?? this.avoidNasses,
      avoidControles: avoidControles ?? this.avoidControles,
      avoidAccidents: avoidAccidents ?? this.avoidAccidents,
      avoidRassemblements: avoidRassemblements ?? this.avoidRassemblements,
      avoidAutres: avoidAutres ?? this.avoidAutres,
      masterSwitch: masterSwitch ?? this.masterSwitch,
    );
  }

  Map<String, dynamic> toJson() => {
        'avoidBarrages': avoidBarrages,
        'avoidNasses': avoidNasses,
        'avoidControles': avoidControles,
        'avoidAccidents': avoidAccidents,
        'avoidRassemblements': avoidRassemblements,
        'avoidAutres': avoidAutres,
        'masterSwitch': masterSwitch,
      };

  /// Indique si un type d'alerte donné doit être évité selon ces filtres.
  bool shouldAvoid(AlertType type) {
    switch (type) {
      case AlertType.barrage:
        return avoidBarrages;
      case AlertType.casseurs:
        return avoidRassemblements;
      case AlertType.danger:
        return avoidAccidents;
      case AlertType.policiers:
        return avoidControles;
      case AlertType.autopompes:
        return avoidAccidents;
      case AlertType.filtre:
        return avoidNasses;
      case AlertType.panic:
      case AlertType.dangerCollectif:
      case AlertType.density:
      case AlertType.autre:
        return avoidAutres;
    }
  }
}
