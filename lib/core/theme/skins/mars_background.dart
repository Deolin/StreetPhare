// lib/core/theme/skins/mars_background.dart
//
// Fond texturé rétro-sci-fi / pulp art du skin « Mars Attacks ».
//
// Enveloppe le contenu d'un écran (menu) avec une image de fond rétro
// affichée à faible opacité, recouverte d'un filtre sombre pour que le
// texte et les contrôles restent parfaitement lisibles.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_skin.dart';
import '../skin_controller.dart';

/// Applique le fond rétro « Mars Attacks » derrière [child].
///
/// Hors du skin `mars_attacks`, rend simplement [child] (aucun surcoût).
/// Réactif : écoute [SkinController] pour basculer à chaud.
class MarsBackground extends StatelessWidget {
  const MarsBackground({super.key, required this.child});

  /// Contenu du menu (Scaffold, colonne, …).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSkin>(
      valueListenable: SkinController.instance,
      builder: (context, skin, _) {
        final isMars = skin == AppSkin.marsAttacks;
        // Structure stable (Stack + 3 enfants toujours présents) : évite le
        // changement dynamique de type d'enfant qui déclenche l'assertion
        // framework « !semantics.parentDataDirty » (Flutter 3.41+).
        return Stack(
          fit: StackFit.expand,
          children: [
            // Image de fond rétro-sci-fi (opacité réduite).
            Offstage(
              offstage: !isMars,
              child: Opacity(
                opacity: 0.15,
                child: SvgPicture.asset(
                  'assets/mars/mars_background.svg',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            // Filtre sombre pour garantir la lisibilité.
            Offstage(
              offstage: !isMars,
              child: const ColoredBox(color: Color(0x66000000)),
            ),
            child,
          ],
        );
      },
    );
  }
}
