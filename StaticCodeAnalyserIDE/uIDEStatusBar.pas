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
  Vcl.Controls, Vcl.ComCtrls;

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

constructor TAnalyserStatusBar.Create(AOwner: TComponent; AParent: TWinControl);
begin
  inherited Create(AOwner);
  FBar := TStatusBar.Create(Self);
  FBar.Parent      := AParent;
  FBar.Align       := alBottom;
  FBar.SimplePanel := False;

  with FBar.Panels.Add do begin Width := 160;  Text := ''; end; // Findings
  with FBar.Panels.Add do begin Width := 220;  Text := ''; end; // Progress
  // Letztes Panel: TStatusBar streckt es automatisch auf alle uebrige
  // Breite wenn Width gross genug ist.
  with FBar.Panels.Add do begin Width := 5000; Text := ''; end; // Mode
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
