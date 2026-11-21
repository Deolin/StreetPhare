// server/src/services/mailer.js
//
// Service centralisé d'envoi d'emails pour StreetPhare :
//   - confirmation d'email des comptes administrateurs ;
//   - notification des administrateurs (nouvel événement soumis, etc.).
//
// Stratégie :
//   1. Si les variables d'environnement SMTP_* sont configurées et que le
//      paquet `nodemailer` est installé, l'email est expédié via SMTP.
//   2. Sinon (développement / test / SMTP indisponible), l'email est consigné
//      dans data/mail-outbox.log afin que le serveur reste fonctionnel.

const fs = require('fs');
const path = require('path');
const config = require('../config');

const OUTBOX_PATH = path.join(__dirname, '..', '..', 'data', 'mail-outbox.log');

const log = (category, message) => console.log(`[MAILER] [${category}] ${message}`);

/// Charge `nodemailer` uniquement s'il est installé et qu'un SMTP est configuré.
function loadNodemailer() {
  if (!config.smtpHost) return null;
  try {
    return require('nodemailer');
  } catch (_) {
    log('WARN', "paquet 'nodemailer' non installé — fallback outbox fichier.");
    return null;
  }
}

/// Consigne un email dans l'outbox fichier (mode dégradé sans SMTP).
function appendOutbox(entry) {
  try {
    const dir = path.dirname(OUTBOX_PATH);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.appendFileSync(OUTBOX_PATH, '==== EMAIL ====\n' + JSON.stringify(entry, null, 2) + '\n', 'utf-8');
  } catch (err) {
    log('ERROR', `Impossible d'écrire l'outbox : ${err.message}`);
  }
}

/// Envoie un email.
/// @param {string[]|string} to   destinataire(s)
/// @param {string} subject
/// @param {string} text          corps texte brut
/// @param {string} [html]        corps HTML (optionnel)
/// @returns {Promise<{sent:boolean, outbox?:boolean, messageId?:string}>}
async function sendMail({ to, subject, text, html }) {
  const recipients = Array.isArray(to) ? to : [to];
  const transporterLib = loadNodemailer();

  if (transporterLib && config.smtpHost) {
    try {
      const transporter = transporterLib.createTransport({
        host: config.smtpHost,
        port: config.smtpPort,
        secure: config.smtpPort === 465,
        auth: config.smtpUser ? { user: config.smtpUser, pass: config.smtpPass } : undefined,
      });

      const info = await transporter.sendMail({
        from: config.smtpFrom,
        to: recipients.join(', '),
        subject,
        text: text || '',
        html: html || undefined,
      });
      log('SEND', `Email envoyé à ${recipients.join(', ')} — ${info.messageId}`);
      return { sent: true, messageId: info.messageId };
    } catch (err) {
      log('ERROR', `Échec SMTP vers ${recipients.join(', ')} : ${err.message} — fallback outbox`);
    }
  }

  appendOutbox({
    at: new Date().toISOString(),
    from: config.smtpFrom,
    to: recipients,
    subject,
    text: text || '',
    html: html || '',
  });
  log('OUTBOX', `Email consigné pour ${recipients.join(', ')}`);
  return { sent: false, outbox: true };
}

module.exports = { sendMail };