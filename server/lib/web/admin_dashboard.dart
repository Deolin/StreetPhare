// server/lib/web/admin_dashboard.dart
//
// Dashboard d'administration sécurisé pour le serveur StreetPhare.
//
// Contient :
//   1. Setup wizard (premier lancement) : création du Master Admin.
//   2. Page de connexion (login).
//   3. Tableau de bord : gestion des comptes modérateurs.
//   4. Grille de permissions (matrice commandes × modérateurs).
//
// L'interface est servie comme HTML inline depuis le serveur Shelf.

const String adminDashboardHtml = r'''
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>StreetPhare — Admin Dashboard</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:system-ui,-apple-system,sans-serif;background:#1a1a2e;color:#eee;min-height:100vh}
header{background:#16213e;padding:16px 24px;display:flex;align-items:center;justify-content:space-between;border-bottom:2px solid #0f3460}
header h1{font-size:20px;color:#e94560}
header .user-info{font-size:13px;color:#aaa}
nav{display:flex;gap:8px;padding:12px 24px;background:#16213e;border-bottom:1px solid #0f3460}
nav a{color:#aaa;text-decoration:none;padding:6px 14px;border-radius:6px;font-size:13px;transition:all .2s}
nav a:hover,nav a.active{background:#e94560;color:#fff}
main{padding:24px;max-width:1400px;margin:0 auto}
.card{background:#16213e;border-radius:12px;padding:20px;border:1px solid #0f3460;margin-bottom:20px}
.card h2{font-size:16px;margin-bottom:12px;color:#e94560;display:flex;align-items:center;gap:8px}
.card h2 .badge{font-size:12px;color:#aaa;font-weight:normal}
table{width:100%;border-collapse:collapse;font-size:13px}
th,td{text-align:left;padding:10px 8px;border-bottom:1px solid #0f3460}
th{color:#aaa;font-weight:600;font-size:12px}
.btn{padding:7px 16px;border:none;border-radius:6px;cursor:pointer;font-size:13px;font-weight:600;transition:all .2s}
.btn-primary{background:#e94560;color:#fff}
.btn-primary:hover{background:#c73050}
.btn-outline{background:transparent;border:1px solid #e94560;color:#e94560}
.btn-outline:hover{background:#e9456015}
.btn-danger{background:#d32f2f;color:#fff}
.btn-danger:hover{background:#b71c1c}
.btn-sm{padding:4px 10px;font-size:11px}
.form-group{margin-bottom:14px}
.form-group label{display:block;font-size:13px;color:#aaa;margin-bottom:4px}
.form-group input{width:100%;padding:10px 12px;border-radius:6px;border:1px solid #0f3460;background:#1a1a2e;color:#eee;font-size:14px;font-family:inherit}
.form-group input:focus{outline:none;border-color:#e94560}
.setup-wizard{max-width:440px;margin:80px auto}
.setup-wizard .logo{text-align:center;margin-bottom:24px}
.setup-wizard .logo .icon{font-size:48px;margin-bottom:8px}
.login-form{max-width:400px;margin:80px auto}
.perm-grid{display:grid;grid-template-columns:auto repeat(2,1fr);gap:1px;background:#0f3460;border-radius:8px;overflow:hidden}
.perm-grid .cell{padding:8px 12px;background:#1a1a2e;text-align:center;font-size:12px}
.perm-grid .cell.header{background:#0f3460;color:#aaa;font-weight:600}
.perm-grid .cell.cmd{text-align:left;font-weight:500}
.perm-grid .cell input[type=checkbox]{width:16px;height:16px;cursor:pointer;accent-color:#e94560}
.perm-grid .cell input[type=checkbox]:disabled{opacity:0.4;cursor:not-allowed}
.empty-state{text-align:center;padding:32px;color:#666;font-style:italic}
.toast{position:fixed;bottom:20px;right:20px;background:#e94560;color:#fff;padding:12px 20px;border-radius:8px;font-size:13px;z-index:999;animation:slideIn .3s}
@keyframes slideIn{from{transform:translateX(100%);opacity:0}to{transform:translateX(0);opacity:1}}
.mono{font-family:monospace;font-size:11px}
.row{display:flex;gap:12px;align-items:center;flex-wrap:wrap}
.spacer{flex:1}
@media(max-width:768px){main{padding:12px}.perm-grid{font-size:10px}}
</style>
</head>
<body>
<header>
<h1>🚦 StreetPhare — Admin Server</h1>
<div class="user-info" id="userInfo"></div>
</header>
<nav id="navBar" style="display:none">
<a href="#" data-page="dashboard" class="active">📊 Dashboard</a>
<a href="#" data-page="accounts">👥 Comptes</a>
<a href="#" data-page="permissions">🔐 Permissions</a>
<a href="#" data-page="events">📋 Événements</a>
</nav>
<main id="mainContent"></main>

<script>
// ── État global ──────────────────────────────────────────────────────────────
let token = localStorage.getItem('sp_admin_token') || '';
let currentPage = 'dashboard';
let accounts = [];
let permissions = {};
let events = [];

const api = async (url, opts = {}) => {
  const headers = opts.headers || {};
  if (token) headers['Authorization'] = 'Bearer ' + token;
  if (opts.body && typeof opts.body === 'object') {
    headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(opts.body);
  }
  const r = await fetch(url, { ...opts, headers });
  if (r.status === 403) {
    const d = await r.json().catch(() => ({}));
    if (d.error === 'SESSION_EXPIRED' || d.error === 'SETUP_REQUIRED') {
      token = '';
      localStorage.removeItem('sp_admin_token');
      boot();
      return null;
    }
  }
  return r;
};

// ── Toast ─────────────────────────────────────────────────────────────────────
const toast = (msg, color = '#e94560') => {
  const el = document.createElement('div');
  el.className = 'toast';
  el.style.background = color;
  el.textContent = msg;
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 3000);
};

// ── Boot ──────────────────────────────────────────────────────────────────────
const boot = async () => {
  const r = await fetch('/api/health');
  const health = await r.json();
  if (!health.setup) {
    renderSetup();
    return;
  }
  if (!token) {
    renderLogin();
    return;
  }
  // Vérifie que le token est valide.
  const ar = await api('/api/health');
  if (!ar || ar.status === 403) {
    renderLogin();
    return;
  }
  document.getElementById('navBar').style.display = 'flex';
  document.getElementById('userInfo').textContent = '🔒 Connecté';
  await loadAll();
  renderPage();
};

// ── Navigation ───────────────────────────────────────────────────────────────
document.getElementById('navBar').addEventListener('click', (e) => {
  const a = e.target.closest('a[data-page]');
  if (!a) return;
  e.preventDefault();
  currentPage = a.dataset.page;
  document.querySelectorAll('nav a').forEach(l => l.classList.remove('active'));
  a.classList.add('active');
  renderPage();
});

// ── Chargement données ────────────────────────────────────────────────────────
const loadAll = async () => {
  try {
    const [ar, pr, er] = await Promise.all([
      api('/api/accounts'), api('/api/permissions'), api('/api/events')
    ]);
    if (ar && ar.ok) accounts = await ar.json();
    if (pr && pr.ok) permissions = (await pr.json()).permissions || {};
    if (er && er.ok) events = await er.json();
  } catch (e) { console.error(e); }
};

// ==========================================================================
// PAGE : Setup Wizard
// ==========================================================================
const renderSetup = () => {
  document.getElementById('mainContent').innerHTML = `
    <div class="setup-wizard">
      <div class="logo">
        <div class="icon">🚦</div>
        <h2 style="color:#e94560">Bienvenue sur StreetPhare</h2>
        <p style="color:#aaa;font-size:14px;margin-top:8px">
          Premier lancement détecté. Créez le compte <strong>Master Admin</strong> pour sécuriser le serveur.
        </p>
      </div>
      <div class="card">
        <div class="form-group">
          <label>Nom d'utilisateur</label>
          <input type="text" id="setupUser" placeholder="admin" autofocus>
        </div>
        <div class="form-group">
          <label>Mot de passe (min. 8 caractères)</label>
          <input type="password" id="setupPass" placeholder="••••••••">
        </div>
        <div class="form-group">
          <label>Confirmer le mot de passe</label>
          <input type="password" id="setupPassConfirm" placeholder="••••••••">
        </div>
        <button class="btn btn-primary" id="setupBtn" style="width:100%;padding:12px">
          🔒 Créer le compte administrateur
        </button>
        <p id="setupError" style="color:#e94560;font-size:12px;margin-top:8px;display:none"></p>
      </div>
    </div>
  `;
  document.getElementById('setupBtn').onclick = async () => {
    const u = document.getElementById('setupUser').value.trim();
    const p = document.getElementById('setupPass').value;
    const pc = document.getElementById('setupPassConfirm').value;
    const err = document.getElementById('setupError');
    if (!u || !p) { err.textContent = 'Tous les champs sont requis.'; err.style.display=''; return; }
    if (p !== pc) { err.textContent = 'Les mots de passe ne correspondent pas.'; err.style.display=''; return; }
    if (p.length < 8) { err.textContent = 'Le mot de passe doit contenir au moins 8 caractères.'; err.style.display=''; return; }
    err.style.display = 'none';
    const r = await fetch('/api/setup', {
      method: 'POST',
      headers: {'Content-Type':'application/json'},
      body: JSON.stringify({username:u,password:p})
    });
    if (r.ok) {
      toast('✅ Compte administrateur créé ! Redirection…', '#4caf50');
      setTimeout(() => location.reload(), 1500);
    } else {
      const d = await r.json();
      err.textContent = d.error || 'Erreur inconnue.';
      err.style.display = '';
    }
  };
};

// ==========================================================================
// PAGE : Login
// ==========================================================================
const renderLogin = () => {
  document.getElementById('mainContent').innerHTML = `
    <div class="login-form">
      <div class="logo" style="text-align:center;margin-bottom:24px">
        <div class="icon" style="font-size:48px">🚦</div>
        <h2 style="color:#e94560;margin-top:8px">Connexion</h2>
      </div>
      <div class="card">
        <div class="form-group">
          <label>Nom d'utilisateur</label>
          <input type="text" id="loginUser" placeholder="admin" autofocus>
        </div>
        <div class="form-group">
          <label>Mot de passe</label>
          <input type="password" id="loginPass" placeholder="••••••••">
        </div>
        <button class="btn btn-primary" id="loginBtn" style="width:100%;padding:12px">
          🔑 Se connecter
        </button>
        <p id="loginError" style="color:#e94560;font-size:12px;margin-top:8px;display:none"></p>
      </div>
    </div>
  `;
  document.getElementById('loginPass').onkeydown = (e) => { if (e.key === 'Enter') document.getElementById('loginBtn').click(); };
  document.getElementById('loginBtn').onclick = async () => {
    const u = document.getElementById('loginUser').value.trim();
    const p = document.getElementById('loginPass').value;
    const err = document.getElementById('loginError');
    if (!u || !p) { err.textContent = 'Identifiants requis.'; err.style.display=''; return; }
    err.style.display = 'none';
    const r = await fetch('/api/login', {
      method:'POST', headers:{'Content-Type':'application/json'},
      body:JSON.stringify({username:u,password:p})
    });
    if (r.ok) {
      const d = await r.json();
      token = d.token;
      localStorage.setItem('sp_admin_token', token);
      location.reload();
    } else {
      const d = await r.json();
      err.textContent = d.error || 'Identifiants invalides.';
      err.style.display = '';
    }
  };
};

// ==========================================================================
// PAGE : Dashboard
// ==========================================================================
const renderDashboard = () => {
  document.getElementById('mainContent').innerHTML = `
    <div class="card">
      <h2>📊 Vue d'ensemble</h2>
      <div class="row">
        <div class="card" style="flex:1;text-align:center">
          <h2 style="font-size:32px;margin:0;color:#4fc3f7">${events.length}</h2>
          <p style="color:#aaa;font-size:12px">Événements</p>
        </div>
        <div class="card" style="flex:1;text-align:center">
          <h2 style="font-size:32px;margin:0;color:#81c784">${accounts.length}</h2>
          <p style="color:#aaa;font-size:12px">Comptes</p>
        </div>
        <div class="card" style="flex:1;text-align:center">
          <h2 style="font-size:32px;margin:0;color:#ffb74d">${Object.keys(permissions).length}</h2>
          <p style="color:#aaa;font-size:12px">Permissions configurées</p>
        </div>
      </div>
    </div>
  `;
};

// ==========================================================================
// PAGE : Comptes
// ==========================================================================
const renderAccounts = () => {
  const rows = accounts.map(a => `
    <tr>
      <td><strong>${escapeHtml(a.username)}</strong></td>
      <td><span class="badge" style="color:${a.role==='admin'?'#e94560':'#4fc3f7'}">${a.role}</span></td>
      <td class="mono">${a.id.substring(0,8)}…</td>
      <td>${new Date(a.created_at).toLocaleDateString()}</td>
      <td>
        ${a.role !== 'admin' ? `
          <button class="btn btn-danger btn-sm" onclick="deleteAccount('${a.id}')">🗑 Supprimer</button>
        ` : '<span style="color:#aaa;font-size:11px">Admin</span>'}
      </td>
    </tr>
  `).join('');

  document.getElementById('mainContent').innerHTML = `
    <div class="card">
      <h2>👥 Comptes <span class="badge">${accounts.length} compte(s)</span></h2>
      <div class="row" style="margin-bottom:16px">
        <button class="btn btn-primary" onclick="showCreateModerator()">＋ Nouveau modérateur</button>
      </div>
      ${accounts.length === 0 ? '<div class="empty-state">Aucun compte modérateur</div>' : `
        <table><thead><tr><th>Nom</th><th>Rôle</th><th>ID</th><th>Créé le</th><th>Actions</th></tr></thead><tbody>${rows}</tbody></table>
      `}
    </div>
    <div id="modalSlot"></div>
  `;
};

window.deleteAccount = async (id) => {
  if (!confirm('Supprimer ce compte ? Toutes ses sessions seront invalidées.')) return;
  const r = await api('/api/accounts/' + id, { method: 'DELETE' });
  if (r && r.ok) { toast('✅ Compte supprimé.', '#4caf50'); await loadAll(); renderPage(); }
  else { toast('❌ Échec suppression.', '#d32f2f'); }
};

window.showCreateModerator = () => {
  document.getElementById('modalSlot').innerHTML = `
    <div style="position:fixed;inset:0;background:#0008;display:flex;align-items:center;justify-content:center;z-index:10" onclick="this.remove()">
      <div class="card" style="width:380px" onclick="event.stopPropagation()">
        <h2>＋ Créer un modérateur</h2>
        <div class="form-group"><label>Nom d'utilisateur</label><input id="newModUser" placeholder="moderator1"></div>
        <div class="form-group"><label>Mot de passe (min. 6 caractères)</label><input type="password" id="newModPass" placeholder="••••••"></div>
        <div class="row">
          <button class="btn btn-primary" onclick="createModerator()">Créer</button>
          <button class="btn btn-outline" onclick="document.getElementById('modalSlot').innerHTML=''">Annuler</button>
        </div>
      </div>
    </div>
  `;
};

window.createModerator = async () => {
  const u = document.getElementById('newModUser').value.trim();
  const p = document.getElementById('newModPass').value;
  if (!u || !p) { toast('Champs requis.'); return; }
  if (p.length < 6) { toast('Mot de passe trop court (min 6).'); return; }
  const r = await api('/api/accounts', { method:'POST', body:{username:u,password:p} });
  if (r && r.ok) { toast('✅ Modérateur créé !', '#4caf50'); await loadAll(); renderPage(); }
  else { const d = r ? await r.json() : {}; toast('❌ '+(d.error||'Erreur')); }
};

// ==========================================================================
// PAGE : Permissions (grille)
// ==========================================================================
const renderPermissions = () => {
  const commands = Object.keys(permissions).sort();
  if (commands.length === 0) {
    document.getElementById('mainContent').innerHTML = '<div class="card"><h2>🔐 Permissions</h2><div class="empty-state">Aucune commande configurée</div></div>';
    return;
  }
  const rows = commands.map(cmd => {
    const mod = permissions[cmd]?.moderator ?? false;
    return `
      <div class="cell cmd">${cmd}</div>
      <div class="cell"><input type="checkbox" checked disabled></div>
      <div class="cell"><input type="checkbox" ${mod?'checked':''}
        onchange="togglePerm('${cmd}', this.checked)"></div>
    `;
  }).join('');

  document.getElementById('mainContent').innerHTML = `
    <div class="card">
      <h2>🔐 Grille de permissions <span class="badge">${commands.length} commandes</span></h2>
      <p style="color:#aaa;font-size:12px;margin-bottom:16px">
        Cochez les commandes autorisées pour les <strong>modérateurs</strong>. L'administrateur a toujours tous les droits.
      </p>
      <div class="perm-grid">
        <div class="cell header">Commande</div>
        <div class="cell header">Admin</div>
        <div class="cell header">Modérateur</div>
        ${rows}
      </div>
      <div class="row" style="margin-top:16px">
        <span class="spacer"></span>
        <button class="btn btn-outline btn-sm" onclick="resetPermissions()">↺ Réinitialiser</button>
      </div>
    </div>
  `;
};

window.togglePerm = async (cmd, allowed) => {
  const r = await api('/api/permissions', {
    method:'PUT', body:{command:cmd, role:'moderator', allowed}
  });
  if (r && r.ok) { toast(`✅ ${cmd} → ${allowed?'autorisé':'bloqué'}`, allowed?'#4caf50':'#ff9800'); }
  else { toast('❌ Erreur mise à jour'); await loadAll(); renderPage(); }
};

window.resetPermissions = async () => {
  if (!confirm('Réinitialiser toutes les permissions aux valeurs par défaut ?')) return;
  const r = await api('/api/permissions/reset', { method:'POST' });
  if (r && r.ok) { toast('✅ Permissions réinitialisées.', '#4caf50'); await loadAll(); renderPage(); }
};

// ==========================================================================
// PAGE : Événements (dashboard admin existant)
// ==========================================================================
const renderEvents = () => {
  const rows = events.map(e => `
    <tr>
      <td><strong>${escapeHtml(e.code)}</strong></td>
      <td>${escapeHtml(e.name)}</td>
      <td class="mono">${(e.created_at||'').substring(0,10)}</td>
      <td class="row">
        <button class="btn btn-outline btn-sm" onclick="editEvent('${e.id}')">✏️</button>
        <button class="btn btn-outline btn-sm" onclick="showQr('${e.code}')">📱 QR</button>
        <button class="btn btn-danger btn-sm" onclick="deleteEvent('${e.id}')">🗑</button>
      </td>
    </tr>
  `).join('');
  document.getElementById('mainContent').innerHTML = `
    <div class="card">
      <h2>📋 Événements <span class="badge">${events.length}</span></h2>
      <div class="row" style="margin-bottom:12px">
        <button class="btn btn-primary" onclick="createEvent()">＋ Nouvel événement</button>
      </div>
      ${events.length===0?'<div class="empty-state">Aucun événement</div>':`<table><thead><tr><th>Code</th><th>Nom</th><th>Créé le</th><th>Actions</th></tr></thead><tbody>${rows}</tbody></table>`}
    </div>
  `;
};

window.createEvent = () => { const n = prompt("Nom de l'événement :"); if (!n) return;
  api('/api/events', { method:'POST', body:{name:n} }).then(r => r && r.ok ? loadAll().then(renderPage) : null); };
window.editEvent = (id) => { const e = events.find(x => x.id === id); if (!e) return;
  const n = prompt('Nom :', e.name); if (!n) return;
  api('/api/events', { method:'POST', body:{...e,name:n,_action:'update'} }).then(r => r && r.ok ? loadAll().then(renderPage) : null); };
window.deleteEvent = (id) => { if (!confirm('Supprimer ?')) return;
  api('/api/events', { method:'POST', body:{id,_action:'delete'} }).then(r => r && r.ok ? loadAll().then(renderPage) : null); };
window.showQr = async (code) => { const r = await api('/api/events/' + code + '/qr');
  if (!r || !r.ok) return; const d = await r.json();
  const w = window.open('','_blank','width=400,height=400'); w.document.write('<img src="'+d.qr+'" style="width:100%"><p style="text-align:center;font-family:monospace">'+code+'</p>'); };

// ==========================================================================
// Router
// ==========================================================================
const renderPage = () => {
  switch (currentPage) {
    case 'accounts': renderAccounts(); break;
    case 'permissions': renderPermissions(); break;
    case 'events': renderEvents(); break;
    default: renderDashboard();
  }
};

const escapeHtml = (s) => (s||'').replace(/&/g,'&').replace(/</g,'<').replace(/>/g,'>');

// ── Démarrage ────────────────────────────────────────────────────────────────
boot();
</script>
</body>
</html>
''';