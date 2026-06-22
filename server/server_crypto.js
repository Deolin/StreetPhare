// test_servers/server_crypto.js
//
// Module cryptographique PARTAGÉ entre les deux serveurs Node.js de
// StreetPhare. Il est volontairement MIRROIR de l'implémentation
// `CryptoUtils` côté Dart (lib/database/crypto_utils.dart) :
//
//   * AES-256-CBC + HMAC-SHA256
//   * Format de sortie : base64Url PADDED ( IV(16) || MAC(32) || CIPHER )
//
// La clé AES est dérivée du SHA-256 de la master passphrase
// (même convention que le client Flutter). Pour le test local on
// utilise la même chaîne 'streetphare-dev-key-CHANGE_ME_IN_PROD' que
// dans main.dart, ce qui permet au FailoverManager Dart de
// déchiffrer réellement les adresses que les serveurs lui renvoient.
//
// ============================================================================
// IMPORTANT — sur le calcul du MAC
// ============================================================================
// Le package Dart `cryptography` (utilisé dans `crypto_utils.dart`)
// calcule le MAC de cette façon pour `AesCbc + Hmac.sha256` :
//
//     mac = HMAC_SHA256(key, ciphertext)
//
// Il NE PRÉFIXE PAS l'IV dans le calcul. C'est seulement le
// format de sérialisation Dart (custom, voir `CryptoUtils.encryptAddress`)
// qui stocke `IV || MAC || CIPHER`.
//
// Donc pour produire un ciphertext DÉCHIFFRABLE par le client
// Dart, on doit :
//   1) chiffrer avec AES-256-CBC
//   2) calculer HMAC_SHA256(key, CIPHER)        ← MAC = HMAC(cipher)
//   3) retourner base64Url PADDED (IV || MAC || CIPHER)
//
// ============================================================================
// IMPORTANT — sur le padding base64Url
// ============================================================================
// Node, en mode `base64url`, omet le padding `=`. Mais le
// décodeur de `dart:convert` (`base64Url.decode`) EXIGE une
// chaîne de longueur multiple de 4. On ajoute donc le padding
// `=` manquant pour rester compatible.
//
// ============================================================================
// IMPORTANT : ce module est UNIQUEMENT destiné à l'environnement
// de test local. En production, la clé maître ne doit PAS être
// dans le code.
// ============================================================================

const crypto = require('crypto');

/**
 * Dérive une clé AES-256 à partir d'une passphrase (SHA-256).
 * @param {string} passphrase
 * @returns {Buffer} clé de 32 octets
 */
function deriveAesKey(passphrase) {
  return crypto.createHash('sha256').update(passphrase, 'utf8').digest();
}

/**
 * Convertit un Buffer en chaîne base64Url AVEC padding `=`.
 * (Node en `base64url` retire le padding par défaut, Dart non.)
 */
function toBase64UrlPadded(buf) {
  let s = buf.toString('base64url');
  // base64url utilise '-' et '_' au lieu de '+' et '/'.
  // toString('base64url') fait déjà la conversion ; on n'a
  // qu'à rajouter le padding manquant.
  while (s.length % 4 !== 0) s += '=';
  return s;
}

/**
 * Convertit une chaîne base64Url (paddée ou non) en Buffer.
 * Tolère l'absence de padding.
 */
function fromBase64Url(s) {
  // Retire le padding éventuel pour que `base64url` Node accepte.
  const stripped = s.replace(/=+$/, '');
  return Buffer.from(stripped, 'base64url');
}

/**
 * Chiffre une adresse (URL) au format StreetPhare :
 *   base64Url( IV(16) || HMAC-SHA256(32) || AES-CBC-CIPHER )
 *
 * Le HMAC est calculé sur le CIPHERTEXT seul (et non IV‖CIPHER),
 * pour correspondre EXACTEMENT au comportement du package
 * `cryptography` Dart utilisé par `CryptoUtils.encryptAddress`.
 *
 * @param {string} address
 * @param {string} passphrase
 * @returns {string} ciphertext base64Url paddé
 */
function encryptAddress(address, passphrase) {
  const key = deriveAesKey(passphrase);
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv('aes-256-cbc', key, iv);
  const enc = Buffer.concat([
    cipher.update(address, 'utf8'),
    cipher.final(),
  ]);
  // HMAC = HMAC_SHA256(key, CIPHER)  ← identique à `cryptography`
  const mac = crypto.createHmac('sha256', key).update(enc).digest();
  return toBase64UrlPadded(Buffer.concat([iv, mac, enc]));
}

/**
 * Déchiffre une adresse chiffrée par `encryptAddress`.
 * Vérifie le HMAC en mode constant-time avant de déchiffrer.
 *
 * @param {string} cipherB64Url
 * @param {string} passphrase
 * @returns {string} adresse en clair
 */
function decryptAddress(cipherB64Url, passphrase) {
  const combined = fromBase64Url(cipherB64Url);
  if (combined.length < 16 + 32 + 16) {
    throw new Error('Ciphertext invalide');
  }
  const iv = combined.slice(0, 16);
  const mac = combined.slice(16, 48);
  const cipher = combined.slice(48);

  const key = deriveAesKey(passphrase);
  // HMAC = HMAC_SHA256(key, CIPHER)
  const expectedMac = crypto.createHmac('sha256', key).update(cipher).digest();
  if (
    expectedMac.length !== mac.length ||
    !crypto.timingSafeEqual(expectedMac, mac)
  ) {
    throw new Error('MAC invalide (intégrité compromise)');
  }
  const decipher = crypto.createDecipheriv('aes-256-cbc', key, iv);
  const dec = Buffer.concat([decipher.update(cipher), decipher.final()]);
  return dec.toString('utf8');
}

module.exports = {
  deriveAesKey,
  encryptAddress,
  decryptAddress,
  toBase64UrlPadded,
  fromBase64Url,
};
