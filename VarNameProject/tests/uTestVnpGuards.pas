unit uTestVnpGuards;

// DUnitX-Tests fuer die Schutzregeln der Editorhilfe "Zahl-Literal als
// Variable einfuehren" (uVnpPlan, uVnpEdits.TargetAt), die der Korpus-A/B
// vom 2026-10-11 verlangt hat: der alte und der neue Plan ueber 8 Mio.
// Zeilen von D:\git-sca-realworld, dazu ein Gegenpruefer mit eigenen
// Zeilen. Jeder Fall hier ist eine Stelle, an der die Hilfe sonst Code
// erzeugt haette, der nicht uebersetzt - oder still anders laeuft (offener
// Block in der Zweigzeile, mehrzeiliger String).
//
// Vertrag wie in uTestVnpPlan/uTestVnpRefuse: Interface-Kommentare von
// uVnpPlan und uVnpEdits, README Grenzen; Erwartungen von Hand, Spalten
// 1-basierte Zeichenspalten der Zeile.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestVnpGuards = class
  public
    // Zeilen, deren Zahlen Konstanten bleiben muessen
    [Test] procedure Guard_RoutineAndPropertyHeads;
    [Test] procedure Guard_TypeLabelGotoAsmExportsAttribute;
    [Test] procedure Guard_GenericDeclarationLine;
    [Test] procedure Guard_CaseLabelsBehindForAndOnHandler;
    [Test] procedure Guard_ValueStartAndListComma;
    [Test] procedure Guard_LeadingCommentKeywords;
    // Zweig ohne begin: was genau EINE Anweisung ist
    [Test] procedure Wrap_ElseBindsToOwnIf;
    [Test] procedure Wrap_OpenBlockOrForeignCloser;
    // Zusammenhang ueber mehrere Zeilen (uVnpEdits.TargetAt)
    [Test] procedure Context_DirectiveBetweenBranchAndStatement;
    [Test] procedure Context_MultiLineString;
    [Test] procedure Context_MultiLineComment;
  end;

implementation

uses
  System.SysUtils,
  uVnpPlan, uVnpEdits;

// Der Plan wird abgelehnt, und der Grund nennt AKeyword.
procedure AssertRefusedWith(const P: TVnpPlan; const AKeyword, AMsg: string);
begin
  Assert.IsFalse(P.Ok, AMsg + ' - Plan "' + P.NewUseLine + '"');
  Assert.IsTrue(Pos(AKeyword, P.Reason) > 0, AMsg + ', Grund: ' + P.Reason);
end;

// Das Ziel fuer den Caret in Zeile ARow, Spalte ACol eines CR-LF-Puffers.
function TargetIn(const ABuffer: string; ARow, ACol: Integer): TVnpTarget;
begin
  Result := TargetAt(TextOf(TEncoding.UTF8.GetBytes(ABuffer)), ARow, ACol,
    'MagicNr');
end;

// Routinen-Koepfe und Eigenschaften: Vorgabewert, dispid, message und
// default muessen Konstanten sein, und eine Variable davor stuende in
// einem Klassen- oder interface-Abschnitt. Bisher lehnte nur der ':' der
// Parameterliste sie ab - zufaellig als "Sprungmarke"; seit Feldbreiten in
// Klammern nicht mehr zaehlen, braucht es die Regel fuer den Zeilenanfang.
procedure TTestVnpGuards.Guard_RoutineAndPropertyHeads;
var
  P : TVnpPlan;
begin
  // Vorgabewert 1.2 in Spalte 57.
  P := PlanIntroduce('    procedure CheckExecutionTime(const ARatio: single '
    + '= 1.2);', '    fStopWatchDELPHI: TStopwatch;', 57, 'N01');
  AssertRefusedWith(P, '"procedure"', 'Vorgabewert');
  // dispid 7 in Spalte 85.
  P := PlanIntroduce('    procedure AddFromStream(const FileName: WideString; '
    + 'Stream: OleVariant); dispid 7;', '    procedure Add; dispid 1;', 85,
    'N01');
  AssertRefusedWith(P, '"procedure"', 'dispid');
  // message WM_USER + 1: die 1 in Spalte 65.
  P := PlanIntroduce('    procedure WMUser1(var Message: TMessage); message '
    + 'WM_USER + 1;', '    procedure WMUser(var Message: TMessage); message '
    + 'WM_USER;', 65, 'N01');
  AssertRefusedWith(P, '"procedure"', 'message');
  // default 25 in Spalte 29.
  P := PlanIntroduce('    property Height default 25;', '    property Align;',
    29, 'N01');
  AssertRefusedWith(P, '"property"', 'default');
  // class procedure mit Vorgabewert 10 in Spalte 37.
  P := PlanIntroduce('  class procedure Init(N: Integer = 10);', 'public', 37,
    'N01');
  AssertRefusedWith(P, '"class"', 'class procedure');
end;

// Typ-Zeile mit 'type' davor, Sprungmarken (goto/label: die Zahl ist eine
// Marke, keine Zahl), asm, exports und Attribute ('[MaxLength(42)]').
procedure TTestVnpGuards.Guard_TypeLabelGotoAsmExportsAttribute;
var
  P : TVnpPlan;
begin
  // 255 in Spalte 24.
  P := PlanIntroduce('  type TBuf = array[0..255] of Byte;', '  procedure Foo;',
    24, 'N01');
  AssertRefusedWith(P, '"type"', 'type');
  P := PlanIntroduce('  goto 10;', '  X := 1;', 8, 'N01');
  AssertRefusedWith(P, '"goto"', 'goto');
  P := PlanIntroduce('  label 10, 20;', '  X: Integer;', 9, 'N01');
  AssertRefusedWith(P, '"label"', 'label');
  P := PlanIntroduce('  asm int 3; end;', 'begin', 11, 'N01');
  AssertRefusedWith(P, '"asm"', 'asm');
  P := PlanIntroduce('  exports Foo index 42;', 'end;', 21, 'N01');
  AssertRefusedWith(P, '"exports"', 'exports');
  P := PlanIntroduce('    [MaxLength(42)]', '    FId: Integer;', 16, 'N01');
  AssertRefusedWith(P, 'Attribut', 'Attribut');
end;

// 'Name<T> =' ist ebenfalls eine Deklaration (generischer Typ); ein
// generischer Aufruf in einer Anweisung bleibt erlaubt.
procedure TTestVnpGuards.Guard_GenericDeclarationLine;
var
  P : TVnpPlan;
begin
  // Die 9 hinter '..' in Spalte 22.
  P := PlanIntroduce('  TArr<T> = array[0..9] of T;', '  TFoo = Integer;', 22,
    'N01');
  AssertRefusedWith(P, 'Deklaration', 'generischer Typ');
  // Die 42 in Spalte 29.
  P := PlanIntroduce('  X := TFoo<Integer>.Create(42);', 'begin', 29, 'N01');
  Assert.IsTrue(P.Ok, 'generischer Aufruf: ' + P.Reason);
  Assert.AreEqual('  X := TFoo<Integer>.Create(N01);', P.NewUseLine,
    'generischer Aufruf, NewUseLine');
end;

// Ein case-Zweig HINTER 'for ... do' wird gesehen (jeder ':' ausserhalb
// von Klammern zaehlt, nur die Typangabe 'for var I:' nicht); ein
// on-Handler ohne Variable hat keinen ':', aber 'on' und 'do'; eine
// Variable namens On ist kein Handler. Der Typ einer for-var ist ein Typ.
procedure TTestVnpGuards.Guard_CaseLabelsBehindForAndOnHandler;
var
  P : TVnpPlan;
begin
  // Die 42 in Spalte 40.
  P := PlanIntroduce('  for I in [1, 2] do case I of 1: X := 42; end;',
    '  X := 0;', 40, 'N01');
  AssertRefusedWith(P, 'case-Zweig', 'for-in mit case');
  // Die 9 in Spalte 17; der erste ':' ist ':='.
  P := PlanIntroduce('  for I := 0 to 9 do case I of 1: X := 42; end;',
    '  X := 0;', 17, 'N01');
  AssertRefusedWith(P, 'case-Zweig', 'for mit case');
  // Die 0 in Spalte 37.
  P := PlanIntroduce('        on EConvertError do Result:=0;', '     except', 37,
    'N01');
  AssertRefusedWith(P, 'on-Handler', 'on-Handler ohne Variable');
  P := PlanIntroduce('  On := 42;', 'begin', 9, 'N01');
  Assert.IsTrue(P.Ok, 'Variable On: ' + P.Reason);
  Assert.AreEqual('  On := N01;', P.NewUseLine, 'Variable On, NewUseLine');
  // Die 9 im Typ in Spalte 17.
  P := PlanIntroduce('  for var I: 0..9 := 0 to 9 do', 'begin', 17, 'N01');
  AssertRefusedWith(P, 'Typ', 'Typ der for-var');
  // Zwei Inline-var auf einer Zeile: auch der ':' der zweiten ist eine
  // Typangabe (die 0 in Spalte 42).
  P := PlanIntroduce('  var s: string := ''''; var i: Integer := 0;', 'begin',
    42, 'N01');
  Assert.IsTrue(P.Ok, 'zwei Inline-var: ' + P.Reason);
  Assert.AreEqual('  var s: string := ''''; var i: Integer := N01;',
    P.NewUseLine, 'zwei Inline-var, NewUseLine');
  // for-in mit Inline-var OHNE Typ: kein Typteil (die 2 in Spalte 49).
  P := PlanIntroduce('  for var s in aStrips do Inc(tris, Length(s) - 2);',
    '  var tris := 0;', 49, 'N01');
  Assert.IsTrue(P.Ok, 'for-in ohne Typ: ' + P.Reason);
  Assert.AreEqual('  for var s in aStrips do Inc(tris, Length(s) - N01);',
    P.NewUseLine, 'for-in ohne Typ, NewUseLine');
end;

// Eine Zeile, die mit einem Wert beginnt, setzt einen Ausdruck fort (der
// else-Wert eines Bedingungsausdrucks von Delphi 13); eine Zeile, die mit
// ',' ausserhalb von Klammern endet, setzt eine Liste fort (case-Marken).
// Ein Aufruf, dessen Argumente weitergehen, endet mit ',' IN der Klammer.
procedure TTestVnpGuards.Guard_ValueStartAndListComma;
var
  P : TVnpPlan;
begin
  P := PlanIntroduce('      42;', '    else', 7, 'N01');
  AssertRefusedWith(P, 'Wert', 'else-Wert');
  // Die 1 in Spalte 8.
  P := PlanIntroduce('      -1;', '    else', 8, 'N01');
  AssertRefusedWith(P, 'Wert', 'negativer else-Wert');
  // Die 432 in Spalte 10.
  P := PlanIntroduce('    431..432,', '      end;', 10, 'N01');
  AssertRefusedWith(P, 'Wert', 'case-Marken mit Zahl vorn');
  // Die 42 in Spalte 13.
  P := PlanIntroduce('    cFirst..42,', '      end;', 13, 'N01');
  AssertRefusedWith(P, 'Liste', 'case-Marken mit Name vorn');
  // Die 42 in Spalte 7.
  P := PlanIntroduce('  Foo(42,', 'begin', 7, 'N01');
  Assert.IsTrue(P.Ok, 'Aufruf ueber mehrere Zeilen: ' + P.Reason);
  Assert.AreEqual('  Foo(N01,', P.NewUseLine, 'Aufruf, NewUseLine');
end;

// Die Woerter am Zeilenanfang zaehlen hinter Kommentaren und Direktiven.
procedure TTestVnpGuards.Guard_LeadingCommentKeywords;
var
  P : TVnpPlan;
begin
  // Die 42 in Spalte 23.
  P := PlanIntroduce('  {$IFDEF X}const C = 42 * 2;{$ENDIF}', 'begin', 23,
    'N01');
  AssertRefusedWith(P, 'Konstante', 'const hinter Direktive');
  // Die 42 in Spalte 19.
  P := PlanIntroduce('  (*x*) const C = 42;', 'begin', 19, 'N01');
  Assert.IsFalse(P.Ok, 'const hinter (* *) - Plan "' + P.NewUseLine + '"');
  // Die 42 in Spalte 21.
  P := PlanIntroduce('  {x} end else Y := 42;', '    X := 1;', 21, 'N01');
  AssertRefusedWith(P, '"end"', 'end hinter Kommentar');
end;

// Ein else bindet an das naechste if davor - steht das auf derselben Zeile,
// ist die Zeile EINE Anweisung, und begin..end um sie aendert nichts. Ein
// begin..end, das auf der Zeile schliesst, enthaelt ';' - auch das ist eine
// Anweisung.
procedure TTestVnpGuards.Wrap_ElseBindsToOwnIf;
var
  P : TVnpPlan;
begin
  // Die 0 in Spalte 20.
  P := PlanIntroduce('      if Compare < 0 then First := I + 1 else Last := '
    + 'I - 1;', '    end else', 20, 'N01');
  Assert.IsTrue(P.Ok, 'if-else: ' + P.Reason);
  Assert.IsTrue(P.Wrap, 'if-else, Wrap');
  Assert.AreEqual('    ', P.BlockIndent, 'if-else, BlockIndent');
  Assert.AreEqual('      if Compare < N01 then First := I + 1 else Last := '
    + 'I - 1;', P.NewUseLine, 'if-else, NewUseLine');
  // Die erste 12 in Spalte 36; alle drei 12 werden ersetzt.
  P := PlanIntroduce('                if H = 0 then H := 12 else if H > 12 '
    + 'then Dec(H, 12);', '              if Use12HourClock then', 36, 'N01');
  Assert.IsTrue(P.Ok, 'else if: ' + P.Reason);
  Assert.AreEqual('                if H = 0 then H := N01 else if H > N01 '
    + 'then Dec(H, N01);', P.NewUseLine, 'else if, NewUseLine');
  // Die 42 in Spalte 36.
  P := PlanIntroduce('  if i = 4 then begin a := 1; b := 42; end;',
    '  if i = 3 then begin a := 1; b := 6; end else', 36, 'N01');
  Assert.IsTrue(P.Ok, 'begin..end auf der Zeile: ' + P.Reason);
  Assert.IsTrue(P.Wrap, 'begin..end auf der Zeile, Wrap');
  // Die 42 in Spalte 14: try..finally..end schliesst auf der Zeile.
  P := PlanIntroduce('    try X := 42; finally Y; end;', '  if A then', 14,
    'N01');
  Assert.IsTrue(P.Ok, 'try auf der Zeile: ' + P.Reason);
end;

// Oeffnet die Zweigzeile einen Block, der erst spaeter schliesst, oder
// traegt sie das Ende eines Konstrukts von ausserhalb (until, finally, end),
// aenderte begin..end um die Zeile still, was laeuft - etwa liefe der Rest
// des Schleifenrumpfs nur noch einmal.
procedure TTestVnpGuards.Wrap_OpenBlockOrForeignCloser;
var
  P : TVnpPlan;
begin
  // Die 42 in Spalte 37.
  P := PlanIntroduce('    for I := 0 to 9 do begin Inc(X, 42);', '  if A then',
    37, 'N01');
  AssertRefusedWith(P, 'Anweisung des Zweigs', 'for mit offenem begin');
  // Die 42 in Spalte 31.
  P := PlanIntroduce('    with Obj do begin Left := 42;', '  if A then', 31,
    'N01');
  AssertRefusedWith(P, 'Anweisung des Zweigs', 'with mit offenem begin');
  P := PlanIntroduce('    X := 42 until X > 100;', '  if A then', 10, 'N01');
  AssertRefusedWith(P, 'Anweisung des Zweigs', 'until von aussen');
  P := PlanIntroduce('    X := 42 finally Free end;', '  if A then', 10, 'N01');
  AssertRefusedWith(P, 'Anweisung des Zweigs', 'finally von aussen');
end;

// Steht zwischen Zweigzeile und Anweisung eine Direktive, landeten begin
// und end in verschiedenen Zweigen der bedingten Uebersetzung; ein
// Kommentar dazwischen stoert nicht.
procedure TTestVnpGuards.Context_DirectiveBetweenBranchAndStatement;
var
  G : TVnpTarget;
begin
  // Zeile 4, die 42 in Spalte 10.
  G := TargetIn('begin'#13#10'  if A then'#13#10'{$IFDEF DEBUG}'#13#10
    + '    Y := 42;'#13#10'{$ELSE}'#13#10'    Y := 0;'#13#10'{$ENDIF}'#13#10
    + 'end;'#13#10, 4, 10);
  AssertRefusedWith(G.Plan, 'Direktive', 'IFDEF zwischen Zweig und Anweisung');
  G := TargetIn('begin'#13#10'  if A then'#13#10'  // Kommentar'#13#10
    + '    Y := 42;'#13#10'end;'#13#10, 4, 10);
  Assert.IsTrue(G.Plan.Ok, 'Kommentar dazwischen: ' + G.Plan.Reason);
  Assert.IsTrue(G.Plan.Wrap, 'Kommentar dazwischen, Wrap');
  Assert.AreEqual<Integer>(2, G.PrevRow, 'Kommentar dazwischen, PrevRow');
end;

// In einem mehrzeiligen String (Delphi 12, ''' ... ''') ist kein Code - die
// Hilfe aenderte sonst still den String; hinter seinem Ende geht es wieder.
procedure TTestVnpGuards.Context_MultiLineString;
const
  BUF = 'begin'#13#10'  S := '''''''#13#10'    DELETE FROM T;'#13#10
    + '    INSERT INTO T VALUES (42);'#13#10'    '''''';'#13#10
    + '  X := 42;'#13#10'end;'#13#10;
var
  G : TVnpTarget;
begin
  // Zeile 4, die 42 in Spalte 27 - die Zeile darueber endet mit ';', ein
  // reiner Zeilen-Leser nahme sie also an.
  G := TargetIn(BUF, 4, 27);
  AssertRefusedWith(G.Plan, 'mehrzeiligen String', 'Zeile im String');
  // Zeile 3 direkt hinter dem Oeffner: derselbe Grund.
  G := TargetIn(BUF, 3, 5);
  AssertRefusedWith(G.Plan, 'mehrzeiligen String', 'erste Zeile im String');
  // Zeile 6, die 42 in Spalte 8.
  G := TargetIn(BUF, 6, 8);
  Assert.IsTrue(G.Plan.Ok, 'hinter dem String: ' + G.Plan.Reason);
  Assert.AreEqual('  X := MagicNr01;', G.Plan.NewUseLine,
    'hinter dem String, NewUseLine');
end;

// In einem Kommentar ueber mehrere Zeilen ({ } und (* *)) ist kein Code -
// auskommentierter Code bleibt unberuehrt. Die Anweisung danach findet die
// Code-Zeile VOR dem Kommentar als Zeile darueber, nicht dessen Schluss.
procedure TTestVnpGuards.Context_MultiLineComment;
const
  BUF = 'begin'#13#10'  X := 1;'#13#10'  { alt:'#13#10'    Y := 42;'#13#10
    + '  }'#13#10'  (* auch alt'#13#10'    Z := 42;'#13#10'  *)'#13#10
    + '  W := 42;'#13#10'end;'#13#10;
var
  G : TVnpTarget;
begin
  // Zeile 4 und 7, die 42 je in Spalte 10.
  G := TargetIn(BUF, 4, 10);
  AssertRefusedWith(G.Plan, 'mehrzeiligen Kommentar', '{ }-Kommentar');
  G := TargetIn(BUF, 7, 10);
  AssertRefusedWith(G.Plan, 'mehrzeiligen Kommentar', '(* *)-Kommentar');
  // Zeile 9, die 42 in Spalte 8; die Code-Zeile darueber ist Zeile 2.
  G := TargetIn(BUF, 9, 8);
  Assert.IsTrue(G.Plan.Ok, 'hinter den Kommentaren: ' + G.Plan.Reason);
  Assert.AreEqual<Integer>(2, G.PrevRow, 'hinter den Kommentaren, PrevRow');
  Assert.AreEqual('  W := MagicNr01;', G.Plan.NewUseLine,
    'hinter den Kommentaren, NewUseLine');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestVnpGuards);
end.
