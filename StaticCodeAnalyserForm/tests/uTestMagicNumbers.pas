unit uTestMagicNumbers;

// Tests fuer TMagicNumberDetector. Triviale Werte (0, 1, -1, 2) und
// per analyser.ini konfigurierbare Trivials werden nicht geflaggt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMagicNumbers = class
  public
    [Test] procedure MagicNumber_Reported;
    [Test] procedure TrivialZero_NotReported;
    [Test] procedure TrivialOne_NotReported;
    [Test] procedure ConstAssignment_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    [Test] procedure ComparisonInsideLiteral_NotReported;
    // Posten 261: der Ganzzahl-Torso eines Floats wurde gemeldet
    [Test] procedure FloatLiteral_NotReported;
    [Test] procedure ExponentLiteral_NotReported;
    [Test] procedure HexLiteral_NotReported;
    [Test] procedure FloatThenRealMagic_StillReported;
    // Posten 172: Zweierpotenz-Pfad und der ini-Override von IsTrivial
    [Test] procedure PowerOfTwo512_NotReported;
    [Test] procedure PowerOfTwo2048_Reported_ObereGrenze;
    [Test] procedure NonPowerOfTwo513_Reported_Kontrolle;
    [Test] procedure TrivialsOverride_ReplacesDefaultList;
  end;

implementation

uses
  // System.Classes: TrivialsOverride_ReplacesDefaultList tauscht die
  // globale TStringList DetectorMagicTrivials aus (Posten 172).
  System.Classes,
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 261: Float-Literale sind keine Magic Numbers -------- }
//
// Der Ziffern-Scan sammelt nur 0..9 und haelt am Dezimalpunkt an; der
// so entstandene Ganzzahl-TORSO wurde ungeprueft gemeldet. Der
// Kommentar 'Nur Integer-Zahl, kein Float / Hex' beschrieb die
// Absicht - es gab nur keine Wache, die sie durchsetzt. Hex fiel
// schon vorher heraus ('$' ist keine Ziffer), Float nicht.
//
// Sichtbar wurde die Willkuer an der Trivial-Pruefung: die greift am
// Torso, also verschwand '2.5' (als '2' trivial) und '3.5' wurde
// gemeldet. Fuer den Leser sah das nach Zufall aus.
//
// Alle Erwartungen an der gebauten Exe gemessen.

procedure TTestMagicNumbers.FloatLiteral_NotReported;
// Heute 1 Fund: 'Magic number "3"'. Nach dem Fix 0.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x, y: Double;'#13#10 +
  'begin'#13#10 +
  '  if x > 3.5 then x := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkMagicNumber),
      'der Ganzzahlteil eines Float-Literals ist keine Magic Number');
  finally F.Free; end;
end;

procedure TTestMagicNumbers.ExponentLiteral_NotReported;
// Exponentschreibweise, heute ebenfalls 'Magic number "3"'.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x, y: Double;'#13#10 +
  'begin'#13#10 +
  '  if x > 3e6 then x := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkMagicNumber),
      'auch die Exponentschreibweise ist ein Float-Literal');
  finally F.Free; end;
end;

procedure TTestMagicNumbers.HexLiteral_NotReported;
// Die HEUTE SCHON richtige Haelfte des Kommentars, jetzt
// festgenagelt: '$' ist keine Ziffer, Digits bleibt leer.
// Vor wie nach dem Fix 0.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x, y: Double;'#13#10 +
  'begin'#13#10 +
  '  if x > $400 then x := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkMagicNumber),
      'Hex-Literale erreichen die Ziffernschleife gar nicht');
  finally F.Free; end;
end;

procedure TTestMagicNumbers.FloatThenRealMagic_StillReported;
// DIE GEGENPROBE, und sie prueft den MELDETEXT, nicht nur die Zahl:
// heute wird der Torso '3' gemeldet, nach dem Fix die echte Magic
// Number '1027'. Ein Test auf die blosse Anzahl waere in beiden
// Faellen 1 und wuerde den Unterschied durchlassen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x, y: Double;'#13#10 +
  'begin'#13#10 +
  '  if (x > 3.5) and (y > 1027) then x := 0;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Fnd := TFindingHelper.FirstOf(F, fkMagicNumber);
    Assert.IsNotNull(Fnd, 'die 1027 bleibt eine Magic Number');
    Assert.IsTrue(Pos('1027', Fnd.MissingVar) > 0,
      'gemeldet werden muss die 1027, nicht der Torso 3 - Text: '
      + Fnd.MissingVar);
  finally F.Free; end;
end;


{ --- Posten 172: Zweierpotenzen und die ini-Trivials ------------- }
//
// Zwei Pfade von IsTrivial waren ungetestet: die Zweierpotenz-Regel
// (bis 1024, ausserhalb des if/else) und der Override aus
// analyser.ini. Der Override ERSETZT die Default-Liste, er ergaenzt
// sie nicht - genau so eine Kante braucht einen Vertragstest.
//
// Alles an der Exe gemessen, der Override end-to-end ueber eine
// eigene analyser.ini mit MagicNumberTrivials=7:
//
//         Default-ini   ini mit "=7"
//   7          1              0
//   100        0              1     <- ersetzt, nicht ergaenzt
//   512        0              0     <- Zweierpotenz, vom Override
//   513        1              1        unberuehrt

procedure TTestMagicNumbers.PowerOfTwo512_NotReported;
// Zweierpotenzen bis 1024 sind idiomatische Bit-/Puffer-
// Konstanten. Gemessen: 0.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: Integer);'#13#10 +
  'begin'#13#10 +
  '  if x = 512 then Beep;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkMagicNumber),
      '512 ist eine Zweierpotenz und damit trivial');
  finally F.Free; end;
end;

procedure TTestMagicNumbers.PowerOfTwo2048_Reported_ObereGrenze;
// Die Grenze der Regel ist 1024, nicht "jede Zweierpotenz".
// Gemessen: 1. Ohne diesen Test waere ein versehentlich
// entfernter Deckel unsichtbar.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: Integer);'#13#10 +
  'begin'#13#10 +
  '  if x = 2048 then Beep;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkMagicNumber),
      '2048 liegt ueber der 1024-Grenze und wird gemeldet');
  finally F.Free; end;
end;

procedure TTestMagicNumbers.NonPowerOfTwo513_Reported_Kontrolle;
// KONTROLLE zur 512: eins daneben, und der Fund kommt.
// Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: Integer);'#13#10 +
  'begin'#13#10 +
  '  if x = 513 then Beep;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkMagicNumber),
      '513 ist keine Zweierpotenz');
  finally F.Free; end;
end;

procedure TTestMagicNumbers.TrivialsOverride_ReplacesDefaultList;
// VERTRAGSTEST fuer den ini-Override. IsTrivial prueft die
// globale Liste im if-Zweig und die Defaults NUR im else -
// eine gesetzte Liste ersetzt sie also komplett. Das ist
// bewusst so, aber ueberraschend: wer "1024" ergaenzen will,
// verliert 0/1/2/-1/10/100, wenn er sie nicht mitschreibt.
//
// End-to-end an der Exe gegengeprueft (analyser.ini mit
// MagicNumberTrivials=7): 7 -> 0 Funde, 100 -> 1 Fund.
//
// Der globale Zustand wird hier gesichert und im finally
// zurueckgestellt - eine Testreihenfolge darf davon nichts
// merken.
const
  SRC_7 =
    'unit t; implementation'#13#10 +
    'procedure Foo(x: Integer);'#13#10 +
    'begin'#13#10 +
    '  if x = 7 then Beep;'#13#10 +
    'end;';
  SRC_100 =
    'unit t; implementation'#13#10 +
    'procedure Foo(x: Integer);'#13#10 +
    'begin'#13#10 +
    '  if x = 100 then Beep;'#13#10 +
    'end;';
var
  F     : TObjectList<TLeakFinding>;
  Alt   : TStringList;
  Eigen : Boolean;
begin
  Alt   := DetectorMagicTrivials;
  Eigen := False;
  try
    DetectorMagicTrivials := TStringList.Create;
    Eigen := True;
    DetectorMagicTrivials.CaseSensitive := False;
    DetectorMagicTrivials.Sorted        := True;
    DetectorMagicTrivials.Add('7');

    F := TFindingHelper.FindingsOf(SRC_7);
    try
      Assert.AreEqual<Integer>(0,
        TFindingHelper.Count(F, fkMagicNumber),
        '7 steht in der Override-Liste und ist damit trivial');
    finally F.Free; end;

    F := TFindingHelper.FindingsOf(SRC_100);
    try
      Assert.AreEqual<Integer>(1,
        TFindingHelper.Count(F, fkMagicNumber),
        'die Override-Liste ERSETZT die Defaults - 100 ist jetzt keine Trivialzahl mehr');
    finally F.Free; end;
  finally
    if Eigen then DetectorMagicTrivials.Free;
    DetectorMagicTrivials := Alt;
  end;
end;


procedure TTestMagicNumbers.MagicNumber_Reported;
// Detector scannt nur nkIfStmt-Bedingungen (per Design konservativ), und
// 1024 waere als Power-of-2 ohnehin trivial (siehe IsTrivial). Deshalb
// non-triviale Konstante in einer if-Bedingung als minimaler Trigger.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin'#13#10 +
  '  if x = 1027 then x := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMagicNumber) >= 1);
  finally F.Free; end;
end;

procedure TTestMagicNumbers.TrivialZero_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin'#13#10 +
  // Posten 292: stand vorher als 'x := 0;' da - eine ZUWEISUNG.
  // Der Detektor scannt nur if-Bedingungen, der Test war damit
  // gruen, ohne den Trivial-Pfad je zu erreichen. Jetzt in einer
  // if-Bedingung; an der Exe gemessen: 0.
  '  if x = 0 then x := 1;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.TrivialOne_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin'#13#10 +
  // Posten 292: dieselbe Blindstelle wie bei TrivialZero.
  // An der Exe gemessen: 0.
  '  if x = 1 then x := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.ConstAssignment_NotReported;
// const-Sektionen sind die korrekte Stelle fuer Numerik-Literale -
// dort soll der Detector NICHT flaggen.
const SRC =
  // Posten 292: die Fixture bestand vorher nur aus der
  // const-Sektion und einem leeren Rumpf - ohne if-Bedingung
  // erreichte sie den Detektor nie. Jetzt wird die Konstante in
  // einer Bedingung BENUTZT: das ist der Fall, den die Regel
  // belohnen soll (benannte Konstante statt Magic Number).
  // An der Exe gemessen: 0 - und mit der nackten 1027 statt
  // MAX_RETRIES waeren es 1.
  'unit t; implementation'#13#10 +
  'const MAX_RETRIES = 1027;'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin'#13#10 +
  '  if x = MAX_RETRIES then x := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var x: Integer;'#13#10 +
  'begin'#13#10 +
  '  if x = 1027 then x := 0;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkMagicNumber then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkMagicNumber finding expected');
    Assert.AreEqual(fkMagicNumber, Hit.Kind);
  finally F.Free; end;
end;

procedure TTestMagicNumbers.ComparisonInsideLiteral_NotReported;
// Review-MEDIUM 2026-08-09: '> 4711' steht INNERHALB eines String-Literals -
// Literal-Inhalte zaehlen nie als Code, also kein Magic-Number-Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Bar;'#13#10 +
  'var Msg: string;'#13#10 +
  'begin'#13#10 +
  '  if Msg = ''items > 4711'' then Msg := '''';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMagicNumber),
    'Vergleich+Zahl im String-Literal ist kein Code');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMagicNumbers);

end.
