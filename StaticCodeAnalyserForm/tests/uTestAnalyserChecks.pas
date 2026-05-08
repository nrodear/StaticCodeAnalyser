unit uTestAnalyserChecks;

// Integrationstests für alle AST-basierten Detektoren.
// Jeder Test parst einen Pascal-Quelltext direkt und prüft die Befunde.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uParser2, uMethodd12, uSCAConsts,
  uLeakDetector2, uCodeSmells2, uSQLInjection, uHardcodedSecret,
  uFormatMismatch, uUnusedUses,
  uNilDeref, uMissingFinally, uDivByZero, uDeadCode,
  uLongMethod, uLongParamList, uMagicNumbers, uDuplicateString,
  uHardcodedPath, uDebugOutput, uDeepNesting,
  uTodoComment, uEmptyMethod, uFieldLeak, uDuplicateBlock,
  uStaticAnalyzer2,
  uTestSrcBuilder,
  System.IOUtils;

type
  // ---- Hilfsfunktionen ----------------------------------------------------------------
  TFindingHelper = record
    class function FindingsOf(const Source: string): TObjectList<TLeakFinding>; static;
    // FindingsOfFile schreibt den Source in eine temporaere Datei und ruft
    // alle Detektoren auf - benoetigt fuer file-scannende Detektoren wie
    // TTodoCommentDetector, die nicht ueber den AST gehen.
    class function FindingsOfFile(const Source: string): TObjectList<TLeakFinding>; static;
    class function Count(Findings: TObjectList<TLeakFinding>;
      Kind: TFindingKind): Integer; static;
    class function CountSev(Findings: TObjectList<TLeakFinding>;
      Kind: TFindingKind; Sev: TLeakSeverity): Integer; static;
  end;

  // ---- MemoryLeak (TLeakDetector2) ----------------------------------------------------
  [TestFixture]
  TTestMemoryLeak = class
  public
    [Test] procedure Leak_CreateWithoutFree_ReportsError;
    [Test] procedure Leak_CreateFreeInFinally_NoFinding;
    [Test] procedure Leak_FreeOutsideFinally_ReportsWarning;
    [Test] procedure Leak_ReturnResult_NoFinding;
    [Test] procedure Leak_PassedToConstructor_NoFinding;
    [Test] procedure Leak_FunctionCallAssign_NoFreeReportsWarning;
    [Test] procedure Leak_FunctionCallAssign_WithFree_NoFinding;
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

  // ---- EmptyExcept (TEmptyExceptDetector2) -------------------------------------------
  [TestFixture]
  TTestEmptyExcept = class
  public
    [Test] procedure EmptyExcept_NoCode_ReportsWarning;
    [Test] procedure EmptyExcept_CommentOnly_ReportsWarning;
    [Test] procedure EmptyExcept_WithHandler_NoFinding;
    [Test] procedure EmptyExcept_WithRaise_NoFinding;
    [Test] procedure EmptyExcept_MultipleBlocks_AllReported;
  end;

  // ---- SQLInjection (TSQLInjectionDetector) ------------------------------------------
  [TestFixture]
  TTestSQLInjection = class
  public
    [Test] procedure SQL_AssignToSQLText_WithConcat_ReportsError;
    [Test] procedure SQL_AssignToCommandText_WithConcat_ReportsError;
    [Test] procedure SQL_StringLiteralContainsSELECT_WithConcat_ReportsError;
    [Test] procedure SQL_NoConcat_NoFinding;
    [Test] procedure SQL_AddCall_WithConcat_ReportsError;
    [Test] procedure SQL_ParametrizedQuery_NoFinding;
    [Test] procedure SQL_DocStringWithSQLKeyword_NoFinding;
    [Test] procedure SQL_LiteralOnlyConcat_NoFinding;
    [Test] procedure SQL_CreateTableMultilineLiteral_NoFinding;
    // Wortgrenze: 'commandtext' darf nicht 'mycommandtextra' matchen
    [Test] procedure SQL_CommandTextSubstring_NoFalsePositive;
  end;

  // ---- HardcodedSecret (THardcodedSecretDetector) ------------------------------------
  [TestFixture]
  TTestHardcodedSecret = class
  public
    [Test] procedure Secret_PasswordAssignedLiteral_ReportsError;
    [Test] procedure Secret_TokenAssignedLiteral_ReportsError;
    [Test] procedure Secret_ApiKeyAssignedLiteral_ReportsError;
    [Test] procedure Secret_AssignFromFunction_NoFinding;
    [Test] procedure Secret_AssignFromVariable_NoFinding;
    [Test] procedure Secret_NonSecretVarWithLiteral_NoFinding;
    // CamelCase/Snake-Case-Wortgrenzen (IsSecretName-Refactor)
    [Test] procedure Secret_SecretarySubstring_NoFinding;
    [Test] procedure Secret_UserTokenSnakeCase_ReportsError;
    // Leeres Literal ist Initialisierung, kein Secret
    [Test] procedure Secret_EmptyLiteral_NoFinding;
  end;

  // ---- NilDeref / MissingFinally / DivByZero / DeadCode -------------------------------
  [TestFixture]
  TTestNewChecks = class
  public
    // NilDeref
    [Test] procedure NilDeref_NilThenDot_ReportsError;
    [Test] procedure NilDeref_AssignedGuard_NoFinding;
    [Test] procedure NilDeref_NotNilGuard_NoFinding;
    [Test] procedure NilDeref_Reassigned_NoFinding;
    [Test] procedure NilDeref_FreeIsSafe_NoFinding;
    [Test] procedure NilDeref_FreeAndNilIsSafe_NoFinding;
    // MissingFinally
    [Test] procedure MissingFinally_CreateFreeNoTry_ReportsWarning;
    [Test] procedure MissingFinally_TryFinally_NoFinding;
    [Test] procedure MissingFinally_NoFreeAtAll_NoFinding;
    [Test] procedure MissingFinally_TryExceptOnly_ReportsWarning;
    // DivByZero
    [Test] procedure DivByZero_LiteralZero_ReportsError;
    [Test] procedure DivByZero_ParamWithoutGuard_ReportsWarning;
    [Test] procedure DivByZero_ParamWithGuard_NoFinding;
    [Test] procedure DivByZero_LocalVarWithoutGuard_ReportsWarning;
    [Test] procedure DivByZero_NonIntegerType_NoFinding;
    // DeadCode
    [Test] procedure DeadCode_AfterExit_ReportsWarning;
    [Test] procedure DeadCode_AfterRaise_ReportsWarning;
    [Test] procedure DeadCode_AfterBreakInLoop_ReportsWarning;
    [Test] procedure DeadCode_ConditionalExit_NoFinding;
    [Test] procedure DeadCode_ExitInIfThenElse_NoFinding;
    [Test] procedure DeadCode_ExitBeforeExceptBlock_NoFinding;
    [Test] procedure DeadCode_ExitBeforeFinallyBlock_NoFinding;
    // LongMethod: nutzt jetzt Body-Zeilen + Statement-Count
    [Test] procedure LongMethod_ShortBodyLongSignature_NoFinding;
    [Test] procedure LongMethod_LongBodyManyStatements_ReportsWarning;
    [Test] procedure LongMethod_ForwardDecl_NoFinding;
    // DeepNesting: try-Bloecke werden nicht mehr gezaehlt
    [Test] procedure DeepNesting_TryFinallyOnly_NoFinding;
    [Test] procedure DeepNesting_FiveLogicalLevels_ReportsWarning;
    [Test] procedure DeepNesting_TryAroundFourLevels_NoFinding;
    // Robustheit
    [Test] procedure Robust_NonExistentFile_ReportsFileError;
    [Test] procedure Robust_EmptyFileName_ReportsFileError;
    [Test] procedure Robust_NonExistentDirectory_ReportsFileError;
    [Test] procedure Robust_EmptyDirectory_ReportsFileError;
    // Suppression
    [Test] procedure Suppression_NoinspectionSpecificKind_FiltersFinding;
    [Test] procedure Suppression_NoinspectionAll_FiltersAllFindings;
    [Test] procedure Suppression_WrongKind_DoesNotFilter;
    [Test] procedure Suppression_MultipleKinds_FiltersAll;
    // KindFromName-Erweiterung: 3 zuvor stumm ignorierte Kinds
    [Test] procedure Suppression_NoinspectionTodoComment_FiltersFinding;
    [Test] procedure Suppression_NoinspectionEmptyMethod_FiltersFinding;
    [Test] procedure Suppression_NoinspectionDuplicateBlock_FiltersFinding;
  end;

  // ---- UnusedUses (TUnusedUsesDetector) -----------------------------------------------
  [TestFixture]
  TTestUnusedUses = class
  public
    // --- Grundfunktionen ---
    [Test] procedure Uses_UnknownUnit_ReportsWarning;
    [Test] procedure Uses_KnownTypeUsed_H2_NoFinding;
    [Test] procedure Uses_QualifiedCall_H1_NoFinding;
    [Test] procedure Uses_GlobalVarUsed_NoFinding;
    [Test] procedure Uses_ParentClass_NoFinding;
    [Test] procedure Uses_AlwaysNeededUnit_NoFinding;
    [Test] procedure Uses_MultipleUnits_OnlyUnusedReported;
    // --- H1: Qualifizierter Bezeichner ---
    [Test] procedure Uses_H1_ShortName_Qualifier_NoFinding;
    [Test] procedure Uses_H1_FullQualName_Qualifier_NoFinding;
    // --- H2: System-Einheiten ---
    [Test] procedure Uses_H2_Generics_TDictionary_NoFinding;
    [Test] procedure Uses_H2_Generics_TList_NoFinding;
    [Test] procedure Uses_H2_Generics_TObjectList_NoFinding;
    [Test] procedure Uses_H2_Math_Floor_NoFinding;
    [Test] procedure Uses_H2_StrUtils_PosEx_NoFinding;
    [Test] procedure Uses_H2_DateUtils_DaysBetween_NoFinding;
    [Test] procedure Uses_H2_IOUtils_TFile_NoFinding;
    [Test] procedure Uses_H2_JSON_TJSONObject_NoFinding;
    [Test] procedure Uses_H2_RegEx_TRegEx_NoFinding;
    [Test] procedure Uses_H2_Zip_TZipFile_NoFinding;
    [Test] procedure Uses_H2_Diagnostics_TStopwatch_NoFinding;
    [Test] procedure Uses_H2_Threading_TTask_NoFinding;
    [Test] procedure Uses_H2_Classes_TStringList_NoFinding;
    [Test] procedure Uses_H2_Registry_TRegistry_NoFinding;
    // --- H2: VCL-Einheiten ---
    [Test] procedure Uses_H2_VclDialogs_ShowMessage_NoFinding;
    [Test] procedure Uses_H2_VclGraphics_TBitmap_NoFinding;
    [Test] procedure Uses_H2_VclComCtrls_TTabSheet_NoFinding;
    [Test] procedure Uses_H2_VclMenus_TPopupMenu_NoFinding;
    // --- H2: Datenbank ---
    [Test] procedure Uses_H2_DataDB_TDataSet_NoFinding;
    // --- Randfaelle ---
    [Test] procedure Uses_UnknownUnit_NoMapping_NoFinding;
    [Test] procedure Uses_TypeAlias_NoFinding;
    [Test] procedure Uses_WithStatement_NoFinding;
    [Test] procedure Uses_RegSuffix_NeverReported;
    [Test] procedure Uses_ShortNameUsed_LongNameInUses_NoFinding;
    [Test] procedure Uses_TypeParam_Generic_NoFinding;
    [Test] procedure Uses_InterfaceAndImpl_OnlyOnceReported;
    [Test] procedure Uses_AllUnused_AllReported;
  end;

  // ---- FormatMismatch (TFormatMismatchDetector) --------------------------------------
  [TestFixture]
  TTestFormatMismatch = class
  public
    [Test] procedure Format_MorePlaceholdersThanArgs_ReportsError;
    [Test] procedure Format_MoreArgsThanPlaceholders_ReportsError;
    [Test] procedure Format_Matching_NoFinding;
    [Test] procedure Format_EscapedPercent_NotCounted;
    [Test] procedure Format_NoArgs_NoPlaceholders_NoFinding;
    [Test] procedure Format_WidthSpecifier_CorrectCount;
    [Test] procedure Format_NestedInsideAdd_NoFinding;
    [Test] procedure Format_StringContentParsed_CorrectCount;
    [Test] procedure Format_EscapedQuoteInString_CorrectCount;
    // Real-world Pattern aus mORMot-artigen deutschen Meldungen mit
    // mehreren eingebetteten Apostrophen
    [Test] procedure Format_MultipleEscapedQuotes_CorrectCount;
  end;

  // ---- LongParamList (TLongParamListDetector) ----------------------------------------
  [TestFixture]
  TTestLongParamList = class
  public
    [Test] procedure LongParamList_FiveParams_NoFinding;
    [Test] procedure LongParamList_SixParams_ReportsHint;
    [Test] procedure LongParamList_TenParams_ReportsHint;
    [Test] procedure LongParamList_NoParams_NoFinding;
    [Test] procedure LongParamList_AllConstParams_StillCounted;
    [Test] procedure LongParamList_VarParams_StillCounted;
    [Test] procedure LongParamList_FunctionWithSeven_ReportsHint;
    [Test] procedure LongParamList_TwoMethodsBothLong_BothReported;
    [Test] procedure LongParamList_GroupedSameType_StillCounted;
    [Test] procedure LongParamList_MixedShortAndLong_OnlyLongReported;
  end;

  // ---- MagicNumbers (TMagicNumberDetector) -------------------------------------------
  [TestFixture]
  TTestMagicNumbers = class
  public
    [Test] procedure Magic_GreaterThanLargeLiteral_ReportsHint;
    [Test] procedure Magic_LessThanLargeLiteral_ReportsHint;
    [Test] procedure Magic_EqualsLargeLiteral_ReportsHint;
    [Test] procedure Magic_NotEqualsLargeLiteral_ReportsHint;
    [Test] procedure Magic_TrivialZero_NoFinding;
    [Test] procedure Magic_TrivialOne_NoFinding;
    [Test] procedure Magic_TrivialMinusOne_NoFinding;
    [Test] procedure Magic_TrivialHundred_NoFinding;
    [Test] procedure Magic_NoIfStatement_NoFinding;
    [Test] procedure Magic_TwoIfsBothMagic_BothReported;
    // Linke Boundary akzeptiert auch '(', ',', '[': '(Count>100)' wird erkannt
    [Test] procedure Magic_ParenthesisLeftBoundary_ReportsHint;
  end;

  // ---- DuplicateString (TDuplicateStringDetector) ------------------------------------
  [TestFixture]
  TTestDuplicateString = class
  public
    [Test] procedure Dup_ThreeOccurrences_ReportsHint;
    [Test] procedure Dup_TwoOccurrences_NoFinding;
    [Test] procedure Dup_TooShortString_NoFinding;
    [Test] procedure Dup_TrivialFormatSpec_NoFinding;
    [Test] procedure Dup_FourOccurrences_ReportsHint;
    [Test] procedure Dup_DifferentStrings_NoFinding;
    [Test] procedure Dup_TwoDifferentDuplicates_BothReported;
    [Test] procedure Dup_StringInAssignment_Counted;
    [Test] procedure Dup_StringInCall_Counted;
    [Test] procedure Dup_TrueFalseTrivial_NoFinding;
  end;

  // ---- HardcodedPath (THardcodedPathDetector) ----------------------------------------
  [TestFixture]
  TTestHardcodedPath = class
  public
    [Test] procedure Path_WindowsDriveBackslash_ReportsWarning;
    [Test] procedure Path_WindowsDriveForwardslash_ReportsWarning;
    [Test] procedure Path_UNCPath_ReportsWarning;
    [Test] procedure Path_UnixUsr_ReportsWarning;
    [Test] procedure Path_UnixEtc_ReportsWarning;
    [Test] procedure Path_UnixHome_ReportsWarning;
    [Test] procedure Path_UnixHomeShort_ReportsWarning;
    [Test] procedure Path_RegularString_NoFinding;
    [Test] procedure Path_RelativePath_NoFinding;
    [Test] procedure Path_SameDuplicateOnce_NotDuplicated;
  end;

  // ---- DebugOutput (TDebugOutputDetector) --------------------------------------------
  [TestFixture]
  TTestDebugOutput = class
  public
    [Test] procedure Debug_WriteLnCall_ReportsWarning;
    [Test] procedure Debug_ShowMessageCall_ReportsWarning;
    [Test] procedure Debug_MessageDlgCall_ReportsWarning;
    [Test] procedure Debug_OutputDebugStringCall_ReportsWarning;
    [Test] procedure Debug_InputBoxCall_ReportsWarning;
    [Test] procedure Debug_NormalCall_NoFinding;
    [Test] procedure Debug_PrefixedNameWordBoundary_NoFalsePositive;
    [Test] procedure Debug_LoggerWriteCall_NoFalsePositive;
    [Test] procedure Debug_TwoDebugCalls_BothReported;
    [Test] procedure Debug_ShowMessagePosCall_ReportsWarning;
  end;

  // ---- TodoComment (TTodoCommentDetector) - filebasiert ------------------------------
  [TestFixture]
  TTestTodoComment = class
  public
    [Test] procedure Todo_LineComment_ReportsHint;
    [Test] procedure Todo_FixmeMarker_ReportsHint;
    [Test] procedure Todo_HackMarker_ReportsHint;
    [Test] procedure Todo_XxxMarker_ReportsHint;
    [Test] procedure Todo_BraceComment_ReportsHint;
    [Test] procedure Todo_MultilineBraceComment_ReportsHint;
    [Test] procedure Todo_TodoInsideStringLiteral_NoFinding;
    [Test] procedure Todo_TodoAsIdentifier_NoFinding;
    [Test] procedure Todo_LowercaseMarker_StillReported;
    [Test] procedure Todo_NoMarker_NoFinding;
  end;

  // ---- EmptyMethod (TEmptyMethodDetector) --------------------------------------------
  [TestFixture]
  TTestEmptyMethod = class
  public
    [Test] procedure Empty_ProcedureBody_ReportsHint;
    [Test] procedure Empty_FunctionBody_ReportsHint;
    [Test] procedure Empty_BodyWithInherited_NoFinding;
    [Test] procedure Empty_BodyWithSingleAssign_NoFinding;
    [Test] procedure Empty_TwoEmptyMethods_BothReported;
    [Test] procedure Empty_OneFilledOneEmpty_OnlyEmptyReported;
    [Test] procedure Empty_Constructor_ReportsHint;
    [Test] procedure Empty_Destructor_ReportsHint;
    [Test] procedure Empty_BodyWithCall_NoFinding;
    [Test] procedure Empty_ForwardDecl_NoFinding;
  end;

  // ---- EmptyExcept Erweiterungen -----------------------------------------------------
  [TestFixture]
  TTestEmptyExceptExt = class
  public
    [Test] procedure EmptyExcept_OnlyWhitespace_ReportsWarning;
    [Test] procedure EmptyExcept_NestedTryExcept_AllReported;
    [Test] procedure EmptyExcept_InsideTryFinally_Reported;
    [Test] procedure EmptyExcept_TwoExceptBlocks_BothReported;
    [Test] procedure EmptyExcept_WithOnAndEmptyOther_OnlyEmptyReported;
  end;

  // ---- SQLInjection Erweiterungen ----------------------------------------------------
  [TestFixture]
  TTestSQLInjectionExt = class
  public
    [Test] procedure SQL_AssignSelectStarConcat_IntToStrSafe_NoFinding;
    [Test] procedure SQL_DeleteWithVarConcat_ReportsError;
    [Test] procedure SQL_AssignWithoutSQLKeyword_NoFinding;
  end;

  // ---- HardcodedSecret Erweiterungen -------------------------------------------------
  [TestFixture]
  TTestHardcodedSecretExt = class
  public
    [Test] procedure Secret_PwdLowercaseAssign_ReportsError;
    [Test] procedure Secret_SecretAssignedLiteral_ReportsError;
    [Test] procedure Secret_PrivateKeyAssignedLiteral_ReportsError;
    [Test] procedure Secret_NormalStringNoSecretName_NoFinding;
  end;

  // ---- DuplicateBlock (TDuplicateBlockDetector) - filebasiert -----------------------
  [TestFixture]
  TTestDuplicateBlock = class
  public
    [Test] procedure Block_TwoIdenticalBlocks_ReportsHint;
    [Test] procedure Block_NoDuplicates_NoFinding;
    [Test] procedure Block_TooShort_NoFinding;
    [Test] procedure Block_TrivialLinesIgnored_NoFinding;
    [Test] procedure Block_ThreeIdenticalBlocks_ReportsOnce;
    [Test] procedure Block_BranchingBoilerplate_NoFinding;
    [Test] procedure Block_DifferentWhitespace_StillDetected;
    [Test] procedure Block_DifferentCase_StillDetected;
    [Test] procedure Block_CommentsBetween_StillDetected;
    [Test] procedure Block_FirstLineReported_NotLast;
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
  end;

  // ---- FormatMismatch Erweiterung ----------------------------------------------------
  [TestFixture]
  TTestFormatMismatchExt = class
  public
    [Test] procedure Format_OnePlaceholderTwoArgs_ReportsError;
    // Vorgaenger-Filter erlaubt nicht nur '.' - 'Result := Format(...)' wird erkannt
    [Test] procedure Format_AssignmentWithoutDot_ReportsError;
  end;

  // ---- NilDeref Erweiterungen --------------------------------------------------------
  [TestFixture]
  TTestNilDerefExt = class
  public
    [Test] procedure NilDeref_AfterFreeAndDot_ReportsError;
    [Test] procedure NilDeref_TwoNilsBothReported;
    [Test] procedure NilDeref_AssignedFromCreate_NoFinding;
    [Test] procedure NilDeref_NilGuardWithBegin_NoFinding;
    // Wortgrenze: 'assigned(objOld)' darf 'obj' nicht schuetzen
    [Test] procedure NilDeref_AssignedGuardVarSubstring_StillReports;
  end;

  // ---- MissingFinally Erweiterungen --------------------------------------------------
  [TestFixture]
  TTestMissingFinallyExt = class
  public
    [Test] procedure MissingFinally_TwoCreates_NoTry_BothReported;
    [Test] procedure MissingFinally_CreateAndImmediateRaise_NoFinding;
    [Test] procedure MissingFinally_FreeAndNilNoTry_ReportsWarning;
    [Test] procedure MissingFinally_NestedTryFinally_NoFinding;
    [Test] procedure MissingFinally_FreeBeforeTry_ReportsWarning;
    [Test] procedure MissingFinally_DestroyNoTry_ReportsWarning;
  end;

  // ---- DivByZero Erweiterungen -------------------------------------------------------
  [TestFixture]
  TTestDivByZeroExt = class
  public
    [Test] procedure Div_LiteralZeroMod_ReportsError;
    [Test] procedure Div_TwoZeroDivs_BothReported;
    [Test] procedure Div_NonZeroLiteral_NoFinding;
    [Test] procedure Div_GuardedLocalVar_NoFinding;
    [Test] procedure Div_StringDivisor_NoFinding;
  end;

  // ---- DeadCode Erweiterungen --------------------------------------------------------
  [TestFixture]
  TTestDeadCodeExt = class
  public
    [Test] procedure DeadCode_NoDeadCode_NoFinding;
    [Test] procedure DeadCode_TwoExitsBothFollowedByDead_BothReported;
    [Test] procedure DeadCode_ExitAtMethodEnd_NoFinding;
  end;

  // ---- LongMethod Erweiterungen ------------------------------------------------------
  [TestFixture]
  TTestLongMethodExt = class
  public
    [Test] procedure LongMethod_TenLineBody_NoFinding;
    [Test] procedure LongMethod_OnlyLineCountTooHigh_NoFinding;
    [Test] procedure LongMethod_OnlyStatementCountTooHigh_NoFinding;
    [Test] procedure LongMethod_TwoMethodsOneLong_OnlyLongReported;
    [Test] procedure LongMethod_EmptyBody_NoFinding;
    [Test] procedure LongMethod_LongCommentNoStatements_NoFinding;
    [Test] procedure LongMethod_BothThresholdsExceeded_ReportsHint;
  end;

  // ---- DeepNesting Erweiterungen -----------------------------------------------------
  [TestFixture]
  TTestDeepNestingExt = class
  public
    [Test] procedure DeepNesting_NoNesting_NoFinding;
    [Test] procedure DeepNesting_FourIfsExactlyAtLimit_NoFinding;
    [Test] procedure DeepNesting_FiveIfsOverLimit_ReportsHint;
    [Test] procedure DeepNesting_DeepForLoops_ReportsHint;
    [Test] procedure DeepNesting_DeepCases_ReportsHint;
    [Test] procedure DeepNesting_RepeatLoops_Counted;
    [Test] procedure DeepNesting_TwoMethodsOneDeep_OnlyDeepReported;
  end;

  // ---- Parser-Robustheit (Real-World mORMot2-Konstrukte) -----------------------------
  // Probe: jeder Test hat einen Memory-Leak in einer Methode, die DURCH oder
  // NACH dem zu testenden Konstrukt definiert ist. Wenn der Parser das
  // Konstrukt korrekt verarbeitet, wird der Leak gefunden; wenn nicht, geht
  // der Body verloren und der Leak verschwindet.
  [TestFixture]
  TTestParserRobustness = class
  public
    [Test] procedure Parser_InterfaceDecl_FollowingMethodLeakDetected;
    [Test] procedure Parser_GenericTypeDecl_MethodLeakDetected;
    [Test] procedure Parser_GenericMethodSig_LeakDetected;
    [Test] procedure Parser_PackedRecord_FollowingMethodLeakDetected;
    [Test] procedure Parser_LabelSection_BodyLeakDetected;
    [Test] procedure Parser_ClassHelperFor_FollowingMethodLeakDetected;
    [Test] procedure Parser_IfdefDuplicatedHeaders_NoPhantomDuplicate;
  end;

implementation

{ TFindingHelper }

class function TFindingHelper.FindingsOf(const Source: string): TObjectList<TLeakFinding>;
var
  Parser  : TParser2;
  Root    : TAstNode;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Parser := TParser2.Create;
  try
    Root := Parser.ParseSource(Source);
    try
      TLeakDetector2.AnalyzeUnit(Root, 'test.pas', Result);
      TEmptyExceptDetector2.AnalyzeUnit(Root, 'test.pas', Result);
      TSQLInjectionDetector.AnalyzeUnit(Root, 'test.pas', Result);
      THardcodedSecretDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TFormatMismatchDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TUnusedUsesDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TNilDerefDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TMissingFinallyDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TDivByZeroDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TDeadCodeDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TLongMethodDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TLongParamListDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TMagicNumberDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TDuplicateStringDetector.AnalyzeUnit(Root, 'test.pas', Result);
      THardcodedPathDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TDebugOutputDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TDeepNestingDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TEmptyMethodDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TFieldLeakDetector.AnalyzeUnit(Root, 'test.pas', Result);
      // TTodoCommentDetector liest die Datei selbst und braucht eine echte
      // Datei - hier nicht aufgerufen. FindingsOfFile() benutzen.
    finally
      Root.Free;
    end;
  finally
    Parser.Free;
  end;
end;

class function TFindingHelper.FindingsOfFile(const Source: string): TObjectList<TLeakFinding>;
var
  Parser   : TParser2;
  Root     : TAstNode;
  TempPath : string;
  SL       : TStringList;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  TempPath := TPath.Combine(TPath.GetTempPath,
    'sca_test_' + TGuid.NewGuid.ToString.Replace('{','').Replace('}','').Replace('-','') + '.pas');
  SL := TStringList.Create;
  try
    SL.Text := Source;
    SL.SaveToFile(TempPath, TEncoding.UTF8);
  finally
    SL.Free;
  end;
  try
    Parser := TParser2.Create;
    try
      Root := Parser.ParseSource(Source);
      try
        TTodoCommentDetector.AnalyzeUnit(Root, TempPath, Result);
        TEmptyMethodDetector.AnalyzeUnit(Root, TempPath, Result);
        TDuplicateBlockDetector.AnalyzeUnit(Root, TempPath, Result);
      finally
        Root.Free;
      end;
    finally
      Parser.Free;
    end;
  finally
    if TFile.Exists(TempPath) then
      TFile.Delete(TempPath);
  end;
end;

class function TFindingHelper.Count(Findings: TObjectList<TLeakFinding>;
  Kind: TFindingKind): Integer;
var
  F: TLeakFinding;
begin
  Result := 0;
  for F in Findings do
    if F.Kind = Kind then Inc(Result);
end;

class function TFindingHelper.CountSev(Findings: TObjectList<TLeakFinding>;
  Kind: TFindingKind; Sev: TLeakSeverity): Integer;
var
  F: TLeakFinding;
begin
  Result := 0;
  for F in Findings do
    if (F.Kind = Kind) and (F.Severity = Sev) then Inc(Result);
end;

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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
      'list in finally freigegeben – kein Befund');
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsWarning),
      'list.Free außerhalb finally – Warning');
    Assert.AreEqual(0, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Ownership über Result abgegeben – kein Befund');
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
      'stream an inherited Create übergeben – kein Befund');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_FunctionCallAssign_NoFreeReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := GetList();'#13#10+
  '  list.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsWarning),
      'Funktionsaufruf-Zuweisung ohne Free – Warning');
  finally F.Free; end;
end;

procedure TTestMemoryLeak.Leak_FunctionCallAssign_WithFree_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := GetList();'#13#10+
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(2, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Field-Receiver mit .Add() faellt auf permissive Default zurueck');
  finally F.Free; end;
end;

{ ---- EmptyExcept ---- }

procedure TTestEmptyExcept.EmptyExcept_NoCode_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    DoSomething;'#13#10+
  '  except'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkEmptyExcept),
      'Leerer except-Block – Warning');
  finally F.Free; end;
end;

procedure TTestEmptyExcept.EmptyExcept_CommentOnly_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    DoSomething;'#13#10+
  '  except'#13#10+
  '    // leer – ignorieren'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkEmptyExcept),
      'Nur Kommentar im except – trotzdem Warning');
  finally F.Free; end;
end;

procedure TTestEmptyExcept.EmptyExcept_WithHandler_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    DoSomething;'#13#10+
  '  except'#13#10+
  '    on E: Exception do'#13#10+
  '      LogError(E.Message);'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkEmptyExcept),
      'Handler vorhanden – kein Befund');
  finally F.Free; end;
end;

procedure TTestEmptyExcept.EmptyExcept_WithRaise_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    DoSomething;'#13#10+
  '  except'#13#10+
  '    raise;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkEmptyExcept),
      'raise im except – kein Befund');
  finally F.Free; end;
end;

procedure TTestEmptyExcept.EmptyExcept_MultipleBlocks_AllReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  try DoA; except end;'#13#10+
  '  try DoB; except end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(2, TFindingHelper.Count(F, fkEmptyExcept),
      'Zwei leere except-Blöcke – beide gemeldet');
  finally F.Free; end;
end;

{ ---- SQLInjection ---- }

procedure TTestSQLInjection.SQL_AssignToSQLText_WithConcat_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Search(Id: string);'#13#10+
  'begin'#13#10+
  '  Query.SQL.Text := ''SELECT * FROM users WHERE id = ''+Id;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkSQLInjection),
      'SQL.Text mit Konkatenation – Error');
  finally F.Free; end;
end;

procedure TTestSQLInjection.SQL_AssignToCommandText_WithConcat_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Run(Tbl: string);'#13#10+
  'begin'#13#10+
  '  Cmd.CommandText := ''UPDATE ''+Tbl+'' SET active=1'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkSQLInjection), 'CommandText – Error');
  finally F.Free; end;
end;

procedure TTestSQLInjection.SQL_StringLiteralContainsSELECT_WithConcat_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Run(Name: string);'#13#10+
  'begin'#13#10+
  '  s := ''SELECT * FROM t WHERE name = ''+Name;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkSQLInjection),
      'SELECT-Literal mit Konkatenation – Error');
  finally F.Free; end;
end;

procedure TTestSQLInjection.SQL_NoConcat_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Run;'#13#10+
  'begin'#13#10+
  '  Query.SQL.Text := ''SELECT * FROM users WHERE id = :Id'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkSQLInjection),
      'Parametrisiertes Query ohne + – kein Befund');
  finally F.Free; end;
end;

procedure TTestSQLInjection.SQL_AddCall_WithConcat_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Run(Id: string);'#13#10+
  'begin'#13#10+
  '  Query.SQL.Add(''SELECT * FROM t WHERE id = ''+Id);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkSQLInjection),
      'SQL.Add mit Konkatenation – Error');
  finally F.Free; end;
end;

procedure TTestSQLInjection.SQL_ParametrizedQuery_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Run(Name: string);'#13#10+
  'begin'#13#10+
  '  Query.SQL.Text := ''SELECT * FROM t WHERE name = :Name'';'#13#10+
  '  Query.ParamByName(''Name'').AsString := Name;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkSQLInjection),
      'Parametrisiertes Query – kein Befund');
  finally F.Free; end;
end;

procedure TTestSQLInjection.SQL_DocStringWithSQLKeyword_NoFinding;
// Reproduziert den FixHint-Falschpositiv: ein Feld wie Result.Before erhält
// einen Dokumentations-String, der SQL-Keywords NICHT an Position 1 hat.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.BuildHint;'#13#10+
  'begin'#13#10+
  '  Result.Before :='#13#10+
  '    ''Query.SQL.Text :=''+'#13#10+
  '    ''  ''''SELECT * FROM t'''';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkSQLInjection),
      'Doku-String mit SQL-Keyword – kein Befund (H2 nur bei Position 1)');
  finally F.Free; end;
end;

procedure TTestSQLInjection.SQL_LiteralOnlyConcat_NoFinding;
// Zwei oder mehr Stringliterale per '+' verkettet sind reine Multi-Line-
// Literale, kein SQL-Injection-Risiko - es gibt keine Variable die ein
// Angreifer manipulieren koennte.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  Query.SQL.Text := ''SELECT a FROM t'' + '' WHERE x=1'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkSQLInjection),
      'Pure Literal-Konkatenation darf kein SQL-Injection-Befund sein');
  finally F.Free; end;
end;

procedure TTestSQLInjection.SQL_CreateTableMultilineLiteral_NoFinding;
// Konkretes Beispiel aus Unit1.pas (sample-dunitx-belege_ui):
// CREATE TABLE - mehrzeilige Stringliteral-Konkatenation, KEIN Risiko.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.CreateTable;'#13#10+
  'begin'#13#10+
  '  SQLQuery.SQL.Text := ''CREATE TABLE IF NOT EXISTS Kommentare '' +'#13#10+
  '    ''(id TEXT PRIMARY KEY NOT NULL, Teaser TEXT, Info TEXT)'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkSQLInjection),
      'Mehrzeiliges CREATE TABLE-Literal darf kein SQL-Injection-Befund sein');
  finally F.Free; end;
end;

procedure TTestSQLInjection.SQL_CommandTextSubstring_NoFalsePositive;
// Wortgrenze-Test: 'mycommandtextra' enthaelt 'commandtext' als Substring,
// darf aber NICHT als SQL-Property erkannt werden. Vor dem WholeWord-Fix
// in IsAssignRisk haette die naive Pos()-Suche hier einen Treffer geliefert.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var dummy: string;'#13#10+
  'begin'#13#10+
  '  mycommandtextra := dummy + ''abc'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkSQLInjection),
      '"mycommandtextra" darf nicht als SQL-Property-Match gelten');
  finally F.Free; end;
end;

{ ---- HardcodedSecret ---- }

procedure TTestHardcodedSecret.Secret_PasswordAssignedLiteral_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  FPassword := ''geheim123'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkHardcodedSecret),
      'Passwort-Literal – Error');
  finally F.Free; end;
end;

procedure TTestHardcodedSecret.Secret_TokenAssignedLiteral_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  ApiToken := ''sk-abc123xyz'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkHardcodedSecret),
      'Token-Literal – Error');
  finally F.Free; end;
end;

procedure TTestHardcodedSecret.Secret_ApiKeyAssignedLiteral_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  APIKey := ''MY-SECRET-KEY'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkHardcodedSecret),
      'API-Key-Literal – Error');
  finally F.Free; end;
end;

procedure TTestHardcodedSecret.Secret_AssignFromFunction_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  FPassword := GetPasswordFromVault();'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkHardcodedSecret),
      'Passwort aus Funktion – kein Befund');
  finally F.Free; end;
end;

procedure TTestHardcodedSecret.Secret_AssignFromVariable_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init(const PWD: string);'#13#10+
  'begin'#13#10+
  '  FPassword := PWD;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkHardcodedSecret),
      'Passwort aus Parameter – kein Befund');
  finally F.Free; end;
end;

procedure TTestHardcodedSecret.Secret_EmptyLiteral_NoFinding;
// Reproduziert den FixHint-Falschpositiv: 'mPasswort := '''''' ist eine
// Initialisierung auf leer und semantisch das Gegenteil eines Secrets.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  mPasswort := '''';'#13#10+
  '  FToken    := '''';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkHardcodedSecret),
      'Leeres Stringliteral darf nicht als Secret gemeldet werden');
  finally F.Free; end;
end;

procedure TTestHardcodedSecret.Secret_NonSecretVarWithLiteral_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  Title := ''Willkommen'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkHardcodedSecret),
      'Normaler String-Literal - kein Befund');
  finally F.Free; end;
end;

procedure TTestHardcodedSecret.Secret_SecretarySubstring_NoFinding;
// 'secretary' enthaelt 'secret' als Substring, ist aber semantisch nichts
// Sicherheitskritisches. Vor dem CamelCase/Snake-Boundary-Refactor in
// IsSecretName haette die naive Pos-Suche faelschlich getriggert.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  secretary := ''Frau Mueller'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkHardcodedSecret),
      '"secretary" darf nicht als Secret-Pattern matchen');
  finally F.Free; end;
end;

procedure TTestHardcodedSecret.Secret_UserTokenSnakeCase_ReportsError;
// Snake-Case-Boundary: 'user_token' enthaelt 'token' nach Underscore -
// gilt als Wortgrenze und MUSS gemeldet werden.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  user_token := ''sk-abcdef'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkHardcodedSecret) >= 1,
      '"user_token" muss als Secret-Variable erkannt werden');
  finally F.Free; end;
end;

{ ---- FormatMismatch ---- }

procedure TTestFormatMismatch.Format_MorePlaceholdersThanArgs_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar(Name: string);'#13#10+
  'begin'#13#10+
  '  ShowMessage(Format(''%s ist %d Jahre alt'', [Name]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkFormatMismatch),
      '2 Platzhalter, 1 Argument – Error');
  finally F.Free; end;
end;

procedure TTestFormatMismatch.Format_MoreArgsThanPlaceholders_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar(A, B: string);'#13#10+
  'begin'#13#10+
  '  ShowMessage(Format(''Nur %s'', [A, B]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkFormatMismatch),
      '1 Platzhalter, 2 Argumente – Error');
  finally F.Free; end;
end;

procedure TTestFormatMismatch.Format_Matching_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar(N: string; A: Integer);'#13#10+
  'begin'#13#10+
  '  ShowMessage(Format(''%s ist %d Jahre alt'', [N, A]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkFormatMismatch),
      '2 Platzhalter, 2 Argumente – kein Befund');
  finally F.Free; end;
end;

procedure TTestFormatMismatch.Format_EscapedPercent_NotCounted;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar(N: string);'#13#10+
  'begin'#13#10+
  '  ShowMessage(Format(''100%% von %s'', [N]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkFormatMismatch),
      '%% ist kein Platzhalter – kein Befund');
  finally F.Free; end;
end;

procedure TTestFormatMismatch.Format_NoArgs_NoPlaceholders_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  ShowMessage(Format(''Kein Platzhalter'', []));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkFormatMismatch),
      'Keine Platzhalter, leeres Array – kein Befund');
  finally F.Free; end;
end;

procedure TTestFormatMismatch.Format_WidthSpecifier_CorrectCount;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar(V: Double);'#13#10+
  'begin'#13#10+
  '  ShowMessage(Format(''Wert: %8.2f'', [V]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkFormatMismatch),
      '%8.2f = 1 Platzhalter, 1 Argument – kein Befund');
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Dotted-no-parens RHS = Borrowed-Reference, kein Befund');
  finally F.Free; end;
end;

procedure TTestFormatMismatch.Format_NestedInsideAdd_NoFinding;
// Results.Add(Format('%d %s',[v,k])) – Format ist verschachteltes Argument,
// kein eigenständiger Aufruf → kein Befund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  Results.Add(Format(''%d  %s'', [Pair.Value, Pair.Key]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkFormatMismatch),
      'Format() als Argument in Add() – kein Befund');
  finally F.Free; end;
end;

procedure TTestFormatMismatch.Format_StringContentParsed_CorrectCount;
// Stellt sicher dass der Lexer den String-Inhalt korrekt liest.
// '%s ist %d Jahre alt' hat 2 Platzhalter.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar(N: string; A: Integer);'#13#10+
  'begin'#13#10+
  '  ShowMessage(Format(''%s ist %d Jahre alt'', [N, A]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkFormatMismatch),
      'Lexer liest String-Inhalt korrekt: 2 Platzhalter, 2 Argumente');
  finally F.Free; end;
end;

procedure TTestFormatMismatch.Format_EscapedQuoteInString_CorrectCount;
// Format-String mit eingebettetem '' (maskiertes Anführungszeichen).
// 'es''s %s' hat 1 Platzhalter.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar(N: string);'#13#10+
  'begin'#13#10+
  '  ShowMessage(Format(''it''''s %s'', [N]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkFormatMismatch),
      'Maskiertes '' im Format-String: 1 Platzhalter, 1 Argument');
  finally F.Free; end;
end;

procedure TTestFormatMismatch.Format_MultipleEscapedQuotes_CorrectCount;
// Real-world mORMot-Pattern: deutsche Meldung mit zwei `'`-eingerahmten
// Bezeichnern UND einem `%s` am Ende. Der Lexer resolved `''` -> `'` und
// vor dem QuoteStrLit-Fix verlor die Stringserialisierung die Boundaries
// -> der Detektor zaehlte 0 Platzhalter statt 1 -> False-Positive
// "Format: 0 placeholders, 1 arguments".
const SRC =
  'unit t; implementation'#13#10+
  'procedure TPmtInf_CCT.plausiOK;'#13#10+
  'begin'#13#10+
  '  Self.addMessage(Format(''Eintrag ''''BIC des Zahlers'''' fehlt: '+
                            '<DbtrAgt><FinInstnId><BIC>%s'', [Self.FBIC]));'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkFormatMismatch),
      'Zwei eingebettete '' + %s am Ende: 1 Platzhalter, 1 Argument');
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
      'Borrowed-Reference (Self.FList) darf nicht als Leak gemeldet werden');
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'b nie freigegeben – 1 Error; a korrekt – kein zweiter Befund');
    Assert.AreEqual(0, TFindingHelper.CountSev(F, fkMemoryLeak, lsWarning),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsWarning),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(3, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsWarning),
      'list.Free nach try/finally – Warning');
    Assert.AreEqual(0, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
      'result1 nie freigegeben – 1 Error; lines korrekt – kein zweiter');
  finally F.Free; end;
end;

{ ---- UnusedUses ---- }

procedure TTestUnusedUses.Uses_UnknownUnit_ReportsWarning;
// Unit die im Code nirgends vorkommt → Warning
const SRC =
  'unit t;'#13#10+
  'uses System.IniFiles;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  DoSomething;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkUnusedUses),
      'System.IniFiles ohne TIniFile-Verwendung – Warning');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_KnownTypeUsed_H2_NoFinding;
// H2: TIniFile als Typ → System.IniFiles ist benoetigt
const SRC =
  'unit t;'#13#10+
  'uses System.IniFiles;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var ini: TIniFile;'#13#10+
  'begin'#13#10+
  '  ini := TIniFile.Create(''cfg.ini'');'#13#10+
  '  ini.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'TIniFile vorhanden – kein Befund');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_QualifiedCall_H1_NoFinding;
// H1: 'system.inifiles.' als Praefix im Code
const SRC =
  'unit t;'#13#10+
  'uses System.IniFiles;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var ini: System.IniFiles.TIniFile;'#13#10+
  'begin'#13#10+
  '  ini := System.IniFiles.TIniFile.Create(''x'');'#13#10+
  '  ini.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'Qualifizierter Bezeichner ''inifiles.'' – kein Befund');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_GlobalVarUsed_NoFinding;
// H2: 'application' (global var aus Vcl.Forms) wird verwendet
const SRC =
  'unit t;'#13#10+
  'uses Vcl.Forms;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  Application.ProcessMessages;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'Application.ProcessMessages – Vcl.Forms benoetigt, kein Befund');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_ParentClass_NoFinding;
// Elternklasse TIniFile im class()-Block → System.IniFiles benoetigt
const SRC =
  'unit t;'#13#10+
  'uses System.IniFiles;'#13#10+
  'type'#13#10+
  '  TMyIni = class(TIniFile)'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'Elternklasse TIniFile – kein Befund (Parser erfasst class()-Block)');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_AlwaysNeededUnit_NoFinding;
// System.SysUtils ist immer benoetigt und wird nie gemeldet
const SRC =
  'unit t;'#13#10+
  'uses System.SysUtils;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'System.SysUtils – immer benoetigt, kein Befund');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_MultipleUnits_OnlyUnusedReported;
// Von drei Units wird eine nie verwendet → genau 1 Befund
const SRC =
  'unit t;'#13#10+
  'uses System.IniFiles, System.Zip, System.Classes;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var sl: TStringList; z: TZipFile;'#13#10+
  'begin'#13#10+
  '  sl := TStringList.Create; sl.Free;'#13#10+
  '  z  := TZipFile.Create;    z.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkUnusedUses),
      'System.IniFiles ungenutzt – genau 1 Befund');
    Assert.AreEqual('System.IniFiles',
      (F[0] as TLeakFinding).MissingVar,
      'Befund zeigt korrekten Unit-Namen');
  finally F.Free; end;
end;

{ ---- NilDeref ---- }

procedure TTestNewChecks.NilDeref_NilThenDot_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var obj: TStringList;'#13#10+
  'begin'#13#10+
  '  obj := nil;'#13#10+
  '  obj.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkNilDeref),
      'nil-Zuweisung dann Punktzugriff – Error');
  finally F.Free; end;
end;

procedure TTestNewChecks.NilDeref_AssignedGuard_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var obj: TStringList;'#13#10+
  'begin'#13#10+
  '  obj := nil;'#13#10+
  '  if Assigned(obj) then'#13#10+
  '    obj.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkNilDeref),
      'Assigned()-Guard – kein Befund');
  finally F.Free; end;
end;

procedure TTestNewChecks.NilDeref_NotNilGuard_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var obj: TStringList;'#13#10+
  'begin'#13#10+
  '  obj := nil;'#13#10+
  '  if obj <> nil then'#13#10+
  '    obj.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkNilDeref),
      'obj <> nil Guard – kein Befund');
  finally F.Free; end;
end;

procedure TTestNewChecks.NilDeref_Reassigned_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var obj: TStringList;'#13#10+
  'begin'#13#10+
  '  obj := nil;'#13#10+
  '  obj := TStringList.Create;'#13#10+
  '  obj.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkNilDeref),
      'Neuzuweisung vor Zugriff – kein Befund');
  finally F.Free; end;
end;

procedure TTestNewChecks.NilDeref_FreeIsSafe_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var obj: TStringList;'#13#10+
  'begin'#13#10+
  '  obj := nil;'#13#10+
  '  obj.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkNilDeref),
      '.Free ist nil-sicher (TObject.Free prueft Self) – kein Befund');
  finally F.Free; end;
end;

procedure TTestNewChecks.NilDeref_FreeAndNilIsSafe_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var obj: TStringList;'#13#10+
  'begin'#13#10+
  '  obj := nil;'#13#10+
  '  FreeAndNil(obj);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkNilDeref),
      'FreeAndNil ist nil-sicher – kein Befund');
  finally F.Free; end;
end;

{ ---- MissingFinally ---- }

procedure TTestNewChecks.MissingFinally_CreateFreeNoTry_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  list.Add(''x'');'#13#10+
  '  list.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkMissingFinally),
      'Create+Free ohne try/finally – Warning');
  finally F.Free; end;
end;

procedure TTestNewChecks.MissingFinally_TryFinally_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    list.Add(''x'');'#13#10+
  '  finally'#13#10+
  '    list.Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMissingFinally),
      'try/finally vorhanden – kein MissingFinally');
  finally F.Free; end;
end;

procedure TTestNewChecks.MissingFinally_NoFreeAtAll_NoFinding;
// Wird von TLeakDetector2 als lsError gemeldet, nicht als MissingFinally
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMissingFinally),
      'Kein Free → TLeakDetector2 zustaendig, kein MissingFinally');
  finally F.Free; end;
end;

procedure TTestNewChecks.MissingFinally_TryExceptOnly_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    list.Add(''x'');'#13#10+
  '  except'#13#10+
  '    list.Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkMissingFinally),
      'try/except ohne finally – Warning');
  finally F.Free; end;
end;

{ ---- DivByZero ---- }

procedure TTestNewChecks.DivByZero_LiteralZero_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var x: Integer;'#13#10+
  'begin'#13#10+
  '  x := 100 div 0;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkDivByZero, lsError),
      'Literal 0 als Divisor – Error');
  finally F.Free; end;
end;

procedure TTestNewChecks.DivByZero_ParamWithoutGuard_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'function TFoo.Avg(Sum, Count: Integer): Integer;'#13#10+
  'begin'#13#10+
  '  Result := Sum div Count;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkDivByZero, lsWarning),
      'Parameter Count ohne Guard – Warning');
  finally F.Free; end;
end;

procedure TTestNewChecks.DivByZero_ParamWithGuard_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'function TFoo.Avg(Sum, Count: Integer): Integer;'#13#10+
  'begin'#13#10+
  '  if Count > 0 then'#13#10+
  '    Result := Sum div Count;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkDivByZero),
      'Guard if Count > 0 – kein Befund');
  finally F.Free; end;
end;

procedure TTestNewChecks.DivByZero_LocalVarWithoutGuard_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var n, m, r: Integer;'#13#10+
  'begin'#13#10+
  '  n := GetN;'#13#10+
  '  m := GetM;'#13#10+
  '  r := n div m;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkDivByZero, lsWarning),
      'Lokale Var m ohne Guard – Warning');
  finally F.Free; end;
end;

procedure TTestNewChecks.DivByZero_NonIntegerType_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var s: TStringList; r: Integer;'#13#10+
  'begin'#13#10+
  '  r := 100 div s.Count;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkDivByZero),
      'Property-Zugriff statt Variable – kein Befund');
  finally F.Free; end;
end;

{ ---- DeadCode ---- }

procedure TTestNewChecks.DeadCode_AfterExit_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  Exit;'#13#10+
  '  DoSomething;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkDeadCode),
      'Code nach Exit – Warning');
  finally F.Free; end;
end;

procedure TTestNewChecks.DeadCode_AfterRaise_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  raise Exception.Create(''X'');'#13#10+
  '  DoSomething;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkDeadCode),
      'Code nach raise – Warning');
  finally F.Free; end;
end;

procedure TTestNewChecks.DeadCode_AfterBreakInLoop_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var i: Integer;'#13#10+
  'begin'#13#10+
  '  for i := 0 to 9 do'#13#10+
  '  begin'#13#10+
  '    Break;'#13#10+
  '    DoSomething;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkDeadCode),
      'Code nach Break in Loop – Warning');
  finally F.Free; end;
end;

procedure TTestNewChecks.DeadCode_ConditionalExit_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  if Condition then'#13#10+
  '    Exit;'#13#10+
  '  DoSomething;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkDeadCode),
      'Bedingtes Exit – DoSomething nicht tot');
  finally F.Free; end;
end;

procedure TTestNewChecks.DeadCode_ExitInIfThenElse_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  if A then'#13#10+
  '    Exit'#13#10+
  '  else'#13#10+
  '    DoB;'#13#10+
  '  DoC;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkDeadCode),
      'Exit in if-Branch, else vorhanden – kein toter Code');
  finally F.Free; end;
end;

{ ---- LongMethod (verbessert) ---- }

procedure TTestNewChecks.LongMethod_ShortBodyLongSignature_NoFinding;
// Lange Parameter-Liste, aber sehr kurzer Body → KEIN Befund.
// Vorher haette das geflaggt werden koennen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar('#13#10+
  '  A: Integer;'#13#10+
  '  B: Integer;'#13#10+
  '  C: Integer;'#13#10+
  '  D: Integer;'#13#10+
  '  E: Integer;'#13#10+
  '  F: Integer;'#13#10+
  '  G: Integer;'#13#10+
  '  H: Integer;'#13#10+
  '  I: Integer;'#13#10+
  '  J: Integer);'#13#10+
  'begin'#13#10+
  '  Result := A + B;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkLongMethod),
      'Body ist kurz – keine LongMethod-Warnung trotz langer Signatur');
  finally F.Free; end;
end;

procedure TTestNewChecks.LongMethod_LongBodyManyStatements_ReportsWarning;
// Echter langer Body mit > 30 Anweisungen UND > 50 Body-Zeilen → Warning
var
  SB: TStringBuilder;
  Src: string;
  F: TObjectList<TLeakFinding>;
  i: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit t; implementation');
    SB.AppendLine('procedure TFoo.Bar;');
    SB.AppendLine('begin');
    for i := 1 to 60 do
      SB.AppendLine(Format('  X%d := %d;', [i, i]));
    SB.AppendLine('end;');
    Src := SB.ToString;
  finally
    SB.Free;
  end;

  F := TFindingHelper.FindingsOf(Src);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkLongMethod),
      'Body > 50 Zeilen UND > 30 Anweisungen – Warning');
  finally F.Free; end;
end;

procedure TTestNewChecks.LongMethod_ForwardDecl_NoFinding;
// Methoden ohne Body (Forward, Interface) duerfen nicht geflaggt werden
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TFoo = class'#13#10+
  '    procedure VeryVeryLongMethodName(A, B, C, D, E: Integer);'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkLongMethod),
      'Methode in Interface-Section ohne Body – kein Befund');
  finally F.Free; end;
end;

{ ---- DeepNesting (verbessert) ---- }

procedure TTestNewChecks.DeepNesting_TryFinallyOnly_NoFinding;
// 5 verschachtelte try/finally → KEIN Befund (Resource-Management)
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    try'#13#10+
  '      try'#13#10+
  '        try'#13#10+
  '          try'#13#10+
  '            DoIt;'#13#10+
  '          finally'#13#10+
  '            C5.Free;'#13#10+
  '          end;'#13#10+
  '        finally C4.Free; end;'#13#10+
  '      finally C3.Free; end;'#13#10+
  '    finally C2.Free; end;'#13#10+
  '  finally C1.Free; end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkDeepNesting),
      'try/finally zaehlen nicht als logische Verschachtelung');
  finally F.Free; end;
end;

procedure TTestNewChecks.DeepNesting_FiveLogicalLevels_ReportsWarning;
// 5 verschachtelte if/for/while → Befund
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var i, j, k, m, n: Integer;'#13#10+
  'begin'#13#10+
  '  for i := 0 to 9 do'#13#10+
  '    for j := 0 to 9 do'#13#10+
  '      for k := 0 to 9 do'#13#10+
  '        for m := 0 to 9 do'#13#10+
  '          if i + j + k + m > 0 then'#13#10+
  '            n := i;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkDeepNesting),
      '5 verschachtelte Schleifen/if – Warning');
  finally F.Free; end;
end;

procedure TTestNewChecks.DeepNesting_TryAroundFourLevels_NoFinding;
// try um 4 logische Ebenen → Tiefe 4, kein Befund
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var i, j, k: Integer;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    for i := 0 to 9 do'#13#10+
  '      for j := 0 to 9 do'#13#10+
  '        for k := 0 to 9 do'#13#10+
  '          if i > j then DoIt;'#13#10+
  '  finally'#13#10+
  '    Cleanup;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkDeepNesting),
      'try um 4 logische Ebenen – Tiefe 4, am Limit, kein Befund');
  finally F.Free; end;
end;

{ ---- Suppression ---- }
// Diese Tests speichern Pascal-Code in tempordativen Dateien, weil Suppression
// das Originalfile lesen muss (FindingsOf nutzt nur Strings).

procedure WriteTempPas(const Content: string; out FileName: string);
begin
  FileName := IncludeTrailingPathDelimiter(TPath.GetTempPath) +
              'sca_test_' + IntToStr(Random(MaxInt)) + '.pas';
  TFile.WriteAllText(FileName, Content, TEncoding.UTF8);
end;

procedure TTestNewChecks.Suppression_NoinspectionSpecificKind_FiltersFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  // noinspection MemoryLeak'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  list.Add(''x'');'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
        '// noinspection MemoryLeak unterdrueckt das Leak');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_NoinspectionAll_FiltersAllFindings;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  // noinspection All'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  list.Add(''x'');'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
        '// noinspection All unterdrueckt alles');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_WrongKind_DoesNotFilter;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  // noinspection SQLInjection'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  list.Add(''x'');'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual(1, TFindingHelper.Count(F, fkMemoryLeak),
        'Falsche Kategorie unterdrueckt nicht');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_MultipleKinds_FiltersAll;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TStringList;'#13#10+
  'begin'#13#10+
  '  // noinspection MemoryLeak, MissingFinally'#13#10+
  '  list := TStringList.Create;'#13#10+
  '  list.Add(''x'');'#13#10+
  '  list.Free;'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
        'MemoryLeak unterdrueckt');
      Assert.AreEqual(0, TFindingHelper.Count(F, fkMissingFinally),
        'MissingFinally unterdrueckt');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_NoinspectionTodoComment_FiltersFinding;
// KindFromName wurde um 'todocomment' erweitert (vorher Silent-Bypass).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'begin'#13#10+
  '  // noinspection TodoComment'#13#10+
  '  // TODO: implementieren'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual(0, TFindingHelper.Count(F, fkTodoComment),
        '// noinspection TodoComment unterdrueckt den TODO-Befund');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_NoinspectionEmptyMethod_FiltersFinding;
// KindFromName um 'emptymethod' erweitert.
const SRC =
  'unit t; implementation'#13#10+
  '// noinspection EmptyMethod'#13#10+
  'procedure TFoo.NothingHere;'#13#10+
  'begin'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      Assert.AreEqual(0, TFindingHelper.Count(F, fkEmptyMethod),
        '// noinspection EmptyMethod unterdrueckt leere Methode');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.Suppression_NoinspectionDuplicateBlock_FiltersFinding;
// KindFromName um 'duplicateblock' erweitert.
// Hinweis: DuplicateBlock braucht >=8 identische Zeilen. Test deckt einen
// minimalen Block ab und prueft: Suppression-Comment auf der ZWEITEN
// Wiederholung unterdrueckt den Befund (oder mindestens nicht alle).
const SRC =
  'unit t; implementation'#13#10+
  'procedure A;'#13#10+
  'begin'#13#10+
  '  Logger.Info(''start a'');'#13#10+
  '  Conn.Open;'#13#10+
  '  Q.SQL.Text := ''select 1'';'#13#10+
  '  Q.Open;'#13#10+
  '  Q.First;'#13#10+
  '  Q.Close;'#13#10+
  '  Conn.Close;'#13#10+
  '  Logger.Info(''end a'');'#13#10+
  'end;'#13#10+
  '// noinspection DuplicateBlock'#13#10+
  'procedure B;'#13#10+
  'begin'#13#10+
  '  Logger.Info(''start a'');'#13#10+
  '  Conn.Open;'#13#10+
  '  Q.SQL.Text := ''select 1'';'#13#10+
  '  Q.Open;'#13#10+
  '  Q.First;'#13#10+
  '  Q.Close;'#13#10+
  '  Conn.Close;'#13#10+
  '  Logger.Info(''end a'');'#13#10+
  'end;';
var
  FName: string;
  F: TObjectList<TLeakFinding>;
  CountWithSuppress: Integer;
begin
  WriteTempPas(SRC, FName);
  try
    F := TStaticAnalyzer2.AnalyzeLeaks(FName);
    try
      // Mindestens ein Befund muss durch die Suppression unterdrueckt sein -
      // ohne Suppression haetten wir 2 Treffer (beide Bloecke).
      CountWithSuppress := TFindingHelper.Count(F, fkDuplicateBlock);
      Assert.IsTrue(CountWithSuppress < 2,
        '// noinspection DuplicateBlock muss mind. einen Befund unterdruecken');
    finally F.Free; end;
  finally
    if FileExists(FName) then DeleteFile(FName);
  end;
end;

procedure TTestNewChecks.DeadCode_ExitBeforeExceptBlock_NoFinding;
// exit als letzte Anweisung im try-Body, danach except-Block – KEIN toter Code
const SRC =
  'unit t; implementation'#13#10+
  'function TFoo.Get(node: TXmlNode): string;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    Result := node.Text;'#13#10+
  '    Exit;'#13#10+
  '  except'#13#10+
  '    on E: Exception do raise;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkDeadCode),
      'except-Block ist kein sequenzieller Code – kein DeadCode');
  finally F.Free; end;
end;

procedure TTestNewChecks.DeadCode_ExitBeforeFinallyBlock_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Cleanup;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    DoWork;'#13#10+
  '    Exit;'#13#10+
  '  finally'#13#10+
  '    DoCleanup;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkDeadCode),
      'finally-Block laeuft auch nach Exit – kein DeadCode');
  finally F.Free; end;
end;

{ ---- Robustheit ---- }

procedure TTestNewChecks.Robust_NonExistentFile_ReportsFileError;
// Eine Datei die nicht existiert -> fkFileReadError, kein Crash
var F: TObjectList<TLeakFinding>;
begin
  F := TStaticAnalyzer2.AnalyzeLeaks(
    'D:\does\not\exist\nirvana.pas');
  try
    Assert.IsTrue(F.Count >= 1, 'Mindestens 1 Befund erwartet');
    Assert.IsTrue(TFindingHelper.Count(F, fkFileReadError) >= 1,
      'Nicht-existente Datei -> fkFileReadError');
  finally F.Free; end;
end;

procedure TTestNewChecks.Robust_EmptyFileName_ReportsFileError;
var F: TObjectList<TLeakFinding>;
begin
  F := TStaticAnalyzer2.AnalyzeLeaks('');
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFileReadError) >= 1,
      'Leerer Dateiname -> fkFileReadError');
  finally F.Free; end;
end;

procedure TTestNewChecks.Robust_NonExistentDirectory_ReportsFileError;
var F: TObjectList<TLeakFinding>;
begin
  F := TStaticAnalyzer2.AnalyzeLeaksRecursive(
    'D:\nirgendwo\unbekannt');
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFileReadError) >= 1,
      'Nicht-existentes Verzeichnis -> fkFileReadError');
  finally F.Free; end;
end;

procedure TTestNewChecks.Robust_EmptyDirectory_ReportsFileError;
// Test mit leerem String-Pfad -> fkFileReadError
var F: TObjectList<TLeakFinding>;
begin
  F := TStaticAnalyzer2.AnalyzeLeaksRecursive('');
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFileReadError) >= 1,
      'Leerer Pfad -> fkFileReadError');
  finally F.Free; end;
end;

{ ---- UnusedUses – H1 ---- }

procedure TTestUnusedUses.Uses_H1_ShortName_Qualifier_NoFinding;
// 'IniFiles.' als Kurzname-Praefix → H1 erkennt Verwendung
const SRC =
  'unit t;'#13#10+
  'uses System.IniFiles;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var x: IniFiles.TIniFile;'#13#10+
  'begin x := IniFiles.TIniFile.Create(''x''); x.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'Kurzname-Praefix IniFiles. → H1 – kein Befund');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H1_FullQualName_Qualifier_NoFinding;
// 'System.Zip.' als vollstaendiger Praefix → H1 erkennt Verwendung
const SRC =
  'unit t;'#13#10+
  'uses System.Zip;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var z: System.Zip.TZipFile;'#13#10+
  'begin z := System.Zip.TZipFile.Create; z.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'Vollname-Praefix System.Zip. → H1 – kein Befund');
  finally F.Free; end;
end;

{ ---- UnusedUses – H2 System ---- }

procedure TTestUnusedUses.Uses_H2_Generics_TDictionary_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.Generics.Collections;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var d: TDictionary<string,Integer>;'#13#10+
  'begin d := TDictionary<string,Integer>.Create; d.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'TDictionary → Generics.Collections benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_Generics_TList_NoFinding;
// Regression: TList<string> ohne TDictionary muss Generics.Collections erkennen
const SRC =
  'unit t;'#13#10+
  'uses System.Generics.Collections;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var list: TList<string>;'#13#10+
  'begin list := TList<string>.Create; list.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'TList<T> → Generics.Collections benoetigt, kein false positive');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_Generics_TObjectList_NoFinding;
// Regression: TObjectList<T> muss Generics.Collections erkennen
const SRC =
  'unit t;'#13#10+
  'uses System.Generics.Collections;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar;'#13#10+
  'var items: TObjectList<TObject>;'#13#10+
  'begin items := TObjectList<TObject>.Create; items.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'TObjectList<T> → Generics.Collections benoetigt, kein false positive');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_Math_Floor_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.Math;'#13#10+
  'implementation'#13#10+
  'function TFoo.Round2(x: Double): Integer;'#13#10+
  'begin Result := Floor(x); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'Floor() → System.Math benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_StrUtils_PosEx_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.StrUtils;'#13#10+
  'implementation'#13#10+
  'function TFoo.Find(const S, Sub: string): Integer;'#13#10+
  'begin Result := PosEx(Sub, S, 1); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'PosEx → System.StrUtils benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_DateUtils_DaysBetween_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.DateUtils;'#13#10+
  'implementation'#13#10+
  'function TFoo.Age(Born: TDateTime): Integer;'#13#10+
  'begin Result := DaysBetween(Now, Born); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'DaysBetween → System.DateUtils benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_IOUtils_TFile_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.IOUtils;'#13#10+
  'implementation'#13#10+
  'function TFoo.Exists(const P: string): Boolean;'#13#10+
  'begin Result := TFile.Exists(P); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'TFile → System.IOUtils benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_JSON_TJSONObject_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.JSON;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Parse(const S: string);'#13#10+
  'var j: TJSONObject;'#13#10+
  'begin j := TJSONObject.Create; j.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'TJSONObject → System.JSON benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_RegEx_TRegEx_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.RegularExpressions;'#13#10+
  'implementation'#13#10+
  'function TFoo.Match(const S: string): Boolean;'#13#10+
  'begin Result := TRegEx.IsMatch(S, ''\d+''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'TRegEx → System.RegularExpressions benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_Zip_TZipFile_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.Zip;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Compress(const Path: string);'#13#10+
  'var z: TZipFile;'#13#10+
  'begin z := TZipFile.Create; z.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'TZipFile → System.Zip benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_Diagnostics_TStopwatch_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.Diagnostics;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Measure;'#13#10+
  'var sw: TStopwatch;'#13#10+
  'begin sw := TStopwatch.StartNew; DoWork; sw.Stop; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'TStopwatch → System.Diagnostics benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_Threading_TTask_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.Threading;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.RunAsync;'#13#10+
  'begin TTask.Run(procedure begin DoWork; end); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'TTask → System.Threading benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_Classes_TStringList_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.Classes;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Build;'#13#10+
  'var sl: TStringList;'#13#10+
  'begin sl := TStringList.Create; sl.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'TStringList → System.Classes benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_Registry_TRegistry_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses System.Win.Registry;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.ReadKey;'#13#10+
  'var r: TRegistry;'#13#10+
  'begin r := TRegistry.Create; r.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'TRegistry → System.Win.Registry benoetigt');
  finally F.Free; end;
end;

{ ---- UnusedUses – H2 VCL ---- }

procedure TTestUnusedUses.Uses_H2_VclDialogs_ShowMessage_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses Vcl.Dialogs;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Warn(const S: string);'#13#10+
  'begin ShowMessage(S); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'ShowMessage → Vcl.Dialogs benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_VclGraphics_TBitmap_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses Vcl.Graphics;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Draw;'#13#10+
  'var bmp: TBitmap;'#13#10+
  'begin bmp := TBitmap.Create; bmp.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'TBitmap → Vcl.Graphics benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_VclComCtrls_TTabSheet_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses Vcl.ComCtrls;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.AddTab(PC: TPageControl);'#13#10+
  'var ts: TTabSheet;'#13#10+
  'begin ts := TTabSheet.Create(PC); ts.PageControl := PC; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'TTabSheet → Vcl.ComCtrls benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_H2_VclMenus_TPopupMenu_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses Vcl.Menus;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.BuildMenu;'#13#10+
  'var pm: TPopupMenu;'#13#10+
  'begin pm := TPopupMenu.Create(nil); pm.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'TPopupMenu → Vcl.Menus benoetigt');
  finally F.Free; end;
end;

{ ---- UnusedUses – H2 Datenbank ---- }

procedure TTestUnusedUses.Uses_H2_DataDB_TDataSet_NoFinding;
const SRC =
  'unit t;'#13#10+
  'uses Data.DB;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Load(DS: TDataSet);'#13#10+
  'begin DS.Open; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'TDataSet → Data.DB benoetigt');
  finally F.Free; end;
end;

{ ---- UnusedUses – Randfaelle ---- }

procedure TTestUnusedUses.Uses_UnknownUnit_NoMapping_NoFinding;
// Eine unbekannte Unit (kein Mapping) → nie melden (kein false positive)
const SRC =
  'unit t;'#13#10+
  'uses MyCompanyUtils;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'Unbekannte Unit ohne Mapping – nie melden (false positive verhindern)');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_TypeAlias_NoFinding;
// TMyEvent = TNotifyEvent – TNotifyEvent muss System.Classes erkennen
const SRC =
  'unit t;'#13#10+
  'uses System.Classes;'#13#10+
  'type'#13#10+
  '  TMyEvent = TNotifyEvent;'#13#10+
  'implementation'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'TNotifyEvent in Typ-Alias – System.Classes benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_WithStatement_NoFinding;
// with DataSet do – TDataSet aus Data.DB muss erkannt werden
const SRC =
  'unit t;'#13#10+
  'uses Data.DB;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Load(DS: TDataSet);'#13#10+
  'begin'#13#10+
  '  with DS do'#13#10+
  '    Open;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'TDataSet im with-Ausdruck – Data.DB benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_RegSuffix_NeverReported;
// Units die auf 'reg' enden werden nie gemeldet (Registrierungs-Units)
const SRC =
  'unit t;'#13#10+
  'uses MyComponentsReg;'#13#10+
  'implementation'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'Unit endet auf ''reg'' → nie melden');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_ShortNameUsed_LongNameInUses_NoFinding;
// uses Vcl.Grids, aber Verwendung als Kurzname 'TStringGrid'
const SRC =
  'unit t;'#13#10+
  'uses Vcl.Grids;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Build;'#13#10+
  'var g: TStringGrid;'#13#10+
  'begin g := TStringGrid.Create(nil); g.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'TStringGrid aus Vcl.Grids – kein Befund');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_TypeParam_Generic_NoFinding;
// TObjectList<TForm> – TForm kommt aus Vcl.Forms als Typparameter
const SRC =
  'unit t;'#13#10+
  'uses Vcl.Forms, System.Generics.Collections;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Build;'#13#10+
  'var list: TObjectList<TForm>;'#13#10+
  'begin list := TObjectList<TForm>.Create; list.Free; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkUnusedUses),
      'TForm als Typparameter – Vcl.Forms benoetigt');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_InterfaceAndImpl_OnlyOnceReported;
// Gleiche Unit in interface UND implementation uses – nur 1x melden
const SRC =
  'unit t;'#13#10+
  'uses System.IniFiles;'#13#10+
  'implementation'#13#10+
  'uses System.IniFiles;'#13#10+
  'procedure TFoo.Bar; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkUnusedUses),
      'Doppelter uses-Eintrag – nur 1 Befund');
  finally F.Free; end;
end;

procedure TTestUnusedUses.Uses_AllUnused_AllReported;
// Drei unbekannte Units – alle drei werden gemeldet
const SRC =
  'unit t;'#13#10+
  'uses System.IniFiles, System.Zip, Vcl.Menus;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar; begin DoNothing; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(3, TFindingHelper.Count(F, fkUnusedUses),
      'Drei ungenutzte Units – alle drei als Warning');
  finally F.Free; end;
end;

// =============================================================================
// LongParamList-Tests
// =============================================================================

procedure TTestLongParamList.LongParamList_FiveParams_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(A, B, C, D, E: Integer);'#13#10+
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLongParamList));
  finally F.Free; end;
end;

procedure TTestLongParamList.LongParamList_SixParams_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(A, B, C, D, E, F: Integer);'#13#10+
  'begin end;';
var Findings: TObjectList<TLeakFinding>;
begin
  Findings := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(Findings, fkLongParamList));
  finally Findings.Free; end;
end;

procedure TTestLongParamList.LongParamList_TenParams_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(A, B, C, D, E, F, G, H, I, J: Integer);'#13#10+
  'begin end;';
var Findings: TObjectList<TLeakFinding>;
begin
  Findings := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(Findings, fkLongParamList));
  finally Findings.Free; end;
end;

procedure TTestLongParamList.LongParamList_NoParams_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLongParamList));
  finally F.Free; end;
end;

procedure TTestLongParamList.LongParamList_AllConstParams_StillCounted;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(const A, B, C, D, E, F: Integer);'#13#10+
  'begin end;';
var Findings: TObjectList<TLeakFinding>;
begin
  Findings := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(Findings, fkLongParamList));
  finally Findings.Free; end;
end;

procedure TTestLongParamList.LongParamList_VarParams_StillCounted;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(var A, B, C: Integer; var D, E, F: string);'#13#10+
  'begin end;';
var Findings: TObjectList<TLeakFinding>;
begin
  Findings := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(Findings, fkLongParamList));
  finally Findings.Free; end;
end;

procedure TTestLongParamList.LongParamList_FunctionWithSeven_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'function Calc(A, B, C, D, E, F, G: Integer): Integer;'#13#10+
  'begin Result := A; end;';
var Findings: TObjectList<TLeakFinding>;
begin
  Findings := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(Findings, fkLongParamList));
  finally Findings.Free; end;
end;

procedure TTestLongParamList.LongParamList_TwoMethodsBothLong_BothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(A, B, C, D, E, F: Integer); begin end;'#13#10+
  'procedure Bar(A, B, C, D, E, F, G: Integer); begin end;';
var Findings: TObjectList<TLeakFinding>;
begin
  Findings := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(2, TFindingHelper.Count(Findings, fkLongParamList));
  finally Findings.Free; end;
end;

procedure TTestLongParamList.LongParamList_GroupedSameType_StillCounted;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(A, B, C: Integer; D, E, F: string);'#13#10+
  'begin end;';
var Findings: TObjectList<TLeakFinding>;
begin
  Findings := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(Findings, fkLongParamList));
  finally Findings.Free; end;
end;

procedure TTestLongParamList.LongParamList_MixedShortAndLong_OnlyLongReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Short(A: Integer); begin end;'#13#10+
  'procedure Long(A, B, C, D, E, F: Integer); begin end;';
var Findings: TObjectList<TLeakFinding>;
begin
  Findings := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(Findings, fkLongParamList));
  finally Findings.Free; end;
end;

// =============================================================================
// MagicNumbers-Tests
// =============================================================================

procedure TTestMagicNumbers.Magic_GreaterThanLargeLiteral_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(X: Integer);'#13#10+
  'begin if X > 50 then Exit; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Magic_LessThanLargeLiteral_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(X: Integer);'#13#10+
  'begin if X < 200 then Exit; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Magic_EqualsLargeLiteral_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(X: Integer);'#13#10+
  'begin if X = 4711 then Exit; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Magic_NotEqualsLargeLiteral_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(X: Integer);'#13#10+
  'begin if X <> 999 then Exit; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Magic_TrivialZero_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(X: Integer);'#13#10+
  'begin if X > 0 then Exit; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Magic_TrivialOne_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(X: Integer);'#13#10+
  'begin if X >= 1 then Exit; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Magic_TrivialMinusOne_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(X: Integer);'#13#10+
  'begin if X = -1 then Exit; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Magic_TrivialHundred_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(X: Integer);'#13#10+
  'begin if X = 100 then Exit; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Magic_NoIfStatement_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var X: Integer;'#13#10+
  'begin X := 4711; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Magic_TwoIfsBothMagic_BothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(X, Y: Integer);'#13#10+
  'begin'#13#10+
  '  if X > 50 then Exit;'#13#10+
  '  if Y < 200 then Exit;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(2, TFindingHelper.Count(F, fkMagicNumber));
  finally F.Free; end;
end;

procedure TTestMagicNumbers.Magic_ParenthesisLeftBoundary_ReportsHint;
// '(Count>250)' ohne Whitespace zwischen '(' und Operator. Vor dem Fix
// in ExtractMagicNumber wurde nur ' >' als Vorgaenger akzeptiert -
// dieser Case wurde uebersehen.
// Achtung: 100 ist in IsTrivial-Liste (uMagicNumbers.pas) -> 250 verwenden
// damit der Detektor wirklich anschlaegt.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(Count: Integer);'#13#10+
  'begin'#13#10+
  '  if (Count>250) then Exit;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkMagicNumber),
    '(Count>250) ohne Spaces muss erkannt werden');
  finally F.Free; end;
end;

// =============================================================================
// DuplicateString-Tests
// =============================================================================

procedure TTestDuplicateString.Dup_ThreeOccurrences_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''wichtig'';'#13#10+
  '  s := ''wichtig'';'#13#10+
  '  s := ''wichtig'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkDuplicateString));
  finally F.Free; end;
end;

procedure TTestDuplicateString.Dup_TwoOccurrences_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''wichtig'';'#13#10+
  '  s := ''wichtig'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDuplicateString));
  finally F.Free; end;
end;

procedure TTestDuplicateString.Dup_TooShortString_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''ab'';'#13#10+
  '  s := ''ab'';'#13#10+
  '  s := ''ab'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDuplicateString));
  finally F.Free; end;
end;

procedure TTestDuplicateString.Dup_TrivialFormatSpec_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''%s'';'#13#10+
  '  s := ''%s'';'#13#10+
  '  s := ''%s'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDuplicateString));
  finally F.Free; end;
end;

procedure TTestDuplicateString.Dup_FourOccurrences_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''hello world'';'#13#10+
  '  s := ''hello world'';'#13#10+
  '  s := ''hello world'';'#13#10+
  '  s := ''hello world'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkDuplicateString));
  finally F.Free; end;
end;

procedure TTestDuplicateString.Dup_DifferentStrings_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''Eins'';'#13#10+
  '  s := ''Zwei'';'#13#10+
  '  s := ''Drei'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDuplicateString));
  finally F.Free; end;
end;

procedure TTestDuplicateString.Dup_TwoDifferentDuplicates_BothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''alpha'';'#13#10+
  '  s := ''alpha'';'#13#10+
  '  s := ''alpha'';'#13#10+
  '  s := ''beta'';'#13#10+
  '  s := ''beta'';'#13#10+
  '  s := ''beta'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(2, TFindingHelper.Count(F, fkDuplicateString));
  finally F.Free; end;
end;

procedure TTestDuplicateString.Dup_StringInAssignment_Counted;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''SELECT * FROM t'';'#13#10+
  '  s := ''SELECT * FROM t'';'#13#10+
  '  s := ''SELECT * FROM t'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkDuplicateString));
  finally F.Free; end;
end;

procedure TTestDuplicateString.Dup_StringInCall_Counted;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  WriteLn(''Hallo Welt'');'#13#10+
  '  WriteLn(''Hallo Welt'');'#13#10+
  '  WriteLn(''Hallo Welt'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkDuplicateString));
  finally F.Free; end;
end;

procedure TTestDuplicateString.Dup_TrueFalseTrivial_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''true'';'#13#10+
  '  s := ''true'';'#13#10+
  '  s := ''true'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDuplicateString));
  finally F.Free; end;
end;

// =============================================================================
// HardcodedPath-Tests
// =============================================================================

procedure TTestHardcodedPath.Path_WindowsDriveBackslash_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''C:\Windows\System32'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_WindowsDriveForwardslash_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''D:/Daten/projekt'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_UNCPath_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''\\fileserver\share\sub'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_UnixUsr_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''/usr/local/bin/foo'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_UnixEtc_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''/etc/hosts'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_UnixHome_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''/home/user/.config'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_UnixHomeShort_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''~/projects/src'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_RegularString_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''hello world'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_RelativePath_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin p := ''subdir/file.txt'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

procedure TTestHardcodedPath.Path_SameDuplicateOnce_NotDuplicated;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var p: string;'#13#10+
  'begin'#13#10+
  '  p := ''C:\Temp'';'#13#10+
  '  p := ''C:\Temp'';'#13#10+
  '  p := ''C:\Temp'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkHardcodedPath));
  finally F.Free; end;
end;

// =============================================================================
// DebugOutput-Tests
// =============================================================================

procedure TTestDebugOutput.Debug_WriteLnCall_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin WriteLn(''debug''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_ShowMessageCall_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin ShowMessage(''Hallo''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_MessageDlgCall_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin MessageDlg(''ok'', mtInformation, [mbOK], 0); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_OutputDebugStringCall_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin OutputDebugString(''hi''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_InputBoxCall_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin s := InputBox(''titel'', ''prompt'', ''default''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_NormalCall_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin Logger.Info(''ok''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_PrefixedNameWordBoundary_NoFalsePositive;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin MyWriteLn(''hi''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_LoggerWriteCall_NoFalsePositive;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin Logger.WriteEntry(''msg''); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_TwoDebugCalls_BothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  WriteLn(''a'');'#13#10+
  '  ShowMessage(''b'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(2, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

procedure TTestDebugOutput.Debug_ShowMessagePosCall_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin ShowMessagePos(''x'', 100, 100); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkDebugOutput));
  finally F.Free; end;
end;

// =============================================================================
// TodoComment-Tests (filebasiert via FindingsOfFile)
// =============================================================================

procedure TTestTodoComment.Todo_LineComment_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  '// TODO: Tabelle persistieren'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_FixmeMarker_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  '// FIXME: race condition'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_HackMarker_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  '// HACK: workaround fuer Bug'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_XxxMarker_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  '// XXX: muss noch geklaert werden'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_BraceComment_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  '{ TODO: refactoring noetig }'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_MultilineBraceComment_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  '{'#13#10+
  '  FIXME: das hier muss neu gebaut werden'#13#10+
  '  weil...'#13#10+
  '}'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_TodoInsideStringLiteral_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin s := ''TODO marker im String''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_TodoAsIdentifier_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var TodoList: Integer;'#13#10+
  'begin TodoList := 0; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_LowercaseMarker_StillReported;
const SRC =
  'unit t; implementation'#13#10+
  '// todo: kleinschreibung'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

procedure TTestTodoComment.Todo_NoMarker_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  '// gewoehnlicher Kommentar'#13#10+
  'procedure Foo; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkTodoComment));
  finally F.Free; end;
end;

// =============================================================================
// EmptyMethod-Tests
// =============================================================================

procedure TTestEmptyMethod.Empty_ProcedureBody_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkEmptyMethod));
  finally F.Free; end;
end;

procedure TTestEmptyMethod.Empty_FunctionBody_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'function Foo: Integer;'#13#10+
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkEmptyMethod));
  finally F.Free; end;
end;

procedure TTestEmptyMethod.Empty_BodyWithInherited_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'destructor TFoo.Destroy;'#13#10+
  'begin inherited; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkEmptyMethod));
  finally F.Free; end;
end;

procedure TTestEmptyMethod.Empty_BodyWithSingleAssign_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var x: Integer;'#13#10+
  'begin x := 5; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkEmptyMethod));
  finally F.Free; end;
end;

procedure TTestEmptyMethod.Empty_TwoEmptyMethods_BothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo; begin end;'#13#10+
  'procedure Bar; begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(2, TFindingHelper.Count(F, fkEmptyMethod));
  finally F.Free; end;
end;

procedure TTestEmptyMethod.Empty_OneFilledOneEmpty_OnlyEmptyReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin end;'#13#10+
  'procedure Bar;'#13#10+
  'begin Foo; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkEmptyMethod));
  finally F.Free; end;
end;

procedure TTestEmptyMethod.Empty_Constructor_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'constructor TFoo.Create;'#13#10+
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkEmptyMethod));
  finally F.Free; end;
end;

procedure TTestEmptyMethod.Empty_Destructor_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'destructor TFoo.Destroy;'#13#10+
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkEmptyMethod));
  finally F.Free; end;
end;

procedure TTestEmptyMethod.Empty_BodyWithCall_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin DoSomething; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkEmptyMethod));
  finally F.Free; end;
end;

procedure TTestEmptyMethod.Empty_ForwardDecl_NoFinding;
// Forward-Declaration in der Class - dort gibt es kein nkBlock,
// also auch keine Empty-Method-Meldung.
const SRC =
  'unit t; interface'#13#10+
  'type TFoo = class'#13#10+
  '  procedure Bar;'#13#10+
  'end;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Bar; begin DoStuff; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkEmptyMethod));
  finally F.Free; end;
end;

// =============================================================================
// EmptyExcept-Erweiterungen
// =============================================================================

procedure TTestEmptyExceptExt.EmptyExcept_OnlyWhitespace_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  try DoStuff'#13#10+
  '  except'#13#10+
  '     '#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkEmptyExcept));
  finally F.Free; end;
end;

procedure TTestEmptyExceptExt.EmptyExcept_NestedTryExcept_AllReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    try DoStuff'#13#10+
  '    except'#13#10+
  '    end;'#13#10+
  '  except'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(2, TFindingHelper.Count(F, fkEmptyExcept));
  finally F.Free; end;
end;

procedure TTestEmptyExceptExt.EmptyExcept_InsideTryFinally_Reported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  try'#13#10+
  '    try DoStuff except end;'#13#10+
  '  finally'#13#10+
  '    Cleanup;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkEmptyExcept));
  finally F.Free; end;
end;

procedure TTestEmptyExceptExt.EmptyExcept_TwoExceptBlocks_BothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  try DoA except end;'#13#10+
  '  try DoB except end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(2, TFindingHelper.Count(F, fkEmptyExcept));
  finally F.Free; end;
end;

procedure TTestEmptyExceptExt.EmptyExcept_WithOnAndEmptyOther_OnlyEmptyReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  try DoA except on E: Exception do Log(E.Message); end;'#13#10+
  '  try DoB except end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkEmptyExcept));
  finally F.Free; end;
end;

// =============================================================================
// SQLInjection-Erweiterungen
// =============================================================================

procedure TTestSQLInjectionExt.SQL_AssignSelectStarConcat_IntToStrSafe_NoFinding;
// 'WHERE id = ' + IntToStr(Id) ist tatsaechlich injection-sicher -
// IntToStr akzeptiert nur Integer, der Output ist garantiert numerisch.
// Recent fix `AllConcatTermsSafe` whitelistet IntToStr/Int64ToStr/
// FormatInt/QuotedStr/QuotedSQL etc. - alle Konkat-Terme sind entweder
// String-Literale ODER safe-cast-Calls -> kein Risiko.
//
// Wer trotzdem warnen will: bare Variable statt IntToStr verwenden.
// Siehe SQL_DeleteWithVarConcat fuer das korrekte Risiko-Pattern.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(Id: Integer);'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  Query.SQL.Text := ''SELECT * FROM users WHERE id = '' + IntToStr(Id);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(0, TFindingHelper.Count(F, fkSQLInjection),
      'IntToStr-Konkat ist safe-cast-whitelisted');
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_DeleteWithVarConcat_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(Name: string);'#13#10+
  'begin'#13#10+
  '  Query.SQL.Text := ''DELETE FROM t WHERE name = '' + Name;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSQLInjection) >= 1);
  finally F.Free; end;
end;

procedure TTestSQLInjectionExt.SQL_AssignWithoutSQLKeyword_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin'#13#10+
  '  s := ''hello '' + ''world'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkSQLInjection));
  finally F.Free; end;
end;

// =============================================================================
// HardcodedSecret-Erweiterungen
// =============================================================================

procedure TTestHardcodedSecretExt.Secret_PwdLowercaseAssign_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var pwd: string;'#13#10+
  'begin pwd := ''geheim123''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkHardcodedSecret) >= 1);
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_SecretAssignedLiteral_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var secret: string;'#13#10+
  'begin secret := ''abc123def456''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkHardcodedSecret) >= 1);
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_PrivateKeyAssignedLiteral_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var private_key: string;'#13#10+
  'begin private_key := ''-----BEGIN RSA''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkHardcodedSecret) >= 1);
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_NormalStringNoSecretName_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var msg: string;'#13#10+
  'begin msg := ''hallo''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkHardcodedSecret));
  finally F.Free; end;
end;

// =============================================================================
// FormatMismatch-Erweiterung
// =============================================================================

procedure TTestFormatMismatchExt.Format_OnePlaceholderTwoArgs_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin s := Format(''%s'', [a, b]); end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkFormatMismatch) >= 1);
  finally F.Free; end;
end;

procedure TTestFormatMismatchExt.Format_AssignmentWithoutDot_ReportsError;
// Vor dem Fix in TryExtractFormatString akzeptierte der Vorgaenger-Filter
// nur '.' - 'Result := Format(...)' (Whitespace davor) wurde uebersehen.
// Jetzt: alles was kein Identifier-Char ist, ist erlaubt.
const SRC =
  'unit t; implementation'#13#10+
  'function Foo(v: Integer): string;'#13#10+
  'begin'#13#10+
  '  Result := Format(''%d %s'', [v]);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkFormatMismatch) >= 1,
      'Format() direkt nach := muss als Mismatch erkannt werden');
  finally F.Free; end;
end;

// =============================================================================
// NilDeref-Erweiterungen
// =============================================================================

procedure TTestNilDerefExt.NilDeref_AfterFreeAndDot_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var lst: TStringList;'#13#10+
  'begin'#13#10+
  '  lst := nil;'#13#10+
  '  lst.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1);
  finally F.Free; end;
end;

procedure TTestNilDerefExt.NilDeref_TwoNilsBothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var a, b: TStringList;'#13#10+
  'begin'#13#10+
  '  a := nil;'#13#10+
  '  b := nil;'#13#10+
  '  a.Add(''x'');'#13#10+
  '  b.Add(''y'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 2);
  finally F.Free; end;
end;

procedure TTestNilDerefExt.NilDeref_AssignedFromCreate_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var lst: TStringList;'#13#10+
  'begin'#13#10+
  '  lst := TStringList.Create;'#13#10+
  '  try lst.Add(''x''); finally lst.Free; end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkNilDeref));
  finally F.Free; end;
end;

procedure TTestNilDerefExt.NilDeref_NilGuardWithBegin_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo(lst: TStringList);'#13#10+
  'begin'#13#10+
  '  if lst <> nil then'#13#10+
  '  begin'#13#10+
  '    lst.Add(''x'');'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkNilDeref));
  finally F.Free; end;
end;

procedure TTestNilDerefExt.NilDeref_AssignedGuardVarSubstring_StillReports;
// Wortgrenze: 'assigned(objOld)' darf 'obj' NICHT als geguarded gelten.
// Vor dem WholeWord-Fix in CondHasGuard wuerde der Substring-Match
// 'assigned(obj' (in 'assigned(objOld)') faelschlicherweise als Guard
// fuer 'obj' anerkannt - der NilDeref-Befund bliebe damit aus.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var obj, objOld: TStringList;'#13#10+
  'begin'#13#10+
  '  obj := nil;'#13#10+
  '  if assigned(objOld) then'#13#10+
  '    obj.Add(''x'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkNilDeref) >= 1,
      'assigned(objOld) darf nicht als Guard fuer obj gelten');
  finally F.Free; end;
end;

// =============================================================================
// MissingFinally-Erweiterungen
// =============================================================================

procedure TTestMissingFinallyExt.MissingFinally_TwoCreates_NoTry_BothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var a, b: TStringList;'#13#10+
  'begin'#13#10+
  '  a := TStringList.Create;'#13#10+
  '  b := TStringList.Create;'#13#10+
  '  a.Free;'#13#10+
  '  b.Free;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMissingFinally) >= 2);
  finally F.Free; end;
end;

procedure TTestMissingFinallyExt.MissingFinally_CreateAndImmediateRaise_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var lst: TStringList;'#13#10+
  'begin'#13#10+
  '  lst := TStringList.Create;'#13#10+
  '  raise Exception.Create(''boom'');'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMissingFinally));
  finally F.Free; end;
end;

procedure TTestMissingFinallyExt.MissingFinally_FreeAndNilNoTry_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var lst: TStringList;'#13#10+
  'begin'#13#10+
  '  lst := TStringList.Create;'#13#10+
  '  lst.Add(''x'');'#13#10+
  '  FreeAndNil(lst);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMissingFinally) >= 1);
  finally F.Free; end;
end;

procedure TTestMissingFinallyExt.MissingFinally_NestedTryFinally_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var a, b: TStringList;'#13#10+
  'begin'#13#10+
  '  a := TStringList.Create;'#13#10+
  '  try'#13#10+
  '    b := TStringList.Create;'#13#10+
  '    try b.Add(''x''); finally b.Free; end;'#13#10+
  '  finally'#13#10+
  '    a.Free;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMissingFinally));
  finally F.Free; end;
end;

procedure TTestMissingFinallyExt.MissingFinally_FreeBeforeTry_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var lst: TStringList;'#13#10+
  'begin'#13#10+
  '  lst := TStringList.Create;'#13#10+
  '  lst.Free;'#13#10+
  '  try DoStuff finally Cleanup; end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMissingFinally) >= 1);
  finally F.Free; end;
end;

procedure TTestMissingFinallyExt.MissingFinally_DestroyNoTry_ReportsWarning;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var lst: TStringList;'#13#10+
  'begin'#13#10+
  '  lst := TStringList.Create;'#13#10+
  '  lst.Add(''x'');'#13#10+
  '  lst.Destroy;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMissingFinally) >= 1);
  finally F.Free; end;
end;

// =============================================================================
// DivByZero-Erweiterungen
// =============================================================================

procedure TTestDivByZeroExt.Div_LiteralZeroMod_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var x: Integer;'#13#10+
  'begin x := 10 mod 0; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDivByZero) >= 1);
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_TwoZeroDivs_BothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var x, y: Integer;'#13#10+
  'begin'#13#10+
  '  x := 5 div 0;'#13#10+
  '  y := 7 div 0;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDivByZero) >= 2);
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_NonZeroLiteral_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var x: Integer;'#13#10+
  'begin x := 10 div 5; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDivByZero));
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_GuardedLocalVar_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var x, n: Integer;'#13#10+
  'begin'#13#10+
  '  if n <> 0 then'#13#10+
  '    x := 100 div n;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDivByZero));
  finally F.Free; end;
end;

procedure TTestDivByZeroExt.Div_StringDivisor_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var s: string;'#13#10+
  'begin s := ''10 div 0''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDivByZero));
  finally F.Free; end;
end;

// =============================================================================
// DeadCode-Erweiterungen
// =============================================================================

procedure TTestDeadCodeExt.DeadCode_NoDeadCode_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  DoA;'#13#10+
  '  DoB;'#13#10+
  '  DoC;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDeadCode));
  finally F.Free; end;
end;

procedure TTestDeadCodeExt.DeadCode_TwoExitsBothFollowedByDead_BothReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  if A then'#13#10+
  '  begin Exit; DoA; end;'#13#10+
  '  if B then'#13#10+
  '  begin Exit; DoB; end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDeadCode) >= 2);
  finally F.Free; end;
end;

procedure TTestDeadCodeExt.DeadCode_ExitAtMethodEnd_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  DoStuff;'#13#10+
  '  Exit;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDeadCode));
  finally F.Free; end;
end;

// =============================================================================
// LongMethod-Erweiterungen
// =============================================================================

procedure TTestLongMethodExt.LongMethod_TenLineBody_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var X: Integer;'#13#10+
  'begin'#13#10+
  '  X := 1;'#13#10+
  '  X := 2;'#13#10+
  '  X := 3;'#13#10+
  '  X := 4;'#13#10+
  '  X := 5;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLongMethod));
  finally F.Free; end;
end;

procedure TTestLongMethodExt.LongMethod_OnlyLineCountTooHigh_NoFinding;
// Body hat 60 Zeilen, aber nur 10 Statements (sonst alles Leerzeilen/Kommentare).
// Da BEIDE Schwellen ueberschritten sein muessen, kein Befund.
var SRC: string;
    F: TObjectList<TLeakFinding>;
    i: Integer;
begin
  SRC := 'unit t; implementation'#13#10+
         'procedure Foo;'#13#10+
         'var X: Integer;'#13#10+
         'begin'#13#10;
  // 10 Statements
  for i := 1 to 10 do
    SRC := SRC + '  X := ' + IntToStr(i) + ';'#13#10;
  // 55 leere Zeilen (Kommentare zaehlen nicht als statements)
  for i := 1 to 55 do
    SRC := SRC + '  // dummy comment line'#13#10;
  SRC := SRC + 'end;';

  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLongMethod));
  finally F.Free; end;
end;

procedure TTestLongMethodExt.LongMethod_OnlyStatementCountTooHigh_NoFinding;
// 40 Statements aber nur ~40 Zeilen - unter Zeilen-Schwelle (50).
var SRC: string;
    F: TObjectList<TLeakFinding>;
    i: Integer;
begin
  SRC := 'unit t; implementation'#13#10+
         'procedure Foo;'#13#10+
         'var X: Integer;'#13#10+
         'begin'#13#10;
  for i := 1 to 40 do
    SRC := SRC + '  X := ' + IntToStr(i) + ';'#13#10;
  SRC := SRC + 'end;';

  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLongMethod));
  finally F.Free; end;
end;

procedure TTestLongMethodExt.LongMethod_TwoMethodsOneLong_OnlyLongReported;
var SRC: string;
    F: TObjectList<TLeakFinding>;
    i: Integer;
begin
  SRC := 'unit t; implementation'#13#10+
         'procedure Short;'#13#10+
         'begin DoStuff; end;'#13#10+
         'procedure Long;'#13#10+
         'var X: Integer;'#13#10+
         'begin'#13#10;
  for i := 1 to 60 do
    SRC := SRC + '  X := ' + IntToStr(i) + ';'#13#10;
  SRC := SRC + 'end;';

  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkLongMethod));
  finally F.Free; end;
end;

procedure TTestLongMethodExt.LongMethod_EmptyBody_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLongMethod));
  finally F.Free; end;
end;

procedure TTestLongMethodExt.LongMethod_LongCommentNoStatements_NoFinding;
// Viele Kommentar-Zeilen, kein Code - keine Statements -> kein Befund.
var SRC: string;
    F: TObjectList<TLeakFinding>;
    i: Integer;
begin
  SRC := 'unit t; implementation'#13#10+
         'procedure Foo;'#13#10+
         'begin'#13#10;
  for i := 1 to 70 do
    SRC := SRC + '  // ' + IntToStr(i)+ ' kommentar'#13#10;
  SRC := SRC + 'end;';

  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkLongMethod));
  finally F.Free; end;
end;

procedure TTestLongMethodExt.LongMethod_BothThresholdsExceeded_ReportsHint;
// 60 Zeilen UND 60 statements - beide Schwellen ueberschritten.
var SRC: string;
    F: TObjectList<TLeakFinding>;
    i: Integer;
begin
  SRC := 'unit t; implementation'#13#10+
         'procedure Foo;'#13#10+
         'var X: Integer;'#13#10+
         'begin'#13#10;
  for i := 1 to 60 do
    SRC := SRC + '  X := ' + IntToStr(i) + ';'#13#10;
  SRC := SRC + 'end;';

  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkLongMethod) >= 1);
  finally F.Free; end;
end;

// =============================================================================
// DeepNesting-Erweiterungen
// =============================================================================

procedure TTestDeepNestingExt.DeepNesting_NoNesting_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  DoA;'#13#10+
  '  DoB;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDeepNesting));
  finally F.Free; end;
end;

procedure TTestDeepNestingExt.DeepNesting_FourIfsExactlyAtLimit_NoFinding;
// MAX_DEPTH = 4, also genau 4 Ebenen ist OK.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  if A then'#13#10+
  '    if B then'#13#10+
  '      if C then'#13#10+
  '        if D then'#13#10+
  '          DoIt;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDeepNesting));
  finally F.Free; end;
end;

procedure TTestDeepNestingExt.DeepNesting_FiveIfsOverLimit_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  if A then'#13#10+
  '    if B then'#13#10+
  '      if C then'#13#10+
  '        if D then'#13#10+
  '          if E then'#13#10+
  '            DoIt;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDeepNesting) >= 1);
  finally F.Free; end;
end;

procedure TTestDeepNestingExt.DeepNesting_DeepForLoops_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var i, j, k, l, m: Integer;'#13#10+
  'begin'#13#10+
  '  for i := 1 to 10 do'#13#10+
  '    for j := 1 to 10 do'#13#10+
  '      for k := 1 to 10 do'#13#10+
  '        for l := 1 to 10 do'#13#10+
  '          for m := 1 to 10 do'#13#10+
  '            DoIt;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDeepNesting) >= 1);
  finally F.Free; end;
end;

procedure TTestDeepNestingExt.DeepNesting_DeepCases_ReportsHint;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  case A of'#13#10+
  '    1: case B of'#13#10+
  '         1: case C of'#13#10+
  '              1: case D of'#13#10+
  '                   1: case E of 1: DoIt; end;'#13#10+
  '                 end;'#13#10+
  '            end;'#13#10+
  '       end;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDeepNesting) >= 1);
  finally F.Free; end;
end;

procedure TTestDeepNestingExt.DeepNesting_RepeatLoops_Counted;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'begin'#13#10+
  '  repeat'#13#10+
  '    repeat'#13#10+
  '      repeat'#13#10+
  '        repeat'#13#10+
  '          repeat'#13#10+
  '            DoIt;'#13#10+
  '          until X1;'#13#10+
  '        until X2;'#13#10+
  '      until X3;'#13#10+
  '    until X4;'#13#10+
  '  until X5;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDeepNesting) >= 1);
  finally F.Free; end;
end;

procedure TTestDeepNestingExt.DeepNesting_TwoMethodsOneDeep_OnlyDeepReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Shallow;'#13#10+
  'begin DoIt; end;'#13#10+
  'procedure Deep;'#13#10+
  'begin'#13#10+
  '  if A then'#13#10+
  '    if B then'#13#10+
  '      if C then'#13#10+
  '        if D then'#13#10+
  '          if E then DoIt;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkDeepNesting));
  finally F.Free; end;
end;

// =============================================================================
// DuplicateBlock-Tests (zeilenbasierte Block-Duplikate)
// =============================================================================

procedure TTestDuplicateBlock.Block_TwoIdenticalBlocks_ReportsHint;
// Zwei Methoden mit identischer 8-Zeilen-Logik -> ein Befund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.A;'#13#10+
  'begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  '  U := 6;'#13#10+
  '  T := 7;'#13#10+
  '  S := 8;'#13#10+
  'end;'#13#10+
  'procedure TFoo.B;'#13#10+
  'begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  '  U := 6;'#13#10+
  '  T := 7;'#13#10+
  '  S := 8;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkDuplicateBlock) >= 1,
        'Doppelter 8-Zeilen-Block soll gemeldet werden');
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_NoDuplicates_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.A;'#13#10+
  'begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  'end;'#13#10+
  'procedure TFoo.B;'#13#10+
  'begin'#13#10+
  '  Q := 10;'#13#10+
  '  R := 20;'#13#10+
  '  S := 30;'#13#10+
  '  T := 40;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDuplicateBlock));
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_TooShort_NoFinding;
// Nur 5 identische Zeilen - unter MIN_BLOCK_LINES (8), kein Befund.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.A;'#13#10+
  'begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  'end;'#13#10+
  'procedure TFoo.B;'#13#10+
  'begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDuplicateBlock));
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_TrivialLinesIgnored_NoFinding;
// Viele 'begin'/'end'-Zeilen sind trivial und zaehlen nicht. Auch
// wenn sich die Methodenrahmen aehneln, soll kein Block-Duplikat
// gemeldet werden, solange die unterschiedlichen Inhalte nur
// 1-2 nicht-triviale Zeilen sind.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.A;'#13#10+
  'begin'#13#10+
  '  if X then'#13#10+
  '  begin'#13#10+
  '    DoA;'#13#10+
  '  end;'#13#10+
  'end;'#13#10+
  'procedure TFoo.B;'#13#10+
  'begin'#13#10+
  '  if X then'#13#10+
  '  begin'#13#10+
  '    DoB;'#13#10+
  '  end;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDuplicateBlock));
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_BranchingBoilerplate_NoFinding;
// Block besteht ueberwiegend aus if/end-Logik (Validierungskette o.ae.) -
// soll NICHT als Duplikat gemeldet werden, weil das Extrahieren in eine
// gemeinsame Methode keinen Mehrwert hat (Pro Aufrufer andere Bedingungen).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.A;'#13#10+
  'begin'#13#10+
  '  if not Valid1 then Exit;'#13#10+
  '  if not Valid2 then Exit;'#13#10+
  '  if not Valid3 then Exit;'#13#10+
  '  if not Valid4 then Exit;'#13#10+
  '  if not Valid5 then Exit;'#13#10+
  '  if not Valid6 then Exit;'#13#10+
  '  if not Valid7 then Exit;'#13#10+
  '  if not Valid8 then Exit;'#13#10+
  'end;'#13#10+
  'procedure TFoo.B;'#13#10+
  'begin'#13#10+
  '  if not Valid1 then Exit;'#13#10+
  '  if not Valid2 then Exit;'#13#10+
  '  if not Valid3 then Exit;'#13#10+
  '  if not Valid4 then Exit;'#13#10+
  '  if not Valid5 then Exit;'#13#10+
  '  if not Valid6 then Exit;'#13#10+
  '  if not Valid7 then Exit;'#13#10+
  '  if not Valid8 then Exit;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkDuplicateBlock),
        'Block aus reinen if-Zeilen ist Branching-Boilerplate, soll geskippt werden');
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_ThreeIdenticalBlocks_ReportsOnce;
// Block kommt 3x vor - es soll trotzdem nur EIN Befund pro Erst-Vorkommen
// kommen (nicht 3 oder uberlappende Folge-Fenster).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.A; begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  '  U := 6;'#13#10+
  '  T := 7;'#13#10+
  '  S := 8;'#13#10+
  'end;'#13#10+
  'procedure TFoo.B; begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  '  U := 6;'#13#10+
  '  T := 7;'#13#10+
  '  S := 8;'#13#10+
  'end;'#13#10+
  'procedure TFoo.C; begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  '  U := 6;'#13#10+
  '  T := 7;'#13#10+
  '  S := 8;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkDuplicateBlock),
        'Block in 3 Methoden - genau 1 Befund (kein Mehrfach-Reporting)');
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_DifferentWhitespace_StillDetected;
// Bloecke unterscheiden sich nur in der Einrueckung / Whitespace-Anzahl.
// NormalizeLine kollabiert Whitespace - Duplikat soll trotzdem erkannt werden.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.A; begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  '  U := 6;'#13#10+
  '  T := 7;'#13#10+
  '  S := 8;'#13#10+
  'end;'#13#10+
  'procedure TFoo.B; begin'#13#10+
  '      X    :=    1;'#13#10+        // viel Whitespace
  '   Y := 2;'#13#10+
  '       Z := 3;'#13#10+
  '   W := 4;'#13#10+
  '       V := 5;'#13#10+
  '   U := 6;'#13#10+
  '       T := 7;'#13#10+
  '   S := 8;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkDuplicateBlock),
        'Whitespace-Unterschiede sollen Duplikat-Erkennung nicht verhindern');
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_DifferentCase_StillDetected;
// Bezeichner unterscheiden sich nur in Gross-/Kleinschreibung.
// Pascal ist case-insensitiv, NormalizeLine lowercased - Duplikat erkennen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.A; begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  '  U := 6;'#13#10+
  '  T := 7;'#13#10+
  '  S := 8;'#13#10+
  'end;'#13#10+
  'procedure TFoo.B; begin'#13#10+
  '  x := 1;'#13#10+                // klein
  '  y := 2;'#13#10+
  '  z := 3;'#13#10+
  '  w := 4;'#13#10+
  '  v := 5;'#13#10+
  '  u := 6;'#13#10+
  '  t := 7;'#13#10+
  '  s := 8;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkDuplicateBlock),
        'Case-Unterschiede sollen Duplikat-Erkennung nicht verhindern');
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_CommentsBetween_StillDetected;
// Im zweiten Block stehen Kommentare zwischen den Code-Zeilen. Da
// Kommentare als trivial gefiltert werden, soll der Block trotzdem als
// Duplikat erkannt werden.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.A; begin'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  '  U := 6;'#13#10+
  '  T := 7;'#13#10+
  '  S := 8;'#13#10+
  'end;'#13#10+
  'procedure TFoo.B; begin'#13#10+
  '  // erster Schritt'#13#10+
  '  X := 1;'#13#10+
  '  Y := 2;'#13#10+
  '  // zweiter Schritt'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  '  // dritter Schritt'#13#10+
  '  U := 6;'#13#10+
  '  T := 7;'#13#10+
  '  S := 8;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkDuplicateBlock),
        'Kommentare zwischen Code-Zeilen sollen Duplikat-Erkennung nicht verhindern');
  finally F.Free; end;
end;

procedure TTestDuplicateBlock.Block_FirstLineReported_NotLast;
// Der gemeldete LineNumber muss das Erst-Vorkommen sein, nicht das letzte.
const SRC =
  'unit t; implementation'#13#10+      // Zeile 1
  'procedure TFoo.A; begin'#13#10+    // 2
  '  X := 1;'#13#10+                   // 3 - Erst-Vorkommen Block-Start
  '  Y := 2;'#13#10+                   // 4
  '  Z := 3;'#13#10+                   // 5
  '  W := 4;'#13#10+                   // 6
  '  V := 5;'#13#10+                   // 7
  '  U := 6;'#13#10+                   // 8
  '  T := 7;'#13#10+                   // 9
  '  S := 8;'#13#10+                   // 10
  'end;'#13#10+                        // 11
  'procedure TFoo.B; begin'#13#10+    // 12
  '  X := 1;'#13#10+                   // 13 - Zweit-Vorkommen
  '  Y := 2;'#13#10+
  '  Z := 3;'#13#10+
  '  W := 4;'#13#10+
  '  V := 5;'#13#10+
  '  U := 6;'#13#10+
  '  T := 7;'#13#10+
  '  S := 8;'#13#10+
  'end;';
var
  F: TObjectList<TLeakFinding>;
  Finding: TLeakFinding;
  FoundExpected: Boolean;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkDuplicateBlock));
    FoundExpected := False;
    for Finding in F do
      if (Finding.Kind = fkDuplicateBlock) and (Finding.LineNumber = '3') then
      begin
        FoundExpected := True;
        Break;
      end;
    Assert.IsTrue(FoundExpected,
      'Befund-Zeile muss 3 (Erst-Vorkommen) sein, nicht 13 (Zweit-Vorkommen)');
  finally F.Free;
  end;
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak));
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
  try Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
        'FList wird nie freigegeben - genau ein Field-Leak');
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak));
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
  try Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak));
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
  try Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
  try Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak));
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
  try Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
        'Nur TBad leakt - genau ein Befund');
  finally F.Free; end;
end;

{ ---- TTestParserRobustness ---- }

procedure TTestParserRobustness.Parser_InterfaceDecl_FollowingMethodLeakDetected;
// Vorher: `IFoo = interface ... end;` hatte keinen Case in ParseTypeSection,
// fiel in TypeAlias-else-Branch, dessen Schleife beim ersten internen `;`
// brach -> komplettes Interface verloren UND der nachfolgende `end;` schloss
// einen ueberraschenden Block. Heute: tkKwInterface-Case ruft ParseClassBody
// und liest das Interface sauber - die nachfolgende Methode bleibt
// erkennbar.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  IFoo = interface'#13#10+
  '    procedure Bar;'#13#10+
  '    function Baz: Integer;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure TFoo.Test;'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  '  // L.Free fehlt!'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak in Methode nach Interface-Decl muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_GenericTypeDecl_MethodLeakDetected;
// Vorher: `TFoo<T> = class` -> Eat(tkEq) schlug am `<` fehl -> SkipToSemicolon
// -> komplette Generic-Klasse verloren. Heute: SkipGenericParams konsumiert
// `<T>` vor dem `=`.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TBox<T> = class'#13#10+
  '    procedure Add(Item: T);'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure TBox<T>.Add(Item: T);'#13#10+
  'var Tmp: TStringList;'#13#10+
  'begin'#13#10+
  '  Tmp := TStringList.Create;'#13#10+
  '  // Tmp.Free fehlt!'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak in qualifizierter Generic-Methode muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_GenericMethodSig_LeakDetected;
// Generic-Methode `function Get<T>: T;`. SkipGenericParams konsumiert das
// `<T>` nach dem Methodennamen, sodass die Param-Liste / Rueckgabetyp
// nicht verschoben werden.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure DoIt;'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  'end;'#13#10+
  'function Get<T>: T;'#13#10+
  'begin'#13#10+
  '  Result := Default(T);'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkMemoryLeak),
      'DoIt vor Generic-Method muss als Leak erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_PackedRecord_FollowingMethodLeakDetected;
// `packed record` wurde vorher als TypeAlias missinterpretiert weil
// tkKwPacked keinen Case hatte. Heute: optionales Eat(tkKwPacked) vor dem
// class/record-Switch.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TPoint = packed record'#13#10+
  '    X: Integer;'#13#10+
  '    Y: Integer;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'procedure UseLeak;'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak nach packed record muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_LabelSection_BodyLeakDetected;
// `label x;` zwischen var-Block und begin liess vorher die Outer-Schleife
// in ParseLocalVarSection enden und ParseMethodImpl sah `label` statt
// `begin` -> Body verloren. Heute: tkKwLabel wird wie var/const/type als
// Section akzeptiert und bis zum naechsten ; geskippt.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure Tricky;'#13#10+
  'label'#13#10+
  '  loop1, loop2;'#13#10+
  'var'#13#10+
  '  L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  '  // L.Free fehlt!'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak in Methode mit label-Section muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_ClassHelperFor_FollowingMethodLeakDetected;
// `record helper for string` war ein Stolperstein: nach `record` kam ein
// Ident `helper` der als Feld-Decl ge-misinterpretiert wurde. Heute:
// SkipHelperFor konsumiert `helper for <type>` bevor ParseClassBody startet.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'type'#13#10+
  '  TStringHelper = record helper for string'#13#10+
  '    function MyLen: Integer;'#13#10+
  '  end;'#13#10+
  'implementation'#13#10+
  'function TStringHelper.MyLen: Integer;'#13#10+
  'begin'#13#10+
  '  Result := Length(Self);'#13#10+
  'end;'#13#10+
  'procedure UseLeak;'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak nach record helper muss erkannt werden');
  finally F.Free; end;
end;

procedure TTestParserRobustness.Parser_IfdefDuplicatedHeaders_NoPhantomDuplicate;
// IFDEF um Method-Header herum ergibt zwei sichtbare Header im Token-Stream
// (Lexer skippt nur Comments). ParseMethodImpl entfernt jetzt einen
// Headless-Knoten wenn der naechste Token wieder ein Method-Keyword ist
// -> kein Phantom-Duplikat im AST mehr.
//
// Wir testen das indirekt: ein Leak in dem (echten) Body soll genau einmal
// gemeldet werden, nicht doppelt durch Phantom-Methode.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  '{$IFDEF FPC}'#13#10+
  'function DoIt: Integer;'#13#10+
  '{$ELSE}'#13#10+
  'function DoIt: Integer;'#13#10+
  '{$ENDIF}'#13#10+
  'var L: TStringList;'#13#10+
  'begin'#13#10+
  '  L := TStringList.Create;'#13#10+
  '  Result := L.Count;'#13#10+
  '  // L.Free fehlt!'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkMemoryLeak),
      'Leak darf nicht durch Phantom-Methoden-Duplikat verdoppelt werden');
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsWarning),
      'list.Free ausserhalb finally -> Warning');
    Assert.AreEqual(0, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(1, TFindingHelper.CountSev(F, fkMemoryLeak, lsError),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkMemoryLeak),
      '.Push(item) wird als Ownership-Transfer erkannt');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMemoryLeak);
  TDUnitX.RegisterTestFixture(TTestUnusedUses);
  TDUnitX.RegisterTestFixture(TTestNewChecks);
  TDUnitX.RegisterTestFixture(TTestEmptyExcept);
  TDUnitX.RegisterTestFixture(TTestSQLInjection);
  TDUnitX.RegisterTestFixture(TTestHardcodedSecret);
  TDUnitX.RegisterTestFixture(TTestFormatMismatch);
  TDUnitX.RegisterTestFixture(TTestLongParamList);
  TDUnitX.RegisterTestFixture(TTestMagicNumbers);
  TDUnitX.RegisterTestFixture(TTestDuplicateString);
  TDUnitX.RegisterTestFixture(TTestHardcodedPath);
  TDUnitX.RegisterTestFixture(TTestDebugOutput);
  TDUnitX.RegisterTestFixture(TTestTodoComment);
  TDUnitX.RegisterTestFixture(TTestEmptyMethod);
  TDUnitX.RegisterTestFixture(TTestEmptyExceptExt);
  TDUnitX.RegisterTestFixture(TTestSQLInjectionExt);
  TDUnitX.RegisterTestFixture(TTestHardcodedSecretExt);
  TDUnitX.RegisterTestFixture(TTestFormatMismatchExt);
  TDUnitX.RegisterTestFixture(TTestNilDerefExt);
  TDUnitX.RegisterTestFixture(TTestMissingFinallyExt);
  TDUnitX.RegisterTestFixture(TTestDivByZeroExt);
  TDUnitX.RegisterTestFixture(TTestDeadCodeExt);
  TDUnitX.RegisterTestFixture(TTestLongMethodExt);
  TDUnitX.RegisterTestFixture(TTestDeepNestingExt);
  TDUnitX.RegisterTestFixture(TTestFieldLeak);
  TDUnitX.RegisterTestFixture(TTestDuplicateBlock);
  TDUnitX.RegisterTestFixture(TTestParserRobustness);
  TDUnitX.RegisterTestFixture(TTestMemoryLeakAdvanced);

end.
