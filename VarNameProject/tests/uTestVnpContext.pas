unit uTestVnpContext;

// VarNameProject - Tests fuer den Zusammenhang ueber mehrere Zeilen in
// uVnpEdits.TargetAt (Pruefer 2026-10-13, Bericht F mit FPC-Harness aus 24
// Gegenbeispielen): mehrzeilige Strings mit mehr als drei Quotes, die
// Kommentargrenzen eines begin..end, asm-Block und initialization-
// Abschnitt, Direktiven zwischen der Zeile darueber und der Anweisung auch
// ohne Block (und am Anfang der Anweisungszeile), die Zeile darueber ab
// ihrem Kommentar-Zustand, '*)' in Spalte 1, der else-Arm eines
// Bedingungsausdrucks (Delphi 13), die FPC-Weiche, Zeilenenden je Zeile
// und die Vorbedingung von
// IntroduceEdits. Jeder Fall hier ist eine Stelle, an der die Hilfe sonst
// Code erzeugt haette, der nicht uebersetzt - oder still anders laeuft
// (Deklaration IM String, 'end;' im Kommentar, Zeile im asm-Block).
//
// Vertrag wie in uTestVnpGuards: Interface-Kommentare von uVnpPlan und
// uVnpEdits, README Grenzen; Erwartungen von Hand, Spalten 1-basierte
// Zeichenspalten der Zeile. Puffer mit CR LF, wo nichts anderes steht.
// Quelltext nur ASCII.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestVnpContext = class
  public
    // Vor dem Plan: wo gar kein Code ist
    [Test] procedure MultiLineString_FiveQuotes;
    [Test] procedure AsmBlock;
    [Test] procedure InitializationSection;
    [Test] procedure FpcAwareUnit;
    // Die Zeile darueber und die Zeilen dazwischen
    [Test] procedure DirectiveAbovePlainStatement;
    [Test] procedure PrevLineStartsInComment;
    [Test] procedure StarParenAtColumnOneAbove;
    // Grenzen des Blocks bei einem Zweig ohne begin
    [Test] procedure Wrap_OpenCommentAtStatementEnd;
    [Test] procedure Wrap_OpenCommentAtBranchEnd;
    [Test] procedure Wrap_ElseOfIfExpression;
    // Zeilenenden und Vorbedingung
    [Test] procedure RowEol_MixedEndings;
    [Test] procedure IntroduceEdits_RefusedPlanIsEmpty;
    // Gegen-Review Welle 1 (Pruefer 2026-10-14, a-d)
    [Test] procedure Wrap_IfExpressionArmsOnOwnLines;
    [Test] procedure DirectiveOnPrevLine;
    [Test] procedure MultiLineString_ReopenedAfterCloser;
    [Test] procedure CommentAndStringStates_Combined;
    [Test] procedure AsmLabel_DoesNotEndAsm;
    // Review Woche 2026-10-21 (G10-02)
    [Test] procedure DirectiveOnStatementLine;
  end;

implementation

uses
  System.SysUtils, uVnpPlan, uVnpEdits;

const
  NAME_BASE = 'MagicNr';

// Die Zeilen ab AFrom mit AEol verbunden - rekursiv statt Verkettung in
// einer Schleife (SCA110); es sind nur wenige Zeilen.
function JoinFrom(const ALines: array of string; AFrom: Integer;
  const AEol: string): string;
begin
  if AFrom = High(ALines) then
    Result := ALines[AFrom]
  else
    Result := ALines[AFrom] + AEol + JoinFrom(ALines, AFrom + 1, AEol);
end;

// Die Zeilen mit CR LF verbunden, mit Zeilenende am Pufferende.
function Buf(const ALines: array of string): string;
begin
  Result := '';
  if Length(ALines) > 0 then
    Result := JoinFrom(ALines, 0, #13#10) + #13#10;
end;

// Der Text zum Puffer ABuffer (UTF-8).
function TextIn(const ABuffer: string): TVnpText;
begin
  Result := TextOf(TEncoding.UTF8.GetBytes(ABuffer));
end;

// Das Ziel fuer den Caret in Zeile ARow, Spalte ACol des Puffers.
function TargetIn(const ABuffer: string; ARow, ACol: Integer): TVnpTarget;
begin
  Result := TargetAt(TextIn(ABuffer), ARow, ACol, NAME_BASE);
end;

// C1h ohne IDE: der Text nach den Ersetzungen (ApplyByteEdits stellt den
// IOTAEditWriter nach).
function RunC1h(const ABuffer: string; ARow, ACol: Integer): string;
var
  T : TVnpText;
  G : TVnpTarget;
  B : TBytes;
begin
  B := TEncoding.UTF8.GetBytes(ABuffer);
  T := TextOf(B);
  G := TargetAt(T, ARow, ACol, NAME_BASE);
  Assert.IsTrue(G.Plan.Ok, 'Plan abgelehnt: ' + G.Plan.Reason);
  Result := TEncoding.UTF8.GetString(ApplyByteEdits(B, IntroduceEdits(T, G)));
end;

// Das Ziel wird abgelehnt, und der Grund nennt AKeyword.
procedure AssertRefusedWith(const G: TVnpTarget; const AKeyword, AMsg: string);
begin
  Assert.IsFalse(G.Plan.Ok, AMsg + ' - Plan "' + G.Plan.NewUseLine + '"');
  Assert.IsTrue(Pos(AKeyword, G.Plan.Reason) > 0,
    AMsg + ', Grund: ' + G.Plan.Reason);
end;

// Das Ziel wird angenommen, mit Block (AWrap) und der Zeile darueber.
procedure AssertAccepted(const G: TVnpTarget; AWrap: Boolean;
  APrevRow: Integer; const AMsg: string);
begin
  Assert.IsTrue(G.Plan.Ok, AMsg + ': ' + G.Plan.Reason);
  Assert.IsTrue(G.Plan.Wrap = AWrap, AMsg + ', Wrap');
  Assert.AreEqual<Integer>(APrevRow, G.PrevRow, AMsg + ', PrevRow');
end;

// N Quotes.
function Q(N: Integer): string;
begin
  Result := StringOfChar('''', N);
end;

{ TTestVnpContext }

// Ein mehrzeiliger String mit fuenf Quotes (Delphi 12): eine Inhaltszeile,
// die mit drei Quotes beginnt, schliesst ihn NICHT - nur genau fuenf am
// Zeilenanfang (Pruefer 2026-10-13, Blocker 2, Harness 23: 'SELECT 42'
// galt als Code, die Deklaration landete im String und kompilierte). Auch
// umgekehrt: bei einem Drei-Quote-String schliesst eine Zeile mit fuenf
// Quotes nicht. Hinter dem Ende geht es wieder.
procedure TTestVnpContext.MultiLineString_FiveQuotes;
var
  B : string;
begin
  B := Buf(['procedure P;', 'begin', '  S := ' + Q(5), '    ' + Q(3)
    + ' quoted;', '    SELECT 42', '    ' + Q(5) + ';', '  X := 42;', 'end;']);
  // Zeile 5, die 42 in Spalte 12.
  AssertRefusedWith(TargetIn(B, 5, 12), 'mehrzeiligen String',
    'Inhaltszeile hinter ''''''');
  AssertRefusedWith(TargetIn(B, 4, 5), 'mehrzeiligen String',
    'Zeile mit drei Quotes im Fuenf-Quote-String');
  // Zeile 7, die 42 in Spalte 8: der String ist zu.
  AssertAccepted(TargetIn(B, 7, 8), False, 6, 'hinter dem String');
  Assert.AreEqual('  X := MagicNr01;', TargetIn(B, 7, 8).Plan.NewUseLine,
    'hinter dem String, NewUseLine');
  B := Buf(['begin', '  S := ' + Q(3), '    ' + Q(5) + ' x', '    SELECT 42',
    '    ' + Q(3) + ';', 'end;']);
  AssertRefusedWith(TargetIn(B, 4, 12), 'mehrzeiligen String',
    'Zeile mit fuenf Quotes im Drei-Quote-String');
end;

// In einem asm-Block ist ';' nur ein Trenner und 'mov eax, 1' keine
// Anweisung - die Zeile darueber "endet" mit ';', der Zeilen-Leser nahm
// sie an (Pruefer 2026-10-13, Harness 4). Hinter dem 'end' des Blocks und
// nach einem einzeiligen 'asm ... end;' ist wieder Pascal-Code.
procedure TTestVnpContext.AsmBlock;
var
  B : string;
begin
  B := Buf(['procedure P;', 'asm', '  mov eax, 1;', '  mov edx, 5', 'end;',
    '', 'procedure Q;', 'begin', '  X := 42;', 'end;']);
  // Zeile 4, die 5 in Spalte 12; Zeile 3, die 1 in Spalte 12.
  AssertRefusedWith(TargetIn(B, 4, 12), 'asm-Block', 'zweite asm-Zeile');
  AssertRefusedWith(TargetIn(B, 3, 12), 'asm-Block', 'erste asm-Zeile');
  // Zeile 9, die 42 in Spalte 8.
  AssertAccepted(TargetIn(B, 9, 8), False, 8, 'hinter dem asm-Block');
  B := Buf(['begin', '  asm int 3; end;', '  X := 42;', 'end;']);
  AssertAccepted(TargetIn(B, 3, 8), False, 2, 'hinter einzeiligem asm');
end;

// Im initialization- und finalization-Abschnitt ist nicht gemessen, ob
// eine Inline-Deklaration gilt - auch hinter der ersten Anweisung des
// Abschnitts (Pruefer 2026-10-13, Harness 11: die Zeile darueber 'Foo;'
// endet eine Anweisung). Das Wort in einem String oeffnet keinen
// Abschnitt.
procedure TTestVnpContext.InitializationSection;
var
  B : string;
begin
  B := Buf(['initialization', '  Foo;', '  Bar(42);', 'end.']);
  // Zeile 3, die 42 in Spalte 7.
  AssertRefusedWith(TargetIn(B, 3, 7), 'initialization',
    'zweite Anweisung in initialization');
  B := Buf(['initialization', '  Foo;', 'finalization', '  Bar(42);', 'end.']);
  AssertRefusedWith(TargetIn(B, 4, 7), 'initialization',
    'Anweisung in finalization');
  B := Buf(['begin', '  S := ''initialization'';', '  X := 42;', 'end;']);
  AssertAccepted(TargetIn(B, 3, 8), False, 2, 'Wort im String');
end;

// Eine Datei mit FPC-Weiche oder FPC-Modus (uVnpPlan.LineLooksFpcAware,
// irgendwo in der Datei): eine Inline-Konstante gibt es in FPC 3.2 nicht,
// die Aktion braeche den FPC-Bau (Bericht B, Befund 1c). Andere
// Direktiven stoeren nicht.
procedure TTestVnpContext.FpcAwareUnit;
var
  B : string;
begin
  B := Buf(['unit U;', '{$IFDEF FPC}{$MODE delphi}{$ENDIF}', 'interface',
    'implementation', 'procedure P;', 'begin', '  X := 42;', 'end;', 'end.']);
  // Zeile 7, die 42 in Spalte 8.
  AssertRefusedWith(TargetIn(B, 7, 8), 'FPC', 'IFDEF FPC am Dateikopf');
  B := Buf(['procedure P;', 'begin', '  X := 42;', 'end;', '',
    'initialization', '{$if defined(fpc)}', 'end.']);
  AssertRefusedWith(TargetIn(B, 3, 8), 'FPC', 'if defined(fpc) weiter unten');
  B := Buf(['{$IFDEF DEBUG}', 'procedure P;', 'begin', '  X := 42;', 'end;',
    '{$ENDIF}']);
  AssertAccepted(TargetIn(B, 4, 8), False, 3, 'IFDEF DEBUG');
end;

// Eine Direktive zwischen der Zeile darueber und der Anweisung sperrt JEDEN
// Plan, nicht nur den mit Block: '{$IFDEF A} if B then {$ELSE} Foo;
// {$ENDIF}' ueber 'Y := 42;' - ohne A endet 'Foo;' die Anweisung, mit A
// stuende die Deklaration hinter 'then' (Pruefer 2026-10-13, Major 4,
// Harness 7). Eine Direktive OBERHALB der Zeile darueber stoert nicht.
procedure TTestVnpContext.DirectiveAbovePlainStatement;
var
  B : string;
begin
  B := Buf(['procedure P;', 'begin', '{$IFDEF A}', '  if B then', '{$ELSE}',
    '  Foo;', '{$ENDIF}', '  Y := 42;', 'end;']);
  // Zeile 8, die 42 in Spalte 8.
  AssertRefusedWith(TargetIn(B, 8, 8), 'Direktive',
    'ENDIF zwischen Foo; und der Anweisung');
  B := Buf(['begin', '{$IFDEF A}', '  Foo;', '  Y := 42;', '{$ENDIF}',
    'end;']);
  AssertAccepted(TargetIn(B, 4, 8), False, 3, 'Direktive oberhalb');
end;

// Die Zeile darueber zaehlt ab ihrem Kommentar-Zustand: '  Foo; // } if A
// then' hinter '{ Beispiel:' ist der Zweig ' if A then' (das 'Foo; //'
// liegt im Kommentar) - vorher las TargetAt sie ab Code, sah 'Foo;' und
// setzte die Deklaration hinter das then (Pruefer 2026-10-13, Minor 1,
// Harness 9). Der Block bekommt die Einrueckung der rohen Zeile.
procedure TTestVnpContext.PrevLineStartsInComment;
var
  B : string;
begin
  B := Buf(['procedure P;', 'begin', '  { Beispiel:', '  Foo; // } if A then',
    '    X := 42;', 'end;']);
  // Zeile 5, die 42 in Spalte 10.
  AssertAccepted(TargetIn(B, 5, 10), True, 4, 'Zweig hinter Kommentar');
  Assert.AreEqual(Buf(['procedure P;', 'begin', '  { Beispiel:',
    '  Foo; // } if A then', '  begin', '    const MagicNr01 = 42;',
    '    X := MagicNr01;', '  end;', 'end;']), RunC1h(B, 5, 10),
    'Zweig hinter Kommentar: Text danach');
  // Umgekehrt: hinter dem Kommentar endet eine Anweisung.
  B := Buf(['begin', '  { x', '  if A then } Foo;', '  X := 42;', 'end;']);
  AssertAccepted(TargetIn(B, 4, 8), False, 3, 'Anweisung hinter Kommentar');
end;

// Ein '*)' in Spalte 1 ist das Ende des Kommentars, kein Code: die Zeile
// zaehlt nicht als Zeile darueber (Pruefer 2026-10-13, Minor 2: das ')'
// galt als Code, und der Plan lehnte ab - "unklar"). Steht hinter dem
// '*)' Code, ist genau der die Zeile darueber.
procedure TTestVnpContext.StarParenAtColumnOneAbove;
var
  B : string;
begin
  B := Buf(['begin', '  X := 1;', '  (* alt', '*)', '  Y := 42;', 'end;']);
  // Zeile 5, die 42 in Spalte 8.
  AssertAccepted(TargetIn(B, 5, 8), False, 2, '*) allein');
  Assert.AreEqual('  Y := MagicNr01;', TargetIn(B, 5, 8).Plan.NewUseLine,
    '*) allein, NewUseLine');
  B := Buf(['begin', '  (* alt', '*) X := 1;', '  Y := 42;', 'end;']);
  AssertAccepted(TargetIn(B, 4, 8), False, 3, '*) mit Code dahinter');
  B := Buf(['begin', '  (* alt', '*) if A then', '    Y := 42;', 'end;']);
  AssertAccepted(TargetIn(B, 4, 10), True, 3, '*) mit Zweig dahinter');
end;

// Endet die Anweisungszeile in einem offenen { }- oder (* *)-Kommentar,
// landete 'end;' im Kommentar - und Code hinter dem Kommentarende ('}
// Y := 1;') rutschte in den Block (Pruefer 2026-10-13, Major 3, Harness
// 5/20/24). Ein Kommentar, der auf der Zeile schliesst, stoert nicht.
procedure TTestVnpContext.Wrap_OpenCommentAtStatementEnd;
var
  B : string;
begin
  B := Buf(['procedure P;', 'begin', '  if A then', '    X := 42; { Kommentar',
    '    geht weiter }', '  Y := 1;', 'end;']);
  // Zeile 4, die 42 in Spalte 10.
  AssertRefusedWith(TargetIn(B, 4, 10), 'offenen Kommentar',
    '{ offen hinter der Anweisung');
  B := Buf(['procedure P;', 'begin', '  while A do',
    '    X := 42; (* Kommentar', '    weiter *)', 'end;']);
  AssertRefusedWith(TargetIn(B, 4, 10), 'offenen Kommentar',
    '(* offen hinter der Anweisung');
  B := Buf(['procedure P;', 'begin', '  if A then', '    X := 42; { c',
    '    } Y := 1;', '  Z := 2;', 'end;']);
  AssertRefusedWith(TargetIn(B, 4, 10), 'offenen Kommentar',
    'Kommentar mit Code hinter dem Ende');
  B := Buf(['procedure P;', 'begin', '  if A then', '    X := 42; { c }',
    '  Y := 1;', 'end;']);
  AssertAccepted(TargetIn(B, 4, 10), True, 3, 'Kommentar schliesst');
end;

// Endet die Zweigzeile in einem offenen Kommentar, landete 'begin' am
// Anfang der naechsten Zeile IM Kommentar (Pruefer 2026-10-13, Major 3,
// Harness 6). Ein Kommentar, der auf der Zweigzeile schliesst, stoert
// nicht - auch nicht ein ganzer Kommentar zwischen Zweig und Anweisung.
procedure TTestVnpContext.Wrap_OpenCommentAtBranchEnd;
var
  B : string;
begin
  B := Buf(['procedure P;', 'begin', '  if A then { Kommentar',
    '    geht weiter }', '    X := 42;', '  Y := 1;', 'end;']);
  // Zeile 5, die 42 in Spalte 10.
  AssertRefusedWith(TargetIn(B, 5, 10), 'Zweigzeile',
    '{ offen hinter dem then');
  B := Buf(['procedure P;', 'begin', '  if A then { kurz }', '    X := 42;',
    'end;']);
  AssertAccepted(TargetIn(B, 4, 10), True, 3, 'Kommentar schliesst');
  B := Buf(['procedure P;', 'begin', '  if A then', '  { ganz',
    '    dazwischen }', '    X := 42;', 'end;']);
  AssertAccepted(TargetIn(B, 6, 10), True, 3, 'Kommentar dazwischen');
  Assert.AreEqual(Buf(['procedure P;', 'begin', '  if A then', '  begin',
    '  { ganz', '    dazwischen }', '    const MagicNr01 = 42;',
    '    X := MagicNr01;', '  end;', 'end;']), RunC1h(B, 6, 10),
    'Kommentar dazwischen: Text danach');
end;

// Das 'else' auf eigener Zeile gehoert zu einem Bedingungsausdruck (Delphi
// 13), wenn die Code-Zeile davor ein 'if' hinter ':=' traegt - ein
// begin..end um den else-Arm waere kein Code (Pruefer 2026-10-13, Minor 3,
// Harness 8). Das 'else' einer if-ANWEISUNG bleibt ein Zweig.
procedure TTestVnpContext.Wrap_ElseOfIfExpression;
var
  B : string;
begin
  B := Buf(['procedure P;', 'begin', '  X := if C then A', '  else',
    '    Foo(42);', 'end;']);
  // Zeile 5, die 42 in Spalte 9.
  AssertRefusedWith(TargetIn(B, 5, 9), 'Bedingungsausdruck',
    'else-Arm des Ausdrucks');
  B := Buf(['procedure P;', 'begin', '  if C then A', '  else', '    Foo(42);',
    'end;']);
  AssertAccepted(TargetIn(B, 5, 9), True, 4, 'else der Anweisung');
  B := Buf(['procedure P;', 'begin', '  if C then', '    A', '  else',
    '    Foo(42);', 'end;']);
  AssertAccepted(TargetIn(B, 6, 9), True, 5,
    'else der Anweisung, Arm darueber');
end;

// Der Bedingungsausdruck ueber mehrere Zeilen (Delphi 13): das 'if' steht
// weiter oben als eine Zeile ueber dem else ('X := if C then' / 'A' /
// 'else' / 'Foo(42);'), oder als erstes Wort einer Zeile hinter einem
// offenen 'X :=' - vorher bekam der else-Arm begin..end mitten im
// Ausdruck (Pruefer 2026-10-14, a). Aufwaerts endet die Suche an einer
// Zeile, die eine Anweisung beendet (';') - das if davor ist dann eine
// Anweisung.
procedure TTestVnpContext.Wrap_IfExpressionArmsOnOwnLines;
var
  B : string;
begin
  B := Buf(['procedure P;', 'begin', '  X := if C then', '    A', '  else',
    '    Foo(42);', 'end;']);
  // Zeile 6, die 42 in Spalte 9.
  AssertRefusedWith(TargetIn(B, 6, 9), 'Bedingungsausdruck',
    'then-Arm auf eigener Zeile, else-Arm darunter');
  B := Buf(['procedure P;', 'begin', '  X :=', '    if C then', '      A',
    '    else', '      Foo(42);', 'end;']);
  AssertRefusedWith(TargetIn(B, 7, 11), 'Bedingungsausdruck',
    'if als erstes Wort hinter X :=');
  // Unvollstaendiger Ausdruck (noch ohne else, mit ';' - mitten im Tippen):
  // Zeile 5, die 42 in Spalte 11, Zweigzeile 'if C then', darueber das
  // offene 'X :=' - vorher bekam die Zeile begin..end.
  B := Buf(['procedure P;', 'begin', '  X :=', '    if C then', '      Foo(42);',
    'end;']);
  AssertRefusedWith(TargetIn(B, 5, 11), 'Bedingungsausdruck',
    'then-Arm hinter if als erstem Wort');
  B := Buf(['procedure P;', 'begin', '  Y := Foo(', '    if C then', '      1',
    '    else', '      Bar(42));', 'end;']);
  AssertRefusedWith(TargetIn(B, 7, 11), 'Bedingungsausdruck',
    'if als Argument hinter Foo(');
  // if-Anweisung: die Zeile ueber dem if beendet eine Anweisung.
  B := Buf(['procedure P;', 'begin', '  Z := 1;', '  if C then', '    A',
    '  else', '    Foo(42);', 'end;']);
  AssertAccepted(TargetIn(B, 7, 9), True, 6, 'if-Anweisung hinter Z := 1;');
  // Ein kompletter Ausdruck DARUEBER (endet mit ';') zaehlt nicht fuer
  // das else weiter unten.
  B := Buf(['procedure P;', 'begin', '  X := if C then A else B;',
    '  if D then', '    A', '  else', '    Foo(42);', 'end;']);
  AssertAccepted(TargetIn(B, 7, 9), True, 6,
    'Ausdruck darueber ist abgeschlossen');
  B := Buf(['procedure P;', 'begin', '  1:', '    if C then', '      Foo(42);',
    'end;']);
  AssertAccepted(TargetIn(B, 5, 11), True, 4, 'if hinter einer case-Marke');
  // Der Ausdruck geht ueber eine then/else-Zeile weiter (Wochen-Review
  // 2026-10-21, in reDelphix G06-18; Folgewelle A7): ein geschachteltes
  // 'if B then' als else-Arm und die else-if-Kette - vorher hielt die
  // Suche an der Zeile mit then/else an, und begin..end landete mitten im
  // Ausdruck. Zeile 5, die 42 in Spalte 11 bzw. 9.
  B := Buf(['procedure P;', 'begin', '  X := if A then 1 else', '    if B then',
    '      Foo(42);', 'end;']);
  AssertRefusedWith(TargetIn(B, 5, 11), 'Bedingungsausdruck',
    'geschachteltes if als else-Arm');
  B := Buf(['procedure P;', 'begin', '  X := if A then 1', '  else if B then',
    '    Foo(42);', 'end;']);
  AssertRefusedWith(TargetIn(B, 5, 9), 'Bedingungsausdruck',
    'else-if-Kette des Ausdrucks');
  // Die Bedingung des Ausdrucks ueber zwei Zeilen: der Gang endet nicht
  // mehr an 'B) then' (README, Grenze bis zur Folgewelle A7). Zeile 7, die
  // 42 in Spalte 9.
  B := Buf(['procedure P;', 'begin', '  X := if (A and', '    B) then',
    '    Foo(1)', '  else', '    Bar(42);', 'end;']);
  AssertRefusedWith(TargetIn(B, 7, 9), 'Bedingungsausdruck',
    'Bedingung ueber zwei Zeilen');
  // Dieselben Formen als Anweisung bleiben Zweige.
  B := Buf(['procedure P;', 'begin', '  if A then Z := 1', '  else if B then',
    '    Foo(42);', 'end;']);
  AssertAccepted(TargetIn(B, 5, 9), True, 4, 'else-if-Kette der Anweisung');
  B := Buf(['procedure P;', 'begin', '  if A then', '    if B then',
    '      Foo(42);', 'end;']);
  AssertAccepted(TargetIn(B, 5, 11), True, 4, 'geschachtelte if-Anweisung');
  B := Buf(['procedure P;', 'begin', '  Z := 1; if B then', '    Foo(42);',
    'end;']);
  AssertAccepted(TargetIn(B, 4, 9), True, 3,
    'if-Anweisung mitten in der Zeile');
end;

// Die Direktive AUF der Zeile darueber zaehlt wie eine dazwischen:
// '{$IFDEF A} if B then {$ELSE} Foo; {$ENDIF}' ueber 'X := 42;' - in
// Konfiguration A stuende 'const' direkt hinter dem then, still (Pruefer
// 2026-10-14, b; vorher lag die Spanne strikt dazwischen). Ein Kommentar
// ohne '$' auf der Zeile darueber stoert nicht.
procedure TTestVnpContext.DirectiveOnPrevLine;
var
  B : string;
begin
  B := Buf(['procedure P;', 'begin',
    '  {$IFDEF A} if B then {$ELSE} Foo; {$ENDIF}', '  X := 42;', 'end;']);
  // Zeile 4, die 42 in Spalte 8.
  AssertRefusedWith(TargetIn(B, 4, 8), 'Direktive',
    'IFDEF/ELSE/ENDIF auf der Zeile darueber');
  B := Buf(['begin', '  Foo; {$ENDIF}', '  X := 42;', 'end;']);
  AssertRefusedWith(TargetIn(B, 3, 8), 'Direktive', 'ENDIF am Zeilenende');
  B := Buf(['begin', '  Foo; (*$ENDIF*)', '  X := 42;', 'end;']);
  AssertRefusedWith(TargetIn(B, 3, 8), 'Direktive', '(*$ENDIF*) am Zeilenende');
  B := Buf(['begin', '  Foo; { kein Dollar }', '  X := 42;', 'end;']);
  AssertAccepted(TargetIn(B, 3, 8), False, 2, 'Kommentar ohne Direktive');
end;

// Hinter dem Schliesser eines mehrzeiligen Strings kann auf derselben
// Zeile ein neuer beginnen (''' + '''): die Zeilen danach sind wieder
// String, keine Code-Zeilen (Pruefer 2026-10-14, c; vorher galt 'SELECT
// 42' als Code, und die Deklaration landete im zweiten String).
procedure TTestVnpContext.MultiLineString_ReopenedAfterCloser;
var
  B : string;
begin
  B := Buf(['procedure P;', 'begin', '  S := ' + Q(3), '    a',
    '    ' + Q(3) + ' + ' + Q(3), '    SELECT 42', '    ' + Q(3) + ';',
    '  X := 42;', 'end;']);
  // Zeile 6, die 42 in Spalte 12: im zweiten String.
  AssertRefusedWith(TargetIn(B, 6, 12), 'mehrzeiligen String',
    'Zeile im wieder geoeffneten String');
  // Zeile 8, die 42 in Spalte 8: hinter dem zweiten Schliesser; die Zeile
  // darueber ist der Schliesser mit ';'.
  AssertAccepted(TargetIn(B, 8, 8), False, 7, 'hinter dem zweiten String');
  // Schliesser mit Code dahinter als Zeile darueber: nur der Code zaehlt.
  B := Buf(['begin', '  S := ' + Q(3), '    a', '    ' + Q(3) + ' + B;',
    '  X := 42;', 'end;']);
  AssertAccepted(TargetIn(B, 5, 8), False, 4, 'Schliesser mit Code dahinter');
  B := Buf(['begin', '  if S = ' + Q(3), '    a', '    ' + Q(3) + ' then',
    '    X := 42;', 'end;']);
  AssertAccepted(TargetIn(B, 5, 10), True, 4,
    'Schliesser mit then dahinter: Zweig');
  // begin..end bekommt die Einrueckung der Zeile, auf der die Anweisung
  // beginnt ('  if S = ...'), nicht die des Codes hinter dem Schliesser
  // (' then': EIN Leerzeichen - Review Woche 2026-10-21, G10-13) und nicht
  // die der rohen Schliesser-Zeile (vier Leerzeichen, so weit wie der
  // Zweig-Inhalt - Folgewelle A7, wie reDelphix uTestRdxIntroContext).
  Assert.AreEqual(Buf(['begin', '  if S = ' + Q(3), '    a',
    '    ' + Q(3) + ' then', '  begin', '    const MagicNr01 = 42;',
    '    X := MagicNr01;', '  end;', 'end;']), RunC1h(B, 5, 10),
    'Schliesser mit then dahinter: Text danach');
end;

// Kommentar- und String-Zustand laufen in EINEM Lauf (Pruefer 2026-10-14,
// Minor zu c): ein ''' am Ende einer Zeile in einem Kommentarblock oeffnet
// keinen String, und ein '{' oder '(*' in einer Inhaltszeile eines
// Strings oeffnet keinen Kommentar.
procedure TTestVnpContext.CommentAndStringStates_Combined;
var
  B : string;
begin
  B := Buf(['begin', '  { Beispiel:', '    S := ' + Q(3), '  }', '  X := 42;',
    'end;']);
  // Zeile 5, die 42 in Spalte 8: kein String offen, Zeile darueber 'begin'.
  AssertAccepted(TargetIn(B, 5, 8), False, 1, 'Oeffner im Kommentarblock');
  B := Buf(['begin', '  (* Beispiel:', '    S := ' + Q(3), '  *)', '  X := 42;',
    'end;']);
  AssertAccepted(TargetIn(B, 5, 8), False, 1, 'Oeffner im (*-Kommentarblock');
  B := Buf(['begin', '  S := ' + Q(3), '    { kein Kommentar', '    (* auch nicht',
    '    ' + Q(3) + ';', '  X := 42;', 'end;']);
  // Zeile 6, die 42 in Spalte 8: die Klammern im String vergiften die
  // Zeilen danach nicht; Zeile darueber ist der Schliesser.
  AssertAccepted(TargetIn(B, 6, 8), False, 5, 'Klammern im String');
  Assert.AreEqual<Integer>(5, PrevCodeRow(TextIn(B), 6),
    'PrevCodeRow: der Schliesser ist die Code-Zeile darueber');
  // Ein Oeffner hinter dem Ende eines Kommentarblocks zaehlt.
  B := Buf(['begin', '  { x', '  } S := ' + Q(3), '    SELECT 42', '    ' + Q(3) + ';',
    'end;']);
  AssertRefusedWith(TargetIn(B, 4, 12), 'mehrzeiligen String',
    'Oeffner hinter dem Kommentarende');
end;

// Die asm-Sprungmarke '@end:' ist kein 'end' - der Block bleibt offen
// (Pruefer 2026-10-14, d; TokensOf trennte das '@' ab, und 'end' beendete
// den asm-Zustand).
procedure TTestVnpContext.AsmLabel_DoesNotEndAsm;
var
  B : string;
begin
  B := Buf(['procedure P;', 'asm', '@end:', '  mov eax, 5', '@@loop:',
    '  mov edx, 1', 'end;', '', 'procedure Q;', 'begin', '  X := 42;', 'end;']);
  // Zeile 4, die 5 in Spalte 12; Zeile 6, die 1 in Spalte 12.
  AssertRefusedWith(TargetIn(B, 4, 12), 'asm-Block', 'hinter @end:');
  AssertRefusedWith(TargetIn(B, 6, 12), 'asm-Block', 'hinter @@loop:');
  // Zeile 11, die 42 in Spalte 8.
  AssertAccepted(TargetIn(B, 11, 8), False, 10, 'hinter dem asm-Block');
end;

// Eingefuegte Zeilen bekommen das Zeilenende der Zeile, vor die sie
// kommen (RowEol): in einer CR-LF-Datei folgt die Deklaration einer
// LF-Anweisungszeile mit LF, 'begin' der Zweigzeile und 'end;' der
// Anweisung; eine LF-Datei mit EINER CR-LF-Zeile bleibt LF (vorher: CR LF,
// sobald eines vorkommt - Pruefer 2026-10-13, Minor 5).
procedure TTestVnpContext.RowEol_MixedEndings;
begin
  Assert.AreEqual('begin'#13#10'  const MagicNr01 = 42;'#10'  X := MagicNr01;'
    + #10'end;'#13#10, RunC1h('begin'#13#10'  X := 42;'#10'end;'#13#10, 2, 8),
    'LF-Anweisung in CR-LF-Datei');
  Assert.AreEqual('begin'#13#10'  if A then'#10'  begin'#10
    + '    const MagicNr01 = 42;'#13#10'    X := MagicNr01;'#13#10'  end;'#13#10
    + 'end;'#10, RunC1h('begin'#13#10'  if A then'#10'    X := 42;'#13#10
    + 'end;'#10, 3, 10), 'Block: begin wie die Zweigzeile, end; wie die '
    + 'Anweisung');
  Assert.AreEqual('begin'#10'  Foo;'#13#10'  const MagicNr01 = 42;'#10
    + '  X := MagicNr01;'#10'end;'#10, RunC1h('begin'#10'  Foo;'#13#10
    + '  X := 42;'#10'end;'#10, 3, 8), 'LF-Datei mit einer CR-LF-Zeile');
  // Letzte Zeile ohne Zeilenende: Rueckfall auf das erste Zeilenende der
  // Datei (LF).
  Assert.AreEqual('begin'#10'  const MagicNr01 = 42;'#10'  X := MagicNr01;',
    RunC1h('begin'#10'  X := 42;', 2, 8), 'letzte Zeile ohne Ende, LF-Datei');
end;

// IntroduceEdits verlangt Plan.Ok: fuer ein abgelehntes Ziel - auch eines
// ohne Zeilen (Default, SourceRow 0) - gibt es keine Ersetzungen statt
// eines Bereichsfehlers (Bericht B, Minor "IntroduceEdits ohne
// Vorbedingung").
procedure TTestVnpContext.IntroduceEdits_RefusedPlanIsEmpty;
var
  T : TVnpText;
  G : TVnpTarget;
begin
  T := TextIn(Buf(['begin', '  X := Y;', 'end;']));
  G := TargetAt(T, 2, 8, NAME_BASE);
  Assert.IsFalse(G.Plan.Ok, 'Vorbedingung: kein Literal am Caret');
  Assert.AreEqual<Integer>(0, Length(IntroduceEdits(T, G)),
    'abgelehntes Ziel: keine Ersetzungen');
  G := Default(TVnpTarget);
  Assert.AreEqual<Integer>(0, Length(IntroduceEdits(T, G)),
    'leeres Ziel (SourceRow 0): keine Ersetzungen');
end;

// Eine Direktive AM ANFANG der Anweisungszeile ('{$ENDIF} X := 42;'): die
// Deklaration kaeme an den Zeilenanfang, also vor das '{$ENDIF}' in den
// Zweig darueber, und ohne A fehlte der Name (E2003). Ebenso '{$ELSE}'.
// Vorher pruefte DirectiveBetween nur die Zeile darueber und die Zeilen
// dazwischen (Review Woche 2026-10-21, G10-02). Ein Kommentar ohne '$'
// auf der Anweisungszeile stoert nicht.
procedure TTestVnpContext.DirectiveOnStatementLine;
var
  B : string;
begin
  B := Buf(['procedure P;', 'begin', '{$IFDEF A}', '  Y := 1;',
    '{$ENDIF} X := 42;', 'end;']);
  // Zeile 5, die 42 in Spalte 15.
  AssertRefusedWith(TargetIn(B, 5, 15), 'Direktive',
    'ENDIF am Anfang der Anweisungszeile');
  B := Buf(['begin', '{$IFDEF A}', '  Y := 1;', '{$ELSE} X := 42;',
    '{$ENDIF}', 'end;']);
  // Zeile 4, die 42 in Spalte 14.
  AssertRefusedWith(TargetIn(B, 4, 14), 'Direktive',
    'ELSE am Anfang der Anweisungszeile');
  // Auch HINTER dem Literal ohne Block: die ganze Zeile zaehlt (lieber
  // ablehnen; reDelphix zieht seit der Folgewelle A7 gleich, vorher nahm
  // es diese Zeile an).
  B := Buf(['begin', '  Foo;', '  X := 42; {$IFDEF D} Log; {$ENDIF}', 'end;']);
  AssertRefusedWith(TargetIn(B, 3, 8), 'Direktive',
    'Direktive hinter dem Literal ohne Block');
  B := Buf(['begin', '  Foo;', '  X := 42; { ohne Dollar }', 'end;']);
  AssertAccepted(TargetIn(B, 3, 8), False, 2,
    'Kommentar ohne Direktive auf der Anweisungszeile');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestVnpContext);
end.
