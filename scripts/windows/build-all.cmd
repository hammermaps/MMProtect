@echo off
setlocal enabledelayedexpansion
set ROOT=%~dp0..\..
cd /d "%ROOT%"

echo [build-all] Server bauen
call scripts\windows\build-server.cmd

echo [build-all] Encoder bauen
call scripts\windows\build-encoder.cmd

echo [build-all] Decoder bauen
call scripts\windows\build-decoder.cmd

echo [build-all] Fertig
endlocal
