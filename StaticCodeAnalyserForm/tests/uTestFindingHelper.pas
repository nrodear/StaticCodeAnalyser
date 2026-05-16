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
  uReversedForRange, uSelfAssignment, uVirtualCallInCtor, uLengthUnderflow,
  uVisibilityCheck,
  uUnusedLocal, uUnusedParameter, uTautologicalExpr,
  uSqlDangerousStatement,
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
      TConcatToFormatDetector.AnalyzeUnit(Root, 'test.pas', Result);
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
      TCyclomaticComplexityDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TEmptyMethodDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TFieldLeakDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TSelfAssignmentDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TVirtualCallInCtorDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TVisibilityCheckDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TUnusedLocalDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TUnusedParameterDetector.AnalyzeUnit(Root, 'test.pas', Result);
      TSqlDangerousStatementDetector.AnalyzeUnit(Root, 'test.pas', Result);
      // TTodoCommentDetector / TReversedForRangeDetector / TLengthUnderflowDetector /
      // TTautologicalExprDetector
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
        TReversedForRangeDetector.AnalyzeUnit(Root, TempPath, Result);
        TLengthUnderflowDetector.AnalyzeUnit(Root, TempPath, Result);
        TTautologicalExprDetector.AnalyzeUnit(Root, TempPath, Result);
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
