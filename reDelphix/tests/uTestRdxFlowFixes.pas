unit uTestRdxFlowFixes;

// Quick-Fixes an ganzen Anweisungen (uRdxFlowFixes, Charge H2) auf Text -
// ohne Parser, ohne Detektor (laeuft in reDelphix.Test UND im FPC-
// Pruefstand):
//   SCA098 'if C then X := True else X := False' -> 'X := C' (ueber Zeilen,
//          'Result:=', else-if, verschachtelt), Gegenrichtung 'X := not C'
//          (Klammern nur um zusammengesetztes C, Vergleich/Bezeichner als
//          Beweis); Kommentar, zwei auf der Zeile, Ausdruck dahinter,
//          begin..end-Zweig.
//   SCA080 'Exit;'/'Continue;' loeschen (eigene Zeile, inline, 'else
//          Exit'); einziger Zweig, case-Zweig, leerer Block, Code dahinter,
//          Schleife, mehrere Spruenge, Kommentar, eigene Routine Exit,
//          finally.
//   SCA047 'X := X;' loeschen (Zeile, inline, Pfad, ohne ';'); Result,
//          Funktionsname, operator Assign, Kommentar, Zweige, Block,
//          ueber Zeilen, mehrdeutig, verschobene Meldung.
// Die Typpruefung (X Boolean, X eine Variable) und with-Bloecke macht der
// Laeufer - die Gegenprobe mit dem echten Detektor steht in
// uTestRdxSimpleFixesDetector (Fixture 9, nur Delphi).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxFlowFixes = class
  public
    [Test] procedure Sca098_Forward;
    [Test] procedure Sca098_Negated;
    [Test] procedure Sca098_LinesAndNesting;
    [Test] procedure Sca098_Refusals;
    [Test] procedure Sca080_OwnLine;
    [Test] procedure Sca080_Inline;
    [Test] procedure Sca080_ElseExit;
    [Test] procedure Sca080_ChainTerminators;
    [Test] procedure Sca080_ContextRefusals;
    [Test] procedure Sca080_DetectorRefusals;
    [Test] procedure Sca047_Delete;
    [Test] procedure Sca047_Refusals;
    [Test] procedure Sca047_Context;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRdxCodeMap, uRdxFlowFixes,
  uTestRdxTextKit;   // Join, Apply

type
  TFlowKind = (wkCond, wkJump, wkSelf);

// ---- Helfer ----

// Der Plan der Hilfe AKind fuer Zeile ALine; AReason = '' heisst Hilfe.
function PlanOf(AKind: TFlowKind; const ASource: string; ALine: Integer;
  const AMessage: string; out AReason: string): TRdxFlowPlan;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    case AKind of
      wkCond:
        TRdxFlowFixes.RedundantConditional(Map, ALine, AMessage, Result,
          AReason);
      wkJump:
        TRdxFlowFixes.RedundantJump(Map, ALine, AMessage, Result, AReason);
    else
      TRdxFlowFixes.SelfAssignment(Map, ALine, AMessage, Result, AReason);
    end;
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Neuer Text oder '' bei Ablehnung (AReason).
function Fix(AKind: TFlowKind; const ASource: string; ALine: Integer;
  const AMessage: string; out AReason: string): string;
var
  P : TRdxFlowPlan;
begin
  Result := '';
  P := PlanOf(AKind, ASource, ALine, AMessage, AReason);
  if AReason = '' then
    Result := Apply(ASource, P.Edit);
end;

// Keine Hilfe, und APart steht im Grund.
procedure AssertRefused(AKind: TFlowKind; const ASource: string;
  ALine: Integer; const AMessage, APart: string);
var
  R : string;
begin
  Assert.AreEqual('', Fix(AKind, ASource, ALine, AMessage, R), 'keine Hilfe');
  Assert.IsTrue(Pos(APart, R) > 0, R);
end;

// Eine Unit mit Routine P; ALines ist ihr Rumpf (ab Zeile 6).
function InProc(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation', 'procedure P;',
    'begin']) + #13#10 + Join(ALines) + #13#10 + Join(['end;', 'end.']);
end;

// Eine Unit, deren implementation ALines traegt (ab Zeile 4).
function InImpl(const ALines: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation']) + #13#10
    + Join(ALines) + #13#10 + 'end.';
end;

// Die Meldungen der Detektoren.
function CondMsg(const AX, AFirst, ASecond: string): string;
begin
  Result := Format('`if Cond then %s := %s else %s := %s` can be simplified '
    + 'to `%s := Cond` (or `not Cond`).', [AX, AFirst, AX, ASecond, AX]);
end;

function JumpMsg(const AWord: string): string;
begin
  Result := Format('`%s;` directly before `end` is redundant - control flow '
    + 'already leaves the block.', [AWord]);
end;

function SelfMsg(const AX: string): string;
begin
  Result := Format('Self-assignment: %s := %s (no-op or copy-paste)',
    [AX, AX]);
end;

// ---- SCA098 ----

procedure TTestRdxFlowFixes.Sca098_Forward;
var
  R : string;
  P : TRdxFlowPlan;
begin
  // Ueber vier Zeilen: eine Zeile, Einrueckung des if.
  Assert.AreEqual(InProc(['  FActive := R.Contains(P);']),
    Fix(wkCond, InProc(['  if R.Contains(P) then', '    FActive := True',
      '  else', '    FActive := False;']), 6,
      CondMsg('FActive', 'True', 'False'), R), R);
  // Schreibweise der Zuweisung wie im then-Zweig; Gross/klein der Werte.
  Assert.AreEqual(InProc(['  Result:=aChar in [''a'', ''b''];']),
    Fix(wkCond, InProc(['  if aChar in [''a'', ''b''] then Result:=True else '
      + 'Result:=False;']), 6, CondMsg('Result', 'True', 'False'), R), R);
  Assert.AreEqual(InProc(['  Flag := A > B']),
    Fix(wkCond, InProc(['  if A > B then Flag := TRUE else flag := FALSE']), 6,
      CondMsg('Flag', 'TRUE', 'FALSE'), R), R);
  P := PlanOf(wkCond, InProc(['  if A > B then Flag := True else Flag := '
    + 'False;']), 6, CondMsg('Flag', 'True', 'False'), R);
  Assert.AreEqual('', R);
  Assert.AreEqual('Flag', P.Target);
  Assert.IsFalse(P.Negated, 'vorwaerts');
  // Ohne ';' vor dem end eines Blocks: das end beendet die Anweisung
  // (STMT_STOPS; Review Woche G07-26 - bis dahin ohne Test).
  Assert.AreEqual(InProc(['  begin Ok := A end;']),
    Fix(wkCond, InProc(['  begin if A then Ok := True else Ok := False end;']),
      6, CondMsg('Ok', 'True', 'False'), R), R);
end;

procedure TTestRdxFlowFixes.Sca098_Negated;
var
  R : string;
  P : TRdxFlowPlan;
begin
  // Zusammengesetztes C in Klammern - ein Vergleich beweist Boolean.
  Assert.AreEqual(InProc(['  Done := not (A > B);']),
    Fix(wkCond, InProc(['  if A > B then Done := False else Done := True;']), 6,
      CondMsg('Done', 'False', 'True'), R), R);
  P := PlanOf(wkCond, InProc(['  if A > B then Done := False else Done := '
    + 'True;']), 6, CondMsg('Done', 'False', 'True'), R);
  Assert.IsTrue(P.Negated and P.CondBoolean, 'Vergleich');
  Assert.AreEqual<Integer>(0, Length(P.CondIdents));
  // Ein Operand ohne Klammern: Pfad mit Aufruf - der Form nach nicht
  // Boolean (der Laeufer lehnt die Gegenrichtung ab).
  P := PlanOf(wkCond, InProc(['  if List.IsEmpty(1) then Done := False else '
    + 'Done := True;']), 6, CondMsg('Done', 'False', 'True'), R);
  Assert.AreEqual('Done := not List.IsEmpty(1)', P.Edit.NewText);
  Assert.IsFalse(P.CondBoolean, 'Aufruf');
  // Ein Bezeichner: Boolean, wenn sein Typ es ist (der Laeufer prueft).
  P := PlanOf(wkCond, InProc(['  if Ready then Done := False else Done := '
    + 'True;']), 6, CondMsg('Done', 'False', 'True'), R);
  Assert.IsTrue(P.CondBoolean and (Length(P.CondIdents) = 1), 'Bezeichner');
  Assert.AreEqual('Ready', P.CondIdents[0]);
  Assert.AreEqual('Done := not Ready', P.Edit.NewText);
  // or ueber geklammerte Vergleiche und einen Bezeichner, not davor.
  P := PlanOf(wkCond, InProc(['  if (P = 0) or not (S[P] = ''N'') or Flag then '
    + 'Done := False else Done := True;']), 6, CondMsg('Done', 'False', 'True'),
    R);
  Assert.IsTrue(P.CondBoolean and (Length(P.CondIdents) = 1), 'or-Kette');
  Assert.AreEqual('Flag', P.CondIdents[0]);
  // Arithmetik als Operand ist nicht Boolean.
  P := PlanOf(wkCond, InProc(['  if (A + B) and C then Done := False else '
    + 'Done := True;']), 6, CondMsg('Done', 'False', 'True'), R);
  Assert.IsFalse(P.CondBoolean, 'Arithmetik');
  // Schon geklammert: keine zweiten Klammern; 'and' auf oberster Ebene: ja.
  Assert.AreEqual(InProc(['  Done := not (A and B);']),
    Fix(wkCond, InProc(['  if (A and B) then Done := False else Done := '
      + 'True;']), 6, CondMsg('Done', 'False', 'True'), R), R);
  Assert.AreEqual(InProc(['  Done := not (A and B);']),
    Fix(wkCond, InProc(['  if A and B then Done := False else Done := True;']),
      6, CondMsg('Done', 'False', 'True'), R), R);
  // Review Woche G07-15: 'not R' mit einem Operanden R verliert das not,
  // statt 'not (not R)' zu werden; 'not A = B' ist '(not A) = B' und bleibt
  // geklammert.
  Assert.AreEqual(InProc(['  Done := Ready;']),
    Fix(wkCond, InProc(['  if not Ready then Done := False else Done := '
      + 'True;']), 6, CondMsg('Done', 'False', 'True'), R), R);
  Assert.AreEqual(InProc(['  Done := (A or B);']),
    Fix(wkCond, InProc(['  if not (A or B) then Done := False else Done := '
      + 'True;']), 6, CondMsg('Done', 'False', 'True'), R), R);
  Assert.AreEqual(InProc(['  Done := not (not A = B);']),
    Fix(wkCond, InProc(['  if not A = B then Done := False else Done := '
      + 'True;']), 6, CondMsg('Done', 'False', 'True'), R), R);
end;

procedure TTestRdxFlowFixes.Sca098_LinesAndNesting;
var
  R : string;
begin
  // Zeilenumbrueche in C bleiben.
  Assert.AreEqual(InProc(['  Result := (A > 0) and', '     (B > 0);']),
    Fix(wkCond, InProc(['  if (A > 0) and', '     (B > 0) then Result := True '
      + 'else Result := False;']), 6, CondMsg('Result', 'True', 'False'), R), R);
  // else if: nur das zweite if.
  Assert.AreEqual(InProc(['  if A then X := 1', '  else Ok := B;']),
    Fix(wkCond, InProc(['  if A then X := 1', '  else if B then Ok := True else '
      + 'Ok := False;']), 7, CondMsg('Ok', 'True', 'False'), R), R);
  // Verschachtelt: das innere if bekommt sein else, das aeussere behaelt
  // seines.
  Assert.AreEqual(InProc(['  if A then Ok := B else Ok := True;']),
    Fix(wkCond, InProc(['  if A then if B then Ok := True else Ok := False '
      + 'else Ok := True;']), 6, CondMsg('Ok', 'True', 'False'), R), R);
end;

procedure TTestRdxFlowFixes.Sca098_Refusals;
const
  MSG_OK = '`if Cond then Ok := True else Ok := False` can be simplified to '
    + '`Ok := Cond` (or `not Cond`).';
begin
  AssertRefused(wkCond, InProc(['  if A then Ok := True // weil', '  else Ok := '
    + 'False;']), 6, MSG_OK, 'Kommentar');
  AssertRefused(wkCond, InProc(['  if A then Ok := True else Ok := False; '
    + 'if B then Ok := True else Ok := False;']), 6, MSG_OK, 'mehrdeutig');
  AssertRefused(wkCond, InProc(['  if A then Ok := True else Ok := False or '
    + 'B;']), 6, MSG_OK, 'geht der Ausdruck weiter');
  AssertRefused(wkCond, InProc(['  if A then begin Ok := True end else Ok := '
    + 'False;']), 6, MSG_OK, 'verschoben');
  // ';' vor dem else: das else gehoert zum case.
  AssertRefused(wkCond, InProc(['  case K of 1: if A then Ok := True; else '
    + 'Ok := False; end;']), 6, MSG_OK, 'verschoben');
  AssertRefused(wkCond, InProc(['  if A then Ok := True else Ok := False;']), 6,
    CondMsg('Other', 'True', 'False'), 'verschoben');
  AssertRefused(wkCond, InProc(['  if A then Ok := True else Ok := False;']), 6,
    'something else', 'Meldung');
end;

// ---- SCA080 ----

procedure TTestRdxFlowFixes.Sca080_OwnLine;
var
  R : string;
begin
  // Das Katalog-Beispiel: die Zeile faellt weg.
  Assert.AreEqual(InProc(['  DoStuff;']),
    Fix(wkJump, InProc(['  DoStuff;', '  Exit;']), 7, JumpMsg('exit'), R), R);
  // Continue am Ende des Schleifenrumpfs, Kette ueber vier end.
  Assert.AreEqual(InProc(['  for I := 0 to 9 do', '  begin', '    if A then',
      '    begin', '      Foo;', '    end;', '  end;']),
    Fix(wkJump, InProc(['  for I := 0 to 9 do', '  begin', '    if A then',
      '    begin', '      Foo;', '      Continue;', '    end;', '  end;']), 11,
      JumpMsg('continue'), R), R);
  // FPC-Schreibweise.
  Assert.AreEqual(InProc(['  foo;']),
    Fix(wkJump, InProc(['  foo;', '  exit;']), 7, JumpMsg('exit'), R), R);
end;

procedure TTestRdxFlowFixes.Sca080_Inline;
var
  R : string;
  P : TRdxFlowPlan;
begin
  Assert.AreEqual(InProc(['  Foo;']),
    Fix(wkJump, InProc(['  Foo; Exit;']), 6, JumpMsg('exit'), R), R);
  // Exit vor 'end;' auf derselben Zeile.
  Assert.AreEqual(InProc(['  if A then', '  begin', '    Foo;', '    end;']),
    Fix(wkJump, InProc(['  if A then', '  begin', '    Foo;', '    Exit; end;']),
      9, JumpMsg('exit'), R), R);
  // Eine schon beendete Schleife davor zaehlt nicht (uRedundantJump).
  Assert.AreEqual(InProc(['  while A do Inc(I);']),
    Fix(wkJump, InProc(['  while A do Inc(I);', '  Exit;']), 7, JumpMsg('exit'),
      R), R);
  P := PlanOf(wkJump, InProc(['  Foo;', '  EXIT;']), 7, JumpMsg('exit'), R);
  Assert.AreEqual('EXIT', P.Target);
end;

procedure TTestRdxFlowFixes.Sca080_ElseExit;
var
  R : string;
begin
  Assert.AreEqual(InProc(['  if A then Foo;']),
    Fix(wkJump, InProc(['  if A then Foo else Exit;']), 6, JumpMsg('exit'), R),
    R);
  Assert.AreEqual(InProc(['  if A then', '    Foo;']),
    Fix(wkJump, InProc(['  if A then', '    Foo', '  else', '    Exit;']), 9,
      JumpMsg('exit'), R), R);
  // Ein String als letztes Zeichen des then-Zweigs.
  Assert.AreEqual(InProc(['  if A then S := ''x'';']),
    Fix(wkJump, InProc(['  if A then S := ''x'' else Exit;']), 6,
      JumpMsg('exit'), R), R);
  // else eines case: der Sprung ist dort die einzige Anweisung der Liste.
  AssertRefused(wkJump, InProc(['  case K of 1: Foo; else Exit; end;']), 6,
    JumpMsg('exit'), 'case bzw. except');
  // Ein Kommentar zwischen then-Zweig und else auf der Zeile davor ginge
  // mit (Review Woche G07-26 - bis dahin ohne Test; auf der Zeile des
  // Sprungs sperrt schon R_LINE_COMMENT).
  AssertRefused(wkJump, InProc(['  if A then Foo {x}', '  else Exit;']), 7,
    JumpMsg('exit'), 'Kommentar zwischen then-Zweig und Sprung');
end;

procedure TTestRdxFlowFixes.Sca080_ChainTerminators;
var
  R : string;
begin
  // Review Woche G07-26: die Terminatoren der end-Kette (ChainEnds, wie
  // uRedundantJump) ausser Dateiende und 'end.'. Continue am Ende eines
  // Blocks direkt vor 'until'.
  Assert.AreEqual(InProc(['  repeat', '    if A then', '    begin', '      Foo;',
      '    end;', '  until B;']),
    Fix(wkJump, InProc(['  repeat', '    if A then', '    begin', '      Foo;',
      '      Continue;', '    end;', '  until B;']), 10, JumpMsg('continue'),
      R), R);
  // Zwei end vor dem Kopf der naechsten Routine.
  Assert.AreEqual(InImpl(['procedure P;', 'begin', '  if A then', '  begin',
      '    Foo;', '  end;', 'end;', 'procedure Q;', 'begin', 'end;']),
    Fix(wkJump, InImpl(['procedure P;', 'begin', '  if A then', '  begin',
      '    Foo;', '    Exit;', '  end;', 'end;', 'procedure Q;', 'begin',
      'end;']), 9, JumpMsg('exit'), R), R);
  // Ein end allein vor einem Routinenkopf genuegt nicht (wie der Detektor).
  AssertRefused(wkJump, InImpl(['procedure P;', 'begin', '  Foo;', '  Exit;',
    'end;', 'procedure Q;', 'begin', 'end;']), 7, JumpMsg('exit'),
    'folgt noch Code');
end;

procedure TTestRdxFlowFixes.Sca080_ContextRefusals;
begin
  AssertRefused(wkJump, InProc(['  if A then Exit;']), 6, JumpMsg('exit'),
    'hinter then');
  AssertRefused(wkJump, InProc(['  case K of 1: Exit; end;']), 6,
    JumpMsg('exit'), 'case-Zweigs');
  AssertRefused(wkJump, InProc(['  if A then', '  begin', '    Exit;',
    '  end;']), 8, JumpMsg('exit'), 'leerer Block');
  AssertRefused(wkJump, InProc(['  try', '    Foo;', '  except', '    Exit;',
    '  end;']), 9, JumpMsg('exit'), 'leerer Block');
end;

procedure TTestRdxFlowFixes.Sca080_DetectorRefusals;
begin
  // Dahinter folgt Code; Exit in einer Schleife; zwei Spruenge.
  AssertRefused(wkJump, InProc(['  Exit;', '  Foo;']), 6, JumpMsg('exit'),
    'folgt noch Code');
  AssertRefused(wkJump, InProc(['  for I := 0 to 9 do', '  begin',
    '    if A then', '    begin', '      Foo;', '      Exit;', '    end;',
    '  end;']), 11, JumpMsg('exit'), 'Schleife');
  AssertRefused(wkJump, InProc(['  if A then Continue; Exit;']), 6,
    JumpMsg('exit'), 'mehrdeutig');
  AssertRefused(wkJump, InProc(['  Foo;', '  Exit; // fertig']), 7,
    JumpMsg('exit'), 'Kommentar');
  // Eine eigene Routine Exit: 'Exit;' riefe sie auf.
  AssertRefused(wkJump, InImpl(['procedure Exit;', 'begin', 'end;',
    'procedure P;', 'begin', '  Foo;', '  Exit;', 'end;']), 10, JumpMsg('exit'),
    'eigene Routine');
  // finally: uebersetzt nicht (E2126/06040) - trotzdem abgelehnt.
  AssertRefused(wkJump, InProc(['  try', '    Foo;', '  finally', '    Bar;',
    '    Exit;', '  end;']), 10, JumpMsg('exit'), 'finally');
  AssertRefused(wkJump, InProc(['  Foo;']), 6, JumpMsg('exit'), 'verschoben');
end;

// ---- SCA047 ----

procedure TTestRdxFlowFixes.Sca047_Delete;
var
  R : string;
  P : TRdxFlowPlan;
begin
  Assert.AreEqual(InProc(['  Foo;', '  Bar;']),
    Fix(wkSelf, InProc(['  Foo;', '  Temp := Temp;', '  Bar;']), 7,
      SelfMsg('Temp'), R), R);
  Assert.AreEqual(InProc(['  Foo; Bar;']),
    Fix(wkSelf, InProc(['  Foo; Temp := Temp; Bar;']), 6, SelfMsg('Temp'), R),
    R);
  // Pfad mit Leerraum und Gross/klein wie der Detektor (Normalize).
  Assert.AreEqual(InProc(['  Foo;']),
    Fix(wkSelf, InProc(['  Foo;', '  pt . Y := Pt.y;']), 7, SelfMsg('pt.Y'), R),
    R);
  P := PlanOf(wkSelf, InProc(['  Foo;', '  pt . Y := Pt.y;']), 7,
    SelfMsg('pt.Y'), R);
  Assert.AreEqual('pt . Y', P.Target);
  Assert.AreEqual(InProc(['  Foo;']),
    Fix(wkSelf, InProc(['  Foo; R^.F := R^.F;']), 6, SelfMsg('R^.F'), R), R);
  // Letzte Anweisung ohne ';'.
  Assert.AreEqual(InProc(['  Foo;']),
    Fix(wkSelf, InProc(['  Foo;', '  Angle := angle']), 7, SelfMsg('Angle'), R),
    R);
end;

procedure TTestRdxFlowFixes.Sca047_Refusals;
begin
  AssertRefused(wkSelf, InProc(['  Foo;', '  Result := Result;']), 7,
    SelfMsg('Result'), 'Result');
  AssertRefused(wkSelf, InImpl(['function F: Integer;', 'begin', '  Foo;',
    '  F := F;', 'end;']), 7, SelfMsg('F'), 'Routine');
  AssertRefused(wkSelf, InImpl(['type', '  TR = record',
    '    class operator Assign(var D: TR; const [ref] S: TR);', '  end;',
    'procedure P;', 'begin', '  Foo;', '  X := X;', 'end;']), 11, SelfMsg('X'),
    'operator Assign');
  // 'Assign' erst auf der Zeile hinter 'operator': der Vorfilter je Zeile
  // (Review R3-03, Charge FC) sucht die Zeilen mit 'operator'.
  AssertRefused(wkSelf, InImpl(['type', '  TR = record', '    class operator',
    '      Assign(var D: TR; const [ref] S: TR);', '  end;', 'procedure P;',
    'begin', '  Foo;', '  X := X;', 'end;']), 12, SelfMsg('X'), 'operator Assign');
  AssertRefused(wkSelf, InProc(['  Foo;', '  Pt.Y := Pt.Y; // + Scroll']), 7,
    SelfMsg('Pt.Y'), 'Kommentar');
  // FPC-Parser-Fehlalarm: 'out.n_points := n_points' ist keine
  // Selbstzuweisung.
  AssertRefused(wkSelf, InProc(['  Foo;', '  out.n_points := n_points;']), 7,
    SelfMsg('n_points'), 'verschoben');
  AssertRefused(wkSelf, InProc(['  Foo;', '  X :=', '    X;']), 7, SelfMsg('X'),
    'mehrere Zeilen');
  AssertRefused(wkSelf, InProc(['  Foo; X := X; X := X;']), 6, SelfMsg('X'),
    'mehrdeutig');
  AssertRefused(wkSelf, InProc(['  Foo; X := X + 1;']), 6, SelfMsg('X'),
    'verschoben');
end;

procedure TTestRdxFlowFixes.Sca047_Context;
var
  R : string;
begin
  AssertRefused(wkSelf, InProc(['  if A then X := X;']), 6, SelfMsg('X'),
    'hinter then');
  AssertRefused(wkSelf, InProc(['  if A then X := 1 else X := X;']), 6,
    SelfMsg('X'), 'hinter else');
  AssertRefused(wkSelf, InProc(['  case K of 1: X := X; end;']), 6,
    SelfMsg('X'), 'case-Zweigs');
  AssertRefused(wkSelf, InProc(['  if A then', '  begin', '    X := X;',
    '  end;']), 8, SelfMsg('X'), 'leerer Block');
  // Erste Anweisung eines Blocks, hinter der noch eine folgt.
  Assert.AreEqual(InProc(['  Foo;']),
    Fix(wkSelf, InProc(['  X := X;', '  Foo;']), 6, SelfMsg('X'), R), R);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxFlowFixes);

end.
