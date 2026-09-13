unit uTestTypeName;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestTypeName = class
  public
    [Test] procedure TPrefix_NoFinding;
    [Test] procedure NoTPrefixClass_Reported;
    [Test] procedure NoTPrefixRecord_Reported;
    [Test] procedure ForwardDecl_Reported;
    [Test] procedure ClassOfReference_NotReported;
    [Test] procedure NonClassType_NoFinding;
    [Test] procedure TypeName_KindAndSeverity;
    // Voll-Review 2026-09-12 (Major 84): RXxx ist laut Unit-Kopf eine
    // gueltige RECORD-Konvention
    [Test] procedure RPrefixRecord_NoFinding;
    [Test] procedure RPrefixClass_StillReported;
    [Test] procedure CPortRecord_StillReported;
    // Voll-Review 2026-09-12 (Testluecke 116): die Suppressions
    [Test] procedure EPrefixException_NoFinding;
    [Test] procedure ErrorSuffix_NoFinding;
    [Test] procedure ExceptionSuffix_NoFinding;
    [Test] procedure GenericClassDecl_Reported;
    // Posten 278: die fehlende CamelCase-Grenze ist Absicht
    [Test] procedure VendorPrefixCamelCase_NoFinding;
    [Test] procedure NoTPrefix_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 278: der T-Zweig bleibt bewusst ohne CamelCase-Grenze }
//
// Der T-Zweig prueft nur das erste Zeichen. Die E-Heuristik und
// IstRKonventionsRecord verlangen zusaetzlich einen Grossbuchstaben an
// Position 2 - der T-Zweig ist der einzige ohne diese Grenze, und der
// Kopfkommentar sagte dazu nichts.
//
// Die Laxheit BLEIBT. Am Korpus gemessen wuerde die Grenze 1.401
// zusaetzliche Hints erzeugen; 1.344 davon treffen das verbreitete
// Idiom 'T' + Vendor-/Formularpraefix (TfrmMain 78x, TdmMain 13x), und
// der Meldetext "rename to start with T" waere fuer jeden von ihnen
// selbstwidersprechend.
//
// Dieser Test haelt die Entscheidung fest - er wird rot, sobald jemand
// die Grenze doch einbaut. An der gebauten Exe gemessen: 0 Funde fuer
// die Vendor-Praefixe, 1 fuer den echten Verstoss.

procedure TTestTypeName.VendorPrefixCamelCase_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TfrmMain = class'#13#10 +
  '  end;'#13#10 +
  '  TdmMain = class'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTypeName),
      'T plus Vendor-Praefix ist gaengiges Delphi und bleibt still');
  finally F.Free; end;
end;

procedure TTestTypeName.NoTPrefix_StillReported;
// Die Positiv-Kontrolle daneben - ohne sie waere der Test oben auch bei
// einer komplett abgeschalteten Regel gruen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  MyThing = class'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTypeName),
      'ein Klassenname ohne T bleibt ein Fund');
  finally F.Free; end;
end;


procedure TTestTypeName.TPrefix_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class end;'#13#10 +
  '  TBar = record FX: Integer; end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTypeName));
  finally F.Free; end;
end;

procedure TTestTypeName.NoTPrefixClass_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type Counter = class end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTypeName));
  finally F.Free; end;
end;

procedure TTestTypeName.NoTPrefixRecord_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type MyData = record FX: Integer; end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTypeName));
  finally F.Free; end;
end;

procedure TTestTypeName.ForwardDecl_Reported;
// Forward `Foo = class;` (ohne body) ist auch ein Treffer - der Name
// startet nicht mit T.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  Foo = class;'#13#10 +
  '  Foo = class FX: Integer; end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkTypeName) >= 1);
  finally F.Free; end;
end;

procedure TTestTypeName.ClassOfReference_NotReported;
// `Foo = class of TBar` ist KEINE eigene Klasse, sondern eine Reference.
// Wird NICHT gemeldet.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type Foo = class of TBar;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTypeName));
  finally F.Free; end;
end;

procedure TTestTypeName.NonClassType_NoFinding;
// Andere Typen (array, integer alias) sind nicht im Scope.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  MyInt = Integer;'#13#10 +
  '  MyArray = array of Integer;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTypeName));
  finally F.Free; end;
end;

procedure TTestTypeName.TypeName_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type Counter = class end;'#13#10 +
  'implementation end.';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkTypeName then
      begin
        Assert.AreEqual<TFindingKind>(fkTypeName, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,    Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkTypeName finding');
  finally Findings.Free; end;
end;

procedure TTestTypeName.RPrefixRecord_NoFinding;
// Voll-Review 2026-09-12 (Major 84): der Unit-Kopf nennt 'RPoint'
// woertlich als konformes Record - der Code meldete es trotzdem
// (Bestands-Exe: 1 Fund auf genau diesem Namen, empirisch belegt).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type RPoint = record X, Y: Double; end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTypeName),
    'RXxx ist die dokumentierte Record-Konvention');
  finally F.Free; end;
end;

procedure TTestTypeName.RPrefixClass_StillReported;
// Gegenrichtung 1: R ist eine RECORD-Konvention. Fuer Klassen bleibt
// T verbindlich - die Ausnahme darf nicht auf 'class' durchschlagen.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type RList = class end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTypeName),
    'fuer Klassen gilt weiterhin T');
  finally F.Free; end;
end;

procedure TTestTypeName.CPortRecord_StillReported;
// Gegenrichtung 2: uebernommene C-Strukturen sind keine Records mit
// R-Konvention. Am Korpus sind das 23 der 25 Namen mit
// 'R'+Grossbuchstabe (RC4_KEY, REPARSE_DATA_BUFFER, RAND_METHOD, ...);
// sie tragen '_' bzw. keinen Kleinbuchstaben und bleiben gemeldet.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type RC4_KEY = record Data: Integer; end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTypeName),
    'C-Port-Struktur folgt keiner Delphi-Konvention');
  finally F.Free; end;
end;

procedure TTestTypeName.EPrefixException_NoFinding;
// Testluecke 116 (Voll-Review 2026-09-12): die E-Praefix-Suppression
// ('E' + Grossbuchstabe) war ungetestet - dabei ist sie der Grund,
// warum SCA151 nicht ueber jeder Exception-Klasse feuert (an der
// Bestands-Exe verifiziert: kein Fund).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type EMyError = class(Exception) end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTypeName),
    'E + Grossbuchstabe ist die Exception-Konvention');
  finally F.Free; end;
end;

procedure TTestTypeName.ErrorSuffix_NoFinding;
// Zweiter Suppressions-Zweig: Name endet auf 'Error' - greift auch
// ohne E-Praefix (Bestands-Exe: kein Fund).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type MyParseError = class(Exception) end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTypeName),
    'Error-Suffix zaehlt als Exception-Konvention');
  finally F.Free; end;
end;

procedure TTestTypeName.ExceptionSuffix_NoFinding;
// Dritter Zweig: Name endet auf 'Exception' (Bestands-Exe: kein Fund).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type SomeException = class(Exception) end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkTypeName),
    'Exception-Suffix zaehlt als Exception-Konvention');
  finally F.Free; end;
end;

procedure TTestTypeName.GenericClassDecl_Reported;
// Gegenrichtung zu den drei Suppressions: eine generische Deklaration
// ohne T-Praefix bleibt ein Fund - die Suppressions duerfen nicht
// versehentlich alles durchlassen, was ungewoehnlich aussieht
// (Bestands-Exe: 1 Fund auf 'Foo').
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type Foo<T> = class end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkTypeName),
    'generische Klasse ohne T-Praefix bleibt ein Fund');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestTypeName);

end.
