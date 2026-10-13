unit uTestRdxIntroGuards;

// DUnitX-Tests fuer die Schutzregeln der Code-Aktion "Lokale Konstante
// einfuehren" (reDelphix, Refactoring ohne Fund; uRdxIntroPlan,
// uRdxIntroEdits.TargetAt), die der Korpus-A/B vom 2026-10-11 verlangt
// hat: der alte und der neue Plan ueber 8 Mio.
// Zeilen von D:\git-sca-realworld, dazu ein Gegenpruefer mit eigenen
// Zeilen. Jeder Fall hier ist eine Stelle, an der die Hilfe sonst Code
// erzeugt haette, der nicht uebersetzt - oder still anders laeuft (offener
// Block in der Zweigzeile, mehrzeiliger String).
//
// Vertrag wie in uTestRdxIntroPlan/uTestRdxIntroRefuse: Interface-
// Kommentare von uRdxIntroPlan und uRdxIntroEdits, README Grenzen (das des
// Labors, VarNameProject\README.md); Erwartungen von Hand, Spalten
// 1-basierte Zeichenspalten der Zeile.
//
// 1:1 aus dem Labor VarNameProject (uTestVnpGuards, Stand 2026-10-14 nach dem
// Review F/B vom 2026-10-13, Entscheid E24: erst der im Labor gemessene
// Stand, die Zusammenlegung mit uRdxCodeMap/uRdxBufferMath folgt
// spaeter).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxIntroGuards = class
  public
    // Zeilen, deren Zahlen Konstanten bleiben muessen
    [Test] procedure Guard_RoutineAndPropertyHeads;
    [Test] procedure Guard_TypeLabelGotoAsmExportsAttribute;
    [Test] procedure Guard_GenericDeclarationLine;
    [Test] procedure Guard_CaseLabelsBehindForAndOnHandler;
    [Test] procedure Guard_ValueStartAndListComma;
    [Test] procedure Guard_LeadingCommentKeywords;
    [Test] procedure Guard_HeadContinuationLines;
    [Test] procedure Guard_SecondDeclarationOnLine;
    [Test] procedure PrevLine_InitializationFinalization;
    // Zweig ohne begin: was genau EINE Anweisung ist
    [Test] procedure Wrap_ElseBindsToOwnIf;
    [Test] procedure Wrap_OpenBlockOrForeignCloser;
    [Test] procedure Wrap_IfExpressionOnPrevLine;
    // Zusammenhang ueber mehrere Zeilen (uRdxIntroEdits.TargetAt)
    [Test] procedure Context_DirectiveBetweenBranchAndStatement;
    [Test] procedure Context_MultiLineString;
    [Test] procedure Context_MultiLineComment;
    [Test] procedure Context_SyncBlockEnd;
  end;

implementation

uses
  System.SysUtils,
  uRdxIntroPlan, uRdxIntroEdits;

// Der Plan wird abgelehnt, und der Grund nennt AKeyword.
procedure AssertRefusedWith(const P: TRdxIntroPlan; const AKeyword, AMsg: string);
begin
  Assert.IsFalse(P.Ok, AMsg + ' - Plan "' + P.NewUseLine + '"');
  Assert.IsTrue(Pos(AKeyword, P.Reason) > 0, AMsg + ', Grund: ' + P.Reason);
end;

// Das Ziel fuer den Caret in Zeile ARow, Spalte ACol eines CR-LF-Puffers.
function TargetIn(const ABuffer: string; ARow, ACol: Integer): TRdxIntroTarget;
begin
  Result := TargetAt(TextOf(TEncoding.UTF8.GetBytes(ABuffer)), ARow, ACol,
    'MagicNr');
end;

// Routinen-Koepfe und Eigenschaften: Vorgabewert, dispid, message und
// default muessen Konstanten sein, und eine Variable davor stuende in
// einem Klassen- oder interface-Abschnitt. Bisher lehnte nur der ':' der
// Parameterliste sie ab - zufaellig als "Sprungmarke"; seit Feldbreiten in
// Klammern nicht mehr zaehlen, braucht es die Regel fuer den Zeilenanfang.
procedure TTestRdxIntroGuards.Guard_RoutineAndPropertyHeads;
var
  P : TRdxIntroPlan;
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
procedure TTestRdxIntroGuards.Guard_TypeLabelGotoAsmExportsAttribute;
var
  P : TRdxIntroPlan;
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
procedure TTestRdxIntroGuards.Guard_GenericDeclarationLine;
var
  P : TRdxIntroPlan;
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
procedure TTestRdxIntroGuards.Guard_CaseLabelsBehindForAndOnHandler;
var
  P : TRdxIntroPlan;
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
procedure TTestRdxIntroGuards.Guard_ValueStartAndListComma;
var
  P : TRdxIntroPlan;
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
procedure TTestRdxIntroGuards.Guard_LeadingCommentKeywords;
var
  P : TRdxIntroPlan;
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

// Fortsetzungen eines Routinen-Kopfs oder einer Eigenschaft auf einer
// Folgezeile ('message WM_USER + 5;', 'dispid 5;', 'external ''x.dll''
// index 5;', 'stdcall; external ...'): die Zeile darueber endet mit ';',
// die Zahl ist aber Teil der Deklaration (Pruefer 2026-10-13, Harness
// 1-3). Dieselben Woerter als Anweisung ('Index := 5;', 'Message(42);',
// 'Index[1] := 42;', 'Name.Add(42);') bleiben erlaubt.
procedure TTestRdxIntroGuards.Guard_HeadContinuationLines;
var
  P : TRdxIntroPlan;
begin
  // Die 5 in Spalte 25.
  P := PlanIntroduce('      message WM_USER + 5;',
    '    procedure WMFoo(var Msg: TMessage);', 25, 'N01');
  AssertRefusedWith(P, '"message"', 'message auf der Folgezeile');
  // Die 5 in Spalte 14.
  P := PlanIntroduce('      dispid 5;', '    procedure Bar;', 14, 'N01');
  AssertRefusedWith(P, '"dispid"', 'dispid auf der Folgezeile');
  // Die 5 in Spalte 26.
  P := PlanIntroduce('  external ''x.dll'' index 5;',
    'function Foo: Integer; stdcall;', 26, 'N01');
  AssertRefusedWith(P, '"external"', 'external index auf der Folgezeile');
  // Die 5 in Spalte 35.
  P := PlanIntroduce('  stdcall; external ''x.dll'' index 5;',
    'function Foo: Integer;', 35, 'N01');
  AssertRefusedWith(P, '"stdcall"', 'stdcall; external auf der Folgezeile');
  // Anweisungen: die 5 in Spalte 12, die 42 in Spalte 11, 15 und 12.
  P := PlanIntroduce('  Index := 5;', 'begin', 12, 'N01');
  Assert.IsTrue(P.Ok, 'Index := 5: ' + P.Reason);
  Assert.AreEqual('  Index := N01;', P.NewUseLine, 'Index := 5, NewUseLine');
  P := PlanIntroduce('  Message(42);', 'begin', 11, 'N01');
  Assert.IsTrue(P.Ok, 'Message(42): ' + P.Reason);
  P := PlanIntroduce('  Index[1] := 42;', 'begin', 15, 'N01');
  Assert.IsTrue(P.Ok, 'Index[1] := 42: ' + P.Reason);
  Assert.AreEqual('  Index[1] := N01;', P.NewUseLine,
    'Index[1] := 42, NewUseLine');
  P := PlanIntroduce('  Name.Add(42);', 'begin', 12, 'N01');
  Assert.IsTrue(P.Ok, 'Name.Add(42): ' + P.Reason);
end;

// Eine Deklaration HINTER einer Anweisung auf derselben Zeile: jedes 'var'
// und 'const' auf oberster Ebene zaehlt, nicht nur das erste Wort
// (Pruefer 2026-10-13, Harness 21/22) - das Literal im Typ der zweiten
// Inline-var und der Wert einer zweiten Inline-const bleiben. Ein Literal
// VOR dem const und der Wert einer zweiten Inline-var ohne Typ gehen.
procedure TTestRdxIntroGuards.Guard_SecondDeclarationOnLine;
var
  P : TRdxIntroPlan;
begin
  // Die 9 in Spalte 24.
  P := PlanIntroduce('  Foo; var A: array[0..9] of Byte;', 'begin', 24, 'N01');
  AssertRefusedWith(P, 'Typ', 'zweite Inline-var, Literal im Typ');
  // Die 5 in Spalte 18.
  P := PlanIntroduce('  Foo; const C = 5;', 'begin', 18, 'N01');
  AssertRefusedWith(P, 'Konstante', 'zweite Inline-const');
  // Die 5 in Spalte 7 - vor dem const.
  P := PlanIntroduce('  Foo(5); const C = 7;', 'begin', 7, 'N01');
  Assert.IsTrue(P.Ok, 'Literal vor dem const: ' + P.Reason);
  Assert.AreEqual('  Foo(N01); const C = 7;', P.NewUseLine,
    'Literal vor dem const, NewUseLine');
  // Die 42 in Spalte 17.
  P := PlanIntroduce('  Foo; var B := 42 + X;', 'begin', 17, 'N01');
  Assert.IsTrue(P.Ok, 'zweite Inline-var ohne Typ: ' + P.Reason);
  Assert.AreEqual('  Foo; var B := N01 + X;', P.NewUseLine,
    'zweite Inline-var ohne Typ, NewUseLine');
end;

// Die Zeile darueber beginnt den initialization-/finalization-Abschnitt:
// ob dort eine Inline-Deklaration gilt, ist nicht gemessen - Abbruch mit
// einem Grund, der den Abschnitt nennt (statt des allgemeinen "unklar").
procedure TTestRdxIntroGuards.PrevLine_InitializationFinalization;
var
  P : TRdxIntroPlan;
begin
  // Die 42 in Spalte 7.
  P := PlanIntroduce('  Bar(42);', 'initialization', 7, 'N01');
  AssertRefusedWith(P, 'initialization', 'hinter initialization');
  P := PlanIntroduce('  Bar(42);', 'finalization // Abbau', 7, 'N01');
  AssertRefusedWith(P, 'initialization', 'hinter finalization');
  P := PlanIntroduce('  Bar(42);', 'INITIALIZATION', 7, 'N01');
  AssertRefusedWith(P, 'initialization', 'gross geschrieben');
end;

// Ein else bindet an das naechste if davor - steht das auf derselben Zeile,
// ist die Zeile EINE Anweisung, und begin..end um sie aendert nichts. Ein
// begin..end, das auf der Zeile schliesst, enthaelt ';' - auch das ist eine
// Anweisung.
procedure TTestRdxIntroGuards.Wrap_ElseBindsToOwnIf;
var
  P : TRdxIntroPlan;
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
procedure TTestRdxIntroGuards.Wrap_OpenBlockOrForeignCloser;
var
  P : TRdxIntroPlan;
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

// Endet die Zeile darueber mit dem then/else eines Bedingungsausdrucks
// (Delphi 13: 'X := if C then Bar else', 'Foo(if C then'), ist die Zeile
// ein Arm des Ausdrucks - ein begin..end darum ist kein Code (Pruefer
// 2026-10-13, Harness 8; den Fall mit 'else' auf eigener Zeile prueft
// uTestRdxIntroContext). Das if einer ANWEISUNG ('if C then Bar else', 'end
// else if X then', '1: if A then') bleibt ein Zweig; die Zeile darueber
// zaehlt ab ihrem Kommentar-Zustand (APrevState).
procedure TTestRdxIntroGuards.Wrap_IfExpressionOnPrevLine;
var
  P : TRdxIntroPlan;
begin
  // Die 42 in Spalte 9.
  P := PlanIntroduce('    Foo(42);', '  X := if C then Bar else', 9, 'N01');
  AssertRefusedWith(P, 'Bedingungsausdruck', 'X := if ... else');
  P := PlanIntroduce('    Foo(42);', '  Y := Foo(if C then', 9, 'N01');
  AssertRefusedWith(P, 'Bedingungsausdruck', 'Foo(if ... then');
  P := PlanIntroduce('    Foo(42);', '  if C then Bar else', 9, 'N01');
  Assert.IsTrue(P.Ok, 'if-Anweisung mit else: ' + P.Reason);
  Assert.IsTrue(P.Wrap, 'if-Anweisung mit else, Wrap');
  P := PlanIntroduce('    Foo(42);', '  end else if X then', 9, 'N01');
  Assert.IsTrue(P.Ok, 'end else if: ' + P.Reason);
  Assert.IsTrue(P.Wrap, 'end else if, Wrap');
  P := PlanIntroduce('      Foo(42);', '    1: if A then', 11, 'N01');
  Assert.IsTrue(P.Ok, 'case-Zweig mit if: ' + P.Reason);
  Assert.IsTrue(P.Wrap, 'case-Zweig mit if, Wrap');
  // Die Zeile darueber beginnt im { }-Kommentar: ihr Code ist ' if A
  // then' hinter dem '}' - ein Zweig, obwohl die Zeile mit ';' aussieht,
  // als endete sie eine Anweisung.
  P := PlanIntroduce('    X := 42;', '  Foo; // } if A then', 10, 'N01', 'b');
  Assert.IsTrue(P.Ok, 'Zeile darueber ab Kommentar-Zustand: ' + P.Reason);
  Assert.IsTrue(P.Wrap, 'Zeile darueber ab Kommentar-Zustand, Wrap');
  Assert.AreEqual('  ', P.BlockIndent,
    'Zeile darueber ab Kommentar-Zustand, BlockIndent der rohen Zeile');
  P := PlanIntroduce('    X := 42;', '  Foo; // } if A then', 10, 'N01');
  Assert.IsTrue(P.Ok, 'dieselbe Zeile ab Code: ' + P.Reason);
  Assert.IsFalse(P.Wrap, 'dieselbe Zeile ab Code: Foo; endet die Anweisung');
end;

// Steht zwischen Zweigzeile und Anweisung eine Direktive, landeten begin
// und end in verschiedenen Zweigen der bedingten Uebersetzung; ein
// Kommentar dazwischen stoert nicht.
procedure TTestRdxIntroGuards.Context_DirectiveBetweenBranchAndStatement;
var
  G : TRdxIntroTarget;
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
procedure TTestRdxIntroGuards.Context_MultiLineString;
const
  BUF = 'begin'#13#10'  S := '''''''#13#10'    DELETE FROM T;'#13#10
    + '    INSERT INTO T VALUES (42);'#13#10'    '''''';'#13#10
    + '  X := 42;'#13#10'end;'#13#10;
var
  G : TRdxIntroTarget;
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
procedure TTestRdxIntroGuards.Context_MultiLineComment;
const
  BUF = 'begin'#13#10'  X := 1;'#13#10'  { alt:'#13#10'    Y := 42;'#13#10
    + '  }'#13#10'  (* auch alt'#13#10'    Z := 42;'#13#10'  *)'#13#10
    + '  W := 42;'#13#10'end;'#13#10;
var
  G : TRdxIntroTarget;
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

// Das Ende des Sync-Blocks (C1h): auf reinen ASCII-Zeilen direkt hinter der
// letzten Verwendung; steht davor Nicht-ASCII, am Anfang der Folgezeile -
// SyncEditBlock liest das Blockende als UTF-8-Bytes und schnitt sonst das
// letzte MagicNr01 an (UI-Test 2026-10-11, Fall 6: keine Sitzung). Ohne
// Folgezeile rueckt die Spalte um die Mehrbytes weiter.
procedure TTestRdxIntroGuards.Context_SyncBlockEnd;
var
  T        : TRdxIntroText;
  G        : TRdxIntroTarget;
  Row, Col : Integer;
begin
  // Fall 1: die zweite 42 endet in Spalte 27, als MagicNr01 in Spalte 42.
  T := TextOf(TEncoding.UTF8.GetBytes('function Twice(Value: Integer): '
    + 'Integer;'#13#10'begin'#13#10'  Result := Value * 42 + 42;'#13#10
    + 'end;'#13#10));
  G := TargetAt(T, 3, 21, 'MagicNr');
  Assert.IsTrue(G.Plan.Ok, 'Fall 1: ' + G.Plan.Reason);
  SyncBlockEnd(T, G, Row, Col);
  Assert.AreEqual<Integer>(4, Row, 'Fall 1, Zeile');
  Assert.AreEqual<Integer>(42, Col, 'Fall 1, Spalte hinter der Verwendung');
  // Fall 6: 'Gr', ue, ss, 'e ', Euro vor der 42 in Spalte 43 - 4 Mehrbytes.
  T := TextOf(TEncoding.UTF8.GetBytes('begin'#13#10'  Result := ''Gr'
    + #$00FC#$00DF'e '#$20AC' '' + IntToStr(Count * 42);'#13#10'end;'#13#10));
  G := TargetAt(T, 2, 43, 'MagicNr');
  Assert.IsTrue(G.Plan.Ok, 'Fall 6: ' + G.Plan.Reason);
  SyncBlockEnd(T, G, Row, Col);
  Assert.AreEqual<Integer>(4, Row, 'Fall 6, Folgezeile');
  Assert.AreEqual<Integer>(1, Col, 'Fall 6, Spalte 1');
  // Dieselbe Anweisung als letzte Zeile ohne Zeilenende: hinter MagicNr01
  // (Spalte 52) plus 4 Mehrbytes.
  T := TextOf(TEncoding.UTF8.GetBytes('begin'#13#10'  Result := ''Gr'
    + #$00FC#$00DF'e '#$20AC' '' + IntToStr(Count * 42);'));
  G := TargetAt(T, 2, 43, 'MagicNr');
  Assert.IsTrue(G.Plan.Ok, 'letzte Zeile: ' + G.Plan.Reason);
  SyncBlockEnd(T, G, Row, Col);
  Assert.AreEqual<Integer>(3, Row, 'letzte Zeile, Zeile');
  Assert.AreEqual<Integer>(56, Col, 'letzte Zeile, Spalte plus Mehrbytes');
  // Zweig ohne begin mit ue vor der 42 (Spalte 26): danach folgt die
  // Zeile mit dem neuen Blockende.
  T := TextOf(TEncoding.UTF8.GetBytes('begin'#13#10'  if A then'#13#10
    + '    S := ''x'#$00FC''' + IntToStr(42);'#13#10'end;'#13#10));
  G := TargetAt(T, 3, 26, 'MagicNr');
  Assert.IsTrue(G.Plan.Ok and G.Plan.Wrap, 'Wrap: ' + G.Plan.Reason);
  SyncBlockEnd(T, G, Row, Col);
  Assert.AreEqual<Integer>(6, Row, 'Wrap, Zeile von end;');
  Assert.AreEqual<Integer>(1, Col, 'Wrap, Spalte 1');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxIntroGuards);
end.
