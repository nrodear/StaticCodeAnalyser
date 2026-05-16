program TestProject;

// CLI-Lauf: Console-Subsystem (DUnitX-Console-Logger braucht stdout).
// TestInsight-Lauf: GUI-Subsystem (sonst flackert beim Start ein cmd-Fenster
// auf, da Windows fuer Console-Apps die ohne Parent-Console starten eine
// neue Console allokiert). Termination wird im TestInsight-Pfad ueber
// Halt(0) erzwungen (siehe begin-Block unten).
{$IFNDEF TESTINSIGHT}
{$APPTYPE CONSOLE}
{$ENDIF}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
{$IFDEF TESTINSIGHT}
  TestInsight.DUnitX,
{$ELSE}
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
{$ENDIF }
  DUnitX.TestFramework,
  uTestSrcBuilder       in 'uTestSrcBuilder.pas',
  uTestTAstNode         in 'uTestTAstNode.pas',
  uTestDfmLexer         in 'uTestDfmLexer.pas',
  uTestDfmParser        in 'uTestDfmParser.pas',
  uTestDfmBinaryReader  in 'uTestDfmBinaryReader.pas',
  uTestDfmPropValue     in 'uTestDfmPropValue.pas',
  uTestDfmDefaultName   in 'uTestDfmDefaultName.pas',
  uTestDfmHardcodedCaption in 'uTestDfmHardcodedCaption.pas',
  uTestDfmHardcodedDbCreds in 'uTestDfmHardcodedDbCreds.pas',
  uTestDfmDuplicateBinding in 'uTestDfmDuplicateBinding.pas',
  uTestDfmDeadEvent     in 'uTestDfmDeadEvent.pas',
  uTestDfmOrphanHandler in 'uTestDfmOrphanHandler.pas',
  uTestDfmEmptyBoundEvent in 'uTestDfmEmptyBoundEvent.pas',
  uTestDfmSchemaMismatch in 'uTestDfmSchemaMismatch.pas',
  uTestDfmCircularDataSource in 'uTestDfmCircularDataSource.pas',
  uTestDfmSqlFromUserInput in 'uTestDfmSqlFromUserInput.pas',
  uTestDfmRequiredField in 'uTestDfmRequiredField.pas',
  uTestDfmFieldTypeMismatch in 'uTestDfmFieldTypeMismatch.pas',
  uTestDfmTabOrderConflict in 'uTestDfmTabOrderConflict.pas',
  uTestDfmForbiddenClass in 'uTestDfmForbiddenClass.pas',
  uTestDfmDbInUiForm in 'uTestDfmDbInUiForm.pas',
  uTestDfmCrossFormCoupling in 'uTestDfmCrossFormCoupling.pas',
  uTestDfmLayerViolation in 'uTestDfmLayerViolation.pas',
  uTestDfmGodHandler in 'uTestDfmGodHandler.pas',
  uTestDfmActionMismatch in 'uTestDfmActionMismatch.pas',
  uTestFindingHelper    in 'uTestFindingHelper.pas',
  uTestLeakDetector     in 'uTestLeakDetector.pas',
  uTestSQLInjection     in 'uTestSQLInjection.pas',
  uTestHardcodedSecret  in 'uTestHardcodedSecret.pas',
  uTestHardcodedPath    in 'uTestHardcodedPath.pas',
  uTestFormatMismatch   in 'uTestFormatMismatch.pas',
  uTestUnusedUses       in 'uTestUnusedUses.pas',
  uTestEmptyExcept      in 'uTestEmptyExcept.pas',
  uTestEmptyMethod      in 'uTestEmptyMethod.pas',
  uTestDuplicate        in 'uTestDuplicate.pas',
  uTestDebugOutput      in 'uTestDebugOutput.pas',
  uTestTodoComment      in 'uTestTodoComment.pas',
  uTestCodeMetrics      in 'uTestCodeMetrics.pas',
  uTestSafetyChecks     in 'uTestSafetyChecks.pas',
  uTestComboChecks      in 'uTestComboChecks.pas',
  uTestParserRobustness in 'uTestParserRobustness.pas',
  uTestPerformance      in 'uTestPerformance.pas',
  uTestRuleCatalog      in 'uTestRuleCatalog.pas',
  uTestExportSARIF      in 'uTestExportSARIF.pas',
  uTestExportSonarGeneric in 'uTestExportSonarGeneric.pas',
  uTestSonarConfig      in 'uTestSonarConfig.pas',
  uTestYamlSubsetParser in 'uTestYamlSubsetParser.pas',
  uTestCustomRuleDetector in 'uTestCustomRuleDetector.pas',
  uTestConcatToFormat   in 'uTestConcatToFormat.pas',
  uTestWithStatement    in 'uTestWithStatement.pas',
  uTestGotoStatement    in 'uTestGotoStatement.pas',
  uTestTabulationCharacter in 'uTestTabulationCharacter.pas',
  uTestTooLongLine      in 'uTestTooLongLine.pas',
  uTestTrailingWhitespace in 'uTestTrailingWhitespace.pas',
  uTestReversedForRange in 'uTestReversedForRange.pas',
  uTestSelfAssignment   in 'uTestSelfAssignment.pas',
  uTestVirtualCallInCtor in 'uTestVirtualCallInCtor.pas',
  uTestLengthUnderflow  in 'uTestLengthUnderflow.pas',
  uTestVisibilityCheck  in 'uTestVisibilityCheck.pas',
  uTestCustomClassDiscovery in 'uTestCustomClassDiscovery.pas',
  uTestSQLInjectionScore in 'uTestSQLInjectionScore.pas',
  uTestSymbolReferenceIndex in 'uTestSymbolReferenceIndex.pas',
  uTestUnusedLocal in 'uTestUnusedLocal.pas',
  uTestUnusedParameter in 'uTestUnusedParameter.pas',
  uTestTautologicalExpr in 'uTestTautologicalExpr.pas',
  uTestDfmMasterDetailUnlinked in 'uTestDfmMasterDetailUnlinked.pas',
  uTestDfmDataModuleSplitHint in 'uTestDfmDataModuleSplitHint.pas',
  uTestSqlDangerousStatement in 'uTestSqlDangerousStatement.pas',
  uTestLowercaseKeyword in 'uTestLowercaseKeyword.pas',
  uTestNoSonarMarker in 'uTestNoSonarMarker.pas',
  uTestEmptyArgumentList in 'uTestEmptyArgumentList.pas',
  uTestInlineAssembly in 'uTestInlineAssembly.pas',
  uTestTrailingCommaArgList in 'uTestTrailingCommaArgList.pas',
  uTestDigitGrouping in 'uTestDigitGrouping.pas',
  uTestCommentedOutCode in 'uTestCommentedOutCode.pas',
  uTestUnitLevelKeywordIndent in 'uTestUnitLevelKeywordIndent.pas',
  uTestRedundantBoolean in 'uTestRedundantBoolean.pas',
  uTestEmptyInterface in 'uTestEmptyInterface.pas',
  uTestAssertMessage in 'uTestAssertMessage.pas',
  uTestExplicitTObjectInheritance in 'uTestExplicitTObjectInheritance.pas',
  uTestGroupedDeclaration in 'uTestGroupedDeclaration.pas',
  uTestEmptyBlock in 'uTestEmptyBlock.pas',
  uTestExceptOnException in 'uTestExceptOnException.pas',
  uTestConsecutiveSection in 'uTestConsecutiveSection.pas',
  uTestRedundantJump in 'uTestRedundantJump.pas',
  uTestClassPerFile in 'uTestClassPerFile.pas',
  uTestSuperfluousSemicolon in 'uTestSuperfluousSemicolon.pas',
  uTestEmptyFinallyBlock in 'uTestEmptyFinallyBlock.pas',
  uTestAssignedAndAssignedNil in 'uTestAssignedAndAssignedNil.pas',
  uTestFreeAndNilHint in 'uTestFreeAndNilHint.pas',
  uTestAvoidOut in 'uTestAvoidOut.pas',
  uTestEmptyVisibilitySection in 'uTestEmptyVisibilitySection.pas',
  uTestLegacyInitializationSection in 'uTestLegacyInitializationSection.pas',
  uTestPublicField in 'uTestPublicField.pas',
  uTestNestedTry in 'uTestNestedTry.pas',
  uTestCaseStatementSize in 'uTestCaseStatementSize.pas',
  uTestEmptyFile in 'uTestEmptyFile.pas',
  uTestTwiceInheritedCalls in 'uTestTwiceInheritedCalls.pas',
  uTestRedundantParentheses in 'uTestRedundantParentheses.pas',
  uTestConsecutiveVisibility in 'uTestConsecutiveVisibility.pas',
  uTestConstructorWithoutInherited in 'uTestConstructorWithoutInherited.pas',
  uTestDestructorWithoutInherited in 'uTestDestructorWithoutInherited.pas',
  uTestRedundantConditional in 'uTestRedundantConditional.pas',
  uTestIfElseBegin in 'uTestIfElseBegin.pas',
  uTestPointerName in 'uTestPointerName.pas',
  uTestBeginEndRequired in 'uTestBeginEndRequired.pas',
  uTestNestedRoutines in 'uTestNestedRoutines.pas',
  uTestFieldName in 'uTestFieldName.pas',
  uTestTypeName in 'uTestTypeName.pas';

{ keep comment here to protect the following conditional from being removed by the IDE when adding a unit }
{$IFNDEF TESTINSIGHT}

var
  runner: ITestRunner;
  results: IRunResults;
  logger: ITestLogger;
  nunitLogger: ITestLogger;
{$ENDIF}

begin
{$IFDEF TESTINSIGHT}
  TestInsight.DUnitX.RunRegisteredTests;
  // Expliziter Exit als Sicherheitsnetz: falls der TestInsight-Client einen
  // Background-Thread / Hidden-Window offen laesst (Embarcadero-Forum-Issue
  // mehrfach gesehen), wartet die RTL beim impliziten `end.`-Shutdown auf
  // dessen Cleanup. Halt(0) umgeht Finalization-Sections und beendet den
  // Prozess sofort - Testergebnisse sind zu diesem Zeitpunkt schon ueber
  // den IPC-Kanal an die IDE gesendet.
  Halt(0);
{$ELSE}
  try
    // Check command line options, will exit if invalid
    TDUnitX.CheckCommandLine;
    // Create the test runner
    runner := TDUnitX.CreateRunner;
    // Tell the runner to use RTTI to find Fixtures
    runner.UseRTTI := True;
    // When true, Assertions must be made during tests;
    runner.FailsOnNoAsserts := False;

    // tell the runner how we will log things
    // Log to the console window if desired
    if TDUnitX.Options.ConsoleMode <> TDunitXConsoleMode.Off then
    begin
      logger := TDUnitXConsoleLogger.Create
        (TDUnitX.Options.ConsoleMode = TDunitXConsoleMode.Quiet);
      runner.AddLogger(logger);
    end;
    // Generate an NUnit compatible XML File
    nunitLogger := TDUnitXXMLNUnitFileLogger.Create
      (TDUnitX.Options.XMLOutputFile);
    runner.AddLogger(nunitLogger);

    // Run tests
    results := runner.Execute;
    if not results.AllPassed then
      System.ExitCode := EXIT_ERRORS;

{$IFNDEF CI}
    // We don't want this happening when running under CI.
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      System.Write('Done.. press <Enter> key to quit.');
      System.Readln;
    end;
{$ENDIF}
  except
    on E: Exception do
      System.Writeln(E.ClassName, ': ', E.Message);
  end;
{$ENDIF}

end.
