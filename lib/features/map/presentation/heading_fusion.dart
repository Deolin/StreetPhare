// lib/features/map/presentation/heading_fusion.dart
//
// Fusion de capteurs pour estimer le cap (orientation) de l'utilisateur de
// façon fluide et stabilisée :
//   - gyroscope      -> vitesse de rotation (lacet) intégrée à court terme
//   - accéléromètre  -> inclinaison de l'appareil + détection de mouvement
//   - références absolues (compas magnétomètre / cap GPS) -> correction du drift
//
// Filtre complémentaire : le gyroscope fournit des variations continues et
// instantanées (y compris dans les zones où le magnétomètre est bruité ou
// semble « bloqué »), tandis que les références absolues corrigent la dérive
// en douceur. Tous les raccourcis angulaires passent par le chemin le plus
// court afin d'éviter les sauts 359° -> 0°.

import 'dart:math' as math;

/// Angle normalisé dans [0, 360).
double normalizeDeg360(double deg) {
  var v = deg % 360.0;
  if (v < 0) v += 360.0;
  return v;
}

/// Angle normalisé dans [-180, 180).
double normalizeDegSigned(double deg) {
  var v = deg % 360.0;
  if (v > 180) v -= 360.0;
  if (v < -180) v += 360.0;
  return v;
}

/// Delta angulaire le plus court de [from] vers [to], dans (-180, 180].
double shortestAngleDelta(double from, double to) =>
    normalizeDegSigned(to - from);

/// Fusion de capteurs pour le cap de l'utilisateur.
class HeadingFusion {
  // Cap fusionné interne, en degrés, normalisé [-180, 180).
  double _heading = 0.0;
  bool _initialized = false;

  double _turnRateDegPerSec = 0.0;
  double _userAccelMag = 0.0;
  String _gravityAxis = 'z';
  bool _level = true;
  DateTime? _lastGyroTime;

  /// Cap fusionné en degrés, normalisé dans [0, 360).
  double get heading => normalizeDeg360(_heading);

  /// Vitesse de rotation de lacet en °/s (positif = sens horaire).
  double get turnRateDegPerSec => _turnRateDegPerSec;

  /// Norme de l'accélération « utilisateur » (gravité retirée) en m/s².
  double get userAccelMag => _userAccelMag;

  /// `true` si l'appareil est proche d'une orientation alignée (gravité
  /// concentrée sur un axe), donc compas magnétique fiable.
  bool get level => _level;

  /// `true` si l'utilisateur semble en mouvement (accélération linéaire).
  bool get isMoving => _userAccelMag > 0.35;

  /// Intègre l'échantillon gyroscopique (rad/s). L'axe de lacet est choisi
  /// selon l'orientation dominante détectée par l'accéléromètre.
  void onGyroscope(double x, double y, double z, DateTime timestamp) {
    final prev = _lastGyroTime;
    _lastGyroTime = timestamp;

    final double rate;
    if (_gravityAxis == 'x') {
      rate = x;
    } else if (_gravityAxis == 'y') {
      rate = y;
    } else {
      rate = z;
    }
    // Signe : virage horaire (cap croissant) <-> rotation négative autour de
    // l'axe vertical (convention main droite).
    _turnRateDegPerSec = -rate * 180.0 / math.pi;

    if (prev == null) return;
    final dt = timestamp.difference(prev).inMicroseconds / 1e6;
    // Rejette les dt aberrants (pause du capteur, premier échantillon...).
    if (dt <= 0 || dt > 0.5) return;

    // Terme « rapide » du filtre complémentaire : intégration gyroscopique.
    _heading = normalizeDegSigned(_heading + _turnRateDegPerSec * dt);
  }

  /// Met à jour l'inclinaison depuis l'accéléromètre (m/s², gravité incluse).
  /// Permet de choisir l'axe de lacet et d'évaluer la fiabilité du compas.
  void onAccelerometer(double x, double y, double z) {
    final mag = math.sqrt(x * x + y * y + z * z);
    if (mag < 0.5) return; // capteur non initialisé / chute libre

    final ax = (x / mag).abs();
    final ay = (y / mag).abs();
    final az = (z / mag).abs();

    if (az >= ax && az >= ay) {
      _gravityAxis = 'z';
    } else if (ay >= ax) {
      _gravityAxis = 'y';
    } else {
      _gravityAxis = 'x';
    }

    // Appareil « niveau » si la gravité est concentrée sur un axe dominant.
    final dominant = math.max(az, math.max(ay, ax));
    _level = dominant > 0.75;
  }

  /// Accélération linéaire (gravité retirée) -> détection de mouvement.
  void onUserAccelerometer(double x, double y, double z) {
    _userAccelMag = math.sqrt(x * x + y * y + z * z);
  }

  /// Corrige le cap vers une référence absolue (compas ou cap GPS) avec une
  /// confiance [trust] dans [0, 1]. Le chemin le plus court est utilisé.
  void feedAbsolute(double refDeg, double trust) {
    final ref = normalizeDegSigned(refDeg);
    if (!_initialized) {
      _heading = ref;
      _initialized = true;
      return;
    }
    final delta = shortestAngleDelta(_heading, ref);
    _heading = normalizeDegSigned(_heading + delta * trust.clamp(0.0, 1.0));
  }
}
