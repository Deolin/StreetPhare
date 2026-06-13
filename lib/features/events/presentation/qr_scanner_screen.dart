// lib/features/events/presentation/qr_scanner_screen.dart
//
// Écran plein-écran de scan QR Code.
//
// Ouvre l'appareil photo, détecte un code QR contenant un JSON
// d'événement StreetPhare, et retourne le JSON parsé à l'appelant.
//
// Usage depuis events_screen :
//   final json = await Navigator.push<Map<String, dynamic>>(
//     context,
//     MaterialPageRoute(builder: (_) => const QrScannerScreen()),
//   );
//   if (json != null) await EventManager.instance.addFromSource(json);

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/streetphare_theme.dart';

/// Écran de scan QR Code plein écran.
/// Pop avec `Map<String, dynamic>` (JSON parsé) si succès, `null` sinon.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _ctrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _processing = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_processing) return;

    final rawValue = capture.barcodes
        .map((b) => b.rawValue)
        .where((v) => v != null && v.isNotEmpty)
        .firstOrNull;

    if (rawValue == null) return;

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSON attendu : objet { ... }');
      }

      // Vérifications minimales des champs obligatoires.
      final required = ['code', 'title', 'startAt', 'visibleAt', 'route',
                        'destLat', 'destLng'];
      for (final key in required) {
        if (!decoded.containsKey(key)) {
          throw FormatException('Champ manquant dans le QR : "$key"');
        }
      }

      // Succès → retour à l'écran précédent avec le JSON.
      if (mounted) Navigator.of(context).pop(decoded);
    } catch (e) {
      setState(() {
        _processing = false;
        _error = 'QR Code invalide :\n$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Scanner un QR Code',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          // Bouton torche
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _ctrl,
            builder: (ctx, state, _) {
              final torchOn = state.torchState == TorchState.on;
              return IconButton(
                icon: Icon(
                  torchOn ? Icons.flashlight_on : Icons.flashlight_off,
                  color: torchOn ? StreetPhareTheme.primary : Colors.white54,
                ),
                onPressed: () => _ctrl.toggleTorch(),
                tooltip: torchOn ? 'Éteindre la torche' : 'Allumer la torche',
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Caméra ────────────────────────────────────────────────────────
          MobileScanner(
            controller: _ctrl,
            onDetect: _onDetect,
          ),

          // ── Viseur central ────────────────────────────────────────────────
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(
                  color: StreetPhareTheme.primary,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          // ── Texte d'instruction ───────────────────────────────────────────
          Positioned(
            bottom: 80,
            left: 24,
            right: 24,
            child: Column(
              children: [
                if (_processing)
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      color: StreetPhareTheme.primary,
                      strokeWidth: 3,
                    ),
                  )
                else if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: StreetPhareTheme.danger.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => setState(() => _error = null),
                          child: const Text(
                            'Réessayer',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Pointez la caméra vers le QR Code de l\'événement',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
