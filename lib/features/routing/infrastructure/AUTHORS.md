# AUTHORS — Moteur de routage piéton StreetPhare

> Mis à jour le 2026-06-11

---

## StreetPhare — Code original

| Auteur | Rôle | Fichiers |
|--------|------|---------|
| Équipe StreetPhare | Auteur principal | `OsmAndBridgePlugin.kt`, `OsmAndNativeChannel.dart`, `OsmAndRoutingService.dart` |

---

## GraphHopper Core — Composant tiers (Apache 2.0)

GraphHopper est un moteur de routage open-source développé et maintenu par
**GraphHopper GmbH** et ses contributeurs.

Dépôt officiel : https://github.com/graphhopper/graphhopper
Licence : Apache License 2.0

Principaux contributeurs historiques :
- Peter Karich (@karussell) — fondateur, mainteneur principal
- Robin Boldt (@boldtrn)
- Thomas Nägele (@thomasnaegel)
- Andrzej Oles (@andrewosh)
- Et tous les contributeurs listés sur :
  https://github.com/graphhopper/graphhopper/graphs/contributors

**Version utilisée** : 7.0  
**Modifications** : aucune (utilisation via la dépendance Maven officielle)

---

## OpenStreetMap — Données géographiques (ODbL 1.0)

Les données géographiques utilisées pour le routage sont issues du projet
**OpenStreetMap**, maintenu par la **OpenStreetMap Foundation (OSMF)**
et ses contributeurs bénévoles.

Site officiel : https://www.openstreetmap.org  
Licence des données : ODbL 1.0 — https://opendatacommons.org/licenses/odbl/

Attribution obligatoire :
> © OpenStreetMap contributors

---

## OSRM — Fallback HTTP (BSD 2-Clause)

**Open Source Routing Machine** est un projet open-source de calcul d'itinéraires.

Dépôt : https://github.com/Project-OSRM/osrm-backend  
Licence : BSD 2-Clause  
Utilisation : API publique `router.project-osrm.org` en fallback réseau

---

## OsmAnd — Protocole d'URL (GPLv3, usage externe uniquement)

OsmAnd est développé par **OsmAnd BV** et ses contributeurs.

Site officiel : https://osmand.net  
Dépôt : https://github.com/osmandapp/OsmAnd  
Licence : GNU General Public License v3 (GPLv3)

**Utilisation dans StreetPhare** : protocole d'URL publique `osmand.api://`
uniquement (aucun code source OsmAnd embarqué).

---

## SLF4J Android — Logging (MIT)

Copyright (C) 2004–2024 QOS.ch  
Licence : MIT  
Dépôt : https://github.com/slf4j/slf4j
