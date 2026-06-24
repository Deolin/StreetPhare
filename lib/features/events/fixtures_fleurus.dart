// lib/features/events/fixtures_fleurus.dart
//
// Constantes géographiques de démonstration pour les événements
// StreetPhare. Extraites de `event_manager.dart` pour assainir
// le code de production.
//
// Toutes les coordonnées GPS sont réelles — commune de Fleurus
// (6220), Belgique.

import 'domain/models/event_model.dart';

/// Coordonnées des lieux-clés de Fleurus.
abstract final class FleurusLocations {
  FleurusLocations._();

  /// Place Albert 1er (centre-ville)
  static const double placeAlbertLat = 50.4762;
  static const double placeAlbertLng = 4.5422;

  /// Institut Notre-Dame (Rue de la Station)
  static const double institutNotreDameLat = 50.4770;
  static const double institutNotreDameLng = 4.5461;

  /// Athénée Royal Jourdan (Rue de la Digue)
  static const double atheneeRoyalLat = 50.4742;
  static const double atheneeRoyalLng = 4.5349;

  /// Poste de Police (Square de l'Europe)
  static const double postePoliceLat = 50.4752;
  static const double postePoliceLng = 4.5418;

  /// Piscine de Fleurus (Rue Fleurjoux)
  static const double piscineLat = 50.4707;
  static const double piscineLng = 4.5553;

  // Points de passage intermédiaires
  static const double rueStationLat = 50.4790;
  static const double rueStationLng = 4.5468;

  static const double routeGosseliesLat = 50.4705;
  static const double routeGosseliesLng = 4.5450;

  static const double rueChausseeLat = 50.4730;
  static const double rueChausseeLng = 4.5480;

  static const double sortieNordLat = 50.4810;
  static const double sortieNordLng = 4.5440;

  static const double sortieRueNamurLat = 50.4752;
  static const double sortieRueNamurLng = 4.5390;

  static const double zoneRepliRadius = 60.0;
  static const double zoneRepliPiscineRadius = 50.0;
}

/// Centre de soins St-Medic — positionné stratégiquement sur la
/// Place Albert 1er, au cœur de Fleurus.
const EventCareCenter stMedicCareCenter = EventCareCenter(
  label: 'St-Medic — Place Albert 1er',
  latitude: FleurusLocations.placeAlbertLat,
  longitude: FleurusLocations.placeAlbertLng,
  contact: '+32 71 82 XX XX',
  notes: 'Point médical permanent — centre-ville Fleurus.',
);

/// Polylines piétonnes réelles de Fleurus (GeoJSON [[lng,lat],...]).
abstract final class FleurusPolylines {
  FleurusPolylines._();

  /// Tour de Fleurus — boucle ~4 km autour du centre.
  static const String tourFleurus =
      '[[4.5422,50.4762],[4.5440,50.4780],[4.5468,50.4790],'
      '[4.5510,50.4785],[4.5550,50.4760],[4.5535,50.4730],'
      '[4.5500,50.4710],[4.5450,50.4705],[4.5390,50.4720],'
      '[4.5370,50.4750],[4.5390,50.4762],[4.5422,50.4762]]';

  /// Traversée des écoles — Institut Notre-Dame → Athénée Royal.
  static const String traverseeEcoles =
      '[[4.5461,50.4770],[4.5450,50.4765],[4.5430,50.4762],'
      '[4.5410,50.4758],[4.5390,50.4752],[4.5375,50.4748],'
      '[4.5355,50.4745],[4.5349,50.4742]]';

  /// Cortège Police — Poste de Police → Piscine.
  static const String cortegePolice =
      '[[4.5418,50.4752],[4.5430,50.4749],[4.5445,50.4745],'
      '[4.5460,50.4740],[4.5480,50.4730],[4.5505,50.4720],'
      '[4.5520,50.4714],[4.5535,50.4710],[4.5553,50.4707]]';
}