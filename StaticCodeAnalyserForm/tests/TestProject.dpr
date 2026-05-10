program TestProject;

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
  uTestYamlSubsetParser in 'uTestYamlSubsetParser.pas',
  uTestCustomRuleDetector in 'uTestCustomRuleDetector.pas';

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
