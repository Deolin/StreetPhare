// lib/core/i18n/strings.dart
//
// Fichier centralisé de toutes les chaînes de caractères de l'application.
// Support multilingue : Français (FR), English (EN), Nederlands (NL), Deutsch (DE).

/// Regroupe toutes les traductions par écran / fonctionnalité.
class AppStrings {
  // ==========================================================================
  // Constructeur privé — utiliser les factories FR, EN, NL, DE
  // ==========================================================================
  const AppStrings._({
    required this.appTitle,
    required this.settingsTitle,
    required this.mapTitle,
    required this.eventsTitle,
    required this.messagingTitle,
    required this.startScreenWelcome,
    required this.startScreenSubtitle,
    required this.startScreenSelectLanguage,
    required this.startScreenButton,
    required this.languageLabel,
    required this.languageSectionTitle,
    required this.languageSectionDescription,
    required this.themeSectionTitle,
    required this.themeDescription,
    required this.themeSystem,
    required this.themeSystemSubtitle,
    required this.themeLight,
    required this.themeLightSubtitle,
    required this.themeDark,
    required this.themeDarkSubtitle,
    required this.batterySaverTitle,
    required this.batterySaverDescription,
    required this.batterySaverSubtitle,
    required this.batterySaverEnabledLabel,
    required this.batterySaverDisabledLabel,
    required this.batterySaverStatusEnabled,
    required this.batterySaverStatusDisabled,
    required this.backgroundAlertsTitle,
    required this.notificationFilterTitle,
    required this.notificationFilterAllLabel,
    required this.notificationFilterAllDescription,
    required this.notificationFilterNearbyLabel,
    required this.notificationFilterNearbyDescription,
    required this.notificationFilterEventsLabel,
    required this.notificationFilterEventsDescription,
    required this.lowVisionTitle,
    required this.lowVisionSubtitle,
    required this.lowVisionDescription,
    required this.lowVisionEnabled,
    required this.lowVisionDisabled,
    required this.lowVisionStatusEnabled,
    required this.lowVisionStatusDisabled,
    required this.messageFilterTitle,
    required this.messageFilterDescription,
    required this.messageFilterAllLabel,
    required this.messageFilterAllDescription,
    required this.messageFilterNearbyLabel,
    required this.messageFilterNearbyDescription,
    required this.messageFilterAdminLabel,
    required this.messageFilterAdminDescription,
    required this.messageFilterAlertLabel,
    required this.messageFilterAlertDescription,
    required this.avoidanceFiltersTitle,
    required this.avoidanceFiltersDescription,
    required this.avoidBarragesTitle,
    required this.avoidBarragesSubtitle,
    required this.avoidNassesTitle,
    required this.avoidNassesSubtitle,
    required this.avoidControlesTitle,
    required this.avoidControlesSubtitle,
    required this.avoidAccidentsTitle,
    required this.avoidAccidentsSubtitle,
    required this.avoidRassemblementsTitle,
    required this.avoidRassemblementsSubtitle,
    required this.avoidAutresTitle,
    required this.avoidAutresSubtitle,
    required this.routeDestinationSection,
    required this.routeDestEventPointLabel,
    required this.routeDestEventPointDescription,
    required this.routeDestSafeZoneLabel,
    required this.routeDestSafeZoneDescription,
    required this.routeDestCareCenterLabel,
    required this.routeDestCareCenterDescription,
    required this.routeDestExitPointLabel,
    required this.routeDestExitPointDescription,
    required this.routeDestUserPointLabel,
    required this.routeDestUserPointDescription,
    required this.mapCacheTitle,
    required this.mapCacheSubtitle,
    required this.mapCacheDescription,
    required this.mapCacheRetentionLabel,
    required this.mapCacheForceUpdate,
    required this.mapCacheCleaned,
    required this.mapCacheDays,
    required this.backgroundServiceTitle,
    required this.backgroundServiceSubtitle,
    required this.backgroundServiceDescription,
    required this.backgroundServiceEnable,
    required this.panicContactsTitle,
    required this.panicContactsDescription,
    required this.panicContactsAdd,
    required this.panicContactsEmpty,
    required this.panicContactsConfigError,
    required this.panicContactsDeleteTitle,
    required this.panicContactsDeleteMessage,
    required this.panicContactsEditTitle,
    required this.panicContactsNewTitle,
    required this.panicContactsFieldName,
    required this.panicContactsFieldPhone,
    required this.panicContactsNameHint,
    required this.panicContactsPhoneHint,
    required this.panicContactsNameRequired,
    required this.panicContactsPhoneRequired,
    required this.panicContactsPhoneTooShort,
    required this.tutorialTitle,
    required this.tutorialButton,
    required this.tutorialDescription,
    required this.aboutTitle,
    required this.aboutApp,
    required this.aboutVersion,
    required this.aboutPlatform,
    required this.aboutLicense,
    required this.aboutEncryption,
    required this.aboutOpenSource,
    required this.aboutDescription,
    required this.bugReportTitle,
    required this.bugReportButton,
    required this.bugReportSuggest,
    required this.bugReportDescription,
    required this.bugReportPrivacy,
    required this.bugReportSectionTitle,
    required this.bugReportSectionDescription,
    required this.eventsJoin,
    required this.eventsNoEvent,
    required this.eventsQrScan,
    required this.qrScanTitle,
    required this.eventsMyEvents,
    required this.eventsEmptyTitle,
    required this.eventsEmptySubtitle,
    required this.eventsJoinTitle,
    required this.eventsJoinSubtitle,
    required this.eventsSecurityTitle,
    required this.eventsSecurityDescription,
    required this.eventsEnterCodeError,
    required this.eventsMaxReachedError,
    required this.eventsUnknownCodeError,
    required this.eventsFleurusCodes,
    required this.eventsQrMaxReached,
    required this.eventsQrAddError,
    required this.eventsQrAddSuccess,
    required this.eventsRemoved,
    required this.eventsLoadButton,
    required this.eventsRemoveTooltip,
    required this.eventsCodeLabel,
    required this.eventsStartLabel,
    required this.eventsRouteHidden,
    required this.eventsStepActive,
    required this.eventsStepTime,
    required this.eventsRouteVisible,
    required this.mapRecenterTooltip,
    required this.mapLoadingTiles,
    required this.mapGpsOff,
    required this.mapGpsDenied,
    required this.mapGpsDeniedForever,
    required this.mapGpsError,
    required this.mapUserPointDefined,
    required this.mapDestinationEvent,
    required this.mapDestinationSafeZone,
    required this.mapDestinationCareCenter,
    required this.mapDestinationExit,
    required this.mapDestinationUserPoint,
    required this.mapRouteSafeCalculating,
    required this.mapRouteSafeFailover,
    required this.mapNoDestinationError,
    required this.mapAddEventButton,
    required this.mapAddEventWarning,
    required this.mapCollectivePanicTitle,
    required this.mapCollectivePanicMessage,
    required this.mapViewOnMap,
    required this.mapIgnore,
    required this.mapNoPanicContactTitle,
    required this.mapNoPanicContactMessage,
    required this.mapOpenSettings,
    required this.mapPanicModeTitle,
    required this.mapPanicModeMessage,
    required this.mapPanicModeActivate,
    required this.mapPanicSmsPreparedTitle,
    required this.mapPanicSmsPreparedMessage,
    required this.mapPanicAlertReadyTitle,
    required this.mapPanicAlertReadyMessage,
    required this.mapPanicMessageBody,
    required this.mapPanicNoGps,
    required this.mapDestinationObjective,
    required this.mapDestinationLongPressHint,
    required this.mapActiveEvent,
    required this.mapPeersNearby,
    required this.mapIsolatedTitle,
    required this.mapIsolatedMessage,
    required this.routeTitle,
    required this.routeCalculate,
    required this.routeDestination,
    required this.routeAvoidLiked,
    required this.routeAvoidPolice,
    required this.routeAvoidCamera,
    required this.routeAlternativesError,
    required this.routeNotFound,
    required this.routeRecommended,
    required this.routeShowAlternatives,
    required this.routeCalculatingAlternatives,
    required this.routeOpenInOsmAnd,
    required this.routeAccept,
    required this.routeItinerary,
    required this.routeRisk,
    required this.routeOsmAndSuccess,
    required this.routeOsmAndError,
    required this.searchTitle,
    required this.searchHint,
    required this.searchNoResult,
    required this.splashInitializing,
    required this.splashCheckingVersion,
    required this.splashCheckingCache,
    required this.splashPurgingCache,
    required this.splashLoadingMap,
    required this.splashCachingTiles,
    required this.splashReady,
    required this.splashError,
    required this.splashSubtitle,
    required this.splashCheckingConnectivity,
    required this.panicButton,
    required this.panicAlertSent,
    required this.onlineStatus,
    required this.offlineStatus,
    required this.meshStatus,
    required this.relayStatus,
    required this.blockedUsersTitle,
    required this.blockedUsersDescription,
    required this.blockedUsersEmpty,
    required this.blockedUsersUnblock,
    required this.blockedUsersCount,
    required this.connectedPeers,
    required this.proximityValidationTitle,
    required this.proximityValidationCheck,
    required this.proximityValid,
    required this.proximityInvalid,
    required this.geofenceEntered,
    required this.geofenceExited,
    required this.dangerReported,
    required this.dangerConfirmed,
    required this.ok,
    required this.cancel,
    required this.save,
    required this.delete,
    required this.confirm,
    required this.close,
    required this.back,
    required this.next,
    required this.done,
    required this.errorGeneric,
    required this.loading,
    required this.retry,
    required this.noInternet,
    required this.locationAccessTitle,
    required this.locationAccessMessage,
    required this.locationAccessButton,
    required this.notificationPermissionTitle,
    required this.notificationPermissionMessage,
    required this.notificationPermissionButton,
    required this.androidChannelAlertsTitle,
    required this.androidChannelAlertsSubtitle,
    required this.androidChannelEventsTitle,
    required this.androidChannelEventsSubtitle,
    required this.androidChannelPanicTitle,
    required this.androidChannelPanicSubtitle,
    required this.androidChannelMessagesTitle,
    required this.androidChannelMessagesSubtitle,
    required this.androidChannelSectionTitle,
    required this.androidChannelManageSystem,
    required this.transportModePedestrian,
    required this.transportModeCar,
    required this.transportModeTransit,
  });

  // Général
  final String appTitle;
  final String settingsTitle;
  final String mapTitle;
  final String eventsTitle;
  final String messagingTitle;

  // Start Screen
  final String startScreenWelcome;
  final String startScreenSubtitle;
  final String startScreenSelectLanguage;
  final String startScreenButton;

  // Langue
  final String languageLabel;
  final String languageSectionTitle;
  final String languageSectionDescription;

  // Thème
  final String themeSectionTitle;
  final String themeDescription;
  final String themeSystem;
  final String themeSystemSubtitle;
  final String themeLight;
  final String themeLightSubtitle;
  final String themeDark;
  final String themeDarkSubtitle;

  // Batterie / Notifications
  final String batterySaverTitle;
  final String batterySaverDescription;
  final String batterySaverSubtitle;
  final String batterySaverEnabledLabel;
  final String batterySaverDisabledLabel;
  final String batterySaverStatusEnabled;
  final String batterySaverStatusDisabled;
  final String backgroundAlertsTitle;
  final String notificationFilterTitle;
  final String notificationFilterAllLabel;
  final String notificationFilterAllDescription;
  final String notificationFilterNearbyLabel;
  final String notificationFilterNearbyDescription;
  final String notificationFilterEventsLabel;
  final String notificationFilterEventsDescription;

  // Accessibilité
  final String lowVisionTitle;
  final String lowVisionSubtitle;
  final String lowVisionDescription;
  final String lowVisionEnabled;
  final String lowVisionDisabled;
  final String lowVisionStatusEnabled;
  final String lowVisionStatusDisabled;

  // Messagerie
  final String messageFilterTitle;
  final String messageFilterDescription;
  final String messageFilterAllLabel;
  final String messageFilterAllDescription;
  final String messageFilterNearbyLabel;
  final String messageFilterNearbyDescription;
  final String messageFilterAdminLabel;
  final String messageFilterAdminDescription;
  final String messageFilterAlertLabel;
  final String messageFilterAlertDescription;

  // Route Safe
  final String avoidanceFiltersTitle;
  final String avoidanceFiltersDescription;
  final String avoidBarragesTitle;
  final String avoidBarragesSubtitle;
  final String avoidNassesTitle;
  final String avoidNassesSubtitle;
  final String avoidControlesTitle;
  final String avoidControlesSubtitle;
  final String avoidAccidentsTitle;
  final String avoidAccidentsSubtitle;
  final String avoidRassemblementsTitle;
  final String avoidRassemblementsSubtitle;
  final String avoidAutresTitle;
  final String avoidAutresSubtitle;
  final String routeDestinationSection;
  final String routeDestEventPointLabel;
  final String routeDestEventPointDescription;
  final String routeDestSafeZoneLabel;
  final String routeDestSafeZoneDescription;
  final String routeDestCareCenterLabel;
  final String routeDestCareCenterDescription;
  final String routeDestExitPointLabel;
  final String routeDestExitPointDescription;
  final String routeDestUserPointLabel;
  final String routeDestUserPointDescription;

  // Cache cartes
  final String mapCacheTitle;
  final String mapCacheSubtitle;
  final String mapCacheDescription;
  final String mapCacheRetentionLabel;
  final String mapCacheForceUpdate;
  final String mapCacheCleaned;
  final String mapCacheDays;

  // Service arrière-plan
  final String backgroundServiceTitle;
  final String backgroundServiceSubtitle;
  final String backgroundServiceDescription;
  final String backgroundServiceEnable;

  // Contacts Panic
  final String panicContactsTitle;
  final String panicContactsDescription;
  final String panicContactsAdd;
  final String panicContactsEmpty;
  final String panicContactsConfigError;
  final String panicContactsDeleteTitle;
  final String panicContactsDeleteMessage;
  final String panicContactsEditTitle;
  final String panicContactsNewTitle;
  final String panicContactsFieldName;
  final String panicContactsFieldPhone;
  final String panicContactsNameHint;
  final String panicContactsPhoneHint;
  final String panicContactsNameRequired;
  final String panicContactsPhoneRequired;
  final String panicContactsPhoneTooShort;

  // Tutoriel
  final String tutorialTitle;
  final String tutorialButton;
  final String tutorialDescription;

  // À propos
  final String aboutTitle;
  final String aboutApp;
  final String aboutVersion;
  final String aboutPlatform;
  final String aboutLicense;
  final String aboutEncryption;
  final String aboutOpenSource;
  final String aboutDescription;

  // Bug report
  final String bugReportTitle;
  final String bugReportButton;
  final String bugReportSuggest;
  final String bugReportDescription;
  final String bugReportPrivacy;
  final String bugReportSectionTitle;
  final String bugReportSectionDescription;

  // Événements
  final String eventsJoin;
  final String eventsNoEvent;
  final String eventsQrScan;
  final String qrScanTitle;
  final String eventsMyEvents;
  final String eventsEmptyTitle;
  final String eventsEmptySubtitle;
  final String eventsJoinTitle;
  final String eventsJoinSubtitle;
  final String eventsSecurityTitle;
  final String eventsSecurityDescription;
  final String eventsEnterCodeError;
  final String eventsMaxReachedError;
  final String eventsUnknownCodeError;
  final String eventsFleurusCodes;
  final String eventsQrMaxReached;
  final String eventsQrAddError;
  final String eventsQrAddSuccess;
  final String eventsRemoved;
  final String eventsLoadButton;
  final String eventsRemoveTooltip;
  final String eventsCodeLabel;
  final String eventsStartLabel;
  final String eventsRouteHidden;
  final String eventsStepActive;
  final String eventsStepTime;
  final String eventsRouteVisible;

  // Map
  final String mapRecenterTooltip;
  final String mapLoadingTiles;
  final String mapGpsOff;
  final String mapGpsDenied;
  final String mapGpsDeniedForever;
  final String mapGpsError;
  final String mapUserPointDefined;
  final String mapDestinationEvent;
  final String mapDestinationSafeZone;
  final String mapDestinationCareCenter;
  final String mapDestinationExit;
  final String mapDestinationUserPoint;
  final String mapRouteSafeCalculating;
  final String mapRouteSafeFailover;
  final String mapNoDestinationError;
  final String mapAddEventButton;
  final String mapAddEventWarning;
  final String mapCollectivePanicTitle;
  final String mapCollectivePanicMessage;
  final String mapViewOnMap;
  final String mapIgnore;
  final String mapNoPanicContactTitle;
  final String mapNoPanicContactMessage;
  final String mapOpenSettings;
  final String mapPanicModeTitle;
  final String mapPanicModeMessage;
  final String mapPanicModeActivate;
  final String mapPanicSmsPreparedTitle;
  final String mapPanicSmsPreparedMessage;
  final String mapPanicAlertReadyTitle;
  final String mapPanicAlertReadyMessage;
  final String mapPanicMessageBody;
  final String mapPanicNoGps;
  final String mapDestinationObjective;
  final String mapDestinationLongPressHint;
  final String mapActiveEvent;
  final String mapPeersNearby;
  final String mapIsolatedTitle;
  final String mapIsolatedMessage;

  // Safe Route Result Sheet
  final String routeTitle;
  final String routeCalculate;
  final String routeDestination;
  final String routeAvoidLiked;
  final String routeAvoidPolice;
  final String routeAvoidCamera;
  final String routeAlternativesError;
  final String routeNotFound;
  final String routeRecommended;
  final String routeShowAlternatives;
  final String routeCalculatingAlternatives;
  final String routeOpenInOsmAnd;
  final String routeAccept;
  final String routeItinerary;
  final String routeRisk;
  final String routeOsmAndSuccess;
  final String routeOsmAndError;

  // Recherche
  final String searchTitle;
  final String searchHint;
  final String searchNoResult;

  // Splash
  final String splashInitializing;
  final String splashCheckingVersion;
  final String splashCheckingCache;
  final String splashPurgingCache;
  final String splashLoadingMap;
  final String splashCachingTiles;
  final String splashReady;
  final String splashError;
  final String splashSubtitle;
  final String splashCheckingConnectivity;

  // Panic
  final String panicButton;
  final String panicAlertSent;

  // Blocage utilisateurs
  final String blockedUsersTitle;
  final String blockedUsersDescription;
  final String blockedUsersEmpty;
  final String blockedUsersUnblock;
  final String blockedUsersCount;

  // Réseau
  final String onlineStatus;
  final String offlineStatus;
  final String meshStatus;
  final String relayStatus;
  final String connectedPeers;

  // Géofencing
  final String proximityValidationTitle;
  final String proximityValidationCheck;
  final String proximityValid;
  final String proximityInvalid;
  final String geofenceEntered;
  final String geofenceExited;
  final String dangerReported;
  final String dangerConfirmed;

  // Boutons communs
  final String ok;
  final String cancel;
  final String save;
  final String delete;
  final String confirm;
  final String close;
  final String back;
  final String next;
  final String done;

  // Erreurs / États
  final String errorGeneric;
  final String loading;
  final String retry;
  final String noInternet;

  // Permissions
  final String locationAccessTitle;
  final String locationAccessMessage;
  final String locationAccessButton;
  final String notificationPermissionTitle;
  final String notificationPermissionMessage;
  final String notificationPermissionButton;

  // Canaux Android Notifications
  final String androidChannelAlertsTitle;
  final String androidChannelAlertsSubtitle;
  final String androidChannelEventsTitle;
  final String androidChannelEventsSubtitle;
  final String androidChannelPanicTitle;
  final String androidChannelPanicSubtitle;
  final String androidChannelMessagesTitle;
  final String androidChannelMessagesSubtitle;
  final String androidChannelSectionTitle;
  final String androidChannelManageSystem;
  final String transportModePedestrian;
  final String transportModeCar;
  final String transportModeTransit;

  // ==========================================================================
  // Français (langue par défaut)
  // ==========================================================================
  factory AppStrings.fr() => const AppStrings._(
        appTitle: 'StreetPhare',
        settingsTitle: 'Paramètres',
        mapTitle: 'Carte',
        eventsTitle: 'Événements',
        messagingTitle: 'Messagerie',
        startScreenWelcome: 'Bienvenue sur StreetPhare',
        startScreenSubtitle:
            'Cartographie citoyenne collaborative et décentralisée',
        startScreenSelectLanguage: 'Choisissez votre langue',
        startScreenButton: 'Commencer',
        languageLabel: 'Français',
        languageSectionTitle: 'Choix de la langue',
        languageSectionDescription:
            'Modifiez la langue de l\'application en temps réel.',
        themeSectionTitle: 'Thème de l\'application',
        themeDescription:
            'Le mode sombre est optimisé pour les écrans OLED et reste discret la nuit.',
        themeSystem: 'Système',
        themeSystemSubtitle: 'Suit le réglage du système',
        themeLight: 'Clair',
        themeLightSubtitle: 'Fond clair, lecture diurne',
        themeDark: 'Sombre',
        themeDarkSubtitle: 'Vrai noir OLED, économie de batterie',
        batterySaverTitle: 'Mode Économe',
        batterySaverDescription:
            'Réduit la fréquence des scans GPS/BLE et prolonge l\'autonomie.',
        batterySaverSubtitle:
            'Réduit la fréquence GPS et BLE pour économiser la batterie',
        batterySaverEnabledLabel: 'Mode Économe activé',
        batterySaverDisabledLabel: 'Mode Économe désactivé',
        batterySaverStatusEnabled: 'Scans réduits, carte suspendue',
        batterySaverStatusDisabled: 'Fonctionnement normal',
        backgroundAlertsTitle: 'Alertes en arrière-plan',
        notificationFilterTitle: 'Filtre de notifications',
        notificationFilterAllLabel: 'Toutes les alertes',
        notificationFilterAllDescription:
            'Notifie chaque micro-événement du réseau',
        notificationFilterNearbyLabel: 'Dangers proches confirmés uniquement',
        notificationFilterNearbyDescription:
            'Filtre : danger ≥3 votes détecté à moins de 100 m',
        notificationFilterEventsLabel: 'Changements de points imminents',
        notificationFilterEventsDescription:
            'Notifie si le prochain point est révélé dans <3 min',
        lowVisionTitle: 'Mode Malvoyant',
        lowVisionSubtitle:
            'Grand texte et interface adaptée pour une meilleure lisibilité',
        lowVisionDescription:
            'Active de très grands caractères, supprime le titre StreetPhare sur la carte et réorganise le menu de signalement en 2 colonnes (grands boutons tactiles). Activé automatiquement si TalkBack/VoiceOver est détecté.',
        lowVisionEnabled: 'Mode Malvoyant activé',
        lowVisionDisabled: 'Mode Malvoyant désactivé',
        lowVisionStatusEnabled: 'Grands caractères, 2 colonnes signalement',
        lowVisionStatusDisabled: 'Interface standard',
        messageFilterTitle: 'Filtre des messages',
        messageFilterDescription:
            'Filtrez les messages reçus sur le réseau décentralisé.',
        messageFilterAllLabel: 'Tous les messages',
        messageFilterAllDescription:
            'Reçoit tous les messages diffusés sur le réseau',
        messageFilterNearbyLabel: 'Messages proches uniquement',
        messageFilterNearbyDescription: 'Messages émis dans un rayon de 300 m',
        messageFilterAdminLabel: 'Administrateurs de l\'événement',
        messageFilterAdminDescription:
            'Messages signés par un administrateur de l\'événement',
        messageFilterAlertLabel: 'Messages d\'alerte uniquement',
        messageFilterAlertDescription:
            'Uniquement les alertes critiques (type ALERT)',
        avoidanceFiltersTitle: 'Filtres d\'évitement (Route Safe)',
        avoidanceFiltersDescription:
            'Cochez les types de dangers à éviter absolument. Le moteur de routage contournera ces zones.',
        avoidBarragesTitle: 'Éviter les barrages',
        avoidBarragesSubtitle: 'Barrages filtrants ou durs',
        avoidNassesTitle: 'Éviter les nasses',
        avoidNassesSubtitle: 'Pièges, zones encerclées',
        avoidControlesTitle: 'Éviter les contrôles de police',
        avoidControlesSubtitle: 'Filtrages, contrôles d\'identité',
        avoidAccidentsTitle: 'Éviter les accidents / autopompes',
        avoidAccidentsSubtitle: 'Camions de pompiers, zones accidentées',
        avoidRassemblementsTitle: 'Éviter les rassemblements à risque',
        avoidRassemblementsSubtitle: 'Zones de rassemblement public à risque',
        avoidAutresTitle: 'Éviter les dangers "autres"',
        avoidAutresSubtitle: 'Tout autre signalement non catégorisé',
        routeDestinationSection: 'Type de destination',
        routeDestEventPointLabel: 'Suivre le point d\'événement actuel',
        routeDestEventPointDescription:
            'Destination par défaut de l\'événement actif',
        routeDestSafeZoneLabel: 'Vers zone safe',
        routeDestSafeZoneDescription:
            '⭐ Priorité absolue : zone de sécurité ou médecin de rue le plus proche',
        routeDestCareCenterLabel: 'Centre de soins le plus proche',
        routeDestCareCenterDescription:
            'Street-medics ou secours de rue les plus proches',
        routeDestExitPointLabel: 'Point de sortie le plus proche',
        routeDestExitPointDescription:
            'Zone d\'évacuation définie dans le JSON de l\'événement',
        routeDestUserPointLabel: 'Point utilisateur',
        routeDestUserPointDescription:
            'Point personnalisé placé manuellement (appui long 3s)',
        mapCacheTitle: 'Cache des tuiles cartographiques',
        mapCacheSubtitle: 'Durée maximale de rétention du cache local',
        mapCacheDescription:
            'Les tuiles de la carte sont conservées localement pour économiser les données mobiles.',
        mapCacheRetentionLabel: 'Durée de rétention : ',
        mapCacheForceUpdate: 'Forcer la mise à jour des cartes',
        mapCacheCleaned:
            'Cache des cartes effacé. Les tuiles seront rechargées au prochain affichage.',
        mapCacheDays: 'jours',
        backgroundServiceTitle: 'Service arrière-plan',
        backgroundServiceSubtitle:
            'Notification persistante « StreetPhare actif »',
        backgroundServiceDescription:
            'Permet à StreetPhare d\'envoyer des alertes même quand l\'application est en tâche de fond ou en veille.',
        backgroundServiceEnable: 'Activer la surveillance',
        panicContactsTitle: 'Contacts d\'urgence (Panic)',
        panicContactsDescription:
            'Ces contacts recevront un SMS d\'alerte avec votre position GPS quand vous appuierez sur PANIC.',
        panicContactsAdd: 'Ajouter un contact',
        panicContactsEmpty: 'Aucun contact d\'urgence enregistré',
        panicContactsConfigError:
            'Aucun contact configuré.\nAjoutez au moins un contact pour le bouton PANIC.',
        panicContactsDeleteTitle: 'Supprimer ce contact ?',
        panicContactsDeleteMessage: 'Sera retiré de la liste.',
        panicContactsEditTitle: 'Modifier le contact',
        panicContactsNewTitle: 'Nouveau contact',
        panicContactsFieldName: 'Nom',
        panicContactsFieldPhone: 'Téléphone',
        panicContactsNameHint: 'Ex. Maman, Samu 112',
        panicContactsPhoneHint: '+32 4 XX XX XX XX',
        panicContactsNameRequired: 'Nom requis',
        panicContactsPhoneRequired: 'Numéro requis',
        panicContactsPhoneTooShort: 'Numéro trop court',
        tutorialTitle: 'Guide de l\'application',
        tutorialButton: 'Voir le tutoriel',
        tutorialDescription:
            'Consultez les fonctionnalités de StreetPhare à tout moment.',
        aboutTitle: 'À propos',
        aboutApp: 'À propos de StreetPhare',
        aboutVersion: 'Version',
        aboutPlatform: 'Plateforme',
        aboutLicense: 'Licence',
        aboutEncryption: 'Chiffrement',
        aboutOpenSource: 'Projet open-source citoyen',
        aboutDescription:
            'StreetPhare est une application de cartographie collaborative décentralisée conçue pour renforcer la sécurité collective lors de rassemblements citoyens. Aucune donnée personnelle n\'est collectée ni transmise à des tiers. Toutes les données restent locales ou transitent via des relais pair-à-pair chiffrés.',
        bugReportTitle: 'Signalement de bugs',
        bugReportButton: 'Signaler un bug',
        bugReportSuggest: 'Suggérer',
        bugReportDescription:
            '💡 Ce formulaire envoie un rapport technique au serveur d\'administration de StreetPhare. Les rapports aident les développeurs à identifier et corriger les problèmes rapidement.',
        bugReportPrivacy:
            '🔒 Aucune donnée personnelle n\'est transmise. Seuls le titre, la description, la catégorie et la version de l\'application sont envoyés.',
        bugReportSectionTitle: 'Signalement de bugs & Suggestions',
        bugReportSectionDescription:
            'Bouton Bug (en haut à droite de la carte) : signalez un bug ou une suggestion directement depuis l\'interface principale sans quitter la carte.',
        eventsJoin: 'Rejoindre un événement',
        eventsNoEvent: 'Aucun événement actif pour le moment',
        eventsQrScan: 'Scanner un QR Code',
        qrScanTitle: 'Scanner un QR Code',
        eventsMyEvents: 'Mes événements',
        eventsEmptyTitle: 'Aucun événement chargé',
        eventsEmptySubtitle:
            'Saisissez un code d\'invitation ou scannez un QR Code pour rejoindre jusqu\'à 3 événements simultanément.',
        eventsJoinTitle: 'Rejoindre un événement',
        eventsJoinSubtitle:
            'Saisissez le code d\'invitation (ex. MANIF-123) ou scannez un QR Code.',
        eventsSecurityTitle: 'Sécurité juste-à-temps',
        eventsSecurityDescription:
            'Pour éviter que le tracé d\'un événement ne soit détourné en amont, StreetPhare ne révèle le trajet qu\'à l\'heure paramétrée par les organisateurs.\n\nDe plus, chaque étape (point de rassemblement) disparaît automatiquement de la carte dès que son heure est dépassée de 5 minutes, ou que vous vous trouvez à moins de 30 m de ce point.',
        eventsEnterCodeError: 'Veuillez saisir un code d\'invitation.',
        eventsMaxReachedError:
            'Maximum 3 événements simultanés. Supprimez-en un avant d\'en ajouter un nouveau.',
        eventsUnknownCodeError: 'Code inconnu ou événement introuvable.',
        eventsFleurusCodes:
            'Codes Fleurus : FLEURUS-TOUR, FLEURUS-ECOLES, FLEURUS-CORTEGE.',
        eventsQrMaxReached:
            'Maximum 3 événements simultanés. Supprimez-en un d\'abord.',
        eventsQrAddError:
            'Impossible d\'ajouter l\'événement (déjà présent ou limite de 3 événements atteinte).',
        eventsQrAddSuccess: 'Événement ajouté depuis le QR Code !',
        eventsRemoved: 'Événement retiré.',
        eventsLoadButton: 'Charger',
        eventsRemoveTooltip: 'Retirer l\'événement',
        eventsCodeLabel: 'Code',
        eventsStartLabel: 'Début',
        eventsRouteHidden: 'Trajet masqué — révélation dans :',
        eventsStepActive: 'Étape {index}/{total} active :',
        eventsStepTime: 'Heure prévue :',
        eventsRouteVisible:
            'Trajet visible — toutes les étapes complétées ou événement sans étapes.',
        mapRecenterTooltip: 'Recentrer la carte',
        mapLoadingTiles: 'Chargement de la carte en cours…',
        mapGpsOff: 'Service GPS désactivé',
        mapGpsDenied: 'Autorisation GPS refusée',
        mapGpsDeniedForever: 'Autorisation GPS refusée définitivement',
        mapGpsError: 'Erreur GPS :',
        mapUserPointDefined: 'Point utilisateur défini — Route Safe lancée…',
        mapDestinationEvent: 'Point d\'événement',
        mapDestinationSafeZone: 'Zone Safe',
        mapDestinationCareCenter: 'Centre de soins',
        mapDestinationExit: 'Sortie',
        mapDestinationUserPoint: 'Point utilisateur',
        mapRouteSafeCalculating: 'Calcul de la Route Safe vers {label}…',
        mapRouteSafeFailover: 'Repli vers {label}…',
        mapNoDestinationError:
            'Aucune destination disponible. Rejoignez un événement ou placez un point manuellement (appui long 3 s sur la carte).',
        mapAddEventButton: 'Ajouter un événement',
        mapAddEventWarning:
            'Veuillez ajouter un événement avant de lancer le suivi.',
        mapCollectivePanicTitle: 'Alerte Panic Collective',
        mapCollectivePanicMessage:
            '⚠️ {count} appareils proches ont déclenché une alerte Panic simultanément.\n\nUn point "Tension importante" a été créé automatiquement au centre géographique de ces signaux.\n\nRestez vigilant et consultez la carte.',
        mapViewOnMap: 'Voir sur la carte',
        mapIgnore: 'Ignorer',
        mapNoPanicContactTitle: 'Aucun contact d\'urgence',
        mapNoPanicContactMessage:
            'Vous devez d\'abord configurer au moins un contact dans les Paramètres pour pouvoir utiliser le bouton PANIC.',
        mapOpenSettings: 'Ouvrir les Paramètres',
        mapPanicModeTitle: 'Mode Panique',
        mapPanicModeMessage:
            'Activer le mode panique enverra un SMS d\'alerte avec votre position GPS à {count} contact(s) :\n\n{list}\n\nContinuer ?',
        mapPanicModeActivate: 'ACTIVER',
        mapPanicSmsPreparedTitle: 'SMS préparé',
        mapPanicSmsPreparedMessage:
            'Impossible d\'ouvrir l\'app SMS automatiquement.\nLe message a été copié dans le presse-papier :\n\n{message}',
        mapPanicAlertReadyTitle: 'Alerte prête',
        mapPanicAlertReadyMessage:
            'Un SMS d\'urgence va être envoyé à {count} contact(s) avec votre position GPS.',
        mapPanicMessageBody:
            '[STREETPHARE] Alerte d\'urgence envoyée le {stamp} UTC.\nPosition : {coords}\nMerci de me contacter ou de prévenir les secours.',
        mapPanicNoGps: 'position GPS indisponible',
        mapDestinationObjective: 'Objectif de la Route Safe',
        mapDestinationLongPressHint:
            'Appui long 3 s sur la carte → "Point utilisateur"',
        mapActiveEvent: 'Événement actif',
        mapPeersNearby: 'Pairs',
        mapIsolatedTitle: 'Réseau StreetPhare indisponible',
        mapIsolatedMessage:
            'L\'application ne peut pas fonctionner pour le moment faute de connexion serveur ou de pairs (Hive) à proximité.',
        routeTitle: 'Itinéraire',
        routeCalculate: 'Calculer l\'itinéraire',
        routeDestination: 'Destination',
        routeAvoidLiked: 'Éviter les zones signalées dangereuses',
        routeAvoidPolice: 'Éviter les zones de contrôle',
        routeAvoidCamera: 'Éviter les zones sous surveillance',
        routeAlternativesError: 'Impossible de calculer les alternatives.',
        routeNotFound:
            'Aucun itinéraire trouvé.\nLes blocages actifs empêchent tout passage, ou la position est trop proche de la destination.',
        routeRecommended: 'Recommandé',
        routeShowAlternatives: 'Voir les routes alternatives',
        routeCalculatingAlternatives: 'Calcul des alternatives en cours…',
        routeOpenInOsmAnd: 'Ouvrir dans OsmAnd',
        routeAccept: 'Accepter',
        routeItinerary: 'Itinéraire',
        routeRisk: 'risque',
        routeOsmAndSuccess:
            'Itinéraire calculé via OSM — affiché sur la carte.',
        routeOsmAndError: 'Impossible de lancer OsmAnd.',
        searchTitle: 'Rechercher',
        searchHint: 'Rechercher un lieu, un événement…',
        searchNoResult: 'Aucun résultat trouvé',
        splashInitializing: 'Initialisation…',
        splashCheckingVersion: 'Vérification de la version…',
        splashCheckingCache: 'Vérification du cache local…',
        splashPurgingCache: 'Cache expiré, purge en cours…',
        splashLoadingMap: 'Chargement de la carte locale…',
        splashCachingTiles: 'Mise en cache des tuiles…',
        splashReady: 'Prêt !',
        splashError: 'Erreur :',
        splashSubtitle: 'Cartographie citoyenne en temps réel',
        splashCheckingConnectivity: 'Vérification de la connectivité…',
        panicButton: 'PANIC',
        panicAlertSent: 'Alerte PANIC envoyée',
        onlineStatus: 'En ligne',
        offlineStatus: 'Hors ligne',
        meshStatus: 'Maillage',
        relayStatus: 'Relais',
        blockedUsersTitle: 'Utilisateurs bloqués',
        blockedUsersDescription:
            'Gérez les utilisateurs dont vous avez bloqué les messages.',
        blockedUsersEmpty: 'Aucun utilisateur bloqué.',
        blockedUsersUnblock: 'Débloquer',
        blockedUsersCount: '{count} utilisateur(s) bloqué(s)',
        connectedPeers: 'Pairs connectés',
        proximityValidationTitle: 'Validation de proximité',
        proximityValidationCheck: 'Vérifier la proximité',
        proximityValid: 'Proximité validée',
        proximityInvalid: 'Proximité invalide',
        geofenceEntered: 'Zone d\'événement entrée',
        geofenceExited: 'Zone d\'événement quittée',
        dangerReported: 'Danger signalé',
        dangerConfirmed: 'Danger confirmé (≥3 votes)',
        ok: 'OK',
        cancel: 'Annuler',
        save: 'Enregistrer',
        delete: 'Supprimer',
        confirm: 'Confirmer',
        close: 'Fermer',
        back: 'Retour',
        next: 'Suivant',
        done: 'Terminé',
        errorGeneric: 'Une erreur est survenue',
        loading: 'Chargement…',
        retry: 'Réessayer',
        noInternet: 'Pas de connexion Internet',
        locationAccessTitle: 'Accès à la position',
        locationAccessMessage:
            'StreetPhare a besoin d\'accéder à votre position pour afficher la carte et les alertes à proximité.',
        locationAccessButton: 'Autoriser',
        notificationPermissionTitle: 'Notifications',
        notificationPermissionMessage:
            'StreetPhare a besoin d\'envoyer des notifications pour les alertes et les événements.',
        notificationPermissionButton: 'Autoriser',
        androidChannelAlertsTitle: 'Alertes terrain',
        androidChannelAlertsSubtitle: 'Barrages, nasses, zones de tension',
        androidChannelEventsTitle: 'Événements & Trajets',
        androidChannelEventsSubtitle:
            'Début de trajet, waypoints, fin de manif',
        androidChannelPanicTitle: 'Alertes Panic collectives',
        androidChannelPanicSubtitle: 'Déclenchement panic multi-appareils',
        androidChannelMessagesTitle: 'Messages Hive P2P',
        androidChannelMessagesSubtitle: 'Nouveaux messages sur le réseau local',
        androidChannelSectionTitle: 'Notifications Android par canal',
        androidChannelManageSystem: 'Gérer dans les Paramètres Android',
        transportModePedestrian: 'Piéton',
        transportModeCar: 'Voiture',
        transportModeTransit: 'Transports',
      );

  // ==========================================================================
  // English
  // ==========================================================================
  factory AppStrings.en() => const AppStrings._(
        appTitle: 'StreetPhare',
        settingsTitle: 'Settings',
        mapTitle: 'Map',
        eventsTitle: 'Events',
        messagingTitle: 'Messaging',
        startScreenWelcome: 'Welcome to StreetPhare',
        startScreenSubtitle: 'Collaborative decentralized citizen mapping',
        startScreenSelectLanguage: 'Choose your language',
        startScreenButton: 'Get Started',
        languageLabel: 'English',
        languageSectionTitle: 'Language Choice',
        languageSectionDescription:
            'Change the application language in real time.',
        themeSectionTitle: 'App Theme',
        themeDescription:
            'Dark mode is optimized for OLED screens and stays discreet at night.',
        themeSystem: 'System',
        themeSystemSubtitle: 'Follows system setting',
        themeLight: 'Light',
        themeLightSubtitle: 'Light background, daytime reading',
        themeDark: 'Dark',
        themeDarkSubtitle: 'True OLED black, battery saving',
        batterySaverTitle: 'Battery Saver',
        batterySaverDescription:
            'Reduces GPS/BLE scan frequency and extends battery life.',
        batterySaverSubtitle: 'Reduces GPS and BLE frequency to save battery',
        batterySaverEnabledLabel: 'Battery Saver enabled',
        batterySaverDisabledLabel: 'Battery Saver disabled',
        batterySaverStatusEnabled: 'Reduced scans, map suspended',
        batterySaverStatusDisabled: 'Normal operation',
        backgroundAlertsTitle: 'Background alerts',
        notificationFilterTitle: 'Notification Filter',
        notificationFilterAllLabel: 'All alerts',
        notificationFilterAllDescription:
            'Notifies every micro-event on the network',
        notificationFilterNearbyLabel: 'Confirmed nearby dangers only',
        notificationFilterNearbyDescription:
            'Filter: danger ≥3 votes detected within 100 m',
        notificationFilterEventsLabel: 'Imminent event point changes',
        notificationFilterEventsDescription:
            'Notifies if the next point is revealed in <3 min',
        lowVisionTitle: 'Low Vision Mode',
        lowVisionSubtitle:
            'Large text and adapted interface for better readability',
        lowVisionDescription:
            'Enables very large characters, removes the StreetPhare title on the map and reorganizes the reporting menu into 2 columns (large touch buttons). Automatically enabled if TalkBack/VoiceOver is detected.',
        lowVisionEnabled: 'Low Vision Mode enabled',
        lowVisionDisabled: 'Low Vision Mode disabled',
        lowVisionStatusEnabled: 'Large characters, 2 columns reporting',
        lowVisionStatusDisabled: 'Standard interface',
        messageFilterTitle: 'Message Filter',
        messageFilterDescription:
            'Filter messages received on the decentralized network.',
        messageFilterAllLabel: 'All messages',
        messageFilterAllDescription:
            'Receives all messages broadcast on the network',
        messageFilterNearbyLabel: 'Nearby messages only',
        messageFilterNearbyDescription: 'Messages sent within a 300 m radius',
        messageFilterAdminLabel: 'Event administrators',
        messageFilterAdminDescription:
            'Messages signed by an event administrator',
        messageFilterAlertLabel: 'Alert messages only',
        messageFilterAlertDescription: 'Only critical alerts (ALERT type)',
        avoidanceFiltersTitle: 'Avoidance Filters (Safe Route)',
        avoidanceFiltersDescription:
            'Check the types of dangers to absolutely avoid. The routing engine will bypass these areas.',
        avoidBarragesTitle: 'Avoid blockades',
        avoidBarragesSubtitle: 'Filtering or hard blockades',
        avoidNassesTitle: 'Avoid kettling',
        avoidNassesSubtitle: 'Traps, surrounded areas',
        avoidControlesTitle: 'Avoid police checkpoints',
        avoidControlesSubtitle: 'Filtering, identity checks',
        avoidAccidentsTitle: 'Avoid accidents / water cannons',
        avoidAccidentsSubtitle: 'Fire trucks, accident areas',
        avoidRassemblementsTitle: 'Avoid risky gatherings',
        avoidRassemblementsSubtitle: 'Public gathering areas at risk',
        avoidAutresTitle: 'Avoid "other" dangers',
        avoidAutresSubtitle: 'Any other non-categorized report',
        routeDestinationSection: 'Destination Type',
        routeDestEventPointLabel: 'Follow the current event point',
        routeDestEventPointDescription:
            'Default destination of the active event',
        routeDestSafeZoneLabel: 'To safe zone',
        routeDestSafeZoneDescription:
            '⭐ Absolute priority: nearest safety zone or street medic',
        routeDestCareCenterLabel: 'Nearest care center',
        routeDestCareCenterDescription: 'Nearest street medics or street help',
        routeDestExitPointLabel: 'Nearest exit point',
        routeDestExitPointDescription:
            'Evacuation zone defined in the event JSON',
        routeDestUserPointLabel: 'User point',
        routeDestUserPointDescription:
            'Custom point placed manually (3s long press)',
        mapCacheTitle: 'Map Tile Cache',
        mapCacheSubtitle: 'Maximum retention duration for local cache',
        mapCacheDescription: 'Map tiles are kept locally to save mobile data.',
        mapCacheRetentionLabel: 'Retention duration: ',
        mapCacheForceUpdate: 'Force map update',
        mapCacheCleaned:
            'Map cache cleared. Tiles will be reloaded on next display.',
        mapCacheDays: 'days',
        backgroundServiceTitle: 'Background Service',
        backgroundServiceSubtitle:
            'Persistent "StreetPhare active" notification',
        backgroundServiceDescription:
            'Allows StreetPhare to send alerts even when the application is in the background or asleep.',
        backgroundServiceEnable: 'Enable monitoring',
        panicContactsTitle: 'Emergency Contacts (Panic)',
        panicContactsDescription:
            'These contacts will receive an alert SMS with your GPS position when you press PANIC.',
        panicContactsAdd: 'Add contact',
        panicContactsEmpty: 'No emergency contacts saved',
        panicContactsConfigError:
            'No contacts configured.\nAdd at least one contact for the PANIC button.',
        panicContactsDeleteTitle: 'Delete this contact?',
        panicContactsDeleteMessage: 'Will be removed from the list.',
        panicContactsEditTitle: 'Edit contact',
        panicContactsNewTitle: 'New contact',
        panicContactsFieldName: 'Name',
        panicContactsFieldPhone: 'Phone',
        panicContactsNameHint: 'E.g. Mom, EMS 911',
        panicContactsPhoneHint: '+32 4 XX XX XX XX',
        panicContactsNameRequired: 'Name required',
        panicContactsPhoneRequired: 'Number required',
        panicContactsPhoneTooShort: 'Number too short',
        tutorialTitle: 'App Guide',
        tutorialButton: 'View tutorial',
        tutorialDescription: 'Consult StreetPhare features at any time.',
        aboutTitle: 'About',
        aboutApp: 'About StreetPhare',
        aboutVersion: 'Version',
        aboutPlatform: 'Platform',
        aboutLicense: 'License',
        aboutEncryption: 'Encryption',
        aboutOpenSource: 'Citizen open-source project',
        aboutDescription:
            'StreetPhare is a decentralized collaborative mapping application designed to strengthen collective safety during citizen gatherings. No personal data is collected or transmitted to third parties. All data remains local or passes through encrypted peer-to-peer relays.',
        bugReportTitle: 'Bug Report',
        bugReportButton: 'Report a bug',
        bugReportSuggest: 'Suggest',
        bugReportDescription:
            '💡 This form sends a technical report to the StreetPhare administration server. Reports help developers identify and fix issues quickly.',
        bugReportPrivacy:
            '🔒 No personal data is transmitted. Only the title, description, category, and app version are sent.',
        bugReportSectionTitle: 'Bug Reporting & Suggestions',
        bugReportSectionDescription:
            'Bug Button (top right of the map): report a bug or suggestion directly from the main interface without leaving the map.',
        eventsJoin: 'Join an event',
        eventsNoEvent: 'No active events at the moment',
        eventsQrScan: 'Scan QR Code',
        qrScanTitle: 'Scan a QR Code',
        eventsMyEvents: 'My events',
        eventsEmptyTitle: 'No events loaded',
        eventsEmptySubtitle:
            'Enter an invitation code or scan a QR Code to join up to 3 events simultaneously.',
        eventsJoinTitle: 'Join an event',
        eventsJoinSubtitle:
            'Enter the invitation code (e.g. MANIF-123) or scan a QR Code.',
        eventsSecurityTitle: 'Just-in-time security',
        eventsSecurityDescription:
            'To prevent an event\'s route from being diverted in advance, StreetPhare only reveals the route at the time set by the organizers.\n\nAdditionally, each step (gathering point) automatically disappears from the map as soon as its time has passed by 5 minutes, or you are within 30 m of that point.',
        eventsEnterCodeError: 'Please enter an invitation code.',
        eventsMaxReachedError:
            'Maximum 3 simultaneous events. Delete one before adding a new one.',
        eventsUnknownCodeError: 'Unknown code or event not found.',
        eventsFleurusCodes:
            'Fleurus codes: FLEURUS-TOUR, FLEURUS-ECOLES, FLEURUS-CORTEGE.',
        eventsQrMaxReached: 'Maximum 3 simultaneous events. Delete one first.',
        eventsQrAddError:
            'Impossible to add the event (already present or 3 events limit reached).',
        eventsQrAddSuccess: 'Event added from QR Code!',
        eventsRemoved: 'Event removed.',
        eventsLoadButton: 'Load',
        eventsRemoveTooltip: 'Remove event',
        eventsCodeLabel: 'Code',
        eventsStartLabel: 'Start',
        eventsRouteHidden: 'Route hidden — revelation in:',
        eventsStepActive: 'Step {index}/{total} active:',
        eventsStepTime: 'Scheduled time:',
        eventsRouteVisible:
            'Route visible — all steps completed or event without steps.',
        mapRecenterTooltip: 'Recenter map',
        mapLoadingTiles: 'Loading map…',
        mapGpsOff: 'GPS service disabled',
        mapGpsDenied: 'GPS permission denied',
        mapGpsDeniedForever: 'GPS permission permanently denied',
        mapGpsError: 'GPS Error:',
        mapUserPointDefined: 'User point defined — Safe Route started…',
        mapDestinationEvent: 'Event point',
        mapDestinationSafeZone: 'Safe Zone',
        mapDestinationCareCenter: 'Care Center',
        mapDestinationExit: 'Exit',
        mapDestinationUserPoint: 'User point',
        mapRouteSafeCalculating: 'Calculating Safe Route to {label}…',
        mapRouteSafeFailover: 'Failover to {label}…',
        mapNoDestinationError:
            'No destination available. Join an event or place a point manually (3s long press on map).',
        mapAddEventButton: 'Add event',
        mapAddEventWarning: 'Please add an event before starting tracking.',
        mapCollectivePanicTitle: 'Collective Panic Alert',
        mapCollectivePanicMessage:
            '⚠️ {count} nearby devices triggered a Panic alert simultaneously.\n\nAn "Important tension" point has been automatically created at the geographic center of these signals.\n\nStay vigilant and check the map.',
        mapViewOnMap: 'View on map',
        mapIgnore: 'Ignore',
        mapNoPanicContactTitle: 'No emergency contacts',
        mapNoPanicContactMessage:
            'You must first configure at least one contact in Settings to use the PANIC button.',
        mapOpenSettings: 'Open Settings',
        mapPanicModeTitle: 'Panic Mode',
        mapPanicModeMessage:
            'Activating panic mode will send an alert SMS with your GPS position to {count} contact(s):\n\n{list}\n\nContinue?',
        mapPanicModeActivate: 'ACTIVATE',
        mapPanicSmsPreparedTitle: 'SMS prepared',
        mapPanicSmsPreparedMessage:
            'Unable to open SMS app automatically.\nThe message has been copied to the clipboard:\n\n{message}',
        mapPanicAlertReadyTitle: 'Alert ready',
        mapPanicAlertReadyMessage:
            'An emergency SMS will be sent to {count} contact(s) with your GPS position.',
        mapPanicMessageBody:
            '[STREETPHARE] Emergency alert sent at {stamp} UTC.\nPosition: {coords}\nPlease contact me or call emergency services.',
        mapPanicNoGps: 'GPS position unavailable',
        mapDestinationObjective: 'Safe Route Objective',
        mapDestinationLongPressHint: '3s long press on map → "User point"',
        mapActiveEvent: 'Active event',
        mapPeersNearby: 'Peers',
        mapIsolatedTitle: 'StreetPhare network unavailable',
        mapIsolatedMessage:
            'The app cannot function at the moment due to lack of server connection or nearby peers (Hive).',
        routeTitle: 'Route',
        routeCalculate: 'Calculate route',
        routeDestination: 'Destination',
        routeAvoidLiked: 'Avoid reported danger zones',
        routeAvoidPolice: 'Avoid checkpoint areas',
        routeAvoidCamera: 'Avoid surveillance areas',
        routeAlternativesError: 'Impossible to calculate alternatives.',
        routeNotFound:
            'No itinerary found.\nActive blockades prevent any passage, or the position is too close to the destination.',
        routeRecommended: 'Recommended',
        routeShowAlternatives: 'See alternative routes',
        routeCalculatingAlternatives: 'Calculating alternatives…',
        routeOpenInOsmAnd: 'Open in OsmAnd',
        routeAccept: 'Accept',
        routeItinerary: 'Itinerary',
        routeRisk: 'risk',
        routeOsmAndSuccess:
            'Itinerary calculated via OSM — displayed on the map.',
        routeOsmAndError: 'Impossible to launch OsmAnd.',
        searchTitle: 'Search',
        searchHint: 'Search for a place, event…',
        searchNoResult: 'No results found',
        splashInitializing: 'Initializing…',
        splashCheckingVersion: 'Checking version…',
        splashCheckingCache: 'Checking local cache…',
        splashPurgingCache: 'Cache expired, purging…',
        splashLoadingMap: 'Loading local map…',
        splashCachingTiles: 'Caching tiles…',
        splashReady: 'Ready!',
        splashError: 'Error:',
        splashSubtitle: 'Real-time citizen mapping',
        splashCheckingConnectivity: 'Checking connectivity…',
        panicButton: 'PANIC',
        panicAlertSent: 'PANIC alert sent',
        onlineStatus: 'Online',
        offlineStatus: 'Offline',
        meshStatus: 'Mesh',
        relayStatus: 'Relay',
        blockedUsersTitle: 'Blocked users',
        blockedUsersDescription:
            'Manage users whose messages you have blocked.',
        blockedUsersEmpty: 'No blocked users.',
        blockedUsersUnblock: 'Unblock',
        blockedUsersCount: '{count} blocked user(s)',
        connectedPeers: 'Connected peers',
        proximityValidationTitle: 'Proximity Validation',
        proximityValidationCheck: 'Check proximity',
        proximityValid: 'Proximity validated',
        proximityInvalid: 'Invalid proximity',
        geofenceEntered: 'Event zone entered',
        geofenceExited: 'Event zone exited',
        dangerReported: 'Danger reported',
        dangerConfirmed: 'Danger confirmed (≥3 votes)',
        ok: 'OK',
        cancel: 'Cancel',
        save: 'Save',
        delete: 'Delete',
        confirm: 'Confirm',
        close: 'Close',
        back: 'Back',
        next: 'Next',
        done: 'Done',
        errorGeneric: 'An error occurred',
        loading: 'Loading…',
        retry: 'Retry',
        noInternet: 'No internet connection',
        locationAccessTitle: 'Location Access',
        locationAccessMessage:
            'StreetPhare needs access to your location to display the map and nearby alerts.',
        locationAccessButton: 'Allow',
        notificationPermissionTitle: 'Notifications',
        notificationPermissionMessage:
            'StreetPhare needs to send notifications for alerts and events.',
        notificationPermissionButton: 'Allow',
        androidChannelAlertsTitle: 'Field alerts',
        androidChannelAlertsSubtitle: 'Blockades, kettling, tension zones',
        androidChannelEventsTitle: 'Events & Trips',
        androidChannelEventsSubtitle: 'Trip start, waypoints, end of demo',
        androidChannelPanicTitle: 'Collective Panic alerts',
        androidChannelPanicSubtitle: 'Multi-device panic triggering',
        androidChannelMessagesTitle: 'Hive P2P Messages',
        androidChannelMessagesSubtitle: 'New messages on the local network',
        androidChannelSectionTitle: 'Android Notifications by Channel',
        androidChannelManageSystem: 'Manage in Android Settings',
        transportModePedestrian: 'Walking',
        transportModeCar: 'Car',
        transportModeTransit: 'Transit',
      );

  // ==========================================================================
  // Nederlands
  // ==========================================================================
  factory AppStrings.nl() => const AppStrings._(
        appTitle: 'StreetPhare',
        settingsTitle: 'Instellingen',
        mapTitle: 'Kaart',
        eventsTitle: 'Evenementen',
        messagingTitle: 'Berichten',
        startScreenWelcome: 'Welkom bij StreetPhare',
        startScreenSubtitle: 'Gedecentraliseerde burgerkartering',
        startScreenSelectLanguage: 'Kies uw taal',
        startScreenButton: 'Beginnen',
        languageLabel: 'Nederlands',
        languageSectionTitle: 'Taalkeuze',
        languageSectionDescription:
            'Wijzig de taal van de applicatie in realtime.',
        themeSectionTitle: 'Applicatie thema',
        themeDescription:
            'De donkere modus is geoptimaliseerd voor OLED-schermen en blijft \u0027s nachts discreet.',
        themeSystem: 'Systeem',
        themeSystemSubtitle: 'Volgt systeeminstelling',
        themeLight: 'Licht',
        themeLightSubtitle: 'Lichte achtergrond, daglichtlezen',
        themeDark: 'Donker',
        themeDarkSubtitle: 'Echt OLED-zwart, batterijbesparing',
        batterySaverTitle: 'Energiebesparing',
        batterySaverDescription:
            'Vermindert de frequentie van GPS/BLE-scans en verlengt de levensduur van de batterij.',
        batterySaverSubtitle:
            'Vermindert GPS- en BLE-frequentie om batterij te sparen',
        batterySaverEnabledLabel: 'Energiebesparing ingeschakeld',
        batterySaverDisabledLabel: 'Energiebesparing uitgeschakeld',
        batterySaverStatusEnabled: 'Verminderde scans, kaart onderbroken',
        batterySaverStatusDisabled: 'Normale werking',
        backgroundAlertsTitle: 'Achtergrondmeldingen',
        notificationFilterTitle: 'Notificatiefilter',
        notificationFilterAllLabel: 'Alle meldingen',
        notificationFilterAllDescription:
            'Meldt elk micro-evenement op het netwerk',
        notificationFilterNearbyLabel: 'Alleen bevestigde gevaren in de buurt',
        notificationFilterNearbyDescription:
            'Filter: gevaar ≥3 stemmen gedetecteerd binnen 100 m',
        notificationFilterEventsLabel: 'Aankomende evenementpuntwijzigingen',
        notificationFilterEventsDescription:
            'Meldt als het volgende punt binnen <3 min wordt onthuld',
        lowVisionTitle: 'Slechtziendheidmodus',
        lowVisionSubtitle:
            'Grote tekst en aangepaste interface voor betere leesbaarheid',
        lowVisionDescription:
            'Schakelt zeer grote karakters in, verwijdert de StreetPhare-titel op de kaart en reorganiseert het signaleringsmenu in 2 kolommen (grote aanraakknoppen). Automatisch ingeschakeld als TalkBack/VoiceOver wordt gedetecteerd.',
        lowVisionEnabled: 'Slechtziendheidmodus ingeschakeld',
        lowVisionDisabled: 'Slechtziendheidmodus uitgeschakeld',
        lowVisionStatusEnabled: 'Grote karakters, 2 kolommen signalering',
        lowVisionStatusDisabled: 'Standaard interface',
        messageFilterTitle: 'Berichtenfilter',
        messageFilterDescription:
            'Filter berichten ontvangen op het gedecentraliseerde netwerk.',
        messageFilterAllLabel: 'Alle berichten',
        messageFilterAllDescription:
            'Ontvangt alle berichten die op het netwerk worden uitgezonden',
        messageFilterNearbyLabel: 'Alleen berichten in de buurt',
        messageFilterNearbyDescription:
            'Berichten verzonden binnen een straal van 300 m',
        messageFilterAdminLabel: 'Evenementbeheerders',
        messageFilterAdminDescription:
            'Berichten ondertekend door een evenementbeheerder',
        messageFilterAlertLabel: 'Alleen alarmmeldingen',
        messageFilterAlertDescription:
            'Alleen kritieke waarschuwingen (type ALERT)',
        avoidanceFiltersTitle: 'Vermijdingsfilters (Veilige Route)',
        avoidanceFiltersDescription:
            'Vink de soorten gevaren aan die u absoluut wilt vermijden. De routeplanner zal deze gebieden omzeilen.',
        avoidBarragesTitle: 'Vermijd blokkades',
        avoidBarragesSubtitle: 'Filterende of harde blokkades',
        avoidNassesTitle: 'Vermijd omsingeling',
        avoidNassesSubtitle: 'Vallen, omsingelde gebieden',
        avoidControlesTitle: 'Vermijd politiecontroles',
        avoidControlesSubtitle: 'Filtering, identiteitscontroles',
        avoidAccidentsTitle: 'Vermijd ongelukken / waterkanonnen',
        avoidAccidentsSubtitle: 'Brandweerwagens, ongevalgebieden',
        avoidRassemblementsTitle: 'Vermijd riskante bijeenkomsten',
        avoidRassemblementsSubtitle: 'Publieke verzamelplaatsen met risico',
        avoidAutresTitle: 'Vermijd "andere" gevaren',
        avoidAutresSubtitle: 'Elke andere niet-gecategoriseerde melding',
        routeDestinationSection: 'Bestemmingstype',
        routeDestEventPointLabel: 'Volg het huidige evenementpunt',
        routeDestEventPointDescription:
            'Standaardbestemming van het actieve evenement',
        routeDestSafeZoneLabel: 'Naar veilige zone',
        routeDestSafeZoneDescription:
            '⭐ Absolute prioriteit: dichtstbijzijnde veiligheidszone of street medic',
        routeDestCareCenterLabel: 'Dichtstbijzijnde zorgcentrum',
        routeDestCareCenterDescription:
            'Dichtstbijzijnde street medics of straathulp',
        routeDestExitPointLabel: 'Dichtstbijzijnde uitgangspunt',
        routeDestExitPointDescription:
            'Evacuatiezone gedefinieerd in het evenement JSON',
        routeDestUserPointLabel: 'Gebruikerspunt',
        routeDestUserPointDescription:
            'Aangepast punt handmatig geplaatst (3s lang indrukken)',
        mapCacheTitle: 'Kaarttegelcache',
        mapCacheSubtitle: 'Maximale bewaartijd voor lokale cache',
        mapCacheDescription:
            'Kaarttegels worden lokaal bewaard om mobiele data te besparen.',
        mapCacheRetentionLabel: 'Bewaartijd: ',
        mapCacheForceUpdate: 'Forceer kaartupdate',
        mapCacheCleaned:
            'Kaartcache gewist. Tegels worden bij de volgende weergave opnieuw geladen.',
        mapCacheDays: 'dagen',
        backgroundServiceTitle: 'Achtergrondservice',
        backgroundServiceSubtitle: 'Blijvende melding "StreetPhare actief"',
        backgroundServiceDescription:
            'Stelt StreetPhare in staat om meldingen te sturen, zelfs als de applicatie op de achtergrond draait of in slaapstand is.',
        backgroundServiceEnable: 'Surveillance inschakelen',
        panicContactsTitle: 'Noodcontacten (Panic)',
        panicContactsDescription:
            'Deze contacten ontvangen een alarm-sms met uw GPS-positie wanneer u op PANIC drukt.',
        panicContactsAdd: 'Contact toevoegen',
        panicContactsEmpty: 'Geen noodcontacten opgeslagen',
        panicContactsConfigError:
            'Geen contacten geconfigureerd.\nVoeg minimaal één contact toe voor de PANIC-knop.',
        panicContactsDeleteTitle: 'Dit contact verwijderen?',
        panicContactsDeleteMessage: 'Zal uit de lijst worden verwijderd.',
        panicContactsEditTitle: 'Contact bewerken',
        panicContactsNewTitle: 'Nieuw contact',
        panicContactsFieldName: 'Naam',
        panicContactsFieldPhone: 'Telefoon',
        panicContactsNameHint: 'Bijv. Mama, 112',
        panicContactsPhoneHint: '+32 4 XX XX XX XX',
        panicContactsNameRequired: 'Naam vereist',
        panicContactsPhoneRequired: 'Nummer vereist',
        panicContactsPhoneTooShort: 'Nummer te kort',
        tutorialTitle: 'App-gids',
        tutorialButton: 'Bekijk handleiding',
        tutorialDescription: 'Raadpleeg StreetPhare-functies op elk moment.',
        aboutTitle: 'Over',
        aboutApp: 'Over StreetPhare',
        aboutVersion: 'Versie',
        aboutPlatform: 'Platform',
        aboutLicense: 'Licentie',
        aboutEncryption: 'Versleuteling',
        aboutOpenSource: 'Burgerlijk open-source project',
        aboutDescription:
            'StreetPhare is een gedecentraliseerde collaboratieve karteringsapplicatie ontworpen om de collectieve veiligheid te versterken tijdens burgerbijeenkomsten. Er worden geen persoonlijke gegevens verzameld of doorgegeven aan derden. Alle gegevens blijven lokaal of gaan via versleutelde peer-to-peer relais.',
        bugReportTitle: 'Bugrapport',
        bugReportButton: 'Meld een bug',
        bugReportSuggest: 'Stel voor',
        bugReportDescription:
            '💡 Dit formulier stuurt een technisch rapport naar de StreetPhare-beheerserver. Rapporten helpen ontwikkelaars problemen snel te identificeren en op te lossen.',
        bugReportPrivacy:
            '🔒 Er worden geen persoonlijke gegevens verzonden. Alleen de titel, beschrijving, categorie en app-versie worden verzonden.',
        bugReportSectionTitle: 'Bugrapportage & Suggesties',
        bugReportSectionDescription:
            'Bug-knop (linksonder op de kaart): meld een bug ou suggestie direct vanuit de hoofdinterface zonder de kaart te verlaten.',
        eventsJoin: 'Word lid van een evenement',
        eventsNoEvent: 'Momenteel geen actieve evenementen',
        eventsQrScan: 'Scan QR-code',
        qrScanTitle: 'Scan een QR-code',
        eventsMyEvents: 'Mijn evenementen',
        eventsEmptyTitle: 'Geen evenementen geladen',
        eventsEmptySubtitle:
            'Voer een uitnodigingscode in of scan een QR-code om lid te worden van maximaal 3 evenementen tegelijk.',
        eventsJoinTitle: 'Word lid van een evenement',
        eventsJoinSubtitle:
            'Voer de uitnodigingscode in (bijv. MANIF-123) of scan een QR-code.',
        eventsSecurityTitle: 'Just-in-time beveiliging',
        eventsSecurityDescription:
            'Om te voorkomen dat de route van een evenement vooraf wordt omgeleid, onthult StreetPhare de route pas op het door de organisatoren ingestelde tijdstip.\n\nBovendien verdwijnt elke stap (verzamelpunt) automatisch van de kaart zodra de tijd met 5 minuten is verstreken, of u zich binnen 30 m van dat punt bevindt.',
        eventsEnterCodeError: 'Voer een uitnodigingscode in.',
        eventsMaxReachedError:
            'Maximaal 3 gelijktijdige evenementen. Verwijder er een voordat u een nieuwe toevoegt.',
        eventsUnknownCodeError: 'Onbekende code of evenement niet gevonden.',
        eventsFleurusCodes:
            'Fleurus-codes: FLEURUS-TOUR, FLEURUS-ECOLES, FLEURUS-CORTEGE.',
        eventsQrMaxReached:
            'Maximaal 3 gelijktijdige evenementen. Verwijder er eerst een.',
        eventsQrAddError:
            'Onmogelijk om het evenement toe te voegen (al aanwezig of limiet van 3 evenementen bereikt).',
        eventsQrAddSuccess: 'Evenement toegevoegd via QR-code!',
        eventsRemoved: 'Evenement verwijderd.',
        eventsLoadButton: 'Laden',
        eventsRemoveTooltip: 'Evenement verwijderen',
        eventsCodeLabel: 'Code',
        eventsStartLabel: 'Start',
        eventsRouteHidden: 'Route verborgen — onthulling in:',
        eventsStepActive: 'Stap {index}/{total} actief:',
        eventsStepTime: 'Geplande tijd:',
        eventsRouteVisible:
            'Route zichtbaar — alle stappen voltooid of evenement zonder stappen.',
        mapRecenterTooltip: 'Kaart hercentreren',
        mapLoadingTiles: 'Kaart laden…',
        mapGpsOff: 'GPS-service uitgeschakeld',
        mapGpsDenied: 'GPS-toegang geweigerd',
        mapGpsDeniedForever: 'GPS-toegang permanent geweigerd',
        mapGpsError: 'GPS-fout:',
        mapUserPointDefined:
            'Gebruikerspunt gedefinieerd — Veilige Route gestart…',
        mapDestinationEvent: 'Evenementpunt',
        mapDestinationSafeZone: 'Veilige Zone',
        mapDestinationCareCenter: 'Zorgcentrum',
        mapDestinationExit: 'Uitgang',
        mapDestinationUserPoint: 'Gebruikerspunt',
        mapRouteSafeCalculating: 'Veilige Route naar {label} berekenen…',
        mapRouteSafeFailover: 'Terugval naar {label}…',
        mapNoDestinationError:
            'Geen bestemming beschikbaar. Word lid van een evenement of plaats handmatig een punt (3s lang indrukken op kaart).',
        mapAddEventButton: 'Evenement toevoegen',
        mapAddEventWarning:
            'Voeg een evenement toe voordat u met volgen begint.',
        mapCollectivePanicTitle: 'Collectieve Paniekwaarschuwing',
        mapCollectivePanicMessage:
            '⚠️ {count} apparaten in de buurt hebben tegelijkertijd een Paniekmelding geactiveerd.\n\nEr is automatisch een "Belangrijke spanning" punt aangemaakt in het geografische midden van deze signalen.\n\nBlijf waakzaam en bekijk de kaart.',
        mapViewOnMap: 'Bekijk op de kaart',
        mapIgnore: 'Negeren',
        mapNoPanicContactTitle: 'Geen noodcontacten',
        mapNoPanicContactMessage:
            'U moet eerst minimaal één contact configureren in Instellingen om de PANIEK-knop te kunnen gebruiken.',
        mapOpenSettings: 'Open Instellingen',
        mapPanicModeTitle: 'Paniekmodus',
        mapPanicModeMessage:
            'Het activeren van de paniekmodus stuurt een alarm-sms met uw GPS-positie naar {count} contact(en):\n\n{list}\n\nDoorgaan?',
        mapPanicModeActivate: 'ACTIVEREN',
        mapPanicSmsPreparedTitle: 'SMS voorbereid',
        mapPanicSmsPreparedMessage:
            'Kan de SMS-app niet automatisch openen.\nHet bericht is naar het klembord gekopieerd:\n\n{message}',
        mapPanicAlertReadyTitle: 'Waarschuwing gereed',
        mapPanicAlertReadyMessage:
            'Er wordt een nood-sms gestuurd naar {count} contact(en) met uw GPS-positie.',
        mapPanicMessageBody:
            '[STREETPHARE] Noodmelding verzonden om {stamp} UTC.\nPositie: {coords}\nNeem contact met mij op of bel de hulpdiensten.',
        mapPanicNoGps: 'GPS-positie niet beschikbaar',
        mapDestinationObjective: 'Doel van de Veilige Route',
        mapDestinationLongPressHint:
            '3s lang indrukken op kaart → "Gebruikerspunt"',
        mapActiveEvent: 'Actief evenement',
        mapPeersNearby: 'Peers',
        mapIsolatedTitle: 'StreetPhare-netwerk niet beschikbaar',
        mapIsolatedMessage:
            'De app kan op dit moment niet functioneren door gebrek aan serververbinding of nabijgelegen peers (Hive).',
        routeTitle: 'Route',
        routeCalculate: 'Bereken route',
        routeDestination: 'Bestemming',
        routeAvoidLiked: 'Vermijd gemelde gevarenzones',
        routeAvoidPolice: 'Vermijd controleposten',
        routeAvoidCamera: 'Vermijd bewakingszones',
        routeAlternativesError: 'Onmogelijk om alternatieven te berekenen.',
        routeNotFound:
            'Geen route gevonden.\nActieve blokkades verhinderen elke doorgang, of de positie is te dicht bij de bestemming.',
        routeRecommended: 'Aanbevolen',
        routeShowAlternatives: 'Bekijk alternatieve routes',
        routeCalculatingAlternatives: 'Alternatieven berekenen…',
        routeOpenInOsmAnd: 'Openen in OsmAnd',
        routeAccept: 'Accepteren',
        routeItinerary: 'Routebeschrijving',
        routeRisk: 'risico',
        routeOsmAndSuccess: 'Route berekend via OSM — weergegeven op de kaart.',
        routeOsmAndError: 'Onmogelijk om OsmAnd te starten.',
        searchTitle: 'Zoeken',
        searchHint: 'Zoek naar een plaats, evenement…',
        searchNoResult: 'Geen resultaten gevonden',
        splashInitializing: 'Initialiseren…',
        splashCheckingVersion: 'Versie controleren…',
        splashCheckingCache: 'Lokale cache controleren…',
        splashPurgingCache: 'Cache verlopen, opschonen…',
        splashLoadingMap: 'Lokale kaart laden…',
        splashCachingTiles: 'Tegels cachen…',
        splashReady: 'Klaar!',
        splashError: 'Fout:',
        splashSubtitle: 'Real-time burgerkartering',
        splashCheckingConnectivity: 'Connectiviteit controleren…',
        panicButton: 'PANIEK',
        panicAlertSent: 'PANIEK-melding verzonden',
        onlineStatus: 'Online',
        offlineStatus: 'Offline',
        meshStatus: 'Mesh',
        relayStatus: 'Relais',
        blockedUsersTitle: 'Geblokkeerde gebruikers',
        blockedUsersDescription:
            'Beheer gebruikers van wie u berichten heeft geblokkeerd.',
        blockedUsersEmpty: 'Geen geblokkeerde gebruikers.',
        blockedUsersUnblock: 'Deblokkeren',
        blockedUsersCount: '{count} geblokkeerde gebruiker(s)',
        connectedPeers: 'Verbonden peers',
        proximityValidationTitle: 'Nabijheidsvalidatie',
        proximityValidationCheck: 'Controleer nabijheid',
        proximityValid: 'Nabijheid gevalideerd',
        proximityInvalid: 'Ongeldige nabijheid',
        geofenceEntered: 'Evenementzone betreden',
        geofenceExited: 'Evenementzone verlaten',
        dangerReported: 'Gevaar gemeld',
        dangerConfirmed: 'Gevaar bevestigd (≥3 stemmen)',
        ok: 'OK',
        cancel: 'Annuleren',
        save: 'Opslaan',
        delete: 'Verwijderen',
        confirm: 'Bevestigen',
        close: 'Sluiten',
        back: 'Terug',
        next: 'Volgende',
        done: 'Gereed',
        errorGeneric: 'Er is een fout opgetreden',
        loading: 'Laden…',
        retry: 'Opnieuw',
        noInternet: 'Geen internetverbinding',
        locationAccessTitle: 'Locatietoegang',
        locationAccessMessage:
            'StreetPhare heeft toegang tot uw locatie nodig om de kaart en meldingen in de buurt weer te geven.',
        locationAccessButton: 'Toestaan',
        notificationPermissionTitle: 'Meldingen',
        notificationPermissionMessage:
            'StreetPhare moet meldingen kunnen sturen voor waarschuwingen en evenementen.',
        notificationPermissionButton: 'Toestaan',
        androidChannelAlertsTitle: 'Terreinwaarschuwingen',
        androidChannelAlertsSubtitle:
            'Blokkades, omsingelingen, spanningszones',
        androidChannelEventsTitle: 'Evenementen & Ritten',
        androidChannelEventsSubtitle:
            'Start van de rit, waypoints, einde van de demo',
        androidChannelPanicTitle: 'Collectieve Paniekmeldingen',
        androidChannelPanicSubtitle: 'Multi-device paniekactivering',
        androidChannelMessagesTitle: 'Hive P2P-berichten',
        androidChannelMessagesSubtitle:
            'Nieuwe berichten op het lokale netwerk',
        androidChannelSectionTitle: 'Android-meldingen per kanaal',
        androidChannelManageSystem: 'Beheren in Android-instellingen',
        transportModePedestrian: 'Te voet',
        transportModeCar: 'Auto',
        transportModeTransit: 'OV',
      );

  // ==========================================================================
  // Deutsch
  // ==========================================================================
  factory AppStrings.de() => const AppStrings._(
        appTitle: 'StreetPhare',
        settingsTitle: 'Einstellungen',
        mapTitle: 'Karte',
        eventsTitle: 'Veranstaltungen',
        messagingTitle: 'Nachrichten',
        startScreenWelcome: 'Willkommen bei StreetPhare',
        startScreenSubtitle: 'Dezentrale Bürgerkartierung',
        startScreenSelectLanguage: 'Wählen Sie Ihre Sprache',
        startScreenButton: 'Loslegen',
        languageLabel: 'Deutsch',
        languageSectionTitle: 'Sprachauswahl',
        languageSectionDescription:
            'Ändern Sie die Anwendungssprache in Echtzeit.',
        themeSectionTitle: 'App-Design',
        themeDescription:
            'Der Dunkelmodus ist für OLED-Bildschirme optimiert und bleibt nachts diskret.',
        themeSystem: 'System',
        themeSystemSubtitle: 'Folgt der Systemeinstellung',
        themeLight: 'Hell',
        themeLightSubtitle: 'Heller Hintergrund, Taglesen',
        themeDark: 'Dunkel',
        themeDarkSubtitle: 'Echtes OLED-Schwarz, Batteriesparmodus',
        batterySaverTitle: 'Energiesparmodus',
        batterySaverDescription:
            'Reduziert die GPS/BLE-Scanfrequenz und verlängert die Akkulaufzeit.',
        batterySaverSubtitle:
            'Reduziert GPS- und BLE-Frequenz zum Batteriesparen',
        batterySaverEnabledLabel: 'Energiesparmodus aktiviert',
        batterySaverDisabledLabel: 'Energiesparmodus deaktiviert',
        batterySaverStatusEnabled: 'Reduzierte Scans, Karte angehalten',
        batterySaverStatusDisabled: 'Normalbetrieb',
        backgroundAlertsTitle: 'Hintergrundwarnungen',
        notificationFilterTitle: 'Benachrichtigungsfilter',
        notificationFilterAllLabel: 'Alle Warnungen',
        notificationFilterAllDescription:
            'Benachrichtigt über jedes Mikro-Ereignis im Netzwerk',
        notificationFilterNearbyLabel: 'Nur bestätigte Gefahren in der Nähe',
        notificationFilterNearbyDescription:
            'Filter: Gefahr ≥3 Stimmen in 100 m Umkreis erkannt',
        notificationFilterEventsLabel: 'Bevorstehende Ereignispunktänderungen',
        notificationFilterEventsDescription:
            'Benachrichtigt, wenn der nächste Punkt in <3 Min. enthüllt wird',
        lowVisionTitle: 'Sehbehindertenmodus',
        lowVisionSubtitle:
            'Großer Text und angepasste Oberfläche für bessere Lesbarkeit',
        lowVisionDescription:
            'Aktiviert sehr große Zeichen, entfernt den StreetPhare-Titel auf der Karte und reorganisiert das Melde-Menü in 2 Spalten (große Touch-Buttons). Wird automatisch aktiviert, wenn TalkBack/VoiceOver erkannt wird.',
        lowVisionEnabled: 'Sehbehindertenmodus aktiviert',
        lowVisionDisabled: 'Sehbehindertenmodus deaktiviert',
        lowVisionStatusEnabled: 'Große Zeichen, 2-Spalten-Meldung',
        lowVisionStatusDisabled: 'Standardoberfläche',
        messageFilterTitle: 'Nachrichtenfilter',
        messageFilterDescription:
            'Filtern Sie Nachrichten, die über das dezentrale Netzwerk empfangen wurden.',
        messageFilterAllLabel: 'Alle Nachrichten',
        messageFilterAllDescription:
            'Empfängt alle im Netzwerk verbreiteten Nachrichten',
        messageFilterNearbyLabel: 'Nur Nachrichten in der Nähe',
        messageFilterNearbyDescription:
            'Nachrichten, die im Umkreis von 300 m gesendet wurden',
        messageFilterAdminLabel: 'Veranstaltungsadministratoren',
        messageFilterAdminDescription:
            'Nachrichten, die von einem Veranstaltungsadministrator signiert wurden',
        messageFilterAlertLabel: 'Nur Alarmmeldungen',
        messageFilterAlertDescription: 'Nur kritische Warnungen (Typ ALERT)',
        avoidanceFiltersTitle: 'Vermeidungsfilter (Sichere Route)',
        avoidanceFiltersDescription:
            'Wählen Sie die Gefahrenarten aus, die unbedingt vermieden werden sollen. Die Routing-Engine wird diese Bereiche umgehen.',
        avoidBarragesTitle: 'Blockaden vermeiden',
        avoidBarragesSubtitle: 'Filternde oder harte Blockaden',
        avoidNassesTitle: 'Einkesselung vermeiden',
        avoidNassesSubtitle: 'Fallen, umzingelde Bereiche',
        avoidControlesTitle: 'Polizeikontrollen vermeiden',
        avoidControlesSubtitle: 'Filterung, Identitätskontrollen',
        avoidAccidentsTitle: 'Unfälle / Wasserwerfer vermeiden',
        avoidAccidentsSubtitle: 'Feuerwehrwagen, Unfallbereiche',
        avoidRassemblementsTitle: 'Riskante Versammlungen vermeiden',
        avoidRassemblementsSubtitle:
            'Öffentliche Versammlungsbereiche mit Risiko',
        avoidAutresTitle: '"Andere" Gefahren vermeiden',
        avoidAutresSubtitle: 'Alle anderen nicht kategorisierten Meldungen',
        routeDestinationSection: 'Zieltyp',
        routeDestEventPointLabel: 'Dem aktuellen Ereignispunkt folgen',
        routeDestEventPointDescription:
            'Standardziel der aktiven Veranstaltung',
        routeDestSafeZoneLabel: 'Zur Safe Zone',
        routeDestSafeZoneDescription:
            '⭐ Absolute Priorität: nächste Sicherheitszone oder Street Medic',
        routeDestCareCenterLabel: 'Nächstgelegenes Versorgungszentrum',
        routeDestCareCenterDescription:
            'Nächstgelegene Street Medics oder Hilfe auf der Straße',
        routeDestExitPointLabel: 'Nächstgelegener Ausgangspunkt',
        routeDestExitPointDescription:
            'Evakuierungszone, definiert im Ereignis-JSON',
        routeDestUserPointLabel: 'Benutzerpunkt',
        routeDestUserPointDescription:
            'Benutzerdefinierter Punkt, manuell platziert (3 Sek. langes Drücken)',
        mapCacheTitle: 'Kartenkachel-Cache',
        mapCacheSubtitle: 'Maximale Aufbewahrungsdauer für lokalen Cache',
        mapCacheDescription:
            'Kartenkacheln werden lokal gespeichert, um mobile Daten zu sparen.',
        mapCacheRetentionLabel: 'Aufbewahrungsdauer: ',
        mapCacheForceUpdate: 'Kartenaktualisierung erzwingen',
        mapCacheCleaned:
            'Karten-Cache geleert. Kacheln werden bei der nächsten Anzeige neu geladen.',
        mapCacheDays: 'Tage',
        backgroundServiceTitle: 'Hintergrunddienst',
        backgroundServiceSubtitle:
            'Dauerhafte Benachrichtigung "StreetPhare aktiv"',
        backgroundServiceDescription:
            'Ermöglicht StreetPhare das Senden von Warnungen, auch wenn die Anwendung im Hintergrund läuft oder im Ruhezustand ist.',
        backgroundServiceEnable: 'Überwachung aktivieren',
        panicContactsTitle: 'Notfallkontakte (Panik)',
        panicContactsDescription:
            'Diese Kontakte erhalten eine Alarm-SMS mit Ihrer GPS-Position, wenn Sie PANIK drücken.',
        panicContactsAdd: 'Kontakt hinzufügen',
        panicContactsEmpty: 'Keine Notfallkontakte gespeichert',
        panicContactsConfigError:
            'Keine Kontakte konfiguriert.\nFügen Sie mindestens einen Kontakt für den PANIK-Button hinzu.',
        panicContactsDeleteTitle: 'Diesen Kontakt löschen?',
        panicContactsDeleteMessage: 'Wird aus der Liste entfernt.',
        panicContactsEditTitle: 'Kontakt bearbeiten',
        panicContactsNewTitle: 'Neuer Kontakt',
        panicContactsFieldName: 'Name',
        panicContactsFieldPhone: 'Telefon',
        panicContactsNameHint: 'Z. B. Mama, Rettungsdienst 112',
        panicContactsPhoneHint: '+32 4 XX XX XX XX',
        panicContactsNameRequired: 'Name erforderlich',
        panicContactsPhoneRequired: 'Nummer erforderlich',
        panicContactsPhoneTooShort: 'Nummer zu kurz',
        tutorialTitle: 'App-Anleitung',
        tutorialButton: 'Tutorial ansehen',
        tutorialDescription:
            'Konsultieren Sie die StreetPhare-Funktionen jederzeit.',
        aboutTitle: 'Über',
        aboutApp: 'Über StreetPhare',
        aboutVersion: 'Version',
        aboutPlatform: 'Plattform',
        aboutLicense: 'Lizenz',
        aboutEncryption: 'Verschlüsselung',
        aboutOpenSource: 'Bürgerliches Open-Source-Projekt',
        aboutDescription:
            'StreetPhare ist eine dezentrale kollaborative Kartierungsanwendung, die entwickelt wurde, um die kollektive Sicherheit bei Bürgerversammlungen zu stärken. Es werden keine personenbezogenen Daten erhoben oder an Dritte übermittelt. Alle Daten bleiben lokal oder werden über verschlüsselte Peer-to-Peer-Relais übertragen.',
        bugReportTitle: 'Fehlerbericht',
        bugReportButton: 'Einen Fehler melden',
        bugReportSuggest: 'Vorschlagen',
        bugReportDescription:
            '💡 Dieses Formular sendet einen technischen Bericht an den StreetPhare-Verwaltungsserver. Berichte helfen Entwicklern, Probleme schnell zu identifizieren und zu beheben.',
        bugReportPrivacy:
            '🔒 Es werden keine persönlichen Daten übermittelt. Nur Titel, Beschreibung, Kategorie und App-Version werden gesendet.',
        bugReportSectionTitle: 'Fehlerberichterstattung & Vorschläge',
        bugReportSectionDescription:
            'Bug-Button (unten links auf der Karte): Melden Sie einen Fehler oder einen Vorschlag direkt von der Hauptoberfläche aus, ohne die Karte zu verlassen.',
        eventsJoin: 'An einer Veranstaltung teilnehmen',
        eventsNoEvent: 'Derzeit keine aktiven Veranstaltungen',
        eventsQrScan: 'QR-Code scannen',
        qrScanTitle: 'Einen QR-Code scannen',
        eventsMyEvents: 'Meine Veranstaltungen',
        eventsEmptyTitle: 'Keine Veranstaltungen geladen',
        eventsEmptySubtitle:
            'Geben Sie einen Einladungscode ein oder scannen Sie einen QR-Code, um an bis zu 3 Veranstaltungen gleichzeitig teilzunehmen.',
        eventsJoinTitle: 'An einer Veranstaltung teilnehmen',
        eventsJoinSubtitle:
            'Geben Sie den Einladungscode ein (z. B. MANIF-123) oder scannen Sie einen QR-Code.',
        eventsSecurityTitle: 'Just-in-Time-Sicherheit',
        eventsSecurityDescription:
            'Um zu verhindern, dass die Route einer Veranstaltung im Vorfeld umgeleitet wird, enthüllt StreetPhare die Route erst zu dem von den Organisatoren festgelegten Zeitpunkt.\n\nZusätzlich verschwindet jeder Schritt (Sammelpunkt) automatisch von der Karte, sobald seine Zeit um 5 Minuten überschritten wurde oder Sie sich in einem Umkreis von 30 m um diesen Punkt befinden.',
        eventsEnterCodeError: 'Bitte geben Sie einen Einladungscode ein.',
        eventsMaxReachedError:
            'Maximal 3 gleichzeitige Veranstaltungen. Löschen Sie eine, bevor Sie eine neue hinzufügen.',
        eventsUnknownCodeError:
            'Unbekannter Code oder Veranstaltung nicht gefunden.',
        eventsFleurusCodes:
            'Fleurus-Codes: FLEURUS-TOUR, FLEURUS-ECOLES, FLEURUS-CORTEGE.',
        eventsQrMaxReached:
            'Maximal 3 gleichzeitige Veranstaltungen. Löschen Sie zuerst eine.',
        eventsQrAddError:
            'Die Veranstaltung konnte nicht hinzugefügt werden (bereits vorhanden oder Limit von 3 Veranstaltungen erreicht).',
        eventsQrAddSuccess: 'Veranstaltung über QR-Code hinzugefügt!',
        eventsRemoved: 'Veranstaltung entfernt.',
        eventsLoadButton: 'Laden',
        eventsRemoveTooltip: 'Veranstaltung entfernen',
        eventsCodeLabel: 'Code',
        eventsStartLabel: 'Beginn',
        eventsRouteHidden: 'Route ausgeblendet — Enthüllung in:',
        eventsStepActive: 'Schritt {index}/{total} aktiv:',
        eventsStepTime: 'Geplante Zeit:',
        eventsRouteVisible:
            'Route sichtbar — alle Schritte abgeschlossen oder Veranstaltung ohne Schritte.',
        mapRecenterTooltip: 'Karte neu zentrieren',
        mapLoadingTiles: 'Karte laden…',
        mapGpsOff: 'GPS-Dienst deaktiviert',
        mapGpsDenied: 'GPS-Berechtigung verweigert',
        mapGpsDeniedForever: 'GPS-Berechtigung dauerhaft verweigert',
        mapGpsError: 'GPS-Fehler:',
        mapUserPointDefined:
            'Benutzerpunkt definiert — Sichere Route gestartet…',
        mapDestinationEvent: 'Ereignispunkt',
        mapDestinationSafeZone: 'Safe Zone',
        mapDestinationCareCenter: 'Versorgungszentrum',
        mapDestinationExit: 'Ausgang',
        mapDestinationUserPoint: 'Benutzerpunkt',
        mapRouteSafeCalculating: 'Sichere Route nach {label} berechnen…',
        mapRouteSafeFailover: 'Rückgriff auf {label}…',
        mapNoDestinationError:
            'Kein Ziel verfügbar. Nehmen Sie an einer Veranstaltung teil oder setzen Sie manuell einen Punkt (3 Sek. langes Drücken auf Karte).',
        mapAddEventButton: 'Veranstaltung hinzufügen',
        mapAddEventWarning:
            'Bitte fügen Sie eine Veranstaltung hinzu, bevor Sie mit dem Tracking beginnen.',
        mapCollectivePanicTitle: 'Kollektiver Panik-Alarm',
        mapCollectivePanicMessage:
            '⚠️ {count} Geräte in der Nähe haben gleichzeitig einen Panik-Alarm ausgelöst.\n\nEin Punkt "Wichtige Spannung" wurde automatisch im geografischen Zentrum dieser Signale erstellt.\n\nBleiben Sie wachsam und sehen Sie auf die Karte.',
        mapViewOnMap: 'Auf der Karte ansehen',
        mapIgnore: 'Ignorer',
        mapNoPanicContactTitle: 'Keine Notfallkontakte',
        mapNoPanicContactMessage:
            'Sie müssen zuerst mindestens einen Kontakt in den Einstellungen konfigurieren, um den PANIK-Button verwenden zu können.',
        mapOpenSettings: 'Einstellungen öffnen',
        mapPanicModeTitle: 'Panikmodus',
        mapPanicModeMessage:
            'Das Aktivieren des Panikmodus sendet eine Alarm-SMS mit Ihrer GPS-Position an {count} Kontakt(e):\n\n{list}\n\nFortfahren?',
        mapPanicModeActivate: 'AKTIVIEREN',
        mapPanicSmsPreparedTitle: 'SMS vorbereitet',
        mapPanicSmsPreparedMessage:
            'Die SMS-App kann nicht automatisch geöffnet werden.\nDie Nachricht wurde in die Zwischenablage kopiert:\n\n{message}',
        mapPanicAlertReadyTitle: 'Alarm bereit',
        mapPanicAlertReadyMessage:
            'Eine Notfall-SMS wird an {count} Kontakt(e) mit Ihrer GPS-Position gesendet.',
        mapPanicMessageBody:
            '[STREETPHARE] Notfallalarm gesendet um {stamp} UTC.\nPosition: {coords}\nBitte kontaktieren Sie mich oder rufen Sie den Rettungsdienst.',
        mapPanicNoGps: 'GPS-Position nicht verfügbar',
        mapDestinationObjective: 'Ziel der Sicheren Route',
        mapDestinationLongPressHint:
            '3 Sek. langes Drücken auf Karte → "Benutzerpunkt"',
        mapActiveEvent: 'Aktive Veranstaltung',
        mapPeersNearby: 'Peers',
        mapIsolatedTitle: 'StreetPhare-Netzwerk nicht verfügbar',
        mapIsolatedMessage:
            'Die App kann derzeit nicht funktionieren, da keine Serververbindung oder keine Peers (Hive) in der Nähe vorhanden sind.',
        routeTitle: 'Route',
        routeCalculate: 'Route berechnen',
        routeDestination: 'Ziel',
        routeAvoidLiked: 'Gemeldete Gefahrenzonen vermeiden',
        routeAvoidPolice: 'Kontrollzonen vermeiden',
        routeAvoidCamera: 'Überwachungszonen vermeiden',
        routeAlternativesError: 'Alternativen konnten nicht berechnet werden.',
        routeNotFound:
            'Keine Route gefunden.\nAktive Blockaden verhindern jegliches Durchkommen, oder die Position ist zu nah am Ziel.',
        routeRecommended: 'Empfohlen',
        routeShowAlternatives: 'Alternative Routen anzeigen',
        routeCalculatingAlternatives: 'Alternativen werden berechnet…',
        routeOpenInOsmAnd: 'In OsmAnd öffnen',
        routeAccept: 'Akzeptieren',
        routeItinerary: 'Route',
        routeRisk: 'Risiko',
        routeOsmAndSuccess:
            'Route über OSM berechnet — auf der Karte angezeigt.',
        routeOsmAndError: 'OsmAnd konnte nicht gestartet werden.',
        searchTitle: 'Suche',
        searchHint: 'Suche nach einem Ort, einer Veranstaltung…',
        searchNoResult: 'Keine Ergebnisse gefunden',
        splashInitializing: 'Initialisiere…',
        splashCheckingVersion: 'Version prüfen…',
        splashCheckingCache: 'Lokalen Cache prüfen…',
        splashPurgingCache: 'Cache abgelaufen, Bereinigung…',
        splashLoadingMap: 'Lokale Karte laden…',
        splashCachingTiles: 'Kacheln cachen…',
        splashReady: 'Bereit!',
        splashError: 'Fehler:',
        splashSubtitle: 'Echtzeit-Bürgerkartierung',
        splashCheckingConnectivity: 'Konnektivität prüfen…',
        panicButton: 'PANIK',
        panicAlertSent: 'PANIK-Alarm gesendet',
        onlineStatus: 'Online',
        offlineStatus: 'Offline',
        meshStatus: 'Mesh',
        relayStatus: 'Relais',
        blockedUsersTitle: 'Blockierte Benutzer',
        blockedUsersDescription:
            'Verwalten Sie Benutzer, deren Nachrichten Sie blockiert haben.',
        blockedUsersEmpty: 'Keine blockierten Benutzer.',
        blockedUsersUnblock: 'Entsperren',
        blockedUsersCount: '{count} blockierte(r) Benutzer',
        connectedPeers: 'Verbundene Peers',
        proximityValidationTitle: 'Näherungsvalidierung',
        proximityValidationCheck: 'Nähe prüfen',
        proximityValid: 'Nähe validiert',
        proximityInvalid: 'Ungültige Nähe',
        geofenceEntered: 'Veranstaltungszone betreten',
        geofenceExited: 'Veranstaltungszone verlassen',
        dangerReported: 'Gefahr gemeldet',
        dangerConfirmed: 'Gefahr bestätigt (≥3 Stimmen)',
        ok: 'OK',
        cancel: 'Abbrechen',
        save: 'Speichern',
        delete: 'Löschen',
        confirm: 'Bestätigen',
        close: 'Schließen',
        back: 'Zurück',
        next: 'Weiter',
        done: 'Fertig',
        errorGeneric: 'Ein Fehler ist aufgetreten',
        loading: 'Laden…',
        retry: 'Wiederholen',
        noInternet: 'Keine Internetverbindung',
        locationAccessTitle: 'Standortzugriff',
        locationAccessMessage:
            'StreetPhare benötigt Zugriff auf Ihren Standort, um die Karte und Warnungen in der Nähe anzuzeigen.',
        locationAccessButton: 'Erlauben',
        notificationPermissionTitle: 'Benachrichtigungen',
        notificationPermissionMessage:
            'StreetPhare muss Benachrichtigungen für Warnungen und Veranstaltungen senden können.',
        notificationPermissionButton: 'Erlauben',
        androidChannelAlertsTitle: 'Feldwarnungen',
        androidChannelAlertsSubtitle:
            'Blockaden, Einkesselungen, Spannungszonen',
        androidChannelEventsTitle: 'Veranstaltungen & Fahrten',
        androidChannelEventsSubtitle: 'Fahrtbeginn, Wegpunkte, Ende der Demo',
        androidChannelPanicTitle: 'Kollektive Panik-Warnungen',
        androidChannelPanicSubtitle: 'Geräteübergreifende Panik-Auslösung',
        androidChannelMessagesTitle: 'Nachrichten',
        androidChannelMessagesSubtitle: 'Neue Nachrichten im lokalen Netzwerk',
        androidChannelSectionTitle: 'Android-Benachrichtigungen nach Kanal',
        androidChannelManageSystem: 'In Android-Einstellungen verwalten',
        transportModePedestrian: 'Zu Fuß',
        transportModeCar: 'Auto',
        transportModeTransit: 'ÖPNV',
      );
}
