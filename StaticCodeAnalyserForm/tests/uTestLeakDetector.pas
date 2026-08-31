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
    // --- Ist-Messung 2026-08-05: Ctor-Argument in einer Zuweisungs-RHS ---
    [Test] procedure Leak_CtorArgInAssignRhs_OwnershipRecognized;
    [Test] procedure Leak_CtorArgStandaloneCall_OwnershipRecognized;
    [Test] procedure Leak_CtorArgIsMemberOfVar_StillReported;
    [Test] procedure Leak_PlainCallArgInAssignRhs_StillReported;
    [Test] procedure Leak_BareFileNameNoDirSegments_StillReported;
    [Test] procedure Leak_TestDirSegment_Suppressed;
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
    // --- Inkr.3 (2026-07-19): Custom-Add-/Insert-/Put-Familie ---
    [Test] procedure Leak_CustomAddMethod_OwnershipRecognized;
    [Test] procedure Leak_InsertNodeCastArg_OwnershipRecognized;
    [Test] procedure Leak_AddressCall_StillReported;            // TP-Gegenprobe
    // --- 30%-Real-World-Audit 2026-07-31, FP-Klasse 1: Ownership-Transfer an
    //     besitzende Senken (letzter Use = Uebergabe an Add/Insert/Append/
    //     Push/Enqueue bzw. an einen fremden Konstruktor). ---
    [Test] procedure Leak_SinkBareAddCall_LastUse_NoFinding;
    [Test] procedure Leak_SinkAddPairCamelInAssignRhs_LastUse_NoFinding;
    [Test] procedure Leak_SinkEnqueueCamel_LastUse_NoFinding;
    [Test] procedure Leak_SinkAddInAssignRhs_LastUse_NoFinding;
    [Test] procedure Leak_SinkCtorArgInAssignRhs_LastUse_NoFinding;
    [Test] procedure Leak_SinkAddThenUsedAgain_StillReported;      // TP-Gegenprobe
    // Review 2026-07-31: Receiver-Policy bleibt strikt (Whitelist), sonst
    // haetten TFPList/TStringBuilder/TCustomImageList-Empfaenger echte Leaks
    // stillgestellt.
    [Test] procedure Leak_SinkResolvedNonOwningReceiver_StillReported;
    [Test] procedure Leak_SinkHelperCallArgNotUnwrapped_StillReported;
    // --- Drop-Sampling after119->after120 (2026-07-31): TP-Verlust-Cluster
    //     "gepunkteter Empfaenger auf nicht-besitzendem Container-Zugang".
    //     Die beiden ersten Tests sind ohne die Zusatzhuerde ROT. ---
    [Test] procedure Leak_SinkDottedItemsAddObject_StillReported;     // TP JvAlarmsForm:106
    [Test] procedure Leak_SinkDottedItemsAddChildObject_StillReported;// TP ftreeviewmenu:230
    // Gegenproben: diese Drops muessen gedroppt BLEIBEN.
    [Test] procedure Leak_SinkDottedItemsPlainAdd_NoFinding;          // mORMot ui.report:5191
    [Test] procedure Leak_SinkBareAddObjectSelfCollection_NoFinding;  // GX_ToDo:265
    [Test] procedure Leak_SinkBareFieldAddObject_NoFinding;           // JvSAL:608
    [Test] procedure Leak_SinkResolvedOwningAccessorName_NoFinding;
    [Test] procedure Leak_TpPenAssignedBack_StillReported;         // TP JvUtils.pas:1854
    [Test] procedure Leak_TpStringsUsedAfterForeignAdd_StillReported; // TP Indy:88
    // --- FP-Klasse 2: TComponent-/Owner-Ownership + Factory-Rueckgaben ---
    [Test] procedure Leak_ComponentOwnerCreate_DottedFieldArg_NoFinding;
    [Test] procedure Leak_ComponentOwnerCreate_TypeIndexProven_NoFinding;
    [Test] procedure Leak_DataClassDottedArg_StillReported;        // TP-Gegenprobe
    // Review 2026-07-31: dotted Argument OHNE Komponenten-Konvention ist kein
    // Owner-Nachweis mehr.
    [Test] procedure Leak_DottedNonComponentArg_StillReported;     // TP-Gegenprobe
    [Test] procedure Leak_FactoryStoresResultInContainer_NoFinding;
    [Test] procedure Leak_FactoryReturnsOwnership_StillReported;   // TP-Gegenprobe
    // Review 2026-07-31: Callee-Aufloesung ist klassen-qualifiziert.
    [Test] procedure Leak_FactoryHomonymInForeignClass_StillReported;
    // --- Parser-Gate-Backlog 2026-07-31 (Konzept 4e/1+4e/2) -------------
    // (a) Der Callee-Ctor DERSELBEN Unit haengt sich per '<Param>.Add(Self)'
    //     in eine besitzende Liste des uebergebenen Parents (jvcl
    //     JvInspector.pas 4130/11876).
    [Test] procedure Leak_CtorRegistersSelfWithParent_NoFinding;
    [Test] procedure Leak_CtorDoesNotRegisterSelf_StillReported;   // TP-Gegenprobe
    // Review-Blocker 1 (2026-07-31): Overload-Mehrdeutigkeit darf NICHT zum
    // Vorfahren klettern - sonst entscheidet der Ctor des Vorfahren ueber eine
    // Ueberladung, die er nicht kennt.
    [Test] procedure Leak_CtorOverloadsAncestorRegisters_StillReported;
    [Test] procedure Leak_CtorUniqueOwnRegisters_NoFinding;        // Gegenprobe
    // Review-Blocker 2 (2026-07-31): 'Self.<Member>' ist KEINE
    // Selbstregistrierung - uebergeben wird ein Feld, nicht Self.
    [Test] procedure Leak_CtorAddsSelfMemberNotSelf_StillReported;
    [Test] procedure Leak_CtorRegistersSelfViaTypecast_NoFinding;  // Gegenprobe
    [Test] procedure Leak_CtorRegistersSelfAsTrailingArg_NoFinding;// Gegenprobe
    // --- Autopsie 2026-08-26, Quick Wins diesseits K1 -------------------
    [Test] procedure Leak_AnonProcLiteral_NoFinding;
    [Test] procedure Leak_RttiAsObjectChain_NoFinding;
    [Test] procedure Leak_FluentCreateChain_StillReported;        // TP-Gegenprobe
    [Test] procedure Leak_CtorSetsFreeOnTerminate_NoFinding;
    [Test] procedure Leak_CtorOverloadsFreeOnTerminate_StillReported;
    // (b) REGRESSIONSFALL: Empfaengertyp ist ein Unit-Alias bzw. eine
    //     Ableitung eines besitzenden Containers ('TPeople =
    //     TObjectList<TPerson>', delphimvcframework DAL.pas:136).
    [Test] procedure Leak_AddReceiverIsUnitAliasOfObjectList_NoFinding;
    [Test] procedure Leak_AddReceiverIsUnitClassOfObjectList_NoFinding;
    [Test] procedure Leak_AddReceiverIsUnitAliasOfTList_StillReported; // TP-Gegenprobe
    // ---- out/var-Parameter als Rueckgabeweg (T3-Backlog, 2026-08-01) ------
    [Test] procedure Leak_OutParamReturn_NoFinding;
    [Test] procedure Leak_VarParamIndexedReturn_NoFinding;
    [Test] procedure Leak_ConstParamAssign_StillReported;
    [Test] procedure Leak_PlainLocalAssign_StillReported;
    // Indiziertes Ziel in fremdem Speicher (2026-08-18):
    // groesste FP-Klasse von SCA001 laut beiden Audits.
    [Test] procedure Leak_IndexedForeignField_OwnershipRecognized;
    [Test] procedure Leak_IndexedSelfProperty_OwnershipRecognized;
    [Test] procedure Leak_IndexedLocalArray_StillReported;
    // Empfaenger-Veto: Objects/Items/Lines besitzen NICHT.
    [Test] procedure Leak_IndexedNonOwningAccessor_StillReported;
    // Form-Verankerung (Review-Blocker 2026-08-18): drei Formen, die
    // die erste Gate-Fassung faelschlich schluckte.
    [Test] procedure Leak_IndexedElementProperty_StillReported;
    [Test] procedure Leak_IndexedElementNonOwning_StillReported;
    [Test] procedure Leak_IndexedUnqualifiedNonOwning_StillReported;
    // Feld-Transfer-Zweig (Review-Major 2026-08-19): das F-Praefix darf
    // die indizierte Kette nicht mehr am Veto vorbeischleusen.
    [Test] procedure Leak_FieldRootedIndexedNonOwning_StillReported;
    [Test] procedure Leak_BareFieldAssignment_StillExempt;
    // KLASSE F der Vollzaehlung: unit-lokaler Callee uebernimmt (30.08.)
    [Test] procedure LocalCalleeTakesOwnership_NotReported;
    [Test] procedure LocalCalleeOnlyReads_StillReported;
    [Test] procedure LocalCalleeTwoParams_StillReported;
    [Test] procedure LocalCalleeArgCountMismatch_StillReported;
    [Test] procedure LocalCalleeForeignReceiver_StillReported;
    // KLASSE D der Vollzaehlung: Owner-Argument ueber den TYP (30.08.)
    [Test] procedure OwnerArgIsComponentTyped_NotReported;
    [Test] procedure OwnerArgIsNotComponentTyped_StillReported;
    [Test] procedure OwnerArgComponentButCreatedIsTObject_StillReported;
    // KLASSE A: TJSONObject.AddPair uebernimmt - typgebunden (30.08.)
    [Test] procedure JsonAddPairTakesOwnership_NotReported;
    [Test] procedure AddPairOnForeignTypeIsNoTransfer_StillReported;
    [Test] procedure JsonArrayAddTakesOwnership_NotReported;
    [Test] procedure PlainListAddIsNoTransfer_StillReported;
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
    // --- 30%-Real-World-Audit 2026-07-31, FP-Klasse 3: indirekte Dtor-Freigabe
    //     (Owner = Schwester-Feld / Free in einer Helper-Methode). ---
    [Test] procedure Field_OwnerIsSiblingFieldFreedInDestroy_NoFinding;
    [Test] procedure Field_OwnerFieldNotFreed_StillReported;      // TP-Gegenprobe
    [Test] procedure Field_FreedViaOwnHelperMethod_NoFinding;
    [Test] procedure Field_HelperDoesNotFree_StillReported;       // TP-Gegenprobe
    [Test] procedure Field_TpNoDestructorAtAll_StillReported;     // TP jvTracker.pas:68
    // --- Pre-Build-Review 2026-07-31 (Fund uFieldLeak.pas:333): das
    //     Schwester-Feld-Owner-Gate braucht die Datenklassen-Sperrliste des
    //     Schwestergates uLeakDetector2.IsComponentOwnerCreate. Konsumenten
    //     (Reader/Writer/Zip) besitzen ihren Quellstream NICHT. ---
    [Test] procedure Field_ConsumerOverSiblingStream_StillReported;
    [Test] procedure Field_OwnerFieldIsDataClass_StillReported;
    // --- Parser-Gate-Backlog 2026-07-31 (Konzept 4e/1) -------------------
    // (a) Freigabe in BeforeDestruction statt Destroy (jvcl JvInspector).
    [Test] procedure Field_FreedInBeforeDestruction_NoFinding;
    [Test] procedure Field_BeforeDestructionFreesOther_StillReported; // TP-Gegenprobe
    // (b) KLASSE L: Freigabe im OnDestroy-Event, kein Destruktor (30.08.)
    [Test] procedure Field_FreedInOnDestroyHandler_NoFinding;
    [Test] procedure Field_DestroyMethodWithoutEventSignature_StillReported;
    // (c) BESTANDSFEHLER: class destructor traegt TypeRef
    //     "destructor;class" und wurde nie gefunden (30.08.)
    [Test] procedure Field_FreedInClassDestructor_NoFinding;
    [Test] procedure Field_ClassDestructorFreesOther_StillReported;
    // (b) Transitive Component-Ownership ohne Destruktor (jvcl
    //     JvGammaPanel 61/63/64, JvCombobox 261).
    [Test] procedure Field_OwnerChainReachesSelf_NoFinding;
    [Test] procedure Field_OwnerChainEndsAtNil_StillReported;         // TP-Gegenprobe
    [Test] procedure Field_OwnerChainOnPlainObjectClass_StillReported; // TP-Gegenprobe
    // FP-Gate 2026-08-17: Feld an ein Interface uebergeben = Refcount traegt
    // die Ownership; ein Free im Destroy waere ein Double-Free.
    [Test] procedure FieldHandedToInterface_NotReported;
    [Test] procedure FieldNotHandedToInterface_StillReported;
    // Owner-Gate 2026-08-17: der Owner darf ueber einen PFAD kommen.
    [Test] procedure Field_OwnerViaPath_NoFinding;
    [Test] procedure Field_OwnerLookalikeIdent_StillReported;
    // Property-Alias 2026-08-18: Freigabe ueber den oeffentlichen Namen.
    [Test] procedure Field_FreedViaPropertyAlias_NoFinding;
    [Test] procedure Field_FreedViaForeignName_StillReported;
    // Fixture-Gate 2026-08-18: der Feld-Pfad hatte keins.
    [Test] procedure Field_InFixturePath_NotReported;
    [Test] procedure Field_InProductionPath_StillReported;
  private
    // Parst ASrc und laesst NUR den Feld-Detektor mit dem
    // angegebenen Dateinamen darueber laufen. Eigener Helfer,
    // weil der Dateiname hier die Testvariable ist -
    // TFindingHelper.FindingsOf gibt ihn nicht frei.
    function FieldLeakCount(const ASrc, AFileName: string): Integer;
  end;

implementation

uses
  // TD-1 Inkrement 2c: direkter Parser-/Detektor-/Context-Zugriff fuer den
  // context-driven LeakyClasses-Test (die uebrigen Tests laufen ueber
  // TFindingHelper.FindingsOf, das den Detektor mit AContext=nil aufruft).
  // uTypeIndex (2026-07-31): das TComponent-Owner-Gate Stufe 1 braucht einen
  // gefuellten Cross-Unit-Typindex - der ist nur ueber einen echten
  // TAnalyzeContext testbar (FindingsOf ruft mit AContext=nil).
  uParser2, uAstNode, uAnalyzeContext, uLeakDetector2, uTypeIndex,
  uFieldLeak;   // Direktaufruf mit kontrolliertem Dateinamen (Fixture-Gate)

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

procedure TTestMemoryLeakAdvanced.Leak_CustomAddMethod_OwnershipRecognized;
// Inkr.3 (add-call 27/101): 'FOptions.AddOption(sl)' - custom Add-Methode
// registriert das Objekt in einer owning-Struktur des Consumers. Marker
// '.add' + CamelCase-Suffix ('O' gross im Original) + Var als Arg;
// Feld-Receiver -> permissiver AddReceiverOwnsItems-Pfad.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var sl: TStringList;'#13#10+
  'begin'#13#10+
  '  sl := TStringList.Create;'#13#10+
  '  FOptions.AddOption(sl);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'custom AddOption uebernimmt Ownership - kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_InsertNodeCastArg_OwnershipRecognized;
// Inkr.3: 'FTree.InsertNode(..., PFileInfo(fi))' - Insert-Familie mit dem
// Objekt in einem CAST-Argument (VarInArgs matcht wortgebunden im Cast).
// Geerdet: HeidiSQL insertfiles.pas ListFiles.InsertNode(PFileInfo(FileInfo)).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var fi: TStringList;'#13#10+
  'begin'#13#10+
  '  fi := TStringList.Create;'#13#10+
  '  FTree.InsertNode(FTree.FocusedNode, amInsertAfter, PFileInfo(fi));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'InsertNode mit Cast-Arg uebernimmt Ownership - kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_AddressCall_StillReported;
// TP-Gegenprobe zur Camel-Regel: '.Address(obj)' ist KEINE Add-Familie
// (Buchstabe nach '.add' ist 'r' und im Original KLEIN) -> kein Ownership-
// Transfer -> das nie freigegebene Objekt bleibt ein Leak-Fund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var obj: TStringList;'#13#10+
  'begin'#13#10+
  '  obj := TStringList.Create;'#13#10+
  '  FLog.Address(obj);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.CountSev(F, fkMemoryLeak, lsError) >= 1,
      '.Address ist keine Add-Familie - Leak bleibt gemeldet');
  finally F.Free; end;
end;

{ --- 30%-Real-World-Audit 2026-07-31: FP-Klasse 1 (Ownership-Senken) --------
  Das strukturelle Gate greift, wenn der LETZTE Use der Variablen die Uebergabe
  an eine Add/Insert/Append/Push/Enqueue-Senke (oder an einen fremden Ctor) ist
  und der Empfaenger nicht die Variable selbst ist. Alle Faelle hier waren vor
  dem Fix ROT (Fund gemeldet), weil der Aufruf gar nicht als nkCall vorlag
  (Zuweisungs-RHS), weil der Receiver fehlt (bare Self-Call) oder weil die
  Sink-Familie neu ist ('Enqueue<Camel>').
  Review 2026-07-31: Der Receiver bleibt STRIKT geprueft - ein aufloesbarer
  Local-/Param-Empfaenger muss die RTL-Ownership-Whitelist treffen. Faelle mit
  aufloesbarem Fremd-Container (TJSONObject/TCustomImageList) sind deshalb
  bewusst TP-Gegenproben, keine Drops. }

procedure TTestMemoryLeakAdvanced.Leak_SinkBareAddCall_LastUse_NoFinding;
// pyscripter cFileTemplates.pas:271 - 'Add(FileTemplate)' ohne Receiver
// (Self-Methode der besitzenden Collection). Ohne '.' vor dem Add griff bisher
// KEINE Ownership-Regel.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFileTemplates.AddJSONTemplate;'#13#10+
  'var FileTemplate: TStringList;'#13#10+
  'begin'#13#10+
  '  FileTemplate := TStringList.Create;'#13#10+
  '  FileTemplate.Sorted := True;'#13#10+
  '  Add(FileTemplate);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'unqualifiziertes Add(obj) der eigenen Collection = Ownership-Transfer');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_SinkAddPairCamelInAssignRhs_LastUse_NoFinding;
// swagdoc Swag.Doc.Path.Operation.RequestParameter.pas:218 -
// 'FJsonObject.AddPair(Key, vJsonEnum)'; System.JSON AddPair uebernimmt.
// vJsonEnum ist als TStringList deklariert, damit es ueberhaupt als leaky
// geprueft wird (TJSONArray steht in keiner Default-LeakyClasses-Liste).
// Der Empfaenger ist ein FELD (nicht aufloesbar -> permissiv, wie im
// bestehenden '.add('-Pfad), und der Aufruf steht in der RHS einer Zuweisung
// auf ein FREMDES Ziel - beides sieht der nkCall-Zweig des alten Gates nicht.
// Review 2026-07-31: vorher stand hier ein LOKALER 'vJsonObject: TJSONObject'
// als Empfaenger; das haette die strikte Receiver-Whitelist umgekehrt.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.GenerateJson;'#13#10+
  'var vJsonEnum: TStringList;'#13#10+
  'begin'#13#10+
  '  vJsonEnum := TStringList.Create;'#13#10+
  '  FLastPair := FJsonObject.AddPair(''enum'', vJsonEnum);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'AddPair (CamelCase-Suffix der Add-Familie) in einer Zuweisungs-RHS '+
      '= Ownership-Transfer');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_SinkEnqueueCamel_LastUse_NoFinding;
// LoggerPro.pas:2913 - 'FInner.EnqueueLogItem(lLogItem)'; die Queue besitzt
// das Item. Das alte Gate kannte nur exakt '.enqueue('.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TLogWriterWithContext.Log;'#13#10+
  'var lLogItem: TStringList;'#13#10+
  'begin'#13#10+
  '  lLogItem := TStringList.Create;'#13#10+
  '  FInner.EnqueueLogItem(lLogItem);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'EnqueueLogItem gehoert zur Enqueue-Familie - Ownership-Transfer');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_SinkAddInAssignRhs_LastUse_NoFinding;
// doublecmd uthumbfileview.pas:137 - 'FWorkingFile.Tag := FBitmapList.Add(Bitmap)'.
// Der Add-Aufruf steckt in der RHS einer Zuweisung auf ein FREMDES Ziel; der
// nkCall-Zweig sah ihn nie.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFileThumbnailsRetriever.Execute;'#13#10+
  'var Bitmap: TBitmap;'#13#10+
  'begin'#13#10+
  '  Bitmap := TBitmap.Create;'#13#10+
  '  FWorkingFile.Tag := FBitmapList.Add(Bitmap);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Add-Aufruf in einer Zuweisungs-RHS zaehlt ebenfalls als Senke');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_SinkCtorArgInAssignRhs_LastUse_NoFinding;
// doublecmd ufileview.pas:2166 - 'Worker := TFileListBuilder.Create(..., Hashed)';
// der Worker-Ctor uebernimmt die Variable (var-Parameter, Free im Worker-Dtor).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFileView.MakeFileSourceFileList;'#13#10+
  'var Hashed: TStringList;'#13#10+
  'begin'#13#10+
  '  Hashed := TStringList.Create;'#13#10+
  '  Worker := TFileListBuilder.Create(FileSource, Hashed);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Uebergabe an fremden Ctor in einer Zuweisungs-RHS = Ownership-Transfer');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_SinkAddThenUsedAgain_StillReported;
// TP-Gegenprobe zum LAST-USE-Anker: das Objekt wird NACH der Senke noch
// benutzt -> die Uebergabe ist nicht der letzte Use, das Gate darf nicht
// greifen. Ohne diesen Anker waere jedes 'X.AddPair(k, obj)' blind
// unterdrueckt.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var host: TJSONObject; obj: TStringList;'#13#10+
  'begin'#13#10+
  '  obj := TStringList.Create;'#13#10+
  '  host.AddPair(''k'', obj);'#13#10+
  '  obj.Sort;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'Use NACH der Senke -> Last-Use-Anker greift nicht, obj bleibt gemeldet');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_SinkResolvedNonOwningReceiver_StillReported;
// Regressionsanker fuer den Review-Fund 2026-07-31 ("ReceiverIsProvenNonOwning
// kehrt die strikte Receiver-Policy um"). Beide Empfaenger sind in der Routine
// AUFLOESBAR (Parameter bzw. Local-Var) und treffen die RTL-Ownership-Whitelist
// NICHT - der Fund muss stehen bleiben:
//   * AConfig: TJSONObject   - Parameter-Aufloesung
//   * TempImageList: TCustomImageList (jvcl JvImageList.pas LoadImageList-
//     FromBitmap) - TImageList KOPIERT die Bitmap, MaskBmp leakt wirklich.
// Mit einer Sperrlisten-Policy (nur 'tlist'/'tstrings'/... veto'en) waeren
// BEIDE Funde verschwunden - dieser Test wird dann ROT.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TdmHighl.SaveColors(AConfig: TJSONObject);'#13#10+
  'var AList: TStringList;'#13#10+
  'begin'#13#10+
  '  AList := TStringList.Create;'#13#10+
  '  AConfig.Add(''Highlighters'', AList);'#13#10+
  'end;'#13#10+
  'procedure TJvImageList.LoadImageListFromBitmap;'#13#10+
  'var TempImageList: TCustomImageList; MaskBmp: TBitmap;'#13#10+
  'begin'#13#10+
  '  MaskBmp := TBitmap.Create;'#13#10+
  '  TempImageList.Add(FSourceBmp, MaskBmp);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(2, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'aufloesbarer Empfaenger ohne Ownership-Nachweis -> beide Leaks bleiben');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_SinkHelperCallArgNotUnwrapped_StillReported;
// Regressionsanker fuer den Review-Fund 2026-07-31 ("SinkArgIsVar packt
// beliebige '<ident>(...)'-Koepfe aus, nicht nur Typecasts"): 'Describe(Buf)'
// uebergibt einen STRING, nicht das Objekt - der Leak bleibt. Bewusst ein
// UNQUALIFIZIERTER Add-Aufruf: bei dotted Empfaengern greift das aeltere
// IsPassedToOwner/VarInArgs schon vorher und der Test waere vakuum-gruen.
// Mit dem alten "jeder Identifier-Kopf ist ein Cast" wird 'describe(buf)' auf
// 'buf' ausgepackt, das Gate feuert und dieser Test wird ROT.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFileTemplates.Log;'#13#10+
  'var Buf: TStringList;'#13#10+
  'begin'#13#10+
  '  Buf := TStringList.Create;'#13#10+
  '  Add(Describe(Buf));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'Helferfunktions-Argument ist kein Typecast - der Leak bleibt gemeldet');
  finally F.Free; end;
end;

{ --- Drop-Sampling after119->after120 (2026-07-31): TP-Verlust-Cluster SCA001 --
  Das Sink-Gate stellte 7 echte Error-Tier-Lecks still, weil eine GEPUNKTETE
  Empfaengerkette ('AlarmListBox.Items', 'ATreeView.Items') in der Routine nicht
  aufloesbar ist und damit auf den permissiven Zweig faellt. Genau diese Ketten
  sind aber die kanonisch NICHT besitzenden VCL/LCL-Container: TStrings besitzt
  Objects[] nie, TTreeNode.Data ist ein untypisierter Pointer.
  Die Zusatzhuerde veto't deshalb, wenn das LETZTE Segment des Empfaengers ein
  nicht-besitzender Container-Zugang ist UND der Senkenname zur *Object*-Familie
  gehoert. }

procedure TTestMemoryLeakAdvanced.Leak_SinkDottedItemsAddObject_StillReported;
// TP jvcl/jvcl/archive/JvAlarmsForm.pas:106 (und 5 baugleiche JVCL-Stellen):
// 'Al' wird erzeugt, per TStrings.AddObject in die Listbox gehaengt und in der
// GANZEN Unit nie freigegeben - TStrings.Destroy raeumt Objects[] nicht ab.
// Ohne die Zusatzhuerde ist dieser Test ROT (0 Funde): 'alarmlistbox.items' ist
// nicht aufloesbar -> permissiver Pfad -> die Senke galt als besitzend.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFormAlarm.AddBtnClick(Sender: TObject);'#13#10+
  'var Al: TStringList;'#13#10+
  'begin'#13#10+
  '  Al := TStringList.Create;'#13#10+
  '  Al.Sorted := True;'#13#10+
  '  AlarmListBox.ItemIndex := AlarmListBox.Items.AddObject(''New'', TObject(Al));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'TStrings.AddObject auf einer gepunkteten .Items-Kette ist KEIN '+
      'Ownership-Transfer - das Leck muss gemeldet bleiben');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_SinkDottedItemsAddChildObject_StillReported;
// TP doublecmd-master/src/ftreeviewmenu.pas:230: das TTreeMenuItem landet als
// TTreeNode.Data (untypisierter Pointer, kein Ownership) und wird nirgends
// freigegeben. Empfaenger 'ATreeView.Items' ist dotted -> ohne die Zusatzhuerde
// ROT. TStringList statt TTreeMenuItem, damit der Typ ohne Auto-Discovery als
// leaky gilt; die Form des Aufrufs ist identisch.
const SRC =
  'unit t; implementation'#13#10+
  'function TMenuHolder.AddTreeViewMenuItem(ATreeView: TTreeView; ParentNode: TTreeNode; const S: string): TTreeNode;'#13#10+
  'var ATreeMenuItem: TStringList;'#13#10+
  'begin'#13#10+
  '  ATreeMenuItem := TStringList.Create;'#13#10+
  '  ATreeMenuItem.Sorted := True;'#13#10+
  '  Result := ATreeView.Items.AddChildObject(ParentNode, S, ATreeMenuItem);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'TTreeNodes.AddChildObject speichert nur den Data-Pointer - das Leck '+
      'muss gemeldet bleiben');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_SinkDottedItemsPlainAdd_NoFinding;
// GEGENPROBE (korrekter Drop, muss gedroppt bleiben): mORMot
// src/ui/mormot.ui.report.pas:5051/5191 - 'PopupMenu.Items.Add(Item)'. Hier ist
// 'Items' ein TMenuItem und der gibt seine Kinder frei. Unterschied zu den
// beiden Tests oben ist AUSSCHLIESSLICH der Senkenname: '.Add' nimmt bei
// TStrings/TTreeNodes einen String, nur die *Object*-Ueberladungen nehmen ein
// Objekt. Faellt die Object-Huerde weg, wird dieser Test ROT.
// Zuweisungs-RHS, damit der aeltere nkCall-Pfad (IsPassedToOwner) nicht schon
// vorher greift und der Test das neue Gate wirklich prueft.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TGdiPages.NewPopupMenuItem(const aCaption: string);'#13#10+
  'var LItem: TStringList;'#13#10+
  'begin'#13#10+
  '  LItem := TStringList.Create;'#13#10+
  '  LItem.Text := aCaption;'#13#10+
  '  FLastIndex := PopupMenu.Items.Add(LItem);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'schlichtes .Items.Add bleibt Ownership-Transfer - nur die '+
      '*Object*-Ueberladungen sind nachweislich nicht besitzend');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_SinkBareAddObjectSelfCollection_NoFinding;
// GEGENPROBE (korrekter Drop): gexperts Src/GX_ToDo.pas:265 bzw. jvcl
// JvParameterList.pas:716 - unqualifiziertes 'AddObject(Token, TokenInfo)' der
// eigenen TStringList-ABLEITUNG, die ihre Objects[] in Clear/Destroy selbst
// freigibt. Leerer Empfaenger darf nie als Container-Zugang gelten.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TTokenList.AddToken(Token: string);'#13#10+
  'var TokenInfo: TStringList;'#13#10+
  'begin'#13#10+
  '  TokenInfo := TStringList.Create;'#13#10+
  '  TokenInfo.Sorted := True;'#13#10+
  '  AddObject(Token, TokenInfo);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'unqualifiziertes AddObject der eigenen Collection bleibt '+
      'Ownership-Transfer');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_SinkBareFieldAddObject_NoFinding;
// GEGENPROBE (korrekter Drop): jvcl/jvcl/run/JvSAL.pas:608 -
// 'Result := Atoms.AddObject(Op, AAtom)'. Der Empfaenger ist ein FELD mit
// fachlichem Namen, kein Container-Zugang - das Veto darf nicht greifen.
const SRC =
  'unit t; implementation'#13#10+
  'function TJvSAL.APO(Op: string): Integer;'#13#10+
  'var AAtom: TStringList;'#13#10+
  'begin'#13#10+
  '  AAtom := TStringList.Create;'#13#10+
  '  AAtom.Sorted := True;'#13#10+
  '  Result := Atoms.AddObject(Op, AAtom);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Feld-Empfaenger ohne Container-Zugangs-Namen bleibt permissiv');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_SinkResolvedOwningAccessorName_NoFinding;
// GEGENPROBE zum Local/Param-Probe-Zweig: der Empfaenger heisst zwar wie ein
// Container-Zugang ('Data'), ist hier aber ein AUFLOESBARER Parameter vom Typ
// TObjectList und trifft damit die RTL-Ownership-Whitelist. Ohne die
// ScopeDeclaresIdent-Pruefung wuerde die Namensliste blind veto'en und dieser
// Test ROT.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar(Data: TObjectList);'#13#10+
  'var Item: TStringList;'#13#10+
  'begin'#13#10+
  '  Item := TStringList.Create;'#13#10+
  '  Item.Sorted := True;'#13#10+
  '  FIndex := Data.AddObject(''k'', Item);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'aufloesbarer TObjectList-Parameter schlaegt die Accessor-Namensliste');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_TpPenAssignedBack_StillReported;
// TP aus der Audit-Liste (jvcl JvUtils.pas:1854): 'PenOld := TPen.Create',
// zurueckkopiert per 'Canvas.Pen.Assign(PenOld)', nie freigegeben. Assign ist
// KEINE Senke - der echte Leak muss erhalten bleiben. TFont statt TPen, weil
// TPen erst per Auto-Discovery in die LeakyClasses kommt; identische Form.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.MoveFrame;'#13#10+
  'var PenOld: TFont;'#13#10+
  'begin'#13#10+
  '  PenOld := TFont.Create;'#13#10+
  '  PenOld.Assign(Canvas.Font);'#13#10+
  '  Canvas.Font.Assign(PenOld);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'Assign ist keine Ownership-Senke - der TPen/TFont-Leak bleibt gemeldet');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_TpStringsUsedAfterForeignAdd_StillReported;
// TP aus der Audit-Liste (Indy SaveToLoadFromFileTests.pas:88): TheStrings wird
// nie freigegeben. In derselben Methode gibt es einen Add-Aufruf - aber mit
// einem ANDEREN Argument, und der letzte Use von TheStrings ist ein Lesezugriff.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.RunTest;'#13#10+
  'var TheStrings: TStringList; sTemp: string;'#13#10+
  'begin'#13#10+
  '  TheStrings := TStringList.Create;'#13#10+
  '  Msg.Body.Add(MsgText);'#13#10+
  '  TheStrings.LoadFromFile(APath);'#13#10+
  '  sTemp := TheStrings.Strings[0];'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'Fremdes Add-Argument + Lesezugriff als letzter Use -> Leak bleibt');
  finally F.Free; end;
end;

{ --- 30%-Real-World-Audit 2026-07-31: FP-Klasse 2 --------------------------- }

procedure TTestMemoryLeakAdvanced.Leak_ComponentOwnerCreate_DottedFieldArg_NoFinding;
// doublecmd umaincommands.pas:2252 - 'TBriefFileView.Create(<Owner>, FrameRight)'.
// Erstes Ctor-Argument ist ein nicht-nil Objekt-Ausdruck = TComponent-Owner-
// Konvention. Ohne Typindex (AContext=nil) greift die Stufe-2-Heuristik: DOTTED
// Ausdruck + Klasse nicht in der Datenklassen-Sperrliste + Komponenten-
// Namenskonvention.
// Review 2026-07-31: die Namenskonvention ist NEU (vorher genuegte 'dotted').
// Deshalb hier 'FRightTabs.ActivePage' (F-Praefix-Feld) statt des puren
// 'RightTabs.ActivePage' aus der Originalquelle - published Form-Felder ohne
// F-Praefix liegen jetzt ausserhalb von Stufe 2 (dokumentierte
// Reichweitengrenze; mit gefuelltem TTypeIndex greift Stufe 1).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TMainCommands.cm_RightBriefView;'#13#10+
  'var aFileView: TComponent;'#13#10+
  'begin'#13#10+
  '  aFileView := TBriefFileView.Create(FRightTabs.ActivePage, FrameRight);'#13#10+
  '  aFileView.Tag := 1;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Create(<Owner-Ausdruck>) = Component-Ownership - kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_ComponentOwnerCreate_TypeIndexProven_NoFinding;
// Stufe 1 des Gates: der Cross-Unit-Typindex belegt die TComponent-Ahnenlinie
// (TForm -> ... -> TComponent ueber die RTL-Seeds). Zugleich die Gegenprobe:
// TStringList ist im Index AUFLOESBAR und KEIN TComponent-Nachfahre -> das Gate
// darf dort nicht greifen, der Leak bleibt. FindingsOf ruft mit AContext=nil,
// deshalb hier der direkte Detektor-Aufruf mit echtem Context.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var frm: TForm; sl: TStringList;'#13#10+
  'begin'#13#10+
  '  frm := TForm.Create(FHost);'#13#10+
  '  sl := TStringList.Create(FHost);'#13#10+
  '  frm.Show;'#13#10+
  '  sl.Sort;'#13#10+
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
    try
      Ctx := TAnalyzeContext.Create;
      F   := TObjectList<TLeakFinding>.Create(True);
      try
        Ctx.LeakyClasses.Add('TForm');
        Ctx.LeakyClasses.Add('TStringList');
        Ctx.TypeIndex := TTypeIndex.Create;
        Ctx.TypeIndex.Build(nil, nil);   // nur die RTL-/VCL-Seeds
        TLeakDetector2.AnalyzeUnit(Root, 'sample.pas', F, Ctx);
        Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
          'frm (TForm=TComponent-Nachfahre) unterdrueckt, sl (TStrings-Ast) bleibt');
      finally
        F.Free;
        Ctx.Free;
      end;
    finally
      Root.Free;
    end;
  finally
    Parser.Free;
  end;
end;

procedure TTestMemoryLeakAdvanced.Leak_DataClassDottedArg_StillReported;
// TP-Gegenprobe zur Stufe-2-Heuristik: bei bekannten DATEN-Klassen ist das
// erste Ctor-Argument ein Dateiname/Quellstream, kein Owner - auch wenn es
// zufaellig ein dotted Ausdruck ist. Ohne diese Sperrliste verschwaende der
// komplette Stream-/Datei-Leak-TP-Block.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var fs: TFileStream;'#13#10+
  'begin'#13#10+
  '  fs := TFileStream.Create(Cfg.FileName, fmOpenRead);'#13#10+
  '  fs.Read(Buf, 10);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'TFileStream.Create(<pfad>) ist kein Owner-Ctor - Leak bleibt gemeldet');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_DottedNonComponentArg_StillReported;
// Regressionsanker fuer den Review-Fund 2026-07-31 ("Stufe 2 wertet JEDES
// dotted erste Ctor-Argument als Owner"). Beide Klassen stehen NICHT in der
// Datenklassen-Sperrliste und sind im Typindex nicht aufloesbar; das erste
// Argument ist dotted, sieht aber nicht nach Komponente aus (kein Self./
// F-Praefix/Owner/Parent) und die Klasse ist keine bekannte VCL-Komponente:
//   * TDictionary<..>.Create(TIStringComparer.Ordinal)  - Comparer, kein Owner
//   * TSynLogFile.Create(Ctxt.FileName)                 - Pfad, kein Owner
// Mit der alten "dotted genuegt"-Regel verschwanden beide Funde.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var D: TDictionary<string, TObject>; L: TSynLogFile;'#13#10+
  'begin'#13#10+
  '  D := TDictionary<string, TObject>.Create(TIStringComparer.Ordinal);'#13#10+
  '  D.Add(''k'', nil);'#13#10+
  '  L := TSynLogFile.Create(Ctxt.FileName);'#13#10+
  '  L.LoadFromMap;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(2, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'dotted Argument ohne Komponenten-Konvention ist kein Owner-Nachweis');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_FactoryStoresResultInContainer_NoFinding;
// cnwizards DasmProc.pas:238 - 'E := AddMemData(...)'. Die same-unit-Factory
// haengt ihr Result SELBST in die besitzende Liste ('Insert(i, Result)') - der
// Aufrufer bekommt nur eine geliehene Referenz.
const SRC =
  'unit t; implementation'#13#10+
  'function TProc.AddMemData(AStart: Cardinal): TStringList;'#13#10+
  'begin'#13#10+
  '  Result := TStringList.Create;'#13#10+
  '  Insert(0, Result);'#13#10+
  'end;'#13#10+
  'procedure TProc.AddExcDesc(AStart: Cardinal);'#13#10+
  'var E: TStringList;'#13#10+
  'begin'#13#10+
  '  E := AddMemData(AStart);'#13#10+
  '  E.Sort;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Factory haengt ihr Result selbst in eine Liste - Rueckgabe ist geborgt');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_FactoryReturnsOwnership_StillReported;
// TP-Gegenprobe: eine Factory, die ihr Result NICHT wegspeichert und keinen
// Owner-Parameter fuehrt, gibt das Ownership sehr wohl ab - der fehlende Free
// beim Aufrufer bleibt ein Befund.
const SRC =
  'unit t; implementation'#13#10+
  'function TProc.BuildList: TStringList;'#13#10+
  'begin'#13#10+
  '  Result := TStringList.Create;'#13#10+
  'end;'#13#10+
  'procedure TProc.Consume;'#13#10+
  'var E: TStringList;'#13#10+
  'begin'#13#10+
  '  E := BuildList();'#13#10+
  '  E.Sort;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
      'echte Ownership-Factory ohne Free beim Aufrufer bleibt gemeldet');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_FactoryHomonymInForeignClass_StillReported;
// Regressionsanker fuer den Review-Fund 2026-07-31 ("CalleeKeepsOwnership loest
// den Callee klassenuebergreifend auf"): Zwei gleichnamige Factories in einer
// Unit. Nur die FREMDE (TWidgetFactory) fuehrt einen Owner-Parameter; der
// Aufruf in TDataFactory.Use meint aber die EIGENE, die das Ownership abgibt.
// Ohne Klassen-Qualifikation genuegte der Fremd-Treffer und der echte Leak
// verschwand.
const SRC =
  'unit t; implementation'#13#10+
  'function TWidgetFactory.BuildWidget(AOwner: TComponent): TStringList;'#13#10+
  'begin'#13#10+
  '  Result := TStringList.Create;'#13#10+
  'end;'#13#10+
  'function TDataFactory.BuildWidget: TStringList;'#13#10+
  'begin'#13#10+
  '  Result := TStringList.Create;'#13#10+
  'end;'#13#10+
  'procedure TDataFactory.Use;'#13#10+
  'var W: TStringList;'#13#10+
  'begin'#13#10+
  '  W := BuildWidget;'#13#10+
  '  W.Sort;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
      'Owner-Parameter der FREMDEN Homonym-Factory darf den Fund nicht gaten');
  finally F.Free; end;
end;

{ --- Parser-Gate-Backlog 2026-07-31 (Konzept 4e/1 + 4e/2) ------------------ }

procedure TTestMemoryLeakAdvanced.Leak_CtorRegistersSelfWithParent_NoFinding;
// jvcl JvInspector.pas 4130/11876: 'TJvInspectorCustomCategoryItem.Create(
// AParent, nil)'. Die Klasse hat keinen eigenen Ctor; der geerbte
// TJvCustomInspectorItem.Create haengt sich per 'AParent.Add(Self)' in die
// besitzende FItems-Liste des Parents. Weder IsOwnerParamCreate (kennt nur
// Self/Owner/AOwner/Application) noch IsComponentOwnerCreate (TComponent-Linie;
// die Items sind TPersistent) sehen das -> ohne den Fix ROT.
// Der Test prueft zugleich die Ahnenkette IN DER UNIT (TSynList erbt den Ctor).
const SRC =
  'unit t; interface'#13#10+
  'type'#13#10+
  '  TSynObjectList = class'#13#10+
  '  public'#13#10+
  '    constructor Create(AParent: TSynObjectList);'#13#10+
  '    function Add(AItem: TSynObjectList): Integer;'#13#10+
  '  end;'#13#10+
  '  TSynList = class(TSynObjectList)'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'constructor TSynObjectList.Create(AParent: TSynObjectList);'#13#10+
  'begin'#13#10+
  '  inherited Create;'#13#10+
  '  if AParent <> nil then'#13#10+
  '    AParent.Add(Self);'#13#10+
  'end;'#13#10+
  'procedure TFoo.Build(AParent: TSynObjectList);'#13#10+
  'var Item: TSynList;'#13#10+
  'begin'#13#10+
  '  Item := TSynList.Create(AParent);'#13#10+
  '  Item.Tag := 1;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'Der Ctor haengt Self in die Liste des Parents - kein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_CtorDoesNotRegisterSelf_StillReported;
// TP-Gegenprobe: identische Form, aber der Ctor MERKT sich den Parent nur
// (Rueckwaerts-Referenz) statt sich in dessen Liste zu haengen. Dann uebernimmt
// niemand die Ownership und der Fund muss stehen bleiben.
const SRC =
  'unit t; interface'#13#10+
  'type'#13#10+
  '  TSynObjectList = class'#13#10+
  '  public'#13#10+
  '    FParent: TSynObjectList;'#13#10+
  '    constructor Create(AParent: TSynObjectList);'#13#10+
  '  end;'#13#10+
  '  TSynList = class(TSynObjectList)'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'constructor TSynObjectList.Create(AParent: TSynObjectList);'#13#10+
  'begin'#13#10+
  '  inherited Create;'#13#10+
  '  FParent := AParent;'#13#10+
  'end;'#13#10+
  'procedure TFoo.Build(AParent: TSynObjectList);'#13#10+
  'var Item: TSynList;'#13#10+
  'begin'#13#10+
  '  Item := TSynList.Create(AParent);'#13#10+
  '  Item.Tag := 1;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
    'Ohne Selbst-Registrierung bleibt Item ein Leak');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_CtorOverloadsAncestorRegisters_StillReported;
// REVIEW-BLOCKER 1 (2026-07-31), ohne den Fix ROT:
// 'TSynList' hat ZWEI ueberladene Konstruktoren, der Vorfahr 'TSynObjectList' genau
// einen - und DER haengt sich per 'AParent.Add(Self)' in die Liste des Parents.
// Vorher lieferte UniqueCtorOf bei Overloads dasselbe nil wie bei "kein Ctor
// gefunden"; die Schleife kletterte darum auch bei Mehrdeutigkeit zum Vorfahren
// und beurteilte 'TSynList.Create(AParent, ''x'')' nach TSynObjectList.Create - obwohl
// nicht entscheidbar ist, welche Ueberladung gemeint war und ob sie den Parent
// ueberhaupt weiterreicht (die zweite tut es nicht: 'inherited Create(nil)').
// Tri-State: Mehrdeutigkeit bricht ab -> kein Gate -> der Fund bleibt.
const SRC =
  'unit t; interface'#13#10+
  'type'#13#10+
  '  TSynObjectList = class'#13#10+
  '  public'#13#10+
  '    constructor Create(AParent: TSynObjectList);'#13#10+
  '    function Add(AItem: TSynObjectList): Integer;'#13#10+
  '  end;'#13#10+
  '  TSynList = class(TSynObjectList)'#13#10+
  '  public'#13#10+
  '    FName: string;'#13#10+
  '    constructor Create(AParent: TSynObjectList; const AName: string); overload;'#13#10+
  '    constructor Create(const AName: string); overload;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'constructor TSynObjectList.Create(AParent: TSynObjectList);'#13#10+
  'begin'#13#10+
  '  inherited Create;'#13#10+
  '  if AParent <> nil then'#13#10+
  '    AParent.Add(Self);'#13#10+
  'end;'#13#10+
  'constructor TSynList.Create(AParent: TSynObjectList; const AName: string);'#13#10+
  'begin'#13#10+
  '  inherited Create(AParent);'#13#10+
  '  FName := AName;'#13#10+
  'end;'#13#10+
  'constructor TSynList.Create(const AName: string);'#13#10+
  'begin'#13#10+
  '  inherited Create(nil);'#13#10+
  '  FName := AName;'#13#10+
  'end;'#13#10+
  'procedure TFoo.Build(AParent: TSynObjectList);'#13#10+
  'var Leaf: TSynList;'#13#10+
  'begin'#13#10+
  '  Leaf := TSynList.Create(AParent, ''x'');'#13#10+
  '  Leaf.Tag := 1;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
    'Overloads sind kein Beweis - der Vorfahren-Ctor darf nicht gaten');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_CtorUniqueOwnRegisters_NoFinding;
// Gegenprobe zu Blocker 1: dieselbe Form, aber die Klasse hat GENAU EINEN
// eigenen Ctor - und der registriert sich per 'AParent.Add(Self)'. Eindeutig
// = beweisbar, das Gate muss weiter greifen (der Tri-State darf nicht
// pauschal abschalten).
const SRC =
  'unit t; interface'#13#10+
  'type'#13#10+
  '  TSynObjectList = class'#13#10+
  '  public'#13#10+
  '    function Add(AItem: TSynObjectList): Integer;'#13#10+
  '  end;'#13#10+
  '  TSynList = class(TSynObjectList)'#13#10+
  '  public'#13#10+
  '    FName: string;'#13#10+
  '    constructor Create(AParent: TSynObjectList; const AName: string);'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'constructor TSynList.Create(AParent: TSynObjectList; const AName: string);'#13#10+
  'begin'#13#10+
  '  inherited Create;'#13#10+
  '  AParent.Add(Self);'#13#10+
  '  FName := AName;'#13#10+
  'end;'#13#10+
  'procedure TFoo.Build(AParent: TSynObjectList);'#13#10+
  'var Leaf: TSynList;'#13#10+
  'begin'#13#10+
  '  Leaf := TSynList.Create(AParent, ''x'');'#13#10+
  '  Leaf.Tag := 1;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'Eindeutiger Ctor mit AParent.Add(Self) - der Parent besitzt Leaf');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_CtorAddsSelfMemberNotSelf_StillReported;
// REVIEW-BLOCKER 2 (2026-07-31), ohne den Fix ROT:
// Der Ctor uebergibt 'Self.FCaption' - ein FELD von Self, nicht Self. Die
// alte Pruefung (TDetectorUtils.ContainsWholeWordLower) akzeptierte '.' als
// rechte Wortgrenze und zaehlte 'self.fcaption' als Selbstregistrierung; damit
// waere 'C := TSynList.Create(MyList)' stillgestellt worden, obwohl niemand C
// besitzt. Der explizite Scan (ArgsContainBareSelf) verwirft den Punkt.
const SRC =
  'unit t; interface'#13#10+
  'type'#13#10+
  '  TSynObjectList = class'#13#10+
  '  public'#13#10+
  '    function Add(AItem: TObject): Integer;'#13#10+
  '  end;'#13#10+
  '  TSynList = class'#13#10+
  '  public'#13#10+
  '    FCaption: TObject;'#13#10+
  '    constructor Create(AItems: TSynObjectList);'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'constructor TSynList.Create(AItems: TSynObjectList);'#13#10+
  'begin'#13#10+
  '  inherited Create;'#13#10+
  '  AItems.Add(Self.FCaption);'#13#10+
  'end;'#13#10+
  'procedure TFoo.Build(MyList: TSynObjectList);'#13#10+
  'var C: TSynList;'#13#10+
  'begin'#13#10+
  '  C := TSynList.Create(MyList);'#13#10+
  '  C.Tag := 1;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
    'Uebergeben wird ein Feld von Self - C bleibt ein echtes Leck');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_CtorRegistersSelfViaTypecast_NoFinding;
// Gegenprobe zu Blocker 2: 'AItems.Add(TObject(Self))' ist eine echte
// Selbstregistrierung - die Klammer ist eine gueltige rechte Wortgrenze und
// muss weiter matchen.
const SRC =
  'unit t; interface'#13#10+
  'type'#13#10+
  '  TSynObjectList = class'#13#10+
  '  public'#13#10+
  '    function Add(AItem: TObject): Integer;'#13#10+
  '  end;'#13#10+
  '  TSynList = class'#13#10+
  '  public'#13#10+
  '    constructor Create(AItems: TSynObjectList);'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'constructor TSynList.Create(AItems: TSynObjectList);'#13#10+
  'begin'#13#10+
  '  inherited Create;'#13#10+
  '  AItems.Add(TObject(Self));'#13#10+
  'end;'#13#10+
  'procedure TFoo.Build(MyList: TSynObjectList);'#13#10+
  'var C: TSynList;'#13#10+
  'begin'#13#10+
  '  C := TSynList.Create(MyList);'#13#10+
  '  C.Tag := 1;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'Typecast-Self ist eine Selbstregistrierung - die Liste besitzt C');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_CtorRegistersSelfAsTrailingArg_NoFinding;
// Gegenprobe zu Blocker 2: 'AItems.Insert(0, Self)' - Self hinter einem Komma
// und am Ende der Argumentliste. Beide Grenzen (Komma links, Stringende
// rechts) muessen weiter als Wortgrenze gelten.
const SRC =
  'unit t; interface'#13#10+
  'type'#13#10+
  '  TSynObjectList = class'#13#10+
  '  public'#13#10+
  '    procedure Insert(AIndex: Integer; AItem: TObject);'#13#10+
  '  end;'#13#10+
  '  TSynList = class'#13#10+
  '  public'#13#10+
  '    constructor Create(AItems: TSynObjectList);'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'constructor TSynList.Create(AItems: TSynObjectList);'#13#10+
  'begin'#13#10+
  '  inherited Create;'#13#10+
  '  AItems.Insert(0, Self);'#13#10+
  'end;'#13#10+
  'procedure TFoo.Build(MyList: TSynObjectList);'#13#10+
  'var C: TSynList;'#13#10+
  'begin'#13#10+
  '  C := TSynList.Create(MyList);'#13#10+
  '  C.Tag := 1;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'Self als letztes Argument bleibt eine Selbstregistrierung');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_AddReceiverIsUnitAliasOfObjectList_NoFinding;
// REGRESSIONSFALL des Parser-Inkrements (Konzept 4e/2), delphimvcframework
// contrib/serversideviews_sempare/DAL.pas:136: 'TPeople = TObjectList<TPerson>'.
// Vor dem Parser-Fix war 'TPeople' unaufloesbar -> AddReceiverOwnsItems lief in
// den permissiven Zweig -> kein Fund. Mit aufloesbarem Typ matchte er die
// Whitelist nicht mehr -> das Gate veto-te und erzeugte den FP. Mehr Typwissen
// machte das Ergebnis schlechter; die Alias-Aufloesung stellt es richtig.
const SRC =
  'unit t; interface'#13#10+
  'type'#13#10+
  '  TPeople = TObjectList<TStringList>;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.AddPerson;'#13#10+
  'var'#13#10+
  '  lPeople: TPeople;'#13#10+
  '  lPerson: TStringList;'#13#10+
  'begin'#13#10+
  '  lPeople := GetPeople;'#13#10+
  '  lPerson := TStringList.Create;'#13#10+
  '  lPeople.Add(lPerson);'#13#10+
  '  lPerson.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
    'TPeople ist ein Alias auf TObjectList - der Container besitzt lPerson');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_AddReceiverIsUnitClassOfObjectList_NoFinding;
// Zweite Auspraegung derselben Klasse (delphimvcframework samples/*/DAL.pas):
// 'TPeople = class(TObjectList<TPerson>)' - Ableitung statt Alias. Auch hier
// steht der besitzende Container erst in der Unit-lokalen Deklaration.
const SRC =
  'unit t; interface'#13#10+
  'type'#13#10+
  '  TPeople = class(TObjectList<TStringList>)'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.AddPerson;'#13#10+
  'var'#13#10+
  '  lPeople: TPeople;'#13#10+
  '  lPerson: TStringList;'#13#10+
  'begin'#13#10+
  '  lPeople := GetPeople;'#13#10+
  '  lPerson := TStringList.Create;'#13#10+
  '  lPeople.Add(lPerson);'#13#10+
  '  lPerson.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
    'TPeople erbt von TObjectList - der Container besitzt lPerson');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_AddReceiverIsUnitAliasOfTList_StillReported;
// TP-Gegenprobe: derselbe Alias-Mechanismus, aber auf TList - das ist KEIN
// besitzender Container (kein OwnsObjects, kein Free auf Items). Die
// Aufloesung darf die strikte Whitelist nicht aushebeln; der Fund bleibt.
// (Spiegelt Leak_TListAddNonOwning_ReportsError durch die Alias-Ebene.)
const SRC =
  'unit t; interface'#13#10+
  'type'#13#10+
  '  TPeople = TList<TStringList>;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.AddPerson;'#13#10+
  'var'#13#10+
  '  lPeople: TPeople;'#13#10+
  '  lPerson: TStringList;'#13#10+
  'begin'#13#10+
  '  lPeople := GetPeople;'#13#10+
  '  lPerson := TStringList.Create;'#13#10+
  '  lPeople.Add(lPerson);'#13#10+
  '  lPerson.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
    'TList besitzt seine Items nicht - lPerson bleibt ein Leak');
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

{ --- 30%-Real-World-Audit 2026-07-31: FP-Klasse 3 (indirekte Dtor-Freigabe) - }

procedure TTestFieldLeak.Field_OwnerIsSiblingFieldFreedInDestroy_NoFinding;
// HeidiSQL grideditlinks.pas:130 - 'FEndTimer := TTimer.Create(FPanel)'; der
// Owner FPanel ist ein SCHWESTER-FELD und wird im Destroy per FreeAndNil
// freigegeben - der Component-Tree raeumt den Timer mit ab.
// IsCreatedWithComponentOwner kennt nur Self/AOwner/Owner -> vor dem Fix ROT.
const SRC =
  'unit t; interface'#13#10+
  'type TSetEditorLink = class'#13#10+
  '  FPanel: TPanel;'#13#10+
  '  FEndTimer: TTimer;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  '  destructor Destroy; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TSetEditorLink.Create;'#13#10+
  'begin'#13#10+
  '  FPanel := TPanel.Create(nil);'#13#10+
  '  FEndTimer := TTimer.Create(FPanel);'#13#10+
  'end;'#13#10+
  'destructor TSetEditorLink.Destroy;'#13#10+
  'begin'#13#10+
  '  FreeAndNil(FPanel);'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'Owner-Feld FPanel wird im Destroy freigegeben - FEndTimer ist kein Leak');
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_OwnerFieldNotFreed_StillReported;
// TP-Gegenprobe: dasselbe Muster, aber das Owner-Feld wird NICHT freigegeben.
// Dann ist der Nachweis nicht erbracht und der Befund muss stehen bleiben.
const SRC =
  'unit t; interface'#13#10+
  'type TSetEditorLink = class'#13#10+
  '  FPanel: TPanel;'#13#10+
  '  FEndTimer: TTimer;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  '  destructor Destroy; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TSetEditorLink.Create;'#13#10+
  'begin'#13#10+
  '  FPanel := TPanel.Create(nil);'#13#10+
  '  FEndTimer := TTimer.Create(FPanel);'#13#10+
  'end;'#13#10+
  'destructor TSetEditorLink.Destroy;'#13#10+
  'begin'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
    'Owner-Feld nicht freigegeben - FEndTimer bleibt gemeldet');
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_FreedViaOwnHelperMethod_NoFinding;
// pyscripter JvDockVSNetStyle.pas:180 - der Destruktor ruft die Helper-Methode
// FreeBlockList, die 'FreeAndNil(FBlocks)' macht. Eine Ebene Inlining.
const SRC =
  'unit t; interface'#13#10+
  'type TJvDockVSChannel = class'#13#10+
  '  FBlocks: TObjectList;'#13#10+
  'public'#13#10+
  '  procedure FreeBlockList;'#13#10+
  '  constructor Create;'#13#10+
  '  destructor Destroy; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TJvDockVSChannel.Create;'#13#10+
  'begin'#13#10+
  '  FBlocks := TObjectList.Create;'#13#10+
  'end;'#13#10+
  'procedure TJvDockVSChannel.FreeBlockList;'#13#10+
  'begin'#13#10+
  '  FreeAndNil(FBlocks);'#13#10+
  'end;'#13#10+
  'destructor TJvDockVSChannel.Destroy;'#13#10+
  'begin'#13#10+
  '  FreeBlockList;'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'Free steckt in der vom Destroy gerufenen Helper-Methode - kein Leak');
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_HelperDoesNotFree_StillReported;
// TP-Gegenprobe: der Destruktor ruft zwar eine eigene Helper-Methode, die
// aber KEIN Free auf dem Feld macht -> Befund bleibt.
const SRC =
  'unit t; interface'#13#10+
  'type TJvDockVSChannel = class'#13#10+
  '  FBlocks: TObjectList;'#13#10+
  'public'#13#10+
  '  procedure ClearBlocks;'#13#10+
  '  constructor Create;'#13#10+
  '  destructor Destroy; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TJvDockVSChannel.Create;'#13#10+
  'begin'#13#10+
  '  FBlocks := TObjectList.Create;'#13#10+
  'end;'#13#10+
  'procedure TJvDockVSChannel.ClearBlocks;'#13#10+
  'begin'#13#10+
  '  FBlocks.Clear;'#13#10+
  'end;'#13#10+
  'destructor TJvDockVSChannel.Destroy;'#13#10+
  'begin'#13#10+
  '  ClearBlocks;'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
    'Helper raeumt nur auf, gibt aber nicht frei - Leak bleibt gemeldet');
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_TpNoDestructorAtAll_StillReported;
// TP aus der Audit-Liste (jvcl jvTracker.pas:68): FBackBitmap wird im Ctor
// erzeugt, die Klasse hat GAR KEINEN Destruktor. Keines der neuen Gates darf
// hier greifen (beide setzen einen vorhandenen Destruktor voraus).
const SRC =
  'unit t; interface'#13#10+
  'type TjvTracker = class'#13#10+
  '  FBackBitmap: TBitmap;'#13#10+
  'public'#13#10+
  '  constructor Create(AOwner: TComponent);'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TjvTracker.Create(AOwner: TComponent);'#13#10+
  'begin'#13#10+
  '  inherited Create(AOwner);'#13#10+
  '  FBackBitmap := TBitmap.Create;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
    'Ctor-Bitmap ohne jeden Destruktor bleibt ein echter Leak');
  finally F.Free; end;
end;

{ --- Pre-Build-Review 2026-07-31, Fund uFieldLeak.pas:333 -------------------- }

procedure TTestFieldLeak.Field_ConsumerOverSiblingStream_StillReported;
// TP-Gegenprobe zum Schwester-Feld-Owner-Gate: TStreamReader KONSUMIERT den
// uebergebenen Stream, er wird von ihm nicht besessen. 'FStream.Free' im
// Destroy gibt also NUR den Stream frei - FReader leakt pro Instanz.
// Ohne die Datenklassen-Sperrliste liefert FirstCreateArgLow 'fstream',
// SearchFree(Dtor,'fstream') = True und das Gate stellte den lsError-Fund
// still -> dieser Test ist ohne den Mechanismus ROT (0 statt 1).
const SRC =
  'unit t; interface'#13#10+
  'type TFoo = class'#13#10+
  '  FStream: TMemoryStream;'#13#10+
  '  FReader: TStreamReader;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  '  destructor Destroy; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TFoo.Create;'#13#10+
  'begin'#13#10+
  '  FStream := TMemoryStream.Create;'#13#10+
  '  FReader := TStreamReader.Create(FStream);'#13#10+
  'end;'#13#10+
  'destructor TFoo.Destroy;'#13#10+
  'begin'#13#10+
  '  FStream.Free;'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
    'TStreamReader besitzt den Quellstream nicht - FReader bleibt ein Leak');
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_OwnerFieldIsDataClass_StillReported;
// Zweite Richtung derselben Sperre: die ERZEUGTE Klasse steht nicht auf der
// Sperrliste (TSynLogFile), aber der angebliche Owner ist ein Stream-Feld.
// Ein Stream besitzt keinen Component-Tree und gibt beim Free nichts mit frei,
// also bleibt FLog ein echtes Leak. Ohne die Owner-Typ-Pruefung faellt der
// Fund weg -> ohne den Mechanismus ROT (0 statt 1).
const SRC =
  'unit t; interface'#13#10+
  'type TFoo = class'#13#10+
  '  FStream: TMemoryStream;'#13#10+
  '  FLog: TSynLogFile;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  '  destructor Destroy; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TFoo.Create;'#13#10+
  'begin'#13#10+
  '  FStream := TMemoryStream.Create;'#13#10+
  '  FLog := TSynLogFile.Create(FStream);'#13#10+
  'end;'#13#10+
  'destructor TFoo.Destroy;'#13#10+
  'begin'#13#10+
  '  FStream.Free;'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
    'Stream-Feld als Owner ist keine Ownership - FLog bleibt ein Leak');
  finally F.Free; end;
end;

{ --- Parser-Gate-Backlog 2026-07-31 (Konzept 4e/1) ------------------------- }

procedure TTestFieldLeak.Field_FreedInBeforeDestruction_NoFinding;
// jvcl JvInspector.pas 302/303/307/311/317/325/332/817/1057/1242/1385 und
// JvInspExtraEditors 118/119: die Klassen raeumen ihre Felder AUSSCHLIESSLICH
// in BeforeDestruction auf. Delphi ruft BeforeDestruction garantiert vor
// Destroy (TObject.Free -> BeforeDestruction -> Destroy), das Feld ist also
// aufgeraeumt. Vor dem Fix sah FindMethod nur TypeRef='destructor' -> ROT.
const SRC =
  'unit t; interface'#13#10+
  'type TJvCustomInspector = class'#13#10+
  '  FRoot: TStringList;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  '  procedure BeforeDestruction; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TJvCustomInspector.Create;'#13#10+
  'begin'#13#10+
  '  FRoot := TStringList.Create;'#13#10+
  'end;'#13#10+
  'procedure TJvCustomInspector.BeforeDestruction;'#13#10+
  'begin'#13#10+
  '  inherited BeforeDestruction;'#13#10+
  '  FRoot.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'FRoot wird in BeforeDestruction freigegeben - kein Leak');
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_BeforeDestructionFreesOther_StillReported;
// TP-Gegenprobe: die Klasse HAT ein BeforeDestruction, gibt darin aber ein
// ANDERES Feld frei. Der neue Suchraum darf nicht pauschal entschaerfen.
const SRC =
  'unit t; interface'#13#10+
  'type TJvCustomInspector = class'#13#10+
  '  FRoot: TStringList;'#13#10+
  '  FOther: TStringList;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  '  procedure BeforeDestruction; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TJvCustomInspector.Create;'#13#10+
  'begin'#13#10+
  '  FRoot := TStringList.Create;'#13#10+
  '  FOther := TStringList.Create;'#13#10+
  'end;'#13#10+
  'procedure TJvCustomInspector.BeforeDestruction;'#13#10+
  'begin'#13#10+
  '  FOther.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
    'Nur FOther wird freigegeben - FRoot bleibt ein Leak');
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_OwnerChainReachesSelf_NoFinding;
// jvcl JvGammaPanel.pas 61/63/64: 'FGamma := TImage.Create(FPanel2)', FPanel2
// gehoert FPanel1, FPanel1 = 'TPanel.Create(Self)'. Die Klasse hat GAR KEINEN
// Destruktor - IsOwnedByFreedSiblingField (verlangt Dtor <> nil) kann dort
// strukturell nie feuern. Der Component-Tree unter Self raeumt alles ab.
// Ohne die Kettenaufloesung ROT (1 statt 0).
const SRC =
  'unit t; interface'#13#10+
  'type TJvGammaPanel = class'#13#10+
  '  FPanel1: TPanel;'#13#10+
  '  FPanel2: TPanel;'#13#10+
  '  FGamma: TTimer;'#13#10+
  'public'#13#10+
  '  constructor Create(AOwner: TComponent);'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TJvGammaPanel.Create(AOwner: TComponent);'#13#10+
  'begin'#13#10+
  '  FPanel1 := TPanel.Create(Self);'#13#10+
  '  FPanel2 := TPanel.Create(FPanel1);'#13#10+
  '  FGamma := TTimer.Create(FPanel2);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'FGamma haengt transitiv unter Self - der Component-Tree raeumt ab');
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_OwnerChainEndsAtNil_StillReported;
// TP-Gegenprobe: die Kette endet bei 'nil' statt bei Self/AOwner - dann gibt
// es keinen Component-Tree, der aufraeumt, und ohne Destruktor leakt FGamma.
const SRC =
  'unit t; interface'#13#10+
  'type TJvGammaPanel = class'#13#10+
  '  FPanel1: TPanel;'#13#10+
  '  FGamma: TTimer;'#13#10+
  'public'#13#10+
  '  constructor Create(AOwner: TComponent);'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TJvGammaPanel.Create(AOwner: TComponent);'#13#10+
  'begin'#13#10+
  '  FPanel1 := TPanel.Create(nil);'#13#10+
  '  FGamma := TTimer.Create(FPanel1);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
    'Kette endet bei nil - kein Owner-Nachweis, FGamma bleibt gemeldet');
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_OwnerChainOnPlainObjectClass_StillReported;
// TP-Gegenprobe fuer Huerde H4, belegt an gexperts EII/D3/EIPanel.pas:238:
// 'TSplitterControl = class' (direkter TObject-Nachfahre) mit
// 'Create(ASplitControl, ATargetControl: TControl)'. Das erste Argument SIEHT
// aus wie ein Owner, ist aber keiner - ein TObject haengt in keinem
// Component-Tree, und das Feld wird nirgends freigegeben = echtes Leck.
// Ohne die H4-Sperre waere dieser TP verschwunden.
const SRC =
  'unit t; interface'#13#10+
  'type'#13#10+
  '  TSynList = class'#13#10+
  '  public'#13#10+
  '    constructor Create(ASplit: TPanel);'#13#10+
  '  end;'#13#10+
  '  TEIPanel = class'#13#10+
  '    FPanel: TPanel;'#13#10+
  '    FSplit: TSynList;'#13#10+
  '  public'#13#10+
  '    constructor Create(AOwner: TComponent);'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'constructor TSynList.Create(ASplit: TPanel);'#13#10+
  'begin'#13#10+
  '  inherited Create;'#13#10+
  'end;'#13#10+
  'constructor TEIPanel.Create(AOwner: TComponent);'#13#10+
  'begin'#13#10+
  '  FPanel := TPanel.Create(Self);'#13#10+
  '  FSplit := TSynList.Create(FPanel);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
    'TSynList ist ein direkter TObject-Nachfahre - kein Component-Tree, FSplit leakt');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_OutParamReturn_NoFinding;
// ACHTUNG (Konvention dieser Datei): die Fixture-Klasse MUSS in
// DEFAULT_LEAKY_CLASSES stehen - sonst verwirft IsLeakyType sie VOR jedem
// Gate und der Test ist wirkungslos, auch wenn er gruen leuchtet.
//
// Zweiter kanonischer Rueckgabeweg neben Result: die Prozedur gibt das
// erzeugte Objekt ueber einen out-Parameter zurueck. Korpus-Beleg
// Alcinoe:4628 ('out TArray<TItem>').
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TSynObjectList = class'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure BuildItems(out AItems: TSynObjectList);'#13#10+
  'begin'#13#10+
  '  AItems := TSynObjectList.Create;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'Rueckgabe ueber out-Parameter ist kein Leck');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_VarParamIndexedReturn_NoFinding;
// Zweite Form: Einhaengen in einen Rueckgabe-Container ueber den Index.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TSynObjectList = class'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure FillSlot(var ASlots: TArray<TSynObjectList>; AIdx: Integer);'#13#10+
  'var'#13#10+
  '  LItem: TSynObjectList;'#13#10+
  'begin'#13#10+
  '  LItem := TSynObjectList.Create;'#13#10+
  '  ASlots[AIdx] := LItem;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'Einhaengen in einen var-Parameter-Container ist kein Leck');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_ConstParamAssign_StillReported;
// WAECHTER, der wichtigste: bei einem CONST-Parameter bleibt die Referenz
// beim Aufgerufenen - dort WAERE es ein echtes Leck. Das Gate darf die
// Modifier deshalb nicht ignorieren.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TSynObjectList = class'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure Fill(const ATarget: TSynObjectList);'#13#10+
  'var'#13#10+
  '  LItem: TSynObjectList;'#13#10+
  'begin'#13#10+
  '  LItem := TSynObjectList.Create;'#13#10+
  '  ATarget.Add(LItem);'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
    'const-Parameter ist kein Rueckgabeweg - der Fund muss bleiben');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_PlainLocalAssign_StillReported;
// WAECHTER: Zuweisung an eine gewoehnliche lokale Variable ist kein
// Ownership-Transfer.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TSynObjectList = class'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure Build;'#13#10+
  'var'#13#10+
  '  LItem, LOther: TSynObjectList;'#13#10+
  'begin'#13#10+
  '  LItem := TSynObjectList.Create;'#13#10+
  '  LOther := LItem;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
    'Zuweisung an eine lokale Variable ist kein Rueckgabeweg');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_IndexedForeignField_OwnershipRecognized;
// Fall (a) des Gates: die linke Seite traegt einen Punkt VOR der
// Klammer, das Ziel liegt also in einem ANDEREN Objekt. Belegt im
// Korpus durch die JCL-Hashmaps (4x dieselbe Form):
//   ADest.FBuckets[I] := NewBucket
// TJclIntegerHashMap.Clear/Destroy gibt die Buckets frei - der
// Aufrufer darf und soll hier NICHT freigeben.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TSynObjectList = class'#13#10+
  '  end;'#13#10+
  '  TDest = class'#13#10+
  '    FBuckets: array[0..3] of TSynObjectList;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure Build(ADest: TDest; I: Integer);'#13#10+
  'var'#13#10+
  '  LItem: TSynObjectList;'#13#10+
  'begin'#13#10+
  '  LItem := TSynObjectList.Create;'#13#10+
  '  ADest.FBuckets[I] := LItem;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'Index-Zuweisung in ein fremdes Objekt ist eine Ownership-Abgabe');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_IndexedSelfProperty_OwnershipRecognized;
// Fall (b): KEIN Punkt, die Wurzel ist eine indizierte Property von
// Self (implizites Self). Entscheidend ist, dass die Wurzel NICHT als
// Lokale oder Parameter deklariert ist - genau das trennt sie vom
// Waechter unten.
//
// Der urspruenglich hier zitierte Beleg (JVCL JvSALHashList,
// 'Items[HashVal] := HashStrings') taugt seit dem Empfaenger-Veto NICHT
// mehr: 'Items' ist ein kanonisch nicht-besitzender Zugang und liegt jetzt
// bewusst auf der anderen Seite der Grenze - festgehalten in
// Leak_IndexedUnqualifiedNonOwning_StillReported. Das Fixture hier nutzt
// deshalb 'Slots', einen Namen ohne Veto; getestet wird die FORM, nicht
// der Name.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TSynObjectList = class'#13#10+
  '  end;'#13#10+
  '  THolder = class'#13#10+
  '  public'#13#10+
  '    property Slots[I: Integer]: TSynObjectList;'#13#10+
  '    procedure Fill(K: Integer);'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure THolder.Fill(K: Integer);'#13#10+
  'var'#13#10+
  '  LNode: TSynObjectList;'#13#10+
  'begin'#13#10+
  '  LNode := TSynObjectList.Create;'#13#10+
  '  Slots[K] := LNode;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'Index-Zuweisung in eine Property von Self ist eine Ownership-Abgabe');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_IndexedLocalArray_StillReported;
// WAECHTER, und der wichtigste der drei: ein LOKALES Array ist kein
// fremder Speicher. Der Frame stirbt mitsamt dem Array, das Objekt
// leckt. Ohne diesen Test wuerde die naechste Verallgemeinerung des
// Gates ("Index reicht") genau hier echte Lecks verschlucken.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TSynObjectList = class'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure Collect;'#13#10+
  'var'#13#10+
  '  LBag: array[0..2] of TSynObjectList;'#13#10+
  '  LEntry: TSynObjectList;'#13#10+
  'begin'#13#10+
  '  LEntry := TSynObjectList.Create;'#13#10+
  '  LBag[0] := LEntry;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
    'ein lokales Array uebernimmt keine Ownership');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_IndexedNonOwningAccessor_StillReported;
// WAECHTER zum Empfaenger-Veto (2026-08-18): eine Index-Zuweisung in
// Objects/Items/Lines/Strings/Data/Nodes ist KEIN Ownership-Transfer.
// TStrings.Objects[] speichert nur die Referenz und gibt sie in Destroy
// nie frei - daher die verbreiteten
// "for i := 0 to Count-1 do Objects[i].Free"-Schleifen.
//
// Der Aufruf-Pfad hat dieses Veto seit dem Review vom 2026-07-31; der
// Zuweisungs-Pfad umging es zunaechst. Am Korpus waren 14 Funde
// betroffen, ausnahmslos ueber "objects[".
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TSynObjectList = class'#13#10+
  '  end;'#13#10+
  '  TBox = class'#13#10+
  '  public'#13#10+
  '    Objects: array[0..3] of TSynObjectList;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure Fill(ABox: TBox; I: Integer);'#13#10+
  'var'#13#10+
  '  LNode: TSynObjectList;'#13#10+
  'begin'#13#10+
  '  LNode := TSynObjectList.Create;'#13#10+
  '  ABox.Objects[I] := LNode;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
    'Objects[] uebernimmt keine Ownership - der Fund muss bleiben');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_IndexedElementProperty_StillReported;
// WAECHTER Form-Verankerung, Teil 1: die Zuweisung geht an eine PROPERTY
// eines indizierten Elements, nicht in die Klammergruppe selbst -
// 'Slots[I].Item := LNode' endet nicht auf ']'. Eine Property-Zuweisung
// ist kein Container-Transfer; die erste Gate-Fassung nahm die ERSTE
// Klammer und schluckte genau diese Form (Muster: Pages[i].PopupMenu).
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TSynObjectList = class'#13#10+
  '  end;'#13#10+
  '  TSlot = class'#13#10+
  '  public'#13#10+
  '    Item: TSynObjectList;'#13#10+
  '  end;'#13#10+
  '  TRack = class'#13#10+
  '  public'#13#10+
  '    Slots: array[0..3] of TSlot;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure Fill(ARack: TRack; I: Integer);'#13#10+
  'var'#13#10+
  '  LNode: TSynObjectList;'#13#10+
  'begin'#13#10+
  '  LNode := TSynObjectList.Create;'#13#10+
  '  ARack.Slots[I].Item := LNode;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
    'Property eines indizierten Elements ist kein Transfer');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_IndexedElementNonOwning_StillReported;
// WAECHTER Form-Verankerung, Teil 2: bei einer KETTE entscheidet der
// Empfaenger der LETZTEN Klammergruppe - hier 'Objects', der
// kanonisch nicht-besitzende Zugang. Die erste Fassung prueft das
// Segment vor der ERSTEN Klammer ('Rows') und sah das Veto nie -
// ausgerechnet auf dem Kanal, ueber den laut A/B-Messung ALLE 14
// Korpus-Rueckkehrer liefen.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TSynObjectList = class'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure Fill(AGrid: TObject; I, J: Integer);'#13#10+
  'var'#13#10+
  '  LNode: TSynObjectList;'#13#10+
  'begin'#13#10+
  '  LNode := TSynObjectList.Create;'#13#10+
  '  AGrid.Rows[I].Objects[J] := LNode;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
    'das Veto muss den Empfaenger der letzten Gruppe sehen');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_IndexedUnqualifiedNonOwning_StillReported;
// WAECHTER, den das Review als fehlend benannt hat: die UNQUALIFIZIERTE
// Veto-Wurzel. 'Objects[K] := LNode' (implizites Self) muss gemeldet
// bleiben - eine Fehlimplementierung, die das Veto nur im Punkt-Zweig
// prueft, liesse alle gepunkteten Tests gruen, waehrend genau der als
// bewusster Preis dokumentierte Fall still von gemeldet auf exempt
// kippte.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TSynObjectList = class'#13#10+
  '  end;'#13#10+
  '  TKeeper = class'#13#10+
  '  public'#13#10+
  '    procedure Stash(N: Integer);'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure TKeeper.Stash(N: Integer);'#13#10+
  'var'#13#10+
  '  LEntry: TSynObjectList;'#13#10+
  'begin'#13#10+
  '  LEntry := TSynObjectList.Create;'#13#10+
  '  Objects[N] := LEntry;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
    'das Veto gilt auch fuer die unqualifizierte Wurzel');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_FieldRootedIndexedNonOwning_StillReported;
// WAECHTER zum Feld-Transfer-Zweig: die Kette WURZELT in einem Feld
// (FCombo), endet aber in einem kanonisch nicht-besitzenden Zugang
// (Objects). Bis 2026-08-19 verliess der Zweig die Funktion beim
// F-Praefix mit True, bevor das Empfaenger-Veto ueberhaupt lief - das
// F sagt nur, wo die Kette ANFAENGT, die Ownership entscheidet sich am
// ENDE. Damit maskierte das Praefix ein echtes Leck auf Error-Tier.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TSynObjectList = class'#13#10+
  '  end;'#13#10+
  '  TRoster = class(TObject)'#13#10+
  '  private'#13#10+
  '    FPanel: TObject;'#13#10+
  '  public'#13#10+
  '    procedure Attach(const AKey: string; Idx: Integer);'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure TRoster.Attach(const AKey: string; Idx: Integer);'#13#10+
  'var'#13#10+
  '  LBadge: TSynObjectList;'#13#10+
  'begin'#13#10+
  '  LBadge := TSynObjectList.Create;'#13#10+
  '  LBadge.Tag := Length(AKey);'#13#10+
  '  FPanel.Items.Objects[Idx] := LBadge;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
    'Feld-Wurzel darf das Empfaenger-Veto nicht aushebeln');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_BareFieldAssignment_StillExempt;
// GEGENSTUECK: die BLANKE Feld-Zuweisung bleibt eine Abgabe. Ein Fix,
// der den Zweig zu weit einschraenkt, wuerde hier still einen Fund
// erzeugen - und der FieldLeakDetector meldet dieselbe Stelle dann
// doppelt. Die Grenze ist die eckige Klammer, nicht das Feld.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TSynObjectList = class'#13#10+
  '  end;'#13#10+
  '  TVault = class(TObject)'#13#10+
  '  strict private'#13#10+
  '    FDepot: TSynObjectList;'#13#10+
  '  public'#13#10+
  '    procedure Seal(ACount: Integer);'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure TVault.Seal(ACount: Integer);'#13#10+
  'var'#13#10+
  '  LBundle: TSynObjectList;'#13#10+
  'begin'#13#10+
  '  LBundle := TSynObjectList.Create;'#13#10+
  '  LBundle.Capacity := ACount;'#13#10+
  '  FDepot := LBundle;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'blanke Feld-Zuweisung bleibt Ownership-Transfer');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_CtorArgInAssignRhs_OwnershipRecognized;
// Der Konstruktor-Zweig von IsPassedToOwner lief nur ueber nkCall-Knoten.
// Aufrufe in einer Zuweisungs-RHS legt der Parser aber als Flachtext in
// nkAssign.TypeRef ab - ausgerechnet die haeufigere Schreibweise war blind.
// Beleg: Alcinoe dwsJSONConnector.pas:614 (Korpus after140).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var inner: TStringList; outer: TOwnerThing;'#13#10+
  'begin'#13#10+
  '  inner := TStringList.Create;'#13#10+
  '  outer := TOwnerThing.Create(inner);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Ctor-Argument in der Zuweisungs-RHS ist Ownership-Transfer');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_CtorArgStandaloneCall_OwnershipRecognized;
// Gegenstueck: dieselbe Uebergabe als FREISTEHENDER Aufruf. Lief schon
// vorher - der Test pinnt, dass beide Schreibweisen gleich behandelt
// werden. Genau diese Ungleichbehandlung war der Defekt.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var inner: TStringList;'#13#10+
  'begin'#13#10+
  '  inner := TStringList.Create;'#13#10+
  '  TOwnerThing.Create(inner);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
      'freistehender Ctor-Aufruf verhaelt sich gleich');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_PlainCallArgInAssignRhs_StillReported;
// WAECHTER: das Gate darf NUR auf Konstruktoren ('.Create(') greifen. Ein
// gewoehnlicher Funktionsaufruf mit unserer Variable als Argument
// uebergibt keine Ownership - der Fund muss bleiben.
//
// Die erste Fassung dieses Tests meldete 0 und wurde deshalb als
// "vorbestehende Luecke" festgenagelt. Das war falsch: die Fixture
// benutzte 'TInnerThing', und IsLeakyType ist eine reine WHITELIST
// (DEFAULT_LEAKY_CLASSES) - die Variable war nie Kandidat, der Test
// wirkungslos. Mit einer Whitelist-Klasse misst er wieder das, was er
// messen soll.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var inner: TStringList; n: Integer;'#13#10+
  'begin'#13#10+
  '  inner := TStringList.Create;'#13#10+
  '  n := ComputeSomething(inner);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMemoryLeak),
      'gewoehnlicher Aufruf ist KEIN Ownership-Transfer');
  finally F.Free; end;
end;




{ ---- Waechter: Harness-Platzhalter darf kein Testpfad-Gate ausloesen ---- }

// Gemeinsame Mechanik der beiden folgenden Tests: der Pfad ist hier der
// Pruefgegenstand, deshalb ein Direkt-Aufruf statt des Harness (der meldet
// immer 'sample.pas').
function LeakCountForPath(const ASource, AFileName: string): Integer;
var
  P    : TParser2;
  Root : TAstNode;
  F    : TObjectList<TLeakFinding>;
begin
  Root := nil;
  F := TObjectList<TLeakFinding>.Create(True);
  P := TParser2.Create;
  // EIN try/finally, bewusst nicht verschachtelt - der eigene Self-Scan
  // meldet NestedTry, und hier gibt es keinen Grund dafuer.
  try
    Root := P.ParseSource(ASource);
    TLeakDetector2.AnalyzeUnit(Root, AFileName, F);
    Result := TFindingHelper.Count(F, fkMemoryLeak);
  finally
    Root.Free;
    P.Free;
    F.Free;
  end;
end;

const
  LEAKY_SRC =
    'unit t; implementation'#13#10+
    'procedure TFoo.Bar;'#13#10+
    'var list: TStringList;'#13#10+
    'begin'#13#10+
    '  list := TStringList.Create;'#13#10+
    'end;';

procedure TTestMemoryLeakAdvanced.Leak_BareFileNameNoDirSegments_StillReported;
// WAECHTER gegen die Regression vom 2026-08-05: das Testpfad-Gate lief
// zuerst mit Basename-Mustern und traf damit den Harness-Platzhalter
// 'sample.pas' (Muster '*Sample.pas'). Folge: der Detektor war im GESAMTEN
// Test-Harness stumm, dutzende Tests fielen auf 0 Funde. Ein blosser
// Dateiname OHNE Verzeichnis darf das Gate nie ausloesen.
begin
  Assert.AreEqual<Integer>(1, LeakCountForPath(LEAKY_SRC, 'sample.pas'),
    'blosser Dateiname ohne Verzeichnis ist kein Testpfad');
end;

procedure TTestMemoryLeakAdvanced.Leak_TestDirSegment_Suppressed;
// Gegenstueck: MIT Verzeichnis-Segment greift das Gate wie vorgesehen.
begin
  Assert.AreEqual<Integer>(0,
    LeakCountForPath(LEAKY_SRC, 'D:\repo\tests\uFoo.pas'),
    'Verzeichnis-Segment tests greift');
end;

procedure TTestMemoryLeakAdvanced.Leak_CtorArgIsMemberOfVar_StillReported;
// WAECHTER, belegt am Korpus (after141): bei
//   Ini := TIniFile.Create(Files.Strings[i]);
// uebergibt der Aufrufer einen STRING, nicht die Liste. 'Files' behaelt
// seine Ownership und muss weiter gemeldet werden. Die erste Fassung des
// Ctor-Gates benutzte VarInArgs, das nur die Wortgrenze prueft, und legte
// den Fund faelschlich stumm.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var Files: TStringList; Ini: TIniFile;'#13#10+
  'begin'#13#10+
  '  Files := TStringList.Create;'#13#10+
  '  Ini := TIniFile.Create(Files.Strings[0]);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    // AreEqual statt '>= 1': die Fixture hat ZWEI Whitelist-Variablen
    // (Files, Ini). Mit '>= 1' haette 'Ini' allein die Zusicherung erfuellt
    // und der Test waere auch dann gruen geblieben, wenn 'Files' wieder
    // faelschlich stillgelegt wird - also genau bei der Regression, gegen
    // die er steht.
    Assert.AreEqual<Integer>(2, TFindingHelper.Count(F, fkMemoryLeak),
      'Member-Zugriff im Ctor-Argument ist kein Ownership-Transfer');
  finally F.Free; end;
end;

procedure TTestFieldLeak.FieldHandedToInterface_NotReported;
// Der Konstruktor gibt das Objekt an die Refcount ab; freigegeben wird ueber
// das Nil-Setzen des Interface-Feldes. Ein Free im Destroy waere ein
// Double-Free - der Fund waere also nicht nur unnoetig, sondern seine
// Befolgung schaedlich.
//
// Bis 2026-08-17 war diese Klasse fuer FELDER offen: das Praedikat
// TLeakDetector2.IsHandedToInterface existiert seit 2026-07-19, wurde aber
// nur auf den Pfaden fuer lokale Variablen gerufen.
//
// Zur Fixture: der Feldtyp ist TStringList, weil der Detektor nur Klassen
// meldet, die er als leck-faehig kennt - mit einer erfundenen Klasse waere
// dieser Test gruen, OHNE das Gate zu beruehren. Der Interface-Cast ist
// entsprechend rein textuell (der Detektor typprueft nicht); den Beweis,
// dass die Fixture ueberhaupt meldefaehig ist, fuehrt der Waechter darunter
// mit derselben Klasse.
const SRC =
  'unit t; interface'#13#10+
  'type TFoo = class'#13#10+
  '  FList: TStringList;'#13#10+
  '  FIntf: IFoo;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  '  destructor Destroy; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TFoo.Create;'#13#10+
  'begin'#13#10+
  '  FList := TStringList.Create;'#13#10+
  '  FIntf := FList as IFoo;'#13#10+
  'end;'#13#10+
  'destructor TFoo.Destroy;'#13#10+
  'begin'#13#10+
  '  FIntf := nil;'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'Feld an Interface uebergeben - der Refcount gibt frei, kein Leak');
  finally F.Free; end;
end;

procedure TTestFieldLeak.FieldNotHandedToInterface_StillReported;
// WAECHTER, und zugleich der Beleg, dass die Fixture oben ueberhaupt
// meldefaehig ist: derselbe AUFBAU (Namen variiert, sonst waere es ein
// DuplicateBlock-Fund) - nur ohne den Interface-Cast, und schon meldet er.
// Damit ist die 0 im Test darueber dem Gate zuzuschreiben, nicht der Fixture.
const SRC =
  'unit t; interface'#13#10+
  'type TBar = class'#13#10+
  '  FItems: TStringList;'#13#10+
  '  FHandle: IFoo;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  '  destructor Destroy; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TBar.Create;'#13#10+
  'begin'#13#10+
  '  FItems := TStringList.Create;'#13#10+
  'end;'#13#10+
  'destructor TBar.Destroy;'#13#10+
  'begin'#13#10+
  '  FHandle := nil;'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
    'ohne Interface-Uebergabe bleibt das Feld ein Leak');
  finally F.Free; end;
end;


procedure TTestFieldLeak.Field_OwnerViaPath_NoFinding;
// Bis 2026-08-17 kannte das Gate nur sechs feste Muster und traf damit nur
// den nackten Bezeichner: 'Create(AOwner)' ja, 'Create(AOwner.Owner)' nein.
// Ein Owner ist aber ein Owner, egal ueber wieviele Punkte man ihn
// erreicht - der Empfaenger traegt das Kind in seine Components-Liste ein
// und gibt es in seinem Destruktor frei. Kanonische Form aus dem Korpus:
// TPopupMenu.Create(AOwner.Owner) - hier mit TStringList nachgebaut,
// weil der Detektor nur Klassen meldet, die er als leck-faehig kennt;
// mit TPopupMenu waere dieser Test gruen, OHNE das Gate zu beruehren.
// Gegen die gebaute Engine gemessen: diese Fixture meldet HEUTE (Error),
// die Variante mit nacktem Create(AOwner) meldet nicht.
const SRC =
  'unit t; interface'#13#10+
  'type TFoo = class'#13#10+
  '  FStuff: TStringList;'#13#10+
  'public'#13#10+
  '  constructor Create(AOwner: TComponent);'#13#10+
  '  destructor Destroy; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TFoo.Create(AOwner: TComponent);'#13#10+
  'begin'#13#10+
  '  FStuff := TStringList.Create(AOwner.Owner);'#13#10+
  'end;'#13#10+
  'destructor TFoo.Destroy;'#13#10+
  'begin'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'Owner ueber einen Pfad ist derselbe Component-Tree');
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_OwnerLookalikeIdent_StillReported;
// WAECHTER gegen eine Namensheuristik: geprueft wird der WURZELBEZEICHNER
// als GANZES, nicht ein Teilstring. 'ownerless' faengt mit 'owner' an und
// ist trotzdem kein Owner - haette das Gate hier ein Pos() benutzt, waere
// dieser Leak stumm.
const SRC =
  'unit t; interface'#13#10+
  'type TBaz = class'#13#10+
  '  FStuff: TStringList;'#13#10+
  'public'#13#10+
  '  constructor Create(ownerless: TComponent);'#13#10+
  '  destructor Destroy; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TBaz.Create(ownerless: TComponent);'#13#10+
  'begin'#13#10+
  '  FStuff := TStringList.Create(ownerless);'#13#10+
  'end;'#13#10+
  'destructor TBaz.Destroy;'#13#10+
  'begin'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
    'ein Bezeichner, der nur mit owner anfaengt, ist kein Owner');
  finally F.Free; end;
end;



procedure TTestFieldLeak.Field_FreedViaPropertyAlias_NoFinding;
// 'Items.Free' gibt dasselbe Objekt frei wie 'FItems.Free' - nur ueber den
// oeffentlichen Namen. SearchFree sucht den Feldnamen und findet nichts.
// Belegt im Korpus (JvExplorerBar und Verwandte).
//
// Das Gate haengt an drei Bedingungen: F-Konvention, die Klasse deklariert
// die Property WIRKLICH, und der Destruktor gibt genau diesen Namen frei.
// Der read-Spezifizierer ist nicht pruefbar - der Parser verwirft ihn.
//
// Vor der Aenderung gegen die gebaute Engine gemessen: meldet (Error).
const SRC =
  'unit t; interface'#13#10+
  'type TFoo = class'#13#10+
  'private'#13#10+
  '  FItems: TStringList;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  '  destructor Destroy; override;'#13#10+
  '  property Items: TStringList read FItems write FItems;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TFoo.Create;'#13#10+
  'begin'#13#10+
  '  FItems := TStringList.Create;'#13#10+
  'end;'#13#10+
  'destructor TFoo.Destroy;'#13#10+
  'begin'#13#10+
  '  Items.Free;'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'Items.Free gibt FItems frei - dieselbe Instanz, anderer Name');
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_FreedViaForeignName_StillReported;
// WAECHTER: irgendein anderer Name im Destruktor darf NICHT als Freigabe
// durchgehen. Die Klasse deklariert hier keine Property 'Cache', also
// greift Bedingung 2 des Gates nicht - der Leak bleibt ein Fund.
// Vor der Aenderung gemessen: meldet (Error), und das muss so bleiben.
const SRC =
  'unit t; interface'#13#10+
  'type TWidget = class'#13#10+
  'private'#13#10+
  '  FCache: TStringList;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  '  destructor Destroy; override;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TWidget.Create;'#13#10+
  'begin'#13#10+
  '  FCache := TStringList.Create;'#13#10+
  'end;'#13#10+
  'destructor TWidget.Destroy;'#13#10+
  'begin'#13#10+
  '  FetchAll.Free;'#13#10+
  '  inherited;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
    'ein fremder Name ist keine Freigabe des Feldes');
  finally F.Free; end;
end;



function TTestFieldLeak.FieldLeakCount(const ASrc,
  AFileName: string): Integer;
// EIN try/finally mit nil-Vorbelegung statt drei geschachtelter
// Bloecke - geschachtelte try-Ebenen sind im Selbstscan ein Fund, und
// hier bringen sie nichts: keiner der drei Aufraeumschritte haengt vom
// Gelingen eines anderen ab.
var
  Prs  : TParser2;
  Root : TAstNode;
  Res  : TObjectList<TLeakFinding>;
begin
  Prs  := nil;
  Root := nil;
  Res  := nil;
  try
    Prs  := TParser2.Create;
    Root := Prs.ParseSource(ASrc);
    Res  := TObjectList<TLeakFinding>.Create(True);
    TFieldLeakDetector.AnalyzeUnit(Root, AFileName, Res);
    Result := TFindingHelper.Count(Res, fkMemoryLeak);
  finally
    Res.Free;
    Root.Free;
    Prs.Free;
  end;
end;

procedure TTestFieldLeak.Field_InFixturePath_NotReported;
// Der Feld-Pfad besass bis zum 18.08. KEIN Fixture-Gate, obwohl der
// Lokal-Pfad (TLeakDetector2.AnalyzeUnit) seit dem Restschulden-Audit
// eines fuehrt und beide unter SCA001 melden. Am Korpus gemessen lagen
// dadurch 67 von 114 Feld-Funden in Testverzeichnissen - 59 Prozent.
//
// AContext bleibt nil: CtxScanRoot liefert dann einen Leerstring, es
// gilt also das dokumentierte unverankerte Alt-Verhalten, bei dem
// allein das Pfad-Segment entscheidet.
//
// Die Fixture erzeugt ein TStringList-Feld im Konstruktor und hat
// KEINEN Destruktor - dieselbe Form, die
// Field_NoDestructor_ReportsError als meldend festhaelt. Ohne den
// Gate stuende hier also ein Fund.
const SRC =
  'unit t; interface'#13#10+
  'type TFoo = class'#13#10+
  'private'#13#10+
  '  FItems: TStringList;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TFoo.Create;'#13#10+
  'begin'#13#10+
  '  FItems := TStringList.Create;'#13#10+
  'end;';
begin
  // Pfad zur LAUFZEIT zusammensetzen: ein Literal der Form
  // C:\proj\tests\Foo.pas waere im Selbstscan selbst ein
  // HardcodedPath-Fund.
  Assert.AreEqual<Integer>(0,
    FieldLeakCount(SRC, 'C:' + PathDelim + 'proj' + PathDelim +
                        'tests' + PathDelim + 'Foo.pas'),
    'Feld-Funde aus einem tests-Verzeichnis gehoeren nicht in den Bericht');
end;

procedure TTestFieldLeak.Field_InProductionPath_StillReported;
// WAECHTER: derselbe Helfer, aber ein normaler Quellpfad. Haelt fest,
// dass der Gate NUR an Testverzeichnissen greift und nicht
// stillschweigend den ganzen Feld-Pfad abschaltet. Klassen- und
// Feldname variiert, damit die beiden Fixturen nicht als Duplikat
// zaehlen.
const SRC =
  'unit t; interface'#13#10+
  'type TWidget = class'#13#10+
  'private'#13#10+
  '  FCache: TStringList;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TWidget.Create;'#13#10+
  'begin'#13#10+
  '  FCache := TStringList.Create;'#13#10+
  'end;';
begin
  Assert.IsTrue(
    FieldLeakCount(SRC, 'C:' + PathDelim + 'proj' + PathDelim +
                        'source' + PathDelim + 'Bar.pas') >= 1,
    'ausserhalb von Testverzeichnissen muss der Feld-Pfad weiter melden');
end;

procedure TTestMemoryLeakAdvanced.Leak_AnonProcLiteral_NoFinding;
// Autopsie 2026-08-26 Klasse 4a (Dev-Cpp main.pas 2365/2387/7071):
// ein anonymes Methoden-Literal ist ein refcount-verwaltetes Closure,
// kein Objekt des Aufrufers - Free waere ein Compilefehler.
// WICHTIG (Gegenpruefungs-Blocker 2026-08-26): die Var muss einen
// DEFAULT-leaky Typ tragen (TThread), sonst skippt IsLeakyType vor dem
// Gate und der Test ist vakuoes-gruen (FindingsOf laeuft mit
// AContext=nil = Default-LeakyClasses). Das innere '.Create' im
// Literal ist der Ausloeser des Korpus-FP (Dev-Cpp main.pas:2365 -
// MatchesCreate matchte den LITERAL-Text).
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var P: TThread;'#13#10+
  'begin'#13#10+
  '  P := procedure begin Sheet := TTabSheet.Create(Host); end;'#13#10+
  '  P();'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'Closure-Literal ist kein Create des Aufrufers');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_RttiAsObjectChain_NoFinding;
// Klasse 4b (Vcl.Styles.DPIAware:284, 12 Korpus-Funde): TRttiContext
// ist ein Record, die AsObject-Referenz aus GetValue ist GEBORGT -
// Free waere ein Bug im fremden Objekt.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var L: TList;'#13#10+
  'begin'#13#10+
  '  L := TRttiContext.Create.GetType(TShape).GetField(''FBitmaps'')' +
       '.GetValue(nil).AsObject as TList;'#13#10+
  '  L.Clear;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'AsObject-Kette ist eine geborgte Referenz');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_FluentCreateChain_StillReported;
// TP-Gegenprobe zu 4b: eine Fluent-Kette OHNE .AsObject besitzt ihr
// Result - das Gate ist bewusst eng auf .asobject zugeschnitten.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  '  L.Add(''x'');'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
    'echtes Create ohne Free bleibt Fund');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_CtorSetsFreeOnTerminate_NoFinding;
// Klasse 5 (IdDNSServer:4152, uCEFApplicationCore:3510): der Thread
// setzt FreeOnTerminate := True im EIGENEN Ctor derselben Unit -
// er raeumt sich selbst ab.
const SRC =
  'unit t; interface'#13#10+
  'type'#13#10+
  '  TWorker = class(TThread)'#13#10+
  '  public'#13#10+
  '    constructor Create;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'constructor TWorker.Create;'#13#10+
  'begin'#13#10+
  '  inherited Create(False);'#13#10+
  '  FreeOnTerminate := True;'#13#10+
  'end;'#13#10+
  'procedure Spawn;'#13#10+
  'var W: TThread;'#13#10+
  'begin'#13#10+
  '  W := TWorker.Create;'#13#10+
  '  W.Start;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'selbstfreigebender Thread ist kein Leak des Aufrufers');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.Leak_CtorOverloadsFreeOnTerminate_StillReported;
// Strenge-Gegenprobe: bei UEBERLADENEN Ctors ist nicht entscheidbar,
// welcher gemeint war - kein Gate (analog Review-Blocker 2026-07-31).
const SRC =
  'unit t; interface'#13#10+
  'type'#13#10+
  '  TWorker = class(TThread)'#13#10+
  '  public'#13#10+
  '    constructor Create; overload;'#13#10+
  '    constructor Create(ATag: Integer); overload;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'constructor TWorker.Create;'#13#10+
  'begin'#13#10+
  '  FreeOnTerminate := True;'#13#10+
  'end;'#13#10+
  'constructor TWorker.Create(ATag: Integer);'#13#10+
  'begin'#13#10+
  'end;'#13#10+
  'procedure Spawn;'#13#10+
  'var W: TThread;'#13#10+
  'begin'#13#10+
  '  W := TWorker.Create(1);'#13#10+
  '  W.Start;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) >= 1,
    'Overload-Mehrdeutigkeit gated nicht');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.LocalCalleeTakesOwnership_NotReported;
// KLASSE F: der Gerufene steht in DERSELBEN Unit und nimmt das Objekt
// in einen Feld-Container. Nachgebaut nach dem Beleg aus dem
// Referenzkorpus, CnPasCodeDoc.pas:386:
//   function TCnDocBaseItem.AddItem(Item: TCnDocBaseItem): Integer;
//   begin
//     FItems.Add(Item);      // FItems ist TObjectList.Create(True)
//   end;
// Der Aufrufer gibt das Objekt ab - "never freed" ist dort unwahr.
const SRC =
  'unit t;'+#13#10+
  'interface'+#13#10+
  'type'+#13#10+
  '  TBar = class'+#13#10+
  '    FItems: TObjectList;'+#13#10+
  '    procedure AddItem(Item: TStringList);'+#13#10+
  '  end;'+#13#10+
  'implementation'+#13#10+
  'procedure TBar.AddItem(Item: TStringList);'+#13#10+
  'begin'+#13#10+
  '  FItems.Add(Item);'+#13#10+
  'end;'+#13#10+
  'procedure Use(B: TBar);'+#13#10+
  'var Item: TStringList;'+#13#10+
  'begin'+#13#10+
  '  Item := TStringList.Create;'+#13#10+
  '  B.AddItem(Item);'+#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
        'unit-lokaler Callee nimmt das Objekt in ein Feld - kein Leck');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.LocalCalleeOnlyReads_StillReported;
// TP-GEGENPROBE, und sie traegt das Gate: derselbe Aufbau, aber der
// Gerufene LIEST nur. Genau daran ist der erste Anlauf gescheitert -
// eine Namensliste haette "AddItem" gegatet, ohne in den Rumpf zu sehen.
// Im Korpus ist AddProperty(Properties: TStrings) so ein Fall: es
// befuellt, es uebernimmt nicht.
const SRC =
  'unit t;'+#13#10+
  'interface'+#13#10+
  'type'+#13#10+
  '  TBar = class'+#13#10+
  '    FItems: TObjectList;'+#13#10+
  '    procedure AddItem(Item: TStringList);'+#13#10+
  '  end;'+#13#10+
  'implementation'+#13#10+
  'procedure TBar.AddItem(Item: TStringList);'+#13#10+
  'begin'+#13#10+
  '  ShowMessage(Item.Text);'+#13#10+
  'end;'+#13#10+
  'procedure Use(B: TBar);'+#13#10+
  'var Item: TStringList;'+#13#10+
  'begin'+#13#10+
  '  Item := TStringList.Create;'+#13#10+
  '  B.AddItem(Item);'+#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) > 0,
        'der Callee liest nur - der Fund muss bleiben');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.LocalCalleeTwoParams_StillReported;
// Die Grenze des Gates, absichtlich gezogen: bei mehr als EINEM
// Parameter muesste die Argumentposition aufgeloest werden, und ein
// Fehlgriff dort maskiert ein echtes Leck. Solange das nicht gemessen
// ist, bleibt der Fund stehen.
const SRC =
  'unit t;'+#13#10+
  'interface'+#13#10+
  'type'+#13#10+
  '  TBar = class'+#13#10+
  '    FItems: TObjectList;'+#13#10+
  '    procedure AddItem(Key: string; Item: TStringList);'+#13#10+
  '  end;'+#13#10+
  'implementation'+#13#10+
  'procedure TBar.AddItem(Key: string; Item: TStringList);'+#13#10+
  'begin'+#13#10+
  '  FItems.Add(Item);'+#13#10+
  'end;'+#13#10+
  'procedure Use(B: TBar);'+#13#10+
  'var Item: TStringList;'+#13#10+
  'begin'+#13#10+
  '  Item := TStringList.Create;'+#13#10+
  '  B.AddItem(''k'', Item);'+#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) > 0,
        'zwei Parameter - das Gate haelt sich bewusst heraus');
  finally F.Free; end;
end;


procedure TTestMemoryLeakAdvanced.LocalCalleeArgCountMismatch_StillReported;
// REGRESSION zu rw34: der Aufruf hat ZWEI Argumente, der einzige
// gleichnamige Callee der Unit hat EINEN Parameter. Dann ist der
// Gerufene ein anderer - hier die Add-Methode eines fremden Objekts -
// und sein Rumpf beweist nichts.
//
// BELEG (doublecmd uColorExt.pas:337/344/347): TColorExt.Save ruft
// AConfig.Add(''FileColors'', AList) an einem TJSONObject; unit-lokal
// gibt es genau ein TColorExt.Add(AItem: TMaskItem), dessen Rumpf
// FMaskItems.Add(AItem) ausfuehrt. Ohne diesen Schnitt hat die blosse
// Namensgleichheit drei Funde unterdrueckt, die den gefundenen Callee
// nie erreichen.
const SRC =
  'unit t;'+#13#10+
  'interface'+#13#10+
  'type'+#13#10+
  '  TBar = class'+#13#10+
  '    FItems: TObjectList;'+#13#10+
  '    procedure Add(Item: TStringList);'+#13#10+
  '  end;'+#13#10+
  'implementation'+#13#10+
  'procedure TBar.Add(Item: TStringList);'+#13#10+
  'begin'+#13#10+
  '  FItems.Add(Item);'+#13#10+
  'end;'+#13#10+
  'procedure Use(Cfg: TJSONObject);'+#13#10+
  'var Item: TStringList;'+#13#10+
  'begin'+#13#10+
  '  Item := TStringList.Create;'+#13#10+
  '  Cfg.Add(''Name'', Item);'+#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) > 0,
        'zwei Argumente gegen einen Parameter - der Callee passt nicht');
  finally F.Free; end;
end;


procedure TTestMemoryLeakAdvanced.LocalCalleeForeignReceiver_StillReported;
// REGRESSION zu rw35: der Aufruf ist EINARGUMENTIG und trifft trotzdem
// einen anderen Gerufenen - der Empfaenger gehoert einer fremden
// Klasse. Nur der Empfaengertyp entscheidet das, die Argumentzahl
// nicht.
//
// BELEG (doublecmd uColorExt.pas:344): 'AList.Add(AItem)' an einem
// TJSONArray, waehrend unit-lokal ein TColorExt.Add(AItem: TMaskItem)
// steht. Dieser eine Fund ueberlebte den Argumentzahl-Schnitt und war
// weiter aus falschem Grund unterdrueckt.
const SRC =
  'unit t;'+#13#10+
  'interface'+#13#10+
  'type'+#13#10+
  '  TBar = class'+#13#10+
  '    FItems: TObjectList;'+#13#10+
  '    procedure Add(Item: TStringList);'+#13#10+
  '  end;'+#13#10+
  '  TFremd = class'+#13#10+
  '    procedure Add(X: TObject);'+#13#10+
  '  end;'+#13#10+
  'implementation'+#13#10+
  'procedure TBar.Add(Item: TStringList);'+#13#10+
  'begin'+#13#10+
  '  FItems.Add(Item);'+#13#10+
  'end;'+#13#10+
  'procedure Use(L: TFremd);'+#13#10+
  'var Item: TStringList;'+#13#10+
  'begin'+#13#10+
  '  Item := TStringList.Create;'+#13#10+
  '  L.Add(Item);'+#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) > 0,
        'fremder Empfaengertyp - der unit-lokale Rumpf beweist nichts');
  finally F.Free; end;
end;


procedure TTestFieldLeak.Field_FreedInOnDestroyHandler_NoFinding;
// KLASSE L der SCA001-Vollzaehlung (30.08.). jcl PeViewer PeResView.pas
// 115/119/121: TPeResViewChild hat GAR KEINEN Destruktor - der Detektor
// meldete "created in constructor but no destructor exists" - und raeumt
// seine drei Felder im OnDestroy-Event auf. Die VCL ruft FormDestroy beim
// Zerstoeren des Fensters, das Feld ist also aufgeraeumt.
const SRC =
  'unit t; interface'#13#10+
  'type TPeResViewChild = class'#13#10+
  '  FResourceImage: TStringList;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  '  procedure FormDestroy(Sender: TObject);'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TPeResViewChild.Create;'#13#10+
  'begin'#13#10+
  '  FResourceImage := TStringList.Create;'#13#10+
  'end;'#13#10+
  'procedure TPeResViewChild.FormDestroy(Sender: TObject);'#13#10+
  'begin'#13#10+
  '  FResourceImage.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'Freigabe im OnDestroy-Handler - die VCL ruft ihn garantiert');
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_DestroyMethodWithoutEventSignature_StillReported;
// TP-Gegenprobe zu KLASSE L, und der Grund fuer die enge Fassung: eine
// Methode, die zufaellig auf 'Destroy' endet, aber NICHT die
// Event-Signatur (ein Parameter vom Typ TObject) traegt, laeuft nicht
// garantiert. 32 der 47 Feld-Funde im Korpus haben ueberhaupt keine
// Freigabe - ein zu weiter Anker haette sie mitgenommen.
const SRC =
  'unit t; interface'#13#10+
  'type TFoo = class'#13#10+
  '  FList: TStringList;'#13#10+
  'public'#13#10+
  '  constructor Create;'#13#10+
  '  procedure DoDestroy;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'constructor TFoo.Create;'#13#10+
  'begin'#13#10+
  '  FList := TStringList.Create;'#13#10+
  'end;'#13#10+
  'procedure TFoo.DoDestroy;'#13#10+
  'begin'#13#10+
  '  FList.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) > 0,
    'DoDestroy ist kein Event-Handler - niemand ruft es garantiert');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.OwnerArgIsComponentTyped_NotReported;
// KLASSE D der SCA001-Vollzaehlung (30.08.): das Owner-Argument heisst
// nicht Self/Owner/AOwner/Application, sein TYP ist aber ein
// TComponent-Nachfahre - dann gilt dieselbe Owner-Konvention.
//
// BELEG (doublecmd uShowMsg.pas 612/625/716/730/743): fuenfmal
// 'TBitBtn.Create(frmDialog)' mit 'frmDialog: TForm'.
const SRC =
  'unit t;'+#13#10+
  'interface'+#13#10+
  'implementation'+#13#10+
  'procedure Zeige;'+#13#10+
  'var frmDialog: TForm; Btn: TComponent;'+#13#10+
  'begin'+#13#10+
  '  Btn := TComponent.Create(frmDialog);'+#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'frmDialog ist eine TForm - der Owner raeumt beim Destroy auf');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.OwnerArgIsNotComponentTyped_StillReported;
// TP-Gegenprobe zu KLASSE D, und der Grund fuer die Typpruefung statt
// einer laengeren Namensliste: im Korpus heissen zwei Muster nach Owner
// und uebernehmen NICHTS -
//   TPSBlockInfo.Create(Owner: TPSBlockInfo)    -> FOwner := Owner
//   TDBObject.Create(OwnerConnection: TDBConnection)
// Das Kind haelt dort den Parent, nicht umgekehrt.
const SRC =
  'unit t;'+#13#10+
  'interface'+#13#10+
  'implementation'+#13#10+
  'procedure Zeige;'+#13#10+
  'var Parent: TStringList; Kind: TComponent;'+#13#10+
  'begin'+#13#10+
  '  Kind := TComponent.Create(Parent);'+#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) > 0,
    'TStringList ist kein TComponent - kein Owner, kein Freibrief');
  finally F.Free; end;
end;


procedure TTestMemoryLeakAdvanced.OwnerArgComponentButCreatedIsTObject_StillReported;
// REGRESSION zu rw38, und der zweite Fehlschluss derselben Bauart wie bei
// Klasse F: das ARGUMENT ist eine echte Komponente, die ERZEUGTE Klasse
// aber nicht. Die Owner-Konvention traegt nur, wenn das erzeugte Objekt
// sich in die Components-Liste des Owners eintraegt - ein TObject tut das
// nicht.
//
// BELEG (jvcl JvWndProcHook.pas:374):
//   HookInfos := TJvHookInfos.Create(AControl);   AControl: TControl
//   TJvHookInfos = class(TObject)
//   constructor TJvHookInfos.Create(AControl: TControl);
//   begin inherited Create; FControl := AControl; end;
// Der Ctor merkt sich den Parent; umgekehrt passiert nichts.
//
// FIXTURE-KONSTRUKTION, damit der Test nicht vakuum-gruen wird: der
// erzeugte Typ muss BEIDES sein - in DEFAULT_LEAKY_CLASSES (sonst
// meldet der Detektor gar nichts und die Gegenprobe prueft ins Leere)
// und unit-lokal mit TObject-Basis (sonst greift das Veto nicht). Die
// Unit deklariert deshalb einen Typ mit dem Namen TStringList; im
// Korpus heisst er TJvHookInfos und ist ueber AutoDiscoverClasses
// leaky.
const SRC =
  'unit t;'+#13#10+
  'interface'+#13#10+
  'type'+#13#10+
  '  TStringList = class(TObject)'+#13#10+
  '    FControl: TControl;'+#13#10+
  '  end;'+#13#10+
  'implementation'+#13#10+
  'procedure Registriere(AControl: TControl);'+#13#10+
  'var HookInfos: TStringList;'+#13#10+
  'begin'+#13#10+
  '  HookInfos := TStringList.Create(AControl);'+#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) > 0,
    'TJvHookInfos ist ein TObject - der TControl ist kein Owner');
  finally F.Free; end;
end;


procedure TTestFieldLeak.Field_FreedInClassDestructor_NoFinding;
// BESTANDSFEHLER, gefunden am 30.08. beim Nachgehen der Klasse L.
//
// Der Parser markiert class-Methoden mit dem TypeRef-Suffix ';class'
// (uParser2:743, damit der DestructorWithoutInherited-Detektor den
// Class-Destruktor vom Instanz-Destruktor unterscheiden kann).
// FindMethod vergleicht per SameText gegen 'destructor' und fand
// 'destructor;class' deshalb NIE - ein class var, das im class
// destructor freigegeben wird, galt als Leck.
//
// BELEG: Kastri DW.StartUpHook.Android.pas:29 und
// DW.UniversalLinks.Android.pas:31.
//
// Die Klasse steht hier BEWUSST im implementation-Abschnitt: nur dort
// wird der Fehler sichtbar. Steht sie im interface, erkennt der
// Detektor das 'class var' gar nicht erst als Feld und schweigt aus
// einem zweiten, unabhaengigen Grund - die beiden Fehler haben
// einander verdeckt.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'type'#13#10+
  '  TFoo = class(TObject)'#13#10+
  '  private'#13#10+
  '    class var FInstance: TStringList;'#13#10+
  '    class constructor CreateClass;'#13#10+
  '    class destructor DestroyClass;'#13#10+
  '  end;'#13#10+
  'class constructor TFoo.CreateClass;'#13#10+
  'begin'#13#10+
  '  FInstance := TStringList.Create;'#13#10+
  'end;'#13#10+
  'class destructor TFoo.DestroyClass;'#13#10+
  'begin'#13#10+
  '  FInstance.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'class var wird im class destructor freigegeben - kein Leck');
  finally F.Free; end;
end;

procedure TTestFieldLeak.Field_ClassDestructorFreesOther_StillReported;
// TP-Gegenprobe: die Klasse HAT einen class destructor, gibt darin aber
// ein ANDERES Feld frei. Der erweiterte Suchraum darf nicht pauschal
// entschaerfen - dieselbe Gegenprobe wie beim BeforeDestruction-Gate.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'type'#13#10+
  '  TFoo = class(TObject)'#13#10+
  '  private'#13#10+
  '    class var FInstance: TStringList;'#13#10+
  '    class var FOther: TStringList;'#13#10+
  '    class constructor CreateClass;'#13#10+
  '    class destructor DestroyClass;'#13#10+
  '  end;'#13#10+
  'class constructor TFoo.CreateClass;'#13#10+
  'begin'#13#10+
  '  FInstance := TStringList.Create;'#13#10+
  'end;'#13#10+
  'class destructor TFoo.DestroyClass;'#13#10+
  'begin'#13#10+
  '  FOther.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) > 0,
    'FInstance wird nirgends freigegeben - der Fund bleibt');
  finally F.Free; end;
end;


procedure TTestMemoryLeakAdvanced.JsonAddPairTakesOwnership_NotReported;
// KLASSE A der SCA001-Vollzaehlung: TJSONObject.AddPair uebernimmt das
// Kind, der JSON-Baum gibt es in seinem Destroy frei.
//
// BELEG (delphimvcframework LoggerPro.JSONLFileAppender.pas:178 und
// swagdoc Swag.Doc.*): 16 Funde tragen dieses Muster, bei 10 ist der
// Empfaengertyp aufloesbar und durchweg TJSONObject.
const SRC =
  'unit t;'+#13#10+
  'interface'+#13#10+
  'implementation'+#13#10+
  'procedure Baue;'+#13#10+
  'var J: TJSONObject; Kind: TStringList;'+#13#10+
  'begin'+#13#10+
  '  Kind := TStringList.Create;'+#13#10+
  '  J.AddPair(''context'', Kind);'+#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'TJSONObject.AddPair uebernimmt - der Baum raeumt auf');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.AddPairOnForeignTypeIsNoTransfer_StillReported;
// TP-Gegenprobe und der Grund fuer die Typbindung: der Kommentar an
// ReceiverVetoesSink verwirft einen globalen Sink-Seed, weil RTL-Namen
// echte Lecks maskieren. 'AddPair' allein sagt nichts - eine eigene
// Klasse mit AddPair(Key, Value) uebernimmt nichts.
const SRC =
  'unit t;'+#13#10+
  'interface'+#13#10+
  'type'+#13#10+
  '  TMeinCache = class'+#13#10+
  '    procedure AddPair(const AKey: string; AWert: TStringList);'+#13#10+
  '  end;'+#13#10+
  'implementation'+#13#10+
  'procedure Baue;'+#13#10+
  'var C: TMeinCache; Kind: TStringList;'+#13#10+
  'begin'+#13#10+
  '  Kind := TStringList.Create;'+#13#10+
  '  C.AddPair(''context'', Kind);'+#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) > 0,
    'TMeinCache ist kein TJSONObject - AddPair beweist hier nichts');
  finally F.Free; end;
end;


procedure TTestMemoryLeakAdvanced.JsonArrayAddTakesOwnership_NotReported;
// KLASSE A der SCA001-Vollzaehlung: der JSON-Array BESITZT seine
// Elemente - in System.JSON wie in fpjson gibt sein Destructor sie frei.
//
// BELEG (doublecmd dmhigh.pas:194/202): 'Attributes := TJSONArray.Create;
// ... Attributes.Add(AttributeNode)'. Gemessen 7 Funde.
const SRC =
  'unit t;'+#13#10+
  'interface'+#13#10+
  'implementation'+#13#10+
  'procedure Baue;'+#13#10+
  'var Arr: TJSONArray; Knoten: TStringList;'+#13#10+
  'begin'+#13#10+
  '  Knoten := TStringList.Create;'+#13#10+
  '  Arr.Add(Knoten);'+#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMemoryLeak),
    'TJSONArray.Add uebernimmt - der Array raeumt auf');
  finally F.Free; end;
end;

procedure TTestMemoryLeakAdvanced.PlainListAddIsNoTransfer_StillReported;
// TP-Gegenprobe und die Grenze der Erweiterung: TList.Add uebernimmt
// KEIN Ownership. Sie ist der haeufigste Empfaenger in dieser Gruppe
// (7 von 29 gemessenen Add-Faellen) und muss ein Fund bleiben - sonst
// waere die Whitelist eine Sperrliste geworden.
const SRC =
  'unit t;'+#13#10+
  'interface'+#13#10+
  'implementation'+#13#10+
  'procedure Baue;'+#13#10+
  'var L: TList; Knoten: TStringList;'+#13#10+
  'begin'+#13#10+
  '  Knoten := TStringList.Create;'+#13#10+
  '  L.Add(Knoten);'+#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMemoryLeak) > 0,
    'TList.Add uebernimmt nicht - der Fund bleibt');
  finally F.Free; end;
end;

end.
