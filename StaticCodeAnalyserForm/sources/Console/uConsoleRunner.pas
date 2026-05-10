unit uConsoleRunner;

// Headless CLI-Mode fuer analyser.d12.exe. Nicht-interaktiv, fuer
// CI/CD-Pipelines (GitHub Actions, GitLab CI, Jenkins, lokale
// Pre-Commit-Hooks).
//
// Aufruf-Beispiele:
//   analyser.exe --path D:\repo --full --report-sarif sca.sarif
//   analyser.exe --path D:\repo --branch --report-sarif sca.sarif
//   analyser.exe --file MeineUnit.pas --quiet
//   analyser.exe --help
//
// Exit-Code-Konvention (klassisch fuer SCA-Tools):
//   0  = keine Findings (clean)
//   1  = nur Hints
//   2  = mindestens 1 Warning (keine Errors)
//   3  = mindestens 1 Error
//   4  = mindestens 1 Read-Error (Parser-/IO-Fehler)
//   99 = Tool-Fehler (Args ungueltig, Pfad fehlt, ...)
//
// Ist der Aufrufer in einem reinen Console-Kontext entstanden (kein
// Terminal angehaengt), schreibt der Runner trotzdem ueber WriteLn -
// fuer Pipe-Redirection und Log-Files reicht das.

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections,
  uMethodd12;

type
  // Ergebnis des CLI-Runs - der Caller (.dpr) ruebergibt das an Halt().
  TCliExitCode = (
    cecClean        = 0,
    cecHints        = 1,
    cecWarnings     = 2,
    cecErrors       = 3,
    cecReadErrors   = 4,
    cecToolError    = 99
  );

  // Geparste Args. Public damit Tests die Parse-Logik isoliert ansprechen
  // koennen (kein Run-Side-Effect).
  TCliArgs = record
    Help          : Boolean;        // --help / -h / -?
    ShowVersion   : Boolean;        // --version
    Path          : string;         // --path <dir>
    SingleFile    : string;         // --file <path>
    Full          : Boolean;        // --full      (rekursiv ab Path)
    Branch        : Boolean;        // --branch    (nur VCS-geaenderte)
    ReportSarif   : string;         // --report-sarif <out.sarif>
    Quiet         : Boolean;        // --quiet
    BaseDir       : string;         // --base-dir <dir>  (fuer relative Pfade
                                    //   im SARIF; default = Path)
    CustomRules   : string;         // --custom-rules <analyser-rules.yml>
    ParseError    : string;         // nicht-leer wenn Args invalid
  end;

  TConsoleRunner = class
  public
    // Parsing-Layer - testbar ohne IO. ParamStr/ParamCount-Wrapper:
    // die Tests koennen ein eigenes string-Array uebergeben.
    class function ParseArgs(const Args: array of string): TCliArgs; static;
    class function ParseSysArgs: TCliArgs; static;

    // Run-Layer. Liefert den Exit-Code fuer Halt(). KEINE Exceptions
    // nach aussen - alles wird auf stderr geloggt + Exit-Code gesetzt.
    class function Run(const Args: TCliArgs): Integer; static;

    // Hauptentry vom .dpr - kombiniert Parse + Run, fuer den haeufigen
    // Fall ohne Test-Mocks.
    class function RunFromCmdLine: Integer; static;
  private
    class procedure WriteHelp; static;
    class procedure WriteVersion; static;
    class procedure WriteSummary(const Findings: TObjectList<TLeakFinding>;
      Quiet: Boolean); static;
    class function CalcExitCode(const Findings: TObjectList<TLeakFinding>): Integer; static;
  end;

implementation

uses
  System.IOUtils,
  uSCAConsts, uStaticAnalyzer2, uVcsChanges, uRepoSettings,
  uExportSARIF, uCustomRuleDetector;

const
  SCA_VERSION = '0.8.0';
  SCA_TOOLNAME = 'StaticCodeAnalyser';

{ ---- Args-Parser ---- }

class function TConsoleRunner.ParseArgs(const Args: array of string): TCliArgs;
// Akzeptiert sowohl "--key value" als auch "--key=value".
// Boolean-Switches haben kein Value.
var
  i      : Integer;
  A, V   : string;
  EqPos  : Integer;
  HasVal : Boolean;
  Errored: Boolean;

  // Holt den Value-String fuer den aktuellen Switch und schreibt ihn in
  // Target. Liefert True bei Erfolg; bei Fehlschlag werden ParseError +
  // Errored-Flag gesetzt. Caller bricht ueber Errored ab.
  procedure GetValue(var Target: string; const SwitchName: string);
  begin
    if HasVal then begin Target := V; Exit; end;
    if i + 1 > High(Args) then
    begin
      Result.ParseError := Format('%s braucht einen Wert', [SwitchName]);
      Errored := True;
      Exit;
    end;
    Inc(i);
    Target := Args[i];
  end;

begin
  // Defaults
  Result.Help        := False;
  Result.ShowVersion := False;
  Result.Path        := '';
  Result.SingleFile  := '';
  Result.Full        := False;
  Result.Branch      := False;
  Result.ReportSarif := '';
  Result.Quiet       := False;
  Result.BaseDir     := '';
  Result.ParseError  := '';
  Errored            := False;

  i := Low(Args);
  while (i <= High(Args)) and not Errored do
  begin
    A := Args[i];
    EqPos := Pos('=', A);
    if EqPos > 0 then
    begin
      V := Copy(A, EqPos + 1, MaxInt);
      A := Copy(A, 1, EqPos - 1);
      HasVal := True;
    end
    else
    begin
      V := '';
      HasVal := False;
    end;

    if (A = '--help') or (A = '-h') or (A = '-?') or (A = '/?') then
      Result.Help := True
    else if A = '--version' then
      Result.ShowVersion := True
    else if A = '--full' then
      Result.Full := True
    else if A = '--branch' then
      Result.Branch := True
    else if A = '--quiet' then
      Result.Quiet := True
    else if A = '--path' then
      GetValue(Result.Path, '--path')
    else if A = '--file' then
      GetValue(Result.SingleFile, '--file')
    else if A = '--report-sarif' then
      GetValue(Result.ReportSarif, '--report-sarif')
    else if A = '--base-dir' then
      GetValue(Result.BaseDir, '--base-dir')
    else if A = '--custom-rules' then
      GetValue(Result.CustomRules, '--custom-rules')
    else
    begin
      Result.ParseError := Format('Unbekannter Switch: %s', [A]);
      Errored := True;
    end;
    Inc(i);
  end;
  if Errored then Exit;

  // Konsistenz-Pruefung: genau eine Eingabe-Quelle muss gesetzt sein.
  if (Result.Path = '') and (Result.SingleFile = '') and
     not Result.Help and not Result.ShowVersion then
  begin
    Result.ParseError := 'Weder --path noch --file angegeben';
    Exit;
  end;

  if (Result.Path <> '') and (Result.SingleFile <> '') then
  begin
    Result.ParseError := '--path und --file sind exklusiv';
    Exit;
  end;

  // --branch braucht --path (Branch-Diff laeuft per Repo-Root)
  if Result.Branch and (Result.Path = '') then
  begin
    Result.ParseError := '--branch braucht --path';
    Exit;
  end;

  // --full / --branch sind exklusiv; ohne beide bei --path = Default --full
  if Result.Full and Result.Branch then
  begin
    Result.ParseError := '--full und --branch sind exklusiv';
    Exit;
  end;
  if (Result.Path <> '') and not Result.Full and not Result.Branch then
    Result.Full := True;

  // BaseDir defaulten auf Path bzw. Dir der SingleFile
  if Result.BaseDir = '' then
  begin
    if Result.Path <> '' then
      Result.BaseDir := Result.Path
    else if Result.SingleFile <> '' then
      Result.BaseDir := ExtractFilePath(Result.SingleFile);
  end;
end;

class function TConsoleRunner.ParseSysArgs: TCliArgs;
var
  Args : TArray<string>;
  i    : Integer;
begin
  SetLength(Args, ParamCount);
  for i := 1 to ParamCount do
    Args[i - 1] := ParamStr(i);
  Result := ParseArgs(Args);
end;

{ ---- Help / Version ---- }

class procedure TConsoleRunner.WriteHelp;
begin
  WriteLn(SCA_TOOLNAME, ' v', SCA_VERSION, ' - Headless CLI');
  WriteLn('');
  WriteLn('Usage:');
  WriteLn('  analyser.exe --path <dir> [--full|--branch] [--report-sarif <file>]');
  WriteLn('  analyser.exe --file <path.pas> [--report-sarif <file>]');
  WriteLn('');
  WriteLn('Input:');
  WriteLn('  --path <dir>          Project root, recursive scan (default mode = --full)');
  WriteLn('  --file <pas>          Single .pas file');
  WriteLn('');
  WriteLn('Scope (mit --path):');
  WriteLn('  --full                Recursive (default if neither flag set)');
  WriteLn('  --branch              Only VCS-changed files (Git/SVN auto-detected)');
  WriteLn('');
  WriteLn('Output:');
  WriteLn('  --report-sarif <file> Write SARIF v2.1.0 report to <file>');
  WriteLn('  --base-dir <dir>      Make file paths in report relative to <dir>');
  WriteLn('                        (default = --path)');
  WriteLn('  --quiet               Suppress per-finding stdout output');
  WriteLn('');
  WriteLn('Custom rules:');
  WriteLn('  --custom-rules <yml>  Load project-specific rules from YAML file');
  WriteLn('                        (regex/substring/word patterns, see');
  WriteLn('                         examples/analyser-rules.yml)');
  WriteLn('');
  WriteLn('Other:');
  WriteLn('  --help, -h, -?, /?    Show this help');
  WriteLn('  --version             Print version and exit');
  WriteLn('');
  WriteLn('Exit codes:');
  WriteLn('   0 = clean');
  WriteLn('   1 = hints only');
  WriteLn('   2 = warnings present');
  WriteLn('   3 = errors present');
  WriteLn('   4 = read errors (parser/IO)');
  WriteLn('  99 = tool error (bad args, missing path, ...)');
  WriteLn('');
  WriteLn('Switch syntax: both "--key value" and "--key=value" are accepted.');
end;

class procedure TConsoleRunner.WriteVersion;
begin
  WriteLn(SCA_TOOLNAME, ' v', SCA_VERSION);
end;

{ ---- Run ---- }

class function TConsoleRunner.Run(const Args: TCliArgs): Integer;
var
  Findings  : TObjectList<TLeakFinding>;
  Files     : TStringList;
  RepoInfo  : string;
  Settings  : TRepoSettings;
begin
  // Sofort-Exits
  if Args.ParseError <> '' then
  begin
    WriteLn(ErrOutput, 'Error: ', Args.ParseError);
    WriteLn(ErrOutput, 'Try --help for usage.');
    Exit(Integer(cecToolError));
  end;
  if Args.Help    then begin WriteHelp;    Exit(Integer(cecClean)); end;
  if Args.ShowVersion then begin WriteVersion; Exit(Integer(cecClean)); end;

  // Pfad-Validierung
  if (Args.Path <> '') and not TDirectory.Exists(Args.Path) then
  begin
    WriteLn(ErrOutput, 'Error: Pfad existiert nicht: ', Args.Path);
    Exit(Integer(cecToolError));
  end;
  if (Args.SingleFile <> '') and not TFile.Exists(Args.SingleFile) then
  begin
    WriteLn(ErrOutput, 'Error: Datei existiert nicht: ', Args.SingleFile);
    Exit(Integer(cecToolError));
  end;

  Findings := nil;
  Files    := nil;
  Settings := nil;
  try
    // Custom-Rules laden BEVOR die Analyse startet (uStaticAnalyzer2
    // ruft TCustomRuleDetector.AnalyzeFile pro Datei auf - HasRules-Check
    // sorgt dafuer dass ohne --custom-rules nichts passiert).
    if Args.CustomRules <> '' then
    begin
      if not TFile.Exists(Args.CustomRules) then
      begin
        WriteLn(ErrOutput, 'Error: Custom-Rules-Datei existiert nicht: ',
                Args.CustomRules);
        Exit(Integer(cecToolError));
      end;
      try
        TCustomRuleDetector.LoadFromYaml(Args.CustomRules);
        if not Args.Quiet then
          WriteLn(Format('Loaded %d custom rule(s) from %s',
            [TCustomRuleDetector.RuleCount, Args.CustomRules]));
      except
        on E: Exception do
        begin
          WriteLn(ErrOutput, 'Custom rules error: ', E.Message);
          Exit(Integer(cecToolError));
        end;
      end;
    end
    else
      // Sicherheitshalber Reset - falls vorheriger CLI-Run im selben Prozess
      // Rules zurueckgelassen hat (relevant wenn Tests den Runner mehrfach
      // aufrufen).
      TCustomRuleDetector.ClearRules;

    try
      // Branch-Mode: VCS-geaenderte Dateien ermitteln, dann analysieren
      if Args.Branch then
      begin
        Settings := TRepoSettings.Create;
        try Settings.Load; except end;
        Files := TVcsChanges.GetChangedPasFilesAuto(Args.Path, RepoInfo, Settings);
        if (Files = nil) or (Files.Count = 0) then
        begin
          if not Args.Quiet then
            WriteLn('No VCS-changed .pas files found. ', RepoInfo);
          Exit(Integer(cecClean));
        end;
        if not Args.Quiet then
          WriteLn(Format('Analyzing %d changed file(s). %s', [Files.Count, RepoInfo]));
        Findings := TStaticAnalyzer2.AnalyzeLeaksFromList(Files);
      end
      // Single-File-Mode
      else if Args.SingleFile <> '' then
      begin
        if not Args.Quiet then
          WriteLn('Analyzing: ', Args.SingleFile);
        Findings := TStaticAnalyzer2.AnalyzeLeaks(Args.SingleFile);
      end
      // Full-Recursive-Mode
      else
      begin
        if not Args.Quiet then
          WriteLn('Analyzing recursively: ', Args.Path);
        Findings := TStaticAnalyzer2.AnalyzeLeaksRecursive(Args.Path);
      end;
    except
      on E: Exception do
      begin
        WriteLn(ErrOutput, 'Tool error: ', E.ClassName, ': ', E.Message);
        Exit(Integer(cecToolError));
      end;
    end;

    if Findings = nil then
      Findings := TObjectList<TLeakFinding>.Create(True);

    // SARIF-Output (wenn angefordert)
    if Args.ReportSarif <> '' then
    begin
      try
        TSARIFWriter.WriteFile(Args.ReportSarif, Findings, Args.BaseDir,
                               SCA_VERSION, SCA_TOOLNAME);
        if not Args.Quiet then
          WriteLn('SARIF report written: ', Args.ReportSarif);
      except
        on E: Exception do
        begin
          WriteLn(ErrOutput, 'SARIF write error: ', E.Message);
          Exit(Integer(cecToolError));
        end;
      end;
    end;

    WriteSummary(Findings, Args.Quiet);
    Result := CalcExitCode(Findings);
  finally
    Findings.Free;
    Files.Free;
    Settings.Free;
  end;
end;

class function TConsoleRunner.RunFromCmdLine: Integer;
begin
  Result := Run(ParseSysArgs);
end;

{ ---- Output ---- }

class procedure TConsoleRunner.WriteSummary(
  const Findings: TObjectList<TLeakFinding>; Quiet: Boolean);
var
  F             : TLeakFinding;
  CntErr        : Integer;
  CntWarn       : Integer;
  CntHint       : Integer;
  CntFileErr    : Integer;
begin
  CntErr     := 0;
  CntWarn    := 0;
  CntHint    := 0;
  CntFileErr := 0;
  for F in Findings do
  begin
    if F.Kind = fkFileReadError then Inc(CntFileErr)
    else case F.Severity of
      lsError   : Inc(CntErr);
      lsWarning : Inc(CntWarn);
      lsHint    : Inc(CntHint);
    end;
  end;

  if not Quiet then
  begin
    WriteLn('');
    for F in Findings do
      WriteLn(Format('%s  %s:%s  %s  %s',
        [F.SeverityText, F.FileName, F.LineNumber,
         KindName(F.Kind), F.MissingVar]));
    WriteLn('');
  end;

  WriteLn(Format('Summary: %d Error(s), %d Warning(s), %d Hint(s), %d Read Error(s)',
    [CntErr, CntWarn, CntHint, CntFileErr]));
end;

class function TConsoleRunner.CalcExitCode(
  const Findings: TObjectList<TLeakFinding>): Integer;
var
  F          : TLeakFinding;
  HasErr     : Boolean;
  HasWarn    : Boolean;
  HasHint    : Boolean;
  HasFileErr : Boolean;
begin
  HasErr     := False;
  HasWarn    := False;
  HasHint    := False;
  HasFileErr := False;
  for F in Findings do
  begin
    if F.Kind = fkFileReadError then HasFileErr := True
    else case F.Severity of
      lsError   : HasErr  := True;
      lsWarning : HasWarn := True;
      lsHint    : HasHint := True;
    end;
  end;
  // Reihenfolge: Errors > Warnings > Hints > FileErrors > Clean
  if HasErr     then Exit(Integer(cecErrors));
  if HasWarn    then Exit(Integer(cecWarnings));
  if HasHint    then Exit(Integer(cecHints));
  if HasFileErr then Exit(Integer(cecReadErrors));
  Result := Integer(cecClean);
end;

end.
