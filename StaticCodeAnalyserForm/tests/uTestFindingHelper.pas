unit uTestFindingHelper;

// Hilfsfunktionen fuer die AST-basierten Detektor-Tests.
// Parst einen Pascal-Quelltext und ruft alle Detektoren auf.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uParser2, uMethodd12, uSCAConsts,
  uLeakDetector2, uCodeSmells2, uSQLInjection, uHardcodedSecret,
  uFormatMismatch, uConcatToFormat, uUnusedUses,
  uNilDeref, uMissingFinally, uDivByZero, uDeadCode,
  uLongMethod, uLongParamList, uMagicNumbers, uDuplicateString,
  uHardcodedPath, uDebugOutput, uDeepNesting,
  uTodoComment, uEmptyMethod, uFieldLeak, uDuplicateBlock,
  uCyclomaticComplexity, uWithStatement,
  uGotoStatement, uTabulationCharacter, uTooLongLine, uTrailingWhitespace,
  uLowercaseKeyword, uNoSonarMarker, uEmptyArgumentList,
  uInlineAssembly, uTrailingCommaArgList, uDigitGrouping,
  uCommentedOutCode, uUnitLevelKeywordIndent, uRedundantBoolean,
  uEmptyInterface, uAssertMessage, uExplicitTObjectInheritance,
  uGroupedDeclaration, uEmptyBlock, uExceptOnException,
  uConsecutiveSection, uRedundantJump, uClassPerFile,
  uSuperfluousSemicolon, uEmptyFinallyBlock, uAssignedAndAssignedNil,
  uFreeAndNilHint, uAvoidOut, uEmptyVisibilitySection,
  uLegacyInitializationSection, uPublicField, uNestedTry,
  uCaseStatementSize, uEmptyFile, uTwiceInheritedCalls,
  uRedundantParentheses, uConsecutiveVisibility,
  uConstructorWithoutInherited, uDestructorWithoutInherited, uRedundantConditional,
  uIfElseBegin, uPointerName,
  uBeginEndRequired, uNestedRoutines,
  uFieldName, uTypeName,
  uInterfaceName, uMethodName,
  uReversedForRange, uSelfAssignment, uVirtualCallInCtor, uLengthUnderflow,
  uVisibilityCheck,
  uUnusedLocal, uUnusedParameter, uTautologicalExpr,
  uSqlDangerousStatement,
  uSynchronizeInDestructor, uLockWithoutTryFinally,
  uPerfHotspots, uConcurrencyExt, uRestHttpSecurity,
  uPublicMemberWithoutDoc, uNamingExt,
  uMissingRaise, uRoutineResultAssigned, uReRaiseException, uCastAndFree,
  uInstanceInvokedConstructor, uInheritedMethodEmpty, uNilComparison,
  uRaisingRawException, uDateFormatSettings, uUnicodeToAnsiCast,
  uCharToCharPointerCast, uIfThenShortCircuit,
  uExceptionTooGeneral, uRaiseOutsideExcept,
  uUseAfterFree, uAbstractNotImpl, uLeakInConstructor, uIntegerOverflow,
  uGodClass, uFreeWithoutNil, uMultipleExit, uLargeClass, uUnsortedUses,
  uMissingUnitHeader,
  uFloatEquality, uExceptInDestructor, uBooleanParam,
  uUnusedPrivateMethod, uCanBeClassMethod, uMissingOverride,
  uBoolAlwaysTrue, uConstantReturn, uHardcodedString,
  uUnpairedLock, uMoveSizeOfPointer, uWithMultipleTargets,
  uGetMemWithoutFreeMem, uSetLengthAppendInLoop, uPointerArithmeticOnString,
  uEmptyOnHandler, uStringFromPointer, uPointerSubtraction,
  uInsecureCryptoAlgorithm, uCommandInjection, uInsecureRandom,
  uDefaultCaseInCaseStatement, uAssertWithSideEffect, uConstStringParameter,
  uCompilerDirectiveScope, uBooleanPropertyNaming,
  uVariantTypeMisuse, uTObjectListWithoutOwnership, uAnonMethodCaptureLoopVar,
  uCognitiveComplexity, uThreadFreeOnTerminateWithRef, uPathTraversal,
  uAttributeIgnoreWithoutReason, uAttributeDuplicate,
  uAttributeCategoryWithoutString, uAttributeTestFixtureWithoutTests,
  uAttributeMisalignment,
  uUnusedRoutine, uUninitVar,
  uStaticAnalyzer2,
  uEngineApi,
  uLexer,            // gLexerIfdef*-Save/Restore in FindingsViaPipeline
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
    // Voller PRODUKTIONS-Pipeline-Weg (Audit 2026-07 Stufe 3): scannt den
    // Source ueber uEngineApi/TAnalysisSession.Run (ssSource) - inklusive
    // Profil-/Severity-Filter, Suppression, PathOverrides und Confidence-
    // Filter. Im Gegensatz zu FindingsOf/FindingsOfFile (rohe Detektor-
    // Aufrufe, KEINE Post-Filter) zeigt dieser Einstieg, was der User im
    // ausgelieferten Default WIRKLICH sieht. AMinConfidence steuert den
    // Confidence-Post-Filter (fcMedium = Auslieferungs-Default, filtert
    // fcLow-demotete Kinds; fcLow = Filter aus).
    class function FindingsViaPipeline(const Source: string;
      AMinConfidence: TFindingConfidence = fcMedium)
      : TObjectList<TLeakFinding>; static;
    class function Count(Findings: TObjectList<TLeakFinding>;
      Kind: TFindingKind): Integer; static;
    class function CountSev(Findings: TObjectList<TLeakFinding>;
      Kind: TFindingKind; Sev: TLeakSeverity): Integer; static;
    // Erster Befund eines Kinds (nil wenn keiner) - fuer Inhalt-Asserts
    // (LineNumber/Severity/Message) nach dem Count-Check.
    class function FirstOf(Findings: TObjectList<TLeakFinding>;
      Kind: TFindingKind): TLeakFinding; static;
    // 1-basierte Zeilennummer (als String, wie TLeakFinding.LineNumber) der
    // ERSTEN Zeile in Source, die AMarker enthaelt; '' wenn nicht gefunden.
    // Fuer selbstwartende Fundzeilen-Asserts: die Erwartung wird aus dem
    // Test-SRC abgeleitet statt hartkodiert (Audit_TestQualitaet P2) -
    // Layout-Aenderungen am SRC brechen den Assert nicht.
    class function LineOf(const Source, AMarker: string): string; static;
  end;

implementation

// Placeholder-Dateiname fuer die in-memory-Tests. NICHT auf 'test.pas',
// 'tests.pas' oder Pfad-Teile mit '/tests/' / '/test/' / '/spec/' /
// '/fixtures/' / '/utest' aendern - THardcodedSecretDetector.IsTestFilePath
// (uHardcodedSecret.pas) skipt diese Pfade als "ist ein Test-File, enthaelt
// nur Mock-Secrets". 'sample.pas' triggert keine der Heuristiken.
// 2026-06-19: Regression aus fa15ae4/f263c19 (Test-File-Skip eingefuehrt).
const
  SAMPLE_FILENAME = 'sample.pas';

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
      TLeakDetector2.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TEmptyExceptDetector2.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TSQLInjectionDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      THardcodedSecretDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TFormatMismatchDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TConcatToFormatDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TUnusedUsesDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TNilDerefDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TMissingFinallyDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TDivByZeroDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TDeadCodeDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TLongMethodDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TLongParamListDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TMagicNumberDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TDuplicateStringDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      THardcodedPathDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TDebugOutputDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TDeepNestingDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TCyclomaticComplexityDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TEmptyMethodDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TFieldLeakDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TSelfAssignmentDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TMissingRaiseDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TRoutineResultAssignedDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TReRaiseExceptionDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TCastAndFreeDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TInstanceInvokedConstructorDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TInheritedMethodEmptyDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TNilComparisonDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TRaisingRawExceptionDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TDateFormatSettingsDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TUnicodeToAnsiCastDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TCharToCharPointerCastDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TIfThenShortCircuitDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TExceptionTooGeneralDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TRaiseOutsideExceptDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TAbstractNotImplDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TLeakInConstructorDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TGodClassDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TFreeWithoutNilDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TMultipleExitDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TLargeClassDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TUnsortedUsesDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TExceptInDestructorDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TBooleanParamDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TCanBeClassMethodDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TMissingOverrideDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TConstantReturnDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TVirtualCallInCtorDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TVisibilityCheckDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TUnusedLocalDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TUnusedParameterDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TSqlDangerousStatementDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TInsecureCryptoAlgorithmDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TCommandInjectionDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TInsecureRandomDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TDefaultCaseInCaseStatementDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TAssertWithSideEffectDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TConstStringParameterDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TVariantTypeMisuseDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TTObjectListWithoutOwnershipDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TAnonMethodCaptureLoopVarDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TCognitiveComplexityDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TThreadFreeOnTerminateWithRefDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TPathTraversalDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TSynchronizeInDestructorDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      TNamingExtDetector.AnalyzeUnit(Root, SAMPLE_FILENAME, Result);
      // TTodoCommentDetector / TReversedForRangeDetector / TLengthUnderflowDetector /
      // TTautologicalExprDetector / TLockWithoutTryFinally / TPerfHotspots /
      // TConcurrencyExt / TRestHttpSecurity / TPublicMemberWithoutDoc
      // lesen die Datei selbst und brauchen eine echte Datei - hier nicht
      // aufgerufen. FindingsOfFile() benutzen.
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
      // Audit 2026-07 Stufe 3: ueber ParseFile statt ParseSource(Source) -
      // derselbe Lade-/Name-Pfad wie in Produktion (Encoding-Fallbacks +
      // Root.Name = Dateipfad; bei ParseSource blieb Root.Name leer und
      // ein kuenftiger Root.Name-Konsument liefe im Test anders).
      Root := Parser.ParseFile(TempPath);
      try
        TTodoCommentDetector.AnalyzeUnit(Root, TempPath, Result);
        TCompilerDirectiveScopeDetector.AnalyzeUnit(Root, TempPath, Result);
        TBooleanPropertyNamingDetector.AnalyzeUnit(Root, TempPath, Result);
        TAttributeIgnoreWithoutReasonDetector.AnalyzeUnit(Root, TempPath, Result);
        TAttributeDuplicateDetector.AnalyzeUnit(Root, TempPath, Result);
        TAttributeCategoryWithoutStringDetector.AnalyzeUnit(Root, TempPath, Result);
        TAttributeTestFixtureWithoutTestsDetector.AnalyzeUnit(Root, TempPath, Result);
        TAttributeMisalignmentDetector.AnalyzeUnit(Root, TempPath, Result);
        TEmptyMethodDetector.AnalyzeUnit(Root, TempPath, Result);
        TDuplicateBlockDetector.AnalyzeUnit(Root, TempPath, Result);
        TWithStatementDetector.AnalyzeUnit(Root, TempPath, Result);
        TGotoStatementDetector.AnalyzeUnit(Root, TempPath, Result);
        // Audit_TestQualitaet F2: UnusedLocal MUSS im File-Harness laufen -
        // sein LooksLikeRealLocalVar-Gate (Nested-Routine-FP-Schutz) liest
        // die Datei; im In-Memory-Harness (FindingsOf) ist Lines=nil und
        // das Gate unbedingt True -> Produktionspfad ungetestet.
        TUnusedLocalDetector.AnalyzeUnit(Root, TempPath, Result);
        TTabulationCharacterDetector.AnalyzeUnit(Root, TempPath, Result);
        TTooLongLineDetector.AnalyzeUnit(Root, TempPath, Result);
        TTrailingWhitespaceDetector.AnalyzeUnit(Root, TempPath, Result);
        TLowercaseKeywordDetector.AnalyzeUnit(Root, TempPath, Result);
        TNoSonarMarkerDetector.AnalyzeUnit(Root, TempPath, Result);
        TEmptyArgumentListDetector.AnalyzeUnit(Root, TempPath, Result);
        TInlineAssemblyDetector.AnalyzeUnit(Root, TempPath, Result);
        TTrailingCommaArgListDetector.AnalyzeUnit(Root, TempPath, Result);
        TDigitGroupingDetector.AnalyzeUnit(Root, TempPath, Result);
        TCommentedOutCodeDetector.AnalyzeUnit(Root, TempPath, Result);
        TUnitLevelKeywordIndentDetector.AnalyzeUnit(Root, TempPath, Result);
        TRedundantBooleanDetector.AnalyzeUnit(Root, TempPath, Result);
        TEmptyInterfaceDetector.AnalyzeUnit(Root, TempPath, Result);
        TAssertMessageDetector.AnalyzeUnit(Root, TempPath, Result);
        TExplicitTObjectInheritanceDetector.AnalyzeUnit(Root, TempPath, Result);
        TGroupedDeclarationDetector.AnalyzeUnit(Root, TempPath, Result);
        TEmptyBlockDetector.AnalyzeUnit(Root, TempPath, Result);
        TExceptOnExceptionDetector.AnalyzeUnit(Root, TempPath, Result);
        TConsecutiveSectionDetector.AnalyzeUnit(Root, TempPath, Result);
        TRedundantJumpDetector.AnalyzeUnit(Root, TempPath, Result);
        TClassPerFileDetector.AnalyzeUnit(Root, TempPath, Result);
        TSuperfluousSemicolonDetector.AnalyzeUnit(Root, TempPath, Result);
        TEmptyFinallyBlockDetector.AnalyzeUnit(Root, TempPath, Result);
        TAssignedAndAssignedNilDetector.AnalyzeUnit(Root, TempPath, Result);
        TFreeAndNilHintDetector.AnalyzeUnit(Root, TempPath, Result);
        TAvoidOutDetector.AnalyzeUnit(Root, TempPath, Result);
        TEmptyVisibilitySectionDetector.AnalyzeUnit(Root, TempPath, Result);
        TLegacyInitializationSectionDetector.AnalyzeUnit(Root, TempPath, Result);
        TPublicFieldDetector.AnalyzeUnit(Root, TempPath, Result);
        TNestedTryDetector.AnalyzeUnit(Root, TempPath, Result);
        TCaseStatementSizeDetector.AnalyzeUnit(Root, TempPath, Result);
        TEmptyFileDetector.AnalyzeUnit(Root, TempPath, Result);
        TTwiceInheritedCallsDetector.AnalyzeUnit(Root, TempPath, Result);
        TRedundantParenthesesDetector.AnalyzeUnit(Root, TempPath, Result);
        TConsecutiveVisibilityDetector.AnalyzeUnit(Root, TempPath, Result);
        TConstructorWithoutInheritedDetector.AnalyzeUnit(Root, TempPath, Result);
        TDestructorWithoutInheritedDetector.AnalyzeUnit(Root, TempPath, Result);
        TRedundantConditionalDetector.AnalyzeUnit(Root, TempPath, Result);
        TIfElseBeginDetector.AnalyzeUnit(Root, TempPath, Result);
        TPointerNameDetector.AnalyzeUnit(Root, TempPath, Result);
        TBeginEndRequiredDetector.AnalyzeUnit(Root, TempPath, Result);
        TNestedRoutinesDetector.AnalyzeUnit(Root, TempPath, Result);
        TFieldNameDetector.AnalyzeUnit(Root, TempPath, Result);
        TTypeNameDetector.AnalyzeUnit(Root, TempPath, Result);
        TInterfaceNameDetector.AnalyzeUnit(Root, TempPath, Result);
        TMethodNameDetector.AnalyzeUnit(Root, TempPath, Result);
        TReversedForRangeDetector.AnalyzeUnit(Root, TempPath, Result);
        TLengthUnderflowDetector.AnalyzeUnit(Root, TempPath, Result);
        TTautologicalExprDetector.AnalyzeUnit(Root, TempPath, Result);
        TLockWithoutTryFinallyDetector.AnalyzeUnit(Root, TempPath, Result);
        TPerfHotspotsDetector.AnalyzeUnit(Root, TempPath, Result);
        TConcurrencyExtDetector.AnalyzeUnit(Root, TempPath, Result);
        TRestHttpSecurityDetector.AnalyzeUnit(Root, TempPath, Result);
        TPublicMemberWithoutDocDetector.AnalyzeUnit(Root, TempPath, Result);
        TUseAfterFreeDetector.AnalyzeUnit(Root, TempPath, Result);
        TIntegerOverflowDetector.AnalyzeUnit(Root, TempPath, Result);
        TMissingUnitHeaderDetector.AnalyzeUnit(Root, TempPath, Result);
        TFloatEqualityDetector.AnalyzeUnit(Root, TempPath, Result);
        TUnusedPrivateMethodDetector.AnalyzeUnit(Root, TempPath, Result);
        TUnusedRoutineDetector.AnalyzeUnit(Root, TempPath, Result);
        TUninitVarDetector.AnalyzeUnit(Root, TempPath, Result);
        TBoolAlwaysTrueDetector.AnalyzeUnit(Root, TempPath, Result);
        THardcodedStringDetector.AnalyzeUnit(Root, TempPath, Result);
        TUnpairedLockDetector.AnalyzeUnit(Root, TempPath, Result);
        TMoveSizeOfPointerDetector.AnalyzeUnit(Root, TempPath, Result);
        TWithMultipleTargetsDetector.AnalyzeUnit(Root, TempPath, Result);
        TGetMemWithoutFreeMemDetector.AnalyzeUnit(Root, TempPath, Result);
        TSetLengthAppendInLoopDetector.AnalyzeUnit(Root, TempPath, Result);
        TPointerArithmeticOnStringDetector.AnalyzeUnit(Root, TempPath, Result);
        TEmptyOnHandlerDetector.AnalyzeUnit(Root, TempPath, Result);
        TStringFromPointerDetector.AnalyzeUnit(Root, TempPath, Result);
        TPointerSubtractionDetector.AnalyzeUnit(Root, TempPath, Result);
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

class function TFindingHelper.FindingsViaPipeline(const Source: string;
  AMinConfidence: TFindingConfidence): TObjectList<TLeakFinding>;
var
  Req      : TScanRequest;
  Ses      : TAnalysisSession;
  Res      : TScanResult;
  OldConf  : TFindingConfidence;
  OldKinds : TFindingKinds;
  OldSev   : TLeakSeverity;
  OldAuto  : Boolean;
  OldIfdefOn      : Boolean;
  OldIfdefDefines : TArray<string>;
  DefName  : string;
begin
  // Globalen Filter-State sichern: ApplyConfig (in Run) schreibt ihn aus dem
  // Request und laesst ihn stehen - andere Tests (uTestConfidenceFilter,
  // Raw-Harness) sollen den Prozess-Default unveraendert vorfinden.
  // Audit_TestQualitaet F1: ApplyConfig mutiert AUSSER den 3 Filter-Globals
  // auch AutoDiscoverCustomClasses + gLexerIfdefSkipEnabled/-Defines - alle
  // mitsichern. NICHT restaurierbar: TCustomRuleDetector.ClearRules (Rules-
  // Liste ist privat, kein Snapshot-API) - Fixtures mit Custom-Rules laden
  // ihre Rules ohnehin pro Test in Setup (uTestCustomRuleDetector).
  OldConf  := uSCAConsts.FindingMinConfidence;
  OldKinds := uSCAConsts.DetectorEnabledKinds;
  OldSev   := uSCAConsts.DetectorMinSeverity;
  OldAuto  := uSCAConsts.AutoDiscoverCustomClasses;
  OldIfdefOn := gLexerIfdefSkipEnabled;
  if Assigned(gLexerIfdefDefines) then
    OldIfdefDefines := gLexerIfdefDefines.ToStringArray
  else
    OldIfdefDefines := nil;
  try
    Req := TScanRequest.Init;         // Direkt-Modus: alle Detektoren, lsHint
    Req.Scope         := ssSource;
    Req.Source        := Source;
    Req.Path          := SAMPLE_FILENAME; // logischer Findings-Name (nicht test-artig!)
    Req.MinConfidence := AMinConfidence;
    Ses := TAnalysisSession.Create;
    try
      Res := Ses.Run(Req);
      try
        Result := Res.ReleaseFindings;
      finally
        Res.Free;
      end;
    finally
      Ses.Free;
    end;
  finally
    uSCAConsts.FindingMinConfidence := OldConf;
    uSCAConsts.DetectorEnabledKinds := OldKinds;
    uSCAConsts.DetectorMinSeverity  := OldSev;
    uSCAConsts.AutoDiscoverCustomClasses := OldAuto;
    LexerIfdefClear;
    for DefName in OldIfdefDefines do
      LexerIfdefAddDefine(DefName);
    gLexerIfdefSkipEnabled := OldIfdefOn;
  end;
end;

class function TFindingHelper.FirstOf(Findings: TObjectList<TLeakFinding>;
  Kind: TFindingKind): TLeakFinding;
var
  F: TLeakFinding;
begin
  Result := nil;
  for F in Findings do
    if F.Kind = Kind then Exit(F);
end;

class function TFindingHelper.LineOf(const Source, AMarker: string): string;
var
  SL : TStringList;
  i  : Integer;
begin
  Result := '';
  SL := TStringList.Create;
  try
    SL.Text := Source;
    for i := 0 to SL.Count - 1 do
      if Pos(AMarker, SL[i]) > 0 then
        Exit(IntToStr(i + 1));
  finally
    SL.Free;
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

end.
