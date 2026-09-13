unit uTestFreeAndNilHint;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFreeAndNilHint = class
  public
    [Test] procedure FreeAlone_NoFinding;
    [Test] procedure FreeAndNilOnNextLine_Reported;
    [Test] procedure DifferentReceiver_NoFinding;
    // Voll-Review 2026-09-12 (Blocker): kein Blockkommentar-Tracking.
    [Test] procedure PatternInsideBlockComment_NoFinding;
    [Test] procedure FreeAndNilHint_KindAndSeverity;
    // Posten 202: Kommentar, Einzeiler, Feld und Self
    [Test] procedure FreeAndNilInMultiLineComment_NoFinding;
    [Test] procedure FreeAndNilOnSameLine_NoFinding_KnownLimit;
    [Test] procedure FreeAndNilOnField_Reported;
    [Test] procedure FreeAndNilOnSelfQualifiedField_NoFinding_KnownLimit;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 202: die vier ungepinnten Grenzen ------------------- }
//
// Der Detektor hatte vier Tests. Was fehlte, waren genau die Faelle,
// an denen sein Vertrag haengt. Alle vier hier am gebauten Stand
// gemessen und festgenagelt - keiner aendert Verhalten.

procedure TTestFreeAndNilHint.FreeAndNilInMultiLineComment_NoFinding;
// Das Muster steht KOMPLETT in einem ueber drei Zeilen offenen
// Blockkommentar. Gemessen: 0 Funde. Pinnt den Kommentar-Schutz -
// in derselben Charge hat genau dieser Zustand drei andere
// Detektoren FP produzieren lassen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+'var L: TObject;'#13#10+
  'begin'#13#10+
  '  Beep;  {'#13#10+
  '  L.Free;'#13#10+
  '  L := nil;'#13#10+
  '  }'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkFreeAndNilHint),
      'das Muster im Blockkommentar ist kein Code');
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.FreeAndNilOnSameLine_NoFinding_KnownLimit;
// DOKUMENTIERTE GRENZE: der Kopfvertrag verlangt "zwei
// aufeinanderfolgende Statements auf BENACHBARTEN ZEILEN". Auf EINER
// Zeile meldet der Detektor bewusst nicht. Gemessen: 0.
// Der Test haelt die Grenze fest, damit sie nicht als Luecke
// wiederentdeckt wird.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+'var L: TObject;'#13#10+
  'begin'#13#10+
  '  L.Free; L := nil;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkFreeAndNilHint),
      'BEKANNTE GRENZE: das Muster auf EINER Zeile wird nicht gemeldet');
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.FreeAndNilOnField_Reported;
// Feld statt Lokaler - gemessen: 1 Fund. Der haeufigste reale Fall
// (Destruktoren) und bisher ohne Test.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  FObj.Free;'#13#10+
  '  FObj := nil;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkFreeAndNilHint),
      'auch auf einem Feld ist das Muster ein Fund');
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.FreeAndNilOnSelfQualifiedField_NoFinding_KnownLimit;
// GRENZE, hier erstmals belegt: mit Self-Qualifizierung meldet der
// Detektor NICHT (gemessen: 0), waehrend die unqualifizierte Form
// darueber 1 liefert. Der Kopfvertrag spricht von "gleicher
// Identifier X" und sagt zur Qualifizierung nichts.
//
// BEWUSST NICHT MITGEFIXT: das waere fundbewegend und braucht einen
// eigenen Bewegungsvertrag. Der Test pinnt das IST-Verhalten, damit
// die Luecke sichtbar bleibt statt unbemerkt.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  Self.FObj.Free;'#13#10+
  '  Self.FObj := nil;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkFreeAndNilHint),
      'BEKANNTE GRENZE: Self-qualifiziert wird nicht erkannt');
  finally F.Free; end;
end;


procedure TTestFreeAndNilHint.FreeAlone_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  Obj.Free;'#13#10 +
  '  DoStuff;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeAndNilHint));
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.FreeAndNilOnNextLine_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  Obj.Free;'#13#10 +
  '  Obj := nil;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkFreeAndNilHint));
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.DifferentReceiver_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  A.Free;'#13#10 +
  '  B := nil;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkFreeAndNilHint));
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.PatternInsideBlockComment_NoFinding;
// Mehrzeilig auskommentierter Alt-Code lieferte vor dem Fix einen
// Fund - der Roh-Scan kannte keinen Blockkommentar-Zustand
// (Projekt-Invariante: Kommentare zaehlen NIE als Code-Use).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  { Alte Version:'#13#10 +
  '  FConn.Free;'#13#10 +
  '  FConn := nil;'#13#10 +
  '  }'#13#10 +
  '  DoNew;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0,
    TFindingHelper.Count(F, fkFreeAndNilHint),
    'auskommentierter Alt-Code darf keinen FreeAndNil-Hinweis melden');
  finally F.Free; end;
end;

procedure TTestFreeAndNilHint.FreeAndNilHint_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  '  Obj.Free;'#13#10 +
  '  Obj := nil;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkFreeAndNilHint then
      begin
        Assert.AreEqual<TFindingKind>(fkFreeAndNilHint, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,          Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkFreeAndNilHint finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFreeAndNilHint);

end.
