# SCA.Engine — Engine & API
*🇩🇪 Deutsch — 🇬🇧 [English](API.md) — 🇫🇷 [Français](API_fr.md)*

Statische Code-Analyse für Delphi/Object Pascal als wiederverwendbares
Laufzeit-Package. Dieses Dokument beschreibt die **Engine** (Architektur,
Pipeline) und die **öffentliche API** (`uEngineApi`), über die ein Consumer die
komplette Analyse aufruft, ohne die internen Einheiten zu kennen.

> Englische Demo-/API-Doku: siehe [../SCA.CLI.Demo/README.md](../SCA.CLI.Demo/README.md).
> Lauffähiges Minimal-Beispiel: [../SCA.CLI.Demo/](../SCA.CLI.Demo/).

- **Package:** `SCA.Engine` (`requires rtl;` — keine VCL/FMX-Abhängigkeit)
- **Version:** 0.9.14 (`uSCAConsts.SCA_VERSION`)
- **Umfang:** ~196 Detektoren (Regel-IDs `SCA001`–`SCA196`)

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
                      (~178 Regeln, je eine uXxx.pas)
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

### 3.8 Quellstellen: `TSourcePlaces` (`uSourcePlaces`)

Beschreibt Stellen einer Quelldatei **auf Anfrage** — für Konsumenten, die Code umschreiben wollen (z. B. das Modul „Source Refactor" reDelphix). Der Dienst liest nur: kein Scan läuft, kein Fund, Feld oder Export wird berührt, und kein Detektor benutzt ihn. Eine Instanz je Datei.

`uEngineApi` exportiert die Klassen- und Record-Typen weiter: `TSourcePlaces`, `TNodeRef`, `TSourceLineRange`, `TUsesSection`, `TNodeKind`, `TNodeKinds`, `TRefactorInfo`, `TRefactorSpan`. Konstanten und Enum-Werte exportiert es **nicht**: die Rollen (`ROLE_*`), Werttypen (`rv*`, `TRefactorValueType`) und Flags (`rf*`, `TRefactorFlags`) brauchen `uses uRefactorInfo`, die Vertragsversion `SOURCE_PLACES_VERSION` braucht `uses uSourcePlaces`. Beide Units liegen im Package.

```pascal
Places := TSourcePlaces.Create;
try
  try
    Opened := Places.Open(FileName);    // False: Datei nicht lesbar
  except
    on E: Exception do
    begin
      Log(E.Message);                   // Parser-Fehler, auch der Watchdog
      Opened := False;                  // nichts ist geöffnet (IsOpen = False)
    end;
  end;
  if Opened then
  begin
    Nodes := Places.NodesAt(Line, [TNodeKind.nkAssign]);   // Fundzeile -> AST-Knoten
    if Length(Nodes) = 1 then
    begin
      Info := Places.ChainOf(Nodes[0].Line, Nodes[0].Col, Nodes[0].Name);
      try
        if Assigned(Info) and Info.FixSafe then
          ...                                              // Umformung bauen
      finally
        Info.Free;
      end;
    end;
  end;
finally
  Places.Free;
end;
```

| Member | Liefert | Bedeutung |
|--------|---------|-----------|
| `Open(FileName)` / `Close` | `Boolean` | Liest die Datei selbst (kein Scan-Cache, kein Engine-Lock) und parst genau den dekodierten Text. `False`, wenn nicht lesbar. Ein Parser-Fehler (auch der Watchdog des Parsers) **wirft**; danach ist der Dienst geschlossen (`IsOpen = False`). Ein vorher geöffneter Text wird zuerst verworfen. |
| `OpenSource(FileName, Source)` | `Boolean` | Wie `Open`, aber auf einem Text, den der Host übergibt (IDE: der Editor-Puffer mit ungespeicherten Änderungen). `FileName` ist nur der Name; die Datei wird nicht gelesen. `False` bei leerem Text; ein Parser-Fehler wirft wie bei `Open`. |
| `IsOpen` / `FileName` / `LineCount` | `Boolean` / `string` / `Integer` | Zustand des geöffneten Texts. |
| `StatementAt(Line, Col)` | `TRefactorInfo` | Die dort beginnende Anweisung: Bereich mit Spalten, Flags, Einfügepunkt, Hash. `nil`, wenn ihr Ende nicht bestimmbar ist, auch wenn ein Delphi-12-Mehrzeilenstring (`'''`) darin steht. |
| `ChainOf(Line, Col, ExpectedTarget = '', ExpectedPlus = ANY_PLUS_COUNT)` | `TRefactorInfo` | Zuweisung mit `+`-Kette: Ziel, Literale, Operanden, `FixSafe`. Zwei Gegenproben, jede liefert bei Abweichung `nil`: das Ziel gegen `ExpectedTarget` (`TNodeRef.Name`; `''` = keine Prüfung) und die Zahl der `+` auf oberster Ebene gegen `ExpectedPlus`, vom Konsumenten unabhängig gezählt (etwa aus `TNodeRef.TypeRef`, so wie SCA044 zählt). Jeder negative Wert (`TSourcePlaces.ANY_PLUS_COUNT`) heißt: keine Prüfung. |
| `CallOf(Line, Col, ExpectedHead)` | `TRefactorInfo` | Aufruf-Anweisung: Kopf plus Kette des einen Arguments, sonst je Argument ein `argument`-Teil. `ExpectedHead` ist der Kopf vor der ersten `(` (`''` = keine Prüfung). |
| `NodesAt(Line, Kinds)` | `TArray<TNodeRef>` | AST-Knoten der Arten, die auf der Zeile beginnen, nach Spalte sortiert. Zwei Treffer heißen: mehrdeutig. |
| `UsesEntries(Section)` | `TArray<TRefactorSpan>` | Jeder Unit-Name der `uses`-Klauseln mit Bereich (`Resolved` = Name wie geschrieben). `usAny` (Vorgabe) umfasst auch die Klausel eines Programms oder einer Library. |
| `IdentifiersIn(Span)` | `TArray<TRefactorSpan>` | Bezeichner in einem Bereich als `ident`-Teile; Schlüsselwörter werden nicht gefiltert. Strings und Kommentare sind ausgeblendet — auch wenn der Bereich mitten in einem beginnt, denn die Datei wird bis zum Bereich mitgelesen. Grenze: einen Delphi-12-Mehrzeilenstring (`'''`) vor dem Bereich erkennt das nicht. |
| `CodeViewOf` / `TextOf` / `HashOf` | | Spaltentreue Code-Sicht, Rohtext und SHA-256 eines Bereichs, alle auf dem Text des letzten `Open`/`OpenSource`. `HashOf` sieht keine spätere Änderung: um eine zu erkennen, den aktuellen Text neu öffnen und `HashOf(Info.Span)` mit `Info.SpanHash` vergleichen, oder direkt vor dem Schreiben `TextOf(Span)` mit dem Zielpuffer vergleichen (so macht es reDelphix). |
| `ConditionalRanges` | `TArray<TSourceLineRange>` | `{$IFDEF}`-Bereiche der Datei. |
| `SectionLine(Section)` | `Integer` | Zeile des Schlüsselworts `interface` / `implementation`; `0`, wenn der Abschnitt fehlt (Programm, Library), und für `usAny`. |
| `LineText(Line)` | `string` | Text einer Zeile des geöffneten Texts; `''` außerhalb. |
| `SpanHasComment(Span)` | `Boolean` | `True`, wenn im Bereich ein Kommentar oder eine Compiler-Direktive steht — für einen Konsumenten, der nur einen Teil einer Anweisung ersetzt (`rfHasComment` gilt für die ganze Anweisung). |
| `DeclaredTypeOf(Line, Name)` | `string` | Deklarierter Typ (nackt, klein geschrieben) eines Bezeichners: Parameter oder lokale Variable der umschließenden Routine, sonst Feld oder Unit-Global; `''`, wenn unbekannt. `Line` ist die **Ankerzeile** einer Anweisung (Zeile eines AST-Knotens), keine Fortsetzungszeile. Kennt keine `with`-Blöcke: liefert die gefundene Deklaration auch dort, wo der Compiler den Namen an ein Member des `with`-Ausdrucks bindet. |
| `InWithBlock(Line)` | `Boolean` | `True`, wenn die Zeile im Rumpf einer `with`-Anweisung liegt (zeilengenau, von der `with`-Zeile bis zur letzten Knoten-Zeile ihrer Anweisung). Das fragen, bevor man aus `DeclaredTypeOf` etwas beweist. |
| `CollectNodesAt` / `CollectUsesEntries` / `CollectIdentifiers` | | Klassenfunktionen: dasselbe auf einem Baum, einer Zeilenliste oder einer Code-Sicht, die der Aufrufer schon hat — für Tests und Konsumenten mit eigenem AST. |

**`TNodeRef`** kopiert die Knotenfelder, die ein Konsument braucht: `Kind`, `Line`, `Col`, `Name` (Ziel bzw. Kopf, wie der Parser ihn zusammengefügt hat) und `TypeRef` (rechte Seite bzw. Typbezug, abgeflacht). Der Baum selbst gehört dem Dienst und lebt nur bis zum nächsten `Open`/`Close`.

**Was `ChainOf` und `CallOf` beweisen.** Ein Operand, der ein bloßer Bezeichner ist, bekommt seinen deklarierten Typ (`rvString`/`rvNonString`, `Resolved` = Typname), und `FixSafe` wird neu abgeleitet. Unbekannt bleibt unbekannt: `rvUnknown` und `FixSafe = False` sind der Normalfall. Keinen `rvString`-Beweis gibt es in einem `with`-Block (`InWithBlock`; `Resolved` nennt weiter die gefundene Deklaration) und keinen für einen bekannten RTL-Aufruf oder einen `.ToString`-Term, dessen Namen eine Funktion der Unit selbst mit einem Nicht-String-Ergebnis deklariert — sie verdeckt die RTL-Routine (z. B. ein unit-lokales `function Trim(..): Variant`). Mit `SysUtils.`/`StrUtils.` qualifizierte Aufrufe behalten ihren Beweis. Eine Funktion in einer verschachtelten Routine sieht der Dienst nicht (der Parser verwirft verschachtelte Routinen).

Koordinaten sind 1-basiert; `EndCol` zeigt **hinter** das letzte Zeichen. Jedes Primitiv außer `Open`/`OpenSource` ist total (`nil`, leer, `0` oder `False` statt Exception, auch wenn nichts geöffnet ist). `SOURCE_PLACES_VERSION` (= 1) ist die Vertragsversion — eine **Übersetzungszeit**-Konstante: ein Konsument prüft sie mit `{$IF SOURCE_PLACES_VERSION <> 1}{$MESSAGE ERROR '...'}{$IFEND}` (reDelphix tut das in `uRdxRecipeRunner`) und baut dann gegen einen geänderten Vertrag nicht mehr. Eine zur Laufzeit getauschte BPL erkennt sie nicht; das leistet die Paketbindung (DCP/`requires`). Die Version steigt bei einer Änderung an der Signatur eines bestehenden Primitivs, an Rollen, an Koordinaten oder an einer Ableitung von `FixSafe`/`ValueType`/`Resolved`, die etwas neu als bewiesen meldet; sie bleibt bei neuen Primitiven, neuen Parametern mit Vorgabewert und Ableitungen, die nur strenger werden.

Je Regel kann `rules/sca-rules.json` `anchor` (worauf die Funde ankern: `statement`, `assign`, `call`, `assign-or-call`; `uses-item` ist reserviert) und `fixMode` (`none` / `assisted` / `auto`) tragen; gelesen über `TRuleCatalog` (`TRuleMeta.Anchor`, `TRuleMeta.FixMode`). Ein fehlender oder unbekannter Wert fällt auf den einkompilierten Katalog zurück; abgeschaltet wird eine Regel mit `"fixMode": "none"`.

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
- Zur Laufzeit muss `SCA.Engine290.bpl` auffindbar sein (globales BPL-Verzeichnis
  oder neben der `.exe`).
- `uses uEngineApi;` (+ bei Detailzugriff `uMethodd12`, `uSCAConsts`;
  `uRefactorInfo`, `uSourcePlaces` für die Konstanten des Quellstellen-Dienstes,
  s. 3.8) — alles aus dem Package.

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
