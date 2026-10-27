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
  TTestRdxCtxIfTexts = class
  public
    [Test] procedure Captions_German;
    [Test] procedure Hints_German;
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
  O := KindAt(InProc(['  {^}if A then', '  begin', '    Foo;', '  end;']),
    ckGuardClause, Src);
  Assert.IsTrue(Pos('gleiche Bedeutung', O.Hint) = 1, O.Hint);
  Assert.AreEqual('die Bedingung ist nicht lesbar (mehrzeiliger String oder '
    + 'Kommentar)', _(R_IF_COND_UNREADABLE));
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
  for K in [ckInvertIf] do
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
  TDUnitX.RegisterTestFixture(TTestRdxCtxIfTexts);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxCtxIfCaption);
  {$ENDIF}

end.
