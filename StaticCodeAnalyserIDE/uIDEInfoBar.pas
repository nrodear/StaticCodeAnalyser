unit uIDEInfoBar;

// Sprint B (Phase C) von Konzept_DiagnosticsHints.md.
// Parnassus-Pattern: NICHT als WS_CHILD-Form embedden (das funktioniert
// nicht weil die Editor-Scrollbar 'alRight' belegt), sondern DIREKT
// AUF DEN EDITOR-CANVAS zeichnen via TControlCanvas auf das interne
// TEditControl der RAD Studio IDE.
//
// PHASE C.1 - DISCOVERY (DIESE DATEI):
//   * FindEditControl(): TWinControl - sucht die TEditControl-Instanz
//     (Klassenname-Match) als Descendant von INTAEditWindow.Form
//   * On-demand Paint via PaintTestStripe(EditControl) - zeichnet
//     einmal beim Aufruf einen 5px-Streifen mit 2px-Strichen pro
//     Finding-Zeile aus gDiagnosticStore.
//   * Painting wird beim ersten Editor-Scroll/Repaint ueberschrieben -
//     KEIN persistent rendering noch.
//
// PHASE C.2 (NAECHSTER SPRINT):
//   * PaintLine-Hook via Delphi-Detours-Library auf
//     TCustomEditControl.PaintLine. Bei jedem Line-Paint nachzeichnen.
//
// PHASE C.3 (SPAETER):
//   * MouseDown-Hook fuer Click-to-Jump
//   * Hover-Tooltip
//
// Internal-API-Risiko: TEditControl ist undokumentiertes Internal
// in coreide*.bpl. Klassenname kann sich zwischen RAD Studio-Versionen
// aendern. Aktuell verifiziert fuer RAD Studio 12.

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.Math, System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Menus, Vcl.ActnList,
  ToolsAPI,
  uSCAConsts,
  uIDEDiagnostic;

const
  INFOBAR_WIDTH       = 5;
  INFOBAR_STROKE_H    = 2;
  INFOBAR_SCROLLBAR_W = 16;
  EDIT_CONTROL_CLASSNAME = 'TEditControl';  // RAD Studio coreide-Internal

type
  TInfoBarRenderer = class
  private
    function ColorForSeverity(S: TDiagnosticSeverity): TColor;
    function FindEditControl(AForm: TCustomForm): TWinControl;
    function GuessTotalLines(AView: IOTAEditView): Integer;
    procedure PaintOnControl(AControl: TWinControl;
                             const AFileName: string;
                             ATotalLines: Integer);
  public
    // Test-Paint: zeichnet einmalig das InfoBar-Stripe auf den Editor
    // der gerade aktiv ist. Painting verschwindet beim naechsten
    // Editor-Repaint - Phase C.2 (Detour) macht es persistent.
    procedure RepaintForCurrentView;
  end;

var
  gInfoBarRenderer : TInfoBarRenderer = nil;

procedure InfoBarPaintTest;

// Test-Menu-Item "SCA InfoBar Test" im IDE-Tools-Menu. Klick:
// (1) Dummy-Diagnostics fuer die aktuelle Editor-Datei in den Store,
// (2) InfoBarPaintTest aufrufen.
// Fuer Phase-C.1-Verifikation - wird in Phase C.3 durch echten
// Scan-Hook ersetzt.
procedure RegisterInfoBarTestMenu;
procedure UnregisterInfoBarTestMenu;

implementation

{ TInfoBarRenderer }

function TInfoBarRenderer.ColorForSeverity(S: TDiagnosticSeverity): TColor;
begin
  // BGR-Reihenfolge
  case S of
    dsError:   Result := $001318E8;  // Rot
    dsWarning: Result := $00008CFF;  // Orange
    dsHint:    Result := $00D47800;  // Blau
  else
    Result := clGray;
  end;
end;

function TInfoBarRenderer.FindEditControl(AForm: TCustomForm): TWinControl;

  function SearchIn(AParent: TWinControl): TWinControl;
  var
    i : Integer;
    Child : TControl;
  begin
    Result := nil;
    if AParent = nil then Exit;
    for i := 0 to AParent.ControlCount - 1 do
    begin
      Child := AParent.Controls[i];
      if Child is TWinControl then
      begin
        // Klassenname-Match (TEditControl ist Internal,
        // nicht via "is TEditControl" pruefbar)
        if SameText(Child.ClassName, EDIT_CONTROL_CLASSNAME) then
          Exit(TWinControl(Child));
        Result := SearchIn(TWinControl(Child));
        if Result <> nil then Exit;
      end;
    end;
  end;

begin
  Result := SearchIn(AForm);
end;

function TInfoBarRenderer.GuessTotalLines(AView: IOTAEditView): Integer;
var
  Pos : IOTAEditPosition;
  SavedLine, SavedCol : Integer;
begin
  Result := 0;
  if AView = nil then Exit;
  if AView.Buffer = nil then Exit;
  Pos := AView.Buffer.EditPosition;
  if Pos = nil then Exit;
  SavedLine := Pos.Row;
  SavedCol  := Pos.Column;
  try
    Pos.GotoLine(MaxInt);
    Result := Pos.Row;
  finally
    Pos.Move(SavedLine, SavedCol);
  end;
end;

procedure TInfoBarRenderer.PaintOnControl(AControl: TWinControl;
  const AFileName: string; ATotalLines: Integer);
var
  Canvas : TControlCanvas;
  R : TRect;
  BarLeft, BarHeight, Y : Integer;
  Map : TDictionary<Integer, TDiagnosticSeverity>;
  Pair : TPair<Integer, TDiagnosticSeverity>;
begin
  if AControl = nil then Exit;
  if ATotalLines <= 0 then Exit;
  if gDiagnosticStore = nil then Exit;

  Canvas := TControlCanvas.Create;
  try
    Canvas.Control := AControl;
    R := AControl.ClientRect;
    BarLeft   := R.Right - INFOBAR_SCROLLBAR_W - INFOBAR_WIDTH;
    BarHeight := R.Bottom - R.Top - INFOBAR_SCROLLBAR_W;
    if BarHeight < 50 then BarHeight := R.Bottom - R.Top;

    // Hintergrund-Streifen (subtil, damit man sieht wo die Bar liegt)
    Canvas.Brush.Color := clBtnFace;
    Canvas.FillRect(Rect(BarLeft, R.Top, BarLeft + INFOBAR_WIDTH,
                         R.Top + BarHeight));

    Map := gDiagnosticStore.BuildLineSeverityMap(AFileName);
    try
      for Pair in Map do
      begin
        Y := R.Top + Round(Pair.Key / ATotalLines * BarHeight);
        if Y < R.Top then Y := R.Top;
        if Y > R.Top + BarHeight - INFOBAR_STROKE_H then
          Y := R.Top + BarHeight - INFOBAR_STROKE_H;
        Canvas.Brush.Color := ColorForSeverity(Pair.Value);
        Canvas.FillRect(Rect(BarLeft, Y,
                             BarLeft + INFOBAR_WIDTH, Y + INFOBAR_STROKE_H));
      end;
    finally
      Map.Free;
    end;
  finally
    Canvas.Free;
  end;
end;

procedure TInfoBarRenderer.RepaintForCurrentView;
var
  EditorNTA : INTAEditorServices;  // TopEditWindow.Form (Window-Handle)
  EditorOTA : IOTAEditorServices;  // TopView (Buffer + Position)
  EditWnd : INTAEditWindow;
  View : IOTAEditView;
  EditControl : TWinControl;
  FileName : string;
  TotalLines : Integer;
begin
  if not Supports(BorlandIDEServices, INTAEditorServices, EditorNTA) then Exit;
  if not Supports(BorlandIDEServices, IOTAEditorServices, EditorOTA) then Exit;

  EditWnd := EditorNTA.TopEditWindow;
  if (EditWnd = nil) or (EditWnd.Form = nil) then Exit;

  EditControl := FindEditControl(EditWnd.Form);
  if EditControl = nil then Exit;

  View := EditorOTA.TopView;
  if View = nil then Exit;
  if View.Buffer = nil then Exit;

  FileName := View.Buffer.FileName;
  TotalLines := GuessTotalLines(View);
  PaintOnControl(EditControl, FileName, TotalLines);
end;

procedure InfoBarPaintTest;
begin
  if gInfoBarRenderer = nil then
    gInfoBarRenderer := TInfoBarRenderer.Create;
  gInfoBarRenderer.RepaintForCurrentView;
end;

{ === Test-Trigger via IDE-Tools-Menu ============================== }

type
  TInfoBarTestHandler = class
  public
    procedure MenuClick(Sender: TObject);
  end;

var
  GInfoBarAction   : TAction = nil;
  GInfoBarMenuItem : TMenuItem = nil;
  GInfoBarHandler  : TInfoBarTestHandler = nil;

procedure TInfoBarTestHandler.MenuClick(Sender: TObject);
var
  EditorOTA : IOTAEditorServices;
  View : IOTAEditView;
  FileName : string;
  Diags : TObjectList<TDiagnostic>;
  D : TDiagnostic;

  procedure AddDummy(ALine: Integer; ASev: TDiagnosticSeverity;
                     const ARuleId, AMsg: string);
  begin
    D := TDiagnostic.Create;
    D.FileName := FileName;
    D.RuleId := ARuleId;
    D.Kind := fkMemoryLeak;  // beliebig, fuer Test
    D.Severity := ASev;
    D.Title := 'Test';
    D.Message := AMsg;
    D.Range := TDiagnosticRange.FromLine(ALine);
    Diags.Add(D);
  end;

begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, EditorOTA) then Exit;
  View := EditorOTA.TopView;
  if (View = nil) or (View.Buffer = nil) then Exit;
  FileName := View.Buffer.FileName;
  if FileName = '' then Exit;
  if gDiagnosticStore = nil then gDiagnosticStore := TDiagnosticStore.Create;

  // 6 Dummy-Diagnostics ueber die Datei verteilt
  Diags := TObjectList<TDiagnostic>.Create(True);
  AddDummy( 10, dsError,   'SCA999', 'Test error at line 10');
  AddDummy( 25, dsWarning, 'SCA999', 'Test warning at line 25');
  AddDummy( 50, dsHint,    'SCA999', 'Test hint at line 50');
  AddDummy( 80, dsError,   'SCA999', 'Test error at line 80');
  AddDummy(120, dsWarning, 'SCA999', 'Test warning at line 120');
  AddDummy(200, dsHint,    'SCA999', 'Test hint at line 200');

  gDiagnosticStore.UpdateFile(FileName, Diags);

  // Painting triggern
  InfoBarPaintTest;
end;

function FindIDEToolsMenuLocal(MainMenu: TMainMenu): TMenuItem;
var
  i : Integer;
  M : TMenuItem;
begin
  Result := nil;
  if MainMenu = nil then Exit;
  for i := 0 to MainMenu.Items.Count - 1 do
  begin
    M := MainMenu.Items[i];
    if (M = nil) or (M.Caption = '') then Continue;
    if Pos('ools', M.Caption) > 0 then Exit(M);
  end;
end;

procedure RegisterInfoBarTestMenu;
var
  NTAS : INTAServices;
  ToolsMenu : TMenuItem;
begin
  if not Supports(BorlandIDEServices, INTAServices, NTAS) then Exit;
  ToolsMenu := FindIDEToolsMenuLocal(NTAS.MainMenu);
  if not Assigned(ToolsMenu) then Exit;

  if GInfoBarHandler = nil then
    GInfoBarHandler := TInfoBarTestHandler.Create;

  GInfoBarAction := TAction.Create(nil);
  GInfoBarAction.ActionList := NTAS.ActionList;
  GInfoBarAction.Caption    := 'SCA InfoBar Test';
  GInfoBarAction.Hint       := 'Test: zeichnet 6 Dummy-Findings als InfoBar-Striche';
  GInfoBarAction.Category   := 'SCA';
  GInfoBarAction.OnExecute  := GInfoBarHandler.MenuClick;

  GInfoBarMenuItem := TMenuItem.Create(NTAS.MainMenu);
  GInfoBarMenuItem.Action := GInfoBarAction;
  GInfoBarMenuItem.Name   := 'SCAInfoBarTestMenuItem';
  ToolsMenu.Add(GInfoBarMenuItem);
end;

procedure UnregisterInfoBarTestMenu;
begin
  if Assigned(GInfoBarMenuItem) then
  begin
    GInfoBarMenuItem.Free;
    GInfoBarMenuItem := nil;
  end;
  if Assigned(GInfoBarAction) then
  begin
    GInfoBarAction.Free;
    GInfoBarAction := nil;
  end;
  if Assigned(GInfoBarHandler) then
  begin
    GInfoBarHandler.Free;
    GInfoBarHandler := nil;
  end;
end;

initialization

finalization
  UnregisterInfoBarTestMenu;
  if gInfoBarRenderer <> nil then
  begin
    gInfoBarRenderer.Free;
    gInfoBarRenderer := nil;
  end;

end.
