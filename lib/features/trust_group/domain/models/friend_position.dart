// lib/features/trust_group/domain/models/friend_position.dart
//
// Position partagée d'un ami de confiance, reçue via le maillage P2P.

import 'package:latlong2/latlong.dart';

/// Durée après laquelle une position est considérée comme obsolète.
const Duration kFriendPositionTtl = Duration(minutes: 2);

/// Position GPS récente d'un ami de confiance.
class FriendPosition {
  const FriendPosition({
    required this.fixedId,
    required this.lat,
    required this.lng,
    required this.updatedAt,
  });

  /// ID secondaire fixe de l'ami émetteur.
  final String fixedId;

  final double lat;
  final double lng;

  /// Horodatage de réception (UTC).
  final DateTime updatedAt;

  /// Position au format [LatLng].
  LatLng get point => LatLng(lat, lng);

  /// `true` si la position est trop ancienne pour être affichée.
  bool get isStale => DateTime.now().difference(updatedAt) > kFriendPositionTtl;
}
