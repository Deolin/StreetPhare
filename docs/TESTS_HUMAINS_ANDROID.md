# 🧪 StreetPhare — Plan de tests humains (Android)

> **Version cible** : `0.4.0-alpha` (APK `flutter build apk --release`)
> **Public** : groupe de testeurs bêta / QA terrain
> **Objectif** : valider en conditions réelles les fonctionnalités de l'app avant diffusion large.

---

## 1. Contexte & objectif

StreetPhare est une application citoyenne de cartographie collaborative temps réel
visant à **sécuriser les déplacements piétons** lors d'événements et de
rassemblements publics. Ce plan couvre les **tests manuels à réaliser sur Android**
(appareils physiques), en complément des tests automatisés déjà présents dans `test/`.

Les objectifs sont :
1. Vérifier que chaque fonctionnalité se comporte comme attendu.
2. Détecter les régressions, crashs et problèmes d'ergonomie.
3. Valider les scénarios **multi-appareils** (P2P, consensus, groupe de confiance).
4. Mesurer le comportement **hors-ligne** et en **arrière-plan**.

---

## 2. Environnement & prérequis

| Élément | Exigence |
|---|---|
| Appareils | ≥ 2 smartphones Android (idéalement versions variées : Android 10 → 15) |
| Build | APK release/debug installé (`flutter install`) |
| Comptes | Aucun compte requis (app anonyme) — 1 PC admin pour le dashboard (optionnel) |
| Réseau | Wi-Fi + 4G/5G pour l'online ; mode avion pour l'offline |
| GPS | Activé, précision « Haute » |
| BLE | Bluetooth activé (maillage P2P) |
| QR | Un QR d'événement à fournir (ou généré via les fixtures Fleurus) |

**Permissions à accorder/refuser pendant les tests :** localisation (avant-plan +
arrière-plan), Bluetooth, caméra (QR), notifications (Android 13+).

---

## 3. Conventions de rapport

**Statut d'un cas :** ✅ OK · ⚠️ Partiel · ❌ KO · ➖ Non testé

**Sévérité d'un bug :**
| Sévérité | Définition |
|---|---|
| 🔴 Bloquant | Crash / perte de donnée / sécurité compromise |
| 🟠 Majeur | Fonction inutilisable, sans contournement |
| 🟡 Mineur | Dysfonctionnement cosmétique ou contournable |
| 🟢 Suggestion | Amélioration UX |

Chaque bug remonté doit inclure : **appareil + version Android**, **étapes de
reproduction**, **résultat attendu vs obtenu**, **capture d'écran**, **sévérité**.
Utiliser le FAB « Rapport de bug » intégré à l'app si possible.

## 4. Installation & Onboarding

| ID | Action | Résultat attendu | Criticité |
|---|---|---|---|
| ONB-01 | Installer l'APK sur un appareil vierge | Installation sans erreur, icône « StreetPhare » présente | 🔴 Bloquant |
| ONB-02 | Lancer l'app la première fois | Splash → écran d'accueil → tutoriel pas-à-pas | 🟠 Majeur |
| ONB-03 | Terminer / passer le tutoriel | Le tutoriel ne réapparaît pas aux lancements suivants | 🟡 Mineur |
| ONB-04 | Relancer l'app sous 24 h | Pas de re-tutoriel (cache 24 h) | 🟡 Mineur |
| ONB-05 | Refuser chaque permission à la première sollicitation | Bandeau « permissions manquantes » affiché, app stable | 🟠 Majeur |
| ONB-06 | Accorder les permissions via le dialogue | Fonctions associées réactivées sans relance | 🟠 Majeur |

## 5. Carte & géolocalisation

| ID | Action | Résultat attendu | Criticité |
|---|---|---|---|
| MAP-01 | Ouvrir la carte | Tuiles OSM chargées, position utilisateur centrée | 🔴 Bloquant |
| MAP-02 | Déplacer / zoomer la carte | Navigation fluide, tuiles se chargent | 🟡 Mineur |
| MAP-03 | Faire pivoter l'appareil | Le marqueur de cap (boussole) suit l'orientation | 🟠 Majeur |
| MAP-04 | Couper puis rallumer le GPS | L'app le détecte, recentre / alerte | 🟠 Majeur |
| MAP-05 | Mode avion sur zone déjà consultée | Les tuiles en cache s'affichent (offline) | 🟠 Majeur |
| MAP-06 | Télécharger des tuiles hors-ligne | Téléchargement terminé, zone visible sans réseau | 🟠 Majeur |

## 6. Signalements (reports)

| ID | Action | Résultat attendu | Criticité |
|---|---|---|---|
| REP-01 | Ouvrir la feuille de signalement | 9 types affichés : barrages, zones filtrées, nasses, autopompes, gaz lacrymogènes, policiers, dangers, groupes casseurs, zone safe | 🔴 Bloquant |
| REP-02 | Créer un signalement localisé | Le marqueur apparaît sur la carte à la bonne position | 🔴 Bloquant |
| REP-03 | Vérifier couleur/icône par type | Chaque type a sa couleur et son icône dédiées | 🟡 Mineur |
| REP-04 | Laisser expirer un signalement (TTL) | L'alerte disparaît après son TTL | 🟠 Majeur |
| REP-05 | Confirmer le signalement d'un autre pair | Statut « validé » après le seuil de consensus (≥ 3) | 🔴 Bloquant |
| REP-06 | Générer du spam (signalements identiques) | Le consensus anti-spam limite la visibilité | 🟠 Majeur |

## 7. Routage « route safe »

| ID | Action | Résultat attendu | Criticité |
|---|---|---|---|
| RUT-01 | Demander un itinéraire vers un point | Itinéraire piéton calculé et affiché | 🔴 Bloquant |
| RUT-02 | Activer des filtres d'évitement | L'itinéraire contourne les zones signalées | 🔴 Bloquant |
| RUT-03 | Calculer une route hors-ligne (GraphHopper embarqué) | Route calculée sans réseau | 🟠 Majeur |
| RUT-04 | Tester le fallback (GraphHopper → OsmAnd → Dijkstra) | Un moteur de secours prend le relais si le premier échoue | 🟠 Majeur |
| RUT-05 | Cibler une « Zone Safe » | La destination prioritaire proposée est la zone safe la plus proche | 🟠 Majeur |

## 8. Alerte PANIC

| ID | Action | Résultat attendu | Criticité |
|---|---|---|---|
| PAN-01 | Déclencher un PANIC individuel | Alerte émise + notifications aux pairs proches | 🔴 Bloquant |
| PAN-02 | Configurer des contacts d'urgence | Contacts persistés et utilisés | 🟠 Majeur |
| PAN-03 | Déclencher un PANIC collectif (plusieurs pings rapprochés) | Agrégation détectée, diffusion collective | 🔴 Bloquant |
| PAN-04 | Déclencher l'« effacement d'urgence » | Purge immédiate des données locales sensibles | 🔴 Bloquant |

## 9. Street-Medic

| ID | Action | Résultat attendu | Criticité |
|---|---|---|---|
| SMD-01 | S'autoriser comme street-medic | Section « Street-medic » activée dans les paramètres | 🟠 Majeur |
| SMD-02 | Demander un medic depuis la carte | Appel du medic le plus proche déclenché | 🔴 Bloquant |
| SMD-03 | Suivre une mission d'intervention | Panneau de mission visible, suivi du blessé OK | 🟠 Majeur |
| SMD-04 | Déclencher l'« alerte 112 » | Redirection vers l'appel d'urgence | 🟠 Majeur |
| SMD-05 | Partager sa position de medic (« Tracé ») | Position partagée puis arrêtée proprement | 🟠 Majeur |

## 10. Événements & QR

| ID | Action | Résultat attendu | Criticité |
|---|---|---|---|
| EVT-01 | Ouvrir le catalogue d'événements | Liste des événements disponibles | 🟠 Majeur |
| EVT-02 | Scanner un QR d'événement | Entrée dans l'événement, géorepérage actif | 🔴 Bloquant |
| EVT-03 | Entrer/sortir de la zone (géorepérage) | Détection d'entrée/sortie + notifications | 🟠 Majeur |
| EVT-04 | Ouvrir le lien `streetphare://event` | L'app s'ouvre sur le bon écran | 🟠 Majeur |

## 11. Messagerie P2P

| ID | Action | Résultat attendu | Criticité |
|---|---|---|---|
| MSG-01 | Envoyer un message à un pair | Message transmis et visible localement (Hive) | 🔴 Bloquant |
| MSG-02 | Ouvrir un fil de discussion | Historique conservé | 🟠 Majeur |
| MSG-03 | Bloquer un utilisateur | Ses messages ne sont plus affichés | 🟠 Majeur |
| MSG-04 | Changer le filtre de messages | Les messages sont filtrés selon le paramètre | 🟠 Majeur |

## 12. Groupe de confiance

| ID | Action | Résultat attendu | Criticité |
|---|---|---|---|
| TRG-01 | Envoyer une demande de suivi | La demande arrive « en attente » chez l'autre | 🔴 Bloquant |
| TRG-02 | Accepter / refuser la demande | Suivi activé seulement après consentement | 🔴 Bloquant |
| TRG-03 | Suivre la position d'un ami | Position mise à jour sur la carte | 🟠 Majeur |
| TRG-04 | Révoquer le consentement | Le suivi cesse immédiatement | 🟠 Majeur |

## 13. Réseau P2P & hors-ligne (multi-appareils)

| ID | Action | Résultat attendu | Criticité |
|---|---|---|---|
| NET-01 | 2 appareils proches, BLE actif, mode avion | Les alertes s'échangent en P2P sans serveur | 🔴 Bloquant |
| NET-02 | Rendre le serveur central indisponible | Failover primary/backup ou repli P2P | 🟠 Majeur |
| NET-03 | Vérifier le compteur de pairs | Le nombre de pairs détectés est cohérent | 🟡 Mineur |
| NET-04 | Écran verrouillé / app en arrière-plan | Le service avant-plan maintient la réception d'alertes | 🟠 Majeur |
| NET-05 | Redémarrer le téléphone | Le service repart (récepteur BOOT_COMPLETED) | 🟠 Majeur |

## 14. Paramètres, thème & accessibilité

| ID | Action | Résultat attendu | Criticité |
|---|---|---|---|
| PAR-01 | Changer la langue (fr/en/nl/de) | Toute l'UI bascule dans la langue choisie | 🟠 Majeur |
| PAR-02 | Passer thème clair → sombre → système | Thème appliqué immédiatement | 🟡 Mineur |
| PAR-03 | Activer le « mode malvoyant » | Textes agrandis (échelle 1.5×), contraste augmenté | 🟠 Majeur |
| PAR-04 | Activer le « mode économe » | Activité réduite, app toujours fonctionnelle | 🟡 Mineur |
| PAR-05 | Régler la rétention du cache cartes | Valeur persistée (7/14/30 j) | 🟡 Mineur |
| PAR-06 | Activer/désactiver le service arrière-plan | Notification persistante « StreetPhare actif » apparaît/disparaît | 🟠 Majeur |
| PAR-07 | Consulter « Mon identifiant » | Identifiant stable affiché, copiable/partageable | 🟡 Mineur |
| PAR-08 | Changer de skin / profil visuel | Thème visuel appliqué | 🟡 Mineur |

## 15. Admin (optionnel — 1 testeur référent)

| ID | Action | Résultat attendu | Criticité |
|---|---|---|---|
| ADM-01 | Accéder au dashboard admin | Connexion JWT + accès dashboard | 🟠 Majeur |
| ADM-02 | Valider/refuser un signalement | La validation influe sur la visibilité côté clients | 🔴 Bloquant |
| ADM-03 | Utiliser la carte administrateur | Les signalements s'affichent pour modération | 🟠 Majeur |

## 16. Divers

| ID | Action | Résultat attendu | Criticité |
|---|---|---|---|
| DIV-01 | Envoyer un rapport de bug (FAB) | Rapport capturé et stocké (offline-first) | 🟠 Majeur |
| DIV-02 | Partager l'APK | Feuille de partage s'ouvre | 🟡 Mineur |
| DIV-03 | Vérifier la mise à jour auto (GitHub) | Dialogue si une version plus récente existe | 🟠 Majeur |
| DIV-04 | Ouvrir le lien `streetphare://invite` | L'app s'ouvre sur l'écran d'invitation | 🟡 Mineur |

---

## 17. Scénarios de bout en bout (E2E) à réaliser en groupe

| # | Scénario | Testeurs min. | Attendu |
|---|---|---|---|
| E2E-01 | **Manifestation simulée** : T1 signale un barrage → T2/T3 confirment → consensus validé | 3-4 | Signalement visible de tous après ≥ 3 confirmations |
| E2E-02 | **Évacuation safe** : T1 demande une route évitant le barrage vers une zone safe | 1-2 | Itinéraire contourne la zone |
| E2E-03 | **PANIC collectif** : plusieurs testeurs déclenchent un PANIC rapproché | 3+ | Alerte collective propagée |
| E2E-04 | **Groupe de confiance** : T1 envoie une demande à T2 → accepte → suivi | 2 | Position visible après consentement |
| E2E-05 | **Hors-ligne total** : mode avion + BLE pour tous, échange d'alertes | 2+ | Alertes échangées via P2P |

---

## 18. Check-list de fin de campagne

- [ ] Tous les cas « 🔴 Bloquant » passent à ✅
- [ ] Les cas « 🟠 Majeur » KO sont documentés (bug report)
- [ ] Tests réalisés sur ≥ 2 versions Android différentes
- [ ] Scénarios E2E multi-appareils exécutés
- [ ] Comportement arrière-plan + redémarrage vérifiés
- [ ] Comportement hors-ligne (cache tuiles + P2P + routage) validé
- [ ] Aucune donnée personnelle persistée après un « effacement d'urgence »

### Modèle de rapport de bug

```text
Appareil / Android :
APK (version/build) :
Domaine (ex : Carte) :
Étapes :
Résultat attendu :
Résultat obtenu :
Sévérité (🔴🟠🟡🟢) :
Captures :
```
