unit uTestVnpRefuse;

// DUnitX-Tests fuer uVnpPlan (VarNameProject, Code-Aktion "Lokale
// Variable einfuehren"): der Zweig ohne begin (begin..end, Einrueckung) und
// alle Ablehnungen - case-Zweig, Sprungmarke, on-Handler, Zeilenanfang,
// schon benannt, Konstanten-Kontexte, Deklarationszeilen, die Zeile
// darueber. Aus uTestVnpPlan abgeteilt (SCA141: Klasse ueber 500 Zeilen),
// gleicher Vertrag und dieselben Regeln: die Interface-Kommentare von
// uVnpPlan, README (Varianten, Grenzen, Messpunkte) und die Demo-Dateien;
// alle Erwartungen sind von Hand abgeleitete Literale, Spalten 1-basierte
// Zeichenspalten der Zeile (ein Tab ist EINE Spalte).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestVnpRefuse = class
  public
    // Zweig ohne begin (Wrap) und Einrueckung
    [Test] procedure Wrap_ThenDoElse;
    [Test] procedure Wrap_TabIndentColumns;
    [Test] procedure Wrap_ExactlyOneCompleteStatement;
    // Ablehnungen und die Zeile darueber
    [Test] procedure Refuse_LabeledLines;
    [Test] procedure Refuse_LineStartKeywords;
    [Test] procedure Refuse_AlreadyNamed;
    [Test] procedure Refuse_ConstantContexts;
    [Test] procedure Refuse_DeclarationLines;
    [Test] procedure PrevLine_MustEndStatement;
  end;

implementation

uses
  System.SysUtils,
  uVnpPlan;

const
  // Ein einzelner Tab als string (nicht Char) fuer Assert.AreEqual.
  TAB1 : string = #9;

// Zweig ohne begin (Fall 3, Messpunkt M9): die Zeile darueber endet mit
// then/do/else (auch mit Kommentar dahinter) -> Wrap; BlockIndent ist die
// Einrueckung der Zweigzeile, DeclText traegt die der Zeile; hinter ';'
// kein Wrap. Fall 2 der Demo: die if-Zeile selbst ist kein Zweig, die
// Deklaration kommt vor das if (vnptest: then wrap .. no wrap after ;).
procedure TTestVnpRefuse.Wrap_ThenDoElse;
var
  P : TVnpPlan;
begin
  P := PlanIntroduce('    Result := 999;', '  if Result > 1000 then', 15,
    'N01');
  Assert.IsTrue(P.Ok, 'then, Ok: ' + P.Reason);
  Assert.IsTrue(P.Wrap, 'then, Wrap');
  Assert.AreEqual('  ', P.BlockIndent, 'then, BlockIndent');
  Assert.AreEqual('    var N01 := 999;', P.DeclText, 'then, DeclText');
  Assert.AreEqual('    Result := N01;', P.NewUseLine, 'then, NewUseLine');
  P := PlanIntroduce('    Result := 999;', '  if X then // Kommentar', 15,
    'N01');
  Assert.IsTrue(P.Ok, 'then mit Kommentar, Ok: ' + P.Reason);
  Assert.IsTrue(P.Wrap, 'then mit Kommentar, Wrap');
  P := PlanIntroduce(#9#9'Sum := Sum + 3;', #9'for i := 0 to 9 do', 16, 'N01');
  Assert.IsTrue(P.Ok, 'do, Ok: ' + P.Reason);
  Assert.IsTrue(P.Wrap, 'do, Wrap');
  Assert.AreEqual(TAB1, P.BlockIndent, 'do, BlockIndent Tab');
  P := PlanIntroduce('    Result := 7;', '  else', 15, 'N01');
  Assert.IsTrue(P.Ok, 'else, Ok: ' + P.Reason);
  Assert.IsTrue(P.Wrap, 'else, Wrap');
  P := PlanIntroduce('    Result := 7;', '  Inc(X);', 15, 'N01');
  Assert.IsTrue(P.Ok, 'hinter ;, Ok: ' + P.Reason);
  Assert.IsFalse(P.Wrap, 'hinter ;, kein Wrap');
  // Neu: Fall 2 der Demo (Clamp), Caret auf der 1000 in der if-Zeile; die
  // Code-Zeile darueber ist 'Result := Value;'.
  P := PlanIntroduce('  if Result > 1000 then', '  Result := Value;', 15,
    'MagicNr01');
  Assert.IsTrue(P.Ok, 'Fall 2, Ok: ' + P.Reason);
  Assert.IsFalse(P.Wrap, 'Fall 2, kein Wrap');
  Assert.AreEqual('  var MagicNr01 := 1000;', P.DeclText, 'Fall 2, DeclText');
  Assert.AreEqual('  if Result > MagicNr01 then', P.NewUseLine,
    'Fall 2, NewUseLine');
end;

// Tabs (Fall 5, Messpunkt M8): ein Tab ist EINE Zeichenspalte - Indent,
// NameCol, OldCols, NewCols; BlockIndent und Indent uebernehmen Tabs und
// gemischte Einrueckung unveraendert.
procedure TTestVnpRefuse.Wrap_TabIndentColumns;
var
  P : TVnpPlan;
begin
  P := PlanIntroduce(#9'Result := Value and $FF00;', 'begin', 22, 'MagicNr01');
  Assert.IsTrue(P.Ok, 'Fall 5, Ok: ' + P.Reason);
  Assert.AreEqual(TAB1, P.Indent, 'Fall 5, Indent');
  Assert.AreEqual(#9'var MagicNr01 := $FF00;', P.DeclText, 'Fall 5, DeclText');
  Assert.AreEqual<Integer>(6, P.NameCol, 'Fall 5, NameCol');
  Assert.AreEqual(#9'Result := Value and MagicNr01;', P.NewUseLine,
    'Fall 5, NewUseLine');
  Assert.AreEqual<Integer>(1, Length(P.OldCols), 'Fall 5, Zahl OldCols');
  Assert.AreEqual<Integer>(22, P.OldCols[0], 'Fall 5, OldCols[0]');
  Assert.AreEqual<Integer>(22, P.NewCols[0], 'Fall 5, NewCols[0]');
  P := PlanIntroduce(#9#9#9'Y := 5;', #9#9'if X then', 9, 'N01');
  Assert.IsTrue(P.Ok, 'Tabs, Ok: ' + P.Reason);
  Assert.IsTrue(P.Wrap, 'Tabs, Wrap');
  Assert.AreEqual(#9#9, P.BlockIndent, 'Tabs, BlockIndent');
  Assert.AreEqual(#9#9#9'var N01 := 5;', P.DeclText, 'Tabs, DeclText');
  Assert.AreEqual<Integer>(8, P.NameCol, 'Tabs, NameCol');
  P := PlanIntroduce(#9'    Y := 5;', #9'  else', 11, 'N01');
  Assert.IsTrue(P.Ok, 'gemischt, Ok: ' + P.Reason);
  Assert.IsTrue(P.Wrap, 'gemischt, Wrap');
  Assert.AreEqual(#9'  ', P.BlockIndent, 'gemischt, BlockIndent');
  Assert.AreEqual(#9'    ', P.Indent, 'gemischt, Indent');
  // Zweigzeile mit Tab, Anweisung mit Leerzeichen: BlockIndent kommt aus
  // der Zweigzeile, Indent aus der Zeile - unabhaengig voneinander.
  P := PlanIntroduce('    Y := 5;', #9'if X then', 10, 'N01');
  Assert.IsTrue(P.Ok, 'Tab/Leerzeichen, Ok: ' + P.Reason);
  Assert.IsTrue(P.Wrap, 'Tab/Leerzeichen, Wrap');
  Assert.AreEqual(TAB1, P.BlockIndent, 'Tab/Leerzeichen, BlockIndent');
  Assert.AreEqual('    var N01 := 5;', P.DeclText, 'Tab/Leerzeichen, DeclText');
end;

// begin..end fuer den Zweig nur, wenn die Zeile genau die EINE Anweisung
// des Zweigs enthaelt und sie dort mit ';' endet (README Grenzen;
// TVnpPlan.Wrap): ohne ';' (vor else), mit Operator am Ende oder offener
// Argumentliste -> "nicht unterstuetzt" (vnptest: no semi); ein else oder
// ein zweites ';' auf der Zeile -> Abbruch (begin..end schloesse das else
// ein bzw. Z := 1 liefe nur noch im Zweig). Nur der Code zaehlt: ';' und
// else in Strings und Kommentaren und 'Else' als Teil eines Bezeichners
// lassen den Wrap zu.
procedure TTestVnpRefuse.Wrap_ExactlyOneCompleteStatement;
var
  P : TVnpPlan;
begin
  P := PlanIntroduce('    Result := 999', '  if X then', 15, 'N01');
  Assert.IsFalse(P.Ok, 'ohne ;');
  Assert.IsTrue(Pos('nicht unterstuetzt', P.Reason) > 0,
    'Grund ohne ;: ' + P.Reason);
  P := PlanIntroduce('    Result := 42 +', '  if Done then', 15, 'N01');
  Assert.IsFalse(P.Ok, 'Ausdruck geht in der naechsten Zeile weiter');
  Assert.IsTrue(Pos('nicht unterstuetzt', P.Reason) > 0,
    'Grund Ausdruck: ' + P.Reason);
  P := PlanIntroduce('    Foo(42,', '  for I := 1 to 3 do', 9, 'N01');
  Assert.IsFalse(P.Ok, 'Argumentliste geht in der naechsten Zeile weiter');
  Assert.IsTrue(Pos('nicht unterstuetzt', P.Reason) > 0,
    'Grund Argumentliste: ' + P.Reason);
  // Neu: die ZEILE endet mit ';', die Zweig-Anweisung aber vor dem else
  // bzw. vor der zweiten Anweisung.
  P := PlanIntroduce('    Y := 42 else Y := 0;', '  if X then', 11, 'N01');
  Assert.IsFalse(P.Ok, 'else auf der Zeile - Plan "' + P.NewUseLine + '"');
  Assert.IsTrue(Pos('Anweisung des Zweigs', P.Reason) > 0,
    'Grund else: ' + P.Reason);
  P := PlanIntroduce('    Y := 42; Z := 1;', '  if X then', 11, 'N01');
  Assert.IsFalse(P.Ok, 'zweite Anweisung - Plan "' + P.NewUseLine + '"');
  Assert.IsTrue(Pos('Anweisung des Zweigs', P.Reason) > 0,
    'Grund zweite Anweisung: ' + P.Reason);
  // ';' im String (die 42 in Spalte 27).
  P := PlanIntroduce('    S := ''a;b'' + IntToStr(42);', '  if X then', 27,
    'N01');
  Assert.IsTrue(P.Ok, '; im String, Ok: ' + P.Reason);
  Assert.IsTrue(P.Wrap, '; im String, Wrap');
  Assert.AreEqual('  ', P.BlockIndent, '; im String, BlockIndent');
  Assert.AreEqual('    S := ''a;b'' + IntToStr(N01);', P.NewUseLine,
    '; im String, NewUseLine');
  P := PlanIntroduce('    Y := 42; // a; b else', '  if X then', 10, 'N01');
  Assert.IsTrue(P.Ok, '; und else im Kommentar, Ok: ' + P.Reason);
  Assert.IsTrue(P.Wrap, '; und else im Kommentar, Wrap');
  Assert.AreEqual('    Y := N01; // a; b else', P.NewUseLine,
    '; und else im Kommentar, NewUseLine');
  P := PlanIntroduce('    S := ''else'' + IntToStr(42);', '  if X then', 28,
    'N01');
  Assert.IsTrue(P.Ok, 'else im String, Ok: ' + P.Reason);
  Assert.IsTrue(P.Wrap, 'else im String, Wrap');
  P := PlanIntroduce('    Elsewhere := 42;', '  if X then', 18, 'N01');
  Assert.IsTrue(P.Ok, 'Elsewhere, Ok: ' + P.Reason);
  Assert.IsTrue(P.Wrap, 'Elsewhere, Wrap');
end;

// Nie vor einem case-Zweig, einer Sprungmarke oder einem on-Handler (README
// Grenzen). Andere ':' machen die Zeile nicht dazu: ':' im String oder im
// Kommentar, die Typangabe einer Inline-var - auch die der Laufvariable
// einer for-Schleife - und die Feldbreite von Writeln (Value:8:2)
// (vnptest: case arm, on handler, colon in string, typed inline var).
procedure TTestVnpRefuse.Refuse_LabeledLines;
var
  P : TVnpPlan;
begin
  P := PlanIntroduce('    2: Result := 999;', '    1: Result := 5;', 18, 'N01');
  Assert.IsFalse(P.Ok, 'case-Zweig');
  Assert.IsTrue(Pos('case-Zweig', P.Reason) > 0,
    'Grund case-Zweig: ' + P.Reason);
  P := PlanIntroduce('    on E: EFoo do Result := 999;', '  except', 31, 'N01');
  Assert.IsFalse(P.Ok, 'on-Handler');
  Assert.IsTrue(Pos('on-Handler', P.Reason) > 0,
    'Grund on-Handler: ' + P.Reason);
  P := PlanIntroduce('  Writeln(''x: '', 42);', 'begin', 19, 'N01');
  Assert.IsTrue(P.Ok, 'Doppelpunkt im String: ' + P.Reason);
  P := PlanIntroduce('  var X: Integer := 42 * Y;', 'begin', 23, 'N01');
  Assert.IsTrue(P.Ok, 'typisierte Inline-var: ' + P.Reason);
  // Neu: Sprungmarke.
  P := PlanIntroduce('Fertig: X := 1;', '  Inc(I);', 14, 'N01');
  Assert.IsFalse(P.Ok, 'Sprungmarke');
  Assert.IsTrue(Pos('Sprungmarke', P.Reason) > 0,
    'Grund Sprungmarke: ' + P.Reason);
  P := PlanIntroduce('  Foo(42); // Hinweis: x', 'begin', 7, 'N01');
  Assert.IsTrue(P.Ok, 'Doppelpunkt im Kommentar: ' + P.Reason);
  // for-Laufvariable mit Typ (die 42 in Spalte 30) und Feldbreite (die 8
  // in Spalte 17): keine Sprungmarke.
  P := PlanIntroduce('  for var I: Integer := 0 to 42 do', 'begin', 30, 'N01');
  Assert.IsTrue(P.Ok, 'typisierte for-var: ' + P.Reason);
  Assert.AreEqual('  for var I: Integer := 0 to N01 do', P.NewUseLine,
    'typisierte for-var, NewUseLine');
  P := PlanIntroduce('  Writeln(Value:8:2);', 'begin', 17, 'N01');
  Assert.IsTrue(P.Ok, 'Feldbreite: ' + P.Reason);
  Assert.AreEqual('  Writeln(Value:N01:2);', P.NewUseLine,
    'Feldbreite, NewUseLine');
end;

// Zeilen, die mit else, end, until, finally oder except beginnen, sind
// keine eigene Anweisung - die Deklaration kaeme vor das Wort statt vor die
// Anweisung dahinter (bei finally/except ans Ende des try-Teils); auch
// gross geschrieben; der Grund nennt das Wort (vnptest: else).
procedure TTestVnpRefuse.Refuse_LineStartKeywords;
var
  P : TVnpPlan;
begin
  P := PlanIntroduce('  else Result := 7;', 'X := 1;', 18, 'N01');
  Assert.IsFalse(P.Ok, 'else');
  // Neu:
  P := PlanIntroduce('  end else Y := 42;', '    X := 1;', 18, 'N01');
  Assert.IsFalse(P.Ok, 'end');
  Assert.IsTrue(Pos('"end"', P.Reason) > 0, 'Grund end: ' + P.Reason);
  P := PlanIntroduce('  until I > 10;', '    Inc(I);', 14, 'N01');
  Assert.IsFalse(P.Ok, 'until');
  Assert.IsTrue(Pos('"until"', P.Reason) > 0, 'Grund until: ' + P.Reason);
  P := PlanIntroduce('  finally Count := 0;', '    Work;', 20, 'N01');
  Assert.IsFalse(P.Ok, 'finally');
  Assert.IsTrue(Pos('"finally"', P.Reason) > 0,
    'Grund finally: ' + P.Reason);
  P := PlanIntroduce('  except Result := 42;', '    Work;', 20, 'N01');
  Assert.IsFalse(P.Ok, 'except');
  Assert.IsTrue(Pos('"except"', P.Reason) > 0, 'Grund except: ' + P.Reason);
  P := PlanIntroduce('  UNTIL I > 10;', '    Inc(I);', 14, 'N01');
  Assert.IsFalse(P.Ok, 'UNTIL gross geschrieben');
end;

// Schon benannt: ist das Literal ALLEIN der Wert einer var/const-
// Deklaration (auch hex, mit Typangabe, mit Tab vor dem Literal) ->
// Abbruch; ist es nur ein Teil des Werts, geht es (README Grenzen;
// vnptest: named var, named hex, named const, var part, var compare).
// 'const Max: Integer = 42;' faellt auch unter die Konstanten-Regel; die
// Pruefung auf 'Namen' (vnptest) haelt fest, dass "schon benannt" zuerst
// greift.
procedure TTestVnpRefuse.Refuse_AlreadyNamed;
var
  P : TVnpPlan;
begin
  P := PlanIntroduce('  var MagicNr01 := 42;', 'begin', 21, 'N02');
  Assert.IsFalse(P.Ok, 'var');
  Assert.IsTrue(Pos('Namen', P.Reason) > 0, 'Grund var: ' + P.Reason);
  P := PlanIntroduce(#9'var MagicNr02 := $FF00;', 'begin', 20, 'N02');
  Assert.IsFalse(P.Ok, 'var hex');
  Assert.IsTrue(Pos('Namen', P.Reason) > 0, 'Grund var hex: ' + P.Reason);
  P := PlanIntroduce('  const Max: Integer = 42; // x', 'begin', 25, 'N02');
  Assert.IsFalse(P.Ok, 'const');
  Assert.IsTrue(Pos('Namen', P.Reason) > 0, 'Grund const: ' + P.Reason);
  P := PlanIntroduce('  var Y := 42 * X;', 'begin', 13, 'N02');
  Assert.IsTrue(P.Ok, 'Teil des Werts: ' + P.Reason);
  P := PlanIntroduce('  var B := X = 42;', 'begin', 18, 'N02');
  Assert.IsTrue(P.Ok, 'Vergleich im Wert: ' + P.Reason);
  // Neu: typisierte Inline-var mit dem Literal allein.
  P := PlanIntroduce('  var X: Integer := 42;', 'begin', 22, 'N02');
  Assert.IsFalse(P.Ok, 'typisierte Inline-var');
  Assert.IsTrue(Pos('Namen', P.Reason) > 0,
    'Grund typisierte Inline-var: ' + P.Reason);
  // Neu: Tab zwischen ':=' und dem Literal (die 42 in Spalte 11).
  P := PlanIntroduce(#9'var X :='#9'42;', 'begin', 11, 'N02');
  Assert.IsFalse(P.Ok, 'Tab vor dem Literal');
  Assert.IsTrue(Pos('Namen', P.Reason) > 0,
    'Grund Tab vor dem Literal: ' + P.Reason);
end;

// Nie in einer Konstanten-Deklaration und nie im Typ einer Inline-var -
// dort sind nur Konstanten erlaubt (README Grenzen, E2026): jedes Literal
// einer const-Zeile (Gross/Klein egal), die Grenzen im Typ, und ein
// Literal im Wert, wenn ein GLEICHES im Typ steht (es wuerde mit ersetzt).
// Ein anderes Literal im Typ hindert den Wert nicht.
procedure TTestVnpRefuse.Refuse_ConstantContexts;
var
  P : TVnpPlan;
begin
  P := PlanIntroduce('  const C = 42 * 2;', 'begin', 13, 'N01');
  Assert.IsFalse(P.Ok, 'const, die 42 - Plan "' + P.NewUseLine + '"');
  Assert.IsTrue(Pos('Konstante', P.Reason) > 0, 'Grund const: ' + P.Reason);
  P := PlanIntroduce('  CONST C = 42 * 2;', 'begin', 18, 'N01');
  Assert.IsFalse(P.Ok, 'CONST, die 2 - Plan "' + P.NewUseLine + '"');
  // array[0..9]: die 0 in Spalte 16, die 9 in Spalte 19.
  P := PlanIntroduce('  var A: array[0..9] of Byte;', 'begin', 16, 'N01');
  Assert.IsFalse(P.Ok, 'Typ, untere Grenze - Plan "' + P.NewUseLine + '"');
  Assert.IsTrue(Pos('Typ', P.Reason) > 0, 'Grund Typ: ' + P.Reason);
  P := PlanIntroduce('  var A: array[0..9] of Byte;', 'begin', 19, 'N01');
  Assert.IsFalse(P.Ok, 'Typ, obere Grenze - Plan "' + P.NewUseLine + '"');
  // 1..9 := 9 - X: die 9 im Typ (Spalte 13) und im Wert (Spalte 18).
  P := PlanIntroduce('  VAR D: 1..9 := 9 - X;', 'begin', 18, 'N01');
  Assert.IsFalse(P.Ok, 'gleiches Literal im Typ - Plan "' + P.NewUseLine
    + '"');
  Assert.IsTrue(Pos('Typ', P.Reason) > 0,
    'Grund gleiches Literal im Typ: ' + P.Reason);
  P := PlanIntroduce('  var D: 1..9 := 5 - X;', 'begin', 18, 'N01');
  Assert.IsTrue(P.Ok, 'anderes Literal im Typ: ' + P.Reason);
  Assert.AreEqual('  var D: 1..9 := N01 - X;', P.NewUseLine,
    'anderes Literal im Typ, der Typ bleibt');
end;

// Die Zeile darueber muss eine Anweisung beenden: ';' im Code (nicht im
// Kommentar) oder begin/try/finally/except/repeat - dann ohne Wrap; '//'
// im String ist kein Kommentar, 'then' im Kommentar kein Zweig; eine
// Sprungmarke allein darueber beendet nichts (vnptest: unclear prev,
// comment after ;, prev with string).
procedure TTestVnpRefuse.PrevLine_MustEndStatement;
var
  P : TVnpPlan;
begin
  P := PlanIntroduce('    Result := 7;', '  X := Y +', 15, 'N01');
  Assert.IsFalse(P.Ok, 'Zeile darueber unfertig');
  Assert.IsTrue(Pos('weder', P.Reason) > 0, 'Grund unfertig: ' + P.Reason);
  P := PlanIntroduce('    Result := 7;', '  Inc(X); // fertig', 15, 'N01');
  Assert.IsTrue(P.Ok, '; mit Kommentar dahinter: ' + P.Reason);
  P := PlanIntroduce('  X := 5;', '  S := ''a'' + ''b''; // fertig', 8, 'N01');
  Assert.IsTrue(P.Ok, 'Strings in der Zeile darueber: ' + P.Reason);
  // Neu:
  P := PlanIntroduce('    X := 5;', '  try', 10, 'N01');
  Assert.IsTrue(P.Ok, 'try, Ok: ' + P.Reason);
  Assert.IsFalse(P.Wrap, 'try, kein Wrap');
  P := PlanIntroduce('    X := 5;', '  finally', 10, 'N01');
  Assert.IsTrue(P.Ok, 'finally, Ok: ' + P.Reason);
  Assert.IsFalse(P.Wrap, 'finally, kein Wrap');
  P := PlanIntroduce('    X := 5;', '  except', 10, 'N01');
  Assert.IsTrue(P.Ok, 'except, Ok: ' + P.Reason);
  Assert.IsFalse(P.Wrap, 'except, kein Wrap');
  P := PlanIntroduce('    X := 5;', '  repeat', 10, 'N01');
  Assert.IsTrue(P.Ok, 'repeat, Ok: ' + P.Reason);
  Assert.IsFalse(P.Wrap, 'repeat, kein Wrap');
  P := PlanIntroduce('  X := 5;', '  S := ''http://x'';', 8, 'N01');
  Assert.IsTrue(P.Ok, '// im String, Ok: ' + P.Reason);
  P := PlanIntroduce('  X := 5;', '  Y := 1; // then', 8, 'N01');
  Assert.IsTrue(P.Ok, 'then im Kommentar, Ok: ' + P.Reason);
  Assert.IsFalse(P.Wrap, 'then im Kommentar, kein Wrap');
  P := PlanIntroduce('  X := 5;', '  Y := Z // fertig;', 8, 'N01');
  Assert.IsFalse(P.Ok, '; nur im Kommentar');
  Assert.IsTrue(Pos('weder', P.Reason) > 0,
    'Grund ; im Kommentar: ' + P.Reason);
  P := PlanIntroduce('    Y := 42;', '  Fertig:', 10, 'N01');
  Assert.IsFalse(P.Ok, 'Sprungmarke allein darueber');
  Assert.IsTrue(Pos('weder', P.Reason) > 0,
    'Grund Sprungmarke darueber: ' + P.Reason);
end;

// Eine Zeile 'Name = ...' ist die Deklaration eines const- oder
// type-Abschnitts - eine Anweisung beginnt nie so, und eine Variable davor
// waere dort ungueltig (README Grenzen). '=' als Vergleich in einer
// Anweisung ('if X = 42 then', 'Ok := X = 42;') bleibt erlaubt.
procedure TTestVnpRefuse.Refuse_DeclarationLines;
var
  P : TVnpPlan;
begin
  // const-Abschnitt: die 42 in Spalte 7.
  P := PlanIntroduce('  B = 42 * 2;', '  A = 1;', 7, 'N01');
  Assert.IsFalse(P.Ok, 'const-Abschnitt - Plan "' + P.NewUseLine + '"');
  Assert.IsTrue(Pos('Deklaration', P.Reason) > 0,
    'Grund const-Abschnitt: ' + P.Reason);
  // type-Abschnitt: die 9 hinter '..' in Spalte 19.
  P := PlanIntroduce('  TArr = array[0..9] of Byte;', '  TFoo = Integer;', 19,
    'N01');
  Assert.IsFalse(P.Ok, 'type-Abschnitt - Plan "' + P.NewUseLine + '"');
  Assert.IsTrue(Pos('Deklaration', P.Reason) > 0,
    'Grund type-Abschnitt: ' + P.Reason);
  // Ohne Leerzeichen um '=': die 42 in Spalte 5.
  P := PlanIntroduce('  C=42;', 'begin', 5, 'N01');
  Assert.IsFalse(P.Ok, 'C=42 - Plan "' + P.NewUseLine + '"');
  // '=' als Vergleich: die 42 in Spalte 10 bzw. 13.
  P := PlanIntroduce('  if X = 42 then', '  Y := 1;', 10, 'N01');
  Assert.IsTrue(P.Ok, 'Vergleich im if: ' + P.Reason);
  Assert.AreEqual('  if X = N01 then', P.NewUseLine,
    'Vergleich im if, NewUseLine');
  P := PlanIntroduce('  Ok := X = 42;', 'begin', 13, 'N01');
  Assert.IsTrue(P.Ok, 'Vergleich in der Zuweisung: ' + P.Reason);
  Assert.AreEqual('  Ok := X = N01;', P.NewUseLine,
    'Vergleich in der Zuweisung, NewUseLine');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestVnpRefuse);
end.
