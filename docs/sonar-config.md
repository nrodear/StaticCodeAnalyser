# Sonar-Konfiguration — Resolver-Pfade

Konzentrierte Referenz aller vier Konfigurations-Quellen für die
Sonar-Integration. Schritt-für-Schritt-Setup siehe
[sonar-setup.md](sonar-setup.md).

## Auflösungs-Reihenfolge

Beim Start jedes Sonar-Befehls (CLI: `--sonar-*`, IDE: Tools>Options Save,
Export-Menü) ruft die Implementierung
[`TSonarConfigResolver.Resolve`](../StaticCodeAnalyserForm/sources/Infrastructure/uSonarConfig.pas)
in dieser Reihenfolge:

1. **CLI-Flags** — Werte aus `--sonar-host` / `--sonar-token` /
   `--sonar-project` / `--sonar-branch` / `--sonar-insecure` /
   `--sonar-config`. Nur im Standalone-Mode.
2. **Environment-Variablen** — `SONAR_HOST_URL`, `SONAR_TOKEN`,
   `SONAR_PROJECT_KEY`, `SONAR_ORGANIZATION`, `SONAR_BRANCH`. Konvention an
   den offiziellen `sonar-scanner` angelehnt.
3. **`sonar-project.properties`** — relativ zu `--path` bzw. dem Projekt-
   Verzeichnis. Token wird hier **nicht** gelesen (Datei wandert in VCS).
4. **`analyser.ini` `[Sonar]` / `[SonarTokens]`** — User-INI in
   `%APPDATA%\StaticCodeAnalyser\analyser.ini`. Alternative Pfade via
   `--sonar-config <ini>`.

Jede Quelle füllt **nur** Felder die noch leer sind. Was CLI nicht setzt
kann Env setzen, was Env nicht setzt kann Properties setzen, etc.

## Pro Setup-Typ

| Setup | Empfohlene Quelle | Begründung |
|---|---|---|
| Lokaler Entwickler (Docker-Sonar) | User-INI + DPAPI-Token | Einmal über Tools>Options eintragen, persistiert verschlüsselt |
| CI-Pipeline (GitHub Actions, Azure) | Env-Vars aus Secrets | Standard-Pfad für CI, kein State auf der Maschine |
| Geteiltes Team-Setup | `sonar-project.properties` im Repo + Token per User | Project-Key zentral, Token pro Entwickler |
| Plugin-only-User (keine CLI) | Tools>Options | UI ist self-service |

## Felder

| Feld | INI-Key (`[Sonar]`) | Env | CLI | Default |
|---|---|---|---|---|
| Host URL | `HostUrl` | `SONAR_HOST_URL` | `--sonar-host` | — |
| Token | `TokenRef` → `[SonarTokens][TokenRef]` (DPAPI-Hex) | `SONAR_TOKEN` | `--sonar-token` | — |
| Project Key | `ProjectKey` | `SONAR_PROJECT_KEY` | `--sonar-project` | — |
| Organization | `Organization` | `SONAR_ORGANIZATION` | (nicht im CLI) | — |
| Branch | `Branch` | `SONAR_BRANCH` | `--sonar-branch` | leer = main |
| Insecure TLS | `Insecure` | — | `--sonar-insecure` | False |
| SourceMapping | `SourceMapping` | — | — | — |

**Pflichtfelder** für `IsValid`: `HostUrl`, `Token`, `ProjectKey`. Fehlt
einer davon, schreibt `--sonar-test` `Configuration incomplete. Missing: ...`
und beendet mit Exit-Code 99.

## Diagnose

`TSonarConfig.SourceHostUrl`, `SourceToken`, `SourceProjectKey` (Strings)
zeigen, **aus welcher Quelle** der jeweilige Wert kam. `--sonar-test`
gibt das vor dem Health-Check aus:

```
Sonar config:
  host    = http://localhost:9000   (analyser.ini)
  project = my-delphi-project       (env SONAR_PROJECT_KEY)
  token   = (42 chars from CLI --sonar-token)
```

Wenn der User sich wundert "warum nutzt das den falschen Host?" — das ist
die Antwort.

## URL-Sanitization

`HostUrl` wird beim Lesen normalisiert: `http://localhost:9000/` und
`http://localhost:9000///` werden identisch zu `http://localhost:9000`
(Trailing-Slashes entfernt). Damit der spätere `/api/system/status`-Concat
nicht zu `http://localhost:9000//api/system/status` wird.

## DPAPI-Details

Der Token wird unter Windows mit
[`CryptProtectData`](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata)
verschlüsselt (Current-User-Scope, Description `'SCA-Sonar-Token'`). Das
Cipher-Blob wird als **Hex-String** in `[SonarTokens][<TokenRef>]` abgelegt.
Decrypt nur auf demselben Windows-User auf demselben Rechner möglich —
kein Replay über Profile, kein Lesen für Admins.

Non-Windows-Fallback (Linux/macOS): Plaintext mit `PT:`-Prefix
Base64-encoded. Der Resolver erkennt das Prefix; das CLI gibt eine **WARNING**
beim Token-Save. CI/CD sollte stattdessen `SONAR_TOKEN`-Env nutzen.

## Test-Coverage

[`uTestSonarConfig.pas`](../StaticCodeAnalyserForm/tests/uTestSonarConfig.pas)
deckt ab:
- Resolver-Reihenfolge (CLI > Env > Props > INI)
- INI- und Properties-Parser (Comments, `=` vs `:`, Token-Ignore in Properties)
- URL-Sanitization
- DPAPI-Roundtrip (Windows-only)
- Source-Tracking (welches Feld kam aus welcher Quelle)
