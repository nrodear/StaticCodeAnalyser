unit uTestCastAndFree;

// Tests fuer den TCastAndFreeDetector.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCastAndFree = class
  public
    // ---- Positive Varianten ------------------------------------------------
    [Test] procedure TObjectCastFree_Reported;
    [Test] procedure TStringListCastFree_Reported;
    [Test] procedure InterfaceCastFree_Reported;
    [Test] procedure CastDestroy_Reported;
    [Test] procedure CastFreeWithEmptyParens_Reported;

    // ---- Negative Varianten / Guards --------------------------------------
    [Test] procedure PlainFree_NoFinding;
    [Test] procedure NonClassCast_NoFinding;
    [Test] procedure QualifiedCall_NoFinding;
    [Test] procedure FunctionResultFree_NoFinding;
    [Test] procedure CastWithoutFreeOrDestroy_NoFinding;

    // ---- Finding-Inhalt ----------------------------------------------------
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestCastAndFree.TObjectCastFree_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(L: TObject);'#13#10 +
  'begin TObject(L).Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkCastAndFree));
  finally F.Free; end;
end;

procedure TTestCastAndFree.TStringListCastFree_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(L: TObject);'#13#10 +
  'begin TStringList(L).Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkCastAndFree));
  finally F.Free; end;
end;

procedure TTestCastAndFree.InterfaceCastFree_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(X: TObject);'#13#10 +
  'begin IInterface(X).Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkCastAndFree));
  finally F.Free; end;
end;

procedure TTestCastAndFree.CastDestroy_Reported;
// Manche Code-Bases rufen direkt Destroy statt Free.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(L: TObject);'#13#10 +
  'begin TStringList(L).Destroy; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkCastAndFree));
  finally F.Free; end;
end;

procedure TTestCastAndFree.CastFreeWithEmptyParens_Reported;
// `Free()` mit leeren Klammern (selten aber legal).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(L: TObject);'#13#10 +
  'begin TObject(L).Free(); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkCastAndFree));
  finally F.Free; end;
end;

procedure TTestCastAndFree.PlainFree_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(L: TStringList);'#13#10 +
  'begin L.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkCastAndFree));
  finally F.Free; end;
end;

procedure TTestCastAndFree.NonClassCast_NoFinding;
// 'Sender' matcht nicht der T/I + Grossbuchstabe-Konvention.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin Sender(X).Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkCastAndFree));
  finally F.Free; end;
end;

procedure TTestCastAndFree.QualifiedCall_NoFinding;
// Owner.Bar(x).Free - qualifizierter Funktionsaufruf, kein Cast.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin Owner.Bar(X).Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkCastAndFree));
  finally F.Free; end;
end;

procedure TTestCastAndFree.FunctionResultFree_NoFinding;
// 'MakeFoo()' ist ein Funktionsaufruf (lowercase 'm' nicht T/I).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin makeFoo(X).Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkCastAndFree));
  finally F.Free; end;
end;

procedure TTestCastAndFree.CastWithoutFreeOrDestroy_NoFinding;
// TStringList(L).Add(...) ist ein normaler Method-Call nach Cast.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(L: TObject);'#13#10 +
  'begin TStringList(L).Add(''x''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkCastAndFree));
  finally F.Free; end;
end;

procedure TTestCastAndFree.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(L: TObject);'#13#10 +
  'begin TObject(L).Free; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkCastAndFree then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkCastAndFree finding expected');
    Assert.AreEqual(fkCastAndFree, Hit.Kind);
    Assert.AreEqual(lsHint,        Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCastAndFree);

end.
