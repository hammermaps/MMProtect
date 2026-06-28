@echo off
setlocal
set ROOT=%~dp0..\..
set UI_DIR=%ROOT%\src\AdminUi
set OUT_DIR=%ROOT%\src\LicenseServer\wwwroot\admin

echo [build-admin-ui] Quelle: %UI_DIR%
echo [build-admin-ui] Ziel:   %OUT_DIR%

where node >nul 2>&1
if errorlevel 1 (
    echo [build-admin-ui] FEHLER: node nicht gefunden. Node.js 18+ von https://nodejs.org/ installieren.
    exit /b 1
)

cd /d "%UI_DIR%"

if exist package-lock.json (
    npm ci
) else (
    npm install
)
if errorlevel 1 exit /b 1

npm run build
if errorlevel 1 exit /b 1

echo [build-admin-ui] Fertig. Admin UI in %OUT_DIR%
endlocal
