@echo off
setlocal
set ROOT=%~dp0..\..
cd /d "%ROOT%"

set PROJECT=src\LicenseServer\LicenseServer.csproj
set OUT=artifacts\server\win-x64

if not exist "%PROJECT%" (
  echo [build-server] Projektdatei fehlt: %PROJECT%
  echo [build-server] Coding-Agent soll src\LicenseServer anlegen.
  exit /b 0
)

dotnet restore "%PROJECT%"
if exist "src\LicenseServer.Tests\LicenseServer.Tests.csproj" dotnet test "src\LicenseServer.Tests\LicenseServer.Tests.csproj" --configuration Release
dotnet publish "%PROJECT%" -c Release -r win-x64 --self-contained false -o "%OUT%"

echo [build-server] Artefakt: %OUT%
endlocal
