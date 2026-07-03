unit uIDELifecycle;

// Lifecycle-Sentinel fuer den Analyser-Frame.
//
// Hintergrund: TAnalyserFrame uebergibt anonymen Methods an Worker-
// Pipelines (TStaticAnalyzer2.AnalyzeLeaksRecursive etc.). Diese
// Closures captured Self - wenn der User waehrend der laufenden Analyse
// das IDE-Dock-Fenster schliesst, wird die Frame-Instanz freigegeben.
// Der Worker-Callback feuert aber noch (suspendiert in Application.
// ProcessMessages). Sein captured Self zeigt dann auf einen freed
// Heap-Block - jeder Field-Access waere ein AV.
//
// Schutzmassnahme: globaler Pointer der genau auf den aktuell lebenden
// Frame zeigt. Constructor setzt ihn auf Self, Destructor nilt ihn als
// allererste Aktion (vor allen anderen Field-Frees). Closures pruefen
// pro Iteration "ist der globale Pointer noch == FrameSnap?" - bei
// Mismatch (Frame zerstoert oder anderer Frame aktiv) sofort Abort
// ohne Field-Zugriff.
//
// Funktioniert weil der Pointer-VERGLEICH safe ist auch wenn Self auf
// invaliden Speicher zeigt - es wird kein Feld dereferenziert.
//
// Diese Variable lebt in einem eigenen Mini-Unit damit sowohl der Frame
// als auch der ausgelagerte TAnalyseRunner sie ohne uses-Zyklus
// importieren koennen.

interface

uses
  uRepoSettings;

var
  GLiveAnalyserFrame: Pointer = nil;

type
  // Single-Point-of-Truth fuer das Detector-State-Setup VOR jedem Scan-Run
  // im IDE-Plugin. Vier Pfade rufen das (siehe Konzept_FindingsPropertiesPanel
  // Refactor-Notiz):
  //   1. TAnalyserFrame.PrepareAnalysis             (Plugin-Hauptfenster)
  //   2. RunSilentAnalysisForFile                   (Silent-Mode + Properties-Auto)
  //   3. TWatchModeManager.SpawnAnalyzer-Vorbereitung (Watch-Mode-Re-Scan)
  //   4. Properties-Auto-Scan via #2
  //
  // Vorher: jeder Pfad hatte seine eigene Setup-Sequenz - Drift-Risiko
  // (Profile-Override-Quelle, UsesCheck hardcoded False im Watch, BumpGeneration
  // fehlte in Silent, etc.). Die Klasse zieht alle Setup-Schritte in EINE
  // Stelle damit Aenderungen automatisch alle Pfade treffen.
  TIDEAnalysisPrep = class
  strict private
    // Die eigentlichen Setup-Schritte 1-8; laufen IMMER unter dem Engine-
    // Lock (SetupForRun klammert). Eigene Methode, damit die bewussten
    // per-Step-try-excepts nicht im Lock-try/finally verschachtelt sind.
    class procedure RunSetupSteps(ASettings: TRepoSettings;
      const AProjectPath: string; const AProfileOverride: string);
  public
    // Reihenfolge der Schritte ist signifikant:
    //   1. Load + RegisterToLeakyClasses (Detector-Klassen-Listen aus INI)
    //   2. UseIdeRuleSet (IDE-Profile aktivieren, Default ide-fast)
    //   3. ProfileOverride (UI-Combo / Frame-Override gewinnt)
    //   4. ApplyDetectorThresholds (Profile-spezifische Schwellwerte)
    //   5. AutoDiscoverCustomClasses global syncen
    //   6. DiscoveredClasses-Listen leeren (frischer Run)
    //   7. Watch-Mode BumpGeneration (laufende Worker droppen)
    //
    // AProjectPath: fuer relative Pfade in CustomRulesFile / Project-INI.
    //               Bei Single-File-Pfaden = ExtractFilePath(AFileName).
    // AProfileOverride: leer = kein Override (INI-Wert gilt). Sonst:
    //                   Profile wird explizit auf diesen Wert gesetzt.
    class procedure SetupForRun(ASettings: TRepoSettings;
      const AProjectPath: string;
      const AProfileOverride: string = '');
  end;

implementation

uses
  uSCAConsts,         // AutoDiscoverCustomClasses, DiscoveredClasses
  uEngineApi,         // TAnalysisSession.Acquire/ReleaseEngineLock
  uIDEWatchMode;      // GWatchMode

class procedure TIDEAnalysisPrep.SetupForRun(ASettings: TRepoSettings;
  const AProjectPath: string; const AProfileOverride: string);
// Pro Schritt eigenes try-except: ein Load-Fehler (z.B. INI gelockt vom
// User-Editor) darf NICHT verhindern dass die spaeteren Schritte
// (UseIdeRuleSet, ApplyDetectorThresholds) laufen - sonst lauft der
// Detector mit komplett fehlkonfiguriertem Global-State und liefert
// keine oder die falschen Findings.
begin
  if not Assigned(ASettings) then Exit;

  // Engine-Lock (rekursiv, prozessweit - derselbe, den TAnalysisSession.Run
  // intern nimmt): die Setup-Schritte mutieren den globalen Detector-State
  // (LeakyClasses via RegisterToLeakyClasses, DiscoveredClasses.Clear ...).
  // Ohne Lock racte das mit einem laufenden Watch-Worker-Scan, der genau
  // diese Listen iteriert -> TStringList-Mutation waehrend Fremd-Iteration
  // (Plugin-Audit CRITICAL, Cluster A). Kein Synchronize/ProcessMessages
  // im Block -> deadlock-frei. Der fruehere FAnalyzeLock (uIDEWatchMode)
  // war einseitig und damit wirkungslos; er ist geloescht.
  TAnalysisSession.AcquireEngineLock;
  try
    RunSetupSteps(ASettings, AProjectPath, AProfileOverride);
  finally
    TAnalysisSession.ReleaseEngineLock;
  end;
end;

class procedure TIDEAnalysisPrep.RunSetupSteps(ASettings: TRepoSettings;
  const AProjectPath: string; const AProfileOverride: string);
// Laeuft unter dem Engine-Lock (Caller SetupForRun klammert).
begin
  // 1. Frische INI lesen.
  try ASettings.Load;                  except end;
  // 2. Detector-Klassen-Listen aus den frisch geladenen Settings registrieren.
  try ASettings.RegisterToLeakyClasses; except end;
  // 3. IDE-Profile-Default (ide-fast) aktivieren. Standalone-EXE laeuft
  //    NICHT durch hier - sie liest [Rules] Profile direkt.
  try ASettings.UseIdeRuleSet;          except end;
  // 4. UI-Override: explizite Profile-Wahl gewinnt ueber INI.
  if AProfileOverride <> '' then
    try ASettings.Profile := AProfileOverride; except end;
  // 5. Profile-spezifische Detector-Thresholds anwenden.
  try ASettings.ApplyDetectorThresholds(AProjectPath); except end;
  // 6. Global flag fuer Detector-Discovery aus den Settings ableiten.
  try AutoDiscoverCustomClasses := ASettings.AutoDiscoverClasses; except end;
  // 7. Frische Discovery-Listen pro Run.
  try
    if Assigned(uSCAConsts.DiscoveredClasses) then
      uSCAConsts.DiscoveredClasses.Clear;
    if Assigned(uSCAConsts.DiscoveredStaticClasses) then
      uSCAConsts.DiscoveredStaticClasses.Clear;
  except end;
  // 8. Laufende Watch-Worker invalidieren.
  try
    if Assigned(GWatchMode) then
      GWatchMode.BumpGeneration;
  except end;
end;

end.
