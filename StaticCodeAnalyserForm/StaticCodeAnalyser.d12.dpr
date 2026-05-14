program analyser.d12;

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
  uExport in 'sources\Infrastructure\uExport.pas',
  uExportHtml in 'sources\Infrastructure\uExportHtml.pas',
  uIgnoreList in 'sources\Infrastructure\uIgnoreList.pas',
  uRepoSettings in 'sources\Infrastructure\uRepoSettings.pas',
  uStaticAnalyzer2 in 'sources\Infrastructure\uStaticAnalyzer2.pas',
  uStaticFiles in 'sources\Infrastructure\uStaticFiles.pas',
  uSuppression in 'sources\Infrastructure\uSuppression.pas',
  uVcsChanges in 'sources\Infrastructure\uVcsChanges.pas',
  uDfmAnalysisRunner in 'sources\Infrastructure\uDfmAnalysisRunner.pas',
  uDfmFrameResolver in 'sources\Infrastructure\uDfmFrameResolver.pas',
  uFormBinder in 'sources\Infrastructure\uFormBinder.pas',
  uDfmDbFieldAnalysis in 'sources\Infrastructure\uDfmDbFieldAnalysis.pas',
  uDfmRepoIndex in 'sources\Infrastructure\uDfmRepoIndex.pas',
  uClaudePrompt in 'sources\Output\uClaudePrompt.pas',
  uExportSARIF in 'sources\Output\uExportSARIF.pas',
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
  uDfmActionMismatch in 'sources\Detectors\uDfmActionMismatch.pas',
  uCustomerForm in 'resources\uCustomerForm.pas' {CustomerForm},
  uOrderForm in 'resources\uOrderForm.pas' {OrderForm},
  uIDEStatsTiles in '..\StaticCodeAnalyserIDE\uIDEStatsTiles.pas',
  uIDEHelpPanel in '..\StaticCodeAnalyserIDE\uIDEHelpPanel.pas';

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
