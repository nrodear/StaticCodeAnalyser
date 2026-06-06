unit uTestPerfHotspots;

// Tests fuer TPerfHotspotsDetector (SCA110-112).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPerfHotspots = class
  public
    // StringConcatInLoop
    [Test] procedure StringConcat_InForLoop_Reported;
    [Test] procedure StringConcat_OutsideLoop_NotReported;
    [Test] procedure StringConcat_InWhile_Reported;
    [Test] procedure StringConcat_DifferentVars_NotReported;

    // ParamByNameInLoop
    [Test] procedure ParamByName_InLoop_Reported;
    [Test] procedure ParamByName_OutsideLoop_NotReported;

    // FieldByNameInLoop
    [Test] procedure FieldByName_InWhileEofLoop_Reported;
    [Test] procedure FieldByName_OutsideLoop_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestPerfHotspots.StringConcat_InForLoop_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    s := s + IntToStr(i);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkStringConcatInLoop) >= 1);
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_OutsideLoop_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string;'#13#10 +
  'begin'#13#10 +
  '  s := s + ''once'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringConcatInLoop));
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_InWhile_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  i := 0;'#13#10 +
  '  while i < 10 do'#13#10 +
  '  begin'#13#10 +
  '    s := s + ''x'';'#13#10 +
  '    Inc(i);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkStringConcatInLoop) >= 1);
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_DifferentVars_NotReported;
// a := b + c ist KEIN Self-Concat -> kein Befund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var a, b, c: string; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    a := b + c;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringConcatInLoop));
  finally F.Free; end;
end;

procedure TTestPerfHotspots.ParamByName_InLoop_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    Q.ParamByName(''id'').AsInteger := i;'#13#10 +
  '    Q.ExecSQL;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkParamByNameInLoop) >= 1);
  finally F.Free; end;
end;

procedure TTestPerfHotspots.ParamByName_OutsideLoop_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Q.ParamByName(''id'').AsInteger := 42;'#13#10 +
  '  Q.ExecSQL;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkParamByNameInLoop));
  finally F.Free; end;
end;

procedure TTestPerfHotspots.FieldByName_InWhileEofLoop_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Total: Currency;'#13#10 +
  'begin'#13#10 +
  '  Total := 0;'#13#10 +
  '  while not Q.Eof do'#13#10 +
  '  begin'#13#10 +
  '    Total := Total + Q.FieldByName(''Amount'').AsCurrency;'#13#10 +
  '    Q.Next;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkFieldByNameInLoop) >= 1);
  finally F.Free; end;
end;

procedure TTestPerfHotspots.FieldByName_OutsideLoop_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Lbl.Caption := Q.FieldByName(''Name'').AsString;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFieldByNameInLoop));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPerfHotspots);

end.
