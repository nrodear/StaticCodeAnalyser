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
  uUnusedRoutine, uUninitVar,
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
      TLeakDetector2.AnalyzeUnit(Root, 'sample.pas', Result);
      TEmptyExceptDetector2.AnalyzeUnit(Root, 'sample.pas', Result);
      TSQLInjectionDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      THardcodedSecretDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TFormatMismatchDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TConcatToFormatDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TUnusedUsesDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TNilDerefDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TMissingFinallyDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TDivByZeroDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TDeadCodeDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TLongMethodDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TLongParamListDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TMagicNumberDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TDuplicateStringDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      THardcodedPathDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TDebugOutputDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TDeepNestingDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TCyclomaticComplexityDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TEmptyMethodDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TFieldLeakDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TSelfAssignmentDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TMissingRaiseDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TRoutineResultAssignedDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TReRaiseExceptionDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TCastAndFreeDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TInstanceInvokedConstructorDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TInheritedMethodEmptyDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TNilComparisonDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TRaisingRawExceptionDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TDateFormatSettingsDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TUnicodeToAnsiCastDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TCharToCharPointerCastDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TIfThenShortCircuitDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TExceptionTooGeneralDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TRaiseOutsideExceptDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TAbstractNotImplDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TLeakInConstructorDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TGodClassDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TFreeWithoutNilDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TMultipleExitDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TLargeClassDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TUnsortedUsesDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TExceptInDestructorDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TBooleanParamDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TCanBeClassMethodDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TMissingOverrideDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TConstantReturnDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TVirtualCallInCtorDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TVisibilityCheckDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TUnusedLocalDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TUnusedParameterDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TSqlDangerousStatementDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TInsecureCryptoAlgorithmDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TCommandInjectionDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TInsecureRandomDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TDefaultCaseInCaseStatementDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TAssertWithSideEffectDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TConstStringParameterDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TVariantTypeMisuseDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TTObjectListWithoutOwnershipDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TAnonMethodCaptureLoopVarDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TSynchronizeInDestructorDetector.AnalyzeUnit(Root, 'sample.pas', Result);
      TNamingExtDetector.AnalyzeUnit(Root, 'sample.pas', Result);
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
      Root := Parser.ParseSource(Source);
      try
        TTodoCommentDetector.AnalyzeUnit(Root, TempPath, Result);
        TCompilerDirectiveScopeDetector.AnalyzeUnit(Root, TempPath, Result);
        TBooleanPropertyNamingDetector.AnalyzeUnit(Root, TempPath, Result);
        TEmptyMethodDetector.AnalyzeUnit(Root, TempPath, Result);
        TDuplicateBlockDetector.AnalyzeUnit(Root, TempPath, Result);
        TWithStatementDetector.AnalyzeUnit(Root, TempPath, Result);
        TGotoStatementDetector.AnalyzeUnit(Root, TempPath, Result);
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
