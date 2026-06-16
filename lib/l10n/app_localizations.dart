import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_nl.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('fr'),
    Locale('nl')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'StreetPhare'**
  String get appTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @mapTitle.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get mapTitle;

  /// No description provided for @eventsTitle.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get eventsTitle;

  /// No description provided for @messagingTitle.
  ///
  /// In en, this message translates to:
  /// **'Messaging'**
  String get messagingTitle;

  /// No description provided for @startScreenWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to StreetPhare'**
  String get startScreenWelcome;

  /// No description provided for @startScreenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Collaborative decentralized citizen mapping'**
  String get startScreenSubtitle;

  /// No description provided for @startScreenSelectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose your language'**
  String get startScreenSelectLanguage;

  /// No description provided for @startScreenButton.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get startScreenButton;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageLabel;

  /// No description provided for @languageSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Language Choice'**
  String get languageSectionTitle;

  /// No description provided for @languageSectionDescription.
  ///
  /// In en, this message translates to:
  /// **'Change the application language in real time.'**
  String get languageSectionDescription;

  /// No description provided for @themeSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'App Theme'**
  String get themeSectionTitle;

  /// No description provided for @themeDescription.
  ///
  /// In en, this message translates to:
  /// **'Dark mode is optimized for OLED screens and stays discreet at night.'**
  String get themeDescription;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeSystemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Follows system setting'**
  String get themeSystemSubtitle;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeLightSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Light background, daytime reading'**
  String get themeLightSubtitle;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeDarkSubtitle.
  ///
  /// In en, this message translates to:
  /// **'True OLED black, battery saving'**
  String get themeDarkSubtitle;

  /// No description provided for @batterySaverTitle.
  ///
  /// In en, this message translates to:
  /// **'Battery Saver'**
  String get batterySaverTitle;

  /// No description provided for @batterySaverDescription.
  ///
  /// In en, this message translates to:
  /// **'Reduces GPS/BLE scan frequency and extends battery life.'**
  String get batterySaverDescription;

  /// No description provided for @batterySaverSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reduces GPS and BLE frequency to save battery'**
  String get batterySaverSubtitle;

  /// No description provided for @batterySaverEnabledLabel.
  ///
  /// In en, this message translates to:
  /// **'Battery Saver enabled'**
  String get batterySaverEnabledLabel;

  /// No description provided for @batterySaverDisabledLabel.
  ///
  /// In en, this message translates to:
  /// **'Battery Saver disabled'**
  String get batterySaverDisabledLabel;

  /// No description provided for @batterySaverStatusEnabled.
  ///
  /// In en, this message translates to:
  /// **'Reduced scans, map suspended'**
  String get batterySaverStatusEnabled;

  /// No description provided for @batterySaverStatusDisabled.
  ///
  /// In en, this message translates to:
  /// **'Normal operation'**
  String get batterySaverStatusDisabled;

  /// No description provided for @backgroundAlertsTitle.
  ///
  /// In en, this message translates to:
  /// **'Background alerts'**
  String get backgroundAlertsTitle;

  /// No description provided for @notificationFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification Filter'**
  String get notificationFilterTitle;

  /// No description provided for @notificationFilterAllLabel.
  ///
  /// In en, this message translates to:
  /// **'All alerts'**
  String get notificationFilterAllLabel;

  /// No description provided for @notificationFilterAllDescription.
  ///
  /// In en, this message translates to:
  /// **'Notifies every micro-event on the network'**
  String get notificationFilterAllDescription;

  /// No description provided for @notificationFilterNearbyLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirmed nearby dangers only'**
  String get notificationFilterNearbyLabel;

  /// No description provided for @notificationFilterNearbyDescription.
  ///
  /// In en, this message translates to:
  /// **'Filter: danger ≥3 votes detected within 100 m'**
  String get notificationFilterNearbyDescription;

  /// No description provided for @notificationFilterEventsLabel.
  ///
  /// In en, this message translates to:
  /// **'Imminent event point changes'**
  String get notificationFilterEventsLabel;

  /// No description provided for @notificationFilterEventsDescription.
  ///
  /// In en, this message translates to:
  /// **'Notifies if the next point is revealed in <3 min'**
  String get notificationFilterEventsDescription;

  /// No description provided for @lowVisionTitle.
  ///
  /// In en, this message translates to:
  /// **'Low Vision Mode'**
  String get lowVisionTitle;

  /// No description provided for @lowVisionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Large text and adapted interface for better readability'**
  String get lowVisionSubtitle;

  /// No description provided for @lowVisionDescription.
  ///
  /// In en, this message translates to:
  /// **'Enables very large characters, removes the StreetPhare title on the map and reorganizes the reporting menu into 2 columns (large touch buttons). Automatically enabled if TalkBack/VoiceOver is detected.'**
  String get lowVisionDescription;

  /// No description provided for @lowVisionEnabled.
  ///
  /// In en, this message translates to:
  /// **'Low Vision Mode enabled'**
  String get lowVisionEnabled;

  /// No description provided for @lowVisionDisabled.
  ///
  /// In en, this message translates to:
  /// **'Low Vision Mode disabled'**
  String get lowVisionDisabled;

  /// No description provided for @lowVisionStatusEnabled.
  ///
  /// In en, this message translates to:
  /// **'Large characters, 2 columns reporting'**
  String get lowVisionStatusEnabled;

  /// No description provided for @lowVisionStatusDisabled.
  ///
  /// In en, this message translates to:
  /// **'Standard interface'**
  String get lowVisionStatusDisabled;

  /// No description provided for @messageFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Message Filter'**
  String get messageFilterTitle;

  /// No description provided for @messageFilterDescription.
  ///
  /// In en, this message translates to:
  /// **'Filter messages received on the decentralized network.'**
  String get messageFilterDescription;

  /// No description provided for @messageFilterAllLabel.
  ///
  /// In en, this message translates to:
  /// **'All messages'**
  String get messageFilterAllLabel;

  /// No description provided for @messageFilterAllDescription.
  ///
  /// In en, this message translates to:
  /// **'Receives all messages broadcast on the network'**
  String get messageFilterAllDescription;

  /// No description provided for @messageFilterNearbyLabel.
  ///
  /// In en, this message translates to:
  /// **'Nearby messages only'**
  String get messageFilterNearbyLabel;

  /// No description provided for @messageFilterNearbyDescription.
  ///
  /// In en, this message translates to:
  /// **'Messages sent within a 300 m radius'**
  String get messageFilterNearbyDescription;

  /// No description provided for @messageFilterAdminLabel.
  ///
  /// In en, this message translates to:
  /// **'Event administrators'**
  String get messageFilterAdminLabel;

  /// No description provided for @messageFilterAdminDescription.
  ///
  /// In en, this message translates to:
  /// **'Messages signed by an event administrator'**
  String get messageFilterAdminDescription;

  /// No description provided for @messageFilterAlertLabel.
  ///
  /// In en, this message translates to:
  /// **'Alert messages only'**
  String get messageFilterAlertLabel;

  /// No description provided for @messageFilterAlertDescription.
  ///
  /// In en, this message translates to:
  /// **'Only critical alerts (ALERT type)'**
  String get messageFilterAlertDescription;

  /// No description provided for @avoidanceFiltersTitle.
  ///
  /// In en, this message translates to:
  /// **'Avoidance Filters (Safe Route)'**
  String get avoidanceFiltersTitle;

  /// No description provided for @avoidanceFiltersDescription.
  ///
  /// In en, this message translates to:
  /// **'Check the types of dangers to absolutely avoid. The routing engine will bypass these areas.'**
  String get avoidanceFiltersDescription;

  /// No description provided for @avoidBarragesTitle.
  ///
  /// In en, this message translates to:
  /// **'Avoid blockades'**
  String get avoidBarragesTitle;

  /// No description provided for @avoidBarragesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Filtering or hard blockades'**
  String get avoidBarragesSubtitle;

  /// No description provided for @avoidNassesTitle.
  ///
  /// In en, this message translates to:
  /// **'Avoid kettling'**
  String get avoidNassesTitle;

  /// No description provided for @avoidNassesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Traps, surrounded areas'**
  String get avoidNassesSubtitle;

  /// No description provided for @avoidControlesTitle.
  ///
  /// In en, this message translates to:
  /// **'Avoid police checkpoints'**
  String get avoidControlesTitle;

  /// No description provided for @avoidControlesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Filtering, identity checks'**
  String get avoidControlesSubtitle;

  /// No description provided for @avoidAccidentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Avoid accidents / water cannons'**
  String get avoidAccidentsTitle;

  /// No description provided for @avoidAccidentsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fire trucks, accident areas'**
  String get avoidAccidentsSubtitle;

  /// No description provided for @avoidRassemblementsTitle.
  ///
  /// In en, this message translates to:
  /// **'Avoid risky gatherings'**
  String get avoidRassemblementsTitle;

  /// No description provided for @avoidRassemblementsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Public gathering areas at risk'**
  String get avoidRassemblementsSubtitle;

  /// No description provided for @avoidAutresTitle.
  ///
  /// In en, this message translates to:
  /// **'Avoid \"other\" dangers'**
  String get avoidAutresTitle;

  /// No description provided for @avoidAutresSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Any other non-categorized report'**
  String get avoidAutresSubtitle;

  /// No description provided for @routeDestinationSection.
  ///
  /// In en, this message translates to:
  /// **'Destination Type'**
  String get routeDestinationSection;

  /// No description provided for @routeDestEventPointLabel.
  ///
  /// In en, this message translates to:
  /// **'Follow the current event point'**
  String get routeDestEventPointLabel;

  /// No description provided for @routeDestEventPointDescription.
  ///
  /// In en, this message translates to:
  /// **'Default destination of the active event'**
  String get routeDestEventPointDescription;

  /// No description provided for @routeDestSafeZoneLabel.
  ///
  /// In en, this message translates to:
  /// **'To the Safe Zone / Nearest care center'**
  String get routeDestSafeZoneLabel;

  /// No description provided for @routeDestSafeZoneDescription.
  ///
  /// In en, this message translates to:
  /// **'⭐ Absolute priority: nearest safety zone or street medic'**
  String get routeDestSafeZoneDescription;

  /// No description provided for @routeDestCareCenterLabel.
  ///
  /// In en, this message translates to:
  /// **'Nearest care center'**
  String get routeDestCareCenterLabel;

  /// No description provided for @routeDestCareCenterDescription.
  ///
  /// In en, this message translates to:
  /// **'Nearest street medics or street help'**
  String get routeDestCareCenterDescription;

  /// No description provided for @routeDestExitPointLabel.
  ///
  /// In en, this message translates to:
  /// **'Nearest exit point'**
  String get routeDestExitPointLabel;

  /// No description provided for @routeDestExitPointDescription.
  ///
  /// In en, this message translates to:
  /// **'Evacuation zone defined in the event JSON'**
  String get routeDestExitPointDescription;

  /// No description provided for @routeDestUserPointLabel.
  ///
  /// In en, this message translates to:
  /// **'User point'**
  String get routeDestUserPointLabel;

  /// No description provided for @routeDestUserPointDescription.
  ///
  /// In en, this message translates to:
  /// **'Custom point placed manually (3s long press)'**
  String get routeDestUserPointDescription;

  /// No description provided for @mapCacheTitle.
  ///
  /// In en, this message translates to:
  /// **'Map Tile Cache'**
  String get mapCacheTitle;

  /// No description provided for @mapCacheSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Maximum retention duration for local cache'**
  String get mapCacheSubtitle;

  /// No description provided for @mapCacheDescription.
  ///
  /// In en, this message translates to:
  /// **'Map tiles are kept locally to save mobile data.'**
  String get mapCacheDescription;

  /// No description provided for @mapCacheRetentionLabel.
  ///
  /// In en, this message translates to:
  /// **'Retention duration: '**
  String get mapCacheRetentionLabel;

  /// No description provided for @mapCacheForceUpdate.
  ///
  /// In en, this message translates to:
  /// **'Force map update'**
  String get mapCacheForceUpdate;

  /// No description provided for @mapCacheCleaned.
  ///
  /// In en, this message translates to:
  /// **'Map cache cleared. Tiles will be reloaded on next display.'**
  String get mapCacheCleaned;

  /// No description provided for @mapCacheDays.
  ///
  /// In en, this message translates to:
  /// **'days'**
  String get mapCacheDays;

  /// No description provided for @backgroundServiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Background Service'**
  String get backgroundServiceTitle;

  /// No description provided for @backgroundServiceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Persistent \"StreetPhare active\" notification'**
  String get backgroundServiceSubtitle;

  /// No description provided for @backgroundServiceDescription.
  ///
  /// In en, this message translates to:
  /// **'Allows StreetPhare to send alerts even when the application is in the background or asleep.'**
  String get backgroundServiceDescription;

  /// No description provided for @backgroundServiceEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable monitoring'**
  String get backgroundServiceEnable;

  /// No description provided for @panicContactsTitle.
  ///
  /// In en, this message translates to:
  /// **'Emergency Contacts (Panic)'**
  String get panicContactsTitle;

  /// No description provided for @panicContactsDescription.
  ///
  /// In en, this message translates to:
  /// **'These contacts will receive an alert SMS with your GPS position when you press PANIC.'**
  String get panicContactsDescription;

  /// No description provided for @panicContactsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add contact'**
  String get panicContactsAdd;

  /// No description provided for @panicContactsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No emergency contacts saved'**
  String get panicContactsEmpty;

  /// No description provided for @panicContactsConfigError.
  ///
  /// In en, this message translates to:
  /// **'No contacts configured.\nAdd at least one contact for the PANIC button.'**
  String get panicContactsConfigError;

  /// No description provided for @panicContactsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this contact?'**
  String get panicContactsDeleteTitle;

  /// No description provided for @panicContactsDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Will be removed from the list.'**
  String get panicContactsDeleteMessage;

  /// No description provided for @panicContactsEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit contact'**
  String get panicContactsEditTitle;

  /// No description provided for @panicContactsNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New contact'**
  String get panicContactsNewTitle;

  /// No description provided for @panicContactsFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get panicContactsFieldName;

  /// No description provided for @panicContactsFieldPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get panicContactsFieldPhone;

  /// No description provided for @panicContactsNameHint.
  ///
  /// In en, this message translates to:
  /// **'E.g. Mom, EMS 911'**
  String get panicContactsNameHint;

  /// No description provided for @panicContactsPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'+32 4 XX XX XX XX'**
  String get panicContactsPhoneHint;

  /// No description provided for @panicContactsNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name required'**
  String get panicContactsNameRequired;

  /// No description provided for @panicContactsPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Number required'**
  String get panicContactsPhoneRequired;

  /// No description provided for @panicContactsPhoneTooShort.
  ///
  /// In en, this message translates to:
  /// **'Number too short'**
  String get panicContactsPhoneTooShort;

  /// No description provided for @tutorialTitle.
  ///
  /// In en, this message translates to:
  /// **'App Guide'**
  String get tutorialTitle;

  /// No description provided for @tutorialButton.
  ///
  /// In en, this message translates to:
  /// **'View tutorial'**
  String get tutorialButton;

  /// No description provided for @tutorialDescription.
  ///
  /// In en, this message translates to:
  /// **'Consult StreetPhare features at any time.'**
  String get tutorialDescription;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'About StreetPhare'**
  String get aboutApp;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get aboutVersion;

  /// No description provided for @aboutPlatform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get aboutPlatform;

  /// No description provided for @aboutLicense.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get aboutLicense;

  /// No description provided for @aboutEncryption.
  ///
  /// In en, this message translates to:
  /// **'Encryption'**
  String get aboutEncryption;

  /// No description provided for @aboutOpenSource.
  ///
  /// In en, this message translates to:
  /// **'Citizen open-source project'**
  String get aboutOpenSource;

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'StreetPhare is a decentralized collaborative mapping application designed to strengthen collective safety during citizen gatherings. No personal data is collected or transmitted to third parties. All data remains local or passes through encrypted peer-to-peer relays.'**
  String get aboutDescription;

  /// No description provided for @bugReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Bug Report'**
  String get bugReportTitle;

  /// No description provided for @bugReportButton.
  ///
  /// In en, this message translates to:
  /// **'Report a bug'**
  String get bugReportButton;

  /// No description provided for @bugReportSuggest.
  ///
  /// In en, this message translates to:
  /// **'Suggest'**
  String get bugReportSuggest;

  /// No description provided for @bugReportDescription.
  ///
  /// In en, this message translates to:
  /// **'💡 This form sends a technical report to the StreetPhare administration server. Reports help developers identify and fix issues quickly.'**
  String get bugReportDescription;

  /// No description provided for @bugReportPrivacy.
  ///
  /// In en, this message translates to:
  /// **'🔒 No personal data is transmitted. Only the title, description, category, and app version are sent.'**
  String get bugReportPrivacy;

  /// No description provided for @bugReportSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Bug Reporting & Suggestions'**
  String get bugReportSectionTitle;

  /// No description provided for @bugReportSectionDescription.
  ///
  /// In en, this message translates to:
  /// **'Bug Button (bottom left of the map): report a bug or suggestion directly from the main interface without leaving the map.'**
  String get bugReportSectionDescription;

  /// No description provided for @eventsJoin.
  ///
  /// In en, this message translates to:
  /// **'Join an event'**
  String get eventsJoin;

  /// No description provided for @eventsNoEvent.
  ///
  /// In en, this message translates to:
  /// **'No active events at the moment'**
  String get eventsNoEvent;

  /// No description provided for @eventsQrScan.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get eventsQrScan;

  /// No description provided for @qrScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan a QR Code'**
  String get qrScanTitle;

  /// No description provided for @searchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search for a place, event…'**
  String get searchHint;

  /// No description provided for @searchNoResult.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get searchNoResult;

  /// No description provided for @routeTitle.
  ///
  /// In en, this message translates to:
  /// **'Route'**
  String get routeTitle;

  /// No description provided for @routeCalculate.
  ///
  /// In en, this message translates to:
  /// **'Calculate route'**
  String get routeCalculate;

  /// No description provided for @routeDestination.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get routeDestination;

  /// No description provided for @routeAvoidLiked.
  ///
  /// In en, this message translates to:
  /// **'Avoid reported danger zones'**
  String get routeAvoidLiked;

  /// No description provided for @routeAvoidPolice.
  ///
  /// In en, this message translates to:
  /// **'Avoid checkpoint areas'**
  String get routeAvoidPolice;

  /// No description provided for @routeAvoidCamera.
  ///
  /// In en, this message translates to:
  /// **'Avoid surveillance areas'**
  String get routeAvoidCamera;

  /// No description provided for @splashInitializing.
  ///
  /// In en, this message translates to:
  /// **'Initializing…'**
  String get splashInitializing;

  /// No description provided for @splashCheckingVersion.
  ///
  /// In en, this message translates to:
  /// **'Checking version…'**
  String get splashCheckingVersion;

  /// No description provided for @splashCheckingCache.
  ///
  /// In en, this message translates to:
  /// **'Checking local cache…'**
  String get splashCheckingCache;

  /// No description provided for @splashPurgingCache.
  ///
  /// In en, this message translates to:
  /// **'Cache expired, purging…'**
  String get splashPurgingCache;

  /// No description provided for @splashLoadingMap.
  ///
  /// In en, this message translates to:
  /// **'Loading local map…'**
  String get splashLoadingMap;

  /// No description provided for @splashCachingTiles.
  ///
  /// In en, this message translates to:
  /// **'Caching tiles…'**
  String get splashCachingTiles;

  /// No description provided for @splashReady.
  ///
  /// In en, this message translates to:
  /// **'Ready!'**
  String get splashReady;

  /// No description provided for @splashError.
  ///
  /// In en, this message translates to:
  /// **'Error:'**
  String get splashError;

  /// No description provided for @splashSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Real-time citizen mapping'**
  String get splashSubtitle;

  /// No description provided for @splashCheckingConnectivity.
  ///
  /// In en, this message translates to:
  /// **'Checking connectivity…'**
  String get splashCheckingConnectivity;

  /// No description provided for @panicButton.
  ///
  /// In en, this message translates to:
  /// **'PANIC'**
  String get panicButton;

  /// No description provided for @panicAlertSent.
  ///
  /// In en, this message translates to:
  /// **'PANIC alert sent'**
  String get panicAlertSent;

  /// No description provided for @onlineStatus.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get onlineStatus;

  /// No description provided for @offlineStatus.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offlineStatus;

  /// No description provided for @meshStatus.
  ///
  /// In en, this message translates to:
  /// **'Mesh'**
  String get meshStatus;

  /// No description provided for @relayStatus.
  ///
  /// In en, this message translates to:
  /// **'Relay'**
  String get relayStatus;

  /// No description provided for @connectedPeers.
  ///
  /// In en, this message translates to:
  /// **'Connected peers'**
  String get connectedPeers;

  /// No description provided for @proximityValidationTitle.
  ///
  /// In en, this message translates to:
  /// **'Proximity Validation'**
  String get proximityValidationTitle;

  /// No description provided for @proximityValidationCheck.
  ///
  /// In en, this message translates to:
  /// **'Check proximity'**
  String get proximityValidationCheck;

  /// No description provided for @proximityValid.
  ///
  /// In en, this message translates to:
  /// **'Proximity validated'**
  String get proximityValid;

  /// No description provided for @proximityInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid proximity'**
  String get proximityInvalid;

  /// No description provided for @geofenceEntered.
  ///
  /// In en, this message translates to:
  /// **'Event zone entered'**
  String get geofenceEntered;

  /// No description provided for @geofenceExited.
  ///
  /// In en, this message translates to:
  /// **'Event zone exited'**
  String get geofenceExited;

  /// No description provided for @dangerReported.
  ///
  /// In en, this message translates to:
  /// **'Danger reported'**
  String get dangerReported;

  /// No description provided for @dangerConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Danger confirmed (≥3 votes)'**
  String get dangerConfirmed;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'An error occurred'**
  String get errorGeneric;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @noInternet.
  ///
  /// In en, this message translates to:
  /// **'No internet connection'**
  String get noInternet;

  /// No description provided for @locationAccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Location Access'**
  String get locationAccessTitle;

  /// No description provided for @locationAccessMessage.
  ///
  /// In en, this message translates to:
  /// **'StreetPhare needs access to your location to display the map and nearby alerts.'**
  String get locationAccessMessage;

  /// No description provided for @locationAccessButton.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get locationAccessButton;

  /// No description provided for @notificationPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationPermissionTitle;

  /// No description provided for @notificationPermissionMessage.
  ///
  /// In en, this message translates to:
  /// **'StreetPhare needs to send notifications for alerts and events.'**
  String get notificationPermissionMessage;

  /// No description provided for @notificationPermissionButton.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get notificationPermissionButton;

  /// No description provided for @androidChannelAlertsTitle.
  ///
  /// In en, this message translates to:
  /// **'Field alerts'**
  String get androidChannelAlertsTitle;

  /// No description provided for @androidChannelAlertsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Blockades, kettling, tension zones'**
  String get androidChannelAlertsSubtitle;

  /// No description provided for @androidChannelEventsTitle.
  ///
  /// In en, this message translates to:
  /// **'Events & Trips'**
  String get androidChannelEventsTitle;

  /// No description provided for @androidChannelEventsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Trip start, waypoints, end of demo'**
  String get androidChannelEventsSubtitle;

  /// No description provided for @androidChannelPanicTitle.
  ///
  /// In en, this message translates to:
  /// **'Collective Panic alerts'**
  String get androidChannelPanicTitle;

  /// No description provided for @androidChannelPanicSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Multi-device panic triggering'**
  String get androidChannelPanicSubtitle;

  /// No description provided for @androidChannelMessagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Hive P2P Messages'**
  String get androidChannelMessagesTitle;

  /// No description provided for @androidChannelMessagesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'New messages on the local network'**
  String get androidChannelMessagesSubtitle;

  /// No description provided for @androidChannelSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Android Notifications by Channel'**
  String get androidChannelSectionTitle;

  /// No description provided for @androidChannelManageSystem.
  ///
  /// In en, this message translates to:
  /// **'Manage in Android Settings'**
  String get androidChannelManageSystem;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['de', 'en', 'fr', 'nl'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de': return AppLocalizationsDe();
    case 'en': return AppLocalizationsEn();
    case 'fr': return AppLocalizationsFr();
    case 'nl': return AppLocalizationsNl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
