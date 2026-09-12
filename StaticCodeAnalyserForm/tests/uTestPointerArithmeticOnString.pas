unit uTestPointerArithmeticOnString;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestPointerArithmeticOnString = class
  public
    [Test] procedure PCharPlusOffsetWithoutCheck_Reported;
    [Test] procedure PAnsiCharMinusOffsetWithoutCheck_Reported;
    [Test] procedure PCharWithEmptyCheck_NotReported;
    [Test] procedure PCharWithLengthCheck_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // Voll-Review 2026-09-12 (Major 79 + Testluecke 185): Wortgrenze
    // der Guard-Suche und der bis dahin ungetestete Assigned-Zweig
    [Test] procedure ForeignIdentSuffix_NoGuard_StillReported;
    [Test] procedure PCharWithAssignedCheck_NotReported;
    [Test] procedure ForeignAssignedCheck_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestPointerArithmeticOnString.PCharPlusOffsetWithoutCheck_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string);'#13#10 +
  'var p: PChar;'#13#10 +
  'begin'#13#10 +
  '  p := PChar(s) + 5;'#13#10 +
  '  DoStuff(p);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkPointerArithmeticOnString) >= 1);
  finally F.Free; end;
end;

procedure TTestPointerArithmeticOnString.PAnsiCharMinusOffsetWithoutCheck_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const a: AnsiString);'#13#10 +
  'var p: PAnsiChar;'#13#10 +
  'begin'#13#10 +
  '  p := PAnsiChar(a) - 1;'#13#10 +
  '  DoStuff(p);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkPointerArithmeticOnString) >= 1);
  finally F.Free; end;
end;

procedure TTestPointerArithmeticOnString.PCharWithEmptyCheck_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string);'#13#10 +
  'var p: PChar;'#13#10 +
  'begin'#13#10 +
  '  if s <> '''' then'#13#10 +
  '    p := PChar(s) + 5;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPointerArithmeticOnString));
  finally F.Free; end;
end;

procedure TTestPointerArithmeticOnString.PCharWithLengthCheck_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string);'#13#10 +
  'var p: PChar;'#13#10 +
  'begin'#13#10 +
  '  if Length(s) >= 6 then'#13#10 +
  '    p := PChar(s) + 5;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkPointerArithmeticOnString));
  finally F.Free; end;
end;

procedure TTestPointerArithmeticOnString.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string);'#13#10 +
  'var p: PChar;'#13#10 +
  'begin'#13#10 +
  '  p := PChar(s) + 1;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkPointerArithmeticOnString then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkPointerArithmeticOnString finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestPointerArithmeticOnString.ForeignIdentSuffix_NoGuard_StillReported;
// Voll-Review 2026-09-12 (Major 79): die Guard-Suche lief ueber Pos
// und traf SUFFIXE fremder Bezeichner - fuer die Variable 's'
// unterdrueckte schon ein 'if flags=0 then' im Vorfenster den Fund
// ('flags=0' enthaelt 's='). Der verschwundene Fund ist eine latente
// AV, denn ein Empty-Check auf s existiert nirgends.
//
// Der Beleg laeuft ueber diesen Harness und nicht ueber die CLI:
// fkPointerArithmeticOnString traegt fcLow (uSCAConsts:1258) und ist
// unter dem Default-Confidence-Filter unsichtbar - auch die
// Positiv-Kontrolle ohne jeden Guard erscheint dort nicht (an der
// Bestands-Exe nachgemessen).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string; flags: Integer);'#13#10 +
  'var p: PChar;'#13#10 +
  'begin'#13#10 +
  '  if flags=0 then'#13#10 +
  '    Exit;'#13#10 +
  '  p := PChar(s) + 5;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkPointerArithmeticOnString),
    'ein fremdes flags=0 ist kein Empty-Check fuer s');
  finally F.Free; end;
end;

procedure TTestPointerArithmeticOnString.PCharWithAssignedCheck_NotReported;
// Testluecke 185 (Voll-Review 2026-09-12): der Assigned-Guard-Zweig
// war ungetestet - keine Bestandsfixture nutzte Assigned. Pinnt
// zugleich, dass Major 79 diesen Zweig nicht mitnimmt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string);'#13#10 +
  'var p: PChar;'#13#10 +
  'begin'#13#10 +
  '  if Assigned(s) then'#13#10 +
  '    p := PChar(s) + 5;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkPointerArithmeticOnString),
    'Assigned(s) gilt als Guard');
  finally F.Free; end;
end;

procedure TTestPointerArithmeticOnString.ForeignAssignedCheck_StillReported;
// Gegenprobe zum Assigned-Zweig: das Assigned gilt einer ANDEREN
// Variablen, deren Name auf den Bezeichner endet ('xs' endet auf
// 's') - kein Guard fuer s.
//
// Dieser Test ist VOR wie NACH Major 79 gruen, und das ist die
// Aussage: die '('-Formen (assigned(/length() waren nie von der
// Suffix-Kollision betroffen, weil die Klammer schon eine
// natuerliche linke Grenze ist ('assigned(xs)' enthaelt kein
// 'assigned(s)'). Er haelt diese Seite gegen kuenftige Umbauten
// fest, die Fenster-Suche und Guard-Muster anfassen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(const s: string; xs: TObject);'#13#10 +
  'var p: PChar;'#13#10 +
  'begin'#13#10 +
  '  if Assigned(xs) then'#13#10 +
  '    p := PChar(s) + 5;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1,
    TFindingHelper.Count(F, fkPointerArithmeticOnString),
    'Assigned auf einer fremden Variablen ist kein Guard fuer s');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPointerArithmeticOnString);

end.
