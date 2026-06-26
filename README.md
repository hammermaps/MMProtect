# PHP License Protection System – Agenten-Paket

Dieses Paket beschreibt ein vollständiges Schutzsystem für PHP-8.4+-Projektcode:

- **License Server**: C# REST API für Windows/Linux, MySQL-Datenbank, Kunden, Lizenzen, Builds, Aktivierungen und Runtime-Leases.
- **Encoder CLI**: C# CLI für Windows/Linux, konfigurierbar per JSON/XML, mehrprojektfähig, kommuniziert beim Encodieren mit dem Lizenzserver.
- **PHP Decoder/Loader**: native PHP/Zend-Extension für Linux und Windows, entschlüsselt geschützte Projektdateien im RAM, integriert sich in Composer-Autoload und OPcache.
- **Jenkins Autobuild**: Pipeline-Vorlagen für Linux und Windows.
- **One-Click Build Scripts**: `.sh` und `.cmd` für Server, Encoder, Decoder und Tests.
- **Test-PHP-Projekt**: kleines Composer-kompatibles Beispielprojekt.

## Wichtige Architekturentscheidung

Composer und `vendor/` bleiben unverschlüsselt. Nur eigener Projektcode wird verschlüsselt.

```text
vendor/                 Klartext
vendor/autoload.php     Klartext
public/index.php        Klartext-Bootstrap empfohlen
src/ oder app/          verschlüsselte .php-Dateien mit MMENC1-Container
config/*.php            optional geschützt
```

Die Dateien behalten die Endung `.php`, damit Composer, Frameworks, `require`, `include`, `realpath` und OPcache möglichst normal funktionieren.

## Agenten-Dokumente

- `docs/01-agent-license-server.md`
- `docs/02-agent-encoder-cli.md`
- `docs/03-agent-php-decoder-loader.md`
- `docs/04-security-crypto-format.md`
- `docs/05-build-test-jenkins.md`
- `docs/06-api-contract.md`

## Schnellstart für Coding Agenten

1. Lies zuerst `docs/00-system-overview.md`.
2. Bearbeite dann nur das passende Projekt:
   - Server-Agent: `docs/01-agent-license-server.md`
   - Encoder-Agent: `docs/02-agent-encoder-cli.md`
   - Decoder-Agent: `docs/03-agent-php-decoder-loader.md`
3. Implementiere nach Akzeptanzkriterien.
4. Führe `scripts/linux/test-all.sh` oder `scripts/windows/test-all.cmd` aus.
5. Jenkins-Pipeline unter `jenkins/` verwenden.
