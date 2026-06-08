import 'package:flutter/material.dart';

/// Modèle décrivant un type de signalement citoyen.
///
/// Chaque type est associé à :
///   - Un libellé affiché dans la feuille d'ancrage
///   - Une icône
///   - Une couleur
///   - Un identifiant technique
enum ReportType {
  barrages(
    id: 'barrages',
    label: 'Barrages',
    icon: Icons.block,
    color: Color(0xFFE53935),
  ),
  zonesFiltrees(
    id: 'zones_filtrees',
    label: 'Zones filtrées',
    icon: Icons.filter_alt,
    color: Color(0xFFFF9800),
  ),
  nasses(
    id: 'nasses',
    label: 'Nasses',
    icon: Icons.crop_square,
    color: Color(0xFFFFB300),
  ),
  autopompes(
    id: 'autopompes',
    label: 'Autopompes',
    icon: Icons.local_fire_department,
    color: Color(0xFF1976D2),
  ),
  policiers(
    id: 'policiers',
    label: 'Policiers',
    icon: Icons.local_police,
    color: Color(0xFF3F51B5),
  ),
  dangers(
    id: 'dangers',
    label: 'Dangers',
    icon: Icons.warning_amber,
    color: Color(0xFFFF6F00),
  ),
  groupesCasseurs(
    id: 'groupes_casseurs',
    label: 'Groupes de casseurs',
    icon: Icons.groups,
    color: Color(0xFF7B1FA2),
  );

  const ReportType({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color color;
}
