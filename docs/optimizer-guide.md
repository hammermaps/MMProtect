# MMProtect PHP Optimizer — Referenz

Der Encoder enthält einen token-basierten PHP-Optimizer, der Quellcode **vor der Verschlüsselung** (und vor der optionalen Obfuskierung) verkleinert und vereinfacht. Das Ergebnis ist kompakter PHP-Code im MMENC1-Container — mit weniger Verschlüsselungsaufwand und kleineren Dateien.

---

## Überblick

| Pass | Name | Flag | Beschreibung |
|------|------|------|-------------|
| 1 | Kommentare entfernen | `comments` | Entfernt `//`, `#` und `/* */` Kommentare |
| 2 | Whitespace reduzieren | `whitespace` (oder `ws`) | Mehrfache Leerzeichen und Einrückungen zusammenfassen |
| 3 | Konstanten falten | `constants` (oder `folding`) | Rechnerisch auflösbare Ausdrücke zur Compilezeit ersetzen |
| 4 | Toter Code entfernen | `deadcode` (oder `dead`) | Unerreichbaren Code nach `return`, `throw`, `exit` und in `if(false)` entfernen |

Alle vier Passes zusammen: `all` (Standardwert wenn `--optimize` ohne Argument angegeben).

---

## Verwendung

### CLI — Dev-Modus

```bash
# Alle Passes (Standard):
mmencoder encode-dir --source src/ --output out/ --dev --optimize

# Explizit alle:
mmencoder encode-dir --source src/ --output out/ --dev --optimize all

# Nur Kommentare und Whitespace:
mmencoder encode-dir --source src/ --output out/ --dev --optimize comments,whitespace

# Nur Konstanten falten:
mmencoder encode-dir --source src/ --output out/ --dev --optimize constants

# Mehrere Passes kombinieren:
mmencoder encode-dir --source src/ --output out/ --dev --optimize comments,whitespace,constants

# Optimizer deaktivieren:
mmencoder encode-dir --source src/ --output out/ --dev --optimize none
```

### CLI — Produktionsmodus

```bash
mmencoder encode-dir \
    --source src/ \
    --output out/ \
    --config encoder.config.json \
    --project mein-projekt \
    --optimize all
```

Das `--optimize`-Flag überschreibt den Wert aus der Konfigurationsdatei.

### Konfigurationsdatei

```json
{
  "defaults": {
    "optimize": "all",
    "compression": "lz4",
    "licenseServer": {
      "baseUrl": "https://license.example.com",
      "apiKey": "..."
    }
  },
  "projects": [ ... ]
}
```

Erlaubte Werte für `"optimize"`:

| Wert | Bedeutung |
|------|-----------|
| `"all"` oder `null` | Alle vier Passes |
| `"none"` | Optimizer deaktiviert |
| `"comments"` | Nur Kommentare entfernen |
| `"whitespace"` oder `"ws"` | Nur Whitespace reduzieren |
| `"constants"` oder `"folding"` oder `"constantfolding"` | Nur Konstanten falten |
| `"deadcode"` oder `"dead"` | Nur toten Code entfernen |
| Kommagetrennt, z. B. `"comments,whitespace"` | Beliebige Kombination |

---

## Pass 1 — Kommentare entfernen (`comments`)

Entfernt alle PHP-Kommentare aus dem Quellcode:

- Zeilenkommentare `// ...`
- Hash-Kommentare `# ...` (außer PHP 8 Attribute `#[...]`)
- Blockkommentare `/* ... */` (inklusive DocBlocks `/** ... */`)

**Vorher:**
```php
<?php
/**
 * Berechnet den Gesamtpreis.
 * @param float $price Netto-Preis
 * @param float $tax   Steuersatz (z. B. 0.19)
 */
function totalPrice(float $price, float $tax): float
{
    // MwSt addieren
    return $price * (1 + $tax); # Ergebnis zurückgeben
}
```

**Nachher:**
```php
<?php
function totalPrice(float $price, float $tax): float
{

    return $price * (1 + $tax); 
}
```

> **Hinweis:** Der `#[Attribute]`-Syntax von PHP 8 wird korrekt erkannt und **nicht** als Kommentar behandelt.

---

## Pass 2 — Whitespace reduzieren (`whitespace`)

Kollabiert aufeinanderfolgende Leerzeichen, Tabs und Leerzeilen zu einem einzigen Leerzeichen oder Zeilenumbruch:

- Mehrere Leerzeichen/Tabs → ein Leerzeichen
- Mehrere Zeilenumbrüche → ein Zeilenumbruch
- Einrückungen werden entfernt

**Vorher:**
```php
<?php

    class OrderService
    {
        private float $taxRate;

        public function __construct(float $taxRate)
        {
            $this->taxRate = $taxRate;
        }
    }
```

**Nachher:**
```php
<?php
class OrderService
{
private float $taxRate;
public function __construct(float $taxRate)
{
$this->taxRate = $taxRate;
}
}
```

> **Empfehlung:** `whitespace` in Kombination mit `comments` verwenden — Whitespace-Pass allein entfernt zwar Einrückungen, aber Kommentare bleiben mit Leerzeilen stehen.

---

## Pass 3 — Konstanten falten (`constants` / `folding`)

Ersetzt arithmetische Ausdrücke mit Literalen und bekannte boolesche Negationen zur Compilezeit.

### Ganzzahlarithmetik

| Operator | Beispiel | Ergebnis |
|----------|----------|----------|
| `+` | `60 * 60` | `3600` |
| `-` | `1024 - 256` | `768` |
| `*` | `8 * 1024 * 1024` | `8388608` |
| `/` | `100 / 4` | `25` (nur wenn ganzzahlig teilbar) |
| `%` | `17 % 5` | `2` |
| `**` | `2 ** 10` | `1024` |

**Beispiele:**
```php
// Vorher:
$timeout = 60 * 60 * 24;       // → 86400
$maxSize = 8 * 1024 * 1024;    // → 8388608
$half    = 100 / 4;             // → 25
$notHalf = 100 / 3;             // bleibt: 100 / 3  (kein exaktes Ergebnis)
```

```php
// Nachher:
$timeout = 86400;
$maxSize = 8388608;
$half    = 25;
$notHalf = 100 / 3;
```

Hexadezimale, binäre und oktale Literale werden ebenfalls unterstützt:
```php
$mask  = 0xFF & 0x0F;           // 255 & 15 = 15
$shift = 1 << 8;                // bleibt: 1 << 8 (Shift ist kein gefalteter Op)
$hex   = 0x10 + 0x20;          // → 48
```

### String-Konkatenation

Einzeln gequotete Strings (`'...'`) werden zusammengefasst:
```php
// Vorher:
$prefix = 'Hello' . ', ' . 'World' . '!';

// Nachher:
$prefix = 'Hello, World!';
```

> **Einschränkung:** Doppelt gequotete Strings (`"..."`) werden nicht gefaltet — sie können variable Interpolation enthalten (`"Hallo $name"`).

### Boolesche Negation

```php
// Vorher:
$active = !false;   // → true
$debug  = !true;    // → false
```

---

## Pass 4 — Toter Code entfernen (`deadcode`)

### 4a — Code nach Exit-Anweisungen

Code nach `return`, `throw`, `exit`, `die` + `;` innerhalb eines Blocks ist unerreichbar und wird entfernt:

```php
// Vorher:
function compute(): int
{
    return 42;
    echo "nie erreicht";
    $x = 100;
    doSomething();
}

// Nachher:
function compute(): int
{
    return 42;
}
```

Die schließende `}` des Blocks bleibt immer erhalten.

### 4b — `if (false)` / `if (0)` entfernen

Blöcke hinter einer Bedingung, die immer `false` oder `0` ist, werden vollständig entfernt:

```php
// Vorher:
if (false) {
    echo "wird nie ausgeführt";
    someHeavyOperation();
}

// Nachher: (Block vollständig entfernt)
```

Mit `else`-Zweig:
```php
// Vorher:
if (false) {
    echo "falsch";
} else {
    echo "richtig";
}

// Nachher:
echo "richtig";
```

### 4c — `if (true)` / `if (1)` auflösen

```php
// Vorher:
if (true) {
    echo "immer ausgeführt";
    doWork();
}

// Nachher: (ohne die if/braces)
echo "immer ausgeführt";
doWork();
```

Mit `else`-Zweig:
```php
// Vorher:
if (true) {
    echo "immer";
} else {
    echo "nie";
}

// Nachher:
echo "immer";
```

---

## Kombination mit Obfuskierung

Wenn `--optimize` und `--obfuscate` zusammen verwendet werden, läuft der **Optimizer immer zuerst**, danach der Obfuskierer:

```
PHP-Quellcode
  → [Optimizer] → optimierter PHP-Code
  → [Obfuskierer] → obfuskierter PHP-Code
  → [AES-256-GCM] → MMENC1-Container
```

```bash
# Optimizer + Obfuskierung + LZ4 (maximale Verschleierung + kleinste Dateigröße):
mmencoder encode-dir \
    --source src/ --output out/ --dev \
    --optimize all \
    --obfuscate \
    --compress lz4
```

---

## Kombination mit LZ4-Komprimierung

Der Optimizer und LZ4 ergänzen sich: Der Optimizer reduziert den Quellcode (entfernt Redundanzen), LZ4 komprimiert dann den optimierten Code weiter.

Typische Einsparungen:
- Optimizer allein: 15–35 % (je nach Kommentaranteil und Konstantendichte)
- LZ4 allein: 40–60 % bei PHP-Quellcode
- Optimizer + LZ4: 50–70 % Gesamteinsparung

---

## Einschränkungen

| Einschränkung | Beschreibung |
|---|---|
| Keine Laufzeitauswertung | Nur Literale (`1 + 2`, `'a' . 'b'`) werden gefaltet — Variablenausdrücke (`$a + $b`) nicht |
| Kein vollständiger PHP-Parser | Der Optimizer arbeitet token-basiert, kein vollständiger AST — komplexe syntaktische Konstrukte werden übersprungen |
| Heredoc/Nowdoc nicht gefaltet | Nur `'...'` (single-quoted) — Heredoc/Nowdoc werden als opaque Token durchgereicht |
| Division nur bei ganzzahligem Ergebnis | `100 / 3` wird nicht gefaltet (Float-Semantik); `100 / 4` wird zu `25` gefaltet |
| Exponent nur für nicht-negative Exponenten | `2 ** -1` wird nicht gefaltet |
| `else if` vs. `elseif` | Beide Schreibweisen werden unterstützt |
| PHP-Attribute `#[...]` | Werden korrekt von `#`-Kommentaren unterschieden |

---

## Dry-Run

Mit `--dry-run` werden keine Dateien geschrieben — der Plan wird nur ausgegeben:

```bash
mmencoder encode-dir \
    --source src/ --output out/ --dev \
    --optimize all \
    --dry-run
```

---

## Testabdeckung

Die Optimizer-Implementation ist vollständig durch Unit-Tests abgedeckt:

```bash
dotnet test src/EncoderCli.Tests/ --filter "PhpOptimizer"
```

Die Testsuite (`PhpOptimizerTests` in `src/EncoderCli.Tests/PhpObfuscatorTests.cs`) umfasst 32 Tests:

| Gruppe | Tests | Inhalt |
|--------|-------|--------|
| `ParsePasses_*` | 4 | `all`, `none`, `null`, kommagetrennte Specs |
| `Optimize_StripComments_*` | 2 | Zeilenkommentar, Blockkommentar |
| `Optimize_Whitespace_*` | 1 | Zusammenfassen mehrerer Leerzeichen |
| `FoldConstants_Int*` | 8 | Add, Sub, Mul, DivExact, DivNonExact, Pow, Mod, HexLiteral |
| `FoldConstants_String*` | 3 | Concat, ChainedConcat, DoubleQuoted (nicht gefaltet) |
| `FoldConstants_Not*` | 2 | `!true→false`, `!false→true` |
| `DeadCode_AfterReturn_*` | 3 | Entfernt, Rest der Datei bleibt, nach throw |
| `DeadCode_IfFalse_*` | 3 | Block entfernt, else-Körper behalten, if(true)-Körper behalten |
| `DeadCode_IfTrue_*` | 2 | Körper behalten, else entfernt |
| `DeadCode_IfZero_*` | 1 | `if(0)` wie `if(false)` behandelt |
| `FoldConstants_InsideString_NotFolded` | 1 | String-Interpolation nicht gefaltet |
| `Combined_*` | 3 | Falten dann Dead Code, alle Passes, `none=unverändert` |

---

## Implementierung

| Datei | Inhalt |
|-------|--------|
| `src/EncoderCli/Encoding/PhpOptimizer.cs` | Token-basierter Optimizer (`PhpOptimizer.Optimize`, `PhpOptimizer.ParsePasses`) |
| `src/EncoderCli/Encoding/ProjectEncoder.cs` | Optimizer-Aufruf vor Obfuskierung in der Encoding-Pipeline |
| `src/EncoderCli/Encoding/LocalDevEncoder.cs` | Optimizer-Aufruf im Dev-Modus |
| `src/EncoderCli/CliArgs.cs` | `--optimize [passes]` CLI-Argument |
| `src/EncoderCli/Configuration/EncoderConfig.cs` | `DefaultOptions.Optimize` Konfigurationsfeld |
| `src/EncoderCli.Tests/PhpObfuscatorTests.cs` | 32 Optimizer-Tests (`PhpOptimizerTests`) |

Die Klasse `PhpOptimizer` implementiert intern einen Mehrstufen-Pipeline:

```
Tokenize()
  → FoldConstants()      (wenn ConstantFolding-Pass aktiv)
  → EliminateDeadCode()  (wenn DeadCode-Pass aktiv)
  → Reconstruct()        (stripComments + collapseWhitespace)
```

Der Tokenizer erkennt: Whitespace, Zeilen-/Blockkommentare, Integer-/Float-Literale, Single-/Double-String, Heredoc/Nowdoc, Bezeichner, Variablen, alle PHP-Operatoren und Satzzeichen.
