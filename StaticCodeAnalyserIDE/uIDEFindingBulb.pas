unit uIDEFindingBulb;

// Editor-Gluehbirne im Plugin (Konzept_GluehbirneAnzeige_2026-10-08, Weg C,
// Arbeitsplan Stufe 2+3): an der CARET-Zeile, wenn dort ein Fund liegt und ein
// Aktions-Anbieter (uFindingActions, z. B. reDelphix) angemeldet ist.
// Klick, Rechtsklick oder Menue-Taste auf die Birne oeffnen dasselbe
// Aktionsmenue wie das Editor-Kontextmenue (uFindingActionMenu).
//
// Die Birne ist ein echtes Steuerelement (uEditorBulbButton) als KIND des
// Code-Editors, im Gutter rechtsbuendig vor dem Code. Der Aufbau ist der
// des Prototyps EditorLamp (mess/editor-bulb f8917083), in der IDE gemessen:
// kein Blinken beim Scrollen, keine IDE-Meldung bei 20+20 Klicks, Entladen
// ohne Fehler, Birne immer an der Caret-Zeile (Nico 2026-10-08).
//
// REGELN
//   * Nie im Zeichenpfad bewegen: der Editor-Notifier des Highlighters
//     ruft FindingBulbEditorChanged aus EndPaint/EditorScrolled, das merkt
//     den Editor nur vor und postet an ein eigenes Hilfsfenster. SetBounds
//     und Visible laufen danach aus der Nachrichtenschleife. KEIN eigener
//     OTA-Slot.
//   * Beim Scrollen wandert die Birne mit der Zeile; aus nur, wenn die
//     Caret-Zeile nicht ganz sichtbar ist (Ausblenden waehrend des Scrollens
//     blinkte im Prototyp).
//   * Ob die Birne erscheint, entscheidet ein billiger Test: Fund auf der
//     Zeile UND mindestens ein Anbieter. Die Aktionen selbst werden erst
//     beim Klick erfragt - reDelphix parst dafuer die ganze Datei, das ist
//     fuer jede Caret-Bewegung zu teuer (gleiches Muster wie das
//     Kontextmenue). Der Test wird je Zeile hoechstens einmal je Sekunde
//     wiederholt, damit ein neuer Scan die Birne nachzieht.
//   * Editoren werden als HWND gemerkt; vor jeder Benutzung IsWindow und
//     FindControl. FreeNotification meldet geschlossene Editorfenster.
//   * Birnen ohne Owner und ohne Name; beim Abmelden alle freigeben, bevor
//     das Paket geht (ihre VMT liegt hier).
//
// BEKANNTE GRENZE: die Zeilen der Funde wandern bei Aenderungen oberhalb
// nicht mit, bis neu gescannt wird - wie beim Editor-Kontextmenue
// (FindingsAtEditorLine liest die Zeilen des Scans).
//
// Anmeldung als UI-Element 'EditorBulb' (SortKey 35, nach dem
// LineHighlighter, dessen Notifier die Ereignisse liefert), Not-Aus
// [UI] Element.EditorBulb=0.

interface

uses
  Vcl.Controls,
  uMethodd12;

type
  // Funde, deren Bereich die Zeile einschliesst. Der Host reicht hier
  // FindingsAtEditorLine aus uIDEAnalyserForm herein - dieselbe Quelle wie
  // das Editor-Kontextmenue, ohne dass diese Unit das Dock-Fenster kennt.
  TBulbFindingsAt = reference to function(const AFile: string;
    ALine: Integer): TArray<TLeakFinding>;

procedure RegisterFindingBulb(const AFindingsAt: TBulbFindingsAt);
procedure UnregisterFindingBulb;

// Aus dem Editor-Notifier (EndPaint, EditorScrolled, EditorResized,
// Faltung): nur vormerken. Ohne angemeldete Birne ein No-op.
procedure FindingBulbEditorChanged(const AEditor: TWinControl);

implementation

// noinspection-file EmptyExcept, ExceptionTooGeneral
// Im IDE-Prozess darf keine Ausnahme aus Hilfsfenster, Timer oder
// Freigabe in den Editor entweichen.

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.Types, System.Generics.Collections, Vcl.Forms, Vcl.Menus,
  ToolsAPI, ToolsAPI.Editor,
  uCrashDiag,             // EStackExhausted - nie verschlucken
  uFindingActions,        // ProviderCount, TFindingAction
  uFindingActionMenu,     // das eine Menue-Modell (Stufe C)
  uIDEFindingActionMenu,  // Modell -> TMenuItems
  uLocalization,
  uEditorBulbGeometry, uEditorBulbButton;

const
  WM_SCA_BULB_UPDATE  = WM_APP + 212;
  TIMER_CARET         = 1;     // Caret-Zeile nachfuehren (Tastatur loest kein Paint aus)
  CARET_POLL_MS       = 250;
  FINDINGS_RECHECK_MS = 1000;  // ein neuer Scan zieht die Birne spaetestens so nach
  MAX_VISIBLE_SCAN    = 600;   // Obergrenze fuer TopLine..BottomLine

type
  // Was die Birne zuletzt fuer einen Editor entschieden hat.
  TBulbLineState = record
    FileName : string;
    Line     : Integer;
    Has      : Boolean;   // Fund auf der Zeile und ein Anbieter da
    Stamp    : UInt64;    // GetTickCount64 der Entscheidung
  end;

  TFindingBulbManager = class(TComponent)
  private
    FFindingsAt : TBulbFindingsAt;
    FWnd        : HWND;
    FPosted     : Boolean;
    FDestroying : Boolean;
    FEditors    : TDictionary<HWND, TWinControl>;
    FBulbs      : TDictionary<HWND, TSCABulbButton>;
    FLineState  : TDictionary<HWND, TBulbLineState>;
    FPending    : TList<HWND>;
    FMenu       : TPopupMenu;
    FActions    : TArray<TFindingAction>;   // die des zuletzt geoeffneten Menues
    procedure WndProc(var Msg: TMessage);
    procedure Schedule(const AEditor: TWinControl);
    procedure ProcessPending;
    procedure PollCaret;
    procedure UpdateEditor(AEditorWnd: HWND);
    procedure HideBulb(AEditorWnd: HWND);
    function EditorOf(AEditorWnd: HWND): TWinControl;
    function BulbFor(AEditorWnd: HWND; AEditor: TWinControl): TSCABulbButton;
    function CaretOf(AEditor: TWinControl; out AFile: string;
      out ALine: Integer): Boolean;
    function LineHasFindings(AEditorWnd: HWND; const AFile: string;
      ALine: Integer): Boolean;
    function FindCaretRect(AEditor: TWinControl; ACaretLine: Integer;
      out ALineRect: TRect; out ACodeLeft: Integer): Boolean;
    procedure BulbBeforeMenu(Sender: TObject);
    procedure ActionClick(Sender: TObject);
  protected
    procedure Notification(AComponent: TComponent;
      Operation: TOperation); override;
  public
    constructor Create(const AFindingsAt: TBulbFindingsAt); reintroduce;
    destructor Destroy; override;
  end;

var
  GBulbManager : TFindingBulbManager = nil;

// Fehler der Birne gehen an DebugView (Praefix 'SCA Bulb:') - der
// Diagnose-Kanal des Plugins; eine Meldung im Editor waere hier lauter als
// der Schaden.
procedure BulbLog(const AText: string);
begin
  // noinspection DebugOutput
  OutputDebugString(PChar('SCA Bulb: ' + AText));
end;

{ TFindingBulbManager }

constructor TFindingBulbManager.Create(const AFindingsAt: TBulbFindingsAt);
begin
  inherited Create(nil);
  FFindingsAt := AFindingsAt;
  FEditors    := TDictionary<HWND, TWinControl>.Create;
  FBulbs      := TDictionary<HWND, TSCABulbButton>.Create;
  FLineState  := TDictionary<HWND, TBulbLineState>.Create;
  FPending    := TList<HWND>.Create;
  FMenu       := TPopupMenu.Create(nil);
  FWnd := AllocateHWnd(WndProc);
  SetTimer(FWnd, TIMER_CARET, CARET_POLL_MS, nil);
end;

destructor TFindingBulbManager.Destroy;
var
  Bulbs : TArray<TSCABulbButton>;
  Eds   : TArray<TWinControl>;
  B     : TSCABulbButton;
  Ed    : TWinControl;
begin
  FDestroying := True;
  // 1) keine Nachrichten und Timer mehr
  if FWnd <> 0 then
  begin
    KillTimer(FWnd, TIMER_CARET);
    DeallocateHWnd(FWnd);
    FWnd := 0;
  end;
  // 2) Birnen frei, solange das Paket noch geladen ist
  Bulbs := FBulbs.Values.ToArray;
  for B in Bulbs do
  try
    B.Free;
  except
  end;
  Eds := FEditors.Values.ToArray;
  for Ed in Eds do
  try
    Ed.RemoveFreeNotification(Self);
  except
  end;
  FActions := nil;
  FreeAndNil(FMenu);
  FreeAndNil(FPending);
  FreeAndNil(FLineState);
  FreeAndNil(FBulbs);
  FreeAndNil(FEditors);
  FFindingsAt := nil;
  inherited Destroy;
end;

procedure TFindingBulbManager.Notification(AComponent: TComponent;
  Operation: TOperation);
var
  Pair : TPair<HWND, TSCABulbButton>;
  Ed   : TPair<HWND, TWinControl>;
  Key  : HWND;
begin
  inherited;
  if (Operation <> opRemove) or FDestroying or not Assigned(FBulbs) then Exit;
  // Eine Birne geht (meist mit ihrem Editor): Eintrag vergessen
  Key := 0;
  for Pair in FBulbs do
    if Pair.Value = AComponent then
    begin
      Key := Pair.Key;
      Break;
    end;
  if Key <> 0 then
    FBulbs.Remove(Key);
  // Ein Editor geht: alles zu ihm vergessen (die Birne als Kind stirbt mit)
  Key := 0;
  for Ed in FEditors do
    if Ed.Value = AComponent then
    begin
      Key := Ed.Key;
      Break;
    end;
  if Key <> 0 then
  begin
    FEditors.Remove(Key);
    FBulbs.Remove(Key);
    FLineState.Remove(Key);
    FPending.Remove(Key);
  end;
end;

{ ---- Ereignisse aus dem Editor: nur vormerken ---- }

procedure TFindingBulbManager.Schedule(const AEditor: TWinControl);
var
  H : HWND;
begin
  if FDestroying or (FWnd = 0) or not Assigned(AEditor) then Exit;
  try
    if not AEditor.HandleAllocated then Exit;
    H := AEditor.Handle;
    if not FEditors.ContainsKey(H) then
    begin
      FEditors.Add(H, AEditor);
      AEditor.FreeNotification(Self);
    end;
    if not FPending.Contains(H) then
      FPending.Add(H);
    if not FPosted then
      FPosted := PostMessage(FWnd, WM_SCA_BULB_UPDATE, 0, 0);
  except
  end;
end;

{ ---- Hilfsfenster: hier, nicht im Editor-Rueckruf, wird bewegt ---- }

procedure TFindingBulbManager.WndProc(var Msg: TMessage);
begin
  try
    if Msg.Msg = WM_SCA_BULB_UPDATE then
    begin
      FPosted := False;
      ProcessPending;
      Msg.Result := 0;
      Exit;
    end;
    if (Msg.Msg = WM_TIMER) and (Msg.WParam = TIMER_CARET) then
    begin
      PollCaret;
      Msg.Result := 0;
      Exit;
    end;
  except
    on E: Exception do
      BulbLog('WndProc ' + E.Message);
  end;
  Msg.Result := DefWindowProc(FWnd, Msg.Msg, Msg.WParam, Msg.LParam);
end;

procedure TFindingBulbManager.ProcessPending;
var
  Items : TArray<HWND>;
  H     : HWND;
begin
  if FDestroying then Exit;
  Items := FPending.ToArray;
  FPending.Clear;
  for H in Items do
    UpdateEditor(H);
end;

// Tastatur bewegt den Caret ohne Paint-Ereignis, und ein neuer Scan
// aendert die Funde ohne Caret-Bewegung: oberen Editor nachfuehren, wenn
// die Zeile wechselte oder die letzte Entscheidung zu alt ist.
procedure TFindingBulbManager.PollCaret;
var
  Svc      : INTACodeEditorServices;
  Ed       : TWinControl;
  FileName : string;
  Line     : Integer;
  St       : TBulbLineState;
begin
  if FDestroying then Exit;
  try
    if not Supports(BorlandIDEServices, INTACodeEditorServices, Svc) then Exit;
    Ed := Svc.GetTopEditor;
    if not Assigned(Ed) or not Ed.HandleAllocated then Exit;
    if not CaretOf(Ed, FileName, Line) then
    begin
      Schedule(Ed);   // die Birne einer verlassenen Zeile muss weg
      Exit;
    end;
    if not FLineState.TryGetValue(Ed.Handle, St) or (St.Line <> Line) or
       not SameText(St.FileName, FileName) or
       (GetTickCount64 - St.Stamp >= FINDINGS_RECHECK_MS) then
      Schedule(Ed);
  except
  end;
end;

function TFindingBulbManager.EditorOf(AEditorWnd: HWND): TWinControl;
begin
  Result := nil;
  if not FEditors.TryGetValue(AEditorWnd, Result) then Exit;
  // Vor jeder Benutzung: lebt das Fenster noch, und ist es noch DIESES
  // Steuerelement?
  if not IsWindow(AEditorWnd) or (FindControl(AEditorWnd) <> Result) then
    Result := nil;
end;

function TFindingBulbManager.CaretOf(AEditor: TWinControl; out AFile: string;
  out ALine: Integer): Boolean;
var
  Svc  : INTACodeEditorServices;
  View : IOTAEditView;
begin
  AFile := '';
  ALine := -1;
  Result := False;
  if not Supports(BorlandIDEServices, INTACodeEditorServices, Svc) then Exit;
  View := Svc.GetViewForEditor(AEditor);
  if not Assigned(View) or not Assigned(View.Buffer) then Exit;
  AFile := View.Buffer.FileName;
  ALine := View.CursorPos.Line;
  Result := (AFile <> '') and (ALine >= 1);
end;

function TFindingBulbManager.LineHasFindings(AEditorWnd: HWND;
  const AFile: string; ALine: Integer): Boolean;
var
  St    : TBulbLineState;
  NowMs : UInt64;
begin
  NowMs := GetTickCount64;
  if FLineState.TryGetValue(AEditorWnd, St) and (St.Line = ALine) and
     SameText(St.FileName, AFile) and (NowMs - St.Stamp < FINDINGS_RECHECK_MS) then
    Exit(St.Has);
  St.FileName := AFile;
  St.Line     := ALine;
  St.Stamp    := NowMs;
  St.Has      := (TFindingActions.ProviderCount > 0) and Assigned(FFindingsAt)
                 and (Length(FFindingsAt(AFile, ALine)) > 0);
  FLineState.AddOrSetValue(AEditorWnd, St);
  Result := St.Has;
end;

function TFindingBulbManager.FindCaretRect(AEditor: TWinControl;
  ACaretLine: Integer; out ALineRect: TRect; out ACodeLeft: Integer): Boolean;
var
  Svc   : INTACodeEditorServices;
  State : INTACodeEditorState;
  LS    : INTACodeEditorLineState;
  V, Last : Integer;
begin
  Result := False;
  ALineRect := Rect(0, 0, 0, 0);
  ACodeLeft := 0;
  if not Supports(BorlandIDEServices, INTACodeEditorServices, Svc) then Exit;
  State := Svc.GetEditorState(AEditor);
  if not Assigned(State) then Exit;
  State.Refresh;
  ACodeLeft := State.CodeLeftEdge;
  Last := State.BottomLine;
  if Last - State.TopLine > MAX_VISIBLE_SCAN then
    Last := State.TopLine + MAX_VISIBLE_SCAN;
  for V := State.TopLine to Last do
  begin
    LS := State.LineState[V];
    if Assigned(LS) and (LS.LogicalLineNum = ACaretLine) then
    begin
      ALineRect := LS.WholeRect;
      if ALineRect.Bottom <= ALineRect.Top then
        ALineRect.Bottom := ALineRect.Top + State.CharHeight;
      Exit(True);
    end;
  end;
end;

function TFindingBulbManager.BulbFor(AEditorWnd: HWND;
  AEditor: TWinControl): TSCABulbButton;
begin
  if FBulbs.TryGetValue(AEditorWnd, Result) then Exit;
  Result := TSCABulbButton.Create(nil);   // kein Owner, kein Name
  Result.Parent := AEditor;
  Result.DropdownMenu := FMenu;
  Result.OnBeforeMenu := BulbBeforeMenu;
  Result.Hint := _('Static Code Analyser: actions for this line');
  Result.FreeNotification(Self);
  FBulbs.Add(AEditorWnd, Result);
end;

procedure TFindingBulbManager.HideBulb(AEditorWnd: HWND);
var
  B : TSCABulbButton;
begin
  if FBulbs.TryGetValue(AEditorWnd, B) and B.Visible then
    B.Visible := False;
end;

procedure TFindingBulbManager.UpdateEditor(AEditorWnd: HWND);
var
  Ed       : TWinControl;
  B        : TSCABulbButton;
  FileName : string;
  Line     : Integer;
  LineRect : TRect;
  CodeLeft : Integer;
  Inp      : TEditorBulbInput;
  R        : TRect;
  PPI      : Integer;
begin
  Ed := EditorOf(AEditorWnd);
  if not Assigned(Ed) then
  begin
    HideBulb(AEditorWnd);
    Exit;
  end;
  try
    if not CaretOf(Ed, FileName, Line) or
       not LineHasFindings(AEditorWnd, FileName, Line) or
       not FindCaretRect(Ed, Line, LineRect, CodeLeft) then
    begin
      HideBulb(AEditorWnd);
      Exit;
    end;

    PPI := Ed.CurrentPPI;
    Inp.LineTop      := LineRect.Top;
    Inp.LineHeight   := LineRect.Bottom - LineRect.Top;
    Inp.GutterLeft   := 0;
    Inp.GutterRight  := CodeLeft;
    Inp.ClientHeight := Ed.ClientHeight;
    Inp.BulbSize     := ScaleBulbSize(BULB_SIZE_96, PPI);
    Inp.Gap          := ScaleBulbValue(BULB_GAP_96, PPI);
    if not BulbBounds(Inp, R) then
    begin
      HideBulb(AEditorWnd);
      Exit;
    end;

    B := BulbFor(AEditorWnd, Ed);
    if B.BoundsRect <> R then
      B.BoundsRect := R;
    if not B.Visible then
      B.Visible := True;
  except
    on E: Exception do
      BulbLog('UpdateEditor ' + E.Message);
  end;
end;

{ ---- Menue ---- }

// Vor dem Oeffnen: zu welchem Editor gehoert die geklickte Birne? Dessen
// Caret-Zeile bestimmt die Funde; die Aktionen werden JETZT erfragt -
// frisch, damit die Objekte der Anbieter zum Menue passen.
procedure TFindingBulbManager.BulbBeforeMenu(Sender: TObject);
var
  Pair      : TPair<HWND, TSCABulbButton>;
  EditorWnd : HWND;
  Ed        : TWinControl;
  FileName  : string;
  Line      : Integer;
  Model     : TFindingMenuModel;
  Item      : TMenuItem;
  i         : Integer;
begin
  FMenu.Items.Clear;
  FActions := nil;
  try
    EditorWnd := 0;
    for Pair in FBulbs do
      if Pair.Value = Sender then
      begin
        EditorWnd := Pair.Key;
        Break;
      end;
    Ed := EditorOf(EditorWnd);
    if Assigned(Ed) and Assigned(FFindingsAt) and CaretOf(Ed, FileName, Line) then
    begin
      Model := BuildFindingMenuModel(FFindingsAt(FileName, Line), [moHeaders]);
      for i := 0 to High(Model.Errors) do
        BulbLog('finding action provider failed - ' + Model.Errors[i]);
      FActions := Model.Actions;
      FillPopupFromModel(FMenu, Model, ActionClick, 0, FMenu, nil);
    end;
  except
    on E: Exception do
      BulbLog('BulbBeforeMenu ' + E.Message);
  end;
  if FMenu.Items.Count = 0 then
  begin
    Item := TMenuItem.Create(FMenu);
    Item.Caption := _('No actions for this line');
    Item.Enabled := False;
    FMenu.Items.Add(Item);
  end;
end;

procedure TFindingBulbManager.ActionClick(Sender: TObject);
var
  Idx : Integer;
  Act : TFindingAction;
begin
  if not (Sender is TMenuItem) then Exit;
  Idx := TMenuItem(Sender).Tag;
  if (Idx < 0) or (Idx > High(FActions)) then Exit;
  Act := FActions[Idx];
  if not Assigned(Act.Execute) then Exit;
  try
    Act.Execute(Sender);
  except
    on EStackExhausted do raise;
    on E: Exception do
      Application.MessageBox(
        PChar(Format(_('Finding action failed: %s'), [E.Message])),
        'Static Code Analyser', MB_OK or MB_ICONWARNING);
  end;
end;

{ ---- Anmeldung ---- }

procedure RegisterFindingBulb(const AFindingsAt: TBulbFindingsAt);
begin
  if Assigned(GBulbManager) then Exit;
  GBulbManager := TFindingBulbManager.Create(AFindingsAt);
end;

procedure UnregisterFindingBulb;
begin
  FreeAndNil(GBulbManager);
end;

procedure FindingBulbEditorChanged(const AEditor: TWinControl);
begin
  if Assigned(GBulbManager) then
    GBulbManager.Schedule(AEditor);
end;

// Ein finalization-Abschnitt ist nur hinter einem initialization-Abschnitt
// erlaubt (E2029) - deshalb der leere davor.
initialization

finalization
  // Sicherheitsnetz: regulaer baut die UI-Registry die Birne ab.
  FreeAndNil(GBulbManager);

end.
