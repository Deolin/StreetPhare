// lib/features/map/presentation/widgets/long_press_detector.dart
//
// Détecteur d'appui long configurable (par défaut > 3 secondes).
//
// Contrairement à `GestureDetector.onLongPress` (durée fixe ~500 ms), ce
// widget permet de définir une durée personnalisée via un
// `LongPressGestureRecognizer`. Utilisé pour déclencher la « route safe »
// sur un appui prolongé de l'icône d'un événement.

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Détecte un appui long de durée [duration] sur [child].
class LongPressDetector extends StatelessWidget {
  const LongPressDetector({
    super.key,
    required this.onLongPress,
    required this.child,
    this.duration = const Duration(seconds: 3),
  });

  /// Callback déclenché à la fin de l'appui long.
  final VoidCallback onLongPress;

  /// Contenu à observer.
  final Widget child;

  /// Durée de l'appui avant déclenchement (défaut : 3 s).
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<
            LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(duration: duration),
          (LongPressGestureRecognizer recognizer) {
            recognizer.onLongPress = onLongPress;
          },
        ),
      },
      child: child,
    );
  }
}
