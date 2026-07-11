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
    // Real-World FP-Audit 2026-07-10: numerischer Akkumulator ist kein String-Concat
    [Test] procedure StringConcat_NumericAccumulator_NotReported;
    // SCA110-FP-Audit 2026-07-11 (clean-lexical): Set-/Array-Literal-RHS + Loop-Scope
    [Test] procedure StringConcat_SetUnionInLoop_NotReported;
    [Test] procedure StringConcat_NonBracketRhsInLoop_Reported;
    [Test] procedure StringConcat_SingleStmtLoopBleed_NotReported;
    [Test] procedure StringConcat_SingleStmtLoop_Reported;

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
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkStringConcatInLoop),
      'genau 1 StringConcatInLoop-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 's := s + IntToStr(i)'),
      TFindingHelper.FirstOf(F, fkStringConcatInLoop).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
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
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkStringConcatInLoop),
      'genau 1 StringConcatInLoop-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 's := s + '),
      TFindingHelper.FirstOf(F, fkStringConcatInLoop).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
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
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkParamByNameInLoop),
      'genau 1 ParamByNameInLoop-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'ParamByName'),
      TFindingHelper.FirstOf(F, fkParamByNameInLoop).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
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
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFieldByNameInLoop),
      'genau 1 FieldByNameInLoop-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'FieldByName'),
      TFindingHelper.FirstOf(F, fkFieldByNameInLoop).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
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

procedure TTestPerfHotspots.StringConcat_NumericAccumulator_NotReported;
// Real-World FP-Audit 2026-07-10: 'j := j + 3' mit j:Integer ist eine numerische
// Akkumulation, KEIN String-Concat (kein O(n^2)-Realloc-Bug). Der LHS-Typ wird
// aus der Deklaration aufgeloest -> numerisch -> kein Fund. Gegenstueck zum
// bestehenden StringConcat_InForLoop_Reported (s:string bleibt Fund).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var j: Integer; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    j := j + 3;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringConcatInLoop),
    'numerischer Akkumulator (j: Integer) ist kein String-Concat');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_SetUnionInLoop_NotReported;
// SCA110-FP-Audit 2026-07-11 (clean-lexical (a)): 'CharSet := CharSet + [C]' ist
// Set-Union (bzw. Array-Concat), KEIN String-O(n^2)-Concat. Ein '+' direkt vor
// '[' ist immer ein Set-/Array-Konstruktor -> unterdruecken. Vgl. real-world
// Alcinoe.StringUtils.pas / Alcinoe.SMTP.Client.pas.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var CharSet: TSysCharSet; i: Integer; C: AnsiChar;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    CharSet := CharSet + [C];'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringConcatInLoop),
    'Set-Union ''x := x + [..]'' ist kein String-Concat');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_NonBracketRhsInLoop_Reported;
// TP-Guard zu (a): gewoehnliches String-Concat (RHS beginnt NICHT mit '[')
// muss weiter feuern - der Bracket-Guard darf nicht ueberschiessen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s, t: string; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    s := s + Copy(t, i, 1);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkStringConcatInLoop),
    'gewoehnliches String-Concat in Schleife bleibt ein Fund');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_SingleStmtLoopBleed_NotReported;
// SCA110-FP-Audit 2026-07-11 (clean-lexical (b)): eine Einzelanweisungs-Schleife
// 'while ... do stmt;' darf NICHT in nachfolgenden Straight-Line-Code ausbluten.
// Frueher blieb der Loop-Header liegen und verschluckte das spaetere,
// unabhaengige 'begin' des if -> der Concat wurde faelschlich als "in Schleife"
// gemeldet (FP-Klasse not-in-loop, vgl. Alcinoe.XMLDoc/JSONDoc).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string; p: Integer;'#13#10 +
  'begin'#13#10 +
  '  while p < 10 do Inc(p);'#13#10 +
  '  if s <> '''' then'#13#10 +
  '  begin'#13#10 +
  '    s := s + ''!'';'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringConcatInLoop),
    'Concat NACH einer Einzelanweisungs-Schleife ist nicht in der Schleife');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_SingleStmtLoop_Reported;
// TP-Guard zu (b): ein echtes String-Concat IN einer Einzelanweisungs-Schleife
// 'for i ... do s := s + x;' ist der reale O(n^2)-Bug und muss feuern - der
// Loop-Scope-Fix erkennt Einzelanweisungs-Bodies jetzt korrekt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do s := s + ''x'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkStringConcatInLoop),
    'String-Concat in Einzelanweisungs-Schleife bleibt ein Fund');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPerfHotspots);

end.
