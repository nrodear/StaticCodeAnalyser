program analyser.d12;

uses
  Vcl.Forms,
  uMainForm in 'sources\uMainForm.pas' {Form2},
  uStaticFiles in 'sources\uStaticFiles.pas',
  uSCAConsts in 'sources\uSCAConsts.pas',
  uMethodd12 in 'sources\uMethodd12.pas',
  uRegExMatches in 'sources\uRegExMatches.pas',
  uParser in 'sources\uParser.pas',
  uLeakDetector in 'sources\uLeakDetector.pas',
  uCodeSmells in 'sources\uCodeSmells.pas',
  uStaticAnalyzer in 'sources\uStaticAnalyzer.pas',
  uAstNode in 'sources\uAstNode.pas',
  uLexer in 'sources\uLexer.pas',
  uParser2 in 'sources\uParser2.pas',
  uLeakDetector2 in 'sources\uLeakDetector2.pas',
  uCodeSmells2 in 'sources\uCodeSmells2.pas',
  uSQLInjectionScore in 'sources\uSQLInjectionScore.pas',
  uSQLInjection in 'sources\uSQLInjection.pas',
  uHardcodedSecret in 'sources\uHardcodedSecret.pas',
  uFormatMismatch in 'sources\uFormatMismatch.pas',
  uUnusedUses in 'sources\uUnusedUses.pas',
  uNilDeref in 'sources\uNilDeref.pas',
  uMissingFinally in 'sources\uMissingFinally.pas',
  uDivByZero in 'sources\uDivByZero.pas',
  uDeadCode in 'sources\uDeadCode.pas',
  uSuppression in 'sources\uSuppression.pas',
  uExport in 'sources\uExport.pas',
  uLongMethod in 'sources\uLongMethod.pas',
  uLongParamList in 'sources\uLongParamList.pas',
  uMagicNumbers in 'sources\uMagicNumbers.pas',
  uDuplicateString in 'sources\uDuplicateString.pas',
  uHardcodedPath in 'sources\uHardcodedPath.pas',
  uDebugOutput in 'sources\uDebugOutput.pas',
  uDeepNesting in 'sources\uDeepNesting.pas',
  uTodoComment in 'sources\uTodoComment.pas',
  uEmptyMethod in 'sources\uEmptyMethod.pas',
  uFixHint in 'sources\uFixHint.pas',
  uIgnoreList in 'sources\uIgnoreList.pas',
  uFieldLeak in 'sources\uFieldLeak.pas',
  uDuplicateBlock in 'sources\uDuplicateBlock.pas',
  uCollectValues in 'sources\uCollectValues.pas',
  uStaticAnalyzer2 in 'sources\uStaticAnalyzer2.pas',
  uVcsChanges in 'sources\uVcsChanges.pas',
  uRepoSettings in 'sources\uRepoSettings.pas',
  MeineUnit in 'resources\MeineUnit.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm2, Form2);
  Application.Run;

end.
