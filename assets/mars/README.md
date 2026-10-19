# Assets « Mars Attacks » — skin rétro-sci-fi / pulp art

Ce dossier contient les assets vectoriels (SVG) du skin « Mars Attacks ».

## Fichiers

| Fichier | Usage |
|---|---|
| `alien_head.svg` | Marqueur cartographique des signalements **Police** (tête d'alien) |
| `cow.svg` | Marqueur cartographique des signalements **Barrage** (vache — clin d'œil aux enlèvements de bestiaux) |
| `spaceship.svg` | Marqueur cartographique des signalements **Autopompes** (vaisseau simplifié) |
| `mars_background.svg` | Fond texturé rétro-sci-fi des menus principaux (rendu en opacité réduite) |
| `launcher_icon.svg` | Source vectorielle de l'icône d'application |

## Générer l'icône d'application (`flutter_launcher_icons`)

`flutter_launcher_icons` exige une image **PNG** (carrée, idéalement 1024×1024),
pas un SVG. Étapes :

1. Convertissez `launcher_icon.svg` en PNG (1024×1024) :
   - ImageMagick : `magick launcher_icon.svg -resize 1024x1024 launcher_icon.png`
   - rsvg-convert : `rsvg-convert -w 1024 -h 1024 launcher_icon.svg -o launcher_icon.png`
   - ou un convertisseur en ligne (SVG → PNG).
2. Placez le PNG à `assets/mars/launcher_icon.png`.
3. Lancez la génération :
   ```
   flutter pub get
   flutter pub run flutter_launcher_icons
   ```

## Rendu des marqueurs

Les marqueurs sont rendus via `flutter_svg` (`SvgPicture.asset`) uniquement
lorsque le skin `mars_attacks` est actif. Sinon, les icônes Material
standards sont conservées.
