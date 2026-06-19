// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'StreetPhare';

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get mapTitle => 'Carte';

  @override
  String get eventsTitle => 'Événements';

  @override
  String get messagingTitle => 'Messagerie';

  @override
  String get startScreenWelcome => 'Bienvenue sur StreetPhare';

  @override
  String get startScreenSubtitle => 'Cartographie citoyenne collaborative et décentralisée';

  @override
  String get startScreenSelectLanguage => 'Choisissez votre langue';

  @override
  String get startScreenButton => 'Commencer';

  @override
  String get languageLabel => 'Français';

  @override
  String get languageSectionTitle => 'Choix de la langue';

  @override
  String get languageSectionDescription => 'Modifiez la langue de l\'application en temps réel.';

  @override
  String get themeSectionTitle => 'Thème de l\'application';

  @override
  String get themeDescription => 'Le mode sombre est optimisé pour les écrans OLED et reste discret la nuit.';

  @override
  String get themeSystem => 'Système';

  @override
  String get themeSystemSubtitle => 'Suit le réglage du système';

  @override
  String get themeLight => 'Clair';

  @override
  String get themeLightSubtitle => 'Fond clair, lecture diurne';

  @override
  String get themeDark => 'Sombre';

  @override
  String get themeDarkSubtitle => 'Vrai noir OLED, économie de batterie';

  @override
  String get batterySaverTitle => 'Mode Économe';

  @override
  String get batterySaverDescription => 'Réduit la fréquence des scans GPS/BLE et prolonge l\'autonomie.';

  @override
  String get batterySaverSubtitle => 'Réduit la fréquence GPS et BLE pour économiser la batterie';

  @override
  String get batterySaverEnabledLabel => 'Mode Économe activé';

  @override
  String get batterySaverDisabledLabel => 'Mode Économe désactivé';

  @override
  String get batterySaverStatusEnabled => 'Scans réduits, carte suspendue';

  @override
  String get batterySaverStatusDisabled => 'Fonctionnement normal';

  @override
  String get backgroundAlertsTitle => 'Alertes en arrière-plan';

  @override
  String get notificationFilterTitle => 'Filtre de notifications';

  @override
  String get notificationFilterAllLabel => 'Toutes les alertes';

  @override
  String get notificationFilterAllDescription => 'Notifie chaque micro-événement du réseau';

  @override
  String get notificationFilterNearbyLabel => 'Dangers proches confirmés uniquement';

  @override
  String get notificationFilterNearbyDescription => 'Filtre : danger ≥3 votes détecté à moins de 100 m';

  @override
  String get notificationFilterEventsLabel => 'Changements de points imminents';

  @override
  String get notificationFilterEventsDescription => 'Notifie si le prochain point est révélé dans <3 min';

  @override
  String get lowVisionTitle => 'Mode Malvoyant';

  @override
  String get lowVisionSubtitle => 'Grand texte et interface adaptée pour une meilleure lisibilité';

  @override
  String get lowVisionDescription => 'Active de très grands caractères, supprime le titre StreetPhare sur la carte et réorganise le menu de signalement en 2 colonnes (grands boutons tactiles). Activé automatiquement si TalkBack/VoiceOver est détecté.';

  @override
  String get lowVisionEnabled => 'Mode Malvoyant activé';

  @override
  String get lowVisionDisabled => 'Mode Malvoyant désactivé';

  @override
  String get lowVisionStatusEnabled => 'Grands caractères, 2 colonnes signalement';

  @override
  String get lowVisionStatusDisabled => 'Interface standard';

  @override
  String get messageFilterTitle => 'Filtre des messages';

  @override
  String get messageFilterDescription => 'Filtrez les messages reçus sur le réseau décentralisé.';

  @override
  String get messageFilterAllLabel => 'Tous les messages';

  @override
  String get messageFilterAllDescription => 'Reçoit tous les messages diffusés sur le réseau';

  @override
  String get messageFilterNearbyLabel => 'Messages proches uniquement';

  @override
  String get messageFilterNearbyDescription => 'Messages émis dans un rayon de 300 m';

  @override
  String get messageFilterAdminLabel => 'Administrateurs de l\'événement';

  @override
  String get messageFilterAdminDescription => 'Messages signés par un administrateur de l\'événement';

  @override
  String get messageFilterAlertLabel => 'Messages d\'alerte uniquement';

  @override
  String get messageFilterAlertDescription => 'Uniquement les alertes critiques (type ALERT)';

  @override
  String get avoidanceFiltersTitle => 'Filtres d\'évitement (Route Safe)';

  @override
  String get avoidanceFiltersDescription => 'Cochez les types de dangers à éviter absolument. Le moteur de routage contournera ces zones.';

  @override
  String get avoidBarragesTitle => 'Éviter les barrages';

  @override
  String get avoidBarragesSubtitle => 'Barrages filtrants ou durs';

  @override
  String get avoidNassesTitle => 'Éviter les nasses';

  @override
  String get avoidNassesSubtitle => 'Pièges, zones encerclées';

  @override
  String get avoidControlesTitle => 'Éviter les contrôles de police';

  @override
  String get avoidControlesSubtitle => 'Filtrages, contrôles d\'identité';

  @override
  String get avoidAccidentsTitle => 'Éviter les accidents / autopompes';

  @override
  String get avoidAccidentsSubtitle => 'Camions de pompiers, zones accidentées';

  @override
  String get avoidRassemblementsTitle => 'Éviter les rassemblements à risque';

  @override
  String get avoidRassemblementsSubtitle => 'Zones de rassemblement public à risque';

  @override
  String get avoidAutresTitle => 'Éviter les dangers « autres »';

  @override
  String get avoidAutresSubtitle => 'Tout autre signalement non catégorisé';

  @override
  String get routeDestinationSection => 'Type de destination';

  @override
  String get routeDestEventPointLabel => 'Suivre le point d\'événement actuel';

  @override
  String get routeDestEventPointDescription => 'Destination par défaut de l\'événement actif';

  @override
  String get routeDestSafeZoneLabel => 'Vers la Zone Safe / Centre de soins le plus proche';

  @override
  String get routeDestSafeZoneDescription => '⭐ Priorité absolue : zone de sécurité ou médecin de rue le plus proche';

  @override
  String get routeDestCareCenterLabel => 'Centre de soins le plus proche';

  @override
  String get routeDestCareCenterDescription => 'Street-medics ou secours de rue les plus proches';

  @override
  String get routeDestExitPointLabel => 'Point de sortie le plus proche';

  @override
  String get routeDestExitPointDescription => 'Zone d\'évacuation définie dans le JSON de l\'événement';

  @override
  String get routeDestUserPointLabel => 'Point utilisateur';

  @override
  String get routeDestUserPointDescription => 'Point personnalisé placé manuellement (appui long 3s)';

  @override
  String get mapCacheTitle => 'Cache des tuiles cartographiques';

  @override
  String get mapCacheSubtitle => 'Durée maximale de rétention du cache local';

  @override
  String get mapCacheDescription => 'Les tuiles de la carte sont conservées localement pour économiser les données mobiles.';

  @override
  String get mapCacheRetentionLabel => 'Durée de rétention : ';

  @override
  String get mapCacheForceUpdate => 'Forcer la mise à jour des cartes';

  @override
  String get mapCacheCleaned => 'Cache des cartes effacé. Les tuiles seront rechargées au prochain affichage.';

  @override
  String get mapCacheDays => 'jours';

  @override
  String get backgroundServiceTitle => 'Service arrière-plan';

  @override
  String get backgroundServiceSubtitle => 'Notification persistante « StreetPhare actif »';

  @override
  String get backgroundServiceDescription => 'Permet à StreetPhare d\'envoyer des alertes même quand l\'application est en tâche de fond ou en veille.';

  @override
  String get backgroundServiceEnable => 'Activer la surveillance';

  @override
  String get panicContactsTitle => 'Contacts d\'urgence (Panic)';

  @override
  String get panicContactsDescription => 'Ces contacts recevront un SMS d\'alerte avec votre position GPS quand vous appuierez sur PANIC.';

  @override
  String get panicContactsAdd => 'Ajouter un contact';

  @override
  String get panicContactsEmpty => 'Aucun contact d\'urgence enregistré';

  @override
  String get panicContactsConfigError => 'Aucun contact configuré.\nAjoutez au moins un contact pour le bouton PANIC.';

  @override
  String get panicContactsDeleteTitle => 'Supprimer ce contact ?';

  @override
  String get panicContactsDeleteMessage => 'Sera retiré de la liste.';

  @override
  String get panicContactsEditTitle => 'Modifier le contact';

  @override
  String get panicContactsNewTitle => 'Nouveau contact';

  @override
  String get panicContactsFieldName => 'Nom';

  @override
  String get panicContactsFieldPhone => 'Téléphone';

  @override
  String get panicContactsNameHint => 'Ex. Maman, Samu 112';

  @override
  String get panicContactsPhoneHint => '+32 4 XX XX XX XX';

  @override
  String get panicContactsNameRequired => 'Nom requis';

  @override
  String get panicContactsPhoneRequired => 'Numéro requis';

  @override
  String get panicContactsPhoneTooShort => 'Numéro trop court';

  @override
  String get tutorialTitle => 'Guide de l\'application';

  @override
  String get tutorialButton => 'Voir le tutoriel';

  @override
  String get tutorialDescription => 'Consultez les fonctionnalités de StreetPhare à tout moment.';

  @override
  String get aboutTitle => 'À propos';

  @override
  String get aboutApp => 'À propos de StreetPhare';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutPlatform => 'Plateforme';

  @override
  String get aboutLicense => 'Licence';

  @override
  String get aboutEncryption => 'Chiffrement';

  @override
  String get aboutOpenSource => 'Projet open-source citoyen';

  @override
  String get aboutDescription => 'StreetPhare est une application de cartographie collaborative décentralisée conçue pour renforcer la sécurité collective lors de rassemblements citoyens. Aucune donnée personnelle n\'est collectée ni transmise à des tiers. Toutes les données restent locales ou transitent via des relais pair-à-pair chiffrés.';

  @override
  String get bugReportTitle => 'Signalement de bugs';

  @override
  String get bugReportButton => 'Signaler un bug';

  @override
  String get bugReportSuggest => 'Suggérer';

  @override
  String get bugReportDescription => '💡 Ce formulaire envoie un rapport technique au serveur d\'administration de StreetPhare. Les rapports aident les développeurs à identifier et corriger les problèmes rapidement.';

  @override
  String get bugReportPrivacy => '🔒 Aucune donnée personnelle n\'est transmise. Seuls le titre, la description, la catégorie et la version de l\'application sont envoyés.';

  @override
  String get bugReportSectionTitle => 'Signalement de bugs & Suggestions';

  @override
  String get bugReportSectionDescription => 'Bouton Bug (en haut à droite de la carte) : signalez un bug ou une suggestion directement depuis l\'interface principale sans quitter la carte.';

  @override
  String get eventsJoin => 'Rejoindre un événement';

  @override
  String get eventsNoEvent => 'Aucun événement actif pour le moment';

  @override
  String get eventsQrScan => 'Scanner un QR Code';

  @override
  String get qrScanTitle => 'Scanner un QR Code';

  @override
  String get searchTitle => 'Rechercher';

  @override
  String get searchHint => 'Rechercher un lieu, un événement…';

  @override
  String get searchNoResult => 'Aucun résultat trouvé';

  @override
  String get routeTitle => 'Itinéraire';

  @override
  String get routeCalculate => 'Calculer l\'itinéraire';

  @override
  String get routeDestination => 'Destination';

  @override
  String get routeAvoidLiked => 'Éviter les zones signalées dangereuses';

  @override
  String get routeAvoidPolice => 'Éviter les zones de contrôle';

  @override
  String get routeAvoidCamera => 'Éviter les zones sous surveillance';

  @override
  String get splashInitializing => 'Initialisation…';

  @override
  String get splashCheckingVersion => 'Vérification de la version…';

  @override
  String get splashCheckingCache => 'Vérification du cache local…';

  @override
  String get splashPurgingCache => 'Cache expiré, purge en cours…';

  @override
  String get splashLoadingMap => 'Chargement de la carte locale…';

  @override
  String get splashCachingTiles => 'Mise en cache des tuiles…';

  @override
  String get splashReady => 'Prêt !';

  @override
  String get splashError => 'Erreur :';

  @override
  String get splashSubtitle => 'Cartographie citoyenne en temps réel';

  @override
  String get splashCheckingConnectivity => 'Vérification de la connectivité…';

  @override
  String get panicButton => 'PANIC';

  @override
  String get panicAlertSent => 'Alerte PANIC envoyée';

  @override
  String get onlineStatus => 'En ligne';

  @override
  String get offlineStatus => 'Hors ligne';

  @override
  String get meshStatus => 'Maillage';

  @override
  String get relayStatus => 'Relais';

  @override
  String get connectedPeers => 'Pairs connectés';

  @override
  String get proximityValidationTitle => 'Validation de proximité';

  @override
  String get proximityValidationCheck => 'Vérifier la proximité';

  @override
  String get proximityValid => 'Proximité validée';

  @override
  String get proximityInvalid => 'Proximité invalide';

  @override
  String get geofenceEntered => 'Zone d\'événement entrée';

  @override
  String get geofenceExited => 'Zone d\'événement quittée';

  @override
  String get dangerReported => 'Danger signalé';

  @override
  String get dangerConfirmed => 'Danger confirmé (≥3 votes)';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Annuler';

  @override
  String get save => 'Enregistrer';

  @override
  String get delete => 'Supprimer';

  @override
  String get confirm => 'Confirmer';

  @override
  String get close => 'Fermer';

  @override
  String get back => 'Retour';

  @override
  String get next => 'Suivant';

  @override
  String get done => 'Terminé';

  @override
  String get errorGeneric => 'Une erreur est survenue';

  @override
  String get loading => 'Chargement…';

  @override
  String get retry => 'Réessayer';

  @override
  String get noInternet => 'Pas de connexion Internet';

  @override
  String get locationAccessTitle => 'Accès à la position';

  @override
  String get locationAccessMessage => 'StreetPhare a besoin d\'accéder à votre position pour afficher la carte et les alertes à proximité.';

  @override
  String get locationAccessButton => 'Autoriser';

  @override
  String get notificationPermissionTitle => 'Notifications';

  @override
  String get notificationPermissionMessage => 'StreetPhare a besoin d\'envoyer des notifications pour les alertes et les événements.';

  @override
  String get notificationPermissionButton => 'Autoriser';

  @override
  String get androidChannelAlertsTitle => 'Alertes terrain';

  @override
  String get androidChannelAlertsSubtitle => 'Barrages, nasses, zones de tension';

  @override
  String get androidChannelEventsTitle => 'Événements & Trajets';

  @override
  String get androidChannelEventsSubtitle => 'Début de trajet, waypoints, fin de manif';

  @override
  String get androidChannelPanicTitle => 'Alertes Panic collectives';

  @override
  String get androidChannelPanicSubtitle => 'Déclenchement panic multi-appareils';

  @override
  String get androidChannelMessagesTitle => 'Messages Hive P2P';

  @override
  String get androidChannelMessagesSubtitle => 'Nouveaux messages sur le réseau local';

  @override
  String get androidChannelSectionTitle => 'Notifications Android par canal';

  @override
  String get androidChannelManageSystem => 'Gérer dans les Paramètres Android';
}
