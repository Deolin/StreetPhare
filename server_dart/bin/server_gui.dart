// server_dart/bin/server_gui.dart
//
// Point d'entrée GUI native Windows/Linux/macOS pour le serveur StreetPhare.
//
// Lance une interface graphique Flutter Desktop qui :
//   - Démarre le serveur Shelf en arrière-plan
//   - Affiche une console temps réel (stdout/stderr)
//   - Propose des boutons d'arrêt/redémarrage
//   - Permet de taper des commandes CLI (/stop, /restart, /kick)
//
// Pour lancer :
//   cd server_dart && dart run bin/server_gui.dart

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Point d'entrée du serveur avec GUI native.
///
/// Cette version minimaliste utilise le terminal directement (pas Flutter Desktop
/// car cela nécessiterait un projet Flutter séparé). Elle offre :
///   - Lancement du serveur Shelf
///   - Écoute des commandes CLI via stdin
///   - Affichage temps réel des logs
///
/// Pour une véritable GUI Flutter Desktop, créez un projet Flutter séparé
/// pointant sur ce binaire comme dépendance.
void main() async {
  print('╔══════════════════════════════════════════════╗');
  print('║     StreetPhare Server — Mode Console        ║');
  print('╠══════════════════════════════════════════════╣');
  print('║  Commandes :                                 ║');
  print('║    /stop     — Arrêter le serveur            ║');
  print('║    /restart  — Redémarrer le serveur         ║');
  print('║    /status   — Afficher l\'état              ║');
  print('║    /kick <id> — Expulser un pair             ║');
  print('║    /help     — Aide                          ║');
  print('║    /quit     — Quitter                       ║');
  print('╚══════════════════════════════════════════════╝');

  Process? serverProcess;
  var running = false;
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 3000;

  Future<void> startServer() async {
    if (running) return;
    print('[GUI] Démarrage du serveur sur le port $port...');
    serverProcess = await Process.start(
      'dart',
      ['run', 'bin/server.dart'],
      environment: {'PORT': '$port'},
      workingDirectory: Directory.current.path,
    );
    running = true;

    serverProcess!.stdout.transform(utf8.decoder).listen((data) {
      for (final line in data.split('\n')) {
        if (line.trim().isNotEmpty) print(line.trim());
      }
    });

    serverProcess!.stderr.transform(utf8.decoder).listen((data) {
      for (final line in data.split('\n')) {
        if (line.trim().isNotEmpty) print('\x1B[31m$line\x1B[0m');
      }
    });

    serverProcess!.exitCode.then((code) {
      print('[GUI] Serveur arrêté (code $code)');
      running = false;
      serverProcess = null;
    });

    // Attendre que le serveur soit prêt.
    await Future.delayed(const Duration(seconds: 2));
    print('[GUI] Dashboard: http://localhost:$port/dashboard');
  }

  Future<void> stopServer() async {
    if (serverProcess == null) return;
    print('[GUI] Arrêt du serveur...');
    serverProcess!.kill(ProcessSignal.sigint);
    try {
      await serverProcess!.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      serverProcess!.kill(ProcessSignal.sigkill);
    }
    serverProcess = null;
    running = false;
    print('[GUI] Serveur arrêté.');
  }

  await startServer();

  // Écoute des commandes CLI.
  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final cmd = line.trim();
    if (cmd.isEmpty) continue;

    switch (cmd.toLowerCase()) {
      case '/stop':
        await stopServer();
        break;
      case '/restart':
        await stopServer();
        await Future.delayed(const Duration(seconds: 1));
        await startServer();
        break;
      case '/status':
        print('[GUI] Serveur: ${running ? "EN COURS (port $port)" : "ARRÊTÉ"}');
        print('[GUI] Dashboard: http://localhost:$port/dashboard');
        break;
      case '/quit':
      case '/exit':
        await stopServer();
        print('[GUI] Au revoir.');
        exit(0);
      case '/help':
        print('Commandes: /stop, /restart, /status, /kick <id>, /help, /quit');
        break;
      default:
        if (cmd.startsWith('/kick ')) {
          final peerId = cmd.substring(6).trim();
          print('[GUI] Kick demandé pour: $peerId (via API admin)');
          try {
            final client = HttpClient();
            final request = await client.postUrl(Uri.parse('http://localhost:$port/api/admin/kick-peer'));
            request.headers.contentType = ContentType.json;
            request.write(jsonEncode({'peer_id': peerId}));
            final response = await request.close();
            print('[GUI] Réponse: ${response.statusCode}');
          } catch (e) {
            print('[GUI] Erreur kick: $e');
          }
        } else {
          print('[GUI] Commande inconnue. Tapez /help.');
        }
    }
  }
}