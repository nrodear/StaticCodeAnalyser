unit uTestReRaiseException;

// Tests fuer den TReRaiseExceptionDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestReRaiseException = class
  public
    // ---- Positive Varianten ------------------------------------------------
    [Test] procedure ReRaiseBoundVar_Reported;
    [Test] procedure ReRaiseBoundVar_CaseInsensitive_Reported;
    [Test] procedure MultipleOnHandlers_AllReported;

    // ---- Negative Varianten / Guards --------------------------------------
    [Test] procedure BareRaise_NoFinding;
    [Test] procedure RaiseDifferentVar_NoFinding;
    [Test] procedure RaiseWrappedException_NoFinding;
    [Test] procedure OnWithoutVar_NoFinding;
    [Test] procedure RaiseOutsideOnHandler_NoFinding;

    // ---- Finding-Inhalt ----------------------------------------------------
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestReRaiseException.ReRaiseBoundVar_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try DoStuff except on E: Exception do raise E; end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkReRaiseException));
  finally F.Free; end;
end;

procedure TTestReRaiseException.ReRaiseBoundVar_CaseInsensitive_Reported;
// Pascal ist case-insensitiv: 'e' und 'E' sind dieselbe Variable.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try DoStuff except on E: Exception do raise e; end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkReRaiseException));
  finally F.Free; end;
end;

procedure TTestReRaiseException.MultipleOnHandlers_AllReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try DoStuff'#13#10 +
  '  except'#13#10 +
  '    on E: EFoo do raise E;'#13#10 +
  '    on X: EBar do raise X;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkReRaiseException));
  finally F.Free; end;
end;

procedure TTestReRaiseException.BareRaise_NoFinding;
// `raise;` ohne Argument ist die korrekte Form.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try DoStuff except on E: Exception do raise; end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkReRaiseException));
  finally F.Free; end;
end;

procedure TTestReRaiseException.RaiseDifferentVar_NoFinding;
// raise auf andere Variable als gebunden -> kein klassisches Re-Raise-Muster.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Other: Exception;'#13#10 +
  'begin'#13#10 +
  '  try DoStuff except on E: Exception do raise Other; end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkReRaiseException));
  finally F.Free; end;
end;

procedure TTestReRaiseException.RaiseWrappedException_NoFinding;
// User wrappt mit neuer Exception - Intent klar, kein Re-Raise.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try DoStuff except'#13#10 +
  '    on E: Exception do raise EWrapper.Create(''wrapped: '' + E.Message);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkReRaiseException));
  finally F.Free; end;
end;

procedure TTestReRaiseException.OnWithoutVar_NoFinding;
// `on Exception do` ohne Bind-Var - kein Re-Raise moeglich.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  try DoStuff except on Exception do LogIt; end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkReRaiseException));
  finally F.Free; end;
end;

procedure TTestReRaiseException.RaiseOutsideOnHandler_NoFinding;
// Ein `raise E` ausserhalb eines on-Handlers ist eine normale
// Exception-Auslosung, kein Re-Raise. Hier: regulaerer raise-Pfad.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(E: Exception);'#13#10 +
  'begin raise E; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkReRaiseException));
  finally F.Free; end;
end;

procedure TTestReRaiseException.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin try DoStuff except on E: Exception do raise E; end; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkReRaiseException then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkReRaiseException finding expected');
    Assert.AreEqual(fkReRaiseException, Hit.Kind);
    Assert.AreEqual(lsWarning,          Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestReRaiseException);

end.
