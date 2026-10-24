unit uTestRdxIntroPlan;

// DUnitX-Tests fuer uRdxIntroPlan (reDelphix, Code-Aktion "Lokale
// Konstante einfuehren", Refactoring ohne Fund): das Literal am Caret,
// alle gleichen Literale der Zeile (nur Code - nicht in Strings und
// Kommentaren), die Deklarationszeile (E26: 'const Name = Literal;'), die
// Spalten vor und nach dem Ersetzen, CodePart, NextFreeName,
// LineLooksFpcAware, Utf8Len und CharColOfByte. Den Zweig ohne begin und
// die Ablehnungen prueft uTestRdxIntroRefuse (geteilt wegen SCA141).
//
// 1:1 aus dem Labor VarNameProject (uTestVnpPlan, Stand 2026-10-14 nach dem
// Review F/B vom 2026-10-13, Entscheid E24: erst der im Labor gemessene
// Stand, die Zusammenlegung mit uRdxCodeMap/uRdxBufferMath folgt
// spaeter), nur Variante C1h: die
// Tests von TemplateCode und LoneLfCount (Variante D1, uTestVnpTemplate)
// bleiben im Labor. README und Demo-Dateien meinen hier und in den Tests
// die des Labors (VarNameProject\README.md, VarNameProject\demo).
//
// Vertrag: die Interface-Kommentare von uRdxIntroPlan, README (Varianten,
// Grenzen, Messpunkte) und die Demo-Dateien (Faelle 1-6). Alle Erwartungen
// sind von Hand abgeleitete Literale. Spalten sind 1-basierte
// Zeichenspalten (UTF-16-Einheiten) der Zeile, ein Tab ist EINE Spalte;
// Byte-Indizes sind 0-basierte UTF-8-Offsets.
//
// Uebernommen aus dem Ad-hoc-Test vnptest.pas (FPC, 2026-10-11): alle 44
// Pruefungen vor "Live-Template-Code (Variante D1)" mit denselben Eingaben
// und Erwartungen; zusammengesetzte Pruefungen (a and b) stehen hier als
// einzelne Assertions.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxIntroPlan = class
  public
    // Gleiche Literale der Zeile, Spalten vor und nach dem Ersetzen
    [Test] procedure Equal_Fall1_CaretOnFirstLiteral;
    [Test] procedure Equal_CaretOnSecondLiteral;
    [Test] procedure Equal_PrefixIsNotEqual;
    [Test] procedure Equal_OnlyCodeCounts;
    // Das Literal am Caret: Grenzen und Formen
    [Test] procedure Literal_CaretEdgesMinusTightSyntax;
    [Test] procedure Literal_Forms;
    [Test] procedure Literal_RangeBounds;
    // Kommentare und Hilfsfunktionen
    [Test] procedure CodePart_StringsStayCommentsGo;
    [Test] procedure Comment_ParenStarParenOnlyOpens;
    [Test] procedure Comment_StarParenAtColumnOne;
    [Test] procedure NextFreeName_WholeWordIgnoreCase;
    [Test] procedure NextFreeName_BeyondNinetyNine;
    [Test] procedure LineLooksFpcAware_Patterns;
    [Test] procedure Utf8Len_CharColOfByte;
    [Test] procedure Fall6_UmlautLineCharColumns;
  end;

implementation

uses
  System.SysUtils,
  uRdxIntroPlan;

const
  // Fall 1 der Demo (VarNameDemo.pas, Scale): 42 in Spalte 21 und 26.
  FALL1 = '  Result := Value * 42 + 42;';
  // Fall 6 der Demo (VarNameDemoUmlaut.pas, Greeting): u-Umlaut, scharfes
  // s und Euro-Zeichen VOR dem Literal; 46 Zeichen, die 42 in Spalte 43.
  FALL6 = '  Result := ''Gr'#$00FC#$00DF'e '#$20AC' '' + IntToStr(Count * 42);';
  // Ein einzelner Tab als string (nicht Char) fuer Assert.AreEqual.
  TAB1 : string = #9;

// Fall 1 (Demo, Caret auf der ersten 42): Deklaration mit der Einrueckung
// der Zeile, NameCol, beide gleichen Literale ersetzt, OldCols/NewCols
// aufsteigend, der Name steht an NewCols; hinter begin kein Wrap
// (vnptest: ok1, lit1, decl1, namecol1, use1, newcols1, newcol1b).
procedure TTestRdxIntroPlan.Equal_Fall1_CaretOnFirstLiteral;
var
  P : TRdxIntroPlan;
begin
  P := PlanIntroduce(FALL1, 'begin', 22, 'MagicNr01');
  Assert.IsTrue(P.Ok, 'Ok: ' + P.Reason);
  Assert.AreEqual<Integer>(2, Length(P.NewCols), 'Zahl NewCols');
  // Zuerst die Paarung NewUseLine/NewCols, dann die genauen Werte.
  Assert.AreEqual('MagicNr01', Copy(P.NewUseLine, P.NewCols[1], 9),
    'Name an NewCols[1]');
  Assert.AreEqual('42', P.Literal, 'Literal');
  Assert.AreEqual('  const MagicNr01 = 42;', P.DeclText, 'DeclText');
  Assert.AreEqual<Integer>(9, P.NameCol, 'NameCol');
  Assert.AreEqual('  Result := Value * MagicNr01 + MagicNr01;', P.NewUseLine,
    'NewUseLine');
  Assert.AreEqual<Integer>(21, P.NewCols[0], 'NewCols[0]');
  Assert.AreEqual<Integer>(33, P.NewCols[1], 'NewCols[1]');
  // Neu: Einrueckung, Spalten vor dem Schreiben, kein Wrap.
  Assert.AreEqual('  ', P.Indent, 'Indent');
  Assert.AreEqual<Integer>(2, Length(P.OldCols), 'Zahl OldCols');
  Assert.AreEqual<Integer>(21, P.OldCols[0], 'OldCols[0]');
  Assert.AreEqual<Integer>(26, P.OldCols[1], 'OldCols[1]');
  Assert.IsFalse(P.Wrap, 'Wrap hinter begin');
end;

// Caret auf der ZWEITEN von zwei gleichen 42: dasselbe Ergebnis - beide
// ersetzt, Spalten aufsteigend. Die Laengendifferenz Name - Literal
// verschiebt die folgenden Stellen: ein kuerzerer Name nach links, ein
// laengerer nach rechts - auch wenn der Name die Ziffer des Literals
// enthaelt ('1' -> 'MagicNr01').
procedure TTestRdxIntroPlan.Equal_CaretOnSecondLiteral;
var
  P : TRdxIntroPlan;
begin
  P := PlanIntroduce(FALL1, 'begin', 27, 'MagicNr01');
  Assert.IsTrue(P.Ok, 'Ok: ' + P.Reason);
  Assert.AreEqual('42', P.Literal, 'Literal');
  Assert.AreEqual('  Result := Value * MagicNr01 + MagicNr01;', P.NewUseLine,
    'NewUseLine');
  Assert.AreEqual<Integer>(2, Length(P.OldCols), 'Zahl OldCols');
  Assert.AreEqual<Integer>(21, P.OldCols[0], 'OldCols[0]');
  Assert.AreEqual<Integer>(26, P.OldCols[1], 'OldCols[1]');
  Assert.AreEqual<Integer>(2, Length(P.NewCols), 'Zahl NewCols');
  Assert.AreEqual<Integer>(21, P.NewCols[0], 'NewCols[0]');
  Assert.AreEqual<Integer>(33, P.NewCols[1], 'NewCols[1]');
  P := PlanIntroduce('  X := 1000000 + 1000000;', 'begin', 20, 'N01');
  Assert.IsTrue(P.Ok, 'kurzer Name, Ok: ' + P.Reason);
  Assert.AreEqual('  X := N01 + N01;', P.NewUseLine, 'kurzer Name, NewUseLine');
  Assert.AreEqual<Integer>(2, Length(P.NewCols), 'kurzer Name, Zahl NewCols');
  Assert.AreEqual<Integer>(8, P.NewCols[0], 'kurzer Name, NewCols[0]');
  Assert.AreEqual<Integer>(14, P.NewCols[1], 'kurzer Name, NewCols[1]');
  // Neu: '1' in Spalte 8 und 12, Caret auf der zweiten; der Name ist 8
  // Zeichen laenger und enthaelt selbst eine '1'.
  P := PlanIntroduce('  X := 1 + 1;', 'begin', 12, 'MagicNr01');
  Assert.IsTrue(P.Ok, 'Name mit Ziffer, Ok: ' + P.Reason);
  Assert.AreEqual('1', P.Literal, 'Name mit Ziffer, Literal');
  Assert.AreEqual('  X := MagicNr01 + MagicNr01;', P.NewUseLine,
    'Name mit Ziffer, NewUseLine');
  Assert.AreEqual<Integer>(2, Length(P.OldCols), 'Name mit Ziffer, Zahl Old');
  Assert.AreEqual<Integer>(8, P.OldCols[0], 'Name mit Ziffer, OldCols[0]');
  Assert.AreEqual<Integer>(12, P.OldCols[1], 'Name mit Ziffer, OldCols[1]');
  Assert.AreEqual<Integer>(2, Length(P.NewCols), 'Name mit Ziffer, Zahl New');
  Assert.AreEqual<Integer>(8, P.NewCols[0], 'Name mit Ziffer, NewCols[0]');
  Assert.AreEqual<Integer>(20, P.NewCols[1], 'Name mit Ziffer, NewCols[1]');
end;

// Gleich heisst derselbe Literaltext: '4' trifft nicht den Anfang von '42',
// '42' nicht die beiden '4' (Caret auf der letzten 4 bzw. auf der 42).
procedure TTestRdxIntroPlan.Equal_PrefixIsNotEqual;
var
  P : TRdxIntroPlan;
begin
  P := PlanIntroduce('X := 4 + 42 + 4;', 'begin', 15, 'MagicNr01');
  Assert.IsTrue(P.Ok, '4, Ok: ' + P.Reason);
  Assert.AreEqual('4', P.Literal, '4, Literal');
  Assert.AreEqual('const MagicNr01 = 4;', P.DeclText, '4, DeclText');
  Assert.AreEqual<Integer>(7, P.NameCol, '4, NameCol ohne Einrueckung');
  Assert.AreEqual('X := MagicNr01 + 42 + MagicNr01;', P.NewUseLine,
    '4, NewUseLine');
  Assert.AreEqual<Integer>(2, Length(P.OldCols), '4, Zahl OldCols');
  Assert.AreEqual<Integer>(6, P.OldCols[0], '4, OldCols[0]');
  Assert.AreEqual<Integer>(15, P.OldCols[1], '4, OldCols[1]');
  Assert.AreEqual<Integer>(2, Length(P.NewCols), '4, Zahl NewCols');
  Assert.AreEqual<Integer>(6, P.NewCols[0], '4, NewCols[0]');
  Assert.AreEqual<Integer>(23, P.NewCols[1], '4, NewCols[1]');
  P := PlanIntroduce('X := 4 + 42 + 4;', 'begin', 11, 'MagicNr01');
  Assert.IsTrue(P.Ok, '42, Ok: ' + P.Reason);
  Assert.AreEqual('42', P.Literal, '42, Literal');
  Assert.AreEqual('X := 4 + MagicNr01 + 4;', P.NewUseLine, '42, NewUseLine');
  Assert.AreEqual<Integer>(1, Length(P.OldCols), '42, Zahl OldCols');
  Assert.AreEqual<Integer>(10, P.OldCols[0], '42, OldCols[0]');
end;

// Nur Literale im Code: Caret im String, im Zeichencode (#13, #$0D), im
// Bezeichner (X42) oder im Kommentar findet keines; gleiche Literale in
// Strings und Kommentaren ({ }, (* *), //) bleiben stehen, ebenso die
// Ziffern in X42 und #42 (kein Literal) und $42, 0.42 (anderer
// Literaltext) (vnptest: string, charcode, only code occurrences).
procedure TTestRdxIntroPlan.Equal_OnlyCodeCounts;
const
  MIXED = '  S := ''42'' + #13 + X42; // 42';
var
  P : TRdxIntroPlan;
begin
  P := PlanIntroduce(MIXED, 'begin', 10, 'N01');
  Assert.IsFalse(P.Ok, 'Caret im String');
  P := PlanIntroduce(MIXED, 'begin', 16, 'N01');
  Assert.IsFalse(P.Ok, 'Caret im Zeichencode #13');
  P := PlanIntroduce('  S := ''a'' + IntToStr(42); { 42 }', 'begin', 24, 'N01');
  Assert.IsTrue(P.Ok, '{ 42 }, Ok: ' + P.Reason);
  Assert.AreEqual<Integer>(1, Length(P.OldCols), 'nur die 42 im Code');
  // Neu:
  P := PlanIntroduce(MIXED, 'begin', 22, 'N01');
  Assert.IsFalse(P.Ok, 'Caret im Bezeichner X42');
  P := PlanIntroduce(MIXED, 'begin', 29, 'N01');
  Assert.IsFalse(P.Ok, 'Caret im //-Kommentar');
  P := PlanIntroduce('  S := #$0D + IntToStr(42);', 'begin', 10, 'N01');
  Assert.IsFalse(P.Ok, 'Caret im Zeichencode #$0D');
  P := PlanIntroduce('  S := ''42'' + IntToStr(42) + IntToStr(42); // 42',
    'begin', 24, 'N01');
  Assert.IsTrue(P.Ok, 'String/Kommentar, Ok: ' + P.Reason);
  Assert.AreEqual('  S := ''42'' + IntToStr(N01) + IntToStr(N01); // 42',
    P.NewUseLine, 'String und Kommentar bleiben');
  Assert.AreEqual<Integer>(2, Length(P.NewCols), 'Zahl NewCols');
  Assert.AreEqual<Integer>(24, P.NewCols[0], 'NewCols[0]');
  Assert.AreEqual<Integer>(40, P.NewCols[1], 'NewCols[1]');
  P := PlanIntroduce('  X := 42 (* 42 *) + 42; { 42 }', 'begin', 8, 'N01');
  Assert.AreEqual('  X := N01 (* 42 *) + N01; { 42 }', P.NewUseLine,
    '(* *) und { } bleiben');
  // Die 42 in Spalte 14; X42, #42, $42 und 0.42 bleiben stehen.
  P := PlanIntroduce('  Y := X42 + 42 + Ord(#42) + $42 + 0.42;', 'begin', 14,
    'N01');
  Assert.IsTrue(P.Ok, 'X42 #42 $42 0.42, Ok: ' + P.Reason);
  Assert.AreEqual('  Y := X42 + N01 + Ord(#42) + $42 + 0.42;', P.NewUseLine,
    'X42 #42 $42 0.42 bleiben');
  Assert.AreEqual<Integer>(1, Length(P.OldCols), 'X42 #42 $42 0.42, Zahl');
  Assert.AreEqual<Integer>(14, P.OldCols[0], 'X42 #42 $42 0.42, OldCols[0]');
end;

// Caret VOR dem Zeichen ACaretCol: vor der ersten Ziffer und direkt hinter
// dem Literal zaehlt, eine Spalte davor und hinter dem ';' nicht (vnptest:
// ok2). Literal direkt hinter ':=' und direkt vor ';'; ein Minus davor
// gehoert nicht zum Literal und bleibt in der Zeile.
procedure TTestRdxIntroPlan.Literal_CaretEdgesMinusTightSyntax;
var
  P : TRdxIntroPlan;
begin
  P := PlanIntroduce('  X := 42;', 'begin', 10, 'N01');
  Assert.IsTrue(P.Ok, 'direkt hinter dem Literal: ' + P.Reason);
  Assert.AreEqual('42', P.Literal, 'Literal, Caret dahinter');
  P := PlanIntroduce('  X := 42;', 'begin', 8, 'N01');
  Assert.IsTrue(P.Ok, 'vor der ersten Ziffer: ' + P.Reason);
  P := PlanIntroduce('  X := 42;', 'begin', 7, 'N01');
  Assert.IsFalse(P.Ok, 'vor dem Leerzeichen davor');
  P := PlanIntroduce('  X := 42;', 'begin', 11, 'N01');
  Assert.IsFalse(P.Ok, 'hinter dem ;');
  P := PlanIntroduce('X:=42;', 'begin', 4, 'N01');
  Assert.IsTrue(P.Ok, 'ohne Leerzeichen: ' + P.Reason);
  Assert.AreEqual('42', P.Literal, 'ohne Leerzeichen, Literal');
  Assert.AreEqual('const N01 = 42;', P.DeclText, 'ohne Leerzeichen, DeclText');
  Assert.AreEqual<Integer>(7, P.NameCol, 'ohne Leerzeichen, NameCol');
  Assert.AreEqual('X:=N01;', P.NewUseLine, 'ohne Leerzeichen, NewUseLine');
  Assert.AreEqual<Integer>(1, Length(P.OldCols), 'ohne Leerzeichen, Zahl');
  Assert.AreEqual<Integer>(4, P.OldCols[0], 'ohne Leerzeichen, OldCols[0]');
  P := PlanIntroduce('X:=42;', 'begin', 6, 'N01');
  Assert.IsTrue(P.Ok, 'Caret direkt vor ;: ' + P.Reason);
  P := PlanIntroduce('  X := -42;', 'begin', 9, 'N01');
  Assert.IsTrue(P.Ok, 'Minus, Ok: ' + P.Reason);
  Assert.AreEqual('42', P.Literal, 'Minus, Literal');
  Assert.AreEqual('  const N01 = 42;', P.DeclText, 'Minus, DeclText');
  Assert.AreEqual('  X := -N01;', P.NewUseLine, 'Minus bleibt in der Zeile');
end;

// Formen des Zahl-Literals: hex mit '$' (auch klein geschrieben),
// Bruch (auch Fall 4 der Demo), Exponent (auch klein und mit Vorzeichen,
// Caret auf der Exponent-Ziffer). Delphi 11: der Zifferntrenner '_'
// gehoert zum Literal (dezimal und hex); die Ziffern eines Binaer-Literals
// ('%1010') sind kein eigenes Literal und nicht gleich dem dezimalen 1010
// (vnptest: hex, float).
procedure TTestRdxIntroPlan.Literal_Forms;
var
  P : TRdxIntroPlan;
begin
  P := PlanIntroduce('  M := X and $FF;', 'begin', 15, 'N01');
  Assert.AreEqual('$FF', P.Literal, 'hex');
  P := PlanIntroduce('  F := 3.25 * R;', 'begin', 9, 'N01');
  Assert.AreEqual('3.25', P.Literal, 'Bruch');
  // Neu:
  P := PlanIntroduce('  F := 1.5E3 * R;', 'begin', 12, 'N01');
  Assert.IsTrue(P.Ok, '1.5E3, Ok: ' + P.Reason);
  Assert.AreEqual('1.5E3', P.Literal, '1.5E3, Literal');
  Assert.AreEqual('  F := N01 * R;', P.NewUseLine, '1.5E3, NewUseLine');
  P := PlanIntroduce('  F := 2e-3;', 'begin', 11, 'N01');
  Assert.IsTrue(P.Ok, '2e-3, Ok: ' + P.Reason);
  Assert.AreEqual('2e-3', P.Literal, '2e-3, Literal');
  Assert.AreEqual('  const N01 = 2e-3;', P.DeclText, '2e-3, DeclText');
  Assert.AreEqual('  F := N01;', P.NewUseLine, '2e-3, NewUseLine');
  P := PlanIntroduce('  M := X and $ff;', 'begin', 16, 'N01');
  Assert.IsTrue(P.Ok, '$ff, Ok: ' + P.Reason);
  Assert.AreEqual('$ff', P.Literal, '$ff, Literal');
  Assert.AreEqual('  M := X and N01;', P.NewUseLine, '$ff, NewUseLine');
  // Fall 4 der Demo (Area): 0.5 in Spalte 30.
  P := PlanIntroduce('  Result := Width * Height * 0.5;', 'begin', 30,
    'MagicNr01');
  Assert.IsTrue(P.Ok, 'Fall 4, Ok: ' + P.Reason);
  Assert.AreEqual('0.5', P.Literal, 'Fall 4, Literal');
  Assert.AreEqual('  const MagicNr01 = 0.5;', P.DeclText, 'Fall 4, DeclText');
  Assert.AreEqual('  Result := Width * Height * MagicNr01;', P.NewUseLine,
    'Fall 4, NewUseLine');
  // Zifferntrenner: 1_000 in Spalte 8 und 16, danach 8 und 14.
  P := PlanIntroduce('  X := 1_000 + 1_000;', 'begin', 8, 'N01');
  Assert.IsTrue(P.Ok, '1_000, Ok: ' + P.Reason);
  Assert.AreEqual('1_000', P.Literal, '1_000, Literal');
  Assert.AreEqual('  X := N01 + N01;', P.NewUseLine, '1_000, NewUseLine');
  Assert.AreEqual<Integer>(2, Length(P.NewCols), '1_000, Zahl NewCols');
  Assert.AreEqual<Integer>(8, P.NewCols[0], '1_000, NewCols[0]');
  Assert.AreEqual<Integer>(14, P.NewCols[1], '1_000, NewCols[1]');
  P := PlanIntroduce('  M := X and $FF_00;', 'begin', 15, 'N01');
  Assert.IsTrue(P.Ok, '$FF_00, Ok: ' + P.Reason);
  Assert.AreEqual('$FF_00', P.Literal, '$FF_00, Literal');
  Assert.AreEqual('  M := X and N01;', P.NewUseLine, '$FF_00, NewUseLine');
  // Binaer-Literal: '%' in Spalte 8, das dezimale 1010 in Spalte 16.
  P := PlanIntroduce('  X := %1010 + 1010;', 'begin', 16, 'N01');
  Assert.IsTrue(P.Ok, '%1010, Ok: ' + P.Reason);
  Assert.AreEqual('1010', P.Literal, '%1010, Literal');
  Assert.AreEqual('  X := %1010 + N01;', P.NewUseLine, '%1010 bleibt stehen');
  Assert.AreEqual<Integer>(1, Length(P.OldCols), '%1010, Zahl OldCols');
  // Caret in %1010: welches Ergebnis auch immer - nie '1010' allein (das
  // ergaebe '%N01').
  P := PlanIntroduce('  X := %1010;', 'begin', 9, 'N01');
  Assert.IsFalse(P.Literal = '1010',
    'Caret im Binaer-Literal, Plan "' + P.NewUseLine + '"');
end;

// Bereiche: '1..5' endet vor '..' - die untere Grenze ist '1'. Die obere
// Grenze ist ein eigenes Literal (README Grenzen; die 9 in '0..9'): der
// Caret darauf findet sie, und als gleiches Literal wird sie mit ersetzt
// (vnptest: range).
procedure TTestRdxIntroPlan.Literal_RangeBounds;
const
  RANGE_LINE = '  if (X > 9) and (Y in [0..9]) then';
var
  P : TRdxIntroPlan;
begin
  P := PlanIntroduce('  case X of 1..5: ;', 'begin', 13, 'N01');
  Assert.AreEqual('1', P.Literal, 'Bereich');
  P := PlanIntroduce(RANGE_LINE, 'begin', 28, 'N01');
  Assert.IsTrue(P.Ok, 'Caret auf der 9 hinter "..": ' + P.Reason);
  Assert.AreEqual('9', P.Literal, 'Literal hinter ".."');
  P := PlanIntroduce(RANGE_LINE, 'begin', 11, 'N01');
  Assert.IsTrue(P.Ok, 'Caret auf der ersten 9: ' + P.Reason);
  Assert.AreEqual('  if (X > N01) and (Y in [0..N01]) then', P.NewUseLine,
    'beide 9 ersetzt');
  Assert.AreEqual<Integer>(2, Length(P.OldCols), 'Zahl OldCols');
  Assert.AreEqual<Integer>(11, P.OldCols[0], 'OldCols[0]');
  Assert.AreEqual<Integer>(28, P.OldCols[1], 'OldCols[1]');
  Assert.AreEqual<Integer>(2, Length(P.NewCols), 'Zahl NewCols');
  Assert.AreEqual<Integer>(11, P.NewCols[0], 'NewCols[0]');
  Assert.AreEqual<Integer>(30, P.NewCols[1], 'NewCols[1]');
end;

// CodePart: Kommentare ({ }, (* *), //) fallen weg, Strings bleiben samt
// ''; Kommentarzeichen im String und Quotes im Kommentar wechseln den
// Zustand nicht; von einer Kommentarzeile bleibt nur ihre Einrueckung
// (vnptest: codepart comment, codepart string, codepart quote).
procedure TTestRdxIntroPlan.CodePart_StringsStayCommentsGo;
begin
  Assert.AreEqual('', Trim(CodePart('    // then; die Deklaration')),
    'eingerueckte Kommentarzeile');
  Assert.AreEqual('  S := ''a;b'';  ', CodePart('  S := ''a;b''; { x } // y'),
    'String bleibt, Kommentare weg');
  Assert.AreEqual('  X := ''it''''s'';', CodePart('  X := ''it''''s'';'),
    'doppeltes Quote im String');
  // Neu:
  Assert.AreEqual('', CodePart('// x'), 'Zeile nur //');
  Assert.AreEqual('', CodePart('{ x }'), 'Zeile nur { }');
  Assert.AreEqual('', CodePart('(* x *)'), 'Zeile nur (* *)');
  Assert.AreEqual('    ', CodePart('    // x'),
    'eingerueckte //-Zeile: nur die Einrueckung bleibt');
  Assert.AreEqual(TAB1, CodePart(#9'{ x }'),
    'Tab-eingerueckte { }-Zeile: nur der Tab bleibt');
  Assert.AreEqual('  X := 1 + 2;', CodePart('  X := 1(* a *) + 2;'),
    '(* *) mitten in der Zeile');
  Assert.AreEqual('  S := ''{'' + ''//'' + ''(*'';',
    CodePart('  S := ''{'' + ''//'' + ''(*'';'), 'Kommentarzeichen im String');
  Assert.AreEqual('  X := 1; ', CodePart('  X := 1; // it''s'),
    'Quote im //-Kommentar');
  Assert.AreEqual('   X := 2;', CodePart('  { it''s } X := 2;'),
    'Quote im {}-Kommentar');
end;

// '(*)' oeffnet einen Kommentar nur: das '*' gehoert zum Oeffner, erst ein
// spaeteres '*)' schliesst (Pascal - unter FPC gibt
// 'X := 42; (*) X := 7; *)' 42 aus). Was dazwischen steht, ist Kommentar:
// die 42 darin bleibt stehen, der Caret darauf findet nichts, und CodePart
// laesst den ganzen Kommentar weg ("Kommentare fallen weg").
procedure TTestRdxIntroPlan.Comment_ParenStarParenOnlyOpens;
const
  // Die 42 im Code in Spalte 8, die im Kommentar in Spalte 16.
  OPENER_LINE = '  X := 42; (*) 42 *)';
var
  P : TRdxIntroPlan;
begin
  P := PlanIntroduce(OPENER_LINE, 'begin', 8, 'N01');
  Assert.IsTrue(P.Ok, 'Ok: ' + P.Reason);
  Assert.AreEqual('  X := N01; (*) 42 *)', P.NewUseLine,
    'die 42 im Kommentar bleibt');
  Assert.AreEqual<Integer>(1, Length(P.OldCols), 'Zahl OldCols');
  P := PlanIntroduce(OPENER_LINE, 'begin', 16, 'N01');
  Assert.IsFalse(P.Ok, 'Caret im Kommentar - Plan "' + P.NewUseLine + '"');
  Assert.AreEqual('', CodePart('(*) x *)'), 'CodePart: alles Kommentar');
end;

// Ein '*)' in Spalte 1 schliesst den (* *)-Kommentar erst am ')' - davor
// las der Leser 'Copy(ALine, 0, 2)' und schloss schon am '*', das ')'
// galt als Code (Pruefer 2026-10-13, Minor 2: eine Zeile mit '*)' am
// Anfang zaehlte als Code-Zeile darueber und fuehrte zur Ablehnung). Ein
// '*' oder ')' allein in Spalte 1 schliesst nicht.
procedure TTestRdxIntroPlan.Comment_StarParenAtColumnOne;
begin
  // Die Char-Ergebnisse per IsTrue: DUnitX hat keine Char-Ueberladung von
  // AreEqual (Gegen-Review Welle 1, Verdacht E2250/E2251).
  Assert.AreEqual(' X := 1;', CodePartFrom('*) X := 1;', 'p'),
    '*) in Spalte 1: nur der Code dahinter');
  Assert.IsTrue(CommentStateAfter('*) X := 1;', 'p') = 'c',
    '*) in Spalte 1 schliesst');
  Assert.AreEqual('', CodePartFrom('*)', 'p'), '*) allein: kein Code');
  Assert.IsTrue(CommentStateAfter('*)', 'p') = 'c', '*) allein schliesst');
  Assert.AreEqual(' Y', CodePartFrom(' *) Y', 'p'), '*) in Spalte 2');
  Assert.AreEqual('', CodePartFrom('*', 'p'), '* allein bleibt Kommentar');
  Assert.IsTrue(CommentStateAfter('*', 'p') = 'p', '* allein schliesst nicht');
  Assert.AreEqual('', CodePartFrom(') X', 'p'), ') ohne * bleibt Kommentar');
  Assert.IsTrue(CommentStateAfter(') X', 'p') = 'p',
    ') ohne * schliesst nicht');
  Assert.IsTrue(CommentStateAfter('*) X', 'b') = 'b',
    'im { }-Kommentar schliesst *) nicht');
end;

// NextFreeName: ABase + '01', '02', ... - der erste Name, der NICHT als
// ganzes Wort im Text steht (auch in einer Luecke, nicht hoechster + 1);
// Gross/Klein egal; als Teil eines laengeren Bezeichners zaehlt er nicht
// (vnptest: next, word).
procedure TTestRdxIntroPlan.NextFreeName_WholeWordIgnoreCase;
begin
  Assert.AreEqual('MagicNr02', NextFreeName('var MagicNr01: Integer;',
    'MagicNr'), 'MagicNr01 belegt');
  Assert.AreEqual('MagicNr01', NextFreeName('MagicNr010 := 1', 'MagicNr'),
    'MagicNr010 ist ein anderes Wort');
  // Neu:
  Assert.AreEqual('MagicNr01', NextFreeName('', 'MagicNr'), 'leerer Text');
  Assert.AreEqual('MagicNr04', NextFreeName('var MagicNr01 := 1;'#13#10
    + 'X := magicnr02 + MAGICNR03;', 'MagicNr'),
    '01..03 belegt, Gross/Klein egal');
  Assert.AreEqual('MagicNr02', NextFreeName('X := MagicNr01 + MagicNr03;',
    'MagicNr'), 'Luecke: 01 und 03 belegt');
  Assert.AreEqual('MagicNr01', NextFreeName('XMagicNr01 := MagicNr01_ + 1;',
    'MagicNr'), 'nur in laengeren Bezeichnern');
  Assert.AreEqual('MagicNr02', NextFreeName('XMagicNr01 := MagicNr01.Value;',
    'MagicNr'), 'spaeteres ganzes Wort zaehlt');
  Assert.AreEqual('MagicNr10', NextFreeName('MagicNr01 MagicNr02 MagicNr03 '
    + 'MagicNr04 MagicNr05 MagicNr06 MagicNr07 MagicNr08 MagicNr09',
    'MagicNr'), 'nach 09 kommt 10');
end;

// Die Namen ABase + AFrom .. ABase + ATo (zweistellig), durch Leerzeichen
// getrennt - rekursiv statt Verkettung in einer Schleife (SCA110).
function TakenNames(const ABase: string; AFrom, ATo: Integer): string;
begin
  Result := '';
  if AFrom <= ATo then
    Result := ABase + Format('%.2d', [AFrom]) + ' '
      + TakenNames(ABase, AFrom + 1, ATo);
end;

// Sind 01 bis 99 belegt, geht es dreistellig weiter - und auch 100 wird
// gegen den Text geprueft (Pruefer 2026-10-13, Minor 4: ein fester
// Rueckfall 'MagicNrX' ohne Pruefung konnte kollidieren).
procedure TTestRdxIntroPlan.NextFreeName_BeyondNinetyNine;
var
  All : string;
begin
  All := TakenNames('MagicNr', 1, 99);
  Assert.AreEqual('MagicNr100', NextFreeName(All, 'MagicNr'),
    '01..99 belegt');
  Assert.AreEqual('MagicNr101', NextFreeName(All + 'MagicNr100', 'MagicNr'),
    '01..100 belegt');
  Assert.AreEqual('MagicNr50', NextFreeName(TakenNames('MagicNr', 1, 49)
    + TakenNames('MagicNr', 51, 99), 'MagicNr'), 'Luecke bei 50');
end;

// LineLooksFpcAware: die Spuren einer FPC-Weiche wie in reDelphix
// (TRdxRecipes.LineLooksFpcAware) - {$IFDEF FPC}, {$IFNDEF FPC}, {$IF
// DEFINED(FPC)}, {$MODE ...} (auch MODESWITCH), die Form (*$..*); Gross/
// Klein und Leerraum egal. Andere Direktiven, 'FPC' in Kommentar oder
// Bezeichner und eine leere Zeile sind keine.
procedure TTestRdxIntroPlan.LineLooksFpcAware_Patterns;
begin
  Assert.IsTrue(LineLooksFpcAware('{$IFDEF FPC}'), 'IFDEF FPC');
  Assert.IsTrue(LineLooksFpcAware('  {$ifndef fpc}'), 'ifndef fpc klein');
  Assert.IsTrue(LineLooksFpcAware('{$IF DEFINED(FPC)}'), 'IF DEFINED(FPC)');
  Assert.IsTrue(LineLooksFpcAware('{$IF Defined(FPC) and (FPC_FULLVERSION '
    + '>= 30200)}'), 'IF Defined(FPC) and ...');
  // FPC_FULLVERSION allein ist eine Weiche (Pruefer 2026-10-14, d).
  Assert.IsTrue(LineLooksFpcAware('{$IF FPC_FULLVERSION >= 30200}'),
    'IF FPC_FULLVERSION allein');
  Assert.IsTrue(LineLooksFpcAware('{$MODE objfpc}{$H+}'), 'MODE objfpc');
  Assert.IsTrue(LineLooksFpcAware('{$mode delphiunicode}'),
    'mode delphiunicode');
  Assert.IsTrue(LineLooksFpcAware('{$MODESWITCH advancedrecords}'),
    'MODESWITCH');
  Assert.IsTrue(LineLooksFpcAware('(*$mode delphi*)'), '(*$mode*)');
  Assert.IsTrue(LineLooksFpcAware('{ $IFDEF FPC }'),
    'Leerraum in der Direktive (vorsichtig)');
  Assert.IsFalse(LineLooksFpcAware('{$IFDEF DEBUG}'), 'IFDEF DEBUG');
  Assert.IsFalse(LineLooksFpcAware('{$IFDEF MSWINDOWS}'), 'IFDEF MSWINDOWS');
  Assert.IsFalse(LineLooksFpcAware('  X := 42; // laeuft auch unter FPC'),
    'FPC im Kommentar ohne Direktive');
  Assert.IsFalse(LineLooksFpcAware('uses FpcUnit, SysUtils;'),
    'FPC im Bezeichner');
  Assert.IsFalse(LineLooksFpcAware('{$R *.dfm}'), 'Ressourcen-Direktive');
  Assert.IsFalse(LineLooksFpcAware(''), 'leer');
end;

// Utf8Len zaehlt UTF-8-Bytes (Umlaut 2, Euro 3, Surrogatpaar 4);
// CharColOfByte bildet den 0-basierten Byte-Index auf die 1-basierte
// UTF-16-Spalte ab - am Zeichenanfang, hinter Euro und Surrogatpaar und am
// Zeilenende (vnptest: utf8len, charcol, charcol0).
procedure TTestRdxIntroPlan.Utf8Len_CharColOfByte;
const
  // a (Byte 0), Euro (Bytes 1-3), b (Byte 4); 3 Zeichen.
  EURO_LINE  = 'a'#$20AC'b';
  // a (Byte 0), Surrogatpaar (Bytes 1-4, Spalten 2-3), b (Byte 5); 4
  // UTF-16-Einheiten.
  EMOJI_LINE = 'a'#$D83D#$DE00'b';
begin
  Assert.AreEqual<Integer>(4, Utf8Len('a'#$00FC'b'), 'Utf8Len Umlaut');
  Assert.AreEqual<Integer>(3, CharColOfByte('a'#$00FC'b', 3),
    'Byte 3 = b hinter Umlaut');
  Assert.AreEqual<Integer>(1, CharColOfByte('abc', 0), 'Byte 0');
  // Neu:
  Assert.AreEqual<Integer>(0, Utf8Len(''), 'Utf8Len leer');
  Assert.AreEqual<Integer>(3, Utf8Len(#$20AC), 'Utf8Len Euro');
  Assert.AreEqual<Integer>(4, Utf8Len(#$D83D#$DE00), 'Utf8Len Surrogatpaar');
  Assert.AreEqual<Integer>(6, Utf8Len(EMOJI_LINE), 'Utf8Len a+Paar+b');
  Assert.AreEqual<Integer>(11, Utf8Len('Gr'#$00FC#$00DF'e '#$20AC),
    'Utf8Len Gruesse+Euro (Demo: 7 Zeichen, 11 Bytes)');
  Assert.AreEqual<Integer>(2, CharColOfByte('a'#$00FC'b', 1),
    'Byte 1 = Umlaut');
  Assert.AreEqual<Integer>(2, CharColOfByte(EURO_LINE, 1), 'Byte 1 = Euro');
  Assert.AreEqual<Integer>(3, CharColOfByte(EURO_LINE, 4),
    'Byte 4 = b hinter Euro');
  Assert.AreEqual<Integer>(4, CharColOfByte(EURO_LINE, 5),
    'Byte 5 = Zeilenende hinter Euro');
  Assert.AreEqual<Integer>(2, CharColOfByte(EMOJI_LINE, 1),
    'Byte 1 = Surrogatpaar');
  Assert.AreEqual<Integer>(4, CharColOfByte(EMOJI_LINE, 5),
    'Byte 5 = b hinter Surrogatpaar');
  Assert.AreEqual<Integer>(5, CharColOfByte(EMOJI_LINE, 6),
    'Byte 6 = Zeilenende hinter Surrogatpaar');
end;

// Nicht-ASCII VOR dem Literal. Fall 6 der Demo (Messpunkt M10): bis hinter
// das Euro-Zeichen 20 Zeichen = 24 Bytes; Byte 42 ist Zeichen 39, das 't'
// (README Lauf 3); 46 Zeichen = 50 Bytes, das Zeilenende ist Spalte 47.
// Der Plan rechnet in Zeichenspalten - die 42 steht in Spalte 43, nicht
// 47. Ein Surrogatpaar sind zwei Spalten (UTF-16) und vier Bytes.
procedure TTestRdxIntroPlan.Fall6_UmlautLineCharColumns;
const
  // Das Paar in Spalte 9-10 (Bytes 8-11), die 42 in Spalte 24 (Byte 25).
  PAIR_LINE = '  S := '''#$D83D#$DE00''' + IntToStr(42);';
var
  P : TRdxIntroPlan;
begin
  Assert.AreEqual<Integer>(50, Utf8Len(FALL6), 'Bytes der ganzen Zeile');
  Assert.AreEqual<Integer>(24,
    Utf8Len('  Result := ''Gr'#$00FC#$00DF'e '#$20AC),
    'Bytes bis hinter das Euro-Zeichen');
  Assert.AreEqual<Integer>(21, CharColOfByte(FALL6, 24),
    'Byte 24 = Spalte 21');
  Assert.AreEqual<Integer>(39, CharColOfByte(FALL6, 42),
    'Byte 42 = Spalte 39');
  Assert.AreEqual<Integer>(43, CharColOfByte(FALL6, 46),
    'Byte 46 = Spalte 43 (die 4)');
  Assert.AreEqual<Integer>(47, CharColOfByte(FALL6, 50),
    'Byte 50 = Zeilenende, Spalte 47');
  P := PlanIntroduce(FALL6, 'begin', 43, 'MagicNr01');
  Assert.IsTrue(P.Ok, 'Ok: ' + P.Reason);
  Assert.AreEqual('42', P.Literal, 'Literal');
  Assert.AreEqual('  const MagicNr01 = 42;', P.DeclText, 'DeclText');
  Assert.AreEqual('  Result := ''Gr'#$00FC#$00DF'e '#$20AC
    + ' '' + IntToStr(Count * MagicNr01);', P.NewUseLine, 'NewUseLine');
  Assert.AreEqual<Integer>(1, Length(P.OldCols), 'Zahl OldCols');
  Assert.AreEqual<Integer>(43, P.OldCols[0], 'OldCols[0]');
  Assert.AreEqual<Integer>(43, P.NewCols[0], 'NewCols[0]');
  // Neu: Surrogatpaar vor dem Literal.
  Assert.AreEqual<Integer>(24, CharColOfByte(PAIR_LINE, 25),
    'Surrogatpaar, Byte 25 = Spalte 24');
  P := PlanIntroduce(PAIR_LINE, 'begin', 24, 'N01');
  Assert.IsTrue(P.Ok, 'Surrogatpaar, Ok: ' + P.Reason);
  Assert.AreEqual('  S := '''#$D83D#$DE00''' + IntToStr(N01);', P.NewUseLine,
    'Surrogatpaar, NewUseLine');
  Assert.AreEqual<Integer>(1, Length(P.OldCols), 'Surrogatpaar, Zahl OldCols');
  Assert.AreEqual<Integer>(24, P.OldCols[0], 'Surrogatpaar, OldCols[0]');
  Assert.AreEqual<Integer>(24, P.NewCols[0], 'Surrogatpaar, NewCols[0]');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxIntroPlan);
end.
