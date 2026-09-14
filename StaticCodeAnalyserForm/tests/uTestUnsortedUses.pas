unit uTestUnsortedUses;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUnsortedUses = class
  public
    [Test] procedure UnsortedUses_Reported;
    [Test] procedure SortedUses_NotReported;
    [Test] procedure SingleEntry_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // Posten 213: die implementation-uses als zweiter nkUses-Knoten
    [Test] procedure UnsortedImplementationUses_Reported;
    [Test] procedure BothUsesClausesUnsorted_TwoFindings;
    [Test] procedure BothUsesClausesSorted_NoFinding;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

{ --- Posten 213: die zweite uses-Klausel ------------------------- }
//
// Alle vier Bestandstests fahren die INTERFACE-uses. Der Detektor
// meldet aber je Klausel einen eigenen Fund, und der zweite
// nkUses-Knoten - die implementation-Klausel - war nie angefasst.
//
// Alle drei am gebauten Stand gemessen.

procedure TTestUnsortedUses.UnsortedImplementationUses_Reported;
// Die interface-Klausel ist SORTIERT, die implementation-Klausel
// nicht. Gemessen: 1 - der Fund kommt also wirklich aus dem zweiten
// Knoten und nicht aus dem ersten.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'uses A1, B1, C1;'#13#10+
  'implementation'#13#10+
  'uses Zeta, Alpha;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1,
      TFindingHelper.Count(F, fkUnsortedUses),
      'auch die implementation-uses wird geprueft');
  finally F.Free; end;
end;

procedure TTestUnsortedUses.BothUsesClausesUnsorted_TwoFindings;
// BEIDE Klauseln unsortiert. Gemessen: 2 - je Klausel ein Fund.
// Belegt die Zusage "eigener Fund je Klausel"; ein Detektor, der
// nach dem ersten Treffer aufhoert, liefert hier 1.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'uses Zulu, Alpha;'#13#10+
  'implementation'#13#10+
  'uses Zeta, Alpha;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(2,
      TFindingHelper.Count(F, fkUnsortedUses),
      'jede unsortierte Klausel ist ein eigener Fund');
  finally F.Free; end;
end;

procedure TTestUnsortedUses.BothUsesClausesSorted_NoFinding;
// Die Gegenprobe: beide sortiert. Gemessen: 0.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'uses A1, B1, C1;'#13#10+
  'implementation'#13#10+
  'uses Alpha, Zeta;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0,
      TFindingHelper.Count(F, fkUnsortedUses),
      'sortierte Klauseln bleiben still');
  finally F.Free; end;
end;


procedure TTestUnsortedUses.UnsortedUses_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'uses System.SysUtils, System.Classes, System.IOUtils;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUnsortedUses) >= 1);
  finally F.Free; end;
end;

procedure TTestUnsortedUses.SortedUses_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'uses System.Classes, System.IOUtils, System.SysUtils;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnsortedUses));
  finally F.Free; end;
end;

procedure TTestUnsortedUses.SingleEntry_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'uses System.SysUtils;'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnsortedUses));
  finally F.Free; end;
end;

procedure TTestUnsortedUses.Finding_KindAndSeverity;
const SRC =
  'unit t; interface'#13#10 +
  'uses System.SysUtils, System.Classes;'#13#10 +
  'implementation end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkUnsortedUses then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkUnsortedUses finding expected');
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnsortedUses);

end.
