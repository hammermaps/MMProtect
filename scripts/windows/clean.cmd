@echo off
setlocal
set ROOT=%~dp0..\..
cd /d "%ROOT%"

if exist artifacts rmdir /s /q artifacts

for /d /r %%D in (bin) do (
  if exist "%%D" rmdir /s /q "%%D"
)

for /d /r %%D in (obj) do (
  if exist "%%D" rmdir /s /q "%%D"
)

echo [clean] Fertig
endlocal
