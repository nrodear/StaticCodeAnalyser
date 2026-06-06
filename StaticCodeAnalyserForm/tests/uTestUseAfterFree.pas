unit uTestUseAfterFree;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestUseAfterFree = class
  public
    [Test] procedure FreeThenUse_Reported;
    [Test] procedure FreeAndNilThenUse_Reported;
    [Test] procedure FreeThenReassign_NoFinding;
    [Test] procedure FreeAtEndOfMethod_NoFinding;
    [Test] procedure FreeOnSelf_NoFinding;
    [Test] procedure FreeOnResult_NoFinding;
    [Test] procedure Finding_KindAndSeverity;
    // A.4.6 CFG-Filter
    [Test] procedure CfgFilter_IfThenFreeExit_NoFinding;
    [Test] procedure CfgFilter_FreeInBothBranches_StillNoFinding;
    // Audit-Fixes nach mORMot/Firebird-Self-Test
    [Test] procedure FreeFieldAssignment_NoFinding;
    [Test] procedure FreeMethodWithArgument_NoFinding;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestUseAfterFree.FreeThenUse_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Free;'#13#10 +
  '  L.Add(''x'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUseAfterFree) >= 1);
  finally F.Free; end;
end;

procedure TTestUseAfterFree.FreeAndNilThenUse_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  FreeAndNil(L);'#13#10 +
  '  L.Add(''x'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkUseAfterFree) >= 1);
  finally F.Free; end;
end;

procedure TTestUseAfterFree.FreeThenReassign_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Free;'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Add(''x'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkUseAfterFree));
  finally F.Free; end;
end;

procedure TTestUseAfterFree.FreeAtEndOfMethod_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Add(''x'');'#13#10 +
  '  L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkUseAfterFree));
  finally F.Free; end;
end;

procedure TTestUseAfterFree.FreeOnSelf_NoFinding;
// Self.Free + spaeterer Self-Use ist Owner-Pattern, kein Befund.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure TFoo.Bar;'#13#10 +
  'begin'#13#10 +
  '  Self.Free;'#13#10 +
  '  Exit;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkUseAfterFree));
  finally F.Free; end;
end;

procedure TTestUseAfterFree.FreeOnResult_NoFinding;
const SRC =
  'unit t; implementation'#13#10 +
  'function Foo: TStringList;'#13#10 +
  'begin'#13#10 +
  '  Result := TStringList.Create;'#13#10 +
  '  try'#13#10 +
  '    Result.LoadFromFile(''x'');'#13#10 +
  '  except'#13#10 +
  '    FreeAndNil(Result);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkUseAfterFree));
  finally F.Free; end;
end;

procedure TTestUseAfterFree.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  L.Free;'#13#10 +
  '  L.Add(''x'');'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkUseAfterFree then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkUseAfterFree finding expected');
    Assert.AreEqual(fkUseAfterFree, Hit.Kind);
    Assert.AreEqual(lsError,        Hit.Severity);
  finally F.Free; end;
end;

{ ---- A.4.6 CFG-Filter Tests ---- }

procedure TTestUseAfterFree.CfgFilter_IfThenFreeExit_NoFinding;
// Klassischer FP-Fall: Free + Exit im if-Branch, Use im else-Branch.
// Lexisch wuerde der Use auf line 8 als UAF geflagged - mit CFG-Filter
// erkennt CanReach(FreeBlock, UseBlock)=False (Free-Block hat nur
// Exit_ als Successor, kein Pfad zum Use-Block).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(Cond: Boolean);'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  if Cond then'#13#10 +
  '  begin'#13#10 +
  '    FreeAndNil(L);'#13#10 +
  '    Exit;'#13#10 +
  '  end;'#13#10 +
  '  L.Add(''x'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkUseAfterFree),
    'CFG-Filter muss FP droppen weil Use nicht von Free aus reachable');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.CfgFilter_FreeInBothBranches_StillNoFinding;
// Free in if-then UND in else-Branch, kein nachfolgender Use. Bisheriger
// lexischer Scan emittiert auch nichts; CFG-Filter veraendert das nicht.
// Sanity-Check dass A.4.6 bestehende negative Cases nicht bricht.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(Cond: Boolean);'#13#10 +
  'var L: TStringList;'#13#10 +
  'begin'#13#10 +
  '  L := TStringList.Create;'#13#10 +
  '  if Cond then'#13#10 +
  '    FreeAndNil(L)'#13#10 +
  '  else'#13#10 +
  '    L.Free;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkUseAfterFree));
  finally F.Free; end;
end;

{ ---- Audit-Fixes ---- }

procedure TTestUseAfterFree.FreeFieldAssignment_NoFinding;
// Firebird-Pattern: 'vTable.free := @ptr' ist eine Assignment auf ein
// Field das zufaellig 'free' heisst (Function-Pointer-Setup fuer
// generated TLB-Header). KEIN Destructor-Call.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var vTable: PVTable;'#13#10 +
  'begin'#13#10 +
  '  vTable := PVTable.Create;'#13#10 +
  '  vTable.free := @SomeFreeDispatcher;'#13#10 +
  '  vTable.execute := @SomeExecuteDispatcher;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkUseAfterFree),
    'Free als Field-Assignment muss ignoriert werden');
  finally F.Free; end;
end;

procedure TTestUseAfterFree.FreeMethodWithArgument_NoFinding;
// mORMot quickjs-Pattern: 'fCx.Free(fGlobalObj)' ist ein Method-Call
// MIT Argument - eine Method namens 'Free' die nicht der Destructor
// ist. TObject.Free() hat keinen Parameter. Leere Klammern 'fCx.Free()'
// bleiben weiter ein Destructor-Match.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var fCx: TQuickJSContext;'#13#10 +
  'begin'#13#10 +
  '  fCx := TQuickJSContext.Create;'#13#10 +
  '  fCx.Free(fGlobalObj);'#13#10 +
  '  fCx.Done;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkUseAfterFree),
    'Free mit Argument ist Method-Call, kein Destructor');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUseAfterFree);

end.
