// lib/features/routing/core/models/routing_profile.dart
//
// Profils de routage pour le moteur de calcul d'itinéraire.
// Chaque profil définit les contraintes de poids, de vitesse
// et les types de routes autorisées/évitées.

/// Profil de déplacement.
enum RoutingProfile {
  /// Piéton (marche) — vitesse ~5 km/h, évite escaliers, priorités trottoirs.
  pedestrian,

  /// Vélo — vitesse ~15 km/h, favorise pistes cyclables.
  bicycle,

  /// Véhicule motorisé — vitesse réelle, favorise axes principaux.
  vehicle,

  /// Urgence — priorité absolue aux axes rapides, ignore les blocages.
  emergency,
}

/// Paramètres de pondération pour un profil de routage.
class ProfileSettings {
  const ProfileSettings({
    required this.maxSpeedKmh,
    required this.walkSpeedMs,
    required this.avoidStairs,
    required this.avoidUnpaved,
    required this.useContractionHierarchies,
    required this.heuristicWeight,
    required this.penaltyFactorDiagonal,
    required this.penaltyFactorTurn,
  });

  /// Vitesse maximale autorisée (km/h).
  final double maxSpeedKmh;

  /// Vitesse de marche réelle (m/s) pour l'estimation du temps.
  final double walkSpeedMs;

  /// Éviter les escaliers si true.
  final bool avoidStairs;

  /// Éviter les chemins non revêtus si true.
  final bool avoidUnpaved;

  /// Utiliser les Contraction Hierarchies pour accélérer le calcul.
  final bool useContractionHierarchies;

  /// Poids de l'heuristique A* (1.0 = standard, >1.0 = greedier).
  final double heuristicWeight;

  /// Facteur de pénalité pour les arêtes diagonales (anti-traversée de blocs).
  final double penaltyFactorDiagonal;

  /// Pénalité par changement de direction (anti-zigzag).
  final double penaltyFactorTurn;

  // ── Profils prédéfinis ─────────────────────────────────────────────────

  /// Piéton — 5 km/h, évite escaliers, pénalité diagonale forte.
  static const pedestrian = ProfileSettings(
    maxSpeedKmh: 6,
    walkSpeedMs: 1.4, // 5.0 km/h
    avoidStairs: true,
    avoidUnpaved: true,
    useContractionHierarchies: true,
    heuristicWeight: 1.2,
    penaltyFactorDiagonal: 3.5,
    penaltyFactorTurn: 1.0,
  );

  /// Vélo — 15 km/h, tolère les chemins non revêtus.
  static const bicycle = ProfileSettings(
    maxSpeedKmh: 20,
    walkSpeedMs: 4.2, // 15 km/h
    avoidStairs: true,
    avoidUnpaved: false,
    useContractionHierarchies: true,
    heuristicWeight: 1.1,
    penaltyFactorDiagonal: 2.0,
    penaltyFactorTurn: 0.5,
  );

  /// Véhicule — vitesse réelle, pas de pénalité piétonne.
  static const vehicle = ProfileSettings(
    maxSpeedKmh: 120,
    walkSpeedMs: 0,
    avoidStairs: false,
    avoidUnpaved: false,
    useContractionHierarchies: true,
    heuristicWeight: 1.05,
    penaltyFactorDiagonal: 1.0,
    penaltyFactorTurn: 0.3,
  );

  /// Urgence — ignore les blocages, favorise les grands axes.
  static const emergency = ProfileSettings(
    maxSpeedKmh: 140,
    walkSpeedMs: 0,
    avoidStairs: false,
    avoidUnpaved: false,
    useContractionHierarchies: false, // pas de CH pour urgence (routes variables)
    heuristicWeight: 1.5,
    penaltyFactorDiagonal: 1.0,
    penaltyFactorTurn: 0.0, // pas de pénalité de virage
  );

  /// Résout le profil depuis l'enum.
  static ProfileSettings from(RoutingProfile profile) {
    return switch (profile) {
      RoutingProfile.pedestrian => pedestrian,
      RoutingProfile.bicycle => bicycle,
      RoutingProfile.vehicle => vehicle,
      RoutingProfile.emergency => emergency,
    };
  }

  /// Durée estimée du trajet pour une distance donnée.
  Duration estimateDuration(double distanceMeters) {
    if (walkSpeedMs <= 0) return Duration.zero;
    return Duration(milliseconds: (distanceMeters / walkSpeedMs * 1000).round());
  }
}