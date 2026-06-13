# Données OSM — Moteur de routage piéton StreetPhare

## Emplacement attendu du fichier

```
android/app/src/main/assets/osm/fleurus.osm.pbf
```

Ce fichier **n'est pas inclus** dans le dépôt Git (trop volumineux).
Il doit être téléchargé et placé ici avant de compiler l'APK.

---

## Comment obtenir `fleurus.osm.pbf`

### Option 1 — Geofabrik (recommandée)

Télécharger l'extrait Belgique puis découper avec `osmium` :

```bash
# 1. Télécharger la Belgique
curl -O https://download.geofabrik.de/europe/belgium-latest.osm.pbf

# 2. Découper la zone de Fleurus (bounding box ~6 km autour)
#    bbox : minLon=4.50 minLat=50.44 maxLon=4.60 maxLat=50.52
osmium extract \
  --bbox 4.50,50.44,4.60,50.52 \
  belgium-latest.osm.pbf \
  --output fleurus.osm.pbf \
  --overwrite

# 3. Copier dans les assets
cp fleurus.osm.pbf android/app/src/main/assets/osm/fleurus.osm.pbf
```

### Option 2 — Overpass Turbo (petits extraits)

1. Ouvrir https://overpass-turbo.eu
2. Sélectionner la zone de Fleurus (6220)
3. Exporter → OpenStreetMap XML / PBF
4. Renommer le fichier `fleurus.osm.pbf`
5. Copier dans `android/app/src/main/assets/osm/`

---

## Attribution obligatoire (ODbL 1.0)

```
© OpenStreetMap contributors — openstreetmap.org/copyright
Ce fichier est sous licence Open Data Commons Open Database License (ODbL) v1.0.
Voir : https://opendatacommons.org/licenses/odbl/1-0/
```

---

## Comportement si le fichier est absent

- GraphHopper ne peut pas s'initialiser → `engineReady = false`
- `OsmAndRoutingService` bascule automatiquement sur :
  1. GraphHopper HTTP local (`192.168.31.18:8080`)
  2. OSRM public (`router.project-osrm.org`)

Le log Android affichera :
```
W/StreetPhare.OsmAndBridge: Fichier OSM absent — moteur désactivé.
    Placez le fichier dans assets/osm/fleurus.osm.pbf
```

---

## Taille estimée

| Zone | Taille .pbf |
|------|-------------|
| Fleurus seul (~6 km²) | ~2–5 MB |
| Arrondissement de Charleroi | ~25 MB |
| Province du Hainaut | ~80 MB |

> ⚠️ Les fichiers >50 MB peuvent ralentir le premier démarrage
> (construction du graphe GraphHopper). Le cache est ensuite persistant.
