unit uIDEFindingBulb;

// Editor-Gluehbirne im Plugin (Konzept_GluehbirneAnzeige_2026-10-08, Weg C,
// Arbeitsplan Stufe 2+3): an der CARET-Zeile, wenn ein Aktions-Anbieter
// (uFindingActions, z. B. reDelphix) zu einem Fund dort eine HILFE anbietet,
// die jetzt ausfuehrbar ist (Nico 2026-10-08: "nur wenn Editorhilfen
// vorhanden sind"). Klick oder Rechtsklick oeffnen das
// Aktionsmenue aus uFindingActionMenu in der Form moAvailableFixesOnly:
// ohne "Stelle zeigen" (der Benutzer steht schon dort), ohne ausgegraute
// Eintraege und Diagnosezeilen - Kontextmenue und Dock-Grid zeigen weiter
// alles. Die Menue-Taste erreicht die Birne nicht (sie bekommt nie den
// Fokus) und oeffnet das Editor-Kontextmenue; eine Tastenbedienung der
// Birne (Alt+Enter) ist eine spaetere Stufe (Review nach Bereichen
// 2026-10-10, Nit 46).
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
//     und Visible laufen danach aus der Nachrichtenschleife - auch das
//     Ausblenden einer Birne, deren Editor ein neues Fensterhandle bekam
//     (RetireBulb merkt sie nur vor, ProcessPending blendet aus und gibt frei;
//     Review 2026-10-14). KEIN eigener OTA-Slot.
//   * Beim Scrollen wandert die Birne mit der Zeile; aus nur, wenn die
//     Caret-Zeile nicht ganz sichtbar ist (Ausblenden waehrend des Scrollens
//     blinkte im Prototyp).
//   * Ob die Birne erscheint, entscheidet TBulbDecision (uBulbDecision,
//     SCA.SharedUI, mit Tests): zwei Stufen - billig die Funde der Zeile
//     (hoechstens einmal je Sekunde neu), teuer die Anbieter, erst wenn der
//     Caret BULB_SETTLE_MS ruht und je Schluessel Datei+Zeile+Zeilentext+
//     Funde nur einmal. Diese Unit liefert der Entscheidung nur die Uhr,
//     die Funde und die Antwort der Anbieter. Nach einer ausgefuehrten
//     Aktion werden alle Entscheidungen verworfen, und das Menue selbst
//     fragt beim Oeffnen frisch und korrigiert die Antwort.
//   * Ohne angemeldeten Anbieter tut die Birne nichts: Schedule und
//     UpdateEditor steigen vor jeder ToolsAPI-Beruehrung aus, der Takt
//     blendet sichtbare Birnen einmal aus (Review 2026-10-14).
//   * Editoren werden als HWND gemerkt; vor jeder Benutzung IsWindow und
//     FindControl. FreeNotification meldet geschlossene Editorfenster.
//   * Birnen ohne Owner und ohne Name; beim Abmelden alle freigeben, bevor
//     das Paket geht (ihre VMT liegt hier).
//
// BEKANNTE GRENZE: die Zeilen der Funde wandern bei Aenderungen oberhalb
// nicht mit, bis neu gescannt wird - wie beim Editor-Kontextmenue
// (FindingsAtEditorLine liest die Zeilen des Scans; je Datei aus der
// juengeren Quelle, Dock oder Silent-/Auto-Scan - seit 2026-10-10 nie
// gemischt).
//
// Anmeldung als UI-Element 'EditorBulb' (SortKey 35, nach dem
// LineHighlighter, dessen Notifier die Ereignisse liefert), Not-Aus
// [UI] Element.EditorBulb=0. Abgebaut wird ueber dieselbe Registry
// (uIDEExpert.TeardownUiElements -> UnregisterFindingBulb), rueckwaerts
// VOR dem LineHighlighter; die finalization unten ist nur das Netz fuer
// den Fall, dass die Registry nie lief.

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

// Baut die Birne auf (Anmelde-Seite des UI-Elements 'EditorBulb'): legt
// den Manager mit Hilfsfenster und Caret-Takt an und merkt sich die
// Fundquelle. Idempotent - ein zweiter Aufruf aendert nichts (auch nicht
// die Quelle). Braucht keinen IDE-Dienst; die Ereignisse kommen vom
// Editor-Notifier des LineHighlighters (FindingBulbEditorChanged).
procedure RegisterFindingBulb(const AFindingsAt: TBulbFindingsAt);
// Baut die Birne ab (Abbau-Seite des Elements, aus TeardownUiElements):
// Takt und Hilfsfenster weg, alle Birnen freigegeben, solange das Paket
// noch geladen ist. Idempotent; danach ist FindingBulbEditorChanged ein
// No-op.
procedure UnregisterFindingBulb;

// Aus dem Editor-Notifier (EndPaint, EditorScrolled, EditorResized,
// Faltung): nur vormerken. Ohne angemeldete Birne ein No-op.
procedure FindingBulbEditorChanged(const AEditor: TWinControl);

implementation

// noinspection-file ExceptionTooGeneral
// Im IDE-Prozess darf keine Ausnahme aus Hilfsfenster, Timer oder
// Freigabe in den Editor entweichen - AUSSER einem erschoepften Stapel und
// EAbort: die gehen weiter zu Application.HandleException (uCrashDiag).

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.Types, System.Generics.Collections, Vcl.Forms, Vcl.Menus,
  ToolsAPI, ToolsAPI.Editor,
  uCrashDiag,             // EStackExhausted - nie verschlucken
  uFindingActions,        // ProviderCount, TFindingAction
  uFindingActionMenu,     // das eine Menue-Modell (Stufe C), FindingIdentityKey
  uIDEFindingActionMenu,  // Modell -> TMenuItems
  uIDEEditorIntegration,  // ViewFileAndLine - eine Fassung mit dem Kontextmenue
  uLocalization,
  uBulbDecision,          // ob die Birne erscheint (getestet)
  uEditorBulbGeometry, uEditorBulbButton;

const
  WM_SCA_BULB_UPDATE  = WM_APP + 212;
  TIMER_CARET         = 1;     // Caret-Zeile nachfuehren (Tastatur loest kein Paint aus)
  CARET_POLL_MS       = 250;
  SIG_SEP             = #1;    // Trenner im Fingerabdruck der Funde einer Zeile

type
  TFindingBulbManager = class(TComponent)
  private
    FFindingsAt : TBulbFindingsAt;
    FWnd        : HWND;
    FPosted     : Boolean;
    FDestroying : Boolean;
    FEditors    : TDictionary<HWND, TWinControl>;
    FBulbs      : TDictionary<HWND, TSCABulbButton>;
    FDecisions  : TDictionary<HWND, TBulbDecision>;
    FPending    : TList<HWND>;
    // Birnen eines Editors, der ein neues Handle bekam (RetireBulb aus
    // Schedule): ausgeblendet und freigegeben erst in ProcessPending aus der
    // Nachrichtenschleife - nicht im Paint-Rueckruf des Editors, aber
    // solange das Paket geladen ist.
    FDoomed     : TList<TSCABulbButton>;
    FMenu       : TPopupMenu;
    FActions    : TArray<TFindingAction>;   // die des zuletzt geoeffneten Menues
    procedure WndProc(var Msg: TMessage);
    procedure Schedule(const AEditor: TWinControl);
    procedure ProcessPending;
    procedure PollCaret;
    procedure UpdateEditor(AEditorWnd: HWND);
    procedure HideBulb(AEditorWnd: HWND);
    procedure HideAllBulbs;
    // Alles zu AKey vergessen; die Birne dazu bleibt, wo sie ist (sie
    // stirbt mit ihrem Editor).
    procedure ForgetKey(AKey: HWND);
    // Wie ForgetKey, aber die Birne dazu zum Ausblenden und Freigeben
    // vormerken (FDoomed) - fuer einen Editor, der unter einem anderen
    // Handle weiterlebt. Ausgeblendet und freigegeben wird in
    // ProcessPending.
    procedure RetireBulb(AKey: HWND);
    function EditorOf(AEditorWnd: HWND): TWinControl;
    function BulbFor(AEditorWnd: HWND; AEditor: TWinControl): TSCABulbButton;
    function CaretOf(AEditor: TWinControl; out AFile: string;
      out ALine: Integer): Boolean;
    function WantsBulb(AEditorWnd: HWND; const AFile: string; ALine: Integer;
      const ALineText: string): Boolean;
    function HasAvailableFixes(const AFound: TArray<TLeakFinding>): Boolean;
    function FindCaretRect(AEditor: TWinControl; ACaretLine: Integer;
      out ALineRect: TRect; out ACodeLeft: Integer;
      out ALineText: string): Boolean;
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
  FDecisions  := TDictionary<HWND, TBulbDecision>.Create;
  FPending    := TList<HWND>.Create;
  FDoomed     := TList<TSCABulbButton>.Create;
  FMenu       := TPopupMenu.Create(nil);
  FWnd := AllocateHWnd(WndProc);
  SetTimer(FWnd, TIMER_CARET, CARET_POLL_MS, nil);
end;

destructor TFindingBulbManager.Destroy;
var
  Bulbs : TArray<TSCABulbButton>;
  B     : TSCABulbButton;
begin
  FDestroying := True;
  // 1) keine Nachrichten und Timer mehr
  if FWnd <> 0 then
  begin
    KillTimer(FWnd, TIMER_CARET);
    DeallocateHWnd(FWnd);
    FWnd := 0;
  end;
  // 2) Birnen frei, solange das Paket noch geladen ist - auch die
  //    vorgemerkten eines umgezogenen Editors. Jede einzeln geschuetzt:
  //    wirft das Freigeben einer Birne (ihr Editorfenster ist im Abbau
  //    der IDE schon halb zerlegt), muessen die uebrigen trotzdem frei
  //    werden - ihre VMT liegt in diesem Paket.
  Bulbs := FBulbs.Values.ToArray + FDoomed.ToArray;
  for B in Bulbs do
  try
    B.Free;
  except
    on EStackExhausted do raise;
    on EAbort do raise;
    on E: Exception do
      BulbLog('Destroy: bulb ' + E.Message);
  end;
  // Die Editoren meldet TComponent.Destroy (inherited) ueber FFreeNotifies
  // ab - genau die lebenden. Eine eigene Schleife ueber FEditors riefe
  // RemoveFreeNotification auf einem Eintrag, der verwaist sein kann
  // (Review reDelphiX nach Bereichen 2026-10-10, Minor 21).
  FActions := nil;
  FreeAndNil(FMenu);
  FreeAndNil(FPending);
  FreeAndNil(FDoomed);
  FreeAndNil(FDecisions);
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
  Keys : TArray<HWND>;
  Key  : HWND;
begin
  inherited;
  if (Operation <> opRemove) or FDestroying or not Assigned(FBulbs) then Exit;
  // Eine Birne geht (meist mit ihrem Editor): Eintrag vergessen
  Keys := nil;
  for Pair in FBulbs do
    if Pair.Value = AComponent then
      Keys := Keys + [Pair.Key];
  for Key in Keys do
    FBulbs.Remove(Key);
  // ... auch eine vorgemerkte, die ihr Editor schon mitnimmt.
  if Assigned(FDoomed) then
    FDoomed.Remove(TSCABulbButton(AComponent));
  // Ein Editor geht: alles zu ihm vergessen (die Birne als Kind stirbt
  // mit) - unter JEDEM Handle, unter dem er stand (Minor 21).
  Keys := nil;
  for Ed in FEditors do
    if Ed.Value = AComponent then
      Keys := Keys + [Ed.Key];
  for Key in Keys do
    ForgetKey(Key);
end;

procedure TFindingBulbManager.ForgetKey(AKey: HWND);
begin
  FBulbs.Remove(AKey);
  FEditors.Remove(AKey);
  FDecisions.Remove(AKey);
  FPending.Remove(AKey);
end;

procedure TFindingBulbManager.RetireBulb(AKey: HWND);
var
  B : TSCABulbButton;
begin
  // Nur vormerken - Schedule ruft dies aus dem Paint-Rueckruf, und dort
  // darf kein Visible gesetzt werden (REGELN im Kopf).
  if FBulbs.TryGetValue(AKey, B) then
  begin
    FDoomed.Add(B);
    if not FPosted then
      FPosted := PostMessage(FWnd, WM_SCA_BULB_UPDATE, 0, 0);
  end;
  ForgetKey(AKey);
end;

// Handles in AEditors, deren Eintrag nicht mehr zu AEditor/AHandle passt:
// ein neues Fensterhandle desselben Editors (Theme-Wechsel, An-/Abdocken)
// oder ein wiederverwendetes Handle eines anderen Editors (Review reDelphiX
// nach Bereichen 2026-10-10, Minor 21) - sonst bliebe eine verwaiste Birne
// stehen.
function StaleEditorKeys(AEditors: TDictionary<HWND, TWinControl>;
  const AEditor: TWinControl; AHandle: HWND): TArray<HWND>;
var
  Ed : TPair<HWND, TWinControl>;
begin
  Result := nil;
  for Ed in AEditors do
    if ((Ed.Value = AEditor) and (Ed.Key <> AHandle))
       or ((Ed.Key = AHandle) and (Ed.Value <> AEditor)) then
      Result := Result + [Ed.Key];
end;

{ ---- Ereignisse aus dem Editor: nur vormerken ---- }

procedure TFindingBulbManager.Schedule(const AEditor: TWinControl);
var
  H   : HWND;
  Key : HWND;
begin
  if FDestroying or (FWnd = 0) or not Assigned(AEditor) then Exit;
  // Ohne Anbieter gibt es keine Hilfe (Monolith: nie) - kein Vormerken,
  // keine Runde je Paint (Review 2026-10-14). Sichtbare Birnen blendet
  // der Takt aus.
  if TFindingActions.ProviderCount = 0 then Exit;
  try
    if not AEditor.HandleAllocated then Exit;
    H := AEditor.Handle;
    // Der alte Eintrag eines umgezogenen Editors samt Birne zieht um bzw.
    // raeumt (StaleEditorKeys).
    for Key in StaleEditorKeys(FEditors, AEditor, H) do
      RetireBulb(Key);
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
    on EStackExhausted do raise;
    on EAbort do raise;
    // Schedule laeuft im Editor-Rueckruf: ein Fehler beim Vormerken kostet
    // nur diese Aktualisierung, nie das Zeichnen des Editors.
    on E: Exception do
      BulbLog('Schedule ' + E.Message);
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
    // Ein erschoepfter Stapel (tiefer Parse im Anbieter) und ein Abbruch
    // gehen weiter zu Application.HandleException - lieber ein sichtbarer
    // Fehler als eine IDE, die ohne Schutzseite weiterlaeuft (uCrashDiag).
    on EStackExhausted do raise;
    on EAbort do raise;
    // Sonst kostet ein Fehler nur diese Birnen-Runde.
    on E: Exception do
      BulbLog('WndProc ' + E.Message);
  end;
  Msg.Result := DefWindowProc(FWnd, Msg.Msg, Msg.WParam, Msg.LParam);
end;

procedure TFindingBulbManager.ProcessPending;
var
  Items : TArray<HWND>;
  H     : HWND;
  B     : TSCABulbButton;
begin
  if FDestroying then Exit;
  // Vorgemerkte Birnen umgezogener Editoren: hier, aus der
  // Nachrichtenschleife, ausblenden und freigeben.
  while FDoomed.Count > 0 do
  begin
    B := FDoomed[FDoomed.Count - 1];
    FDoomed.Delete(FDoomed.Count - 1);
    B.Visible := False;
    B.Free;
  end;
  Items := FPending.ToArray;
  FPending.Clear;
  for H in Items do
    UpdateEditor(H);
end;

// Tastatur bewegt den Caret ohne Paint-Ereignis, und ein neuer Scan
// aendert die Funde ohne Caret-Bewegung: oberen Editor nachfuehren, wenn
// die Entscheidung es verlangt (TBulbDecision.NeedsRevisit).
procedure TFindingBulbManager.PollCaret;
var
  Svc      : INTACodeEditorServices;
  Ed       : TWinControl;
  FileName : string;
  Line     : Integer;
  D        : TBulbDecision;
begin
  if FDestroying then Exit;
  try
    // Ohne Anbieter gibt es keine Hilfe (Monolith: nie), bei inaktiver IDE
    // bewegt sich kein Caret - dann keine Runde je Sekunde (Review
    // reDelphiX nach Bereichen 2026-10-10, Minor 22). Sichtbare Birnen
    // gehen einmal aus.
    if TFindingActions.ProviderCount = 0 then
    begin
      HideAllBulbs;
      Exit;
    end;
    if not Application.Active then Exit;
    if not Supports(BorlandIDEServices, INTACodeEditorServices, Svc) then Exit;
    Ed := Svc.GetTopEditor;
    if not Assigned(Ed) or not Ed.HandleAllocated then Exit;
    if not CaretOf(Ed, FileName, Line) then
    begin
      Schedule(Ed);   // die Birne einer verlassenen Zeile muss weg
      Exit;
    end;
    if not FDecisions.TryGetValue(Ed.Handle, D) then
      D.Reset;
    if D.NeedsRevisit(FileName, Line, GetTickCount64) then
      Schedule(Ed);
  except
    on EStackExhausted do raise;
    on EAbort do raise;
    // Ein Fehler beim Nachfuehren kostet nur diesen Takt.
    on E: Exception do
      BulbLog('PollCaret ' + E.Message);
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
// Die Ansicht DIESES Editors (nicht TopView: die Birne haengt an jedem
// Editor, auch in der geteilten Ansicht); Datei und Zeile daraus liest
// dieselbe Funktion wie das Kontextmenue.
var
  Svc : INTACodeEditorServices;
begin
  AFile  := '';
  ALine  := -1;
  Result := False;
  if not Supports(BorlandIDEServices, INTACodeEditorServices, Svc) then Exit;
  Result := TIDEEditor.ViewFileAndLine(Svc.GetViewForEditor(AEditor), AFile,
    ALine);
end;

// Fingerabdruck der Funde einer Zeile: aendert ein neuer Scan sie, wird
// die Anbieter-Antwort neu eingeholt. Je Fund die Identitaet, mit der auch
// das Menue Doppelte erkennt (FindingIdentityKey).
function FindingsSignature(const AFound: TArray<TLeakFinding>): string;
var
  F  : TLeakFinding;
  SB : TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    for F in AFound do
      if Assigned(F) then
        SB.Append(FindingIdentityKey(F)).Append(SIG_SEP);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TFindingBulbManager.WantsBulb(AEditorWnd: HWND; const AFile: string;
  ALine: Integer; const ALineText: string): Boolean;
// Treiber der Entscheidung (uBulbDecision): liefert Uhr, Funde und die
// Antwort der Anbieter; die Regeln stehen dort.
var
  D        : TBulbDecision;
  NowMs    : UInt64;
  Found    : TArray<TLeakFinding>;
  FoundNow : Boolean;
begin
  NowMs := GetTickCount64;
  if not FDecisions.TryGetValue(AEditorWnd, D) then
    D.Reset;
  Found    := nil;
  FoundNow := False;
  if D.WantsFindings(AFile, ALine, NowMs) then
  begin
    FoundNow := True;
    if Assigned(FFindingsAt) then
      Found := FFindingsAt(AFile, ALine);
    D.NoteFindings(AFile, ALine, FindingsSignature(Found), NowMs);
  end;
  if D.WantsProviderCheck(ALineText, NowMs) then
  begin
    // ERST als gefragt speichern, dann fragen: wirft ein Anbieter (etwa
    // ein Stapelueberlauf im Parse), fragte PollCaret dieselbe Zeile sonst
    // alle 250 ms erneut - ohne Schutzseite endet der zweite Ueberlauf hart.
    FDecisions.AddOrSetValue(AEditorWnd, D);
    // Die Funde aus Stufe 1 dieser Runde, sonst frisch (Minor 22).
    if not FoundNow and Assigned(FFindingsAt) then
      Found := FFindingsAt(AFile, ALine);
    D.NoteProviderAnswer(HasAvailableFixes(Found));
  end;
  FDecisions.AddOrSetValue(AEditorWnd, D);
  Result := D.ShowsBulb;
end;

function TFindingBulbManager.HasAvailableFixes(
  const AFound: TArray<TLeakFinding>): Boolean;
var
  Model : TFindingMenuModel;
  i     : Integer;
begin
  Result := False;
  if Length(AFound) = 0 then Exit;
  Model := BuildFindingMenuModel(AFound, [moAvailableFixesOnly]);
  for i := 0 to High(Model.Errors) do
    BulbLog('finding action provider failed - ' + Model.Errors[i]);
  Result := not Model.IsEmpty;
end;

function TFindingBulbManager.FindCaretRect(AEditor: TWinControl;
  ACaretLine: Integer; out ALineRect: TRect; out ACodeLeft: Integer;
  out ALineText: string): Boolean;
// Lage der Caret-Zeile direkt ueber IsLogicalLineVisible und
// LogicalLineState - nicht mehr ueber bis zu 600 LineState-Abfragen von
// TopLine bis BottomLine (Review 2026-10-14). False, wenn die Zeile nicht
// sichtbar ist (gescrollt oder gefaltet).
//
// State.Refresh VOR dem Lesen - und das ist zugleich die Antwort auf H6
// der Caret-Synthese ("laesst INTACodeEditorState.Refresh malen?"): diese
// Routine laeuft nach JEDEM EndPaint des Editors (Notifier -> Schedule ->
// Nachricht -> UpdateEditor) und ruft Refresh ohne Schleife; malte Refresh,
// folgte ein EndPaint, und die Birne liefe in einen Dauer-Repaint - in der
// IDE gemessen: kein Blinken beim Scrollen (Nico 2026-10-08). Refresh
// malt also nicht. uIDELineHighlighter.HitCacheKeyOf vermerkt dasselbe.
var
  Svc   : INTACodeEditorServices;
  State : INTACodeEditorState;
  LS    : INTACodeEditorLineState;
begin
  Result := False;
  ALineRect := Rect(0, 0, 0, 0);
  ACodeLeft := 0;
  ALineText := '';
  if not Supports(BorlandIDEServices, INTACodeEditorServices, Svc) then Exit;
  State := Svc.GetEditorState(AEditor);
  if not Assigned(State) then Exit;
  State.Refresh;
  ACodeLeft := State.CodeLeftEdge;
  if not State.IsLogicalLineVisible(ACaretLine) then Exit;
  LS := State.LogicalLineState[ACaretLine];
  if not Assigned(LS) or (LS.LogicalLineNum <> ACaretLine) then Exit;
  ALineRect := LS.WholeRect;
  if ALineRect.Bottom <= ALineRect.Top then
    ALineRect.Bottom := ALineRect.Top + State.CharHeight;
  ALineText := LS.Text;
  Result := True;
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

procedure TFindingBulbManager.HideAllBulbs;
var
  B : TSCABulbButton;
begin
  for B in FBulbs.Values do
    if B.Visible then
      B.Visible := False;
end;

procedure TFindingBulbManager.UpdateEditor(AEditorWnd: HWND);
var
  Ed       : TWinControl;
  B        : TSCABulbButton;
  FileName : string;
  Line     : Integer;
  LineText : string;
  LineRect : TRect;
  CodeLeft : Integer;
  Inp      : TEditorBulbInput;
  R        : TRect;
  PPI      : Integer;
  D        : TBulbDecision;
begin
  Ed := EditorOf(AEditorWnd);
  // Ohne Anbieter keine ToolsAPI-Beruehrung (Review 2026-10-14).
  if not Assigned(Ed) or (TFindingActions.ProviderCount = 0) then
  begin
    HideBulb(AEditorWnd);
    Exit;
  end;
  try
    if not CaretOf(Ed, FileName, Line) then
    begin
      HideBulb(AEditorWnd);
      Exit;
    end;
    // Erst die Lage, dann die Entscheidung: eine unsichtbare Zeile fragt
    // nie die Anbieter, stempelt aber den Stand - sonst plante der Takt
    // alle 250 ms neu, bis die Zeile wieder sichtbar ist.
    if not FindCaretRect(Ed, Line, LineRect, CodeLeft, LineText) then
    begin
      if not FDecisions.TryGetValue(AEditorWnd, D) then
        D.Reset;
      D.NoteLineHidden(FileName, Line, GetTickCount64);
      FDecisions.AddOrSetValue(AEditorWnd, D);
      HideBulb(AEditorWnd);
      Exit;
    end;
    if not WantsBulb(AEditorWnd, FileName, Line, LineText) then
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
    on EStackExhausted do raise;
    on EAbort do raise;
    // Sonst kostet ein Fehler nur die Birne dieses Editors.
    on E: Exception do
      BulbLog('UpdateEditor ' + E.Message);
  end;
end;

{ ---- Menue ---- }

// Vor dem Oeffnen: zu welchem Editor gehoert die geklickte Birne? Dessen
// Caret-Zeile bestimmt die Funde; die Aktionen werden JETZT erfragt -
// frisch, damit die Objekte der Anbieter zum Menue passen. Nur verfuegbare
// Hilfen (moAvailableFixesOnly); die frische Antwort korrigiert zugleich
// die gemerkte - ist nichts mehr da, geht die Birne danach aus.
procedure TFindingBulbManager.BulbBeforeMenu(Sender: TObject);
var
  Pair      : TPair<HWND, TSCABulbButton>;
  EditorWnd : HWND;
  Ed        : TWinControl;
  FileName  : string;
  Line      : Integer;
  Model     : TFindingMenuModel;
  Item      : TMenuItem;
  D         : TBulbDecision;
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
      Model := BuildFindingMenuModel(FFindingsAt(FileName, Line),
        [moHeaders, moAvailableFixesOnly]);
      for i := 0 to High(Model.Errors) do
        BulbLog('finding action provider failed - ' + Model.Errors[i]);
      FActions := Model.Actions;
      FillPopupFromModel(FMenu, Model, ActionClick, 0, FMenu, nil);
      if FDecisions.TryGetValue(EditorWnd, D) then
      begin
        D.NoteProviderAnswer(not Model.IsEmpty);
        FDecisions.AddOrSetValue(EditorWnd, D);
      end;
      if Model.IsEmpty then
        Schedule(Ed);
    end;
  except
    on EStackExhausted do raise;
    on EAbort do raise;
    // Sonst bleibt das Menue mit 'Keine Aktionen' stehen.
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
    on EAbort do raise;   // ein stiller Abbruch ist keine Warnung wert
    on E: Exception do
      Application.MessageBox(
        PChar(Format(_('Finding action failed: %s'), [E.Message])),
        'Static Code Analyser', MB_OK or MB_ICONWARNING);
  end;
  // Die Aktion hat den Text geaendert (auch ausserhalb der Zeile, etwa die
  // uses-Klausel): keine gemerkte Entscheidung gilt mehr.
  FDecisions.Clear;
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
  // NUR Sicherheitsnetz: regulaer baut die UI-Registry die Birne ab
  // (uIDEExpert.TeardownUiElements -> UnregisterFindingBulb, vor dem
  // LineHighlighter). Hierher kommt ein lebender Manager nur, wenn die
  // Registry nie lief (die IDE entlaedt das Paket ohne Wizard-Destruktor).
  // Dann ist das Freigeben das kleinere Uebel gegenueber dem Leck: die
  // Birnen sind Kinder lebender Editoren, und ihre VMT liegt in diesem
  // Paket - stehen sie, zeichnet der naechste Paint in entladenen Code.
  if Assigned(GBulbManager) then
  begin
    BulbLog('finalization: manager still alive - the UI registry did not '
      + 'tear it down');
    FreeAndNil(GBulbManager);
  end;

end.
