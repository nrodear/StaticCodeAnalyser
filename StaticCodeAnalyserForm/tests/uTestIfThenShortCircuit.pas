unit uTestIfThenShortCircuit;

// Tests fuer den TIfThenShortCircuitDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestIfThenShortCircuit = class
  public
    [Test] procedure BareIfThenWithCalls_Reported;
    [Test] procedure MathIfThenWithCalls_Reported;
    [Test] procedure StrUtilsIfThenWithCalls_Reported;
    [Test] procedure CaseInsensitive_Reported;

    [Test] procedure IfThenWithLiterals_NoFinding;
    [Test] procedure IfThenWithStringLiteralContainingParen_NoFinding;
    [Test] procedure UnrelatedCall_NoFinding;

    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestIfThenShortCircuit.BareIfThenWithCalls_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(b: Boolean);'#13#10 +
  'begin x := IfThen(b, A(), B()); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkIfThenShortCircuit));
  finally F.Free; end;
end;

procedure TTestIfThenShortCircuit.MathIfThenWithCalls_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(b: Boolean);'#13#10 +
  'begin x := Math.IfThen(b, Compute(), Fallback()); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkIfThenShortCircuit));
  finally F.Free; end;
end;

procedure TTestIfThenShortCircuit.StrUtilsIfThenWithCalls_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(b: Boolean);'#13#10 +
  'begin s := StrUtils.IfThen(b, GetA(), GetB()); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkIfThenShortCircuit));
  finally F.Free; end;
end;

procedure TTestIfThenShortCircuit.CaseInsensitive_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(b: Boolean);'#13#10 +
  'begin x := IFTHEN(b, A(), B()); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkIfThenShortCircuit));
  finally F.Free; end;
end;

procedure TTestIfThenShortCircuit.IfThenWithLiterals_NoFinding;
// Literale Werte sind harmlos - keine Side-Effects.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(b: Boolean);'#13#10 +
  'begin x := IfThen(b, 42, 0); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkIfThenShortCircuit));
  finally F.Free; end;
end;

procedure TTestIfThenShortCircuit.IfThenWithStringLiteralContainingParen_NoFinding;
// String-Literal mit '(' im Text - sollte nicht als nested-Call gewertet werden.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(b: Boolean);'#13#10 +
  'begin s := IfThen(b, ''hello(world)'', ''bye''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkIfThenShortCircuit));
  finally F.Free; end;
end;

procedure TTestIfThenShortCircuit.UnrelatedCall_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin DoSomething(A(), B()); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkIfThenShortCircuit));
  finally F.Free; end;
end;

procedure TTestIfThenShortCircuit.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(b: Boolean);'#13#10 +
  'begin x := IfThen(b, A(), B()); end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkIfThenShortCircuit then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkIfThenShortCircuit finding expected');
    Assert.AreEqual(fkIfThenShortCircuit, Hit.Kind);
    Assert.AreEqual(lsWarning,            Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestIfThenShortCircuit);

end.
