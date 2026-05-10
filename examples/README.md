# Custom Rule Profiles

YAML-Profile für die Custom-Rule-Engine (`uCustomRuleDetector`).
Werden über `[Detectors] CustomRulesFile=...` in `analyser.ini`
oder via CLI-Flag `--custom-rules <file>` aktiviert.

## Verfügbare Profile

| Datei | Fokus | Severity-Verteilung | Use-Case |
|---|---|---|---|
| [`analyser-rules.yml`](analyser-rules.yml) | Generisches Beispiel-Set | mixed | Vorlage für eigene Regeln |
| [`profile-strict.yml`](profile-strict.yml) | Coding-Style-Konventionen | error/warning | Greenfield-Projekte mit Coding-Guideline |
| [`profile-security.yml`](profile-security.yml) | Web/Crypto/IO-Sicherheit | error/warning | Web-/Service-Apps, Public-Facing Code |
| [`profile-legacy-migration.yml`](profile-legacy-migration.yml) | Migration alter Patterns | hint | Modernisierungs-Sprints in Bestandscode |

## Wie aktivieren

### Variante A — pro Projekt (empfohlen)

1. Profil-YAML ins **Projekt-Root** kopieren, z.B. als `analyser-rules.yml`
2. In `%APPDATA%\StaticCodeAnalyser\analyser.ini`:
   ```ini
   [Detectors]
   CustomRulesFile=analyser-rules.yml
   ```
3. Plugin neu starten / "Analyse starten"

Vorteil: Ruleset ist mit dem Code versioniert, im Repo committed,
für das ganze Team identisch.

### Variante B — global

1. Profil-YAML irgendwo zentral ablegen (z.B. `C:\Team\sca-rules.yml`)
2. In `analyser.ini`:
   ```ini
   [Detectors]
   CustomRulesFile=C:\Team\sca-rules.yml
   ```

Vorteil: ein Ruleset für mehrere Projekte. Nachteil: nicht mit dem
Projekt-Code versioniert — Drift-Risiko.

### Variante C — CLI

```powershell
analyser.d12.exe --path . --full --custom-rules profile-strict.yml --report-sarif sca.sarif
```

Vorteil: pro CI-Pipeline ein anderes Profil möglich (z.B. `strict`
auf `main`-Branch, `legacy-migration` auf Feature-Branches).

## Pfad-Auflösung (relative Pfade)

`CustomRulesFile=analyser-rules.yml` wird der Reihe nach gesucht in:
1. `<Projekt-Root>\analyser-rules.yml` ← typisch
2. `%APPDATA%\StaticCodeAnalyser\analyser-rules.yml`
3. `<Tool-Verzeichnis>\analyser-rules.yml`

Erste existierende Datei gewinnt. Absolute Pfade (`C:\...` oder
UNC `\\server\...`) werden direkt verwendet.

## Profile mischen

Ein Projekt kann nur **eine** YAML-Datei laden. Wer mehrere Profile
will, kopiert die Rules in ein gemeinsames File:

```yaml
version: 1
rules:
  # --- aus profile-strict.yml ---
  - id: STRICT001
    ...
  # --- aus profile-security.yml ---
  - id: SEC001
    ...
```

Rule-IDs müssen unique sein — bei Konflikten wird die **letzte**
Definition genommen.

## Eigenes Profil schreiben

Vorlage: [`analyser-rules.yml`](analyser-rules.yml). Pflichtfelder
pro Regel: `id`, `pattern`. Alles andere optional (sinnvolle
Defaults, siehe Vorlage-Kommentare).

Pattern-Typen:
- `substring` (default) — naiver Substring-Match
- `word` — nur ganze Identifier (Wort-Grenzen)
- `regex` — .NET-Regex-Syntax

Datei-Filter:
- `file-include: ["src/**/*.pas"]` — Glob-Pattern, mehrere möglich
- `file-exclude: ["**/*Test*.pas"]`

Glob-Wildcards:
- `*` — ein Pfad-Segment
- `**/` — beliebige Tiefe inkl. null
- `?` — ein Zeichen

## Tipps für Custom Rules

1. **Test mit kleinem Pattern starten** — Substring oder Word zuerst,
   nur wenn nötig zu Regex eskalieren.
2. **`file-exclude` für Test-Code** — fast immer sinnvoll. Tests dürfen
   anti-pattern-haltig sein (Sleep, Mocks, Magic Numbers).
3. **Severity sparsam mit `error`** — nur wenn der Befund einen Build
   in CI failen soll. Andernfalls `warning` oder `hint`.
4. **Message ohne Code-Snippet** — der Grid zeigt schon Datei + Zeile.
   Die Message soll erklären *warum* das Pattern problematisch ist.
5. **`fix-hint` für Migrations-Rules** — der konkrete Refactor-Schritt.
   Wird in HTML-Reports und Plugin-Tooltips angezeigt.

## Validierung & Debug

- **YAML kaputt?** → IDE-Plugin loggt via OutputDebugString
  (Fenster: Tools → Debug-Ausgabe). CLI gibt Error auf stderr.
- **Regex kaputt?** → Lade-Zeit-Exception mit Rule-ID:
  `Custom rule R001: invalid regex "[unbalanced": ...`
- **Kein Match?** → Pattern-Type checken (substring vs regex),
  File-Globs prüfen (`src/**/*.pas` matcht NICHT `tests/foo.pas`).

## Beitragen

Eigene generische Profile (z.B. `profile-fmx-mobile.yml`,
`profile-mormot-best-practices.yml`) sind willkommen — PR auf
[github.com/nrodear/StaticCodeAnalyser](https://github.com/nrodear/StaticCodeAnalyser).
