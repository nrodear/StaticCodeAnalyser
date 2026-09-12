unit uTestGroupedDeclaration;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestGroupedDeclaration = class
  public
    [Test] procedure SingleVarPerLine_NoFinding;
    // Voll-Review 2026-09-12 (Blocker): case-Label-Listen sind Syntax,
    // keine gruppierte Deklaration.
    [Test] procedure CaseLabelsWithStatement_NoFinding;
    [Test] procedure GroupedVarAfterCaseEnd_StillReported;
    [Test] procedure TwoVarsGrouped_Reported;
    [Test] procedure ThreeVarsGrouped_Reported;
    [Test] procedure ParameterGrouped_NotReported;
    [Test] procedure FieldGrouped_Reported;
    [Test] procedure GroupedDeclaration_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestGroupedDeclaration.CaseLabelsWithStatement_NoFinding;
// 'vaOne, vaTwo: DoIt;' im case-Rumpf erfuellte das Muster (>=2
// Idents, ':', Ident danach) und meldete - obwohl das schlicht
// case-Syntax ist. Das case-Gate muss den Rumpf ausnehmen, auch
// mit geschachteltem begin-Block.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(K: TKind);'#13#10 +
  'begin'#13#10 +
  '  case K of'#13#10 +
  '    vaOne, vaTwo: DoIt;'#13#10 +
  '    vaThree: begin'#13#10 +
  '      Log;'#13#10 +
  '    end;'#13#10 +
  '    nkCall, nkAssign: ProcessNode;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkGroupedDeclaration),
    'case-Label-Listen duerfen nicht als gruppierte Deklaration melden');
  finally F.Free; end;
end;

procedure TTestGroupedDeclaration.GroupedVarAfterCaseEnd_StillReported;
// Gegenprobe: NACH dem case-Ende ist das Gate wieder offen - eine
// echte Gruppen-Deklaration in der naechsten Prozedur muss melden.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(K: TKind);'#13#10 +
  'begin'#13#10 +
  '  case K of'#13#10 +
  '    vaOne: DoIt;'#13#10 +
  '  end;'#13#10 +
  'end;'#13#10 +
  'procedure Bar;'#13#10 +
  'var A, B: Integer;'#13#10 +
  'begin'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(
    TFindingHelper.Count(F, fkGroupedDeclaration) >= 1,
    'nach dem case-Ende muss die echte Gruppen-Deklaration melden');
  finally F.Free; end;
end;

procedure TTestGroupedDeclaration.SingleVarPerLine_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  A: Integer;'#13#10 +
  '  B: Integer;'#13#10 +
  'begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGroupedDeclaration));
  finally F.Free; end;
end;

procedure TTestGroupedDeclaration.TwoVarsGrouped_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var'#13#10 +
  '  A, B: Integer;'#13#10 +
  'begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkGroupedDeclaration));
  finally F.Free; end;
end;

procedure TTestGroupedDeclaration.ThreeVarsGrouped_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  A, B, C: Integer;'#13#10 +
  'begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkGroupedDeclaration));
  finally F.Free; end;
end;

procedure TTestGroupedDeclaration.ParameterGrouped_NotReported;
// Gruppierte Parameter `procedure F(A, B: Integer)` sind in Delphi
// idiomatische Syntax und werden NICHT als GroupedDecl geflaggt - sonst
// wuerde jede Helper-Funktion mit gleichgetypten Parametern Noise produzieren.
// Self-Test auf eigenem Code zeigte 660+ FPs durch diese Klasse;
// detector-seitig via ParenDepth-Filter geloest.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(A, B: Integer); begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkGroupedDeclaration));
  finally F.Free; end;
end;

procedure TTestGroupedDeclaration.FieldGrouped_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    FA, FB: Integer;'#13#10 +
  '  end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkGroupedDeclaration) >= 1);
  finally F.Free; end;
end;

procedure TTestGroupedDeclaration.GroupedDeclaration_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; var A, B: Integer; begin end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkGroupedDeclaration then
      begin
        Assert.AreEqual<TFindingKind>(fkGroupedDeclaration, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,              Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkGroupedDeclaration finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestGroupedDeclaration);

end.
