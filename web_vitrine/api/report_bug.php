<?php
/**
 * StreetPhare — Réception des rapports de bugs (streetphare.be)
 *
 * Point d'entrée POST pour les rapports de bugs envoyés par l'application
 * mobile.  Consigne le rapport dans un fichier texte local sur le serveur
 * web PHP.  Si le serveur No-IP principal est en ligne, lui transfère
 * également une copie du rapport.
 *
 * Utilisation :
 *   POST https://streetphare.be/api/report_bug.php
 *
 * Corps JSON attendu :
 * {
 *   "app_version": "2.2.0+1",
 *   "platform": "android",
 *   "log": "...",
 *   "description": "...",
 *   "contact": "..."
 * }
 */

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

// Adresse No-IP du serveur principal
define('PRIMARY_HOST', 'streetphare-principal.ddns.net');
define('PRIMARY_PORT', 3000);

// Dossier de stockage des rapports
define('REPORTS_DIR', __DIR__ . '/../bug_reports/');

// Timeout de transfert vers le serveur principal
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

if (!$input) {
    http_response_code(400);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['error' => 'Corps JSON invalide.']);
    exit;
}

// ---------------------------------------------------------------------------
// Construction du rapport textuel
// ---------------------------------------------------------------------------

$timestamp   = date('Y-m-d H:i:s');
$reportId    = date('Ymd_His') . '_' . bin2hex(random_bytes(4));
$appVersion  = $input['app_version']  ?? 'inconnue';
$platform    = $input['platform']     ?? 'inconnue';
$description = $input['description']  ?? '';
$contact     = $input['contact']      ?? '';
$log         = $input['log']          ?? '';

$reportBody = <<<REPORT
========================================
RAPPORT DE BUG StreetPhare
ID        : $reportId
Date      : $timestamp
Version   : $appVersion
Plateforme: $platform
Contact   : $contact
========================================

DESCRIPTION
-----------
$description

LOG APPLICATIF
--------------
$log

========================================
REPORT;

// ---------------------------------------------------------------------------
// Étape 1 : Sauvegarde locale
// ---------------------------------------------------------------------------

if (!is_dir(REPORTS_DIR)) {
    @mkdir(REPORTS_DIR, 0755, true);
}

$localFile = REPORTS_DIR . $reportId . '.txt';
$saved = @file_put_contents($localFile, $reportBody, LOCK_EX);

if ($saved === false) {
    // Échec sauvegarde locale — on répond quand même
    error_log("StreetPhare report_bug: impossible d'écrire $localFile");
}

// ---------------------------------------------------------------------------
// Étape 2 : Transfert vers le serveur No-IP principal (best-effort)
// ---------------------------------------------------------------------------

$forwarded = false;
$forwardError = '';

$ch = curl_init();
curl_setopt_array($ch, [
    CURLOPT_URL            => 'http://' . PRIMARY_HOST . ':' . PRIMARY_PORT . '/api/bug_report',
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST           => true,
    CURLOPT_POSTFIELDS     => $raw,
    CURLOPT_HTTPHEADER     => ['Content-Type: application/json'],
    CURLOPT_CONNECTTIMEOUT => 5,
    CURLOPT_TIMEOUT        => TRANSFER_TIMEOUT,
]);

$response = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
$error    = curl_error($ch);
curl_close($ch);

if ($response !== false && $httpCode >= 200 && $httpCode < 300) {
    $forwarded = true;
} else {
    $forwardError = $error ?: "HTTP $httpCode";
}

// ---------------------------------------------------------------------------
// Réponse
// ---------------------------------------------------------------------------

$statusCode = $saved !== false ? 201 : 500;

http_response_code($statusCode);
header('Content-Type: application/json; charset=utf-8');
echo json_encode([
    'report_id'  => $reportId,
    'saved_local' => $saved !== false,
    'forwarded_to_primary' => $forwarded,
    'forward_error' => $forwarded ? null : $forwardError,
    'timestamp' => $timestamp,
], JSON_UNESCAPED_UNICODE);