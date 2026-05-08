unit uMainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.ShellAPI, System.SysUtils,
  System.Classes, Vcl.Graphics, System.Generics.Collections,
   Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Grids, uStaticAnalyzer2,
  uMethodd12, uSCAConsts, uFixHint, uClaudePrompt, uLocalization,
  uRepoSettings, uRecentPaths, uFindingGridRenderer,
  Vcl.Controls
 ;

type
  TForm2 = class(TForm)
    Panel1: TPanel;
    Panel2: TPanel;
    Panel3: TPanel;
    Button1: TButton;
    Projectpath: TComboBox;
    Savetofile: TEdit;
    ResultGrid: TStringGrid;
    Label1: TLabel;
    Button2: TButton;
    Button3: TButton;
    Button4: TButton;
    Button6: TButton;
    Button7: TButton;
    StatusBar1: TStatusBar;
    Label3: TLabel;
    Panel4: TPanel;
    procedure Button1Click(Sender: TObject);
    procedure ResultGridClick(Sender: TObject);
    procedure ResultGridDblClick(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure Button4Click(Sender: TObject);
    procedure Button3Click(Sender: TObject);
    procedure Button6Click(Sender: TObject);
    procedure Button7Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ResultGridDrawCell(Sender: TObject; ACol, ARow: Integer;
      Rect: TRect; State: TGridDrawState);
    procedure AppShowHint(var HintStr: string; var CanShow: Boolean;
      var HintInfo: THintInfo);

  private
    // Aktuell angezeigte Befunde - in der Form gehalten, damit ResultGridClick
    // den vollen TLeakFinding (inkl. Kind/Severity-Details) zur ausgewaehlten
    // Zeile findet und einen kompletten Claude-AI-Prompt erzeugen kann.
    FAllFindings : TObjectList<TLeakFinding>;
    // Inner helper: registriert eine bereits geladene Settings-Instanz und
    // setzt optional die Discovery-Listen zurueck. Wird vom Analyse-Pfad
    // direkt benutzt (der die Settings noch fuer UsesCheck/AutoDiscover braucht).
    procedure ApplyDetectorConfig(Settings: TRepoSettings;
      AClearDiscovery: Boolean);
    procedure AnalyseAllClasses(Sender: TObject; const path: string);
    procedure AnalyseSingleFile(const AFilePath: string);
    procedure FillGridFromFindings(Findings: TObjectList<TLeakFinding>;
      const ABaseDir: string);
    function  BuildClaudePrompt(F: TLeakFinding): string;
    function SelectFolder: string;
    function SelectPasFile: string;
    function GetAbsolutePath(const RelativePath: string): string;
    function SelectFile: string;
    procedure LoadRecentPaths;
    procedure SaveRecentPath(const APath: string);
    function  AppPath: string;
    function  RecentIniPath: string;
    procedure NavigateDelphiToLine(LineNo: Integer);
  public
  end;

var
  Form2: TForm2;

implementation

uses
  clipbrd, uStaticFiles;

{$R *.dfm}

procedure TForm2.FormCreate(Sender: TObject);
var
  Settings: TRepoSettings;
begin
  // UI-Sprache aus analyser.ini [UI]/Language - MUSS vor den ersten
  // _()-Aufrufen passieren. Kurzlebige Settings-Instanz nur fuer den
  // Language-Read; volle Settings sind im Standalone nicht noetig.
  Settings := TRepoSettings.Create;
  try
    try Settings.Load; except end;
    SetLanguage(Settings.Language);
  finally
    Settings.Free;
  end;
  ResultGrid.Cells[0, 0] := _('File');
  ResultGrid.Cells[1, 0] := _('Method');
  ResultGrid.Cells[2, 0] := _('Line');
  ResultGrid.Cells[3, 0] := _('Detail');
  ResultGrid.Cells[4, 0] := _('Severity');
  ResultGrid.OnDrawCell := ResultGridDrawCell;
  ResultGrid.OnDblClick := ResultGridDblClick;
  // Tooltip nur fuer Datei-Spalte, dynamisch ueber Application.OnShowHint.
  // Hint muss != '' sein damit VCL das Event ueberhaupt feuert -
  // AppShowHint setzt dann den echten Text aus der Zelle (oder canceled).
  ResultGrid.ParentShowHint := False;
  ResultGrid.ShowHint := True;
  ResultGrid.Hint := ' ';
  Application.HintPause      := 100;
  Application.HintShortPause := 100;
  Application.OnShowHint     := AppShowHint;
  // Owner-list - der Lifetime der TLeakFinding-Instanzen ist an die Form gekoppelt.
  FAllFindings := TObjectList<TLeakFinding>.Create(True);
  LoadRecentPaths;
end;

procedure TForm2.FormDestroy(Sender: TObject);
begin
  // Globalen Application.OnShowHint loesen damit kein dangling Methodenzeiger
  // ueberlebt wenn das Form zerstoert wird (relevant beim IDE-Plugin-Hosting).
  if TMethod(Application.OnShowHint).Data = Self then
    Application.OnShowHint := nil;
  FreeAndNil(FAllFindings);
end;

procedure TForm2.AppShowHint(var HintStr: string; var CanShow: Boolean;
  var HintInfo: THintInfo);
// Globaler Hint-Filter - feuert vor jedem Tooltip im Application-Scope.
// Wir lassen den Hint nur fuer Spalte 0 des ResultGrid durch und setzen
// CursorRect auf die aktuelle Zelle, damit VCL das Event neu feuert sobald
// die Maus die Zelle verlaesst (sonst bleibt der alte Tooltip kleben).
var
  ACol, ARow : Integer;
begin
  if HintInfo.HintControl <> ResultGrid then Exit;

  ResultGrid.MouseToCell(HintInfo.CursorPos.X, HintInfo.CursorPos.Y,
    ACol, ARow);
  if (ACol = 0) and (ARow >= 1) and (ARow < ResultGrid.RowCount) and
     (ResultGrid.Cells[0, ARow] <> '') then
  begin
    HintStr               := ResultGrid.Cells[0, ARow];
    HintInfo.CursorRect   := ResultGrid.CellRect(ACol, ARow);
    HintInfo.HintMaxWidth := 600;
    CanShow               := True;
  end
  else
    CanShow := False;
end;

procedure TForm2.ResultGridDrawCell(Sender: TObject; ACol, ARow: Integer;
  Rect: TRect; State: TGridDrawState);
// Implementation in UI/uFindingGridRenderer.pas - hier nur die Standalone-
// Konfiguration: Severity-Spalte 4, kein Theme/Zebra/Sort/Accent-Bar
// (Standalone-Look ist bewusst einfach, hardcoded Pastell-Pasteltoene).
begin
  TFindingGridRenderer.DrawCell(Sender, ACol, ARow, Rect, State,
    TFindingGridRenderer.StandaloneConfig);
end;

procedure TForm2.Button1Click(Sender: TObject);
begin
  Close;
end;

procedure TForm2.Button2Click(Sender: TObject);
begin
  Projectpath.Text := SelectFolder;
end;

procedure TForm2.Button3Click(Sender: TObject);
begin
  Savetofile.Text := GetAbsolutePath(SelectFile);
end;

procedure TForm2.Button4Click(Sender: TObject);
var
  lines: TStringList;
  i: Integer;
begin
  lines := TStringList.Create;
  try
    lines.Add('Datei;Methode;Zeile;Variable;Schweregrad');
    for i := 1 to ResultGrid.RowCount - 1 do
      if ResultGrid.Cells[0, i] <> '' then
        lines.Add(
          ResultGrid.Cells[0, i] + ';' +
          ResultGrid.Cells[1, i] + ';' +
          ResultGrid.Cells[2, i] + ';' +
          ResultGrid.Cells[3, i] + ';' +
          ResultGrid.Cells[4, i]
        );
    lines.SaveToFile(GetAbsolutePath(Savetofile.Text));
    StatusBar1.SimpleText := _('Saved: ') + GetAbsolutePath(Savetofile.Text);
  finally
    lines.Free;
  end;
end;

procedure TForm2.Button6Click(Sender: TObject);
begin
  if not TStaticFiles.ValidatePath(Projectpath.Text) then
  begin
    ShowMessage(_('Please provide a valid project path.'));
    Exit;
  end;
  SaveRecentPath(Projectpath.Text);
  AnalyseAllClasses(Sender, Projectpath.Text);
end;

procedure TForm2.Button7Click(Sender: TObject);
// Datei-Analyse: Datei-Dialog -> AnalyseSingleFile mit allen Detektoren.
var
  filePath: string;
begin
  filePath := SelectPasFile;
  if filePath = '' then Exit; // User hat abgebrochen
  AnalyseSingleFile(filePath);
end;

function TForm2.SelectPasFile: string;
var
  Dlg: TOpenDialog;
begin
  Result := '';
  Dlg := TOpenDialog.Create(nil);
  try
    Dlg.Title  := _('Select Pascal file to analyse');
    Dlg.Filter := _('Pascal file (*.pas)|*.pas|All files|*.*');
    Dlg.DefaultExt := 'pas';
    // Startverzeichnis aus aktuellem Projektpfad
    if (Projectpath.Text <> '') and DirectoryExists(Projectpath.Text) then
      Dlg.InitialDir := Projectpath.Text;
    if Dlg.Execute then
      Result := Dlg.FileName;
  finally
    Dlg.Free;
  end;
end;

procedure TForm2.ApplyDetectorConfig(Settings: TRepoSettings;
  AClearDiscovery: Boolean);
begin
  try
    Settings.RegisterToLeakyClasses;
    Settings.ApplyDetectorThresholds;
    AutoDiscoverCustomClasses := Settings.AutoDiscoverClasses;
    if AClearDiscovery then
    begin
      // Discovery-Treffer aus vorherigen Laeufen verwerfen, sonst landen
      // sie mit-persistiert in LeakyClassesDiscover.log.
      if Assigned(uSCAConsts.DiscoveredClasses) then
        uSCAConsts.DiscoveredClasses.Clear;
      if Assigned(uSCAConsts.DiscoveredStaticClasses) then
        uSCAConsts.DiscoveredStaticClasses.Clear;
    end;
  except
    // INI-Wert defekt darf den Lauf nicht abbrechen.
  end;
end;

procedure TForm2.AnalyseAllClasses(Sender: TObject; const path: string);
var
  Settings: TRepoSettings;
  findings: TObjectList<TLeakFinding>;
begin
  Screen.Cursor := crHourglass;
  Settings := TRepoSettings.Create;
  try
    try Settings.Load; except end;
    // Custom-LeakyClasses + Excludes in die globalen Listen ziehen,
    // AutoDiscover-Flag durchreichen. MUSS vor dem Analyzer-Aufruf
    // passieren, sonst landet TMeineKlasse & Co. nie in LeakyClasses.
    ApplyDetectorConfig(Settings, True);

    StatusBar1.SimpleText := _('Checking all classes...');
    Application.ProcessMessages;

    // Frueher: TStaticAnalyzer.AnalyzeAllClassesRecursive (uParser-basiert,
    // nur MemoryLeak + EmptyExcept). Jetzt: TStaticAnalyzer2 ueber alle 21
    // Detektoren - dieselbe Pipeline wie "Aktuelle Datei" und das IDE-Plugin.
    findings := TStaticAnalyzer2.AnalyzeLeaksRecursive(path,
      nil, Settings.UsesCheck);
    try
      FillGridFromFindings(findings, path);
    finally
      findings.Free;
    end;

    // Discovery-Treffer in INI persistieren (nur wenn aktiviert).
    if Settings.AutoDiscoverClasses then
      try Settings.PersistDiscoveredClasses; except end;
  finally
    Settings.Free;
    Screen.Cursor := crDefault;
  end;
end;

procedure TForm2.AnalyseSingleFile(const AFilePath: string);
// Analysiert eine einzelne Datei mit allen Detektoren des AST-basierten
// Analyzers (TStaticAnalyzer2) - ergibt zusaetzlich zu Memory-Leaks auch
// Code-Smells, NilDeref, MagicNumber, DuplicateBlock etc.
var
  Settings: TRepoSettings;
  findings: TObjectList<TLeakFinding>;
begin
  if not FileExists(AFilePath) then
  begin
    ShowMessage(_('File not found: ') + AFilePath);
    Exit;
  end;

  // nil-init ist wichtig: wenn AnalyzeLeaks crasht BEVOR die Liste
  // zugewiesen wird, sehen wir ungueltigen Speicher im finally.
  findings := nil;
  Screen.Cursor := crHourglass;
  Settings := TRepoSettings.Create;
  try
    try Settings.Load; except end;
    ApplyDetectorConfig(Settings, True);

    StatusBar1.SimpleText := _('Analysing: ') + ExtractFileName(AFilePath);
    Application.ProcessMessages;

    try
      try
        findings := TStaticAnalyzer2.AnalyzeLeaks(AFilePath,
          Settings.UsesCheck);
      except
        on E: Exception do
        begin
          ShowMessage(_('Analysis error: ') + E.Message);
          Exit;
        end;
      end;

      if Assigned(findings) then
        FillGridFromFindings(findings, ExtractFilePath(AFilePath));
    finally
      findings.Free;
    end;

    if Settings.AutoDiscoverClasses then
      try Settings.PersistDiscoveredClasses; except end;
  finally
    Settings.Free;
    Screen.Cursor := crDefault;
  end;
end;

procedure TForm2.FillGridFromFindings(Findings: TObjectList<TLeakFinding>;
  const ABaseDir: string);
// Gemeinsame Befuell-Logik fuer Single-File- und Recursive-Analyse.
// Uebernimmt die Findings ins FAllFindings-Feld (damit ResultGridClick
// per row-Index den vollen Befund findet). ABaseDir steuert den
// relativ angezeigten Datei-Pfad in Spalte 0.
var
  f       : TLeakFinding;
  i       : Integer;
  baseDir : string;
begin
  ResultGrid.RowCount := 2;
  ResultGrid.Rows[1].Clear;

  // Alte Befunde entsorgen, neue uebernehmen. OwnsObjects=False auf der
  // Eingangsliste verhindert dass deren Free die Items mit-freigibt.
  FAllFindings.Clear;
  if Assigned(Findings) then
  begin
    Findings.OwnsObjects := False;
    for i := 0 to Findings.Count - 1 do
      FAllFindings.Add(Findings[i]);
  end;

  if FAllFindings.Count = 0 then
  begin
    ResultGrid.Cells[0, 1] := _('No findings.');
    StatusBar1.SimpleText  := _('Done. No findings.');
    Exit;
  end;

  baseDir := IncludeTrailingPathDelimiter(ABaseDir);
  ResultGrid.RowCount := FAllFindings.Count + 1;
  for i := 0 to FAllFindings.Count - 1 do
  begin
    f := FAllFindings[i];
    ResultGrid.Cells[0, i + 1] := ExtractRelativePath(baseDir, f.FileName);
    ResultGrid.Cells[1, i + 1] := f.MethodName;
    ResultGrid.Cells[2, i + 1] := f.LineNumber;
    ResultGrid.Cells[3, i + 1] := f.MissingVar;
    ResultGrid.Cells[4, i + 1] := f.SeverityText;
  end;
  StatusBar1.SimpleText := Format(_('Done. %d findings. Click a row -> ' +
    'AI prompt on clipboard.'), [FAllFindings.Count]);
end;

procedure TForm2.ResultGridDblClick(Sender: TObject);
var
  row: Integer;
  relPath, absPath: string;
  lineNo: Integer;
begin
  row := ResultGrid.Row;
  if row < 1 then Exit;
  relPath := ResultGrid.Cells[0, row];
  if relPath = '' then Exit;
  lineNo := StrToIntDef(ResultGrid.Cells[2, row], 0);
  absPath := IncludeTrailingPathDelimiter(Projectpath.Text) + relPath;
  if not FileExists(absPath) then
  begin
    StatusBar1.SimpleText := _('File not found: ') + absPath;
    Exit;
  end;
  ShellExecute(Handle, 'open', PChar(absPath), nil, nil, SW_SHOWNORMAL);
  if lineNo > 0 then
  begin
    Sleep(800); // Delphi IDE Zeit geben, die Datei zu oeffnen
    NavigateDelphiToLine(lineNo);
  end;
  StatusBar1.SimpleText := Format(_('Opened: %s  Line: %d'), [relPath, lineNo]);
end;

procedure TForm2.NavigateDelphiToLine(LineNo: Integer);
var
  BDSWnd: HWND;
  lineStr: string;
  i: Integer;
  inp: TInput;
  vk: Word;
begin
  // Belt-and-suspenders: ohne Ziel-Zeile wuerde ein Ctrl+G Dialog leer
  // bestaetigt und die IDE haengt mit einem offenen Dialog herum.
  if LineNo <= 0 then Exit;
  BDSWnd := FindWindow('TAppBuilder', nil);
  if BDSWnd = 0 then Exit;
  SetForegroundWindow(BDSWnd);
  Sleep(150);
  // Ctrl+G = Search > Go to Line Number
  ZeroMemory(@inp, SizeOf(inp));
  inp.Itype := INPUT_KEYBOARD;
  inp.ki.wVk := VK_CONTROL;
  SendInput(1, inp, SizeOf(TInput));
  inp.ki.wVk := Ord('G');
  SendInput(1, inp, SizeOf(TInput));
  inp.ki.dwFlags := KEYEVENTF_KEYUP;
  SendInput(1, inp, SizeOf(TInput));
  inp.ki.wVk := VK_CONTROL;
  SendInput(1, inp, SizeOf(TInput));
  Sleep(200);
  // Zeilennummer eintippen
  lineStr := IntToStr(LineNo);
  for i := 1 to Length(lineStr) do
  begin
    vk := VkKeyScan(lineStr[i]) and $FF;
    ZeroMemory(@inp, SizeOf(inp));
    inp.Itype := INPUT_KEYBOARD;
    inp.ki.wVk := vk;
    SendInput(1, inp, SizeOf(TInput));
    inp.ki.dwFlags := KEYEVENTF_KEYUP;
    SendInput(1, inp, SizeOf(TInput));
  end;
  Sleep(50);
  ZeroMemory(@inp, SizeOf(inp));
  inp.Itype := INPUT_KEYBOARD;
  inp.ki.wVk := VK_RETURN;
  SendInput(1, inp, SizeOf(TInput));
  inp.ki.dwFlags := KEYEVENTF_KEYUP;
  SendInput(1, inp, SizeOf(TInput));
end;

procedure TForm2.ResultGridClick(Sender: TObject);
// Bei Klick auf eine Befund-Zeile: kompletten Markdown-Block fuer Claude AI
// in die Zwischenablage schreiben. Enthaelt Befund-Metadaten, Loesungs-Hinweis
// (Vorher/Nachher) und Code-Kontext aus der Quelldatei.
var
  idx : Integer;
  F   : TLeakFinding;
begin
  idx := ResultGrid.Row - 1; // 0-basiert: Zeile 0 ist Header
  if (idx < 0) or (idx >= FAllFindings.Count) then Exit;
  F := FAllFindings[idx];
  Clipboard.AsText := BuildClaudePrompt(F);
  StatusBar1.SimpleText := Format(
    _('AI prompt copied to clipboard: %s, line %s (%s)'),
    [ExtractFileName(F.FileName), F.LineNumber, F.SeverityText]);
end;

function TForm2.BuildClaudePrompt(F: TLeakFinding): string;
// Thin-Wrapper. Logik ist in uClaudePrompt zentralisiert (war zuvor 1:1
// dupliziert mit dem IDE-Plugin).
begin
  Result := TClaudePrompt.Build(F);
end;

function TForm2.SelectFolder: string;
var
  OpenDialog: TFileOpenDialog;
begin
  Result := '';
  OpenDialog := TFileOpenDialog.Create(nil);
  try
    OpenDialog.Options := [fdoPickFolders, fdoPathMustExist, fdoForceFileSystem];
    OpenDialog.Title := _('Choose folder');
    if OpenDialog.Execute then
      Result := OpenDialog.FileName;
  finally
    OpenDialog.Free;
  end;
end;

function TForm2.GetAbsolutePath(const RelativePath: string): string;
begin
  Result := RelativePath;
  if ExtractFileDrive(RelativePath) <> '' then
    Exit;
  Result := ExpandFileName(RelativePath);
end;

function TForm2.SelectFile: string;
var
  OpenDialog: TOpenDialog;
begin
  Result := '';
  OpenDialog := TOpenDialog.Create(nil);
  try
    OpenDialog.Title := _('Save results');
    OpenDialog.Filter := _('CSV files|*.csv|Log files|*.log');
    OpenDialog.FileName := 'analyse_all.csv';
    if OpenDialog.Execute then
      Result := OpenDialog.FileName;
  finally
    OpenDialog.Free;
  end;
end;

// Recent Paths -- duenne Wrapper um TRecentPaths (Common/uRecentPaths.pas).
// Pinned-Eintrag = App-Pfad neben der EXE, Position end.
function TForm2.AppPath: string;
begin
  Result := ExcludeTrailingPathDelimiter(ExtractFilePath(Application.ExeName));
end;

function TForm2.RecentIniPath: string;
begin
  Result := ChangeFileExt(Application.ExeName, '.ini');
end;

procedure TForm2.LoadRecentPaths;
begin
  // Wenn die INI defekt ist (Disk-Voll, ACL, manuelles Editieren) darf
  // der FormCreate nicht crashen - dann startet die App ohne MRU.
  try
    TRecentPaths.Load(
      Projectpath, RecentIniPath,
      DEFAULT_MAX_RECENT,
      AppPath, ppLast);
  except
    Projectpath.Items.Clear;
    Projectpath.Text := '';
  end;
end;

procedure TForm2.SaveRecentPath(const APath: string);
begin
  TRecentPaths.Save(
    Projectpath, RecentIniPath, APath,
    DEFAULT_MAX_RECENT,
    AppPath, ppLast);
end;

end.
