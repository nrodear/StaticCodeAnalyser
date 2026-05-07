unit uIDEGridTooltip;

// Per-Cell-Tooltip-Subsystem fuer das Befund-Grid.
//
// Vorher: 4 Felder im Frame (FOldGridWndProc + FSavedHintPause +
// FSavedHintShortPause + FHintPauseOverridden) plus die GridWndProc-
// Methode (~57 Zeilen) plus Setup im Konstruktor und Teardown im
// Destruktor. Insgesamt ~80 Zeilen subclass-Pattern direkt im Frame.
//
// Jetzt: ein Feld (FGridTooltip: TFindingGridTooltip), Konstruktor +
// Destruktor des Helpers managen das Subclassing automatisch.
//
// Zwei Aufgaben werden hier erledigt:
//
// 1. CM_HINTSHOW: Per-Zellen-Tooltip nur fuer die Datei-Spalte (Spalte 0).
//    Der Tooltip zeigt den vollen Pfad (DisplayName in der Cell ist
//    gekuerzt). Andere Spalten unterdruecken den Tooltip via Msg.Result=1.
//    Datenquelle: TList<TLeakFinding> Referenz, vom Frame eingespeist.
//    Lookup: ARow-1 = Index in die Findings-Liste.
//
// 2. CM_MOUSEENTER / CM_MOUSELEAVE: Application.HintPause / HintShortPause
//    werden waehrend "Maus ueber Grid" auf 100 ms gesetzt, danach
//    wiederhergestellt. Damit greift der schnelle 100 ms-Delay nur lokal,
//    der Rest der IDE behaelt den User-Default.
//
// Lifecycle:
//   * Constructor: speichert die Original-WndProc (zum Restore), setzt die
//     eigene WndProc als Subclass. Speichert die Findings-Referenz.
//   * Destructor: Restore-WndProc (defensiv, Grid kann schon weg sein),
//     plus HintPause-Restore falls aktiv. Owner=Self im Frame greift dann
//     nochmal aber FreeAndNil im Frame.Destroy macht das vorher.

interface

uses
  System.Classes, System.Generics.Collections,
  Winapi.Messages,
  Vcl.Controls, Vcl.Grids,
  uMethodd12;

type
  TFindingGridTooltip = class(TComponent)
  private
    FGrid                 : TStringGrid;
    FFindings             : TList<TLeakFinding>;
    FOldWndProc           : TWndMethod;
    FSavedHintPause       : Integer;
    FSavedHintShortPause  : Integer;
    FHintPauseOverridden  : Boolean;
    procedure WndProc(var Msg: TMessage);
  public
    // AGrid muss zum Konstruktions-Zeitpunkt existieren (WndProc wird
    // sofort gesubclassed). AFindings ist eine *gehaltene* Referenz,
    // kein Ownership - die Liste lebt im Frame und ueberlebt den Helper.
    // AOwner=Frame -> Auto-Free, plus Frame.Destroy ruft FreeAndNil
    // explizit fruehzeitig damit Restore-Reihenfolge stimmt.
    constructor Create(AOwner: TComponent;
                       AGrid: TStringGrid;
                       AFindings: TList<TLeakFinding>); reintroduce;
    destructor Destroy; override;
  end;

implementation

uses
  Vcl.Forms;  // Application

constructor TFindingGridTooltip.Create(AOwner: TComponent;
  AGrid: TStringGrid; AFindings: TList<TLeakFinding>);
begin
  inherited Create(AOwner);
  FGrid     := AGrid;
  FFindings := AFindings;

  // Tooltip-Voraussetzungen am Grid: Hint != '' (Placeholder) damit VCL
  // CM_HINTSHOW ueberhaupt feuert. ShowHint=True und ParentShowHint=False
  // weil die IDE den Default haeufig auf False zieht.
  FGrid.ParentShowHint := False;
  FGrid.ShowHint       := True;
  FGrid.Hint           := ' ';

  FOldWndProc       := FGrid.WindowProc;
  FGrid.WindowProc  := WndProc;
end;

destructor TFindingGridTooltip.Destroy;
begin
  // Subclass aufloesen bevor das Grid stirbt - sonst feuert ein letzter
  // CM_*-Wisch in unsere ungueltige WndProc. Defensiv: Grid kann auch
  // schon weg sein (z.B. wenn der Frame seinen Designed-Resource-Free
  // vorher durchgelaufen ist).
  if Assigned(FGrid) and Assigned(FOldWndProc) then
  begin
    FGrid.WindowProc := FOldWndProc;
    FOldWndProc := nil;
  end;

  // HintPause restaurieren falls Maus zuletzt im Grid war und wir den
  // 100ms-Override aktiv hatten.
  if FHintPauseOverridden then
  begin
    Application.HintPause      := FSavedHintPause;
    Application.HintShortPause := FSavedHintShortPause;
    FHintPauseOverridden := False;
  end;

  inherited;
end;

procedure TFindingGridTooltip.WndProc(var Msg: TMessage);
var
  HI         : Vcl.Controls.PHintInfo;
  ACol, ARow : Integer;
  idx        : Integer;
begin
  case Msg.Msg of
    CM_HINTSHOW:
      begin
        HI := Vcl.Controls.PHintInfo(Msg.LParam);
        FGrid.MouseToCell(HI.CursorPos.X, HI.CursorPos.Y, ACol, ARow);
        idx := ARow - 1;
        if (ACol = 0) and Assigned(FFindings) and
           (idx >= 0) and (idx < FFindings.Count) then
        begin
          // Voller Pfad aus Findings, nicht der gekuerzte DisplayName aus
          // der Cell - der Tooltip soll Mehrwert liefern.
          HI.HintStr      := FFindings[idx].FileName;
          HI.CursorRect   := FGrid.CellRect(ACol, ARow);
          HI.HintMaxWidth := 600;
          Msg.Result := 0;     // 0 = anzeigen
        end
        else
          Msg.Result := 1;     // 1 = unterdruecken
        Exit;
      end;

    CM_MOUSEENTER:
      begin
        if not FHintPauseOverridden then
        begin
          FSavedHintPause      := Application.HintPause;
          FSavedHintShortPause := Application.HintShortPause;
          Application.HintPause      := 100;
          Application.HintShortPause := 100;
          FHintPauseOverridden := True;
        end;
      end;

    CM_MOUSELEAVE:
      begin
        if FHintPauseOverridden then
        begin
          Application.HintPause      := FSavedHintPause;
          Application.HintShortPause := FSavedHintShortPause;
          FHintPauseOverridden := False;
        end;
      end;
  end;
  FOldWndProc(Msg);
end;

end.
