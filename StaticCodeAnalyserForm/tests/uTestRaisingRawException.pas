unit uTestRaisingRawException;

// Tests fuer den TRaisingRawExceptionDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRaisingRawException = class
  public
    [Test] procedure RaiseExceptionCreate_Reported;
    [Test] procedure RaiseExceptionCreateWithMessage_Reported;

    [Test] procedure RaiseSubclass_NoFinding;
    [Test] procedure BareRaise_NoFinding;
    [Test] procedure RaiseVariable_NoFinding;

    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestRaisingRawException.RaiseExceptionCreate_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin raise Exception.Create(''oops''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRaisingRawException));
  finally F.Free; end;
end;

procedure TTestRaisingRawException.RaiseExceptionCreateWithMessage_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(x: Integer);'#13#10 +
  'begin raise Exception.CreateFmt(''bad: %d'', [x]); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  // CreateFmt sollte auch matchen weil 'exception.create' Praefix-Match ist.
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkRaisingRawException));
  finally F.Free; end;
end;

procedure TTestRaisingRawException.RaiseSubclass_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin raise EArgumentException.Create(''bad''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRaisingRawException));
  finally F.Free; end;
end;

procedure TTestRaisingRawException.BareRaise_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin try DoStuff except raise; end; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRaisingRawException));
  finally F.Free; end;
end;

procedure TTestRaisingRawException.RaiseVariable_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(E: Exception);'#13#10 +
  'begin raise E; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRaisingRawException));
  finally F.Free; end;
end;

procedure TTestRaisingRawException.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin raise Exception.Create(''oops''); end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkRaisingRawException then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkRaisingRawException finding expected');
    Assert.AreEqual(fkRaisingRawException, Hit.Kind);
    Assert.AreEqual(lsWarning,             Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRaisingRawException);

end.
