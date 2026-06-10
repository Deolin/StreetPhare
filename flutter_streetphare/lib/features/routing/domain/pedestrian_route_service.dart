// lib/features/routing/domain/pedestrian_route_service.dart
//
// Interface de domaine pour le service de ROUTAGE PIÉTON.
//
// PRINCIPE FONDAMENTAL :
//   Un itinéraire "Route Safe" DOIT impérativement suivre les voiries
//   praticables à pied (rues, trottoirs, chemins, passages piétons).
//   Il est INTERDIT de tracer des lignes droites à travers des bâtiments,
//   des terrains privés, ou tout obstacle physique.
//
// DEUX MODES D'IMPLÉMENTATION :
//   1. LOCAL (hors-ligne, approximatif) :
//      Algorithme de Dijkstra sur grille GPS (SafePathEngine).
//      Les diagonales sont pénalisées pour limiter les traversées de
//      bâtiments. Efficace en mode dégradé / offline.
//
//   2. RÉSEAU (en ligne, précis) :
//      Appel à un moteur de routage OSM (OSRM, GraphHopper, Valhalla)
//      avec le profil "foot" ou "pedestrian". Garantit que le tracé
//      suit exactement le réseau routier piéton OpenStreetMap.
//
// L'implémentation active est choisie par [SafePathEngine] en fonction
// de la disponibilité réseau.

import 'package:latlong2/latlong.dart';

import 'models/route_result.dart';

// ============================================================================
// Mode de routage piéton
// ============================================================================

/// Stratégie de calcul du chemin piéton.
enum PedestrianRoutingMode {
  /// Calcul local sur grille (offline, approximatif).
  /// Rapide, sans réseau, mais peut traverser des zones non-praticables.
  localGrid,

  /// Calcul via API OSM (OSRM/GraphHopper profil "foot").
  /// Précis, suit le réseau routier réel, mais nécessite une connexion.
  osmNetwork,
}

// ============================================================================
// Contraintes piétonnes
// ============================================================================

/// Paramètres de contraintes spécifiques au routage piéton.
///
/// Ces contraintes sont appliquées lors du calcul d'itinéraire pour
/// garantir que le tracé correspond à ce qu'un piéton peut physiquement
/// parcourir (pas de passages à travers des bâtiments ou obstacles).
class PedestrianConstraints {
  const PedestrianConstraints({
    /// Pénalité appliquée aux mouvements diagonaux dans la grille locale.
    /// Une valeur élevée (ex: 3.0) dissuade les coupes en diagonale à
    /// travers les bâtiments. Valeur recommandée : 2.5–4.0.
    this.diagonalPenaltyFactor = 3.0,

    /// Pénalité de base pour une cellule "inconnue" (ni route ni obstacle).
    /// Force l'algorithme à préférer les chemins confirmés comme praticables.
    this.unknownTerrainPenalty = 150.0,

    /// Pas de grille en mètres (résolution du calcul local).
    /// Un pas plus petit = plus précis mais plus lent.
    /// Valeur recommandée pour zones urbaines : 15–25 m.
    this.gridStepMeters = 20.0,
  });

  /// Facteur de pénalité pour les arêtes diagonales de la grille.
  ///
  /// En mode local, les connexions diagonales (NE, NW, SE, SW) sont
  /// multipliées par ce facteur pour décourager les traversées de
  /// bâtiments situées en diagonale. Les connexions orthogonales
  /// (N, S, E, W) sont supposées suivre la voirie.
  final double diagonalPenaltyFactor;

  /// Pénalité en mètres-équivalent pour les terrains non confirmés.
  final double unknownTerrainPenalty;

  /// Pas de grille en mètres pour le calcul local.
  final double gridStepMeters;

  /// Contraintes standard pour une zone urbaine dense (ex: centre de Fleurus).
  static const PedestrianConstraints urban = PedestrianConstraints(
    diagonalPenaltyFactor: 3.5,
    unknownTerrainPenalty: 200.0,
    gridStepMeters: 20.0,
  );

  /// Contraintes relâchées pour une zone rurale ou semi-urbaine.
  static const PedestrianConstraints rural = PedestrianConstraints(
    diagonalPenaltyFactor: 2.0,
    unknownTerrainPenalty: 80.0,
    gridStepMeters: 30.0,
  );
}

// ============================================================================
// Interface de service — contrat abstrait
// ============================================================================

/// Interface abstraite du service de routage piéton.
///
/// Toute implémentation concrète (locale ou réseau) DOIT garantir
/// que les itinéraires retournés suivent des voiries praticables à pied.
///
/// Implémentations disponibles :
///   - [LocalPedestrianRouteService] : grille Dijkstra (offline)
///   - Intégration future OSRM/GraphHopper (online)
abstract class IPedestrianRouteService {
  /// Calcule 1 à [maxAlternatives] itinéraires piétons entre [start] et [end].
  ///
  /// Garanties :
  ///   - Les itinéraires suivent des voiries praticables à pied.
  ///   - Aucun tracé en ligne droite à travers un bâtiment.
  ///   - Les zones de danger actives (signalements StreetPhare) sont
  ///     évitées ou pénalisées selon les [AvoidanceFilters].
  ///
  /// Retourne une liste vide si aucun itinéraire n'est calculable
  /// (obstacles insurmontables, hors zone de couverture, etc.).
  Future<List<RouteResult>> computePedestrianRoutes({
    required LatLng start,
    required LatLng end,
    PedestrianConstraints constraints = PedestrianConstraints.urban,
  });

  /// Mode actif de routage.
  PedestrianRoutingMode get activeMode;
}

// ============================================================================
// Utilitaires — calcul de distance piéton
// ============================================================================

/// Estime la durée de marche à pied pour une distance donnée.
///
/// Vitesse de marche moyenne retenue : 4,5 km/h (norme OMS pour
/// adultes valides sur terrain urbain).
Duration estimateWalkDuration(double distanceMeters) {
  const metersPerSecond = 4500.0 / 3600.0; // 4,5 km/h → m/s
  return Duration(seconds: (distanceMeters / metersPerSecond).round());
}

/// Formatte une durée de marche en texte lisible.
/// Ex : 35 minutes → "35 min", 75 minutes → "1h 15min".
String formatWalkDuration(Duration d) {
  final totalMin = d.inMinutes;
  if (totalMin < 60) return '$totalMin min';
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}min';
}
