unit uTestRdxContextRunner;

// Code-Aktionen ohne Fund (Charge B): das Konstrukt unter dem Caret
// (uRdxCodeMap.TokenContaining/LiteralContaining, V4 - erste Fixture), der
// Laeufer am Caret (uRdxContextRunner, V5) mit "Lokale Konstante
// einfuehren" (TRdxMagicFixes.IntroduceAt) und C3 "try/finally um Create"
// (TRdxTryFixes.CreateAt) - zweite Fixture; beide auf Text, ohne Parser
// (reDelphix.Test UND FPC-Pruefstand). Nur Delphi (dritte Fixture): der
// Menuetext der Kontextaktion (uRdxFixTable.ContextCaption) ist auf einer
// Fundzeile derselbe wie der der Fund-Hilfe SCA014 bzw. SCA009 (PlanFixIn,
// TRdxFixTable.CaptionFor) - nur dann faellt sie im Menue weg (Dedup per
// Caption, Entscheid F2).
// Der Caret steht als CARET_MARK '{^}' im Text (uTestRdxTextKit.CaretOf):
// VOR dem Zeichen hinter der Marke.
// Je Aktion: Angebot (Text vorher/nachher von Hand), Sperre mit Grund, kein
// Kandidat = kein Eintrag (F4), und die Gleichheit mit dem Quick-Fix (die
// Kette ist dieselbe - Bewegung null fuer SCA014/SCA009 pruefen
// uTestRdxMagicFix und uTestRdxTryFixes unveraendert).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxCaret = class
  public
    [Test] procedure Token_ContainsColumn;
    [Test] procedure Token_BehindAndOutside;
    [Test] procedure Literal_Numbers;
    [Test] procedure Literal_CharsAndStrings;
    [Test] procedure Literal_NotInIdentifierOrComment;
  end;

  [TestFixture]
  TTestRdxContextRunner = class
  public
    // ---- Lokale Konstante einfuehren ----
    [Test] procedure Const_CaretPositions;
    [Test] procedure Const_LiteralForms;
    [Test] procedure Const_OnlyTheCaretLiteral;
    [Test] procedure Const_NameCollisionFree;
    [Test] procedure Const_SameAsSca014;
    [Test] procedure Const_NoCandidate_NoEntry;
    [Test] procedure Const_Refused_WithReason;
    [Test] procedure Const_Refused_LazarusProject;
    // ---- C3 try/finally um Create ----
    [Test] procedure Try_Basic;
    [Test] procedure Try_InlineVarAndFreeAndNil;
    [Test] procedure Try_SameAsSca009;
    [Test] procedure Try_NoRelease_Refused;
    [Test] procedure Try_NotLocal_NoEntry;
    [Test] procedure Try_NoCandidate_NoEntry;
    // ---- Laeufer ----
    [Test] procedure Run_BothOnOneLine;
    [Test] procedure Run_InvalidContext;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxContextCaption = class
  public
    [Test] procedure Caption_ConstLikeSca014;
    [Test] procedure Caption_TryLikeSca009;
    [Test] procedure Caption_RefusedKeepsName;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  uSCAConsts,            // fkMagicNumber, fkMissingFinally
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // CaptionFor, ContextCaption
  uTestRdxDetectorKit,   // TSeen, PlanFixIn
  {$ENDIF}
  uFindingActions,       // TEditorContext
  uRdxBufferMath, uRdxCodeMap, uRdxMagicFixes, uRdxTryFixes,
  uRdxContextRunner,
  uRdxText,              // _
  uTestRdxTextKit;       // Join, Apply, NewMap, CaretOf, LineOf, TempName,
                         // NewTempDir, WriteText, RemoveTree

const
  MAGIC_MSG = 'Magic number "%s" in if condition - use a constant';

// ---- Helfer ----

// Eine Unit mit der Prozedur P(X, Y) und dem Rumpf ABody; AHead vor
// interface (wie uTestRdxMagicFix).
function UnitWith(const AHead, ABody: array of string): string;
begin
  Result := Join(['unit u;']) + #13#10 + Join(AHead) + #13#10
    + Join(['interface', 'implementation', 'procedure P(X, Y: Integer);',
      'begin']) + #13#10 + Join(ABody) + #13#10 + Join(['end;', 'end.']);
end;

// Eine Unit mit der globalen Variablen G und der Prozedur P mit den lokalen
// Variablen AVars (ohne var-Abschnitt, wenn leer) und dem Rumpf ABody.
function ProcWith(const AVars, ABody: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation', 'var',
    '  G: TFoo;', 'procedure P;']) + #13#10;
  if Length(AVars) > 0 then
    Result := Result + 'var' + #13#10 + Join(AVars) + #13#10;
  Result := Result + 'begin' + #13#10 + Join(ABody) + #13#10
    + Join(['end;', 'end.']);
end;

// Ein Dateiname, dessen Verzeichnis es nicht gibt - der Plattenblick
// (FileReason) findet dort nichts.
function NoDiskFile: string;
begin
  Result := TempName('rdx_ctx_', PathDelim) + 'u.pas';
end;

// Die Eintraege des Laeufers fuer ASource am Caret ALine/ACol.
function RunPos(const ASource, AFileName: string;
  ALine, ACol: Integer): TArray<TRdxContextOutcome>;
var
  SL : TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Result := TRdxContextRunner.Run(SL,
      TEditorContext.At(AFileName, ALine, ACol));
  finally
    SL.Free;
  end;
end;

// Dasselbe am Caret von AMarked (CARET_MARK); ASource ohne Marke.
function RunAt(const AMarked: string; out ASource: string;
  const AFileName: string = ''): TArray<TRdxContextOutcome>;
var
  Line, Col : Integer;
  F         : string;
begin
  ASource := AMarked;
  Assert.IsTrue(CaretOf(ASource, Line, Col), 'Caret-Marke fehlt');
  F := AFileName;
  if F = '' then
    F := NoDiskFile;
  Result := RunPos(ASource, F, Line, Col);
end;

// Genau EIN Eintrag am Caret, von der Art AKind.
function OneAt(const AMarked: string; AKind: TRdxContextKind;
  out ASource: string; const AFileName: string = ''): TRdxContextOutcome;
var
  All : TArray<TRdxContextOutcome>;
begin
  All := RunAt(AMarked, ASource, AFileName);
  Assert.AreEqual<Integer>(1, Length(All), 'ein Eintrag: ' + ASource);
  Result := All[0];
  Assert.IsTrue(Result.Kind = AKind, 'Art des Eintrags');
end;

// Der Text nach dem einen, freigegebenen Eintrag der Art AKind.
function Fixed(const AMarked: string; AKind: TRdxContextKind): string;
var
  O   : TRdxContextOutcome;
  Src : string;
begin
  O := OneAt(AMarked, AKind, Src);
  Assert.IsTrue(O.Enabled, 'freigegeben: ' + O.Reason);
  Assert.AreEqual('', O.Reason);
  Result := Apply(Src, O.Edits);
end;

// Kein Eintrag am Caret (F4).
procedure AssertNone(const AMarked, AWhat: string);
var
  Src : string;
begin
  Assert.AreEqual<Integer>(0, Length(RunAt(AMarked, Src)), AWhat);
end;

// Genau ein gesperrter Eintrag der Art AKind: keine Ersetzungen, APart im
// Grund; liefert ihn.
function Refused(const AMarked: string; AKind: TRdxContextKind;
  const APart: string; const AFileName: string = ''): TRdxContextOutcome;
var
  Src : string;
begin
  Result := OneAt(AMarked, AKind, Src, AFileName);
  Assert.IsFalse(Result.Enabled, 'gesperrt: ' + Src);
  Assert.AreEqual<Integer>(0, Length(Result.Edits), 'keine Ersetzung');
  Assert.AreEqual('', Result.Hint, 'kein Hinweis');
  Assert.IsTrue(Pos(APart, Result.Reason) > 0, APart + ' in: ' + Result.Reason);
end;

// Liegt ALiteral (das erste Vorkommen in Zeile 1 von AText) am Caret als
// AKind - an seinem Anfang, im zweiten Zeichen und direkt dahinter?
procedure AssertLiteral(const AText, ALiteral: string; AKind: TRdxLiteralKind);
var
  Map             : TRdxCodeMap;
  P, Col, F, S, i : Integer;
begin
  P := Pos(ALiteral, AText);
  Assert.IsTrue(P > 0, ALiteral);
  Map := NewMap(AText);
  try
    for i := 0 to 2 do
    begin
      case i of
        0: Col := P;
        1: Col := P + 1;
      else
        Col := P + Length(ALiteral);
      end;
      Assert.IsTrue(LiteralContaining(Map, 1, Col, F, S) = AKind,
        ALiteral + ' an Spalte ' + IntToStr(Col));
      Assert.AreEqual<Integer>(P, F, ALiteral + ': Anfang');
      Assert.AreEqual<Integer>(P + Length(ALiteral), S, ALiteral + ': Ende');
    end;
  finally
    Map.Free;
  end;
end;

// Kein Literal an Spalte ACol der Zeile 1 von AText.
procedure AssertNoLiteral(const AText: string; ACol: Integer;
  const AWhat: string);
var
  Map  : TRdxCodeMap;
  F, S : Integer;
begin
  Map := NewMap(AText);
  try
    Assert.IsTrue(LiteralContaining(Map, 1, ACol, F, S) = lkNone, AWhat);
    Assert.AreEqual<Integer>(0, F, AWhat + ': Anfang');
    Assert.AreEqual<Integer>(0, S, AWhat + ': Ende');
  finally
    Map.Free;
  end;
end;

{ ---- V4: das Konstrukt unter dem Caret ---- }

// '  X := Foo(12);' - X 3, ':=' 5, Foo 8, '(' 11, '12' 12, ')' 14, ';' 15.
procedure TTestRdxCaret.Token_ContainsColumn;
var
  Map : TRdxCodeMap;
begin
  Map := NewMap('  X := Foo(12);');
  try
    Assert.AreEqual('x', TokenContaining(Map, 1, 3).Low);
    Assert.AreEqual(':=', TokenContaining(Map, 1, 5).Low);
    Assert.AreEqual(':=', TokenContaining(Map, 1, 6).Low, 'zweites Zeichen');
    Assert.AreEqual('foo', TokenContaining(Map, 1, 9).Low);
    // Foo endet an 11, '(' beginnt dort: das an ACol gilt.
    Assert.AreEqual('(', TokenContaining(Map, 1, 11).Low);
    Assert.AreEqual('12', TokenContaining(Map, 1, 13).Low);
    Assert.AreEqual<Integer>(12, TokenContaining(Map, 1, 13).Col);
    Assert.AreEqual<Integer>(2, TokenContaining(Map, 1, 13).Len);
  finally
    Map.Free;
  end;
end;

procedure TTestRdxCaret.Token_BehindAndOutside;
var
  Map : TRdxCodeMap;
  T   : TRdxToken;
begin
  Map := NewMap(Join(['  X := Foo(12);', '  Y; { Kommentar }', '']));
  try
    // Direkt hinter einem Token: das Token (Caret nach dem Tippen).
    Assert.AreEqual('x', TokenContaining(Map, 1, 4).Low, 'hinter X');
    Assert.AreEqual(':=', TokenContaining(Map, 1, 7).Low, 'hinter :=');
    Assert.AreEqual(';', TokenContaining(Map, 1, 16).Low, 'Zeilenende');
    // Leerraum ohne Nachbar, Kommentar, ausserhalb: kein Token.
    T := TokenContaining(Map, 1, 1);
    Assert.AreEqual('', T.Low, 'Einzug');
    Assert.AreEqual<Integer>(0, T.Len);
    Assert.AreEqual<Integer>(1, T.Line);
    Assert.AreEqual<Integer>(1, T.Col);
    Assert.AreEqual('', TokenContaining(Map, 1, 17).Low, 'virtueller Raum');
    Assert.AreEqual('', TokenContaining(Map, 2, 10).Low, 'Kommentar');
    Assert.AreEqual('', TokenContaining(Map, 3, 1).Low, 'leere Zeile');
    Assert.AreEqual('', TokenContaining(Map, 9, 1).Low, 'hinter dem Text');
    Assert.AreEqual('', TokenContaining(Map, 1, 0).Low, 'Spalte 0');
  finally
    Map.Free;
  end;
end;

procedure TTestRdxCaret.Literal_Numbers;
const
  L = '  A := $FF + 1.5 + 1e3 + 1_000 + %101 + &17 + 2.5E-3 + 7;';
begin
  AssertLiteral(L, '$FF', lkNumber);
  AssertLiteral(L, '1.5', lkNumber);
  AssertLiteral(L, '1e3', lkNumber);
  AssertLiteral(L, '1_000', lkNumber);
  AssertLiteral(L, '%101', lkNumber);
  AssertLiteral(L, '&17', lkNumber);
  AssertLiteral(L, '2.5E-3', lkNumber);
  // Bereich: '0..9' sind zwei Literale, '..' gehoert zu keinem.
  AssertLiteral('  S := [0..9];', '9', lkNumber);
  AssertLiteral('  S := [0..9];', '0', lkNumber);
end;

procedure TTestRdxCaret.Literal_CharsAndStrings;
const
  L = '  S := #13#10 + #$0D + ''a''''b'' + ''x''#13''y'';';
begin
  AssertLiteral(L, '#13#10', lkChar);
  AssertLiteral(L, '#$0D', lkChar);
  AssertLiteral(L, '''a''''b''', lkString);
  // Mischform ohne Leerraum: EIN String-Literal.
  AssertLiteral(L, '''x''#13''y''', lkString);
end;

procedure TTestRdxCaret.Literal_NotInIdentifierOrComment;
begin
  AssertNoLiteral('  X12 := Y;', 4, 'Ziffer in einem Bezeichner');
  AssertNoLiteral('  B := 12x;', 8, 'Bezeichner-Zeichen dahinter');
  AssertNoLiteral('  B := Y.Z; // 42', 16, 'Kommentar');
  AssertNoLiteral('  B := &begin;', 9, 'Escape-Bezeichner');
  AssertNoLiteral('  B := Y;', 2, 'Einzug');
end;

{ ---- Lokale Konstante einfuehren ---- }

// Caret am Anfang, im Literal und direkt dahinter: derselbe Eintrag.
procedure TTestRdxContextRunner.Const_CaretPositions;
const
  WANT: array[0..2] of string = ('  Bar({^}200);', '  Bar(2{^}00);',
    '  Bar(200{^});');
var
  M   : string;
  O   : TRdxContextOutcome;
  Src : string;
  All : TArray<TRdxContextOutcome>;
begin
  for M in WANT do
  begin
    Assert.AreEqual(UnitWith([], ['  Foo;', '  const MagicNr01 = 200;',
      '  Bar(MagicNr01);']), Fixed(UnitWith([], ['  Foo;', M]),
      ckIntroduceConst), M);
  end;
  O := OneAt(UnitWith([], ['  Foo;', '  Bar(2{^}00);']), ckIntroduceConst, Src);
  Assert.AreEqual('200', O.Name, 'Menuetext');
  Assert.IsTrue(Pos('MagicNr01', O.Hint) > 0, O.Hint);
  Assert.IsFalse(O.ChangesBehavior, 'bedeutungsgleich');
  Assert.AreEqual<Integer>(1, Length(O.Edits), 'EINE Ersetzung');
  // Caret im virtuellen Raum hinter dem Zeilenende: wie direkt dahinter.
  All := RunPos(UnitWith([], ['  Foo;', '  X := 200', '    + Y;']),
    NoDiskFile, 8, 99);
  Assert.AreEqual<Integer>(1, Length(All), 'virtueller Raum');
  Assert.AreEqual('200', All[0].Name);
end;

procedure TTestRdxContextRunner.Const_LiteralForms;
const
  LITS: array[0..4] of string = ('$FF', '1.5', '1_000', '1e3', '2.5E-3');
var
  L : string;
begin
  for L in LITS do
    Assert.AreEqual(UnitWith([], ['  Foo;', '  const MagicNr01 = ' + L + ';',
      '  Bar(MagicNr01);']), Fixed(UnitWith([], ['  Foo;',
      '  Bar(' + Copy(L, 1, 1) + '{^}' + Copy(L, 2, MaxInt) + ');']),
      ckIntroduceConst), L);
end;

// Nur das Literal am Caret (E28), nicht alle gleichen der Zeile.
procedure TTestRdxContextRunner.Const_OnlyTheCaretLiteral;
begin
  Assert.AreEqual(UnitWith([], ['  Foo;', '  const MagicNr01 = 200;',
    '  Bar(200, MagicNr01);']), Fixed(UnitWith([], ['  Foo;',
    '  Bar(200, 20{^}0);']), ckIntroduceConst));
  // Ein Zweig ohne begin bekommt begin..end (wie SCA014).
  Assert.AreEqual(UnitWith([], ['  if X > 0 then', '  begin',
    '    const MagicNr01 = 5;', '    Bar(MagicNr01);', '  end;']),
    Fixed(UnitWith([], ['  if X > 0 then', '    Bar({^}5);']),
    ckIntroduceConst));
end;

// Der erste freie Name - auch ein Kommentar zaehlt (NextFreeName).
procedure TTestRdxContextRunner.Const_NameCollisionFree;
var
  O   : TRdxContextOutcome;
  Src : string;
begin
  O := OneAt(UnitWith([], ['  Foo; // MagicNr01', '  Bar(4{^}2);']),
    ckIntroduceConst, Src);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsTrue(Pos('const MagicNr02 = 42;', Apply(Src, O.Edits)) > 0,
    Apply(Src, O.Edits));
  Assert.IsTrue(Pos('MagicNr02', O.Hint) > 0, O.Hint);
end;

// Auf einer SCA014-Fundzeile dieselbe Ersetzung wie der Quick-Fix.
procedure TTestRdxContextRunner.Const_SameAsSca014;
var
  Src, R : string;
  O      : TRdxContextOutcome;
  Map    : TRdxCodeMap;
  P      : TRdxMagicPlan;
begin
  O := OneAt(UnitWith([], ['  Foo;', '  if X > 2{^}00 then Bar;']),
    ckIntroduceConst, Src);
  Map := NewMap(Src);
  try
    Assert.IsTrue(TRdxMagicFixes.MagicNumber(Map, LineOf(Src, 'if X >'),
      Format(MAGIC_MSG,
      ['200']), P, R), R);
  finally
    Map.Free;
  end;
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual(Apply(Src, P.Edits), Apply(Src, O.Edits));
  Assert.AreEqual(P.Value, O.Name, 'Menuetext wie SCA014');
end;

// Kein Zahl-Literal am Caret: kein Eintrag (F4) - auch nicht gesperrt.
procedure TTestRdxContextRunner.Const_NoCandidate_NoEntry;
begin
  AssertNone(UnitWith([], ['  Foo;', '  Bar(Fo{^}o);']), 'Bezeichner');
  AssertNone(UnitWith([], ['  Foo;', '  Bar(''20{^}0'');']), 'String');
  AssertNone(UnitWith([], ['  Foo;', '  Bar(X); // 20{^}0']), 'Kommentar');
  AssertNone(UnitWith([], ['  Foo;', '  Bar(#1{^}3);']), 'Zeichen (F5)');
  AssertNone(UnitWith([], ['  Foo;', '  Bar(X1{^}2);']), 'in einem Bezeichner');
  AssertNone(UnitWith([], ['  Foo;', '{^}  Bar(12);']), 'Einzug');
end;

// Kandidat da, aber gesperrt: Eintrag mit Grund, Name schon gesetzt.
procedure TTestRdxContextRunner.Const_Refused_WithReason;
var
  O : TRdxContextOutcome;
begin
  O := Refused(UnitWith([], ['  Foo;', '  const C = 2{^}00;']),
    ckIntroduceConst, 'Deklaration');
  Assert.AreEqual('200', O.Name, 'Name auch gesperrt');
  Refused(UnitWith(['{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}'], ['  Foo;',
    '  Bar(2{^}00);']), ckIntroduceConst, 'FPC');
  Refused(UnitWith(['{$IFDEF VER150}{$ENDIF}'], ['  Foo;', '  Bar(2{^}00);']),
    ckIntroduceConst, 'Delphi 10.3');
  // Delphi-11-Binaerliteral: die Code-Aktion liest nur dezimal und hex.
  O := Refused(UnitWith([], ['  Foo;', '  Bar(%1{^}01);']), ckIntroduceConst,
    '%101');
  Assert.AreEqual('%101', O.Name);
end;

// Was nur die Platte weiss (FileReason): ein Lazarus-Projekt neben der Unit.
procedure TTestRdxContextRunner.Const_Refused_LazarusProject;
const
  MARKED = 'unit u;'#13#10'interface'#13#10'implementation'#13#10
    + 'procedure P;'#13#10'begin'#13#10'  Foo;'#13#10'  Bar(2{^}00);'#13#10
    + 'end;'#13#10'end.';
var
  Dir, Src : string;
  O        : TRdxContextOutcome;
begin
  Dir := NewTempDir('rdx_ctx_');
  try
    WriteText(Dir + 'demo.lpi', '<?xml version="1.0"?>');
    O := Refused(MARKED, ckIntroduceConst, 'Lazarus', Dir + 'u.pas');
    Assert.IsTrue(Pos('demo.lpi', O.Reason) > 0, O.Reason);
    // Ohne Projektdatei dieselbe Stelle freigegeben.
    Assert.IsTrue(DeleteFile(Dir + 'demo.lpi'), 'demo.lpi geloescht');
    O := OneAt(MARKED, ckIntroduceConst, Src, Dir + 'u.pas');
    Assert.IsTrue(O.Enabled, 'ohne .lpi freigegeben: ' + O.Reason);
  finally
    RemoveTree(Dir);
  end;
end;

{ ---- C3 try/finally um Create ---- }

procedure TTestRdxContextRunner.Try_Basic;
const
  WANT: array[0..2] of string = ('{^}  X := TFoo.Create;',
    '  X := TFoo.Cr{^}eate;', '  X := TFoo.Create;{^}');
var
  M, Src, Expected : string;
  O                : TRdxContextOutcome;
  All              : TArray<TRdxContextOutcome>;
begin
  Expected := ProcWith(['  X: TFoo;'], ['  X := TFoo.Create;', '  try',
    '    X.Run;', '  finally', '    X.Free;', '  end;']);
  for M in WANT do
    Assert.AreEqual(Expected, Fixed(ProcWith(['  X: TFoo;'], [M, '  X.Run;',
      '  X.Free;']), ckTryFinallyCreate), M);
  O := OneAt(ProcWith(['  X: TFoo;'], ['  X := TFoo.Cr{^}eate;', '  X.Run;',
    '  X.Free;']), ckTryFinallyCreate, Src);
  Assert.AreEqual('X', O.Name, 'Menuetext');
  Assert.IsTrue(O.ChangesBehavior, 'gekennzeichnet (E2)');
  Assert.IsTrue(Pos('try', O.Hint) > 0, O.Hint);
  // Caret im virtuellen Raum hinter dem Zeilenende: wie das Zeilenende.
  All := RunPos(Src, NoDiskFile, LineOf(Src, 'X := TFoo.Create'), 200);
  Assert.AreEqual<Integer>(1, Length(All), 'virtueller Raum');
  Assert.AreEqual(Expected, Apply(Src, All[0].Edits));
end;

procedure TTestRdxContextRunner.Try_InlineVarAndFreeAndNil;
begin
  Assert.AreEqual(ProcWith([], ['  Foo;', '  var L := TStringList.Create;',
    '  try', '    L.Add(''a'');', '  finally', '    FreeAndNil(L);', '  end;']),
    Fixed(ProcWith([], ['  Foo;', '  var L := TStringList.Cre{^}ate;',
    '  L.Add(''a'');', '  FreeAndNil(L);']), ckTryFinallyCreate));
  // Zwei Erzeugungen auf einer Zeile: die, in deren Anweisung der Caret
  // steht - und dann fehlt die eigene Zeile (try/finally/end).
  Assert.AreEqual('B', Refused(ProcWith(['  A, B: TFoo;'],
    ['  A := TFoo.Create; B := TFoo.Cr{^}eate;', '  B.Run;', '  B.Free;',
    '  A.Free;']), ckTryFinallyCreate, 'eigenen Zeilen').Name);
  Assert.AreEqual('A', Refused(ProcWith(['  A, B: TFoo;'],
    ['  A := TFoo.Cr{^}eate; B := TFoo.Create;', '  B.Run;', '  B.Free;',
    '  A.Free;']), ckTryFinallyCreate, 'weiterer Code').Name);
end;

// Auf einer SCA009-Fundzeile dieselbe Ersetzung wie der Quick-Fix.
procedure TTestRdxContextRunner.Try_SameAsSca009;
var
  Src, R : string;
  O      : TRdxContextOutcome;
  Map    : TRdxCodeMap;
  P      : TRdxTryPlan;
begin
  O := OneAt(ProcWith(['  X: TFoo;'], ['  X := TFoo.Cr{^}eate;', '  X.Run;',
    '  if X.Ok then', '    Bar;', '  X.Free;', '  X := nil;']),
    ckTryFinallyCreate, Src);
  Map := NewMap(Src);
  try
    Assert.IsTrue(TRdxTryFixes.MissingFinally(Map,
      LineOf(Src, 'X := TFoo.Create'), 'X', P, R), R);
  finally
    Map.Free;
  end;
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual(Apply(Src, P.Edit), Apply(Src, O.Edits));
  Assert.AreEqual(P.Name, O.Name, 'Menuetext wie SCA009');
end;

// F6: ohne vorhandene Freigabe in derselben Liste gesperrt, mit Grund.
procedure TTestRdxContextRunner.Try_NoRelease_Refused;
var
  O : TRdxContextOutcome;
begin
  O := Refused(ProcWith(['  X: TFoo;'], ['  X := TFoo.Cr{^}eate;', '  X.Run;']),
    ckTryFinallyCreate, 'keine Freigabe X.Free');
  Assert.AreEqual('X', O.Name, 'Name auch gesperrt');
  Assert.IsTrue(O.ChangesBehavior, 'auch gesperrt gekennzeichnet');
  // Freigabe in einem anderen Block bzw. nur bedingt.
  Refused(ProcWith(['  X: TFoo;'], ['  X := TFoo.Cr{^}eate;', '  X.Run;',
    '  if X.Ok then', '    X.Free;']), ckTryFinallyCreate, 'X.Free');
  // Neue Zuweisung zwischen Erzeugung und Freigabe.
  Refused(ProcWith(['  X: TFoo;'], ['  X := TFoo.Cr{^}eate;', '  X.Run;',
    '  X := TFoo.Create;', '  X.Free;']), ckTryFinallyCreate,
    'zweite Zuweisung');
end;

// Kandidat ist nur eine lokale Variable: ein anderer Halter kennte nach
// finally das freie Objekt bzw. uebernimmt es - kein Eintrag (F4), auch
// wenn die Freigabe dasteht.
procedure TTestRdxContextRunner.Try_NotLocal_NoEntry;
var
  Dummy : string;
begin
  AssertNone(ProcWith([], ['  G := TFoo.Cr{^}eate;', '  G.Run;', '  G.Free;']),
    'globale Variable');
  AssertNone(ProcWith([], ['  F := TFoo.Cr{^}eate;', '  F.Run;', '  F.Free;']),
    'Feld (nicht deklariert in der Routine)');
  AssertNone(ProcWith([], ['  Self.F := TFoo.Cr{^}eate;', '  Self.F.Run;',
    '  Self.F.Free;']), 'Feld ueber Self');
  AssertNone(ProcWith([], ['  A[1] := TFoo.Cr{^}eate;', '  A[1].Free;']),
    'Element');
  AssertNone(ProcWith([], ['  Result := TFoo.Cr{^}eate;', '  Result.Run;',
    '  Result.Free;']), 'Result');
  // Auch als letzte Anweisung (die Kette saehe dort "keine Freigabe
  // dahinter") - die Frage nach dem Halter kommt zuerst.
  AssertNone(ProcWith([], ['  Foo;', '  Result := TFoo.Cr{^}eate;']),
    'Result als letzte Anweisung');
  AssertNone(ProcWith([], ['  Foo;', '  F := TFoo.Cr{^}eate;']),
    'Feld als letzte Anweisung');
  // Gegenprobe: dieselbe Zeile mit lokaler Variable ist ein Kandidat.
  Assert.AreEqual<Integer>(1, Length(RunAt(ProcWith(['  F: TFoo;'],
    ['  F := TFoo.Cr{^}eate;', '  F.Run;', '  F.Free;']), Dummy)),
    'lokal: ein Eintrag');
end;

// Kein Kandidat oder schon geschuetzt: kein Eintrag (F4).
procedure TTestRdxContextRunner.Try_NoCandidate_NoEntry;
begin
  AssertNone(ProcWith(['  X: TFoo;'], ['  with TFoo.Cr{^}eate do', '    Run;']),
    'with');
  AssertNone(ProcWith(['  X: TFoo;'], ['  X := {^}G;', '  X.Free;']),
    'keine Erzeugung');
  AssertNone(ProcWith(['  X: TFoo;'], ['  TFoo.Cr{^}eate;']), 'ohne Zuweisung');
  AssertNone(ProcWith(['  X: TFoo;'], ['  // X := TFoo.Cr{^}eate;', '  Foo;']),
    'Kommentar');
  AssertNone(ProcWith(['  X: TFoo;'], ['  X := TFoo.Cr{^}eate;', '  try',
    '    X.Run;', '  finally', '    X.Free;', '  end;']), 'schon geschuetzt');
end;

{ ---- Laeufer ---- }

// Ein Literal in der Erzeugung: beide Aktionen, Konstante zuerst.
procedure TTestRdxContextRunner.Run_BothOnOneLine;
var
  All : TArray<TRdxContextOutcome>;
  Src : string;
begin
  All := RunAt(ProcWith(['  X: TFoo;'], ['  Foo;', '  X := TFoo.Create(2{^}00);',
    '  X.Run;', '  X.Free;']), Src);
  Assert.AreEqual<Integer>(2, Length(All));
  Assert.IsTrue(All[0].Kind = ckIntroduceConst, 'zuerst die Konstante');
  Assert.IsTrue(All[1].Kind = ckTryFinallyCreate);
  Assert.IsTrue(All[0].Enabled and All[1].Enabled, All[0].Reason + All[1].Reason);
  // Auf X nur die Erzeugung.
  All := RunAt(ProcWith(['  X: TFoo;'], ['  Foo;', '  {^}X := TFoo.Create(200);',
    '  X.Run;', '  X.Free;']), Src);
  Assert.AreEqual<Integer>(1, Length(All));
  Assert.IsTrue(All[0].Kind = ckTryFinallyCreate);
end;

procedure TTestRdxContextRunner.Run_InvalidContext;
var
  SL : TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Text := UnitWith([], ['  Foo;', '  Bar(200);']);
    Assert.AreEqual<Integer>(1, Length(TRdxContextRunner.Run(SL,
      TEditorContext.At(NoDiskFile, 8, 8))), 'gueltig: ein Eintrag');
    Assert.AreEqual<Integer>(0, Length(TRdxContextRunner.Run(nil,
      TEditorContext.At(NoDiskFile, 8, 8))), 'ohne Text');
    Assert.AreEqual<Integer>(0, Length(TRdxContextRunner.Run(SL,
      TEditorContext.At('', 8, 8))), 'ohne Datei');
    Assert.AreEqual<Integer>(0, Length(TRdxContextRunner.Run(SL,
      TEditorContext.At(NoDiskFile, 8, 0))), 'Spalte 0');
    Assert.AreEqual<Integer>(0, Length(TRdxContextRunner.Run(SL,
      TEditorContext.At(NoDiskFile, 99, 1))), 'Zeile hinter dem Text');
  finally
    SL.Free;
  end;
end;

{$IFNDEF FPC}

{ ---- Menuetext: gleich dem der Fund-Hilfe (Dedup, F2) ---- }

// Der Eintrag am Caret von AMarked (genau einer der Art AKind).
function OutcomeAt(const AMarked: string; AKind: TRdxContextKind;
  out ASource: string): TRdxContextOutcome;
begin
  Result := OneAt(AMarked, AKind, ASource, 't.pas');
end;

function SeenAt(ALine: Integer; const AMsg: string): TSeen;
begin
  Result := Default(TSeen);
  Result.Line := ALine;
  Result.Msg := AMsg;
end;

procedure TTestRdxContextCaption.Caption_ConstLikeSca014;
var
  Src : string;
  O   : TRdxContextOutcome;
  Fix : TRdxFixOutcome;
begin
  O := OutcomeAt(UnitWith([], ['  Foo;', '  if X > 2{^}00 then Bar;']),
    ckIntroduceConst, Src);
  Fix := PlanFixIn(Src, 't.pas', fkMagicNumber, SeenAt(LineOf(Src, 'if X >'),
    Format(MAGIC_MSG, ['200'])));
  Assert.IsTrue(Fix.Enabled and O.Enabled, Fix.Reason + O.Reason);
  Assert.AreEqual(TRdxFixTable.CaptionFor(fkMagicNumber, Fix),
    TRdxFixTable.ContextCaption(O));
  Assert.AreEqual(Fix.Hint, O.Hint, 'derselbe Hinweis');
  Assert.AreEqual(Apply(Src, Fix.Edits), Apply(Src, O.Edits));
end;

procedure TTestRdxContextCaption.Caption_TryLikeSca009;
var
  Src : string;
  O   : TRdxContextOutcome;
  Fix : TRdxFixOutcome;
begin
  O := OutcomeAt(ProcWith(['  X: TFoo;'], ['  X := TFoo.Cr{^}eate;', '  X.Run;',
    '  X.Free;']), ckTryFinallyCreate, Src);
  Fix := PlanFixIn(Src, 't.pas', fkMissingFinally,
    SeenAt(LineOf(Src, 'X := TFoo.Create'), 'X'));
  Assert.IsTrue(Fix.Enabled and O.Enabled, Fix.Reason + O.Reason);
  Assert.AreEqual(TRdxFixTable.CaptionFor(fkMissingFinally, Fix),
    TRdxFixTable.ContextCaption(O));
  Assert.IsTrue(Pos(_('(changes behavior)'), TRdxFixTable.ContextCaption(O)) > 0,
    'Kennzeichnung (E2)');
  Assert.AreEqual(Fix.Hint, O.Hint, 'derselbe Hinweis');
  Assert.AreEqual(Apply(Src, Fix.Edits), Apply(Src, O.Edits));
end;

procedure TTestRdxContextCaption.Caption_RefusedKeepsName;
var
  O : TRdxContextOutcome;
begin
  O := Default(TRdxContextOutcome);
  O.Kind := ckTryFinallyCreate;
  O.Name := 'LList';
  O.ChangesBehavior := True;
  Assert.AreEqual(Format(_('Free %s in a try/finally block'), ['LList']) + ' '
    + _('(changes behavior)'), TRdxFixTable.ContextCaption(O));
  O.Kind := ckIntroduceConst;
  O.Name := '$FF';
  O.ChangesBehavior := False;
  Assert.AreEqual(Format(_('Introduce local constant for %s'), ['$FF']),
    TRdxFixTable.ContextCaption(O));
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxCaret);
  TDUnitX.RegisterTestFixture(TTestRdxContextRunner);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxContextCaption);
  {$ENDIF}

end.
