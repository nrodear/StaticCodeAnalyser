unit uIDEStatusBar;

// Drei-Panel-Statusleiste am unteren Rand des Analyser-Frames:
//   * Panel 0 (links,  fix 160 px) - Befund-Counter ("X / Y findings")
//   * Panel 1 (mitte,  fix 220 px) - Datei-Progress / aktuelle Datei
//   * Panel 2 (rechts, full)       - Modus / Status-Meldungen / Fehler
//
// Vorher: TStatusBar-Field plus drei fast-identische Push-Methoden
// (StatusFindings/StatusProgress/StatusMode) direkt im Frame, plus
// Setup-Code im Constructor. Jetzt gekapselt - der Frame haelt nur
// noch die Instanz und delegiert die Push-Aufrufe.
//
// Defensiv: alle Push-Methoden pruefen Existenz des Bar-Widgets und
// Panel-Index-Bound. Damit kann der Frame waehrend des Constructors
// (vor StatusBar-Setup) und Destruktor-Pfade weiterhin StatusXxx-
// Aufrufe absetzen ohne AV.

interface

uses
  System.Classes,
  Vcl.Controls, Vcl.ComCtrls, Vcl.Forms;

type
  TAnalyserStatusBar = class(TComponent)
  private
    FBar : TStatusBar;
    procedure SetPanelText(Index: Integer; const T: string);
  public
    // Erstellt die TStatusBar als alBottom-Child von AParent mit den
    // drei Panels (Findings / Progress / Mode).
    // Die Default-Caption fuer Panel 2 wird vom Caller via Mode(_('Ready.'))
    // gesetzt - der Helper kennt keine Localization.
    constructor Create(AOwner: TComponent; AParent: TWinControl); reintroduce;

    // Panel-Push-Methoden (idempotent, AV-sicher).
    procedure Findings(const T: string);
    procedure Progress(const T: string);
    procedure Mode(const T: string);

    // Direkt-Zugriff auf die TStatusBar - fuer ApplyThemeRecursive und
    // andere Faelle die das Widget brauchen. Setter weglassen, ist
    // explizit read-only.
    property Bar: TStatusBar read FBar;
  end;

implementation

// noinspection-file WithStatement
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

// noinspection ConstructorWithoutInherited
// FP: 'inherited Create(AOwner)' wird auf Z67 explizit aufgerufen;
// Parser-Pattern fuer nkInherited erfasst die parameterized Form nicht.
constructor TAnalyserStatusBar.Create(AOwner: TComponent; AParent: TWinControl);
// Panel-Widths sind 96-DPI-Defaults. Auf Hi-DPI-Displays (150% / 200%)
// wachsen Schrift + Glyph-Groessen mit, die Panel-Breiten muessen
// entsprechend mitziehen. Vcl.Forms.Screen.PixelsPerInch ist auf der
// Hi-DPI-Skala 144 / 192 etc. - Skalierungsfaktor = PPI / 96.
const
  W_FINDINGS = 160; // "X / Y findings"
  W_PROGRESS = 220; // "Analysing file ..."
  W_MODE     = 5000; // letztes Panel — fuellt automatisch
var
  Scale: Single;

  function S(W: Integer): Integer;
  begin
    Result := Round(W * Scale);
  end;

begin
  inherited Create(AOwner);
  FBar := TStatusBar.Create(Self);
  FBar.Parent      := AParent;
  FBar.Align       := alBottom;
  FBar.SimplePanel := False;

  Scale := Screen.PixelsPerInch / 96;

  with FBar.Panels.Add do begin Width := S(W_FINDINGS); Text := ''; end;
  with FBar.Panels.Add do begin Width := S(W_PROGRESS); Text := ''; end;
  // Letztes Panel: TStatusBar streckt es automatisch auf die uebrige
  // Breite wenn Width gross genug ist. 5000 reicht auch fuer 4K.
  with FBar.Panels.Add do begin Width := S(W_MODE);     Text := ''; end;
end;

procedure TAnalyserStatusBar.SetPanelText(Index: Integer; const T: string);
begin
  if Assigned(FBar) and (Index >= 0) and (Index < FBar.Panels.Count) then
    FBar.Panels[Index].Text := T;
end;

procedure TAnalyserStatusBar.Findings(const T: string);
begin
  SetPanelText(0, T);
end;

procedure TAnalyserStatusBar.Progress(const T: string);
begin
  SetPanelText(1, T);
end;

procedure TAnalyserStatusBar.Mode(const T: string);
begin
  SetPanelText(2, T);
end;

end.
