unit uTestNestedTry;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestNestedTry = class
  public
    [Test] procedure SingleTry_NoFinding;
    [Test] procedure NestedTryExcept_Reported;
    [Test] procedure NestedTryFinally_Reported;
    [Test] procedure NestedTry_KindAndSeverity;
    // Posten 181: Abgrenzung nach unten + Kommentar-Zustand
    [Test] procedure SequentialTry_NoFinding;
    [Test] procedure NestedTry_StillReported_Kontrolle;
    [Test] procedure NestedTryInMultiLineComment_NoFinding;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 181: die Zustandsmaschine hatte vier Tests ----------- }
//
// Der Detektor traegt eine eigene ~80-Zeilen-Scanner-Zustandsmaschine
// mit Tiefenzaehlung und zeilenuebergreifendem Kommentar-Zustand. Was
// fehlte, war die Abgrenzung nach unten: dass SEQUENTIELLE trys eben
// keine geschachtelten sind.
//
// Alle drei am gebauten Stand gemessen. Der Scanner ist NICHT von dem
// Zustandsleck betroffen, das in derselben Charge drei andere
// Detektoren getroffen hat - er sammelt Token und steigt am Treffer
// nicht aus. Der dritte Test nagelt das fest.

procedure TTestNestedTry.SequentialTry_NoFinding;
// DIE FEHLENDE ABGRENZUNG: zwei trys NACHEINANDER, nicht ineinander.
// Eine Tiefenzaehlung, die beim Schliessen nicht dekrementiert,
// wuerde hier melden. Gemessen: 0.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  try A; finally B; end;'#13#10+
  '  try C; finally D; end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkNestedTry),
      'zwei aufeinanderfolgende try-Bloecke sind nicht geschachtelt');
  finally F.Free; end;
end;

procedure TTestNestedTry.NestedTry_StillReported_Kontrolle;
// Die Positiv-Kontrolle direkt daneben - ohne sie waere der Test
// oben auch bei abgeschalteter Regel gruen. Gemessen: 1.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    try A; finally B; end;'#13#10+
  '  finally'#13#10+
  '    C;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkNestedTry),
      'ineinander geschachtelte trys bleiben ein Fund');
  finally F.Free; end;
end;

procedure TTestNestedTry.NestedTryInMultiLineComment_NoFinding;
// Der zeilenuebergreifende Kommentar-Zustand: die komplette
// Schachtelung steht in einem ueber vier Zeilen offenen {..}.
// Gemessen: 0.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  Beep;  {'#13#10+
  '    try'#13#10+
  '      try A; finally B; end;'#13#10+
  '    finally C; end;'#13#10+
  '  }'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkNestedTry),
      'die Schachtelung im Blockkommentar ist kein Code');
  finally F.Free; end;
end;


procedure TTestNestedTry.SingleTry_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try DoStuff; except Log; end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkNestedTry));
  finally F.Free; end;
end;

procedure TTestNestedTry.NestedTryExcept_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    try'#13#10 +
  '      DoInner;'#13#10 +
  '    except'#13#10 +
  '      LogInner;'#13#10 +
  '    end;'#13#10 +
  '  except'#13#10 +
  '    LogOuter;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkNestedTry) >= 1);
  finally F.Free; end;
end;

procedure TTestNestedTry.NestedTryFinally_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    try'#13#10 +
  '      DoStuff;'#13#10 +
  '    finally'#13#10 +
  '      CleanupA;'#13#10 +
  '    end;'#13#10 +
  '  finally'#13#10 +
  '    CleanupB;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkNestedTry) >= 1);
  finally F.Free; end;
end;

procedure TTestNestedTry.NestedTry_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  try try DoStuff; except Log; end; except Outer; end;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkNestedTry then
      begin
        Assert.AreEqual<TFindingKind>(fkNestedTry, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,     Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkNestedTry finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestNestedTry);

end.
