unit uTestRdxFloatEqualityFix;

// Editorhilfe SCA144 FloatEquality (uRdxFloatEqualityFix): der Planer auf
// Text und die Typ- und Kontextpruefungen als reine Funktionen (erste
// Fixture, auch FPC), dazu der ECHTE Detektor (uFloatEquality) auf dem
// echten AST ueber den Einstieg der Tabelle (TRdxFixTable.FixFor, Adapter
// PlanFloatEquality; zweite Fixture, nur Delphi - bis zur Integration der
// Charge QF stand hier eine woertliche Kopie des Adapters). Die Fixtures der
// ersten stehen in 'procedure Foo(Ratio: Double; Other: Double)', der Rumpf
// beginnt auf Zeile 6 (LINE).
//
// Realwelt-Test rwE29 (Fehler TES5Edit wbDataFormat.pas:3315): prueft der
// then-Zweig denselben Operanden mit Toleranz ('if Value <> 0.0 then if
// SingleSameValue(Value, 0.0) then Value := 0.0'), ist der exakte Vergleich
// Absicht - gesperrt (TolerantBranch_NoHelp, gegen 7d5de210 rot: dort
// 'not IsZero(Value)' angeboten; die Gegenproben darin waren schon gruen).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxFloatEqualityFix = class
  public
    // ---- Umformung ----
    [Test] procedure Equal_BecomesSameValue;
    [Test] procedure ZeroLiteral_BecomesIsZero;
    [Test] procedure NotEqual_GetsNot;
    [Test] procedure WholeExpressions_Rewritten;
    [Test] procedure Spelling_KeptFromSource;
    // ---- Gegenproben ----
    [Test] procedure Precedence_NoHelp;
    [Test] procedure PartOfLargerExpression_NoHelp;
    [Test] procedure MovedLine_NoHelp;
    [Test] procedure CommentOrString_NoHelp;
    [Test] procedure TwiceOnLine_NoHelp;
    [Test] procedure GuardIdiom_NoHelp;
    [Test] procedure TolerantBranch_NoHelp;
    [Test] procedure OwnFunction_NoHelp;
    [Test] procedure WithBefore_NoHelp;
    [Test] procedure DeclarationList_NoHelp;
    [Test] procedure Message_NoHelp;
    // ---- Typbeweis und Kontext (Bausteine des Adapters) ----
    [Test] procedure TypeReason_ProvenFloats;
    [Test] procedure TypeReason_Refused;
    [Test] procedure ContextReason_LowAndWith;
    // ---- Realwelt-Test rwE30 (Fix-Runde 2) ----
    [Test] procedure OldCompilerBranch_NoHelp;
    [Test] procedure WithClosedBefore_Help;
    [Test] procedure WithFieldRecord_Help;
    [Test] procedure WithOtherTargets_NoHelp;
    [Test] procedure LocalType_NestedParam;
    [Test] procedure TypeReason_SingleWithInteger;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxFloatEqualityDetector = class
  public
    // ---- echter Detektor ----
    [Test] procedure Detector_ReportsLineAndOperands;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_AddsMathToUses;
    [Test] procedure Detector_TwoOnLine_BothFixed;
    [Test] procedure Detector_CatalogExample_Fixed;
    [Test] procedure Detector_SubExpression_NoHelp;
    [Test] procedure Detector_Currency_NoHelp;
    [Test] procedure Detector_Guard_NoHelp;
    // ---- Adapter ----
    [Test] procedure Adapter_HintAndName;
    [Test] procedure Adapter_LowConfidence_NoHelp;
    [Test] procedure Adapter_NestedRoutine_ParamProven;
    [Test] procedure Adapter_NoFile_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uEngineApi, uRuleCatalog, uFloatEquality,
  uRdxRecipeRunner,      // TRdxFixOutcome, UsesNamesOf
  uRdxFixTable,          // TRdxFixTable.FixFor
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText, FixAllWith
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxFloatEqualityFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply, NewMap

const
  LINE = 6;   // erste Rumpfzeile von Wrap

// ---- Helfer ----

function Wrap(const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation',
    'procedure Foo(Ratio: Double; Other: Double);', 'begin']) + #13#10
    + Join(ABody) + #13#10 + Join(['end;', 'end.']);
end;

// Die Meldung des Detektors (uFloatEquality) fuer den Vergleich.
function Msg(const ALeft, AOp, ARight: string): string;
begin
  Result := Format('Float equality (%s %s %s) is unreliable due to IEEE-754 '
    + 'rounding - use SameValue/Math.IsZero', [ALeft, AOp, ARight]);
end;

// Der Planer fuer Zeile ALine mit der Meldung AMessage: der neue Text, oder
// '' bei Ablehnung (AReason).
function PlanAt(const ASource: string; ALine: Integer; const AMessage: string;
  out AReason: string): string;
var
  Map : TRdxCodeMap;
  E   : TRdxEdit;
  Ok  : Boolean;
begin
  Result := '';
  AReason := '';
  Map := NewMap(ASource);
  try
    Ok := TRdxFloatEqualityFix.ToleranceCompare(Map, ALine, AMessage, E,
      AReason);
  finally
    Map.Free;
  end;
  if Ok then
    Result := Apply(ASource, E);
end;

// Die Hilfe muss gelten (sonst scheitert der Test mit dem Grund).
function Applied(const ASource: string; ALine: Integer;
  const ALeft, AOp, ARight: string): string;
var
  R : string;
begin
  Result := PlanAt(ASource, ALine, Msg(ALeft, AOp, ARight), R);
  Assert.IsTrue(Result <> '', R);
end;

procedure AssertRefused(const ASource: string; ALine: Integer;
  const ALeft, AOp, ARight, AReason: string);
var
  R : string;
begin
  Assert.AreEqual('', PlanAt(ASource, ALine, Msg(ALeft, AOp, ARight), R),
    'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
end;

// ---- Umformung ----

procedure TTestRdxFloatEqualityFix.Equal_BecomesSameValue;
var
  Map : TRdxCodeMap;
  E   : TRdxEdit;
  R   : string;
begin
  Assert.AreEqual(Wrap(['  if SameValue(Ratio, 0.5) then Work;']),
    Applied(Wrap(['  if Ratio = 0.5 then Work;']), LINE, 'Ratio', '=', '0.5'));
  Assert.AreEqual(Wrap(['  if SameValue(0.5, Ratio) then Work;']),
    Applied(Wrap(['  if 0.5 = Ratio then Work;']), LINE, '0.5', '=', 'Ratio'));
  Assert.AreEqual(Wrap(['  if SameValue(Ratio, Other) then Work;']),
    Applied(Wrap(['  if Ratio = Other then Work;']), LINE, 'Ratio', '=',
      'Other'));
  // Die Ersetzung reicht genau ueber den Vergleich.
  Map := NewMap(Wrap(['  if Ratio = 0.5 then Work;']));
  try
    Assert.IsTrue(TRdxFloatEqualityFix.ToleranceCompare(Map, LINE,
      Msg('Ratio', '=', '0.5'), E, R), R);
  finally
    Map.Free;
  end;
  Assert.AreEqual('Ratio = 0.5', E.Expected);
  Assert.AreEqual('SameValue(Ratio, 0.5)', E.NewText);
  Assert.AreEqual<Integer>(LINE, E.Span.StartLine);
  Assert.AreEqual<Integer>(6, E.Span.StartCol);
  Assert.AreEqual<Integer>(17, E.Span.EndCol);
end;

procedure TTestRdxFloatEqualityFix.ZeroLiteral_BecomesIsZero;
begin
  Assert.AreEqual(Wrap(['  if IsZero(Ratio) then Work;']),
    Applied(Wrap(['  if Ratio = 0 then Work;']), LINE, 'Ratio', '=', '0'));
  Assert.AreEqual(Wrap(['  if IsZero(Ratio) then Work;']),
    Applied(Wrap(['  if 0.0 = Ratio then Work;']), LINE, '0.0', '=', 'Ratio'));
  Assert.AreEqual(Wrap(['  if IsZero(Ratio) then Work;']),
    Applied(Wrap(['  if Ratio = 0.00 then Work;']), LINE, 'Ratio', '=',
      '0.00'));
  // 0.5 ist keine Null.
  Assert.AreEqual(Wrap(['  if SameValue(Ratio, 0.05) then Work;']),
    Applied(Wrap(['  if Ratio = 0.05 then Work;']), LINE, 'Ratio', '=',
      '0.05'));
end;

procedure TTestRdxFloatEqualityFix.NotEqual_GetsNot;
begin
  Assert.AreEqual(Wrap(['  while not SameValue(Ratio, Other) do Work;']),
    Applied(Wrap(['  while Ratio <> Other do Work;']), LINE, 'Ratio', '<>',
      'Other'));
  Assert.AreEqual(Wrap(['  if not IsZero(Ratio) then Work;']),
    Applied(Wrap(['  if Ratio <> 0 then Work;']), LINE, 'Ratio', '<>', '0'));
end;

procedure TTestRdxFloatEqualityFix.WholeExpressions_Rewritten;
begin
  // Zuweisung, Argument, geklammerte Bedingung, until, Argument nach Komma.
  Assert.AreEqual(Wrap(['  Ok := SameValue(Ratio, Other);']),
    Applied(Wrap(['  Ok := Ratio = Other;']), LINE, 'Ratio', '=', 'Other'));
  Assert.AreEqual(Wrap(['  Assert(SameValue(Ratio, 0.5), ''x'');']),
    Applied(Wrap(['  Assert(Ratio = 0.5, ''x'');']), LINE, 'Ratio', '=',
      '0.5'));
  Assert.AreEqual(Wrap(['  if (SameValue(Ratio, 0.5)) and Flag then Work;']),
    Applied(Wrap(['  if (Ratio = 0.5) and Flag then Work;']), LINE, 'Ratio',
      '=', '0.5'));
  Assert.AreEqual(Wrap(['  repeat', '    Work;', '  until SameValue(Ratio, 1);']),
    Applied(Wrap(['  repeat', '    Work;', '  until Ratio = 1;']), LINE + 2,
      'Ratio', '=', '1'));
  Assert.AreEqual(Wrap(['  Check(Flag, not SameValue(Ratio, Other));']),
    Applied(Wrap(['  Check(Flag, Ratio <> Other);']), LINE, 'Ratio', '<>',
      'Other'));
  // Der Vergleich als Bedingung, das then auf der Folgezeile.
  Assert.AreEqual(Wrap(['  if SameValue(Ratio, 0.5)', '  then Work;']),
    Applied(Wrap(['  if Ratio = 0.5', '  then Work;']), LINE, 'Ratio', '=',
      '0.5'));
end;

procedure TTestRdxFloatEqualityFix.Spelling_KeptFromSource;
begin
  Assert.AreEqual(Wrap(['  IF SameValue(ratio, 1.5E3) THEN Work;']),
    Applied(Wrap(['  IF ratio = 1.5E3 THEN Work;']), LINE, 'ratio', '=',
      '1.5E3'));
  // Gross/klein der Meldung zaehlt nicht - geschrieben wird der Quelltext.
  Assert.AreEqual(Wrap(['  if IsZero(ratio) then Work;']),
    Applied(Wrap(['  if ratio = 0 then Work;']), LINE, 'RATIO', '=', '0'));
end;

// ---- Gegenproben ----

procedure TTestRdxFloatEqualityFix.Precedence_NoHelp;
begin
  // 'A = B and C' ist 'A = (B and C)', 'C and A = B' ist '(C and A) = B'.
  AssertRefused(Wrap(['  if Ratio = Other and Flag then Work;']), LINE,
    'Ratio', '=', 'Other', _(R_FLOAT_AFTER, ['Ratio = Other', 'and']));
  AssertRefused(Wrap(['  if Flag and Ratio = Other then Work;']), LINE,
    'Ratio', '=', 'Other', _(R_FLOAT_BEFORE, ['Ratio = Other', 'and']));
  AssertRefused(Wrap(['  if not Ratio = Other then Work;']), LINE,
    'Ratio', '=', 'Other', _(R_FLOAT_BEFORE, ['Ratio = Other', 'not']));
end;

procedure TTestRdxFloatEqualityFix.PartOfLargerExpression_NoHelp;
begin
  // Der Detektor meldet bei 'a + b = c' den Teilausdruck 'b = c'.
  AssertRefused(Wrap(['  if A + Ratio = 0.5 then Work;']), LINE,
    'Ratio', '=', '0.5', _(R_FLOAT_BEFORE, ['Ratio = 0.5', '+']));
  AssertRefused(Wrap(['  if Ratio = Other * 2 then Work;']), LINE,
    'Ratio', '=', 'Other', _(R_FLOAT_AFTER, ['Ratio = Other', '*']));
  // '1e-9' meldet der Detektor als '1e'.
  AssertRefused(Wrap(['  if Ratio = 1e-9 then Work;']), LINE,
    'Ratio', '=', '1e', _(R_FLOAT_AFTER, ['Ratio = 1e', '-']));
  AssertRefused(Wrap(['  if Ratio = Arr[0] then Work;']), LINE,
    'Ratio', '=', 'Arr', _(R_FLOAT_AFTER, ['Ratio = Arr', '[']));
  AssertRefused(Wrap(['  if Obj.Ratio = 0.5 then Work;']), LINE,
    'Ratio', '=', '0.5', _(R_FLOAT_BEFORE, ['Ratio = 0.5', '.']));
end;

procedure TTestRdxFloatEqualityFix.MovedLine_NoHelp;
var
  Src, R : string;
begin
  Src := Wrap(['  if Ratio = 0.5 then Work;']);
  AssertRefused(Src, LINE + 1, 'Ratio', '=', '0.5',
    MsgMovedSuffix(_(R_FLOAT_MOVED, ['Ratio = 0.5'])));
  AssertRefused(Src, 99, 'Ratio', '=', '0.5',
    MsgMovedSuffix(_(R_FLOAT_MOVED, ['Ratio = 0.5'])));
  AssertRefused(Src, 0, 'Ratio', '=', '0.5',
    MsgMovedSuffix(_(R_FLOAT_MOVED, ['Ratio = 0.5'])));
  // Andere Zahl bzw. anderer Operator als in der Meldung.
  AssertRefused(Src, LINE, 'Ratio', '=', '0.25',
    MsgMovedSuffix(_(R_FLOAT_MOVED, ['Ratio = 0.25'])));
  AssertRefused(Src, LINE, 'Ratio', '<>', '0.5',
    MsgMovedSuffix(_(R_FLOAT_MOVED, ['Ratio <> 0.5'])));
  // Die Zahl im Quelltext ist laenger ('0.55' fuer die Meldung '0.5').
  Assert.AreEqual('', PlanAt(Wrap(['  if Ratio = 0.55 then Work;']), LINE,
    Msg('Ratio', '=', '0.5'), R));
  Assert.AreEqual(MsgMovedSuffix(_(R_FLOAT_MOVED, ['Ratio = 0.5'])), R);
end;

procedure TTestRdxFloatEqualityFix.CommentOrString_NoHelp;
begin
  AssertRefused(Wrap(['  // if Ratio = 0.5 then Work;']), LINE, 'Ratio', '=',
    '0.5', MsgMovedSuffix(_(R_FLOAT_MOVED, ['Ratio = 0.5'])));
  AssertRefused(Wrap(['  S := ''Ratio = 0.5'';']), LINE, 'Ratio', '=', '0.5',
    MsgMovedSuffix(_(R_FLOAT_MOVED, ['Ratio = 0.5'])));
  AssertRefused(Wrap(['  if Ratio {x} = 0.5 then Work;']), LINE, 'Ratio',
    '=', '0.5', _(R_FLOAT_COMMENT, ['Ratio = 0.5']));
  // Ein Kommentar dahinter bleibt stehen.
  Assert.AreEqual(Wrap(['  if SameValue(Ratio, 0.5) then Work; // Ratio = 0.5']),
    Applied(Wrap(['  if Ratio = 0.5 then Work; // Ratio = 0.5']), LINE,
      'Ratio', '=', '0.5'));
end;

procedure TTestRdxFloatEqualityFix.TwiceOnLine_NoHelp;
begin
  AssertRefused(Wrap(['  if (Ratio = 0.5) or (Ratio = 0.5) then Work;']),
    LINE, 'Ratio', '=', '0.5', _(R_FLOAT_MANY, ['Ratio = 0.5']));
end;

procedure TTestRdxFloatEqualityFix.GuardIdiom_NoHelp;
begin
  // 'if X = 0 then X := ...' setzt einen Vorgabewert - exakt gewollt.
  AssertRefused(Wrap(['  if Ratio = 0 then Ratio := 1;']), LINE, 'Ratio',
    '=', '0', _(R_FLOAT_GUARD, ['Ratio = 0']));
  AssertRefused(Wrap(['  if 0 = Ratio then Ratio := 1;']), LINE, '0', '=',
    'Ratio', _(R_FLOAT_GUARD, ['0 = Ratio']));
  // Gegenproben: eine andere Variable im Zweig, ein Vergleich ohne Null.
  Assert.AreEqual(Wrap(['  if IsZero(Ratio) then Other := 1;']),
    Applied(Wrap(['  if Ratio = 0 then Other := 1;']), LINE, 'Ratio', '=',
      '0'));
  Assert.AreEqual(Wrap(['  if SameValue(Ratio, 0.5) then Ratio := 1;']),
    Applied(Wrap(['  if Ratio = 0.5 then Ratio := 1;']), LINE, 'Ratio', '=',
      '0.5'));
end;

procedure TTestRdxFloatEqualityFix.TolerantBranch_NoHelp;
begin
  // TES5Edit (rwE29): fast-null Werte werden auf exakt 0 normalisiert - mit
  // 'not IsZero(Ratio)' uebersprange der Zweig genau sie.
  AssertRefused(Wrap(['  if Ratio <> 0.0 then',
    '    if SingleSameValue(Ratio, 0.0) then', '      Ratio := 0.0;']), LINE,
    'Ratio', '<>', '0.0', _(R_FLOAT_TOLERANT, ['Ratio <> 0.0', LINE + 1]));
  // Im begin-Block, IsZero, auch hinter einem Aufruf davor.
  AssertRefused(Wrap(['  if Ratio = Other then', '  begin', '    Work;',
    '    if not IsZero(Other) then Exit;', '  end;']), LINE, 'Ratio', '=',
    'Other', _(R_FLOAT_TOLERANT, ['Ratio = Other', LINE + 3]));
  // Gegenproben: der Toleranzvergleich steht hinter dem Zweig (nach ';'
  // bzw. im else-Zweig) oder nennt eine andere Variable - die Hilfe bleibt.
  Assert.AreEqual(Wrap(['  if not IsZero(Ratio) then Work;',
    '  if SameValue(Ratio, 0.0) then Work;']),
    Applied(Wrap(['  if Ratio <> 0.0 then Work;',
      '  if SameValue(Ratio, 0.0) then Work;']), LINE, 'Ratio', '<>', '0.0'));
  Assert.AreEqual(Wrap(['  if IsZero(Ratio) then Work',
    '  else if IsZero(Ratio) then Work;']),
    Applied(Wrap(['  if Ratio = 0 then Work',
      '  else if IsZero(Ratio) then Work;']), LINE, 'Ratio', '=', '0'));
  Assert.AreEqual(Wrap(['  if not IsZero(Ratio) then',
    '    if IsZero(Other) then Work;']),
    Applied(Wrap(['  if Ratio <> 0 then', '    if IsZero(Other) then Work;']),
      LINE, 'Ratio', '<>', '0'));
end;

procedure TTestRdxFloatEqualityFix.OwnFunction_NoHelp;
var
  Src : string;
begin
  // Eine eigene Routine SameValue bzw. ein eigener Bezeichner IsZero.
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'function SameValue(A: Double; B: Double): Boolean;', 'begin',
    '  Result := False;', 'end;',
    'procedure Foo(Ratio: Double; Other: Double);', 'begin',
    '  if Ratio = 0.5 then Work;', 'end;', 'end.']), 10, 'Ratio', '=', '0.5',
    _(R_FLOAT_OWN, ['SameValue']));
  AssertRefused(Join(['unit t;', 'interface', 'var', '  IsZero: Boolean;',
    'implementation', 'procedure Foo(Ratio: Double; Other: Double);', 'begin',
    '  if Ratio = 0 then Work;', 'end;', 'end.']), 8, 'Ratio', '=', '0',
    _(R_FLOAT_OWN, ['IsZero']));
  // Gegenprobe: ein Aufruf von SameValue deklariert nichts.
  Src := Wrap(['  Ok := SameValue(A, B);', '  if Ratio = 0.5 then Work;']);
  Assert.AreEqual(Wrap(['  Ok := SameValue(A, B);',
    '  if SameValue(Ratio, 0.5) then Work;']),
    Applied(Src, LINE + 1, 'Ratio', '=', '0.5'));
end;

procedure TTestRdxFloatEqualityFix.WithBefore_NoHelp;
var
  Src : string;
begin
  AssertRefused(Wrap(['  with Pt do', '    if Ratio = 0.5 then Work;']),
    LINE + 1, 'Ratio', '=', '0.5', _(R_FLOAT_WITH, ['SameValue']));
  AssertRefused(Wrap(['  with Pt do if Ratio = 0 then Work;']), LINE,
    'Ratio', '=', '0', _(R_FLOAT_WITH, ['IsZero']));
  // Gegenprobe: das with steht in einer anderen Routine davor.
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure Bar;',
    'begin', '  with Pt do Work;', 'end;',
    'procedure Foo(Ratio: Double; Other: Double);', 'begin',
    '  if Ratio = 0.5 then Work;', 'end;', 'end.']);
  Assert.AreEqual(StringReplace(Src, 'Ratio = 0.5', 'SameValue(Ratio, 0.5)',
    []), Applied(Src, 10, 'Ratio', '=', '0.5'));
end;

procedure TTestRdxFloatEqualityFix.DeclarationList_NoHelp;
var
  Src : string;
begin
  // Eine Aufzaehlung mit Werten - keine Bedingung, auch wenn Ratio dort wie
  // eine Float-Variable heisst.
  Src := Join(['unit t;', 'interface', 'type',
    '  TFoo = (Ratio = 0, Other = 1);', 'implementation', 'end.']);
  AssertRefused(Src, 4, 'Ratio', '=', '0', _(R_FLOAT_LIST, ['Ratio = 0']));
  AssertRefused(Src, 4, 'Other', '=', '1', _(R_FLOAT_LIST, ['Other = 1']));
end;

procedure TTestRdxFloatEqualityFix.Message_NoHelp;
var
  L, Op, R, Reason : string;
begin
  Assert.AreEqual('', PlanAt(Wrap(['  if Ratio = 0.5 then Work;']), LINE, 'x',
    Reason));
  Assert.AreEqual(_(R_FLOAT_MSG), Reason);
  // Nur '=' und '<>' meldet der Detektor.
  Assert.AreEqual('', PlanAt(Wrap(['  if Ratio >= 0.5 then Work;']), LINE,
    Msg('Ratio', '>=', '0.5'), Reason));
  Assert.AreEqual(_(R_FLOAT_MSG), Reason);
  AssertRefused(Wrap(['  if 0 = 0.5 then Work;']), LINE, '0', '=', '0.5',
    _(R_FLOAT_NO_VAR, ['0 = 0.5']));
  // Die Teile der Meldung und der Name fuer den Menuetext.
  Assert.IsTrue(TRdxFloatEqualityFix.Operands(Msg('Ratio', '<>', '0.0'), L,
    Op, R));
  Assert.AreEqual('Ratio', L);
  Assert.AreEqual('<>', Op);
  Assert.AreEqual('0.0', R);
  Assert.AreEqual(CALL_IS_ZERO,
    TRdxFloatEqualityFix.CallName(Msg('Ratio', '<>', '0.0')));
  Assert.AreEqual(CALL_SAME_VALUE,
    TRdxFloatEqualityFix.CallName(Msg('Ratio', '=', '0.5')));
  Assert.AreEqual('', TRdxFloatEqualityFix.CallName('x'));
end;

// ---- Typbeweis und Kontext ----

procedure TTestRdxFloatEqualityFix.TypeReason_ProvenFloats;
begin
  Assert.AreEqual('', TRdxFloatEqualityFix.TypeReason('Ratio', 'double',
    '0.5', ''));
  Assert.AreEqual('', TRdxFloatEqualityFix.TypeReason('Ratio', 'real',
    'Other', 'extended'));
  Assert.AreEqual('', TRdxFloatEqualityFix.TypeReason('S', 'Single', 'T',
    'single'), 'Single gegen Single');
  // IsZero hat ein Argument - eine Single-Seite ist dort eindeutig.
  Assert.AreEqual('', TRdxFloatEqualityFix.TypeReason('S', 'single', '0',
    ''));
  Assert.AreEqual('', TRdxFloatEqualityFix.TypeReason('0.0', '', 'S',
    'single'));
end;

procedure TTestRdxFloatEqualityFix.TypeReason_Refused;
begin
  Assert.AreEqual(_(R_FLOAT_UNKNOWN, ['Ratio']),
    TRdxFloatEqualityFix.TypeReason('Ratio', '', '0.5', ''));
  Assert.AreEqual(_(R_FLOAT_CURRENCY, ['Price']),
    TRdxFloatEqualityFix.TypeReason('Price', 'currency', '0.5', ''));
  Assert.AreEqual(_(R_FLOAT_NOT_FLOAT, ['F', 'tfloat']),
    TRdxFloatEqualityFix.TypeReason('Ratio', 'double', 'F', 'tfloat'));
  Assert.AreEqual(_(R_FLOAT_SINGLE, ['S', '0.5']),
    TRdxFloatEqualityFix.TypeReason('S', 'single', '0.5', ''));
  Assert.AreEqual(_(R_FLOAT_SINGLE, ['S', 'D']),
    TRdxFloatEqualityFix.TypeReason('D', 'double', 'S', 'single'));
end;

procedure TTestRdxFloatEqualityFix.ContextReason_LowAndWith;
begin
  Assert.AreEqual('', TRdxFloatEqualityFix.ContextReason(False, False,
    Msg('Ratio', '=', '0.5')));
  Assert.AreEqual(_(R_FLOAT_LOW), TRdxFloatEqualityFix.ContextReason(True,
    False, Msg('Ratio', '=', '0.5')));
  Assert.AreEqual(_(R_FLOAT_LOW), TRdxFloatEqualityFix.ContextReason(True,
    True, Msg('Ratio', '=', '0.5')));
  Assert.AreEqual(_(R_FLOAT_WITH, ['IsZero']),
    TRdxFloatEqualityFix.ContextReason(False, True, Msg('Ratio', '=', '0')));
end;

{ ---- Realwelt-Test rwE30 (Fix-Runde 2) ---- }

procedure TTestRdxFloatEqualityFix.OldCompilerBranch_NoHelp;
var
  R, Src : string;
begin
  // jvcl JvSimpleXml.pas:252: nur Delphi 5 und aelter sehen den Zweig, dort
  // gibt es Math.IsZero nicht.
  Assert.AreEqual('', PlanAt(Wrap(['{$IFNDEF COMPILER6_UP}',
    '  if Ratio = 0 then Work;', '{$ENDIF}']), LINE + 1,
    Msg('Ratio', '=', '0'), R));
  Assert.IsTrue(Pos('{$IFNDEF COMPILER6_UP}', R) > 0, R);
  // Gegenprobe: der Zweig fuer moderne Compiler.
  Src := Wrap(['{$IFDEF COMPILER6_UP}', '  if Ratio = 0 then Work;',
    '{$ENDIF}']);
  Assert.AreEqual(StringReplace(Src, 'Ratio = 0', 'IsZero(Ratio)', []),
    Applied(Src, LINE + 1, 'Ratio', '=', '0'));
end;

procedure TTestRdxFloatEqualityFix.WithClosedBefore_Help;
var
  Src : string;
begin
  // issrc Resample.pas:65, Img32.SVG.Reader.pas:1398: die with-Anweisungen
  // der Routine sind vor dem Vergleich zu Ende.
  Src := Wrap(['  with Pt do', '  begin', '    X := 1;', '  end;',
    '  with Pt do Y := 2;', '  if Ratio = 0.5 then Work;']);
  Assert.AreEqual(StringReplace(Src, 'Ratio = 0.5', 'SameValue(Ratio, 0.5)',
    []), Applied(Src, LINE + 5, 'Ratio', '=', '0.5'));
end;

const
  // Img32.SVG.Path.pas: TArcInfo, ein Record nur mit Feldern.
  ARC_UNIT: array[0..18] of string = ('unit t;', 'interface', 'type',
    '  TArcInfo = record', '    rec         : TRectD;',
    '    startPos    : TPointD;', '    rectAngle   : double;',
    '    sweepClockW : Boolean;', '  end;', 'implementation',
    'procedure Foo(const fArcInfo: TArcInfo; Ratio: Double);', 'begin',
    '  with fArcInfo do', '  begin', '    if rectAngle <> 0 then Work;',
    '    if Ratio = 0.5 then Work;', '  end;', 'end;', 'end.');

procedure TTestRdxFloatEqualityFix.WithFieldRecord_Help;
var
  Src, LT, RT : string;
  Map         : TRdxCodeMap;
  InWith      : Boolean;
begin
  Src := Join(ARC_UNIT);
  Assert.AreEqual(StringReplace(Src, 'rectAngle <> 0', 'not IsZero(rectAngle)',
    []), Applied(Src, 15, 'rectAngle', '<>', '0'));
  Assert.AreEqual(StringReplace(Src, 'Ratio = 0.5', 'SameValue(Ratio, 0.5)',
    []), Applied(Src, 16, 'Ratio', '=', '0.5'), 'kein Feld - bindet aussen');
  // Der Adapter bekommt den Feldtyp bzw. nichts (dann DeclaredTypeOf).
  Map := NewMap(Src);
  try
    TRdxFloatEqualityFix.WithMemberTypes(Map, 15,
      Msg('rectAngle', '<>', '0'), InWith, LT, RT);
    Assert.IsTrue(InWith);
    Assert.AreEqual('double', LT);
    Assert.AreEqual('', RT);
    TRdxFloatEqualityFix.WithMemberTypes(Map, 16, Msg('Ratio', '=', '0.5'),
      InWith, LT, RT);
    Assert.IsTrue(InWith);
    Assert.AreEqual('', LT);
  finally
    Map.Free;
  end;
end;

procedure TTestRdxFloatEqualityFix.WithOtherTargets_NoHelp;
var
  Src : string;
begin
  // Ein Record mit Methode, ein Feld namens IsZero, ein Pfad als Ziel, ein
  // Klassentyp: das with kann an mehr als Felder binden.
  Src := StringReplace(Join(ARC_UNIT), '    sweepClockW : Boolean;',
    '    function Area: Double;', []);
  AssertRefused(Src, 15, 'rectAngle', '<>', '0', _(R_FLOAT_WITH, ['IsZero']));
  Src := StringReplace(Join(ARC_UNIT), '    sweepClockW : Boolean;',
    '    IsZero : Boolean;', []);
  // (das Feld IsZero faengt schon die Sperre 'eigenes IsZero')
  AssertRefused(Src, 15, 'rectAngle', '<>', '0', _(R_FLOAT_OWN, ['IsZero']));
  Src := StringReplace(Join(ARC_UNIT), '  with fArcInfo do',
    '  with Self.fArcInfo do', []);
  AssertRefused(Src, 15, 'rectAngle', '<>', '0', _(R_FLOAT_WITH, ['IsZero']));
  Src := StringReplace(Join(ARC_UNIT), '  TArcInfo = record',
    '  TArcInfo = class', []);
  AssertRefused(Src, 15, 'rectAngle', '<>', '0', _(R_FLOAT_WITH, ['IsZero']));
end;

procedure TTestRdxFloatEqualityFix.LocalType_NestedParam;
var
  Src : string;
  Map : TRdxCodeMap;
begin
  // jcl JclGraphics.pas:822: SinC verdeckt den gleichnamigen Parameter.
  Src := Join(['unit t;', 'interface', 'implementation',
    'function Lanczos3Filter(Value: Double): Single;',
    '  function SinC(Value: Single): Single;', '  begin',
    '    if Value <> 0.0 then Result := Value', '    else Result := 1;',
    '  end;', 'begin', '  Result := SinC(Value);', 'end;', 'end.']);
  Map := NewMap(Src);
  try
    Assert.AreEqual('single', TRdxFloatEqualityFix.LocalType(Map, 7, 'Value'));
    Assert.AreEqual('double', TRdxFloatEqualityFix.LocalType(Map, 11, 'Value'));
    Assert.AreEqual('', TRdxFloatEqualityFix.LocalType(Map, 7, 'Other'));
  finally
    Map.Free;
  end;
end;

procedure TTestRdxFloatEqualityFix.TypeReason_SingleWithInteger;
begin
  // CEF4Delphi uCEFBufferPanel.pas:1675 'SameValue(TempScale, 1)', Single:
  // eine ganze Zahl waehlt die Single-Ueberladung.
  Assert.AreEqual('', TRdxFloatEqualityFix.TypeReason('TempScale', 'single',
    '1', ''));
  Assert.AreEqual('', TRdxFloatEqualityFix.TypeReason('100', '', 'S',
    'single'));
  // Gegenprobe: eine Zahl mit Punkt bleibt gesperrt (TypeReason_Refused).
  Assert.AreEqual(_(R_FLOAT_SINGLE, ['S', '1.0']),
    TRdxFloatEqualityFix.TypeReason('S', 'single', '1.0', ''));
end;

{$IFNDEF FPC}

{ ---- Adapter und Detektor ---- }

const
  // Der Hinweis woertlich (R_FLOATEQ_HINT ist tabellen-intern in
  // uRdxFixTable; der Adapter PlanFloatEquality setzt ihn vor AppendUses)
  // - seit Charge G7 die deutsche Fassung aus de.po, mit echtem Umlaut.
  R_FLOATEQ_HINT = 'vergleicht jetzt mit Toleranz (Standard-Epsilon von '
    + 'System.Math) statt exakt - ein gewollt exakter Vergleich (Schalter- '
    + 'oder Sentinelwert) '#$00E4'ndert damit seine Bedeutung';
  // Wie Wrap, mit 'uses System.Math;' - der Rumpf beginnt auf Zeile 7.
  DLINE = 7;

function DWrap(const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation',
    'uses System.Math;', 'procedure Foo(Ratio: Double; Other: Double);',
    'begin']) + #13#10 + Join(ABody) + #13#10 + Join(['end;', 'end.']);
end;

// Die Funde der Art SCA144 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TFloatEqualityDetector.AnalyzeUnit(Root, Path, Results);
end;

// Dasselbe in der Form TDetectFunc (FixAllWith).
function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_floateq_', ASource, AKind, RunDetector);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectKind(ASource, fkFloatEquality);
end;

// Die Hilfe fuer einen Fund ueber den Einstieg der Tabelle
// (TRdxFixTable.FixFor, Adapter PlanFloatEquality); AOpen: mit
// geoeffnetem Quellstellen-Dienst. Eigener Lauf statt PlanFixIn
// (uTestRdxDetectorKit): der Fund braucht die Konfidenz (fcLow) und einen
// Lauf ohne Datei.
function PlanSeen(const ASource: string; const ASeen: TSeen;
  AConfidence: TFindingConfidence; AOpen: Boolean): TRdxFixOutcome;
var
  SL     : TStringList;
  Places : TSourcePlaces;
  F      : TLeakFinding;
begin
  SL := TStringList.Create;
  Places := nil;
  F := nil;
  try
    Places := TSourcePlaces.Create;
    F := TLeakFinding.New('t.pas', '', ASeen.Line, ASeen.Msg, fkFloatEquality);
    F.Confidence := AConfidence;
    SL.Text := ASource;
    if AOpen then
    begin
      Assert.IsTrue(Places.OpenSource('t.pas', ASource), 'OpenSource');
      Result := TRdxFixTable.FixFor(Places, SL, F,
        TRdxRecipeRunner.UsesNamesOf(Places));
    end
    else
      Result := TRdxFixTable.FixFor(nil, SL, F, nil);
  finally
    F.Free;
    Places.Free;
    SL.Free;
  end;
end;

// Die Hilfe fuer den ersten Fund des Detektors.
function PlanFirst(const ASource: string): TRdxFixOutcome;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet einen Fund');
  Result := PlanSeen(ASource, Seen[0], fcHigh, True);
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt (FixAllWith: PlanFixIn mit geoeffnetem Quellstellen-Dienst und
// der Konfidenz der Art, fcHigh - wie PlanFirst).
function FixAll(const ASource: string): string;
begin
  Result := FixAllWith(ASource, fkFloatEquality, DetectKind);
end;

procedure TTestRdxFloatEqualityDetector.Detector_ReportsLineAndOperands;
var
  Seen     : TArray<TSeen>;
  L, Op, R : string;
begin
  Seen := Detect(DWrap(['  if Ratio = 0.5 then Work;']));
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(DLINE, Seen[0].Line, 'Zeile des Vergleichs');
  Assert.IsTrue(TRdxFloatEqualityFix.Operands(Seen[0].Msg, L, Op, R),
    Seen[0].Msg);
  Assert.AreEqual('Ratio', L);
  Assert.AreEqual('=', Op);
  Assert.AreEqual('0.5', R);
end;

procedure TTestRdxFloatEqualityDetector.Detector_RoundTrip;
var
  Fixed : string;
begin
  Fixed := FixAll(DWrap(['  if Ratio = 0.5 then Work;',
    '  while Ratio <> 0 do Work;']));
  Assert.AreEqual(DWrap(['  if SameValue(Ratio, 0.5) then Work;',
    '  while not IsZero(Ratio) do Work;']), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxFloatEqualityDetector.Detector_AddsMathToUses;
var
  Src, Fixed : string;
  O          : TRdxFixOutcome;
begin
  Src := Join(['unit t;', 'interface', 'implementation',
    'uses System.SysUtils;', 'procedure Foo(Ratio: Double; Other: Double);',
    'begin', '  if Ratio = Other then Work;', 'end;', 'end.']);
  O := PlanFirst(Src);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(2, Length(O.Edits), 'Vergleich und uses');
  Assert.AreEqual(R_FLOATEQ_HINT + ' + uses System.Math', O.Hint);
  Fixed := Apply(Src, O.Edits);
  Assert.IsTrue(Pos('if SameValue(Ratio, Other) then', Fixed) > 0, Fixed);
  Assert.IsTrue(Pos('System.Math', Fixed) > 0, Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxFloatEqualityDetector.Detector_TwoOnLine_BothFixed;
var
  Src : string;
begin
  Src := DWrap(['  if (Ratio = 0.5) and (Other <> 0) then Work;']);
  Assert.AreEqual<Integer>(2, Length(Detect(Src)), 'zwei Funde');
  Assert.AreEqual(
    DWrap(['  if (SameValue(Ratio, 0.5)) and (not IsZero(Other)) then Work;']),
    FixAll(Src));
end;

procedure TTestRdxFloatEqualityDetector.Detector_CatalogExample_Fixed;
var
  Meta  : TRuleMeta;
  Src   : string;
  Fixed : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkFloatEquality);
  Assert.IsTrue(Pos('Ratio = 0.5', Meta.BadExample) > 0, Meta.BadExample);
  // Der Katalog deutet den Rumpf mit '...' an - dort beginnt er.
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    StringReplace(CatalogText(Meta.BadExample), '...', 'begin',
      [rfReplaceAll]), 'end;', 'end.']);
  Assert.AreEqual<Integer>(1, Length(Detect(Src)),
    'der Detektor meldet das Beispiel');
  Fixed := FixAll(Src);
  Assert.IsTrue(Pos('if SameValue(Ratio, 0.5) then', Fixed) > 0, Fixed);
  Assert.IsTrue(Pos('Math', Fixed) > 0, 'uses ergaenzt: ' + Fixed);
end;

procedure TTestRdxFloatEqualityDetector.Detector_SubExpression_NoHelp;
var
  O : TRdxFixOutcome;
begin
  // Der Detektor meldet den Teilausdruck 'Ratio = 0.5' aus 'Other + Ratio'.
  O := PlanFirst(DWrap(['  if Other + Ratio = 0.5 then Work;']));
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_FLOAT_BEFORE, ['Ratio = 0.5', '+']), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

procedure TTestRdxFloatEqualityDetector.Detector_Currency_NoHelp;
var
  O : TRdxFixOutcome;
begin
  O := PlanFirst(Join(['unit t;', 'interface', 'implementation',
    'uses System.Math;', 'procedure Foo(Price: Currency);', 'begin',
    '  if Price = 0.5 then Work;', 'end;', 'end.']));
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_FLOAT_CURRENCY, ['Price']), O.Reason);
end;

procedure TTestRdxFloatEqualityDetector.Detector_Guard_NoHelp;
var
  O : TRdxFixOutcome;
begin
  // Der Detektor meldet das Waechter-Idiom herabgestuft (fcLow); der Planer
  // erkennt es am Text - TSeen traegt die Stufe nicht.
  O := PlanFirst(DWrap(['  if Ratio = 0 then Ratio := 1;']));
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_FLOAT_GUARD, ['Ratio = 0']), O.Reason);
end;

procedure TTestRdxFloatEqualityDetector.Adapter_HintAndName;
var
  O : TRdxFixOutcome;
begin
  O := PlanFirst(DWrap(['  if Ratio = 0.5 then Work;']));
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual(CALL_SAME_VALUE, O.Name);
  Assert.AreEqual(R_FLOATEQ_HINT, O.Hint, 'Math schon da - kein uses');
  Assert.AreEqual<Integer>(1, Length(O.Edits));
  O := PlanFirst(DWrap(['  if Ratio = 0 then Work;']));
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual(CALL_IS_ZERO, O.Name);
end;

procedure TTestRdxFloatEqualityDetector.Adapter_LowConfidence_NoHelp;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  Src := DWrap(['  if Ratio = 0.5 then Work;']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen));
  O := PlanSeen(Src, Seen[0], fcLow, True);
  Assert.IsFalse(O.Enabled, 'herabgestuft - keine Hilfe');
  Assert.AreEqual(_(R_FLOAT_LOW), O.Reason);
  O := PlanSeen(Src, Seen[0], fcMedium, True);
  Assert.IsTrue(O.Enabled, O.Reason);
end;

procedure TTestRdxFloatEqualityDetector.Adapter_NestedRoutine_ParamProven;
var
  O : TRdxFixOutcome;
begin
  // In einer verschachtelten Routine liefert DeclaredTypeOf '' - seit
  // rwE30 beweist der Text den Parameter ('function SinC(Value: Single)'
  // in Lanczos3Filter, JclGraphics.pas:822). Bis dahin: keine Hilfe.
  O := PlanFirst(Join(['unit t;', 'interface', 'implementation',
    'uses System.Math;', 'procedure Foo;', '  procedure Inner(Ratio: Double);',
    '  begin', '    if Ratio = 0.5 then Work;', '  end;', 'begin',
    '  Inner(1);', 'end;', 'end.']));
  Assert.IsTrue(O.Enabled, O.Reason);
  // Gegenprobe: ein Name, den keine umschliessende Routine deklariert,
  // bleibt unbewiesen. Die Deklaration in der Nachbar-Routine Other braucht
  // der Detektor (er sammelt Float-Variablen nur nach 'Name: Double' -
  // ohne sie gaebe es keinen Fund und PlanFirst schluege fehl, Review
  // e/HilfeFixI); Inner sieht sie nicht.
  O := PlanFirst(Join(['unit t;', 'interface', 'implementation',
    'uses System.Math;', 'procedure Other(Ratio: Double);', 'begin',
    'end;', 'procedure Foo;', '  procedure Inner;',
    '  begin', '    if Ratio = 0.5 then Work;', '  end;', 'begin',
    '  Inner;', 'end;', 'end.']));
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_FLOAT_UNKNOWN, ['Ratio']), O.Reason);
end;

procedure TTestRdxFloatEqualityDetector.Adapter_NoFile_NoHelp;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  Src := DWrap(['  if Ratio = 0.5 then Work;']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen));
  O := PlanSeen(Src, Seen[0], fcHigh, False);
  Assert.IsFalse(O.Enabled);
  Assert.AreEqual(MsgNoFileOpen, O.Reason);
  Assert.AreEqual(CALL_SAME_VALUE, O.Name, 'Name auch ohne Datei');
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxFloatEqualityFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxFloatEqualityDetector);
  {$ENDIF}

end.
