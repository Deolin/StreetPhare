#!/usr/bin/env bash
# build-graph.sh — Télécharge OSM + GTFS et construit le graphe OpenTripPlanner.
#
# Usage :
#   cd server/otp
#   ./build-graph.sh
#
# Prérequis : Docker installé, ~6-8 Go de RAM disponibles.
# Données par défaut :
#   - OSM  : Geofabrik Belgique (https://download.geofabrik.de/europe/belgium-latest.osm.pbf)
#   - GTFS : TEC Wallonie (https://opendata.tec-wl.be/GTFSV3/TEC-GTFSV3.zip)
# Surcharge possible via variables d'environnement :
#   STREETPHARE_OSM_PBF_URL  (ex: un .osm.pbf de Wallonie, plus léger)
#   STREETPHARE_GTFS_URL     (ex: un flux GTFS SNCB/train)
set -euo pipefail

cd "$(dirname "$0")"

DATA_DIR="./data"
mkdir -p "$DATA_DIR"

OSM_PBF_URL="${STREETPHARE_OSM_PBF_URL:-https://download.geofabrik.de/europe/belgium-latest.osm.pbf}"
GTFS_URL="${STREETPHARE_GTFS_URL:-https://opendata.tec-wl.be/GTFSV3/TEC-GTFSV3.zip}"

echo "[OTP] Téléchargement OSM : $OSM_PBF_URL"
curl -L "$OSM_PBF_URL" -o "$DATA_DIR/osm.pbf"

echo "[OTP] Téléchargement GTFS : $GTFS_URL"
# ⚠️ Le nom du fichier GTFS doit contenir « gtfs » (exigence OTP).
curl -L "$GTFS_URL" -o "$DATA_DIR/gtfs-tec.zip"

echo "[OTP] Copie de build-config.json"
cp build-config.json "$DATA_DIR/build-config.json"

echo "[OTP] Construction du graphe (peut prendre plusieurs minutes)…"
docker run --rm \
  -e JAVA_TOOL_OPTIONS='-Xmx6g' \
  -v "$(pwd)/$DATA_DIR:/var/opentripplanner" \
  docker.io/opentripplanner/opentripplanner:latest \
  --build --save

echo "[OTP] ✅ Graphe construit dans $DATA_DIR/graphs/"
echo "[OTP] Démarrage : docker compose up -d"
