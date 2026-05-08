unit uIDEWatchMode;

// !!! RISKY - ENDLOSSCHLEIFE MOEGLICH !!!
// Der Live-Watch kann unter ungluecklichen Umstaenden in eine Schleife
// laufen. Bekannte / vermutete Trigger:
//   * Worker laeuft >1000 ms - User tippt waehrenddessen weiter -
//     EditorViewModified feuert wieder - sofort nach DebounceFire wird
//     der naechste Worker gespawned. Bei sehr grossen Dateien oder
//     langsamen Maschinen kann der Backlog wachsen statt schrumpfen.
//   * Analyzer/Findings-Update triggert Editor-Repaint - falls die IDE
//     das als Modify interpretiert (Delphi-version-abhaengig), feuert
//     EditorViewModified ohne dass der User getippt hat.
//   * IOTAModuleNotifier.Modified hat in manchen Delphi-Versionen
//     unklares Fire-Timing (vor/nach AfterSave) - in Kombination mit
//     dem Save-Debounce-Reset koennen sich Edit- und Save-Pfad
//     gegenseitig unbegrenzt nachtriggern.
// Schutz heute: Generation-Counter dropt _spaete_ Worker-Ergebnisse,
// verhindert aber keinen ueberlappenden Spawn. Vor dem Default-On-
// Schalten unbedingt:
//   - Re-Entrancy-Guard (kein Spawn solange Worker laeuft)
//   - Hard-Cap (z.B. max 1 Spawn / 5s)
//   - oder echten Cancel-Token (TODO.md: "WatchMode echtes Cancel-Token")
// Fuer den manuellen "Aktuelle Datei"-Klick akzeptabel - der User
// schaltet den Watch bewusst an und kann ihn durch Bulk-Run abschalten.
//
// Single-File-Live-Watch: scant DIE EINE Datei, fuer die der User gerade
// "Aktuelle Datei" geklickt hat, automatisch bei jedem Save / Edit.
//
// Aktivierung ist NICHT konfigurierbar - kein INI-Flag. Der "Aktuelle
// Datei"-Pfad ruft Manager.Activate(...) mit dem Dateipfad; Bulk-Pfade
// (Full-Project, Branch-Changes) deaktivieren explizit. Tab-Wechsel auf
// eine andere Datei aendert NICHTS am Watched-File - der User muss
// erneut "Aktuelle Datei" klicken um die Beobachtung umzuhaengen.
//
// Trigger-Pfade (beide gegen FWatchedFile gegated):
//   * Save (AfterSave-Hook)        - debounced 300 ms
//   * Edit (EditorViewModified +
//           IOTAModuleNotifier.Modified, defense in depth) - 1000 ms
//
// Architektur:
//
//   TFindingModuleNotifier   - genau einer, attached an FWatchedFile.
//                              Implementiert IOTAModuleNotifier;
//                              AfterSave triggert Save-Pfad, Modified
//                              triggert Edit-Pfad. Bei Re-Activate auf
//                              andere Datei: detached + neu attached.
//   TFindingEditSvcNotifier  - INTAEditServicesNotifier. Liefert
//                              EditorViewModified als zuverlaessigen
//                              Per-Edit-Hook (IOTAModuleNotifier.Modified
//                              ist Delphi-version-abhaengig flaky).
//                              EditorViewActivated ist No-op - kein
//                              Auto-Attach an andere Dateien.
//   TWatchAnalyzer (TThread) - laeuft die Detektoren auf Background-Thread.
//                             Synchronisiert das Ergebnis zurueck zur UI
//                             via TThread.Synchronize. Die schwere Arbeit
//                             (Lexer + Parser + 21 Detektoren) blockiert
//                             damit nicht die IDE.
//   TWatchModeManager        - Singleton (GWatchMode). Single-Slot fuer
//                              den Watched-Module-Notifier, Debounce-
//                              Timer (300 ms Save, 1000 ms Edit),
//                              Generation-Counter (laete Worker-Ergebnisse
//                              droppen wenn manuelle Analyse zwischen-
//                              zeitlich gestartet wurde), Lock fuer
//                              globale Detector-State (LeakyClasses etc.).
//
// Lifecycle:
//   * RegisterWatchMode: erzeugt Manager (no-op fuer ToolsAPI; Notifier
//     wird erst beim Activate aus PrepareAnalysis heraus angehaengt -
//     analog zur uIDELineHighlighter-Strategie, kein Plugin-Install-Risk).
//   * Manager.Activate(...AWatchedFile): findet das IOTAModule zu
//     AWatchedFile und haengt EINEN TFindingModuleNotifier dran.
//     Bei Re-Activate auf andere Datei: Detach + Re-Attach.
//   * Manager.Deactivate: RemoveNotifier; Generation wird inkrementiert
//     sodass laufende Worker ihre Ergebnisse droppen.
//   * UnregisterWatchMode: Deactivate + Free.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.SyncObjs, Vcl.ExtCtrls, ToolsAPI, DeskUtil, DockForm,
  uMethodd12, uSCAConsts;

type
  // Wird vom Manager gerufen wenn ein Worker fertig ist. Frame muss seine
  // Findings-Liste fuer DiesesFile ersetzen (MergeFindingsForFile).
  TWatchFindingsCallback = procedure(const FileName: string;
    Findings: TObjectList<TLeakFinding>) of object;

  // Statusbar-Update wenn Watch-Mode aktiv/inaktiv oder ein Worker laeuft.
  TWatchStatusCallback = procedure(const Status: string) of object;

  // Per-Modul Notifier. AfterSave delegiert an Manager.
  //
  // KRITISCH: Klasse muss ALLE drei IOTAModuleNotifier-Versionen
  // explizit listen + implementieren. Der IDE-Kern (coreide290.bpl)
  // QueryInterface't beim Save den neusten verfuegbaren Interface-Typ
  // (90 in Delphi 12). Wenn wir nur die Base-Interface listen, schlaegt
  // QueryInterface fehl, der IDE-Kern dereferenziert einen NULL-Pointer
  // -> AV in EdScript.TOTAEditView.BeginPaint waehrend Save-Repaint.
  // Pattern: BADI.ModuleNotifier.pas (geprueft Delphi 12 kompatibel).
  TFindingModuleNotifier = class(TNotifierObject, IInterface,
    IOTANotifier, IOTAModuleNotifier80, IOTAModuleNotifier90,
    IOTAModuleNotifier)
  private
    FFileName : string;
  protected
    // IOTANotifier
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
    // IOTAModuleNotifier
    function CheckOverwrite: Boolean;
    procedure ModuleRenamed(const NewName: string); overload;
    // IOTAModuleNotifier80
    function AllowSave: Boolean;
    function GetOverwriteFileNameCount: Integer;
    function GetOverwriteFileName(Index: Integer): string;
    procedure SetSaveFileName(const FileName: string);
    // IOTAModuleNotifier90
    procedure BeforeRename(const OldFileName, NewFileName: string);
    procedure AfterRename(const OldFileName, NewFileName: string);
  public
    constructor Create(const AFileName: string);
  end;

  TWatchModeManager = class
  private
    FActive             : Boolean;
    // Single-File-Watch: nur DIESE Datei wird beobachtet. Andere offene
    // Dateien werden NICHT mit-analysiert (auch wenn ihre Saves/Edits in
    // der IDE feuern). Wechsel des Watched-File geht nur ueber neuen
    // Activate-Aufruf.
    FWatchedFile        : string;
    // Generation: bei jeder Activate/Deactivate-Sequence und bei manueller
    // Analyse incrementiert. Worker captures bei Spawn; vor Synchronize
    // wird verglichen - mismatch => Result droppen.
    FGeneration         : Integer;
    // Genau ein Notifier-Slot fuer FWatchedFile. Bei Activate auf eine
    // andere Datei: Detach + Re-Attach.
    FAttachedModule     : IOTAModule;            // strong ref
    FAttachedNotifier   : IOTAModuleNotifier;    // strong ref
    FAttachedNotifIdx   : Integer;
    // Save-Debounce-Timer: bei rascher Save-Folge nur letzten Stand analysieren.
    FDebounceTimer      : TTimer;
    FPendingFileName    : string;
    // Edit-Debounce-Timer (laenger): Modified-/EditorViewModified-Hook
    // feuert pro Tastenanschlag.
    FEditDebounceTimer  : TTimer;
    FEditPendingFileName: string;
    // INTAEditServicesNotifier: liefert EditorViewModified als zuverlaessigen
    // Per-Edit-Hook (IOTAModuleNotifier.Modified ist Delphi-version-abhaengig
    // unzuverlaessig). Gegated gegen FWatchedFile - andere Dateien ignoriert.
    FEditSvcNotifierIdx : Integer;
    FEditSvcNotifierIfc : INTAEditServicesNotifier;
    // Mutex serialisiert globale Detector-State-Zugriffe (LeakyClasses,
    // AutoDiscoverCustomClasses ...) zwischen UI-Thread (manuelle Analyse)
    // und Background-Thread (Watch-Worker).
    FAnalyzeLock        : TCriticalSection;
    FOnFindings         : TWatchFindingsCallback;
    FOnStatus           : TWatchStatusCallback;
    procedure DebounceFire(Sender: TObject);
    procedure EditDebounceFire(Sender: TObject);
    procedure SpawnAnalyzer(const AFileName: string);
    procedure DoStatus(const S: string);
    function  AttachToWatchedFile(const AFileName: string): Boolean;
    procedure DetachWatched;
    procedure RegisterEditServicesNotifier;
    procedure UnregisterEditServicesNotifier;
    // Normalisiert Pfade fuer SameText-Vergleiche: Pfade kommen aus
    // verschiedenen Quellen (IOTAModuleNotifier-Konstruktor vs.
    // EditView.Buffer.FileName) und koennen sich in Slash-Richtung und
    // Whitespace unterscheiden. Case ist auf Windows egal (SameText), aber
    // '/' vs '\' nicht.
    class function NormalizePath(const APath: string): string; static;
  public
    constructor Create;
    destructor Destroy; override;

    // Vom Frame im "Aktuelle Datei"-Pfad gerufen. Aktiviert Live-Watch
    // ausschliesslich auf AWatchedFile (Save+Edit, je 300/1000 ms debounced).
    // Bei erneutem Aufruf mit anderem AWatchedFile: alter Notifier wird
    // detached, neuer attached.
    procedure Activate(OnFindings: TWatchFindingsCallback;
      OnStatus: TWatchStatusCallback;
      const AWatchedFile: string);
    procedure Deactivate;

    // Read-only fuer EditorViewModified-Gate (Hook prueft ob die aktive
    // View zum Watched-File gehoert).
    property WatchedFile: string read FWatchedFile;

    // Wird vom Frame gerufen direkt vor einer manuellen Analyse, damit
    // laufende Worker ihre Ergebnisse droppen (sonst wuerden sie die
    // gerade geschriebenen FAllFindings ueberschreiben).
    procedure BumpGeneration;

    // Vom ModuleNotifier bzw. EditServicesNotifier gerufen.
    procedure NotifyFileSaved(const AFileName: string);
    procedure NotifyFileEdited(const AFileName: string);

    // Vom Worker (via Synchronize) gerufen um zu pruefen ob das Ergebnis
    // noch aktuell ist (d.h. Generation hat sich nicht geaendert).
    function IsCurrentGeneration(AGen: Integer): Boolean;
    function CurrentGeneration: Integer;

    // Wird vom Worker (Background) UM den Detector-Lauf herum genutzt um
    // den Detector-State exklusiv zu serialisieren.
    procedure AcquireAnalyzeLock;
    procedure ReleaseAnalyzeLock;

    property Active: Boolean read FActive;
  end;

var
  GWatchMode: TWatchModeManager = nil;

procedure RegisterWatchMode;
procedure UnregisterWatchMode;

implementation

uses
  System.StrUtils, Vcl.Forms, uStaticAnalyzer2, uLocalization;

const
  DEBOUNCE_MS      = 300;   // Save-Trigger: schnelle Reaktion erwuenscht
  EDIT_DEBOUNCE_MS = 1000;  // Edit-Trigger: jeden Tastenanschlag debouncen,
                            // 1000ms Pause schont CPU bei normalem Tippen

type
  // INTAEditServicesNotifier: liefert ein Set von IDE-Editor-Hooks, von
  // denen wir ausschliesslich EditorViewActivated brauchen - damit bekommen
  // wir mit wenn der User eine Datei in den Editor zieht, die NACH unserer
  // Activate-Phase geoeffnet wurde. Ohne diesen Pfad kriegt eine
  // nachtraeglich geoeffnete Datei keinen IOTAModuleNotifier - ihre Saves
  // / Edits triggern keine Live-Analyse.
  //
  // Auf-/Abmeldung lifecycle-mirror zu uIDELineHighlighter:
  // TNotifierObject als Basis, NUR INTAIDEEditServicesNotifier als
  // Interface - kein zusaetzliches IOTANotifier (sonst doppelte vtables).
  TFindingEditSvcNotifier = class(TNotifierObject, INTAEditServicesNotifier)
  protected
    // INTAEditServicesNotifier
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

  // Background-Thread: laed die Datei, parsed, fuehrt 21 Detektoren aus,
  // synchronized das Ergebnis zurueck zum Frame-Callback.
  TWatchAnalyzer = class(TThread)
  private
    FFileName     : string;
    FUsesCheck    : Boolean;
    FStartGen     : Integer;
    FResults      : TObjectList<TLeakFinding>;
    procedure DeliverResults;
  protected
    procedure Execute; override;
  public
    constructor Create(const AFileName: string; AUsesCheck: Boolean;
      AStartGen: Integer);
  end;

{ ---- TFindingModuleNotifier ---- }

constructor TFindingModuleNotifier.Create(const AFileName: string);
begin
  inherited Create;
  // Pfad einmal beim Speichern normalisieren - dann matchen spaetere
  // SameText-Vergleiche im Manager unabhaengig von der Quelle (Konstruktor
  // bekommt ihn aus IOTAModule.FileName, Notify-Pfad aus EditView.Buffer).
  FFileName := TWatchModeManager.NormalizePath(AFileName);
end;

procedure TFindingModuleNotifier.AfterSave;
begin
  // Save fertig - Manager bittet um Re-Analyse (mit Debounce).
  if Assigned(GWatchMode) then
    GWatchMode.NotifyFileSaved(FFileName);
end;

procedure TFindingModuleNotifier.BeforeSave;       begin end;
procedure TFindingModuleNotifier.Destroyed;        begin end;

procedure TFindingModuleNotifier.Modified;
// Wird bei jeder Aenderung der Editor-Inhalte vom IDE gerufen. Notifier
// haengt nur an FWatchedFile (Single-File-Watch) - kein zusaetzlicher
// Gate noetig, der Manager filtert ohnehin gegen FWatchedFile.
begin
  if Assigned(GWatchMode) then
    GWatchMode.NotifyFileEdited(FFileName);
end;
procedure TFindingModuleNotifier.ModuleRenamed(const NewName: string);
begin
  FFileName := TWatchModeManager.NormalizePath(NewName);
end;

function TFindingModuleNotifier.CheckOverwrite: Boolean;
begin
  Result := True;
end;

// IOTAModuleNotifier80 - keine eigene Logik noetig, Defaults zurueckgeben
function TFindingModuleNotifier.AllowSave: Boolean;
begin Result := True; end;

function TFindingModuleNotifier.GetOverwriteFileNameCount: Integer;
begin Result := 0; end;

function TFindingModuleNotifier.GetOverwriteFileName(Index: Integer): string;
begin Result := ''; end;

procedure TFindingModuleNotifier.SetSaveFileName(const FileName: string);
begin end;

// IOTAModuleNotifier90 - Rename-Hook. Wir tracken nur den Filename, damit
// AfterSave auch nach Rename den richtigen Pfad meldet.
procedure TFindingModuleNotifier.BeforeRename(
  const OldFileName, NewFileName: string);
begin end;

procedure TFindingModuleNotifier.AfterRename(
  const OldFileName, NewFileName: string);
begin
  FFileName := TWatchModeManager.NormalizePath(NewFileName);
end;

{ ---- TFindingEditSvcNotifier ---- }

procedure TFindingEditSvcNotifier.EditorViewActivated(
  const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
// No-op im Single-File-Watch-Modus: Tab-Wechsel auf andere Dateien
// triggert KEINE Analyse - die andere Datei wird nicht beobachtet.
// Erst ein erneuter "Aktuelle Datei"-Klick wechselt das Watched-File.
begin end;

procedure TFindingEditSvcNotifier.EditorViewModified(
  const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
// Per-Edit-Hook. Feuert fuer JEDE editierte View - wir filtern auf
// FWatchedFile, damit Edits an anderen offenen Dateien ignoriert werden.
// IOTAModuleNotifier.Modified ist Delphi-version-abhaengig unzuverlaessig
// (manchmal pro Tastenanschlag, manchmal nur Clean->Dirty); diese Quelle
// hier feuert garantiert pro Edit.
var
  FileName : string;
begin
  if not Assigned(GWatchMode) then Exit;
  if not GWatchMode.Active then Exit;
  if not Assigned(EditView) or not Assigned(EditView.Buffer) then Exit;
  FileName := EditView.Buffer.FileName;
  if FileName = '' then Exit;
  GWatchMode.NotifyFileEdited(FileName);
end;

procedure TFindingEditSvcNotifier.WindowShow(const EditWindow: INTAEditWindow;
  Show, LoadedFromDesktop: Boolean);                        begin end;
procedure TFindingEditSvcNotifier.WindowNotification(
  const EditWindow: INTAEditWindow; Operation: TOperation); begin end;
procedure TFindingEditSvcNotifier.WindowActivated(
  const EditWindow: INTAEditWindow);                        begin end;
procedure TFindingEditSvcNotifier.WindowCommand(
  const EditWindow: INTAEditWindow; Command, Param: Integer;
  var Handled: Boolean);                                    begin end;
procedure TFindingEditSvcNotifier.DockFormVisibleChanged(
  const EditWindow: INTAEditWindow; DockForm: TDockableForm); begin end;
procedure TFindingEditSvcNotifier.DockFormUpdated(
  const EditWindow: INTAEditWindow; DockForm: TDockableForm); begin end;
procedure TFindingEditSvcNotifier.DockFormRefresh(
  const EditWindow: INTAEditWindow; DockForm: TDockableForm); begin end;

{ ---- TWatchAnalyzer ---- }

constructor TWatchAnalyzer.Create(const AFileName: string; AUsesCheck: Boolean;
  AStartGen: Integer);
begin
  inherited Create(False); // CreateSuspended=False -> sofort starten
  FreeOnTerminate := True;
  FFileName  := AFileName;
  FUsesCheck := AUsesCheck;
  FStartGen  := AStartGen;
end;

procedure TWatchAnalyzer.Execute;
begin
  FResults := nil;
  try
    try
      // Globale Detector-Variablen koennen waehrend manueller Analyse
      // umgeschrieben werden -> Lock vorm Detector-Lauf.
      if Assigned(GWatchMode) then
        GWatchMode.AcquireAnalyzeLock;
      try
        FResults := TStaticAnalyzer2.AnalyzeLeaks(FFileName, FUsesCheck);
      finally
        if Assigned(GWatchMode) then
          GWatchMode.ReleaseAnalyzeLock;
      end;
    except
      // Detector-Crash darf das Plugin nicht reissen. Liste leer lassen
      // damit DeliverResults sauber durchlaeuft.
      FreeAndNil(FResults);
      FResults := TObjectList<TLeakFinding>.Create(True);
    end;

    // Ergebnis muss auf dem UI-Thread an den Frame.
    Synchronize(DeliverResults);
  finally
    // Wenn DeliverResults die Liste nicht uebernommen hat, hier freigeben.
    if Assigned(FResults) then
      FreeAndNil(FResults);
  end;
end;

procedure TWatchAnalyzer.DeliverResults;
// Auf UI-Thread. Pruefen ob unser Ergebnis noch aktuell ist (Manager
// koennte zwischenzeitlich Generation gebumpt haben - z.B. weil
// manuelle Analyse die Liste ohnehin neu fuellt).
var
  Local : TObjectList<TLeakFinding>;
begin
  if not Assigned(GWatchMode) then Exit;
  if not GWatchMode.IsCurrentGeneration(FStartGen) then Exit;
  if not Assigned(GWatchMode.FOnFindings) then Exit;

  // ALLERERSTES: Field-Ref auf nil bevor wir die Liste an den Callback
  // weiterreichen. Falls Synchronize mid-Callback eine Exception wirft
  // (Thread-Terminate o.ae.), sieht der Worker-finally FResults=nil und
  // gibt nicht doppelt frei. Der Callback uebernimmt die Liste via
  // Local-Snapshot - er ist verantwortlich fuer Free / Re-Parenting.
  Local := FResults;
  FResults := nil;

  // Ownership: callback uebernimmt die Liste (sezt OwnsObjects:=False
  // und freed sie nach dem Reinkopieren in Frame.FAllFindings).
  GWatchMode.FOnFindings(FFileName, Local);
end;

{ ---- TWatchModeManager ---- }

constructor TWatchModeManager.Create;
begin
  inherited;
  FActive             := False;
  FGeneration         := 0;
  FAttachedNotifIdx   := -1;
  FAnalyzeLock        := TCriticalSection.Create;
  FEditSvcNotifierIdx := -1;

  FDebounceTimer := TTimer.Create(nil);
  FDebounceTimer.Enabled  := False;
  FDebounceTimer.Interval := DEBOUNCE_MS;
  FDebounceTimer.OnTimer  := DebounceFire;

  FEditDebounceTimer := TTimer.Create(nil);
  FEditDebounceTimer.Enabled  := False;
  FEditDebounceTimer.Interval := EDIT_DEBOUNCE_MS;
  FEditDebounceTimer.OnTimer  := EditDebounceFire;
end;

destructor TWatchModeManager.Destroy;
begin
  Deactivate;
  FreeAndNil(FEditDebounceTimer);
  FreeAndNil(FDebounceTimer);
  FreeAndNil(FAnalyzeLock);
  inherited;
end;

procedure TWatchModeManager.Activate(OnFindings: TWatchFindingsCallback;
  OnStatus: TWatchStatusCallback; const AWatchedFile: string);
var
  NewWatched: string;
begin
  NewWatched := NormalizePath(AWatchedFile);

  // Callbacks IMMER updaten - auch bei Re-Activate mit gleichem File. Sonst
  // bleiben bei Frame-Re-Init alte Callbacks auf einem bereits zerstoerten
  // Frame haengen und der Worker liefert Ergebnisse ins Leere (oder schlimmer:
  // an einen frisch belegten Speicherbereich).
  FOnFindings := OnFindings;
  FOnStatus   := OnStatus;

  if NewWatched = '' then Exit;

  // Re-Activate auf gleiches File: nichts zu tun, Notifier haengt schon.
  if FActive and SameText(FWatchedFile, NewWatched) then Exit;

  // Re-Activate auf ANDERES File: alten Notifier abmelden, pending Trigger
  // verwerfen (sonst feuert noch ein Worker fuer das alte File).
  if FActive then
  begin
    DetachWatched;
    FPendingFileName := '';
    FEditPendingFileName := '';
    FDebounceTimer.Enabled := False;
    FEditDebounceTimer.Enabled := False;
  end;

  FActive       := True;
  FWatchedFile  := NewWatched;
  Inc(FGeneration);

  if not AttachToWatchedFile(NewWatched) then
  begin
    DoStatus(Format(_('Watch: could not attach to %s'),
      [ExtractFileName(NewWatched)]));
    FActive := False;
    FWatchedFile := '';
    Exit;
  end;

  // EditServicesNotifier liefert den zuverlaessigen Per-Edit-Hook
  // (EditorViewModified). Immer registriert wenn aktiv.
  RegisterEditServicesNotifier;

  DoStatus(Format(_('Watching: %s'), [ExtractFileName(NewWatched)]));
end;

procedure TWatchModeManager.Deactivate;
begin
  if not FActive then Exit;
  FActive := False;
  Inc(FGeneration); // alle laufenden Worker invalidieren
  FDebounceTimer.Enabled     := False;
  FEditDebounceTimer.Enabled := False;
  FPendingFileName     := '';
  FEditPendingFileName := '';
  UnregisterEditServicesNotifier;
  DetachWatched;
  FWatchedFile := '';
  DoStatus('');
  FOnFindings := nil;
  FOnStatus   := nil;
end;

procedure TWatchModeManager.BumpGeneration;
begin
  Inc(FGeneration);
end;

function TWatchModeManager.CurrentGeneration: Integer;
begin
  Result := FGeneration;
end;

function TWatchModeManager.IsCurrentGeneration(AGen: Integer): Boolean;
begin
  Result := FActive and (FGeneration = AGen);
end;

procedure TWatchModeManager.AcquireAnalyzeLock;
begin
  if Assigned(FAnalyzeLock) then FAnalyzeLock.Acquire;
end;

procedure TWatchModeManager.ReleaseAnalyzeLock;
begin
  if Assigned(FAnalyzeLock) then FAnalyzeLock.Release;
end;

class function TWatchModeManager.NormalizePath(const APath: string): string;
begin
  // Slashes vereinheitlichen + trimmen. Case-Vergleich macht spaeter SameText.
  Result := StringReplace(APath, '/', '\', [rfReplaceAll]).Trim;
end;

procedure TWatchModeManager.NotifyFileSaved(const AFileName: string);
// Wird auf UI-Thread aus AfterSave gerufen. Debounce fuer den Fall dass
// Save mehrfach hintereinander feuert (z.B. Save-on-Build).
var
  Norm: string;
begin
  if not FActive then Exit;
  if AFileName = '' then Exit;
  Norm := NormalizePath(AFileName);
  // Single-File-Watch: nur das beobachtete File triggert.
  if not SameText(Norm, FWatchedFile) then Exit;

  // Save hat Vorrang ueber Edit-Pending: wenn fuer dieselbe Datei bereits
  // ein Edit-Trigger pending ist, verwerfen wir den - sonst feuert 700 ms
  // nach dem Save eine zweite redundante Analyse.
  FEditPendingFileName := '';
  FEditDebounceTimer.Enabled := False;

  FPendingFileName := Norm;
  FDebounceTimer.Enabled := False; // Reset
  FDebounceTimer.Enabled := True;  // 300 ms warten dann feuern
  DoStatus(Format(_('Saved, queueing analysis: %s'), [ExtractFileName(Norm)]));
end;

procedure TWatchModeManager.NotifyFileEdited(const AFileName: string);
// Wird aus Modified-Hook bzw. EditorViewModified gerufen (per Edit).
// Edit-Debounce ist 1000 ms - schont CPU bei normalem Tippen.
var
  Norm: string;
begin
  if not FActive then Exit;
  if AFileName = '' then Exit;
  Norm := NormalizePath(AFileName);
  // Single-File-Watch: nur das beobachtete File triggert.
  if not SameText(Norm, FWatchedFile) then Exit;

  // Wenn fuer dieselbe Datei bereits ein Save-Trigger pending ist, kein
  // separater Edit-Trigger noetig - der Save-Pfad analysiert sowieso in
  // <=300 ms.
  if SameText(FPendingFileName, Norm) then Exit;

  FEditPendingFileName := Norm;
  FEditDebounceTimer.Enabled := False; // Reset bei jedem Tastenanschlag
  FEditDebounceTimer.Enabled := True;
  // KEIN DoStatus pro Tastenanschlag - die Statusbar wuerde flackern.
  // Status kommt erst beim DebounceFire.
end;

procedure TWatchModeManager.DebounceFire(Sender: TObject);
begin
  FDebounceTimer.Enabled := False;
  if not FActive then Exit;
  if FPendingFileName = '' then Exit;
  SpawnAnalyzer(FPendingFileName);
  FPendingFileName := '';
end;

procedure TWatchModeManager.EditDebounceFire(Sender: TObject);
begin
  FEditDebounceTimer.Enabled := False;
  if not FActive then Exit;
  if FEditPendingFileName = '' then Exit;
  SpawnAnalyzer(FEditPendingFileName);
  FEditPendingFileName := '';
end;

procedure TWatchModeManager.RegisterEditServicesNotifier;
var
  EditSvc : IOTAEditorServices;
begin
  if FEditSvcNotifierIdx <> -1 then Exit; // bereits registriert
  if not Supports(BorlandIDEServices, IOTAEditorServices, EditSvc) then Exit;
  try
    // TFindingEditSvcNotifier erbt von TNotifierObject - Refcount aktiv.
    // Direkt auf Interface-Variable speichern; Cast nicht noetig, da die
    // Klasse INTAEditServicesNotifier in ihrer Deklaration listet.
    FEditSvcNotifierIfc := TFindingEditSvcNotifier.Create;
    FEditSvcNotifierIdx := EditSvc.AddNotifier(FEditSvcNotifierIfc);
  except
    // Service evtl. nicht verfuegbar - Edit-Trigger bleibt aus, kein Crash.
    FEditSvcNotifierIdx := -1;
    FEditSvcNotifierIfc := nil;
  end;
end;

procedure TWatchModeManager.UnregisterEditServicesNotifier;
var
  EditSvc : IOTAEditorServices;
begin
  if FEditSvcNotifierIdx = -1 then Exit;
  try
    if Supports(BorlandIDEServices, IOTAEditorServices, EditSvc) then
      EditSvc.RemoveNotifier(FEditSvcNotifierIdx);
  except
    // EditSvc evtl. schon weg.
  end;
  FEditSvcNotifierIdx := -1;
  FEditSvcNotifierIfc := nil;
end;

procedure TWatchModeManager.SpawnAnalyzer(const AFileName: string);
var
  UsesCheck: Boolean;
begin
  if not FileExists(AFileName) then Exit;
  // UsesCheck-Flag aus globalem State lesen (wurde von ApplyDetectorThresholds
  // / RegisterToLeakyClasses gesetzt). Wir koennten auch FRepoSettings.UsesCheck
  // lesen, aber das wuerde uns an die Frame-Lifetime koppeln.
  UsesCheck := False; // V1: konservativer Default. Worker schaltet UsesCheck
                      // explizit aus, damit der Live-Pfad immer schnell bleibt.

  DoStatus(Format(_('Analysing: %s'), [ExtractFileName(AFileName)]));
  TWatchAnalyzer.Create(AFileName, UsesCheck, FGeneration);
end;

procedure TWatchModeManager.DoStatus(const S: string);
begin
  if Assigned(FOnStatus) then
    try FOnStatus(S); except end;
end;

function TWatchModeManager.AttachToWatchedFile(
  const AFileName: string): Boolean;
// Sucht das IOTAModule zu AFileName und haengt einen TFindingModuleNotifier
// dran. Liefert False wenn die Datei nicht offen ist oder kein Source-
// Editor existiert (z.B. .dfm-only).
var
  ModSvc : IOTAModuleServices;
  i      : Integer;
  M      : IOTAModule;
  SE     : IOTASourceEditor;
  Notif  : IOTAModuleNotifier;

  function FindSourceEditor: IOTASourceEditor;
  var j: Integer;
  begin
    Result := nil;
    for j := 0 to M.ModuleFileCount - 1 do
      if Supports(M.ModuleFileEditors[j], IOTASourceEditor, Result) then
        Exit;
  end;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then Exit;
  for i := 0 to ModSvc.ModuleCount - 1 do
  begin
    M := ModSvc.Modules[i];
    if not Assigned(M) then Continue;
    SE := FindSourceEditor;
    if not Assigned(SE) then Continue; // kein Source-Editor (DFM only o.ae.)
    if not SameText(NormalizePath(SE.FileName), AFileName) then Continue;
    try
      Notif := TFindingModuleNotifier.Create(SE.FileName);
      FAttachedNotifIdx := M.AddNotifier(Notif);
      FAttachedModule   := M;
      FAttachedNotifier := Notif;
      Exit(True);
    except
      // Defensive: AddNotifier-Fehler -> Watch ist effektiv aus.
      Exit(False);
    end;
  end;
end;

procedure TWatchModeManager.DetachWatched;
begin
  if Assigned(FAttachedModule) and (FAttachedNotifIdx <> -1) then
  begin
    try
      FAttachedModule.RemoveNotifier(FAttachedNotifIdx);
    except
      // Modul evtl. schon zerstoert.
    end;
  end;
  FAttachedNotifIdx := -1;
  FAttachedNotifier := nil; // dropt Ref, Notifier-Objekt wird frei
  FAttachedModule   := nil;
end;

{ ---- Public Register/Unregister ---- }

procedure RegisterWatchMode;
begin
  if Assigned(GWatchMode) then Exit;
  GWatchMode := TWatchModeManager.Create;
end;

procedure UnregisterWatchMode;
begin
  if Assigned(GWatchMode) then
    FreeAndNil(GWatchMode);
end;

end.
