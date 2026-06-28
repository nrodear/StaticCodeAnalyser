# SCA.Engine — Engine & API
*🇩🇪 Deutsch — 🇬🇧 [English](API.md)*

Statische Code-Analyse für Delphi/Object Pascal als wiederverwendbares
Laufzeit-Package. Dieses Dokument beschreibt die **Engine** (Architektur,
Pipeline) und die **öffentliche API** (`uEngineApi`), über die ein Consumer die
komplette Analyse aufruft, ohne die internen Einheiten zu kennen.

> Englische Demo-/API-Doku: siehe [../SCA.CLI.Demo/README.md](../SCA.CLI.Demo/README.md).
> Lauffähiges Minimal-Beispiel: [../SCA.CLI.Demo/](../SCA.CLI.Demo/).

- **Package:** `SCA.Engine` (`requires rtl;` — keine VCL/FMX-Abhängigkeit)
- **Version:** 0.9.8 (`uSCAConsts.SCA_VERSION`)
- **Umfang:** ~174 Detektoren (Regel-IDs `SCA001`–`SCA183`)

---

## 1. Architektur

Die Engine ist eine reine Analyse-Bibliothek ohne UI. Der Daten-Fluss eines
Scans:

```
  .pas / .dfm
      │
      ▼
  Lexer (uLexer)  ──►  Parser (uParser2)  ──►  AST (uAstNode)
                                                   │
                              ┌────────────────────┤
                              ▼                    ▼
                      AST-Detektoren        Zeilen-/Token-Detektoren
                      (~174 Regeln, je eine uXxx.pas)
                              │
                              ▼
                     TLeakFinding-Liste
                              │
   ┌──────────────────────────┼───────────────────────────────┐
   ▼                          ▼                                 ▼
 Suppression            Confidence-Filter                  Baseline
 (uSuppression:         (uConfidenceFilter:                (uBaseline:
  // noinspection)       MinConfidence)                     bekannte Funde)
   └──────────────────────────┼───────────────────────────────┘
                              ▼
                         TScanResult
                              │
                ┌─────────────┼─────────────┐
                ▼             ▼             ▼
             SARIF          Sonar          HTML
        (uExportSARIF) (uExportSonar…) (uExportHtml)
```

Querschnitts-Infrastruktur:

- **`uAnalyzeContext`** — hält die per-Scan-Caches (AST-Cache, Symbol-Referenz-
  Index, DFM-Repo-Index). Wird durch die Detektoren gereicht; keine globalen
  per-Scan-Variablen mehr.
- **`uStaticFiles`** — rekursive Datei-Sammlung mit Default-Ausschlüssen
  (`__history`, `__recovery`, `.git`, `.svn`, `node_modules`) + Ignore-/Test-
  Filter (`uIgnoreList`).
- **`uRuleCatalog`** — Regel-Metadaten (ID, Titel, Severity, Typ) + Profile.
- **`uRepoSettings`** — `analyser.ini`-Konfiguration (Schwellen, Profile,
  Pfad-Overrides, Custom-Rules).

---

## 2. Schnellstart

Ein rekursiver Scan in einer Zeile:

```pascal
uses uEngineApi;

var Res: TScanResult;
begin
  Res := ScanRecursive('C:\meinprojekt');   // alle Detektoren, default-Limits
  try
    WriteLn('Funde: ', Res.FindingCount,
            '  (Fehler ', Res.ErrorCount,
            ', Warnung ', Res.WarningCount,
            ', Hinweis ', Res.HintCount, ')');
  finally
    Res.Free;   // gibt auch die Findings-Liste frei
  end;
end;
```

Ein vollständiges, lauffähiges Beispiel ist das Projekt **`SCA.CLI.Demo`**.

---

## 3. Die API: `uEngineApi`

Die Facade besteht aus einem Request-Record, einem Result-Objekt, einer
Session-Klasse und zwei Convenience-Funktionen.

### 3.1 Einstiegspunkte

| Aufruf | Zweck |
|--------|-------|
| `ScanRecursive(APath, AProfile=''): TScanResult` | Rekursiver Verzeichnis-Scan (Einzeiler). |
| `AnalyzeSource(ASource, AProfile=''): TScanResult` | In-Memory-Scan eines Quelltext-Strings (Editor-Lint/Embedding). |
| `TAnalysisSession.Create.Run(Req): TScanResult` | Voller Zugriff über `TScanRequest` (alle Optionen). |

### 3.2 `TScanRequest`

Mit `TScanRequest.Init` mit sinnvollen Defaults befüllen (`ssRecursive`, alle
Detektoren, loseste Schwellen), dann gezielt überschreiben.

| Feld | Typ | Bedeutung |
|------|-----|-----------|
| `Scope` | `TScanScope` | Scan-Art (s. 3.5). Default `ssRecursive`. |
| `Path` | `string` | Wurzel (rekursiv) / Datei (single) / Basis-Dir (Liste). |
| `Files` | `TArray<string>` | Explizite Datei-Liste für `ssFileList`. |
| `Source` | `string` | In-Memory-Quelltext für `ssSource`. |
| `VcsRange` | `string` | `ssVcsChanged`: `''`=Auto, sonst `shaA..shaB`. |
| `Profile` | `string` | `''`=alle Detektoren, sonst Profilname (s. 3.6). |
| `MinSeverity` | `TLeakSeverity` | Funde unter dieser Schwelle werden verworfen. |
| `MinConfidence` | `TFindingConfidence` | FP-Schwelle (Default `fcMedium`). |
| `MaxFileBytes` | `Integer` | `<=0` → Engine-Default (5 MB). |
| `UsesCheck` | `Boolean` | Teuren Unused-Uses-Detektor mitlaufen lassen. |
| `AutoDiscover` | `Boolean` | Custom-Klassen während des Scans entdecken. |
| `IfdefDefines` | `TArray<string>` | `{$IFDEF}`-aware Parsing mit diesen Defines. |
| `CustomRulesPath` | `string` | YAML mit Custom-Rules (`''`=keine). |
| `BaselinePath` | `string` | Funde gegen Baseline-JSON filtern (`''`=aus). |
| `WriteBaselinePath` | `string` | Aktuelle Funde als neue Baseline schreiben. |
| `ApplyRepoIni` | `Boolean` | `analyser.ini` voll laden+anwenden (wie der CLI). |
| `MinSeverityName` | `string` | INI-Modus: Override `'error'`/`'warning'`/`'hint'`. |
| `ConfigRoot` | `string` | INI-Modus: Wurzel für INI-/Rules-Auflösung. |
| `SkipConfig` | `Boolean` | `true`: keine Config anwenden (Consumer hat State selbst gesetzt). |
| `SingleFileProjectRoot` | `string` | `ssSingleFile`: ProjectRoot für Cross-Unit-Index. |
| `IgnoreList` | `TIgnoreList` | `ssRecursive`: Ignore-/Test-Filter (`nil`=keiner). |
| `Progress` | `TProc<Integer,Integer>` | `(current,total)`; `EAbort` darin bricht ab. |

### 3.3 `TScanResult`

Besitzt die Findings-Liste; mit `.Free` freigeben (gibt die Findings mit frei,
außer nach `ReleaseFindings`).

```pascal
TScanResult = class
  function FindingCount: Integer;     // Gesamtzahl
  function ErrorCount:   Integer;     // Severity lsError
  function WarningCount: Integer;     // Severity lsWarning
  function HintCount:    Integer;     // Severity lsHint
  property Findings: TObjectList<TLeakFinding>;   // Detailzugriff
  property BaseDir:  string;                       // Scan-Wurzel

  function ReleaseFindings: TObjectList<TLeakFinding>;  // Ownership abgeben

  procedure WriteSarif(const AFileName: string;
                       const AToolName: string = SCA_DEFAULT_TOOLNAME);
  procedure WriteSonar(const AFileName: string);
  procedure WriteHtml (const AFileName: string);
end;
```

### 3.4 Konfigurations-Modi

`TAnalysisSession.Run` entscheidet anhand des Requests, woher die Detektor-
Konfiguration kommt:

1. **Direkt (Default):** Nur die Felder des Requests (`Profile`, `MinSeverity`,
   `MinConfidence`, `MaxFileBytes`, `IfdefDefines`, `CustomRulesPath`). Keine
   `analyser.ini`. → das macht `ScanRecursive`/`AnalyzeSource`.
2. **`ApplyRepoIni := True`:** Lädt die `analyser.ini` (aus `ConfigRoot`/`Path`)
   und wendet sie voll an — 8 Schwellen, Pfad-Overrides, Magic-/Format-Listen,
   INI-Profil + INI-Custom-Rules. So fährt der CLI.
3. **`SkipConfig := True`:** `Run` wendet **keine** Config an — der Consumer hat
   den globalen Detektor-/Schwellen-State bereits selbst gesetzt (so machen es
   IDE-Plugin und Form über ihre eigene Vorbereitung). `Run` macht dann nur
   Scope → Scan → Baseline.

### 3.5 Scopes (`TScanScope`)

| Wert | Beschreibung |
|------|--------------|
| `ssRecursive` | Verzeichnis rekursiv (Default). Nutzt `Path` + optional `IgnoreList`. |
| `ssSingleFile` | Eine `.pas`-Datei (`Path`); mit `SingleFileProjectRoot` projektweiter Symbol-Index. |
| `ssFileList` | Explizite Datei-Liste (`Files`); `Path` = optionaler Basis-Dir. |
| `ssVcsChanged` | Nur per VCS geänderte Dateien (`Path`=Repo, `VcsRange` optional). |
| `ssSource` | In-Memory-Quelltext (`Source`); `Path`=optionaler logischer Name. |

### 3.6 Profile

Ein Profil ist eine Whitelist von Befund-Arten. `''` (leer) = **alle**
Detektoren. Eingebaute Profile (`uRuleCatalog`):

| Profil | Inhalt |
|--------|--------|
| `default` / `strict` | Alle Regeln. |
| `ide-fast` | Schnelles Subset für Live-Analyse (Bugs + Vulnerabilities + DFM-Kritisches). |
| `security` | Nur Vulnerabilities/Secrets (SQLInjection, HardcodedSecret, …). |
| `bugs-only` | Nur echte Fehler (Leaks, NilDeref, DivByZero, FormatMismatch, …). |
| `code-quality` | Code-Smells (LongMethod, MagicNumber, Cyclomatic, Duplikate, …). |
| `dfm-only` | Nur DFM-/Formular-Regeln. |

### 3.7 Datenmodell: `TLeakFinding` (`uMethodd12`)

Jeder Befund:

| Member | Typ / Rückgabe | Bedeutung |
|--------|----------------|-----------|
| `FileName` | `string` | Quelldatei. |
| `MethodName` | `string` | Methode/Routine (falls bekannt). |
| `LineNumber` / `LineInt` | `string` / `Integer` | Zeile (String-Feld + Integer-Helper). |
| `MissingVar` / `Message` | `string` | Detailmeldung (`Message` = Alias). |
| `Severity` | `TLeakSeverity` | `lsError` / `lsWarning` / `lsHint`. |
| `Kind` | `TFindingKind` | Konkrete Regel-Art (`fkXxx`). |
| `Confidence` | `TFindingConfidence` | `fcLow` / `fcMedium` / `fcHigh`. |
| `RuleID` | `string` | Custom-Rule-ID (sonst leer). |
| `FindingType` | `TFindingType` | Kategorie (s.u.). |
| `SeverityText` / `TypeText` | `string` | Lesbare Labels. |
| `ResolvedRuleId` | `string` | `SCAxxx` (RuleID falls gesetzt, sonst Catalog-Lookup). |

Enums (`uSCAConsts`):

```pascal
TLeakSeverity     = (lsError, lsWarning, lsHint);
TFindingConfidence= (fcLow, fcMedium, fcHigh);
TFindingType      = (ftBug, ftCodeSmell, ftVulnerability,
                     ftSecurityHotspot, ftCodeDuplication, ftFileError);
```

---

## 4. Lebenszyklus / Threading

- Die Engine ist **nicht thread-safe** (geteilter globaler Konfig-/Cache-State).
  Pro Prozess einen Scan zur Zeit.
- Der **rekursive Scan** ist für kurzlebige Ein-Scan-Prozesse (CLI/Demo) sicher.
  In residenten Hosts (IDE) den Single-File-/Source-Pfad bevorzugen.
- `TScanResult` besitzt die Findings; `Free` gibt sie frei. Mit
  `ReleaseFindings` geht die Ownership an den Aufrufer über.

---

## 5. Das Package referenzieren (Consumer-Setup)

Ein Fremd-Consumer braucht **nur das Package**, keine Engine-Quelltexte:

- `.dproj`: `UsePackages=true` und `DCC_UsePackage` enthält `SCA.Engine;rtl`.
- **Kein** Engine-Source-Verzeichnis im `DCC_UnitSearchPath`.
- Zur Laufzeit muss `SCA.Engine.bpl` auffindbar sein (globales BPL-Verzeichnis
  oder neben der `.exe`).
- `uses uEngineApi;` (+ bei Detailzugriff `uMethodd12`, `uSCAConsts`) — alles aus
  dem Package.

Vollständiges Beispiel inkl. `.dpr`/`.dproj`: **`SCA.CLI.Demo`**.

---

## 6. Beispiele

**Profil + SARIF-Export:**

```pascal
var Res := ScanRecursive('C:\src', 'security');
try
  Res.WriteSarif('report.sarif');
finally
  Res.Free;
end;
```

**Voller Request (INI-Modus, Baseline, Fortschritt):**

```pascal
var Req := TScanRequest.Init;
Req.Path          := 'C:\src';
Req.ApplyRepoIni  := True;            // analyser.ini voll anwenden
Req.BaselinePath  := 'baseline.json'; // bekannte Funde ausblenden
Req.Progress      := procedure(C, T: Integer)
                     begin Write(#13, C, '/', T); end;

var Ses := TAnalysisSession.Create;
try
  var Res := Ses.Run(Req);
  try
    Res.WriteSonar('sonar.json');
  finally
    Res.Free;
  end;
finally
  Ses.Free;
end;
```

**In-Memory (Editor-Lint):**

```pascal
var Res := AnalyzeSource(EditorBuffer.Text);
try
  for var F in Res.Findings do
    WriteLn(F.LineInt, ': [', F.ResolvedRuleId, '] ', F.Message);
finally
  Res.Free;
end;
```

---

## 7. Exit-Code-Konvention (CLI/Tools)

Eigenständige Tools nutzen üblicherweise: `0` = sauber, `3` = Funde vorhanden,
`1`/`2` = Fehler (Ausnahme / ungültiger Pfad). Siehe `SCA.CLI.Demo`.
