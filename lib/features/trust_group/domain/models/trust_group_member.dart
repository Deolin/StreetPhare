// lib/features/trust_group/domain/models/trust_group_member.dart
//
// Membre du groupe de confiance. Chaque membre est identifié par un
// « ID secondaire fixe » (stable, partagé hors-ligne avec ses amis),
// distinct de l'ID éphémère rotatif utilisé sur le réseau P2P.

/// Représente un ami de confiance ajouté au groupe.
class TrustGroupMember {
  const TrustGroupMember({required this.alias, required this.fixedId});

  /// Désérialisation JSON.
  factory TrustGroupMember.fromJson(Map<String, dynamic> json) {
    return TrustGroupMember(
      alias: (json['alias'] as String?)?.trim().isNotEmpty == true
          ? (json['alias'] as String).trim()
          : 'Ami',
      fixedId: (json['fixedId'] as String?) ?? '',
    );
  }

  /// Surnom local choisi par l'utilisateur (ex: « Alice »).
  final String alias;

  /// Identifiant secondaire fixe de l'ami (ex: `SP-ABCD-EFGH-JKLM-NPQR`).
  final String fixedId;

  /// Sérialisation JSON (persistance SharedPreferences).
  Map<String, dynamic> toJson() => {'alias': alias, 'fixedId': fixedId};
}
