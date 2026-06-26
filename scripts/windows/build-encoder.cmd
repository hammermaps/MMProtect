@echo off
setlocal
set ROOT=%~dp0..\..
cd /d "%ROOT%"

set PROJECT=src\EncoderCli\EncoderCli.csproj
set OUT=artifacts\encoder\win-x64

if not exist "%PROJECT%" (
  echo [build-encoder] Projektdatei fehlt: %PROJECT%
  echo [build-encoder] Coding-Agent soll src\EncoderCli anlegen.
  exit /b 0
)

dotnet restore "%PROJECT%"
if exist "src\EncoderCli.Tests\EncoderCli.Tests.csproj" dotnet test "src\EncoderCli.Tests\EncoderCli.Tests.csproj" --configuration Release
dotnet publish "%PROJECT%" -c Release -r win-x64 --self-contained false -o "%OUT%"

echo [build-encoder] Artefakt: %OUT%
endlocal
