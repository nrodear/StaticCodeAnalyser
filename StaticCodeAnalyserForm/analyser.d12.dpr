program analyser.d12;

uses
  Vcl.Forms,
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
  // ---- Infrastructure ----
  uExport in 'sources\Infrastructure\uExport.pas',
  uExportHtml in 'sources\Infrastructure\uExportHtml.pas',
  uIgnoreList in 'sources\Infrastructure\uIgnoreList.pas',
  uRepoSettings in 'sources\Infrastructure\uRepoSettings.pas',
  uStaticAnalyzer2 in 'sources\Infrastructure\uStaticAnalyzer2.pas',
  uStaticFiles in 'sources\Infrastructure\uStaticFiles.pas',
  uSuppression in 'sources\Infrastructure\uSuppression.pas',
  uVcsChanges in 'sources\Infrastructure\uVcsChanges.pas',
  // ---- Output ----
  uClaudePrompt in 'sources\Output\uClaudePrompt.pas',
  uFixHint in 'sources\Output\uFixHint.pas',
  // ---- Common ----
  uCollectValues in 'sources\Common\uCollectValues.pas',
  uDetectorUtils in 'sources\Common\uDetectorUtils.pas',
  uMethodd12 in 'sources\Common\uMethodd12.pas',
  uRecentPaths in 'sources\Common\uRecentPaths.pas',
  uRegExMatches in 'sources\Common\uRegExMatches.pas',
  uSCAConsts in 'sources\Common\uSCAConsts.pas',
  // ---- Detectors ----
  uCodeSmells2 in 'sources\Detectors\uCodeSmells2.pas',
  uDeadCode in 'sources\Detectors\uDeadCode.pas',
  uDebugOutput in 'sources\Detectors\uDebugOutput.pas',
  uDeepNesting in 'sources\Detectors\uDeepNesting.pas',
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
  uCustomClassDiscovery in 'sources\Detectors\uCustomClassDiscovery.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm2, Form2);
  Application.CreateForm(TForm2, Form2);
  Application.Run;

end.
