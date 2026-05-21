unit uTestCanBeClassMethod;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCanBeClassMethod = class
  public
    [Test] procedure NoSelfAccess_Reported;
    [Test] procedure SelfAccess_NotReported;
    [Test] procedure FieldAccess_NotReported;
    [Test] procedure AlreadyClassMethod_NotReported;
    [Test] procedure VirtualMethod_NotReported;
    [Test] procedure Constructor_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestCanBeClassMethod.NoSelfAccess_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'function TMath.Add(A, B: Integer): Integer;'#13#10 +
  'begin'#13#10 +
  '  Result := A + B;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkCanBeClassMethod) >= 1);
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.SelfAccess_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  Self.Update;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkCanBeClassMethod));
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.FieldAccess_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  FCounter := FCounter + 1;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkCanBeClassMethod));
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.AlreadyClassMethod_NotReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TMath = class'#13#10 +
  '    class function Add(A, B: Integer): Integer; static;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'class function TMath.Add(A, B: Integer): Integer;'#13#10 +
  'begin Result := A + B; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkCanBeClassMethod));
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.VirtualMethod_NotReported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    function Bar(A, B: Integer): Integer; virtual;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'function TFoo.Bar(A, B: Integer): Integer;'#13#10 +
  'begin Result := A + B; end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkCanBeClassMethod));
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.Constructor_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'constructor TFoo.Create;'#13#10 +
  'begin'#13#10 +
  '  // Konstruktor ohne Field-Access - trotzdem nicht class-methodisierbar'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkCanBeClassMethod));
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'function TMath.Add(A, B: Integer): Integer;'#13#10 +
  'begin'#13#10 +
  '  Result := A + B;'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkCanBeClassMethod then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkCanBeClassMethod finding expected');
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCanBeClassMethod);

end.
