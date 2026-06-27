# MMProtect License Server — Docker-Deployment

Diese Anleitung beschreibt den Betrieb des License Servers als Docker-Container. Alle sicherheitsrelevanten Parameter (Port, Datenbankverbindung, API-Keys, Verschlüsselungsschlüssel, Signing-Key) werden ausschließlich über Umgebungsvariablen übergeben — kein Editieren von Konfigurationsdateien im Container.

---

## Voraussetzungen

- Docker 24.0 oder neuer
- Docker Compose v2 (`docker compose`, nicht `docker-compose`)
- `openssl` auf dem Host (für Key-Generierung)

```bash
docker --version        # Docker version 24.x.x
docker compose version  # Docker Compose version v2.x.x
```

---

## Schnellstart — SQLite (ein Container, kein MySQL)

Geeignet für Entwicklung, kleine Deployments und Tests.

```bash
# 1. Konfiguration anlegen
cp .env.example .env
chmod 600 .env

# 2. Pflicht-Variablen setzen
openssl rand -hex 32 | sed -i "s|MMPROTECT_ENCODER_API_KEY_0=.*|MMPROTECT_ENCODER_API_KEY_0=$(openssl rand -hex 32)|" .env
openssl rand -hex 32 | sed -i "s|MMPROTECT_ADMIN_API_KEY_0=.*|MMPROTECT_ADMIN_API_KEY_0=$(openssl rand -hex 32)|" .env
sed -i "s|MMPROTECT_KEK=.*|MMPROTECT_KEK=$(openssl rand -hex 32)|" .env

# Alternativ: direkt in .env eintragen (empfohlen)
nano .env

# 3. Container starten
docker compose -f docker-compose.sqlite.yml up -d

# 4. Prüfen
curl http://localhost:8080/health
```

---

## Schnellstart — MySQL (Produktions-Setup)

```bash
# 1. Konfiguration anlegen
cp .env.example .env
chmod 600 .env
nano .env    # Passwörter, Keys und ggf. Signing-Key-Pfad eintragen

# 2. Container starten (startet MySQL + License Server)
docker compose up -d

# 3. Prüfen
curl http://localhost:8080/health
# → {"status":"ok","version":"0.1.0","timeUtc":"...","database":"ok"}
```

---

## Umgebungsvariablen — vollständige Referenz

Alle Variablen werden in `.env` gesetzt und von `docker compose` ausgelesen. Bei `docker run` werden sie direkt mit `-e VAR=wert` übergeben.

### Port

| Variable | Standard | Beschreibung |
|---|---|---|
| `MMPROTECT_PORT` | `8080` | Externer Host-Port **und** interner Listen-Port. Ändert beides konsistent. |

```bash
# Beispiel: Port 9443 verwenden
MMPROTECT_PORT=9443
```

### Datenbank

| Variable | Standard | Beschreibung |
|---|---|---|
| `MMPROTECT_DB_PROVIDER` | `mysql` | `mysql` oder `sqlite` |
| `MYSQL_DATABASE` | `mm_license` | MySQL-Datenbankname |
| `MYSQL_USER` | `mm_license` | MySQL-Benutzername |
| `MYSQL_PASSWORD` | `change-me-db-password` | MySQL-Passwort |
| `MYSQL_ROOT_PASSWORD` | `change-me-root-password` | MySQL-Root-Passwort (nur MySQL-Container) |
| `MMPROTECT_MYSQL_CONNSTR` | *(aus MYSQL_\* gebaut)* | Vollständiger Connection String — überschreibt alle MYSQL_\*-Variablen |
| `MMPROTECT_SQLITE_CONNSTR` | `Data Source=/var/cache/mmprotect/mm_license.db` | SQLite-Pfad im Container |

> Die `MYSQL_*`-Variablen werden automatisch in den Connection String des License Servers interpoliert. `MMPROTECT_MYSQL_CONNSTR` ist nur nötig, wenn ein externer MySQL-Server mit abweichender URL verwendet wird.

### API-Keys

| Variable | Pflicht | Beschreibung |
|---|---|---|
| `MMPROTECT_ENCODER_API_KEY_0` | **Ja** | Erster Encoder-API-Key (Bearer-Token für `/api/v1/encoder/`) |
| `MMPROTECT_ADMIN_API_KEY_0` | **Ja** | Erster Admin-API-Key (Bearer-Token für `/api/v1/admin/`) |

Weitere statische Keys werden direkt als zusätzliche Umgebungsvariablen gesetzt — kein Neustart des Servers nötig für dynamische Keys, die über die Admin-API verwaltet werden:

```bash
# In .env oder als -e Argumente:
Security__EncoderApiKeys__1=zweiter-encoder-key
Security__EncoderApiKeys__2=dritter-encoder-key
Security__AdminApiKeys__1=zweiter-admin-key
```

Keys generieren:
```bash
openssl rand -hex 32
```

### Kryptografie

| Variable | Standard | Beschreibung |
|---|---|---|
| `MMPROTECT_KEK` | *(leer)* | AES-256-GCM Key Encryption Key — schützt Build-Keys in der DB. Leer = Dev-Modus (Startup-Warning). |
| `MMPROTECT_SIGNING_KEY_HOST_PATH` | *(nicht gesetzt)* | Pfad auf dem **Host** zur ECDSA-P256-Datei. Aktiviert automatisch Mount + SigningPrivateKeyFile. |

KEK generieren:
```bash
openssl rand -hex 32
```

### Lease-Einstellungen

| Variable | Standard | Beschreibung |
|---|---|---|
| `MMPROTECT_LEASE_TTL_MINUTES` | `1440` | Gültigkeitsdauer einer Lease (Minuten) |
| `MMPROTECT_GRACE_PERIOD_DAYS` | `7` | Offline-Toleranz: so lange gilt eine gecachte Lease ohne Serverkontakt (Tage) |

### Reverse Proxy

| Variable | Standard | Beschreibung |
|---|---|---|
| `MMPROTECT_REVERSE_PROXY_ENABLED` | `false` | `true` wenn nginx/Traefik vorgelagert ist (wertet X-Forwarded-For aus) |
| `MMPROTECT_FORWARD_LIMIT` | `1` | Anzahl vertrauenswürdiger Proxy-Hops |

### Rate Limiting

| Variable | Standard | Beschreibung |
|---|---|---|
| `MMPROTECT_RATE_LIMITING_ENABLED` | `true` | Rate Limiting aktivieren |
| `MMPROTECT_RATE_LIMIT_PERMITS` | `10` | Max. Lease-Anfragen pro IP pro Zeitfenster |
| `MMPROTECT_RATE_LIMIT_WINDOW` | `60` | Zeitfenster in Sekunden |

---

## Signing-Key einrichten

Der Signing-Key (ECDSA-P256) signiert alle Runtime-Leases. In Produktion ist er **Pflicht** — ohne ihn fällt der Server auf HMAC-SHA256 zurück (Startup-Warnung, unsicher).

### 1. Key-Paar generieren

```bash
# Erzeugt signing-private.pem und signing-public.pem
scripts/linux/gen-signing-keys.sh /etc/mmprotect/keys

# Berechtigungen sichern
chmod 600 /etc/mmprotect/keys/signing-private.pem
```

### 2. In `.env` konfigurieren

```bash
# Pfad auf dem HOST zur PEM-Datei
MMPROTECT_SIGNING_KEY_HOST_PATH=/etc/mmprotect/keys/signing-private.pem
```

Das war es. Compose montiert die Datei automatisch unter `/run/secrets/signing-private.pem` im Container und setzt `Security__SigningPrivateKeyFile` entsprechend. Kein weiterer Eingriff nötig.

### 3. Public Key an Kunden verteilen

```bash
# signing-public.pem → an jeden Kunden mit dem Loader
# Kunden konfigurieren: mmloader.signing_public_key_file = /pfad/signing-public.pem
```

---

## `docker run` ohne Compose

Für den Betrieb ohne Compose-Datei — alle Parameter werden direkt als `-e` Argumente übergeben:

```bash
# Image bauen
docker build -t mmprotect-license-server:latest .

# SQLite-Beispiel
docker run -d \
  --name mm-license-server \
  --restart unless-stopped \
  -p 8080:8080 \
  -e ASPNETCORE_HTTP_PORTS=8080 \
  -e DatabaseProvider=sqlite \
  -e "ConnectionStrings__Sqlite=Data Source=/data/mm_license.db" \
  -e "Security__EncoderApiKeys__0=$(openssl rand -hex 32)" \
  -e "Security__AdminApiKeys__0=$(openssl rand -hex 32)" \
  -e "Security__KeyEncryptionKey=$(openssl rand -hex 32)" \
  -e "Security__SigningPrivateKeyFile=/run/secrets/signing-private.pem" \
  -v /etc/mmprotect/keys/signing-private.pem:/run/secrets/signing-private.pem:ro \
  -v mm_license_data:/data \
  mmprotect-license-server:latest

# MySQL-Beispiel
docker run -d \
  --name mm-license-server \
  --restart unless-stopped \
  -p 8080:8080 \
  -e ASPNETCORE_HTTP_PORTS=8080 \
  -e DatabaseProvider=mysql \
  -e "ConnectionStrings__MySql=Server=db.example.com;Port=3306;Database=mm_license;User Id=mm_license;Password=GEHEIM;SslMode=Required;" \
  -e "Security__EncoderApiKeys__0=ENCODER-KEY" \
  -e "Security__AdminApiKeys__0=ADMIN-KEY" \
  -e "Security__KeyEncryptionKey=$(openssl rand -hex 32)" \
  -e "Security__SigningPrivateKeyFile=/run/secrets/signing-private.pem" \
  -v /etc/mmprotect/keys/signing-private.pem:/run/secrets/signing-private.pem:ro \
  mmprotect-license-server:latest
```

> **Hinweis:** Generierte Werte für `Security__EncoderApiKeys__0` etc. beim `docker run`-Aufruf werden in der Prozessliste sichtbar. Für Produktion `.env`-Datei oder einen Secrets Manager verwenden.

---

## Hinter einem Reverse Proxy (nginx / Traefik)

Wenn der License Server hinter einem Reverse Proxy läuft, muss `ReverseProxy__Enabled=true` gesetzt sein, damit X-Forwarded-For für das Rate Limiting korrekt ausgewertet wird.

```bash
# In .env:
MMPROTECT_REVERSE_PROXY_ENABLED=true
MMPROTECT_FORWARD_LIMIT=1        # Anzahl vertrauenswürdiger Proxy-Hops
```

Beispiel nginx-Konfiguration (TLS-Terminierung):

```nginx
server {
    listen 443 ssl;
    server_name license.example.com;

    ssl_certificate     /etc/letsencrypt/live/license.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/license.example.com/privkey.pem;

    location / {
        proxy_pass         http://127.0.0.1:8080;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }
}
```

Ausführliche Proxy-Konfiguration: [`docs/proxy-setup.md`](proxy-setup.md).

---

## Backup

### SQLite

```bash
# Snapshot des benannten Volumes
docker run --rm \
  -v mm_license_data:/data:ro \
  -v "$(pwd)/backup":/backup \
  busybox \
  sh -c 'sqlite3 /data/mm_license.db ".backup /backup/mm_license_$(date +%Y%m%d_%H%M%S).db"'
```

### MySQL

```bash
# mysqldump aus dem laufenden Container
docker exec mm-license-mysql \
  mysqldump --single-transaction mm_license \
  | gzip > backup/mm_license_$(date +%Y%m%d).sql.gz
```

---

## Logs

```bash
# Live-Logs
docker logs -f mm-license-server

# Letzte 100 Zeilen
docker logs --tail=100 mm-license-server

# Mit Compose
docker compose logs -f license-server
```

---

## Image aktualisieren

```bash
# Neues Image bauen
docker compose build --no-cache

# Container neu starten (Zero-Downtime bei Compose: pull + up -d)
docker compose up -d --build
```

---

## Produktions-Checkliste

Vor dem ersten Produktionsbetrieb:

- [ ] `MMPROTECT_ENCODER_API_KEY_0` und `MMPROTECT_ADMIN_API_KEY_0` auf zufällige Werte gesetzt (`openssl rand -hex 32`)
- [ ] `MMPROTECT_KEK` gesetzt (`openssl rand -hex 32`) — schützt Build-Keys in der DB
- [ ] `MMPROTECT_SIGNING_KEY_HOST_PATH` gesetzt — ECDSA-Signaturen aktiv
- [ ] `MYSQL_PASSWORD` und `MYSQL_ROOT_PASSWORD` auf sichere Werte gesetzt (nicht die Standardwerte!)
- [ ] `.env`-Datei mit `chmod 600` abgesichert — nur root/mmprotect lesbar
- [ ] `.env` ist in `.gitignore` eingetragen und wurde nicht committed
- [ ] Port 8080 ist **nicht** direkt öffentlich erreichbar — TLS-Proxy davor
- [ ] `MMPROTECT_REVERSE_PROXY_ENABLED=true` falls nginx/Traefik vorgelagert
- [ ] Backup-Routine eingerichtet (Cron oder CI-Job)
- [ ] Health-Check in Monitoring eingebunden: `GET /health` → HTTP 200

---

## Startup-Warnungen

Der License Server gibt beim Start Warnungen aus, wenn sicherheitsrelevante Konfiguration fehlt:

| Warnung | Ursache | Behebung |
|---|---|---|
| `build keys stored unencrypted` | `MMPROTECT_KEK` nicht gesetzt | KEK generieren und setzen |
| `lease signatures use HMAC-SHA256` | `MMPROTECT_SIGNING_KEY_HOST_PATH` nicht gesetzt | Signing-Key mounten |
| `AdminApiKeys not configured or uses default key` | Standard-Key aus `.env.example` noch aktiv | Echten Zufallskey setzen |

Warnungen anzeigen:
```bash
docker logs mm-license-server 2>&1 | grep -i "mmprotect\|warning"
```

---

## Troubleshooting

| Problem | Ursache | Lösung |
|---|---|---|
| Container startet nicht, `MMPROTECT_ENCODER_API_KEY_0 must be set` | Pflichtfeld fehlt in `.env` | `.env` befüllen und neu starten |
| `The process cannot access the file signing-private.pem` | Falscher Host-Pfad oder fehlende Leserechte | `chmod 644 /pfad/signing-private.pem` auf dem Host |
| `AUTH_INVALID` bei Encoder-Aufruf | Falscher oder abweichender API-Key | Key aus `.env` prüfen |
| MySQL-Container nicht healthy | Falsches Passwort im Health-Check | `MYSQL_PASSWORD` in `.env` korrekt setzen |
| Port bereits belegt | Port 8080 durch anderen Prozess blockiert | `MMPROTECT_PORT=8081` in `.env` |
| Lease-Signatur-Warnung im mmloader | `signing-public.pem` beim Kunden veraltet | Neuen Public Key verteilen |
