unit uTestMethodName;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMethodName = class
  public
    [Test] procedure PascalCase_NoFinding;
    [Test] procedure LowerCamel_Reported;
    [Test] procedure QualifiedName_Reported;
    [Test] procedure UnderscorePrefix_NotReported;
    [Test] procedure MethodName_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestMethodName.PascalCase_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure DoStuff; begin end;'#13#10 +
  'function GetX: Integer; begin Result := 0; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMethodName));
  finally F.Free; end;
end;

procedure TTestMethodName.LowerCamel_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure doStuff; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkMethodName));
  finally F.Free; end;
end;

procedure TTestMethodName.QualifiedName_Reported;
// `TFoo.doStuff` - der Teil nach dem Punkt zaehlt.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.doStuff; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkMethodName));
  finally F.Free; end;
end;

procedure TTestMethodName.UnderscorePrefix_NotReported;
// `_Magic` ist ausgenommen (RTL-Konvention fuer Reserved-Magic).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure _MagicCallback; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMethodName));
  finally F.Free; end;
end;

procedure TTestMethodName.MethodName_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure doStuff; begin end;';
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
begin
  Findings := TFindingHelper.FindingsOfFile(SRC);
  try
    for Fnd in Findings do
      if Fnd.Kind = fkMethodName then
      begin
        Assert.AreEqual<TFindingKind>(fkMethodName, Fnd.Kind);
        Assert.AreEqual<TLeakSeverity>(lsHint,      Fnd.Severity);
        Exit;
      end;
    Assert.Fail('expected fkMethodName finding');
  finally Findings.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMethodName);

end.
