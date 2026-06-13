// lib/features/routing/domain/models/avoidance_filters.dart
//
// Préférences utilisateur pour le moteur de routage "Safe Path".
//
// L'utilisateur peut, dans les paramètres, cocher/décocher quels
// types de dangers il ACCEPTE de traverser ou veut ABSOLUMENT ÉVITER.
// L'algorithme adapte son calcul en fonction de ces booléens.
//
// Par défaut, on évite les nasses et autopompes (souvent synonymes
// d'embuscade) mais on accepte les barrages filtrants (souvent
// contrôlables, dialogables, etc.).

import 'package:flutter/foundation.dart';

import '../../../../database/alert_model.dart';

/// Préférences d'évitement persistées.
@immutable
class AvoidanceFilters {
  const AvoidanceFilters({
    this.avoidBarrages = false,
    this.avoidNasses = true,
    this.avoidControles = false,
    this.avoidAccidents = true,
    this.avoidRassemblements = false,
    this.avoidAutres = true,
  });

  /// Ne JAMAIS traverser un barrage.
  final bool avoidBarrages;

  /// Ne JAMAIS traverser une nasse (piège).
  final bool avoidNasses;

  /// Ne JAMAIS traverser un contrôle de police.
  final bool avoidControles;

  /// Ne JAMAIS traverser un accident / autopompe.
  final bool avoidAccidents;

  /// Ne JAMAIS traverser une zone de rassemblement à risque.
  final bool avoidRassemblements;

  /// Ne JAMAIS traverser un danger "autre".
  final bool avoidAutres;

  /// Renvoie `true` si le type d'alerte fourni doit être ÉVITÉ
  /// (donc traité comme une barrière infranchissable dans le graphe).
  bool shouldAvoid(AlertType type) {
    switch (type) {
      case AlertType.barrage:
        return avoidBarrages;
      case AlertType.nasse:
        return avoidNasses;
      case AlertType.controle:
        return avoidControles;
      case AlertType.accident:
        return avoidAccidents;
      case AlertType.rassemblement:
        return avoidRassemblements;
      case AlertType.autre:
        return avoidAutres;
      case AlertType.zoneSafe:
        // Les zones safes sont des points positifs, on ne les évite jamais.
        return false;
      case AlertType.panicCollectif:
        // Les alertes panic collectives sont traitées comme des dangers autres.
        return avoidAutres;
      case AlertType.density:
        // La densité est une information de pondération, pas un obstacle bloquant.
        return false;
    }
  }

  AvoidanceFilters copyWith({
    bool? avoidBarrages,
    bool? avoidNasses,
    bool? avoidControles,
    bool? avoidAccidents,
    bool? avoidRassemblements,
    bool? avoidAutres,
  }) {
    return AvoidanceFilters(
      avoidBarrages: avoidBarrages ?? this.avoidBarrages,
      avoidNasses: avoidNasses ?? this.avoidNasses,
      avoidControles: avoidControles ?? this.avoidControles,
      avoidAccidents: avoidAccidents ?? this.avoidAccidents,
      avoidRassemblements: avoidRassemblements ?? this.avoidRassemblements,
      avoidAutres: avoidAutres ?? this.avoidAutres,
    );
  }

  /// Sérialise en `Map<String, dynamic>` pour persistance.
  Map<String, dynamic> toJson() => {
        'ab': avoidBarrages,
        'an': avoidNasses,
        'ac': avoidControles,
        'aa': avoidAccidents,
        'am': avoidRassemblements,
        'ax': avoidAutres,
      };

  factory AvoidanceFilters.fromJson(Map<String, dynamic> json) {
    return AvoidanceFilters(
      avoidBarrages: (json['ab'] as bool?) ?? false,
      avoidNasses: (json['an'] as bool?) ?? true,
      avoidControles: (json['ac'] as bool?) ?? false,
      avoidAccidents: (json['aa'] as bool?) ?? true,
      avoidRassemblements: (json['am'] as bool?) ?? false,
      avoidAutres: (json['ax'] as bool?) ?? true,
    );
  }
}
