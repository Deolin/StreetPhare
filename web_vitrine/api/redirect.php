<?php
/**
 * StreetPhare — Point de routage API (streetphare.be)
 *
 * Centralise les requêtes de l'application mobile (version check, maps, events,
 * bug reports) et les redirige vers l'adresse No-IP du serveur principal
 * StreetPhare.  Si le serveur No-IP est injoignable, les clients sont
 * automatiquement basculés vers l'infrastructure secondaire / P2P locale.
 *
 * Utilisation :
 *   GET/POST https://streetphare.be/api/redirect.php?action=<action>
 *
 * Actions supportées :
 *   version     → version check
 *   events      → CRUD événements
 *   map         → proxy de tuiles
 *   stats       → statistiques
 *   ping        → health check
 */

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

// Adresse No-IP du serveur principal StreetPhare
define('PRIMARY_HOST', 'streetphare-principal.ddns.net');
define('PRIMARY_PORT', 3000);

// Adresse du serveur secondaire / backup
define('SECONDARY_HOST', 'streetphare-backup.ddns.net');
define('SECONDARY_PORT', 3001);

// Timeout de connexion en secondes
define('CONNECT_TIMEOUT', 5);
define('REQUEST_TIMEOUT', 15);

// Fichier de log local
define('LOG_FILE', __DIR__ . '/redirect.log');

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function log_request(string $message): void {
    $line = '[' . date('Y-m-d H:i:s') . '] ' . $message . PHP_EOL;
    @file_put_contents(LOG_FILE, $line, FILE_APPEND | LOCK_EX);
}

/**
 * Tente un appel HTTP vers l'hôte cible.
 * Retourne la réponse brute ou false en cas d'échec.
 */
function proxy_to(string $host, int $port, string $method, string $path, ?string $body, array $headers): array|false {
    $url = "http://$host:$port$path";

    $ch = curl_init();
    curl_setopt_array($ch, [
        CURLOPT_URL            => $url,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_FOLLOWLOCATION => false,
        CURLOPT_CONNECTTIMEOUT => CONNECT_TIMEOUT,
        CURLOPT_TIMEOUT        => REQUEST_TIMEOUT,
        CURLOPT_HEADER         => true,
        CURLOPT_CUSTOMREQUEST  => $method,
    ]);

    // Transmettre les en-têtes utiles (sans Host)
    $forwardedHeaders = [];
    foreach ($headers as $key => $value) {
        $lowerKey = strtolower($key);
        if (in_array($lowerKey, ['host', 'content-length'], true)) {
            continue;
        }
        $forwardedHeaders[] = "$key: $value";
    }
    if (!empty($forwardedHeaders)) {
        curl_setopt($ch, CURLOPT_HTTPHEADER, $forwardedHeaders);
    }

    if ($body !== null && in_array($method, ['POST', 'PUT', 'PATCH'])) {
        curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
    }

    $response = curl_exec($ch);
    $error    = curl_error($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $headerSize = curl_getinfo($ch, CURLINFO_HEADER_SIZE);
    curl_close($ch);

    if ($response === false || !empty($error)) {
        log_request("FAIL $host:$port → $error");
        return false;
    }

    $responseHeaders = substr($response, 0, $headerSize);
    $responseBody    = substr($response, $headerSize);

    return [
        'http_code' => $httpCode,
        'headers'   => $responseHeaders,
        'body'      => $responseBody,
    ];
}

/**
 * Envoie une réponse JSON au client.
 */
function json_response(int $code, array $data): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, Authorization');
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

/**
 * Relaie la réponse brute du serveur cible vers le client.
 */
function relay_response(array $proxyResult): void {
    // Extraire le Content-Type
    if (preg_match('/Content-Type:\s*([^\r\n]+)/i', $proxyResult['headers'], $m)) {
        header('Content-Type: ' . trim($m[1]));
    }
    header('Access-Control-Allow-Origin: *');
    http_response_code($proxyResult['http_code']);
    echo $proxyResult['body'];
    exit;
}

// ---------------------------------------------------------------------------
// Point d'entrée
// ---------------------------------------------------------------------------

// CORS preflight
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, Authorization');
    http_response_code(204);
    exit;
}

$action = $_GET['action'] ?? $_POST['action'] ?? '';
$method = $_SERVER['REQUEST_METHOD'];
$path   = '/api/' . $action;

// Ajouter la query string (sauf 'action')
$qs = $_GET;
unset($qs['action']);
if (!empty($qs)) {
    $path .= '?' . http_build_query($qs);
}

$body = file_get_contents('php://input') ?: null;

// Collecter les en-têtes entrants
$clientHeaders = [];
foreach (getallheaders() as $key => $value) {
    $clientHeaders[$key] = $value;
}

log_request("REQ $method $path from {$_SERVER['REMOTE_ADDR']}");

// === Étape 1 : Essayer le serveur PRINCIPAL No-IP ===
$result = proxy_to(PRIMARY_HOST, PRIMARY_PORT, $method, $path, $body, $clientHeaders);

if ($result !== false) {
    log_request("OK primary " . PRIMARY_HOST . " → HTTP " . $result['http_code']);
    relay_response($result);
    exit;
}

log_request("PRIMARY unreachable, trying SECONDARY...");

// === Étape 2 : Basculer vers le serveur SECONDAIRE ===
$result = proxy_to(SECONDARY_HOST, SECONDARY_PORT, $method, $path, $body, $clientHeaders);

if ($result !== false) {
    log_request("OK secondary " . SECONDARY_HOST . " → HTTP " . $result['http_code']);
    relay_response($result);
    exit;
}

// === Étape 3 : Échec total → mode P2P / hors-ligne ===
log_request("ALL UNAVAILABLE → returning P2P fallback");
json_response(503, [
    'status'  => 'offline',
    'mode'    => 'p2p',
    'message' => 'Les serveurs StreetPhare sont temporairement injoignables. '
               . 'L\'application fonctionne en mode P2P local.',
    'retry_after_seconds' => 60,
]);