# MMProtect Open-Source-Roadmap

Diese Uebersicht beschreibt, welche Bestandteile fuer eine belastbare Open-Source-Variante von MMProtect noch ergaenzt werden sollten. Die Einteilung trennt zwischen zwingenden Kernfunktionen, sinnvollen Erweiterungen und optionalem Komfort.

## Ziel der Open-Source-Variante

Die Open-Source-Version sollte den technischen Kern bereitstellen:

- PHP-Projektcode verschluesseln
- Lizenzdaten verwalten
- verschluesselte PHP-Dateien zur Laufzeit ueber eine PHP-Extension ausfuehren
- Composer- und OPcache-kompatibel bleiben
- Lizenzen online pruefen und zeitweise offline weiterlaufen lassen
- die kryptografischen Formate offen dokumentieren
- Tests, Build-Skripte und Beispielprojekte enthalten

Nicht zwingend Teil der ersten Open-Source-Version sind SaaS-Funktionen, Zahlungsabwicklung, Kundenportal oder Enterprise-Key-Management.

## Muss Ergaenzt Werden

Diese Punkte sollten vor einer ernsthaften Open-Source-Verwendung umgesetzt oder stabilisiert werden.

| Bereich | Ergaenzung | Grund |
|---|---|---|
| Produktive Key-Speicherung | Build-Keys duerfen nicht im Klartext oder Demo-Verfahren in der Datenbank liegen | Kritisch fuer echten Schutz |
| Echte Lease-Signaturen | Demo-HMAC/SHA-Fallback vollstaendig durch ECDSA-P256 ersetzen | Loader muss Serverantworten sicher pruefen koennen |
| Runtime-Revocation | Lizenz, Build, Aktivierung und API-Client muessen zur Laufzeit sperrbar sein | Gesperrte Installationen duerfen keine neuen Leases erhalten |
| Audit-Logging | Ereignisse aktiv in `audit_log` schreiben | Nachvollziehbarkeit bei Nutzung, Fehlern und Missbrauch |
| Admin-CLI | Kunden, Projekte, Lizenzen, Builds und Aktivierungen verwalten | Eine Weboberflaeche ist optional, aber Verwaltung wird benoetigt |
| Sichere Dev-/Prod-Trennung | `dev_mode` klar absichern, warnen oder in Release-Builds deaktivierbar machen | Verhindert unsichere Auslieferungen |
| Lizenzstatus-Pruefung | `active`, `suspended`, `revoked`, `expired` konsequent auswerten | Grundlage jeder Lizenzlogik |
| Aktivierungsverwaltung | Aktivierungen anzeigen, sperren, loeschen und zuruecksetzen | Noetig bei Serverumzug, VM-Wechsel oder Hardwaretausch |
| Sicherheits-Tests | Ablauf, Revocation, falsche Signatur, falscher Fingerprint, manipulierte Datei testen | Schuetzt vor stillen Sicherheitsluecken |
| Release-Builds | Artefakte fuer Linux und Windows bereitstellen | Encoder, Server und Loader sollen direkt nutzbar sein |
| Installationsskripte | Quickstart- und One-Click-Skripte fuer Server, Encoder und Loader | Senkt Einstiegshuerde |
| Security-Grenzen dokumentieren | Klar beschreiben, was nicht geschuetzt wird | Wichtig fuer ehrliche Erwartungen |

## Sollte Ergaenzt Werden

Diese Punkte sind nicht zwingend fuer den ersten MVP, machen das Projekt aber deutlich praktischer.

| Bereich | Ergaenzung | Nutzen |
|---|---|---|
| Domain-Bindung | Lizenz optional an Domain oder Host binden | Vergleichbar mit ionCube Pro |
| IP-Bindung | Lizenz optional an oeffentliche IP oder IP-Bereich binden | Sinnvoll fuer Serverprodukte |
| Hostname-/Machine-Policy | Maschinenbindung konfigurierbar machen | Weniger Probleme bei VM-Migrationen |
| Feature-Gates | PHP-API wie `mmprotect_has_feature("feature")` | Einzelne Module oder Funktionen lizenzieren |
| Lizenzdatei-Signatur | `.mmprotect/license.json` signieren und pruefen | Schutz gegen lokale Manipulation |
| Manifest-Validierung | Manifest konsequent gegen Serverstand pruefen | Erschwert Dateiaustausch |
| API-Key-Verwaltung | API-Clients anlegen, sperren und rotieren | Wichtig fuer CI- und Encoder-Sicherheit |
| Docker-Compose-Demo | License Server, Datenbank, Demo-Projekt und Testlauf in einem Setup | Gut fuer Entwickler und Evaluierung |
| Datenbankmigrationen | Migrationssystem statt nur `schema.sql` | Sauberer Upgrade-Pfad |
| Strukturierte Logs | Logs ohne Secrets, aber mit Trace-IDs und Ereignistypen | Betriebssicherheit |
| Monitoring-Endpunkte | Health, Version, DB-Status, Lease-Zaehler | Hilfreich im Produktivbetrieb |
| Build-Matrix | PHP 8.4/8.5, Linux x64, Windows x64 | Bessere Plattformabdeckung |

## Optional

Diese Funktionen koennen spaeter ergaenzt werden oder in eine kommerzielle Variante wandern.

| Bereich | Ergaenzung | Einschaetzung |
|---|---|---|
| Web-Admin-Oberflaeche | Kunden, Lizenzen und Aktivierungen im Browser verwalten | Komfortfunktion |
| Obfuscation | Klassen-, Funktions- und Variablennamen verschleiern | Nuetzlich, aber nachrangig gegenueber Krypto und Lizenzpruefung |
| MAC-Bindung | Lizenz an MAC-Adresse binden | Oft stoeranfaellig bei VMs und Containern |
| Online-Kundenportal | Kunden koennen Lizenzdaten selbst sehen oder herunterladen | Eher SaaS-/Commercial-Funktion |
| Zahlungsintegration | Stripe, PayPal oder Rechnungslogik | Nicht Teil des technischen OSS-Kerns |
| Automatische Updates | Lizenzserver verteilt neue Builds | Separates Update-System |
| Telemetrie | Nutzungsstatistiken pro Installation | Datenschutzsensibel, nur transparent und optional |
| mTLS fuer Loader | Client-Zertifikat zusaetzlich zum Runtime-Lease | Sehr gut, aber komplexer Betrieb |
| HSM-/KMS-Anbindung | Private Keys in Vault, Azure, AWS oder HSM | Enterprise-Funktion |
| Mehrmandantenfaehigkeit | Mehrere Hersteller auf einem Lizenzserver | Eher Plattform-/SaaS-Funktion |

## Nicht In Die Open-Source-Basis Aufnehmen

Diese Punkte sollten nicht in den technischen Open-Source-Kern.

| Funktion | Begruendung |
|---|---|
| Fertiges SaaS-Lizenzportal | Zu viel Produktlogik fuer den ersten Kern |
| Zahlungs- und Aboverwaltung | Kein Bestandteil des PHP-Code-Schutzes |
| Versteckte Telemetrie | Schaedigt Vertrauen und erschwert Datenschutz |
| Proprietaere Sonderformate ohne Dokumentation | Open Source sollte pruefbar bleiben |
| Vendor-Lock-in-Mechaniken | Passen schlecht zu einer offenen Basis |

## Empfohlener Open-Source-MVP

Fuer eine erste brauchbare Open-Source-Version sollte das Projekt aus diesen Paketen bestehen:

| Paket | Inhalt |
|---|---|
| `mmprotect-server` | REST API, SQLite/MySQL, Lizenzpruefung, Revocation, Audit-Log |
| `mmencoder` | CLI-Encoding, Manifest, Signaturen, Include/Exclude, Composer-kompatible Ausgabe |
| `mmloader` | PHP 8.4/8.5 Extension, Runtime-Lease, OPcache-Guard, Offline-Grace |
| `mmprotect-admin` | CLI fuer Kunden, Projekte, Lizenzen, Builds und Aktivierungen |
| `docs/` | Quickstart, Security-Modell, API-Vertrag, Build-Anleitung |
| `tests/` | E2E-Test, Manipulations-Tests, Revocation-Tests, OPcache-Test |

## Empfohlene Reihenfolge

1. Produktive Kryptografie abschliessen
2. Build-Key-Speicherung absichern
3. Runtime-Revocation fertigstellen
4. Audit-Logging aktivieren
5. Admin-CLI ergaenzen
6. Sicherheits- und E2E-Tests erweitern
7. Linux-/Windows-Release-Builds automatisieren
8. Docker-Compose-Demo und Quickstart-Doku ergaenzen
9. Domain/IP/Feature-Gates nachziehen
10. Weboberflaeche und Komfortfunktionen optional spaeter umsetzen

## Kurzfazit

Die Open-Source-Variante sollte zuerst Sicherheit, Nachvollziehbarkeit und Bedienbarkeit liefern. Komfortfunktionen wie Webportal, Zahlungsabwicklung, Obfuscation oder Enterprise-Key-Management koennen spaeter folgen.

Der wichtigste Grundsatz: Erst den Kern vertrauenswuerdig machen, dann die Produktfunktionen darum herum bauen.
