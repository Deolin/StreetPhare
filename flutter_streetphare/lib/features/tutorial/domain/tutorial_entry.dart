// lib/features/tutorial/domain/tutorial_entry.dart
//
// Modèle de données d'une entrée du tutoriel applicatif.
//
// Le tutoriel est structuré comme un tableau de données catégorisées :
//   Catégorie | Fonctionnalité | Description utilisateur
//
// RÈGLE D'OR D'INTERFACE : les descriptions sont purement fonctionnelles
// et abstraites. Elles décrivent CE QUE FAIT l'outil, jamais COMMENT
// il le fait. Les termes techniques sous-jacents (implémentation,
// protocoles, identifiants) sont réservés au code source.

/// Catégories de fonctionnalités affichées dans le tutoriel.
enum TutorialCategory {
  /// Fonctionnalités liées à la navigation et à la carte.
  navigation,

  /// Fonctionnalités liées à la coordination collective.
  coordination,

  /// Fonctionnalités liées à la sécurité personnelle.
  securite,

  /// Fonctionnalités liées aux alertes et signalements.
  alertes,

  /// Fonctionnalités liées aux paramètres et configurations.
  configuration,
}

extension TutorialCategoryLabel on TutorialCategory {
  String get label {
    switch (this) {
      case TutorialCategory.navigation:
        return 'Navigation';
      case TutorialCategory.coordination:
        return 'Coordination';
      case TutorialCategory.securite:
        return 'Sécurité';
      case TutorialCategory.alertes:
        return 'Alertes';
      case TutorialCategory.configuration:
        return 'Configuration';
    }
  }

  /// Icône associée à la catégorie (matériel icon code point).
  String get iconName {
    switch (this) {
      case TutorialCategory.navigation:
        return 'map';
      case TutorialCategory.coordination:
        return 'groups';
      case TutorialCategory.securite:
        return 'shield';
      case TutorialCategory.alertes:
        return 'warning';
      case TutorialCategory.configuration:
        return 'settings';
    }
  }
}

/// Une entrée individuelle dans le tableau du tutoriel.
///
/// [category]    : catégorie fonctionnelle (Navigation, Sécurité, etc.).
/// [feature]     : nom court de la fonctionnalité.
/// [description] : explication utilisateur — fonctionnelle et abstraite,
///                 sans jamais mentionner la technologie sous-jacente.
class TutorialEntry {
  const TutorialEntry({
    required this.category,
    required this.feature,
    required this.description,
  });

  final TutorialCategory category;

  /// Nom court de la fonctionnalité (affiché dans la colonne du milieu).
  final String feature;

  /// Description fonctionnelle destinée à l'utilisateur final.
  /// DOIT rester abstraite sur la technologie.
  final String description;
}

// ============================================================================
// Données du tutoriel — liste statique de toutes les entrées
// ============================================================================

/// Retourne la liste complète des entrées du tutoriel, organisées par
/// catégorie. Ces descriptions sont volontairement fonctionnelles :
/// elles expliquent l'expérience utilisateur, pas l'implémentation.
const List<TutorialEntry> kTutorialEntries = [

  // ── Navigation ─────────────────────────────────────────────────────────────

  TutorialEntry(
    category: TutorialCategory.navigation,
    feature: 'Carte en temps réel',
    description:
        'La carte s\'actualise automatiquement avec les signalements de '
        'votre entourage. Les zones à risque sont colorisées en fonction '
        'de leur intensité signalée.',
  ),
  TutorialEntry(
    category: TutorialCategory.navigation,
    feature: 'Route Safe',
    description:
        'Calcule un itinéraire piéton sécurisé entre votre position et '
        'une destination, en contournant les zones signalées comme '
        'dangereuses par les autres participants.',
  ),
  TutorialEntry(
    category: TutorialCategory.navigation,
    feature: 'Itinéraires alternatifs',
    description:
        'Le moteur vous propose jusqu\'à 3 variantes d\'itinéraire. '
        'Choisissez celui qui vous convient selon la distance et le '
        'niveau de risque estimé.',
  ),
  TutorialEntry(
    category: TutorialCategory.navigation,
    feature: 'Événements & Tracés',
    description:
        'Rejoignez un événement via un code d\'invitation ou un QR Code. '
        'Le tracé du parcours ne se révèle qu\'à l\'heure définie par '
        'les organisateurs, pour éviter qu\'il soit connu en avance.',
  ),

  // ── Coordination ───────────────────────────────────────────────────────────

  TutorialEntry(
    category: TutorialCategory.coordination,
    feature: 'Réseau de proximité',
    description:
        'L\'application échange des informations avec les appareils '
        'à proximité, même sans connexion internet. Plus les participants '
        'sont nombreux et proches, plus le réseau est robuste.',
  ),
  TutorialEntry(
    category: TutorialCategory.coordination,
    feature: 'Fonctionnement hors-ligne',
    description:
        'En cas de coupure réseau ou de saturation mobile, l\'application '
        'continue de fonctionner grâce aux échanges directs entre appareils '
        'proches. Aucune infrastructure centrale n\'est requise.',
  ),
  TutorialEntry(
    category: TutorialCategory.coordination,
    feature: 'Étapes juste-à-temps',
    description:
        'Les points de rassemblement d\'un événement sont révélés '
        'progressivement, selon l\'avancement du parcours. Une étape '
        'disparaît automatiquement une fois franchie ou expirée.',
  ),

  // ── Sécurité ───────────────────────────────────────────────────────────────

  TutorialEntry(
    category: TutorialCategory.securite,
    feature: 'Bouton Panic',
    description:
        'En situation d\'urgence, ce bouton envoie instantanément votre '
        'position GPS par SMS à vos contacts d\'urgence pré-configurés. '
        'Appuyez 3 secondes pour éviter les faux déclenchements.',
  ),
  TutorialEntry(
    category: TutorialCategory.securite,
    feature: 'Centre de soins',
    description:
        'L\'application indique sur la carte les points de secours et '
        'd\'assistance médicale déclarés pour votre événement. '
        'Le moteur Route Safe peut vous y guider automatiquement.',
  ),
  TutorialEntry(
    category: TutorialCategory.securite,
    feature: 'Zones de repli',
    description:
        'Des zones de sécurité prédéfinies sont intégrées dans chaque '
        'événement. En cas de besoin, le moteur de navigation vous '
        'oriente vers la plus proche.',
  ),
  TutorialEntry(
    category: TutorialCategory.securite,
    feature: 'Confidentialité totale',
    description:
        'Aucune donnée personnelle n\'est collectée ni transmise à '
        'des serveurs tiers. Votre identité est protégée : l\'application '
        'utilise des identifiants temporaires renouvelés régulièrement.',
  ),

  // ── Alertes ────────────────────────────────────────────────────────────────

  TutorialEntry(
    category: TutorialCategory.alertes,
    feature: 'Signaler un danger',
    description:
        'Appuyez sur la carte pour signaler un danger (barrage, zone '
        'encerclée, contrôle, accident...). Votre signalement est '
        'automatiquement partagé avec les participants proches.',
  ),
  TutorialEntry(
    category: TutorialCategory.alertes,
    feature: 'Confirmation collective',
    description:
        'Un signalement devient visible sur la carte de tous une fois '
        'confirmé par au moins 3 participants. Cela limite les fausses '
        'alertes et renforce la fiabilité de l\'information.',
  ),
  TutorialEntry(
    category: TutorialCategory.alertes,
    feature: 'Expiration automatique',
    description:
        'Les alertes ont une durée de vie limitée. Une alerte non '
        'reconfirmée disparaît automatiquement de la carte pour que '
        'les informations restent actuelles.',
  ),

  // ── Configuration ──────────────────────────────────────────────────────────

  TutorialEntry(
    category: TutorialCategory.configuration,
    feature: 'Mode Économe',
    description:
        'Active un fonctionnement réduit pour préserver la batterie '
        'lors des longues journées. Les mises à jour sont moins fréquentes '
        'mais l\'essentiel reste opérationnel.',
  ),
  TutorialEntry(
    category: TutorialCategory.configuration,
    feature: 'Filtres d\'évitement',
    description:
        'Personnalisez les types de dangers que le moteur Route Safe '
        'doit impérativement contourner. Les autres types sont signalés '
        'mais l\'itinéraire peut les frôler si nécessaire.',
  ),
  TutorialEntry(
    category: TutorialCategory.configuration,
    feature: 'Alertes en arrière-plan',
    description:
        'Choisissez quelles notifications vous souhaitez recevoir quand '
        'l\'application est en fond : toutes les alertes, uniquement les '
        'dangers proches, ou uniquement les changements de parcours.',
  ),
];
