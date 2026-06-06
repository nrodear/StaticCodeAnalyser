unit uTestEmptyArgumentList;

// Tests fuer TEmptyArgumentListDetector (file-scan: `Foo()` -> `Foo;`).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEmptyArgumentList = class
  public
    [Test] procedure NoCall_NoFinding;
    [Test] procedure SimpleEmptyCall_Reported;
    [Test] procedure FunctionResultAssign_Reported;
    [Test] procedure NonEmptyArgs_NotReported;
    [Test] procedure EmptyParensAfterComma_NotReported;
    [Test] procedure EmptyParensInString_NotReported;
    [Test] procedure EmptyParensInComment_NotReported;
    [Test] procedure EmptyArgumentList_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestEmptyArgumentList.NoCall_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyArgumentList));
  finally F.Free; end;
end;

procedure TTestEmptyArgumentList.SimpleEmptyCall_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  DoStuff();'#13#10 +              // <-- Treffer
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyArgumentList));
  finally F.Free; end;
end;

procedure TTestEmptyArgumentList.FunctionResultAssign_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var X: Integer;'#13#10 +
  'begin'#13#10 +
  '  X := MyFunc();'#13#10 +          // <-- Treffer
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyArgumentList));
  finally F.Free; end;
end;

procedure TTestEmptyArgumentList.NonEmptyArgs_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  WriteLn(''hello'');'#13#10 +
  '  DoStuff(1, 2, 3);'#13#10 +
  '  X := Func(A);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyArgumentList));
  finally F.Free; end;
end;

procedure TTestEmptyArgumentList.EmptyParensAfterComma_NotReported;
// `(...)` ohne vorangehenden Identifier (z.B. leeres Tupel/Set, oder
// gleich am Zeilenanfang) ist KEIN leeres Argument-List.
const SRC =
  'unit t; implementation'#13#10 +
  'const Empty: TArray<Integer> = ();'#13#10 +
  'procedure Foo;'#13#10 +
  'begin DoStuff(1, , 2); end;';   // syntaktisch komisch, aber kein `()` nach Ident
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyArgumentList));
  finally F.Free; end;
end;

procedure TTestEmptyArgumentList.EmptyParensInString_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  WriteLn(''Call MyProc() to start'');'#13#10 +  // String -> kein Treffer
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyArgumentList));
  finally F.Free; end;
end;

procedure TTestEmptyArgumentList.EmptyParensInComment_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  '// call MyProc() somewhere'#13#10 +
  '{ also DoStuff() in this comment }'#13#10 +
  'procedure Foo; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyArgumentList));
  finally F.Free; end;
end;

procedure TTestEmptyArgumentList.EmptyArgumentList_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; begin DoStuff(); end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkEmptyArgumentList then
      begin
        Assert.AreEqual<TFindingKind>(fkEmptyArgumentList, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,             Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkEmptyArgumentList finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEmptyArgumentList);

end.
