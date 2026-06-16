// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'StreetPhare';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get mapTitle => 'Map';

  @override
  String get eventsTitle => 'Events';

  @override
  String get messagingTitle => 'Messaging';

  @override
  String get startScreenWelcome => 'Welcome to StreetPhare';

  @override
  String get startScreenSubtitle => 'Collaborative decentralized citizen mapping';

  @override
  String get startScreenSelectLanguage => 'Choose your language';

  @override
  String get startScreenButton => 'Get Started';

  @override
  String get languageLabel => 'English';

  @override
  String get languageSectionTitle => 'Language Choice';

  @override
  String get languageSectionDescription => 'Change the application language in real time.';

  @override
  String get themeSectionTitle => 'App Theme';

  @override
  String get themeDescription => 'Dark mode is optimized for OLED screens and stays discreet at night.';

  @override
  String get themeSystem => 'System';

  @override
  String get themeSystemSubtitle => 'Follows system setting';

  @override
  String get themeLight => 'Light';

  @override
  String get themeLightSubtitle => 'Light background, daytime reading';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeDarkSubtitle => 'True OLED black, battery saving';

  @override
  String get batterySaverTitle => 'Battery Saver';

  @override
  String get batterySaverDescription => 'Reduces GPS/BLE scan frequency and extends battery life.';

  @override
  String get batterySaverSubtitle => 'Reduces GPS and BLE frequency to save battery';

  @override
  String get batterySaverEnabledLabel => 'Battery Saver enabled';

  @override
  String get batterySaverDisabledLabel => 'Battery Saver disabled';

  @override
  String get batterySaverStatusEnabled => 'Reduced scans, map suspended';

  @override
  String get batterySaverStatusDisabled => 'Normal operation';

  @override
  String get backgroundAlertsTitle => 'Background alerts';

  @override
  String get notificationFilterTitle => 'Notification Filter';

  @override
  String get notificationFilterAllLabel => 'All alerts';

  @override
  String get notificationFilterAllDescription => 'Notifies every micro-event on the network';

  @override
  String get notificationFilterNearbyLabel => 'Confirmed nearby dangers only';

  @override
  String get notificationFilterNearbyDescription => 'Filter: danger ≥3 votes detected within 100 m';

  @override
  String get notificationFilterEventsLabel => 'Imminent event point changes';

  @override
  String get notificationFilterEventsDescription => 'Notifies if the next point is revealed in <3 min';

  @override
  String get lowVisionTitle => 'Low Vision Mode';

  @override
  String get lowVisionSubtitle => 'Large text and adapted interface for better readability';

  @override
  String get lowVisionDescription => 'Enables very large characters, removes the StreetPhare title on the map and reorganizes the reporting menu into 2 columns (large touch buttons). Automatically enabled if TalkBack/VoiceOver is detected.';

  @override
  String get lowVisionEnabled => 'Low Vision Mode enabled';

  @override
  String get lowVisionDisabled => 'Low Vision Mode disabled';

  @override
  String get lowVisionStatusEnabled => 'Large characters, 2 columns reporting';

  @override
  String get lowVisionStatusDisabled => 'Standard interface';

  @override
  String get messageFilterTitle => 'Message Filter';

  @override
  String get messageFilterDescription => 'Filter messages received on the decentralized network.';

  @override
  String get messageFilterAllLabel => 'All messages';

  @override
  String get messageFilterAllDescription => 'Receives all messages broadcast on the network';

  @override
  String get messageFilterNearbyLabel => 'Nearby messages only';

  @override
  String get messageFilterNearbyDescription => 'Messages sent within a 300 m radius';

  @override
  String get messageFilterAdminLabel => 'Event administrators';

  @override
  String get messageFilterAdminDescription => 'Messages signed by an event administrator';

  @override
  String get messageFilterAlertLabel => 'Alert messages only';

  @override
  String get messageFilterAlertDescription => 'Only critical alerts (ALERT type)';

  @override
  String get avoidanceFiltersTitle => 'Avoidance Filters (Safe Route)';

  @override
  String get avoidanceFiltersDescription => 'Check the types of dangers to absolutely avoid. The routing engine will bypass these areas.';

  @override
  String get avoidBarragesTitle => 'Avoid blockades';

  @override
  String get avoidBarragesSubtitle => 'Filtering or hard blockades';

  @override
  String get avoidNassesTitle => 'Avoid kettling';

  @override
  String get avoidNassesSubtitle => 'Traps, surrounded areas';

  @override
  String get avoidControlesTitle => 'Avoid police checkpoints';

  @override
  String get avoidControlesSubtitle => 'Filtering, identity checks';

  @override
  String get avoidAccidentsTitle => 'Avoid accidents / water cannons';

  @override
  String get avoidAccidentsSubtitle => 'Fire trucks, accident areas';

  @override
  String get avoidRassemblementsTitle => 'Avoid risky gatherings';

  @override
  String get avoidRassemblementsSubtitle => 'Public gathering areas at risk';

  @override
  String get avoidAutresTitle => 'Avoid \"other\" dangers';

  @override
  String get avoidAutresSubtitle => 'Any other non-categorized report';

  @override
  String get routeDestinationSection => 'Destination Type';

  @override
  String get routeDestEventPointLabel => 'Follow the current event point';

  @override
  String get routeDestEventPointDescription => 'Default destination of the active event';

  @override
  String get routeDestSafeZoneLabel => 'To the Safe Zone / Nearest care center';

  @override
  String get routeDestSafeZoneDescription => '⭐ Absolute priority: nearest safety zone or street medic';

  @override
  String get routeDestCareCenterLabel => 'Nearest care center';

  @override
  String get routeDestCareCenterDescription => 'Nearest street medics or street help';

  @override
  String get routeDestExitPointLabel => 'Nearest exit point';

  @override
  String get routeDestExitPointDescription => 'Evacuation zone defined in the event JSON';

  @override
  String get routeDestUserPointLabel => 'User point';

  @override
  String get routeDestUserPointDescription => 'Custom point placed manually (3s long press)';

  @override
  String get mapCacheTitle => 'Map Tile Cache';

  @override
  String get mapCacheSubtitle => 'Maximum retention duration for local cache';

  @override
  String get mapCacheDescription => 'Map tiles are kept locally to save mobile data.';

  @override
  String get mapCacheRetentionLabel => 'Retention duration: ';

  @override
  String get mapCacheForceUpdate => 'Force map update';

  @override
  String get mapCacheCleaned => 'Map cache cleared. Tiles will be reloaded on next display.';

  @override
  String get mapCacheDays => 'days';

  @override
  String get backgroundServiceTitle => 'Background Service';

  @override
  String get backgroundServiceSubtitle => 'Persistent \"StreetPhare active\" notification';

  @override
  String get backgroundServiceDescription => 'Allows StreetPhare to send alerts even when the application is in the background or asleep.';

  @override
  String get backgroundServiceEnable => 'Enable monitoring';

  @override
  String get panicContactsTitle => 'Emergency Contacts (Panic)';

  @override
  String get panicContactsDescription => 'These contacts will receive an alert SMS with your GPS position when you press PANIC.';

  @override
  String get panicContactsAdd => 'Add contact';

  @override
  String get panicContactsEmpty => 'No emergency contacts saved';

  @override
  String get panicContactsConfigError => 'No contacts configured.\nAdd at least one contact for the PANIC button.';

  @override
  String get panicContactsDeleteTitle => 'Delete this contact?';

  @override
  String get panicContactsDeleteMessage => 'Will be removed from the list.';

  @override
  String get panicContactsEditTitle => 'Edit contact';

  @override
  String get panicContactsNewTitle => 'New contact';

  @override
  String get panicContactsFieldName => 'Name';

  @override
  String get panicContactsFieldPhone => 'Phone';

  @override
  String get panicContactsNameHint => 'E.g. Mom, EMS 911';

  @override
  String get panicContactsPhoneHint => '+32 4 XX XX XX XX';

  @override
  String get panicContactsNameRequired => 'Name required';

  @override
  String get panicContactsPhoneRequired => 'Number required';

  @override
  String get panicContactsPhoneTooShort => 'Number too short';

  @override
  String get tutorialTitle => 'App Guide';

  @override
  String get tutorialButton => 'View tutorial';

  @override
  String get tutorialDescription => 'Consult StreetPhare features at any time.';

  @override
  String get aboutTitle => 'About';

  @override
  String get aboutApp => 'About StreetPhare';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutPlatform => 'Platform';

  @override
  String get aboutLicense => 'License';

  @override
  String get aboutEncryption => 'Encryption';

  @override
  String get aboutOpenSource => 'Citizen open-source project';

  @override
  String get aboutDescription => 'StreetPhare is a decentralized collaborative mapping application designed to strengthen collective safety during citizen gatherings. No personal data is collected or transmitted to third parties. All data remains local or passes through encrypted peer-to-peer relays.';

  @override
  String get bugReportTitle => 'Bug Report';

  @override
  String get bugReportButton => 'Report a bug';

  @override
  String get bugReportSuggest => 'Suggest';

  @override
  String get bugReportDescription => '💡 This form sends a technical report to the StreetPhare administration server. Reports help developers identify and fix issues quickly.';

  @override
  String get bugReportPrivacy => '🔒 No personal data is transmitted. Only the title, description, category, and app version are sent.';

  @override
  String get bugReportSectionTitle => 'Bug Reporting & Suggestions';

  @override
  String get bugReportSectionDescription => 'Bug Button (bottom left of the map): report a bug or suggestion directly from the main interface without leaving the map.';

  @override
  String get eventsJoin => 'Join an event';

  @override
  String get eventsNoEvent => 'No active events at the moment';

  @override
  String get eventsQrScan => 'Scan QR Code';

  @override
  String get qrScanTitle => 'Scan a QR Code';

  @override
  String get searchTitle => 'Search';

  @override
  String get searchHint => 'Search for a place, event…';

  @override
  String get searchNoResult => 'No results found';

  @override
  String get routeTitle => 'Route';

  @override
  String get routeCalculate => 'Calculate route';

  @override
  String get routeDestination => 'Destination';

  @override
  String get routeAvoidLiked => 'Avoid reported danger zones';

  @override
  String get routeAvoidPolice => 'Avoid checkpoint areas';

  @override
  String get routeAvoidCamera => 'Avoid surveillance areas';

  @override
  String get splashInitializing => 'Initializing…';

  @override
  String get splashCheckingVersion => 'Checking version…';

  @override
  String get splashCheckingCache => 'Checking local cache…';

  @override
  String get splashPurgingCache => 'Cache expired, purging…';

  @override
  String get splashLoadingMap => 'Loading local map…';

  @override
  String get splashCachingTiles => 'Caching tiles…';

  @override
  String get splashReady => 'Ready!';

  @override
  String get splashError => 'Error:';

  @override
  String get splashSubtitle => 'Real-time citizen mapping';

  @override
  String get splashCheckingConnectivity => 'Checking connectivity…';

  @override
  String get panicButton => 'PANIC';

  @override
  String get panicAlertSent => 'PANIC alert sent';

  @override
  String get onlineStatus => 'Online';

  @override
  String get offlineStatus => 'Offline';

  @override
  String get meshStatus => 'Mesh';

  @override
  String get relayStatus => 'Relay';

  @override
  String get connectedPeers => 'Connected peers';

  @override
  String get proximityValidationTitle => 'Proximity Validation';

  @override
  String get proximityValidationCheck => 'Check proximity';

  @override
  String get proximityValid => 'Proximity validated';

  @override
  String get proximityInvalid => 'Invalid proximity';

  @override
  String get geofenceEntered => 'Event zone entered';

  @override
  String get geofenceExited => 'Event zone exited';

  @override
  String get dangerReported => 'Danger reported';

  @override
  String get dangerConfirmed => 'Danger confirmed (≥3 votes)';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get confirm => 'Confirm';

  @override
  String get close => 'Close';

  @override
  String get back => 'Back';

  @override
  String get next => 'Next';

  @override
  String get done => 'Done';

  @override
  String get errorGeneric => 'An error occurred';

  @override
  String get loading => 'Loading…';

  @override
  String get retry => 'Retry';

  @override
  String get noInternet => 'No internet connection';

  @override
  String get locationAccessTitle => 'Location Access';

  @override
  String get locationAccessMessage => 'StreetPhare needs access to your location to display the map and nearby alerts.';

  @override
  String get locationAccessButton => 'Allow';

  @override
  String get notificationPermissionTitle => 'Notifications';

  @override
  String get notificationPermissionMessage => 'StreetPhare needs to send notifications for alerts and events.';

  @override
  String get notificationPermissionButton => 'Allow';

  @override
  String get androidChannelAlertsTitle => 'Field alerts';

  @override
  String get androidChannelAlertsSubtitle => 'Blockades, kettling, tension zones';

  @override
  String get androidChannelEventsTitle => 'Events & Trips';

  @override
  String get androidChannelEventsSubtitle => 'Trip start, waypoints, end of demo';

  @override
  String get androidChannelPanicTitle => 'Collective Panic alerts';

  @override
  String get androidChannelPanicSubtitle => 'Multi-device panic triggering';

  @override
  String get androidChannelMessagesTitle => 'Hive P2P Messages';

  @override
  String get androidChannelMessagesSubtitle => 'New messages on the local network';

  @override
  String get androidChannelSectionTitle => 'Android Notifications by Channel';

  @override
  String get androidChannelManageSystem => 'Manage in Android Settings';
}
