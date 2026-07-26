unit uTestEmptyInterface;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEmptyInterface = class
  public
    [Test] procedure InterfaceWithMethods_NoFinding;
    [Test] procedure EmptyInterfaceMultiline_Reported;
    [Test] procedure EmptyInterfaceWithParent_Reported;
    [Test] procedure EmptyInterfaceWithGuid_Reported;
    [Test] procedure UnitInterfaceSection_NotReported;
    [Test] procedure EmptyInterface_KindAndSeverity;
    // --- Restschulden-Audit 2026-07-26: Strip-Zentralisierung ---
    // Der Detektor lief bis dahin auf einer gedrifteten lokalen Kopie
    // (StripCommentsFile) statt auf TDetectorUtils.
    // StripFileCommentsKeepStringsCached. Einzige beobachtbare Kante der
    // Kopie: eine Zeile, die KOMPLETT in einem mehrzeiligen
    // `{..}`/`(*..*)`-Block liegt (lokal: zusaetzliches Leerzeichen,
    // zentral: nichts). Beide Tests halten Fund UND Fundzeile fest.
    [Test] procedure EmptyInterfaceMultilineComment_Reported;
    [Test] procedure MultilineCommentInterfaceWithMethod_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestEmptyInterface.InterfaceWithMethods_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type IFoo = interface'#13#10 +
  '  procedure Bar;'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyInterface));
  finally F.Free; end;
end;

procedure TTestEmptyInterface.EmptyInterfaceMultiline_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type IMarker = interface'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyInterface));
  finally F.Free; end;
end;

procedure TTestEmptyInterface.EmptyInterfaceWithParent_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type IService = interface(IUnknown) end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyInterface));
  finally F.Free; end;
end;

procedure TTestEmptyInterface.EmptyInterfaceWithGuid_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type IMarker = interface'#13#10 +
  '  [''{12345678-1234-1234-1234-123456789012}'']'#13#10 +
  'end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyInterface));
  finally F.Free; end;
end;

procedure TTestEmptyInterface.UnitInterfaceSection_NotReported;
// Das Unit-Section-`interface` (vor `implementation`) darf NICHT als
// EmptyInterface gemeldet werden - es hat kein `=` davor.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyInterface));
  finally F.Free; end;
end;

procedure TTestEmptyInterface.EmptyInterface_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type IMarker = interface end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkEmptyInterface then
      begin
        Assert.AreEqual<TFindingKind>(fkEmptyInterface, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,          Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkEmptyInterface finding');
  finally F.Free; end;
end;

procedure TTestEmptyInterface.EmptyInterfaceMultilineComment_Reported;
// FIX-TEST zur Strip-Zentralisierung (Restschulden-Audit 2026-07-26).
// Zwei DREIzeilige Blockkommentare - je die MITTLERE Zeile liegt komplett
// im Kommentar und trifft damit genau den Zweig, in dem die geloeschte
// lokale Kopie ein Extra-Leerzeichen ausgab:
//   * der erste Block liegt VOR dem Interface -> verschiebt alle
//     Folgepositionen und damit die LineFor-Map (Fundzeile muss stimmen),
//   * der zweite liegt IM Rumpf -> landet im Leer-Test zwischen
//     `interface` und `end` (Rumpf muss weiterhin als leer gelten).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  { Doku-Kommentar'#13#10 +
  '    ueber drei'#13#10 +
  '    Zeilen }'#13#10 +
  '  IMarker = interface'#13#10 +
  '    { auch im Rumpf'#13#10 +
  '      ueber mehrere'#13#10 +
  '      Zeilen }'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkEmptyInterface),
      'Rumpf aus reinem Blockkommentar ist leer - genau 1 Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'IMarker = interface'),
      TFindingHelper.FirstOf(F, fkEmptyInterface).LineNumber,
      'Fundzeile muss trotz vorangehendem Mehrzeilen-Kommentar stimmen');
  finally F.Free; end;
end;

procedure TTestEmptyInterface.MultilineCommentInterfaceWithMethod_NotReported;
// GEGENPROBE: identisches Kommentar-Layout, aber der Rumpf enthaelt einen
// echten Vertrag. Haette der Strip Kommentar-Inhalt stehen lassen oder die
// Methodenzeile mit-verschluckt, waere hier ein FP (bzw. bei der
// Fix-Variante ein FN) sichtbar.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  { Doku-Kommentar'#13#10 +
  '    ueber drei'#13#10 +
  '    Zeilen }'#13#10 +
  '  IMarker = interface'#13#10 +
  '    { auch im Rumpf'#13#10 +
  '      ueber mehrere'#13#10 +
  '      Zeilen }'#13#10 +
  '    procedure Bar;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyInterface),
    'Interface mit Methode ist nicht leer - kein Fund erlaubt');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEmptyInterface);

end.
