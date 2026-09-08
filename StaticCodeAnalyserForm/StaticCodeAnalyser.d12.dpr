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
  Vcl.Themes,          // TStyleManager - Hell/Dunkel der Standalone-EXE
  Vcl.Styles,          // registriert die gelinkten VCL-Styles
  System.SysUtils,
  MainController in 'sources\MainController.pas',
  uMainForm in 'sources\UI\uMainForm.pas' {Form2},
  uDfmTextViewer in 'sources\UI\uDfmTextViewer.pas',
  uConsoleRunner in 'sources\Console\uConsoleRunner.pas',
  uAppTheme;

{$R *.res}
{$R 'styles\sca_styles.RES'}  // SCADark.vsf (s. styles\README.md)
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
// Nach dem Aufruf sind BEIDE Kanaele gebunden - an ihre Umleitung, an
// die Konsole oder an das Null-Geraet. Ein Rueckgabewert waere nichts
// wert: bis 08.09. lieferte die Routine "True wenn irgendein Kanal
// verfuegbar ist", der einzige Aufrufer hat ihn nie gelesen, und mit
// der NUL-Bindung waere er auch noch falsch geworden (False, obwohl
// jetzt ein Kanal existiert).
//
// ACHTUNG, hier stand bis 08.09. das Gegenteil des Wahren ("nicht
// crash-relevant"): ohne Bindung sind Output und ErrOutput UNGEBUNDEN,
// und ein ungebundenes TextFile laesst unter {$I+} jedes WriteLn
// werfen. Der Lauf starb an seiner ersten Ausgabezeile. Wer die
// NUL-Bindung wieder herausnimmt, holt den Absturz zurueck.
var
  // Muss die komplette WriteLn-Lifetime bis zum RTL-Finalization-Close
  // ueberleben -> Programm-globale Variable, kein lokales Array.
  GStdOutTextBuf: array[0..65535] of Byte;

procedure AttachToParentConsole;
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

  // Bindet EINEN Kanal - und zwar in JEDEM Fall.
  //
  // Bis zum Chargen-Review 08.09. war das eine Alles-oder-nichts-
  // Entscheidung: nur wenn WEDER Konsole NOCH irgendeine Umleitung
  // vorlag, wurde auf NUL ausgewichen. Ist aber genau EINER der beiden
  // Kanaele umgeleitet und keine Konsole attached, blieb der andere
  // ungebunden - und ein ungebundenes TextFile laesst unter {$I+} jedes
  // WriteLn mit EInOutError fliegen.
  //
  // Das ist kein konstruierter Fall: ein Elternprozess ohne Konsole
  // (Dienst, Aufgabenplanung, pythonw.exe) startet die Exe mit
  // stdout=PIPE und laesst stderr, wie es ist. Dann ist OutRedirected
  // True, ErrRedirected und Attached False - und die erste Zeile nach
  // ErrOutput toetet den Lauf. Der aeussere Handler macht daraus 99
  // statt des abgestuften Exit-Codes: die Pipeline sieht einen
  // Werkzeugfehler, wo ein sauberer Lauf war.
  //
  // Jeder Kanal bekommt sein EIGENES try: scheitert die Bindung des
  // einen (kein NUL-Geraet, exotische Sandbox), soll der andere
  // trotzdem zustande kommen.
  procedure BindeKanal(var T: Text; AStdHandleId: DWORD;
    ARedirected, AAttached: Boolean);
  var
    H : THandle;
  begin
    try
      H := GetStdHandle(AStdHandleId);
      if ARedirected then
        BindToStdHandle(T, AStdHandleId)
      else if AAttached then
      begin
        // CONOUT$ = Special-File der aktiven Konsole, immer schreibbar
        // solange eine Konsole attached ist.
        AssignFile(T, 'CONOUT$');
        Rewrite(T);
      end
      else if (H <> 0) and (H <> INVALID_HANDLE_VALUE) then
        // Weder umgeleitet noch selbst attached, aber ein gueltiger
        // Handle: eine GEERBTE Konsole. AttachConsole scheitert dann
        // mit ERROR_ACCESS_DENIED, weil schon eine haengt. Diesen Fall
        // darf der NUL-Zweig unten nicht schlucken - er wuerde eine
        // funktionierende Ausgabe stumm schalten.
        BindToStdHandle(T, AStdHandleId)
      else
      begin
        // Wirklich kein Kanal: auf das Null-Geraet binden, damit die
        // WriteLns ins Leere laufen statt zu werfen. Der Lauf und vor
        // allem die EXIT-CODES funktionieren - genau das, was der
        // Kopfkommentar zusichert.
        AssignFile(T, 'NUL');
        Rewrite(T);
      end;
    except
      // Auch NUL nicht verfuegbar: dann bleibt dieser Kanal ungebunden.
      // Mehr ist hier nicht zu retten; der Exit-Code traegt weiter.
    end;
  end;

var
  OutRedirected, ErrRedirected, Attached: Boolean;
begin
  OutRedirected := IsRedirected(GetStdHandle(STD_OUTPUT_HANDLE));
  ErrRedirected := IsRedirected(GetStdHandle(STD_ERROR_HANDLE));
  Attached      := AttachConsole(ATTACH_PARENT_PROCESS_FLAG);

  BindeKanal(Output, STD_OUTPUT_HANDLE, OutRedirected, Attached);
  // Der 64-KB-Puffer nur fuer den umgeleiteten Normalausgabe-Fall (P13:
  // sonst ein WriteFile-Syscall je 128 Bytes). Auf der echten Konsole
  // flusht die RTL ohnehin pro Write-Statement, und auf NUL waere er
  // sinnlos.
  if OutRedirected then
    SetTextBuf(Output, GStdOutTextBuf);
  BindeKanal(ErrOutput, STD_ERROR_HANDLE, ErrRedirected, Attached);
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
        // Die Meldung ist NACHRANGIG gegenueber dem Exit-Code: bricht
        // der Ausgabekanal genau hier weg (Pipe geschlossen, Platte
        // voll, NUL-Bindung oben fehlgeschlagen), darf das den 99er
        // nicht mitreissen. Ohne dieses innere try flog die Exception
        // aus dem Handler heraus und der Aufrufer bekam einen
        // Laufzeitfehler statt eines auswertbaren Codes.
        CliExitCode := 99;
        try
          WriteLn(ErrOutput, 'Fatal: ', E.ClassName, ': ', E.Message);
        except
          // kein Kanal - der Exit-Code traegt die Information allein
        end;
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
    // Hell/Dunkel VOR CreateForm: sonst entsteht die Form hell und
    // springt sichtbar um. TAppTheme liest die gemerkte Wahl aus
    // analyser.ini ([UI] Theme) und folgt im Auslieferzustand dem
    // Windows-Systemthema. Ist kein dunkler VCL-Style in die EXE gelinkt
    // (Projektoptionen > Anwendung > Erscheinungsbild), bleibt es still
    // beim hellen Systemstil - siehe Kopf von uAppTheme.
    TAppTheme.Initialize;
    // Application.Icon wird von der RTL automatisch aus der MAINICON-
    // Resource gesetzt (siehe <Icon_MainIcon> im dproj -> branding\sca.ico).
    // Keine explizite Zuweisung noetig - canonical Embarcadero-Weg.
    Application.CreateForm(TForm2, Form2);
    // uCustomerForm + uOrderForm (resources\) sind seit 2026-07-04 nicht
    // mehr einkompiliert - reine Scan-Fixtures auf Disk, siehe uses-Kommentar.
    Application.Run;
  end;
end.
