# OpenTripPlanner (OTP) — Itinéraires « transports en commun »

Ce dossier contient le déploiement d'**OpenTripPlanner 2**, le moteur de
routage multi-paliers (marche + bus/tram/train) utilisé par le profil
« transit » de l'application StreetPhare.

Le client Flutter interroge déjà :

```
https://streetphare.ddns.net/otp/routers/default/plan
```

Caddy route `/otp/*` vers le conteneur OTP (`127.0.0.1:8080`) — voir `../Caddyfile`.

---

## Prérequis

- **Docker** (avec docker compose).
- **RAM** : ~4 Go pour une région (Wallonie), ~6-8 Go pour la Belgique entière.
- Ports 80/443 publics déjà gérés par Caddy (OTP n'écoute qu'en local).

## Données d'entrée

| Type | Source par défaut | Remarque |
|---|---|---|
| OSM (réseau viaire) | `https://download.geofabrik.de/europe/belgium-latest.osm.pbf` | Belgique entière (~600 Mo). Pour alléger : utiliser un extrait de Wallonie. |
| GTFS (horaires TC) | `https://opendata.tec-wl.be/GTFSV3/TEC-GTFSV3.zip` | TEC Wallonie (bus). Peut être remplacé par un flux train (SNCB) ou multi-opérateurs. |

Les URLs sont surchargeables via les variables d'environnement
`STREETPHARE_OSM_PBF_URL` et `STREETPHARE_GTFS_URL`.

## 1. Construire le graphe

```bash
cd server/otp
./build-graph.sh
```

Le script télécharge `osm.pbf` + `gtfs-tec.zip` dans `./data`, copie
`build-config.json`, puis construit le graphe via :

```bash
docker run --rm \
  -e JAVA_TOOL_OPTIONS='-Xmx6g' \
  -v "$(pwd)/data:/var/opentripplanner" \
  docker.io/opentripplanner/opentripplanner:latest \
  --build --save
```

> ⚠️ Le nom du fichier GTFS doit contenir « gtfs » (exigence OTP).

## 2. Démarrer le service

```bash
cd server/otp
docker compose up -d
```

Vérifier :

```bash
docker compose logs -f otp
```

## 3. Tester

```bash
curl "https://streetphare.ddns.net/otp/routers/default/plan?fromPlace=50.4828,4.5492&toPlace=50.4802,4.5448&mode=TRANSIT,WALK"
```

Une réponse JSON avec `plan.itineraries` non vide = OTP fonctionnel.

## 4. Redéployer après mise à jour des données

Re-télécharger + reconstruire le graphe :

```bash
cd server/otp
./build-graph.sh
docker compose restart otp
```

## Remarques

- **Mémoire** : ajuster `JAVA_TOOL_OPTIONS` dans `docker-compose.yml` et
  `build-graph.sh` selon la taille de l'extrait OSM.
- **Région plus légère** : Geofabrik propose des extraits régionaux
  (ex. Wallonie) — remplacer l'URL OSM par l'extrait correspondant pour
  réduire RAM et temps de build.
- **Multi-opérateurs** : déposer plusieurs fichiers `*.gtfs*.zip` dans `./data`
  (ex. TEC + SNCB) avant `./build-graph.sh`.
