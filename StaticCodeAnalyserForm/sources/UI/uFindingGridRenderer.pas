unit uFindingGridRenderer;

// Gemeinsame TStringGrid-OnDrawCell-Logik fuer das Befund-Grid in IDE-Plugin
// und Standalone. Aus uIDEAnalyserForm.GridDrawCell + uMainForm.ResultGridDrawCell
// extrahiert; Aufrufer uebergeben einen Config-Record der die Plugin-Spezifika
// (Severity-Spalte, Theme, Zebra, Accent-Bar, Sort-Indicator) umschaltet.
//
// Ausserdem: TFindingGridLayout.SetColumnWidths fuer das Resize-Verhalten
// (Severity- und Typ-Spalten haben fixe Breite, "Regel"-Spalte fuellt den Rest).

interface

uses
  Winapi.Windows, System.Classes, Vcl.Graphics, Vcl.Grids, Vcl.Themes;

type
  TFindingGridConfig = record
    // Spalte in der die SeverityText-Strings liegen ("Fehler"/"Error",
    // "Warnung"/"Warning", "Hinweis"/"Hint"). Standalone: 4, IDE: 5.
    SeverityColumn   : Integer;

    // True: Hintergrundfarben aus dem aktiven IDE-Theme ableiten (uAnalyserTheme
    // SeverityBg + StyleServices). False: hardcoded Pastell (BGR-Hex) wie der
    // alte Standalone-Pfad.
    UseTheme         : Boolean;

    // Sort-Indikator '^'/'v' an die Header-Caption haengen.
    ShowSortIndicator: Boolean;
    SortColumn       : Integer;     // -1 = nicht sortiert
    SortDescending   : Boolean;

    // Odd-Row-Tint (in Theme-Mode auf clBtnFace gemappt).
    ShowZebra        : Boolean;

    // 4px-Severity-Akzent-Streifen am linken Rand der Spalte 0.
    ShowAccentBar    : Boolean;

    // Datei-Spalte fett zeichnen.
    BoldFileColumn   : Boolean;

    // DT_END_ELLIPSIS am Text - bei zu schmaler Spalte "…" anhaengen
    // statt hart abzuschneiden.
    TruncateEllipsis : Boolean;
  end;

  TFindingGridRenderer = class
  public
    class procedure DrawCell(Sender: TObject; ACol, ARow: Integer;
      Rect: TRect; State: TGridDrawState;
      const Config: TFindingGridConfig); static;

    // Default-Configs fuer die zwei Aufrufer. Bequeme Ein-Liner statt
    // 8 Felder pro Aufruf zu fuellen.
    class function StandaloneConfig: TFindingGridConfig; static;
    class function IDEConfig(ASortColumn: Integer;
      ASortDescending: Boolean): TFindingGridConfig; static;
  end;

  // Resize-Layout fuer das Befund-Grid: Severity- und Typ-Spalten haben
  // fixe Breite, "Regel"-Spalte fuellt den Rest minus Scrollbar. Wird
  // vom Frame.GridResize-Event-Handler aufgerufen (event-Binding muss
  // method-of-object bleiben, daher Wrapper im Frame).
  TFindingGridLayout = class
  public
    class procedure SetColumnWidths(AGrid: TStringGrid); static;
  end;

implementation

uses
  uAnalyserPalette, uAnalyserTypes, uAnalyserTheme;

const
  // Hardcoded Pastell-Hintergrund fuer Standalone (UseTheme=False).
  // BGR-Hex-Format - $RRGGBB im Editor liest sich verwirrend.
  COLOR_ERROR_FALLBACK   = TColor($00C0C0FF); // hellrot
  COLOR_WARNING_FALLBACK = TColor($00C0FFFF); // hellgelb

class function TFindingGridRenderer.StandaloneConfig: TFindingGridConfig;
begin
  Result.SeverityColumn    := 4;
  Result.UseTheme          := False;
  Result.ShowSortIndicator := False;
  Result.SortColumn        := -1;
  Result.SortDescending    := False;
  Result.ShowZebra         := False;
  Result.ShowAccentBar     := False;
  Result.BoldFileColumn    := False;
  Result.TruncateEllipsis  := False;
end;

class function TFindingGridRenderer.IDEConfig(ASortColumn: Integer;
  ASortDescending: Boolean): TFindingGridConfig;
begin
  Result.SeverityColumn    := 5;
  Result.UseTheme          := True;
  Result.ShowSortIndicator := True;
  Result.SortColumn        := ASortColumn;
  Result.SortDescending    := ASortDescending;
  Result.ShowZebra         := True;
  Result.ShowAccentBar     := True;
  Result.BoldFileColumn    := True;
  Result.TruncateEllipsis  := True;
end;

class procedure TFindingGridRenderer.DrawCell(Sender: TObject;
  ACol, ARow: Integer; Rect: TRect; State: TGridDrawState;
  const Config: TFindingGridConfig);
var
  grid     : TStringGrid;
  severity : string;
  bgColor  : TColor;
  txtRect  : TRect;
  HeaderBg : TColor;
  HeaderFg : TColor;
  SepLine  : TColor;
  HeaderText: string;
  SevEnum   : TFindingSeverity;
  SevBg     : TColor;
  Accent    : TColor;
  IndR      : TRect;
  DtFlags   : Cardinal;
begin
  grid := TStringGrid(Sender);
  txtRect := Rect;
  InflateRect(txtRect, -4, 0);

  // ---- Header-Zeile -------------------------------------------------------
  if ARow = 0 then
  begin
    if Config.UseTheme then
    begin
      HeaderBg := StyleServices.GetSystemColor(clBtnFace);
      HeaderFg := StyleServices.GetSystemColor(clBtnText);
      SepLine  := StyleServices.GetSystemColor(cl3DDkShadow);
    end
    else
    begin
      HeaderBg := clBtnFace;
      HeaderFg := clWindowText;
      SepLine  := cl3DDkShadow;
    end;

    grid.Canvas.Brush.Color := HeaderBg;
    grid.Canvas.FillRect(Rect);

    // Trennlinie unten (nur im Theme-Mode optisch wichtig)
    if Config.UseTheme then
    begin
      grid.Canvas.Pen.Color := SepLine;
      grid.Canvas.MoveTo(Rect.Left,  Rect.Bottom - 1);
      grid.Canvas.LineTo(Rect.Right, Rect.Bottom - 1);
    end;

    grid.Canvas.Brush.Style := bsClear;
    grid.Canvas.Font.Name   := 'Segoe UI';
    grid.Canvas.Font.Size   := 8;
    grid.Canvas.Font.Style  := [fsBold];
    grid.Canvas.Font.Color  := HeaderFg;

    HeaderText := grid.Cells[ACol, ARow];
    if Config.ShowSortIndicator and (ACol = Config.SortColumn) then
    begin
      if Config.SortDescending then
        HeaderText := HeaderText + ' v'
      else
        HeaderText := HeaderText + ' ^';
    end;

    DrawText(grid.Canvas.Handle, PChar(HeaderText), -1, txtRect,
      DT_SINGLELINE or DT_VCENTER or DT_LEFT or DT_NOPREFIX);
    Exit;
  end;

  // ---- Datenzeilen --------------------------------------------------------
  if (Config.SeverityColumn >= 0) and (Config.SeverityColumn < grid.ColCount) then
    severity := grid.Cells[Config.SeverityColumn, ARow]
  else
    severity := '';

  if Config.UseTheme then
  begin
    SevEnum := SeverityFromText(severity);
    SevBg   := SeverityBg(SevEnum); // theme-bewusst (clWindow + Akzent-Tint)
    if SevBg <> clNone then
      bgColor := SevBg
    else if Config.ShowZebra and Odd(ARow) then
      bgColor := StyleServices.GetSystemColor(clBtnFace) // theme-konformes Zebra
    else
      bgColor := StyleServices.GetSystemColor(clWindow);
  end
  else
  begin
    SevEnum := SeverityFromText(severity); // wird ggf. fuer Accent gebraucht
    if (severity = 'Fehler') or (severity = 'Error') then
      bgColor := COLOR_ERROR_FALLBACK
    else if (severity = 'Warnung') or (severity = 'Warning') then
      bgColor := COLOR_WARNING_FALLBACK
    else
      bgColor := clWindow;
  end;

  if gdSelected in State then
  begin
    if Config.UseTheme then
      bgColor := StyleServices.GetSystemColor(clHighlight)
    else
      bgColor := clHighlight;
  end;

  grid.Canvas.Brush.Color := bgColor;
  grid.Canvas.FillRect(Rect);
  grid.Canvas.Brush.Style := bsClear;

  // 4px Severity-Akzent-Streifen am linken Rand der Spalte 0.
  if Config.ShowAccentBar and (ACol = 0) and (SevEnum <> fsUnknown) then
  begin
    Accent := SeverityAccent(SevEnum);
    if Accent <> clNone then
    begin
      IndR.Left   := Rect.Left;
      IndR.Top    := Rect.Top;
      IndR.Right  := Rect.Left + 4;
      IndR.Bottom := Rect.Bottom;
      grid.Canvas.Brush.Color := Accent;
      grid.Canvas.FillRect(IndR);
      grid.Canvas.Brush.Style := bsClear;
    end;
  end;

  grid.Canvas.Font.Name := 'Segoe UI';
  grid.Canvas.Font.Size := 8;
  if gdSelected in State then
  begin
    if Config.UseTheme then
      grid.Canvas.Font.Color := StyleServices.GetSystemColor(clHighlightText)
    else
      grid.Canvas.Font.Color := clHighlightText;
  end
  else
  begin
    if Config.UseTheme then
      grid.Canvas.Font.Color := StyleServices.GetSystemColor(clWindowText)
    else
      grid.Canvas.Font.Color := clWindowText;
  end;

  // Datei-Spalte (Spalte 0) fett, ausser bei Selektion.
  if Config.BoldFileColumn and (ACol = 0) and (not (gdSelected in State)) then
    grid.Canvas.Font.Style := [fsBold]
  else
    grid.Canvas.Font.Style := [];

  DtFlags := DT_SINGLELINE or DT_VCENTER or DT_LEFT or DT_NOPREFIX;
  if Config.TruncateEllipsis then
    DtFlags := DtFlags or DT_END_ELLIPSIS;

  DrawText(grid.Canvas.Handle, PChar(grid.Cells[ACol, ARow]),
    -1, txtRect, DtFlags);
end;

{ TFindingGridLayout }

class procedure TFindingGridLayout.SetColumnWidths(AGrid: TStringGrid);
const
  COL_SEV_W  = 90;  // Schweregrad-Spalte fix
  COL_TYPE_W = 110; // Typ-Spalte fix
var
  used, regelW: Integer;
begin
  if not Assigned(AGrid) then Exit;
  AGrid.ColWidths[3] := COL_TYPE_W;
  AGrid.ColWidths[5] := COL_SEV_W;
  used := AGrid.ColWidths[0] + AGrid.ColWidths[1] +
          AGrid.ColWidths[2] + COL_TYPE_W + COL_SEV_W +
          GetSystemMetrics(SM_CXVSCROLL);
  regelW := AGrid.ClientWidth - used;
  if regelW > 80 then
    AGrid.ColWidths[4] := regelW;
end;

end.
