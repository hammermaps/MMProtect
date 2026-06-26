# Source-Projekte

Dieses Verzeichnis enthält konkrete Startinhalte:

```text
LicenseServer/          ASP.NET-Core-REST-API
EncoderCli/             C# CLI Encoder mit MMENC1-Ausgabe
PhpDecoderLoader/       native PHP/Zend-Extension Skeleton
LicenseServer.Tests/    xUnit Smoke Tests
EncoderCli.Tests/       xUnit Tests
MmProtect.sln           Visual-Studio-/dotnet-Solution
```

## Build

```bash
dotnet build src/MmProtect.sln
bash scripts/linux/build-decoder.sh
```

## Hinweis

Der Server und Encoder sind als MVP-Startcode angelegt. Der PHP-Loader ist ein nativer Extension-Startstand mit Zend-Compile-Hook und MMENC1-Erkennung.
