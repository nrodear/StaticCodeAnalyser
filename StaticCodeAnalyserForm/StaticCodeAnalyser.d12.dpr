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
  uAnalyserPalette in '..\SCA.SharedUI\sources\uAnalyserPalette.pas',
  uAnalyserTheme in '..\SCA.SharedUI\sources\uAnalyserTheme.pas',
  uAnalyserTypes in '..\SCA.Engine\sources\Common\uAnalyserTypes.pas',
  uLocalization in '..\SCA.Engine\sources\Common\uLocalization.pas',
  uFindingGridRenderer in '..\SCA.SharedUI\sources\uFindingGridRenderer.pas',
  uFindingFilter in '..\SCA.SharedUI\sources\uFindingFilter.pas',
  uMainForm in 'sources\UI\uMainForm.pas' {Form2},
  uDfmTextViewer in 'sources\UI\uDfmTextViewer.pas',
  uAstNode in '..\SCA.Engine\sources\Parsing\uAstNode.pas',
  uLexer in '..\SCA.Engine\sources\Parsing\uLexer.pas',
  uParser2 in '..\SCA.Engine\sources\Parsing\uParser2.pas',
  uComponentGraph in '..\SCA.Engine\sources\Parsing\uComponentGraph.pas',
  uDfmLexer in '..\SCA.Engine\sources\Parsing\uDfmLexer.pas',
  uDfmParser in '..\SCA.Engine\sources\Parsing\uDfmParser.pas',
  uDfmBinaryReader in '..\SCA.Engine\sources\Parsing\uDfmBinaryReader.pas',
  uClaudePrompt in '..\SCA.Engine\sources\Output\uClaudePrompt.pas',
  uExportSARIF in '..\SCA.Engine\sources\Output\uExportSARIF.pas',
  uExportSonarGeneric in '..\SCA.Engine\sources\Output\uExportSonarGeneric.pas',
  uSonarPush in '..\SCA.Engine\sources\Output\uSonarPush.pas',
  uFixHint in '..\SCA.Engine\sources\Output\uFixHint.pas',
  uConsoleRunner in 'sources\Console\uConsoleRunner.pas',
  uCollectValues in '..\SCA.Engine\sources\Common\uCollectValues.pas',
  uDetectorUtils in '..\SCA.Engine\sources\Common\uDetectorUtils.pas',
  uMethodd12 in '..\SCA.Engine\sources\Common\uMethodd12.pas',
  uRecentPaths in '..\SCA.SharedUI\sources\uRecentPaths.pas',
  uRegExMatches in '..\SCA.Engine\sources\Common\uRegExMatches.pas',
  uRuleCatalog in '..\SCA.Engine\sources\Common\uRuleCatalog.pas',
  uSCAConsts in '..\SCA.Engine\sources\Common\uSCAConsts.pas',
  uIDEColors in '..\SCA.SharedUI\sources\uIDEColors.pas',
  uYamlSubsetParser in '..\SCA.Engine\sources\Common\uYamlSubsetParser.pas',
  uQuickFix in '..\SCA.Engine\sources\Common\uQuickFix.pas',
  uCustomerForm in 'resources\uCustomerForm.pas' {CustomerForm},
  uOrderForm in 'resources\uOrderForm.pas' {OrderForm},
  uIDEStatsTiles in '..\SCA.SharedUI\sources\uIDEStatsTiles.pas',
  uIDEHelpPanel in '..\SCA.SharedUI\sources\uIDEHelpPanel.pas',
  uIDEToolbar in '..\SCA.SharedUI\sources\uIDEToolbar.pas',
  uExportMenu in '..\SCA.SharedUI\sources\uExportMenu.pas',
  ConcatToFormatSample in 'resources\ConcatToFormatSample.pas',
  WithStatementSample in 'resources\WithStatementSample.pas',
  uAstFileCache in '..\SCA.Engine\sources\Infrastructure\uAstFileCache.pas',
  uBaseline in '..\SCA.Engine\sources\Infrastructure\uBaseline.pas',
  uDfmAnalysisRunner in '..\SCA.Engine\sources\Infrastructure\uDfmAnalysisRunner.pas',
  uDfmDbFieldAnalysis in '..\SCA.Engine\sources\Infrastructure\uDfmDbFieldAnalysis.pas',
  uDfmFrameResolver in '..\SCA.Engine\sources\Infrastructure\uDfmFrameResolver.pas',
  uDfmRepoIndex in '..\SCA.Engine\sources\Infrastructure\uDfmRepoIndex.pas',
  uExport in '..\SCA.Engine\sources\Infrastructure\uExport.pas',
  uExportHtml in '..\SCA.Engine\sources\Infrastructure\uExportHtml.pas',
  uFileTextCache in '..\SCA.Engine\sources\Infrastructure\uFileTextCache.pas',
  uFindingFingerprint in '..\SCA.Engine\sources\Infrastructure\uFindingFingerprint.pas',
  uSuppressionTelemetry in '..\SCA.Engine\sources\Infrastructure\uSuppressionTelemetry.pas',
  uFormBinder in '..\SCA.Engine\sources\Infrastructure\uFormBinder.pas',
  uIgnoreList in '..\SCA.Engine\sources\Infrastructure\uIgnoreList.pas',
  uConfidenceFilter in '..\SCA.Engine\sources\Infrastructure\uConfidenceFilter.pas',
  uPathOverrides in '..\SCA.Engine\sources\Infrastructure\uPathOverrides.pas',
  uRepoSettings in '..\SCA.Engine\sources\Infrastructure\uRepoSettings.pas',
  uSonarConfig in '..\SCA.Engine\sources\Infrastructure\uSonarConfig.pas',
  uSonarPull in '..\SCA.Engine\sources\Infrastructure\uSonarPull.pas',
  uStaticAnalyzer2 in '..\SCA.Engine\sources\Infrastructure\uStaticAnalyzer2.pas',
  uStaticFiles in '..\SCA.Engine\sources\Infrastructure\uStaticFiles.pas',
  uSuppression in '..\SCA.Engine\sources\Infrastructure\uSuppression.pas',
  uSymbolReferenceIndex in '..\SCA.Engine\sources\Infrastructure\uSymbolReferenceIndex.pas',
  uVcsChanges in '..\SCA.Engine\sources\Infrastructure\uVcsChanges.pas',
  uPointerSubtraction in '..\SCA.Engine\sources\Detectors\uPointerSubtraction.pas',
  uInsecureCryptoAlgorithm in '..\SCA.Engine\sources\Detectors\uInsecureCryptoAlgorithm.pas',
  uCommandInjection in '..\SCA.Engine\sources\Detectors\uCommandInjection.pas',
  uUnusedRoutine in '..\SCA.Engine\sources\Detectors\uUnusedRoutine.pas',
  uUninitVar in '..\SCA.Engine\sources\Detectors\uUninitVar.pas',
  uStringFromPointer in '..\SCA.Engine\sources\Detectors\uStringFromPointer.pas',
  uEmptyOnHandler in '..\SCA.Engine\sources\Detectors\uEmptyOnHandler.pas',
  uUnusedPrivateMethod in '..\SCA.Engine\sources\Detectors\uUnusedPrivateMethod.pas',
  uFreeWithoutNil in '..\SCA.Engine\sources\Detectors\uFreeWithoutNil.pas',
  uAbstractNotImpl in '..\SCA.Engine\sources\Detectors\uAbstractNotImpl.pas',
  uPointerArithmeticOnString in '..\SCA.Engine\sources\Detectors\uPointerArithmeticOnString.pas',
  uSetLengthAppendInLoop in '..\SCA.Engine\sources\Detectors\uSetLengthAppendInLoop.pas',
  uGetMemWithoutFreeMem in '..\SCA.Engine\sources\Detectors\uGetMemWithoutFreeMem.pas',
  uWithMultipleTargets in '..\SCA.Engine\sources\Detectors\uWithMultipleTargets.pas',
  uMoveSizeOfPointer in '..\SCA.Engine\sources\Detectors\uMoveSizeOfPointer.pas',
  uUnpairedLock in '..\SCA.Engine\sources\Detectors\uUnpairedLock.pas',
  uHardcodedString in '..\SCA.Engine\sources\Detectors\uHardcodedString.pas',
  uConstantReturn in '..\SCA.Engine\sources\Detectors\uConstantReturn.pas',
  uBoolAlwaysTrue in '..\SCA.Engine\sources\Detectors\uBoolAlwaysTrue.pas',
  uMissingOverride in '..\SCA.Engine\sources\Detectors\uMissingOverride.pas',
  uCanBeClassMethod in '..\SCA.Engine\sources\Detectors\uCanBeClassMethod.pas',
  uBooleanParam in '..\SCA.Engine\sources\Detectors\uBooleanParam.pas',
  uExceptInDestructor in '..\SCA.Engine\sources\Detectors\uExceptInDestructor.pas',
  uFloatEquality in '..\SCA.Engine\sources\Detectors\uFloatEquality.pas',
  uMissingUnitHeader in '..\SCA.Engine\sources\Detectors\uMissingUnitHeader.pas',
  uUnsortedUses in '..\SCA.Engine\sources\Detectors\uUnsortedUses.pas',
  uLargeClass in '..\SCA.Engine\sources\Detectors\uLargeClass.pas',
  uMultipleExit in '..\SCA.Engine\sources\Detectors\uMultipleExit.pas',
  uGodClass in '..\SCA.Engine\sources\Detectors\uGodClass.pas',
  uUseAfterFree in '..\SCA.Engine\sources\Detectors\uUseAfterFree.pas',
  uIntegerOverflow in '..\SCA.Engine\sources\Detectors\uIntegerOverflow.pas',
  uLeakInConstructor in '..\SCA.Engine\sources\Detectors\uLeakInConstructor.pas',
  uTautologicalExpr in '..\SCA.Engine\sources\Detectors\uTautologicalExpr.pas',
  uConstructorWithoutInherited in '..\SCA.Engine\sources\Detectors\uConstructorWithoutInherited.pas',
  uRoutineResultAssigned in '..\SCA.Engine\sources\Detectors\uRoutineResultAssigned.pas',
  uDestructorWithoutInherited in '..\SCA.Engine\sources\Detectors\uDestructorWithoutInherited.pas',
  uConcurrencyExt in '..\SCA.Engine\sources\Detectors\uConcurrencyExt.pas',
  uRaiseOutsideExcept in '..\SCA.Engine\sources\Detectors\uRaiseOutsideExcept.pas',
  uExceptionTooGeneral in '..\SCA.Engine\sources\Detectors\uExceptionTooGeneral.pas',
  uCustomRuleDetector in '..\SCA.Engine\sources\Detectors\uCustomRuleDetector.pas',
  uUnicodeToAnsiCast in '..\SCA.Engine\sources\Detectors\uUnicodeToAnsiCast.pas',
  uIfThenShortCircuit in '..\SCA.Engine\sources\Detectors\uIfThenShortCircuit.pas',
  uNilComparison in '..\SCA.Engine\sources\Detectors\uNilComparison.pas',
  uCharToCharPointerCast in '..\SCA.Engine\sources\Detectors\uCharToCharPointerCast.pas',
  uDateFormatSettings in '..\SCA.Engine\sources\Detectors\uDateFormatSettings.pas',
  uRaisingRawException in '..\SCA.Engine\sources\Detectors\uRaisingRawException.pas',
  uInheritedMethodEmpty in '..\SCA.Engine\sources\Detectors\uInheritedMethodEmpty.pas',
  uInstanceInvokedConstructor in '..\SCA.Engine\sources\Detectors\uInstanceInvokedConstructor.pas',
  uPublicMemberWithoutDoc in '..\SCA.Engine\sources\Detectors\uPublicMemberWithoutDoc.pas',
  uCastAndFree in '..\SCA.Engine\sources\Detectors\uCastAndFree.pas',
  uReRaiseException in '..\SCA.Engine\sources\Detectors\uReRaiseException.pas',
  uMissingRaise in '..\SCA.Engine\sources\Detectors\uMissingRaise.pas',
  uLockWithoutTryFinally in '..\SCA.Engine\sources\Detectors\uLockWithoutTryFinally.pas',
  uSynchronizeInDestructor in '..\SCA.Engine\sources\Detectors\uSynchronizeInDestructor.pas',
  uNamingExt in '..\SCA.Engine\sources\Detectors\uNamingExt.pas',
  uRestHttpSecurity in '..\SCA.Engine\sources\Detectors\uRestHttpSecurity.pas',
  uPerfHotspots in '..\SCA.Engine\sources\Detectors\uPerfHotspots.pas',
  uRedundantConditional in '..\SCA.Engine\sources\Detectors\uRedundantConditional.pas',
  uVisibilityCheck in '..\SCA.Engine\sources\Detectors\uVisibilityCheck.pas',
  uHardcodedSecret in '..\SCA.Engine\sources\Detectors\uHardcodedSecret.pas',
  uDeadCode in '..\SCA.Engine\sources\Detectors\uDeadCode.pas',
  uConsecutiveVisibility in '..\SCA.Engine\sources\Detectors\uConsecutiveVisibility.pas',
  uTwiceInheritedCalls in '..\SCA.Engine\sources\Detectors\uTwiceInheritedCalls.pas',
  uNestedRoutines in '..\SCA.Engine\sources\Detectors\uNestedRoutines.pas',
  uEmptyBlock in '..\SCA.Engine\sources\Detectors\uEmptyBlock.pas',
  uPointerName in '..\SCA.Engine\sources\Detectors\uPointerName.pas',
  uExceptOnException in '..\SCA.Engine\sources\Detectors\uExceptOnException.pas',
  uCommentedOutCode in '..\SCA.Engine\sources\Detectors\uCommentedOutCode.pas',
  uMethodName in '..\SCA.Engine\sources\Detectors\uMethodName.pas',
  uInterfaceName in '..\SCA.Engine\sources\Detectors\uInterfaceName.pas',
  uTypeName in '..\SCA.Engine\sources\Detectors\uTypeName.pas',
  uFieldName in '..\SCA.Engine\sources\Detectors\uFieldName.pas',
  uBeginEndRequired in '..\SCA.Engine\sources\Detectors\uBeginEndRequired.pas',
  uIfElseBegin in '..\SCA.Engine\sources\Detectors\uIfElseBegin.pas',
  uRedundantParentheses in '..\SCA.Engine\sources\Detectors\uRedundantParentheses.pas',
  uEmptyFile in '..\SCA.Engine\sources\Detectors\uEmptyFile.pas',
  uCaseStatementSize in '..\SCA.Engine\sources\Detectors\uCaseStatementSize.pas',
  uGroupedDeclaration in '..\SCA.Engine\sources\Detectors\uGroupedDeclaration.pas',
  uLegacyInitializationSection in '..\SCA.Engine\sources\Detectors\uLegacyInitializationSection.pas',
  uNestedTry in '..\SCA.Engine\sources\Detectors\uNestedTry.pas',
  uPublicField in '..\SCA.Engine\sources\Detectors\uPublicField.pas',
  uEmptyVisibilitySection in '..\SCA.Engine\sources\Detectors\uEmptyVisibilitySection.pas',
  uAvoidOut in '..\SCA.Engine\sources\Detectors\uAvoidOut.pas',
  uFreeAndNilHint in '..\SCA.Engine\sources\Detectors\uFreeAndNilHint.pas',
  uAssignedAndAssignedNil in '..\SCA.Engine\sources\Detectors\uAssignedAndAssignedNil.pas',
  uEmptyFinallyBlock in '..\SCA.Engine\sources\Detectors\uEmptyFinallyBlock.pas',
  uSuperfluousSemicolon in '..\SCA.Engine\sources\Detectors\uSuperfluousSemicolon.pas',
  uClassPerFile in '..\SCA.Engine\sources\Detectors\uClassPerFile.pas',
  uRedundantJump in '..\SCA.Engine\sources\Detectors\uRedundantJump.pas',
  uConsecutiveSection in '..\SCA.Engine\sources\Detectors\uConsecutiveSection.pas',
  uExplicitTObjectInheritance in '..\SCA.Engine\sources\Detectors\uExplicitTObjectInheritance.pas',
  uAssertMessage in '..\SCA.Engine\sources\Detectors\uAssertMessage.pas',
  uEmptyInterface in '..\SCA.Engine\sources\Detectors\uEmptyInterface.pas',
  uRedundantBoolean in '..\SCA.Engine\sources\Detectors\uRedundantBoolean.pas',
  uUnitLevelKeywordIndent in '..\SCA.Engine\sources\Detectors\uUnitLevelKeywordIndent.pas',
  uDigitGrouping in '..\SCA.Engine\sources\Detectors\uDigitGrouping.pas',
  uTrailingCommaArgList in '..\SCA.Engine\sources\Detectors\uTrailingCommaArgList.pas',
  uInlineAssembly in '..\SCA.Engine\sources\Detectors\uInlineAssembly.pas',
  uLowercaseKeyword in '..\SCA.Engine\sources\Detectors\uLowercaseKeyword.pas',
  uEmptyArgumentList in '..\SCA.Engine\sources\Detectors\uEmptyArgumentList.pas',
  uNoSonarMarker in '..\SCA.Engine\sources\Detectors\uNoSonarMarker.pas',
  uTrailingWhitespace in '..\SCA.Engine\sources\Detectors\uTrailingWhitespace.pas',
  uTooLongLine in '..\SCA.Engine\sources\Detectors\uTooLongLine.pas',
  uTabulationCharacter in '..\SCA.Engine\sources\Detectors\uTabulationCharacter.pas',
  uGotoStatement in '..\SCA.Engine\sources\Detectors\uGotoStatement.pas',
  uDfmCrossFormCoupling in '..\SCA.Engine\sources\Detectors\uDfmCrossFormCoupling.pas',
  uDfmDataModuleSplitHint in '..\SCA.Engine\sources\Detectors\uDfmDataModuleSplitHint.pas',
  uDfmDbInUiForm in '..\SCA.Engine\sources\Detectors\uDfmDbInUiForm.pas',
  uDfmDeadEvent in '..\SCA.Engine\sources\Detectors\uDfmDeadEvent.pas',
  uDfmDefaultName in '..\SCA.Engine\sources\Detectors\uDfmDefaultName.pas',
  uDfmDuplicateBinding in '..\SCA.Engine\sources\Detectors\uDfmDuplicateBinding.pas',
  uDfmEmptyBoundEvent in '..\SCA.Engine\sources\Detectors\uDfmEmptyBoundEvent.pas',
  uDfmFieldTypeMismatch in '..\SCA.Engine\sources\Detectors\uDfmFieldTypeMismatch.pas',
  uDfmForbiddenClass in '..\SCA.Engine\sources\Detectors\uDfmForbiddenClass.pas',
  uDfmGodHandler in '..\SCA.Engine\sources\Detectors\uDfmGodHandler.pas',
  uDfmHardcodedCaption in '..\SCA.Engine\sources\Detectors\uDfmHardcodedCaption.pas',
  uDfmHardcodedDbCreds in '..\SCA.Engine\sources\Detectors\uDfmHardcodedDbCreds.pas',
  uDfmLayerViolation in '..\SCA.Engine\sources\Detectors\uDfmLayerViolation.pas',
  uDfmMasterDetailUnlinked in '..\SCA.Engine\sources\Detectors\uDfmMasterDetailUnlinked.pas',
  uDfmOrphanHandler in '..\SCA.Engine\sources\Detectors\uDfmOrphanHandler.pas',
  uDfmRequiredField in '..\SCA.Engine\sources\Detectors\uDfmRequiredField.pas',
  uDfmSchemaMismatch in '..\SCA.Engine\sources\Detectors\uDfmSchemaMismatch.pas',
  uDfmSqlFromUserInput in '..\SCA.Engine\sources\Detectors\uDfmSqlFromUserInput.pas',
  uDfmTabOrderConflict in '..\SCA.Engine\sources\Detectors\uDfmTabOrderConflict.pas',
  uDuplicateBlock in '..\SCA.Engine\sources\Detectors\uDuplicateBlock.pas',
  uDuplicateString in '..\SCA.Engine\sources\Detectors\uDuplicateString.pas',
  uEmptyMethod in '..\SCA.Engine\sources\Detectors\uEmptyMethod.pas',
  uFieldLeak in '..\SCA.Engine\sources\Detectors\uFieldLeak.pas',
  uFormatMismatch in '..\SCA.Engine\sources\Detectors\uFormatMismatch.pas',
  uHardcodedPath in '..\SCA.Engine\sources\Detectors\uHardcodedPath.pas',
  uLengthUnderflow in '..\SCA.Engine\sources\Detectors\uLengthUnderflow.pas',
  uLongMethod in '..\SCA.Engine\sources\Detectors\uLongMethod.pas',
  uLongParamList in '..\SCA.Engine\sources\Detectors\uLongParamList.pas',
  uMagicNumbers in '..\SCA.Engine\sources\Detectors\uMagicNumbers.pas',
  uMissingFinally in '..\SCA.Engine\sources\Detectors\uMissingFinally.pas',
  uNilDeref in '..\SCA.Engine\sources\Detectors\uNilDeref.pas',
  uReversedForRange in '..\SCA.Engine\sources\Detectors\uReversedForRange.pas',
  uSelfAssignment in '..\SCA.Engine\sources\Detectors\uSelfAssignment.pas',
  uSqlDangerousStatement in '..\SCA.Engine\sources\Detectors\uSqlDangerousStatement.pas',
  uSQLInjection in '..\SCA.Engine\sources\Detectors\uSQLInjection.pas',
  uTodoComment in '..\SCA.Engine\sources\Detectors\uTodoComment.pas',
  uUnusedLocal in '..\SCA.Engine\sources\Detectors\uUnusedLocal.pas',
  uUnusedParameter in '..\SCA.Engine\sources\Detectors\uUnusedParameter.pas',
  uUnusedUses in '..\SCA.Engine\sources\Detectors\uUnusedUses.pas',
  uVirtualCallInCtor in '..\SCA.Engine\sources\Detectors\uVirtualCallInCtor.pas',
  uWithStatement in '..\SCA.Engine\sources\Detectors\uWithStatement.pas',
  uCodeSmells2 in '..\SCA.Engine\sources\Detectors\uCodeSmells2.pas',
  uConcatToFormat in '..\SCA.Engine\sources\Detectors\uConcatToFormat.pas',
  uCyclomaticComplexity in '..\SCA.Engine\sources\Detectors\uCyclomaticComplexity.pas',
  uDebugOutput in '..\SCA.Engine\sources\Detectors\uDebugOutput.pas',
  uDeepNesting in '..\SCA.Engine\sources\Detectors\uDeepNesting.pas',
  uDfmActionMismatch in '..\SCA.Engine\sources\Detectors\uDfmActionMismatch.pas',
  uDfmCircularDataSource in '..\SCA.Engine\sources\Detectors\uDfmCircularDataSource.pas',
  uLeakDetector2 in '..\SCA.Engine\sources\Detectors\uLeakDetector2.pas',
  uDivByZero in '..\SCA.Engine\sources\Detectors\uDivByZero.pas',
  uSQLInjectionScore in '..\SCA.Engine\sources\Detectors\uSQLInjectionScore.pas',
  uCustomClassDiscovery in '..\SCA.Engine\sources\Detectors\uCustomClassDiscovery.pas';

{$R *.res}
// App-Icon kommt via <Icon_MainIcon> im .dproj: Delphi auto-embeddet das
// .ico als MAINICON in die StaticCodeAnalyser.d12.res (= das `*.res`
// oben), Windows nutzt es fuer Shell-Icon + Taskbar + Application.Icon.
// Keine explizite {$R '...res'}-Directive noetig, kein uBrandingImage,
// keine Runtime-Pipeline. Canonical Embarcadero-Weg.

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
    // CliExitCode wird in BEIDEN Pfaden des try/except gesetzt - eine Default-
    // Initialisierung waere ein Dead-Store (H2077). RunFromCmdLine entweder
    // returned einen Code, oder wirft -> except setzt 99.
    var CliExitCode: Integer;
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
    // Application.Icon wird von der RTL automatisch aus der MAINICON-
    // Resource gesetzt (siehe <Icon_MainIcon> im dproj -> branding\sca.ico).
    // Keine explizite Zuweisung noetig - canonical Embarcadero-Weg.
    Application.CreateForm(TForm2, Form2);
  // uCustomerForm + uOrderForm sind Test-Fixtures fuer die DFM-Detektoren
    // (qCustomers: TFDQuery, dsOrders: TDataSetProvider, ...). Sie bleiben
    // im Projekt fuer die Kompilierung, werden aber NICHT als Runtime-Form
    // instanziiert - sonst wirft das DFM-Streaming FireDAC-512 (keine
    // Connection auf qCustomers). Bei Bedarf manuell als TForm.Create.
    Application.Run;
  end;
end.
