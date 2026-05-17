unit uTestQuickFix;

// Tests fuer uQuickFix - pure-text Transformations pro Provider.
// Keine IDE-Abhaengigkeit; laeuft headless in DUnitX.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestQuickFix = class
  public
    // ---- RedundantBoolean ----
    [Test] procedure RedBool_EqTrue_Removed;
    [Test] procedure RedBool_NeqFalse_Removed;
    [Test] procedure RedBool_EqFalse_BecomesNot;
    [Test] procedure RedBool_NeqTrue_BecomesNot;
    [Test] procedure RedBool_PropertyPath_Works;
    [Test] procedure RedBool_NoMatch_Untouched;

    // ---- FreeAndNil ----
    [Test] procedure FreeNil_PlainFree_Replaced;
    [Test] procedure FreeNil_PropertyPath_Replaced;
    [Test] procedure FreeNil_NoFree_NoChange;

    // ---- EmptyArgumentList ----
    [Test] procedure EmptyArgs_BasicCall_Stripped;
    [Test] procedure EmptyArgs_WithArgs_Untouched;

    // ---- AssignedAndAssignedNil ----
    [Test] procedure AssignedNil_AssignedThenNil_Simplified;
    [Test] procedure AssignedNil_NilThenAssigned_Simplified;

    // ---- Registry ----
    [Test] procedure Registry_RedundantBoolean_IsRegistered;
    [Test] procedure Registry_NotRegistered_NoFix;
  end;

implementation

uses
  System.SysUtils,
  uSCAConsts, uMethodd12, uQuickFix;

function MakeFinding(K: TFindingKind): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.FileName := 'test.pas';
  Result.LineNumber := '1';
  Result.SetKind(K);
end;

{ ---- RedundantBoolean ---- }

procedure TTestQuickFix.RedBool_EqTrue_Removed;
var
  F : TLeakFinding;
  R : TQuickFixResult;
begin
  F := MakeFinding(fkRedundantBoolean);
  try
    R := TQuickFix.ProposeFix(F, '  if IsActive = True then ;');
    Assert.IsTrue(R.Applied);
    Assert.AreEqual('  if IsActive then ;', R.Fixed);
  finally F.Free; end;
end;

procedure TTestQuickFix.RedBool_NeqFalse_Removed;
var
  F : TLeakFinding;
  R : TQuickFixResult;
begin
  F := MakeFinding(fkRedundantBoolean);
  try
    R := TQuickFix.ProposeFix(F, '  if IsActive <> False then ;');
    Assert.IsTrue(R.Applied);
    Assert.AreEqual('  if IsActive then ;', R.Fixed);
  finally F.Free; end;
end;

procedure TTestQuickFix.RedBool_EqFalse_BecomesNot;
var
  F : TLeakFinding;
  R : TQuickFixResult;
begin
  F := MakeFinding(fkRedundantBoolean);
  try
    R := TQuickFix.ProposeFix(F, '  if IsDone = False then Exit;');
    Assert.IsTrue(R.Applied);
    Assert.AreEqual('  if not IsDone then Exit;', R.Fixed);
  finally F.Free; end;
end;

procedure TTestQuickFix.RedBool_NeqTrue_BecomesNot;
var
  F : TLeakFinding;
  R : TQuickFixResult;
begin
  F := MakeFinding(fkRedundantBoolean);
  try
    R := TQuickFix.ProposeFix(F, '  while Closed <> True do Step;');
    Assert.IsTrue(R.Applied);
    Assert.AreEqual('  while not Closed do Step;', R.Fixed);
  finally F.Free; end;
end;

procedure TTestQuickFix.RedBool_PropertyPath_Works;
var
  F : TLeakFinding;
  R : TQuickFixResult;
begin
  F := MakeFinding(fkRedundantBoolean);
  try
    R := TQuickFix.ProposeFix(F, '  if Self.FCache.IsLoaded = True then ;');
    Assert.IsTrue(R.Applied);
    Assert.AreEqual('  if Self.FCache.IsLoaded then ;', R.Fixed);
  finally F.Free; end;
end;

procedure TTestQuickFix.RedBool_NoMatch_Untouched;
var
  F : TLeakFinding;
  R : TQuickFixResult;
begin
  F := MakeFinding(fkRedundantBoolean);
  try
    R := TQuickFix.ProposeFix(F, '  if MaybeNil(X) then DoStuff;');
    Assert.IsFalse(R.Applied);
    Assert.AreEqual('  if MaybeNil(X) then DoStuff;', R.Fixed);
  finally F.Free; end;
end;

{ ---- FreeAndNil ---- }

procedure TTestQuickFix.FreeNil_PlainFree_Replaced;
var
  F : TLeakFinding;
  R : TQuickFixResult;
begin
  F := MakeFinding(fkFreeAndNilHint);
  try
    R := TQuickFix.ProposeFix(F, '  FCache.Free;');
    Assert.IsTrue(R.Applied);
    Assert.AreEqual('  FreeAndNil(FCache);', R.Fixed);
  finally F.Free; end;
end;

procedure TTestQuickFix.FreeNil_PropertyPath_Replaced;
var
  F : TLeakFinding;
  R : TQuickFixResult;
begin
  F := MakeFinding(fkFreeAndNilHint);
  try
    R := TQuickFix.ProposeFix(F, '  Self.FOwner.FList.Free;');
    Assert.IsTrue(R.Applied);
    Assert.AreEqual('  FreeAndNil(Self.FOwner.FList);', R.Fixed);
  finally F.Free; end;
end;

procedure TTestQuickFix.FreeNil_NoFree_NoChange;
var
  F : TLeakFinding;
  R : TQuickFixResult;
begin
  F := MakeFinding(fkFreeAndNilHint);
  try
    R := TQuickFix.ProposeFix(F, '  DoSomething;');
    Assert.IsFalse(R.Applied);
  finally F.Free; end;
end;

{ ---- EmptyArgumentList ---- }

procedure TTestQuickFix.EmptyArgs_BasicCall_Stripped;
var
  F : TLeakFinding;
  R : TQuickFixResult;
begin
  F := MakeFinding(fkEmptyArgumentList);
  try
    R := TQuickFix.ProposeFix(F, '  DoStuff();');
    Assert.IsTrue(R.Applied);
    Assert.AreEqual('  DoStuff;', R.Fixed);
  finally F.Free; end;
end;

procedure TTestQuickFix.EmptyArgs_WithArgs_Untouched;
var
  F : TLeakFinding;
  R : TQuickFixResult;
begin
  F := MakeFinding(fkEmptyArgumentList);
  try
    R := TQuickFix.ProposeFix(F, '  DoStuff(42);');
    Assert.IsFalse(R.Applied);
  finally F.Free; end;
end;

{ ---- AssignedAndAssignedNil ---- }

procedure TTestQuickFix.AssignedNil_AssignedThenNil_Simplified;
var
  F : TLeakFinding;
  R : TQuickFixResult;
begin
  F := MakeFinding(fkAssignedAndAssignedNil);
  try
    R := TQuickFix.ProposeFix(F, '  if Assigned(Obj) and (Obj <> nil) then ;');
    Assert.IsTrue(R.Applied);
    Assert.AreEqual('  if Assigned(Obj) then ;', R.Fixed);
  finally F.Free; end;
end;

procedure TTestQuickFix.AssignedNil_NilThenAssigned_Simplified;
var
  F : TLeakFinding;
  R : TQuickFixResult;
begin
  F := MakeFinding(fkAssignedAndAssignedNil);
  try
    R := TQuickFix.ProposeFix(F, '  if (Obj <> nil) and Assigned(Obj) then ;');
    Assert.IsTrue(R.Applied);
    Assert.AreEqual('  if Assigned(Obj) then ;', R.Fixed);
  finally F.Free; end;
end;

{ ---- Registry ---- }

procedure TTestQuickFix.Registry_RedundantBoolean_IsRegistered;
begin
  Assert.IsTrue(TQuickFix.HasProviderFor(fkRedundantBoolean));
  Assert.IsTrue(TQuickFix.HasProviderFor(fkFreeAndNilHint));
  Assert.IsTrue(TQuickFix.HasProviderFor(fkEmptyArgumentList));
  Assert.IsTrue(TQuickFix.HasProviderFor(fkAssignedAndAssignedNil));
end;

procedure TTestQuickFix.Registry_NotRegistered_NoFix;
var
  F : TLeakFinding;
  R : TQuickFixResult;
begin
  // fkMemoryLeak hat keinen Provider - kein Fix.
  F := MakeFinding(fkMemoryLeak);
  try
    R := TQuickFix.ProposeFix(F, '  list := TStringList.Create;');
    Assert.IsFalse(R.Applied);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestQuickFix);

end.
