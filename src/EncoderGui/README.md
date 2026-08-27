# MMProtect Encoder GUI

Die Avalonia-Anwendung ist ein lokales Entwicklerwerkzeug für Linux-x64 und Windows-x64
und benötigt zum Bauen das .NET-10-SDK.
Sie verwendet dieselbe `EncoderFacade` wie die Produktions-CLI und verändert keine
öffentlichen License-Server-APIs.

Das Profil wird im gewählten Quellprojekt als `.mmprotect/gui-project.json`
gespeichert. Es enthält gegebenenfalls den Encoder-API-Schlüssel, erhält unter Linux
Modus `0600` und wird automatisch in die lokale `.gitignore` aufgenommen. Diese Datei
niemals weitergeben oder einchecken. Ein Export als CLI-JSON enthält den Schlüssel
ebenfalls und muss entsprechend geschützt werden.

```bash
dotnet run --project src/EncoderGui/EncoderGui.csproj
scripts/linux/build-encoder.sh
```

Die Build-Skripte veröffentlichen `artifacts/encoder-gui/linux-x64/mmencoder-gui`
und `artifacts/encoder-gui/win-x64/mmencoder-gui.exe` als selbstständige Anwendungen.
