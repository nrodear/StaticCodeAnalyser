unit uTestEmptyOnHandler;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEmptyOnHandler = class
  public
    [Test] procedure OnHandlerWithSemicolon_Reported;
    [Test] procedure OnHandlerWithEmptyBeginEnd_Reported;
    [Test] procedure OnHandlerWithBody_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestEmptyOnHandler.OnHandlerWithSemicolon_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoStuff;'#13#10 +
  '  except'#13#10 +
  '    on E: EDatabaseError do ;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkEmptyOnHandler) >= 1);
  finally F.Free; end;
end;

procedure TTestEmptyOnHandler.OnHandlerWithEmptyBeginEnd_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoStuff;'#13#10 +
  '  except'#13#10 +
  '    on E: EFileNotFound do'#13#10 +
  '    begin'#13#10 +
  '    end;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkEmptyOnHandler) >= 1);
  finally F.Free; end;
end;

procedure TTestEmptyOnHandler.OnHandlerWithBody_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try'#13#10 +
  '    DoStuff;'#13#10 +
  '  except'#13#10 +
  '    on E: EDatabaseError do'#13#10 +
  '      Logger.Error(E.Message);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkEmptyOnHandler));
  finally F.Free; end;
end;

procedure TTestEmptyOnHandler.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try DoStuff; except on E: EX do ; end;'#13#10 +
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
      if Fnd.Kind = fkEmptyOnHandler then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkEmptyOnHandler finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEmptyOnHandler);

end.
