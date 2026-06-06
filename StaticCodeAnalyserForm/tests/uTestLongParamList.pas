unit uTestLongParamList;

// Tests fuer TLongParamListDetector. Schwellwert (Default 5 Parameter)
// kommt aus FRepoSettings.LongParamListMaxParams.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestLongParamList = class
  public
    [Test] procedure FewParams_NoFinding;
    [Test] procedure ManyParams_Reported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestLongParamList.FewParams_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(A, B: Integer); begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkLongParamList));
  finally F.Free; end;
end;

procedure TTestLongParamList.ManyParams_Reported;
// 8 Parameter weit ueber dem Default-Schwellwert (5).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(A, B, C, D, E, F, G, H: Integer); begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLongParamList) >= 1);
  finally F.Free; end;
end;

procedure TTestLongParamList.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(A, B, C, D, E, F, G, H: Integer); begin end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkLongParamList then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkLongParamList finding expected');
    Assert.AreEqual(fkLongParamList, Hit.Kind);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLongParamList);

end.
