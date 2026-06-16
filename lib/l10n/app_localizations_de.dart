// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'StreetPhare';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get mapTitle => 'Karte';

  @override
  String get eventsTitle => 'Veranstaltungen';

  @override
  String get messagingTitle => 'Nachrichten';

  @override
  String get startScreenWelcome => 'Willkommen bei StreetPhare';

  @override
  String get startScreenSubtitle => 'Dezentrale Bürgerkartierung';

  @override
  String get startScreenSelectLanguage => 'Wählen Sie Ihre Sprache';

  @override
  String get startScreenButton => 'Loslegen';

  @override
  String get languageLabel => 'Deutsch';

  @override
  String get languageSectionTitle => 'Sprachauswahl';

  @override
  String get languageSectionDescription => 'Ändern Sie die Anwendungssprache in Echtzeit.';

  @override
  String get themeSectionTitle => 'App-Design';

  @override
  String get themeDescription => 'Der Dunkelmodus ist für OLED-Bildschirme optimiert und bleibt nachts diskret.';

  @override
  String get themeSystem => 'System';

  @override
  String get themeSystemSubtitle => 'Folgt der Systemeinstellung';

  @override
  String get themeLight => 'Hell';

  @override
  String get themeLightSubtitle => 'Heller Hintergrund, Taglesen';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get themeDarkSubtitle => 'Echtes OLED-Schwarz, Batteriesparmodus';

  @override
  String get batterySaverTitle => 'Energiesparmodus';

  @override
  String get batterySaverDescription => 'Reduziert die GPS/BLE-Scanfrequenz und verlängert die Akkulaufzeit.';

  @override
  String get batterySaverSubtitle => 'Reduziert GPS- und BLE-Frequenz zum Batteriesparen';

  @override
  String get batterySaverEnabledLabel => 'Energiesparmodus aktiviert';

  @override
  String get batterySaverDisabledLabel => 'Energiesparmodus deaktiviert';

  @override
  String get batterySaverStatusEnabled => 'Reduzierte Scans, Karte angehalten';

  @override
  String get batterySaverStatusDisabled => 'Normalbetrieb';

  @override
  String get backgroundAlertsTitle => 'Hintergrundwarnungen';

  @override
  String get notificationFilterTitle => 'Benachrichtigungsfilter';

  @override
  String get notificationFilterAllLabel => 'Alle Warnungen';

  @override
  String get notificationFilterAllDescription => 'Benachrichtigt über jedes Mikro-Ereignis im Netzwerk';

  @override
  String get notificationFilterNearbyLabel => 'Nur bestätigte Gefahren in der Nähe';

  @override
  String get notificationFilterNearbyDescription => 'Filter: Gefahr ≥3 Stimmen in 100 m Umkreis erkannt';

  @override
  String get notificationFilterEventsLabel => 'Bevorstehende Ereignispunktänderungen';

  @override
  String get notificationFilterEventsDescription => 'Benachrichtigt, wenn der nächste Punkt in <3 Min. enthüllt wird';

  @override
  String get lowVisionTitle => 'Sehbehindertenmodus';

  @override
  String get lowVisionSubtitle => 'Großer Text und angepasste Oberfläche für bessere Lesbarkeit';

  @override
  String get lowVisionDescription => 'Aktiviert sehr große Zeichen, entfernt den StreetPhare-Titel auf der Karte und reorganisiert das Melde-Menü in 2 Spalten (große Touch-Buttons). Wird automatisch aktiviert, wenn TalkBack/VoiceOver erkannt wird.';

  @override
  String get lowVisionEnabled => 'Sehbehindertenmodus aktiviert';

  @override
  String get lowVisionDisabled => 'Sehbehindertenmodus deaktiviert';

  @override
  String get lowVisionStatusEnabled => 'Große Zeichen, 2-Spalten-Meldung';

  @override
  String get lowVisionStatusDisabled => 'Standardoberfläche';

  @override
  String get messageFilterTitle => 'Nachrichtenfilter';

  @override
  String get messageFilterDescription => 'Filtern Sie Nachrichten, die über das dezentrale Netzwerk empfangen wurden.';

  @override
  String get messageFilterAllLabel => 'Alle Nachrichten';

  @override
  String get messageFilterAllDescription => 'Empfängt alle im Netzwerk verbreiteten Nachrichten';

  @override
  String get messageFilterNearbyLabel => 'Nur Nachrichten in der Nähe';

  @override
  String get messageFilterNearbyDescription => 'Nachrichten, die im Umkreis von 300 m gesendet wurden';

  @override
  String get messageFilterAdminLabel => 'Veranstaltungsadministratoren';

  @override
  String get messageFilterAdminDescription => 'Nachrichten, die von einem Veranstaltungsadministrator signiert wurden';

  @override
  String get messageFilterAlertLabel => 'Nur Alarmmeldungen';

  @override
  String get messageFilterAlertDescription => 'Nur kritische Warnungen (Typ ALERT)';

  @override
  String get avoidanceFiltersTitle => 'Vermeidungsfilter (Sichere Route)';

  @override
  String get avoidanceFiltersDescription => 'Wählen Sie die Gefahrenarten aus, die unbedingt vermieden werden sollen. Die Routing-Engine wird diese Bereiche umgehen.';

  @override
  String get avoidBarragesTitle => 'Blockaden vermeiden';

  @override
  String get avoidBarragesSubtitle => 'Filternde oder harte Blockaden';

  @override
  String get avoidNassesTitle => 'Einkesselung vermeiden';

  @override
  String get avoidNassesSubtitle => 'Fallen, umzingelte Bereiche';

  @override
  String get avoidControlesTitle => 'Polizeikontrollen vermeiden';

  @override
  String get avoidControlesSubtitle => 'Filterung, Identitätskontrollen';

  @override
  String get avoidAccidentsTitle => 'Unfälle / Wasserwerfer vermeiden';

  @override
  String get avoidAccidentsSubtitle => 'Feuerwehrwagen, Unfallbereiche';

  @override
  String get avoidRassemblementsTitle => 'Riskante Versammlungen vermeiden';

  @override
  String get avoidRassemblementsSubtitle => 'Öffentliche Versammlungsbereiche mit Risiko';

  @override
  String get avoidAutresTitle => '« Andere » Gefahren vermeiden';

  @override
  String get avoidAutresSubtitle => 'Alle anderen nicht kategorisierten Meldungen';

  @override
  String get routeDestinationSection => 'Zieltyp';

  @override
  String get routeDestEventPointLabel => 'Dem aktuellen Ereignispunkt folgen';

  @override
  String get routeDestEventPointDescription => 'Standardziel der aktiven Veranstaltung';

  @override
  String get routeDestSafeZoneLabel => 'Zur Safe Zone / Nächstgelegenes Versorgungszentrum';

  @override
  String get routeDestSafeZoneDescription => '⭐ Absolute Priorität: nächste Sicherheitszone oder Street Medic';

  @override
  String get routeDestCareCenterLabel => 'Nächstgelegenes Versorgungszentrum';

  @override
  String get routeDestCareCenterDescription => 'Nächstgelegene Street Medics oder Hilfe auf der Straße';

  @override
  String get routeDestExitPointLabel => 'Nächstgelegener Ausgangspunkt';

  @override
  String get routeDestExitPointDescription => 'Evakuierungszone, definiert im Ereignis-JSON';

  @override
  String get routeDestUserPointLabel => 'Benutzerpunkt';

  @override
  String get routeDestUserPointDescription => 'Benutzerdefinierter Punkt, manuell platziert (3 Sek. langes Drücken)';

  @override
  String get mapCacheTitle => 'Kartenkachel-Cache';

  @override
  String get mapCacheSubtitle => 'Maximale Aufbewahrungsdauer für lokalen Cache';

  @override
  String get mapCacheDescription => 'Kartenkacheln werden lokal gespeichert, um mobile Daten zu sparen.';

  @override
  String get mapCacheRetentionLabel => 'Aufbewahrungsdauer: ';

  @override
  String get mapCacheForceUpdate => 'Kartenaktualisierung erzwingen';

  @override
  String get mapCacheCleaned => 'Karten-Cache geleert. Kacheln werden bei der nächsten Anzeige neu geladen.';

  @override
  String get mapCacheDays => 'Tage';

  @override
  String get backgroundServiceTitle => 'Hintergrunddienst';

  @override
  String get backgroundServiceSubtitle => 'Dauerhafte Benachrichtigung \"StreetPhare aktiv\"';

  @override
  String get backgroundServiceDescription => 'Ermöglicht StreetPhare das Senden von Warnungen, auch wenn die Anwendung im Hintergrund läuft oder im Ruhezustand ist.';

  @override
  String get backgroundServiceEnable => 'Überwachung aktivieren';

  @override
  String get panicContactsTitle => 'Notfallkontakte (Panik)';

  @override
  String get panicContactsDescription => 'Diese Kontakte erhalten eine Alarm-SMS mit Ihrer GPS-Position, wenn Sie PANIK drücken.';

  @override
  String get panicContactsAdd => 'Kontakt hinzufügen';

  @override
  String get panicContactsEmpty => 'Keine Notfallkontakte gespeichert';

  @override
  String get panicContactsConfigError => 'Keine Kontakte konfiguriert.\nFügen Sie mindestens einen Kontakt für den PANIK-Button hinzu.';

  @override
  String get panicContactsDeleteTitle => 'Diesen Kontakt löschen?';

  @override
  String get panicContactsDeleteMessage => 'Wird aus der Liste entfernt.';

  @override
  String get panicContactsEditTitle => 'Kontakt bearbeiten';

  @override
  String get panicContactsNewTitle => 'Neuer Kontakt';

  @override
  String get panicContactsFieldName => 'Name';

  @override
  String get panicContactsFieldPhone => 'Telefon';

  @override
  String get panicContactsNameHint => 'Z. B. Mama, Rettungsdienst 112';

  @override
  String get panicContactsPhoneHint => '+32 4 XX XX XX XX';

  @override
  String get panicContactsNameRequired => 'Name erforderlich';

  @override
  String get panicContactsPhoneRequired => 'Nummer erforderlich';

  @override
  String get panicContactsPhoneTooShort => 'Nummer zu kurz';

  @override
  String get tutorialTitle => 'App-Anleitung';

  @override
  String get tutorialButton => 'Tutorial ansehen';

  @override
  String get tutorialDescription => 'Konsultieren Sie die StreetPhare-Funktionen jederzeit.';

  @override
  String get aboutTitle => 'Über';

  @override
  String get aboutApp => 'Über StreetPhare';

  @override
  String get aboutVersion => 'Version';

  @override
  String get aboutPlatform => 'Plattform';

  @override
  String get aboutLicense => 'Lizenz';

  @override
  String get aboutEncryption => 'Verschlüsselung';

  @override
  String get aboutOpenSource => 'Bürgerliches Open-Source-Projekt';

  @override
  String get aboutDescription => 'StreetPhare ist eine dezentrale kollaborative Kartierungsanwendung, die entwickelt wurde, um die kollektive Sicherheit bei Bürgerversammlungen zu stärken. Es werden keine personenbezogenen Daten erhoben oder an Dritte übermittelt. Alle Daten bleiben lokal oder werden über verschlüsselte Peer-to-peer-Relais übertragen.';

  @override
  String get bugReportTitle => 'Fehlerbericht';

  @override
  String get bugReportButton => 'Einen Fehler melden';

  @override
  String get bugReportSuggest => 'Vorschlagen';

  @override
  String get bugReportDescription => '💡 Dieses Formular sendet einen technischen Bericht an den StreetPhare-Verwaltungsserver. Berichte helfen Entwicklern, Probleme schnell zu identifizieren und zu beheben.';

  @override
  String get bugReportPrivacy => '🔒 Es werden keine persönlichen Daten übermittelt. Nur Titel, Beschreibung, Kategorie und App-Version werden gesendet.';

  @override
  String get bugReportSectionTitle => 'Fehlerberichterstattung & Vorschläge';

  @override
  String get bugReportSectionDescription => 'Bug-Button (unten links auf der Karte): Melden Sie einen Fehler oder einen Vorschlag direkt von der Hauptoberfläche aus, ohne die Karte zu verlassen.';

  @override
  String get eventsJoin => 'An einer Veranstaltung teilnehmen';

  @override
  String get eventsNoEvent => 'Derzeit keine aktiven Veranstaltungen';

  @override
  String get eventsQrScan => 'QR-Code scannen';

  @override
  String get qrScanTitle => 'Einen QR-Code scannen';

  @override
  String get searchTitle => 'Suche';

  @override
  String get searchHint => 'Suche nach einem Ort, einer Veranstaltung…';

  @override
  String get searchNoResult => 'Keine Ergebnisse gefunden';

  @override
  String get routeTitle => 'Route';

  @override
  String get routeCalculate => 'Route berechnen';

  @override
  String get routeDestination => 'Ziel';

  @override
  String get routeAvoidLiked => 'Gemeldete Gefahrenzonen vermeiden';

  @override
  String get routeAvoidPolice => 'Kontrollzonen vermeiden';

  @override
  String get routeAvoidCamera => 'Überwachungszonen vermeiden';

  @override
  String get splashInitializing => 'Initialisiere…';

  @override
  String get splashCheckingVersion => 'Version prüfen…';

  @override
  String get splashCheckingCache => 'Lokalen Cache prüfen…';

  @override
  String get splashPurgingCache => 'Cache abgelaufen, Bereinigung…';

  @override
  String get splashLoadingMap => 'Lokale Karte laden…';

  @override
  String get splashCachingTiles => 'Kacheln cachen…';

  @override
  String get splashReady => 'Bereit!';

  @override
  String get splashError => 'Fehler:';

  @override
  String get splashSubtitle => 'Echtzeit-Bürgerkartierung';

  @override
  String get splashCheckingConnectivity => 'Konnektivität prüfen…';

  @override
  String get panicButton => 'PANIK';

  @override
  String get panicAlertSent => 'PANIK-Alarm gesendet';

  @override
  String get onlineStatus => 'Online';

  @override
  String get offlineStatus => 'Offline';

  @override
  String get meshStatus => 'Mesh';

  @override
  String get relayStatus => 'Relais';

  @override
  String get connectedPeers => 'Verbundene Peers';

  @override
  String get proximityValidationTitle => 'Näherungsvalidierung';

  @override
  String get proximityValidationCheck => 'Nähe prüfen';

  @override
  String get proximityValid => 'Nähe validiert';

  @override
  String get proximityInvalid => 'Ungültige Nähe';

  @override
  String get geofenceEntered => 'Veranstaltungszone betreten';

  @override
  String get geofenceExited => 'Veranstaltungszone verlassen';

  @override
  String get dangerReported => 'Gefahr gemeldeter';

  @override
  String get dangerConfirmed => 'Gefahr bestätigt (≥3 Stimmen)';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get save => 'Speichern';

  @override
  String get delete => 'Löschen';

  @override
  String get confirm => 'Bestätigen';

  @override
  String get close => 'Schließen';

  @override
  String get back => 'Zurück';

  @override
  String get next => 'Weiter';

  @override
  String get done => 'Fertig';

  @override
  String get errorGeneric => 'Ein Fehler ist aufgetreten';

  @override
  String get loading => 'Laden…';

  @override
  String get retry => 'Wiederholen';

  @override
  String get noInternet => 'Keine Internetverbindung';

  @override
  String get locationAccessTitle => 'Standortzugriff';

  @override
  String get locationAccessMessage => 'StreetPhare benötigt Zugriff auf Ihren Standort, um die Karte und Warnungen in der Nähe anzuzeigen.';

  @override
  String get locationAccessButton => 'Erlauben';

  @override
  String get notificationPermissionTitle => 'Benachrichtigungen';

  @override
  String get notificationPermissionMessage => 'StreetPhare muss Benachrichtigungen für Warnungen und Veranstaltungen senden können.';

  @override
  String get notificationPermissionButton => 'Erlauben';

  @override
  String get androidChannelAlertsTitle => 'Feldwarnungen';

  @override
  String get androidChannelAlertsSubtitle => 'Blockaden, Einkesselungen, Spannungszonen';

  @override
  String get androidChannelEventsTitle => 'Veranstaltungen & Fahrten';

  @override
  String get androidChannelEventsSubtitle => 'Fahrtbeginn, Wegpunkte, Ende der Demo';

  @override
  String get androidChannelPanicTitle => 'Kollektive Panik-Warnungen';

  @override
  String get androidChannelPanicSubtitle => 'Geräteübergreifende Panik-Auslösung';

  @override
  String get androidChannelMessagesTitle => 'Nachrichten';

  @override
  String get androidChannelMessagesSubtitle => 'Neue Nachrichten im lokalen Netzwerk';

  @override
  String get androidChannelSectionTitle => 'Android-Benachrichtigungen nach Kanal';

  @override
  String get androidChannelManageSystem => 'In Android-Einstellungen verwalten';
}
