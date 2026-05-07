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

var
  GLiveAnalyserFrame: Pointer = nil;

implementation

end.
