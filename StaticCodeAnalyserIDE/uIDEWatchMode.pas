unit uIDEWatchMode;

// Watch-Mode: Live-Analyse beim Speichern. Wenn aktiviert
// (analyser.ini [Detectors] WatchMode=1), wird beim 'Strg+S' in der IDE
// automatisch genau die geaenderte Datei re-analysiert, ohne dass der
// User auf "Aktuelle Datei" klicken muss.
//
// Architektur:
//
//   TFindingModuleNotifier  - pro geoeffnetem Modul einer. Implementiert
//                             IOTAModuleNotifier; AfterSave-Hook ruft den
//                             Manager.
//   TWatchAnalyzer (TThread) - laeuft die Detektoren auf Background-Thread.
//                             Synchronisiert das Ergebnis zurueck zur UI
//                             via TThread.Synchronize. Die schwere Arbeit
//                             (Lexer + Parser + 21 Detektoren) blockiert
//                             damit nicht die IDE.
//   TWatchModeManager       - Singleton (GWatchMode). Track der attachen
//                             Module-Notifier, Debounce-Timer (300 ms),
//                             Generation-Counter (laete Worker-Ergebnisse
//                             droppen wenn manuelle Analyse zwischenzeitlich
//                             gestartet wurde), Lock fuer globale Detector-
//                             State (LeakyClasses etc.).
//
// Lifecycle:
//   * RegisterWatchMode: erzeugt Manager (no-op fuer ToolsAPI; Notifier
//     werden erst beim Activate aus PrepareAnalysis heraus angehaengt -
//     analog zur uIDELineHighlighter-Strategie, kein Plugin-Install-Risk).
//   * Manager.Activate(Frame): iteriert IOTAModuleServices.Modules und
//     attached pro Source-Module einen TFindingModuleNotifier.
//   * Manager.Deactivate: iteriert die Notifier und ruft RemoveNotifier;
//     Generation wird inkrementiert sodass laufende Worker ihre Ergebnisse
//     droppen.
//   * UnregisterWatchMode: Deactivate + Free.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.SyncObjs, Vcl.ExtCtrls, ToolsAPI,
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
    // Generation: bei jeder Activate/Deactivate-Sequence und bei manueller
    // Analyse incrementiert. Worker captures bei Spawn; vor Synchronize
    // wird verglichen - mismatch => Result droppen.
    FGeneration         : Integer;
    // Tracking der pro-Modul-Notifier (analog zu uIDELineHighlighter).
    FAttachedModules    : TList<IOTAModule>;            // strong refs
    FAttachedNotifiers  : TList<IOTAModuleNotifier>;    // strong refs
    FAttachedNotifIdxs  : TList<Integer>;                // RemoveNotifier-Indices
    // Debounce-Timer: bei rascher Save-Folge nur den letzten Stand analysieren.
    FDebounceTimer      : TTimer;
    FPendingFileName    : string;
    // Mutex serialisiert globale Detector-State-Zugriffe (LeakyClasses,
    // AutoDiscoverCustomClasses ...) zwischen UI-Thread (manuelle Analyse)
    // und Background-Thread (Watch-Worker).
    FAnalyzeLock        : TCriticalSection;
    FOnFindings         : TWatchFindingsCallback;
    FOnStatus           : TWatchStatusCallback;
    procedure DebounceFire(Sender: TObject);
    procedure SpawnAnalyzer(const AFileName: string);
    procedure DoStatus(const S: string);
    procedure AttachToOpenModules;
    procedure DetachAll;
  public
    constructor Create;
    destructor Destroy; override;

    // Vom Frame in PrepareAnalysis gerufen wenn INI [Detectors] WatchMode=1
    // ist. Aktiviert das Live-Tracking und liefert die UI-Callbacks.
    procedure Activate(OnFindings: TWatchFindingsCallback;
      OnStatus: TWatchStatusCallback);
    procedure Deactivate;

    // Wird vom Frame gerufen direkt vor einer manuellen Analyse, damit
    // laufende Worker ihre Ergebnisse droppen (sonst wuerden sie die
    // gerade geschriebenen FAllFindings ueberschreiben).
    procedure BumpGeneration;

    // Wird vom Frame gerufen nach Plugin-Init wenn WatchMode-INI=1, um
    // den TFindingModuleNotifier auf bereits offene Module zu legen.
    procedure RescanOpenModules;

    // Vom ModuleNotifier gerufen.
    procedure NotifyFileSaved(const AFileName: string);

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
  Vcl.Forms, uStaticAnalyzer2;

const
  DEBOUNCE_MS = 300;

type
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
  FFileName := AFileName;
end;

procedure TFindingModuleNotifier.AfterSave;
begin
  // Save fertig - Manager bittet um Re-Analyse (mit Debounce).
  if Assigned(GWatchMode) then
    GWatchMode.NotifyFileSaved(FFileName);
end;

procedure TFindingModuleNotifier.BeforeSave;       begin end;
procedure TFindingModuleNotifier.Destroyed;        begin end;
procedure TFindingModuleNotifier.Modified;         begin end;
procedure TFindingModuleNotifier.ModuleRenamed(const NewName: string);
begin
  FFileName := NewName;
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
  FFileName := NewFileName;
end;

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
  FActive            := False;
  FGeneration        := 0;
  FAttachedModules   := TList<IOTAModule>.Create;
  FAttachedNotifiers := TList<IOTAModuleNotifier>.Create;
  FAttachedNotifIdxs := TList<Integer>.Create;
  FAnalyzeLock       := TCriticalSection.Create;

  FDebounceTimer := TTimer.Create(nil);
  FDebounceTimer.Enabled  := False;
  FDebounceTimer.Interval := DEBOUNCE_MS;
  FDebounceTimer.OnTimer  := DebounceFire;
end;

destructor TWatchModeManager.Destroy;
begin
  Deactivate;
  FreeAndNil(FDebounceTimer);
  FreeAndNil(FAnalyzeLock);
  FreeAndNil(FAttachedNotifIdxs);
  FreeAndNil(FAttachedNotifiers);
  FreeAndNil(FAttachedModules);
  inherited;
end;

procedure TWatchModeManager.Activate(OnFindings: TWatchFindingsCallback;
  OnStatus: TWatchStatusCallback);
begin
  if FActive then Exit;
  FOnFindings := OnFindings;
  FOnStatus   := OnStatus;
  FActive     := True;
  Inc(FGeneration);
  AttachToOpenModules;
  DoStatus('watching: live analysis on save');
end;

procedure TWatchModeManager.Deactivate;
begin
  if not FActive then Exit;
  FActive := False;
  Inc(FGeneration); // alle laufenden Worker invalidieren
  FDebounceTimer.Enabled := False;
  DetachAll;
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

procedure TWatchModeManager.RescanOpenModules;
begin
  if not FActive then Exit;
  AttachToOpenModules;
end;

procedure TWatchModeManager.NotifyFileSaved(const AFileName: string);
// Wird auf UI-Thread aus AfterSave gerufen. Debounce fuer den Fall dass
// Save mehrfach hintereinander feuert (z.B. Save-on-Build).
begin
  if not FActive then Exit;
  if AFileName = '' then Exit;
  // Nur .pas-Files (kein .dfm/.dpr/...). Detektoren laufen auf Pascal-Source.
  if not AFileName.ToLower.EndsWith('.pas') then Exit;

  FPendingFileName := AFileName;
  FDebounceTimer.Enabled := False; // Reset
  FDebounceTimer.Enabled := True;  // 300 ms warten dann feuern
  DoStatus('saved, queueing analysis: ' + ExtractFileName(AFileName));
end;

procedure TWatchModeManager.DebounceFire(Sender: TObject);
begin
  FDebounceTimer.Enabled := False;
  if not FActive then Exit;
  if FPendingFileName = '' then Exit;
  SpawnAnalyzer(FPendingFileName);
  FPendingFileName := '';
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

  DoStatus('analysing: ' + ExtractFileName(AFileName));
  TWatchAnalyzer.Create(AFileName, UsesCheck, FGeneration);
end;

procedure TWatchModeManager.DoStatus(const S: string);
begin
  if Assigned(FOnStatus) then
    try FOnStatus(S); except end;
end;

procedure TWatchModeManager.AttachToOpenModules;
var
  ModSvc : IOTAModuleServices;
  i      : Integer;
  M      : IOTAModule;
  SE     : IOTASourceEditor;
  Notif  : IOTAModuleNotifier;
  Idx    : Integer;

  function ModuleIsAttached: Boolean;
  var j: Integer;
  begin
    Result := False;
    for j := 0 to FAttachedModules.Count - 1 do
      if FAttachedModules[j] = M then Exit(True);
  end;

  function FindSourceEditor: IOTASourceEditor;
  var j: Integer;
  begin
    Result := nil;
    for j := 0 to M.ModuleFileCount - 1 do
      if Supports(M.ModuleFileEditors[j], IOTASourceEditor, Result) then
        Exit;
  end;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModSvc) then Exit;
  for i := 0 to ModSvc.ModuleCount - 1 do
  begin
    M := ModSvc.Modules[i];
    if not Assigned(M) then Continue;
    if ModuleIsAttached then Continue;
    SE := FindSourceEditor;
    if not Assigned(SE) then Continue; // kein Source-Editor (DFM only o.ae.)
    if not SE.FileName.ToLower.EndsWith('.pas') then Continue;
    try
      Notif := TFindingModuleNotifier.Create(SE.FileName);
      Idx   := M.AddNotifier(Notif);
      FAttachedModules.Add(M);
      FAttachedNotifiers.Add(Notif);
      FAttachedNotifIdxs.Add(Idx);
    except
      // Defensive: einzelnes Modul darf den Rest nicht reissen.
    end;
  end;
end;

procedure TWatchModeManager.DetachAll;
var
  i : Integer;
begin
  // Sauber abmelden bevor Listen freigegeben werden - sonst haben die
  // Module veraltete Slots auf entladenen Code (vgl. uIDELineHighlighter).
  for i := 0 to FAttachedModules.Count - 1 do
  begin
    if not Assigned(FAttachedModules[i]) then Continue;
    try
      FAttachedModules[i].RemoveNotifier(FAttachedNotifIdxs[i]);
    except
      // Modul evtl. schon zerstoert.
    end;
  end;
  FAttachedNotifIdxs.Clear;
  FAttachedNotifiers.Clear; // dropt Refs, Notifier-Objekte werden frei
  FAttachedModules.Clear;
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
