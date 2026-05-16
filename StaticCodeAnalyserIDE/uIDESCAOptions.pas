unit uIDESCAOptions;

// Tools > Options-Page "Static Code Analyser" - User-konfigurierbare
// Settings fuer den Silent-Mode (Editor-Rechtsklick + Hotkey).
//
// Registriert sich unter:
//   Tools > Options > Third Party > Static Code Analyser
//
// Persistenz: alle Werte werden in derselben analyser.ini gespeichert die
// auch das Dock-Plugin nutzt. Damit ist die IDE-Options-Page nur eine
// alternative UI - kein doppelter Settings-Store.
//
// Architektur:
//   * TSCAOptionsFrame    - TFrame mit den Controls (Checkbox heute, spaeter
//                            erweiterbar)
//   * TSCAAddInOptions    - INTAAddInOptions-Impl: GetFrameClass liefert
//                            den Frame, FrameCreated initialisiert Werte,
//                            DialogClosed speichert bei OK
//   * RegisterSCAAddInOptions / Unregister - Lifecycle aus dem Plugin-Init

interface

uses
  System.Classes, System.SysUtils, System.UITypes,    // clGrayText
  Vcl.Graphics,                                       // TFontStyle (fsBold)
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  ToolsAPI,
  uRepoSettings,
  uLocalization,                 // _() i18n-Wrapper
  uRuleCatalog;                  // TRuleCatalog.ProfileNames fuer Combo

type
  TSCAOptionsFrame = class(TFrame)
    // Silent-Mode
    grpSilent          : TGroupBox;
    chkSilentEnabled   : TCheckBox;
    lblSilentInfo      : TLabel;
    // Rule-Set
    grpRuleSet         : TGroupBox;
    lblProfile         : TLabel;
    cboProfile         : TComboBox;
    lblMinSev          : TLabel;
    cboMinSev          : TComboBox;
    lblIdeProfile      : TLabel;
    cboIdeProfile      : TComboBox;
    // Detectors
    grpDetectors       : TGroupBox;
    chkUsesCheck       : TCheckBox;
    chkIncludeTests    : TCheckBox;
    chkAutoDiscover    : TCheckBox;
  private
    procedure BuildControls;
    procedure PopulateProfileCombos;
    procedure PopulateMinSevCombo;
  public
    constructor Create(AOwner: TComponent); override;
    // Werte aus den Settings in die Controls schreiben (FrameCreated).
    procedure LoadFromSettings(ASettings: TRepoSettings);
    // Werte aus den Controls in die Settings zurueckschreiben
    // (DialogClosed mit Accepted=True).
    procedure SaveToSettings(ASettings: TRepoSettings);
  end;

  TSCAAddInOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FFrame : TSCAOptionsFrame;
  public
    // INTAAddInOptions
    function GetArea: string;
    function GetCaption: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    procedure DialogClosed(Accepted: Boolean);
    function ValidateContents: Boolean;
    function GetHelpContext: Integer;
    function IncludeInIDEInsight: Boolean;
  end;

procedure RegisterSCAAddInOptions;
procedure UnregisterSCAAddInOptions;

implementation

{$R *.dfm}

uses
  uIDEThemeIntegration;   // ApplyIDETheme one-shot helper

const
  // Sentinel-Text fuer "kein Profile-Override". Wird im Combo angezeigt
  // und in LoadFromSettings/SaveToSettings als Marker verglichen - daher
  // bewusst NICHT durch _() geleitet (Identity-Fallback wuerde reichen,
  // aber so bleibt der Schluessel offensichtlich stabil).
  SCA_DEFAULT_DISPLAY = '(default)';

var
  GSCAOptionsIfc : INTAAddInOptions = nil;
  GSCAOptionsObj : TSCAAddInOptions = nil;

{ TSCAOptionsFrame }

constructor TSCAOptionsFrame.Create(AOwner: TComponent);
begin
  inherited;
  Name    := '';       // keinen Komponenten-Namen fuer den Frame
  BuildControls;
end;

procedure TSCAOptionsFrame.BuildControls;
// Drei Sektionen via TGroupBox: Silent Mode / Rule-Set / Detectors.
// Persistenz: alle Werte schreiben in analyser.ini (TRepoSettings.Save).
// Layout: feste Pixel-Positionen, keine Anchors - bei AutoSize+WordWrap
// produzieren Anchors sonst "0-Breite"-Effekte in der Options-Page.
const
  MARGIN_LEFT  = 16;
  MARGIN_TOP   = 12;
  GROUP_W      = 500;   // einheitliche Breite fuer alle GroupBoxes
  GROUP_GAP    = 12;
  INNER_LEFT   = 16;    // Linker Abstand innerhalb einer GroupBox
  INNER_TOP    = 22;    // Erstes Element unter der GroupBox-Caption
  LINE_GAP     = 8;     // Vertikal-Abstand zwischen Zeilen
  LBL_W        = 100;   // Label-Breite (rechts Combo)
  CMB_W        = 200;   // Combo-Breite
var
  Y : Integer;          // Cursor - typed const waere unter {$J-} read-only

  function NextY(AHeight: Integer): Integer;
  begin
    Result := Y;
    Y := Y + AHeight + GROUP_GAP;
  end;

begin
  Y := MARGIN_TOP;
  // ================= Silent Mode =================
  // Hoehe 120 deckt Checkbox (22) + Info-Label mit 2 Zeilen WordWrap ab.
  grpSilent              := TGroupBox.Create(Self);
  grpSilent.Parent       := Self;
  grpSilent.Left         := MARGIN_LEFT;
  grpSilent.Top          := NextY(120);
  grpSilent.Width        := GROUP_W;
  grpSilent.Height       := 120;
  grpSilent.Caption      := _('Silent Mode');

  chkSilentEnabled         := TCheckBox.Create(Self);
  chkSilentEnabled.Parent  := grpSilent;
  chkSilentEnabled.Left    := INNER_LEFT;
  chkSilentEnabled.Top     := INNER_TOP;
  chkSilentEnabled.Width   := GROUP_W - 2 * INNER_LEFT;
  chkSilentEnabled.Caption :=
    _('Enable silent analysis (editor right-click + Ctrl+Alt+A)');

  // TLabel mit AutoSize=True (Default) + WordWrap=True ist in VCL buggy:
  // schrumpft die Width auf "text passt in 1 Zeile" zusammen und wrappt
  // dann pro Wort. AutoSize=False + festes Height (40 = 2 Zeilen 9pt)
  // umgeht das.
  lblSilentInfo            := TLabel.Create(Self);
  lblSilentInfo.Parent     := grpSilent;
  lblSilentInfo.AutoSize   := False;
  lblSilentInfo.Left       := INNER_LEFT + 16;
  lblSilentInfo.Top        := chkSilentEnabled.Top + chkSilentEnabled.Height + 6;
  lblSilentInfo.Width      := GROUP_W - 2 * INNER_LEFT - 16;
  lblSilentInfo.Height     := 40;
  lblSilentInfo.WordWrap   := True;
  lblSilentInfo.Caption    :=
    _('Editor right-click + Ctrl+Alt+A trigger a single-file analysis; ' +
      'findings appear as stripes + hover overlays in the editor (no dock).');

  // ================= Rule-Set =================
  grpRuleSet              := TGroupBox.Create(Self);
  grpRuleSet.Parent       := Self;
  grpRuleSet.Left         := MARGIN_LEFT;
  grpRuleSet.Top          := NextY(124);
  grpRuleSet.Width        := GROUP_W;
  grpRuleSet.Height       := 124;
  grpRuleSet.Caption      := _('Rule-Set (analyser.ini [Rules])');

  // Standalone Profile
  lblProfile              := TLabel.Create(Self);
  lblProfile.Parent       := grpRuleSet;
  lblProfile.Left         := INNER_LEFT;
  lblProfile.Top          := INNER_TOP + 3;
  lblProfile.Width        := LBL_W;
  lblProfile.Caption      := _('Profile (CLI/Form):');

  cboProfile              := TComboBox.Create(Self);
  cboProfile.Parent       := grpRuleSet;
  cboProfile.Left         := INNER_LEFT + LBL_W;
  cboProfile.Top          := INNER_TOP;
  cboProfile.Width        := CMB_W;
  cboProfile.Style        := csDropDownList;

  // MinSeverity
  lblMinSev               := TLabel.Create(Self);
  lblMinSev.Parent        := grpRuleSet;
  lblMinSev.Left          := INNER_LEFT;
  lblMinSev.Top           := lblProfile.Top + 28;
  lblMinSev.Width         := LBL_W;
  lblMinSev.Caption       := _('Min-Severity:');

  cboMinSev               := TComboBox.Create(Self);
  cboMinSev.Parent        := grpRuleSet;
  cboMinSev.Left          := INNER_LEFT + LBL_W;
  cboMinSev.Top           := cboProfile.Top + 28;
  cboMinSev.Width         := CMB_W;
  cboMinSev.Style         := csDropDownList;

  // IDE-Profile
  lblIdeProfile           := TLabel.Create(Self);
  lblIdeProfile.Parent    := grpRuleSet;
  lblIdeProfile.Left      := INNER_LEFT;
  lblIdeProfile.Top       := lblMinSev.Top + 28;
  lblIdeProfile.Width     := LBL_W;
  lblIdeProfile.Caption   := _('IDE Profile:');

  cboIdeProfile           := TComboBox.Create(Self);
  cboIdeProfile.Parent    := grpRuleSet;
  cboIdeProfile.Left      := INNER_LEFT + LBL_W;
  cboIdeProfile.Top       := cboMinSev.Top + 28;
  cboIdeProfile.Width     := CMB_W;
  cboIdeProfile.Style     := csDropDownList;

  PopulateProfileCombos;
  PopulateMinSevCombo;

  // ================= Detectors =================
  grpDetectors            := TGroupBox.Create(Self);
  grpDetectors.Parent     := Self;
  grpDetectors.Left       := MARGIN_LEFT;
  grpDetectors.Top        := NextY(110);
  grpDetectors.Width      := GROUP_W;
  grpDetectors.Height     := 110;
  grpDetectors.Caption    := _('Detectors (analyser.ini [Detectors])');

  chkUsesCheck            := TCheckBox.Create(Self);
  chkUsesCheck.Parent     := grpDetectors;
  chkUsesCheck.Left       := INNER_LEFT;
  chkUsesCheck.Top        := INNER_TOP;
  chkUsesCheck.Width      := GROUP_W - 2 * INNER_LEFT;
  chkUsesCheck.Caption    := _('UsesCheck - report unused entries in uses clause ' +
                               '(may produce false positives)');

  chkIncludeTests         := TCheckBox.Create(Self);
  chkIncludeTests.Parent  := grpDetectors;
  chkIncludeTests.Left    := INNER_LEFT;
  chkIncludeTests.Top     := chkUsesCheck.Top + LINE_GAP + chkUsesCheck.Height;
  chkIncludeTests.Width   := GROUP_W - 2 * INNER_LEFT;
  chkIncludeTests.Caption := _('IncludeTests - analyse DUnit/DUnitX test units too');

  chkAutoDiscover         := TCheckBox.Create(Self);
  chkAutoDiscover.Parent  := grpDetectors;
  chkAutoDiscover.Left    := INNER_LEFT;
  chkAutoDiscover.Top     := chkIncludeTests.Top + LINE_GAP + chkIncludeTests.Height;
  chkAutoDiscover.Width   := GROUP_W - 2 * INNER_LEFT;
  chkAutoDiscover.Caption := _('AutoDiscoverClasses - extend LeakyClasses with ' +
                               'project-specific classes');
end;

procedure TSCAOptionsFrame.PopulateProfileCombos;
// Beide Profile-Combos werden aus TRuleCatalog.ProfileNames gefuellt
// (default, ide-fast, strict, security, bugs-only, code-quality, dfm-only
// + Custom-Profile aus sca-rules.json).
var
  Names : TArray<string>;
  N     : string;
begin
  Names := TRuleCatalog.ProfileNames;
  cboProfile.Items.Clear;
  cboIdeProfile.Items.Clear;
  // Erste Position: leerer Eintrag = "kein Override" (faellt im
  // ApplyDetectorThresholds auf 'default' zurueck). Sentinel SCA_DEFAULT_DISPLAY
  // wird identisch fuer Display und IndexOf-Vergleich benutzt (nicht via _()).
  cboProfile.Items.Add(SCA_DEFAULT_DISPLAY);
  cboIdeProfile.Items.Add(SCA_DEFAULT_DISPLAY);
  for N in Names do
  begin
    cboProfile.Items.Add(N);
    cboIdeProfile.Items.Add(N);
  end;
  cboProfile.ItemIndex    := 0;
  cboIdeProfile.ItemIndex := 0;
end;

procedure TSCAOptionsFrame.PopulateMinSevCombo;
// Drei feste Stufen (lsHint/lsWarning/lsError + leer).
begin
  cboMinSev.Items.Clear;
  cboMinSev.Items.Add('hint');
  cboMinSev.Items.Add('warning');
  cboMinSev.Items.Add('error');
  cboMinSev.ItemIndex := 0;
end;

procedure TSCAOptionsFrame.LoadFromSettings(ASettings: TRepoSettings);

  procedure SelectComboBy(ACombo: TComboBox; const AValue: string;
    const ADefaultDisplay: string = SCA_DEFAULT_DISPLAY);
  // Setzt cboXxx.ItemIndex anhand des AValue-Strings; faellt auf Eintrag
  // ADefaultDisplay (typisch '(default)') zurueck wenn der Wert leer ist
  // oder nicht im Combo gelistet.
  var
    Idx : Integer;
  begin
    if AValue = '' then
      Idx := ACombo.Items.IndexOf(ADefaultDisplay)
    else
      Idx := ACombo.Items.IndexOf(AValue);
    if Idx < 0 then
      Idx := ACombo.Items.IndexOf(ADefaultDisplay);
    if Idx < 0 then Idx := 0;
    ACombo.ItemIndex := Idx;
  end;

begin
  if not Assigned(ASettings) then Exit;

  // Silent
  if Assigned(chkSilentEnabled) then
    chkSilentEnabled.Checked := ASettings.SilentEnabled;

  // Rule-Set: leere Werte aus INI als '(default)' anzeigen
  if Assigned(cboProfile)    then SelectComboBy(cboProfile,    ASettings.Profile);
  if Assigned(cboMinSev)     then SelectComboBy(cboMinSev,     LowerCase(ASettings.MinSeverity), 'hint');
  if Assigned(cboIdeProfile) then SelectComboBy(cboIdeProfile, ASettings.IdeProfile);

  // Detectors
  if Assigned(chkUsesCheck)    then chkUsesCheck.Checked    := ASettings.UsesCheck;
  if Assigned(chkIncludeTests) then chkIncludeTests.Checked := ASettings.IncludeTests;
  if Assigned(chkAutoDiscover) then chkAutoDiscover.Checked := ASettings.AutoDiscoverClasses;
end;

procedure TSCAOptionsFrame.SaveToSettings(ASettings: TRepoSettings);

  function ComboValueOrEmpty(ACombo: TComboBox;
    const ADefaultDisplay: string = SCA_DEFAULT_DISPLAY): string;
  // Liefert den Combo-Text, oder '' wenn der "(default)"-Eintrag selektiert
  // ist - so bleibt die INI sauber (leerer Wert = fall back auf 'default'
  // in TRuleCatalog.GetProfile).
  begin
    if (ACombo.ItemIndex < 0) then Exit('');
    Result := ACombo.Items[ACombo.ItemIndex];
    if SameText(Result, ADefaultDisplay) then Result := '';
  end;

begin
  if not Assigned(ASettings) then Exit;

  if Assigned(chkSilentEnabled) then
    ASettings.SilentEnabled := chkSilentEnabled.Checked;

  if Assigned(cboProfile)    then ASettings.Profile     := ComboValueOrEmpty(cboProfile);
  if Assigned(cboMinSev)     then ASettings.MinSeverity := cboMinSev.Items[cboMinSev.ItemIndex];
  if Assigned(cboIdeProfile) then ASettings.IdeProfile  := ComboValueOrEmpty(cboIdeProfile);

  if Assigned(chkUsesCheck)    then ASettings.UsesCheck           := chkUsesCheck.Checked;
  if Assigned(chkIncludeTests) then ASettings.IncludeTests        := chkIncludeTests.Checked;
  if Assigned(chkAutoDiscover) then ASettings.AutoDiscoverClasses := chkAutoDiscover.Checked;
end;

{ TSCAAddInOptions }

function TSCAAddInOptions.GetArea: string;
begin
  // Leerer String -> erscheint unter "Third Party" im Optionen-Tree
  // (laut ToolsAPI-Doku: empfohlen fuer Plugin-Pages).
  Result := '';
end;

function TSCAAddInOptions.GetCaption: string;
begin
  // Erscheint als Tree-Node-Caption. Kein Dot = einzelner Eintrag,
  // keine Sub-Hierarchie.
  Result := 'Static Code Analyser';
end;

function TSCAAddInOptions.GetFrameClass: TCustomFrameClass;
begin
  Result := TSCAOptionsFrame;
end;

procedure TSCAAddInOptions.FrameCreated(AFrame: TCustomFrame);
// Wird gerufen wenn der User die Options-Page oeffnet. Wir laden hier die
// aktuellen Werte aus analyser.ini ins Frame.
var
  Settings : TRepoSettings;
begin
  FFrame := AFrame as TSCAOptionsFrame;
  Settings := TRepoSettings.Create;
  try
    try Settings.Load; except end;
    FFrame.LoadFromSettings(Settings);
  finally
    Settings.Free;
  end;
  // IDE-Theme uebernehmen - sonst rendert der Frame im VCL-Default
  // (hell) auch wenn die IDE im Dark-Mode laeuft. Bisher hat das Erbe
  // vom Parent-Panel teilweise gegriffen, war aber inkonsistent.
  ApplyIDETheme(FFrame);
end;

procedure TSCAAddInOptions.DialogClosed(Accepted: Boolean);
// User hat OK oder Cancel geklickt. Bei OK speichern wir die Werte zurueck
// in analyser.ini. Bei Cancel ignorieren wir die UI-Aenderungen.
var
  Settings : TRepoSettings;
begin
  if not Accepted then Exit;
  if not Assigned(FFrame) then Exit;
  Settings := TRepoSettings.Create;
  try
    try Settings.Load; except end;       // bestehende Werte laden
    FFrame.SaveToSettings(Settings);     // unsere Aenderungen drueber
    try Settings.Save; except end;       // zurueckschreiben
  finally
    Settings.Free;
  end;
end;

function TSCAAddInOptions.ValidateContents: Boolean;
begin
  // Aktuell keine zu validierenden Felder (Checkbox kann nicht falsch sein).
  Result := True;
end;

function TSCAAddInOptions.GetHelpContext: Integer;
begin
  Result := 0;     // kein eigener Help-Context
end;

function TSCAAddInOptions.IncludeInIDEInsight: Boolean;
begin
  // True = unser Eintrag wird in der IDE-Insight-Suche ('Preferences') gelistet
  Result := True;
end;

{ Lifecycle }

procedure RegisterSCAAddInOptions;
var
  EnvSvc : INTAEnvironmentOptionsServices;
begin
  if Assigned(GSCAOptionsObj) then Exit;
  if not Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, EnvSvc) then
    Exit;

  GSCAOptionsObj := TSCAAddInOptions.Create;
  GSCAOptionsIfc := GSCAOptionsObj as INTAAddInOptions;
  EnvSvc.RegisterAddInOptions(GSCAOptionsIfc);
end;

procedure UnregisterSCAAddInOptions;
var
  EnvSvc : INTAEnvironmentOptionsServices;
begin
  if not Assigned(GSCAOptionsIfc) then Exit;
  try
    if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, EnvSvc) then
      EnvSvc.UnregisterAddInOptions(GSCAOptionsIfc);
  except
  end;
  GSCAOptionsIfc := nil;     // Refcount sinkt -> Object freigegeben
  GSCAOptionsObj := nil;
end;

end.
