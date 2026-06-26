@echo off
setlocal
set ROOT=%~dp0..\..
cd /d "%ROOT%"

echo [test-all] PHP Demo testen
cd tests\php-demo
where composer >nul 2>nul
if %ERRORLEVEL%==0 (
  composer dump-autoload -o -a
) else (
  echo [test-all] composer fehlt, ueberspringe autoload generation
)

php -v
php public\index.php
php tests\smoke.php

cd /d "%ROOT%"

echo [test-all] .NET Tests
if exist "src\LicenseServer.Tests\LicenseServer.Tests.csproj" dotnet test src\LicenseServer.Tests\LicenseServer.Tests.csproj
if exist "src\EncoderCli.Tests\EncoderCli.Tests.csproj" dotnet test src\EncoderCli.Tests\EncoderCli.Tests.csproj

echo [test-all] Decoder Smoke
if exist "artifacts\decoder\win-x64\php_mmloader.dll" (
  php -d zend_extension="%ROOT%\artifacts\decoder\win-x64\php_mmloader.dll" tests\decoder-loader\plain.php
) else (
  echo [test-all] Decoder-Artefakt fehlt, ueberspringe Decoder Smoke
)

echo [test-all] Fertig
endlocal
