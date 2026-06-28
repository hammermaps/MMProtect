<?php
/**
 * MMProtect Auto-Update Script
 *
 * Dieses Script prüft beim Kunden ob eine neue Version der verschlüsselten
 * PHP-Dateien verfügbar ist und lädt sie herunter.
 *
 * Aufruf:
 *   php update.php [--force]
 *
 * Voraussetzungen:
 *   - .mmprotect/license.json muss vorhanden sein
 *   - Internet-Zugang zum License Server
 *   - Schreibrechte auf das App-Verzeichnis
 *
 * Deployment-Strategie: symlink-Swap (atomar)
 *   /var/www/myapp        → Symlink auf /var/www/myapp-current/
 *   /var/www/myapp-new/   → neues Verzeichnis (während Deployment)
 *   Nach Abschluss: Symlink wird atomar auf myapp-new/ umgezeigt.
 */

declare(strict_types=1);

// ---------------------------------------------------------------------------
// Konfiguration
// ---------------------------------------------------------------------------

$appRoot    = dirname(__DIR__);                          // Verzeichnis der App
$protectDir = $appRoot . '/.mmprotect';
$licenseFile = $protectDir . '/license.json';
$manifestFile = $protectDir . '/manifest.json';

$forceUpdate = in_array('--force', $argv ?? [], true);

// ---------------------------------------------------------------------------
// Lizenz-Datei lesen
// ---------------------------------------------------------------------------

if (!file_exists($licenseFile)) {
    echo "[ERROR] .mmprotect/license.json nicht gefunden.\n";
    exit(1);
}

$license = json_decode(file_get_contents($licenseFile), true);
if (!$license) {
    echo "[ERROR] license.json ist kein gültiges JSON.\n";
    exit(1);
}

$licenseId     = $license['licenseId']     ?? null;
$licenseKey    = $license['licenseKey']    ?? null;
$licenseServer = $license['licenseServer'] ?? null;

if (!$licenseId || !$licenseKey || !$licenseServer) {
    echo "[ERROR] license.json fehlen Pflichtfelder (licenseId, licenseKey, licenseServer).\n";
    exit(1);
}

// ---------------------------------------------------------------------------
// Aktuelle buildId lesen
// ---------------------------------------------------------------------------

$currentBuildId = null;
if (file_exists($manifestFile)) {
    $manifest = json_decode(file_get_contents($manifestFile), true);
    $currentBuildId = $manifest['buildId'] ?? null;
}

echo "[INFO] Aktuelle Build-ID: " . ($currentBuildId ?? '(keine)') . "\n";
echo "[INFO] License Server:    $licenseServer\n";

// ---------------------------------------------------------------------------
// Neueste Version vom License Server abfragen
// ---------------------------------------------------------------------------

$updateUrl = rtrim($licenseServer, '/') . '/api/v1/customer/builds/latest'
    . '?licenseId=' . urlencode($licenseId)
    . '&licenseKey=' . urlencode($licenseKey);

echo "[INFO] Prüfe auf Update: $updateUrl\n";

$ctx = stream_context_create([
    'http' => [
        'timeout' => 15,
        'method'  => 'GET',
        'header'  => "Accept: application/json\r\n",
    ],
    'ssl' => [
        'verify_peer'      => true,
        'verify_peer_name' => true,
    ],
]);

$response = @file_get_contents($updateUrl, false, $ctx);
if ($response === false) {
    echo "[ERROR] Verbindung zum License Server fehlgeschlagen.\n";
    exit(1);
}

$data = json_decode($response, true);
if (!$data || !isset($data['buildId'])) {
    echo "[ERROR] Unerwartete Antwort: $response\n";
    exit(1);
}

$newBuildId    = $data['buildId'];
$manifestJson  = $data['manifestJson'];
$downloadUrl   = $data['downloadUrl'] ?? null;

echo "[INFO] Verfügbare Build-ID: $newBuildId\n";

// ---------------------------------------------------------------------------
// Vergleich: ist ein Update nötig?
// ---------------------------------------------------------------------------

if (!$forceUpdate && $currentBuildId === $newBuildId) {
    echo "[OK] Bereits auf dem neuesten Stand ($currentBuildId). Kein Update nötig.\n";
    exit(0);
}

echo "[INFO] Update verfügbar: $currentBuildId → $newBuildId\n";

// ---------------------------------------------------------------------------
// Neue Dateien herunterladen (wenn downloadUrl gesetzt ist)
// ---------------------------------------------------------------------------

if ($downloadUrl) {
    echo "[INFO] Lade neue Version herunter: $downloadUrl\n";

    $zipPath = sys_get_temp_dir() . '/mmprotect-update-' . $newBuildId . '.zip';
    $extractDir = $appRoot . '-new-' . $newBuildId;

    // ZIP herunterladen
    $zipCtx = stream_context_create(['http' => ['timeout' => 120]]);
    $zipData = @file_get_contents($downloadUrl, false, $zipCtx);
    if ($zipData === false || strlen($zipData) < 100) {
        echo "[ERROR] Download fehlgeschlagen oder leer.\n";
        exit(1);
    }
    file_put_contents($zipPath, $zipData);
    echo "[INFO] Download abgeschlossen (" . round(strlen($zipData) / 1024) . " KB)\n";

    // ZIP entpacken
    $zip = new ZipArchive();
    if ($zip->open($zipPath) !== true) {
        echo "[ERROR] ZIP konnte nicht geöffnet werden.\n";
        exit(1);
    }
    @mkdir($extractDir, 0755, true);
    $zip->extractTo($extractDir);
    $zip->close();
    unlink($zipPath);
    echo "[INFO] Entpackt nach: $extractDir\n";

    // Neues manifest.json schreiben (mit korrekter Signatur vom Server)
    $newProtectDir = $extractDir . '/.mmprotect';
    @mkdir($newProtectDir, 0755, true);
    file_put_contents($newProtectDir . '/manifest.json',
        json_encode(json_decode($manifestJson), JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
    // license.json aus aktueller Installation kopieren
    copy($licenseFile, $newProtectDir . '/license.json');

    // Atomarer Symlink-Swap (Linux/Unix)
    $currentLink = $appRoot;
    if (is_link($currentLink)) {
        $oldTarget = readlink($currentLink);
        symlink($extractDir, $currentLink . '.new');
        rename($currentLink . '.new', $currentLink); // atomar auf POSIX
        echo "[OK] Deployment abgeschlossen (Symlink: $currentLink → $extractDir)\n";
        // Altes Verzeichnis aufräumen (optional, nach Überprüfung)
        echo "[INFO] Altes Verzeichnis: $oldTarget (kann nach Prüfung gelöscht werden)\n";
    } else {
        // Kein Symlink — nur .mmprotect/ aktualisieren
        echo "[WARN] App-Root ist kein Symlink. Nur .mmprotect/ wird aktualisiert.\n";
        file_put_contents($manifestFile,
            json_encode(json_decode($manifestJson), JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
        echo "[OK] manifest.json aktualisiert.\n";
        echo "[INFO] Bitte die verschlüsselten PHP-Dateien manuell ersetzen.\n";
    }
} else {
    // Kein downloadUrl — nur manifest.json aktualisieren
    // (Dateien wurden manuell deployed oder kommen über ein anderes System)
    echo "[INFO] Kein Download-URL konfiguriert. Aktualisiere nur .mmprotect/manifest.json.\n";
    file_put_contents($manifestFile,
        json_encode(json_decode($manifestJson), JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
    echo "[OK] manifest.json auf Build $newBuildId aktualisiert.\n";
    echo "[INFO] Stelle sicher, dass die verschlüsselten PHP-Dateien für Build $newBuildId\n";
    echo "       bereits im App-Verzeichnis vorhanden sind.\n";
}

echo "[DONE] Update abgeschlossen.\n";
