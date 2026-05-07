unit uIDEHelpPanel;

// Rechtsseitiges Hilfe-Panel des Analyser-Frame-Plugins:
// zeigt pro selektiertem Befund die Beschreibung + Vorher/Nachher-Code-
// Beispiele (aus uFixHint). Im _docked_-Modus (Tool-Window in IDE-Tab/
// Side-Bar gedockt, typisch 200-400 px breit) blendet sich das Panel
// komplett aus, das Grid bekommt die volle Breite. Im _floating_-Modus
// (eigenes Fenster) erscheint es wieder auf 1/3 der Client-Breite.
//
// Vorher: 7 Felder (FHelpPanel + FHelpSplitter + FHelpDescLabel +
// FHelpBeforePanel + FHelpBefore + FHelpAfter + FDockStateTimer) plus
// 4 Methoden (HostIsFloating, SyncHelpVisibility, DockStateTimerTick,
// UpdateHelp) und ~140 Zeilen Constructor-Setup direkt in der
// God-Class TAnalyserFrame.
//
// Jetzt: ein Feld (FHintPanel: TFindingHintPanel) im Frame, der Rest
// gekapselt. Public API:
//   * Constructor(AOwner, AParent, AAnchor) baut alle Widgets auf
//     AParent und startet den Dock-State-Timer.
//   * ShowFinding(F)     - Befund-Details anzeigen.
//   * ShowPlaceholder    - "Zeile waehlen ..." Default-Text.
//   * ApplyLayout        - aus Frame.Resize aufrufen, macht Dock-Sync
//                          + 1/3-Breite + Vorher/Nachher-Verhaeltnis.
//   * Panel              - lesender Zugriff auf das aeussere TPanel
//                          fuer ApplyThemeRecursive.

interface

uses
  System.Classes,
  Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls,
  uMethodd12;

type
  TFindingHintPanel = class(TComponent)
  private
    FHelpPanel       : TPanel;
    FHelpSplitter    : TSplitter;
    FHelpDescLabel   : TLabel;
    FHelpBeforePanel : TPanel;
    FHelpBefore      : TMemo;
    FHelpAfter       : TMemo;
    FDockStateTimer  : TTimer;
    FAnchor          : TWinControl;

    function  HostIsFloating: Boolean;
    procedure SyncHelpVisibility;
    procedure DockStateTimerTick(Sender: TObject);
  public
    // AOwner    - Komponenten-Owner (typisch der Frame, fuer auto-Free).
    // AParent   - Container der das Panel aufnimmt (PanelClient des Frames).
    // AAnchor   - irgendein Control das im selben Form-Chain wie der Frame
    //             liegt; HostIsFloating laeuft den Parent-Chain hoch zur
    //             ersten TCustomForm. Typisch der Frame selbst.
    constructor Create(AOwner: TComponent;
                       AParent: TWinControl;
                       AAnchor: TWinControl); reintroduce;
    destructor Destroy; override;

    // Befund-Details setzen. Wenn der Detektor keinen Hint liefert,
    // wird automatisch der "kein Hinweis verfuegbar"-Text angezeigt.
    procedure ShowFinding(F: TLeakFinding);

    // Default-Text "Zeile waehlen fuer Loesungshinweis".
    procedure ShowPlaceholder;

    // Aus Frame.Resize aufrufen. Macht:
    //   1) Sync Help/Splitter Visible an HostIsFloating (auto-hide docked)
    //   2) Help-Panel auf 1/3 der Container-Breite (nur wenn Visible)
    //   3) Vorher/Nachher-Haelften gleichmaessig vertikal aufteilen
    procedure ApplyLayout;

    // Lesender Zugriff fuer Theme-Refresh-Code, der rekursiv ApplyTheme
    // an alle Sub-Controls anwendet.
    property Panel: TPanel read FHelpPanel;
  end;

implementation

uses
  System.SysUtils, Vcl.Graphics, Vcl.Themes, Vcl.Forms,
  uFixHint, uAnalyserPalette, uAnalyserTheme, uAnalyserTypes,
  uLocalization;

const
  HELP_PANEL_INIT_WIDTH = 360;
  HELP_PANEL_MIN_WIDTH  = 180;

constructor TFindingHintPanel.Create(AOwner: TComponent;
  AParent: TWinControl; AAnchor: TWinControl);
var
  HelpLeftSep         : TPanel;
  HelpCode            : TPanel;
  LblBefore           : TLabel;
  BeforeAfterSplitter : TSplitter;
  HelpAfterPanel      : TPanel;
  LblAfter            : TLabel;
begin
  inherited Create(AOwner);
  FAnchor := AAnchor;

  // ---- Outer panel: rechts an PanelClient angedockt ----
  FHelpPanel := TPanel.Create(Self);
  FHelpPanel.Parent              := AParent;
  FHelpPanel.Align               := alRight;
  FHelpPanel.Width               := HELP_PANEL_INIT_WIDTH;
  FHelpPanel.Constraints.MinWidth := HELP_PANEL_MIN_WIDTH;
  FHelpPanel.BevelOuter          := bvNone;
  FHelpPanel.Color               := clBtnFace;

  // 1px linke Trennlinie zwischen Grid und Help-Panel.
  HelpLeftSep := TPanel.Create(Self);
  HelpLeftSep.Parent     := FHelpPanel;
  HelpLeftSep.Align      := alLeft;
  HelpLeftSep.Width      := 1;
  HelpLeftSep.BevelOuter := bvNone;
  HelpLeftSep.Color      := cl3DDkShadow;

  FHelpDescLabel := TLabel.Create(Self);
  FHelpDescLabel.Parent      := FHelpPanel;
  FHelpDescLabel.Align       := alTop;
  FHelpDescLabel.Height      := 16;
  FHelpDescLabel.Layout      := tlCenter;
  FHelpDescLabel.Font.Name   := 'Segoe UI';
  FHelpDescLabel.Font.Size   := 8;
  FHelpDescLabel.Font.Style  := [fsBold];
  FHelpDescLabel.Font.Color  := clBtnText;
  FHelpDescLabel.Color       := clBtnFace;
  FHelpDescLabel.ParentColor := False;
  FHelpDescLabel.Caption     := '  ' + _('Select a row to see the fix hint');

  HelpCode := TPanel.Create(Self);
  HelpCode.Parent      := FHelpPanel;
  HelpCode.Align       := alClient;
  HelpCode.BevelOuter  := bvNone;
  HelpCode.Color       := clBtnFace;

  // ---- Vorher (oben) ----
  FHelpBeforePanel := TPanel.Create(Self);
  FHelpBeforePanel.Parent      := HelpCode;
  FHelpBeforePanel.Align       := alTop;
  FHelpBeforePanel.Height      := 150;
  FHelpBeforePanel.BevelOuter  := bvNone;
  FHelpBeforePanel.Color       := clWindow;

  LblBefore := TLabel.Create(Self);
  LblBefore.Parent      := FHelpBeforePanel;
  LblBefore.Align       := alTop;
  LblBefore.Height      := 14;
  LblBefore.Layout      := tlCenter;
  LblBefore.Caption     := '  ' + _('Before (problem)');
  LblBefore.Font.Name   := 'Segoe UI';
  LblBefore.Font.Size   := 8;
  LblBefore.Font.Style  := [fsBold];
  LblBefore.Font.Color  := SeverityAccent(fsError);
  LblBefore.ParentColor := True;

  FHelpBefore := TMemo.Create(Self);
  FHelpBefore.Parent      := FHelpBeforePanel;
  FHelpBefore.Align       := alClient;
  FHelpBefore.ReadOnly    := True;
  FHelpBefore.BorderStyle := bsNone;
  FHelpBefore.ScrollBars  := ssBoth;
  FHelpBefore.Color       := clWindow;
  FHelpBefore.Font.Name   := 'Consolas';
  FHelpBefore.Font.Size   := 8;
  FHelpBefore.Font.Color  := clWindowText;

  // ---- Splitter Vorher/Nachher ----
  BeforeAfterSplitter := TSplitter.Create(Self);
  BeforeAfterSplitter.Parent      := HelpCode;
  BeforeAfterSplitter.Align       := alTop;
  BeforeAfterSplitter.Height      := 4;
  BeforeAfterSplitter.Color       := cl3DDkShadow;
  BeforeAfterSplitter.ResizeStyle := rsUpdate;

  // ---- Nachher (Rest) ----
  HelpAfterPanel := TPanel.Create(Self);
  HelpAfterPanel.Parent      := HelpCode;
  HelpAfterPanel.Align       := alClient;
  HelpAfterPanel.BevelOuter  := bvNone;
  HelpAfterPanel.Color       := clWindow;

  LblAfter := TLabel.Create(Self);
  LblAfter.Parent      := HelpAfterPanel;
  LblAfter.Align       := alTop;
  LblAfter.Height      := 14;
  LblAfter.Layout      := tlCenter;
  LblAfter.Caption     := '  ' + _('After (solution)');
  LblAfter.Font.Name   := 'Segoe UI';
  LblAfter.Font.Size   := 8;
  LblAfter.Font.Style  := [fsBold];
  LblAfter.Font.Color  := SeverityAccent(fsHint);
  LblAfter.ParentColor := True;

  FHelpAfter := TMemo.Create(Self);
  FHelpAfter.Parent      := HelpAfterPanel;
  FHelpAfter.Align       := alClient;
  FHelpAfter.ReadOnly    := True;
  FHelpAfter.BorderStyle := bsNone;
  FHelpAfter.ScrollBars  := ssBoth;
  FHelpAfter.Color       := clWindow;
  FHelpAfter.Font.Name   := 'Consolas';
  FHelpAfter.Font.Size   := 8;
  FHelpAfter.Font.Color  := clWindowText;

  // ---- Splitter Grid|Help (Visible folgt FHelpPanel) ----
  FHelpSplitter := TSplitter.Create(Self);
  FHelpSplitter.Parent      := AParent;
  FHelpSplitter.Align       := alRight;
  FHelpSplitter.Width       := 4;
  FHelpSplitter.Color       := cl3DDkShadow;
  FHelpSplitter.ResizeStyle := rsUpdate;

  // ---- Polling-Timer fuer Floating/Docked-Detection ----
  // Resize feuert beim Re-Dock zu frueh (Floating-Property noch alter Wert);
  // 250 ms Polling sieht den Wechsel zuverlaessig binnen <250 ms.
  FDockStateTimer := TTimer.Create(Self);
  FDockStateTimer.Interval := 250;
  FDockStateTimer.OnTimer  := DockStateTimerTick;
  FDockStateTimer.Enabled  := True;
end;

destructor TFindingHintPanel.Destroy;
begin
  // Timer fruehzeitig stoppen, damit ein letzter Tick nicht auf bereits
  // genullte Widgets zugreift. Eigentliches Free passiert via Owner.
  if Assigned(FDockStateTimer) then
    FDockStateTimer.Enabled := False;
  inherited;
end;

function TFindingHintPanel.HostIsFloating: Boolean;
// Sucht im Parent-Chain die hostende TCustomForm und liefert deren
// Floating-Status. Im IDE-Plugin ist das die INTACustomDockableForm-
// Wrapper-Form: Floating=True wenn der Tool-Window geloest steht,
// False wenn er an einer Dock-Site (Tab, Side-Bar) angedockt ist.
var P: TWinControl;
begin
  Result := False;
  if not Assigned(FAnchor) then Exit;
  P := FAnchor.Parent;
  while Assigned(P) do
  begin
    if P is TCustomForm then
      Exit(TCustomForm(P).Floating);
    P := P.Parent;
  end;
end;

procedure TFindingHintPanel.SyncHelpVisibility;
// Setzt FHelpPanel + FHelpSplitter sichtbar/unsichtbar passend zum
// Floating-Status. Idempotent - kein Aufruf wenn Status unveraendert.
var ShowHelp: Boolean;
begin
  ShowHelp := HostIsFloating;
  if Assigned(FHelpPanel)    and (FHelpPanel.Visible    <> ShowHelp) then
    FHelpPanel.Visible    := ShowHelp;
  if Assigned(FHelpSplitter) and (FHelpSplitter.Visible <> ShowHelp) then
    FHelpSplitter.Visible := ShowHelp;
end;

procedure TFindingHintPanel.DockStateTimerTick(Sender: TObject);
begin
  SyncHelpVisibility;
end;

procedure TFindingHintPanel.ApplyLayout;
var
  ShowHelp : Boolean;
  ParentW  : Integer;
  ThirdW   : Integer;
  HalfW    : Integer;
begin
  SyncHelpVisibility;
  ShowHelp := HostIsFloating;

  // 1/3-Breite nur wenn Panel sichtbar ist.
  if ShowHelp and Assigned(FHelpPanel) and Assigned(FHelpPanel.Parent) then
  begin
    ParentW := FHelpPanel.Parent.ClientWidth;
    ThirdW  := ParentW div 3;
    if ThirdW > FHelpPanel.Constraints.MinWidth then
      FHelpPanel.Width := ThirdW;
  end;

  // Vorher/Nachher gleichmaessig vertikal teilen.
  if ShowHelp and Assigned(FHelpBeforePanel) and Assigned(FHelpBeforePanel.Parent) then
  begin
    HalfW := (FHelpBeforePanel.Parent.Height - 5) div 2; // -5 fuer Splitter
    if HalfW > 40 then
      FHelpBeforePanel.Height := HalfW;
  end;
end;

procedure TFindingHintPanel.ShowPlaceholder;
begin
  FHelpDescLabel.Caption := '  ' + _('Select a row to see the fix hint');
  FHelpDescLabel.Color   := StyleServices.GetSystemColor(clBtnFace);
  FHelpBefore.Lines.Text := '';
  FHelpAfter.Lines.Text  := '';
end;

procedure TFindingHintPanel.ShowFinding(F: TLeakFinding);
var
  Hint         : TFixHint;
  ColorDefault : TColor;
begin
  ColorDefault := StyleServices.GetSystemColor(clBtnFace);

  if not Assigned(F) then
  begin
    ShowPlaceholder;
    Exit;
  end;

  Hint := TFixHintResolver.FixHint(F);

  if Hint.Description = '' then
  begin
    FHelpDescLabel.Caption := '  ' + _('No fix hint available.');
    FHelpDescLabel.Color   := ColorDefault;
    FHelpBefore.Lines.Text := '';
    FHelpAfter.Lines.Text  := '';
    Exit;
  end;

  // Severity-Akzent als Hintergrund des Beschriftungs-Labels.
  FHelpDescLabel.Color :=
    SeverityBg(SeverityFromKindLevel(F.Kind, F.Severity), clBtnFace);
  if FHelpDescLabel.Color = clNone then
    FHelpDescLabel.Color := ColorDefault;

  FHelpDescLabel.Caption := '  ' + Hint.Description;
  FHelpBefore.Lines.Text := Hint.Before;
  FHelpAfter.Lines.Text  := Hint.After;
end;

end.
