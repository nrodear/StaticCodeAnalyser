# How-To: Einen neuen Detektor allumfassend einbauen

Schritt-für-Schritt-Anleitung mit Checkliste. Wenn **alle** Punkte abgehakt sind, ist der Detektor in Standalone-App + IDE-Plugin + Tests + Regelkatalog + UI-Lokalisierung integriert.

## Checkliste (in dieser Reihenfolge abarbeiten)

```
Detector-Code
[ ]  1. uXxx.pas erstellen (StaticCodeAnalyserForm/sources/Detectors/)
[ ]  2. TFindingKind fkXxx in uSCAConsts.pas zum Enum hinzufuegen
[ ]  3. KIND_META-Eintrag in uSCAConsts.pas (gleiche Reihenfolge wie Enum!)
[ ]  4. (optional) IsSonarDelphiKind erweitern falls SonarDelphi-Import
Regel-Katalog
[ ]  5. rules/sca-rules.json: Rule-Eintrag mit SCA-ID + Metadaten
[ ]  6. (optional) profiles-Block in sca-rules.json wenn das Kind in
        einem Profil sein soll
Hint / Help (Before/After)
[ ]  7. uFixHint.pas: case-Branch fuer fkXxx mit Description/Before/After
Lokalisierung
[ ]  8. i18n/de.po: msgid/msgstr fuer alle neuen _()-Strings
[ ]  9. i18n/en.po: msgid/msgstr (msgstr = msgid bei englischer Quelle)
Scan-Engine
[ ] 10. uStaticAnalyzer2.BuildAllDetectors: AddD(...) fuer den Detektor
Tests
[ ] 11. uTestXxx.pas in tests/ anlegen (DUnitX-TestFixture)
[ ] 12. uTestFindingHelper: Detektor in FindingsOf ODER FindingsOfFile
        registrieren (AST-only vs File-scannend)
[ ] 13. TestProject.dpr: uTestXxx in uses-Klausel
[ ] 14. TestProject.dproj: <DCCReference> fuer uTestXxx.pas
Projekt-Dateien (3 Stueck!)
[ ] 15. StaticCodeAnalyser.d12.dpr: uXxx in uses
[ ] 16. StaticCodeAnalyser.d12.dproj: <DCCReference> fuer uXxx.pas
[ ] 17. StaticCodeAnalyser.IDE.d12.dpk: uXxx in contains
[ ] 18. StaticCodeAnalyser.IDE.d12.dproj: <DCCReference> fuer uXxx.pas
Combobox-Listen (nur falls neuer eigenstaendiger Filter-Eintrag gewuenscht)
[ ] 19. uMainForm.FormCreate: SeverityFilterCombo.Items.AddObject(...)
[ ] 20. uIDEAnalyserForm: FFilterCombo.Items.AddObject(...) via Helper
[ ] 21. uFindingFilter: TFilterMode/TTypeFilter Enum erweitern + Matches
        anpassen
Konsistenz-Test
[ ] 22. IDE bauen + alle Tests laufen lassen
[ ] 23. uTestRuleCatalog-Konsistenztest gruen (jeder fkXxx hat einen
        sca-rules.json-Eintrag inkl. MQR-Mapping)
```

---

## 1. Detector-Unit

Konvention: `StaticCodeAnalyserForm/sources/Detectors/uXxx.pas`. Zwei Skelett-Varianten je nachdem, ob du am AST oder am File-Inhalt arbeitest.

### Variante A — AST-basiert (bevorzugt)

```pascal
unit uXxx;

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TXxxDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

class procedure TXxxDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Calls : TList<TAstNode>;
  N     : TAstNode;
  F     : TLeakFinding;
begin
  Calls := UnitNode.FindAll(nkCall);
  try
    for N in Calls do
    begin
      // ... deine Bedingung
      if not Bedingung(N) then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';  // ggf. Method-Owner ermitteln
      F.LineNumber := IntToStr(N.Line);
      F.MissingVar := 'Beschreibung des konkreten Treffers';
      F.SetKind(fkXxx);     // setzt automatisch Severity aus KIND_META
      Results.Add(F);
    end;
  finally
    Calls.Free;
  end;
end;

end.
```

### Variante B — File-scannend (wenn AST nicht reicht)

Nutzt `AcquireLines`/`ReleaseLines` aus `uFileTextCache` und ideal die zentralen Helfer aus `uDetectorUtils` (`ScanCodeLine`, `StripStringsAndComments`, `MergeAdjacentStringLiterals`).

```pascal
implementation

uses
  uFileTextCache, uDetectorUtils;

class procedure TXxxDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines : TStringList;
  i     : Integer;
  Cached: Boolean;
  State : TCommentScanState;
  Code  : string;
  Col   : Integer;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    State := Default(TCommentScanState);
    for i := 0 to Lines.Count - 1 do
    begin
      // Strings + Kommentare gestrippt, Block-Comment-State traegt sich.
      Code := TDetectorUtils.ScanCodeLine(Lines[i], State, Col);
      // ... deine Pattern-Suche in Code
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;
```

## 2-3. TFindingKind + KIND_META

**Beide MUESSEN in derselben Reihenfolge sein.** `KindFromName` macht Reverse-Lookup über Index, der nicht-ausgerichtete Eintraege erkennt der Konsistenz-Test in `uTestRuleCatalog`.

In [uSCAConsts.pas](StaticCodeAnalyserForm/sources/Common/uSCAConsts.pas):

```pascal
// Im TFindingKind-Enum (Reihenfolge merken!):
fkXxx,    // SCAxxx, kurzer Kommentar

// Im KIND_META-Array (an der GLEICHEN Position):
(Name: 'Xxx'; FindingType: ftBug; DefaultSeverity: lsWarning),
```

Die `Name`-Strings sind die User-sichtbaren Namen + werden für `// noinspection Xxx`-Suppression genutzt.

## 4. SonarDelphi-Mapping (optional)

Falls der Detektor einen SonarDelphi-Pendant hat, [uSCAConsts.pas:819 `IsSonarDelphiKind`](StaticCodeAnalyserForm/sources/Common/uSCAConsts.pas#L819) erweitern. Sonst überspringen — neue Eigen-Detektoren sind kein SonarDelphi.

## 5-6. rules/sca-rules.json

Datei: [rules/sca-rules.json](rules/sca-rules.json). Schema-Pflichtfelder pro Regel:

```json
{
  "id": "SCAxxx",
  "kind": "Xxx",
  "name": "Object created without try/finally",
  "shortDescription": "Ein-Satz-Erklaerung",
  "fullDescription": "Mehrzeilige Markdown-Erklaerung mit Beispielen.",
  "defaultSeverity": "warning",
  "type": "bug",
  "configKey": "...",
  "detectorUnit": "uXxx",
  "tags": ["leak", "memory"],
  "cleanCodeAttribute": "LOGICAL",
  "impacts": [
    { "softwareQuality": "Reliability", "severity": "high" }
  ],
  "examples": {
    "bad":  "// Pascal-Snippet (Anti-Pattern)",
    "good": "// Pascal-Snippet (Fix)"
  }
}
```

**MQR-Mapping (`cleanCodeAttribute` + `impacts`) ist Pflicht** — der Konsistenz-Test `EveryFindingKindHasMqrMapping` in `uTestRuleCatalog` schreit sonst.

Wenn das Kind in einem **Profil** (z.B. `ide-fast`, `bugs-only`) erscheinen soll, am Datei-Ende den `profiles`-Block ergänzen.

## 7. uFixHint — Before/After-Code-Beispiele

[uFixHint.pas:37 ff.](StaticCodeAnalyserForm/sources/Output/uFixHint.pas#L37): ein `case` über `Finding.Kind`. Neuer Branch:

```pascal
fkXxx:
begin
  Result.Description := _('Kurze Problem-Beschreibung (lokalisiert)');
  Result.Before :=
    'list := TStringList.Create;'#13#10 +
    'list.Add(''entry'');'#13#10 +
    '// list.Free is missing!';
  Result.After :=
    'list := TStringList.Create;'#13#10 +
    'try'#13#10 +
    '  list.Add(''entry'');'#13#10 +
    'finally'#13#10 +
    '  FreeAndNil(list);'#13#10 +
    'end;';
end;
```

**Konvention:** `Description` ist lokalisiert (`_()`), `Before`/`After` bleiben **englisch** (Claude-AI-Prompts und Jira-Tickets sind englisch).

## 8-9. i18n .po-Dateien

Jeder neue `_('...')`-String braucht einen Eintrag in **beiden** Dateien:

[i18n/de.po](i18n/de.po):
```po
msgid "Kurze Problem-Beschreibung"
msgstr "Kurze Problem-Beschreibung (deutsche Uebersetzung)"
```

[i18n/en.po](i18n/en.po):
```po
msgid "Kurze Problem-Beschreibung"
msgstr "Kurze Problem-Beschreibung"
```

> Die `msgid` ist der Source-String aus dem Pascal-Code. `msgstr` ist die Übersetzung. Beide Dateien müssen die gleichen `msgid`s enthalten.

## 10. Scan-Engine — `BuildAllDetectors`

[uStaticAnalyzer2.pas:173 ff.](StaticCodeAnalyserForm/sources/Infrastructure/uStaticAnalyzer2.pas#L173). Eine Zeile pro Detektor:

```pascal
AddD('Xxx', fkXxx,
  procedure(R: TAstNode; const F: string; L: TObjectList<TLeakFinding>)
  begin TXxxDetector.AnalyzeUnit(R, F, L); end);
```

Stelle: am Ende der Add-Kette in `BuildAllDetectors`. Wenn `DETECTOR_CAPACITY` überschritten wird, wirft die Methode eine Exception mit Hinweis — Konstante erhöhen.

## 11-14. Tests

### Test-Unit `uTestXxx.pas`

```pascal
unit uTestXxx;
interface
uses DUnitX.TestFramework;
type
  [TestFixture]
  TTestXxx = class
  public
    [Test] procedure Xxx_PositiveCase_Reported;
    [Test] procedure Xxx_NegativeCase_NoFinding;
  end;

implementation
uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestXxx.Xxx_PositiveCase_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; begin ... end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);  // oder FindingsOfFile
  try Assert.IsTrue(TFindingHelper.Count(F, fkXxx) >= 1);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestXxx);
end.
```

### uTestFindingHelper-Pipeline

[uTestFindingHelper.pas](StaticCodeAnalyserForm/tests/uTestFindingHelper.pas):
- **`FindingsOf`** (AST-only): wenn der Detektor `nur` `UnitNode` braucht und nicht selbst die Datei liest.
- **`FindingsOfFile`** (schreibt SRC als Tempfile): wenn der Detektor `AcquireLines` oder anderes File-IO macht.

Eine Zeile in der passenden Methode:
```pascal
TXxxDetector.AnalyzeUnit(Root, 'test.pas', Result);          // FindingsOf
TXxxDetector.AnalyzeUnit(Root, TempPath, Result);            // FindingsOfFile
```

### TestProject.dpr + .dproj

`TestProject.dpr` uses-Klausel:
```pascal
uTestXxx in 'uTestXxx.pas',
```

`TestProject.dproj` ItemGroup:
```xml
<DCCReference Include="uTestXxx.pas"/>
```

## 15-18. Projekt-Dateien (drei Projekte!)

Beide Apps brauchen **sowohl** den `.dpr`/`.dpk`-uses-Eintrag **als auch** die `.dproj`-`<DCCReference>`. Sonst greift entweder die IDE oder MSBuild ins Leere.

### Standalone-App

[StaticCodeAnalyser.d12.dpr](StaticCodeAnalyserForm/StaticCodeAnalyser.d12.dpr):
```pascal
uXxx in 'sources\Detectors\uXxx.pas',
```

[StaticCodeAnalyser.d12.dproj](StaticCodeAnalyserForm/StaticCodeAnalyser.d12.dproj):
```xml
<DCCReference Include="sources\Detectors\uXxx.pas"/>
```

### IDE-Plugin

[StaticCodeAnalyser.IDE.d12.dpk](StaticCodeAnalyserIDE/StaticCodeAnalyser.IDE.d12.dpk):
```pascal
uXxx in '..\StaticCodeAnalyserForm\sources\Detectors\uXxx.pas',
```

[StaticCodeAnalyser.IDE.d12.dproj](StaticCodeAnalyserIDE/StaticCodeAnalyser.IDE.d12.dproj):
```xml
<DCCReference Include="..\StaticCodeAnalyserForm\sources\Detectors\uXxx.pas"/>
```

## 19-21. Combobox-Listen (nur wenn neuer Filter-Eintrag)

Ein NEUER `fkXxx` ist standardmäßig **schon filterbar** über die Severity-Filter (Errors/Warnings/Hints) und Type-Filter (Bug/Code Smell/...) — dafür ist nichts zu tun.

Eine **dedizierte Combo-Zeile** (z.B. „Memory Leaks (all)") nur bei Bedarf:

### Standalone
[uMainForm.pas:254 ff.](StaticCodeAnalyserForm/sources/UI/uMainForm.pas#L254):
```pascal
SeverityFilterCombo.Items.AddObject(_('Xxx (all)'), TObject(Ord(fmXxx)));
```

### IDE-Plugin
[uIDEAnalyserForm.pas:1000](StaticCodeAnalyserIDE/uIDEAnalyserForm.pas#L1000) via dem `AddFilter`-Helper.

### uFindingFilter
Wenn neuer eigener Filter-Eintrag: TFilterMode-Enum (`fmXxx`) ergänzen + `TFindingFilter.Matches` um den Case erweitern.

## 22-23. Bauen + Konsistenz-Tests

In der IDE bauen (Standalone-App + IDE-Plugin + TestProject). Dann:

| Test | Was wird geprüft |
|------|-----------------|
| `TTestXxx` | Detektor selbst (positive + negative Cases) |
| `TTestRuleCatalog.EveryFindingKindHasCatalogEntry` | jedes `fkXxx` hat einen JSON-Eintrag |
| `TTestRuleCatalog.EveryFindingKindHasMqrMapping` | jedes `fkXxx` hat `cleanCodeAttribute` + `impacts` |
| `TTestSuppressionCompleteness` | jedes `fkXxx` ist über `// noinspection Xxx` suppressbar |
| `TTestRuleCatalog.ProfileNamesIncludesBundled` | Profile-Liste konsistent |

Alle vier müssen grün sein, sonst fehlt irgendwo in den Punkten 2/3/5/8.

---

## Häufige Stolpersteine

| Symptom | Wahrscheinliche Ursache |
|---------|------------------------|
| `E2065 Identifier redeclared: 'uXxx'` | Unit in interface- UND impl-uses gelistet (siehe [feedback_delphi_pitfalls.md](.claude-memory/feedback_delphi_pitfalls.md)) |
| `F2613 Unit '...' not found` beim Standalone-Build | `.dpr`-uses-Eintrag (Punkt 15) vergessen |
| IDE-Plugin lädt nicht, ohne Fehlermeldung | `.dpk` `contains` (Punkt 17) vergessen |
| Test sieht das Finding nie | `uTestFindingHelper`-Eintrag (Punkt 12) vergessen — Detektor läuft im Test gar nicht |
| Konsistenz-Test rot („MqrMapping missing") | `cleanCodeAttribute` oder `impacts` in `sca-rules.json` vergessen |
| Finding zeigt `Severity = lsHint` statt erwartetem `lsError` | `SetKind` ohne Default-Severity-Override → Wert kommt aus `KIND_META.DefaultSeverity` → Punkt 3 prüfen |
| `// noinspection Xxx` greift nicht | Punkt 3: `KIND_META.Name` muss exakt `'Xxx'` sein (case-insensitive) |
| String erscheint englisch trotz DE-UI | `_('...')`-String fehlt in `de.po` |
| Anonyme Methode in `OnDrawCell` heap-storm | nicht relevant für Detektoren — Detektoren laufen 1× pro File |

## Minimal-Diff-Beispiel zum Vergleich

Der jüngste „SqlDangerousStatement"-Touch ([Commit 8359413](https://github.com/nrodear/StaticCodeAnalyser/commit/8359413)) hat **nichts** an Punkten 2/3/5/8/10/15-18 geändert — Detektor existierte schon. Eine wirkliche Neueinführung (z.B. `fkSelfAssignment`) bewegt sich über alle 23 Punkte.

## TL;DR

> Detector ist nicht nur die `uXxx.pas`. Ohne die Registrierung in **drei Projektdateien-Paaren** (Standalone/IDE/Tests), KIND_META + Rules-JSON + uFixHint + i18n + BuildAllDetectors + TFindingHelper läuft er in der Praxis entweder nicht, ist nicht filterbar, hat keinen Hint, ist nicht übersetzt oder nicht suppressbar. Die Checkliste am Anfang ist die Pflichtliste.
