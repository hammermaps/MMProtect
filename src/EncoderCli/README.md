# EncoderCli

C# CLI zum Verschlüsseln von Projektdateien.

## Build

```bash
dotnet build src/EncoderCli/EncoderCli.csproj
```

## Nutzung

```bash
export MM_ENCODER_API_KEY=dev-encoder-api-key-change-me
dotnet run --project src/EncoderCli/EncoderCli.csproj -- validate --config configs/encoder.config.json --project mangelmelder
dotnet run --project src/EncoderCli/EncoderCli.csproj -- encode --config configs/encoder.config.json --project mangelmelder
```

## Hinweis

Die erzeugten Dateien sind echte `MMENC1`-Container mit AES-GCM. Die Signatur ist im Startstand eine Demo-Signatur und muss produktiv durch Server-/Vendor-Signatur ersetzt werden.
