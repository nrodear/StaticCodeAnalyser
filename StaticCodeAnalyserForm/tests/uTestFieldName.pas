unit uTestFieldName;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFieldName = class
  public
    [Test] procedure FPrefix_NoFinding;
    [Test] procedure NoFPrefix_Reported;
    [Test] procedure MethodInClass_NoFinding;
    [Test] procedure UnitLevelVar_NoFinding;
    [Test] procedure FieldName_KindAndSeverity;
    [Test] procedure MultilineHeaderMiddleParam_NotReported;
    [Test] procedure TypedClassConst_NotReported;
    [Test] procedure VarAfterConstSection_FieldReportedAgain;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestFieldName.FPrefix_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    FCount: Integer;'#13#10 +
  '    FName: string;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFieldName));
  finally F.Free; end;
end;

procedure TTestFieldName.NoFPrefix_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    Counter: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFieldName));
  finally F.Free; end;
end;

procedure TTestFieldName.MethodInClass_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '    function GetX: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFieldName));
  finally F.Free; end;
end;

procedure TTestFieldName.UnitLevelVar_NoFinding;
// Unit-level Variables sind keine Klassen-Felder.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'var'#13#10 +
  '  Counter: Integer;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFieldName));
  finally F.Free; end;
end;

procedure TTestFieldName.FieldName_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    Counter: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkFieldName then
      begin
        Assert.AreEqual<TFindingKind>(fkFieldName, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,     Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkFieldName finding');
  finally Findings.Free; end;
end;

procedure TTestFieldName.MultilineHeaderMiddleParam_NotReported;
// Voll-Review 2026-09-12 (Blocker): die Mittelzeile 'B: string;' eines
// dreizeiligen Methodenkopfs hat weder ')' noch einen Modifier-Prefix
// und passierte alle Guards -> FP 'Field B does not follow F<Name>'.
// Jetzt haelt die Klammerbilanz die offene Parameterliste fest.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    procedure Foo(A: Integer;'#13#10 +
  '      B: string;'#13#10 +
  '      C: Boolean);'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFieldName));
  finally F.Free; end;
end;

procedure TTestFieldName.TypedClassConst_NotReported;
// Zweite FP-Klasse des Blockers: die 'const'-Zeile schaltete nur SICH
// SELBST stumm, die typisierte Konstante danach wurde als Feld
// geflaggt. Jetzt traegt die const-Untersektion bis zum naechsten
// Abschnitts-Keyword.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    const'#13#10 +
  '      Timeout: Integer = 500;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFieldName));
  finally F.Free; end;
end;

procedure TTestFieldName.VarAfterConstSection_FieldReportedAgain;
// Gegenrichtung zum const-Untersektions-Gate: 'var' beendet die
// Untersektion, das Feld dahinter wird weiter gemeldet. Assert auf
// EXAKT 1 ist beidseitig scharf - die Bestandsfassung meldete hier 2
// (Timeout faelschlich mit), eine uebergriffige Untersektion 0.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  private'#13#10 +
  '    const'#13#10 +
  '      Timeout: Integer = 500;'#13#10 +
  '    var'#13#10 +
  '      Speed: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFieldName));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFieldName);

end.
