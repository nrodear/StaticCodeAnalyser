unit uIDEInfoBar;

// Sprint B von Konzept_DiagnosticsHints.md (lokal):
// InfoBar = 5px-Streifen links der Editor-Scrollbar mit 2px-Strichen
// pro Finding-Zeile (Severity-Farbe). Click-to-Jump zur naechstgele-
// genen Finding-Zeile + Cursor auf Range.Start.
//
// Z-ORDER-Pattern: WS_CHILD-Embedding analog uIDEAnnotationOverlay.
// Initial WS_POPUP, beim ersten ShowForView wird via SetWindowLongPtr
// + SetParent zum WS_CHILD des Editor-Window-Handle.
//
// Lifecycle: Singleton gInfoBar, lazy-init beim ersten Aufruf, im
// finalization-Block freigegeben.

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Math, System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms,
  ToolsAPI,
  uIDEDiagnostic;

const
  INFOBAR_WIDTH       = 5;   // Pixel-Breite
  INFOBAR_STROKE_H    = 2;   // Pixel-Hoehe pro Finding-Strich
  INFOBAR_SCROLLBAR_W = 16;  // typische VCL-Scrollbar-Breite

type
  TInfoBar = class(TForm)
  private
    FCurrentFile   : string;
    FCurrentParent : HWND;
    FEditView      : IOTAEditView;
    FTotalLines    : Integer;

    procedure EmbedIntoEditor(AEditorHandle: HWND);
    procedure RecomputeBounds;
    function ColorForSeverity(S: TDiagnosticSeverity): TColor;
    function GetEditorClientWnd(AView: IOTAEditView): HWND;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
                        X, Y: Integer); override;
  public
    constructor CreateBar(AOwner: TComponent); reintroduce;
    procedure ShowForView(AView: IOTAEditView);
    procedure HideAndUnbind;
    procedure RefreshFromStore;
  end;

var
  gInfoBar : TInfoBar = nil;  // Singleton, lazy-init

// Wird vom TFindingEditorEvents.EditorViewActivated gerufen wenn der
// User Editor-Datei wechselt. Erstellt den Bar bei erstem Aufruf.
procedure InfoBarShowForView(AView: IOTAEditView);

implementation

{ TInfoBar }

constructor TInfoBar.CreateBar(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  BorderStyle := bsNone;
  Position    := poDesigned;
  Color       := clBtnFace;  // Default - in Paint mit Theme-BG ueberzeichnen
  FCurrentParent := 0;
end;

procedure TInfoBar.CreateParams(var Params: TCreateParams);
begin
  inherited;
  // Initial WS_POPUP, EmbedIntoEditor wechselt zu WS_CHILD beim ersten
  // ShowForView. Analog uIDEAnnotationOverlay.
  Params.Style     := WS_POPUP;
  Params.ExStyle   := WS_EX_NOACTIVATE;
  Params.WndParent := Application.Handle;
end;

procedure TInfoBar.EmbedIntoEditor(AEditorHandle: HWND);
var
  Style, ExStyle : NativeInt;
begin
  if AEditorHandle = 0 then Exit;
  if AEditorHandle = FCurrentParent then Exit;

  if not HandleAllocated then HandleNeeded;

  Style   := GetWindowLongPtr(Handle, GWL_STYLE);
  ExStyle := GetWindowLongPtr(Handle, GWL_EXSTYLE);
  Style   := (Style and not WS_POPUP) or WS_CHILD or WS_CLIPSIBLINGS;
  ExStyle := ExStyle and not (WS_EX_TOPMOST or WS_EX_TOOLWINDOW);
  SetWindowLongPtr(Handle, GWL_STYLE, Style);
  SetWindowLongPtr(Handle, GWL_EXSTYLE, ExStyle);

  Winapi.Windows.SetParent(Handle, AEditorHandle);
  SetWindowPos(Handle, 0, 0, 0, 0, 0,
    SWP_FRAMECHANGED or SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or
    SWP_NOACTIVATE or SWP_NOOWNERZORDER);

  FCurrentParent := AEditorHandle;
end;

function TInfoBar.GetEditorClientWnd(AView: IOTAEditView): HWND;
var
  EW : INTAEditWindow;
begin
  Result := 0;
  if AView = nil then Exit;
  // INTAEditWindow.Form ist TCustomForm des Editor-Tabs.
  EW := AView.GetEditWindow;
  if (EW = nil) or (EW.Form = nil) then Exit;
  Result := EW.Form.Handle;
end;

procedure TInfoBar.RecomputeBounds;
var
  ParentWnd : HWND;
  R         : TRect;
  X, Y, H   : Integer;
begin
  ParentWnd := FCurrentParent;
  if ParentWnd = 0 then Exit;
  if not GetClientRect(ParentWnd, R) then Exit;

  // Position: rechts vom Editor-Text, links der Scrollbar.
  X := R.Right - INFOBAR_SCROLLBAR_W - INFOBAR_WIDTH;
  Y := R.Top;
  H := R.Bottom - R.Top - INFOBAR_SCROLLBAR_W;  // minus horizontale SB
  if H < 50 then H := R.Bottom - R.Top;  // fallback: keine H-SB

  SetBounds(X, Y, INFOBAR_WIDTH, H);
end;

procedure TInfoBar.ShowForView(AView: IOTAEditView);
var
  EditorWnd : HWND;
begin
  if AView = nil then Exit;
  FEditView := AView;

  if AView.Buffer = nil then Exit;
  FCurrentFile := AView.Buffer.FileName;

  // Nur anzeigen wenn Datei Findings hat
  if (gDiagnosticStore = nil) or
     (gDiagnosticStore.CountForFile(FCurrentFile) = 0) then
  begin
    HideAndUnbind;
    Exit;
  end;

  EditorWnd := GetEditorClientWnd(AView);
  if EditorWnd = 0 then Exit;

  EmbedIntoEditor(EditorWnd);
  RecomputeBounds;
  if not Visible then Visible := True;
  Invalidate;
end;

procedure TInfoBar.HideAndUnbind;
begin
  if Visible then Visible := False;
end;

procedure TInfoBar.RefreshFromStore;
begin
  if (FCurrentFile = '') or (FEditView = nil) then Exit;
  if (gDiagnosticStore = nil) or
     (gDiagnosticStore.CountForFile(FCurrentFile) = 0) then
  begin
    HideAndUnbind;
    Exit;
  end;
  RecomputeBounds;
  if not Visible then Visible := True;
  Invalidate;
end;

function TInfoBar.ColorForSeverity(S: TDiagnosticSeverity): TColor;
begin
  // BGR-Reihenfolge (Win32 TColor). Theme-aware-Verbesserung in Sprint C.
  case S of
    dsError:   Result := $001318E8;  // Rot   (R E8, G 18, B 13)
    dsWarning: Result := $00008CFF;  // Orange (R FF, G 8C, B 00)
    dsHint:    Result := $00D47800;  // Blau  (R 00, G 78, B D4)
  else
    Result := clGray;
  end;
end;

procedure TInfoBar.Paint;
var
  Map  : TDictionary<Integer, TDiagnosticSeverity>;
  Pair : TPair<Integer, TDiagnosticSeverity>;
  Y, BarHeight : Integer;
  C : TColor;
begin
  // Hintergrund (Editor-Theme-aehnlich; spaeter via uAnalyserTheme)
  Canvas.Brush.Color := clBtnFace;
  Canvas.FillRect(ClientRect);

  if (gDiagnosticStore = nil) or (FCurrentFile = '') then Exit;
  if FEditView = nil then Exit;

  // Total-Lines aus Buffer ermitteln. Buffer.LinesInBuffer ist
  // OTAPI-API. Falls 0 -> kein Render.
  try
    FTotalLines := FEditView.Buffer.LinesInBuffer;
  except
    FTotalLines := 0;
  end;
  if FTotalLines <= 0 then Exit;

  BarHeight := Height;
  if BarHeight <= 0 then Exit;

  Map := gDiagnosticStore.BuildLineSeverityMap(FCurrentFile);
  try
    for Pair in Map do
    begin
      Y := Round(Pair.Key / FTotalLines * BarHeight);
      if Y < 0 then Y := 0;
      if Y > BarHeight - INFOBAR_STROKE_H then Y := BarHeight - INFOBAR_STROKE_H;
      C := ColorForSeverity(Pair.Value);
      Canvas.Brush.Color := C;
      Canvas.FillRect(Rect(0, Y, Width, Y + INFOBAR_STROKE_H));
    end;
  finally
    Map.Free;
  end;
end;

procedure TInfoBar.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Diags : TArray<TDiagnostic>;
  D, Best : TDiagnostic;
  BarY, Dist, MinDist : Integer;
  Pos : IOTAEditPosition;
begin
  inherited;
  if Button <> mbLeft then Exit;
  if FEditView = nil then Exit;
  if (gDiagnosticStore = nil) or (FCurrentFile = '') then Exit;

  Diags := gDiagnosticStore.GetForFile(FCurrentFile);
  if Length(Diags) = 0 then Exit;
  if FTotalLines <= 0 then Exit;

  Best := nil;
  MinDist := MaxInt;
  for D in Diags do
  begin
    BarY := Round(D.Range.StartLine / FTotalLines * Height);
    Dist := Abs(BarY - Y);
    if Dist < MinDist then
    begin
      MinDist := Dist;
      Best := D;
    end;
  end;

  if Assigned(Best) then
  begin
    // Jump zur Finding-Zeile + Cursor auf StartCol
    Pos := FEditView.Buffer.EditPosition;
    if Pos <> nil then
    begin
      Pos.Move(Best.Range.StartLine, Best.Range.StartCol);
      // Scroll so dass Zeile sichtbar (3 Zeilen Padding oben)
      FEditView.SetTopRow(Max(1, Best.Range.StartLine - 3));
    end;
    FEditView.Paint;
  end;
end;

procedure InfoBarShowForView(AView: IOTAEditView);
begin
  if gInfoBar = nil then
    gInfoBar := TInfoBar.CreateBar(Application);
  gInfoBar.ShowForView(AView);
end;

initialization

finalization
  if gInfoBar <> nil then
  begin
    gInfoBar.Free;
    gInfoBar := nil;
  end;

end.
