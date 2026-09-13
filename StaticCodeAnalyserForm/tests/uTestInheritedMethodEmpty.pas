unit uTestInheritedMethodEmpty;

// Tests fuer den TInheritedMethodEmptyDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestInheritedMethodEmpty = class
  public
    // ---- Positive Varianten ------------------------------------------------
    [Test] procedure BareInherited_Reported;
    [Test] procedure InheritedWithSameName_Reported;

    // ---- Negative Varianten / Guards --------------------------------------
    [Test] procedure InheritedPlusOtherStatement_NoFinding;
    [Test] procedure InheritedWithDifferentName_NoFinding;
    [Test] procedure NotOverride_NoFinding;
    [Test] procedure EmptyBody_NoFinding;
    [Test] procedure AbstractMethod_NoFinding;

    // ---- Finding-Inhalt ----------------------------------------------------
    [Test] procedure Finding_KindAndSeverity;
    // Voll-Review 2026-09-12 (Major 71): Argumentliste zaehlt
    [Test] procedure TransformedArgs_NotReported;
    [Test] procedure TransformedCallArg_NotReported;
    [Test] procedure ExactPassThrough_Reported;
    [Test] procedure ExactPassThroughConstParam_Reported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestInheritedMethodEmpty.BareInherited_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar; override;'#13#10 +
  'begin inherited; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInheritedMethodEmpty));
  finally F.Free; end;
end;

procedure TTestInheritedMethodEmpty.InheritedWithSameName_Reported;
// 'inherited Bar;' ist semantisch identisch zu 'inherited;' wenn die
// Methode den gleichen Namen hat - immer noch leer.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar; override;'#13#10 +
  'begin inherited Bar; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInheritedMethodEmpty));
  finally F.Free; end;
end;

procedure TTestInheritedMethodEmpty.InheritedPlusOtherStatement_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar; override;'#13#10 +
  'begin'#13#10 +
  '  inherited;'#13#10 +
  '  DoSomething;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInheritedMethodEmpty));
  finally F.Free; end;
end;

procedure TTestInheritedMethodEmpty.InheritedWithDifferentName_NoFinding;
// 'inherited OtherMethod;' ruft bewusst eine andere Parent-Methode auf -
// Method-Hijacking, legitim.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar; override;'#13#10 +
  'begin inherited Baz; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInheritedMethodEmpty));
  finally F.Free; end;
end;

procedure TTestInheritedMethodEmpty.NotOverride_NoFinding;
// Method ohne 'override'-Direktive - kein Pattern, kein Finding.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin inherited; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInheritedMethodEmpty));
  finally F.Free; end;
end;

procedure TTestInheritedMethodEmpty.EmptyBody_NoFinding;
// Leerer Body (kein inherited) wird von EmptyRoutineCheck gefangen,
// nicht von uns.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar; override;'#13#10 +
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInheritedMethodEmpty));
  finally F.Free; end;
end;

procedure TTestInheritedMethodEmpty.AbstractMethod_NoFinding;
// abstract = kein Body, kein Pattern.
const SRC =
  'unit t; interface'#13#10 +
  'type TFoo = class'#13#10 +
  '  procedure Bar; virtual; abstract;'#13#10 +
  'end;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInheritedMethodEmpty));
  finally F.Free; end;
end;

procedure TTestInheritedMethodEmpty.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar; override;'#13#10 +
  'begin inherited; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkInheritedMethodEmpty then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkInheritedMethodEmpty finding expected');
    Assert.AreEqual(fkInheritedMethodEmpty, Hit.Kind);
    Assert.AreEqual(lsHint,                 Hit.Severity);
  finally F.Free; end;
end;

procedure TTestInheritedMethodEmpty.TransformedArgs_NotReported;
// Voll-Review 2026-09-12 (Major 71): die Argumentliste wurde komplett
// ignoriert - `inherited Create(nil)` reparentet auf nil und ist KEIN
// Bypass; die Empfehlung 'remove the override entirely' wuerde das
// Verhalten aendern (Bestands-Exe: 1 FP, empirisch belegt).
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create(AOwner: TComponent); override;'#13#10 +
  'begin'#13#10 +
  '  inherited Create(nil);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInheritedMethodEmpty),
    'inherited Create(nil) reparentet - kein Bypass');
  finally F.Free; end;
end;

procedure TTestInheritedMethodEmpty.TransformedCallArg_NotReported;
// Geschwisterfall: das Argument wird durch einen Aufruf TRANSFORMIERT
// (Bestands-Exe: 1 FP auf dieser Fixture, empirisch belegt).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.SetName(const S: string); override;'#13#10 +
  'begin'#13#10 +
  '  inherited SetName(Trim(S));'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkInheritedMethodEmpty),
    'transformiertes Argument ist kein Bypass');
  finally F.Free; end;
end;

procedure TTestInheritedMethodEmpty.ExactPassThrough_Reported;
// Gegenrichtung: die EXAKTE 1:1-Durchreichung (gleiche Anzahl, gleiche
// Reihenfolge, pure Parameter-Namen) bleibt ein Bypass und wird weiter
// gemeldet - pinnt, dass Major 71 nicht ueberschiesst.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar(A, B: Integer); override;'#13#10 +
  'begin'#13#10 +
  '  inherited Bar(A, B);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInheritedMethodEmpty),
    '1:1-Durchreichung ist ein reiner Bypass');
  finally F.Free; end;
end;

procedure TTestInheritedMethodEmpty.ExactPassThroughConstParam_Reported;
// nkParam.Name traegt den Modifier als Praefix ('const S') - der
// Vergleich muss den Modifier abstreifen, sonst wuerde jede
// const-Signatur faelschlich als transformiert gelten (stiller Drop).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.SetTitle(const S: string); override;'#13#10 +
  'begin'#13#10 +
  '  inherited SetTitle(S);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkInheritedMethodEmpty),
    'Durchreichung eines const-Parameters ist ein reiner Bypass');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestInheritedMethodEmpty);

end.
