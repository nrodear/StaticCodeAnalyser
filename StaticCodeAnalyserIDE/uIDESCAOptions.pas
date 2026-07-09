unit uIDESCAOptions;

// Tools > Options-Page "Static Code Analyser" - User-konfigurierbare
// Settings fuer den Silent-Mode (Editor-Rechtsklick).
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
  Winapi.Messages,                                    // TMessage / CM_STYLECHANGED
  System.Classes, System.SysUtils, System.UITypes,    // clGrayText
  Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Dialogs,
  ToolsAPI,
  uIDEAddInOptionsBase,          // gemeinsame Basis fuer INTAAddInOptions-Adapter
  uRepoSettings,
  uLocalization,                 // _() i18n-Wrapper
  uRuleCatalog;                  // TRuleCatalog.ProfileNames fuer Combo

type
  TSCAOptionsFrame = class(TFrame)
    // Scroll-Container: das Frame ist mittlerweile hoeher als die meisten
    // Options-Dialoge der IDE - User braucht eine Scroll-Moeglichkeit, sonst
    // sind die unteren Gruppen (Rule-Set, Detectors) ggf. nicht erreichbar.
    // TScrollBox mit AutoScroll=True: die ScrollBar-Range adaptiert
    // automatisch an die kumulative Hoehe der GroupBox-Children.
    FScroll            : TScrollBox;
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
    // Display
    grpDisplay              : TGroupBox;
    lblOverlayPos           : TLabel;
    cboOverlayPos           : TComboBox;
    lblOverlayPosInfo       : TLabel;
    chkOverlayShowOnHover   : TCheckBox;
    lblOverlayShowOnHoverInfo : TLabel;
    lblEditorColorScheme    : TLabel;
    cboEditorColorScheme    : TComboBox;
    lblEditorColorSchemeInfo: TLabel;
    // Baseline (non-destruktiver "nur neue Funde"-Filter)
    grpBaseline             : TGroupBox;
    chkBaselineOnlyNew      : TCheckBox;
    lblBaselineFile         : TLabel;
    edtBaselineFile         : TEdit;
    btnBaselineBrowse       : TButton;
    lblBaselineInfo         : TLabel;
  private
    procedure BaselineBrowseClick(Sender: TObject);
    procedure BuildControls;
    // BuildControls als Orchestrator + Sektionen. Reihenfolge spiegelt den
    // Layout-Stapel: Silent / Rule-Set / Detectors / Display.
    procedure BuildSilentSection(AParent: TWinControl; var AY: Integer);
    procedure BuildRuleSetSection(AParent: TWinControl; var AY: Integer);
    procedure BuildDetectorsSection(AParent: TWinControl; var AY: Integer);
    procedure BuildDisplaySection(AParent: TWinControl; var AY: Integer);
    procedure BuildBaselineSection(AParent: TWinControl; var AY: Integer);
    procedure PopulateProfileCombos;
    procedure PopulateMinSevCombo;
    // VCL-Style-Wechsel via Application.Broadcast - feuert zuverlaessiger
    // als der TIDETheme-Subscribe in manchen IDE-Versionen. Beide Pfade
    // rufen Apply auf das Frame; Apply ist idempotent.
    procedure CMStyleChanged(var Message: TMessage); message CM_STYLECHANGED;
    // Sammeltrigger fuer den uIDEColors.StyleAsHintLabel-Helper - listet
    // alle Info-Labels einmal nach BuildControls auf.
    procedure ApplyHintStyleToAllInfoLabels;
  public
    constructor Create(AOwner: TComponent); override;
    // Werte aus den Settings in die Controls schreiben (FrameCreated).
    procedure LoadFromSettings(ASettings: TRepoSettings);
    // Werte aus den Controls in die Settings zurueckschreiben
    // (DialogClosed mit Accepted=True).
    procedure SaveToSettings(ASettings: TRepoSettings);
  end;

  // Boilerplate (FFrame/FThemeSub, FrameCreated, DialogClosed, OnThemeChanged,
  // ValidateContents, GetHelpContext, IncludeInIDEInsight, GetArea) lebt in
  // TIDEAddInOptionsBase. Hier nur die SCA-spezifischen Hooks.
  TSCAAddInOptions = class(TIDEAddInOptionsBase)
  protected
    procedure DoLoadFrame(AFrame: TCustomFrame); override;
    procedure DoSaveFrame(AFrame: TCustomFrame); override;
  public
    function GetCaption: string; override;
    function GetFrameClass: TCustomFrameClass; override;
  end;

procedure RegisterSCAAddInOptions;
procedure UnregisterSCAAddInOptions;

implementation

// noinspection-file BeginEndRequired, CanBeClassMethod, ClassPerFile, ConsecutiveSection, GodClass, NestedRoutine, NestedTry, PublicMemberWithoutDoc, TooLongLine, UnsortedUses, UnusedPrivateMethod, UnusedPublicMember
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

{$R *.dfm}

uses
  uIDETheme,         // TIDETheme.Apply + Subscribe
  uIDEColors,        // IDE_FG_DIM - semantische Theme-Farbe (wie uIDESonarOptions)
  uAnalyserTheme;    // TEditorColorScheme + Parse/ToStr

const
  // Sentinel-Text fuer "kein Profile-Override". Wird im Combo angezeigt
  // und in LoadFromSettings/SaveToSettings als Marker verglichen - daher
  // bewusst NICHT durch _() geleitet (Identity-Fallback wuerde reichen,
  // aber so bleibt der Schluessel offensichtlich stabil).
  SCA_DEFAULT_DISPLAY = '(default)';

  // Layout-Konstanten - frueher Inner-Const-Block in BuildControls. Auf
  // Unit-Ebene gezogen, damit die BuildXxxSection-Methoden alle dieselben
  // Werte sehen ohne Parameter-Schleifen.
  // GROUP_W=540 deckungsgleich mit uIDESonarOptions (konsistente Breite).
  MARGIN_LEFT  = 16;
  MARGIN_TOP   = 12;
  GROUP_W      = 540;
  GROUP_GAP    = 12;
  INNER_LEFT   = 16;    // Linker Abstand innerhalb einer GroupBox
  INNER_TOP    = 22;    // Erstes Element unter der GroupBox-Caption
  LINE_GAP     = 8;     // Vertikal-Abstand zwischen Zeilen
  LBL_W        = 100;   // Label-Breite (rechts Combo)
  CMB_W        = 200;   // Combo-Breite

var
  GSCAOptionsIfc : INTAAddInOptions = nil;
  GSCAOptionsObj : TSCAAddInOptions = nil;

{ TSCAOptionsFrame }

constructor TSCAOptionsFrame.Create(AOwner: TComponent);
begin
  inherited;
  Name    := '';       // keinen Komponenten-Namen fuer den Frame
  BuildControls;
  // Background: semantische Konstante in uIDEColors - identisch zur Sonar-
  // Options-Page (beide Pages sollen visuell konsistent wirken).
  Self.ParentColor      := False;
  Self.ParentBackground := False;
  Self.Color            := IDE_BG_OPTIONS_FRAME;
  ApplyHintStyleToAllInfoLabels;
end;

procedure TSCAOptionsFrame.BuildControls;
// Orchestriert die fuenf Sektionen. Jede BuildXxxSection bekommt den
// vertikalen Cursor Y per var-Parameter und schreibt ihn nach Section-
// Ende fortgeschaltet zurueck. Layout: feste Pixel-Positionen, keine
// Anchors - bei AutoSize+WordWrap produzieren Anchors sonst "0-Breite"-
// Effekte in der Options-Page.
var
  Y : Integer;
begin
  // ---- Scroll-Container ----
  // Frame fuellt sich selbst (Tools > Options legt das in eine fixed-size
  // Page). Der ScrollBox darin fuellt das Frame komplett (alClient) und
  // adapter die VertScrollBar-Range automatisch an die GroupBox-Hoehen.
  // Settings haben 5 Gruppen mit kumulativ ~1000+ Pixel - ohne Scroll
  // waeren die unteren nicht erreichbar auf kleineren Options-Dialogen.
  FScroll              := TScrollBox.Create(Self);
  FScroll.Parent       := Self;
  FScroll.Align        := alClient;
  FScroll.BorderStyle  := bsNone;
  FScroll.AutoScroll   := True;
  FScroll.VertScrollBar.Tracking  := True;
  FScroll.HorzScrollBar.Visible   := False;

  Y := MARGIN_TOP;
  BuildSilentSection   (FScroll, Y);
  BuildRuleSetSection  (FScroll, Y);
  BuildDetectorsSection(FScroll, Y);
  BuildDisplaySection  (FScroll, Y);
  BuildBaselineSection (FScroll, Y);
end;

procedure TSCAOptionsFrame.BuildSilentSection(AParent: TWinControl;
  var AY: Integer);
// Hoehe 120 deckt Checkbox (22) + Info-Label mit 2 Zeilen WordWrap ab.
const
  SECT_H = 120;
begin
  grpSilent              := TGroupBox.Create(Self);
  grpSilent.Parent       := AParent;
  grpSilent.Left         := MARGIN_LEFT;
  grpSilent.Top          := AY;
  grpSilent.Width        := GROUP_W;
  grpSilent.Height       := SECT_H;
  grpSilent.Caption      := _('Silent Mode');
  Inc(AY, SECT_H + GROUP_GAP);

  chkSilentEnabled         := TCheckBox.Create(Self);
  chkSilentEnabled.Parent  := grpSilent;
  chkSilentEnabled.Left    := INNER_LEFT;
  chkSilentEnabled.Top     := INNER_TOP;
  chkSilentEnabled.Width   := GROUP_W - 2 * INNER_LEFT;
  chkSilentEnabled.Caption :=
    _('Enable silent analysis (editor right-click menu)');

  // TLabel mit AutoSize=True (Default) + WordWrap=True ist in VCL buggy:
  // schrumpft die Width auf "text passt in 1 Zeile" zusammen und wrappt
  // dann pro Wort. AutoSize=False + festes Height umgeht das.
  lblSilentInfo            := TLabel.Create(Self);
  lblSilentInfo.Parent     := grpSilent;
  lblSilentInfo.AutoSize   := False;
  lblSilentInfo.Left       := INNER_LEFT + 16;
  lblSilentInfo.Top        := chkSilentEnabled.Top + chkSilentEnabled.Height + 6;
  lblSilentInfo.Width      := GROUP_W - 2 * INNER_LEFT - 16;
  lblSilentInfo.Height     := 60;   // 40 + 20 px (User-Wunsch 2026-06-19)
  lblSilentInfo.WordWrap   := True;
  lblSilentInfo.Caption    :=
    _('Editor right-click triggers a single-file analysis; ' +
      'findings appear as stripes + hover overlays in the editor (no dock).');
end;

procedure TSCAOptionsFrame.BuildRuleSetSection(AParent: TWinControl;
  var AY: Integer);
const
  SECT_H = 124;
begin
  grpRuleSet              := TGroupBox.Create(Self);
  grpRuleSet.Parent       := AParent;
  grpRuleSet.Left         := MARGIN_LEFT;
  grpRuleSet.Top          := AY;
  grpRuleSet.Width        := GROUP_W;
  grpRuleSet.Height       := SECT_H;
  grpRuleSet.Caption      := _('Rule-Set (analyser.ini [Rules])');
  Inc(AY, SECT_H + GROUP_GAP);

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
end;

procedure TSCAOptionsFrame.BuildDetectorsSection(AParent: TWinControl;
  var AY: Integer);
const
  SECT_H = 110;
begin
  grpDetectors            := TGroupBox.Create(Self);
  grpDetectors.Parent     := AParent;
  grpDetectors.Left       := MARGIN_LEFT;
  grpDetectors.Top        := AY;
  grpDetectors.Width      := GROUP_W;
  grpDetectors.Height     := SECT_H;
  grpDetectors.Caption    := _('Detectors (analyser.ini [Detectors])');
  Inc(AY, SECT_H + GROUP_GAP);

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

procedure TSCAOptionsFrame.BuildDisplaySection(AParent: TWinControl;
  var AY: Integer);
// Section hat dynamische Hoehe - die GroupBox-Hoehe wird unten auf Basis
// der echten Children-Position rekalkuliert. Der Y-Cursor wird aber wie
// frueher um den INITIALEN SECT_H_INIT weitergeschaltet (1:1-Verhalten
// zur Vor-Refactor-Version; ggf. spaeter durch grpDisplay.Height
// ersetzen wenn das alte Overlap-Verhalten unerwuenscht war).
const
  SECT_H_INIT = 332;
begin
  // Annotation-Overlay Position. Combo mit zwei Modi:
  //   sameline (Default) - Overlay startet AUF der Finding-Zeile
  //   below             - Overlay startet eine Zeile unter der Finding-Zeile
  // Aenderung greift erst nach IDE-Neustart (Cache in uIDELineHighlighter).
  grpDisplay              := TGroupBox.Create(Self);
  grpDisplay.Parent       := AParent;
  grpDisplay.Left         := MARGIN_LEFT;
  grpDisplay.Top          := AY;
  grpDisplay.Width        := GROUP_W;
  grpDisplay.Height       := SECT_H_INIT;        // wird unten korrigiert
  grpDisplay.Caption      := _('Display');
  Inc(AY, SECT_H_INIT + GROUP_GAP);

  lblOverlayPos           := TLabel.Create(Self);
  lblOverlayPos.Parent    := grpDisplay;
  lblOverlayPos.Left      := INNER_LEFT;
  lblOverlayPos.Top       := INNER_TOP + 3;
  lblOverlayPos.Width     := 160;
  lblOverlayPos.Caption   := _('Annotation overlay position:');

  cboOverlayPos           := TComboBox.Create(Self);
  cboOverlayPos.Parent    := grpDisplay;
  cboOverlayPos.Left      := INNER_LEFT + 160;
  cboOverlayPos.Top       := INNER_TOP;
  cboOverlayPos.Width     := 240;
  cboOverlayPos.Style     := csDropDownList;
  cboOverlayPos.Items.Add(_('Same line at end (default)'));
  cboOverlayPos.Items.Add(_('One line below'));
  cboOverlayPos.ItemIndex := 0;

  lblOverlayPosInfo          := TLabel.Create(Self);
  lblOverlayPosInfo.Parent   := grpDisplay;
  lblOverlayPosInfo.AutoSize := False;
  lblOverlayPosInfo.Left     := INNER_LEFT;
  lblOverlayPosInfo.Top      := cboOverlayPos.Top + cboOverlayPos.Height + 8;
  lblOverlayPosInfo.Width    := GROUP_W - 2 * INNER_LEFT;
  lblOverlayPosInfo.Height   := 48;   // 28 + 20
  lblOverlayPosInfo.WordWrap := True;
  lblOverlayPosInfo.Caption  :=
    _('Where the hover annotation overlay anchors relative to the finding ' +
      'line. Takes effect after IDE restart.');

  // Die fruehere Checkbox "Auto-expand annotation overlay" ist entfallen
  // (UX-Entscheid 2026-07-05): das Overlay faltet jetzt IMMER automatisch
  // bis zur vollen Hint-Ansicht auf - keine Collapsed-Zwischenstufe mehr.
  chkOverlayShowOnHover         := TCheckBox.Create(Self);
  chkOverlayShowOnHover.Parent  := grpDisplay;
  chkOverlayShowOnHover.Left    := INNER_LEFT;
  chkOverlayShowOnHover.Top     := lblOverlayPosInfo.Top + lblOverlayPosInfo.Height + 10;
  chkOverlayShowOnHover.Width   := GROUP_W - 2 * INNER_LEFT;
  chkOverlayShowOnHover.Caption :=
    _('Show annotation overlay on hover (otherwise click marked line)');

  lblOverlayShowOnHoverInfo          := TLabel.Create(Self);
  lblOverlayShowOnHoverInfo.Parent   := grpDisplay;
  lblOverlayShowOnHoverInfo.AutoSize := False;
  lblOverlayShowOnHoverInfo.Left     := INNER_LEFT;
  lblOverlayShowOnHoverInfo.Top      := chkOverlayShowOnHover.Top + chkOverlayShowOnHover.Height + 4;
  lblOverlayShowOnHoverInfo.Width    := GROUP_W - 2 * INNER_LEFT;
  lblOverlayShowOnHoverInfo.Height   := 50;   // 30 + 20
  lblOverlayShowOnHoverInfo.WordWrap := True;
  lblOverlayShowOnHoverInfo.Caption  :=
    _('When OFF (default): overlay appears only when you click a marked ' +
      'line - undisturbed reading. When ON: overlay follows the mouse ' +
      'and pops up as soon as you hover a marked line.');

  // ---- Editor-Color-Scheme (Stripe + Mini-Infobar + Overlay-Titlebar) ----
  lblEditorColorScheme         := TLabel.Create(Self);
  lblEditorColorScheme.Parent  := grpDisplay;
  lblEditorColorScheme.Left    := INNER_LEFT;
  lblEditorColorScheme.Top     := lblOverlayShowOnHoverInfo.Top +
                                  lblOverlayShowOnHoverInfo.Height + 12;
  lblEditorColorScheme.Caption := _('Editor marker color scheme:');

  cboEditorColorScheme         := TComboBox.Create(Self);
  cboEditorColorScheme.Parent  := grpDisplay;
  cboEditorColorScheme.Left    := INNER_LEFT;
  cboEditorColorScheme.Top     := lblEditorColorScheme.Top +
                                  lblEditorColorScheme.Height + 2;
  cboEditorColorScheme.Width   := 220;
  cboEditorColorScheme.Style   := csDropDownList;
  cboEditorColorScheme.Items.Add(_('Default (bright colors)'));   // ecsDefault
  cboEditorColorScheme.Items.Add(_('Gray (neutral)'));            // ecsGray
  cboEditorColorScheme.Items.Add(_('Subtle (muted colors)'));     // ecsSubtle

  lblEditorColorSchemeInfo          := TLabel.Create(Self);
  lblEditorColorSchemeInfo.Parent   := grpDisplay;
  lblEditorColorSchemeInfo.AutoSize := False;
  lblEditorColorSchemeInfo.Left     := INNER_LEFT;
  lblEditorColorSchemeInfo.Top      := cboEditorColorScheme.Top +
                                       cboEditorColorScheme.Height + 4;
  lblEditorColorSchemeInfo.Width    := GROUP_W - 2 * INNER_LEFT;
  lblEditorColorSchemeInfo.Height   := 50;   // 30 + 20
  lblEditorColorSchemeInfo.WordWrap := True;
  lblEditorColorSchemeInfo.Caption  :=
    _('Affects only the editor marker stripe, mini-infobar and hover ' +
      'overlay titlebar. Properties Panel + main grid remain at the ' +
      'default severity colors. Light/Dark variants are automatic.');

  // GroupBox-Hoehe an die echten Children anpassen.
  // +112 statt +12 = User-Wunsch 100 px mehr Unter-Padding (rein optisch).
  // Achtung: dies aendert NICHT AY - das Vorgaenger-Layout schaltete den
  // Cursor immer um SECT_H_INIT(=332) weiter, nicht um die korrigierte
  // grpDisplay.Height. Refactor preserved das Verhalten 1:1.
  grpDisplay.Height := lblEditorColorSchemeInfo.Top +
                       lblEditorColorSchemeInfo.Height + 112;
end;

procedure TSCAOptionsFrame.BuildBaselineSection(AParent: TWinControl;
  var AY: Integer);
// "Nur neue Funde"-Filter: blendet Funde aus, deren Fingerprint in einer
// Baseline-JSON steht (Format = CLI --write-baseline / HTML-Export). Non-
// destruktiv - reiner Anzeige-Filter, Grid/Export behalten die Vollmenge.
const
  BTN_W = 32;
begin
  grpBaseline         := TGroupBox.Create(Self);
  grpBaseline.Parent  := AParent;
  grpBaseline.Left    := MARGIN_LEFT;
  grpBaseline.Top     := AY;
  grpBaseline.Width   := GROUP_W;
  grpBaseline.Caption := _('Baseline (show only new findings)');

  chkBaselineOnlyNew         := TCheckBox.Create(Self);
  chkBaselineOnlyNew.Parent  := grpBaseline;
  chkBaselineOnlyNew.Left    := INNER_LEFT;
  chkBaselineOnlyNew.Top     := INNER_TOP;
  chkBaselineOnlyNew.Width   := GROUP_W - 2 * INNER_LEFT;
  chkBaselineOnlyNew.Caption :=
    _('Show only findings new since the baseline (hide the legacy backlog)');

  lblBaselineFile         := TLabel.Create(Self);
  lblBaselineFile.Parent  := grpBaseline;
  lblBaselineFile.Left    := INNER_LEFT;
  lblBaselineFile.Top     := chkBaselineOnlyNew.Top + chkBaselineOnlyNew.Height + 12;
  lblBaselineFile.Caption := _('Baseline file:');

  edtBaselineFile         := TEdit.Create(Self);
  edtBaselineFile.Parent  := grpBaseline;
  edtBaselineFile.Left    := INNER_LEFT;
  edtBaselineFile.Top     := lblBaselineFile.Top + lblBaselineFile.Height + 4;
  edtBaselineFile.Width   := GROUP_W - 2 * INNER_LEFT - BTN_W - 6;

  btnBaselineBrowse         := TButton.Create(Self);
  btnBaselineBrowse.Parent  := grpBaseline;
  btnBaselineBrowse.Left    := edtBaselineFile.Left + edtBaselineFile.Width + 6;
  btnBaselineBrowse.Top     := edtBaselineFile.Top - 1;
  btnBaselineBrowse.Width   := BTN_W;
  btnBaselineBrowse.Height  := edtBaselineFile.Height + 2;
  btnBaselineBrowse.Caption := '...';
  btnBaselineBrowse.OnClick := BaselineBrowseClick;

  lblBaselineInfo          := TLabel.Create(Self);
  lblBaselineInfo.Parent   := grpBaseline;
  lblBaselineInfo.AutoSize := False;
  lblBaselineInfo.Left     := INNER_LEFT;
  lblBaselineInfo.Top      := edtBaselineFile.Top + edtBaselineFile.Height + 8;
  lblBaselineInfo.Width    := GROUP_W - 2 * INNER_LEFT;
  lblBaselineInfo.Height   := 64;
  lblBaselineInfo.WordWrap := True;
  lblBaselineInfo.Caption  :=
    _('Create a baseline from the current findings via the dock menu ' +
      '"Write baseline from current scan...", or with the CLI ' +
      '--write-baseline. The file is shared across CLI, IDE and HTML export. ' +
      'Takes effect on the next analysis.');

  grpBaseline.Height := lblBaselineInfo.Top + lblBaselineInfo.Height + 12;
  Inc(AY, grpBaseline.Height + GROUP_GAP);
end;

procedure TSCAOptionsFrame.BaselineBrowseClick(Sender: TObject);
var
  Dlg : TFileOpenDialog;
begin
  Dlg := TFileOpenDialog.Create(nil);
  try
    Dlg.Options := [fdoFileMustExist, fdoForceFileSystem];
    Dlg.Title   := _('Select baseline file');
    with Dlg.FileTypes.Add do
    begin
      DisplayName := _('Baseline JSON');
      FileMask    := '*.json';
    end;
    with Dlg.FileTypes.Add do
    begin
      DisplayName := _('All files');
      FileMask    := '*.*';
    end;
    if (Trim(edtBaselineFile.Text) <> '')
       and DirectoryExists(ExtractFilePath(edtBaselineFile.Text)) then
      Dlg.DefaultFolder := ExtractFilePath(edtBaselineFile.Text);
    if Dlg.Execute then
      edtBaselineFile.Text := Dlg.FileName;
  finally
    Dlg.Free;
  end;
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

  // Display: 'sameline' -> Index 0, 'below' -> Index 1, alles andere -> 0
  if Assigned(cboOverlayPos) then
  begin
    if SameText(ASettings.OverlayPosition, 'below') then
      cboOverlayPos.ItemIndex := 1
    else
      cboOverlayPos.ItemIndex := 0;
  end;
  if Assigned(chkOverlayShowOnHover) then
    chkOverlayShowOnHover.Checked := ASettings.OverlayShowOnHover;
  if Assigned(cboEditorColorScheme) then
    cboEditorColorScheme.ItemIndex :=
      ComboIndexFromScheme(ParseEditorColorScheme(ASettings.EditorColorScheme));

  // Baseline
  if Assigned(chkBaselineOnlyNew) then
    chkBaselineOnlyNew.Checked := ASettings.BaselineOnlyNew;
  if Assigned(edtBaselineFile) then
    edtBaselineFile.Text := ASettings.BaselineFile;
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

  // Display: Index 1 = below, alles andere = sameline
  if Assigned(cboOverlayPos) then
  begin
    if cboOverlayPos.ItemIndex = 1 then
      ASettings.OverlayPosition := 'below'
    else
      ASettings.OverlayPosition := 'sameline';
  end;
  if Assigned(chkOverlayShowOnHover) then
    ASettings.OverlayShowOnHover := chkOverlayShowOnHover.Checked;
  if Assigned(cboEditorColorScheme) then
  begin
    ASettings.EditorColorScheme := EditorColorSchemeToStr(
      SchemeFromComboIndex(cboEditorColorScheme.ItemIndex));
    // Cache sofort aktualisieren - sonst wirkt die Schema-Auswahl erst
    // beim naechsten BPL-Load. RefreshEditorColorSchemeCache ist
    // komplett defensiv.
    RefreshEditorColorSchemeCache(ASettings.EditorColorScheme);
  end;

  // Baseline
  if Assigned(chkBaselineOnlyNew) then
    ASettings.BaselineOnlyNew := chkBaselineOnlyNew.Checked;
  if Assigned(edtBaselineFile) then
    ASettings.BaselineFile := Trim(edtBaselineFile.Text);
end;

procedure TSCAOptionsFrame.ApplyHintStyleToAllInfoLabels;
// Stylet alle Info-Labels einheitlich (uIDEColors.StyleAsHintLabel -
// IDE_FG_DIM, 8pt, ParentFont aus). GroupBox-Captions bleiben unangetastet.
begin
  StyleAsHintLabel(lblSilentInfo);
  StyleAsHintLabel(lblOverlayPosInfo);
  StyleAsHintLabel(lblOverlayShowOnHoverInfo);
  StyleAsHintLabel(lblEditorColorSchemeInfo);
  StyleAsHintLabel(lblBaselineInfo);
end;

procedure TSCAOptionsFrame.CMStyleChanged(var Message: TMessage);
begin
  inherited;
  // VCL-broadcastet diese Message wenn der aktive Style wechselt.
  // Belt-and-suspenders zum TIDETheme-Subscribe - sollte einer der
  // beiden Pfade in einer IDE-Version mal nicht feuern, faengt der
  // andere es ab. Apply ist idempotent.
  if csDestroying in ComponentState then Exit;
  TIDETheme.Apply(Self);
end;

{ TSCAAddInOptions }

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

procedure TSCAAddInOptions.DoLoadFrame(AFrame: TCustomFrame);
// Werte aus analyser.ini ins Frame laden. Wrapper-try um Load-Fehler:
// kaputte/fehlende INI ergibt Default-Werte, kein Crash.
var
  Settings : TRepoSettings;
begin
  Settings := TRepoSettings.Create;
  try
    try Settings.Load; except end;
    TSCAOptionsFrame(AFrame).LoadFromSettings(Settings);
  finally
    Settings.Free;
  end;
end;

procedure TSCAAddInOptions.DoSaveFrame(AFrame: TCustomFrame);
// Werte aus Frame zurueck in analyser.ini. Doppel-try ist Absicht: Load
// merged bestehende Werte unter unseren (sonst wuerden andere Sections
// geloescht), Save persistiert das Result.
var
  Settings : TRepoSettings;
begin
  Settings := TRepoSettings.Create;
  try
    try Settings.Load; except end;
    TSCAOptionsFrame(AFrame).SaveToSettings(Settings);
    try Settings.Save; except end;
  finally
    Settings.Free;
  end;
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
