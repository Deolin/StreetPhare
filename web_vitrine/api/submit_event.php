<?php
/**
 * StreetPhare — Soumission d'un nouvel événement (streetphare.be)
 *
 * Point d'entrée POST pour la page vitrine « Créer un événement ».
 *  1. Valide les champs obligatoires ;
 *  2. Consigne une copie locale (sauvegarde de secours) ;
 *  3. Transfère la soumission au serveur StreetPhare en HTTPS
 *     (streetphare.ddns.net /api/events/submit), lequel :
 *       - place la demande « en attente de validation » (administration) ;
 *       - envoie la notification email via SMTP authentifié.
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
// (Notification email retirée : l'ancien mail() PHP non authentifié était
// bloqué par Cloudflare. L'email de notification est désormais envoyé par le
// serveur StreetPhare via SMTP authentifié lors du transfert ci-dessous.)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Étape 2 : Transfert au serveur StreetPhare
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
    // Le serveur StreetPhare est exposé UNIQUEMENT en HTTPS (port 443) à
    // travers Cloudflare/Caddy. L'ancien http://...:3000 (port brut) était
    // bloqué par Cloudflare → la soumission n'était jamais prise en compte
    // côté administration.
    CURLOPT_URL            => 'https://' . PRIMARY_HOST . '/api/events/submit',
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST           => true,
    CURLOPT_POSTFIELDS     => $payload,
    CURLOPT_HTTPHEADER     => ['Content-Type: application/json'],
    CURLOPT_CONNECTTIMEOUT => 5,
    CURLOPT_TIMEOUT        => TRANSFER_TIMEOUT,
    CURLOPT_SSL_VERIFYPEER => true,
    CURLOPT_SSL_VERIFYHOST => 2,
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

// Réponse HONNÊTE : on ne prétend pas que tout va bien si le transfert vers le
// serveur StreetPhare a échoué. Une copie locale reste conservée en secours
// (event_submissions/), mais l'utilisateur est averti de l'échec.
header('Content-Type: application/json; charset=utf-8');
if ($forwarded) {
    http_response_code(201);
    echo json_encode([
        'success'       => true,
        'submission_id' => $submissionId,
        'saved_local'   => $savedLocal !== false,
        'forwarded'     => true,
        'timestamp'     => $timestamp,
    ], JSON_UNESCAPED_UNICODE);
} else {
    http_response_code(502);
    echo json_encode([
        'success'       => false,
        'error'         => 'La demande a été conservée localement mais n\'a pas pu être transmise au serveur StreetPhare' . ($forwardError ? ' (' . $forwardError . ').' : '.'),
        'submission_id' => $submissionId,
        'saved_local'   => $savedLocal !== false,
        'forwarded'     => false,
        'forward_error' => $forwardError,
        'timestamp'     => $timestamp,
    ], JSON_UNESCAPED_UNICODE);
}