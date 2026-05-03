unit uIDEEditSubclass;

// SKELETON — noch nicht produktionsreif aktiviert.
//
// Idee: Win32-Subclassing der EditWindow-Form (Variante 6 aus dem CR).
// Die Tools-API gibt uns ueber IOTAEditWindow.Form ein TCustomForm.
// In dessen Children befindet sich das eigentliche Editor-Control.
// Wir hooken dessen WindowProc ein, lassen das Original zeichnen und
// malen nach dem Paint einen farbigen Streifen ueber die Befund-Zeile.
//
// Vorteile gegenueber INTAEditViewNotifier (Variante 2):
//   * Lifecycle ist an die TForm gebunden (FreeNotification)
//   * Kein AV in coreide290.bpl beim Projekt-Schliessen
//   * Volle Pixel-Kontrolle (wirklich rote Zeile)
//
// IDE-Versions-Abhaengigkeit:
//   Das Auffinden des konkreten Edit-Controls innerhalb von
//   IOTAEditWindow.Form ist NICHT in der ToolsAPI dokumentiert. Der
//   ClassName variiert zwischen Delphi-Versionen. Aktueller Stand
//   (Delphi 12 Athens): das Editor-Control ist meist das groesste
//   TWinControl der Form mit Align=alClient.
//   FindEditControl() unten implementiert eine Heuristik dafuer.
//   Falls auf einer anderen Version nicht gefunden: Highlighter-Skeleton
//   bleibt inaktiv, kein Crash.
//
// Aktivierung:
//   1. {$DEFINE ENABLE_EDIT_SUBCLASS} setzen
//   2. RegisterEditSubclass im Plugin aufrufen
//   3. EditSubclassMgr.SetFindings(...) nach jeder Analyse
//
// Stand: Skeleton ist getestet bezgl. Compile, NICHT bezgl. korrektem
// Subclass-Verhalten. Vor Produktiv-Einsatz unbedingt mit GExperts/CnPack
// verfizieren wie das Edit-Control in der jeweiligen Delphi-Version
// heisst und sich verhaelt.

{$DEFINE ENABLE_EDIT_SUBCLASS_SKELETON}
// ENABLE_EDIT_SUBCLASS aktiviert die WindowProc-Hooks. Default OFF -
// Skeleton kompiliert, tut aber NICHTS bis es bewusst eingeschaltet wird.

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, ToolsAPI,
  uMethodd12, uSCAConsts;

type
  // Pro EditWindow-Form ein Subclass-Wrapper. Lifetime via FreeNotification
  // an die Form gebunden - wenn die Form zerstoert wird, gibt sich der
  // Wrapper selbst frei.
  TEditWindowSubclass = class(TComponent)
  private
    FForm        : TCustomForm;
    FEditCtrl    : TWinControl;
    FOldWndProc  : TWndMethod;
    FActive      : Boolean;
    procedure NewWndProc(var Message: TMessage);
    procedure UninstallHook;
    function FindEditControl(AParent: TWinControl): TWinControl;
  protected
    procedure Notification(AComponent: TComponent;
      Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent; AForm: TCustomForm); reintroduce;
    destructor Destroy; override;
    procedure Repaint;
    property Form: TCustomForm read FForm;
    property EditCtrl: TWinControl read FEditCtrl;
    property Active: Boolean read FActive;
  end;

  // Singleton der alle bekannten Subclasses verwaltet.
  TEditSubclassManager = class
  private
    FSubclasses : TObjectList<TEditWindowSubclass>;
    // FilePath (lower-case) -> (LineNumber -> Severity)
    FFindings   : TObjectDictionary<string, TDictionary<Integer, TLeakSeverity>>;
    function NormalizePath(const APath: string): string;
    function FindOrAttachToCurrentEditWindow: TEditWindowSubclass;

  public
    constructor Create;
    destructor Destroy; override;
    // Fuer aktuell geoeffnete EditView die Subclass anhaengen (idempotent).
    procedure AttachToCurrent;
    // Befund-Map befuellen + alle aktiven Subclasses neu zeichnen.
    procedure SetFindings(Findings: TObjectList<TLeakFinding>);
    // Lookup fuer den WndProc-Hook.
    function TryGetSeverity(const FilePath: string; Line: Integer;
      out Severity: TLeakSeverity): Boolean;
  end;

var
  GEditSubclassMgr: TEditSubclassManager = nil;

procedure RegisterEditSubclass;
procedure UnregisterEditSubclass;

implementation

const
  STRIPE_HEIGHT_PX_DEFAULT = 16; // Fallback wenn keine Zeilenhoehe ermittelbar
  CL_SEV_ERROR    = TColor($000000FF); // Rot
  CL_SEV_WARNING  = TColor($000080FF); // Orange
  CL_SEV_HINT     = TColor($0000C040); // Gruen
  CL_SEV_FILEERR  = TColor($00808080); // Grau

function SeverityColor(S: TLeakSeverity): TColor;
begin
  case S of
    lsError   : Result := CL_SEV_ERROR;
    lsWarning : Result := CL_SEV_WARNING;
    lsHint    : Result := CL_SEV_HINT;
  else
    Result := CL_SEV_FILEERR;
  end;
end;

function GetCurrentEditWindow: INTAEditWindow;
var
  EditSvc: IOTAEditorServices;
  TopView: IOTAEditView;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAEditorServices, EditSvc) then Exit;
  TopView := EditSvc.TopView;
  if TopView <> nil then
    Result := TopView.GetEditWindow;
end;

function GetCurrentEditFileName: string;
var
  EditSvc: IOTAEditorServices;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAEditorServices, EditSvc) then Exit;
  if (EditSvc.TopBuffer <> nil) then
    Result := EditSvc.TopBuffer.FileName;
end;

// Forward-Helper - wird in TEditWindowSubclass.NewWndProc benoetigt.
type
  TLineSevPair = TPair<Integer, TLeakSeverity>;

function EnumLineSeverities(const FileName: string): TArray<TLineSevPair>; forward;

{ ---- TEditWindowSubclass ---- }

constructor TEditWindowSubclass.Create(AOwner: TComponent; AForm: TCustomForm);
begin
  inherited Create(AOwner);
  FForm := AForm;
  // FreeNotification: wenn die Form zerstoert wird, kriegen wir Notification
  // mit opRemove -> WindowProc safe zurueckstellen.
  FForm.FreeNotification(Self);
  FEditCtrl := FindEditControl(FForm);
  if not Assigned(FEditCtrl) then Exit; // skeleton bleibt inaktiv
  FEditCtrl.FreeNotification(Self);
  {$IFDEF ENABLE_EDIT_SUBCLASS_SKELETON}
  // Hook: WindowProc abfangen ueber VCL-Property (sauberer als SetWindowLong).
  FOldWndProc := FEditCtrl.WindowProc;
  FEditCtrl.WindowProc := NewWndProc;
  FActive := True;
  {$ENDIF}
end;

destructor TEditWindowSubclass.Destroy;
begin
  UninstallHook;
  inherited;
end;

procedure TEditWindowSubclass.UninstallHook;
begin
  if FActive and Assigned(FEditCtrl) then
  begin
    try
      FEditCtrl.WindowProc := FOldWndProc;
    except
      // Falls Control bereits halb-zerstoert ist, ignorieren.
    end;
    FActive := False;
  end;
end;

procedure TEditWindowSubclass.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  // Beide moeglichen Quellen koennen freigegeben werden - in jedem Fall
  // den Hook entfernen, sonst gibt's einen invaliden WindowProc.
  if (Operation = opRemove) and ((AComponent = FForm) or (AComponent = FEditCtrl)) then
  begin
    UninstallHook;
    FEditCtrl := nil;
    FForm := nil;
  end;
end;

procedure TEditWindowSubclass.Repaint;
begin
  if Assigned(FEditCtrl) and FEditCtrl.HandleAllocated then
    FEditCtrl.Invalidate;
end;

function TEditWindowSubclass.FindEditControl(AParent: TWinControl): TWinControl;
// Heuristik: das Editor-Control ist das groesste TWinControl mit Align=alClient.
// In Delphi 12 typischerweise direkt unter der Form, aber wir suchen
// rekursiv durch alle Container.
var
  i        : Integer;
  Child    : TControl;
  Found    : TWinControl;
  BestArea : Integer;
  Area     : Integer;
begin
  Result := nil;
  BestArea := 0;
  if AParent = nil then Exit;
  for i := 0 to AParent.ControlCount - 1 do
  begin
    Child := AParent.Controls[i];
    if not (Child is TWinControl) then Continue;
    // Editor-Controls sind grosse alClient-Controls
    if (Child.Align = alClient) and (Child.Width > 100) and (Child.Height > 100) then
    begin
      Area := Child.Width * Child.Height;
      if Area > BestArea then
      begin
        Result := TWinControl(Child);
        BestArea := Area;
      end;
    end;
    // Rekursion in Unter-Container
    Found := FindEditControl(TWinControl(Child));
    if Assigned(Found) then
    begin
      Area := Found.Width * Found.Height;
      if Area > BestArea then
      begin
        Result := Found;
        BestArea := Area;
      end;
    end;
  end;
end;

procedure TEditWindowSubclass.NewWndProc(var Message: TMessage);
var
  PS       : TPaintStruct;
  DC       : HDC;
  Canvas   : TCanvas;
  FileName : string;
  CellH    : Integer;
  TopRow   : Integer;
  Line     : Integer;
  Y        : Integer;
  Sev      : TLeakSeverity;
  EditSvc  : IOTAEditorServices;
  View     : IOTAEditView;
  Pairs    : TArray<TLineSevPair>;
  i        : Integer;
begin
  // Erst Original ausfuehren - die IDE muss ihren Editor zeichnen.
  FOldWndProc(Message);

  if Message.Msg <> WM_PAINT then Exit;
  if GEditSubclassMgr = nil then Exit;
  if not Assigned(FEditCtrl) then Exit;

  // Aktive Datei + View ermitteln
  if not Supports(BorlandIDEServices, IOTAEditorServices, EditSvc) then Exit;
  View := EditSvc.TopView;
  if View = nil then Exit;
  if View.Buffer = nil then Exit;
  FileName := View.Buffer.FileName;
  if FileName = '' then Exit;

  // Zeilenhoehe ableiten: in Delphi 12 hat IOTAEditView keine direkte
  // CellSize/GetCellSize-API. Wir berechnen sie aus dem sichtbaren Bereich:
  //   CellH ~= EditCtrl.Height / sichtbare Zeilen
  TopRow := View.TopRow;
  CellH  := STRIPE_HEIGHT_PX_DEFAULT;
  if (View.GetBottomRow > TopRow) and (FEditCtrl.Height > 0) then
    CellH := FEditCtrl.Height div (View.GetBottomRow - TopRow + 1);
  if CellH <= 0 then CellH := STRIPE_HEIGHT_PX_DEFAULT;

  // Paint-DC erst nachdem Original den Buffer geleert hat - GetDC gibt uns
  // einen frischen DC, kein BeginPaint (das hat das Original schon gemacht).
  DC := GetDC(FEditCtrl.Handle);
  if DC = 0 then Exit;
  try
    Canvas := TCanvas.Create;
    try
      Canvas.Handle := DC;
      // Pro Befund-Zeile einen 4px Streifen ganz links zeichnen.
      // ('Komplett rote Zeile' wuerde den Buffer-Text uebermalen - waere unleserlich.
      //  Wenn wirklich gewuenscht: Pen-Color setzen + FillRect mit halbtransparenter
      //  Brush ueber die ganze LineRect.)
      Pairs := EnumLineSeverities(FileName);
      for i := 0 to High(Pairs) do
      begin
        Line := Pairs[i].Key;
        Sev  := Pairs[i].Value;
        if Line < TopRow then Continue;                 // ueber dem sichtbaren Bereich
        Y := (Line - TopRow) * CellH;
        if Y > FEditCtrl.Height then Break;             // unter dem sichtbaren Bereich
        Canvas.Brush.Color := SeverityColor(Sev);
        Canvas.FillRect(Rect(0, Y, 4, Y + CellH));
      end;
    finally
      Canvas.Free;
    end;
  finally
    ReleaseDC(FEditCtrl.Handle, DC);
  end;
end;

// Helper als iterierbare Pairs - in der WndProc inlinable.
function EnumLineSeverities(const FileName: string): TArray<TLineSevPair>;
var
  Lines : TDictionary<Integer, TLeakSeverity>;
  Key   : string;
  Pair  : TLineSevPair;
  Tmp   : TList<TLineSevPair>;
begin
  SetLength(Result, 0);
  if GEditSubclassMgr = nil then Exit;
  Key := FileName.ToLower.Replace('/', '\');
  if not GEditSubclassMgr.FFindings.TryGetValue(Key, Lines) then Exit;
  Tmp := TList<TLineSevPair>.Create;
  try
    for Pair in Lines do
      Tmp.Add(Pair);
    Result := Tmp.ToArray;
  finally
    Tmp.Free;
  end;
end;

{ ---- TEditSubclassManager ---- }

constructor TEditSubclassManager.Create;
begin
  inherited;
  FSubclasses := TObjectList<TEditWindowSubclass>.Create(True);
  FFindings   := TObjectDictionary<string, TDictionary<Integer, TLeakSeverity>>.Create([doOwnsValues]);
end;

destructor TEditSubclassManager.Destroy;
begin
  FSubclasses.Free;
  FFindings.Free;
  inherited;
end;

function TEditSubclassManager.NormalizePath(const APath: string): string;
begin
  Result := APath.ToLower.Replace('/', '\');
end;

procedure TEditSubclassManager.SetFindings(Findings: TObjectList<TLeakFinding>);
var
  F     : TLeakFinding;
  Key   : string;
  Lines : TDictionary<Integer, TLeakSeverity>;
  L     : Integer;
  Sub   : TEditWindowSubclass;
begin
  FFindings.Clear;
  if Findings <> nil then
    for F in Findings do
    begin
      if F.FileName = '' then Continue;
      L := StrToIntDef(F.LineNumber, 0);
      if L <= 0 then Continue;
      Key := NormalizePath(F.FileName);
      if not FFindings.TryGetValue(Key, Lines) then
      begin
        Lines := TDictionary<Integer, TLeakSeverity>.Create;
        FFindings.Add(Key, Lines);
      end;
      if Lines.ContainsKey(L) then
      begin
        if Ord(F.Severity) < Ord(Lines[L]) then
          Lines[L] := F.Severity;
      end
      else
        Lines.Add(L, F.Severity);
    end;
  // Subclass an die aktuelle View anhaengen (idempotent), Repaint
  AttachToCurrent;
  for Sub in FSubclasses do
    Sub.Repaint;
end;

function TEditSubclassManager.FindOrAttachToCurrentEditWindow: TEditWindowSubclass;
var
  EditWin : INTAEditWindow;
  TheForm : TCustomForm;
  Sub     : TEditWindowSubclass;
begin
  Result := nil;
  EditWin := GetCurrentEditWindow;
  if EditWin = nil then Exit;
  TheForm := EditWin.Form;
  if TheForm = nil then Exit;
  // Schon eine Subclass fuer diese Form?
  for Sub in FSubclasses do
    if Sub.Form = TheForm then Exit(Sub);
  // Neu anlegen
  Sub := TEditWindowSubclass.Create(nil, TheForm);
  FSubclasses.Add(Sub);
  Result := Sub;
end;

procedure TEditSubclassManager.AttachToCurrent;
begin
  FindOrAttachToCurrentEditWindow;
end;

function TEditSubclassManager.TryGetSeverity(const FilePath: string;
  Line: Integer; out Severity: TLeakSeverity): Boolean;
var
  Lines: TDictionary<Integer, TLeakSeverity>;
begin
  Result := False;
  if FFindings.Count = 0 then Exit;
  if not FFindings.TryGetValue(NormalizePath(FilePath), Lines) then Exit;
  Result := Lines.TryGetValue(Line, Severity);
end;

{ ---- Public Register/Unregister ---- }

procedure RegisterEditSubclass;
begin
  if Assigned(GEditSubclassMgr) then Exit;
  GEditSubclassMgr := TEditSubclassManager.Create;
end;

procedure UnregisterEditSubclass;
begin
  if not Assigned(GEditSubclassMgr) then Exit;
  FreeAndNil(GEditSubclassMgr);
end;

end.
