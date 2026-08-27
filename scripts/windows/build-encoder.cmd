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

rem win-x64 -- self-contained single-file EXE (kein .NET auf dem Zielsystem noetig)
dotnet publish "%PROJECT%" -c Release -r win-x64 --self-contained true -o "%OUT%"
echo [build-encoder] win-x64: %OUT%\mmencoder.exe

set GUI_PROJECT=src\EncoderGui\EncoderGui.csproj
set GUI_OUT=artifacts\encoder-gui\win-x64
dotnet publish "%GUI_PROJECT%" -c Release -r win-x64 --self-contained true -o "%GUI_OUT%"
echo [build-encoder] GUI win-x64: %GUI_OUT%\mmencoder-gui.exe

set GUI_OUT_LINUX=artifacts\encoder-gui\linux-x64
dotnet publish "%GUI_PROJECT%" -c Release -r linux-x64 --self-contained true -o "%GUI_OUT_LINUX%"
echo [build-encoder] GUI linux-x64: %GUI_OUT_LINUX%\mmencoder-gui

rem win-arm64 -- Windows on ARM (Surface Pro X, Snapdragon X etc.)
set OUT_ARM=artifacts\encoder\win-arm64
dotnet publish "%PROJECT%" -c Release -r win-arm64 --self-contained true -o "%OUT_ARM%"
echo [build-encoder] win-arm64: %OUT_ARM%\mmencoder.exe

echo [build-encoder] Fertig -- selbststaendige EXEs, kein .NET auf dem Zielsystem noetig.
endlocal
