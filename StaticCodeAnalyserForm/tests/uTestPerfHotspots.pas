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
    // Welle 1 (TTypeResolver): QWord fehlt in der Regex-NUMTYPES, der AST-Resolver
    // kennt es -> nur der Resolver-Pfad unterdrueckt diesen numerischen Akkumulator.
    [Test] procedure StringConcat_QWordAccumulator_ResolverOnly_NotReported;
    // Track A (2026-07-12): RHS strukturell beweisbar kein String -> suppress.
    // LHS-Typ NICHT in NUMTYPES, damit nur RhsIsProvablyNonString greift (isoliert).
    [Test] procedure StringConcat_RhsNumericLiteral_NotReported;      // N2
    [Test] procedure StringConcat_RhsArithmeticOperator_NotReported;  // N3
    [Test] procedure StringConcat_RhsSetConstructor_NotReported;      // N1
    [Test] procedure StringConcat_RhsNumericFunc_NotReported;         // N4
    // TP-Gegenproben: echte String/Char-Concats muessen weiter feuern
    [Test] procedure StringConcat_RhsCharIndexAccess_StillReported;   // s+arr[i]
    [Test] procedure StringConcat_RhsCharLiteral_StillReported;       // s+','
    [Test] procedure StringConcat_RhsCharIndexLiteralDigit_StillReported; // s+arr[0]: Bracket-Tiefe
    [Test] procedure StringConcat_RhsNumFnDotToString_StillReported;      // s+Integer(x).ToString: N4-trailing-dot

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

procedure TTestPerfHotspots.StringConcat_QWordAccumulator_ResolverOnly_NotReported;
// Welle 1 - Beleg fuer die additive AST-Typ-Aufloesung (Core-Detektoren-Architektur).
// 'q := q + i' mit q:QWord ist numerische Akkumulation, kein O(n^2)-String-Concat.
// Die lexikalische LhsDeclaredNumeric kennt 'qword' NICHT (fehlt in ihrer NUMTYPES-
// Liste) -> wuerde faelschlich melden. Der TTypeResolver loest q -> qword auf und
// unterdrueckt (IsNumericTypeName). Zeigt, dass der Resolver-Pfad zusaetzlich greift.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var q: QWord; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    q := q + i;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringConcatInLoop),
    'q: QWord ist numerisch - nur der AST-Resolver kennt qword -> kein Fund');
  finally F.Free; end;
end;

// ---- Track A: RhsIsProvablyNonString (2026-07-12) ----
// LHS-Typ bewusst 'TAcc'/'TSet' (NICHT in NUMTYPES), damit LhsDeclaredNumeric
// NICHT vorab suppress't -> ohne den neuen Guard waeren das FPs. Prueft also
// isoliert RhsIsProvablyNonString.

procedure TTestPerfHotspots.StringConcat_RhsNumericLiteral_NotReported;
// N2: Zahl-Literal-Operand -> beweisbar numerisch.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TAcc; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    x := x + 7;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringConcatInLoop),
    'x := x + 7 (Zahl-Literal) ist numerisch, kein String-Concat');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_RhsArithmeticOperator_NotReported;
// N3: numerischer Operator '*' auf Tiefe 0 -> beweisbar numerisch.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TAcc; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    x := x + i * 2;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringConcatInLoop),
    'x := x + i * 2 (Operator *) ist numerisch, kein String-Concat');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_RhsSetConstructor_NotReported;
// N1: RHS beginnt mit '[' -> Set-/Array-Konstruktor, kein String.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TSet; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    x := x + [i];'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringConcatInLoop),
    'x := x + [i] (Set-Konstruktor) ist kein String-Concat');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_RhsNumericFunc_NotReported;
// N4: numerischer Func-Operand Length(...) ohne trailing '.' -> Integer.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: TAcc; s: string; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    x := x + Length(s);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkStringConcatInLoop),
    'x := x + Length(s) (numerische Func) ist numerisch, kein String-Concat');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_RhsCharIndexAccess_StillReported;
// TP-Gegenprobe: 's := s + arr[i]' haengt ein Char an (echtes O(n^2)-Concat).
// Die '[i]'-Ziffer liegt auf Bracket-Tiefe 1 -> darf N2 NICHT ausloesen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string; arr: array of Char; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    s := s + arr[i];'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkStringConcatInLoop),
    's := s + arr[i] (Char-Anhang) bleibt ein String-Concat-Fund');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_RhsCharLiteral_StillReported;
// TP-Gegenprobe: 's := s + '','' ' haengt ein Char-Literal an (echtes Concat).
// Das Literal wird uebersprungen -> keine Klausel greift -> bleibt Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    s := s + '','';'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkStringConcatInLoop),
    's := s + '','' (Char-Literal) bleibt ein String-Concat-Fund');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_RhsCharIndexLiteralDigit_StillReported;
// TP-Gegenprobe (Bracket-Tiefe-Lock): 's := s + arr[0]' - die Ziffer '0' liegt
// auf Bracket-Tiefe 1 und darf N2 NICHT ausloesen; s+Char(arr[0]) ist ein
// echtes Concat.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string; arr: array of Char; i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    s := s + arr[0];'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkStringConcatInLoop),
    'Ziffer in arr[0] ist auf Bracket-Tiefe 1 - kein N2 - bleibt Fund');
  finally F.Free; end;
end;

procedure TTestPerfHotspots.StringConcat_RhsNumFnDotToString_StillReported;
// TP-Gegenprobe (N4-trailing-dot-Lock): 's := s + Integer(x).ToString' - .ToString
// liefert String; das '.' nach dem NumFn-')' verhindert N4 -> bleibt Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var s: string; x, i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 10 do'#13#10 +
  '  begin'#13#10 +
  '    s := s + Integer(x).ToString;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkStringConcatInLoop),
    'Integer(x).ToString (trailing .) ist String - N4 greift nicht - bleibt Fund');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPerfHotspots);

end.
