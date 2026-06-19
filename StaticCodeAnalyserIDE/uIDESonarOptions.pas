unit uIDESonarOptions;

// Tools > Options > Third Party > "Sonar Integration"
//
// Eigene Options-Page neben "Static Code Analyser" (uIDESCAOptions). Bindet
// gegen den selben analyser.ini-Store, Section [Sonar] + [SonarTokens].
// Token wird ueber DPAPI verschluesselt (uSonarConfig.StoreToken).
//
// Felder:
//   * HostUrl       (URL-Validierung beim Speichern)
//   * ProjectKey    (mit "Detect from project"-Button -> liest aus
//                    sonar-project.properties im aktuellen Projekt-Pfad)
//   * Token         (PasswordChar, leerer Edit = vorhandenes Token unveraendert)
//   * Branch        (optional, leer = main)
//   * Insecure-TLS  (Checkbox)
//
// Buttons:
//   * "Test Connection"  - ruft TSonarHealthCheck.Run und zeigt Modal-Dialog
//   * "Open INI"         - oeffnet analyser.ini im Default-Editor
//
// Statusbar-Indikator (klein, im Plugin selbst - nicht in dieser Page):
// gruen/gelb/rot je nach letztem Health-Check (Tooltip mit Timestamp).

interface

uses
  Winapi.Messages,                                    // TMessage / CM_STYLECHANGED
  System.Classes, System.SysUtils, System.UITypes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Dialogs,
  ToolsAPI,
  uIDEAddInOptionsBase,    // gemeinsame Basis fuer INTAAddInOptions-Adapter
  uLocalization,           // _() i18n-Wrapper (analog uIDESCAOptions)
  uSonarConfig;

type
  TSonarOptionsFrame = class(TFrame)
    grpServer        : TGroupBox;
    lblHost          : TLabel;
    edHost           : TEdit;
    lblProject       : TLabel;
    edProject        : TEdit;
    btnDetectProject : TButton;
    lblBranch        : TLabel;
    edBranch         : TEdit;
    chkInsecure      : TCheckBox;

    grpAuth          : TGroupBox;
    lblToken         : TLabel;
    edToken          : TEdit;
    lblTokenInfo     : TLabel;
    btnRevealToken   : TButton;

    grpActions       : TGroupBox;
    btnTest          : TButton;
    btnOpenIni       : TButton;
    memoResult       : TMemo;
  private
    FOriginalToken : string;   // beim Laden gemerkt; '' = leer beibehalten
    FIniPath       : string;
    procedure BuildControls;
    procedure DetectProjectClick(Sender: TObject);
    procedure TestConnectionClick(Sender: TObject);
    procedure RevealTokenClick(Sender: TObject);
    procedure OpenIniClick(Sender: TObject);
    // VCL-Style-Wechsel via Application.Broadcast - belt-and-suspenders
    // zum TIDETheme-Subscribe (TSonarAddInOptions.OnThemeChanged).
    procedure CMStyleChanged(var Message: TMessage); message CM_STYLECHANGED;
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadFromIni(const IniPath: string);
    procedure SaveToIni(const IniPath: string);
  end;

  // Boilerplate (FFrame/FThemeSub, FrameCreated, DialogClosed, OnThemeChanged,
  // ValidateContents, GetHelpContext, IncludeInIDEInsight, GetArea) lebt in
  // TIDEAddInOptionsBase. Hier nur die Sonar-spezifischen Hooks.
  TSonarAddInOptions = class(TIDEAddInOptionsBase)
  protected
    procedure DoLoadFrame(AFrame: TCustomFrame); override;
    procedure DoSaveFrame(AFrame: TCustomFrame); override;
  public
    function GetCaption: string; override;
    function GetFrameClass: TCustomFrameClass; override;
  end;

procedure RegisterSonarAddInOptions;
procedure UnregisterSonarAddInOptions;

implementation

// noinspection-file BeginEndRequired, BooleanParam, CanBeClassMethod, ClassPerFile, DebugOutput, DuplicateString, EmptyExcept, GodClass, GroupedDeclaration, HardcodedString, IfElseBegin, LongMethod, MultipleExit, NilComparison, PublicMemberWithoutDoc, TooLongLine, UnsortedUses, UnusedParameter, UnusedPrivateMethod, UnusedPublicMember
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

{$R *.dfm}

uses
  System.IniFiles, System.IOUtils, Winapi.ShellAPI, Winapi.Windows,
  uIDETheme,    // TIDETheme.Apply + Subscribe
  uIDEColors;   // semantische Palette (IDE_BG_CONTENT, IDE_FG_DIM)

var
  GSonarOptionsIfc : INTAAddInOptions = nil;
  GSonarOptionsObj : TSonarAddInOptions = nil;

const
  TOKEN_REF_DEFAULT = 'ide-default';
  TOKEN_PLACEHOLDER = '(stored - leave empty to keep)';

{ TSonarOptionsFrame }

constructor TSonarOptionsFrame.Create(AOwner: TComponent);
begin
  inherited;
  Name := '';
  BuildControls;
  // Background-Policy identisch zu TSCAOptionsFrame (uIDESCAOptions) -
  // beide Options-Pages sollen visuell konsistent wirken. Ohne dieses
  // Override uebernahm der Frame die hellgraue Container-Farbe des
  // Options-Dialogs, was neben der dunklen SCA-Page inkonsistent aussah.
  Self.ParentColor      := False;
  Self.ParentBackground := False;
  Self.Color            := IDE_BG_OPTIONS_FRAME;
end;

procedure TSonarOptionsFrame.BuildControls;
const
  MARGIN_LEFT = 16;
  GROUP_W     = 540;
  INNER_LEFT  = 16;
  INNER_TOP   = 22;
  LBL_W       = 100;
  EDIT_W      = 360;
var
  Y : Integer;
begin
  Y := 12;

  // ============== Server ==============
  grpServer         := TGroupBox.Create(Self);
  grpServer.Parent  := Self;
  grpServer.Left    := MARGIN_LEFT;
  grpServer.Top     := Y;
  grpServer.Width   := GROUP_W;
  grpServer.Height  := 168;
  grpServer.Caption := _('Server');
  Inc(Y, grpServer.Height + 12);

  // TLabel mit AutoSize=True (Default) schrumpft sich beim ersten Layout-
  // Tick auf seine Caption-Breite - das verschiebt die Label-Right-Kante
  // unvorhersehbar. AutoSize=False + feste Width/Height haelt die Spalte
  // stabil, vor allem bei DPI-Skalierung und uebersetzten Captions.
  lblHost := TLabel.Create(Self); lblHost.Parent := grpServer;
  lblHost.AutoSize := False;
  lblHost.Left := INNER_LEFT; lblHost.Top := INNER_TOP + 3;
  lblHost.Width := LBL_W; lblHost.Height := 17;
  lblHost.Caption := _('Host URL:');
  edHost := TEdit.Create(Self); edHost.Parent := grpServer;
  edHost.Left := INNER_LEFT + LBL_W; edHost.Top := INNER_TOP;
  edHost.Width := EDIT_W; edHost.TextHint := 'https://sonar.company.com';

  lblProject := TLabel.Create(Self); lblProject.Parent := grpServer;
  lblProject.AutoSize := False;
  lblProject.Left := INNER_LEFT; lblProject.Top := lblHost.Top + 32;
  lblProject.Width := LBL_W; lblProject.Height := 17;
  lblProject.Caption := _('Project Key:');
  edProject := TEdit.Create(Self); edProject.Parent := grpServer;
  edProject.Left := INNER_LEFT + LBL_W; edProject.Top := edHost.Top + 32;
  edProject.Width := EDIT_W - 100;
  btnDetectProject := TButton.Create(Self); btnDetectProject.Parent := grpServer;
  btnDetectProject.Left := edProject.Left + edProject.Width + 4;
  btnDetectProject.Top := edProject.Top;
  btnDetectProject.Width := 96; btnDetectProject.Height := edProject.Height;
  btnDetectProject.Caption := _('Detect');
  btnDetectProject.OnClick := DetectProjectClick;

  lblBranch := TLabel.Create(Self); lblBranch.Parent := grpServer;
  lblBranch.AutoSize := False;
  lblBranch.Left := INNER_LEFT; lblBranch.Top := lblProject.Top + 32;
  lblBranch.Width := LBL_W; lblBranch.Height := 17;
  lblBranch.Caption := _('Branch:');
  edBranch := TEdit.Create(Self); edBranch.Parent := grpServer;
  edBranch.Left := INNER_LEFT + LBL_W; edBranch.Top := edProject.Top + 32;
  edBranch.Width := EDIT_W; edBranch.TextHint := 'main';

  chkInsecure := TCheckBox.Create(Self); chkInsecure.Parent := grpServer;
  chkInsecure.Left := INNER_LEFT + LBL_W; chkInsecure.Top := edBranch.Top + 32;
  chkInsecure.Width := EDIT_W;
  chkInsecure.Caption := _('Accept self-signed TLS certificates');

  // ============== Auth ==============
  // Hoehe 116 (vorher 100): bei Hi-DPI wickelt der 8pt-Help-Text auf 2
  // Zeilen und die zweite Zeile lag unter der GroupBox-Unterkante.
  grpAuth         := TGroupBox.Create(Self);
  grpAuth.Parent  := Self;
  grpAuth.Left    := MARGIN_LEFT;
  grpAuth.Top     := Y;
  grpAuth.Width   := GROUP_W;
  grpAuth.Height  := 116;
  grpAuth.Caption := _('Authentication');
  Inc(Y, grpAuth.Height + 12);

  lblToken := TLabel.Create(Self); lblToken.Parent := grpAuth;
  lblToken.AutoSize := False;
  lblToken.Left := INNER_LEFT; lblToken.Top := INNER_TOP + 3;
  lblToken.Width := LBL_W; lblToken.Height := 17;
  lblToken.Caption := _('Bearer Token:');
  edToken := TEdit.Create(Self); edToken.Parent := grpAuth;
  edToken.Left := INNER_LEFT + LBL_W; edToken.Top := INNER_TOP;
  edToken.Width := EDIT_W - 100;
  edToken.PasswordChar := '*';
  btnRevealToken := TButton.Create(Self); btnRevealToken.Parent := grpAuth;
  btnRevealToken.Left := edToken.Left + edToken.Width + 4;
  btnRevealToken.Top := edToken.Top;
  btnRevealToken.Width := 96; btnRevealToken.Height := edToken.Height;
  btnRevealToken.Caption := _('Show');
  btnRevealToken.OnClick := RevealTokenClick;

  lblTokenInfo := TLabel.Create(Self); lblTokenInfo.Parent := grpAuth;
  lblTokenInfo.AutoSize := False;
  lblTokenInfo.Left := INNER_LEFT + LBL_W;
  lblTokenInfo.Top := edToken.Top + 28;
  lblTokenInfo.Width := EDIT_W;
  // 40px statt 26: Hi-DPI 8pt mit WordWrap braucht ~18-20px pro Zeile.
  // 26 hatte die zweite Zeile angeschnitten.
  lblTokenInfo.Height := 40;
  lblTokenInfo.WordWrap := True;
  StyleAsHintLabel(lblTokenInfo);   // IDE_FG_DIM, 8pt, ParentFont aus
  lblTokenInfo.Caption := _(
    'Token is stored DPAPI-encrypted in analyser.ini [SonarTokens]. ' +
    'Only this Windows user on this machine can decrypt it.');

  // ============== Actions ==============
  // Hoehe 200 statt 220 - die Standard-Tools>Options-Page hat ~520 px
  // Inhaltshoehe. Mit grpServer(168) + 12 + grpAuth(100) + 12 + grpActions
  // landeten wir vorher bei 524 und die untere Memo-Kante wurde abgeschnitten.
  grpActions         := TGroupBox.Create(Self);
  grpActions.Parent  := Self;
  grpActions.Left    := MARGIN_LEFT;
  grpActions.Top     := Y;
  grpActions.Width   := GROUP_W;
  grpActions.Height  := 200;
  grpActions.Caption := _('Connectivity');

  btnTest := TButton.Create(Self); btnTest.Parent := grpActions;
  btnTest.Left := INNER_LEFT; btnTest.Top := INNER_TOP;
  btnTest.Width := 140; btnTest.Height := 26;
  btnTest.Caption := _('Test Connection');
  btnTest.OnClick := TestConnectionClick;

  btnOpenIni := TButton.Create(Self); btnOpenIni.Parent := grpActions;
  btnOpenIni.Left := btnTest.Left + btnTest.Width + 8;
  btnOpenIni.Top := btnTest.Top;
  btnOpenIni.Width := 140; btnOpenIni.Height := 26;
  btnOpenIni.Caption := _('Open analyser.ini');
  btnOpenIni.OnClick := OpenIniClick;

  memoResult := TMemo.Create(Self); memoResult.Parent := grpActions;
  memoResult.Left := INNER_LEFT; memoResult.Top := btnTest.Top + btnTest.Height + 8;
  memoResult.Width := GROUP_W - 2 * INNER_LEFT;
  memoResult.Height := grpActions.Height - (memoResult.Top - INNER_TOP) - 24;
  memoResult.ScrollBars := ssVertical;
  memoResult.ReadOnly := True;
  memoResult.Font.Name := 'Consolas';
  // IDE_BG_CONTENT statt IDE_BG_CHROME - ReadOnly reicht als Hinweis,
  // grauer Background liest sich wie disabled.
  memoResult.Color := IDE_BG_CONTENT;
end;

procedure TSonarOptionsFrame.LoadFromIni(const IniPath: string);
var
  Ini      : TMemIniFile;
  TokenRef : string;
begin
  FIniPath := IniPath;
  if not TFile.Exists(IniPath) then Exit;
  // TMemIniFile statt TIniFile - vertraegt UTF-8-BOM (z.B. Notepad-Save).
  Ini := TMemIniFile.Create(IniPath, TEncoding.UTF8);
  try
    edHost.Text     := Ini.ReadString('Sonar', 'HostUrl',      '');
    edProject.Text  := Ini.ReadString('Sonar', 'ProjectKey',   '');
    edBranch.Text   := Ini.ReadString('Sonar', 'Branch',       '');
    chkInsecure.Checked := Ini.ReadBool('Sonar', 'Insecure',   False);
    TokenRef        := Ini.ReadString('Sonar', 'TokenRef',     '');
  finally
    Ini.Free;
  end;

  if TokenRef <> '' then
  begin
    FOriginalToken := TSonarConfigResolver.LoadToken(IniPath, TokenRef);
    if FOriginalToken <> '' then
    begin
      edToken.Text := TOKEN_PLACEHOLDER;
      edToken.PasswordChar := #0;  // Placeholder lesbar zeigen
    end;
  end;
end;

procedure TSonarOptionsFrame.SaveToIni(const IniPath: string);
var
  Ini      : TMemIniFile;
  NewToken : string;
begin
  if IniPath = '' then Exit;
  ForceDirectories(ExtractFilePath(IniPath));

  Ini := TMemIniFile.Create(IniPath, TEncoding.UTF8);
  try
    Ini.WriteString('Sonar', 'HostUrl',    Trim(edHost.Text));
    Ini.WriteString('Sonar', 'ProjectKey', Trim(edProject.Text));
    Ini.WriteString('Sonar', 'Branch',     Trim(edBranch.Text));
    Ini.WriteBool  ('Sonar', 'Insecure',   chkInsecure.Checked);
    Ini.WriteString('Sonar', 'TokenRef',   TOKEN_REF_DEFAULT);
    Ini.UpdateFile;  // TMemIniFile persistiert erst durch UpdateFile
  finally
    Ini.Free;
  end;

  NewToken := edToken.Text;
  // Placeholder = "unchanged" - alten Token belassen
  if NewToken = TOKEN_PLACEHOLDER then Exit;
  if NewToken = '' then Exit;  // leer = nicht ueberschreiben

  TSonarConfigResolver.StoreToken(IniPath, TOKEN_REF_DEFAULT, NewToken);
end;

procedure TSonarOptionsFrame.CMStyleChanged(var Message: TMessage);
begin
  inherited;
  // VCL-broadcastet diese Message wenn der aktive Style wechselt.
  // Belt-and-suspenders zum TIDETheme-Subscribe; Apply ist idempotent.
  if csDestroying in ComponentState then Exit;
  TIDETheme.Apply(Self);
end;

procedure TSonarOptionsFrame.DetectProjectClick(Sender: TObject);
// Liest sonar.projectKey aus sonar-project.properties im aktiven Projekt
// und uebernimmt in das Project-Feld.
var
  ModSvc   : IOTAModuleServices;
  ProjGroup: IOTAProjectGroup;
  Proj     : IOTAProject;
  Dir, Path: string;
  Cfg      : TSonarConfig;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then Exit;
  ProjGroup := ModSvc.MainProjectGroup;
  if (ProjGroup = nil) or (ProjGroup.ProjectCount = 0) then Exit;
  Proj := ProjGroup.ActiveProject;
  if Proj = nil then Exit;
  Dir := ExtractFilePath(Proj.FileName);
  Path := TSonarConfigResolver.ProjectPropsPath(Dir);
  if not TFile.Exists(Path) then
  begin
    ShowMessage(_('No sonar-project.properties found in ') + Dir);
    Exit;
  end;
  Cfg := Default(TSonarConfig);
  TSonarConfigResolver.ReadFromProjectProps(Dir, Cfg);
  if Cfg.ProjectKey <> '' then
  begin
    edProject.Text := Cfg.ProjectKey;
    if Cfg.HostUrl <> '' then edHost.Text := Cfg.HostUrl;
  end
  else
    ShowMessage(_('sonar.projectKey not found in ') + Path);
end;

procedure TSonarOptionsFrame.TestConnectionClick(Sender: TObject);
// Health-Check mit den AKTUELLEN UI-Werten (nicht den persistierten).
var
  Cli : TSonarCliOverrides;
  Cfg : TSonarConfig;
  R   : TSonarHealthResult;
  S   : string;
begin
  Cli := Default(TSonarCliOverrides);
  Cli.HostUrl    := Trim(edHost.Text);
  Cli.ProjectKey := Trim(edProject.Text);
  Cli.Branch     := Trim(edBranch.Text);
  Cli.Insecure   := chkInsecure.Checked;
  if (edToken.Text <> '') and (edToken.Text <> TOKEN_PLACEHOLDER) then
    Cli.Token := edToken.Text
  else
    Cli.Token := FOriginalToken;

  Cfg := TSonarConfigResolver.Resolve(Cli, '', '');
  // KEIN Application.ProcessMessages hier - im IDE-Plugin ist Application
  // die Delphi-IDE selbst; ProcessMessages kann andere Events feuern und
  // Re-Entrancy im Options-Dialog ausloesen. Der User sieht das
  // "Running..."-Update einfach nicht, dafuer bleibt der Dialog stabil.
  Screen.Cursor := crHourGlass;
  try
    memoResult.Clear;
    memoResult.Lines.Add(_('Running health-check (this may take up to ~15s)...'));
    R := TSonarHealthCheck.Run(Cfg);
    S := TSonarHealthCheck.FormatChecklist(R);
    memoResult.Text := S;
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TSonarOptionsFrame.RevealTokenClick(Sender: TObject);
begin
  if edToken.PasswordChar = '*' then
  begin
    edToken.PasswordChar := #0;
    btnRevealToken.Caption := _('Hide');
  end
  else
  begin
    edToken.PasswordChar := '*';
    btnRevealToken.Caption := _('Show');
  end;
end;

procedure TSonarOptionsFrame.OpenIniClick(Sender: TObject);
begin
  if FIniPath = '' then Exit;
  if not TFile.Exists(FIniPath) then
  begin
    ShowMessage(_('File does not exist yet: ') + FIniPath +
      sLineBreak + _('Save once to create it.'));
    Exit;
  end;
  ShellExecute(0, 'open', PChar(FIniPath), nil, nil, SW_SHOWNORMAL);
end;

{ TSonarAddInOptions }

function TSonarAddInOptions.GetCaption: string;
begin
  Result := 'Sonar Integration';
end;

function TSonarAddInOptions.GetFrameClass: TCustomFrameClass;
begin
  Result := TSonarOptionsFrame;
end;

procedure TSonarAddInOptions.DoLoadFrame(AFrame: TCustomFrame);
begin
  TSonarOptionsFrame(AFrame).LoadFromIni(TSonarConfigResolver.DefaultIniPath);
end;

procedure TSonarAddInOptions.DoSaveFrame(AFrame: TCustomFrame);
begin
  TSonarOptionsFrame(AFrame).SaveToIni(TSonarConfigResolver.DefaultIniPath);
end;

procedure RegisterSonarAddInOptions;
// Reihenfolge wie in uIDESCAOptions.RegisterSCAAddInOptions: erst Service
// abfragen, erst dann Object/Interface erzeugen. Wenn die IDE keinen
// EnvironmentOptionsServices anbietet (sollte nie - aber sicher ist sicher),
// lassen wir das Object gar nicht entstehen und vermeiden eine Leak-Spur.
var
  EnvSvc : INTAEnvironmentOptionsServices;
begin
  if Assigned(GSonarOptionsObj) then Exit;
  if not Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, EnvSvc) then
    Exit;

  GSonarOptionsObj := TSonarAddInOptions.Create;
  GSonarOptionsIfc := GSonarOptionsObj as INTAAddInOptions;
  EnvSvc.RegisterAddInOptions(GSonarOptionsIfc);
end;

procedure UnregisterSonarAddInOptions;
var
  EnvSvc : INTAEnvironmentOptionsServices;
begin
  if not Assigned(GSonarOptionsIfc) then Exit;
  try
    if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, EnvSvc) then
      EnvSvc.UnregisterAddInOptions(GSonarOptionsIfc);
  except
  end;
  GSonarOptionsIfc := nil;   // Refcount sinkt -> Object freigegeben
  GSonarOptionsObj := nil;
end;

end.
