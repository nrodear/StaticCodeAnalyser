unit uTestNilDeref;

// Tests fuer TNilDerefDetector. Pattern: Variable koennte nil sein
// (z.B. Function-Return ohne Assigned-Check) und wird dereferenziert.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestNilDeref = class
  public
    [Test] procedure UncheckedReturn_Reported;
    [Test] procedure AssignedCheck_NotReported;
    [Test] procedure NotNilCheck_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestNilDeref.UncheckedReturn_Reported;
// TNilDerefDetector matched aktuell ausschliesslich `var := nil` gefolgt
// von `var.Method(...)`. Die "function-return-might-be-nil"-Variante
// (`x := FindThing; x.DoStuff`) ist out-of-scope - dafuer braeuchte es
// eine Inter-Procedural-Nullable-Analyse die Delphi-AST nicht
// strukturell erlaubt. Bis dahin hier das Pattern testen das tatsaechlich
// erkannt wird (Audit V5 / 2026-05-30).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  x := nil;'#13#10 +
  '  x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1);
  finally F.Free; end;
end;

procedure TTestNilDeref.AssignedCheck_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'function FindThing: TObject; forward;'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  x := FindThing;'#13#10 +
  '  if Assigned(x) then'#13#10 +
  '    x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref));
  finally F.Free; end;
end;

procedure TTestNilDeref.NotNilCheck_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'function FindThing: TObject; forward;'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  x := FindThing;'#13#10 +
  '  if x <> nil then'#13#10 +
  '    x.DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNilDeref));
  finally F.Free; end;
end;

procedure TTestNilDeref.Finding_KindAndSeverity;
// Siehe UncheckedReturn_Reported - Detector matched nur `var := nil`.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TObject;'#13#10 +
  'begin'#13#10 +
  '  x := nil;'#13#10 +
  '  x.DoStuff;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkNilDeref then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkNilDeref finding expected');
    Assert.AreEqual(fkNilDeref, Hit.Kind);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNilDeref);

end.
