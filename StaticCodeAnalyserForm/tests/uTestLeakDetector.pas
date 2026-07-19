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
    // Real-World FP-Audit 2026-07-10: CreateAnonymousThread = FreeOnTerminate
    [Test] procedure Leak_AnonymousThreadCreate_NoFinding;
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
    // FP-Gate (borrowed-reference, 2026-07-11): 'X := Func(...)' nur auf
    // konstruktor-artige / lokale-Factory-Callees. Geborgte Getter
    // (CnOtaGetRootComponentFromEditor, Images.Bitmap) duerfen nicht flaggen;
    // konstruktor-artige Namen + bewiesene lokale Factories bleiben Fund.
    [Test] procedure Leak_BorrowedGetterCallWithParens_NoFinding;
    [Test] procedure Leak_BorrowedDottedGetterCallWithParens_NoFinding;
    [Test] procedure Leak_ConstructorLikeCallReturn_NoFree_ReportsWarning;
    [Test] procedure Leak_LocalFactoryCallWithParens_NoFree_ReportsWarning;
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
    // finally-Mis-Attachment-Fix (2026-07-13): Region-Grenze mit nested begin/end
    // im finally darf den Source-Check nicht verwirren -> Free ausserhalb bleibt Warning.
    [Test] procedure Leak_NestedBlockInFinally_FreeOutside_StillWarns;
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
    // FP-Gates (2026-07-04, Real-World-Audit Prio 3): os-handle- und
    // owner-parameter-Gate inkl. TP-Guards (Create(nil) / Expr-Argument).
    [Test] procedure Leak_OsHandleSocketAssign_NoFinding;
    [Test] procedure Leak_OsHandleAcceptWrapperAssign_NoFinding;
    [Test] procedure Leak_CreateWithOwnerApplication_NoFinding;
    [Test] procedure Leak_CreateWithOwnerSelf_NoFinding;
    [Test] procedure Leak_CreateWithNilOwner_ReportsError;
    [Test] procedure Leak_CreateWithSelfDerivedExprArg_ReportsError;
    // TD-1 Inkrement 2c: LeakyClasses aus dem TAnalyzeContext - context-driven
    // Detection, AContext=nil folgt dem uSCAConsts-Global.
    [Test] procedure Leak_ContextLeakyClasses_DrivesDetection;
    // Real-World FP-Repro (TOnLogistManager.GetImportKz): class
    // function, Result-Zuweisung zwischen Create und try, TOracleQuery.Create(nil),
    // Freigabe per FreeAndNil im finally. Paar aus FP-Check (freigegeben -> 0) und
    // TP-Baseline (nicht freigegeben -> 1, beweist dass TOracleQuery im Setup
    // ueberhaupt als leaky geprueft wird).
    [Test] procedure Leak_OracleQuery_ClassFuncFreeAndNilInFinally_NoFinding;
    [Test] procedure Leak_OracleQuery_ClassFuncNoFree_ReportsError;
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
    // FP-Gate Prio 5 (2026-07-06): except-Free-raise-Idiom mit finally anderswo
    [Test] procedure Leak_ExceptFreeRaise_WithUnrelatedFinally_NoWarning;
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
    // Ownership-Sink Core-Audit 2026-07-18: Container-Add im BEDINGUNGS-Kontext.
    [Test] procedure Leak_AddNodeInCondition_OwnershipRecognized;
    // --- SCA001-Gross-Triage 2026-07-18 (free-missed-Bucket, SearchFree-Haertung) ---
    [Test] procedure Leak_DisposeOf_NoFinding;
    [Test] procedure Leak_TypecastFree_NoFinding;
    [Test] procedure Leak_WithDoFree_NoFinding;
    // Werttyp-Return-Gate ('Rueckgabewert'-Pfad)
    [Test] procedure Leak_ValueTypeReturnCall_NoFinding;
    [Test] procedure Leak_ObjectReturnMakeCall_StillReported;   // TP-Gegenprobe
    // --- Inkr.2 (2026-07-19): iface-cast / raise / Instanz-Factory ---
    [Test] procedure Leak_InterfaceHardCast_NoFinding;
    [Test] procedure Leak_AsInterfaceCast_NoFinding;
    [Test] procedure Leak_RaisedVar_NoFinding;
    [Test] procedure Leak_InstanceFactoryCreate_NoFinding;
    [Test] procedure Leak_TypeCreateSuffix_StillError;          // TP-Gegenprobe
    [Test] procedure Leak_MetaclassCreateNew_StillError;        // TP-Gegenprobe
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

uses
  // TD-1 Inkrement 2c: direkter Parser-/Detektor-/Context-Zugriff fuer den
  // context-driven LeakyClasses-Test (die uebrigen Tests laufen ueber
  // TFindingHelper.FindingsOf, das den Detektor mit AContext=nil aufruft).
  uParser2, uAstNode, uAnalyzeContext, uLeakDetector2;

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

procedure TTestMemoryLeak.Leak_ContextLeakyClasses_DrivesDetection;
// TD-1 Inkrement 2c: LeakyClasses wurde vom uSCAConsts-Global in den
// TAnalyzeContext gezogen. Dieser Test beweist beide Richtungen des
// CtxLeakyClasses-Fallbacks:
//   (a) mit gesetztem Ctx.LeakyClasses richtet sich IsLeakyType nach dem
//       Context -> die Custom-Klasse wird als Leak erkannt;
//   (b) bei AContext=nil faellt IsLeakyType auf den Global zurueck, der die
//       Custom-Klasse NICHT kennt -> kein Befund.
// 'TTd1LeakyProbe' steht bewusst in KEINER Default-LeakyClasses-Liste, damit
// (b) unabhaengig von der globalen Konfiguration 0 liefert.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var thing: TTd1LeakyProbe;'#13#10+
  'begin'#13#10+
  '  thing := TTd1LeakyProbe.Create;'#13#10+
  '  thing.DoWork;'#13#10+
  'end;';
var
  Parser  : TParser2;
  Root    : TAstNode;
  Ctx     : TAnalyzeContext;
  FCtx    : TObjectList<TLeakFinding>;
  FGlobal : TObjectList<TLeakFinding>;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    try
      // (a) Context kennt die Custom-Klasse -> Detection folgt dem Context.
      Ctx  := TAnalyzeContext.Create;
      FCtx := TObjectList<TLeakFinding>.Create(True);
      try
        Ctx.LeakyClasses.Add('TTd1LeakyProbe');
        TLeakDetector2.AnalyzeUnit(Root, 'sample.pas', FCtx, Ctx);
        Assert.AreEqual<Integer>(1, TFindingHelper.Count(FCtx, fkMemoryLeak),
          'Custom-Klasse in Ctx.LeakyClasses -> Leak-Detection folgt dem Context');
      finally
        FCtx.Free;
        Ctx.Free;
      end;

      // (b) AContext=nil -> Global-Fallback (kennt die Custom-Klasse nicht).
      FGlobal := TObjectList<TLeakFinding>.Create(True);
      try
        TLeakDetector2.AnalyzeUnit(Root, 'sample.pas', FGlobal);
        Assert.AreEqual<Integer>(0, TFindingHelper.Count(FGlobal, fkMemoryLeak),
          'AContext=nil folgt dem Global (ohne Custom-Klasse) -> kein Befund');
      finally
        FGlobal.Free;
      end;
    finally
      Root.Free;
    end;
  finally
    Parser.Free;
  end;
end;

//   class function ...: string;
//   var mQuery: TOracleQuery;
//   begin
//     mQuery := TOracleQuery.Create(nil);   // <-- Fund-Zeile
//     Result := 'N';
//     try ... finally FreeAndNil(mQuery); end;
//   end;
// TOracleQuery ist keine Default-LeakyClass -> per Ctx.LeakyClasses.Add
// aktiviert, sonst wuerde der FP-Check trivial (weil ungeprueft) 0 liefern.
const
  ORACLE_SRC_HEAD =
    'unit t; implementation'#13#10+
    'class function TOnLogistManager.GetImportKz(aInvoiceid: string): string;'#13#10+
    'var mQuery: TOracleQuery;'#13#10+
    'begin'#13#10+
    '  mQuery := TOracleQuery.Create(nil);'#13#10+
    '  Result := ''N'';'#13#10;

procedure TTestMemoryLeak.Leak_OracleQuery_ClassFuncFreeAndNilInFinally_NoFinding;
const SRC = ORACLE_SRC_HEAD +
  '  try'#13#10+
  '    mQuery.Session := MainSessionData.OracleSession;'#13#10+
  '    mQuery.SQL.Text := ''SELECT einlesenkz FROM onlogist_import'';'#13#10+
  '    mQuery.Execute;'#13#10+
  '    if not mQuery.Eof then Result := mQuery.Field(0).AsString;'#13#10+
  '  finally'#13#10+
  '    FreeAndNil(mQuery);'#13#10+
  '  end;'#13#10+
  'end;';
var
  Parser : TParser2;
  Root   : TAstNode;
  Ctx    : TAnalyzeContext;
  F      : TObjectList<TLeakFinding>;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    Ctx  := TAnalyzeContext.Create;
    F    := TObjectList<TLeakFinding>.Create(True);
    try
      Ctx.LeakyClasses.Add('TOracleQuery');
      TLeakDetector2.AnalyzeUnit(Root, 'sample.pas', F, Ctx);
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
        'Create(nil) vor try, FreeAndNil im finally -> kein Leak (FP-Regression)');
    finally
      F.Free; Ctx.Free; Root.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTestMemoryLeak.Leak_OracleQuery_ClassFuncNoFree_ReportsError;
const SRC = ORACLE_SRC_HEAD +
  '  mQuery.Session := MainSessionData.OracleSession;'#13#10+
  '  mQuery.SQL.Text := ''SELECT einlesenkz FROM onlogist_import'';'#13#10+
  '  mQuery.Execute;'#13#10+
  '  if not mQuery.Eof then Result := mQuery.Field(0).AsString;'#13#10+
  'end;';
var
  Parser : TParser2;
  Root   : TAstNode;
  Ctx    : TAnalyzeContext;
  F      : TObjectList<TLeakFinding>;
begin
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(SRC);
    Ctx  := TAnalyzeContext.Create;
    F    := TObjectList<TLeakFinding>.Create(True);
    try
      Ctx.LeakyClasses.Add('TOracleQuery');
      TLeakDetector2.AnalyzeUnit(Root, 'sample.pas', F, Ctx);
      Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
        'TOracleQuery ohne Free -> Error (beweist: Klasse wird im Setup geprueft)');
    finally
      F.Free; Ctx.Free; Root.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTestMemoryLeak.Leak_AnonymousThreadCreate_NoFinding;
// FP-Fix Real-World-FP-Audit 2026-07-10: 'th := TThread.CreateAnonymousThread(...)'
// liefert einen FreeOnTerminate-Thread (self-freeing); ein try/finally-Free waere
// ein Use-after-free. TThread ist Default-Leaky -> vorher als Leak gemeldet.
const SRC =
  'unit t; implementation'#13#10+
  'procedure P;'#13#10+
  'var th: TThread;'#13#10+
  'begin'#13#10+
  '  th := TThread.CreateAnonymousThread(nil);'#13#10+
  '  th.Start;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'CreateAnonymousThread = FreeOnTerminate, kein Leak');
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

procedure TTestMemoryLeak.Leak_NestedBlockInFinally_FreeOutside_StillWarns;
// finally-Mis-Attachment-Fix TP-Gegenprobe: der neue Source-basierte finally-
// Region-Check muss die try-Region trotz nested 'begin/end' IM finally korrekt
// begrenzen. 'list.Free' steht NACH dem try/finally -> ausserhalb der Region ->
// muss weiter Warning liefern (der Fix darf nicht ueber die Region hinaus-
// suppressen). 'other' wird im finally freigegeben -> kein Fund.
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
  '    if other.Count > 0 then begin other.Free; end;'#13#10+
  '  end;'#13#10+
  '  list.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsWarning),
      'list.Free ausserhalb finally (mit nested begin/end im finally) bleibt Warning');
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
  '  list := MakeList();'#13#10+
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
  '  list := MakeList();'#13#10+
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

procedure TTestMemoryLeak.Leak_BorrowedGetterCallWithParens_NoFinding;
// FP-Gate (borrowed-reference, 2026-07-11, Real-World-Audit): cnwizards
// 'Keys := CnOtaGetVersionInfoKeys(FProject)' bzw. 'Root :=
// CnOtaGetRootComponentFromEditor(...)'. Der Callee ist ein GETTER (liefert
// ein IDE-eigenes, geborgtes Objekt), kein Konstruktor. Die "Rueckgabewert"-
// Heuristik meldete das frueher als Leak; jetzt geben nur konstruktor-artige
// Callees Ownership ab -> kein Befund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var keys: TStringList;'#13#10+
  'begin'#13#10+
  '  keys := CnOtaGetVersionInfoKeys(FProject);'#13#10+
  '  keys.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'geborgter Getter-Aufruf (kein Konstruktor) ist kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_BorrowedDottedGetterCallWithParens_NoFinding;
// FP-Gate (borrowed-reference, 2026-07-11): Alcinoe ALFmxImgList
// 'aBitmap := Images.Bitmap(aSize, AIndex)' - ImageList-Cache-Getter, geborgt
// (der Quell-Kommentar dort warnt sogar, dass die ImageList das Bitmap
// zerstoeren kann). Callee 'Bitmap' ist kein Konstruktor -> kein Befund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var bmp: TBitmap;'#13#10+
  'begin'#13#10+
  '  bmp := Images.Bitmap(ASize, AIndex);'#13#10+
  '  bmp.SaveToFile(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'dotted Getter Images.Bitmap(...) ist geborgt, kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_ConstructorLikeCallReturn_NoFree_ReportsWarning;
// TP-Guard fuer das borrowed-reference-Gate (2026-07-11): ein konstruktor-
// artiger Callee (Wurzel Make/New/Clone/Create/Acquire) uebergibt Ownership.
// 'list := MakeList()' ohne Free bleibt ein Leak-Befund (Rueckgabewert) -
// die FP-Reduktion darf konstruktor-artige Factory-Returns nicht schlucken.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := MakeList();'#13#10+
  '  list.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
      'konstruktor-artiger Callee (MakeList) ohne Free bleibt ein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_LocalFactoryCallWithParens_NoFree_ReportsWarning;
// TP-Guard: eine bewiesene lokale Factory DERSELBEN Klasse, MIT Klammern
// aufgerufen ('list := BuildList()' mit 'Result := TStringList.Create' im
// Body), ist Ownership-Transfer. Der IsLocalFactory-Fallback haelt die
// Erkennung trotz nicht-konstruktor-artigem Namen ('Build...') aufrecht.
const SRC =
  'unit t; implementation'#13#10+
  'function TFoo.BuildList: TStringList;'#13#10+
  'begin'#13#10+
  '  Result := TStringList.Create;'#13#10+
  'end;'#13#10+
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
    Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
      'lokale Factory mit Klammern (BuildList) ohne Free bleibt ein Leak');
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

procedure TTestMemoryLeak.Leak_OsHandleSocketAssign_NoFinding;
// FP-Gate (2026-07-04): os-handle - socket() liefert ein Integer-OS-Handle,
// kein Delphi-Objekt; Freigabe laeuft ueber closesocket, nicht ueber Free.
// Real-World: mormot.net.sock.pas:2835/3106/3122,
// DMVC.Expert.Forms.NewProjectWizard.pas:1039.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.TestPort;'#13#10+
  'var s: TSocket;'#13#10+
  'begin'#13#10+
  '  s := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);'#13#10+
  '  closesocket(s);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'socket() ist eine OS-Handle-API, keine Objekt-Konstruktion - kein SCA001');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_OsHandleAcceptWrapperAssign_NoFinding;
// FP-Gate (2026-07-04): os-handle - doaccept() (mORMot-Wrapper um accept())
// liefert ebenfalls ein OS-Handle. Real-World: mormot.net.sock.pas:3230.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.AcceptClient;'#13#10+
  'var sock: TSocket;'#13#10+
  'begin'#13#10+
  '  sock := doaccept(FListener, FAddr, True);'#13#10+
  '  UseSocket(sock);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'doaccept() ist eine OS-Handle-API, keine Objekt-Konstruktion - kein SCA001');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_CreateWithOwnerApplication_NoFinding;
// FP-Gate (2026-07-04): owner-parameter - Create(Application) folgt der
// TComponent-Owner-Konvention: die Application gibt das Objekt in ihrem
// Destroy ueber die Components[]-Liste frei -> kein Leak.
// Real-World: doublecmd foptionshotkeys.pas:687
// 'CommandsForm := CommandsFormClass.Create(Application);'.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.ShowOptions;'#13#10+
  'var frm: TComponent;'#13#10+
  'begin'#13#10+
  '  frm := TOptionsForm.Create(Application);'#13#10+
  '  frm.Tag := 1;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Create(Application) uebergibt Ownership an den Owner - kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_CreateWithOwnerSelf_NoFinding;
// FP-Gate (2026-07-04): owner-parameter - Create(Self) im Form-/Frame-Code:
// Self (der umgebende TComponent) uebernimmt die Freigabe.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.InitUi;'#13#10+
  'var tmr: TTimer;'#13#10+
  'begin'#13#10+
  '  tmr := TTimer.Create(Self);'#13#10+
  '  tmr.Enabled := True;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Create(Self) uebergibt Ownership an den Owner - kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_CreateWithNilOwner_ReportsError;
// TP-Guard fuer das owner-parameter-Gate (2026-07-04): Create(nil) hat
// KEINEN Owner - der Aufrufer muss selbst freigeben. Entspricht dem
// Korpus-TP sample-dunitx-belege_ui/BelegeUnit.pas:52
// 'SQLQuery := TSQLQuery.Create(nil);' ohne Free.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.LoadFromDB;'#13#10+
  'var q: TSQLQuery;'#13#10+
  'begin'#13#10+
  '  q := TSQLQuery.Create(nil);'#13#10+
  '  q.Open;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'Create(nil) ohne Free muss weiterhin als Leak (lsError) gemeldet werden');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_CreateWithSelfDerivedExprArg_ReportsError;
// TP-Guard fuer das owner-parameter-Gate (2026-07-04): das Gate verlangt,
// dass das GESAMTE Argument exakt ein Owner-Bezeichner ist. Ein Ausdruck,
// der 'Self' nur enthaelt, ist kein Owner. Entspricht dem Korpus-TP
// CodeReader.ZXing...GenericGF.pas:642
// 'lResult := TStringBuilder.Create((8 * self.degree));' ohne Free.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Dump;'#13#10+
  'var sb: TStringBuilder;'#13#10+
  'begin'#13#10+
  '  sb := TStringBuilder.Create(8 * Self.Degree);'#13#10+
  '  sb.Append(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'Create(8 * Self.Degree) ist kein Owner-Argument - Leak bleibt gemeldet');
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
  '  list := MakeList();'#13#10+
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

procedure TTestMemoryLeakAdvanced.Leak_ExceptFreeRaise_WithUnrelatedFinally_NoWarning;
// FP-Gate Prio 5 (Real-World-Audit 2026-07-04, z.B. MVCFramework.Middleware.
// Compression.pas:138): b wird auf dem Erfolgspfad per Ownership-Transfer
// weitergereicht (Setter - KEIN Add-Muster, IsPassedToOwner greift bewusst
// nicht) und im re-raisenden except-Handler freigegeben. Weil die UNABHAENGIGE
// Variable a ein finally hat (HasFinally=True), meldete der Detektor frueher
// faelschlich "Free ausserhalb finally" (lsWarning) fuer b. except-Free-raise
// ist Ausnahme-Pfad-Cleanup - aequivalent zu finally -> kein Befund.
// Gegenstueck zu Leak_FreeInExceptOnly_KnownLimitation (dort ohne finally ->
// schon vorher 0); zusammen decken sie beide HasFinally-Zweige ab.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var'#13#10+
  '  a, b: TStringList;'#13#10+
  'begin'#13#10+
  '  a := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    a.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    a.Free;'#13#10+
  '  end;'#13#10+
  '  b := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    Consumer.SetContentStream(b);'#13#10+
  '  except'#13#10+
  '    b.Free;'#13#10+
  '    raise;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'except-Free-raise = geschuetzt wie finally; das finally von a darf ' +
      'keinen lsWarning-FP fuer b ausloesen');
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

procedure TTestMemoryLeakAdvanced.Leak_AddNodeInCondition_OwnershipRecognized;
// Ownership-Sink Core-Audit 2026-07-18: das Item wird in einer if-BEDINGUNG an
// eine ownership-uebernehmende Tree-Add-Methode uebergeben. Calls INNERHALB einer
// Bedingung sind keine nkCall-Knoten (Flachtext in nkIfStmt.TypeRef), daher
// verpasste der nkCall-Arg-Guard sie -> CondPassesToOwnerAdd deckt sie ab. Bei
// Erfolg besitzt FTree das Item, bei Misserfolg wird es freigegeben - kein Leak.
// FTree ist ein Feld (Typ unaufloesbar) -> permissive Receiver-Ownership wie beim
// bestehenden .AddNode-Arg-Fall im Statement-Kontext. Geerdet in
// Alcinoe/ALWebSpider Unit1.pas (FPageNotYetDownloadedBinTree.AddNode).
// BEWUSST ohne Free und ohne try/finally: so kann NUR IsPassedToOwner (via
// CondPassesToOwnerAdd) den Befund unterdruecken -> der Test isoliert den Fix
// (ohne ihn wuerde SCA001 hier feuern). Der Call steht in der if-BEDINGUNG,
// deren TypeRef der Parser space-separiert ablegt ('ftree . addnode ( anode )') -
// die Whitespace-Kompaktierung im Detektor deckt genau das ab.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var aNode: TStringList;'#13#10+
  'begin'#13#10+
  '  aNode := TStringList.Create;'#13#10+
  '  if FTree.AddNode(aNode) then Exit;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Item in if-Bedingung an Tree-AddNode uebergeben (Ownership-Transfer) - kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_DisposeOf_NoFinding;
// SCA001-Gross-Triage 2026-07-18 (free-missed 22/101): '.DisposeOf' ist das
// ARC-/NextGen-Idiom (auf Classic Alias fuer Free) - SearchFree kannte es
// nicht -> "nie freigegeben"-FP (FMX LBitmap.DisposeOf / Str.DisposeOf).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  list.Add(''x'');'#13#10+
  '  list.DisposeOf;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'DisposeOf ist eine Freigabe - kein "nie freigegeben"-Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_TypecastFree_NoFinding;
// free-missed: 'TStringList(list).Free' - der Cast schiebt ')' zwischen
// Var-Namen und '.free' -> das 'varname.free'-Muster verfehlte es (JvUIB
// TStringList(FParams).Free im Destroy).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TObject;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  TStringList(list).Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'Typecast-Free ist eine Freigabe - kein "nie freigegeben"-Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_WithDoFree_NoFinding;
// free-missed: 'with bm do begin ...; Free; end' - das bare Free im with-Body
// meint das with-Objekt; der Parser haengt den Body als Children unter das
// with-nkCall(bm) (DropTarget 'with bm do ... free').
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var bm: TBitmap;'#13#10+
  'begin'#13#10+
  '  bm := TBitmap.Create;'#13#10+
  '  with bm do'#13#10+
  '  begin'#13#10+
  '    SetSize(4, 4);'#13#10+
  '    Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'bare Free im with-Body des Objekts ist eine Freigabe');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_ValueTypeReturnCall_NoFinding;
// Werttyp-Return-Gate ('other'-Bucket, 3x MakePath): der 'Rueckgabewert'-Pfad
// meldete Calls von in-unit-Funktionen mit WERT-Return (TFileName=String).
// Werttypen koennen nie leaken -> Signatur-Lookup unterdrueckt den Fund.
// (Local bewusst leaky-typisiert, damit der Pfad ueberhaupt erreicht wird.)
const SRC =
  'unit t; implementation'#13#10+
  'function MakePath(const A: string): TFileName;'#13#10+
  'begin Result := A; end;'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := MakePath(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'in-unit-Funktion mit Werttyp-Return kann nicht leaken - kein Fund');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_ObjectReturnMakeCall_StillReported;
// TP-Gegenprobe zum Werttyp-Gate: MakeList liefert laut in-unit-Signatur ein
// OBJEKT (TStringList) - der 'Rueckgabewert'-Fund muss bleiben.
const SRC =
  'unit t; implementation'#13#10+
  'function MakeList(N: Integer): TStringList;'#13#10+
  'begin Result := TStringList.Create; end;'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := MakeList(5);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
      'Objekt-Return-Factory ohne Free bleibt ein Fund');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_InterfaceHardCast_NoFinding;
// Inkr.2 (iface-cast 15/101): 'IBoxedValue(b)' - Interface-Hard-Cast gibt das
// Objekt an die Refcount ab; der letzte Release gibt es frei. I-Konvention im
// Original-Case ('I'+Grossbuchstabe; 'IntToStr(b)' matcht NICHT).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var b: TStringList; v: IBoxedValue;'#13#10+
  'begin'#13#10+
  '  b := TStringList.Create;'#13#10+
  '  v := IBoxedValue(b);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Interface-Hard-Cast uebergibt an Refcount - kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_AsInterfaceCast_NoFinding;
// Inkr.2: 'obj as IMyIntf' - as-Cast an Interface-Refcount.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var obj: TStringList; Intf: IMyIntf;'#13#10+
  'begin'#13#10+
  '  obj := TStringList.Create;'#13#10+
  '  Intf := obj as IMyIntf;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'as-Interface-Cast uebergibt an Refcount - kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_RaisedVar_NoFinding;
// Inkr.2 (Batch 8 'raise LException'): 'raise E' uebernimmt Ownership -
// die RTL gibt das Objekt im Exception-Handler frei.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var E: TStringList;'#13#10+
  'begin'#13#10+
  '  E := TStringList.Create;'#13#10+
  '  raise E;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'geraiste Var gehoert der RTL - kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_InstanceFactoryCreate_NoFinding;
// Inkr.2 (factory 13/101): 'mgr.CreateOptionFromFile(..)' - Receiver 'mgr' ist
// eine lokale INSTANZ (kein Typname, TypeLow endet nicht auf 'class') -> das
// ist eine Factory-Methode, keine direkte Konstruktion; Result fremd-owned
// (Triage 13/13). Kein lsError.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var mgr: TManager; opt: TStringList;'#13#10+
  'begin'#13#10+
  '  mgr := GetManager;'#13#10+
  '  opt := mgr.CreateOptionFromFile(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'Instanz-Factory-CreateXxx ist keine direkte Konstruktion - kein lsError');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_TypeCreateSuffix_StillError;
// TP-Gegenprobe: 'TSQLQuery.CreateNew(nil)' - Receiver ist ein TYPNAME (keine
// Local/kein Param) -> direkte Konstruktion, Create(nil) ohne Free = Leak.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var q: TSQLQuery;'#13#10+
  'begin'#13#10+
  '  q := TSQLQuery.CreateNew(nil);'#13#10+
  '  q.Open;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.CountSev(F, fkMemoryLeak, lsError) >= 1,
      'Typname.CreateNew ohne Free bleibt ein Leak-Error');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_MetaclassCreateNew_StillError;
// TP-Gegenprobe Metaclass: Receiver 'C' IST eine Local, aber ihr Typ endet auf
// 'class' (TFormClass-Konvention) -> C.CreateNew ist eine ECHTE Konstruktion
// ueber die Metaklasse -> Fund bleibt.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var C: TFormClass; f: TStringList;'#13#10+
  'begin'#13#10+
  '  C := GetFormClass;'#13#10+
  '  f := C.CreateNew(nil);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.CountSev(F, fkMemoryLeak, lsError) >= 1,
      'Metaclass-Local.CreateNew bleibt eine echte Konstruktion - Fund bleibt');
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
