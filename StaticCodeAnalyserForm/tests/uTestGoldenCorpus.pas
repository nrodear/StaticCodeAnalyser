unit uTestGoldenCorpus;

// GOLDEN-CORPUS-REGRESSIONSTEST (Todo_FalsePositiveReduction #2)
// ---------------------------------------------------------------------------
// Zweck: die grossen, ueber die FP-Reduktions-Serie abgebauten FP-Klassen
// dauerhaft gegen Regression sichern - auf KORPUS-Ebene, nicht nur per
// Einzel-Snippet. Anlass: der Parser-Outer-Body-Fix (2026-06-25) legte die
// SCA148-bare-Member-FP-Klasse offen; eine spaetere Aenderung koennte solche
// FPs unbemerkt im Aggregat zurueckbringen. Kleine Unit-Tests fangen das
// einzeln, aber nicht die Wechselwirkung mehrerer Muster in einer realen Datei.
//
// Jeder Fall ist eine REALISTISCHE, groessere Unit, die mehrere Muster
// kombiniert, mit Per-Kind-Erwartungswerten. Bidirektional:
//   * Negative Faelle (FP-Schutz): erwartet 0 fuer die gefixte Regel.
//   * Positive Kontrolle (FN-Schutz): erwartet >=1 fuer echte Bugs, damit die
//     Suppression-Logik nicht ueber-suppress.
//
// WICHTIG (Helper-Wahl): die Test-Harness hat zwei Detektor-Buendel:
//   FindingsOf      -> AST-Detektoren inkl. SCA148/SCA121 (NICHT SCA166)
//   FindingsOfFile  -> source-line-Detektoren inkl. SCA166 (NICHT SCA148/121)
// Daher pro Finding-Kind den passenden Helper nutzen (CountCurated/CountFile).
//
// Erweiterung: Jeder kuenftige FP-Fix sollte hier einen realistischen Fall
// ergaenzen (nicht nur einen Snippet-Unit-Test).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestGoldenCorpus = class
  public
    // --- FP-Schutz (gefixte Klassen) ---
    [Test] procedure CanBeClassMethod_InstanceAccess_NoneFlagged;
    [Test] procedure NestedRoutines_OuterStateRecovered_NoUninitNoResult;
    // --- SCA144 (FloatEquality) Regressions-Anker 2026-07-25/26 ---
    [Test] procedure NestedDoubleShadowsOuter_FloatEqualityStillDetected;
    [Test] procedure SentinelRhsParameterlessNestedFunc_NotDemoted;
    // --- SCA009 (MissingFinally) Regressions-Anker 2026-07-25 ---
    [Test] procedure WithFreeIdiom_NoMissingFinally;
    // --- FN-Schutz (echte Bugs muessen weiter gefunden werden) ---
    [Test] procedure RealBugs_StillDetected;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

// SCA148 / SCA121 leben im FindingsOf-Buendel (AST-Detektoren).
function CountCurated(const SRC: string; K: TFindingKind): Integer;
var F: TObjectList<TLeakFinding>; Fnd: TLeakFinding;
begin
  Result := 0;
  F := TFindingHelper.FindingsOf(SRC);
  try
    for Fnd in F do if Fnd.Kind = K then Inc(Result);
  finally F.Free; end;
end;

// SCA166 lebt im FindingsOfFile-Buendel (source-line-Detektoren).
function CountFile(const SRC: string; K: TFindingKind): Integer;
var F: TObjectList<TLeakFinding>; Fnd: TLeakFinding;
begin
  Result := 0;
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do if Fnd.Kind = K then Inc(Result);
  finally F.Free; end;
end;

// ===========================================================================
// FP-Schutz: SCA148 CanBeClassMethod
// Klassen-Hierarchie, in der JEDE Methode Instanz-State beruehrt - ueber eigenes
// Feld (RHS-Blob), bare Sibling-Aufruf, geerbtes Feld und geerbte Methode.
// KEINE davon darf als class method geflaggt werden (deckt RHS-/Sibling-/
// Vererbungs-Suppression in einer Datei ab).
// ===========================================================================
procedure TTestGoldenCorpus.CanBeClassMethod_InstanceAccess_NoneFlagged;
const SRC =
  'unit golden_sca148;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TBase = class'#13#10 +
  '    FCache: TObject;'#13#10 +              // geerbtes Feld (F-Konvention)
  '    Lexer: TObject;'#13#10 +               // geerbtes Non-F-Feld
  '    procedure BaseHelper;'#13#10 +         // geerbte Methode
  '  end;'#13#10 +
  '  TWorker = class(TBase)'#13#10 +
  '    FList: TObject;'#13#10 +
  '    function ComputeWithOwnField(A, B: Integer): Integer;'#13#10 +
  '    procedure CallsInheritedMethod;'#13#10 +
  '    procedure UsesInheritedField;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TBase.BaseHelper;'#13#10 +
  'begin FCache.Free; end;'#13#10 +           // eigenes Feld
  'function TWorker.ComputeWithOwnField(A, B: Integer): Integer;'#13#10 +
  'begin Result := A + B + FList.GetHashCode; end;'#13#10 +  // eigenes Feld im RHS
  'procedure TWorker.CallsInheritedMethod;'#13#10 +
  'begin BaseHelper; end;'#13#10 +            // geerbte Sibling-Methode bare
  'procedure TWorker.UsesInheritedField;'#13#10 +
  'begin Lexer.Free; end;'#13#10 +            // geerbtes Feld bare
  'end.';
begin
  Assert.AreEqual<Integer>(0, CountCurated(SRC, fkCanBeClassMethod),
    'Alle Methoden beruehren Instanz-State (eigen/geerbt) - kein SCA148');
end;

// ===========================================================================
// FP-Schutz: Parser nested routine + SCA166 (uninit) + SCA121 (Result)
// ===========================================================================
procedure TTestGoldenCorpus.NestedRoutines_OuterStateRecovered_NoUninitNoResult;
const SRC =
  'unit golden_nested;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'function ProcessData(Count: Integer): Integer;'#13#10 +
  'var'#13#10 +
  '  Total: Integer;'#13#10 +
  '  procedure Accumulate;'#13#10 +
  '  var i: Integer;'#13#10 +
  '  begin'#13#10 +
  '    try'#13#10 +
  '      for i := 0 to Count - 1 do'#13#10 +
  '        Total := Total + i;'#13#10 +       // Outer Total + Param Count (im nested)
  '    finally'#13#10 +
  '      Total := Total + 1;'#13#10 +
  '    end;'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  Total := 0;'#13#10 +                     // Outer-Write VOR nested-Aufruf
  '  Accumulate;'#13#10 +
  '  Result := Total;'#13#10 +                // Outer Result-Assign
  'end;'#13#10 +
  'end.';
begin
  Assert.AreEqual<Integer>(0, CountFile(SRC, fkUninitVar),
    'Total wird im Outer-Body gesetzt; nested-proc-Read darf kein uninit ausloesen');
  Assert.AreEqual<Integer>(0, CountCurated(SRC, fkRoutineResultUnassigned),
    'Result wird im (recoverten) Outer-Body zugewiesen - kein Finding');
end;

// ===========================================================================
// FP-/FN-Schutz: SCA144 nearest-decl-Gate (Commit 9660ca8 "Welle 1b" +
// Scoping-Fix dwsUtils.pas:2776 in uFloatEquality.NearestDeclTypeLowBefore).
// Eine geschachtelte function mit Double-Parametern shadowt die aeusseren
// Parameter GLEICHEN Namens. uParser2 verwirft nested routines aus dem AST,
// daher entscheidet der SOURCE-basierte nearest-decl-Walk, welche Deklaration
// den Operanden-Typ liefert. Bricht der Walk (oder faellt auf die aeussere
// Decl zurueck), maskiert das Shadowing einen echten Float-TP:
//   * outer Variant / nested Double  (dws-Klasse VarCompareSafe/CompareDoubles)
//   * outer Integer  / nested Double  (Ordinal-Shadow-Variante)
// Beide nested 'a = b'-Vergleiche MUESSEN als FloatEquality gefunden werden -
// die naechstliegende Decl vor der Fundstelle ist jeweils Double.
// FloatEquality lebt im FindingsOfFile-Buendel -> CountFile.
// ===========================================================================
procedure TTestGoldenCorpus.NestedDoubleShadowsOuter_FloatEqualityStillDetected;
const SRC =
  'unit golden_sca144_shadow;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  // Fall 1: aeussere Variant-Params, nested Double-Params gleichen Namens.
  'function VarCompareSafe(const left: Variant; const right: Variant): Integer;'#13#10 +
  '  function CompareDoubles(const left: Double; const right: Double): Integer;'#13#10 +
  '  begin'#13#10 +
  '    if left = right then Exit(0);'#13#10 +      // nearest decl = Double -> TP
  '    Result := 1;'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  Result := CompareDoubles(0, 0);'#13#10 +
  'end;'#13#10 +
  // Fall 2: aeussere Integer-Params, nested Double-Params gleichen Namens.
  'function IntCompareSafe(const a: Integer; const b: Integer): Integer;'#13#10 +
  '  function CmpVals(const a: Double; const b: Double): Integer;'#13#10 +
  '  begin'#13#10 +
  '    if a = b then Exit(0);'#13#10 +            // nearest decl = Double -> TP
  '    Result := 1;'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  Result := CmpVals(0, 0);'#13#10 +
  'end;'#13#10 +
  'end.';
begin
  Assert.IsTrue(CountFile(SRC, fkFloatEquality) >= 2,
    'nested Double-Params shadowen aeussere Variant-/Integer-Params - beide ' +
    'Double-Vergleiche muessen ueber nearest-decl weiter gefunden werden');
end;

// ===========================================================================
// FP-Schutz: SCA144 Sentinel-Zero-DEMOTE (Commit jvcl JvgUtils.pas:1516 -
// uFloatEquality.SentinelZeroLocalDemote, bare-Ident-RHS-Nachweis). Eine
// parameterlose nested function als RHS ('Denominator := DigitsToValue;')
// ist textuell von einem Local-Read nicht zu unterscheiden, liefert aber
// einen BERECHNETEN Wert -> der Divisions-Guard 'Denominator <> 0' ist ein
// echter TP und darf NICHT auf fcLow demotet werden (sonst filtert der
// Auslieferungs-Default ihn weg). Confidence MUSS fcHigh bleiben.
// ===========================================================================
procedure TTestGoldenCorpus.SentinelRhsParameterlessNestedFunc_NotDemoted;
const SRC =
  'unit golden_sca144_sentinel;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'function Calc: Single;'#13#10 +
  '  function DigitsToValue: Single;'#13#10 +
  '  begin'#13#10 +
  '    Result := 3.7;'#13#10 +
  '  end;'#13#10 +
  '  function TestForMulDiv: Single;'#13#10 +
  '  var Denominator: Single;'#13#10 +
  '  begin'#13#10 +
  '    Denominator := DigitsToValue;'#13#10 +     // parameterloser Call, KEIN Local
  '    if Denominator <> 0 then'#13#10 +          // Divisions-Guard = TP
  '      Result := 1 / Denominator;'#13#10 +
  '  end;'#13#10 +
  'begin'#13#10 +
  '  Result := TestForMulDiv;'#13#10 +
  'end;'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFloatEquality) >= 1,
      'Divisions-Guard auf berechnetem Wert bleibt ein Fund');
    Hit := TFindingHelper.FirstOf(F, fkFloatEquality);
    Assert.AreEqual<TFindingConfidence>(fcHigh, Hit.Confidence,
      'parameterloser nested-Function-Call als RHS ist kein beweisbares Local ' +
      '-> KEIN Sentinel-Demote, volle Confidence bleibt');
  finally F.Free; end;
end;

// ===========================================================================
// FP-/FN-Schutz: SCA009 with-Free-Idiom (Commit 56eb854 "Inkrement A2" -
// uMissingFinally SearchFree-WFin-Stack + bare-Free-Source-Gate). Das
// klassische Dialog-Idiom 'with L do try..finally Free end' schuetzt das
// Objekt korrekt -> KEIN MissingFinally. Gegenprobe: 'with L do begin ..Free
// end' OHNE try schuetzt nicht und MUSS weiter gemeldet werden (keine
// Ueber-Suppression). MissingFinally hat Lines-abhaengige Source-Guards ->
// FindingsOfFile / CountFile (im In-Memory-Harness inert).
// ===========================================================================
procedure TTestGoldenCorpus.WithFreeIdiom_NoMissingFinally;
const SRC_OK =           // FP-Schutz: geschuetztes with-try-finally-Free
  'unit golden_sca009_withfree;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  with L do'#13#10 +
  '  try'#13#10 +
  '    Add(''x'');'#13#10 +
  '  finally'#13#10 +
  '    Free;'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'end.';
const SRC_TP =           // FN-Schutz: with-Body OHNE try -> ungeschuetzt
  'unit golden_sca009_notry;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Bar;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  with L do'#13#10 +
  '  begin'#13#10 +
  '    Add(''x'');'#13#10 +
  '    Free;'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'end.';
begin
  Assert.AreEqual<Integer>(0, CountFile(SRC_OK, fkMissingFinally),
    'bare Free im with-finally ist geschuetzt -> kein SCA009');
  Assert.IsTrue(CountFile(SRC_TP, fkMissingFinally) >= 1,
    'with-Body ohne try: bare Free ungeschuetzt -> SCA009 bleibt (keine Ueber-Suppression)');
end;

// ===========================================================================
// FN-Schutz: echte Bugs MUESSEN weiter erkannt werden (keine Ueber-Suppression).
// Bewaehrte Muster aus den Einzel-Unit-Tests, in einer Datei kombiniert.
// (Funktionsnamen ohne 'result'-Substring - sonst greift der SCA121-Source-
// Fallback und suppress faelschlich.)
// ===========================================================================
procedure TTestGoldenCorpus.RealBugs_StillDetected;
const SRC =
  'unit golden_realbugs;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TMath = class'#13#10 +
  '    Counter: Integer;'#13#10 +
  '    function Add(A, B: Integer): Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'function TMath.Add(A, B: Integer): Integer;'#13#10 +
  'begin Result := A + B; end;'#13#10 +       // nur Params -> SCA148-Kandidat (TP)
  'function Tally: Integer;'#13#10 +
  'begin end;'#13#10 +                        // weist Result NIE zu -> SCA121
  'procedure ReadsUninit;'#13#10 +
  'var u: Integer;'#13#10 +
  'begin'#13#10 +
  '  WriteLn(u);'#13#10 +                     // u nie geschrieben -> SCA166
  'end;'#13#10 +
  'end.';
begin
  Assert.IsTrue(CountCurated(SRC, fkCanBeClassMethod) >= 1,
    'Zustandslose Methode (nur Params) MUSS weiter SCA148 ausloesen');
  Assert.IsTrue(CountCurated(SRC, fkRoutineResultUnassigned) >= 1,
    'Funktion ohne Result-Zuweisung MUSS weiter SCA121 ausloesen');
  Assert.IsTrue(CountFile(SRC, fkUninitVar) >= 1,
    'Echte uninit-Variable MUSS weiter SCA166 ausloesen');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGoldenCorpus);

end.
