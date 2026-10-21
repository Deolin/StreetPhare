// server/public/admin/events-editor.js
//
// Editeur d evenements du dashboard d administration StreetPhare.
//
// Permet a un administrateur (ou un moderateur avec la permission
// `manageEvents`) de :
//   1. Lister les evenements, en selectionner un, en creer / supprimer.
//   2. Modifier les metadonnees (titre, debut, fin, visibilite, zone).
//   3. Placer sur la carte les points de l evenement :
//        - points de passage du cortege (avec heure prevue)
//        - points d entree / sortie
//        - zones sures de repli
//        - medecins / centres de soins
//        - points remarquables (rassemblement syndicaliste)
//   4. Deplacer un point (drag & drop), le modifier ou le supprimer.
//   5. Tracer le trajet (polyline GeoJSON) et definir la destination.
//
// L API utilisee est exposee par server/src/routes/adminEvents.js.

// ---------------------------------------------------------------------------
// ETAT LOCAL
// ---------------------------------------------------------------------------

/// Liste des evenements connus du dashboard (remplie par l API).
let adminEvents = [];

/// Code de l evenement selectionne (null = aucun).
let selectedEventCode = null;

/// Catalogue des types de points (charge depuis l API).
let pointTypes = [];

/// Mode de placement actif sur la carte : 'point' | 'route' | null.
let evMode = null;

/// Coordonnees du point en cours de placement / edition.
let evDraft = { lat: null, lng: null };

/// Point en cours d edition : { typeKey, index } ou null.
let editingPoint = null;

/// Sommets du trajet en cours de trace.
let routeDraft = [];

/// Couleurs de repli (si le catalogue serveur est indisponible).
const EV_FALLBACK_COLORS = {
  waypoints: '#d29922',
  exitPoints: '#ffa657',
  safeZones: '#3fb950',
  careCenters: '#f85149',
  pois: '#bc8cff',
};

/// Couleur d un type de point.
function evColor(typeKey) {
  const t = pointTypes.find(x => x.key === typeKey);
  return (t && t.color) || EV_FALLBACK_COLORS[typeKey] || '#79c0ff';
}

/// Libelle lisible d un type de point.
function evTypeLabel(typeKey) {
  const t = pointTypes.find(x => x.key === typeKey);
  return (t && t.label) || typeKey;
}

/// Couche Leaflet dediee a l edition des evenements.
let evLayer = null;

// ---------------------------------------------------------------------------
// ACCES API
// ---------------------------------------------------------------------------

/// Appel JSON authentifie vers l API d administration des evenements.
async function evApi(method, path, body) {
  const opts = {
    method,
    headers: { 'Authorization': `Bearer ${adminToken}` },
  };
  if (body !== undefined) {
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(body);
  }
  const res = await fetch(`/api/admin/events${path}`, opts);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `Erreur ${res.status}`);
  return data;
}

/// Met a jour le message de statut de l editeur.
function evStatus(message, isError = false) {
  const el = document.getElementById('ev-status');
  if (!el) return;
  el.textContent = message;
  el.style.color = isError ? '#f85149' : '#8b949e';
}

// ---------------------------------------------------------------------------
// CHARGEMENT
// ---------------------------------------------------------------------------

/// Charge le catalogue des types de points.
async function loadPointTypes() {
  const sel = document.getElementById('ev-point-type');
  if (!sel) return;
  try {
    const data = await evApi('GET', '/point-types');
    pointTypes = data.types || [];
    if (sel.options.length <= 1) {
      sel.innerHTML = '<option value="">— Type de point —</option>'
        + pointTypes.map(t => `<option value="${t.key}">${t.icon || ''} ${escapeHtml(t.label)}</option>`).join('');
    }
  } catch (e) {
    if (sel.options.length <= 1) {
      sel.innerHTML = '<option value="">— Type de point —</option>'
        + Object.keys(EV_FALLBACK_COLORS).map(k => `<option value="${k}">${k}</option>`).join('');
    }
  }
}

/// Charge la liste des evenements depuis l API.
async function loadEvents() {
  try {
    const data = await evApi('GET', '');
    adminEvents = data.events || [];
  } catch (e) {
    adminEvents = [];
  }
  renderEventList();
  if (selectedEventCode && !adminEvents.some(e => e.code === selectedEventCode)) {
    selectedEventCode = null;
  }
  if (!selectedEventCode && adminEvents.length) {
    selectEvent(adminEvents[0].code);
  } else {
    renderEventList();
    renderEventDetails();
  }
  drawSelectedEvent();
}

/// Evenement actuellement selectionne (objet) ou null.
function currentEvent() {
  return adminEvents.find(e => e.code === selectedEventCode) || null;
}

// ---------------------------------------------------------------------------
// LISTE DES EVENEMENTS
// ---------------------------------------------------------------------------

/// Affiche la liste des evenements dans le panneau.
function renderEventList() {
  const list = document.getElementById('events-list');
  if (!list) return;
  if (!adminEvents.length) { list.innerHTML = 'Aucun evenement'; return; }
  const now = Date.now();
  list.innerHTML = adminEvents.map(ev => {
    const start = ev.startAt ? new Date(ev.startAt).getTime() : 0;
    const end = ev.endAt ? new Date(ev.endAt).getTime() : null;
    let badge = '<span class="ev-badge" style="background:#8b949e">BROUILLON</span>';
    if (end && end < now) badge = '<span class="ev-badge" style="background:#6e7681">TERMINE</span>';
    else if (start <= now) badge = '<span class="ev-badge" style="background:#3fb950">EN COURS</span>';
    else badge = '<span class="ev-badge" style="background:#d29922">PLANIFIE</span>';
    const nbPts = (ev.waypoints || []).length + (ev.exitPoints || []).length
      + (ev.safeZones || []).length + (ev.careCenters || []).length + (ev.pois || []).length;
    return `<div class="ev-item ${selectedEventCode === ev.code ? 'selected' : ''}">
      <div class="ev-main" onclick="selectEvent('${escapeHtml(ev.code)}')">
        <b>${escapeHtml(ev.title || ev.code)}</b> ${badge}<br>
        <span class="meta">${escapeHtml(ev.code)} · ${nbPts} point(s)</span>
      </div>
    </div>`;
  }).join('');
}

/// Selectionne un evenement et recharge son contenu.
function selectEvent(code) {
  selectedEventCode = code;
  editingPoint = null;
  evDraft = { lat: null, lng: null };
  routeDraft = [];
  cancelPlacement();
  renderEventList();
  renderEventDetails();
  renderPointList();
  drawSelectedEvent();
}

/// Affiche le detail de l evenement selectionne dans le formulaire.
function renderEventDetails() {
  const ev = currentEvent();
  const t = (id) => document.getElementById(id);
  if (!ev) {
    if (t('ev-edit-title')) t('ev-edit-title').value = '';
    if (t('ev-route-info')) t('ev-route-info').textContent = '';
    return;
  }
  if (t('ev-edit-title')) t('ev-edit-title').value = ev.title || '';
  if (t('ev-edit-start')) t('ev-edit-start').value = toLocalInput(ev.startAt);
  if (t('ev-edit-end')) t('ev-edit-end').value = toLocalInput(ev.endAt);
  if (t('ev-edit-visible')) t('ev-edit-visible').value = toLocalInput(ev.visibleAt || ev.startAt);
  if (t('ev-edit-zone')) t('ev-edit-zone').value = ev.generalZone || '';
  const nPts = ['waypoints', 'exitPoints', 'safeZones', 'careCenters', 'pois']
    .reduce((acc, k) => acc + ((ev[k] || []).length), 0);
  if (t('ev-route-info')) {
    const nRoute = countRouteVertices(ev.routeGeoJson);
    t('ev-route-info').textContent = `${nPts} point(s) · ${nRoute} sommet(s) de trajet`;
  }
}

/// Convertit une date ISO en valeur compatible `datetime-local`.
function toLocalInput(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '';
  const pad = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/// Convertit une valeur `datetime-local` en ISO UTC.
function fromLocalInput(value) {
  if (!value) return null;
  const d = new Date(value);
  if (isNaN(d.getTime())) return null;
  return d.toISOString();
}

/// Compte les sommets d une polyline GeoJSON.
function countRouteVertices(routeGeoJson) {
  if (!routeGeoJson) return 0;
  try {
    const parsed = JSON.parse(routeGeoJson);
    return Array.isArray(parsed) ? parsed.length : 0;
  } catch (_) {
    return 0;
  }
}

// ---------------------------------------------------------------------------
// CRUD EVENEMENT
// ---------------------------------------------------------------------------

/// Cree un nouvel evenement a partir du formulaire.
async function createEvent() {
  const code = document.getElementById('ev-code').value.trim().toUpperCase();
  const title = document.getElementById('ev-title').value.trim();
  const startLocal = document.getElementById('ev-start').value;
  if (!code || !title) { evStatus('Code et titre requis', true); return; }
  const startAt = fromLocalInput(startLocal) || new Date().toISOString();
  try {
    const data = await evApi('POST', '', { code, title, startAt });
    selectedEventCode = data.event.code;
    document.getElementById('ev-code').value = '';
    document.getElementById('ev-title').value = '';
    await loadEvents();
    evStatus(`Evenement ${data.event.code} cree`);
  } catch (e) {
    evStatus(e.message, true);
  }
}

/// Enregistre les metadonnees de l evenement selectionne.
async function saveEventMeta() {
  if (!selectedEventCode) { evStatus('Aucun evenement selectionne', true); return; }
  const body = {
    title: document.getElementById('ev-edit-title').value.trim(),
    startAt: fromLocalInput(document.getElementById('ev-edit-start').value),
    endAt: fromLocalInput(document.getElementById('ev-edit-end').value),
    visibleAt: fromLocalInput(document.getElementById('ev-edit-visible').value),
    generalZone: document.getElementById('ev-edit-zone').value.trim() || null,
  };
  if (!body.title) { evStatus('Le titre ne peut pas etre vide', true); return; }
  try {
    const data = await evApi('PUT', `/${encodeURIComponent(selectedEventCode)}`, body);
    mergeEvent(data.event);
    renderEventList();
    renderEventDetails();
    drawSelectedEvent();
    evStatus('Parametres enregistres');
  } catch (e) {
    evStatus(e.message, true);
  }
}

/// Supprime l evenement selectionne.
async function deleteSelectedEvent() {
  if (!selectedEventCode) { evStatus('Aucun evenement selectionne', true); return; }
  const code = selectedEventCode;
  if (!confirm(`Supprimer definitivement l evenement ${code} ?`)) return;
  try {
    await evApi('DELETE', `/${encodeURIComponent(code)}`);
    selectedEventCode = null;
    await loadEvents();
    evStatus(`Evenement ${code} supprime`);
  } catch (e) {
    evStatus(e.message, true);
  }
}

/// Met a jour l evenement selectionne en memoire (sans rechargement complet).
function mergeEvent(event) {
  if (!event) return;
  const idx = adminEvents.findIndex(e => e.code === event.code);
  if (idx === -1) adminEvents.push(event);
  else adminEvents[idx] = event;
}

// ---------------------------------------------------------------------------
// POINTS : FORMULAIRE ET PLACEMENT
// ---------------------------------------------------------------------------

/// Reagit au changement de type de point : reconstruit les champs.
function onPointTypeChange(value) {
  const container = document.getElementById('ev-point-fields');
  if (!container) return;
  const type = pointTypes.find(t => t.key === value);
  editingPoint = null;
  if (!type) { container.innerHTML = ''; return; }
  container.innerHTML = type.fields.map(f => {
    if (f.type === 'select') {
      const opts = (f.options || []).map(o => `<option value="${escapeHtml(o)}">${escapeHtml(o)}</option>`).join('');
      return `<label>${escapeHtml(f.label)}</label><select data-ev-field="${f.name}">${opts}</select>`;
    }
    return `<label>${escapeHtml(f.label)}</label>`
      + `<input data-ev-field="${f.name}" type="${f.type || 'text'}"${f.step ? ` step="${f.step}"` : ''}`
      + `${f.min !== undefined ? ` min="${f.min}"` : ''}${f.max !== undefined ? ` max="${f.max}"` : ''}`
      + ` value="${escapeHtml(f.default !== undefined ? f.default : '')}">`;
  }).join('');
  updateModeIndicator();
}

/// Lit les valeurs du formulaire de point.
function readPointForm() {
  const typeKey = document.getElementById('ev-point-type').value;
  const type = pointTypes.find(t => t.key === typeKey);
  if (!type) return null;
  const point = {};
  for (const f of type.fields) {
    const input = document.querySelector(`#ev-point-fields [data-ev-field="${f.name}"]`);
    let value = input ? input.value : undefined;
    if (value === '' || value === undefined) {
      if (f.default !== undefined) value = f.default;
      else continue;
    }
    point[f.name] = f.type === 'number' ? Number(value) : value;
  }
  point.lat = evDraft.lat;
  point.lng = evDraft.lng;
  return point;
}

/// Demande le mode « placement d'un point sur la carte ».
function startPointPlacement() {
  if (!selectedEventCode) { evStatus('Selectionnez d abord un evenement', true); return; }
  if (!document.getElementById('ev-point-type').value) { evStatus('Choisissez un type de point', true); return; }
  evMode = 'point';
  map.getContainer().style.cursor = 'crosshair';
  updateModeIndicator();
}

/// Annule toute edition / placement en cours.
function cancelPointEdit() {
  editingPoint = null;
  evDraft = { lat: null, lng: null };
  cancelPlacement();
  onPointTypeChange(document.getElementById('ev-point-type').value);
  renderPointList();
}

/// Reinitialise le mode de placement sur la carte.
function cancelPlacement() {
  evMode = null;
  routeDraft = [];
  if (map) map.getContainer().style.cursor = '';
  updateModeIndicator();
}

/// Met a jour l indicateur de mode dans le panneau.
function updateModeIndicator() {
  const el = document.getElementById('ev-mode-indicator');
  if (!el) return;
  if (evMode === 'point') {
    el.textContent = 'Mode actif : cliquez sur la carte pour placer le point.';
  } else if (evMode === 'route') {
    el.textContent = 'Mode actif : cliquez pour ajouter des sommets au trajet. Validez ensuite.';
  } else if (evMode === 'destination') {
    el.textContent = 'Mode actif : cliquez sur la carte pour definir la destination.';
  } else {
    el.textContent = 'Mode : inactif.';
  }
}

/// Enregistre le point (creation ou modification) via l API.
async function submitPoint() {
  if (!selectedEventCode) { evStatus('Selectionnez d abord un evenement', true); return; }
  const typeKey = document.getElementById('ev-point-type').value;
  if (!typeKey) { evStatus('Choisissez un type de point', true); return; }
  if (evDraft.lat == null) { evStatus('Cliquez sur la carte pour placer le point', true); return; }

  const point = readPointForm();
  if (!point) { evStatus('Formulaire incomplet', true); return; }

  try {
    let data;
    if (editingPoint) {
      data = await evApi('PUT', `/${encodeURIComponent(selectedEventCode)}/points/${typeKey}/${editingPoint.index}`, point);
    } else {
      data = await evApi('POST', `/${encodeURIComponent(selectedEventCode)}/points/${typeKey}`, point);
    }
    mergeEvent(data.event);
    editingPoint = null;
    evDraft = { lat: null, lng: null };
    cancelPlacement();
    renderPointList();
    renderEventDetails();
    drawSelectedEvent();
    evStatus('Point enregistre');
  } catch (e) {
    evStatus(e.message, true);
  }
}

// ---------------------------------------------------------------------------
// POINTS : LISTE, EDITION, DEPLACEMENT, SUPPRESSION
// ---------------------------------------------------------------------------

/// Affiche la liste des points de l evenement selectionne, regroupes par type.
function renderPointList() {
  const list = document.getElementById('ev-points-list');
  if (!list) return;
  const ev = currentEvent();
  if (!ev) { list.innerHTML = 'Selectionnez un evenement'; return; }

  const groups = [];
  for (const type of pointTypes) {
    const items = ev[type.key] || [];
    if (!items.length) continue;
    groups.push({ type, items });
  }
  if (!groups.length) { list.innerHTML = 'Aucun point pour cet evenement'; return; }

  list.innerHTML = groups.map(g => `
    <div style="margin-top:6px">
      <div style="font-size:10px;color:#8b949e;text-transform:uppercase">
        ${escapeHtml(g.type.icon || '')} ${escapeHtml(g.type.label)} (${g.items.length})
      </div>
      ${g.items.map((p, i) => {
        const isSel = editingPoint && editingPoint.typeKey === g.type.key && editingPoint.index === i;
        const extra = p.direction ? ` — ${escapeHtml(p.direction)}`
          : (p.contact ? ` — ${escapeHtml(p.contact)}`
          : (p.scheduledAt ? ` — ${escapeHtml(String(p.scheduledAt).slice(11, 16))}` : ''));
        return `<div class="pt-row">
          <span class="pt-dot" style="background:${evColor(g.type.key)}"></span>
          <div class="pt-main ${isSel ? 'selected' : ''}" onclick="editPoint('${g.type.key}', ${i})">
            ${escapeHtml(p.label || '(sans libelle)')}${extra}<br>
            <span class="meta">${Number(p.lat).toFixed(5)}, ${Number(p.lng).toFixed(5)}</span>
          </div>
          <div class="pt-actions">
            ${g.type.ordered ? `<button onclick="movePoint('${g.type.key}', ${i}, -1)" title="Monter">&#9650;</button>
            <button onclick="movePoint('${g.type.key}', ${i}, 1)" title="Descendre">&#9660;</button>` : ''}
            <button class="ok" onclick="editPoint('${g.type.key}', ${i})">&#9998;</button>
            <button class="danger" onclick="deletePoint('${g.type.key}', ${i})">&#10005;</button>
          </div>
        </div>`;
      }).join('')}
    </div>`).join('');
}

/// Charge un point dans le formulaire pour modification.
function editPoint(typeKey, index) {
  const ev = currentEvent();
  if (!ev) return;
  const point = (ev[typeKey] || [])[index];
  if (!point) return;

  const sel = document.getElementById('ev-point-type');
  sel.value = typeKey;
  onPointTypeChange(typeKey);
  const type = pointTypes.find(t => t.key === typeKey);
  if (type) {
    for (const f of type.fields) {
      const input = document.querySelector(`#ev-point-fields [data-ev-field="${f.name}"]`);
      if (!input) continue;
      let value = point[f.name];
      if (f.name === 'scheduledAt' && value) value = toLocalInput(value);
      input.value = value !== undefined && value !== null ? value : '';
    }
  }

  editingPoint = { typeKey, index };
  evDraft = { lat: Number(point.lat), lng: Number(point.lng) };
  evMode = 'point';
  map.getContainer().style.cursor = 'crosshair';
  updateModeIndicator();
  renderPointList();
  drawSelectedEvent();
}

/// Deplace un point ordonne (waypoints) d un cran.
async function movePoint(typeKey, index, delta) {
  const ev = currentEvent();
  if (!ev) return;
  const list = ev[typeKey] || [];
  const to = index + delta;
  if (to < 0 || to >= list.length) return;
  try {
    const data = await evApi('POST', `/${encodeURIComponent(ev.code)}/points/${typeKey}/reorder`, { from: index, to });
    mergeEvent(data.event);
    renderPointList();
    drawSelectedEvent();
  } catch (e) {
    evStatus(e.message, true);
  }
}

/// Supprime un point.
async function deletePoint(typeKey, index) {
  const ev = currentEvent();
  if (!ev) return;
  const point = (ev[typeKey] || [])[index];
  if (!point) return;
  if (!confirm(`Supprimer le point "${point.label || ''}" ?`)) return;
  try {
    const data = await evApi('DELETE', `/${encodeURIComponent(ev.code)}/points/${typeKey}/${index}`);
    mergeEvent(data.event);
    if (editingPoint && editingPoint.typeKey === typeKey && editingPoint.index === index) editingPoint = null;
    renderPointList();
    renderEventDetails();
    drawSelectedEvent();
    evStatus('Point supprime');
  } catch (e) {
    evStatus(e.message, true);
  }
}

// ---------------------------------------------------------------------------
// TRAJET (POLYLINE) ET DESTINATION
// ---------------------------------------------------------------------------

/// Demande le mode « trace du trajet ».
function startRoutePlacement() {
  if (!selectedEventCode) { evStatus('Selectionnez d abord un evenement', true); return; }
  const ev = currentEvent();
  routeDraft = [];
  try {
    const parsed = JSON.parse(ev.routeGeoJson || '[]');
    if (Array.isArray(parsed)) routeDraft = parsed.map(p => [Number(p[0]), Number(p[1])]);
  } catch (_) { routeDraft = []; }
  evMode = 'route';
  map.getContainer().style.cursor = 'crosshair';
  updateModeIndicator();
  drawSelectedEvent();
}

/// Enregistre le trajet trace (GeoJSON `[[lng,lat],...]`).
async function saveRoute() {
  if (!selectedEventCode) { evStatus('Aucun evenement selectionne', true); return; }
  if (!routeDraft.length) { evStatus('Aucun sommet a enregistrer', true); return; }
  try {
    const data = await evApi('PUT', `/${encodeURIComponent(selectedEventCode)}/route`, {
      routeGeoJson: JSON.stringify(routeDraft.map(p => [p[0], p[1]])),
    });
    mergeEvent(data.event);
    cancelPlacement();
    renderEventDetails();
    drawSelectedEvent();
    evStatus(`Trajet enregistre (${routeDraft.length} sommets)`);
  } catch (e) {
    evStatus(e.message, true);
  }
}

/// Efface le trajet de l evenement.
async function clearRoute() {
  if (!selectedEventCode) { evStatus('Aucun evenement selectionne', true); return; }
  if (!confirm('Effacer le trajet de cet evenement ?')) return;
  try {
    const data = await evApi('PUT', `/${encodeURIComponent(selectedEventCode)}/route`, { routeGeoJson: '' });
    mergeEvent(data.event);
    routeDraft = [];
    renderEventDetails();
    drawSelectedEvent();
    evStatus('Trajet efface');
  } catch (e) {
    evStatus(e.message, true);
  }
}

/// Definit la destination de l evenement a partir du point clique.
async function setDestinationFromMap() {
  if (!selectedEventCode) { evStatus('Aucun evenement selectionne', true); return; }
  if (evDraft.lat == null) { evStatus('Cliquez sur la carte pour choisir la destination', true); return; }
  try {
    const data = await evApi('PUT', `/${encodeURIComponent(selectedEventCode)}/route`, {
      destinationLatitude: evDraft.lat,
      destinationLongitude: evDraft.lng,
    });
    mergeEvent(data.event);
    renderEventDetails();
    drawSelectedEvent();
    evStatus('Destination definie');
  } catch (e) {
    evStatus(e.message, true);
  }
}

// ---------------------------------------------------------------------------
// RENDU CARTE
// ---------------------------------------------------------------------------

/// Cree (au besoin) la couche Leaflet dediee a l edition.
function ensureEventLayer() {
  if (!evLayer) evLayer = L.layerGroup().addTo(map);
  return evLayer;
}

/// Dessine l evenement selectionne (trajet, destination, points).
function drawSelectedEvent() {
  const layer = ensureEventLayer();
  layer.clearLayers();
  const ev = currentEvent();
  if (!ev) return;

  // --- Trajet (polyline) -------------------------------------------------
  const route = routeDraft.length ? routeDraft : parseRoute(ev.routeGeoJson);
  if (route.length) {
    const latlngs = route.map(p => [p[1], p[0]]);
    L.polyline(latlngs, { color: '#79c0ff', weight: 4, opacity: 0.85, dashArray: evMode === 'route' ? '6 6' : null })
      .bindPopup(`<b>Trajet</b><br><small>${route.length} sommets</small>`)
      .addTo(layer);
    if (evMode === 'route') {
      route.forEach((p, i) => {
        L.circleMarker([p[1], p[0]], { radius: 5, color: '#79c0ff', fillOpacity: 0.9 })
          .bindTooltip(`Sommet ${i + 1}`, { permanent: true, direction: 'top' })
          .addTo(layer);
      });
    }
  }

  // --- Destination --------------------------------------------------------
  if (ev.destinationLatitude != null && ev.destinationLongitude != null) {
    L.marker([ev.destinationLatitude, ev.destinationLongitude], {
      icon: L.divIcon({ className: '', html: '<div style="font-size:20px">🏁</div>', iconSize: [20, 20] }),
    }).bindPopup('<b>Destination</b>').addTo(layer);
  }

  // --- Points -------------------------------------------------------------
  for (const type of pointTypes) {
    const items = ev[type.key] || [];
    items.forEach((p, index) => {
      const isEditing = editingPoint && editingPoint.typeKey === type.key && editingPoint.index === index;
      const color = evColor(type.key);
      const isZone = type.key === 'safeZones';
      const radius = isZone ? Math.max(8, Number(p.radius) || 50) : 9;
      // Leaflet : `L.circleMarker` et `L.circle` ne sont PAS deplacables
      // (seuls les `L.marker` le sont). On utilise donc un marqueur
      // `draggable` par point, avec un cercle decoratif pour le rayon
      // des zones sures.
      if (isZone) {
        L.circle([p.lat, p.lng], { radius, color, fillOpacity: 0.12, weight: 2, interactive: false })
          .addTo(layer);
      }

      const size = isEditing ? 16 : 13;
      const icon = L.divIcon({
        className: '',
        html: '<div style="width:' + size + 'px;height:' + size + 'px;border-radius:50%;'
          + 'background:' + color + ';border:2px solid ' + (isEditing ? '#ffffff' : '#0d1117') + ';"></div>',
        iconSize: [size, size],
        iconAnchor: [size / 2, size / 2],
      });

      const shape = L.marker([p.lat, p.lng], { icon, draggable: true, title: p.label || type.label })
        .bindPopup(evPointPopup(type, p))
        .addTo(layer);

      shape.on('dragend', (e) => {
        const pos = e.target.getLatLng();
        movePointTo(type.key, index, pos.lat, pos.lng);
      });
      shape.on('click', () => editPoint(type.key, index));
    });
  }
}
/// Contenu de la bulle d info d un point.
function evPointPopup(type, p) {
  const rows = [`<b>${escapeHtml(p.label || type.label)}</b>`];
  rows.push(`<small>${escapeHtml(type.label)}</small>`);
  if (p.direction) rows.push(`Direction : ${escapeHtml(p.direction)}`);
  if (p.contact) rows.push(`Contact : ${escapeHtml(p.contact)}`);
  if (p.notes) rows.push(`Notes : ${escapeHtml(p.notes)}`);
  if (p.scheduledAt) rows.push(`Heure : ${escapeHtml(String(p.scheduledAt).slice(0, 16).replace('T', ' '))}`);
  if (p.radius != null) rows.push(`Rayon : ${escapeHtml(p.radius)} m`);
  rows.push(`<small>${Number(p.lat).toFixed(5)}, ${Number(p.lng).toFixed(5)}</small>`);
  return rows.join('<br>');
}

/// Parse une polyline GeoJSON en tableau de [lng, lat].
function parseRoute(routeGeoJson) {
  if (!routeGeoJson) return [];
  try {
    const parsed = JSON.parse(routeGeoJson);
    if (!Array.isArray(parsed)) return [];
    return parsed
      .filter(p => Array.isArray(p) && p.length >= 2)
      .map(p => [Number(p[0]), Number(p[1])])
      .filter(p => Number.isFinite(p[0]) && Number.isFinite(p[1]));
  } catch (_) {
    return [];
  }
}

/// Enregistre la nouvelle position d un point deplace (drag & drop).
async function movePointTo(typeKey, index, lat, lng) {
  const ev = currentEvent();
  if (!ev) return;
  try {
    const data = await evApi('PUT', `/${encodeURIComponent(ev.code)}/points/${typeKey}/${index}`, { lat, lng });
    mergeEvent(data.event);
    drawSelectedEvent();
    evStatus('Point deplace');
  } catch (e) {
    evStatus(e.message, true);
    drawSelectedEvent();
  }
}

// ---------------------------------------------------------------------------
// GESTION DU CLIC SUR LA CARTE (EDITION)
// ---------------------------------------------------------------------------

/// Gere un clic sur la carte selon le mode actif.
function handleEditorMapClick(lat, lng) {
  if (evMode === 'point') {
    evDraft = { lat, lng };
    updateModeIndicator();
    drawSelectedEvent();
    const sel = document.getElementById('ev-point-type');
    if (sel) sel.scrollIntoView({ block: 'nearest' });
  } else if (evMode === 'route') {
    routeDraft.push([lng, lat]);
    drawSelectedEvent();
    const info = document.getElementById('ev-route-info');
    if (info) info.textContent = `${routeDraft.length} sommet(s) — cliquez "Valider le trajet" pour enregistrer`;
  } else if (evMode === 'destination') {
    evDraft = { lat, lng };
    setDestinationFromMap();
  }
}

/// Active le mode « destination » (definition de la destination au clic).
function startDestinationPlacement() {
  if (!selectedEventCode) { evStatus('Selectionnez d abord un evenement', true); return; }
  evMode = 'destination';
  map.getContainer().style.cursor = 'crosshair';
  updateModeIndicator();
}

// ---------------------------------------------------------------------------
// INITIALISATION
// ---------------------------------------------------------------------------

/// Initialise l editeur d evenements (appele au demarrage du dashboard).
async function initEventsEditor() {
  if (!adminToken) return;
  await loadPointTypes();
  await loadEvents();
  renderEventList();
  renderEventDetails();
  renderPointList();
}

/// Recharge la liste des evenements (appele lors d une diffusion WS).
function onEventsChanged(events) {
  if (Array.isArray(events)) adminEvents = events;
  renderEventList();
  renderEventDetails();
  renderPointList();
  drawSelectedEvent();
}
