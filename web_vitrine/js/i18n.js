/**
 * StreetPhare — Internationalisation légère (i18n)
 * ================================================
 * Charge les traductions FR/EN et les applique au DOM.
 * Préserve la langue choisie dans localStorage.
 *
 * Usage HTML :
 *   <span data-i18n="hero.pill">Open Source · Gratuit · Sans traçage</span>
 *   <span data-i18n="hero.stat1_val">100%</span>
 */

(function () {
  'use strict';

  const SUPPORTED_LANGS = ['fr', 'en', 'nl', 'de'];
  const LOCALES_DIR = 'locales';
  const STORAGE_KEY = 'streetphare_lang';
  const DATA_ATTR = 'data-i18n';

  let currentLang = 'fr';
  let translations = {};

  // ════════════════════════════════════════════════════════════════
  //  DÉTECTION DE LA LANGUE INITIALE
  // ════════════════════════════════════════════════════════════════

  function detectLang() {
    // 1. localStorage
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored && SUPPORTED_LANGS.includes(stored)) return stored;

    // 2. préférence navigateur
    const navLang = (navigator.language || '').slice(0, 2).toLowerCase();
    if (SUPPORTED_LANGS.includes(navLang)) return navLang;

    // 3. défaut français
    return 'fr';
  }

  // ════════════════════════════════════════════════════════════════
  //  CHARGEMENT DU FICHIER DE LANGUE
  // ════════════════════════════════════════════════════════════════

  function loadTranslations(lang) {
    // Chemin relatif vers le dossier locales/
    // Si la page est dans un sous-dossier (ex: /sub/page.html), on remonte
    const path = document.location.pathname;
    const base = (path.lastIndexOf('/') > 0) ? '../' : '';
    const url = `${base}${LOCALES_DIR}/${lang}.json`;

    // Cache-breaker en dev
    const cacheBuster = location.hostname === 'localhost' ? `?v=${Date.now()}` : '';
    return fetch(url + cacheBuster)
      .then(r => {
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        return r.json();
      });
  }

  // ════════════════════════════════════════════════════════════════
  //  APPLICATION DES TRADUCTIONS AU DOM
  // ════════════════════════════════════════════════════════════════

  function resolve(obj, path) {
    return path.split('.').reduce((o, k) => (o && o[k] !== undefined) ? o[k] : null, obj);
  }

  function applyTranslations() {
    // 1. Éléments avec data-i18n
    document.querySelectorAll(`[${DATA_ATTR}]`).forEach(el => {
      const key = el.getAttribute(DATA_ATTR);
      const value = resolve(translations, key);
      if (value !== null && value !== undefined) {
        // Si c'est un <input> avec placeholder
        if (el.tagName === 'INPUT' && el.getAttribute('data-i18n-type') === 'placeholder') {
          el.setAttribute('placeholder', String(value));
        } else {
          el.innerHTML = String(value);
        }
      }
    });

    // 2. Mise à jour de l'attribut lang de <html>
    document.documentElement.lang = currentLang;

    // 3. Mise à jour du sélecteur de langue
    document.querySelectorAll('.lang-switch').forEach(btn => {
      const btnLang = btn.getAttribute('data-lang');
      if (btnLang === currentLang) {
        btn.classList.add('active');
        btn.setAttribute('aria-pressed', 'true');
      } else {
        btn.classList.remove('active');
        btn.setAttribute('aria-pressed', 'false');
      }
    });

    // 4. Dispatch un événement pour les mises à jour dynamiques
    document.dispatchEvent(new CustomEvent('i18n-updated', {
      detail: { lang: currentLang, translations }
    }));
  }

  // ════════════════════════════════════════════════════════════════
  //  CHANGEMENT DE LANGUE
  // ════════════════════════════════════════════════════════════════

  function setLang(lang) {
    if (!SUPPORTED_LANGS.includes(lang)) return;
    if (lang === currentLang) return;

    loadTranslations(lang).then(data => {
      currentLang = lang;
      translations = data;
      localStorage.setItem(STORAGE_KEY, lang);
      applyTranslations();
    }).catch(err => {
      console.warn(`[i18n] Échec chargement de la langue "${lang}":`, err.message);
    });
  }

  // ════════════════════════════════════════════════════════════════
  //  INITIALISATION
  // ════════════════════════════════════════════════════════════════

  function init() {
    currentLang = detectLang();
    loadTranslations(currentLang)
      .then(data => {
        translations = data;
        applyTranslations();
      })
      .catch(err => {
        console.warn('[i18n] Échec chargement initial, fallback FR:', err.message);
        // Fallback : recharger en français
        if (currentLang !== 'fr') {
          return loadTranslations('fr').then(data => {
            currentLang = 'fr';
            translations = data;
            localStorage.setItem(STORAGE_KEY, 'fr');
            applyTranslations();
          });
        }
      });

    // Gestion des clics sur les boutons de langue
    document.addEventListener('click', e => {
      const btn = e.target.closest('.lang-switch');
      if (!btn) return;
      const lang = btn.getAttribute('data-lang');
      if (lang) setLang(lang);
    });

    // API publique
    window.StreetPhareI18n = {
      getLang: () => currentLang,
      setLang,
      t: (key) => resolve(translations, key) || key,
    };
  }

  // Démarrage différé pour laisser le DOM se construire
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();