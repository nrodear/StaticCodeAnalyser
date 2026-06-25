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
