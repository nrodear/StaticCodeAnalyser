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
  Winapi.Windows,                                     // VK_TAB / VK_ESCAPE / VK_BACK ...
  Winapi.Messages,                                    // TMessage / CM_STYLECHANGED
  System.Classes, System.SysUtils, System.UITypes,    // clGrayText
  Vcl.Graphics,                                       // TFontStyle (fsBold)
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Menus,                                          // ShortCut / TextToShortCut / ShortCutToText
  ToolsAPI,
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
    // Hotkeys
    grpHotkeys           : TGroupBox;
    chkShortcutsEnabled  : TCheckBox;     // Master-Toggle - oben in der Gruppe
    lblMasterInfo        : TLabel;
    chkFindingNavEnabled : TCheckBox;
    lblFindingNavInfo    : TLabel;
    lblShortcutsCaption  : TLabel;
    lblShortcutSilent    : TLabel;
    edShortcutSilent     : TEdit;
    lblShortcutUp        : TLabel;
    edShortcutUp         : TEdit;
    lblShortcutDown      : TLabel;
    edShortcutDown       : TEdit;
    lblRestartHint       : TLabel;
    lblGridShortcuts     : TLabel;
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
    chkAutoExpandAnnotation : TCheckBox;
    lblAutoExpandInfo       : TLabel;
    chkOverlayShowOnHover   : TCheckBox;
    lblOverlayShowOnHoverInfo : TLabel;
    lblEditorColorScheme    : TLabel;
    cboEditorColorScheme    : TComboBox;
    lblEditorColorSchemeInfo: TLabel;
  private
    procedure BuildControls;
    procedure PopulateProfileCombos;
    procedure PopulateMinSevCombo;
    // KeyDown-Capture (cnpack-Stil): User klickt in das Edit + drueckt eine
    // Tastenkombi; wir schreiben die ShortCutToText-Repraesentation rein.
    procedure ShortcutEditKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    // VCL-Style-Wechsel via Application.Broadcast - feuert zuverlaessiger
    // als der TIDETheme-Subscribe in manchen IDE-Versionen. Beide Pfade
    // rufen Apply auf das Frame; Apply ist idempotent.
    procedure CMStyleChanged(var Message: TMessage); message CM_STYLECHANGED;
    // Hint-Style fuer alle Info-Labels (IDE_FG_DIM, 8pt) - exakt wie in
    // uIDESonarOptions, damit die zwei Options-Pages optisch konsistent
    // wirken. Wird einmal nach BuildControls aufgerufen.
    procedure StyleAsHint(L: TLabel);
    procedure ApplyHintStyleToAllInfoLabels;
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
    FFrame    : TSCAOptionsFrame;
    // IDE-Theme-Abo: TIDETheme ruft OnThemeChanged bei jedem Wechsel.
    // Wird in FrameCreated angelegt, in DialogClosed entsorgt.
    FThemeSub : IInterface;
    procedure OnThemeChanged;
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

var
  GSCAOptionsIfc : INTAAddInOptions = nil;
  GSCAOptionsObj : TSCAAddInOptions = nil;

{ TSCAOptionsFrame }

constructor TSCAOptionsFrame.Create(AOwner: TComponent);
begin
  inherited;
  Name    := '';       // keinen Komponenten-Namen fuer den Frame
  BuildControls;
  // Optisches Match zur Sonar-Options-Page (uIDESonarOptions):
  //   * KEIN ApplySegoeUI auf Self - Sonar erbt den IDE-Default-Font;
  //     wenn wir Segoe UI 8 erzwingen wuerden, weicht SCA optisch ab.
  //   * Info-Labels bekommen IDE_FG_DIM + 8pt (= Sonar-Hint-Style).
  //   * Keine Bold-GroupBox-Captions (Sonar hat das nicht).
  ApplyHintStyleToAllInfoLabels;
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
    // noinspection UninitVar
    // Y (outer) wird im outer-Body initialisiert bevor NextY aufgerufen
    // wird; FP des Nested-Closure-Pattern.
    Result := Y;
    Y := Y + AHeight + GROUP_GAP;
  end;

begin
  // ---- Scroll-Container ----
  // Frame fuellt sich selbst (Tools > Options legt das in eine fixed-size
  // Page). Der ScrollBox darin fuellt das Frame komplett (alClient) und
  // adapter die VertScrollBar-Range automatisch an die GroupBox-Hoehen.
  // Settings haben mittlerweile 4 Gruppen (Silent/Hotkeys/RuleSet/Detectors)
  // mit kumulativ ~700+ Pixel - ohne Scroll waeren die unteren nicht
  // erreichbar auf kleineren Options-Dialogen.
  FScroll              := TScrollBox.Create(Self);
  FScroll.Parent       := Self;
  FScroll.Align        := alClient;
  FScroll.BorderStyle  := bsNone;
  FScroll.AutoScroll   := True;
  FScroll.VertScrollBar.Tracking  := True;
  FScroll.HorzScrollBar.Visible   := False;

  Y := MARGIN_TOP;
  // ================= Silent Mode =================
  // Hoehe 120 deckt Checkbox (22) + Info-Label mit 2 Zeilen WordWrap ab.
  grpSilent              := TGroupBox.Create(Self);
  grpSilent.Parent       := FScroll;
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
  grpRuleSet.Parent       := FScroll;
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
  grpDetectors.Parent     := FScroll;
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

  // ================= Display =================
  // Annotation-Overlay Position. Combo mit zwei Modi:
  //   sameline (Default) - Overlay startet AUF der Finding-Zeile
  //   below             - Overlay startet eine Zeile unter der Finding-Zeile
  // Aenderung greift erst nach IDE-Neustart (Cache in uIDELineHighlighter).
  grpDisplay              := TGroupBox.Create(Self);
  grpDisplay.Parent       := FScroll;
  grpDisplay.Left         := MARGIN_LEFT;
  grpDisplay.Top          := NextY(332);   // 232 + 100 User-Wunsch
  grpDisplay.Width        := GROUP_W;
  grpDisplay.Height       := 332;          // wird unten dynamisch korrigiert
  grpDisplay.Caption      := _('Display');

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
  lblOverlayPosInfo.Height   := 28;
  lblOverlayPosInfo.WordWrap := True;
  lblOverlayPosInfo.Caption  :=
    _('Where the hover annotation overlay anchors relative to the finding ' +
      'line. Takes effect after IDE restart.');

  chkAutoExpandAnnotation         := TCheckBox.Create(Self);
  chkAutoExpandAnnotation.Parent  := grpDisplay;
  chkAutoExpandAnnotation.Left    := INNER_LEFT;
  chkAutoExpandAnnotation.Top     := lblOverlayPosInfo.Top + lblOverlayPosInfo.Height + 10;
  chkAutoExpandAnnotation.Width   := GROUP_W - 2 * INNER_LEFT;
  chkAutoExpandAnnotation.Caption :=
    _('Auto-expand annotation overlay on hover');

  lblAutoExpandInfo          := TLabel.Create(Self);
  lblAutoExpandInfo.Parent   := grpDisplay;
  lblAutoExpandInfo.AutoSize := False;
  lblAutoExpandInfo.Left     := INNER_LEFT;
  lblAutoExpandInfo.Top      := chkAutoExpandAnnotation.Top + chkAutoExpandAnnotation.Height + 4;
  lblAutoExpandInfo.Width    := GROUP_W - 2 * INNER_LEFT;
  lblAutoExpandInfo.Height   := 30;
  lblAutoExpandInfo.WordWrap := True;
  lblAutoExpandInfo.Caption  :=
    _('When OFF (default): overlay stays as a compact title bar until ' +
      'you click the title - keeps the editor uncluttered. When ON: ' +
      'overlay auto-expands after ~250 ms.');

  chkOverlayShowOnHover         := TCheckBox.Create(Self);
  chkOverlayShowOnHover.Parent  := grpDisplay;
  chkOverlayShowOnHover.Left    := INNER_LEFT;
  chkOverlayShowOnHover.Top     := lblAutoExpandInfo.Top + lblAutoExpandInfo.Height + 8;
  chkOverlayShowOnHover.Width   := GROUP_W - 2 * INNER_LEFT;
  chkOverlayShowOnHover.Caption :=
    _('Show annotation overlay on hover');

  lblOverlayShowOnHoverInfo          := TLabel.Create(Self);
  lblOverlayShowOnHoverInfo.Parent   := grpDisplay;
  lblOverlayShowOnHoverInfo.AutoSize := False;
  lblOverlayShowOnHoverInfo.Left     := INNER_LEFT;
  lblOverlayShowOnHoverInfo.Top      := chkOverlayShowOnHover.Top + chkOverlayShowOnHover.Height + 4;
  lblOverlayShowOnHoverInfo.Width    := GROUP_W - 2 * INNER_LEFT;
  lblOverlayShowOnHoverInfo.Height   := 30;
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
  lblEditorColorSchemeInfo.Height   := 30;
  lblEditorColorSchemeInfo.WordWrap := True;
  lblEditorColorSchemeInfo.Caption  :=
    _('Affects only the editor marker stripe, mini-infobar and hover ' +
      'overlay titlebar. Properties Panel + main grid remain at the ' +
      'default severity colors. Light/Dark variants are automatic.');

  // GroupBox-Hoehe an die echten Children anpassen.
  // +112 statt +12 = User-Wunsch 100 px mehr Unter-Padding (rein optisch).
  grpDisplay.Height := lblEditorColorSchemeInfo.Top +
                       lblEditorColorSchemeInfo.Height + 112;

  // ================= Hotkeys ================= (BOTTOM)
  // Bewusst als letzte Gruppe positioniert - Shortcut-Konfiguration ist
  // unten in den Settings, weil sie selten geaendert wird und in der ueb-
  // lichen "scroll to see more" Lese-Reihenfolge der Page steht.
  //
  // Struktur:
  //   * chkShortcutsEnabled         = Master-Toggle ueber ALLE Shortcuts
  //   * chkFindingNavEnabled + Info = Per-Feature-Toggle Befund-Navigation
  //   * Drei TEdit-Felder (cnpack-Stil): klick + Tastenkombi -> ShortCutToText
  //   * Restart-Hinweis (italic) + nicht-konfigurierbare Grid-Shortcuts
  grpHotkeys              := TGroupBox.Create(Self);
  grpHotkeys.Parent       := FScroll;
  grpHotkeys.Left         := MARGIN_LEFT;
  grpHotkeys.Top          := NextY(360);
  grpHotkeys.Width        := GROUP_W;
  grpHotkeys.Height       := 360;
  grpHotkeys.Caption      := _('Hotkeys');

  // ---- Master-Toggle (alle Shortcuts) ----
  chkShortcutsEnabled         := TCheckBox.Create(Self);
  chkShortcutsEnabled.Parent  := grpHotkeys;
  chkShortcutsEnabled.Left    := INNER_LEFT;
  chkShortcutsEnabled.Top     := INNER_TOP;
  chkShortcutsEnabled.Width   := GROUP_W - 2 * INNER_LEFT;
  chkShortcutsEnabled.Caption := _('Enable all keyboard shortcuts (master toggle)');
  chkShortcutsEnabled.Font.Style := [fsBold];

  lblMasterInfo               := TLabel.Create(Self);
  lblMasterInfo.Parent        := grpHotkeys;
  lblMasterInfo.AutoSize      := False;
  lblMasterInfo.Left          := INNER_LEFT + 16;
  lblMasterInfo.Top           := chkShortcutsEnabled.Top + chkShortcutsEnabled.Height + 4;
  lblMasterInfo.Width         := GROUP_W - 2 * INNER_LEFT - 16;
  lblMasterInfo.Height        := 28;
  lblMasterInfo.WordWrap      := True;
  lblMasterInfo.Caption       :=
    _('Disable to mute every plugin shortcut at once. Right-click menu + ' +
      'toolbar buttons remain functional.');

  // ---- Per-Feature: Befund-Navigation ----
  chkFindingNavEnabled         := TCheckBox.Create(Self);
  chkFindingNavEnabled.Parent  := grpHotkeys;
  chkFindingNavEnabled.Left    := INNER_LEFT;
  chkFindingNavEnabled.Top     := lblMasterInfo.Top + lblMasterInfo.Height + 8;
  chkFindingNavEnabled.Width   := GROUP_W - 2 * INNER_LEFT;
  chkFindingNavEnabled.Caption :=
    _('Enable finding navigation (Ctrl+Alt+Up / Ctrl+Alt+Down)');

  lblFindingNavInfo            := TLabel.Create(Self);
  lblFindingNavInfo.Parent     := grpHotkeys;
  lblFindingNavInfo.AutoSize   := False;
  lblFindingNavInfo.Left       := INNER_LEFT + 16;
  lblFindingNavInfo.Top        := chkFindingNavEnabled.Top + chkFindingNavEnabled.Height + 4;
  lblFindingNavInfo.Width      := GROUP_W - 2 * INNER_LEFT - 16;
  lblFindingNavInfo.Height     := 28;
  lblFindingNavInfo.WordWrap   := True;
  lblFindingNavInfo.Caption    :=
    _('Jump to the next / previous highlighted finding line in the current ' +
      'editor tab (wrap-around at file end/start).');

  // ---- Konfigurierbare Shortcuts (cnpack-Stil) ----
  lblShortcutsCaption           := TLabel.Create(Self);
  lblShortcutsCaption.Parent    := grpHotkeys;
  lblShortcutsCaption.Left      := INNER_LEFT;
  lblShortcutsCaption.Top       := lblFindingNavInfo.Top + lblFindingNavInfo.Height + 10;
  lblShortcutsCaption.AutoSize  := True;
  lblShortcutsCaption.Caption   := _('Configurable shortcuts (click into field + press key combo):');
  lblShortcutsCaption.Font.Style := [fsBold];

  const SHORTCUT_LBL_W = 220;
  const SHORTCUT_EDIT_W = 160;
  var Y0 := lblShortcutsCaption.Top + lblShortcutsCaption.Height + 6;

  // Silent-Analyse-Shortcut
  lblShortcutSilent          := TLabel.Create(Self);
  lblShortcutSilent.Parent   := grpHotkeys;
  lblShortcutSilent.Left     := INNER_LEFT;
  lblShortcutSilent.Top      := Y0 + 3;
  lblShortcutSilent.AutoSize := False;
  lblShortcutSilent.Width    := SHORTCUT_LBL_W;
  lblShortcutSilent.Caption  := _('Silent analysis:');
  edShortcutSilent           := TEdit.Create(Self);
  edShortcutSilent.Parent    := grpHotkeys;
  edShortcutSilent.Left      := INNER_LEFT + SHORTCUT_LBL_W;
  edShortcutSilent.Top       := Y0;
  edShortcutSilent.Width     := SHORTCUT_EDIT_W;
  edShortcutSilent.OnKeyDown := ShortcutEditKeyDown;
  Inc(Y0, 26);

  // Finding-Nav Up
  lblShortcutUp              := TLabel.Create(Self);
  lblShortcutUp.Parent       := grpHotkeys;
  lblShortcutUp.Left         := INNER_LEFT;
  lblShortcutUp.Top          := Y0 + 3;
  lblShortcutUp.AutoSize     := False;
  lblShortcutUp.Width        := SHORTCUT_LBL_W;
  lblShortcutUp.Caption      := _('Jump to previous finding:');
  edShortcutUp               := TEdit.Create(Self);
  edShortcutUp.Parent        := grpHotkeys;
  edShortcutUp.Left          := INNER_LEFT + SHORTCUT_LBL_W;
  edShortcutUp.Top           := Y0;
  edShortcutUp.Width         := SHORTCUT_EDIT_W;
  edShortcutUp.OnKeyDown     := ShortcutEditKeyDown;
  Inc(Y0, 26);

  // Finding-Nav Down
  lblShortcutDown            := TLabel.Create(Self);
  lblShortcutDown.Parent     := grpHotkeys;
  lblShortcutDown.Left       := INNER_LEFT;
  lblShortcutDown.Top        := Y0 + 3;
  lblShortcutDown.AutoSize   := False;
  lblShortcutDown.Width      := SHORTCUT_LBL_W;
  lblShortcutDown.Caption    := _('Jump to next finding:');
  edShortcutDown             := TEdit.Create(Self);
  edShortcutDown.Parent      := grpHotkeys;
  edShortcutDown.Left        := INNER_LEFT + SHORTCUT_LBL_W;
  edShortcutDown.Top         := Y0;
  edShortcutDown.Width       := SHORTCUT_EDIT_W;
  edShortcutDown.OnKeyDown   := ShortcutEditKeyDown;
  Inc(Y0, 30);

  // Restart-Hinweis (italic)
  lblRestartHint             := TLabel.Create(Self);
  lblRestartHint.Parent      := grpHotkeys;
  lblRestartHint.Left        := INNER_LEFT;
  lblRestartHint.Top         := Y0;
  lblRestartHint.AutoSize    := False;
  lblRestartHint.Width       := GROUP_W - 2 * INNER_LEFT;
  lblRestartHint.Height      := 16;
  lblRestartHint.Caption     := _('Changes take effect after restarting the IDE.');
  lblRestartHint.Font.Style  := [fsItalic];
  Inc(Y0, 22);

  // Nicht-konfigurierbare Grid-Shortcuts als Read-only-Hinweis.
  lblGridShortcuts           := TLabel.Create(Self);
  lblGridShortcuts.Parent    := grpHotkeys;
  lblGridShortcuts.Left      := INNER_LEFT;
  lblGridShortcuts.Top       := Y0;
  lblGridShortcuts.AutoSize  := False;
  lblGridShortcuts.Width     := GROUP_W - 2 * INNER_LEFT;
  lblGridShortcuts.Height    := 32;
  lblGridShortcuts.WordWrap  := True;
  lblGridShortcuts.Caption   :=
    _('Findings-grid shortcuts (not configurable): Ctrl+Alt+F = Quick-Fix, ' +
      'Ctrl+Alt+S = Suppression, Enter = goto editor line.');
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

  // Hotkeys
  if Assigned(chkShortcutsEnabled) then
    chkShortcutsEnabled.Checked := ASettings.ShortcutsEnabled;
  if Assigned(chkFindingNavEnabled) then
    chkFindingNavEnabled.Checked := ASettings.FindingNavEnabled;
  if Assigned(edShortcutSilent) then
    edShortcutSilent.Text := ASettings.SilentAnalyseShortcut;
  if Assigned(edShortcutUp) then
    edShortcutUp.Text := ASettings.FindingNavUpShortcut;
  if Assigned(edShortcutDown) then
    edShortcutDown.Text := ASettings.FindingNavDownShortcut;

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
  if Assigned(chkAutoExpandAnnotation) then
    chkAutoExpandAnnotation.Checked := ASettings.AutoExpandAnnotation;
  if Assigned(chkOverlayShowOnHover) then
    chkOverlayShowOnHover.Checked := ASettings.OverlayShowOnHover;
  if Assigned(cboEditorColorScheme) then
    cboEditorColorScheme.ItemIndex :=
      ComboIndexFromScheme(ParseEditorColorScheme(ASettings.EditorColorScheme));
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

  if Assigned(chkShortcutsEnabled) then
    ASettings.ShortcutsEnabled := chkShortcutsEnabled.Checked;
  if Assigned(chkFindingNavEnabled) then
    ASettings.FindingNavEnabled := chkFindingNavEnabled.Checked;
  if Assigned(edShortcutSilent) then
    ASettings.SilentAnalyseShortcut := Trim(edShortcutSilent.Text);
  if Assigned(edShortcutUp) then
    ASettings.FindingNavUpShortcut := Trim(edShortcutUp.Text);
  if Assigned(edShortcutDown) then
    ASettings.FindingNavDownShortcut := Trim(edShortcutDown.Text);

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
  if Assigned(chkAutoExpandAnnotation) then
    ASettings.AutoExpandAnnotation := chkAutoExpandAnnotation.Checked;
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
end;

procedure TSCAOptionsFrame.StyleAsHint(L: TLabel);
// 1:1 wie Sonar-Options-Page (uIDESonarOptions.lblTokenInfo):
//   * IDE_FG_DIM = semantische Theme-Farbe (faellt im Dark-Theme auf
//     den richtigen Grau-Ton, statt hartkodiert clGrayText).
//   * Font.Size := 8 + ParentFont := False - 8pt statt Default 9pt
//     damit Hint-Text subtler als Field-Labels wirkt; ParentFont OFF
//     damit Theme-Wechsel den Size nicht zurueckschiebt.
//   * Kein italic - Sonar nutzt das auch nicht.
begin
  if not Assigned(L) then Exit;
  L.ParentFont := False;
  L.Font.Size  := 8;
  L.Font.Color := IDE_FG_DIM;
end;

procedure TSCAOptionsFrame.ApplyHintStyleToAllInfoLabels;
// Stylet alle Info-Labels einheitlich als Sonar-Hint (IDE_FG_DIM, 8pt).
// GroupBox-Captions bleiben unangetastet - Sonar-Look hat keine Bold-
// Captions, das wirkte aufgesetzt und vererbte Bold an die Children.
begin
  StyleAsHint(lblSilentInfo);
  StyleAsHint(lblOverlayPosInfo);
  StyleAsHint(lblAutoExpandInfo);
  StyleAsHint(lblOverlayShowOnHoverInfo);
  StyleAsHint(lblEditorColorSchemeInfo);
  StyleAsHint(lblMasterInfo);
  StyleAsHint(lblFindingNavInfo);
  StyleAsHint(lblRestartHint);
  StyleAsHint(lblGridShortcuts);
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

procedure TSCAOptionsFrame.ShortcutEditKeyDown(Sender: TObject;
  var Key: Word; Shift: TShiftState);
// Capture-Mechanik analog cnpack: User klickt in eines der drei Edit-Felder
// und drueckt die gewuenschte Tastenkombi - wir schreiben den menschen-
// lesbaren ShortCutToText-String ins Feld. User kann auch manuell tippen
// (TEdit ist normal editierbar).
//
// Wir ignorieren reine Modifier-Tasten (Shift/Strg/Alt alleine), Tab
// (sonst kann der User das Feld nicht mehr verlassen), und Backspace
// (User soll loeschen koennen). Escape leert das Feld.
var
  SC : TShortCut;
begin
  // Reine Modifier-Tasten alleine ignorieren - sonst flackert das Feld bei
  // jedem Strg-Druck zwischen leerem String und der vorigen Belegung.
  if (Key = VK_SHIFT) or (Key = VK_CONTROL) or (Key = VK_MENU)
     or (Key = VK_LWIN) or (Key = VK_RWIN) then
    Exit;
  // Tab + Backspace durchlassen (Navigation + Editier-Standard).
  if (Key = VK_TAB) or (Key = VK_BACK) then Exit;
  // Escape = Feld leeren (= "Default-Bindung verwenden").
  if Key = VK_ESCAPE then
  begin
    (Sender as TEdit).Text := '';
    Key := 0;
    Exit;
  end;
  SC := Vcl.Menus.ShortCut(Key, Shift);
  if SC = 0 then Exit;
  (Sender as TEdit).Text := Vcl.Menus.ShortCutToText(SC);
  Key := 0;  // Tastendruck konsumieren, kein weiteres TEdit-Standard-Verhalten
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
  TIDETheme.Apply(FFrame);
  // Theme-Live-Update: falls der User mid-Options-Dialog die
  // "IDE Style"-Option umstellt (gleicher Dialog!), aktualisiert
  // OnThemeChanged unseren Frame automatisch.
  FThemeSub := TIDETheme.Subscribe(OnThemeChanged);
end;

procedure TSCAAddInOptions.OnThemeChanged;
begin
  if Assigned(FFrame) then
    TIDETheme.Apply(FFrame);
end;

procedure TSCAAddInOptions.DialogClosed(Accepted: Boolean);
// User hat OK oder Cancel geklickt. Bei OK speichern wir die Werte zurueck
// in analyser.ini. Bei Cancel ignorieren wir die UI-Aenderungen.
var
  Settings : TRepoSettings;
begin
  try
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
  finally
    // Theme-Subscription aufloesen - IDE gibt FFrame nach DialogClosed
    // frei; ein noch lebendes Abo wuerde beim naechsten Theme-Wechsel
    // in die freigegebene Frame-Referenz feuern.
    FThemeSub := nil;
    FFrame := nil;
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
