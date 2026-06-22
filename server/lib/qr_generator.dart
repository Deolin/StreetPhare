// server/lib/qr_generator.dart
//
// Générateur de QR Code pour les événements StreetPhare.
//
// Responsabilités :
//   - Sérialiser un événement en JSON compact
//   - Compresser le JSON avec GZIP
//   - Encoder en Base64
//   - Générer un QR code au format SVG (affichable partout)

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:qr/qr.dart';

import 'models/event.dart';

/// Service de génération de QR codes pour les événements.
class QrGenerator {
  QrGenerator._();
  static final QrGenerator instance = QrGenerator._();


  // ---------------------------------------------------------------------------
  // Encodage du payload QR
  // ---------------------------------------------------------------------------

  /// Génère le payload texte pour un QR code d'événement.
  ///
  /// Format : `SP_EVENT:<base64>` où base64 est le JSON compact compressé GZIP.
  String encodeEventPayload(ServerEvent event) {
    final compact = event.toCompactJson();
    final jsonStr = jsonEncode(compact);
    final compressed = _gzipCompress(jsonStr);
    final b64 = base64UrlEncode(compressed);
    return 'SP_EVENT:$b64';
  }

  /// Décode un payload QR en données JSON brutes (Map).
  static Map<String, dynamic>? decodeEventPayloadRaw(String payload) {
    if (!payload.startsWith('SP_EVENT:')) return null;
    final b64 = payload.substring(9);
    try {
      final compressed = base64Url.decode(b64);
      final jsonStr = _gzipDecompress(compressed);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Génération de QR code en SVG
  // ---------------------------------------------------------------------------

  /// Génère un QR code au format SVG (string XML).
  /// Utilise `QrImage` (helper du package `qr`) pour accéder à la matrice.
  String generateQrSvg(String payload, {int moduleSize = 4}) {
    final qrCode = QrCode.fromData(
      data: payload,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );

    final image = QrImage(qrCode);
    final count = image.moduleCount;
    final size = count * moduleSize;

    final buffer = StringBuffer();
    buffer.writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'width="$size" height="$size" viewBox="0 0 $size $size" '
        'shape-rendering="crispEdges">');
    buffer.writeln('<rect width="100%" height="100%" fill="#ffffff"/>');

    for (int y = 0; y < count; y++) {
      for (int x = 0; x < count; x++) {
        if (image.isDark(y, x)) {
          final rx = x * moduleSize;
          final ry = y * moduleSize;
          buffer.writeln(
              '<rect x="$rx" y="$ry" '
              'width="$moduleSize" height="$moduleSize" fill="#000000"/>');
        }
      }
    }

    buffer.writeln('</svg>');
    return buffer.toString();
  }

  /// Génère un QR code en data URI SVG (prêt pour <img src="...">).
  String generateQrDataUri(String payload, {int moduleSize = 4}) {
    final svg = generateQrSvg(payload, moduleSize: moduleSize);
    // Encode l'SVG en base64 pour une data URI robuste
    final bytes = utf8.encode(svg);
    final b64 = base64Encode(bytes);
    return 'data:image/svg+xml;base64,$b64';
  }

  // ---------------------------------------------------------------------------
  // Génération QR pour un événement
  // ---------------------------------------------------------------------------

  /// Génère un QR code (data URI) pour un événement complet.
  String generateEventQr(ServerEvent event, {int moduleSize = 4}) {
    final payload = encodeEventPayload(event);
    return generateQrDataUri(payload, moduleSize: moduleSize);
  }

  // ---------------------------------------------------------------------------
  // Compression GZIP
  // ---------------------------------------------------------------------------

  static Uint8List _gzipCompress(String data) {
    final bytes = utf8.encode(data);
    final compressed = GZipEncoder().encode(bytes);
    return Uint8List.fromList(compressed);
  }

  static String _gzipDecompress(Uint8List compressed) {
    final bytes = GZipDecoder().decodeBytes(compressed);
    return utf8.decode(bytes);
  }
}