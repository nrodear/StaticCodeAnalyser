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
  Winapi.Windows, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Grids, Vcl.Themes,
  uAnalyserTypes;  // TFindingSeverity (fuer GetCellSeverity-Callback)

type
  // Virtual-Mode-Callback: liefert den Zell-Inhalt fuer (ACol, ARow). Wird
  // im OnDrawCell-Handler aufgerufen statt grid.Cells[] zu lesen. Damit
  // muessen die Forms keine Cells[]-Strings mehr pro Datenzeile
  // vorallokieren - bei 66k+ Befunden spart das deutlich Speicher
  // (32-Bit-Process-Limit). ARow = 0 ist immer der Header.
  TGridCellTextProc = reference to function(ACol, ARow: Integer): string;

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

    // Optional: wenn gesetzt, wird der Zell-Inhalt aus dieser Callback
    // gezogen statt aus grid.Cells. Aktiviert den Virtual-Mode. Bei nil
    // bleibt das alte Verhalten (Cells[] wird verwendet) - Backwards-
    // Compatibility falls noch jemand Cells[] befuellt.
    GetCellText      : TGridCellTextProc;

    // Optional: liefert die Severity-Enum-Stufe fuer ARow direkt aus dem
    // Daten-Model. Wenn gesetzt, spart der Renderer sich pro gezeichneter
    // Zelle den zusaetzlichen GetCellText(SeverityColumn) + SeverityFromText-
    // String-Roundtrip - bei 150k+ Befunden sichtbar im Scroll-Frame.
    // Bei nil bleibt der Legacy-Pfad ueber CellText + SeverityFromText.
    GetCellSeverity  : TFunc<Integer, TFindingSeverity>;

    // Optional: liefert die TCustomStyleServices, die fuer Color-Auf-
    // loesungen verwendet werden soll. Bei nil wird die VCL-globale
    // Vcl.Themes.StyleServices verwendet (= TStyleManager.ActiveStyle).
    //
    // KRITISCH fuer das IDE-Plugin: das Plugin soll dem IDE-Theme
    // folgen (z.B. Dark), nicht dem aktiven VCL-Style (z.B. Mountain_
    // Mist). Die zwei koennen unterschiedlich sein. Der Provider holt
    // bei jedem Aufruf die aktuelle IDE-StyleServices via
    // IOTAIDEThemingServices.StyleServices.
    GetStyleServices : TFunc<TCustomStyleServices>;
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
  // uAnalyserTypes ist bereits in der interface-uses (fuer TFindingSeverity
  // im Config-Record); doppelte Listung wuerde Delphi 12 mit E2004
  // "Bezeichner redeklariert" abbrechen.
  uAnalyserPalette, uAnalyserTheme;

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
  // noinspection UninitVar
  // grid wird im outer-body zu TStringGrid(Sender); CellText (nested)
  // greift erst danach darauf zu - FP des Nested-Closure-Pattern.
  grid     : TStringGrid;
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
  Styles    : TCustomStyleServices;
  function CellText(Col, Row: Integer): string;
  begin
    if Assigned(Config.GetCellText) then
      Result := Config.GetCellText(Col, Row)
    else
      Result := grid.Cells[Col, Row];
  end;
begin
  grid := TStringGrid(Sender);
  txtRect := Rect;
  InflateRect(txtRect, -4, 0);

  // Style-Services-Lookup: IDE-Plugin liefert via Config.GetStyleServices
  // die Theming.StyleServices (IDE-Theme-spezifisch). Standalone und alle
  // anderen Caller bekommen den VCL-globalen Fallback.
  Styles := nil;
  if Assigned(Config.GetStyleServices) then
    Styles := Config.GetStyleServices();
  if not Assigned(Styles) then
    Styles := Vcl.Themes.StyleServices;

  // ---- Header-Zeile -------------------------------------------------------
  if ARow = 0 then
  begin
    if Config.UseTheme then
    begin
      HeaderBg := Styles.GetSystemColor(clBtnFace);
      HeaderFg := Styles.GetSystemColor(clBtnText);
      SepLine  := Styles.GetSystemColor(cl3DDkShadow);
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

    HeaderText := CellText(ACol, ARow);
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
  // Severity einmal pro Zelle bestimmen. Wenn GetCellSeverity gesetzt ist,
  // spart der Direkt-Enum-Lookup einen GetCellText(SeverityColumn)-Aufruf +
  // SeverityFromText-String-Parse pro Zelle - bei 150k+ Befunden spuerbar
  // beim Scrollen. Legacy-Pfad bleibt fuer Aufrufer die den Callback (noch)
  // nicht setzen.
  if Assigned(Config.GetCellSeverity) then
    SevEnum := Config.GetCellSeverity(ARow)
  else if (Config.SeverityColumn >= 0) and
          (Config.SeverityColumn < grid.ColCount) then
    SevEnum := SeverityFromText(CellText(Config.SeverityColumn, ARow))
  else
    SevEnum := fsUnknown;

  if Config.UseTheme then
  begin
    // SeverityBg-Overload mit explizitem Styles — sonst wuerde die VCL-
    // globale StyleServices verwendet (= falscher Style im IDE-Plugin
    // wenn VCL-Style != IDE-Theme).
    SevBg := SeverityBg(SevEnum, clWindow, Styles);
    if SevBg <> clNone then
      bgColor := SevBg
    else if Config.ShowZebra and Odd(ARow) then
      bgColor := Styles.GetSystemColor(clBtnFace) // theme-konformes Zebra
    else
      bgColor := Styles.GetSystemColor(clWindow);
  end
  else
  begin
    // Standalone-Fallback ohne Theme: hardcoded Pastell aus dem Enum (kein
    // String-Vergleich mehr, eindeutig + sprachunabhaengig).
    case SevEnum of
      fsError:   bgColor := COLOR_ERROR_FALLBACK;
      fsWarning: bgColor := COLOR_WARNING_FALLBACK;
    else
      bgColor := clWindow;
    end;
  end;

  if gdSelected in State then
  begin
    if Config.UseTheme then
      bgColor := Styles.GetSystemColor(clHighlight)
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
      grid.Canvas.Font.Color := Styles.GetSystemColor(clHighlightText)
    else
      grid.Canvas.Font.Color := clHighlightText;
  end
  else
  begin
    if Config.UseTheme then
      grid.Canvas.Font.Color := Styles.GetSystemColor(clWindowText)
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

  DrawText(grid.Canvas.Handle, PChar(CellText(ACol, ARow)),
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
