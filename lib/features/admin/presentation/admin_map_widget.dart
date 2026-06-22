// lib/features/admin/presentation/admin_map_widget.dart
//
// Widget de carte partagé pour le Dashboard d'Administration Web.
//
// Ce widget est extrait des fonctionnalités de `map_screen.dart`
// pour être réutilisable dans le tableau de bord admin côté à côte
// avec les données analytiques.
//
// Fonctionnalités :
//   - flutter_map avec tuiles sombres (CartoDB dark_all) par défaut
//   - Écoute du flux d'alertes global (NetworkCoordinator.instance.alertsStream)
//   - Affichage temps réel des marqueurs d'alertes sur la carte
//   - Support du mode sombre (forcé à true dans le dashboard)
//   - Zoom/pan standard (rotation désactivée)
//   - Marqueurs colorés par type d'alerte

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../database/alert_model.dart';
import '../../../network/network_coordinator.dart';

/// URL des tuiles sombres CartoDB (dashboard admin).
const String _kTileUrlDark =
    'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
const String _kTileUrlLight =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Widget de carte autonome pour le Dashboard Admin.
///
/// Affiche une carte flutter_map avec les alertes en temps réel.
/// S'intègre dans n'importe quel layout (colonne, ligne, Stack).
class AdminMapWidget extends StatefulWidget {
  const AdminMapWidget({
    super.key,
    this.height,
    this.width,
    this.initialCenter = const LatLng(50.4762, 4.5422),
    this.initialZoom = 14.0,
    this.darkMode = true,
    this.showAttribution = true,
  });

  /// Hauteur du widget (null = s'étend dans le parent).
  final double? height;

  /// Largeur du widget (null = s'étend dans le parent).
  final double? width;

  /// Centre initial de la carte.
  final LatLng initialCenter;

  /// Zoom initial.
  final double initialZoom;

  /// Force le mode sombre (true par défaut pour le dashboard).
  final bool darkMode;

  /// Affiche l'attribution des tuiles.
  final bool showAttribution;

  @override
  State<AdminMapWidget> createState() => _AdminMapWidgetState();
}

class _AdminMapWidgetState extends State<AdminMapWidget> {
  final MapController _mapController = MapController();

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  /// Convertit un [AlertType] en couleur de marqueur.
  Color _colorForAlertType(AlertType type) {
    switch (type) {
      case AlertType.barrage:
        return Colors.red;
      case AlertType.barrage:
        return Colors.orange;
      case AlertType.policiers:
        return Colors.blue;
      case AlertType.danger:
        return Colors.purple;
      case AlertType.casseurs:
        return Colors.amber;
      case AlertType.autre:
        return Colors.green;
      case AlertType.dangerCollectif:
        return Colors.redAccent;
      case AlertType.density:
        return Colors.cyanAccent;
      case AlertType.autre:
        return Colors.grey;
    }
  }

  /// Icône pour le type d'alerte.
  IconData _iconForAlertType(AlertType type) {
    switch (type) {
      case AlertType.barrage:
        return Icons.block;
      case AlertType.barrage:
        return Icons.safety_check;
      case AlertType.policiers:
        return Icons.local_police;
      case AlertType.danger:
        return Icons.warning_amber;
      case AlertType.casseurs:
        return Icons.groups;
      case AlertType.autre:
        return Icons.shield;
      case AlertType.dangerCollectif:
        return Icons.campaign;
      case AlertType.density:
        return Icons.people;
      case AlertType.autre:
        return Icons.error;
    }
  }

  /// Construit la liste des marqueurs à partir du flux d'alertes.
  List<Marker> _buildMarkers(List<Alert> alerts) {
    return alerts
        .where((a) => a.status == AlertStatus.active ||
            a.status == AlertStatus.pending)
        .map((alert) {
      final color = _colorForAlertType(alert.type);
      return Marker(
        point: LatLng(alert.latitude, alert.longitude),
        width: 36,
        height: 36,
        child: Tooltip(
          message: '${_describeAlertType(alert.type)} '
              '(${alert.createdAt.hour}:${alert.createdAt.minute.toString().padLeft(2, '0')})',
          child: Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.9),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              _iconForAlertType(alert.type),
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      );
    }).toList();
  }

  String _describeAlertType(AlertType type) {
    switch (type) {
      case AlertType.barrage:
        return 'Barrage';
      case AlertType.barrage:
        return 'Nasse';
      case AlertType.policiers:
        return 'Contrôle';
      case AlertType.danger:
        return 'Accident';
      case AlertType.casseurs:
        return 'Rassemblement';
      case AlertType.autre:
        return 'Zone sûre';
      case AlertType.dangerCollectif:
        return 'Panic';
      case AlertType.density:
        return 'Densité';
      case AlertType.autre:
        return 'Autre';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tileUrl = widget.darkMode ? _kTileUrlDark : _kTileUrlLight;

    return SizedBox(
      height: widget.height,
      width: widget.width,
      child: StreamBuilder<List<Alert>>(
        stream: NetworkCoordinator.instance.alertsStream,
        builder: (context, snapshot) {
          final alerts = snapshot.data ?? [];
          final markers = _buildMarkers(alerts);

          return FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.initialCenter,
              initialZoom: widget.initialZoom,
              minZoom: 3,
              maxZoom: 19,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: tileUrl,
                userAgentPackageName: 'com.streetphare.admin',
                maxNativeZoom: 19,
                tileDisplay: TileDisplay.fadeIn(
                  duration: const Duration(milliseconds: 200),
                ),
              ),
              if (markers.isNotEmpty) MarkerLayer(markers: markers),
              if (widget.showAttribution)
                RichAttributionWidget(
                  alignment: AttributionAlignment.bottomLeft,
                  attributions: [
                    TextSourceAttribution(
                      widget.darkMode
                          ? 'CartoDB / OpenStreetMap contributors'
                          : 'OpenStreetMap contributors',
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}