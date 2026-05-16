unit uTestUnitLevelKeywordIndent;

// Tests fuer TUnitLevelKeywordIndentDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUnitLevelKeywordIndent = class
  public
    [Test] procedure FlushLeftKeywords_NoFinding;
    [Test] procedure IndentedImplementation_Reported;
    [Test] procedure IndentedInitialization_Reported;
    [Test] procedure IndentedInterface_AloneOnLine_Reported;
    [Test] procedure InterfaceInTypeDecl_NotReported;
    [Test] procedure UnitLevelKeywordIndent_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestUnitLevelKeywordIndent.FlushLeftKeywords_NoFinding;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses System.SysUtils;'#13#10 +
  'implementation'#13#10 +
  'procedure Foo; begin end;'#13#10 +
  'initialization'#13#10 +
  '  Foo;'#13#10 +
  'finalization'#13#10 +
  '  Foo;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkUnitLevelKeywordIndent));
  finally F.Free; end;
end;

procedure TTestUnitLevelKeywordIndent.IndentedImplementation_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  '  implementation'#13#10 +
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkUnitLevelKeywordIndent));
  finally F.Free; end;
end;

procedure TTestUnitLevelKeywordIndent.IndentedInitialization_Reported;
const SRC =
  'unit t;'#13#10 +
  'implementation'#13#10 +
  '  initialization'#13#10 +
  '  Foo;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkUnitLevelKeywordIndent));
  finally F.Free; end;
end;

procedure TTestUnitLevelKeywordIndent.IndentedInterface_AloneOnLine_Reported;
const SRC =
  'unit t;'#13#10 +
  '  interface'#13#10 +
  'uses x;'#13#10 +
  'implementation';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkUnitLevelKeywordIndent));
  finally F.Free; end;
end;

procedure TTestUnitLevelKeywordIndent.InterfaceInTypeDecl_NotReported;
// `interface` als Typ-Konstrukt darf eingerueckt sein - es ist NICHT
// Unit-Section. Test: das Wort `interface` ist nicht das einzige auf
// der Zeile (RestEmpty = False), daher kein Treffer.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  IMyService = interface(IUnknown)'#13#10 +
  '    procedure DoStuff;'#13#10 +
  '  end;'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkUnitLevelKeywordIndent));
  finally F.Free; end;
end;

procedure TTestUnitLevelKeywordIndent.UnitLevelKeywordIndent_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  '   implementation'#13#10 +
  'procedure Foo; begin end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in F do
      if Fnd.Kind = fkUnitLevelKeywordIndent then
      begin
        Assert.AreEqual<TFindingKind>(fkUnitLevelKeywordIndent, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,                  Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkUnitLevelKeywordIndent finding');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUnitLevelKeywordIndent);

end.
