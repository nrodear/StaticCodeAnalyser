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

// Stack-Size erhoeht von 1 MB (Default) auf 32 MB. Detektoren walken
// rekursiv durchs AST (uDeepNesting.Walk, uCyclomaticComplexity.Walk,
// ...). Bei tief verschachteltem Real-World-Code (JvId3v2.pas mit langen
// if-then-else-Ketten) sprengt der Default-Stack. Audit-Trigger:
// 'D:/git-sca-realworld/jvcl' segfault mit --quiet --report-sarif.
{$MAXSTACKSIZE 33554432}    // 32 MB Maximum
{$MINSTACKSIZE 4194304}     // 4  MB Initial-Reserve

uses
  Winapi.Windows,
  Vcl.Forms,
  System.SysUtils,
  MeineUnit in 'resources\MeineUnit.pas',
  MainController in 'sources\MainController.pas',
  uMainForm in 'sources\UI\uMainForm.pas' {Form2},
  uDfmTextViewer in 'sources\UI\uDfmTextViewer.pas',
  uConsoleRunner in 'sources\Console\uConsoleRunner.pas',
  uCustomerForm in 'resources\uCustomerForm.pas' {CustomerForm},
  uOrderForm in 'resources\uOrderForm.pas' {OrderForm},
  ConcatToFormatSample in 'resources\ConcatToFormatSample.pas',
  WithStatementSample in 'resources\WithStatementSample.pas';

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
  //
  // Bekannter Trade-Off: CONOUT$ ignoriert stdout/stderr-Redirects (Pipe
  // oder 'sca.exe > log.txt'). Wer Output in eine Datei braucht, soll
  // detector-specific File-Flags nutzen (z.B. --time-detectors-out FILE).
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
