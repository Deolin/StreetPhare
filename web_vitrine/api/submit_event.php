<?php
/**
 * StreetPhare — Soumission d'un nouvel événement (streetphare.be)
 *
 * Point d'entrée POST pour la page vitrine « Créer un événement ».
 *  1. Valide les champs obligatoires ;
 *  2. Consigne une copie locale ;
 *  3. Envoie un email de notification à l'administrateur du site
 *     (contact@streetphare.be) ;
 *  4. Transfère la soumission au serveur StreetPhare (streetphare.ddns.net)
 *     où elle sera placée « en attente de validation » dans la section
 *     administration « Événements ».
 *
 * ⚠️ NON-ANONYMAT DE L'ORGANISATEUR :
 * Contrairement aux participants qui restent anonymes, l'administrateur d'un
 * événement est identifiable : email ET numéro de téléphone sont obligatoires.
 * Cette traçabilité vise à désigner un responsable joignable et à prévenir
 * les usages malhonnêtes ou illégaux de la plateforme.
 */

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

define('PRIMARY_HOST', 'streetphare.ddns.net');
define('PRIMARY_PORT', 3000);
define('CONTACT_EMAIL', 'contact@streetphare.be');
define('SUBMISSIONS_DIR', __DIR__ . '/../event_submissions/');
define('TRANSFER_TIMEOUT', 10);

// ---------------------------------------------------------------------------
// CORS & méthode
// ---------------------------------------------------------------------------

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['error' => 'Méthode non autorisée. Utilisez POST.']);
    exit;
}

// ---------------------------------------------------------------------------
// Lecture du corps JSON
// ---------------------------------------------------------------------------

$raw   = file_get_contents('php://input');
$input = json_decode($raw, true);

if (!is_array($input)) {
    http_response_code(400);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['error' => 'Corps JSON invalide.']);
    exit;
}

// ---------------------------------------------------------------------------
// Normalisation & validation
// ---------------------------------------------------------------------------

function clean(string $v): string {
    return trim(strip_tags($v));
}

$email     = clean($input['email']     ?? '');
$phone     = clean($input['phone']     ?? '');
$pseudo    = clean($input['pseudo']    ?? '');
$name      = clean($input['name']      ?? '');
$startDate = clean($input['startDate'] ?? '');
$city      = clean($input['city']      ?? '');
$summary   = clean($input['summary']   ?? '');

$errors = [];
if (!filter_var($email, FILTER_VALIDATE_EMAIL)) $errors[] = 'Adresse email invalide.';
if ($phone === '') $errors[] = 'Le numéro de contact est obligatoire (organisateur identifiable).';
if ($name === '')  $errors[] = 'Le nom de l\'événement est requis.';
if ($startDate === '') $errors[] = 'La date de début est requise.';
if ($city === '')  $errors[] = 'La ville est requise.';

if ($errors) {
    http_response_code(422);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['error' => implode(' ', $errors)], JSON_UNESCAPED_UNICODE);
    exit;
}

$submissionId = date('Ymd_His') . '_' . bin2hex(random_bytes(4));
$timestamp    = date('Y-m-d H:i:s');

// ---------------------------------------------------------------------------
// Étape 1 : Sauvegarde locale
// ---------------------------------------------------------------------------

if (!is_dir(SUBMISSIONS_DIR)) {
    @mkdir(SUBMISSIONS_DIR, 0755, true);
}

$localBody = <<<TXT
========================================
SOUMISSION D'ÉVÉNEMENT StreetPhare
ID         : $submissionId
Date       : $timestamp
========================================
Email admin : $email
Téléphone   : $phone
Pseudo      : $pseudo
Événement   : $name
Début       : $startDate
Ville       : $city
Résumé      : $summary
========================================
TXT;

$localFile = SUBMISSIONS_DIR . $submissionId . '.txt';
$savedLocal = @file_put_contents($localFile, $localBody, LOCK_EX);

// ---------------------------------------------------------------------------
// Étape 2 : Notification mail à l'administrateur du site
// ---------------------------------------------------------------------------

$mailSubject = '[StreetPhare] Nouvel événement soumis — ' . $name;
$mailBody = <<<TXT
Une nouvelle demande de création d'événement a été soumise sur le site vitrine.

Nom de l'événement : $name
Date de début       : $startDate
Ville               : $city
Pseudo              : $pseudo
Email admin         : $email
Numéro de contact   : $phone

Résumé :
$summary

---
Cette demande est en attente de validation dans la section administration « Événements ».
TXT;

$mailHeaders = [
    'From: StreetPhare <no-reply@streetphare.be>',
    'Reply-To: ' . $email,
    'Content-Type: text/plain; charset=UTF-8',
    'X-Mailer: PHP/' . phpversion(),
];

$mailSent = @mail(CONTACT_EMAIL, $mailSubject, $mailBody, implode("\r\n", $mailHeaders));

// ---------------------------------------------------------------------------
// Étape 3 : Transfert au serveur StreetPhare (best-effort)
// ---------------------------------------------------------------------------

$forwarded    = false;
$forwardError = '';

$payload = json_encode([
    'email'     => $email,
    'phone'     => $phone,
    'pseudo'    => $pseudo,
    'name'      => $name,
    'startDate' => $startDate,
    'city'      => $city,
    'summary'   => $summary,
], JSON_UNESCAPED_UNICODE);

$ch = curl_init();
curl_setopt_array($ch, [
    CURLOPT_URL            => 'http://' . PRIMARY_HOST . ':' . PRIMARY_PORT . '/api/events/submit',
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST           => true,
    CURLOPT_POSTFIELDS     => $payload,
    CURLOPT_HTTPHEADER     => ['Content-Type: application/json'],
    CURLOPT_CONNECTTIMEOUT => 5,
    CURLOPT_TIMEOUT        => TRANSFER_TIMEOUT,
]);

$response = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$curlErr  = curl_error($ch);
curl_close($ch);

if ($response !== false && $httpCode >= 200 && $httpCode < 300) {
    $forwarded = true;
} else {
    $forwardError = $curlErr ?: "HTTP $httpCode";
}

// ---------------------------------------------------------------------------
// Réponse
// ---------------------------------------------------------------------------

http_response_code($savedLocal !== false ? 201 : 500);
header('Content-Type: application/json; charset=utf-8');
echo json_encode([
    'success'       => true,
    'submission_id' => $submissionId,
    'saved_local'   => $savedLocal !== false,
    'mail_sent'     => $mailSent,
    'forwarded'     => $forwarded,
    'forward_error' => $forwarded ? null : $forwardError,
    'timestamp'     => $timestamp,
], JSON_UNESCAPED_UNICODE);