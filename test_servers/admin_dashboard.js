// test_servers/admin_dashboard.js
// Alias de secours — redirige vers admin_dashboard_v2.js
// pour éviter l'erreur MODULE_NOT_FOUND si un script ou
// un développeur référence l'ancien nom sans le suffixe _v2.
'use strict';

const path = require('path');

console.warn('[admin_dashboard] ⚠️  Alias de secours actif.');
console.warn('[admin_dashboard] → Redirection vers admin_dashboard_v2.js');

// Déclenche le vrai dashboard v2
require(path.join(__dirname, 'admin_dashboard_v2.js'));