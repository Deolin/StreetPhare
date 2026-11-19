// lib/features/trust_group/domain/models/follow_request.dart
//
// Demande de suivi reçue : un autre utilisateur souhaite suivre ma position.

/// Représente une demande de suivi entrante.
class FollowRequest {
  const FollowRequest({
    required this.fromFixedId,
    required this.fromAlias,
    required this.fromEphemeralId,
  });

  /// Désérialisation JSON.
  factory FollowRequest.fromJson(Map<String, dynamic> json) => FollowRequest(
        fromFixedId: (json['fromFixedId'] as String?) ?? '',
        fromAlias: (json['fromAlias'] as String?) ?? 'Ami',
        fromEphemeralId: (json['fromEphemeralId'] as String?) ?? '',
      );

  /// ID secondaire fixe du demandeur.
  final String fromFixedId;

  /// Pseudonyme auto-déclaré du demandeur.
  final String fromAlias;

  /// ID éphémère du demandeur (pour adresser la réponse d'acceptation).
  final String fromEphemeralId;

  /// Sérialisation JSON (persistance des demandes en attente).
  Map<String, dynamic> toJson() => {
        'fromFixedId': fromFixedId,
        'fromAlias': fromAlias,
        'fromEphemeralId': fromEphemeralId,
      };
}
