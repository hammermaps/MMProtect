@echo off
setlocal
set ROOT=%~dp0..\..
cd /d "%ROOT%"

set VERSION=%1
if "%VERSION%"=="" set VERSION=0.1.0

if not exist artifacts\release mkdir artifacts\release

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Compress-Archive -Path artifacts\server,artifacts\encoder,artifacts\decoder,configs,docs,database,scripts,jenkins -DestinationPath artifacts\release\mmprotect-%VERSION%.zip -Force"

echo [package-release] artifacts\release\mmprotect-%VERSION%.zip
endlocal
