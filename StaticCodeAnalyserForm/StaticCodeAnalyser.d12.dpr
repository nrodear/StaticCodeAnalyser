program StaticCodeAnalyser.d12;

// GUI-AppType (kein {$APPTYPE CONSOLE}): Windows allokiert KEINE Konsole
// beim Start. Damit kein schwarzes cmd-Fenster beim Doppelklick.
//
// Im CLI-Mode haengen wir uns ueber AttachConsole(ATTACH_PARENT_PROCESS)
// an die schon offene Konsole des Aufrufers an (typisch: cmd.exe oder ein
// CI-Runner). Nicht umgeleitete Streams gehen auf CONOUT$; UMGELEITETE
// Streams (Pipe / '> log.txt') werden an ihre geerbten Std-Handles
// gebunden und landen im Redirect-Ziel (siehe AttachToParentConsole).
//
// Bekannter Schoenheitsfehler: der cmd-Prompt kommt sofort zurueck bevor
// die letzte Output-Zeile sichtbar ist (Windows-Quirk fuer GUI-Subsystem-
// Programme die nachtraeglich AttachConsole rufen). Wer es absolut blockend
// braucht, ruft 'start /wait analyser.exe ...' oder pipt nach 'more'.
// CI-Runner (PowerShell, GH Actions) sehen das nicht - die loggen synchron.

// Build-Hygiene (2026-07-04): die Scan-Fixtures (MeineUnit, uCustomerForm,
// uOrderForm, ConcatToFormatSample, WithStatementSample) sind NICHT mehr
// gelinkt - keine Form-Source referenziert sie, sie blaehten nur die
// ausgelieferte EXE auf (uCustomerForm zog FireDAC-DFM-Streaming mit).
// Die Dateien bleiben unter resources\ als reine Scan-Eingaben liegen
// (Self-Scan-Baseline + Demo-Scans lesen sie von Disk, nicht aus der EXE).
uses
  Winapi.Windows,
  Vcl.Forms,
  System.SysUtils,
  MainController in 'sources\MainController.pas',
  uMainForm in 'sources\UI\uMainForm.pas' {Form2},
  uDfmTextViewer in 'sources\UI\uDfmTextViewer.pas',
  uConsoleRunner in 'sources\Console\uConsoleRunner.pas';

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
//
// Redirect-Support (Design-Entscheid 2026-07-05, ersetzt den frueheren
// CONOUT$-only-Trade-Off): ist stdout/stderr beim Start UMGELEITET
// (Pipe oder 'sca.exe > log.txt'), wird das jeweilige TextFile direkt an
// den geerbten Std-Handle gebunden - der Output landet also im Redirect-
// Ziel wie bei jedem normalen Konsolenprogramm. Das funktioniert AUCH
// ohne Parent-Konsole (CI-Runner/mintty, wo AttachConsole fehlschlaegt -
// vorher ging der Output dort komplett verloren). Nicht umgeleitete
// Streams gehen wie bisher auf CONOUT$ der attachten Konsole.
// Fuer den Redirect-Fall bekommt Output einen 64KB-Puffer (P13: statt
// einem WriteFile-Syscall pro 128 Bytes; auf der echten Konsole flusht
// die RTL ohnehin pro Write-Statement, dort bringt der Puffer nichts).
//
// Liefert True wenn irgendein Output-Kanal verfuegbar ist (Konsole
// und/oder Redirect). False nur ohne beides (Doppelklick aus Explorer) -
// dann gehen WriteLns ins Leere, was nicht crash-relevant ist.
var
  // Muss die komplette WriteLn-Lifetime bis zum RTL-Finalization-Close
  // ueberleben -> Programm-globale Variable, kein lokales Array.
  GStdOutTextBuf: array[0..65535] of Byte;

function AttachToParentConsole: Boolean;
const
  ATTACH_PARENT_PROCESS_FLAG = DWORD(-1);

  // True wenn der Std-Handle existiert und KEINE echte Konsole ist
  // (= umgeleitet auf Datei, Pipe oder Geraet wie NUL). GetConsoleMode
  // schlaegt genau fuer Nicht-Konsolen-Handles fehl - deckt damit auch
  // '> NUL' ab, das als FILE_TYPE_CHAR durch einen reinen
  // GetFileType-Check rutschen wuerde (Review 2026-07-05).
  function IsRedirected(AHandle: THandle): Boolean;
  var
    Mode: DWORD;
  begin
    Result := False;
    if (AHandle = 0) or (AHandle = INVALID_HANDLE_VALUE) then Exit;
    Result := not GetConsoleMode(AHandle, Mode);
  end;

  // Bindet ein RTL-TextFile an seinen Std-Handle. AssignFile('') + Rewrite
  // bindet laut RTL (System.TextOpen) adressbasiert: @T=@ErrOutput ->
  // STD_ERROR_HANDLE, sonst STD_OUTPUT_HANDLE. Der explizite Override
  // danach ist dafuer redundant, macht die Bindung aber unabhaengig von
  // dieser Adress-Magie (z.B. falls kuenftig ein drittes TextFile hier
  // durchlaeuft) und dokumentiert die Absicht.
  procedure BindToStdHandle(var T: Text; AStdHandleId: DWORD);
  begin
    AssignFile(T, '');
    Rewrite(T);
    TTextRec(T).Handle := GetStdHandle(AStdHandleId);
  end;

var
  OutRedirected, ErrRedirected, Attached: Boolean;
begin
  OutRedirected := IsRedirected(GetStdHandle(STD_OUTPUT_HANDLE));
  ErrRedirected := IsRedirected(GetStdHandle(STD_ERROR_HANDLE));
  Attached      := AttachConsole(ATTACH_PARENT_PROCESS_FLAG);
  Result        := Attached or OutRedirected or ErrRedirected;
  if not Result then Exit;
  try
    if OutRedirected then
    begin
      BindToStdHandle(Output, STD_OUTPUT_HANDLE);
      SetTextBuf(Output, GStdOutTextBuf);
    end
    else if Attached then
    begin
      // CONOUT$ = Special-File der aktiven Konsole, immer schreibbar
      // solange eine Konsole attached ist.
      AssignFile(Output, 'CONOUT$');
      Rewrite(Output);
    end;

    if ErrRedirected then
      BindToStdHandle(ErrOutput, STD_ERROR_HANDLE)
    else if Attached then
    begin
      AssignFile(ErrOutput, 'CONOUT$');
      Rewrite(ErrOutput);
    end;
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
    // uCustomerForm + uOrderForm (resources\) sind seit 2026-07-04 nicht
    // mehr einkompiliert - reine Scan-Fixtures auf Disk, siehe uses-Kommentar.
    Application.Run;
  end;
end.
