unit uTestRaiseOutsideExcept;

// Tests fuer den TRaiseOutsideExceptDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRaiseOutsideExcept = class
  public
    // Positive: bare `raise;` ausserhalb except
    [Test] procedure BareRaise_TopLevel_Reported;
    [Test] procedure BareRaise_InsideIf_Reported;
    [Test] procedure BareRaise_InsideFinally_Reported;

    // Negative: bare `raise;` ist innerhalb except/on-handler korrekt
    [Test] procedure BareRaise_InsideExcept_NotReported;
    [Test] procedure BareRaise_InsideOnHandler_NotReported;
    [Test] procedure RaiseWithClass_NeverFlagged;

    // Finding-Inhalt
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestRaiseOutsideExcept.BareRaise_TopLevel_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin raise; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRaiseOutsideExcept));
  finally F.Free; end;
end;

procedure TTestRaiseOutsideExcept.BareRaise_InsideIf_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: Integer);'#13#10 +
  'begin if x < 0 then raise; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRaiseOutsideExcept));
  finally F.Free; end;
end;

procedure TTestRaiseOutsideExcept.BareRaise_InsideFinally_Reported;
// finally-Block ist KEIN except-Handler - bare raise dort ist genauso
// gefaehrlich wie auf Top-Level.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try Bar; finally raise; end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRaiseOutsideExcept));
  finally F.Free; end;
end;

procedure TTestRaiseOutsideExcept.BareRaise_InsideExcept_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try Bar; except Log(''oops''); raise; end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRaiseOutsideExcept));
  finally F.Free; end;
end;

procedure TTestRaiseOutsideExcept.BareRaise_InsideOnHandler_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try Bar; except on E: EConvertError do raise; end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRaiseOutsideExcept));
  finally F.Free; end;
end;

procedure TTestRaiseOutsideExcept.RaiseWithClass_NeverFlagged;
// `raise EFoo.Create(...)` ist immer korrekt - egal wo. Detector darf
// das nicht flaggen weil Name != 'raise'.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: Integer);'#13#10 +
  'begin'#13#10 +
  '  if x < 0 then raise EArgumentException.Create(''neg'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRaiseOutsideExcept));
  finally F.Free; end;
end;

procedure TTestRaiseOutsideExcept.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo; begin raise; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkRaiseOutsideExcept then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkRaiseOutsideExcept finding expected');
    Assert.AreEqual(fkRaiseOutsideExcept, Hit.Kind);
    Assert.AreEqual(lsError,              Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRaiseOutsideExcept);

end.
