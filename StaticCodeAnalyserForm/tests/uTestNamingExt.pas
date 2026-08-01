unit uTestNamingExt;

// Tests fuer TNamingExtDetector (SCA118-119).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestNamingExt = class
  public
    // ExceptionName
    [Test] procedure ExceptionWithoutEPrefix_Reported;
    [Test] procedure ExceptionWithEPrefix_NotReported;
    [Test] procedure NonExceptionClass_NotReported;

    // LocalConstantName
    [Test] procedure PascalCaseNumericConst_Reported;
    [Test] procedure UpperSnakeNumericConst_NotReported;
    [Test] procedure ShortConstName_NotReported;
    [Test] procedure StringConst_NotReported;
    // 2026-07-26: Inline-const im RUMPF ist keine Deklarations-Konstante
    [Test] procedure InlineConstInBody_NotReported;
    // 2026-08-01 Konstanten-Gates (30%-Audit): Phantomknoten aus
    // Initialisiererlisten, strukturierte Konstanten, untypisierte
    // String-/Char-Literale.
    [Test] procedure UntypedStringConst_NotReported;
    [Test] procedure CharLiteralConst_NotReported;
    [Test] procedure TypedArrayConst_NotReported;
    [Test] procedure RecordArrayInitializerFields_NotReported;
    [Test] procedure NegativeNumericConst_StillReported;
    [Test] procedure TypedScalarConst_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestNamingExt.ExceptionWithoutEPrefix_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type MyParseError = class(Exception);'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkExceptionName) >= 1);
  finally F.Free; end;
end;

procedure TTestNamingExt.ExceptionWithEPrefix_NotReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type EMyParseError = class(Exception);'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExceptionName));
  finally F.Free; end;
end;

procedure TTestNamingExt.NonExceptionClass_NotReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type MyWorker = class end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkExceptionName));
  finally F.Free; end;
end;

procedure TTestNamingExt.PascalCaseNumericConst_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  MaxRetries = 3;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLocalConstantName) >= 1);
  finally F.Free; end;
end;

procedure TTestNamingExt.UpperSnakeNumericConst_NotReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  MAX_RETRIES = 3;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLocalConstantName));
  finally F.Free; end;
end;

procedure TTestNamingExt.ShortConstName_NotReported;
// Sehr kurze Namen (<=2 Zeichen) sind Loop-Counter, kein Befund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  N = 10;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLocalConstantName));
  finally F.Free; end;
end;

procedure TTestNamingExt.StringConst_NotReported;
// Strings sind oft UI-Labels (PascalCase OK), kein Befund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  MsgFileNotFound: string = ''File not found'';'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLocalConstantName));
  finally F.Free; end;
end;

procedure TTestNamingExt.InlineConstInBody_NotReported;
// Seit uParser2.ParseInlineConstStmt (2026-07-26) landet auch
// "const X = 42;" MITTEN IM RUMPF als nkConstSection im AST. SCA119 zielt
// aber auf die Konvention der Deklarations-/Unit-Ebene (UPPER_SNAKE_CASE);
// Inline-Konstanten schreibt man in Delphi 10.3+ wie lokale Variablen.
// Ohne die Direkt-Kind-Einschraenkung schlug das im Korpus mit +523 Funden
// auf (deltaT, interpolated, CPartBase ...) - reines Rauschen.
// GEGENPROBE steckt in PascalCaseNumericConst_Reported: die echte
// const-SEKTION im Deklarationsteil bleibt ein Fund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  const deltaT = 42;'#13#10 +
  '  Beep;'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLocalConstantName),
    'Inline-const im Rumpf darf SCA119 nicht ausloesen');
  finally F.Free; end;
end;

procedure TTestNamingExt.UntypedStringConst_NotReported;
// Der alte Skip sah nur den DEKLARIERTEN Typ. Ohne Typannotation gibt es
// keinen - der Literal-Typ des Initialisierers entscheidet jetzt mit.
// Korpus-Beleg: jvcl JvaDBReg.pas:59 'cItemField = ''ItemField'''.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  cItemField = ''ItemField'';'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLocalConstantName),
    'Untypisierte String-Konstante ist keine numerische Konstante');
  finally F.Free; end;
end;

procedure TTestNamingExt.CharLiteralConst_NotReported;
// Korpus-Beleg: cnwizards TestCharLiterals.pas:18 'Fred = #80'.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  CaptionSeparator = #80;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLocalConstantName),
    'Char-Literal ist keine numerische Konstante');
  finally F.Free; end;
end;

procedure TTestNamingExt.TypedArrayConst_NotReported;
// Korpus-Beleg: jvcl JvListBox.pas:198
// 'Sorted: array[Boolean] of DWORD = (0, LBS_SORT)'. Die Regel empfiehlt
// UPPER_SNAKE_CASE ausdruecklich fuer 'numeric constants'.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  SortFlags: array[Boolean] of DWORD = (0, 2);'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLocalConstantName),
    'Strukturierte typed-Array-Konstante ist kein Naming-Fund');
  finally F.Free; end;
end;

procedure TTestNamingExt.RecordArrayInitializerFields_NotReported;
// DIE FP-KLASSE MIT DER GROESSTEN MASSE. Der Wert-Scan in
// uParser2.ParseVarLikeSection ist nicht klammerbalanciert und bricht am
// ersten ';' ab - auch wenn das INNERHALB der Klammern steht. Ab dort
// laeuft ein neuer Durchlauf, und die Record-FELDNAMEN landen als eigene
// "Konstanten" im AST (Korpus-Beleg: Indy IdGlobalProtocols.pas:2632
// 'Offset', jvcl JvPainterEffectsForm.pas:128 'Pos').
// Erkennungsmerkmal hier: dem Phantom fehlt das '=' im TypeRef - eine
// gueltige Pascal-Konstante MUSS initialisiert sein.
// Der Parser-Fix liegt bewusst ausserhalb dieser Serie.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'type'#13#10 +
  '  TZoneRec = record TimeZone: string; Offset: string; end;'#13#10 +
  'const'#13#10 +
  '  Zones: array[0..1] of TZoneRec = ('#13#10 +
  '    (TimeZone: ''NST''; Offset: ''-0330''),'#13#10 +
  '    (TimeZone: ''EST''; Offset: ''-0500''));'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLocalConstantName),
    'Record-Feldnamen aus einem Initialisierer sind keine Konstanten');
  finally F.Free; end;
end;

procedure TTestNamingExt.NegativeNumericConst_StillReported;
// WAECHTER: die Gates duerfen den Kern der Regel nicht mitnehmen. Ein
// negativer Zahlwert faengt nicht mit '(' oder Quote an und bleibt Fund.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  MinTemperature = -273;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLocalConstantName) >= 1,
    'Negative Zahlkonstante muss weiter gemeldet werden');
  finally F.Free; end;
end;

procedure TTestNamingExt.TypedScalarConst_StillReported;
// WAECHTER: skalar-typisierte Konstante ist genau der Fall, den die Regel
// meint - der Typteil enthaelt weder array noch record.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'const'#13#10 +
  '  BufferSize: Integer = 4096;'#13#10 +
  'begin'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLocalConstantName) >= 1,
    'Skalar typisierte Konstante muss weiter gemeldet werden');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNamingExt);

end.
