program analyser.d12;

uses
  Vcl.Forms,
  MeineUnit in 'resources\MeineUnit.pas',
  MainController in 'sources\MainController.pas',
  uAnalyserPalette in 'sources\uAnalyserPalette.pas',
  uAnalyserTheme in 'sources\uAnalyserTheme.pas',
  uAnalyserTypes in 'sources\uAnalyserTypes.pas',
  uAstNode in 'sources\uAstNode.pas',
  uClaudePrompt in 'sources\uClaudePrompt.pas',
  uCodeSmells in 'sources\uCodeSmells.pas',
  uCodeSmells2 in 'sources\uCodeSmells2.pas',
  uCollectValues in 'sources\uCollectValues.pas',
  uDeadCode in 'sources\uDeadCode.pas',
  uDebugOutput in 'sources\uDebugOutput.pas',
  uDeepNesting in 'sources\uDeepNesting.pas',
  uDetectorUtils in 'sources\uDetectorUtils.pas',
  uDivByZero in 'sources\uDivByZero.pas',
  uDuplicateBlock in 'sources\uDuplicateBlock.pas',
  uDuplicateString in 'sources\uDuplicateString.pas',
  uEmptyMethod in 'sources\uEmptyMethod.pas',
  uExport in 'sources\uExport.pas',
  uFieldLeak in 'sources\uFieldLeak.pas',
  uFixHint in 'sources\uFixHint.pas',
  uFormatMismatch in 'sources\uFormatMismatch.pas',
  uHardcodedPath in 'sources\uHardcodedPath.pas',
  uHardcodedSecret in 'sources\uHardcodedSecret.pas',
  uIgnoreList in 'sources\uIgnoreList.pas',
  uLeakDetector in 'sources\uLeakDetector.pas',
  uLeakDetector2 in 'sources\uLeakDetector2.pas',
  uLexer in 'sources\uLexer.pas',
  uLocalization in 'sources\uLocalization.pas',
  uLongMethod in 'sources\uLongMethod.pas',
  uLongParamList in 'sources\uLongParamList.pas',
  uMagicNumbers in 'sources\uMagicNumbers.pas',
  uMainForm in 'sources\uMainForm.pas' {Form2},
  uMethodd12 in 'sources\uMethodd12.pas',
  uMissingFinally in 'sources\uMissingFinally.pas',
  uNilDeref in 'sources\uNilDeref.pas',
  uParser in 'sources\uParser.pas',
  uParser2 in 'sources\uParser2.pas',
  uRegExMatches in 'sources\uRegExMatches.pas',
  uRepoSettings in 'sources\uRepoSettings.pas',
  uSCAConsts in 'sources\uSCAConsts.pas',
  uSQLInjection in 'sources\uSQLInjection.pas',
  uSQLInjectionScore in 'sources\uSQLInjectionScore.pas',
  uStaticAnalyzer in 'sources\uStaticAnalyzer.pas',
  uStaticAnalyzer2 in 'sources\uStaticAnalyzer2.pas',
  uStaticFiles in 'sources\uStaticFiles.pas',
  uSuppression in 'sources\uSuppression.pas',
  uTodoComment in 'sources\uTodoComment.pas',
  uUnusedUses in 'sources\uUnusedUses.pas',
  uVcsChanges in 'sources\uVcsChanges.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm2, Form2);
  Application.CreateForm(TForm2, Form2);
  Application.Run;

end.
