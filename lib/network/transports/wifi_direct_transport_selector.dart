// lib/network/transports/wifi_direct_transport_selector.dart
export 'wifi_direct_noop.dart'
    if (dart.library.io) 'wifi_direct_transport.dart';
