unit uTestBooleanPropertyNaming;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestBooleanPropertyNaming = class
  public
    [Test] procedure NounBooleanProperty_Reported;
    [Test] procedure IsPrefixedProperty_NotReported;
    [Test] procedure HasPrefixedProperty_NotReported;
    [Test] procedure EstablishedName_Enabled_NotReported;
    [Test] procedure NonBooleanProperty_NotReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestBooleanPropertyNaming.NounBooleanProperty_Reported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    property Ready: Boolean read FReady;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkBooleanPropertyNaming) >= 1,
      'property Ready: Boolean muss gemeldet werden (IsReady besser)');
  finally F.Free; end;
end;

procedure TTestBooleanPropertyNaming.IsPrefixedProperty_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    property IsReady: Boolean read FReady;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBooleanPropertyNaming),
      'IsReady ist konform');
  finally F.Free; end;
end;

procedure TTestBooleanPropertyNaming.HasPrefixedProperty_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    property HasItems: Boolean read FHasItems;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBooleanPropertyNaming),
      'HasItems ist konform');
  finally F.Free; end;
end;

procedure TTestBooleanPropertyNaming.EstablishedName_Enabled_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    property Enabled: Boolean read FEnabled;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBooleanPropertyNaming),
      'Enabled ist etablierte VCL-Konvention - Whitelist');
  finally F.Free; end;
end;

procedure TTestBooleanPropertyNaming.NonBooleanProperty_NotReported;
const SRC =
  'unit t; interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '  public'#13#10 +
  '    property Count: Integer read FCount;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkBooleanPropertyNaming),
      'Integer-Property ist nicht Scope dieses Detektors');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestBooleanPropertyNaming);

end.
