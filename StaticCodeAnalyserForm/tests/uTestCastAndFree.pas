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
    // Autopsie 2026-08-26 (Fix 1): Pointer-Idiom-Operanden.
    [Test] procedure PointerContainerIndex_NotReported;
    [Test] procedure ObjectsIndex_StillReported;
    [Test] procedure BareObjectsIndex_StillReported;
    [Test] procedure StackPopAndData_NotReported;
    [Test] procedure BareClassField_StillReported;
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
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCastAndFree));
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
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCastAndFree));
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
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCastAndFree));
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
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCastAndFree));
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
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkCastAndFree));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCastAndFree));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCastAndFree));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCastAndFree));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCastAndFree));
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
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCastAndFree));
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

procedure TTestCastAndFree.PointerContainerIndex_NotReported;
// Autopsie 2026-08-26, Fix 1: TList.Items ist Pointer - der Cast ist
// zum Kompilieren ZWINGEND (E2018 ohne), nicht redundant. Die Klasse
// stellte 19/24 des Audit-Samples.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Clear;'#13#10+
  'begin'#13#10+
  '  TItem(FList[0]).Free;'#13#10+
  '  TItem(FList.Items[1]).Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCastAndFree),
      'Index-Operand = Pointer-Idiom, kein Fund');
  finally F.Free; end;
end;

procedure TTestCastAndFree.ObjectsIndex_StillReported;
// TP-Gegenprobe: TStrings.Objects liefert TObject - dort ist der
// Cast fuer Free wirklich redundant (die belegte TP-Klasse).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Clear;'#13#10+
  'begin'#13#10+
  '  TItem(FNames.Objects[0]).Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkCastAndFree) >= 1,
      'Objects[..]-Zugriff bleibt Fund');
  finally F.Free; end;
end;

procedure TTestCastAndFree.BareObjectsIndex_StillReported;
// TP-Gegenprobe (doublecmd uvfsmodule:75): bare Objects[I] in einer
// TStringList-Ableitung - die Ausnahme muss auch OHNE Punkt greifen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TVfsList.Clear;'#13#10+
  'begin'#13#10+
  '  TVfsModule(Objects[0]).Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkCastAndFree) >= 1,
      'bare Objects[..] bleibt Fund');
  finally F.Free; end;
end;

procedure TTestCastAndFree.StackPopAndData_NotReported;
// Fix 1: TStack.Pop liefert Pointer, TListItem.Data ist Pointer -
// beide Casts zwingend. Pop() mit Klammern wird normalisiert
// (Gegenpruefungs-Spec-Luecke).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Drain;'#13#10+
  'begin'#13#10+
  '  TJob(FStack.Pop).Free;'#13#10+
  '  TJob(FStack.Pop()).Free;'#13#10+
  '  TMeta(Node.Data).Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkCastAndFree),
      'Pop/Pop()/Data sind Pointer-Idiome, kein Fund');
  finally F.Free; end;
end;

procedure TTestCastAndFree.BareClassField_StillReported;
// TP-Gegenprobe (JvButtons FGlyphDrawer): bare Feld-Operanden bleiben
// gemeldet - die Klassenfeld-TPs sind der Grund, warum die Regel
// nicht auf Objects-only verengt wurde.
const SRC =
  'unit t; implementation'#13#10+
  'destructor TBtn.Destroy;'#13#10+
  'begin'#13#10+
  '  TGlyphEx(FGlyph).Free;'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkCastAndFree) >= 1,
      'bare Ident-Operand bleibt Fund');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCastAndFree);

end.
