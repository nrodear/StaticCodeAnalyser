# Custom Rule Profiles

YAML-Profile für die Custom-Rule-Engine (`uCustomRuleDetector`).
Werden über `[Detectors] CustomRulesFile=...` in `analyser.ini`
oder via CLI-Flag `--custom-rules <file>` aktiviert.

## Demo-Projekt

[`ShowcaseDemo/`](ShowcaseDemo/README.md) - VCL-Demo für das Video: rund 160-220 Funde, jede reDelphix-Code-Aktion mindestens einmal angeboten; Drehbuch: [`ShowcaseDemo/DREHBUCH.md`](ShowcaseDemo/DREHBUCH.md).

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
StaticCodeAnalyser.d12.exe --path . --full --custom-rules profile-strict.yml `
  --report-sarif sca.sarif
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

Rule-IDs müssen unique sein: der Leser prüft das nicht, zwei Regeln mit
derselben ID feuern **beide**, und ihre Funde sind im Report nicht
auseinanderzuhalten.

## Eigenes Profil schreiben

Vorlage: [`analyser-rules.yml`](analyser-rules.yml). Pflichtfelder
pro Regel: `id`, `pattern`. Alles andere optional (sinnvolle
Defaults, siehe Vorlage-Kommentare).

Pattern-Typen (Schlüssel `pattern-type`), alle zeilenweise und mit
Beachtung der Groß-/Kleinschreibung:
- `substring` (default) — naiver Substring-Match
- `word` — nur ganze Identifier: das Muster ist ein bloßer Bezeichner
  (`TADOQuery`), der Leser setzt die Wort-Grenzen selbst. Kein Regex: ein
  `\b` oder `|` im Muster wird als Text gesucht und trifft nie.
- `regex` — PCRE-Syntax (Delphi `System.RegularExpressions`), z. B.
  `\bTIB(Query|Table)\b`; `(?i)` am Anfang ignoriert die Schreibweise

Datei-Filter (Glob-Pattern, mehrere möglich, nur als Block-Liste):

```yaml
    file-include:
      - "**/src/**/*.pas"
    file-exclude:
      - "**/*Test*.pas"
```

- Die Flow-Form `file-include: ["src/**/*.pas"]` versteht der YAML-Leser
  nicht: der Filter fällt still weg, die Regel feuert auf allen Dateien.
- Das Muster wird gegen den **vollen Pfad** der Datei geprüft
  (`C:/Projekt/src/a.pas`, `\` als `/`, Groß-/Kleinschreibung egal) und
  muss ihn ganz abdecken. Darum beginnt jedes Muster mit `**/`:
  `src/**/*.pas` oder `*.pas` treffen nie, `**/src/**/*.pas` trifft
  `src/a.pas` und `src/sub/c.pas`, aber nicht `tests/b.pas`.

Glob-Wildcards:
- `*` — beliebige Zeichen innerhalb eines Pfad-Segments
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
   Der Leser liest das Feld, zeigt es derzeit aber nirgends an (weder im
   HTML-Report noch im Plugin); was der Nutzer sehen soll, gehört in
   `message`.

## Validierung & Debug

- **YAML oder Regex kaputt, Datei fehlt?** → Das hängt am Weg:
  - CLI mit `--custom-rules <datei>`: Meldung auf stderr, Exit 99, kein
    Scan, z. B. `Custom rules error: Custom rule R001: invalid regex
    "[unbalanced": ...` oder `Error: Custom-Rules-Datei existiert nicht: ...`.
  - `[Detectors] CustomRulesFile=` in der `analyser.ini` (IDE-Plugin,
    Oberfläche, CLI ohne `--custom-rules`): der Scan läuft still **ohne**
    Custom-Rules weiter. Den Grund meldet nur OutputDebugString (lesbar z. B.
    mit DebugView): `StaticCodeAnalyser: Custom-Rules-Datei nicht ladbar
    (...)` bzw. `StaticCodeAnalyser: CustomRulesFile nicht gefunden: ...`.
- **Kein Match?** → Pattern-Type checken (substring vs regex),
  File-Globs prüfen: Block-Liste statt `[...]`, Muster mit `**/` am
  Anfang (`**/src/**/*.pas` matcht `src/foo.pas`, NICHT `tests/foo.pas`).

## Beitragen

Eigene generische Profile (z.B. `profile-fmx-mobile.yml`,
`profile-mormot-best-practices.yml`) sind willkommen — PR auf
[github.com/nrodear/StaticCodeAnalyser](https://github.com/nrodear/StaticCodeAnalyser).
