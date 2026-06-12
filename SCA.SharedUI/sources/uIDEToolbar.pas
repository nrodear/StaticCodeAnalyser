unit uIDEToolbar;

// Builder-Helper fuer die Toolbar-Zeilen des Analyser-Frames.
//
// ZWECK
//   Im Frame-Constructor wurden 3 Toolbar-Zeilen (PanelPath, PanelButtons,
//   PanelSearch) + 3 Label-Combo-Sub-Panels (Severity/Type/Profile) + 3
//   Spacer-Panels mit fast identischem Setup-Boilerplate gebaut. Insgesamt
//   ~108 Zeilen reine Property-Zuweisung. Diese Unit kapselt die drei
//   wiederkehrenden Patterns als statische Klassen-Methoden.
//
// API
//   TIDEToolbar.CreateRow        — TPanel alTop mit Padding (Outer-Row)
//   TIDEToolbar.AddSpacer        — TBevel alLeft mit fixer Breite (Gap)
//   TIDEToolbar.CreateLabelCombo — TPanel alLeft mit Label + Combo darin,
//                                  liefert die Combo zurueck (Items + OnChange
//                                  setzt der Aufrufer).
//
// DESIGN
//   - Alle Methoden sind class function — TIDEToolbar selbst hat keinen
//     Zustand, ist nur Namespace.
//   - Der Aufrufer haelt die Returns; Ownership liegt beim uebergebenen
//     AOwner (i.d.R. das Frame).
//   - Padding/Spacing-Konstanten kommen vom Aufrufer (DPI-skaliert) und
//     bleiben damit lokal zum Frame.
//   - Color wird NICHT gesetzt — TPanel.Color defaultet auf clBtnFace,
//     ParentBackground defaultet auf True, also paintet jedes Panel
//     ueber das aktive VCL-Style-Theme den richtigen Chrome-Hintergrund.
//     Beim IDE-Theme-Wechsel propagiert das via Style-Hooks automatisch.

interface

uses
  System.Classes,
  Vcl.Controls, Vcl.ExtCtrls, Vcl.StdCtrls;

type
  TIDEToolbar = class
  public
    // Outer-Row: TPanel alTop am AParent (i.d.R. das Frame).
    // - Hoehe = ARowHeight (vom Aufrufer DPI-skaliert)
    // - Padding rundherum, mit Right-Padding=0 fuer buendige rechte Kante
    //   (alRight-Buttons schliessen ohne Inset ab — matched optisch ueber
    //   alle drei Reihen).
    class function CreateRow(AOwner: TComponent; AParent: TWinControl;
      ARowHeight, APadLR, APadTB: Integer): TPanel; static;

    // Spacer: TBevel alLeft mit fixer Breite, unsichtbar (Shape=bsSpacer).
    // Wird zwischen Toolbar-Gruppen eingesetzt, damit der Abstand
    // konsistent ist. AWidth ist vom Aufrufer DPI-skaliert.
    // TBevel ist TGraphicControl (kein HWND) - leichter als TPanel:
    // kein Style-Hook, kein Window-Handle, ein Z-Order-Eintrag weniger.
    class procedure AddSpacer(AOwner: TComponent; ARow: TWinControl;
      AWidth: Integer); static;

    // Label+Combo-Bundle: TPanel alLeft, darauf TLabel alLeft + TComboBox
    // alClient. Returned die ComboBox, damit der Aufrufer Items.AddObject
    // + OnChange + Hint setzen kann. Das Sub-Panel-Layout verhindert die
    // VCL-Quirk dass Label+Combo direkt nebeneinander auf einem alLeft-
    // Parent in unterschiedlichen Align-Passes verschoben werden.
    //
    // AOut-Param ALabel: falls der Aufrufer den Label-Caption spaeter via
    // _() neu setzt (Language-Switch) oder auf das Label tippt.
    class function CreateLabelCombo(AOwner: TComponent; ARow: TWinControl;
      const ACaption: string;
      ALabelWidth, AComboWidth: Integer;
      out ALabel: TLabel): TComboBox; static;

    // Standalone-Label auf einer Toolbar-Zeile (Layout=tlCenter, AutoSize=
    // False, fixe Breite). Fuer Faelle wo der Label NICHT zu einer Combo
    // gehoert (z.B. "Search:"-Label vor TEdit) und CreateLabelCombo nicht
    // passt.
    class function AddLabel(AOwner: TComponent; ARow: TWinControl;
      const ACaption: string; AWidth: Integer): TLabel; static;

    // Standard-Button auf einer Toolbar-Zeile. Wenn AHint nicht leer,
    // werden Hint + ShowHint:=True gesetzt. AAlign bestimmt links/rechts.
    class function AddButton(AOwner: TComponent; ARow: TWinControl;
      const ACaption: string; AWidth: Integer; AAlign: TAlign;
      AOnClick: TNotifyEvent; const AHint: string = ''): TButton; static;

    // Setzt das Standard-Plugin-Font (Segoe UI, ASize) auf AControl,
    // mit ParentFont=False. Wird intern von CreateLabelCombo benutzt
    // und kann fuer Standalone-Controls (Frame, Grid, Edit, ComboBox)
    // direkt aufgerufen werden statt 3× Boilerplate.
    class procedure ApplySegoeUI(AControl: TControl;
      ASize: Integer = 8); static;
  end;

implementation

// noinspection-file CanBeStrictPrivate, ClassPerFile, ConsecutiveSection, LongParamList, PublicField, TooLongLine, UnusedPublicMember
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

type
  // Delphi friend-by-unit-Trick: TControl.Font und .ParentFont sind in
  // Vcl.Controls als protected deklariert und werden erst in Sub-Klassen
  // (TPanel/TButton/TLabel/TEdit/...) published. ApplySegoeUI nimmt aber
  // TControl als Basis-Typ, damit beliebige UI-Controls durchlaufen
  // koennen — der Cast TControlHack(AControl) macht die protected-Member
  // im Scope dieser Unit zugaenglich.
  TControlHack = class(TControl);

class function TIDEToolbar.CreateRow(AOwner: TComponent; AParent: TWinControl;
  ARowHeight, APadLR, APadTB: Integer): TPanel;
begin
  Result := TPanel.Create(AOwner);
  Result.Parent     := AParent;
  Result.Align      := alTop;
  Result.Height     := ARowHeight;
  Result.BevelOuter := bvNone;
  // Right-Padding bewusst 0 — alRight-Buttons docken buendig an die
  // rechte Frame-Kante.
  Result.Padding.SetBounds(APadLR, APadTB, 0, APadTB);
  // Color NICHT setzen — TPanel-Defaults (Color=clBtnFace,
  // ParentBackground=True) reichen: das VCL-Style malt den themed
  // Chrome-Hintergrund, Style-Hooks tracken spaetere Theme-Wechsel.
end;

class procedure TIDEToolbar.AddSpacer(AOwner: TComponent; ARow: TWinControl;
  AWidth: Integer);
var
  Bevel : TBevel;
begin
  Bevel := TBevel.Create(AOwner);
  Bevel.Parent := ARow;
  Bevel.Align  := alLeft;
  Bevel.Width  := AWidth;
  // bsSpacer macht den Bevel komplett unsichtbar (keine Linie, kein
  // Rahmen), nimmt nur Layout-Platz. Genau das was wir wollen.
  Bevel.Shape  := bsSpacer;
end;

class function TIDEToolbar.CreateLabelCombo(AOwner: TComponent;
  ARow: TWinControl; const ACaption: string;
  ALabelWidth, AComboWidth: Integer; out ALabel: TLabel): TComboBox;
var
  SubPanel : TPanel;
begin
  // Sub-Container: alLeft auf der Row, fixe Gesamt-Width (Label + Combo).
  SubPanel := TPanel.Create(AOwner);
  SubPanel.Parent     := ARow;
  SubPanel.Align      := alLeft;
  SubPanel.BevelOuter := bvNone;
  SubPanel.Width      := ALabelWidth + AComboWidth;

  // Label: alLeft im Sub-Container.
  ALabel := TLabel.Create(AOwner);
  ALabel.Parent   := SubPanel;
  ALabel.Caption  := ACaption;
  ALabel.Align    := alLeft;
  ALabel.AutoSize := False;
  ALabel.Width    := ALabelWidth;
  ALabel.Layout   := tlCenter;

  // Combo: alClient im Sub-Container, Standard-Font wie der Rest
  // der Toolbar (Segoe UI 8). ApplySegoeUI setzt ParentFont=False —
  // notwendig weil die IDE die Frame-Font beim Embedding manchmal
  // ueberschreibt.
  Result := TComboBox.Create(AOwner);
  Result.Parent := SubPanel;
  Result.Style  := csDropDownList;
  Result.Align  := alClient;
  ApplySegoeUI(Result);
end;

class function TIDEToolbar.AddLabel(AOwner: TComponent; ARow: TWinControl;
  const ACaption: string; AWidth: Integer): TLabel;
begin
  Result := TLabel.Create(AOwner);
  Result.Parent   := ARow;
  Result.Caption  := ACaption;
  Result.Align    := alLeft;
  Result.AutoSize := False;
  Result.Width    := AWidth;
  Result.Layout   := tlCenter;
end;

class function TIDEToolbar.AddButton(AOwner: TComponent; ARow: TWinControl;
  const ACaption: string; AWidth: Integer; AAlign: TAlign;
  AOnClick: TNotifyEvent; const AHint: string): TButton;
begin
  Result := TButton.Create(AOwner);
  Result.Parent  := ARow;
  Result.Caption := ACaption;
  Result.Width   := AWidth;
  Result.Align   := AAlign;
  Result.OnClick := AOnClick;
  // Hint+ShowHint-Pair nur wenn der Aufrufer einen Hint geliefert hat —
  // sonst bleibt ShowHint im Default (False), wie es auch im alten Code
  // fuer Buttons ohne Hint war.
  if AHint <> '' then
  begin
    Result.Hint     := AHint;
    Result.ShowHint := True;
  end;
end;

class procedure TIDEToolbar.ApplySegoeUI(AControl: TControl; ASize: Integer);
begin
  // Cast auf TControlHack (siehe Typ-Deklaration in implementation), damit
  // wir Font und ParentFont auf der TControl-Basis manipulieren koennen —
  // alle relevanten UI-Controls (TForm/TFrame/TPanel/TLabel/TButton/
  // TComboBox/TEdit/TMemo/TStringGrid) erben diese Properties.
  TControlHack(AControl).Font.Name := 'Segoe UI';
  TControlHack(AControl).Font.Size := ASize;
  TControlHack(AControl).ParentFont := False;
end;

end.
