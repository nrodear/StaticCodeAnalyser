unit uIDEFindingsPropertiesForm;

// OTAPI-Wrapper fuer das Findings-Properties-Panel (Konzept_FindingsPropertiesPanel
// Phase 3). Spiegelt das Pattern von uIDEAnalyserForm/TAnalyserDockableForm,
// haelt aber NUR den Wrapper hier - die UI lebt in SCA.SharedUI als plain
// VCL-Frame ohne ToolsAPI-Import.
//
// Layering-Constraint (aus dem Konzept):
//   SCA.SharedUI/uFindingsPropertiesFrame  - plain VCL, KEIN ToolsAPI
//   StaticCodeAnalyserIDE/<diese Unit>     - INTACustomDockableForm + Theme-
//                                            Subscribe + Watch-Mode-Subscribe
//
// Lifecycle:
//   1. RegisterFindingsPropertiesDockableForm (im RegisterAnalyserDockableForm-
//      Pfad nach RegisterWatchMode): erzeugt GFindingsPropsForm, registriert
//      das DockableForm beim NTAServices. Kein Frame, keine Subscription.
//   2. User klickt View > Findings Properties (oder per Editor-Context-Menu):
//      NTASvc.CreateDockableForm -> IDE erzeugt TFindingsPropertiesFrame
//      -> FrameCreated() wird gerufen:
//        - TIDETheme.Apply(Frame) + Subscribe (RefreshFromTheme bei Theme-
//          Change). Refcount-Token in FThemeSub gehalten.
//        - GWatchMode.SubscribeFindings(...) -> Updates kommen ueber den
//          Callback an. Refcount-Token in FFindingsSub.
//        - Beim aktuellen ActiveEditor-Tab vorab SetActiveFile aufrufen,
//          damit der Header sofort den File-Namen zeigt (auch ohne Watch
//          aktiv).
//   3. User schliesst das Dock-Fenster: IDE freed den Frame; FThemeSub und
//      FFindingsSub bleiben am Wrapper haengen (Subscriptions sind aktiv
//      solange der Wrapper lebt). Beim naechsten Open wird ein NEUER Frame
//      erzeugt - in FrameCreated subscriben wir erneut (alte Subscriptions
//      werden ueberschrieben, refcount-decay = auto-unsubscribe).

interface

uses
  Winapi.Windows,
  System.Classes, System.SysUtils, System.Generics.Collections,
  Vcl.Forms, Vcl.Controls, Vcl.Menus, Vcl.ActnList, Vcl.ImgList,
  Vcl.ComCtrls,                                 // TToolBar
  System.IniFiles,
  DesignIntf,                                   // TEditState, TEditAction
  ToolsAPI, DeskUtil, DockForm,
  uMethodd12,
  uFindingsPropertiesFrame;

type
  TFindingsPropertiesDockableForm = class(TInterfacedObject,
    INTACustomDockableForm)
  private
    FFrame         : TFindingsPropertiesFrame;
    // Refcount-Token: solange wir die Refs halten, ist die Subscription
    // aktiv. Bei Wrapper-Destroy refcount-decay -> Subscription entfernt
    // sich selbst aus dem jeweiligen Manager.
    FThemeSub      : IInterface;
    FFindingsSub   : IInterface;
    // Suppress-Window fuer EditorViewActivated: ein Click auf einen Finding
    // triggert OpenFileAtLine, das mehrere EditorViewActivated-Events feuern
    // kann (M.Show, SafeCloseModule, transient empty buffer). Diese wuerden
    // SetActiveFile triggern und das Grid clearen. Solange GetTickCount <
    // FSuppressActivationUntil ist, ignoriert HandleEditorViewActivated alle
    // Events. 250ms reichen fuer typische Event-Bursts ohne legitime
    // User-Tab-Wechsel nennenswert zu blockieren.
    FSuppressActivationUntil : Cardinal;
    // Window-State-Persistence (Option C, Hybrid):
    //   * IDE-Desktop-INI (Save/LoadWindowState) - sessionuebergreifend via
    //     Tools > Save Desktop / Project-Desktop-Persistenz.
    //   * analyser.ini - session-intern, ueberlebt User-Close+Reopen
    //     innerhalb der selben IDE-Session.
    //   * Center-on-IDE Fallback wenn beide leer ODER off-screen.
    // FPendingState wird in LoadWindowState gefuellt und in FrameCreated
    // angewandt (zum LoadWindowState-Zeitpunkt gibt es noch keinen Frame
    // bzw. HostForm).
    FPendingLeft   : Integer;
    FPendingTop    : Integer;
    FPendingWidth  : Integer;
    FPendingHeight : Integer;
    FHasPendingState : Boolean;
    procedure ReadIniState;
    procedure WriteIniState;
    procedure ApplyPendingStateToHost;
    procedure CenterOnIDEMainWindow;
    class function IniFilePath: string; static;
    class function IsRectOnAnyMonitor(L, T, W, H: Integer): Boolean; static;
    procedure HandleWatchFindings(const FileName: string;
      Findings: TObjectList<TLeakFinding>);
    procedure HandleFindingClick(Sender: TObject; Finding: TLeakFinding);
    procedure HandleFrameDestroying(Sender: TObject);
    procedure HandleEditorViewActivated(const AFileName: string);
    procedure HandleThemeChanged;
    procedure InitialPopulateFromActiveEditor;
    procedure TriggerAutoScan(const AFileName: string);
    function  CloneFinding(F: TLeakFinding): TLeakFinding;
  public
    // INTACustomDockableForm
    function GetCaption: string;
    function GetIdentifier: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    function GetMenuActionList: TCustomActionList;
    function GetMenuImageList: TCustomImageList;
    procedure CustomizePopupMenu(PopupMenu: TPopupMenu);
    function GetToolBarActionList: TCustomActionList;
    function GetToolBarImageList: TCustomImageList;
    procedure CustomizeToolBar(ToolBar: TToolBar);
    procedure SaveWindowState(Desktop: TCustomIniFile;
      const Section: string; IsProject: Boolean);
    procedure LoadWindowState(Desktop: TCustomIniFile; const Section: string);
    function GetEditState: TEditState;
    function EditAction(Action: TEditAction): Boolean;

    // Menue-Handler analog ViewMenuClick im TAnalyserDockableForm.
    procedure ViewMenuClick(Sender: TObject);

    property Frame: TFindingsPropertiesFrame read FFrame;
  end;

var
  GFindingsPropsForm: TFindingsPropertiesDockableForm = nil;
  // INTAEditServicesNotifier-Slot. Wird im RegisterFindingsPropertiesDockable-
  // Form angemeldet, im Unregister abgemeldet. Liefert EditorViewActivated -
  // damit kann das Properties-Panel auf Tab-Wechsel reagieren ohne dass
  // der User extra klicken muss.
  GFindingsPropsEditNotifIdx : Integer = -1;
  GFindingsPropsEditNotifIfc : INTAEditServicesNotifier = nil;
  // View > Static Code Analysis > Findings Properties - Menue-Eintrag.
  // Wird im Register angelegt, im Unregister freed (sonst bleibt ein
  // dangling Menuepunkt nach BPL-Reload).
  GFindingsPropsMenuItem     : TMenuItem = nil;

procedure RegisterFindingsPropertiesDockableForm;
procedure UnregisterFindingsPropertiesDockableForm;
procedure ShowFindingsPropertiesDockableForm;

implementation

// noinspection-file BeginEndRequired, EmptyMethod, PublicMemberWithoutDoc, TooLongLine, UnsortedUses, UnusedParameter, UnusedRoutine

uses
  System.IOUtils,
  Vcl.Graphics,
  uIDETheme,
  uIDEWatchMode,
  uIDEEditorIntegration,
  uIDEAnalyserForm,           // RunSilentAnalysisForFile
  uIDEToolbar,                // ApplySegoeUI - Plugin-Font
  uLocalization,              // _() Translation-Macro
  uRepoSettings;              // ConfigFilePath fuer analyser.ini

const
  // User-sichtbarer Name. In Anlehnung an das Plugin-Hauptmenue
  // "Static Code Analysis" - das Properties-Panel ist die per-File-
  // Schwester des Hauptfensters, daher gleicher Namespace mit
  // " - File"-Suffix.
  CAPTION_DEFAULT = 'Static Code Analysis - File';
  IDENTIFIER      = 'StaticCodeAnalyser.FindingsPropertiesDockForm';
  INI_SECTION     = 'FindingsPropertiesPanel';
  // Mindestabstand zum Bildschirmrand bei Off-Screen-Check. 8px reicht
  // damit die Titlebar noch greifbar ist.
  ONSCREEN_MARGIN = 8;

type
  // Phase 4: Editor-Tab-Change-Hook. EditorViewActivated feuert wenn der
  // User im Editor zwischen Tabs wechselt; wir mappen das auf
  // Frame.SetActiveFile. Klasse hier lokal gehalten (analog
  // TFindingEditSvcNotifier in uIDEWatchMode) - keine OTAPI-Notifier-
  // Implementierung leaked in shared UI.
  //
  // Lebenszeit: Notifier ist permanent registriert (Register..Unregister-
  // FindingsPropertiesDockableForm). EditorViewActivated checked ob ein
  // Frame existiert + nutzt den Wrapper-Hook. Wenn kein Frame da ist
  // (Dock-Fenster geschlossen), no-op.
  TFindingsPropsEditSvcNotifier = class(TNotifierObject,
    INTAEditServicesNotifier)
  protected
    procedure WindowShow(const EditWindow: INTAEditWindow;
      Show, LoadedFromDesktop: Boolean);
    procedure WindowNotification(const EditWindow: INTAEditWindow;
      Operation: TOperation);
    procedure WindowActivated(const EditWindow: INTAEditWindow);
    procedure WindowCommand(const EditWindow: INTAEditWindow;
      Command, Param: Integer; var Handled: Boolean);
    procedure EditorViewActivated(const EditWindow: INTAEditWindow;
      const EditView: IOTAEditView);
    procedure EditorViewModified(const EditWindow: INTAEditWindow;
      const EditView: IOTAEditView);
    procedure DockFormVisibleChanged(const EditWindow: INTAEditWindow;
      DockForm: TDockableForm);
    procedure DockFormUpdated(const EditWindow: INTAEditWindow;
      DockForm: TDockableForm);
    procedure DockFormRefresh(const EditWindow: INTAEditWindow;
      DockForm: TDockableForm);
  end;

{ TFindingsPropsEditSvcNotifier }

procedure TFindingsPropsEditSvcNotifier.EditorViewActivated(
  const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
var
  FileName: string;
begin
  if not Assigned(GFindingsPropsForm) then Exit;
  if not Assigned(EditView) or not Assigned(EditView.Buffer) then Exit;
  FileName := EditView.Buffer.FileName;
  if FileName = '' then Exit;
  GFindingsPropsForm.HandleEditorViewActivated(FileName);
end;

procedure TFindingsPropsEditSvcNotifier.WindowShow(
  const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);   begin end;
procedure TFindingsPropsEditSvcNotifier.WindowNotification(
  const EditWindow: INTAEditWindow; Operation: TOperation);              begin end;
procedure TFindingsPropsEditSvcNotifier.WindowActivated(
  const EditWindow: INTAEditWindow);                                     begin end;
procedure TFindingsPropsEditSvcNotifier.WindowCommand(
  const EditWindow: INTAEditWindow; Command, Param: Integer;
  var Handled: Boolean);                                                 begin end;
procedure TFindingsPropsEditSvcNotifier.EditorViewModified(
  const EditWindow: INTAEditWindow; const EditView: IOTAEditView);       begin end;
procedure TFindingsPropsEditSvcNotifier.DockFormVisibleChanged(
  const EditWindow: INTAEditWindow; DockForm: TDockableForm);            begin end;
procedure TFindingsPropsEditSvcNotifier.DockFormUpdated(
  const EditWindow: INTAEditWindow; DockForm: TDockableForm);            begin end;
procedure TFindingsPropsEditSvcNotifier.DockFormRefresh(
  const EditWindow: INTAEditWindow; DockForm: TDockableForm);            begin end;

{ TFindingsPropertiesDockableForm }

function TFindingsPropertiesDockableForm.GetCaption: string;
begin
  Result := _(CAPTION_DEFAULT);
end;

function TFindingsPropertiesDockableForm.GetIdentifier: string;
begin
  Result := IDENTIFIER;
end;

function TFindingsPropertiesDockableForm.GetFrameClass: TCustomFrameClass;
begin
  Result := TFindingsPropertiesFrame;
end;

procedure TFindingsPropertiesDockableForm.FrameCreated(AFrame: TCustomFrame);
// Wird vom IDE gerufen NACH dem TFindingsPropertiesFrame.Create. Hier:
//   - Theme apply + subscribe
//   - Watch-Mode Findings-Subscription anhaengen
//   - Click-Handler haengen
//   - Constraints aufs Host-Form propagieren (Float-Mindestgroesse)
//   - Falls Watch-Mode bereits eine watched Datei hat: SetActiveFile.
var
  HostForm: TCustomForm;
begin
  FFrame := AFrame as TFindingsPropertiesFrame;

  // Font-Reset auf Plugin-Standard (Segoe UI 8). Belt-and-suspenders zum
  // Frame-Constructor; manche IDE-Dock-Sequenzen ueberschreiben den Font
  // beim Re-Parent (selbe Begruendung wie TAnalyserDockableForm.FrameCreated).
  TIDEToolbar.ApplySegoeUI(FFrame);

  // Constraints aufs Host-Form propagieren - sonst kann der User das
  // floated Fenster auf 0px ziehen. Pattern aus TAnalyserDockableForm.
  HostForm := GetParentForm(FFrame);
  if Assigned(HostForm) then
  begin
    if HostForm.Constraints.MinWidth < FFrame.Constraints.MinWidth then
      HostForm.Constraints.MinWidth := FFrame.Constraints.MinWidth;
    if HostForm.Constraints.MinHeight < FFrame.Constraints.MinHeight then
      HostForm.Constraints.MinHeight := FFrame.Constraints.MinHeight;
  end;

  // Window-State restoren (Hybrid Option C):
  //   1. IDE-Desktop-State (FPending* aus LoadWindowState) hat Vorrang
  //   2. analyser.ini (Session-Persistence) als Fallback
  //   3. Center-on-IDE-MainWindow als Fallback-Fallback
  // ReadIniState ist no-op wenn schon Pending-Werte aus IDE-Desktop da
  // sind. ApplyPendingStateToHost validiert on-screen + nutzt
  // CenterOnIDEMainWindow wenn Werte ungueltig.
  ReadIniState;
  ApplyPendingStateToHost;

  // Initial-Apply: erstmal das jetzt aktive IDE-Theme einmalig anwenden,
  // damit das Frame nicht im Default-VCL-Style aufpoppt.
  TIDETheme.Apply(FFrame);
  FFrame.RefreshFromTheme;

  // Theme-Subscribe: bei IDE-Theme-Wechsel (Tools > Options > User Interface
  // > Theme) re-applien wir das Theme und triggern den Frame-internen
  // Refresh. Refcount-Token muss am Wrapper haengen - solange wir leben,
  // bleibt die Subscription aktiv. Callback muss `procedure of object`
  // sein - daher die HandleThemeChanged-Methode statt anonymer Block.
  FThemeSub := TIDETheme.Subscribe(HandleThemeChanged);

  // Watch-Mode-Subscription: jedes Mal wenn der Live-Watch-Worker ein
  // Ergebnis liefert, kriegen wir hier eine BORROWED Findings-Liste
  // (siehe TWatchFindingsSubscriber-Doku). Wir klonen sie und reichen
  // sie an den Frame weiter, der sie als OWNED uebernimmt.
  if Assigned(GWatchMode) then
    FFindingsSub := GWatchMode.SubscribeFindings(HandleWatchFindings);

  FFrame.OnFindingClick := HandleFindingClick;
  FFrame.OnDestroying   := HandleFrameDestroying;

  // Bei initialem Open: aktive Editor-Datei in den Header schreiben, auch
  // wenn noch kein Watch-Lauf gefeuert hat. Das gibt dem User sofort
  // visuelles Feedback "ich beobachte File X".
  InitialPopulateFromActiveEditor;
end;

procedure TFindingsPropertiesDockableForm.HandleThemeChanged;
// TIDETheme-Subscribe-Callback. Erwartet `procedure of object`. IDE hat
// das Theme gewechselt - Frame neu themen + Refresh.
begin
  if not Assigned(FFrame) then Exit;
  TIDETheme.Apply(FFrame);
  FFrame.RefreshFromTheme;
end;

procedure TFindingsPropertiesDockableForm.HandleEditorViewActivated(
  const AFileName: string);
// Tab-Wechsel im Editor. Wir wechseln den Frame-Header auf die neue Datei
// UND triggern automatisch einen Single-File-Scan damit der Properties-
// Panel-User die Findings sofort sieht ohne extra "Aktuelle Datei"-Klick.
// SetActiveFile ist idempotent fuer SameText-Treffer - kein Flicker.
// Suppress-Window: nach einem Finding-Click sendet ShowFileAtLine eine
// Burst-Sequenz von Events; in den ersten 250ms ignorieren.
begin
  if not Assigned(FFrame) then Exit;
  if GetTickCount < FSuppressActivationUntil then Exit;
  FFrame.SetActiveFile(AFileName);
  // Auto-Scan der neuen Datei. ACenterOnFirstFinding=False, sonst wuerde
  // der Editor bei jedem Tab-Wechsel auf den ersten Befund springen.
  // RunSilentAnalysisForFile dispatched die Findings via
  // GWatchMode.DispatchToSubscribers an unseren HandleWatchFindings.
  TriggerAutoScan(AFileName);
end;

procedure TFindingsPropertiesDockableForm.HandleFrameDestroying(
  Sender: TObject);
// IDE schliesst das Dock-Fenster ODER macht Dock/Undock-Recreate. Im
// Recreate-Pfad wird der NEUE Frame ZUERST erstellt (FrameCreated bumpt
// FFrame := NEW), dann der ALTE zerstoert (Sender = OLD, NICHT == FFrame).
// Ohne den Sender-Check wuerden wir FFrame :=  nil setzen und damit den
// gerade frisch verbundenen NEUEN Frame "vergessen" - Properties-Panel
// bekaeme keine Subscriber-Updates mehr und bliebe leer.
begin
  if Sender = FFrame then
  begin
    // Window-State persistieren BEVOR der Frame gefreed wird - sonst ist
    // GetParentForm bereits nil. WriteIniState liest Host.Left/Top/W/H.
    WriteIniState;
    FFrame := nil;
  end;
end;

procedure TFindingsPropertiesDockableForm.HandleWatchFindings(
  const FileName: string; Findings: TObjectList<TLeakFinding>);
// Watch-Mode-Subscriber-Callback. Findings sind BORROWED (siehe Doku in
// uIDEWatchMode); wir muessen klonen wenn wir sie persistieren wollen.
// Der Frame uebernimmt eine OWNED-TObjectList - also klonen wir hier.
var
  Owned : TObjectList<TLeakFinding>;
  F     : TLeakFinding;
begin
  if not Assigned(FFrame) then Exit;
  Owned := TObjectList<TLeakFinding>.Create({AOwnsObjects=}True);
  try
    if Assigned(Findings) then
      for F in Findings do
        Owned.Add(CloneFinding(F));
  except
    Owned.Free;
    raise;
  end;
  // Ownership-Transfer in den Frame; SetFindings macht's atomisch + freed
  // Owned nach dem Reinkopieren in FAllFindings.
  FFrame.SetFindings(FileName, Owned);
end;

function TFindingsPropertiesDockableForm.CloneFinding(
  F: TLeakFinding): TLeakFinding;
// Deep-Copy aller Datenfelder. Alle Felder sind value-types oder strings -
// shallow copy reicht.
begin
  Result := TLeakFinding.Create;
  Result.FileName   := F.FileName;
  Result.MethodName := F.MethodName;
  Result.LineNumber := F.LineNumber;
  Result.MissingVar := F.MissingVar;
  Result.Severity   := F.Severity;
  Result.Kind       := F.Kind;
  Result.Confidence := F.Confidence;
  Result.RuleID     := F.RuleID;
end;

procedure TFindingsPropertiesDockableForm.HandleFindingClick(Sender: TObject;
  Finding: TLeakFinding);
// Soft-Navigate via TIDEEditor.ShowFileAtLine - bringt die Datei nach
// vorne (oder oeffnet sie wenn noch nicht da), setzt den Caret. Wichtig:
// NICHT TIDEEditor.OpenFileAtLine - das macht SafeCloseModule auf die
// Companion-Datei, was ein normales Form-Modul (Foo.pas+Foo.dfm) komplett
// schliesst weil FindModule(Foo.dfm) das Foo-Modul liefert. Effekt waere:
// jeder Click oeffnet die Datei neu.
//
// Suppress-Window: ShowFileAtLine kann mehrere EditorViewActivated-
// Events feuern (Show + CursorPos + Paint). Ohne Suppress wuerde der
// Tab-Wechsel-Hook diese als "User wechselt zu anderer Datei" interpretieren
// und das Grid clearen.
var
  Line: Integer;
begin
  if not Assigned(Finding) then Exit;
  if Finding.FileName = '' then Exit;
  Line := StrToIntDef(Finding.LineNumber, 0);
  if Line <= 0 then Exit;

  FSuppressActivationUntil := GetTickCount + 250;   // ms
  TIDEEditor.ShowFileAtLine(Finding.FileName, Line);
  TIDEEditor.CenterCurrentViewOnLine(Line);
end;

procedure TFindingsPropertiesDockableForm.InitialPopulateFromActiveEditor;
// Beim ersten Open ODER nach Dock/Undock-Recreate: aktive Editor-Datei in
// den Frame-Header schreiben + Auto-Scan triggern. SetActiveFile bleibt
// synchron (nur State-Update). TriggerAutoScan wird ueber ForceQueue
// nach-getaktet, damit das Dock-Layout fertig ist bevor wir die Findings-
// Pipeline anwerfen - sonst kann der NEUE Frame Findings empfangen waehrend
// die IDE noch beim Parent-Setup ist, was zum Verlust der Findings beim
// Recreate fuehrt.
var
  EditSvc       : IOTAEditorServices;
  TopView       : IOTAEditView;
  FileName      : string;
  CapturedName  : string;
begin
  if not Assigned(FFrame) then Exit;
  if not Supports(BorlandIDEServices, IOTAEditorServices, EditSvc) then Exit;
  TopView := EditSvc.TopView;
  if not Assigned(TopView) or not Assigned(TopView.Buffer) then Exit;
  FileName := TopView.Buffer.FileName;
  if FileName = '' then Exit;
  FFrame.SetActiveFile(FileName);

  // ForceQueue auf Main-Thread - der anonyme Block laeuft im naechsten
  // Message-Loop-Tick. Global-Singleton-Check schuetzt gegen Wrapper-
  // Unregister waehrend des Queue-Slots.
  CapturedName := FileName;
  TThread.ForceQueue(nil,
    procedure
    begin
      if not Assigned(GFindingsPropsForm) then Exit;
      if not Assigned(GFindingsPropsForm.FFrame) then Exit;
      GFindingsPropsForm.TriggerAutoScan(CapturedName);
    end);
end;

procedure TFindingsPropertiesDockableForm.TriggerAutoScan(
  const AFileName: string);
// Single-File-Auto-Scan ueber den Silent-Pfad. Findings landen via
// DispatchToSubscribers in HandleWatchFindings -> Frame.SetFindings.
// ACenterOnFirstFinding=False unterdrueckt das Editor-Scroll-To-First-
// Finding (sonst springt der Editor bei jedem Tab-Wechsel unerwartet).
//
// Nur fuer .pas / .dpr / .dpk - andere Extensions (.dfm-as-Text, .inc, ...)
// hat der Detector kein sinnvolles Single-File-Analyse-Modell.
var
  Ext: string;
begin
  if AFileName = '' then Exit;
  Ext := LowerCase(ExtractFileExt(AFileName));
  if not ((Ext = '.pas') or (Ext = '.dpr') or (Ext = '.dpk')) then Exit;
  if not FileExists(AFileName) then Exit;
  // RunSilentAnalysisForFile ist synchron. Bei haeufigem Tab-Wechsel
  // koennte das User-spuerbaren Lag erzeugen - falls noetig, spaeter
  // mit Debounce-Timer hinterlegen.
  try
    RunSilentAnalysisForFile(AFileName, {ACenterOnFirstFinding=}False);
  except
    // Detector-Crash darf den Tab-Wechsel-Hook nicht reissen.
  end;
end;

procedure TFindingsPropertiesDockableForm.ViewMenuClick(Sender: TObject);
begin
  ShowFindingsPropertiesDockableForm;
end;

// ---- INTACustomDockableForm No-Op-Stubs ----

function TFindingsPropertiesDockableForm.GetMenuActionList: TCustomActionList;
begin Result := nil; end;

function TFindingsPropertiesDockableForm.GetMenuImageList: TCustomImageList;
begin Result := nil; end;

procedure TFindingsPropertiesDockableForm.CustomizePopupMenu(
  PopupMenu: TPopupMenu);
begin end;

function TFindingsPropertiesDockableForm.GetToolBarActionList: TCustomActionList;
begin Result := nil; end;

function TFindingsPropertiesDockableForm.GetToolBarImageList: TCustomImageList;
begin Result := nil; end;

procedure TFindingsPropertiesDockableForm.CustomizeToolBar(ToolBar: TToolBar);
begin end;

procedure TFindingsPropertiesDockableForm.SaveWindowState(Desktop: TCustomIniFile;
  const Section: string; IsProject: Boolean);
// IDE ruft das beim Desktop-Save (Tools > Save Desktop). Wir schreiben
// die aktuelle Host-Form-Geometrie damit der naechste IDE-Restart das
// Layout wiederherstellen kann.
var
  Host: TCustomForm;
begin
  if not Assigned(FFrame) then Exit;
  Host := GetParentForm(FFrame);
  if not Assigned(Host) then Exit;
  Desktop.WriteInteger(Section, 'Left',    Host.Left);
  Desktop.WriteInteger(Section, 'Top',     Host.Top);
  Desktop.WriteInteger(Section, 'Width',   Host.Width);
  Desktop.WriteInteger(Section, 'Height',  Host.Height);
  Desktop.WriteBool   (Section, 'Floating', Host.HostDockSite = nil);
end;

procedure TFindingsPropertiesDockableForm.LoadWindowState(Desktop: TCustomIniFile;
  const Section: string);
// IDE ruft das beim Desktop-Load (auch beim IDE-Start). Zum Zeitpunkt
// existiert noch kein Frame - wir merken uns die Werte und applien sie
// in FrameCreated nachdem HostForm verfuegbar ist.
begin
  FPendingLeft   := Desktop.ReadInteger(Section, 'Left',   -1);
  FPendingTop    := Desktop.ReadInteger(Section, 'Top',    -1);
  FPendingWidth  := Desktop.ReadInteger(Section, 'Width',  -1);
  FPendingHeight := Desktop.ReadInteger(Section, 'Height', -1);
  FHasPendingState := (FPendingWidth > 0) and (FPendingHeight > 0);
end;

class function TFindingsPropertiesDockableForm.IniFilePath: string;
// Pfad zur analyser.ini ueber TRepoSettings.ConfigFilePath. Eine kurz-
// lebige Instanz reicht - die Methode resolved den Pfad rein aus
// %APPDATA% + RegEntries, kein Disk-IO.
var
  Settings: TRepoSettings;
begin
  Settings := TRepoSettings.Create;
  try
    Result := Settings.ConfigFilePath;
  finally
    Settings.Free;
  end;
end;

class function TFindingsPropertiesDockableForm.IsRectOnAnyMonitor(
  L, T, W, H: Integer): Boolean;
// True wenn das Rechteck (mindestens teilweise mit ONSCREEN_MARGIN Reserve)
// auf irgendeinem Monitor liegt. Schuetzt vor "Position auf nicht mehr
// existierendem 2.-Monitor" beim Multi-Monitor-Setup-Wechsel.
var
  i: Integer;
  Mon: TMonitor;
  R: TRect;
begin
  Result := False;
  if (W <= 0) or (H <= 0) then Exit;
  for i := 0 to Screen.MonitorCount - 1 do
  begin
    Mon := Screen.Monitors[i];
    R := Mon.WorkareaRect;
    // Mindestens ein 8x8-Quadrat aus dem Fenster muss in der WorkArea liegen.
    if (L + W > R.Left + ONSCREEN_MARGIN) and (L < R.Right - ONSCREEN_MARGIN) and
       (T + H > R.Top + ONSCREEN_MARGIN) and (T < R.Bottom - ONSCREEN_MARGIN) then
      Exit(True);
  end;
end;

procedure TFindingsPropertiesDockableForm.ReadIniState;
// Session-Persistence-Layer (analyser.ini). Wird beim FrameCreated
// konsultiert, falls die IDE-Desktop-State leer ist (z.B. User hat das
// Form innerhalb der Session geschlossen + reopened ohne Desktop-Save
// dazwischen).
var
  Ini: TMemIniFile;
begin
  if FHasPendingState then Exit;   // Desktop-State hat Vorrang
  if not TFile.Exists(IniFilePath) then Exit;
  Ini := TMemIniFile.Create(IniFilePath);
  try
    FPendingLeft   := Ini.ReadInteger(INI_SECTION, 'Left',   -1);
    FPendingTop    := Ini.ReadInteger(INI_SECTION, 'Top',    -1);
    FPendingWidth  := Ini.ReadInteger(INI_SECTION, 'Width',  -1);
    FPendingHeight := Ini.ReadInteger(INI_SECTION, 'Height', -1);
    FHasPendingState := (FPendingWidth > 0) and (FPendingHeight > 0);
  finally
    Ini.Free;
  end;
end;

procedure TFindingsPropertiesDockableForm.WriteIniState;
// Session-Persistence: vom Frame-OnDestroying-Hook gerufen. Erfasst die
// Geometrie BEVOR der Host-Form weggeht, damit sie beim naechsten Open
// innerhalb der selben IDE-Session restored werden kann.
var
  Host: TCustomForm;
  Ini: TMemIniFile;
begin
  if not Assigned(FFrame) then Exit;
  Host := GetParentForm(FFrame);
  if not Assigned(Host) then Exit;
  // Nur sinnvolle Geometrien persistieren.
  if (Host.Width <= 0) or (Host.Height <= 0) then Exit;
  try
    Ini := TMemIniFile.Create(IniFilePath);
    try
      Ini.WriteInteger(INI_SECTION, 'Left',   Host.Left);
      Ini.WriteInteger(INI_SECTION, 'Top',    Host.Top);
      Ini.WriteInteger(INI_SECTION, 'Width',  Host.Width);
      Ini.WriteInteger(INI_SECTION, 'Height', Host.Height);
      Ini.UpdateFile;
    finally
      Ini.Free;
    end;
  except
    // INI-Schreibfehler nie ans Plugin rauseskalieren.
  end;
end;

procedure TFindingsPropertiesDockableForm.ApplyPendingStateToHost;
// Im FrameCreated gerufen, nachdem das Host-Form existiert. Wenn die
// gespeicherten Werte plausibel und ON-Screen sind, anwenden. Sonst
// Center-on-IDE-Fallback.
var
  Host: TCustomForm;
begin
  if not Assigned(FFrame) then Exit;
  Host := GetParentForm(FFrame);
  if not Assigned(Host) then Exit;

  if FHasPendingState and IsRectOnAnyMonitor(
       FPendingLeft, FPendingTop, FPendingWidth, FPendingHeight) then
  begin
    Host.SetBounds(FPendingLeft, FPendingTop, FPendingWidth, FPendingHeight);
    FHasPendingState := False;   // einmal anwenden
  end
  else
    CenterOnIDEMainWindow;
end;

procedure TFindingsPropertiesDockableForm.CenterOnIDEMainWindow;
// Fallback wenn keine plausible Geometrie verfuegbar ist. Zentriert das
// Host-Form ueber dem IDE-Main-Window (Application.MainForm).
var
  Host: TCustomForm;
  MainBounds: TRect;
begin
  if not Assigned(FFrame) then Exit;
  Host := GetParentForm(FFrame);
  if not Assigned(Host) then Exit;
  if not Assigned(Application.MainForm) then Exit;
  MainBounds := Application.MainForm.BoundsRect;
  Host.Left := MainBounds.Left + (MainBounds.Width  - Host.Width)  div 2;
  Host.Top  := MainBounds.Top  + (MainBounds.Height - Host.Height) div 2;
end;

function TFindingsPropertiesDockableForm.GetEditState: TEditState;
begin Result := []; end;

function TFindingsPropertiesDockableForm.EditAction(
  Action: TEditAction): Boolean;
begin Result := False; end;

{ ---- Register / Show / Unregister ---- }

procedure RegisterFindingsPropertiesDockableForm;
var
  NTASvc   : INTAServices;
  EditSvc  : IOTAEditorServices;
  MainMenu : TMainMenu;
  ViewMenu : TMenuItem;
  Item     : TMenuItem;
  i        : Integer;
begin
  if Assigned(GFindingsPropsForm) then Exit;
  if not Supports(BorlandIDEServices, INTAServices, NTASvc) then Exit;

  GFindingsPropsForm := TFindingsPropertiesDockableForm.Create;
  NTASvc.RegisterDockableForm(GFindingsPropsForm);

  // Editor-Tab-Change-Hook permanent registrieren (Phase 4). EditorView-
  // Activated checked selbst ob ein Frame existiert - no-op solange das
  // Dock-Fenster geschlossen ist.
  if Supports(BorlandIDEServices, IOTAEditorServices, EditSvc) then
    try
      GFindingsPropsEditNotifIfc := TFindingsPropsEditSvcNotifier.Create;
      GFindingsPropsEditNotifIdx := EditSvc.AddNotifier(
        GFindingsPropsEditNotifIfc);
    except
      // Service nicht verfuegbar - Tab-Hook bleibt aus, kein Crash.
      GFindingsPropsEditNotifIdx := -1;
      GFindingsPropsEditNotifIfc := nil;
    end;

  // View > "SCA Findings Properties" Menue-Eintrag (analog zu uIDEAnalyser-
  // Form.RegisterAnalyserDockableForm). Erst View-Menu suchen.
  MainMenu := NTASvc.GetMainMenu;
  ViewMenu := nil;
  if Assigned(MainMenu) then
    for i := 0 to MainMenu.Items.Count - 1 do
      if SameText(MainMenu.Items[i].Name, 'ViewsMenu') or
         SameText(MainMenu.Items[i].Caption, 'Ansicht') or
         SameText(MainMenu.Items[i].Caption, '&Ansicht') or
         SameText(MainMenu.Items[i].Caption, 'View') or
         SameText(MainMenu.Items[i].Caption, '&View') then
      begin
        ViewMenu := MainMenu.Items[i];
        Break;
      end;
  if Assigned(ViewMenu) then
  begin
    Item := TMenuItem.Create(nil);
    Item.Caption := _(CAPTION_DEFAULT);
    Item.OnClick := GFindingsPropsForm.ViewMenuClick;
    ViewMenu.Add(Item);
    GFindingsPropsMenuItem := Item;
  end;
end;

procedure ShowFindingsPropertiesDockableForm;
var
  NTASvc : INTAServices;
begin
  if not Assigned(GFindingsPropsForm) then Exit;
  if not Supports(BorlandIDEServices, INTAServices, NTASvc) then Exit;
  try
    NTASvc.CreateDockableForm(GFindingsPropsForm);
  except
    on E: Exception do
      Application.MessageBox(
        PChar(_(CAPTION_DEFAULT) + ': ' + E.ClassName + #10#13 + E.Message),
        PChar(_('Plugin Open Error')),
        MB_ICONERROR or MB_OK);
  end;
end;

procedure UnregisterFindingsPropertiesDockableForm;
var
  NTASvc  : INTAServices;
  EditSvc : IOTAEditorServices;
begin
  // Menue-Item zuerst entfernen, damit kein dangling Eintrag im IDE-View-
  // Menue bleibt (Klick darauf wuerde nach Unregister crashen).
  if Assigned(GFindingsPropsMenuItem) then
  begin
    if Assigned(GFindingsPropsMenuItem.Parent) then
      GFindingsPropsMenuItem.Parent.Remove(GFindingsPropsMenuItem);
    FreeAndNil(GFindingsPropsMenuItem);
  end;

  // Editor-Notifier zuerst loesen - sonst koennte ein spaeter Aufruf den
  // bereits freigegebenen Wrapper triggern.
  if GFindingsPropsEditNotifIdx <> -1 then
  begin
    try
      if Supports(BorlandIDEServices, IOTAEditorServices, EditSvc) then
        EditSvc.RemoveNotifier(GFindingsPropsEditNotifIdx);
    except
      // EditSvc evtl. schon weg.
    end;
    GFindingsPropsEditNotifIdx := -1;
    GFindingsPropsEditNotifIfc := nil;
  end;

  if not Assigned(GFindingsPropsForm) then Exit;
  if Supports(BorlandIDEServices, INTAServices, NTASvc) then
    try
      NTASvc.UnregisterDockableForm(GFindingsPropsForm);
    except
      // IDE evtl. schon im Teardown
    end;
  GFindingsPropsForm := nil;  // TInterfacedObject-Refcount setzt frei
end;

end.
