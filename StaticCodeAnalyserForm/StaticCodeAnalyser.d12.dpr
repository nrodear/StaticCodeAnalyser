program StaticCodeAnalyser.d12;

// GUI-AppType (kein {$APPTYPE CONSOLE}): Windows allokiert KEINE Konsole
// beim Start. Damit kein schwarzes cmd-Fenster beim Doppelklick.
//
// Im CLI-Mode haengen wir uns ueber AttachConsole(ATTACH_PARENT_PROCESS)
// an die schon offene Konsole des Aufrufers an (typisch: cmd.exe oder ein
// CI-Runner). stdout/stderr werden danach auf CONOUT$ umgebogen, damit
// WriteLn / Output / ErrOutput am erwarteten Ziel landen.
//
// Bekannter Schoenheitsfehler: der cmd-Prompt kommt sofort zurueck bevor
// die letzte Output-Zeile sichtbar ist (Windows-Quirk fuer GUI-Subsystem-
// Programme die nachtraeglich AttachConsole rufen). Wer es absolut blockend
// braucht, ruft 'start /wait analyser.exe ...' oder pipt nach 'more'.
// CI-Runner (PowerShell, GH Actions) sehen das nicht - die loggen synchron.

uses
  Winapi.Windows,
  Vcl.Forms,
  System.SysUtils,
  MeineUnit in 'resources\MeineUnit.pas',
  MainController in 'sources\MainController.pas',
  uAnalyserPalette in 'sources\UI\uAnalyserPalette.pas',
  uAnalyserTheme in 'sources\UI\uAnalyserTheme.pas',
  uAnalyserTypes in 'sources\UI\uAnalyserTypes.pas',
  uLocalization in 'sources\UI\uLocalization.pas',
  uFindingGridRenderer in 'sources\UI\uFindingGridRenderer.pas',
  uFindingFilter in 'sources\UI\uFindingFilter.pas',
  uMainForm in 'sources\UI\uMainForm.pas' {Form2},
  uDfmTextViewer in 'sources\UI\uDfmTextViewer.pas',
  uAstNode in 'sources\Parsing\uAstNode.pas',
  uLexer in 'sources\Parsing\uLexer.pas',
  uParser2 in 'sources\Parsing\uParser2.pas',
  uComponentGraph in 'sources\Parsing\uComponentGraph.pas',
  uDfmLexer in 'sources\Parsing\uDfmLexer.pas',
  uDfmParser in 'sources\Parsing\uDfmParser.pas',
  uDfmBinaryReader in 'sources\Parsing\uDfmBinaryReader.pas',
  uClaudePrompt in 'sources\Output\uClaudePrompt.pas',
  uExportSARIF in 'sources\Output\uExportSARIF.pas',
  uExportSonarGeneric in 'sources\Output\uExportSonarGeneric.pas',
  uSonarPush in 'sources\Output\uSonarPush.pas',
  uFixHint in 'sources\Output\uFixHint.pas',
  uConsoleRunner in 'sources\Console\uConsoleRunner.pas',
  uCollectValues in 'sources\Common\uCollectValues.pas',
  uDetectorUtils in 'sources\Common\uDetectorUtils.pas',
  uMethodd12 in 'sources\Common\uMethodd12.pas',
  uRecentPaths in 'sources\Common\uRecentPaths.pas',
  uRegExMatches in 'sources\Common\uRegExMatches.pas',
  uRuleCatalog in 'sources\Common\uRuleCatalog.pas',
  uSCAConsts in 'sources\Common\uSCAConsts.pas',
  uYamlSubsetParser in 'sources\Common\uYamlSubsetParser.pas',
  uQuickFix in 'sources\Common\uQuickFix.pas',
  uCustomerForm in 'resources\uCustomerForm.pas' {CustomerForm},
  uOrderForm in 'resources\uOrderForm.pas' {OrderForm},
  uIDEStatsTiles in 'sources\UI\uIDEStatsTiles.pas',
  uIDEHelpPanel in 'sources\UI\uIDEHelpPanel.pas',
  ConcatToFormatSample in 'resources\ConcatToFormatSample.pas',
  WithStatementSample in 'resources\WithStatementSample.pas',
  uAstFileCache in 'sources\Infrastructure\uAstFileCache.pas',
  uBaseline in 'sources\Infrastructure\uBaseline.pas',
  uDfmAnalysisRunner in 'sources\Infrastructure\uDfmAnalysisRunner.pas',
  uDfmDbFieldAnalysis in 'sources\Infrastructure\uDfmDbFieldAnalysis.pas',
  uDfmFrameResolver in 'sources\Infrastructure\uDfmFrameResolver.pas',
  uDfmRepoIndex in 'sources\Infrastructure\uDfmRepoIndex.pas',
  uExport in 'sources\Infrastructure\uExport.pas',
  uExportHtml in 'sources\Infrastructure\uExportHtml.pas',
  uFileTextCache in 'sources\Infrastructure\uFileTextCache.pas',
  uFormBinder in 'sources\Infrastructure\uFormBinder.pas',
  uIgnoreList in 'sources\Infrastructure\uIgnoreList.pas',
  uPathOverrides in 'sources\Infrastructure\uPathOverrides.pas',
  uRepoSettings in 'sources\Infrastructure\uRepoSettings.pas',
  uSonarConfig in 'sources\Infrastructure\uSonarConfig.pas',
  uSonarPull in 'sources\Infrastructure\uSonarPull.pas',
  uStaticAnalyzer2 in 'sources\Infrastructure\uStaticAnalyzer2.pas',
  uStaticFiles in 'sources\Infrastructure\uStaticFiles.pas',
  uSuppression in 'sources\Infrastructure\uSuppression.pas',
  uSymbolReferenceIndex in 'sources\Infrastructure\uSymbolReferenceIndex.pas',
  uVcsChanges in 'sources\Infrastructure\uVcsChanges.pas',
  uAbstractNotImpl in 'sources\Detectors\uAbstractNotImpl.pas',
  uAssertMessage in 'sources\Detectors\uAssertMessage.pas',
  uAssignedAndAssignedNil in 'sources\Detectors\uAssignedAndAssignedNil.pas',
  uAvoidOut in 'sources\Detectors\uAvoidOut.pas',
  uBeginEndRequired in 'sources\Detectors\uBeginEndRequired.pas',
  uCaseStatementSize in 'sources\Detectors\uCaseStatementSize.pas',
  uCastAndFree in 'sources\Detectors\uCastAndFree.pas',
  uCharToCharPointerCast in 'sources\Detectors\uCharToCharPointerCast.pas',
  uClassPerFile in 'sources\Detectors\uClassPerFile.pas',
  uCodeSmells2 in 'sources\Detectors\uCodeSmells2.pas',
  uCommentedOutCode in 'sources\Detectors\uCommentedOutCode.pas',
  uConcatToFormat in 'sources\Detectors\uConcatToFormat.pas',
  uConcurrencyExt in 'sources\Detectors\uConcurrencyExt.pas',
  uConsecutiveSection in 'sources\Detectors\uConsecutiveSection.pas',
  uConsecutiveVisibility in 'sources\Detectors\uConsecutiveVisibility.pas',
  uConstructorWithoutInherited in 'sources\Detectors\uConstructorWithoutInherited.pas',
  uCustomClassDiscovery in 'sources\Detectors\uCustomClassDiscovery.pas',
  uCustomRuleDetector in 'sources\Detectors\uCustomRuleDetector.pas',
  uCyclomaticComplexity in 'sources\Detectors\uCyclomaticComplexity.pas',
  uDateFormatSettings in 'sources\Detectors\uDateFormatSettings.pas',
  uDeadCode in 'sources\Detectors\uDeadCode.pas',
  uDebugOutput in 'sources\Detectors\uDebugOutput.pas',
  uDeepNesting in 'sources\Detectors\uDeepNesting.pas',
  uDestructorWithoutInherited in 'sources\Detectors\uDestructorWithoutInherited.pas',
  uDfmActionMismatch in 'sources\Detectors\uDfmActionMismatch.pas',
  uDfmCircularDataSource in 'sources\Detectors\uDfmCircularDataSource.pas',
  uDfmCrossFormCoupling in 'sources\Detectors\uDfmCrossFormCoupling.pas',
  uDfmDataModuleSplitHint in 'sources\Detectors\uDfmDataModuleSplitHint.pas',
  uDfmDbInUiForm in 'sources\Detectors\uDfmDbInUiForm.pas',
  uDfmDeadEvent in 'sources\Detectors\uDfmDeadEvent.pas',
  uDfmDefaultName in 'sources\Detectors\uDfmDefaultName.pas',
  uDfmDuplicateBinding in 'sources\Detectors\uDfmDuplicateBinding.pas',
  uDfmEmptyBoundEvent in 'sources\Detectors\uDfmEmptyBoundEvent.pas',
  uDfmFieldTypeMismatch in 'sources\Detectors\uDfmFieldTypeMismatch.pas',
  uDfmForbiddenClass in 'sources\Detectors\uDfmForbiddenClass.pas',
  uDfmGodHandler in 'sources\Detectors\uDfmGodHandler.pas',
  uDfmHardcodedCaption in 'sources\Detectors\uDfmHardcodedCaption.pas',
  uDfmHardcodedDbCreds in 'sources\Detectors\uDfmHardcodedDbCreds.pas',
  uDfmLayerViolation in 'sources\Detectors\uDfmLayerViolation.pas',
  uDfmMasterDetailUnlinked in 'sources\Detectors\uDfmMasterDetailUnlinked.pas',
  uDfmOrphanHandler in 'sources\Detectors\uDfmOrphanHandler.pas',
  uDfmRequiredField in 'sources\Detectors\uDfmRequiredField.pas',
  uDfmSchemaMismatch in 'sources\Detectors\uDfmSchemaMismatch.pas',
  uDfmSqlFromUserInput in 'sources\Detectors\uDfmSqlFromUserInput.pas',
  uDfmTabOrderConflict in 'sources\Detectors\uDfmTabOrderConflict.pas',
  uDigitGrouping in 'sources\Detectors\uDigitGrouping.pas',
  uDivByZero in 'sources\Detectors\uDivByZero.pas',
  uDuplicateBlock in 'sources\Detectors\uDuplicateBlock.pas',
  uDuplicateString in 'sources\Detectors\uDuplicateString.pas',
  uEmptyArgumentList in 'sources\Detectors\uEmptyArgumentList.pas',
  uEmptyBlock in 'sources\Detectors\uEmptyBlock.pas',
  uEmptyFile in 'sources\Detectors\uEmptyFile.pas',
  uEmptyFinallyBlock in 'sources\Detectors\uEmptyFinallyBlock.pas',
  uEmptyInterface in 'sources\Detectors\uEmptyInterface.pas',
  uEmptyMethod in 'sources\Detectors\uEmptyMethod.pas',
  uEmptyVisibilitySection in 'sources\Detectors\uEmptyVisibilitySection.pas',
  uExceptionTooGeneral in 'sources\Detectors\uExceptionTooGeneral.pas',
  uExceptOnException in 'sources\Detectors\uExceptOnException.pas',
  uExplicitTObjectInheritance in 'sources\Detectors\uExplicitTObjectInheritance.pas',
  uFieldLeak in 'sources\Detectors\uFieldLeak.pas',
  uFieldName in 'sources\Detectors\uFieldName.pas',
  uFormatMismatch in 'sources\Detectors\uFormatMismatch.pas',
  uFreeAndNilHint in 'sources\Detectors\uFreeAndNilHint.pas',
  uFreeWithoutNil in 'sources\Detectors\uFreeWithoutNil.pas',
  uGodClass in 'sources\Detectors\uGodClass.pas',
  uGotoStatement in 'sources\Detectors\uGotoStatement.pas',
  uGroupedDeclaration in 'sources\Detectors\uGroupedDeclaration.pas',
  uHardcodedPath in 'sources\Detectors\uHardcodedPath.pas',
  uHardcodedSecret in 'sources\Detectors\uHardcodedSecret.pas',
  uIfElseBegin in 'sources\Detectors\uIfElseBegin.pas',
  uIfThenShortCircuit in 'sources\Detectors\uIfThenShortCircuit.pas',
  uInheritedMethodEmpty in 'sources\Detectors\uInheritedMethodEmpty.pas',
  uInlineAssembly in 'sources\Detectors\uInlineAssembly.pas',
  uInstanceInvokedConstructor in 'sources\Detectors\uInstanceInvokedConstructor.pas',
  uIntegerOverflow in 'sources\Detectors\uIntegerOverflow.pas',
  uInterfaceName in 'sources\Detectors\uInterfaceName.pas',
  uLargeClass in 'sources\Detectors\uLargeClass.pas',
  uLeakDetector2 in 'sources\Detectors\uLeakDetector2.pas',
  uLeakInConstructor in 'sources\Detectors\uLeakInConstructor.pas',
  uLegacyInitializationSection in 'sources\Detectors\uLegacyInitializationSection.pas',
  uLengthUnderflow in 'sources\Detectors\uLengthUnderflow.pas',
  uLockWithoutTryFinally in 'sources\Detectors\uLockWithoutTryFinally.pas',
  uLongMethod in 'sources\Detectors\uLongMethod.pas',
  uLongParamList in 'sources\Detectors\uLongParamList.pas',
  uLowercaseKeyword in 'sources\Detectors\uLowercaseKeyword.pas',
  uMagicNumbers in 'sources\Detectors\uMagicNumbers.pas',
  uMethodName in 'sources\Detectors\uMethodName.pas',
  uMissingFinally in 'sources\Detectors\uMissingFinally.pas',
  uMissingRaise in 'sources\Detectors\uMissingRaise.pas',
  uMissingUnitHeader in 'sources\Detectors\uMissingUnitHeader.pas',
  uMultipleExit in 'sources\Detectors\uMultipleExit.pas',
  uNamingExt in 'sources\Detectors\uNamingExt.pas',
  uNestedRoutines in 'sources\Detectors\uNestedRoutines.pas',
  uNestedTry in 'sources\Detectors\uNestedTry.pas',
  uNilComparison in 'sources\Detectors\uNilComparison.pas',
  uNilDeref in 'sources\Detectors\uNilDeref.pas',
  uNoSonarMarker in 'sources\Detectors\uNoSonarMarker.pas',
  uPerfHotspots in 'sources\Detectors\uPerfHotspots.pas',
  uPointerName in 'sources\Detectors\uPointerName.pas',
  uPublicField in 'sources\Detectors\uPublicField.pas',
  uPublicMemberWithoutDoc in 'sources\Detectors\uPublicMemberWithoutDoc.pas',
  uRaiseOutsideExcept in 'sources\Detectors\uRaiseOutsideExcept.pas',
  uRaisingRawException in 'sources\Detectors\uRaisingRawException.pas',
  uRedundantBoolean in 'sources\Detectors\uRedundantBoolean.pas',
  uRedundantConditional in 'sources\Detectors\uRedundantConditional.pas',
  uRedundantJump in 'sources\Detectors\uRedundantJump.pas',
  uRedundantParentheses in 'sources\Detectors\uRedundantParentheses.pas',
  uReRaiseException in 'sources\Detectors\uReRaiseException.pas',
  uRestHttpSecurity in 'sources\Detectors\uRestHttpSecurity.pas',
  uReversedForRange in 'sources\Detectors\uReversedForRange.pas',
  uRoutineResultAssigned in 'sources\Detectors\uRoutineResultAssigned.pas',
  uSelfAssignment in 'sources\Detectors\uSelfAssignment.pas',
  uSqlDangerousStatement in 'sources\Detectors\uSqlDangerousStatement.pas',
  uSQLInjection in 'sources\Detectors\uSQLInjection.pas',
  uSQLInjectionScore in 'sources\Detectors\uSQLInjectionScore.pas',
  uSuperfluousSemicolon in 'sources\Detectors\uSuperfluousSemicolon.pas',
  uSynchronizeInDestructor in 'sources\Detectors\uSynchronizeInDestructor.pas',
  uTabulationCharacter in 'sources\Detectors\uTabulationCharacter.pas',
  uTautologicalExpr in 'sources\Detectors\uTautologicalExpr.pas',
  uTodoComment in 'sources\Detectors\uTodoComment.pas',
  uTooLongLine in 'sources\Detectors\uTooLongLine.pas',
  uTrailingCommaArgList in 'sources\Detectors\uTrailingCommaArgList.pas',
  uTrailingWhitespace in 'sources\Detectors\uTrailingWhitespace.pas',
  uTwiceInheritedCalls in 'sources\Detectors\uTwiceInheritedCalls.pas',
  uTypeName in 'sources\Detectors\uTypeName.pas',
  uUnicodeToAnsiCast in 'sources\Detectors\uUnicodeToAnsiCast.pas',
  uUnitLevelKeywordIndent in 'sources\Detectors\uUnitLevelKeywordIndent.pas',
  uUnsortedUses in 'sources\Detectors\uUnsortedUses.pas',
  uUnusedLocal in 'sources\Detectors\uUnusedLocal.pas',
  uUnusedParameter in 'sources\Detectors\uUnusedParameter.pas',
  uUnusedUses in 'sources\Detectors\uUnusedUses.pas',
  uUseAfterFree in 'sources\Detectors\uUseAfterFree.pas',
  uVirtualCallInCtor in 'sources\Detectors\uVirtualCallInCtor.pas',
  uVisibilityCheck in 'sources\Detectors\uVisibilityCheck.pas',
  uWithStatement in 'sources\Detectors\uWithStatement.pas',
  uFloatEquality in 'sources\Detectors\uFloatEquality.pas',
  uExceptInDestructor in 'sources\Detectors\uExceptInDestructor.pas',
  uBooleanParam in 'sources\Detectors\uBooleanParam.pas',
  uUnusedPrivateMethod in 'sources\Detectors\uUnusedPrivateMethod.pas',
  uCanBeClassMethod in 'sources\Detectors\uCanBeClassMethod.pas',
  uMissingOverride in 'sources\Detectors\uMissingOverride.pas',
  uBoolAlwaysTrue in 'sources\Detectors\uBoolAlwaysTrue.pas',
  uConstantReturn in 'sources\Detectors\uConstantReturn.pas',
  uHardcodedString in 'sources\Detectors\uHardcodedString.pas',
  uPointerArithmeticOnString in 'sources\Detectors\uPointerArithmeticOnString.pas',
  uSetLengthAppendInLoop in 'sources\Detectors\uSetLengthAppendInLoop.pas',
  uGetMemWithoutFreeMem in 'sources\Detectors\uGetMemWithoutFreeMem.pas',
  uWithMultipleTargets in 'sources\Detectors\uWithMultipleTargets.pas',
  uMoveSizeOfPointer in 'sources\Detectors\uMoveSizeOfPointer.pas',
  uUnpairedLock in 'sources\Detectors\uUnpairedLock.pas';

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

// Hangt sich an die Konsole des Aufrufer-Prozesses (typisch cmd.exe / pwsh)
// und biegt die Pascal-RTL-TextFiles Output/ErrOutput dorthin um.
// Liefert True wenn eine Konsole verfuegbar war (auch wenn sie bereits
// zuvor existierte, z.B. CI-Runner). False wenn der Aufrufer keine Konsole
// hatte (Doppelklick aus Explorer) - in dem Fall gehen WriteLns ins Leere,
// was im CLI-Mode unueblich aber nicht crash-relevant ist.
function AttachToParentConsole: Boolean;
const
  ATTACH_PARENT_PROCESS_FLAG = DWORD(-1);
begin
  Result := AttachConsole(ATTACH_PARENT_PROCESS_FLAG);
  if not Result then Exit;
  // System.Output / System.ErrOutput wurden vom RTL-Startup auf die (nicht
  // existente) Default-Konsole gemappt. Nach AttachConsole zeigen die alten
  // Handles ins Leere - daher TextFiles neu auf CONOUT$ binden. CONOUT$ ist
  // ein Windows-Special-File das auf die aktive Konsole verweist und immer
  // schreibbar ist solange eine Konsole attached ist.
  try
    AssignFile(Output,    'CONOUT$');
    Rewrite(Output);
    AssignFile(ErrOutput, 'CONOUT$');
    Rewrite(ErrOutput);
  except
    // Bei IO-Errors stillschweigend zurueck - der CLI-Lauf laeuft weiter,
    // nur ohne Output. Exit-Codes funktionieren unabhaengig davon.
  end;
end;

begin
  if IsCliMode then
  begin
    // Headless-Pfad - keine VCL-Form, exit code via Halt.
    AttachToParentConsole;
    var CliExitCode: Integer;
    CliExitCode := 99;
    try
      CliExitCode := uConsoleRunner.TConsoleRunner.RunFromCmdLine;
    except
      on E: Exception do
      begin
        WriteLn(ErrOutput, 'Fatal: ', E.ClassName, ': ', E.Message);
        CliExitCode := 99;
      end;
    end;
    // FreeConsole VOR Halt - Halt umgeht try/finally, also nicht
    // dorthinein. Sonst bleibt der cmd-Prompt-Cursor haengen.
    FreeConsole;
    Halt(CliExitCode);
  end
  else
  begin
    Application.Initialize;
    Application.MainFormOnTaskbar := True;
    Application.CreateForm(TForm2, Form2);
  // uCustomerForm + uOrderForm sind Test-Fixtures fuer die DFM-Detektoren
    // (qCustomers: TFDQuery, dsOrders: TDataSetProvider, ...). Sie bleiben
    // im Projekt fuer die Kompilierung, werden aber NICHT als Runtime-Form
    // instanziiert - sonst wirft das DFM-Streaming FireDAC-512 (keine
    // Connection auf qCustomers). Bei Bedarf manuell als TForm.Create.
    Application.Run;
  end;
end.
