unit uTestRdxContextIf;

// Code-Aktionen ohne Fund C7/C8 (Charge C78, 2026-10-27; Wettbewerbs-Todo
// 2026-10-23): if umkehren und Waechter-Klausel (C7), De Morgan, Vergleich
// drehen, if teilen und zusammenfuegen (C8) - ueber den Laeufer am Caret
// (uRdxContextRunner.Run), auf Text, ohne Parser (reDelphix.Test UND
// FPC-Pruefstand). Je Aktion eine Fixture: Angebot mit dem Ergebnistext
// von Hand (gegen den Vorrang von Delphi geprueft: not vor and vor or vor
// Vergleich), Sperre mit Grund, kein Kandidat = kein Eintrag (F4). Nur
// Delphi (letzte Fixture): der Menuetext ueber uRdxFixTable.ContextCaption
// - die Waechter-Klausel traegt den der Fund-Hilfe SCA018 (Dedup F2).
// Der Caret steht als CARET_MARK '{^}' im Text (uTestRdxTextKit.CaretOf).
// FPC-Mikroproben, die Original und Umbau gegeneinander rechnen: Charge
// C78, Scratchpad (nicht eingecheckt) - Ergebnis im Commit.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxCtxInvertIf = class
  public
    [Test] procedure Invert_LinesAndCaret;
    [Test] procedure Invert_Blocks;
    [Test] procedure Invert_NotRemoved;
    [Test] procedure Invert_FullParentheses;
    [Test] procedure Invert_NilFlip;
    [Test] procedure Invert_MultiLineCondition;
    [Test] procedure Invert_StringsInCondition;
    [Test] procedure Invert_RoundTrip;
    [Test] procedure Invert_DanglingElseBelongsInner;
    [Test] procedure Invert_CaseInBranch;
    [Test] procedure Invert_CommentsStay;
    [Test] procedure Invert_ElseIf_Refused;
    [Test] procedure Invert_DanglingTail_Refused;
    [Test] procedure Invert_Directive_Refused;
    [Test] procedure Invert_CondComment_Refused;
    [Test] procedure Invert_MultiLineString_Refused;
    [Test] procedure Invert_EmptyBranch_Refused;
    [Test] procedure Invert_NoCandidate_NoEntry;
    [Test] procedure Invert_Unreadable_NoEntry;
  end;

  [TestFixture]
  TTestRdxCtxGuard = class
  public
    [Test] procedure Guard_LastIf;
    [Test] procedure Guard_CaretOnThen;
    [Test] procedure Guard_SameAsSca018;
    [Test] procedure Guard_NotLast_NoEntry;
    [Test] procedure Guard_InnerIf_NoEntry;
    [Test] procedure Guard_ResultNotSet_Refused;
    [Test] procedure Guard_Directive_Refused;
  end;

  [TestFixture]
  TTestRdxCtxDeMorgan = class
  public
    [Test] procedure DeMorgan_NotAnd;
    [Test] procedure DeMorgan_NotOrComparisons;
    [Test] procedure DeMorgan_CaretOnNot;
    [Test] procedure DeMorgan_DoubleNegation;
    [Test] procedure DeMorgan_InsideAndKeepsParens;
    [Test] procedure DeMorgan_Reverse;
    [Test] procedure DeMorgan_WhileUntilThreeTerms;
    [Test] procedure DeMorgan_StringOperand;
    [Test] procedure DeMorgan_MultiLine;
    [Test] procedure DeMorgan_Bitwise_NoEntry;
    [Test] procedure DeMorgan_Mixed_Refused;
    [Test] procedure DeMorgan_Comment_Refused;
  end;

  [TestFixture]
  TTestRdxCtxFlip = class
  public
    [Test] procedure Flip_Less;
    [Test] procedure Flip_AllOperators;
    [Test] procedure Flip_Assignment;
    [Test] procedure Flip_InParentheses;
    [Test] procedure Flip_PureIntrinsic;
    [Test] procedure Flip_Literals;
    [Test] procedure Flip_RoundTrip;
    [Test] procedure Flip_Call_Refused;
    [Test] procedure Flip_ShadowedIntrinsic_Refused;
    [Test] procedure Flip_AsAndComment_Refused;
    [Test] procedure Flip_NoCandidate_NoEntry;
  end;

  [TestFixture]
  TTestRdxCtxSplitIf = class
  public
    [Test] procedure Split_Simple;
    [Test] procedure Split_Block;
    [Test] procedure Split_SingleLine;
    [Test] procedure Split_ThreeTerms;
    [Test] procedure Split_Comparisons;
    [Test] procedure Split_MergeRoundTrip;
    [Test] procedure Split_Else_Refused;
    [Test] procedure Split_BoolEval_Refused;
    [Test] procedure Split_Comment_Refused;
    [Test] procedure Split_NotTopLevel_NoEntry;
  end;

  [TestFixture]
  TTestRdxCtxMergeIf = class
  public
    [Test] procedure Merge_Simple;
    [Test] procedure Merge_Block;
    [Test] procedure Merge_BeginOnThenLine;
    [Test] procedure Merge_Parentheses;
    [Test] procedure Merge_AndChainSingleLine;
    [Test] procedure Merge_CaretOnThen;
    [Test] procedure Merge_OuterElse_Refused;
    [Test] procedure Merge_InnerElse_Refused;
    [Test] procedure Merge_BoolEval_Refused;
    [Test] procedure Merge_Comment_Refused;
    [Test] procedure Merge_NoCandidate_NoEntry;
  end;

  [TestFixture]
  TTestRdxCtxIfTexts = class
  public
    [Test] procedure Captions_German;
    [Test] procedure Hints_German;
    [Test] procedure Order_DeMorganBeforeSplit;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxCtxIfCaption = class
  public
    [Test] procedure Caption_GuardLikeSca018;
    [Test] procedure Caption_OthersFromRunner;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  uSCAConsts,            // fkDeepNesting
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // CaptionFor, ContextCaption
  {$ENDIF}
  uFindingActions,       // TEditorContext
  uRdxBufferMath, uRdxCodeMap,
  uRdxContextRunner,
  uRdxIfFixes,           // R_IF_*
  uRdxCondFixes,         // R_CF_*
  uRdxDeepNestingFix,    // GuardClause, R_DN_*
  uRdxText,              // _
  uTestRdxTextKit;       // Join, Apply, InProc, CaretOf, LineOf, NewMap

// ---- Helfer ----

// Die Eintraege am Caret ALine/ACol.
function RunPos(const ASource: string;
  ALine, ACol: Integer): TArray<TRdxContextOutcome>;
var
  SL : TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Result := TRdxContextRunner.Run(SL,
      TEditorContext.At('C:\rdx_ctx_if_none\u.pas', ALine, ACol));
  finally
    SL.Free;
  end;
end;

// Dasselbe am Caret von AMarked (CARET_MARK); ASource ohne Marke.
function RunAt(const AMarked: string;
  out ASource: string): TArray<TRdxContextOutcome>;
var
  Line, Col : Integer;
begin
  ASource := AMarked;
  Assert.IsTrue(CaretOf(ASource, Line, Col), 'Caret-Marke fehlt');
  Result := RunPos(ASource, Line, Col);
end;

// Wie viele Eintraege der Art AKind in AList; der letzte in AOut.
function CountKind(const AList: TArray<TRdxContextOutcome>;
  AKind: TRdxContextKind; out AOut: TRdxContextOutcome): Integer;
var
  O : TRdxContextOutcome;
begin
  Result := 0;
  AOut := Default(TRdxContextOutcome);
  for O in AList do
    if O.Kind = AKind then
    begin
      Inc(Result);
      AOut := O;
    end;
end;

// Genau EIN Eintrag der Art AKind am Caret.
function KindAt(const AMarked: string; AKind: TRdxContextKind;
  out ASource: string): TRdxContextOutcome;
begin
  Assert.AreEqual<Integer>(1, CountKind(RunAt(AMarked, ASource), AKind,
    Result), 'ein Eintrag der Art: ' + ASource);
end;

// Der Text nach dem freigegebenen Eintrag der Art AKind.
function Fixed(const AMarked: string; AKind: TRdxContextKind): string;
var
  O   : TRdxContextOutcome;
  Src : string;
begin
  O := KindAt(AMarked, AKind, Src);
  Assert.IsTrue(O.Enabled, 'freigegeben: ' + O.Reason);
  Assert.AreEqual('', O.Reason);
  Assert.IsTrue(O.Hint <> '', 'Hinweis');
  Assert.IsFalse(O.ChangesBehavior, 'bedeutungsgleich');
  Result := Apply(Src, O.Edits);
end;

// Kein Eintrag der Art AKind am Caret.
procedure AssertNone(const AMarked: string; AKind: TRdxContextKind;
  const AWhat: string);
var
  Src : string;
  O   : TRdxContextOutcome;
begin
  Assert.AreEqual<Integer>(0, CountKind(RunAt(AMarked, Src), AKind, O),
    AWhat);
end;

// Genau ein gesperrter Eintrag der Art AKind mit dem Grund AReason.
procedure AssertRefused(const AMarked: string; AKind: TRdxContextKind;
  const AReason: string);
var
  Src : string;
  O   : TRdxContextOutcome;
begin
  O := KindAt(AMarked, AKind, Src);
  Assert.IsFalse(O.Enabled, 'gesperrt: ' + Src);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
  Assert.AreEqual('', O.Hint, 'kein Hinweis');
  Assert.AreEqual(AReason, O.Reason);
end;

// Eine Unit mit dem Kopf AHead vor interface und der Prozedur P mit dem
// Rumpf ABody.
function UnitWith(const AHead, ABody: array of string): string;
begin
  Result := Join(['unit u;']) + #13#10 + Join(AHead) + #13#10
    + Join(['interface', 'implementation', 'procedure P;', 'begin']) + #13#10
    + Join(ABody) + #13#10 + Join(['end;', 'end.']);
end;

// Der Caret auf dem ersten AWord der Zeile von ASource, die AText traegt.
function RunOnWord(const ASource, AText, AWord: string): TArray<TRdxContextOutcome>;
var
  Line : Integer;
  SL   : TStringList;
begin
  Line := LineOf(ASource, AText);
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Result := RunPos(ASource, Line, Pos(AWord, SL[Line - 1]));
  finally
    SL.Free;
  end;
end;

// Der Text nach dem Eintrag AKind am ersten AWord der Zeile mit AText.
function FixedOnWord(const ASource, AText, AWord: string;
  AKind: TRdxContextKind): string;
var
  O : TRdxContextOutcome;
begin
  Assert.AreEqual<Integer>(1, CountKind(RunOnWord(ASource, AText, AWord),
    AKind, O), 'ein Eintrag: ' + AText);
  Assert.IsTrue(O.Enabled, O.Reason);
  Result := Apply(ASource, O.Edits);
end;

{ ---- C7 if umkehren ---- }

procedure TTestRdxCtxInvertIf.Invert_LinesAndCaret;
const
  MARKS: array[0..3] of string = ('  {^}if Ready then', '  i{^}f Ready then',
    '  if{^} Ready then', '  if Ready th{^}en');
var
  M : string;
begin
  for M in MARKS do
    Assert.AreEqual(InProc(['  if not Ready then', '    Bar', '  else',
      '    Foo;']), Fixed(InProc([M, '    Foo', '  else', '    Bar;']),
      ckInvertIf), M);
end;

procedure TTestRdxCtxInvertIf.Invert_Blocks;
begin
  Assert.AreEqual(InProc(['  if not (A > 0) then', '  begin', '    Bar;',
    '    Baz;', '  end', '  else', '  begin', '    Foo;', '  end;']),
    Fixed(InProc(['  {^}if A > 0 then', '  begin', '    Foo;', '  end',
    '  else', '  begin', '    Bar;', '    Baz;', '  end;']), ckInvertIf));
end;

// 'not F' -> F, auch ohne die Klammer um die ganze Bedingung.
procedure TTestRdxCtxInvertIf.Invert_NotRemoved;
begin
  Assert.AreEqual(InProc(['  if Assigned(P) then Bar else Foo;']),
    Fixed(InProc(['  {^}if not Assigned(P) then Foo else Bar;']), ckInvertIf));
  Assert.AreEqual(InProc(['  if A and B then Bar else Foo;']),
    Fixed(InProc(['  {^}if not (A and B) then Foo else Bar;']), ckInvertIf));
  Assert.AreEqual(InProc(['  if X = 1 then Bar else Foo;']),
    Fixed(InProc(['  {^}if not (X = 1) then Foo else Bar;']), ckInvertIf));
end;

// Vorrang: 'not X > 0' hiesse '(not X) > 0' - die Negation klammert alles
// ausser einem einfachen Operanden.
procedure TTestRdxCtxInvertIf.Invert_FullParentheses;
begin
  Assert.AreEqual(InProc(['  if not ((X > 0) and Ready) then Bar else Foo;']),
    Fixed(InProc(['  {^}if (X > 0) and Ready then Foo else Bar;']),
    ckInvertIf));
  Assert.AreEqual(InProc(['  if not (Ready or Done) then Bar else Foo;']),
    Fixed(InProc(['  {^}if Ready or Done then Foo else Bar;']), ckInvertIf));
  Assert.AreEqual(InProc(['  if not (X > 0) then Bar else Foo;']),
    Fixed(InProc(['  {^}if X > 0 then Foo else Bar;']), ckInvertIf));
  Assert.AreEqual(InProc(['  if not (Ready) then Bar else Foo;']),
    Fixed(InProc(['  {^}if (Ready) then Foo else Bar;']), ckInvertIf));
  Assert.AreEqual(InProc(['  if not List[I].Visible then Bar else Foo;']),
    Fixed(InProc(['  {^}if List[I].Visible then Foo else Bar;']), ckInvertIf));
end;

// '=' <-> '<>' nur mit nil auf einer Seite.
procedure TTestRdxCtxInvertIf.Invert_NilFlip;
begin
  Assert.AreEqual(InProc(['  if P <> nil then Bar else Foo;']),
    Fixed(InProc(['  {^}if P = nil then Foo else Bar;']), ckInvertIf));
  Assert.AreEqual(InProc(['  if nil = FList.Next then Bar else Foo;']),
    Fixed(InProc(['  {^}if nil <> FList.Next then Foo else Bar;']),
    ckInvertIf));
  Assert.AreEqual(InProc(['  if not (X = 0) then Bar else Foo;']),
    Fixed(InProc(['  {^}if X = 0 then Foo else Bar;']), ckInvertIf),
    'ohne nil bleibt not (..)');
end;

procedure TTestRdxCtxInvertIf.Invert_MultiLineCondition;
begin
  Assert.AreEqual(InProc(['  if not (Ready and', '     Done) then', '    Bar',
    '  else', '    Foo;']), Fixed(InProc(['  {^}if Ready and', '     Done then',
    '    Foo', '  else', '    Bar;']), ckInvertIf));
end;

// Schluesselwoerter in Strings sind Text.
procedure TTestRdxCtxInvertIf.Invert_StringsInCondition;
begin
  Assert.AreEqual(InProc(['  if not (S = ''then'') then Bar else Foo(''else'');']),
    Fixed(InProc(['  {^}if S = ''then'' then Foo(''else'') else Bar;']),
    ckInvertIf));
  Assert.AreEqual(InProc(['  if not (S = ''a'' + #13#10) then Bar else Foo;']),
    Fixed(InProc(['  {^}if S = ''a'' + #13#10 then Foo else Bar;']),
    ckInvertIf));
end;

// Zweimal umkehren = das Original.
procedure TTestRdxCtxInvertIf.Invert_RoundTrip;
const
  BODIES: array[0..2] of string = ('  if A > 0 then Foo else Bar;',
    '  if P = nil then Foo else Bar;', '  if Ready and Done then Foo else Bar;');
var
  B, Src, Once : string;
begin
  for B in BODIES do
  begin
    Src := InProc([B]);
    Once := FixedOnWord(Src, B, 'if', ckInvertIf);
    Assert.AreNotEqual(Src, Once, B);
    Assert.AreEqual(Src, FixedOnWord(Once, '  if ', 'if', ckInvertIf), B);
  end;
end;

// Das else gehoert dem inneren if (dangling else): das aeussere hat keins.
procedure TTestRdxCtxInvertIf.Invert_DanglingElseBelongsInner;
begin
  AssertNone(InProc(['  {^}if A then if B then Foo else Bar;']), ckInvertIf,
    'aeusseres if ohne else');
  Assert.AreEqual(InProc(['  if A then if not B then Bar else Foo;']),
    Fixed(InProc(['  if A then {^}if B then Foo else Bar;']), ckInvertIf));
end;

// Das else eines case im then-Zweig gehoert dem case.
procedure TTestRdxCtxInvertIf.Invert_CaseInBranch;
begin
  Assert.AreEqual(InProc(['  if not A then Baz else case K of 1: Foo; else Bar; end;']),
    Fixed(InProc(['  {^}if A then case K of 1: Foo; else Bar; end else Baz;']),
    ckInvertIf));
end;

// Kommentare hinter then/else bleiben stehen, die Zweige tauschen.
procedure TTestRdxCtxInvertIf.Invert_CommentsStay;
begin
  Assert.AreEqual(InProc(['  if not A then // ja', '    Bar', '  else // nein',
    '    Foo;']), Fixed(InProc(['  {^}if A then // ja', '    Foo',
    '  else // nein', '    Bar;']), ckInvertIf));
end;

procedure TTestRdxCtxInvertIf.Invert_ElseIf_Refused;
begin
  AssertRefused(InProc(['  {^}if A then Foo else if B then Bar else Baz;']),
    ckInvertIf, _(R_IF_ELSE_IF));
end;

procedure TTestRdxCtxInvertIf.Invert_DanglingTail_Refused;
begin
  AssertRefused(InProc(['  {^}if A then Foo else while B do if C then Bar;']),
    ckInvertIf, _(R_IF_DANGLING));
end;

procedure TTestRdxCtxInvertIf.Invert_Directive_Refused;
begin
  AssertRefused(InProc(['  {^}if A then Foo {$IFDEF X} else Bar {$ENDIF};']),
    ckInvertIf, _(R_IF_DIRECTIVE));
end;

procedure TTestRdxCtxInvertIf.Invert_CondComment_Refused;
begin
  AssertRefused(InProc(['  {^}if A { wichtig } then Foo else Bar;']),
    ckInvertIf, _(R_IF_COND_COMMENT));
  AssertRefused(InProc(['  {^}if A // wichtig', '  then Foo else Bar;']),
    ckInvertIf, _(R_IF_COND_COMMENT));
end;

// Ein mehrzeiliger String (Delphi 12) in der Bedingung: der Leser liest
// sie nicht - gesperrt statt einer halben Bedingung in 'not (..)'.
procedure TTestRdxCtxInvertIf.Invert_MultiLineString_Refused;
begin
  AssertRefused(InProc(['  {^}if S = ''''''', '    abc', '    '''''' then Foo else Bar;']),
    ckInvertIf, _(R_IF_COND_UNREADABLE));
end;

procedure TTestRdxCtxInvertIf.Invert_EmptyBranch_Refused;
begin
  AssertRefused(InProc(['  {^}if A then else Foo;']), ckInvertIf,
    _(R_IF_EMPTY_BRANCH));
end;

procedure TTestRdxCtxInvertIf.Invert_NoCandidate_NoEntry;
begin
  AssertNone(InProc(['  {^}if A then Foo;']), ckInvertIf, 'ohne else');
  AssertNone(InProc(['  if Re{^}ady then Foo else Bar;']), ckInvertIf,
    'Caret in der Bedingung');
  AssertNone(InProc(['  if Ready then Foo else {^}Bar;']), ckInvertIf,
    'Caret im Zweig');
  AssertNone(InProc(['  X := {^}if A then 1 else 2;']), ckInvertIf,
    'bedingter Ausdruck (Delphi 13)');
  AssertNone(InProc(['  // {^}if A then Foo else Bar;']), ckInvertIf,
    'Kommentar');
end;

// Anonyme Methode im Zweig: der Leser liest es nicht - kein Eintrag.
procedure TTestRdxCtxInvertIf.Invert_Unreadable_NoEntry;
begin
  AssertNone(InProc(['  {^}if A then', '    Run(procedure begin Foo; end)',
    '  else', '    Bar;']), ckInvertIf, 'anonyme Methode');
  AssertNone(InProc(['  {^}if A then', '  L1: Foo', '  else', '    Bar;']),
    ckInvertIf, 'Marke');
end;

{ ---- C7 Waechter-Klausel ---- }

procedure TTestRdxCtxGuard.Guard_LastIf;
begin
  Assert.AreEqual(InProc(['  Prepare;', '  if not Ready then Exit;',
    '  Work;', '  More;']), Fixed(InProc(['  Prepare;', '  {^}if Ready then',
    '  begin', '    Work;', '    More;', '  end;']), ckGuardClause));
  Assert.AreEqual(InProc(['  if Assigned(P) then Exit;', '  Work;']),
    Fixed(InProc(['  {^}if not Assigned(P) then', '  begin', '    Work;',
    '  end;']), ckGuardClause));
end;

procedure TTestRdxCtxGuard.Guard_CaretOnThen;
begin
  Assert.AreEqual(InProc(['  if not (A and B) then Exit;', '  Work;']),
    Fixed(InProc(['  if A and B th{^}en', '  begin', '    Work;', '  end;']),
    ckGuardClause));
end;

// Dieselbe Ersetzung wie die Fund-Hilfe SCA018 an derselben Routine.
procedure TTestRdxCtxGuard.Guard_SameAsSca018;
var
  Src, Why : string;
  O        : TRdxContextOutcome;
  Map      : TRdxCodeMap;
  E        : TRdxEdit;
begin
  O := KindAt(InProc(['  Prepare;', '  {^}if Ready then', '  begin',
    '    if Deep then', '      Work;', '  end;']), ckGuardClause, Src);
  Map := NewMap(Src);
  try
    Assert.IsTrue(TRdxDeepNestingFix.GuardClause(Map, LineOf(Src, 'if Deep'),
      'Depth 2 (if from line 8, limit: 1)', E, Why), Why);
  finally
    Map.Free;
  end;
  Assert.AreEqual<Integer>(1, Length(O.Edits));
  Assert.AreEqual(Apply(Src, E), Apply(Src, O.Edits));
end;

procedure TTestRdxCtxGuard.Guard_NotLast_NoEntry;
begin
  AssertNone(InProc(['  {^}if Ready then', '  begin', '    Work;', '  end;',
    '  Done;']), ckGuardClause, 'Code dahinter');
  AssertNone(InProc(['  {^}if Ready then', '  begin', '    Work;', '  end',
    '  else', '  begin', '    Done;', '  end;']), ckGuardClause, 'mit else');
  AssertNone(InProc(['  {^}if Ready then Work;']), ckGuardClause,
    'ohne begin..end');
end;

procedure TTestRdxCtxGuard.Guard_InnerIf_NoEntry;
begin
  AssertNone(InProc(['  if Ready then', '  begin', '    {^}if Deep then',
    '    begin', '      Work;', '    end;', '  end;']), ckGuardClause,
    'inneres if');
end;

procedure TTestRdxCtxGuard.Guard_ResultNotSet_Refused;
var
  Src : string;
begin
  Src := Join(['unit u;', 'interface', 'implementation',
    'function F: Integer;', 'begin', '  {^}if Ready then', '  begin',
    '    Result := 1;', '  end;', 'end;', 'end.']);
  AssertRefused(Src, ckGuardClause, _(R_DN_RESULT));
end;

procedure TTestRdxCtxGuard.Guard_Directive_Refused;
begin
  AssertRefused(InProc(['  {^}if Ready then', '  begin', '    {$IFDEF D}',
    '    Work;', '    {$ENDIF}', '  end;']), ckGuardClause, _(R_DN_DIRECTIVE));
end;

{ ---- C8 De Morgan ---- }

procedure TTestRdxCtxDeMorgan.DeMorgan_NotAnd;
begin
  Assert.AreEqual(InProc(['  if (not A) or (not B) then Foo;']),
    Fixed(InProc(['  if not (A {^}and B) then Foo;']), ckDeMorgan));
end;

procedure TTestRdxCtxDeMorgan.DeMorgan_NotOrComparisons;
begin
  Assert.AreEqual(InProc(['  if (not (X > 0)) and (not Done) then Foo;']),
    Fixed(InProc(['  if not ((X > 0) {^}or Done) then Foo;']), ckDeMorgan));
end;

procedure TTestRdxCtxDeMorgan.DeMorgan_CaretOnNot;
begin
  Assert.AreEqual(InProc(['  if (not A) or (not B.Ok) then Foo;']),
    Fixed(InProc(['  if {^}not (A and B.Ok) then Foo;']), ckDeMorgan));
  AssertNone(InProc(['  if {^}not A then Foo;']), ckDeMorgan,
    'not ohne Kette');
end;

procedure TTestRdxCtxDeMorgan.DeMorgan_DoubleNegation;
begin
  Assert.AreEqual(InProc(['  if A or (not B) then Foo;']),
    Fixed(InProc(['  if not (not A {^}and B) then Foo;']), ckDeMorgan));
end;

// In einer and-Kette braucht das or-Ergebnis Klammern.
procedure TTestRdxCtxDeMorgan.DeMorgan_InsideAndKeepsParens;
begin
  Assert.AreEqual(InProc(['  if X and ((not A) or (not B)) then Foo;']),
    Fixed(InProc(['  if X and not (A {^}and B) then Foo;']), ckDeMorgan));
  Assert.AreEqual(InProc(['  if X and ((not A) and (not B)) then Foo;']),
    Fixed(InProc(['  if X and not (A {^}or B) then Foo;']), ckDeMorgan));
end;

// Ohne 'not ( )' darum: die Kette wird 'not (..)' - und zurueck.
procedure TTestRdxCtxDeMorgan.DeMorgan_Reverse;
begin
  Assert.AreEqual(InProc(['  if not ((not A) or (not B)) then Foo;']),
    Fixed(InProc(['  if A {^}and B then Foo;']), ckDeMorgan));
  Assert.AreEqual(InProc(['  if not (A and B) then Foo;']),
    Fixed(InProc(['  if (not A) {^}or (not B) then Foo;']), ckDeMorgan));
  Assert.AreEqual(InProc(['  if not (A or (X > 0)) then Foo;']),
    Fixed(InProc(['  if not A {^}and not (X > 0) then Foo;']), ckDeMorgan));
end;

procedure TTestRdxCtxDeMorgan.DeMorgan_WhileUntilThreeTerms;
begin
  Assert.AreEqual(InProc(['  while (not A) or (not B) or (not C) do Foo;']),
    Fixed(InProc(['  while not (A and B {^}and C) do Foo;']), ckDeMorgan));
  Assert.AreEqual(InProc(['  repeat', '    Foo;',
    '  until (not A) and (not B);']), Fixed(InProc(['  repeat', '    Foo;',
    '  until not (A {^}or B);']), ckDeMorgan));
end;

procedure TTestRdxCtxDeMorgan.DeMorgan_StringOperand;
begin
  Assert.AreEqual(InProc(['  if (not (S = ''and'')) or (not Ok) then Foo;']),
    Fixed(InProc(['  if not ((S = ''and'') {^}and Ok) then Foo;']),
    ckDeMorgan));
end;

procedure TTestRdxCtxDeMorgan.DeMorgan_MultiLine;
begin
  Assert.AreEqual(InProc(['  if (not Assigned(A)) or (not A.Enabled) then Foo;']),
    Fixed(InProc(['  if not (Assigned(A) {^}and', '      A.Enabled) then Foo;']),
    ckDeMorgan));
end;

// Bitweise (Operand eines Vergleichs bzw. 'X > 0 or Done' = 'X > (0 or
// Done)') und ausserhalb einer Bedingung: kein Eintrag.
procedure TTestRdxCtxDeMorgan.DeMorgan_Bitwise_NoEntry;
begin
  AssertNone(InProc(['  if (Flags {^}and Mask) <> 0 then Foo;']), ckDeMorgan,
    'Operand eines Vergleichs');
  AssertNone(InProc(['  if X > 0 {^}or Done then Foo;']), ckDeMorgan,
    'Vorrang: X > (0 or Done)');
  AssertNone(InProc(['  B := not (A {^}and C);']), ckDeMorgan,
    'Zuweisung');
  AssertNone(InProc(['  if Foo(A {^}and B) then Bar;']), ckDeMorgan,
    'Argument');
end;

procedure TTestRdxCtxDeMorgan.DeMorgan_Mixed_Refused;
begin
  AssertRefused(InProc(['  if not (A {^}or B xor C) then Foo;']), ckDeMorgan,
    _(R_CF_MIXED, ['or', 'xor']));
end;

procedure TTestRdxCtxDeMorgan.DeMorgan_Comment_Refused;
begin
  AssertRefused(InProc(['  if not (A {^}and { b } B) then Foo;']), ckDeMorgan,
    _(R_CF_COMMENT));
end;

{ ---- C8 Vergleich drehen ---- }

procedure TTestRdxCtxFlip.Flip_Less;
var
  O   : TRdxContextOutcome;
  Src : string;
begin
  Assert.AreEqual(InProc(['  if List.Count > Index then Foo;']),
    Fixed(InProc(['  if Index {^}< List.Count then Foo;']), ckFlipCompare));
  O := KindAt(InProc(['  if Index <{^} List.Count then Foo;']), ckFlipCompare,
    Src);
  Assert.AreEqual('<', O.Name, 'Menuetext');
end;

procedure TTestRdxCtxFlip.Flip_AllOperators;
const
  OPS: array[0..5] of string = ('<', '>', '<=', '>=', '=', '<>');
  MIRROR: array[0..5] of string = ('>', '<', '>=', '<=', '=', '<>');
var
  i : Integer;
begin
  for i := 0 to High(OPS) do
    Assert.AreEqual(InProc(['  if B + 1 ' + MIRROR[i] + ' A then Foo;']),
      Fixed(InProc(['  if A {^}' + OPS[i] + ' B + 1 then Foo;']),
      ckFlipCompare), OPS[i]);
end;

procedure TTestRdxCtxFlip.Flip_Assignment;
begin
  Assert.AreEqual(InProc(['  B := Y * 2 <= X;']),
    Fixed(InProc(['  B := X {^}>= Y * 2;']), ckFlipCompare));
  Assert.AreEqual(InProc(['  while Limit > I do Inc(I);']),
    Fixed(InProc(['  while I {^}< Limit do Inc(I);']), ckFlipCompare));
end;

// In einer Klammer: der Vergleich ist schon begrenzt, keine neue Klammer.
procedure TTestRdxCtxFlip.Flip_InParentheses;
begin
  Assert.AreEqual(InProc(['  if (B > A) and Ready then Foo;']),
    Fixed(InProc(['  if (A {^}< B) and Ready then Foo;']), ckFlipCompare));
end;

procedure TTestRdxCtxFlip.Flip_PureIntrinsic;
begin
  Assert.AreEqual(InProc(['  if Length(S) > I then Foo;']),
    Fixed(InProc(['  if I {^}< Length(S) then Foo;']), ckFlipCompare));
  Assert.AreEqual(InProc(['  if I <= High(A) then Foo;']),
    Fixed(InProc(['  if High(A) {^}>= I then Foo;']), ckFlipCompare));
end;

procedure TTestRdxCtxFlip.Flip_Literals;
begin
  Assert.AreEqual(InProc(['  if ''x'' = S then Foo;']),
    Fixed(InProc(['  if S {^}= ''x'' then Foo;']), ckFlipCompare));
  Assert.AreEqual(InProc(['  if P <> nil then Foo;']),
    Fixed(InProc(['  if nil {^}<> P then Foo;']), ckFlipCompare));
  Assert.AreEqual(InProc(['  if X > -1.5e3 then Foo;']),
    Fixed(InProc(['  if -1.5e3 {^}< X then Foo;']), ckFlipCompare));
end;

procedure TTestRdxCtxFlip.Flip_RoundTrip;
var
  Src, Once : string;
begin
  Src := InProc(['  if Index < List.Count then Foo;']);
  Once := FixedOnWord(Src, 'if Index', '<', ckFlipCompare);
  Assert.AreEqual(Src, FixedOnWord(Once, 'if List', '>', ckFlipCompare));
end;

procedure TTestRdxCtxFlip.Flip_Call_Refused;
begin
  AssertRefused(InProc(['  if List.IndexOf(X) {^}< 0 then Foo;']),
    ckFlipCompare, _(R_CF_CALL, ['IndexOf']));
  AssertRefused(InProc(['  if A {^}= GetValue() then Foo;']), ckFlipCompare,
    _(R_CF_CALL, ['GetValue']));
end;

procedure TTestRdxCtxFlip.Flip_ShadowedIntrinsic_Refused;
var
  Src : string;
begin
  Src := Join(['unit u;', 'interface', 'implementation',
    'function Length(const S: string): Integer;', 'begin', '  Result := 0;',
    'end;', 'procedure P;', 'begin', '  if I {^}< Length(S) then Foo;',
    'end;', 'end.']);
  AssertRefused(Src, ckFlipCompare, _(R_CF_CALL, ['Length']));
end;

procedure TTestRdxCtxFlip.Flip_AsAndComment_Refused;
begin
  AssertRefused(InProc(['  if (X as TFoo).Count {^}> 0 then Foo;']),
    ckFlipCompare, _(R_CF_CALL, ['as']));
  AssertRefused(InProc(['  if A { a } {^}< B then Foo;']), ckFlipCompare,
    _(R_CF_COMMENT));
end;

procedure TTestRdxCtxFlip.Flip_NoCandidate_NoEntry;
begin
  AssertNone(InProc(['  L := TList{^}<Integer>.Create;']), ckFlipCompare,
    'Typparameter');
  AssertNone(InProc(['  if X in [1, 2] {^}then Foo;']), ckFlipCompare,
    'Caret auf then');
  AssertNone(InProc(['  Foo(A {^}< B, C);']), ckFlipCompare,
    'Argument eines Aufrufs (keine Wurzel)');
  AssertNone(InProc(['  // if A {^}< B then Foo;']), ckFlipCompare,
    'Kommentar');
end;

{ ---- C8 if teilen ---- }

procedure TTestRdxCtxSplitIf.Split_Simple;
begin
  Assert.AreEqual(InProc(['  if A then', '    if B then', '      Foo;']),
    Fixed(InProc(['  if A {^}and B then', '    Foo;']), ckSplitIf));
end;

procedure TTestRdxCtxSplitIf.Split_Block;
begin
  Assert.AreEqual(InProc(['  if A then', '    if B then', '    begin',
    '      Foo;', '    end;']), Fixed(InProc(['  if A {^}and B then',
    '  begin', '    Foo;', '  end;']), ckSplitIf));
end;

procedure TTestRdxCtxSplitIf.Split_SingleLine;
begin
  Assert.AreEqual(InProc(['  if A then', '    if B then Foo;']),
    Fixed(InProc(['  if A {^}and B then Foo;']), ckSplitIf));
end;

// Am 'and' des Carets: links bleibt die Kette, rechts auch.
procedure TTestRdxCtxSplitIf.Split_ThreeTerms;
begin
  Assert.AreEqual(InProc(['  if A and B then', '    if C then', '      Foo;']),
    Fixed(InProc(['  if A and B {^}and C then', '    Foo;']), ckSplitIf));
  Assert.AreEqual(InProc(['  if A then', '    if B and C then', '      Foo;']),
    Fixed(InProc(['  if A {^}and B and C then', '    Foo;']), ckSplitIf));
end;

procedure TTestRdxCtxSplitIf.Split_Comparisons;
begin
  Assert.AreEqual(InProc(['  if (X > 0) then', '    if (Y > 0) then',
    '      Foo;']), Fixed(InProc(['  if (X > 0) {^}and (Y > 0) then',
    '    Foo;']), ckSplitIf));
end;

// Teilen und wieder zusammenfuegen = das Original.
procedure TTestRdxCtxSplitIf.Split_MergeRoundTrip;
var
  Src, Once : string;
begin
  Src := InProc(['  if Assigned(P) and P.Visible then', '  begin',
    '    Paint(P);', '  end;']);
  Once := FixedOnWord(Src, 'if Assigned', 'and', ckSplitIf);
  Assert.AreEqual(InProc(['  if Assigned(P) then', '    if P.Visible then',
    '    begin', '      Paint(P);', '    end;']), Once);
  Assert.AreEqual(InProc(['  if Assigned(P) and P.Visible then', '  begin',
    '    Paint(P);', '  end;']), FixedOnWord(Once, 'if Assigned', 'if',
    ckMergeIf));
end;

procedure TTestRdxCtxSplitIf.Split_Else_Refused;
begin
  AssertRefused(InProc(['  if A {^}and B then Foo else Bar;']), ckSplitIf,
    _(R_IF_SPLIT_ELSE));
end;

procedure TTestRdxCtxSplitIf.Split_BoolEval_Refused;
begin
  AssertRefused(UnitWith(['{$B+}'], ['  if A {^}and B then Foo;']), ckSplitIf,
    _(R_IF_BOOLEVAL, [2]));
  AssertRefused(UnitWith(['{$BOOLEVAL ON}'], ['  if A {^}and B then Foo;']),
    ckSplitIf, _(R_IF_BOOLEVAL, [2]));
end;

procedure TTestRdxCtxSplitIf.Split_Comment_Refused;
begin
  AssertRefused(InProc(['  if A {^}and { b } B then Foo;']), ckSplitIf,
    _(R_IF_COND_COMMENT));
end;

procedure TTestRdxCtxSplitIf.Split_NotTopLevel_NoEntry;
begin
  AssertNone(InProc(['  if A or B {^}and C then Foo;']), ckSplitIf,
    'and unter or');
  AssertNone(InProc(['  if (A {^}and B) or C then Foo;']), ckSplitIf,
    'in Klammern');
  AssertNone(InProc(['  while A {^}and B do Foo;']), ckSplitIf, 'while');
end;

{ ---- C8 if zusammenfuegen ---- }

procedure TTestRdxCtxMergeIf.Merge_Simple;
begin
  Assert.AreEqual(InProc(['  if A and B then', '    Foo;']),
    Fixed(InProc(['  {^}if A then', '    if B then', '      Foo;']),
    ckMergeIf));
end;

procedure TTestRdxCtxMergeIf.Merge_Block;
begin
  Assert.AreEqual(InProc(['  if A and B then', '    Foo;']),
    Fixed(InProc(['  {^}if A then', '  begin', '    if B then', '      Foo;',
    '  end;']), ckMergeIf));
  Assert.AreEqual(InProc(['  if A and B then', '  begin', '    Foo;',
    '    Bar;', '  end;']), Fixed(InProc(['  {^}if A then', '  begin',
    '    if B then', '    begin', '      Foo;', '      Bar;', '    end;',
    '  end;']), ckMergeIf));
end;

procedure TTestRdxCtxMergeIf.Merge_BeginOnThenLine;
begin
  Assert.AreEqual(InProc(['  if A and B then', '    Foo;']),
    Fixed(InProc(['  {^}if A then begin', '    if B then', '      Foo;',
    '  end;']), ckMergeIf));
end;

// Ein Glied, das kein Faktor ist, kommt in Klammern (or bindet schwaecher
// als and, ein Vergleich schwaecher als beide).
procedure TTestRdxCtxMergeIf.Merge_Parentheses;
begin
  Assert.AreEqual(InProc(['  if (A or B) and (X > 0) then', '    Foo;']),
    Fixed(InProc(['  {^}if A or B then', '    if X > 0 then', '      Foo;']),
    ckMergeIf));
  Assert.AreEqual(InProc(['  if not A and Assigned(P) then', '    Foo;']),
    Fixed(InProc(['  {^}if not A then', '    if Assigned(P) then',
    '      Foo;']), ckMergeIf));
end;

procedure TTestRdxCtxMergeIf.Merge_AndChainSingleLine;
begin
  Assert.AreEqual(InProc(['  if A and B and C then Foo;']),
    Fixed(InProc(['  {^}if A and B then if C then Foo;']), ckMergeIf));
end;

procedure TTestRdxCtxMergeIf.Merge_CaretOnThen;
begin
  Assert.AreEqual(InProc(['  if A and B then', '    Foo;']),
    Fixed(InProc(['  if A th{^}en', '    if B then', '      Foo;']),
    ckMergeIf));
end;

procedure TTestRdxCtxMergeIf.Merge_OuterElse_Refused;
begin
  AssertRefused(InProc(['  {^}if A then', '  begin', '    if B then Foo;',
    '  end', '  else', '    Bar;']), ckMergeIf, _(R_IF_MERGE_OUTER_ELSE));
end;

// Ohne begin..end gehoert das else dem inneren if (dangling else).
procedure TTestRdxCtxMergeIf.Merge_InnerElse_Refused;
begin
  AssertRefused(InProc(['  {^}if A then if B then Foo else Bar;']), ckMergeIf,
    _(R_IF_MERGE_INNER_ELSE));
end;

procedure TTestRdxCtxMergeIf.Merge_BoolEval_Refused;
begin
  AssertRefused(UnitWith(['{$B+,R-}'], ['  {^}if A then', '    if B then Foo;']),
    ckMergeIf, _(R_IF_BOOLEVAL, [2]));
end;

procedure TTestRdxCtxMergeIf.Merge_Comment_Refused;
begin
  AssertRefused(InProc(['  {^}if A then // erst', '    if B then', '      Foo;']),
    ckMergeIf, _(R_IF_MERGE_COMMENT));
  AssertRefused(InProc(['  {^}if A then', '  begin', '    if B then Foo; // b',
    '  end;']), ckMergeIf, _(R_IF_MERGE_COMMENT));
end;

procedure TTestRdxCtxMergeIf.Merge_NoCandidate_NoEntry;
begin
  AssertNone(InProc(['  {^}if A then', '  begin', '    if B then Foo;',
    '    Bar;', '  end;']), ckMergeIf, 'zwei Anweisungen im Block');
  AssertNone(InProc(['  {^}if A then Foo;']), ckMergeIf, 'kein inneres if');
  AssertNone(InProc(['  if A then', '    {^}if B then', '      Foo;']),
    ckMergeIf, 'Caret auf dem inneren if');
end;

{ ---- Texte und Reihenfolge ---- }

function OutcomeOf(AKind: TRdxContextKind;
  const AName: string): TRdxContextOutcome;
begin
  Result := Default(TRdxContextOutcome);
  Result.Kind := AKind;
  Result.Name := AName;
end;

procedure TTestRdxCtxIfTexts.Captions_German;
begin
  Assert.AreEqual('if umkehren (then und else tauschen)',
    TRdxContextRunner.CaptionOf(OutcomeOf(ckInvertIf, '')));
  Assert.AreEqual('De Morgan auf "and" anwenden',
    TRdxContextRunner.CaptionOf(OutcomeOf(ckDeMorgan, 'and')));
  Assert.AreEqual('Seiten von "<=" tauschen',
    TRdxContextRunner.CaptionOf(OutcomeOf(ckFlipCompare, '<=')));
  Assert.AreEqual('if am "and" teilen',
    TRdxContextRunner.CaptionOf(OutcomeOf(ckSplitIf, '')));
  Assert.IsTrue(Pos('Mit dem inneren if zusammenf',
    TRdxContextRunner.CaptionOf(OutcomeOf(ckMergeIf, ''))) = 1);
  // Arten mit Fund-Hilfe: den Text baut uRdxFixTable.ContextCaption.
  Assert.AreEqual('', TRdxContextRunner.CaptionOf(OutcomeOf(ckGuardClause, '')));
  Assert.AreEqual('', TRdxContextRunner.CaptionOf(OutcomeOf(ckIntroduceConst,
    '12')));
end;

procedure TTestRdxCtxIfTexts.Hints_German;
var
  O   : TRdxContextOutcome;
  Src : string;
begin
  O := KindAt(InProc(['  {^}if A then Foo else Bar;']), ckInvertIf, Src);
  Assert.IsTrue(Pos('gleiche Bedeutung', O.Hint) = 1, O.Hint);
  O := KindAt(InProc(['  if A {^}and B then Foo;']), ckSplitIf, Src);
  Assert.IsTrue(Pos('{$B-}', O.Hint) > 0, O.Hint);
  O := KindAt(InProc(['  {^}if A then', '  begin', '    Foo;', '  end;']),
    ckGuardClause, Src);
  Assert.IsTrue(Pos('gleiche Bedeutung', O.Hint) = 1, O.Hint);
  Assert.AreEqual('die Bedingung ist nicht lesbar (mehrzeiliger String oder '
    + 'Kommentar)', _(R_IF_COND_UNREADABLE));
end;

// Mehrere Aktionen am selben Token: in der Reihenfolge von TRdxContextKind.
procedure TTestRdxCtxIfTexts.Order_DeMorganBeforeSplit;
var
  All : TArray<TRdxContextOutcome>;
  Src : string;
begin
  All := RunAt(InProc(['  if A {^}and B then Foo;']), Src);
  Assert.AreEqual<Integer>(2, Length(All));
  Assert.IsTrue(All[0].Kind = ckDeMorgan, 'De Morgan zuerst');
  Assert.IsTrue(All[1].Kind = ckSplitIf, 'dann teilen');
  All := RunAt(InProc(['  {^}if A then', '  begin', '    if B then Foo;',
    '  end;']), Src);
  Assert.AreEqual<Integer>(2, Length(All), 'Waechter-Klausel und zusammenfuegen');
  Assert.IsTrue(All[0].Kind = ckGuardClause);
  Assert.IsTrue(All[1].Kind = ckMergeIf);
end;

{$IFNDEF FPC}

procedure TTestRdxCtxIfCaption.Caption_GuardLikeSca018;
var
  Fix : TRdxFixOutcome;
begin
  Fix := Default(TRdxFixOutcome);
  Assert.AreEqual(TRdxFixTable.CaptionFor(fkDeepNesting, Fix),
    TRdxFixTable.ContextCaption(OutcomeOf(ckGuardClause, '')));
  Assert.IsTrue(Pos('Letztes if in eine W', TRdxFixTable.ContextCaption(
    OutcomeOf(ckGuardClause, ''))) = 1);
end;

procedure TTestRdxCtxIfCaption.Caption_OthersFromRunner;
var
  K : TRdxContextKind;
  O : TRdxContextOutcome;
begin
  for K in [ckInvertIf, ckDeMorgan, ckFlipCompare, ckSplitIf, ckMergeIf] do
  begin
    O := OutcomeOf(K, 'and');
    Assert.AreEqual(TRdxContextRunner.CaptionOf(O),
      TRdxFixTable.ContextCaption(O));
    Assert.IsTrue(TRdxFixTable.ContextCaption(O) <> '');
  end;
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxCtxInvertIf);
  TDUnitX.RegisterTestFixture(TTestRdxCtxGuard);
  TDUnitX.RegisterTestFixture(TTestRdxCtxDeMorgan);
  TDUnitX.RegisterTestFixture(TTestRdxCtxFlip);
  TDUnitX.RegisterTestFixture(TTestRdxCtxSplitIf);
  TDUnitX.RegisterTestFixture(TTestRdxCtxMergeIf);
  TDUnitX.RegisterTestFixture(TTestRdxCtxIfTexts);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxCtxIfCaption);
  {$ENDIF}

end.
