# SCA.Engine — Engine & API
*🇩🇪 Deutsch — 🇬🇧 [English](API.md) — 🇫🇷 [Français](API_fr.md)*

Statische Code-Analyse für Delphi/Object Pascal als wiederverwendbares
Laufzeit-Package. Dieses Dokument beschreibt die **Engine** (Architektur,
Pipeline) und die **öffentliche API** (`uEngineApi`), über die ein Consumer die
komplette Analyse aufruft, ohne die internen Einheiten zu kennen.

> Englische Demo-/API-Doku: siehe [../SCA.CLI.Demo/README.md](../SCA.CLI.Demo/README.md).
> Lauffähiges Minimal-Beispiel: [../SCA.CLI.Demo/](../SCA.CLI.Demo/).

- **Package:** `SCA.Engine` (`requires rtl, xmlrtl;` — `xmlrtl` liest `.dproj`/`.groupproj` für die Projekt-Scopes; keine VCL/FMX-Abhängigkeit)
- **Version:** 0.9.18 (`uSCAConsts.SCA_VERSION`)
- **Umfang:** 205 Regeln (Regel-IDs `SCA001`–`SCA205`, `rules/sca-rules.json`)

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
Session-Klasse, einem Testfixture-Filter und zwei Convenience-Funktionen.

### 3.1 Einstiegspunkte

| Aufruf | Zweck |
|--------|-------|
| `ScanRecursive(APath, AProfile=''): TScanResult` | Rekursiver Verzeichnis-Scan (Einzeiler). |
| `AnalyzeSource(ASource, AProfile=''): TScanResult` | In-Memory-Scan eines Quelltext-Strings (Editor-Lint/Embedding). |
| `TAnalysisSession.Create.Run(Req): TScanResult` | Voller Zugriff über `TScanRequest` (alle Optionen). |

### 3.2 `TScanRequest`

Mit `TScanRequest.Init` mit sinnvollen Defaults befüllen (`ssRecursive`, alle
Detektoren, loseste Schwellen, Ein-Zweig-`{$IFDEF}`-Sicht mit
`TScanRequest.DefaultIfdefDefines`, Include-Defines an, `dlDelphi`, seriell),
dann gezielt überschreiben.

| Feld | Typ | Bedeutung |
|------|-----|-----------|
| `Scope` | `TScanScope` | Scan-Art (s. 3.5). Default `ssRecursive`. |
| `Path` | `string` | Wurzel (rekursiv) / Datei (single) / Basis-Dir (Liste) / `.dproj`, `.lpi`, `.lpk` (Projekt) / `.groupproj`, `.lpg` (Projektgruppe). |
| `Files` | `TArray<string>` | Explizite Datei-Liste für `ssFileList`. |
| `Source` | `string` | In-Memory-Quelltext für `ssSource`. |
| `VcsRange` | `string` | `ssVcsChanged`: `''`=Auto, sonst `shaA..shaB`. |
| `Profile` | `string` | `''`=alle Detektoren, sonst Profilname (s. 3.6). |
| `MinSeverity` | `TLeakSeverity` | Funde unter dieser Schwelle werden verworfen. |
| `MinConfidence` | `TFindingConfidence` | FP-Schwelle (Default `fcMedium`). |
| `MaxFileBytes` | `Integer` | `<=0` → Engine-Default (5 MB). |
| `UsesCheck` | `Boolean` | Teuren Unused-Uses-Detektor mitlaufen lassen. |
| `AutoDiscover` | `Boolean` | Custom-Klassen während des Scans entdecken. |
| `IfdefDefines` | `TArray<string>` | `{$IFDEF}`-aware Parsing mit diesen Defines: ein Zweig, wie ihn ein Compiler sieht. `Init` setzt `DefaultIfdefDefines` (`MSWINDOWS`, `WIN64`, `UNICODE`, `CONDITIONALEXPRESSIONS`); `nil`/leer = beide Zweige jedes `{$IFDEF}`. Scan-Sicht: `Run` wendet sie auch bei `SkipConfig` an. |
| `IncludeDefines` | `Boolean` | `{$I}`-Include-Dateien für ihre `{$DEFINE}`-Wirkung lesen. `Init` setzt `True`; `False` = Include-blind (CLI `--no-include-defines`). Scan-Sicht wie `IfdefDefines`. |
| `Dialect` | `TSourceDialect` | `dlDelphi` (`Init`) oder `dlFpc` (`uSCAConsts`): `dlFpc` sammelt beim Verzeichnis-Walk zusätzlich `*.pp` und ergänzt bei nicht leerem `IfdefDefines` `FPC` und `LCL`. Bei `.lpi`/`.lpk`/`.lpg`-Projekt-Scopes erzwungen `dlFpc`. Scan-Sicht wie `IfdefDefines`. |
| `CustomRulesPath` | `string` | YAML mit Custom-Rules (`''`=keine). |
| `BaselinePath` | `string` | Funde gegen Baseline-JSON filtern (`''`=aus). |
| `WriteBaselinePath` | `string` | Aktuelle Funde als neue Baseline schreiben. |
| `ApplyRepoIni` | `Boolean` | `analyser.ini` voll laden+anwenden (wie der CLI). |
| `MinSeverityName` | `string` | INI-Modus: Override `'error'`/`'warning'`/`'hint'`. |
| `ConfigRoot` | `string` | INI-Modus: Wurzel für INI-/Rules-Auflösung. |
| `SkipConfig` | `Boolean` | `true`: keine Config anwenden (Consumer hat State selbst gesetzt). |
| `IndexRoot` | `string` | `ssProject`/`ssProjectGroup`/`ssFileList`: Verzeichnis, über das die Cross-Unit-Indizes (Symbol-Referenzen, Typen, DFM) gebaut werden, während die Analyse auf der Liste bleibt. `''` = gemeinsamer Wurzelpfad der aufgelösten Liste (Projekt-Scopes) bzw. die Liste selbst (`ssFileList`). |
| `SingleFileProjectRoot` | `string` | `ssSingleFile`: ProjectRoot für Cross-Unit-Index. |
| `IgnoreList` | `TIgnoreList` | `ssRecursive`, `ssProject`, `ssProjectGroup`: Ignore-/Test-Filter (`nil`=keiner). |
| `Parallel` | `Boolean` | Per-Datei-paralleler Scan (Opt-in, `Init`: `False`; CLI `--parallel`). Fällt auf seriell zurück, wenn ein nicht parallel-sicherer Modus aktiv ist (Auto-Discovery, Custom-Rules, Detektor-Zeitmessung); die Ergebnis-Reihenfolge gleicht dem seriellen Lauf. Bei `SkipConfig` nicht angewendet. |
| `ParallelWorkers` | `Integer` | Worker-Zahl bei `Parallel`; `0` = `TThread.ProcessorCount`. |
| `Progress` | `TProc<Integer,Integer>` | `(current,total)`; `EAbort` darin bricht ab. Im Parallel-Modus kommt der Callback erst in der Merge-Phase, auf dem Aufrufer-Thread. |

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
   Scope → Scan → Baseline. Die Scan-Sicht (`IfdefDefines`, `IncludeDefines`,
   `Dialect`) gilt in jedem Modus.

### 3.5 Scopes (`TScanScope`)

| Wert | Beschreibung |
|------|--------------|
| `ssRecursive` | Verzeichnis rekursiv (Default). Nutzt `Path` + optional `IgnoreList`. |
| `ssSingleFile` | Eine `.pas`-Datei (`Path`); mit `SingleFileProjectRoot` projektweiter Symbol-Index. |
| `ssFileList` | Explizite Datei-Liste (`Files`); `Path` = optionaler Basis-Dir. |
| `ssVcsChanged` | Nur per VCS geänderte Dateien (`Path`=Repo, `VcsRange` optional). |
| `ssSource` | In-Memory-Quelltext (`Source`); `Path`=optionaler logischer Name. |
| `ssProject` | Dateien eines Projekts (`Path` = `.dproj`: dessen `DCCReference`-Liste; `.lpi`/`.lpk`: das Lazarus-Pendant); meldet zusätzlich Dateien im Projektordner, die das Projekt nicht führt (SCA194/SCA195). |
| `ssProjectGroup` | Vereinigung der Projekt-Listen einer Gruppe (`Path` = `.groupproj` oder `.lpg`). |

Eine nicht auflösbare Projektdatei liefert ein Ergebnis mit genau einem
`fkFileReadError`-Fund statt einer Exception.

### 3.6 Profile

Ein Profil ist eine Whitelist von Befund-Arten. `''` (leer) = **alle**
Detektoren. Eingebaute Profile (`uRuleCatalog`):

| Profil | Inhalt |
|--------|--------|
| `default` | Alle Regeln außer den Stil-Regeln von `style`. |
| `strict` | Alle Regeln. |
| `ide-fast` | Schnelles Subset für Live-Analyse (Bugs + Vulnerabilities + DFM-Kritisches). |
| `security` | Nur Vulnerabilities/Secrets (SQLInjection, HardcodedSecret, …). |
| `bugs-only` | Nur echte Fehler (Leaks, NilDeref, DivByZero, FormatMismatch, …). |
| `code-quality` | Code-Smells (LongMethod, MagicNumber, Cyclomatic, Duplikate, …). |
| `dfm-only` | Nur DFM-/Formular-Regeln. |
| `style` | Nur Stil-Regeln (PublicMemberWithoutDoc, BeginEndRequired, WithStatement, …). |
| `selftest-quiet` | Alle Regeln außer einigen Layout-Regeln — für den Scan des Analysers selbst. |

### 3.7 Datenmodell: `TLeakFinding` (`uMethodd12`)

Jeder Befund:

| Member | Typ / Rückgabe | Bedeutung |
|--------|----------------|-----------|
| `FileName` | `string` | Quelldatei. |
| `MethodName` | `string` | Methode/Routine (falls bekannt). |
| `LineNumber` / `LineInt` | `string` / `Integer` | Zeile (String-Feld + Integer-Helper). |
| `EndLine` / `SpanEnd` / `IsMultiLine` / `SpanLineCount` | `Integer` / `Integer` / `Boolean` / `Integer` | Letzte Zeile des Befund-Bereichs. `EndLine = 0` (Default) = einzeilig; `SpanEnd` lesen (geklemmt, nie kleiner als die Startzeile) statt des Rohfelds. Ein Bereich ändert nur, wie viel Fläche ein Fund markiert, nie die Zahl der Funde. |
| `MissingVar` / `Message` | `string` | Detailmeldung (`Message` = Alias). |
| `Severity` | `TLeakSeverity` | `lsError` / `lsWarning` / `lsHint` — so, wie sie nach den Post-Filtern (Evidenz-Politik, `[PathOverrides]`) steht. |
| `OriginalSeverity` | `TLeakSeverity` | Die Schwere, die der **Detektor** vergeben hat. Post-Filter ändern `Severity` nur über `OverrideSeverity`, das die erste Original-Schwere sichert; `SavedDetectorSeverity`/`SeverityWasOverridden` sind deren Speicher — nicht direkt lesen. |
| `Kind` | `TFindingKind` | Konkrete Regel-Art (`fkXxx`). |
| `Confidence` | `TFindingConfidence` | `fcLow` / `fcMedium` / `fcHigh`. |
| `RuleID` | `string` | Custom-Rule-ID (sonst leer). |
| `RelatedLines` | `string` | Weitere Zeilen derselben Sache — heute nur SCA015/SCA021 (die Partnerstellen einer Duplikat-Gruppe): kommagetrennte 1-basierte Zeilennummern, aufsteigend, ohne die Ankerzeile; leer bei allen anderen Regeln. |
| `StructureChain` | `string` | Verschachtelungskette zur Fundstelle, von außen nach innen, verbunden mit `CHAIN_SEP` (`' → '`), z. B. `if → for → while`; heute nur SCA018 (DeepNesting), sonst leer. |
| `LeakVariant` / `MemoryLeakVariant` | `string` | Variante von SCA001 (MemoryLeak): `never-freed`, `freed-outside-finally`, `return-value-not-freed`, `proven-leak`. `LeakVariant` ist das Feld, das der Detektor setzt (leer = nicht gesetzt); `MemoryLeakVariant` liefert es oder leitet es aus `OriginalSeverity` und Meldung ab; `''` bei jeder anderen Art. |
| `FindingType` | `TFindingType` | Kategorie (s.u.). |
| `SeverityText` / `TypeText` | `string` | Lesbare Labels. |
| `ResolvedRuleId` | `string` | `SCAxxx` (RuleID falls gesetzt, sonst Catalog-Lookup). |

`RelatedLines`, `StructureChain` und `LeakVariant` stehen bewusst nicht in der
Meldung und damit weder im SARIF- noch im Baseline-Fingerprint. Erzeuger legen
Funde mit `TLeakFinding.New(...)`/`NewAtPos(...)` oder `Create` +
`SetKind(Kind[, Confidence])` an (Schwere aus der Katalog-Vorgabe).

Enums (`uSCAConsts`):

```pascal
TLeakSeverity     = (lsError, lsWarning, lsHint);
TFindingConfidence= (fcLow, fcMedium, fcHigh);
TFindingType      = (ftBug, ftCodeSmell, ftVulnerability,
                     ftSecurityHotspot, ftCodeDuplication, ftFileError);
```

### 3.8 Quellstellen: `TSourcePlaces` (`uSourcePlaces`)

Beschreibt Stellen einer Quelldatei **auf Anfrage** — für Konsumenten, die Code umschreiben wollen (z. B. das Modul „Source Refactor" reDelphix). Der Dienst liest nur: kein Scan läuft, kein Fund, Feld oder Export wird berührt, und kein Detektor benutzt ihn. Eine Instanz je Datei.

`uEngineApi` exportiert die Typen `TSourcePlaces`, `TNodeRef`, `TSourceLineRange`, `TUsesSection`, `TNodeKind`, `TNodeKinds`, `TRefactorInfo`, `TRefactorSpan` weiter; die Werte der weitergereichten Enums gehen qualifiziert über den Alias (`TNodeKind.nkAssign`, `TUsesSection.usImplementation`). **Nicht** weiter exportiert werden die Konstanten und die übrigen Enums: die Rollen (`ROLE_*`), Werttypen (`rv*`, `TRefactorValueType`) und Flags (`rf*`, `TRefactorFlags`) brauchen `uses uRefactorInfo`, die Vertragsversion `SOURCE_PLACES_VERSION` braucht `uses uSourcePlaces`. Beide Units liegen im Package.

```pascal
Places := TSourcePlaces.Create;
try
  try
    Opened := Places.Open(FileName);    // False: Datei nicht lesbar
  except
    on EStackExhausted do raise;        // uCrashDiag: nie verschlucken - nach einem Ueberlauf fehlt die Schutzseite
    on EAbort do raise;                 // ein stiller Abbruch gehoert dem Host
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
| `Open(FileName)` / `Close` | `Boolean` | Liest die Datei selbst (kein Scan-Cache, kein Engine-Lock) und parst genau den dekodierten Text. `False`, wenn nicht lesbar. Ein Parser-Fehler (auch der Watchdog des Parsers) **wirft**; beim Fangen `EStackExhausted` (`uCrashDiag`) und `EAbort` nie verschlucken; danach ist der Dienst geschlossen (`IsOpen = False`). Ein vorher geöffneter Text wird zuerst verworfen. |
| `OpenSource(FileName, Source)` | `Boolean` | Wie `Open`, aber auf einem Text, den der Host übergibt (IDE: der Editor-Puffer mit ungespeicherten Änderungen). `FileName` ist nur der Name; die Datei wird nicht gelesen. `False` bei leerem Text; ein Parser-Fehler wirft wie bei `Open`. |
| `SetIfdefDefines(Defines)` | | Lexer-Sicht des nächsten `Open`/`OpenSource`. Der Dienst parst immer in seiner eigenen Sicht, nie in der prozessweiten, die ein laufender Scan aus `TScanRequest.IfdefDefines` setzt. `nil` oder leer (Vorgabe) = beide Zweige jedes `{$IFDEF}`; sonst ein Zweig mit genau diesen Defines — ein Konsument, der die Sicht des Laufs kennt (`TScanRequest.IfdefDefines`), bekommt Knoten und Typen dann aus derselben Sicht wie die Funde. Ausnahme: bei einem `dlFpc`-Lauf mit nicht leerer Define-Liste (erzwungen auch für `.lpi`/`.lpk`/`.lpg`-Projekte) ergänzt der Scan `FPC` und `LCL` (`TAnalysisSession.ApplyIfdefView`), der Dienst nicht — für die Sicht der Funde gibt der Aufrufer die beiden selbst mit. Die Werte werden kopiert und bleiben über `Close` hinweg gesetzt. Grenzen der Doppelzweig-Sicht: `DeclaredTypeOf` liefert `''` für einen Namen, den die Zweige mit verschiedenen Typen deklarieren, und `NodesAt` kann Knoten beider Zweige liefern. Defines aus Include-Dateien wertet der Dienst nicht aus. |
| `IsOpen` / `FileName` / `LineCount` | `Boolean` / `string` / `Integer` | Zustand des geöffneten Texts. |
| `StatementAt(Line, Col)` | `TRefactorInfo` | Die dort beginnende Anweisung: Bereich mit Spalten, Flags, Einfügepunkt, Hash. `nil`, wenn ihr Ende nicht bestimmbar ist, auch wenn ein Delphi-12-Mehrzeilenstring (`'''`) darin steht. |
| `ChainOf(Line, Col, ExpectedTarget = '', ExpectedPlus = ANY_PLUS_COUNT)` | `TRefactorInfo` | Zuweisung mit `+`-Kette: Ziel, Literale, Operanden, `FixSafe`. Zwei Gegenproben, jede liefert bei Abweichung `nil`: das Ziel gegen `ExpectedTarget` (`TNodeRef.Name`; `''` = keine Prüfung) und die Zahl der `+` auf oberster Ebene gegen `ExpectedPlus`, vom Konsumenten unabhängig gezählt (etwa aus `TNodeRef.TypeRef`, so wie SCA044 zählt). Jeder negative Wert (`TSourcePlaces.ANY_PLUS_COUNT`) heißt: keine Prüfung. |
| `CallOf(Line, Col, ExpectedHead)` | `TRefactorInfo` | Aufruf-Anweisung: Kopf plus Kette des einen Arguments, sonst je Argument ein `argument`-Teil. `ExpectedHead` ist der Kopf vor der ersten `(` (`''` = keine Prüfung). |
| `NodesAt(Line, Kinds)` | `TArray<TNodeRef>` | AST-Knoten der Arten, die auf der Zeile beginnen, nach Spalte sortiert. Zwei Treffer heißen: mehrdeutig. |
| `UsesEntries(Section)` | `TArray<TRefactorSpan>` | Jeder Unit-Name der `uses`-Klauseln mit Bereich (`Resolved` = Name wie geschrieben). `usAny` (Vorgabe) umfasst auch die Klausel eines Programms oder einer Library. |
| `IdentifiersIn(Span)` | `TArray<TRefactorSpan>` | Bezeichner in einem Bereich als `ident`-Teile; Schlüsselwörter werden nicht gefiltert. Strings und Kommentare sind ausgeblendet — auch wenn der Bereich mitten in einem beginnt, denn die Datei wird bis zum Bereich mitgelesen. Grenze: einen Delphi-12-Mehrzeilenstring (`'''`) vor dem Bereich erkennt das nicht. |
| `CodeViewOf` / `TextOf` / `HashOf` | | Spaltentreue Code-Sicht, Rohtext und SHA-256 eines Bereichs, alle auf dem Text des letzten `Open`/`OpenSource`. In der Code-Sicht sind Strings mit `~` gefüllt (`TRefactorInfoBuilder.VIEW_FILL`), Kommentare und Compiler-Direktiven samt Begrenzern dagegen Leerzeichen. `HashOf` sieht keine spätere Änderung: um eine zu erkennen, den aktuellen Text neu öffnen und `HashOf(Info.Span)` mit `Info.SpanHash` vergleichen, oder direkt vor dem Schreiben `TextOf(Span)` mit dem Zielpuffer vergleichen (so macht es reDelphix). |
| `ConditionalRanges` | `TArray<TSourceLineRange>` | Bedingte Bereiche der Datei in Quelltext-Reihenfolge: ein Bereich je Zweig (`{$IFDEF}`..`{$ELSE}`, `{$ELSE}`..`{$ENDIF}`), für jede bedingte Direktive (`$IF`, `$IFDEF`, `$IFNDEF`, `$IFOPT`). |
| `SectionLine(Section)` | `Integer` | Zeile des Schlüsselworts `interface` / `implementation`; `0`, wenn der Abschnitt fehlt (Programm, Library), und für `usAny`. |
| `LineText(Line)` | `string` | Text einer Zeile des geöffneten Texts; `''` außerhalb. |
| `SpanHasComment(Span)` | `Boolean` | `True`, wenn im Bereich ein Kommentar oder eine Compiler-Direktive steht — für einen Konsumenten, der nur einen Teil einer Anweisung ersetzt (`rfHasComment` gilt für die ganze Anweisung). |
| `DeclaredTypeOf(Line, Name)` | `string` | Deklarierter Typ (nackt, klein geschrieben) eines Bezeichners, als **Beweis**: Parameter, lokale Variable oder lokale typisierte Konstante der umschließenden Routine, sonst Feld der Klasse aus dem Methodennamen (`TFoo.Bar`) und ihrer Vorfahren in dieser Unit, sonst Unit-Global; `''`, wenn unbekannt oder nicht bewiesen - ein Vorfahr von außerhalb der Unit (er kann jeden Namen verdecken), ein Klassen- oder Record-Helper, eine Methode eines verschachtelten Typs, eine Property oder Methode gleichen Namens, verschiedene Typen für denselben Namen (`{$IFDEF}`-Zweige), eine Zeile in einer verschachtelten Routine. Bekannte Grenze: eine untypisierte Klassenkonstante (`const Max = 10;` im Klassenrumpf) hat keinen Knoten, ein gleichnamiges Unit-Global gilt dann als bewiesen. Der Typ-Resolver der Detektoren behält seine gröbere Fallback-Ebene. `string[N]` ergibt `'shortstring'`, nicht `'string'` (der Typ-Resolver der Detektoren bleibt bei `'string'`). `Line` ist die **Ankerzeile** einer Anweisung (Zeile eines AST-Knotens), keine Fortsetzungszeile. Kennt keine `with`-Blöcke: liefert die gefundene Deklaration auch dort, wo der Compiler den Namen an ein Member des `with`-Ausdrucks bindet. |
| `InWithBlock(Line)` | `Boolean` | `True`, wenn die Zeile im Rumpf einer `with`-Anweisung liegt (zeilengenau, von der `with`-Zeile bis zur letzten Knoten-Zeile ihrer Anweisung). Das fragen, bevor man aus `DeclaredTypeOf` etwas beweist. |
| `CollectNodesAt` / `CollectUsesEntries` / `CollectIdentifiers` | | Klassenfunktionen: dasselbe auf einem Baum, einer Zeilenliste oder einer Code-Sicht, die der Aufrufer schon hat — für Tests und Konsumenten mit eigenem AST. |

**`TNodeRef`** kopiert die Knotenfelder, die ein Konsument braucht: `Kind`, `Line`, `Col`, `Name` (Ziel bzw. Kopf, wie der Parser ihn zusammengefügt hat) und `TypeRef` (rechte Seite bzw. Typbezug, abgeflacht). Der Baum selbst gehört dem Dienst und lebt nur bis zum nächsten `Open`/`Close`.

**Was `ChainOf` und `CallOf` beweisen.** Ein Operand, der ein bloßer Bezeichner ist, bekommt seinen deklarierten Typ (`rvString`/`rvNonString`, `Resolved` = Typname), und `FixSafe` wird neu abgeleitet. Ein Operand vom Typ `Char`, `WideChar`, `AnsiChar`, `ShortString` oder `PAnsiChar` bleibt `rvString` (Format nimmt ihn für `%s`), aber nicht verlustfrei - ein `#0` beendet den Text, ein `AnsiChar` ab `#$80` geht als Ordinalwert durch -, er macht also nie `FixSafe`. Unbekannt bleibt unbekannt: `rvUnknown` und `FixSafe = False` sind der Normalfall. Keinen `rvString`-Beweis gibt es in einem `with`-Block (`InWithBlock`; `Resolved` nennt weiter die gefundene Deklaration) und keinen für einen bekannten RTL-Aufruf oder einen `.ToString`-Term, dessen Namen eine Funktion der Unit selbst mit einem Nicht-String-Ergebnis deklariert — sie verdeckt die RTL-Routine (z. B. ein unit-lokales `function Trim(..): Variant`). Mit `SysUtils.`/`StrUtils.` qualifizierte Aufrufe behalten ihren Beweis. Eine Funktion in einer verschachtelten Routine sieht der Dienst nicht (der Parser verwirft verschachtelte Routinen).

Koordinaten sind 1-basiert; `EndCol` zeigt **hinter** das letzte Zeichen. Jedes Primitiv außer `Open`/`OpenSource` ist total (`nil`, leer, `0` oder `False` statt Exception, auch wenn nichts geöffnet ist). `SOURCE_PLACES_VERSION` (= 1) ist die Vertragsversion — eine **Übersetzungszeit**-Konstante: ein Konsument prüft sie mit `{$IF SOURCE_PLACES_VERSION <> 1}{$MESSAGE ERROR '...'}{$IFEND}` (reDelphix tut das in `uRdxRecipeRunner`, `uRdxPlacesRunner` und `uRdxFixRunner`) und baut dann gegen einen geänderten Vertrag nicht mehr. Eine zur Laufzeit getauschte BPL erkennt sie nicht; das leistet die Paketbindung (DCP/`requires`). Die Version steigt bei einer Änderung an der Signatur eines bestehenden Primitivs, an Rollen, an Koordinaten oder an einer Ableitung von `FixSafe`/`ValueType`/`Resolved`, die etwas neu als bewiesen meldet; sie bleibt bei neuen Primitiven, neuen Parametern mit Vorgabewert und Ableitungen, die nur strenger werden.

Je Regel kann `rules/sca-rules.json` `anchor` (worauf die Funde ankern: `statement`, `assign`, `call`, `assign-or-call`; `uses-item` ist reserviert) und `fixMode` (`none` / `assisted` / `auto`) tragen; gelesen über `TRuleCatalog` (`TRuleMeta.Anchor`, `TRuleMeta.FixMode`). Ein fehlender oder unbekannter Wert fällt auf den einkompilierten Katalog zurück; abgeschaltet wird eine Regel mit `"fixMode": "none"` - dann bietet ein Modul auf ihrem Signal gar keine Schreibhilfe an. `assisted` = nur Vorlage oder Vorschau, nie geschrieben; `auto` = darf schreiben. Ohne Wert bieten die Rezepte auf der Anweisung (Format()/SQL) nichts an, zeilenbasierte Hilfen eines Moduls entscheiden selbst. `editorHelp` (Boolean) sagt, ob ein IDE-Modul für die Regel einen Quick-Fix hat (eine Code-Aktion zu ihren Funden; reDelphix: Glühbirne, Strg+Alt+F); Berichte lesen es für das QF-Badge und den Filter „Quick-Wins“ im HTML (`TRuleMeta.EditorHelp`, ein fehlender Wert fällt auf den einkompilierten Katalog zurück).

### 3.9 Klassenmethoden der Session: Engine-Lock und Caches

| Aufruf | Zweck |
|--------|-------|
| `TAnalysisSession.AcquireEngineLock` / `ReleaseEngineLock` | Prozessweiter Engine-Lock für Consumer, die den globalen Detektor-State selbst ändern (z. B. vor einem `SkipConfig`-Lauf). Rekursiv: ein Halter, der danach `Run` ruft, betritt ihn erneut. Nie über `Synchronize`/`ProcessMessages` hinweg halten. |
| `TAnalysisSession.TryAcquireEngineLock: Boolean` | Nicht blockierende Probe für Aufrufer im UI-Thread, die bei laufendem Scan überspringen statt einfrieren. `True` = Lock gehalten; der Aufrufer **muss** `ReleaseEngineLock` rufen. |
| `TAnalysisSession.ReleaseTransientCaches` | Gibt die transienten Engine-Caches frei (heute: der prozessweite Datei-Text-Cache). Der Consumer ruft das an seinem letzten Punkt (nach Anzeige, Reports oder Export). Zu früh kostet nur einen Warmstart, nie Korrektheit; nicht während eines laufenden Scans rufen. |

### 3.10 Testfixtures: `TFixtureFilter`

Die Regel, Funde in Testfixture-Pfaden auszublenden, gehört der Engine; `Run`
wendet sie **nicht** an — das entscheidet der Consumer (heute nur der CLI).

| Aufruf | Zweck |
|--------|-------|
| `TFixtureFilter.AutoHidesFixtures(AProfile): Boolean` | Ob ein Profil Fixture-Funde von sich aus ausblendet: `default` und `selftest-quiet` ja, `strict` und jedes andere Profil nein. |
| `TFixtureFilter.Apply(AFindings, ABaseDir, ADroppedFiles = nil): Integer` | Entfernt Fixture-Funde aus der Liste und liefert ihre Anzahl. `ABaseDir` (die Scan-Wurzel) verankert die Pfadmuster; `fkFileReadError` bleibt immer stehen; `ADroppedFiles` sammelt optional die betroffenen Dateinamen. |

---

## 4. Lebenszyklus / Threading

- Die Engine ist **nicht thread-safe** (geteilter globaler Konfig-/Cache-State).
  Pro Prozess einen Scan zur Zeit; `Run` nimmt den Engine-Lock (s. 3.9).
  `Parallel` parallelisiert die Dateien *innerhalb* eines Scans.
- Der **rekursive Scan** ist für kurzlebige Ein-Scan-Prozesse (CLI/Demo) sicher.
  In residenten Hosts (IDE) den Single-File-/Source-Pfad bevorzugen.
- `TScanResult` besitzt die Findings; `Free` gibt sie frei. Mit
  `ReleaseFindings` geht die Ownership an den Aufrufer über.

---

## 5. Das Package referenzieren (Consumer-Setup)

Ein Fremd-Consumer braucht **nur das Package**, keine Engine-Quelltexte:

- `.dproj`: `UsePackages=true` und `DCC_UsePackage` enthält `SCA.Engine;rtl`.
- **Kein** Engine-Source-Verzeichnis im `DCC_UnitSearchPath`.
- Zur Laufzeit müssen `SCA.Engine290.bpl` (Delphi 12; `{$LIBSUFFIX AUTO}`) und
  die Delphi-Laufzeitpakete, die es verlangt (`rtl`, `xmlrtl`), auffindbar sein
  (globales BPL-Verzeichnis oder neben der `.exe`).
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
