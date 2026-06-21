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
    [Test] procedure FieldViaMethodCall_NotReported;
    [Test] procedure LowercaseFieldAccess_NotReported;
    [Test] procedure AlreadyClassMethod_NotReported;
    [Test] procedure VirtualMethod_NotReported;
    [Test] procedure VirtualMethodWithSpaceBeforeDirective_NotReported;
    [Test] procedure ProcedureNoSelfAccess_SuggestsClassProcedure;
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeClassMethod));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeClassMethod));
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.FieldViaMethodCall_NotReported;
// FP-Fix (Real-World 2026-06-21): Feldzugriff via Methode/Property/Index
// (`FList.Add(...)`) wird vom Parser als EIN Node-Name abgelegt - das
// fuehrende Segment 'FList' ist trotzdem ein Feld -> kein class method.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  FList.Add(1);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeClassMethod),
    'Feldzugriff via Methode (FList.Add) ist Instance-State - kein Finding');
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.LowercaseFieldAccess_NotReported;
// FP-Fix (Real-World 2026-06-21): lowercase-f-Feldkonvention (Alcinoe
// fOwner/fUpdateSQL) - 'f' + Grossbuchstabe ist ebenfalls ein Feld.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  fOwner.Update;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeClassMethod),
    'lowercase-f-Feld (fOwner) ist Instance-State - kein Finding');
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeClassMethod));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeClassMethod));
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.VirtualMethodWithSpaceBeforeDirective_NotReported;
// FP-Fix doublecmd CharDistribution.pas: 'procedure Reset; virtual;'
// (mit Space vor 'virtual'). Pos(';virtual', ...) im alten Pattern
// matched nicht weil dort ';virtual' ohne Space gesucht wurde.
// Real-Pattern: 'procedure ; virtual' im TypeRef (Parser-Output mit
// Space-Normalisierung).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'type'#13#10 +
  '  TFoo = class'#13#10 +
  '    procedure Reset; virtual;'#13#10 +     // Space vor virtual
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TFoo.Reset;'#13#10 +
  'begin'#13#10 +
  '  // nothing'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeClassMethod),
      'virtual mit Space davor MUSS als polymorph erkannt werden');
  finally F.Free; end;
end;

procedure TTestCanBeClassMethod.ProcedureNoSelfAccess_SuggestsClassProcedure;
// FP-Fix doublecmd CharDistribution.pas: bei procedure (statt function)
// wurde 'could be declared as `class function`' empfohlen - syntaktisch
// falsch. Sollte 'class procedure' sein.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TUtil.DoIt(X: Integer);'#13#10 +
  'begin'#13#10 +
  '  WriteLn(X);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
    Fnd : TLeakFinding;
    Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkCanBeClassMethod then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkCanBeClassMethod finding expected for procedure');
    Assert.IsTrue(Pos('class procedure', Hit.MissingVar) > 0,
      'Procedure-Empfehlung muss "class procedure" enthalten, nicht "class function"');
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCanBeClassMethod));
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
