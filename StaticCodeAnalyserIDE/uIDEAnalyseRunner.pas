unit uIDEAnalyseRunner;

// Drei Analyse-Pipelines des Frame-Plugins - seit dem Plugin-Audit (Stufe 3)
// ASYNCHRON in einem Worker-Thread (Muster: TWatchAnalyzer):
//   * RunAll       - rekursiver Verzeichnis-Scan + alle Detektoren
//                    (Scan-Phase + Datei-Phase, MAX_SCAN_FILES Hardlimit)
//   * RunCurrent   - eine einzelne Pas-Datei
//   * RunChanged   - VCS-Diff (Git/SVN) + nur die geaenderten Dateien
//
// Threading-Modell (ersetzt den frueheren synchronen UI-Thread-Scan mit
// Application.ProcessMessages + GLiveAnalyserFrame-Sentinel):
//
//   * Genau EIN Worker-Slot (FWorker). Zweiter Start waehrend eines Laufs
//     wird mit Status-Meldung abgelehnt.
//   * Der Worker fasst NIE Frame-eigene Objekte an: UsesCheck ist eine
//     Bool-Kopie, die IgnoreList eine Deep-Copy (TIgnoreList.CopyFrom,
//     Ownership beim Worker). Engine-Serialisierung uebernimmt der
//     prozessweite Engine-Lock in TAnalysisSession.Run.
//   * Progress: Worker throttled (~10/s) und queued reine Zahlen via
//     TThread.Queue auf den UI-Thread; die UI-Logik (Marquee/Normal,
//     Statustexte, Cancel-Poll) laeuft in HandleProgressUI.
//   * Ergebnis: Synchronize(DeliverResults) NACH TAnalysisSession.Run
//     (Engine-Lock dort bereits freigegeben -> deadlock-frei).
//   * Cancel: FProgress.Cancelled wird im UI-Tick gepollt -> Worker.
//     Terminate; die Engine-Progress-Closure prueft CheckTerminated und
//     wirft EAbort im Worker-Kontext (Engine raeumt auf wie bisher).
//   * Lifecycle: FRunner-Rueckreferenz im Worker wird AUSSCHLIESSLICH auf
//     dem UI-Thread gelesen (Queue-/Synchronize-Closures) und geschrieben
//     (Runner-Destructor detacht: FRunner := nil + Terminate +
//     RemoveQueuedEvents). Ein detachter Worker scannt zu Ende bzw. bricht
//     am naechsten Tick ab, liefert nichts aus und gibt sich selbst frei
//     (FreeOnTerminate). KEIN Pointer-Sentinel, KEIN WaitFor noetig.
//
// Frame-Click-Handler shrinken auf Validierung + PrepareAnalysis +
// Runner.RunX; FinishAnalysis haengt am OnRunDone-Callback (feuert nach
// jedem Lauf-Ende: normal, Cancel oder Fehler).

interface

uses
  System.Classes, System.Generics.Collections,
  Vcl.ComCtrls,
  uMethodd12, uIgnoreList, uRepoSettings,
  uIDEAnalyseProgress;

type
  // Status-Update-Callback (Frame.StatusMode / Frame.StatusProgress).
  TAnalyseStatusProc = procedure(const T: string) of object;

  // Result-Delivery-Callback (Frame.PopulateFindings - exakte Signatur).
  // Findings sind BORROWED - der Runner gibt die Liste nach dem Aufruf frei.
  TAnalyseFindingsProc = procedure(const F: TObjectList<TLeakFinding>;
                                   const BaseDir: string) of object;

  // Lauf-Ende-Callback (Frame.FinishAnalysis) - feuert nach JEDEM Ausgang.
  TAnalyseDoneProc = procedure of object;

  TAnalyseRunner = class;

  // Art des Laufs - steuert Request-Aufbau + Progress-UI-Verhalten.
  // bkProject/bkGroup (Scan-Scope-Konzept 2026-07-20, Phase 4): Dateiliste
  // kommt via ToolsAPI aus dem AKTIVEN IDE-Projekt bzw. der Projektgruppe -
  // im UI-Thread gesammelt (ToolsAPI ist nicht threadsicher), Worker faehrt
  // ssFileList + IndexRoot (Verzeichnis-Superset fuer die Cross-Unit-Indizes).
  TBulkScanKind = (bkAll, bkCurrent, bkChanged, bkProject, bkGroup);

  // Worker-Thread fuer genau einen Scan-Request. Selbstfreigebend
  // (FreeOnTerminate); nach Detach durch den Runner laeuft er ins Leere.
  TBulkScanWorker = class(TThread)
  private
    // NUR auf dem UI-Thread lesen/schreiben (Queue-/Synchronize-Closures
    // bzw. Runner-Destructor). Der Worker-Thread selbst fasst FRunner nie an.
    FRunner    : TAnalyseRunner;
    FKind      : TBulkScanKind;
    FPath      : string;
    FFiles     : TArray<string>;
    FIndexRoot : string;   // bkProject/bkGroup: Cross-Unit-Index-Superset
    FUsesCheck : Boolean;
    FIgnore    : TIgnoreList;   // eigene Deep-Copy, Ownership hier
    FLastTick  : Cardinal;      // Throttle-State (nur Worker-Thread)
    FFilePhase : Boolean;       // Phasen-Wechsel Scan->Datei erzwingt Tick
    FTooMany   : Boolean;
    FCancelled : Boolean;
    FErrorMsg  : string;
    FFindings  : TObjectList<TLeakFinding>;
    FBaseDir   : string;
    procedure QueueProgress(ACurrent, ATotal: Integer);
    procedure DeliverResults;   // via Synchronize (UI-Thread)
  protected
    procedure Execute; override;
  public
    // AIgnoreCopy: Ownership geht an den Worker ueber (auch im Fehlerfall).
    constructor Create(ARunner: TAnalyseRunner; AKind: TBulkScanKind;
      const APath: string; const AFiles: TArray<string>;
      AUsesCheck: Boolean; AIgnoreCopy: TIgnoreList;
      const AIndexRoot: string = '');
    destructor Destroy; override;
  end;

  TAnalyseRunner = class(TComponent)
  private
    // Refs (kein Ownership - alle leben im Frame; der Runner wird im
    // Frame-Destructor VOR den Widgets freigegeben, d.h. solange der
    // Runner lebt, leben auch ProgressBar/Controller/Callbacks).
    FProgress     : TAnalyseProgressController;
    FRepoSettings : TRepoSettings;
    FIgnoreList   : TIgnoreList;
    FProgressBar  : TProgressBar;
    FOnStatusMode     : TAnalyseStatusProc;
    FOnStatusProgress : TAnalyseStatusProc;
    FOnFindings       : TAnalyseFindingsProc;
    FOnRunDone        : TAnalyseDoneProc;
    // Aktiver Worker-Slot; nil = idle. Nur UI-Thread.
    FWorker       : TBulkScanWorker;
    function  StartWorker(AKind: TBulkScanKind; const APath: string;
      const AFiles: TArray<string>; ATotalKnown: Integer;
      const AIndexRoot: string = ''): Boolean;
    // Vom Worker via TThread.Queue: UI-Progress (Marquee/Normal, Texte,
    // Cancel-Poll).
    procedure HandleProgressUI(ACurrent, ATotal: Integer);
    // Vom Worker via Synchronize: Ergebnis-Uebergabe + UI-Abschluss.
    // AFindings ist BORROWED (Worker gibt frei); Lauf-Ausgang (Cancelled/
    // TooMany/ErrorMsg/BaseDir) wird direkt aus den Worker-Feldern gelesen
    // (gleiche Unit).
    procedure HandleScanDone(AWorker: TBulkScanWorker;
      const AFindings: TObjectList<TLeakFinding>);
  public
    constructor Create(AOwner: TComponent;
                       AProgress: TAnalyseProgressController;
                       ARepoSettings: TRepoSettings;
                       AIgnoreList: TIgnoreList;
                       AProgressBar: TProgressBar;
                       AOnStatusMode, AOnStatusProgress: TAnalyseStatusProc;
                       AOnFindings: TAnalyseFindingsProc;
                       AOnRunDone: TAnalyseDoneProc); reintroduce;
    destructor Destroy; override;

    procedure RunAll(const APath: string);
    procedure RunCurrent(const AFilePath: string);
    procedure RunChanged(const AStartPath: string);
    // Phase 4 (Scan-Scope): vorab (UI-Thread!) gesammelte ToolsAPI-Dateiliste.
    // AIndexRoot = Verzeichnis-Superset fuer die Cross-Unit-Indizes
    // (typisch das Projekt-/Gruppenverzeichnis); ABasePath fuer Export-Pfade.
    procedure RunFileList(AKind: TBulkScanKind; const ABasePath: string;
      const AFiles: TArray<string>; const AIndexRoot: string);

    // Direkter Abbruch (zusaetzlich zum FProgress.Cancelled-Poll):
    // terminiert den Worker sofort - die Engine bricht am naechsten
    // Progress-Tick ab.
    procedure CancelRun;

    function IsBusy: Boolean;
  end;

// Welle 1b (2026-07-20): joint ALLE lebenden Bulk-Worker (auch beim
// Dock-Close detachte "Orphans") - Pflichtaufruf im BPL-Unload-Pfad
// (UnregisterAnalyserDockableForm), BEVOR die Package-Code-Pages entladen
// werden. Main-Thread-only; WaitFor pumpt CheckSynchronize.
procedure JoinAllBulkWorkers;

implementation

// noinspection-file BeginEndRequired, ClassPerFile, ConcatToFormat, CyclomaticComplexity, DigitGrouping, DuplicateString, ExceptionTooGeneral, ExceptOnException, LongParamList, NestedTry, PublicField, PublicMemberWithoutDoc, RedundantJump, TooLongLine, UnsortedUses
// Plugin-Top-Level: catch-all an OTAPI/Detector-Grenzen - eine geworfene
// Exception darf nie die laufende IDE killen. Idiomatisch fuer IDE-Plugins.
// ClassPerFile: Worker-Thread + Runner bilden eine Lifecycle-Einheit
// (Detach-Protokoll ueber private Felder) - gleiche Konvention wie
// uIDEWatchMode (Manager + Worker in einer Unit).

uses
  System.SysUtils, System.IOUtils, System.Math,
  Winapi.Windows,                    // GetTickCount
  uVcsChanges, uStaticFiles, uEngineApi,
  uLocalization;                     // _() Macro

const
  MAX_SCAN_FILES = 20000; // Hardlimit - schuetzt vor Endlos-Scan

var
  // Welle 1b (2026-07-20): ALLE Bulk-Worker (FreeOnTerminate ist AUS, die
  // Unit besitzt die Threads). Reap bei jedem StartWorker; JoinAllBulkWorkers
  // im BPL-Unload-Pfad. Deckt auch Dock-Close-Orphans (frueherer Detach lief
  // ohne Join) und schliesst das Selbst-Free-Epilog-Fenster (kein
  // FreeOnTerminate-Destroy in Package-Code mehr). Main-Thread-only.
  GBulkWorkers : TList<TThread> = nil;

procedure ReapBulkWorkers;
var
  i : Integer;
begin
  if not Assigned(GBulkWorkers) then Exit;
  for i := GBulkWorkers.Count - 1 downto 0 do
    if GBulkWorkers[i].Finished then
    begin
      GBulkWorkers[i].Free;
      GBulkWorkers.Delete(i);
    end;
end;

procedure JoinAllBulkWorkers;
var
  i : Integer;
begin
  if not Assigned(GBulkWorkers) then Exit;
  for i := 0 to GBulkWorkers.Count - 1 do
    GBulkWorkers[i].Terminate;
  for i := GBulkWorkers.Count - 1 downto 0 do
  begin
    try
      GBulkWorkers[i].WaitFor;   // pumpt CheckSynchronize im Main-Thread
    except
    end;
    GBulkWorkers[i].Free;
    GBulkWorkers.Delete(i);
  end;
end;

{ ---- TBulkScanWorker ---- }

constructor TBulkScanWorker.Create(ARunner: TAnalyseRunner;
  AKind: TBulkScanKind; const APath: string; const AFiles: TArray<string>;
  AUsesCheck: Boolean; AIgnoreCopy: TIgnoreList;
  const AIndexRoot: string = '');
begin
  inherited Create(False);  // sofort starten
  // Welle 1b (2026-07-20): FreeOnTerminate AUS - GBulkWorkers besitzt den
  // Thread (Reap in StartWorker, Join beim BPL-Unload). Selbst-Free wuerde
  // den Destruktor-Epilog in Package-Code legen, der beim Unload weg ist.
  FreeOnTerminate := False;
  FRunner    := ARunner;
  FKind      := AKind;
  FPath      := APath;
  FFiles     := AFiles;
  FUsesCheck := AUsesCheck;
  FIgnore    := AIgnoreCopy;
  FIndexRoot := AIndexRoot;
end;

destructor TBulkScanWorker.Destroy;
begin
  FreeAndNil(FIgnore);
  FreeAndNil(FFindings);
  inherited;
end;

procedure TBulkScanWorker.QueueProgress(ACurrent, ATotal: Integer);
begin
  TThread.Queue(Self,
    procedure
    begin
      // FRunner-Zugriff auf dem UI-Thread; Runner-Destructor hat ggf.
      // detacht (nil) - dann ist der Tick ein No-op.
      if Assigned(FRunner) then
        FRunner.HandleProgressUI(ACurrent, ATotal);
    end);
end;

procedure TBulkScanWorker.Execute;
begin
  try
    try
      var Req := TScanRequest.Init;
      // Config hat der Aufrufer via SetupForRun gesetzt (unter Engine-Lock).
      Req.SkipConfig := True;
      Req.UsesCheck  := FUsesCheck;
      case FKind of
        bkAll:
          begin
            // Smart-Path (User 2026-07-22): der ▶-Button-Pfad kann ein
            // Verzeichnis ODER eine .dproj/.groupproj sein (der '...'-Dialog
            // laesst beides zu). Endung entscheidet den Engine-Scope; die
            // .dproj/.groupproj-Aufloesung inkl. Auto-IndexRoot/BaseDir macht
            // der Engine-Dispatch (uEngineApi). IgnoreList wirkt bei
            // ssRecursive im Walk, bei ssProject/ssProjectGroup im Dispatch.
            if SameText(ExtractFileExt(FPath), '.dproj') then
              Req.Scope := ssProject
            else if SameText(ExtractFileExt(FPath), '.groupproj') then
              Req.Scope := ssProjectGroup
            else
              Req.Scope := ssRecursive;
            Req.Path       := FPath;
            Req.IgnoreList := FIgnore;
            // FBaseDir (Plugin-lokal fuer Marker/Export): bei Projektdatei
            // deren Verzeichnis; die Engine liefert intern zusaetzlich den
            // CommonRoot fuer die Findings-Pfade.
            if Req.Scope in [ssProject, ssProjectGroup] then
              FBaseDir := ExtractFilePath(FPath)
            else
              FBaseDir := FPath;
          end;
        bkCurrent:
          begin
            // Single-File mit projektweitem Symbol-Index (Cross-Unit-
            // Detektoren). ProjectRoot via .dproj/.dpk/.dpr-Walk-Up.
            Req.Scope                 := ssSingleFile;
            Req.Path                  := FPath;
            Req.SingleFileProjectRoot := TStaticFiles.FindProjectRoot(FPath);
            FBaseDir                  := ExtractFilePath(FPath);
          end;
        bkChanged, bkProject, bkGroup:
          begin
            // bkProject/bkGroup: Liste per IgnoreCopy vorfiltern (der
            // Engine-ssFileList-Zweig wendet keine IgnoreList an; explizite
            // bkChanged-Listen bleiben bewusst ungefiltert = User-Wille).
            if (FKind <> bkChanged) and Assigned(FIgnore) then
            begin
              var Keep := TStringList.Create;
              try
                for var FN in FFiles do
                  if not FIgnore.IsIgnored(FN) then
                    Keep.Add(FN);
                FFiles := Keep.ToStringArray;
              finally
                Keep.Free;
              end;
            end;
            Req.Scope := ssFileList;
            Req.Files := FFiles;
            Req.IndexRoot := FIndexRoot;   // leer bei bkChanged
            FBaseDir  := FPath;
          end;
      else
        ; // alle TBulkScanKind-Werte oben abgedeckt
      end;

      // Progress fuer die Lang-Laeufer; Single-File (bkCurrent) bekommt
      // eine Minimal-Closure, damit Terminate/Join den Lauf am naechsten
      // Engine-Tick abbrechen kann (Welle 1b - vorher lief bkCurrent trotz
      // Terminate immer komplett durch).
      if FKind = bkCurrent then
        Req.Progress :=
          procedure(Current, Total: Integer)
          begin
            if TThread.CheckTerminated then Abort;
          end
      else
        Req.Progress :=
          procedure(Current, Total: Integer)
          // Laeuft im WORKER-Thread (Engine-Callback). Kein UI-Zugriff -
          // nur Cancel-/Limit-Checks + gedrosseltes Queue der Zahlen.
          var
            tick  : Cardinal;
            force : Boolean;
          begin
            // Cancel (CancelRun/Detach/IDE-Shutdown): EAbort im Worker-
            // Kontext - die Engine raeumt ihre Result-Liste selbst auf.
            if TThread.CheckTerminated then
              Abort;
            if (Total < 0) and (Current > MAX_SCAN_FILES) then
            begin
              FTooMany := True;
              Abort;
            end;
            // Phasen-Wechsel Scan->Datei erzwingt einen Tick, damit der
            // Marquee->Normal-Switch nicht am Throttle haengt.
            force := (Total >= 0) and not FFilePhase;
            if force then FFilePhase := True;
            tick := GetTickCount;
            if force or (tick - FLastTick > 100)
               or ((Total > 0) and (Current = Total)) then
            begin
              FLastTick := tick;
              QueueProgress(Current, Total);
            end;
          end;

      var Ses := TAnalysisSession.Create;
      var Res: TScanResult := nil;
      try
        Res := Ses.Run(Req);
        FFindings := Res.ReleaseFindings;
      finally
        Res.Free;
        Ses.Free;
      end;
    except
      on EAbort do
        FCancelled := True;   // Cancel ODER Datei-Limit (FTooMany unterscheidet)
      on E: Exception do
        FErrorMsg := E.Message;
    end;

    // Ergebnis auf den UI-Thread. Engine-Lock ist hier bereits frei
    // (Run zurueckgekehrt) -> deadlock-frei. FIFO der Sync-Queue
    // garantiert: alle vorher gequeueten Progress-Ticks laufen VOR
    // DeliverResults; danach endet Execute -> FreeOnTerminate. Es kann
    // also kein Queue-Eintrag einen toten Worker referenzieren.
    Synchronize(DeliverResults);
  finally
    // Wenn DeliverResults nicht uebernommen hat (Detach), hier freigeben.
    FreeAndNil(FFindings);
  end;
end;

procedure TBulkScanWorker.DeliverResults;
// UI-Thread. Runner kann inzwischen detacht haben (Frame geschlossen).
var
  Local: TObjectList<TLeakFinding>;
begin
  Local := FFindings;
  FFindings := nil;
  try
    if Assigned(FRunner) then
      FRunner.HandleScanDone(Self, Local);
  finally
    Local.Free;
  end;
end;

{ ---- TAnalyseRunner ---- }

constructor TAnalyseRunner.Create(AOwner: TComponent;
  AProgress: TAnalyseProgressController; ARepoSettings: TRepoSettings;
  AIgnoreList: TIgnoreList; AProgressBar: TProgressBar;
  AOnStatusMode, AOnStatusProgress: TAnalyseStatusProc;
  AOnFindings: TAnalyseFindingsProc; AOnRunDone: TAnalyseDoneProc);
begin
  inherited Create(AOwner);
  FProgress         := AProgress;
  FRepoSettings     := ARepoSettings;
  FIgnoreList       := AIgnoreList;
  FProgressBar      := AProgressBar;
  FOnStatusMode     := AOnStatusMode;
  FOnStatusProgress := AOnStatusProgress;
  FOnFindings       := AOnFindings;
  FOnRunDone        := AOnRunDone;
end;

destructor TAnalyseRunner.Destroy;
begin
  // Detach statt WaitFor: der Worker haelt NUR eigene Kopien (IgnoreList-
  // Deep-Copy, Bool, Strings) - er darf den Frame-Teardown ueberleben.
  // FRunner := nil (UI-Thread) macht alle kuenftigen Queue-/Synchronize-
  // Closures zu No-ops; RemoveQueuedEvents droppt bereits gequeuete
  // Progress-Ticks; Terminate laesst die Engine am naechsten Tick abbrechen.
  if Assigned(FWorker) then
  begin
    FWorker.FRunner := nil;
    FWorker.Terminate;
    TThread.RemoveQueuedEvents(FWorker);
    FWorker := nil;   // Objekt bleibt in GBulkWorkers - Reap/Join raeumt
  end;
  inherited;
end;

function TAnalyseRunner.IsBusy: Boolean;
begin
  Result := Assigned(FWorker);
end;

procedure TAnalyseRunner.CancelRun;
begin
  if Assigned(FWorker) then
    FWorker.Terminate;
end;

function TAnalyseRunner.StartWorker(AKind: TBulkScanKind; const APath: string;
  const AFiles: TArray<string>; ATotalKnown: Integer;
  const AIndexRoot: string): Boolean;
var
  IgnoreCopy: TIgnoreList;
begin
  Result := False;
  if Assigned(FWorker) then
  begin
    FOnStatusMode(_('An analysis is already running.'));
    Exit;
  end;

  if Assigned(FProgress) then
    FProgress.BeginRun(ATotalKnown);

  // Worker-eigene IgnoreList-Kopie (der Worker darf keine Frame-Objekte
  // lesen - der Frame kann waehrend des Scans geschlossen werden).
  // Test-Filter aus analyser.ini [Detectors] IncludeTests uebernehmen.
  // Ownership geht erst mit erfolgreichem Worker-Create ueber - wirft der
  // Thread-Create (EThread), gibt der except-Zweig die Kopie frei (der
  // halbkonstruierte Worker hat FIgnore nie zugewiesen, sein Destructor
  // freed nur nil).
  IgnoreCopy := nil;
  try
    if AKind in [bkAll, bkProject, bkGroup] then
    begin
      // bkProject/bkGroup (Verifikations-Fix 2026-07-20): ignore.txt +
      // SkipTests gelten auch fuer ToolsAPI-Projektlisten - Parity zu
      // bkAll und zur Standalone (deren ssProject-Dispatch filtert).
      IgnoreCopy := TIgnoreList.Create;
      if Assigned(FIgnoreList) then
        IgnoreCopy.CopyFrom(FIgnoreList);
      if Assigned(FRepoSettings) then
        IgnoreCopy.SkipTests := not FRepoSettings.IncludeTests;
    end;
    ReapBulkWorkers;
    FWorker := TBulkScanWorker.Create(Self, AKind, APath, AFiles,
      Assigned(FRepoSettings) and FRepoSettings.UsesCheck, IgnoreCopy,
      AIndexRoot);
    GBulkWorkers.Add(FWorker);
  except
    IgnoreCopy.Free;
    if Assigned(FProgress) then FProgress.EndRun;
    raise;
  end;
  Result := True;
end;

procedure TAnalyseRunner.HandleProgressUI(ACurrent, ATotal: Integer);
// UI-Thread (via TThread.Queue). Solange der Runner lebt, leben auch
// ProgressBar + Frame-Callbacks (Runner wird im Frame-Destructor zuerst
// freigegeben und detacht dabei den Worker).
begin
  // Cancel-Poll: Cancel-Menu-Item setzt FProgress.Cancelled (UI) - hier
  // in den Worker uebersetzen. Zusaetzlich wirkt CancelRun direkt.
  if Assigned(FProgress) and FProgress.Cancelled then
    CancelRun;

  if not Assigned(FProgressBar) then Exit;

  if ATotal < 0 then
  begin
    // ---- Scan-Phase (Verzeichnis-Suche) ----
    // pbstMarquee = echte indeterminate-Animation; Position bleibt 0.
    if FProgressBar.Style <> pbstMarquee then
      FProgressBar.Style := pbstMarquee;
    FOnStatusProgress(Format(_('Scanning... %d found'), [ACurrent]));
  end
  else
  begin
    // ---- Analyse-Phase ----
    // Reihenfolge wichtig: Max + Position ZUERST, Style ZULETZT - sonst
    // blitzt beim Marquee->Normal-Switch kurz Position=0 auf.
    if (FProgressBar.Max <> ATotal) and (ATotal > 0) then
      FProgressBar.Max := ATotal;
    FProgressBar.Position := ACurrent;
    if FProgressBar.Style <> pbstNormal then
      FProgressBar.Style := pbstNormal;
    FOnStatusProgress(Format(_('File %d / %d (%d%%)'),
      [ACurrent, ATotal,
       IfThen(ATotal > 0, Round(ACurrent * 100 / ATotal), 0)]));
  end;
end;

procedure TAnalyseRunner.HandleScanDone(AWorker: TBulkScanWorker;
  const AFindings: TObjectList<TLeakFinding>);
// UI-Thread (via Synchronize). Schliesst den Lauf ab: Ergebnis-Delivery,
// Status-Meldung, UI zurueck in Ruhe-Zustand, FinishAnalysis-Callback.
begin
  FWorker := nil;   // Slot frei - Objekt bleibt in GBulkWorkers (Reap)

  try
    if AWorker.FErrorMsg <> '' then
      FOnStatusMode(_('Analysis error: ') + AWorker.FErrorMsg)
    else
    begin
      if Assigned(AFindings) then
        FOnFindings(AFindings, AWorker.FBaseDir);  // BORROWED - Worker gibt frei
      if AWorker.FTooMany then
        FOnStatusMode(Format(
          _('More than %d files found - scan cancelled.'), [MAX_SCAN_FILES]))
      else if AWorker.FCancelled then
        FOnStatusMode(_('Analysis cancelled - no new findings loaded'));
    end;
  finally
    if Assigned(FProgress) then
      FProgress.EndRun;
    if Assigned(FOnRunDone) then
      FOnRunDone;
  end;
end;

procedure TAnalyseRunner.RunAll(const APath: string);
begin
  StartWorker(bkAll, APath, nil, 0);
end;

procedure TAnalyseRunner.RunCurrent(const AFilePath: string);
// Status-Anzeige: "Analysing: Foo.pas + Foo.dfm" wenn die companion .dfm
// existiert (DFM-Detektoren laufen via TDfmAnalysisRunner.AnalyzePasFile mit).
// Kein Progress-Callback - Single-File ist kurz; BeginRun(0) liefert die
// Marquee-"laeuft"-Indikation, EndRun kommt ueber HandleScanDone.
var
  DfmPath, DisplayName: string;
begin
  DisplayName := ExtractFileName(AFilePath);
  DfmPath := TPath.ChangeExtension(AFilePath, '.dfm');
  if TFile.Exists(DfmPath) then
    DisplayName := DisplayName + ' + ' + ExtractFileName(DfmPath);
  FOnStatusProgress(_('Analysing: ') + DisplayName);
  StartWorker(bkCurrent, AFilePath, nil, 0);
end;

procedure TAnalyseRunner.RunFileList(AKind: TBulkScanKind;
  const ABasePath: string; const AFiles: TArray<string>;
  const AIndexRoot: string);
// Phase 4 (Scan-Scope-Konzept): Liste kommt fertig vom UI-Thread
// (ToolsAPI-Sammlung in uIDEAnalyserForm) - hier nur Checks + Spawn.
// Expliziter Count-Check statt MAX_SCAN_FILES-Progress-Cap: der greift
// bei ssFileList nie (Review-Gap G1 im Konzept).
begin
  if Assigned(FWorker) then
  begin
    FOnStatusMode(_('An analysis is already running.'));
    Exit;
  end;
  if Length(AFiles) = 0 then
  begin
    FOnStatusMode(_('No .pas files in the selected project scope.'));
    Exit;
  end;
  if Length(AFiles) > MAX_SCAN_FILES then
  begin
    FOnStatusMode(Format(
      _('More than %d files in scope - scan cancelled.'), [MAX_SCAN_FILES]));
    Exit;
  end;
  FOnStatusProgress(Format(_('%d file(s) - running...'), [Length(AFiles)]));
  StartWorker(AKind, ABasePath, AFiles, Length(AFiles), AIndexRoot);
end;

procedure TAnalyseRunner.RunChanged(const AStartPath: string);
// Branch-Aenderungen via Git oder SVN. Der VCS-Diff selbst laeuft synchron
// auf dem UI-Thread (kurzer git/svn-Aufruf; liest FRepoSettings, das darf
// der Worker nicht) - nur die eigentliche Analyse geht in den Worker.
var
  files : TStringList;
  info  : string;
begin
  if Assigned(FWorker) then
  begin
    FOnStatusMode(_('An analysis is already running.'));
    Exit;
  end;

  files := TVcsChanges.GetChangedPasFilesAuto(AStartPath, info, FRepoSettings);
  try
    if files.Count = 0 then
    begin
      FOnStatusMode(info + _(' - no changed .pas files'));
      Exit;
    end;
    FOnStatusMode(info);
    FOnStatusProgress(Format(_('%d file(s) - running...'), [files.Count]));
    StartWorker(bkChanged, AStartPath, files.ToStringArray, files.Count);
  finally
    files.Free;
  end;
end;

initialization
  GBulkWorkers := TList<TThread>.Create;

finalization
  // Defensiv: falls der Unload-Pfad den Join verpasst hat.
  JoinAllBulkWorkers;
  FreeAndNil(GBulkWorkers);

end.
