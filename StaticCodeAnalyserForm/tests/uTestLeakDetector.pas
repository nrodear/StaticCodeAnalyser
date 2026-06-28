unit uTestLeakDetector;

// Tests fuer den TLeakDetector2, TFieldLeakDetector und MemoryLeakAdvanced.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestSrcBuilder,
  uTestFindingHelper;

type
  // ---- MemoryLeak (TLeakDetector2) ----------------------------------------------------
  [TestFixture]
  TTestMemoryLeak = class
  public
    [Test] procedure Leak_CreateWithoutFree_ReportsError;
    [Test] procedure Leak_CreateFreeInFinally_NoFinding;
    [Test] procedure Leak_CustomFreeWrapper_NoFinding;
    [Test] procedure Leak_FreeOutsideFinally_ReportsWarning;
    [Test] procedure Leak_ReturnResult_NoFinding;
    [Test] procedure Leak_ReturnViaLegacyFuncName_NoFinding;
    [Test] procedure Leak_ExitWithValue_NoFinding;
    [Test] procedure Leak_ExitWithValueCast_NoFinding;
    [Test] procedure Leak_PassedToConstructor_NoFinding;
    [Test] procedure Leak_FunctionCallAssign_NoFreeReportsWarning;
    [Test] procedure Leak_FunctionCallAssign_WithFree_NoFinding;
    [Test] procedure Leak_BorrowedGetter_NoFinding;
    // Real-World 2026-06-26: 'Rueckgabewert'-FPs durch geliehene Referenzen
    // in Typecasts / Indexed-Access (cnwizards Design-Editoren).
    [Test] procedure Leak_TypecastGetterResult_NoFinding;
    [Test] procedure Leak_TypecastIndexedItem_NoFinding;
    [Test] procedure Leak_TypecastBareIdent_NoFinding;
    [Test] procedure Leak_IndexedPropertyResult_NoFinding;
    [Test] procedure Leak_SimilarVarName_NoFalsePositive;
    [Test] procedure Leak_MultipleVars_BothReported;
    [Test] procedure Leak_NoFalsePositive_BlacklistFree;
    [Test] procedure Leak_NoFalsePositive_FreeAndNilListExtra;
    [Test] procedure Leak_NilWithoutFree_ReportsError;
    [Test] procedure Leak_DoubleCreate_KnownLimitation_NoFinding;
    [Test] procedure Leak_ObjectListAdd_FieldReceiver_NoFinding;
    [Test] procedure Leak_ParseFilesAllClasses_NoFinding;
    [Test] procedure Leak_GenericObjectList_FreedInFinally_NoFinding;
    [Test] procedure Leak_FactoryMethodNoParens_BorrowedRef_NoFinding;
    [Test] procedure Leak_SiblingFactoryNoParens_ReportsLeak;
    [Test] procedure Leak_SiblingBorrowedGetterNoParens_NoFinding;
    // --- 30 weitere Leak-Tests ---
    [Test] procedure Leak_TFileStream_NoFree_ReportsError;
    [Test] procedure Leak_TMemoryStream_FreeInFinally_NoFinding;
    [Test] procedure Leak_TBitmap_NoFree_ReportsError;
    [Test] procedure Leak_TIniFile_DestroyInFinally_NoFinding;
    [Test] procedure Leak_TStreamReader_NoFree_ReportsError;
    [Test] procedure Leak_TStreamWriter_FreeInFinally_NoFinding;
    [Test] procedure Leak_TRegistry_NoFree_ReportsError;
    [Test] procedure Leak_TStringStream_NoFree_ReportsError;
    [Test] procedure Leak_ShortVarName_NoFree_ReportsError;
    [Test] procedure Leak_CreateInForLoop_NoFree_ReportsError;
    [Test] procedure Leak_TwoVars_OnlyOneFreed_ReportsOneError;
    [Test] procedure Leak_FreeInTryBody_NotFinally_ReportsWarning;
    [Test] procedure Leak_DestroyInFinally_NoFinding;
    [Test] procedure Leak_CreateBeforeTry_FreeInFinally_NoFinding;
    [Test] procedure Leak_ThreeVarsAllFreed_NoFinding;
    [Test] procedure Leak_VarDeclaredButNeverCreated_NoFinding;
    [Test] procedure Leak_CreateInWhileLoop_NoFree_ReportsError;
    [Test] procedure Leak_FunctionCallFreedInFinally_NoFinding;
    [Test] procedure Leak_FactoryMethodFreedInFinally_NoFinding;
    [Test] procedure Leak_GenericObjectList_NoFree_ReportsError;
    [Test] procedure Leak_ConditionalCreate_NoFree_ReportsError;
    [Test] procedure Leak_FreeAndNilWordBoundary_NoFalsePositive;
    [Test] procedure Leak_DotFreeWordBoundary_NoFalsePositive;
    [Test] procedure Leak_NestedTryFinally_OuterFinallyFrees_NoFinding;
    [Test] procedure Leak_CreateInsideTryBody_FreedInFinally_NoFinding;
    [Test] procedure Leak_PassedToClassCreate_NoFinding;
    [Test] procedure Leak_MultipleTypes_EachLeaking_AllReported;
    [Test] procedure Leak_FreeAfterTryFinally_ReportsWarning;
    [Test] procedure Leak_TwoFreeAndNil_BothVars_NoFinding;
    [Test] procedure Leak_LargeMethod_OneVarLeaks_OneError;
    [Test] procedure Leak_NestedTryFinally_InnerVarHasOwnFinally_NoFinding;
    [Test] procedure Leak_IfThenAssignElseBeginBlock_OuterFinallyFrees_NoFinding;
    [Test] procedure Leak_InheritedCreateWithVarArg_NoFinding;
    [Test] procedure Leak_InheritedCreateDottedCall_NoFinding;
    [Test] procedure Leak_InlineVarWithCreate_NoFree_ReportsError;
    [Test] procedure Leak_InlineVarWithCreate_FreeInFinally_NoFinding;
    [Test] procedure Leak_AnonymousFunctionInRhs_NoCrash;
    // Regression: 'list := obj.FList' ist Borrowed-Reference, kein Factory-Call
    [Test] procedure Leak_AssignFromFieldDottedNoParens_NoFinding;
    // Regression: CamelCase-Konstruktor-Varianten (CreateUtf8, CreateFmt, ...)
    [Test] procedure Leak_CreateUtf8_NoFree_ReportsError;
    [Test] procedure Leak_CreateFmt_NoFree_ReportsError;
    [Test] procedure Leak_DotCreatedProperty_NotConstructor_NoFinding;
  end;

  // ---- MemoryLeak Advanced - Wrong-Free / Pointer-Issues / Container-Ownership ----
  // Fokus: korrektheits-kritische Patterns die echten Bug-Hunt-Wert haben:
  //   * Falsch-Free (Free auf andere Variable, vor Create, in falschem Branch)
  //   * Pointer-Aliasing (zwei Refs auf dasselbe Objekt)
  //   * Try/finally-Edge-Cases (geschachtelt, except statt finally, Reassignment)
  //   * Container-Ownership-Whitelist (TObjectList vs. TStringList)
  //   * Recent-Fix-Coverage (.Parent-Assign, .AddChild, FField := var)
  //
  // Einige Tests dokumentieren EXPLIZIT bekannte False-Negatives des aktuellen
  // String-basierten Detektors (z.B. Use-After-Free, Reassignment-Lost-Ref).
  // Solche Tests haben '_KnownLimitation_NoFinding' im Namen und im Body
  // einen Kommentar mit "TODO: Detector improvement opportunity".
  [TestFixture]
  TTestMemoryLeakAdvanced = class
  public
    // --- A: Wrong-Free / Mismatched Free (10 Tests) ---
    [Test] procedure Leak_FreeOnDifferentVarTypo_OriginalLeaks;
    [Test] procedure Leak_NilAssignmentInsteadOfFree_ReportsError;
    [Test] procedure Leak_FreeBeforeCreate_KnownLimitation_NoFinding;
    [Test] procedure Leak_FreeOnFieldNotLocalVar_LocalLeaks;
    [Test] procedure Leak_DoubleFreeAndNilSameVar_NoFinding;
    [Test] procedure Leak_FreeInExceptOnly_KnownLimitation_NoFinding;
    [Test] procedure Leak_FreeAndNilWhitespacePadded_NoFalsePositive;
    [Test] procedure Leak_ReassignedThenFree_KnownLimitation_NoFinding;
    [Test] procedure Leak_FreeOnlyInIfBranch_KnownLimitation_NoFinding;
    [Test] procedure Leak_UseAfterFree_KnownLimitation_NoFinding;

    // --- B: Pointer / Reference Aliasing (8 Tests) ---
    [Test] procedure Leak_AssignedToOtherVarFreedViaOther_OriginalLeaks;
    [Test] procedure Leak_TwoVarsAliasedDoubleFree_KnownLimitation_NoFinding;
    [Test] procedure Leak_NilCheckBeforeFree_NoFinding;
    [Test] procedure Leak_AssignedToFFieldWithFPrefix_NoFinding;
    [Test] procedure Leak_AssignedToSelfDotField_NoFinding;
    [Test] procedure Leak_AssignedToFieldAsInterface_NoFinding;
    [Test] procedure Leak_BorrowedFromAddCall_NoFinding;
    [Test] procedure Leak_BorrowedFromAddChildCall_NoFinding;

    // --- C: Try/Finally Edge Cases (7 Tests) ---
    [Test] procedure Leak_CreateInsideTryBeginFinally_NoFinding;
    [Test] procedure Leak_NestedTryFinally_BothFreed_NoFinding;
    [Test] procedure Leak_NestedTryFinally_InnerLeaks_OneError;
    [Test] procedure Leak_TryExceptNoFinally_LeaksError;
    [Test] procedure Leak_MultiCreateOneFinally_AllFreed_NoFinding;
    [Test] procedure Leak_MultiCreateOneFinally_LastNotFreed_OneError;
    [Test] procedure Leak_FreeAfterTryFinallyBlock_ReportsWarning;

    // --- D: Container-Ownership-Whitelist (5 Tests) ---
    [Test] procedure Leak_TObjectListAddTypedReceiver_OwnershipRecognized;
    [Test] procedure Leak_TListAddNonOwning_ReportsError;
    [Test] procedure Leak_TObjectDictionaryAdd_OwnershipRecognized;
    [Test] procedure Leak_AddObjectMethod_OwnershipRecognized;
    [Test] procedure Leak_TStackPush_OwnershipRecognized;
  end;

  // ---- FieldLeak (TFieldLeakDetector) ------------------------------------------------
  // Klassen-Feld-Leaks im Create/Destroy-Pattern
  [TestFixture]
  TTestFieldLeak = class
  public
    [Test] procedure Field_CreatedAndFreed_NoFinding;
    [Test] procedure Field_CreatedNotFreed_ReportsError;
    [Test] procedure Field_CreatedFreedViaFreeAndNil_NoFinding;
    [Test] procedure Field_NoDestructor_ReportsError;
    [Test] procedure Field_NotCreatedInCreate_NoFinding;
    [Test] procedure Field_NonLeakyType_NoFinding;
    [Test] procedure Field_SelfQualified_RecognizedAsCreate;
    [Test] procedure Field_TwoFieldsOneLeaks_OneError;
    [Test] procedure Field_FreedViaDestroyMethod_NoFinding;
    [Test] procedure Field_TwoClassesIndependent_OnlyLeakingReported;
    [Test] procedure Field_FreedViaAlias_NoFinding;
  end;

implementation

{ ---- MemoryLeak ---- }

procedure TTestMemoryLeak.Leak_CreateWithoutFree_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  list.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'list ohne Free soll als Error gemeldet werden');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_CreateFreeInFinally_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    list.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(list);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'list in finally freigegeben – kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_CustomFreeWrapper_NoFinding;
// FP-Fix (Real-World 2026-06-21): Custom-Free-Wrapper deren Name 'free'
// enthaelt (ALFreeAndNil, ALFreeObjectList, ...) muessen als Freigabe
// erkannt werden - sonst FP-Leak. Alcinoe nutzt diese durchgaengig.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    list.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    ALFreeAndNil(list);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'ALFreeAndNil ist ein Free-Wrapper - kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_FreeOutsideFinally_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list, other: TStringList;'#13#10+
  'begin'#13#10+
  '  list  := TStringList.Create;'#13#10+
  '  other := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    other.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    other.Free;'#13#10+
  '  end;'#13#10+
  '  list.Free;'#13#10+   // außerhalb finally, aber try/finally vorhanden
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsWarning),
      'list.Free außerhalb finally – Warning');
    Assert.AreEqual<Integer>(0, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'other korrekt freigegeben – kein Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_ReturnResult_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'function TFoo.Build: TStringList;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  list.Add(''x'');'#13#10+
  '  Result := list;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Ownership über Result abgegeben – kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_ReturnViaLegacyFuncName_NoFinding;
// FP-Fix doublecmd torrent/BDecode.pas:bdecodeHash:
// Pascal/Delphi-Legacy-Syntax verwendet den Funktionsnamen selbst als
// implizite Ergebnis-Variable statt 'Result := ...'. Beide Formen
// sind gueltig und semantisch identisch - Detector muss beide
// als Ownership-Transfer-Return erkennen.
const SRC =
  'unit t; implementation'#13#10+
  'function bdecodeHash: TStringList;'#13#10+
  'var r: TStringList;'#13#10+
  'begin'#13#10+
  '  r := TStringList.Create;'#13#10+
  '  r.Add(''x'');'#13#10+
  '  bdecodeHash := r;'#13#10+      // legacy Pascal-Stil
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Legacy <FuncName> := r ist Ownership-Transfer wie Result := r');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_ExitWithValue_NoFinding;
// FP-Fix doublecmd-Audit: 'Exit(varname)' ist moderner Shortcut fuer
// 'Result := varname; Exit;' - Ownership-Transfer wie Result-Assignment.
// Detector hat das vorher nicht erkannt (nur nkAssign-Walk).
// In doublecmd: 825 Exit-Calls.
const SRC =
  'unit t; implementation'#13#10+
  'function Build: TStringList;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  list.Add(''x'');'#13#10+
  '  Exit(list);'#13#10+           // modern Result-Transfer
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Exit(list) gibt Ownership weiter - kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_ExitWithValueCast_NoFinding;
// Wie Leak_ExitWithValue, aber mit explicit cast.
const SRC =
  'unit t; implementation'#13#10+
  'function GetIntf: IInterface;'#13#10+
  'var L: TInterfacedObject;'#13#10+
  'begin'#13#10+
  '  L := TInterfacedObject.Create;'#13#10+
  '  Exit(L as IInterface);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Exit(L as IInterface) ist Ownership-Transfer mit Cast');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_PassedToConstructor_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'constructor TFoo.Create(const AFile: string);'#13#10+
  'var stream: TFileStream;'#13#10+
  'begin'#13#10+
  '  stream := TFileStream.Create(AFile, fmOpenRead);'#13#10+
  '  inherited Create(stream, True);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'stream an inherited Create übergeben – kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_FunctionCallAssign_NoFreeReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := BuildList();'#13#10+
  '  list.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsWarning),
      'Funktionsaufruf-Zuweisung ohne Free – Warning');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_BorrowedGetter_NoFinding;
// Regression TAstNode.FindAll - 'Source := EnsureCacheFor(AKind)' liefert
// SHARED-Cache-Ref, kein Ownership-Transfer. Caller darf NICHT free-en.
// Convention: Functions mit Prefix Ensure*/Get*/Find*/Lookup*/Peek*/
// Cached*/Fetch* liefern geliehene Referenzen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := EnsureCacheFor(42);'#13#10+
  '  list.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'EnsureCacheFor liefert SHARED-Ref, kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_TypecastBareIdent_NoFinding;
// FP-Fix 2026-06-28 (delphimvcframework): 'lList := TMVCListOfInteger(AObject)'.
// Typecast eines bestehenden Identifiers/Params borgt die Referenz (ein Cast
// allokiert nie) - kein Ownership, kein Leak. Frueher nur Casts mit '.'/'['-Arg
// erkannt; bare-Ident-Arg fiel durch.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar(AObject: TObject);'#13#10+
  'var lList: TList;'#13#10+
  'begin'#13#10+
  '  lList := TMVCListOfInteger(AObject);'#13#10+
  '  lList.Clear;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'Typecast eines bare Identifiers borgt - kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_TypecastGetterResult_NoFinding;
// cnwizards CnDesignPropEditors: Comp := TComponent(GetComponent(0)).
// Typecast eines Accessor-Ergebnisses borgt - kein Ownership, kein Leak.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var Comp: TComponent;'#13#10+
  'begin'#13#10+
  '  Comp := TComponent(GetComponent(0));'#13#10+
  '  Comp.Tag := 1;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Typecast(Getter) ist geliehen, kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_TypecastIndexedItem_NoFinding;
// cnwizards CnPropertyCompareFrm: Comp := TComponent(FSelection[0]).
// Typecast eines Collection-Items borgt - kein Ownership, kein Leak.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var Comp: TComponent;'#13#10+
  'begin'#13#10+
  '  Comp := TComponent(FSelection[0]);'#13#10+
  '  Comp.Tag := 1;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Typecast(Item) ist geliehen, kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_IndexedPropertyResult_NoFinding;
// cnwizards CnCompToCodeFrm: AChildComp := (Sender as TForm).Components[I].
// Indexed-Property-Zugriff als Ergebnis borgt das Element - kein Leak.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar(Sender: TObject);'#13#10+
  'var Comp: TComponent;'#13#10+
  'begin'#13#10+
  '  Comp := (Sender as TForm).Components[0];'#13#10+
  '  Comp.Tag := 1;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Indexed-Property-Ergebnis ist geliehen, kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_FunctionCallAssign_WithFree_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := BuildList();'#13#10+
  '  try'#13#10+
  '    list.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(list);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Funktionsaufruf mit Free in finally – kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_SimilarVarName_NoFalsePositive;
// VarNames und VarNamesList – der Detektor darf kein false positive auf
// VarNamesList erzeugen, wenn nur VarNames freigegeben wird.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var VarNames: TStringList;'#13#10+
  'begin'#13#10+
  '  VarNames := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    VarNames.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(VarNames);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'VarNames korrekt freigegeben – kein Befund (kein false positive)');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_MultipleVars_BothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var a, b: TStringList;'#13#10+
  'begin'#13#10+
  '  a := TStringList.Create;'#13#10+
  '  b := TStringList.Create;'#13#10+
  '  a.Add(''x'');'#13#10+
  '  b.Add(''y'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(2, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'a und b nie freigegeben – beide als Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_NoFalsePositive_BlacklistFree;
// 'blacklist.Free' soll 'list' NICHT als freigegeben markieren
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list, blacklist: TStringList;'#13#10+
  'begin'#13#10+
  '  list      := TStringList.Create;'#13#10+
  '  blacklist := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    blacklist.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(blacklist);'#13#10+
  '  end;'#13#10+
  '  // list.Free fehlt!'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'list nie freigegeben – Error; blacklist korrekt – kein zweiter Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_NoFalsePositive_FreeAndNilListExtra;
// FreeAndNil(listExtra) soll 'list' NICHT als freigegeben markieren
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list, listExtra: TStringList;'#13#10+
  'begin'#13#10+
  '  list      := TStringList.Create;'#13#10+
  '  listExtra := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    listExtra.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(listExtra);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'list nie freigegeben – FreeAndNil(listExtra) darf nicht zählen');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_NilWithoutFree_ReportsError;
// list := nil ohne vorheriges Free = Leck
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  list.Add(''x'');'#13#10+
  '  list := nil;  // Free fehlt!'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'list := nil ohne Free – Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_DoubleCreate_KnownLimitation_NoFinding;
// Zweites Create ohne zwischenzeitliches Free verliert die Referenz auf
// das ERSTE Objekt - klassischer Reassignment-Leak. Aktueller String-
// basierter Detektor trackt aber nur "Variablenname hat Free gesehen"
// (nicht: pro Instanz). Mit dem abschliessenden FreeAndNil(list) sieht
// der Detektor: Free vorhanden -> kein Leak gemeldet.
// TODO: Detector improvement opportunity - SSA-Form / Definition-Use-
// Tracking wuerde das catchen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  list.Add(''a'');'#13#10+
  '  list := TStringList.Create; // zweites Create ohne Free!'#13#10+
  '  list.Add(''b'');'#13#10+
  '  FreeAndNil(list);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Reassignment-Lost-Ref wird vom Detektor nicht erkannt (known limitation)');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_ObjectListAdd_FieldReceiver_NoFinding;
// FOwnerList.Add(item) - Receiver ist ein Klassen-Feld (F-Praefix),
// dessen Typ NICHT in der Methode aufloesbar ist (kein Local-Var/Param-
// Match). Recent fix `AddReceiverOwnsItems` faellt fuer unaufloesbare
// Receiver auf permissive Default zurueck (= Ownership angenommen) -
// vermeidet Regression bei haeufigen FList.Add(item)-Mustern in Frame-/
// Form-Konstruktoren.
//
// Trade-off: das ist ein known false-negative bei TList<T>-aehnlichen
// Field-Listen die NICHT ownership-bewusst sind. Bei Local-Var-Receiver
// wuerde die strikte Whitelist greifen.
// TODO: Detector improvement opportunity - Field-Type-Lookup im
// enclosing class declaration ausbauen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var item: TStringList;'#13#10+
  'begin'#13#10+
  '  item := TStringList.Create;'#13#10+
  '  item.Add(''x'');'#13#10+
  '  FOwnerList.Add(item);  // FOwnerList = Field, Typ unbekannt'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Field-Receiver mit .Add() faellt auf permissive Default zurueck');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_ParseFilesAllClasses_NoFinding;
// Entspricht dem realen Muster von TStaticAnalyzer.ParseFilesAllClasses:
// 6 leaky Variablen (TStringList, TObjectList<...>), alle via FreeAndNil
// im finally-Block freigegeben. Kein Befund erwartet.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TStaticAnalyzer.ParseFilesAllClasses;'#13#10+
  'var'#13#10+
  '  filename: string;'#13#10+
  '  i, k: Integer;'#13#10+
  '  methodInfos: TObjectList<TMethodInfo>;'#13#10+
  '  VarNames: TStringList;'#13#10+
  '  leakResults: TObjectList<TLeakResult>;'#13#10+
  '  smellResults: TObjectList<TSmellFinding>;'#13#10+
  '  rawLines: TStringList;'#13#10+
  '  lowLines: TStringList;'#13#10+
  'begin'#13#10+
  '  VarNames     := TStringList.Create;'#13#10+
  '  leakResults  := TObjectList<TLeakResult>.Create;'#13#10+
  '  smellResults := TObjectList<TSmellFinding>.Create;'#13#10+
  '  methodInfos  := TObjectList<TMethodInfo>.Create;'#13#10+
  '  rawLines     := TStringList.Create;'#13#10+
  '  lowLines     := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    for i := 0 to 10 do'#13#10+
  '    begin'#13#10+
  '      try'#13#10+
  '        rawLines.LoadFromFile(filename);'#13#10+
  '      except'#13#10+
  '        Continue;'#13#10+
  '      end;'#13#10+
  '      lowLines.Clear;'#13#10+
  '      for k := 0 to rawLines.Count - 1 do'#13#10+
  '        lowLines.Add(rawLines[k]);'#13#10+
  '      methodInfos.Clear;'#13#10+
  '      try'#13#10+
  '        TParser.ParseLines(rawLines, methodInfos);'#13#10+
  '      except'#13#10+
  '        Continue;'#13#10+
  '      end;'#13#10+
  '      leakResults.Clear;'#13#10+
  '      smellResults.Clear;'#13#10+
  '    end;'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(VarNames);'#13#10+
  '    FreeAndNil(leakResults);'#13#10+
  '    FreeAndNil(smellResults);'#13#10+
  '    FreeAndNil(methodInfos);'#13#10+
  '    FreeAndNil(rawLines);'#13#10+
  '    FreeAndNil(lowLines);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'ParseFilesAllClasses: alle Vars korrekt im finally freigegeben – kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_GenericObjectList_FreedInFinally_NoFinding;
// TObjectList<T> mit generischem Typparameter: wird korrekt als leaky erkannt,
// aber durch FreeAndNil im finally-Block sauber freigegeben.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var results: TObjectList<TLeakFinding>;'#13#10+
  'begin'#13#10+
  '  results := TObjectList<TLeakFinding>.Create;'#13#10+
  '  try'#13#10+
  '    results.Add(TLeakFinding.Create);'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(results);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'TObjectList<T> in finally freigegeben – kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_FactoryMethodNoParens_BorrowedRef_NoFinding;
// Dotted-no-parens Pattern (`classes := TConsts.GetLeakyClasses`):
// HasFunctionCallAssign verlangt explizit '(' im RHS. Ohne Klammern
// wird das Pattern als geliehene Referenz gewertet (z.B. Field-Access
// `list := obj.FList`), nicht als Factory-Aufruf. Bewusste Trade-off-
// Entscheidung im Detektor (TODO-Eintrag erledigt): lieber False-
// Negative auf seltene parameterlose Factories (TFoo.Singleton) als
// False-Positive auf Standard-Field-/Property-Zuweisungen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var classes: TStringList;'#13#10+
  'begin'#13#10+
  '  classes := TConsts.GetLeakyClasses;'#13#10+
  '  classes.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Dotted-no-parens RHS = Borrowed-Reference, kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_SiblingFactoryNoParens_ReportsLeak;
// FN-Fix (MeineUnit 2026-06-21): `list := MeineFactory;` (klammerloser
// Aufruf einer parameterlosen Schwester-Factory DERSELBEN Klasse, deren
// Body `Result := TFoo.Create` macht) ist Ownership-Transfer -> Leak,
// wenn list nie freigegeben wird.
const SRC =
  'unit t; implementation'#13#10+
  'function TFoo.MakeList: TStringList;'#13#10+
  'begin'#13#10+
  '  Result := TStringList.Create;'#13#10+
  'end;'#13#10+
  'function TFoo.Leaky: TStringList;'#13#10+
  'var list1: TStringList;'#13#10+
  'begin'#13#10+
  '  list1 := MakeList;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
      'klammerloser Schwester-Factory-Aufruf ohne Free muss als Leak gemeldet werden');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_SiblingBorrowedGetterNoParens_NoFinding;
// Praezisions-Guard: eine Schwester-Methode die ein FELD zurueckgibt
// (`Result := FCache`, kein Create) ist ein geliehener Getter - der
// klammerlose Aufruf darf NICHT als Leak gemeldet werden.
const SRC =
  'unit t; implementation'#13#10+
  'function TFoo.GetCached: TStringList;'#13#10+
  'begin'#13#10+
  '  Result := FCache;'#13#10+
  'end;'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list1: TStringList;'#13#10+
  'begin'#13#10+
  '  list1 := GetCached;'#13#10+
  '  list1.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'geliehener Getter (Result := FCache) ist kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_IfThenAssignElseBeginBlock_OuterFinallyFrees_NoFinding;
// Regression: TDuplicateStringDetector.AnalyzeUnit produzierte einen
// false-positive Memory-Leak-Befund fuer 'Lst', weil der Parser ein
// "x := y else begin ... end;"-Muster im THEN-Zweig falsch verarbeitet hat.
// Die RHS einer Zuweisung muss an 'else' enden, sonst verschluckt sie den
// else-Block und das end;-Zaehlen verschiebt sich.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Analyze;'#13#10+
  'var'#13#10+
  '  Lst: TStringList;'#13#10+
  '  Counts: TList;'#13#10+
  '  S: string;'#13#10+
  'begin'#13#10+
  '  Counts := TList.Create;'#13#10+
  '  Lst := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    for S in Lst do'#13#10+
  '    begin'#13#10+
  '      if Counts.ContainsKey(S) then'#13#10+
  '        Counts[S] := Counts[S] + 1'#13#10+
  '      else'#13#10+
  '      begin'#13#10+
  '        Counts.Add(S, 1);'#13#10+
  '        Counts.Add(S, 2);'#13#10+
  '      end;'#13#10+
  '    end;'#13#10+
  '  finally'#13#10+
  '    Counts.Free;'#13#10+
  '    Lst.Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Lst und Counts werden im aeusseren finally freigegeben - kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_InheritedCreateWithVarArg_NoFinding;
// Regression: Parser hat den Aufrufausdruck nach 'inherited' verworfen
// (nkInherited.Name war nur 'inherited'). Folge: IsPassedToOwner sah
// kein 'create' und meldete einen False-Positive Leak. Mit Fix wird
// 'Create(stream, True)' im Name erfasst und Ownership-Transfer erkannt.
const SRC =
  'unit t; implementation'#13#10+
  'constructor TFoo.Create(const AFile: string);'#13#10+
  'var stream: TFileStream;'#13#10+
  'begin'#13#10+
  '  stream := TFileStream.Create(AFile, fmOpenRead);'#13#10+
  '  inherited Create(stream, True);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'stream wird an inherited Create uebergeben - kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_InheritedCreateDottedCall_NoFinding;
// 'inherited Foo.Bar(...)' - dotted call nach inherited muss komplett
// erfasst werden. ParsePrimary kann das, der alte Parser ist abgebrochen.
const SRC =
  'unit t; implementation'#13#10+
  'constructor TBar.Create(AOwner: TComponent);'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  inherited Create.Configure(list);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'list an dotted inherited-Call uebergeben - kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_InlineVarWithCreate_NoFree_ReportsError;
// Regression: mid-block 'var lst: TStringList := TStringList.Create;'
// wurde vom Parser komplett ignoriert (kein nkLocalVar). Folge: Detektor
// hat das Leak nicht erkannt. Mit Fix wird inline-var als nkLocalVar +
// nkAssign abgelegt und der fehlende Free gemeldet.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  var lst: TStringList := TStringList.Create;'#13#10+
  '  lst.Add(''hi'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'inline-var ohne Free muss als Leak (lsError) gemeldet werden');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_InlineVarWithCreate_FreeInFinally_NoFinding;
// Inline-var korrekt mit try/finally - kein Befund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  var lst: TStringList := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    lst.Add(''hi'');'#13#10+
  '  finally'#13#10+
  '    lst.Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'inline-var mit Free in finally - kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_AnonymousFunctionInRhs_NoCrash;
// Regression: anonyme Methoden im RHS einer Zuweisung haben den Parser
// fruehzeitig abbrechen lassen, weil das innere 'end' als Statement-Ende
// interpretiert wurde. Mit begin/end-Tracking im RHS-Reader wird der
// gesamte Funktionskoerper als TypeRef der Zuweisung abgelegt.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var lst: TStringList;'#13#10+
  '    Comparator: TFunc<Integer>;'#13#10+
  'begin'#13#10+
  '  lst := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    Comparator := function: Integer'#13#10+
  '      begin'#13#10+
  '        Result := 42;'#13#10+
  '      end;'#13#10+
  '    lst.Add(IntToStr(Comparator()));'#13#10+
  '  finally'#13#10+
  '    lst.Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'lst korrekt freigegeben trotz anonymer Methode in der RHS');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_AssignFromFieldDottedNoParens_NoFinding;
// Regression: `list := obj.FList` ist eine geliehene Referenz auf ein
// existierendes Feld - kein Ownership-Transfer, also kein Leak.
// Vorher hat HasFunctionCallAssign jeden dotted Bezeichner ohne '(' als
// Factory-Call interpretiert -> false-positive Memory-Leak-Warnung.
//
// Pattern-Demo: einer der ersten Tests, der den uTestSrcBuilder-Helper
// nutzt. Statt `const SRC = '...'#13#10+...'` (Apostroph-Hoelle) wird
// der Quelltext per Builder konstruiert. Delphi-Constraint: `const`
// erlaubt keinen Funktionscall, daher `var SRC: string := ...`.
var
  SRC: string;
  F  : TObjectList<TLeakFinding>;
begin
  SRC := ProcInUnit('TFoo.Bar', 'list: TStringList', [
    'list := Self.FList;',
    'list.Add(''x'');',
    '// kein Free - list ist nur eine Referenz auf FList,',
    '// nicht der Owner.'
  ]);
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Borrowed-Reference (Self.FList) darf nicht als Leak gemeldet werden');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_CreateUtf8_NoFree_ReportsError;
// Regression: mORMot-Idiom `E := EOrmException.CreateUtf8('%', [...])`.
// Vorher hat HasCreateAssign nur '.create' + non-Ident-Char akzeptiert,
// 'createutf8' wurde als Verb-Form abgewiesen -> Leak unentdeckt.
// Jetzt: CamelCase-Suffix (U gross) = Konstruktor-Variante.
var
  SRC: string;
  F  : TObjectList<TLeakFinding>;
begin
  SRC := ProcInUnit('TFoo.Bar', 'sl: TStringList', [
    'sl := TStringList.CreateUtf8(''demo'');',
    'sl.Add(''x'');',
    '// kein Free - sollte Leak melden'
  ]);
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
      'CreateUtf8 ohne Free muss Leak melden (CamelCase-Konstruktor-Variante)');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_CreateFmt_NoFree_ReportsError;
// Regression: RTL-Idiom `E := EConvertError.CreateFmt('Bad %s', [s])`.
// Analog CreateUtf8: 'F' gross => Konstruktor-Variante.
var
  SRC: string;
  F  : TObjectList<TLeakFinding>;
begin
  SRC := ProcInUnit('TFoo.Bar', 'sl: TStringList', [
    'sl := TStringList.CreateFmt(''Bad %s'', [''x'']);',
    'sl.Add(''y'');'
  ]);
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
      'CreateFmt ohne Free muss Leak melden');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_DotCreatedProperty_NotConstructor_NoFinding;
// Negative regression: `.Created` (Folge-Zeichen klein) ist KEIN Konstruktor -
// kann Property oder Field-Read sein, die eine bereits existierende Instanz
// liefert (Borrowed-Reference, kein Ownership-Transfer). Darf nicht als
// Create-Assign gewertet werden, sonst False-Positive auf jeder Read-
// Property mit 'created'-Suffix. Wichtig: leaky Typ (TStringList) damit
// der Detektor wirklich bis MatchesCreate kommt - sonst trivial bestanden.
var
  SRC: string;
  F  : TObjectList<TLeakFinding>;
begin
  SRC := ProcInUnit('TFoo.Bar', 'sl: TStringList', [
    'sl := Self.Created;',
    '// kein Free - sl ist nur eine Referenz auf eine bestehende Liste'
  ]);
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      '.Created (Property/Field-Suffix in lowercase) darf nicht als Konstruktor erkannt werden');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_NestedTryFinally_InnerVarHasOwnFinally_NoFinding;
// Reproduziert das Muster aus TDuplicateStringDetector.AnalyzeUnit:
// 3 leaky Vars (Counts, AllNodes, Lst). AllNodes hat eigenes try/finally
// in einer Schleife. Counts und Lst werden im aeusseren finally freigegeben.
const SRC =
  'unit t; implementation'#13#10+
  'class procedure TFoo.Analyze;'#13#10+
  'var'#13#10+
  '  Counts: TList;'#13#10+
  '  AllNodes: TList;'#13#10+
  '  Lst: TStringList;'#13#10+
  '  i: Integer;'#13#10+
  'begin'#13#10+
  '  Counts := TList.Create;'#13#10+
  '  Lst := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    for i := 1 to 2 do'#13#10+
  '    begin'#13#10+
  '      AllNodes := TList.Create;'#13#10+
  '      try'#13#10+
  '        Lst.Clear;'#13#10+
  '      finally'#13#10+
  '        AllNodes.Free;'#13#10+
  '      end;'#13#10+
  '    end;'#13#10+
  '  finally'#13#10+
  '    Counts.Free;'#13#10+
  '    Lst.Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Lst und Counts in aeusserem finally, AllNodes in eigenem inneren finally - kein Befund');
  finally F.Free; end;
end;

{ ---- 30 weitere MemoryLeak-Tests ---- }

procedure TTestMemoryLeak.Leak_TFileStream_NoFree_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var fs: TFileStream;'#13#10+
  'begin'#13#10+
  '  fs := TFileStream.Create(''test.txt'', fmOpenRead);'#13#10+
  '  fs.Read(buf, 10);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'TFileStream nie freigegeben – Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_TMemoryStream_FreeInFinally_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var ms: TMemoryStream;'#13#10+
  'begin'#13#10+
  '  ms := TMemoryStream.Create;'#13#10+
  '  try'#13#10+
  '    ms.LoadFromFile(''data.bin'');'#13#10+
  '  finally'#13#10+
  '    ms.Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'TMemoryStream in finally freigegeben – kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_TBitmap_NoFree_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var bmp: TBitmap;'#13#10+
  'begin'#13#10+
  '  bmp := TBitmap.Create;'#13#10+
  '  bmp.Width := 100;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'TBitmap nie freigegeben – Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_TIniFile_DestroyInFinally_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var ini: TIniFile;'#13#10+
  'begin'#13#10+
  '  ini := TIniFile.Create(''config.ini'');'#13#10+
  '  try'#13#10+
  '    ini.WriteString(''S'', ''K'', ''V'');'#13#10+
  '  finally'#13#10+
  '    ini.Destroy;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'TIniFile.Destroy in finally – kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_TStreamReader_NoFree_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var reader: TStreamReader;'#13#10+
  'begin'#13#10+
  '  reader := TStreamReader.Create(''file.txt'');'#13#10+
  '  reader.ReadLine;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'TStreamReader nie freigegeben – Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_TStreamWriter_FreeInFinally_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var writer: TStreamWriter;'#13#10+
  'begin'#13#10+
  '  writer := TStreamWriter.Create(''out.txt'');'#13#10+
  '  try'#13#10+
  '    writer.WriteLine(''hello'');'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(writer);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'TStreamWriter in finally freigegeben – kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_TRegistry_NoFree_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var reg: TRegistry;'#13#10+
  'begin'#13#10+
  '  reg := TRegistry.Create;'#13#10+
  '  reg.OpenKey(''Software\MyApp'', True);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'TRegistry nie freigegeben – Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_TStringStream_NoFree_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var ss: TStringStream;'#13#10+
  'begin'#13#10+
  '  ss := TStringStream.Create(''hello'');'#13#10+
  '  DoSomething(ss);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'TStringStream nie freigegeben – Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_ShortVarName_NoFree_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var sl: TStringList;'#13#10+
  'begin'#13#10+
  '  sl := TStringList.Create;'#13#10+
  '  sl.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'Kurzer Variablenname sl – Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_CreateInForLoop_NoFree_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var i: Integer; items: TStringList;'#13#10+
  'begin'#13#10+
  '  for i := 0 to 2 do'#13#10+
  '  begin'#13#10+
  '    items := TStringList.Create;'#13#10+
  '    items.Add(IntToStr(i));'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'Create in for-Schleife ohne Free – Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_TwoVars_OnlyOneFreed_ReportsOneError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var a, b: TStringList;'#13#10+
  'begin'#13#10+
  '  a := TStringList.Create;'#13#10+
  '  b := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    a.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    a.Free;'#13#10+
  '  end;'#13#10+
  '  // b wird nie freigegeben'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'b nie freigegeben – 1 Error; a korrekt – kein zweiter Befund');
    Assert.AreEqual<Integer>(0, TFindingHelper.CountSev(F, fkMemoryLeak, lsWarning),
      'a in finally freigegeben – kein Warning');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_FreeInTryBody_NotFinally_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    list.Add(''x'');'#13#10+
  '    list.Free;'#13#10+
  '  finally'#13#10+
  '    DoSomething;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsWarning),
      'Free im try-Rumpf statt finally – Warning');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_DestroyInFinally_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    list.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    list.Destroy;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      '.Destroy in finally zählt als Freigabe – kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_CreateBeforeTry_FreeInFinally_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    list.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(list);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Create vor try, FreeAndNil in finally – kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_ThreeVarsAllFreed_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var a, b, c: TStringList;'#13#10+
  'begin'#13#10+
  '  a := TStringList.Create;'#13#10+
  '  b := TStringList.Create;'#13#10+
  '  c := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    a.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(a);'#13#10+
  '    FreeAndNil(b);'#13#10+
  '    FreeAndNil(c);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Drei Variablen alle in finally freigegeben – kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_VarDeclaredButNeverCreated_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  DoSomething(list);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Deklariert aber nie erzeugt – kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_CreateInWhileLoop_NoFree_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  while True do'#13#10+
  '  begin'#13#10+
  '    list := TStringList.Create;'#13#10+
  '    list.Add(''x'');'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'Create in while-Schleife ohne Free – Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_FunctionCallFreedInFinally_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := BuildList();'#13#10+
  '  try'#13#10+
  '    list.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(list);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Funktionsrückgabe in finally freigegeben – kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_FactoryMethodFreedInFinally_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var classes: TStringList;'#13#10+
  'begin'#13#10+
  '  classes := TConsts.GetLeakyClasses;'#13#10+
  '  try'#13#10+
  '    classes.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(classes);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Parameterlose Factory-Methode in finally freigegeben – kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_GenericObjectList_NoFree_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var items: TObjectList<TStringList>;'#13#10+
  'begin'#13#10+
  '  items := TObjectList<TStringList>.Create;'#13#10+
  '  items.Add(TStringList.Create);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.CountSev(F, fkMemoryLeak, lsError) >= 1,
      'TObjectList<T> nie freigegeben – mindestens 1 Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_ConditionalCreate_NoFree_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar(NeedList: Boolean);'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  if NeedList then'#13#10+
  '    list := TStringList.Create;'#13#10+
  '  DoWork(list);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'Bedingtes Create ohne Free – Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_FreeAndNilWordBoundary_NoFalsePositive;
// FreeAndNil(listmore) darf 'list' nicht als freigegeben markieren
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list, listmore: TStringList;'#13#10+
  'begin'#13#10+
  '  list     := TStringList.Create;'#13#10+
  '  listmore := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    list.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(listmore);'#13#10+
  '  end;'#13#10+
  '  // list.Free fehlt!'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'FreeAndNil(listmore) zählt nicht für list – list als Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_DotFreeWordBoundary_NoFalsePositive;
// streamdata.Free darf 'stream' nicht als freigegeben markieren
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var stream, streamdata: TMemoryStream;'#13#10+
  'begin'#13#10+
  '  stream     := TMemoryStream.Create;'#13#10+
  '  streamdata := TMemoryStream.Create;'#13#10+
  '  try'#13#10+
  '    stream.Write(buf, 10);'#13#10+
  '  finally'#13#10+
  '    streamdata.Free;'#13#10+
  '  end;'#13#10+
  '  // stream.Free fehlt!'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'streamdata.Free zählt nicht für stream – stream als Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_NestedTryFinally_OuterFinallyFrees_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    try'#13#10+
  '      list.Add(''x'');'#13#10+
  '    except'#13#10+
  '      on E: Exception do LogError(E.Message);'#13#10+
  '    end;'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(list);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Verschachteltes try/except im try/finally – kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_CreateInsideTryBody_FreedInFinally_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    list := TStringList.Create;'#13#10+
  '    list.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(list);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Create im try-Rumpf, Free in finally – kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_PassedToClassCreate_NoFinding;
// SomeOwner.Create(item) – Ownership geht auf SomeOwner über
const SRC =
  'unit t; implementation'#13#10+
  'constructor TOwner.Create(AStream: TMemoryStream);'#13#10+
  'var stream: TMemoryStream;'#13#10+
  'begin'#13#10+
  '  stream := TMemoryStream.Create;'#13#10+
  '  inherited Create(stream, True);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'inherited Create(stream) – Ownership-Transfer, kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_MultipleTypes_EachLeaking_AllReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var sl: TStringList; ms: TMemoryStream; bmp: TBitmap;'#13#10+
  'begin'#13#10+
  '  sl  := TStringList.Create;'#13#10+
  '  ms  := TMemoryStream.Create;'#13#10+
  '  bmp := TBitmap.Create;'#13#10+
  '  sl.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(3, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'Drei verschiedene Typen, alle nie freigegeben – 3 Errors');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_FreeAfterTryFinally_ReportsWarning;
// Free steht nach dem try/finally-Block – zu spät
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list, other: TStringList;'#13#10+
  'begin'#13#10+
  '  list  := TStringList.Create;'#13#10+
  '  other := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    other.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    other.Free;'#13#10+
  '  end;'#13#10+
  '  list.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsWarning),
      'list.Free nach try/finally – Warning');
    Assert.AreEqual<Integer>(0, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'other korrekt freigegeben – kein Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_TwoFreeAndNil_BothVars_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var src, dst: TStringList;'#13#10+
  'begin'#13#10+
  '  src := TStringList.Create;'#13#10+
  '  dst := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    dst.AddStrings(src);'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(src);'#13#10+
  '    FreeAndNil(dst);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'src und dst beide in finally freigegeben – kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_LargeMethod_OneVarLeaks_OneError;
// Methode mit vielen Variablen – nur eine leckt
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var'#13#10+
  '  lines: TStringList;'#13#10+
  '  result1: TStringList;'#13#10+
  '  i: Integer;'#13#10+
  'begin'#13#10+
  '  lines   := TStringList.Create;'#13#10+
  '  result1 := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    for i := 0 to lines.Count - 1 do'#13#10+
  '      result1.Add(lines[i]);'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(lines);'#13#10+
  '    // result1.Free fehlt!'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'result1 nie freigegeben – 1 Error; lines korrekt – kein zweiter');
  finally F.Free; end;
end;
{ ====================================================================
  TTestMemoryLeakAdvanced - 30 Tests fuer Wrong-Free / Pointer-Issues
  ==================================================================== }

// --- A: Wrong-Free / Mismatched Free (10 Tests) ---

procedure TTestMemoryLeakAdvanced.Leak_FreeOnDifferentVarTypo_OriginalLeaks;
// Klassischer Tippfehler: Variable 'list' wird erstellt, 'other' freigegeben.
// 'list' bleibt unfreigegeben - sollte als Error gemeldet werden.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list, other: TStringList;'#13#10+
  'begin'#13#10+
  '  list  := TStringList.Create;'#13#10+
  '  other := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    list.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    other.Free;'#13#10+   // tippfehler: sollte list.Free sein
  '    other.Free;'#13#10+   // double-free auf other (nicht detektiert)
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'list ohne Free trotz Tippfehler -> Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_NilAssignmentInsteadOfFree_ReportsError;
// 'a := nil' gibt das Objekt NICHT frei - klassischer Refactoring-Fehler.
// Detektor sieht keinen Free-Aufruf -> Error.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  list.Add(''x'');'#13#10+
  '  list := nil;'#13#10+   // ohne Free: Speicherleck
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'list := nil ohne vorheriges Free -> Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_FreeBeforeCreate_KnownLimitation_NoFinding;
// Reihenfolge-Bug: Free wird auf nil aufgerufen (no-op), dann Create -
// das neue Objekt wird nie freigegeben. Aktueller String-Detektor
// erkennt das nicht (kein Order-of-Operations-Tracking).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := nil;'#13#10+
  '  list.Free;'#13#10+         // no-op auf nil
  '  list := TStringList.Create;'#13#10+
  '  list.Add(''x'');'#13#10+
  // kein zweites Free
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    // Aktueller String-Detektor sieht 'list.Free' im Body und denkt OK.
    // Das ist eine bekannte Limitation - wir dokumentieren das current
    // behavior: KEINE Befund. TODO: Order-of-Operations-aware Detector.
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Detektor erkennt Free-vor-Create-Reihenfolge nicht (known limitation)');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_FreeOnFieldNotLocalVar_LocalLeaks;
// Lokale 'list' wird erstellt, freigegeben wird das Klassen-Feld 'FList'.
// Lokale Variable bleibt unfreigegeben.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  list.Add(''x'');'#13#10+
  '  FList.Free;'#13#10+        // freed das Field, nicht die Lokale
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'lokale list nicht freigegeben (Field freigegeben statt Local)');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_DoubleFreeAndNilSameVar_NoFinding;
// Defensive double-FreeAndNil ist redundant aber harmlos (zweiter Aufruf
// ist no-op auf nil). Detektor sieht zwei FreeAndNils -> kein Befund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    list.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(list);'#13#10+
  '    FreeAndNil(list);'#13#10+   // redundant aber safe
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'doppeltes FreeAndNil ist safe -> kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_FreeInExceptOnly_KnownLimitation_NoFinding;
// Echtes Bug-Pattern: Free im except-Block aber NICHT im finally.
// Wenn der try-Body normal durchlaeuft, wird nicht freigegeben - Leak.
//
// Detektor-Limitation: SearchFree findet 'list.Free' im except-Block
// ohne Branch-Awareness; HasTryFinallyBlock returnt False fuer reines
// try/except, daher greift der "Free outside finally"-Warning-Pfad
// auch nicht. Resultat: KEIN Befund obwohl Bug.
// TODO: Detector improvement opportunity - Free-im-except-Branch als
// "kein garantiertes Free" werten, oder try/except ohne Free auf
// Normal-Pfad als Warning melden.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    list.Add(''x'');'#13#10+
  '  except'#13#10+
  '    list.Free;'#13#10+         // nur bei Exception
  '    raise;'#13#10+
  '  end;'#13#10+
  // kein Free fuer den normalen Pfad
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Free-nur-im-except wird vom Detektor nicht erkannt (known limitation)');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_FreeAndNilWhitespacePadded_NoFalsePositive;
// FreeAndNil mit Whitespace im Argument: Free(  list  ) - sollte als
// gueltiger Free erkannt werden (kein False-Positive).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    list.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(  list  );'#13#10+   // whitespace gepadded
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'FreeAndNil mit Whitespace soll ohne Befund durchgehen');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_ReassignedThenFree_KnownLimitation_NoFinding;
// Bekannte Limitation: Variable wird zweimal mit Create belegt, nur das
// zweite Free gibt das zweite Objekt frei. Das ERSTE Objekt ist verloren
// (no reference more), aber der String-basierte Detektor zaehlt nur
// "Variablenname hat Free gesehen" -> kein Befund.
// TODO: Detector improvement opportunity - SSA-Form / Definition-Use-
// Tracking wuerde das catchen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+   // erste Instanz
  '  list := TStringList.Create;'#13#10+   // ueberschreibt -> erste Instanz LEAK
  '  try'#13#10+
  '    list.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    list.Free;'#13#10+                  // freed nur die zweite
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Detektor erkennt verlorene-Referenz-Reassignment nicht (known limitation)');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_FreeOnlyInIfBranch_KnownLimitation_NoFinding;
// Free in einem von zwei If-Pfaden -> Pfad-abhaengiger Leak. Statischer
// Detektor sieht "Free existiert irgendwo" und gibt frei -> kein Befund.
// TODO: Detector improvement opportunity - Branch-aware Free-Coverage.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar(cond: Boolean);'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  if cond then'#13#10+
  '    list.Free;'#13#10+               // nur dieser Pfad freed
  '  // else: Leak'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Pfad-abhaengiger Free ist not detected (known limitation)');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_UseAfterFree_KnownLimitation_NoFinding;
// Use-After-Free: list.Free; list.Add('x'); - klassischer UAF-Bug.
// Statischer Detektor erkennt das nicht (kein Lifetime-Tracking).
// Findet aber den Free -> kein Leak-Befund.
// TODO: Separate Use-After-Free-Detector implementieren.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  list.Free;'#13#10+
  '  list.Add(''x'');'#13#10+   // UAF - nicht detected
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Use-After-Free wird vom Leak-Detektor nicht erkannt (known limitation)');
  finally F.Free; end;
end;

// --- B: Pointer / Reference Aliasing (8 Tests) ---

procedure TTestMemoryLeakAdvanced.Leak_AssignedToOtherVarFreedViaOther_OriginalLeaks;
// 'list' wird erstellt, in 'other' kopiert, 'other' wird freigegeben.
// Detektor sieht 'list' nicht in der Free-Suche - 'other' ist eine
// andere Variable. Dokumentiert: list bekommt Leak-Befund.
// (Tatsaechlich gibt es nur EIN Objekt - other.Free freed es. Aber der
// statische Detektor weiss nichts ueber Aliasing.)
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list, other: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  other := list;'#13#10+
  '  other.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    // 'other := list' wird vom Var-zu-Field-Heuristik-Pattern nicht
    // erfasst (other ist kein Feld). Kein Free auf 'list' selbst -> Error.
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'list ohne direktes Free -> Error (Aliasing nicht erkannt)');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_TwoVarsAliasedDoubleFree_KnownLimitation_NoFinding;
// Double-Free via Aliasing: a und b zeigen aufs selbe Objekt, beide rufen
// Free. Detektor sieht beide Variablen-Frees getrennt - 'a' freed, 'b'
// freed (b hatte aber kein Create). Kein Leak-Befund - aber das ist
// auch nicht der Job des Leak-Detektors. TODO: separater Double-Free-
// Detektor.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var a, b: TStringList;'#13#10+
  'begin'#13#10+
  '  a := TStringList.Create;'#13#10+
  '  b := a;'#13#10+
  '  a.Free;'#13#10+
  '  b.Free;'#13#10+   // double-free!
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Double-Free via Aliasing nicht detected (known limitation)');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_NilCheckBeforeFree_NoFinding;
// Defensive Nil-Check vor Free ist gueltiges Idiom, sollte nicht zu
// False-Positive fuehren.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    list.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    if Assigned(list) then list.Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'if Assigned(list) then list.Free ist gueltiges Free');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_AssignedToFFieldWithFPrefix_NoFinding;
// FField := localVar - Var-zu-Feld-Transfer. Recent fix: F-Praefix als
// Feld-Heuristik erkannt -> kein Leak-Befund auf der Lokalen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  FList := list;'#13#10+   // Ownership ans Feld abgegeben
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'list zu FField transferiert -> kein Local-Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_AssignedToSelfDotField_NoFinding;
// Self.FList := localVar - explizites Self-Praefix muss auch erkannt
// werden (recent fix).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  Self.FList := list;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Self.FList := list -> kein Local-Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_AssignedToFieldAsInterface_NoFinding;
// FIfc := localVar as ISomething - Interface-Refcount uebernimmt
// Lifetime. Recent fix erkennt das.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var notifier: TStringList;'#13#10+
  'begin'#13#10+
  '  notifier := TStringList.Create;'#13#10+
  '  FNotifierIfc := notifier as IInterface;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'FField := var as IInterface -> kein Local-Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_BorrowedFromAddCall_NoFinding;
// node := tree.Add(...) - Borrowed-Return aus Tree-/Container-API.
// Recent fix: '.add(' / '.addchild(' / '.addnode(' / '.appendchild('
// als Borrowed-Return erkannt.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var node: TStringList;'#13#10+
  'begin'#13#10+
  '  node := someTree.Add(42, 0, 0);'#13#10+   // borrowed
  '  node.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Borrowed-Return aus .Add(...) ist kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_BorrowedFromAddChildCall_NoFinding;
// item := view.AddChild(name) - VCL TTreeView-Pattern.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var item: TStringList;'#13#10+
  'begin'#13#10+
  '  item := someView.AddChild(''Name'');'#13#10+
  '  item.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Borrowed-Return aus .AddChild(...) ist kein Leak');
  finally F.Free; end;
end;

// --- C: Try/Finally Edge Cases (7 Tests) ---

procedure TTestMemoryLeakAdvanced.Leak_CreateInsideTryBeginFinally_NoFinding;
// Anti-Pattern: Create INNERHALB des try-Bodies. Wenn Create raised,
// laeuft finally trotzdem - aber der spaetere Free auf nil ist no-op.
// Wenn Create durchlief, freed finally korrekt. Statisch: Free im
// finally vorhanden -> kein Befund (technisch korrekt).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    list := TStringList.Create;'#13#10+   // INSIDE try
  '    list.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    list.Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Create-im-try mit Free-im-finally -> kein Leak-Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_NestedTryFinally_BothFreed_NoFinding;
// Verschachtelte try/finally, beide Listen freigegeben.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var outer, inner: TStringList;'#13#10+
  'begin'#13#10+
  '  outer := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    inner := TStringList.Create;'#13#10+
  '    try'#13#10+
  '      inner.Add(''i'');'#13#10+
  '      outer.Add(''o'');'#13#10+
  '    finally'#13#10+
  '      inner.Free;'#13#10+
  '    end;'#13#10+
  '  finally'#13#10+
  '    outer.Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Verschachteltes try/finally, beide freigegeben -> kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_NestedTryFinally_InnerLeaks_OneError;
// Verschachtelt, aber inner wird NICHT freigegeben.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var outer, inner: TStringList;'#13#10+
  'begin'#13#10+
  '  outer := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    inner := TStringList.Create;'#13#10+
  '    inner.Add(''i'');'#13#10+
  // kein Free fuer inner!
  '    outer.Add(''o'');'#13#10+
  '  finally'#13#10+
  '    outer.Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'inner ohne Free -> ein Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_TryExceptNoFinally_LeaksError;
// try/except statt try/finally - keine garantierte Cleanup. Wenn der
// try-Body normal durchlaeuft, gibt es keinen Free.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    list.Add(''x'');'#13#10+
  '  except'#13#10+
  '    on E: Exception do ShowMessage(E.Message);'#13#10+
  '  end;'#13#10+
  // kein Free
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'try/except ohne Free -> Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_MultiCreateOneFinally_AllFreed_NoFinding;
// Drei Variablen, alle in einem finally-Block freigegeben.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var a, b, c: TStringList;'#13#10+
  'begin'#13#10+
  '  a := TStringList.Create;'#13#10+
  '  b := TStringList.Create;'#13#10+
  '  c := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    a.Add(''1''); b.Add(''2''); c.Add(''3'');'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(a);'#13#10+
  '    FreeAndNil(b);'#13#10+
  '    FreeAndNil(c);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'drei Vars alle freigegeben -> kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_MultiCreateOneFinally_LastNotFreed_OneError;
// Drei Variablen, aber 'c' wird vergessen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var a, b, c: TStringList;'#13#10+
  'begin'#13#10+
  '  a := TStringList.Create;'#13#10+
  '  b := TStringList.Create;'#13#10+
  '  c := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    a.Add(''1''); b.Add(''2''); c.Add(''3'');'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(a);'#13#10+
  '    FreeAndNil(b);'#13#10+
  // c vergessen!
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'c ohne Free -> ein Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_FreeAfterTryFinallyBlock_ReportsWarning;
// Free steht NACH dem finally-Block (nicht IM finally). Andere Variablen
// werden korrekt im finally behandelt - die hier ist ausserhalb.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list, other: TStringList;'#13#10+
  'begin'#13#10+
  '  list  := TStringList.Create;'#13#10+
  '  other := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    other.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    other.Free;'#13#10+
  '  end;'#13#10+
  '  list.Free;'#13#10+      // ausserhalb finally
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsWarning),
      'list.Free ausserhalb finally -> Warning');
    Assert.AreEqual<Integer>(0, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'other korrekt im finally -> kein Error');
  finally F.Free; end;
end;

// --- D: Container-Ownership-Whitelist (5 Tests) ---

procedure TTestMemoryLeakAdvanced.Leak_TObjectListAddTypedReceiver_OwnershipRecognized;
// TObjectList ist ownership-aware - .Add(item) uebernimmt Lifecycle.
// Recent fix: Receiver-Type-Lookup erkennt TObjectList-Receiver.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TObjectList<TStringList>; item: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TObjectList<TStringList>.Create(True);'#13#10+
  '  try'#13#10+
  '    item := TStringList.Create;'#13#10+
  '    list.Add(item);'#13#10+         // ownership ans TObjectList
  '  finally'#13#10+
  '    list.Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'TObjectList.Add(item) -> ownership erkannt, kein Leak fuer item');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_TListAddNonOwning_ReportsError;
// TList<T> ist NICHT ownership-aware - .Add(item) speichert nur die
// Referenz. Recent fix: AddReceiverOwnsItems matched 'tlist' nicht
// gegen die OWNING_PREFIXES-Whitelist (TObjectList/Dict/Queue/Stack).
// Da der Receiver-Typ aufloesbar ist (Local-Var TList<TStringList>),
// greift die strikte Pruefung -> kein Ownership-Transfer -> 'item'
// muss als Leak gemeldet werden.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TList<TStringList>; item: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TList<TStringList>.Create;'#13#10+
  '  try'#13#10+
  '    item := TStringList.Create;'#13#10+
  '    list.Add(item);'#13#10+         // TList nimmt KEIN Ownership
  '  finally'#13#10+
  '    list.Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'TList.Add ist kein Ownership-Transfer -> item leak'#13#10+
      'wird gemeldet');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_TObjectDictionaryAdd_OwnershipRecognized;
// TObjectDictionary mit doOwnsValues - .Add(key, value) uebernimmt
// Ownership des Values.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var dict: TObjectDictionary<string, TStringList>; val: TStringList;'#13#10+
  'begin'#13#10+
  '  dict := TObjectDictionary<string, TStringList>.Create([doOwnsValues]);'#13#10+
  '  try'#13#10+
  '    val := TStringList.Create;'#13#10+
  '    dict.Add(''k'', val);'#13#10+
  '  finally'#13#10+
  '    dict.Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'TObjectDictionary.Add(key, val) -> ownership erkannt');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_AddObjectMethod_OwnershipRecognized;
// TStringList.AddObject(text, obj) - klassisches String+Object-Pattern.
// Whitelisted via .addobject(-Branch in IsPassedToOwner.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList; obj: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    obj := TStringList.Create;'#13#10+
  '    list.AddObject(''label'', obj);'#13#10+
  '  finally'#13#10+
  '    list.Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'AddObject(text, obj) wird als Ownership-Transfer erkannt');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_TStackPush_OwnershipRecognized;
// TStack/TObjectStack.Push(item) als Ownership-Transfer.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var stack: TObjectStack<TStringList>; item: TStringList;'#13#10+
  'begin'#13#10+
  '  stack := TObjectStack<TStringList>.Create;'#13#10+
  '  try'#13#10+
  '    item := TStringList.Create;'#13#10+
  '    stack.Push(item);'#13#10+
  '  finally'#13#10+
  '    stack.Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      '.Push(item) wird als Ownership-Transfer erkannt');
  finally F.Free; end;
end;
// =============================================================================
// FieldLeak-Tests (Klassen-Feld-Leaks im Create/Destroy-Pattern)
// =============================================================================

procedure TTestFieldLeak.Field_CreatedAndFreed_NoFinding;
// Standard-Pattern: Konstruktor erzeugt Feld, Destruktor gibt es frei.
const SRC =
  'unit t; interface'#13#10+
  'type TFoo = class'#13#10+
  '  FList: TStringList;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  '  destructor Destroy; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TFoo.Create;'#13#10+
  'begin'#13#10+
  '  inherited;'#13#10+
  '  FList := TStringList.Create;'#13#10+
  'end;'#13#10+
  'destructor TFoo.Destroy;'#13#10+
  'begin'#13#10+
  '  FList.Free;'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak));
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_CreatedNotFreed_ReportsError;
// Klassischer Leak: Konstruktor erzeugt, Destruktor vergessen.
const SRC =
  'unit t; interface'#13#10+
  'type TFoo = class'#13#10+
  '  FList: TStringList;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  '  destructor Destroy; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TFoo.Create;'#13#10+
  'begin'#13#10+
  '  FList := TStringList.Create;'#13#10+
  'end;'#13#10+
  'destructor TFoo.Destroy;'#13#10+
  'begin'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
        'FList wird nie freigegeben - genau ein Field-Leak');
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_FreedViaAlias_NoFinding;
// FP-Fix (Self-Scan 2026-06-21): Alias-Free-Idiom im Destruktor
//   L := FField;  FField := nil;  L.Free;
// (Teardown-Pattern gegen Re-Entrancy, uIDEWatchMode FSubscribers). Das Feld
// WIRD freigegeben - nur ueber die lokale Alias-Var, nicht via FField.Free.
const SRC =
  'unit t; interface'#13#10+
  'type TFoo = class'#13#10+
  '  FList: TStringList;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  '  destructor Destroy; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TFoo.Create;'#13#10+
  'begin'#13#10+
  '  FList := TStringList.Create;'#13#10+
  'end;'#13#10+
  'destructor TFoo.Destroy;'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := FList;'#13#10+
  '  FList := nil;'#13#10+
  '  L.Free;'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'Feld via lokalen Alias freigegeben - kein Leak');
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_CreatedFreedViaFreeAndNil_NoFinding;
// FreeAndNil-Variante muss auch als Free-Aequivalent gelten.
const SRC =
  'unit t; interface'#13#10+
  'type TFoo = class'#13#10+
  '  FStream: TFileStream;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  '  destructor Destroy; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TFoo.Create;'#13#10+
  'begin'#13#10+
  '  FStream := TFileStream.Create(''x'', fmOpenRead);'#13#10+
  'end;'#13#10+
  'destructor TFoo.Destroy;'#13#10+
  'begin'#13#10+
  '  FreeAndNil(FStream);'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak));
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_NoDestructor_ReportsError;
// Klasse hat Konstruktor mit Feld-Erzeugung aber GAR keinen Destruktor.
const SRC =
  'unit t; interface'#13#10+
  'type TFoo = class'#13#10+
  '  FList: TStringList;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TFoo.Create;'#13#10+
  'begin'#13#10+
  '  FList := TStringList.Create;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
        'Ohne Destruktor laeuft FList am Ende leak');
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_NotCreatedInCreate_NoFinding;
// Wenn das Feld im Konstruktor gar nicht zugewiesen wird, ist das ein
// anderes Pattern (vielleicht lazy init, vielleicht gar nicht genutzt) -
// nicht Aufgabe dieses Detektors.
const SRC =
  'unit t; interface'#13#10+
  'type TFoo = class'#13#10+
  '  FList: TStringList;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  '  destructor Destroy; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TFoo.Create;'#13#10+
  'begin'#13#10+
  '  inherited;'#13#10+
  'end;'#13#10+
  'destructor TFoo.Destroy;'#13#10+
  'begin'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak));
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_NonLeakyType_NoFinding;
// Felder von Wert-Typen (Integer, string) interessieren den Detektor nicht.
const SRC =
  'unit t; interface'#13#10+
  'type TFoo = class'#13#10+
  '  FCount: Integer;'#13#10+
  '  FName: string;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TFoo.Create;'#13#10+
  'begin'#13#10+
  '  FCount := 42;'#13#10+
  '  FName := ''hello'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak));
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_SelfQualified_RecognizedAsCreate;
// 'Self.FList := TStringList.Create' soll genauso erkannt werden.
const SRC =
  'unit t; interface'#13#10+
  'type TFoo = class'#13#10+
  '  FList: TStringList;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  '  destructor Destroy; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TFoo.Create;'#13#10+
  'begin'#13#10+
  '  Self.FList := TStringList.Create;'#13#10+
  'end;'#13#10+
  'destructor TFoo.Destroy;'#13#10+
  'begin'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
        'Self-qualifizierte Zuweisung muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_TwoFieldsOneLeaks_OneError;
// Eines von zwei Feldern wird vergessen freizugeben - genau 1 Befund.
const SRC =
  'unit t; interface'#13#10+
  'type TFoo = class'#13#10+
  '  FList:   TStringList;'#13#10+
  '  FStream: TMemoryStream;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  '  destructor Destroy; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TFoo.Create;'#13#10+
  'begin'#13#10+
  '  FList := TStringList.Create;'#13#10+
  '  FStream := TMemoryStream.Create;'#13#10+
  'end;'#13#10+
  'destructor TFoo.Destroy;'#13#10+
  'begin'#13#10+
  '  FList.Free;'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
        'FStream nicht freigegeben, FList schon');
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_FreedViaDestroyMethod_NoFinding;
// .Destroy direkt auf dem Feld muss als Free-Aequivalent gelten.
const SRC =
  'unit t; interface'#13#10+
  'type TFoo = class'#13#10+
  '  FList: TStringList;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  '  destructor Destroy; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TFoo.Create;'#13#10+
  'begin'#13#10+
  '  FList := TStringList.Create;'#13#10+
  'end;'#13#10+
  'destructor TFoo.Destroy;'#13#10+
  'begin'#13#10+
  '  FList.Destroy;'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak));
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_TwoClassesIndependent_OnlyLeakingReported;
// Zwei Klassen in einer Unit - eine korrekt, eine leakt. Es darf nicht
// gemischt werden (z.B. Free in einer Klasse zaehlt nicht fuer die andere).
const SRC =
  'unit t; interface'#13#10+
  'type'#13#10+
  '  TGood = class'#13#10+
  '    FList: TStringList;'#13#10+
  '  public'#13#10+
  '    constructor Create;'#13#10+
  '    destructor Destroy; override;'#13#10+
  '  end;'#13#10+
  '  TBad = class'#13#10+
  '    FList: TStringList;'#13#10+
  '  public'#13#10+
  '    constructor Create;'#13#10+
  '    destructor Destroy; override;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'constructor TGood.Create;'#13#10+
  'begin FList := TStringList.Create; end;'#13#10+
  'destructor TGood.Destroy;'#13#10+
  'begin FList.Free; inherited; end;'#13#10+
  'constructor TBad.Create;'#13#10+
  'begin FList := TStringList.Create; end;'#13#10+
  'destructor TBad.Destroy;'#13#10+
  'begin inherited; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
        'Nur TBad leakt - genau ein Befund');
  finally F.Free; end;
end;

end.
