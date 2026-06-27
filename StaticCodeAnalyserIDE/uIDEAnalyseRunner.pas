unit uIDEAnalyseRunner;

// Drei Analyse-Pipelines des Frame-Plugins:
//   * RunAll       - rekursiver Verzeichnis-Scan + alle Detektoren
//                    (Scan-Phase + Datei-Phase, MAX_SCAN_FILES Hardlimit,
//                    Cancel via FAnalyseProgress.Cancelled)
//   * RunCurrent   - eine einzelne Pas-Datei (kurz, kein Worker-Callback)
//   * RunChanged   - VCS-Diff (Git/SVN) + nur die geaenderten Dateien
//
// Vorher: ~330 Zeilen direkt im Frame, plus die Worker-Closures mit
// captured Frame-Self - Lifecycle-Race wurde via GLiveAnalyserFrame-
// Sentinel abgefedert.
//
// Lifecycle-Sicherheit (kritisch beim Hot-Plug-Reload des IDE-Plugins):
//
//   Wenn der User waehrend einer laufenden Analyse das IDE-Dock-Fenster
//   schliesst, wird die Frame-Instanz freigegeben. Der Worker-Callback
//   feuert aber noch (suspendiert in Application.ProcessMessages). Sein
//   captured Self wuerde dann auf einen freed Heap-Block zeigen.
//
//   Schutz: Der Frame-Constructor setzt das globale GLiveAnalyserFrame :=
//   Pointer(Self), der Destructor nilt es als ALLERERSTES (vor allen
//   anderen Field-Frees). Closures snapshoten den Frame-Pointer in eine
//   *lokale* Variable (anonymous-method-Capture-by-Value) und vergleichen
//   sie pro Iteration gegen GLiveAnalyserFrame. Bei Mismatch -> Abort.
//
//   Wichtig: der Sentinel-Vergleich darf KEINEN Self-Deref erfordern -
//   sonst waere er selbst nicht safe gegen dangling Self. Deshalb capture
//   wir die Snapshot in einer LOCAL var, nicht via Self.FFramePtr.
//
// Frame-Click-Handler bleiben in TAnalyserFrame und shrinken auf
// Validierung + PrepareAnalysis + Runner.RunX + FinishAnalysis-Wrapper.

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
  TAnalyseFindingsProc = procedure(const F: TObjectList<TLeakFinding>;
                                   const BaseDir: string) of object;

  TAnalyseRunner = class(TComponent)
  private
    // Refs (kein Ownership - alle leben im Frame).
    FProgress     : TAnalyseProgressController;
    FRepoSettings : TRepoSettings;
    FIgnoreList   : TIgnoreList;
    FProgressBar  : TProgressBar;
    // Frame-Pointer fuer Lifecycle-Sentinel (KEIN Deref - nur Pointer-
    // Vergleich gegen GLiveAnalyserFrame).
    FFramePtr     : Pointer;
    // Callbacks (procedure of object - haengen vom Frame ab).
    FOnStatusMode     : TAnalyseStatusProc;
    FOnStatusProgress : TAnalyseStatusProc;
    FOnFindings       : TAnalyseFindingsProc;
    // Throttle-State fuer Worker-UI-Updates (~10/s).
    FLastTick     : Cardinal;
  public
    // AOwner = Frame (haftet via TComponent-Owner-Mechanismus).
    // AFramePtr = Pointer(Frame), wird gegen GLiveAnalyserFrame verglichen.
    constructor Create(AOwner: TComponent;
                       AFramePtr: Pointer;
                       AProgress: TAnalyseProgressController;
                       ARepoSettings: TRepoSettings;
                       AIgnoreList: TIgnoreList;
                       AProgressBar: TProgressBar;
                       AOnStatusMode, AOnStatusProgress: TAnalyseStatusProc;
                       AOnFindings: TAnalyseFindingsProc); reintroduce;

    procedure RunAll(const APath: string);
    procedure RunCurrent(const AFilePath: string);
    procedure RunChanged(const AStartPath: string);
  end;

implementation

// noinspection-file BeginEndRequired, ConcatToFormat, CyclomaticComplexity, DigitGrouping, DuplicateString, ExceptionTooGeneral, ExceptOnException, LongParamList, NestedTry, PublicField, PublicMemberWithoutDoc, RedundantJump, TooLongLine, UnsortedUses
// Plugin-Top-Level: catch-all an OTAPI/Detector-Grenzen - eine geworfene
// Exception darf nie die laufende IDE killen. Idiomatisch fuer IDE-Plugins.

uses
  System.SysUtils, System.IOUtils, System.Math,
  Winapi.Windows,                    // GetTickCount
  Vcl.Forms,                         // Application.ProcessMessages, Screen
  Vcl.Controls,                      // crHourglass, crDefault
  uStaticAnalyzer2, uVcsChanges, uStaticFiles, uEngineApi,
  uLocalization,                     // _() Macro
  uIDELifecycle;                     // GLiveAnalyserFrame

constructor TAnalyseRunner.Create(AOwner: TComponent; AFramePtr: Pointer;
  AProgress: TAnalyseProgressController; ARepoSettings: TRepoSettings;
  AIgnoreList: TIgnoreList; AProgressBar: TProgressBar;
  AOnStatusMode, AOnStatusProgress: TAnalyseStatusProc;
  AOnFindings: TAnalyseFindingsProc);
begin
  inherited Create(AOwner);
  FFramePtr         := AFramePtr;
  FProgress         := AProgress;
  FRepoSettings     := ARepoSettings;
  FIgnoreList       := AIgnoreList;
  FProgressBar      := AProgressBar;
  FOnStatusMode     := AOnStatusMode;
  FOnStatusProgress := AOnStatusProgress;
  FOnFindings       := AOnFindings;
end;

procedure TAnalyseRunner.RunAll(const APath: string);
const
  MAX_SCAN_FILES = 20000; // Hardlimit - schuetzt vor Endlos-Scan
var
  findings     : TObjectList<TLeakFinding>;
  wasCancelled : Boolean;
  // Snapshot fuer Closure (Capture-by-Value, kein Self-Deref).
  FrameSnap    : Pointer;
begin
  FrameSnap := FFramePtr;
  FLastTick := 0;
  wasCancelled := False;
  // Test-Filter aus analyser.ini [Detectors] IncludeTests uebernehmen:
  // IncludeTests=1 -> Tests einschliessen -> SkipTests=False.
  if Assigned(FIgnoreList) and Assigned(FRepoSettings) then
    FIgnoreList.SkipTests := not FRepoSettings.IncludeTests;
  try
    // ProgressBar.Max kennen wir erst nach dem ersten Callback - bis dahin
    // zeigen wir einen "Marquee"-aehnlichen Stand (Max=100, Position=0).
    // BeginRun INSIDE try damit EndRun im finally garantiert laeuft auch
    // wenn BeginRun selbst raised (sehr unwahrscheinlich, aber EndRun
    // ist idempotent - setzt UI sicher in Ruhe-Zustand zurueck).
    if Assigned(FProgress) then FProgress.BeginRun(0);
    try
      FOnStatusMode(_('Analysis running - searching for files...'));
      Application.ProcessMessages;

      findings := nil;
      try
        try
          // Phase 4: Scan ueber die Facade (Config hat der Aufrufer via
          // SetupForRun gesetzt -> SkipConfig). Progress-Proc + IgnoreList +
          // UsesCheck wandern in den Request; EAbort propagiert wie zuvor.
          var Req := TScanRequest.Init;
          Req.SkipConfig := True;
          Req.Scope      := ssRecursive;
          Req.Path       := APath;
          Req.UsesCheck  := FRepoSettings.UsesCheck;
          Req.IgnoreList := FIgnoreList;
          Req.Progress   :=
            procedure(Current, Total: Integer)
            // Total = -1 -> Verzeichnis-Scan-Phase
            // Total >= 0 -> pro-Datei-Analyse-Phase
            var
              tick     : Cardinal;
              doUpdate : Boolean;
            begin
              // ALLERERSTES: Lifecycle-Race-Schutz. FrameSnap ist eine
              // captured Local - kein Self-Deref noetig, safe auch wenn
              // der Runner selbst inzwischen dangling waere.
              if GLiveAnalyserFrame <> FrameSnap then
                Abort;
              try
                if not Assigned(FProgressBar) then Exit;

                tick := GetTickCount;
                doUpdate := (tick - FLastTick > 100);

                // Defensiv: erster File-Phase-Tick (Total>=0) MUSS durch,
                // damit der Style-Switch Marquee->Normal nicht durch den
                // 100ms-Throttle bis zum naechsten Tick verzoegert wird.
                if (Total >= 0) and (FProgressBar.Style = pbstMarquee) then
                  doUpdate := True;

                if Total < 0 then
                begin
                  // ---- Scan-Phase ----
                  if Current > MAX_SCAN_FILES then
                  begin
                    FOnStatusMode(Format(
                      _('More than %d files found - scan cancelled.'),
                      [MAX_SCAN_FILES]));
                    Abort;
                  end;
                  if doUpdate then
                  begin
                    FLastTick := tick;
                    // pbstMarquee = echte indeterminate-Animation
                    // (ComCtl32-Marquee, Style-Switch atomic, kein
                    // Position-Sliding). Position bleibt auf 0 - so
                    // gibt's beim Uebergang zur Datei-Phase keinen
                    // Clamp-Flash mehr.
                    if FProgressBar.Style <> pbstMarquee then
                      FProgressBar.Style := pbstMarquee;
                    FOnStatusProgress(Format(_('Scanning... %d found'), [Current]));
                    Application.ProcessMessages;
                  end;
                end
                else
                begin
                  // ---- Analyse-Phase ----
                  if doUpdate or (Current = Total) then
                  begin
                    FLastTick := tick;
                    // Reihenfolge wichtig: Max + Position ZUERST, Style
                    // ZULETZT. Sonst wird beim Style-Wechsel pbstMarquee->
                    // pbstNormal kurz die alte Position=0 sichtbar (zweite
                    // "Bar faengt bei 0 an"-Phase nach der Scan-Animation).
                    // Mit dieser Reihenfolge zeigt die Bar beim Style-
                    // Switch direkt schon den aktuellen Fortschritt.
                    if (FProgressBar.Max <> Total) and (Total > 0) then
                      FProgressBar.Max := Total;
                    FProgressBar.Position := Current;
                    if FProgressBar.Style <> pbstNormal then
                      FProgressBar.Style := pbstNormal;
                    FOnStatusProgress(Format(_('File %d / %d (%d%%)'),
                      [Current, Total,
                       IfThen(Total > 0, Round(Current * 100 / Total), 0)]));
                    Application.ProcessMessages;
                  end;
                end;

                if Assigned(FProgress) and FProgress.Cancelled then
                  Abort; // EAbort - silent
              except
                on EAbort do raise;
                // andere UI-Update-Fehler schlucken, Analyse weiterlaufen lassen
              end;
            end;
          var Ses := TAnalysisSession.Create;
          var Res: TScanResult := nil;
          try
            Res := Ses.Run(Req);
            findings := Res.ReleaseFindings;
          finally
            Res.Free;
            Ses.Free;
          end;
        except
          on EAbort do
          begin
            wasCancelled := True;
            // findings ist nil - AnalyzeLeaksRecursive gibt seine Result-Liste
            // bei EAbort frei. Wir behalten daher die alten FAllFindings.
          end;
          on E: Exception do
          begin
            FOnStatusMode(_('Analysis error: ') + E.Message);
            Exit;
          end;
        end;

        // Lifecycle-Check: Frame koennte waehrend ProcessMessages-Reentries
        // im Worker zerstoert worden sein. Ohne Frame ist OnFindings/
        // OnStatusMode nicht mehr aufrufbar (procedure-of-object haengt am
        // Frame). Bei Mismatch: findings explizit freigeben, Cleanup ueber-
        // springen.
        if GLiveAnalyserFrame <> FrameSnap then
        begin
          FreeAndNil(findings);
          Exit;
        end;

        if Assigned(findings) then
          FOnFindings(findings, APath);

        if wasCancelled then
          FOnStatusMode(_('Analysis cancelled - no new findings loaded'));
      finally
        // FreeAndNil statt Free: bei EAbort hat AnalyzeLeaksRecursive die
        // Liste ggf. schon selbst freigegeben (findings = nil). Free auf
        // nil ist safe, FreeAndNil ist semantisch klarer.
        FreeAndNil(findings);
      end;
    except
      on E: Exception do
        if GLiveAnalyserFrame = FrameSnap then
          FOnStatusMode(_('Unexpected error: ') + E.Message);
        // Bei zerstoertem Frame: Exception still verschlucken.
    end;
  finally
    if (GLiveAnalyserFrame = FrameSnap) and Assigned(FProgress) then
      FProgress.EndRun;
  end;
end;

procedure TAnalyseRunner.RunCurrent(const AFilePath: string);
// Eine einzelne Pas-Datei. Kein Worker-Callback (Single-File-Analyse
// ist kurz, Cancel waere Overkill). Lifecycle-Race-Schutz analog
// RunAll - aber hier reicht der finally-Cleanup, weil keine
// ProcessMessages mid-flight stehen.
//
// Status-Anzeige: "Analysing: Foo.pas + Foo.dfm" wenn die companion .dfm
// existiert. Die DFM-Detektoren laufen ohnehin via TDfmAnalysisRunner.
// AnalyzePasFile - der User sieht damit, dass beide Dateien abgedeckt sind.
var
  findings    : TObjectList<TLeakFinding>;
  FrameSnap   : Pointer;
  DfmPath     : string;
  DisplayName : string;
begin
  FrameSnap := FFramePtr;
  Screen.Cursor := crHourglass;
  // Marquee an, damit der User waehrend der Single-File-Analyse die
  // "laeuft jetzt"-Indikation bekommt (gleiche Optik wie Scan-Phase
  // in RunAll). Kein BeginRun/EndRun - die ProgressBar wird hier
  // nur stilistisch genutzt, ohne Counter-Logik.
  if Assigned(FProgressBar) then
    FProgressBar.Style := pbstMarquee;
  try
    try
      DisplayName := ExtractFileName(AFilePath);
      DfmPath := TPath.ChangeExtension(AFilePath, '.dfm');
      if TFile.Exists(DfmPath) then
        DisplayName := DisplayName + ' + ' + ExtractFileName(DfmPath);
      FOnStatusProgress(_('Analysing: ') + DisplayName);
      Application.ProcessMessages;

      findings := nil;
      try
        try
          // Single-File-Analyse mit projektweitem Symbol-Index. ProjectRoot
          // via .dproj/.dpk/.dpr-Walk-Up (oder .git als Fallback). Visibility-
          // Detektoren (CanBeUnit/Strict/Protected/Unused) laufen single-
          // file; der Projekt-Scope dient anderen Cross-Unit-Konsumenten.
          // Phase 4: Single-File ueber die Facade. Config via SetupForRun
          // (-> SkipConfig); ProjectRoot fuer den projektweiten Symbol-Index.
          var Req := TScanRequest.Init;
          Req.SkipConfig            := True;
          Req.Scope                 := ssSingleFile;
          Req.Path                  := AFilePath;
          Req.SingleFileProjectRoot := TStaticFiles.FindProjectRoot(AFilePath);
          Req.UsesCheck             := FRepoSettings.UsesCheck;
          var Ses := TAnalysisSession.Create;
          var Res: TScanResult := nil;
          try
            Res := Ses.Run(Req);
            findings := Res.ReleaseFindings;
          finally
            Res.Free;
            Ses.Free;
          end;
        except
          on E: Exception do
          begin
            FOnStatusMode(_('Analysis error: ') + E.Message);
            Exit;
          end;
        end;

        if (GLiveAnalyserFrame = FrameSnap) and Assigned(findings) then
          FOnFindings(findings, ExtractFilePath(AFilePath));
      finally
        findings.Free;
      end;
    except
      on E: Exception do
        if GLiveAnalyserFrame = FrameSnap then
          FOnStatusMode(_('Unexpected error: ') + E.Message);
    end;
  finally
    Screen.Cursor := crDefault;
    if Assigned(FProgressBar) then
    begin
      FProgressBar.Style := pbstNormal;
      FProgressBar.Position := 0;
    end;
  end;
end;

procedure TAnalyseRunner.RunChanged(const AStartPath: string);
// Branch-Aenderungen via Git oder SVN. AStartPath dient als Repo-
// Detection-Anker. Files werden ueber TVcsChanges eingeholt; danach
// laeuft der gleiche Worker-Loop wie RunAll, nur ohne Scan-Phase
// (Files-Liste ist schon bekannt).
var
  files     : TStringList;
  info      : string;
  findings  : TObjectList<TLeakFinding>;
  wasCanc   : Boolean;
  FrameSnap : Pointer;
begin
  FrameSnap := FFramePtr;

  // ---- VCS-Diff einholen ----
  files := TVcsChanges.GetChangedPasFilesAuto(AStartPath, info, FRepoSettings);
  try
    if files.Count = 0 then
    begin
      FOnStatusMode(info + _(' - no changed .pas files'));
      Exit;
    end;

    // ---- Analyse starten ----
    FLastTick := 0;
    wasCanc := False;
    try
      // BeginRun INSIDE try damit EndRun im finally garantiert laeuft
      // auch wenn BeginRun selbst raised. EndRun ist idempotent.
      if Assigned(FProgress) then FProgress.BeginRun(files.Count);

      FOnStatusMode(info);
      FOnStatusProgress(Format(_('%d file(s) - running...'), [files.Count]));
      Application.ProcessMessages;

      findings := nil;
      try
        try
          // Phase 4: geaenderte Dateien ueber die Facade (Config via
          // SetupForRun -> SkipConfig). Liste + Progress-Proc + UsesCheck
          // wandern in den Request.
          var Req := TScanRequest.Init;
          Req.SkipConfig := True;
          Req.Scope      := ssFileList;
          Req.Files      := files.ToStringArray;
          Req.UsesCheck  := FRepoSettings.UsesCheck;
          Req.Progress   :=
            procedure(Current, Total: Integer)
            var
              tick: Cardinal;
            begin
              if GLiveAnalyserFrame <> FrameSnap then
                Abort;
              try
                if not Assigned(FProgressBar) then Exit;
                tick := GetTickCount;
                if (tick - FLastTick > 100) or (Current = Total) then
                begin
                  FLastTick := tick;
                  // RunChanged hat keine Scan-Phase - Files-Liste ist
                  // schon vor BeginRun bekannt. BeginRun(files.Count)
                  // setzt Style := pbstNormal und Max := files.Count.
                  // Daher kein Style-/Max-Wechsel mehr noetig.
                  FProgressBar.Position := Current;
                  FOnStatusProgress(Format(_('File %d / %d'), [Current, Total]));
                  Application.ProcessMessages;
                end;
                if Assigned(FProgress) and FProgress.Cancelled then Abort;
              except
                on EAbort do raise;
              end;
            end;
          var Ses := TAnalysisSession.Create;
          var Res: TScanResult := nil;
          try
            Res := Ses.Run(Req);
            findings := Res.ReleaseFindings;
          finally
            Res.Free;
            Ses.Free;
          end;
        except
          on EAbort do
            wasCanc := True;
          on E: Exception do
          begin
            FOnStatusMode(_('Analysis error: ') + E.Message);
            Exit;
          end;
        end;

        if (GLiveAnalyserFrame = FrameSnap) and Assigned(findings) then
          FOnFindings(findings, AStartPath);
        if wasCanc and (GLiveAnalyserFrame = FrameSnap) then
          FOnStatusMode(_('Analysis cancelled'));
      finally
        findings.Free;
      end;
    finally
      if (GLiveAnalyserFrame = FrameSnap) and Assigned(FProgress) then
        FProgress.EndRun;
    end;
  finally
    files.Free;
  end;
end;

end.
