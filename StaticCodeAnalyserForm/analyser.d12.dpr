program analyser.d12;

{$APPTYPE CONSOLE}
// CONSOLE-AppType: ermoeglicht stdout/stderr-IO und korrekte Exit-Codes.
// Die VCL-Form startet trotzdem - im GUI-Mode ist das Console-Window nur
// ein zusaetzliches Fenster (nicht stoerend bei Plugin-Builds).
// Im CLI-Mode (siehe TConsoleRunner.RunFromCmdLine in main-Block unten)
// kein Application.Run -> kein Form-Spawn -> reine CLI-Output.

uses
  Vcl.Forms,
  System.SysUtils,
  MeineUnit in 'resources\MeineUnit.pas',
  MainController in 'sources\MainController.pas',
  uAnalyserPalette in 'sources\UI\uAnalyserPalette.pas',
  uAnalyserTheme in 'sources\UI\uAnalyserTheme.pas',
  uAnalyserTypes in 'sources\UI\uAnalyserTypes.pas',
  uLocalization in 'sources\UI\uLocalization.pas',
  uFindingGridRenderer in 'sources\UI\uFindingGridRenderer.pas',
  uMainForm in 'sources\UI\uMainForm.pas' {Form2},
  // ---- Parsing ----
  uAstNode in 'sources\Parsing\uAstNode.pas',
  uLexer in 'sources\Parsing\uLexer.pas',
  uParser2 in 'sources\Parsing\uParser2.pas',
  uComponentGraph in 'sources\Parsing\uComponentGraph.pas',
  uDfmLexer in 'sources\Parsing\uDfmLexer.pas',
  uDfmParser in 'sources\Parsing\uDfmParser.pas',
  // ---- Infrastructure ----
  uExport in 'sources\Infrastructure\uExport.pas',
  uExportHtml in 'sources\Infrastructure\uExportHtml.pas',
  uIgnoreList in 'sources\Infrastructure\uIgnoreList.pas',
  uRepoSettings in 'sources\Infrastructure\uRepoSettings.pas',
  uStaticAnalyzer2 in 'sources\Infrastructure\uStaticAnalyzer2.pas',
  uStaticFiles in 'sources\Infrastructure\uStaticFiles.pas',
  uSuppression in 'sources\Infrastructure\uSuppression.pas',
  uVcsChanges in 'sources\Infrastructure\uVcsChanges.pas',
  uDfmAnalysisRunner in 'sources\Infrastructure\uDfmAnalysisRunner.pas',
  uFormBinder in 'sources\Infrastructure\uFormBinder.pas',
  uDfmDbFieldAnalysis in 'sources\Infrastructure\uDfmDbFieldAnalysis.pas',
  uDfmRepoIndex in 'sources\Infrastructure\uDfmRepoIndex.pas',
  // ---- Output ----
  uClaudePrompt in 'sources\Output\uClaudePrompt.pas',
  uExportSARIF in 'sources\Output\uExportSARIF.pas',
  uFixHint in 'sources\Output\uFixHint.pas',
  // ---- Console (CLI-Mode) ----
  uConsoleRunner in 'sources\Console\uConsoleRunner.pas',
  // ---- Common ----
  uCollectValues in 'sources\Common\uCollectValues.pas',
  uDetectorUtils in 'sources\Common\uDetectorUtils.pas',
  uMethodd12 in 'sources\Common\uMethodd12.pas',
  uRecentPaths in 'sources\Common\uRecentPaths.pas',
  uRegExMatches in 'sources\Common\uRegExMatches.pas',
  uRuleCatalog in 'sources\Common\uRuleCatalog.pas',
  uSCAConsts in 'sources\Common\uSCAConsts.pas',
  uYamlSubsetParser in 'sources\Common\uYamlSubsetParser.pas',
  // ---- Detectors ----
  uCodeSmells2 in 'sources\Detectors\uCodeSmells2.pas',
  uDeadCode in 'sources\Detectors\uDeadCode.pas',
  uDebugOutput in 'sources\Detectors\uDebugOutput.pas',
  uDeepNesting in 'sources\Detectors\uDeepNesting.pas',
  uCustomRuleDetector in 'sources\Detectors\uCustomRuleDetector.pas',
  uCyclomaticComplexity in 'sources\Detectors\uCyclomaticComplexity.pas',
  uDivByZero in 'sources\Detectors\uDivByZero.pas',
  uDuplicateBlock in 'sources\Detectors\uDuplicateBlock.pas',
  uDuplicateString in 'sources\Detectors\uDuplicateString.pas',
  uEmptyMethod in 'sources\Detectors\uEmptyMethod.pas',
  uFieldLeak in 'sources\Detectors\uFieldLeak.pas',
  uFormatMismatch in 'sources\Detectors\uFormatMismatch.pas',
  uHardcodedPath in 'sources\Detectors\uHardcodedPath.pas',
  uHardcodedSecret in 'sources\Detectors\uHardcodedSecret.pas',
  uLeakDetector2 in 'sources\Detectors\uLeakDetector2.pas',
  uLongMethod in 'sources\Detectors\uLongMethod.pas',
  uLongParamList in 'sources\Detectors\uLongParamList.pas',
  uMagicNumbers in 'sources\Detectors\uMagicNumbers.pas',
  uMissingFinally in 'sources\Detectors\uMissingFinally.pas',
  uNilDeref in 'sources\Detectors\uNilDeref.pas',
  uSQLInjection in 'sources\Detectors\uSQLInjection.pas',
  uSQLInjectionScore in 'sources\Detectors\uSQLInjectionScore.pas',
  uTodoComment in 'sources\Detectors\uTodoComment.pas',
  uUnusedUses in 'sources\Detectors\uUnusedUses.pas',
  uCustomClassDiscovery in 'sources\Detectors\uCustomClassDiscovery.pas',
  uDfmDefaultName in 'sources\Detectors\uDfmDefaultName.pas',
  uDfmHardcodedCaption in 'sources\Detectors\uDfmHardcodedCaption.pas',
  uDfmHardcodedDbCreds in 'sources\Detectors\uDfmHardcodedDbCreds.pas',
  uDfmDuplicateBinding in 'sources\Detectors\uDfmDuplicateBinding.pas',
  uDfmDeadEvent in 'sources\Detectors\uDfmDeadEvent.pas',
  uDfmOrphanHandler in 'sources\Detectors\uDfmOrphanHandler.pas',
  uDfmEmptyBoundEvent in 'sources\Detectors\uDfmEmptyBoundEvent.pas',
  uDfmSchemaMismatch in 'sources\Detectors\uDfmSchemaMismatch.pas',
  uDfmCircularDataSource in 'sources\Detectors\uDfmCircularDataSource.pas',
  uDfmSqlFromUserInput in 'sources\Detectors\uDfmSqlFromUserInput.pas',
  uDfmRequiredField in 'sources\Detectors\uDfmRequiredField.pas',
  uDfmFieldTypeMismatch in 'sources\Detectors\uDfmFieldTypeMismatch.pas',
  uDfmTabOrderConflict in 'sources\Detectors\uDfmTabOrderConflict.pas',
  uDfmForbiddenClass in 'sources\Detectors\uDfmForbiddenClass.pas',
  uDfmDbInUiForm in 'sources\Detectors\uDfmDbInUiForm.pas',
  uDfmCrossFormCoupling in 'sources\Detectors\uDfmCrossFormCoupling.pas',
  uDfmLayerViolation in 'sources\Detectors\uDfmLayerViolation.pas',
  uDfmGodHandler in 'sources\Detectors\uDfmGodHandler.pas',
  uDfmActionMismatch in 'sources\Detectors\uDfmActionMismatch.pas';

{$R *.res}

// Erkennung CLI- vs GUI-Mode: jeder Argument der mit '-' oder '/' anfaengt
// (typische Switch-Praefixe) -> CLI. Sonst -> GUI starten.
function IsCliMode: Boolean;
var
  i  : Integer;
  A  : string;
begin
  Result := False;
  for i := 1 to ParamCount do
  begin
    A := ParamStr(i);
    if (A <> '') and ((A[1] = '-') or (A[1] = '/')) then
      Exit(True);
  end;
end;

begin
  if IsCliMode then
  begin
    // Headless-Pfad - keine VCL-Form, exit code via Halt.
    try
      Halt(uConsoleRunner.TConsoleRunner.RunFromCmdLine);
    except
      on E: Exception do
      begin
        WriteLn(ErrOutput, 'Fatal: ', E.ClassName, ': ', E.Message);
        Halt(99);
      end;
    end;
  end
  else
  begin
    Application.Initialize;
    Application.MainFormOnTaskbar := True;
    Application.CreateForm(TForm2, Form2);
    Application.Run;
  end;
end.
