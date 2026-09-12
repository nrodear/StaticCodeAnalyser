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
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

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

initialization
  TDUnitX.RegisterTestFixture(TTestTypeName);

end.
