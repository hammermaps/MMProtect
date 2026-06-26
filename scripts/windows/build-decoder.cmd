@echo off
setlocal
set ROOT=%~dp0..\..
cd /d "%ROOT%"

echo [build-decoder] Windows PHP Extension Build
echo Voraussetzungen:
echo   - Visual Studio Build Tools
echo   - PHP SDK
echo   - PHP 8.4 Devpack NTS/TS
echo   - Umgebungsvariablen PHP_SDK_DIR und PHP_DEVPACK_DIR

if "%PHP_SDK_DIR%"=="" (
  echo [build-decoder] PHP_SDK_DIR ist nicht gesetzt.
  exit /b 0
)

if "%PHP_DEVPACK_DIR%"=="" (
  echo [build-decoder] PHP_DEVPACK_DIR ist nicht gesetzt.
  exit /b 0
)

if not exist "src\PhpDecoderLoader" (
  echo [build-decoder] src\PhpDecoderLoader fehlt. Coding-Agent soll Extension anlegen.
  exit /b 0
)

echo [build-decoder] TODO: Agent soll hier konkrete PHP-SDK-Buildschritte eintragen.
echo [build-decoder] Erwartetes Artefakt: artifacts\decoder\win-x64\php_mmloader.dll

if not exist "artifacts\decoder\win-x64" mkdir "artifacts\decoder\win-x64"

endlocal
