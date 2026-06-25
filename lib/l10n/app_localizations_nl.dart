// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class AppLocalizationsNl extends AppLocalizations {
  AppLocalizationsNl([String locale = 'nl']) : super(locale);

  @override
  String get appTitle => 'StreetPhare';

  @override
  String get settingsTitle => 'Instellingen';

  @override
  String get mapTitle => 'Kaart';

  @override
  String get eventsTitle => 'Evenementen';

  @override
  String get messagingTitle => 'Berichten';

  @override
  String get startScreenWelcome => 'Welkom bij StreetPhare';

  @override
  String get startScreenSubtitle => 'Gedecentraliseerde burgerkartering';

  @override
  String get startScreenSelectLanguage => 'Kies uw taal';

  @override
  String get startScreenButton => 'Beginnen';

  @override
  String get languageLabel => 'Nederlands';

  @override
  String get languageSectionTitle => 'Taalkeuze';

  @override
  String get languageSectionDescription =>
      'Wijzig de taal van de applicatie in realtime.';

  @override
  String get themeSectionTitle => 'Applicatie thema';

  @override
  String get themeDescription =>
      'De donkere modus is geoptimaliseerd voor OLED-schermen en blijft \'s nachts discreet.';

  @override
  String get themeSystem => 'Systeem';

  @override
  String get themeSystemSubtitle => 'Volgt systeeminstelling';

  @override
  String get themeLight => 'Licht';

  @override
  String get themeLightSubtitle => 'Lichte achtergrond, daglichtlezen';

  @override
  String get themeDark => 'Donker';

  @override
  String get themeDarkSubtitle => 'Echt OLED-zwart, batterijbesparing';

  @override
  String get batterySaverTitle => 'Energiebesparing';

  @override
  String get batterySaverDescription =>
      'Vermindert de frequentie van GPS/BLE-scans en verlengt de levensduur van de batterij.';

  @override
  String get batterySaverSubtitle =>
      'Vermindert GPS- en BLE-frequentie om batterij te sparen';

  @override
  String get batterySaverEnabledLabel => 'Energiebesparing ingeschakeld';

  @override
  String get batterySaverDisabledLabel => 'Energiebesparing uitgeschakeld';

  @override
  String get batterySaverStatusEnabled =>
      'Verminderde scans, kaart onderbroken';

  @override
  String get batterySaverStatusDisabled => 'Normale werking';

  @override
  String get backgroundAlertsTitle => 'Achtergrondmeldingen';

  @override
  String get notificationFilterTitle => 'Notificatiefilter';

  @override
  String get notificationFilterAllLabel => 'Alle meldingen';

  @override
  String get notificationFilterAllDescription =>
      'Meldt elk micro-evenement op het netwerk';

  @override
  String get notificationFilterNearbyLabel =>
      'Alleen bevestigde gevaren in de buurt';

  @override
  String get notificationFilterNearbyDescription =>
      'Filter: gevaar ≥3 stemmen gedetecteerd binnen 100 m';

  @override
  String get notificationFilterEventsLabel =>
      'Aankomende evenementpuntwijzigingen';

  @override
  String get notificationFilterEventsDescription =>
      'Meldt als het volgende punt binnen <3 min wordt onthuld';

  @override
  String get lowVisionTitle => 'Slechtziendheidmodus';

  @override
  String get lowVisionSubtitle =>
      'Grote tekst en aangepaste interface voor betere leesbaarheid';

  @override
  String get lowVisionDescription =>
      'Schakelt zeer grote karakters in, verwijdert de StreetPhare-titel op de kaart en reorganiseert het signaleringsmenu in 2 kolommen (grote aanraakknoppen). Automatisch ingeschakeld als TalkBack/VoiceOver wordt gedetecteerd.';

  @override
  String get lowVisionEnabled => 'Slechtziendheidmodus ingeschakeld';

  @override
  String get lowVisionDisabled => 'Slechtziendheidmodus uitgeschakeld';

  @override
  String get lowVisionStatusEnabled =>
      'Grote karakters, 2 kolommen signalering';

  @override
  String get lowVisionStatusDisabled => 'Standaard interface';

  @override
  String get messageFilterTitle => 'Berichtenfilter';

  @override
  String get messageFilterDescription =>
      'Filter berichten ontvangen op het gedecentraliseerde netwerk.';

  @override
  String get messageFilterAllLabel => 'Alle berichten';

  @override
  String get messageFilterAllDescription =>
      'Ontvangt alle berichten die op het netwerk worden uitgezonden';

  @override
  String get messageFilterNearbyLabel => 'Alleen berichten in de buurt';

  @override
  String get messageFilterNearbyDescription =>
      'Berichten verzonden binnen een straal van 300 m';

  @override
  String get messageFilterAdminLabel => 'Evenementbeheerders';

  @override
  String get messageFilterAdminDescription =>
      'Berichten ondertekend door een evenementbeheerder';

  @override
  String get messageFilterAlertLabel => 'Alleen alarmmeldingen';

  @override
  String get messageFilterAlertDescription =>
      'Alleen kritieke waarschuwingen (type ALERT)';

  @override
  String get avoidanceFiltersTitle => 'Vermijdingsfilters (Veilige Route)';

  @override
  String get avoidanceFiltersDescription =>
      'Vink de soorten gevaren aan die u absoluut wilt vermijden. De routeplanner zal deze gebieden omzeilen.';

  @override
  String get avoidBarragesTitle => 'Vermijd blokkades';

  @override
  String get avoidBarragesSubtitle => 'Filterende of harde blokkades';

  @override
  String get avoidNassesTitle => 'Vermijd omsingeling';

  @override
  String get avoidNassesSubtitle => 'Vallen, omsingelde gebieden';

  @override
  String get avoidControlesTitle => 'Vermijd politiecontroles';

  @override
  String get avoidControlesSubtitle => 'Filtering, identiteitscontroles';

  @override
  String get avoidAccidentsTitle => 'Vermijd ongelukken / waterkanonnen';

  @override
  String get avoidAccidentsSubtitle => 'Brandweerwagens, ongevalgebieden';

  @override
  String get avoidRassemblementsTitle => 'Vermijd riskante bijeenkomsten';

  @override
  String get avoidRassemblementsSubtitle =>
      'Publieke verzamelplaatsen met risico';

  @override
  String get avoidAutresTitle => 'Vermijd « andere » gevaren';

  @override
  String get avoidAutresSubtitle => 'Elke andere niet-gecategoriseerde melding';

  @override
  String get routeDestinationSection => 'Bestemmingstype';

  @override
  String get routeDestEventPointLabel => 'Volg het huidige evenementpunt';

  @override
  String get routeDestEventPointDescription =>
      'Standaardbestemming van het actieve evenement';

  @override
  String get routeDestSafeZoneLabel =>
      'Naar de Veilige Zone / Dichtstbijzijnde zorgcentrum';

  @override
  String get routeDestSafeZoneDescription =>
      '⭐ Absolute prioriteit: dichtstbijzijnde veiligheidszone of street medic';

  @override
  String get routeDestCareCenterLabel => 'Dichtstbijzijnde zorgcentrum';

  @override
  String get routeDestCareCenterDescription =>
      'Dichtstbijzijnde street medics of straathulp';

  @override
  String get routeDestExitPointLabel => 'Dichtstbijzijnde uitgangspunt';

  @override
  String get routeDestExitPointDescription =>
      'Evacuatiezone gedefinieerd in het evenement JSON';

  @override
  String get routeDestUserPointLabel => 'Gebruikerspunt';

  @override
  String get routeDestUserPointDescription =>
      'Aangepast punt handmatig geplaatst (3s lang indrukken)';

  @override
  String get mapCacheTitle => 'Kaarttegelcache';

  @override
  String get mapCacheSubtitle => 'Maximale bewaartijd voor lokale cache';

  @override
  String get mapCacheDescription =>
      'Kaarttegels worden lokaal bewaard om mobiele data te besparen.';

  @override
  String get mapCacheRetentionLabel => 'Bewaartijd: ';

  @override
  String get mapCacheForceUpdate => 'Forceer kaartupdate';

  @override
  String get mapCacheCleaned =>
      'Kaartcache gewist. Tegels worden bij de volgende weergave opnieuw geladen.';

  @override
  String get mapCacheDays => 'dagen';

  @override
  String get backgroundServiceTitle => 'Achtergrondservice';

  @override
  String get backgroundServiceSubtitle =>
      'Blijvende melding \"StreetPhare actief\"';

  @override
  String get backgroundServiceDescription =>
      'Stelt StreetPhare in staat om meldingen te sturen, zelfs als de applicatie op de achtergrond draait of in slaapstand is.';

  @override
  String get backgroundServiceEnable => 'Surveillance inschakelen';

  @override
  String get panicContactsTitle => 'Noodcontacten (Panic)';

  @override
  String get panicContactsDescription =>
      'Deze contacten ontvangen een alarm-sms met uw GPS-positie wanneer u op PANIC drukt.';

  @override
  String get panicContactsAdd => 'Contact toevoegen';

  @override
  String get panicContactsEmpty => 'Geen noodcontacten opgeslagen';

  @override
  String get panicContactsConfigError =>
      'Geen contacten geconfigureerd.\nVoeg minimaal één contact toe voor de PANIC-knop.';

  @override
  String get panicContactsDeleteTitle => 'Dit contact verwijderen?';

  @override
  String get panicContactsDeleteMessage =>
      'Zal uit de lijst worden verwijderd.';

  @override
  String get panicContactsEditTitle => 'Contact bewerken';

  @override
  String get panicContactsNewTitle => 'Nieuw contact';

  @override
  String get panicContactsFieldName => 'Naam';

  @override
  String get panicContactsFieldPhone => 'Telefoon';

  @override
  String get panicContactsNameHint => 'Bijv. Mama, 112';

  @override
  String get panicContactsPhoneHint => '+32 4 XX XX XX XX';

  @override
  String get panicContactsNameRequired => 'Naam vereist';

  @override
  String get panicContactsPhoneRequired => 'Nummer vereist';

  @override
  String get panicContactsPhoneTooShort => 'Nummer te kort';

  @override
  String get tutorialTitle => 'App-gids';

  @override
  String get tutorialButton => 'Bekijk handleiding';

  @override
  String get tutorialDescription =>
      'Raadpleeg StreetPhare-functies op elk moment.';

  @override
  String get aboutTitle => 'Over';

  @override
  String get aboutApp => 'Over StreetPhare';

  @override
  String get aboutVersion => 'Versie';

  @override
  String get aboutPlatform => 'Platform';

  @override
  String get aboutLicense => 'Licentie';

  @override
  String get aboutEncryption => 'Versleuteling';

  @override
  String get aboutOpenSource => 'Burgerlijk open-source project';

  @override
  String get aboutDescription =>
      'StreetPhare is een gedecentraliseerde collaboratieve karteringsapplicatie ontworpen om de collectieve veiligheid te versterken tijdens burgerbijeenkomsten. Er worden geen persoonlijke gegevens verzameld of doorgegeven aan derden. Alle gegevens blijven lokaal of gaan via versleutelde peer-to-peer relais.';

  @override
  String get bugReportTitle => 'Bugrapport';

  @override
  String get bugReportButton => 'Meld een bug';

  @override
  String get bugReportSuggest => 'Stel voor';

  @override
  String get bugReportDescription =>
      '💡 Dit formulier stuurt een technisch rapport naar de StreetPhare-beheerserver. Rapporten helpen ontwikkelaars problemen snel te identificeren en op te lossen.';

  @override
  String get bugReportPrivacy =>
      '🔒 Er worden geen persoonlijke gegevens verzonden. Alleen de titel, beschrijving, categorie en app-versie worden verzonden.';

  @override
  String get bugReportSectionTitle => 'Bugrapportage & Suggesties';

  @override
  String get bugReportSectionDescription =>
      'Bug-knop (linksonder op de kaart): meld een bug of suggestie direct vanuit de hoofdinterface zonder de kaart te verlaten.';

  @override
  String get eventsJoin => 'Word lid van een evenement';

  @override
  String get eventsNoEvent => 'Momenteel geen actieve evenementen';

  @override
  String get eventsMyEvents => 'Mijn evenementen';

  @override
  String get eventsEmptyTitle => 'Geen evenement geladen';

  @override
  String get eventsEmptySubtitle =>
      'Voer een uitnodigingscode in of scan een QR-code om deel te nemen aan maximaal 3 evenementen tegelijk.';

  @override
  String get eventsJoinTitle => 'Word lid van een evenement';

  @override
  String get eventsJoinSubtitle =>
      'Voer de uitnodigingscode in (bijv. MANIF-123) of scan een QR-code.';

  @override
  String get eventsSecurityTitle => 'Just-in-time beveiliging';

  @override
  String get eventsSecurityDescription =>
      'Om te voorkomen dat een evenementroute van tevoren wordt gekaapt, onthult StreetPhare de route pas op het door de organisatoren ingestelde tijdstip.\n\nBovendien verdwijnt elke stap (verzamelpunt) automatisch van de kaart zodra de tijd met 5 minuten is overschreden, of als u zich binnen 30 m van dat punt bevindt.';

  @override
  String get eventsEnterCodeError => 'Voer een uitnodigingscode in.';

  @override
  String get eventsMaxReachedError =>
      'Maximaal 3 gelijktijdige evenementen. Verwijder er een voordat u een nieuwe toevoegt.';

  @override
  String get eventsUnknownCodeError =>
      'Onbekende code of evenement niet gevonden.';

  @override
  String get eventsFleurusCodes =>
      'Fleurus-codes: FLEURUS-TOUR, FLEURUS-ECOLES, FLEURUS-CORTEGE.';

  @override
  String get eventsQrMaxReached =>
      'Maximaal 3 gelijktijdige evenementen. Verwijder er eerst een.';

  @override
  String get eventsQrAddError =>
      'Kan het evenement niet toevoegen (al aanwezig of limiet van 3 evenementen bereikt).';

  @override
  String get eventsQrAddSuccess => 'Evenement toegevoegd van QR-code!';

  @override
  String get eventsRemoved => 'Evenement verwijderd.';

  @override
  String get eventsLoadButton => 'Laden';

  @override
  String get eventsRemoveTooltip => 'Evenement verwijderen';

  @override
  String get eventsCodeLabel => 'Code';

  @override
  String get eventsStartLabel => 'Start';

  @override
  String get eventsRouteHidden => 'Route verborgen — onthulling in:';

  @override
  String eventsStepActive(int index, int total) {
    return 'Stap $index/$total actief:';
  }

  @override
  String get eventsStepTime => 'Geplande tijd:';

  @override
  String get eventsRouteVisible =>
      'Route zichtbaar — alle stappen voltooid of evenement zonder stappen.';

  @override
  String get mapRecenterTooltip => 'Kaart opnieuw centreren';

  @override
  String get mapLoadingTiles => 'Kaart laden…';

  @override
  String get mapGpsOff => 'GPS-service uitgeschakeld';

  @override
  String get mapGpsDenied => 'GPS-toestemming geweigerd';

  @override
  String get mapGpsDeniedForever => 'GPS-toestemming permanent geweigerd';

  @override
  String get mapGpsError => 'GPS-fout:';

  @override
  String get mapUserPointDefined =>
      'Gebruikerspunt gedefinieerd — Veilige Route gestart…';

  @override
  String get mapDestinationEvent => 'Evenementpunt';

  @override
  String get mapDestinationSafeZone => 'Veilige Zone';

  @override
  String get mapDestinationCareCenter => 'Zorgcentrum';

  @override
  String get mapDestinationExit => 'Uitgang';

  @override
  String get mapDestinationUserPoint => 'Gebruikerspunt';

  @override
  String mapRouteSafeCalculating(String label) {
    return 'Bereken Veilige Route naar $label…';
  }

  @override
  String mapRouteSafeFailover(String label) {
    return 'Uitwijk naar $label…';
  }

  @override
  String get mapNoDestinationError =>
      'Geen bestemming beschikbaar. Word lid van een evenement of plaats een punt handmatig (3s lang indrukken op de kaart).';

  @override
  String get mapAddEventButton => 'Evenement toevoegen';

  @override
  String get mapAddEventWarning =>
      'Voeg een evenement toe voordat u de tracking start.';

  @override
  String get mapCollectivePanicTitle => 'Collectieve Paniekwaarschuwing';

  @override
  String mapCollectivePanicMessage(int count) {
    return '⚠️ $count apparaten in de buurt hebben tegelijkertijd een Paniek-alarm geactiveerd.\n\nEen punt \"Hoge Spanning\" is automatisch aangemaakt op het geografische centrum van deze signalen.\n\nBlijf waakzaam en raadpleeg de kaart.';
  }

  @override
  String get mapViewOnMap => 'Bekijk op kaart';

  @override
  String get mapIgnore => 'Negeren';

  @override
  String get mapNoPanicContactTitle => 'Geen noodcontacten';

  @override
  String get mapNoPanicContactMessage =>
      'U moet eerst ten minste één contact configureren in Instellingen om de PANIEK-knop te gebruiken.';

  @override
  String get mapOpenSettings => 'Instellingen openen';

  @override
  String get mapPanicModeTitle => 'Paniekmodus';

  @override
  String mapPanicModeMessage(int count, String list) {
    return 'Het activeren van de paniekmodus stuurt een alarm-sms met uw GPS-positie naar $count contact(en):\n\n$list\n\nDoorgaan?';
  }

  @override
  String get mapPanicModeActivate => 'ACTIVEREN';

  @override
  String get mapPanicSmsPreparedTitle => 'SMS voorbereid';

  @override
  String mapPanicSmsPreparedMessage(String message) {
    return 'Kan SMS-app niet automatisch openen.\nHet bericht is naar het klembord gekopieerd:\n\n$message';
  }

  @override
  String get mapPanicAlertReadyTitle => 'Alarm gereed';

  @override
  String mapPanicAlertReadyMessage(int count) {
    return 'Er wordt een nood-sms verzonden naar $count contact(en) met uw GPS-positie.';
  }

  @override
  String mapPanicMessageBody(String stamp, String coords) {
    return '[STREETPHARE] Noodalarm verzonden op $stamp UTC.\nPositie: $coords\nNeem contact met mij op of waarschuw de hulpdiensten.';
  }

  @override
  String get mapPanicNoGps => 'GPS-positie niet beschikbaar';

  @override
  String get mapDestinationObjective => 'Doel van de Veilige Route';

  @override
  String get mapDestinationLongPressHint =>
      '3s lang indrukken op kaart → \"Gebruikerspunt\"';

  @override
  String get mapActiveEvent => 'Actief evenement';

  @override
  String get mapPeersNearby => 'Apparaten in de buurt';

  @override
  String get mapIsolatedTitle => 'StreetPhare-netwerk niet beschikbaar';

  @override
  String get mapIsolatedMessage =>
      'De applicatie kan momenteel niet werken vanwege gebrek aan serververbinding of peers (Hive) in de buurt.';

  @override
  String get eventsQrScan => 'Scan QR-code';

  @override
  String get qrScanTitle => 'Scan een QR-code';

  @override
  String get searchTitle => 'Zoeken';

  @override
  String get searchHint => 'Zoek naar een plaats, evenement…';

  @override
  String get searchNoResult => 'Geen resultaten gevonden';

  @override
  String get routeTitle => 'Route';

  @override
  String get routeCalculate => 'Bereken route';

  @override
  String get routeDestination => 'Bestemming';

  @override
  String get routeAvoidLiked => 'Vermijd gemelde gevarenzones';

  @override
  String get routeAvoidPolice => 'Vermijd controleposten';

  @override
  String get routeAvoidCamera => 'Vermijd bewakingszones';

  @override
  String get splashInitializing => 'Initialiseren…';

  @override
  String get splashCheckingVersion => 'Versie controleren…';

  @override
  String get splashCheckingCache => 'Lokale cache controleren…';

  @override
  String get splashPurgingCache => 'Cache verlopen, opschonen…';

  @override
  String get splashLoadingMap => 'Lokale kaart laden…';

  @override
  String get splashCachingTiles => 'Tegels cachen…';

  @override
  String get splashReady => 'Klaar!';

  @override
  String get splashError => 'Fout:';

  @override
  String get splashSubtitle => 'Real-time burgerkartering';

  @override
  String get splashCheckingConnectivity => 'Connectiviteit controleren…';

  @override
  String get panicButton => 'PANIEK';

  @override
  String get panicAlertSent => 'PANIEK-melding verzonden';

  @override
  String get onlineStatus => 'Online';

  @override
  String get offlineStatus => 'Offline';

  @override
  String get meshStatus => 'Mesh';

  @override
  String get relayStatus => 'Relais';

  @override
  String get connectedPeers => 'Verbonden peers';

  @override
  String get proximityValidationTitle => 'Nabijheidsvalidatie';

  @override
  String get proximityValidationCheck => 'Controleer nabijheid';

  @override
  String get proximityValid => 'Nabijheid gevalideerd';

  @override
  String get proximityInvalid => 'Ongeldige nabijheid';

  @override
  String get geofenceEntered => 'Evenementzone betreden';

  @override
  String get geofenceExited => 'Evenementzone verlaten';

  @override
  String get dangerReported => 'Gevaar gemeld';

  @override
  String get dangerConfirmed => 'Gevaar bevestigd (≥3 stemmen)';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Annuleren';

  @override
  String get save => 'Opslaan';

  @override
  String get delete => 'Verwijderen';

  @override
  String get confirm => 'Bevestigen';

  @override
  String get close => 'Sluiten';

  @override
  String get back => 'Terug';

  @override
  String get next => 'Volgende';

  @override
  String get done => 'Gereed';

  @override
  String get errorGeneric => 'Er is een fout opgetreden';

  @override
  String get loading => 'Laden…';

  @override
  String get retry => 'Opnieuw';

  @override
  String get noInternet => 'Geen internetverbinding';

  @override
  String get locationAccessTitle => 'Locatietoegang';

  @override
  String get locationAccessMessage =>
      'StreetPhare heeft toegang tot uw locatie nodig om de kaart en meldingen in de buurt weer te geven.';

  @override
  String get locationAccessButton => 'Toestaan';

  @override
  String get notificationPermissionTitle => 'Meldingen';

  @override
  String get notificationPermissionMessage =>
      'StreetPhare moet meldingen kunnen sturen voor waarschuwingen en evenementen.';

  @override
  String get notificationPermissionButton => 'Toestaan';

  @override
  String get androidChannelAlertsTitle => 'Terreinwaarschuwingen';

  @override
  String get androidChannelAlertsSubtitle =>
      'Blokkades, omsingelingen, spanningszones';

  @override
  String get androidChannelEventsTitle => 'Evenementen & Ritten';

  @override
  String get androidChannelEventsSubtitle =>
      'Start van de rit, waypoints, einde van de demo';

  @override
  String get androidChannelPanicTitle => 'Collectieve Paniekmeldingen';

  @override
  String get androidChannelPanicSubtitle => 'Multi-device paniekactivering';

  @override
  String get androidChannelMessagesTitle => 'Hive P2P-berichten';

  @override
  String get androidChannelMessagesSubtitle =>
      'Nuwe berichten op het lokale netwerk';

  @override
  String get androidChannelSectionTitle => 'Android-meldingen per kanaal';

  @override
  String get androidChannelManageSystem => 'Beheren in Android-instellingen';
}
