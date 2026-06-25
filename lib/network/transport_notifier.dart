// lib/network/transport_notifier.dart
//
// Widget d'écoute de la machine d'état réseau.
//
// Se place à la racine de l'application (au-dessus de MaterialApp
// ou dans le Scaffold principal) pour écouter [NetworkManager] et
// afficher automatiquement les notifications de basculement réseau
// sans bloquer l'interface utilisateur.

import 'package:flutter/material.dart';

import 'network_manager.dart';

/// Callback appelé quand un basculement de transport a lieu.
/// Reçoit le transport précédent et le nouveau transport.
typedef TransportSwitchCallback = void Function(
  NetworkTransport from,
  NetworkTransport to,
);

/// Widget non visuel qui écoute [NetworkManager] et délègue les
/// notifications à un callback. Se place idéalement dans le
/// `builder` de `MaterialApp` ou dans le `Scaffold` principal.
class TransportNotifier extends StatefulWidget {
  const TransportNotifier({
    super.key,
    required this.child,
    this.onSwitch,
  });

  final Widget child;
  final TransportSwitchCallback? onSwitch;

  @override
  State<TransportNotifier> createState() => _TransportNotifierState();
}

class _TransportNotifierState extends State<TransportNotifier> {
  NetworkTransport _previous = NetworkTransport.none;
  bool _isolationShown = false;

  @override
  void initState() {
    super.initState();
    NetworkManager.instance.addListener(_onNetworkChanged);
    _previous = NetworkManager.instance.currentTransport;
  }

  @override
  void dispose() {
    NetworkManager.instance.removeListener(_onNetworkChanged);
    super.dispose();
  }

  void _onNetworkChanged() {
    final current = NetworkManager.instance.currentTransport;
    if (current != _previous) {
      widget.onSwitch?.call(_previous, current);
      // Affiche un SnackBar de basculement (non bloquant).
      _showSwitchNotification(_previous, current);
      _previous = current;
    }

    if (current == NetworkTransport.none && !_isolationShown) {
      _isolationShown = true;
      _showIsolationMessage();
    } else if (current != NetworkTransport.none && _isolationShown) {
      _isolationShown = false;
    }
  }

  void _showSwitchNotification(NetworkTransport from, NetworkTransport to) {
    if (!mounted) return;
    final reason = _switchReason(from, to);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(_transportIcon(to), color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(reason)),
          ],
        ),
        backgroundColor: Colors.blueGrey.shade700,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  void _showIsolationMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.signal_wifi_off, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Vous êtes isolé du réseau 😭\n'
                'StreetPhare va vous reconnecter dès que possible.',
              ),
            ),
          ],
        ),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  String _transportLabel(NetworkTransport t) {
    switch (t) {
      case NetworkTransport.ble:
        return 'BLE P2P';
      case NetworkTransport.wifiDirect:
        return 'Wi-Fi Direct';
      case NetworkTransport.cellular:
        return 'Relais Internet';
      case NetworkTransport.none:
        return 'Aucun';
    }
  }

  IconData _transportIcon(NetworkTransport t) {
    switch (t) {
      case NetworkTransport.ble:
        return Icons.bluetooth;
      case NetworkTransport.wifiDirect:
        return Icons.wifi;
      case NetworkTransport.cellular:
        return Icons.signal_cellular_alt;
      case NetworkTransport.none:
        return Icons.signal_wifi_off;
    }
  }

  String _switchReason(NetworkTransport from, NetworkTransport to) {
    final fromLabel = _transportLabel(from);
    final toLabel = _transportLabel(to);
    if (to == NetworkTransport.none) {
      return 'Tous les réseaux sont indisponibles.';
    }
    return '$fromLabel perdu, basculement sur $toLabel…';
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Widget de vérification périodique du matériel (Bluetooth / Wi-Fi éteint).
///
/// Affiche un bandeau d'action si un capteur requis est désactivé au
/// niveau système.
class HardwareStatusBanner extends StatefulWidget {
  const HardwareStatusBanner({super.key, required this.child});
  final Widget child;

  @override
  State<HardwareStatusBanner> createState() => _HardwareStatusBannerState();
}

class _HardwareStatusBannerState extends State<HardwareStatusBanner> {
  bool _bleDisabled = false;
  bool _wifiDisabled = false;

  @override
  void initState() {
    super.initState();
    _checkHardware();
    NetworkManager.instance.addListener(_checkHardware);
  }

  @override
  void dispose() {
    NetworkManager.instance.removeListener(_checkHardware);
    super.dispose();
  }

  void _checkHardware() {
    final status = NetworkManager.instance.hardwareStatus;
    setState(() {
      _bleDisabled = status['ble'] == false;
      _wifiDisabled = status['wifi'] == false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_bleDisabled)
          MaterialBanner(
            content: const Text(
              'Le Bluetooth est désactivé.\n'
              'Réactivez-le pour détecter les appareils StreetPhare à proximité.',
              style: TextStyle(color: Colors.white),
            ),
            leading: const Icon(Icons.bluetooth_disabled, color: Colors.white),
            backgroundColor: Colors.blueGrey.shade800,
            actions: [
              TextButton(
                onPressed: () =>
                    NetworkManager.instance.openBluetoothSettings(),
                child: const Text('ACTIVER',
                    style: TextStyle(color: Colors.cyanAccent)),
              ),
            ],
          ),
        if (_wifiDisabled)
          MaterialBanner(
            content: const Text(
              'Le Wi-Fi est désactivé.\n'
              'Réactivez-le pour le maillage P2P local.',
              style: TextStyle(color: Colors.white),
            ),
            leading: const Icon(Icons.wifi_off, color: Colors.white),
            backgroundColor: Colors.blueGrey.shade800,
            actions: [
              TextButton(
                onPressed: () => NetworkManager.instance.openWifiSettings(),
                child: const Text('ACTIVER',
                    style: TextStyle(color: Colors.cyanAccent)),
              ),
            ],
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}
