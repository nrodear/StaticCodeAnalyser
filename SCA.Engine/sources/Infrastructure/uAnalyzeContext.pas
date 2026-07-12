unit uAnalyzeContext;

// ============================================================================
//  Phase 3 / Konzept_D2 — Singleton-Entkopplung (Foundation D.2.1)
// ============================================================================
//
// Buendelt den PER-SCAN-State, der heute in 5 globalen Singletons liegt
// (gAstFileCache/gFileTextCache/gSymbolRefIndex/gDfmRepoIndex/gDetectorTimings),
// in EIN Objekt. Erster, verhaltensneutraler Schritt: TStaticAnalyzer2.ParseLeaks
// erzeugt einen TAnalyzeContext und laesst ihn die per-Scan-Instanzen BESITZEN.
// Die Globals bleiben vorerst als Backward-Compat-Aliase bestehen (die ~140
// Detektoren lesen sie noch direkt) - das eigentliche Threading des Context
// durch alle Detektor-Signaturen (D.2.3-5) + Multi-Instance-Sicherheit ist ein
// spaeterer, separater Schritt (siehe Konzept_D2_SingletonEntkopplung.md).
//
// Eigentums-Regeln (WICHTIG - exakt das heutige ParseLeaks-Verhalten):
//   * AstFileCache / SymbolRefIndex / DfmRepoIndex: per-Scan, vom Context
//     BESESSEN -> in Destroy freigegeben (Reihenfolge: Indizes vor dem
//     AST-Cache, den sie referenzieren koennten).
//   * FileTextCache: nur REFERENZIERT. Lebt ABSICHTLICH ueber das Scan-Ende
//     hinaus (Post-Scan-Suppression + Fingerprint/ContextHash nutzen ihn);
//     wird vom naechsten Scan-Start GECLEART (Instanz bleibt stabil, seit
//     2026-07-04 kein FreeAndNil+Re-Create mehr - kein Use-after-free-
//     Fenster) und erst in der unit-finalization freigegeben.
//     Der Context fasst ihn NICHT an.
//   * DetectorTimings: gehoert dem AUFRUFER (CLI --time-detectors). Nur
//     referenziert, NICHT freigegeben.

interface

uses
  System.SysUtils, System.Classes,      // System.Classes: TStringList (LeakyClasses-Klon, TD-1 2c)
  System.Generics.Collections, System.Generics.Defaults,
  uSCAConsts,        // TSuppressionMarker (UnusedSuppression-Collection, 2026-07-05)
  uAstFileCache, uFileTextCache, uSymbolReferenceIndex, uDfmRepoIndex,
  uTypeIndex;

type
  // ==========================================================================
  //  TD-1 Thread-Safety (Inkrement 1, 2026-07-06) — Per-Scan-Skalar-Config
  // ==========================================================================
  // Snapshot der SKALAREN Scan-Konfiguration, die heute in Prozess-Globals in
  // uSCAConsts liegt (11 Schwellen + 3 Filter-Skalare + 2 Flags). Wird pro Scan
  // EINMAL aus den Globals gesnapshottet (ParseLeaks, direkt nach Context-
  // Create) und von den Scan-Pfaden aus IHREM Context gelesen - Voraussetzung
  // fuer parallele Scans, die sich nicht mehr denselben Prozess-Global teilen.
  // Byte-identisch, weil der Snapshot die Globals 1:1 kopiert solange (heute)
  // genau ein Scan zur Zeit laeuft. Die Globals BLEIBEN als Fallback fuer
  // AContext=nil (Tests/Single-File, s. Cfg*-Helfer unten).
  // Bewusst NUR Skalare: die Config-LISTEN (LeakyClasses/Excludes/... ) sind
  // AutoDiscover-mutiert und folgen in Inkrement 2.
  TEngineScalarConfig = record
    // --- 11 Detektor-Schwellen (Typen exakt wie die Globals in uSCAConsts) ---
    MaxBodyLines         : Integer;   // uLongMethod
    MaxStatements        : Integer;   // uLongMethod (sekundaere Schwelle)
    MaxNesting           : Integer;   // uDeepNesting
    MaxParams            : Integer;   // uLongParamList
    MaxCyclomatic        : Integer;   // uCyclomaticComplexity
    MaxLineLength        : Integer;   // uTooLongLine
    MaxCaseBranches      : Integer;   // uCaseStatementSize
    MaxLocalVars         : Integer;   // uUninitVar Hard-Cap
    MaxChildrenRecursive : Integer;   // uUninitVar Hard-Cap
    MinBlockLines        : Integer;   // uDuplicateBlock
    MaxFileBytes         : Integer;   // uStaticAnalyzer2 per-File-Size-Gate
    // --- 3 Filter-Skalare ---
    EnabledKinds         : TFindingKinds;      // Profile-Whitelist ([] = alle)
    MinSeverity          : TLeakSeverity;      // Severity-Schwelle
    MinConfidence        : TFindingConfidence; // Konfidenz-Schwelle (Read-Site
                                               // uConfidenceFilter = Inkrement 2)
    // --- 2 Flags ---
    AutoDiscover           : Boolean; // AutoDiscoverCustomClasses (Main-Loop-Gate)
    UIMaxDisplayedFindings : Integer; // UI-Grid-Cap (Read-Site UI = Inkrement 2)
  end;

  // Perf (2026-07-05): P1-strip-cache - EIN Cache-Eintrag fuer den Output
  // von TDetectorUtils.StripStringsAndComments (gestrippter Ganztext +
  // Char->Quellzeile-Map), pro FillCh-Variante (aktuell genau 2: '~' / ' ').
  TStripCacheEntry = record
    FillCh  : Char;
    Code    : string;
    LineFor : TArray<Integer>;
  end;

  TAnalyzeContext = class
  private
    // Perf (2026-07-05): P1-strip-cache - per-Scan-Cache fuer gestrippte
    // Ganztexte. Der Main-Loop verarbeitet Datei fuer Datei und
    // RunAllDetectors laesst alle Detektoren nacheinander ueber DIESELBE
    // Datei laufen - deshalb wird bewusst NUR die AKTUELLE Datei gehalten
    // (Key-Vergleich, bei Datei-Wechsel ersetzen). So kollabieren ~16
    // Ganztext-Strips pro Datei auf 1 pro FillCh-Variante, ohne dass bei
    // 12k Dateien gestrippte Texte (~= Dateigroesse) akkumulieren.
    // Lifecycle: Eintraege sind managed Types -> sterben mit dem Context.
    FStripFile    : string;                    // Datei der Cache-Eintraege
    FStripEntries : TArray<TStripCacheEntry>;  // praktisch max. 2 Slots
  public
    // TD-1 (2026-07-06): Per-Scan-Snapshot der skalaren Scan-Config (s.
    // TEngineScalarConfig). Value-Record - lebt/stirbt mit dem Context.
    // Wird von ParseLeaks DIREKT nach Create via SnapshotConfigFromGlobals aus
    // den uSCAConsts-Globals gefuellt; davor (und bei AContext=nil) lesen die
    // Cfg*-Helfer weiter das Prozess-Global.
    Config          : TEngineScalarConfig;
    // --- vom Context besessen (Destroy gibt frei) ---
    AstFileCache    : TAstFileCache;
    SymbolRefIndex  : TSymbolReferenceIndex;
    DfmRepoIndex    : TDfmRepoIndex;
    // Track C (Konzept_StrukturellePhase): Cross-Unit-Typ-Index (Typ-Kind +
    // Klassen-Elternkette). Additiv/inert - noch von keinem Detektor gelesen
    // (nil-Fallback via CtxTypeIndex). Wie SymbolRefIndex vom Context BESESSEN
    // -> in Destroy freigegeben (Indizes vor dem AstFileCache, den sie nutzen).
    TypeIndex       : TTypeIndex;
    // TD-1 Inkrement 2c (2026-07-06): per-Scan-Kopie der scan-zeit-MUTIERTEN
    // Config-Liste LeakyClasses (uSCAConsts-Global). AutoDiscovery haengt die
    // waehrend des Scans entdeckten Klassen an DIESE Instanz statt an den
    // Prozess-Global -> parallele Scans teilen sich die Liste nicht mehr.
    // Die List-Settings MUESSEN 1:1 die des Globals sein (CaseSensitive=False/
    // Sorted/dupIgnore), sonst weichen IndexOf/Membership ab = Byte-Drift.
    // BESESSEN (Create/Destroy); gefuellt in ParseLeaks direkt nach
    // SnapshotConfigFromGlobals aus dem Global-Baseline. Die Scan-Leser
    // (uLeakDetector2/uFieldLeak/uMissingFinally ueber IsLeakyType) lesen via
    // CtxLeakyClasses mit Global-Fallback bei AContext=nil (Tests/Single-File).
    LeakyClasses    : TStringList;
    // UnusedSuppression (Audit_CodeReview #2, 2026-07-05): per-Scan-Collection
    // der '// noinspection'-Marker, eingesammelt im ParseLeaks-Main-Loop
    // solange der Dateitext noch heiss im FileTextCache liegt. Key = Marker-
    // HOST-Pfad (fuer .dfm-Findings die zugehoerige .pas), case-insensitiv
    // (Windows-Pfade). Dateien ohne Marker landen NICHT im Dictionary.
    // BESESSEN (Create/Destroy); ParseLeaks uebernimmt das Dictionary am
    // Scan-Ende per Ownership-Transfer (Feld -> nil) fuer die Post-Scan-
    // Suppression-Phase - Destroy ist dann nil-sicher.
    SuppressionMarkers : TObjectDictionary<string, TList<TSuppressionMarker>>;
    // --- nur referenziert (Destroy fasst sie NICHT an) ---
    FileTextCache   : TFileTextCache;
    DetectorTimings : TDictionary<string, TPair<Int64, Integer>>;

    // Perf (2026-07-05): P1-strip-cache - Lookup/Store fuer
    // TDetectorUtils.StripStringsAndCommentsCached. TryGet liefert nur bei
    // exaktem Key-Match (FileName UND FillCh) True; Put verwirft bei
    // Datei-Wechsel alle alten Eintraege (Speicher-Deckel, s.o.).
    function  TryGetStrippedText(const FileName: string; FillCh: Char;
      out Code: string; out LineFor: TArray<Integer>): Boolean;
    procedure PutStrippedText(const FileName: string; FillCh: Char;
      const Code: string; const LineFor: TArray<Integer>);

    // TD-1 (2026-07-06): Kopiert die skalare Scan-Config 1:1 aus den uSCAConsts-
    // Prozess-Globals in Config. Aufruf in ParseLeaks DIREKT nach Create - zu
    // dem Zeitpunkt halten die Globals bereits die fuer diesen Scan gueltige
    // Config (ApplyConfig/SetupForRun lief davor), damit Config == Globals =
    // beweisbar byte-identisches Verhalten.
    procedure SnapshotConfigFromGlobals;

    constructor Create;
    destructor Destroy; override;
  end;

// Helfer fuer die Detektor-Migration (D.2.3): liefert den per-Scan-FileText-
// Cache aus dem Context, oder nil wenn kein Context da ist (Tests/Single-File
// -> AcquireLines faellt dann auf das Prozess-Global zurueck). So bleibt der
// Detektor-Body ein Einzeiler: AcquireLines(FileName, Owned, CtxFileTextCache(AContext)).
function CtxFileTextCache(AContext: TAnalyzeContext): TFileTextCache;
// Analog fuer die Direkt-Global-Leser (D.2.3 Schritt 2): nil-sicherer Zugriff auf
// die per-Scan-Indizes. nil -> Detektor verhaelt sich wie Single-File-Modus
// (kein Cross-Unit-Index), exakt wie heute wenn das Global nil ist.
function CtxSymbolRefIndex(AContext: TAnalyzeContext): TSymbolReferenceIndex;
function CtxDfmRepoIndex(AContext: TAnalyzeContext): TDfmRepoIndex;
function CtxAstFileCache(AContext: TAnalyzeContext): TAstFileCache;
// Track C: Cross-Unit-Typ-Index. nil -> Detektor faellt auf Single-Unit-
// Verhalten zurueck (kein Cross-Unit-Typ-Wissen), exakt wie heute.
function CtxTypeIndex(AContext: TAnalyzeContext): TTypeIndex;

// TD-1 Inkrement 2c (2026-07-06): LeakyClasses-Leser mit Context-oder-Global-
// Fallback. ABWEICHEND von den Ctx*-Index-Helfern oben faellt dieser NICHT auf
// nil zurueck, sondern auf den uSCAConsts-Global: die scan-freien Aufrufer
// (Tests/Single-File, AContext=nil) erwarten die global konfigurierte Liste,
// exakt wie IsLeakyType sie bisher direkt gelesen hat. Innerhalb eines Scans
// liefert er Ctx.LeakyClasses (Baseline + AutoDiscovery-Adds) -> byte-identisch.
function CtxLeakyClasses(AContext: TAnalyzeContext): TStringList;

// TD-1 (2026-07-06): Skalar-Config-Leser mit Context-oder-Global-Fallback.
// Jede Funktion liefert den Context-Wert wenn AContext<>nil, sonst das
// uSCAConsts-Prozess-Global. Da SnapshotConfigFromGlobals Config==Globals
// setzt (single-scan) liefern beide Pfade denselben Wert -> byte-identisch.
// AContext=nil (Tests/Single-File) faellt exakt auf das heutige Global-
// Verhalten zurueck. Explizit pro Wert statt generisch = am sichersten.
function CfgMaxBodyLines(AContext: TAnalyzeContext): Integer;
function CfgMaxStatements(AContext: TAnalyzeContext): Integer;
function CfgMaxNesting(AContext: TAnalyzeContext): Integer;
function CfgMaxParams(AContext: TAnalyzeContext): Integer;
function CfgMaxCyclomatic(AContext: TAnalyzeContext): Integer;
function CfgMaxLineLength(AContext: TAnalyzeContext): Integer;
function CfgMaxCaseBranches(AContext: TAnalyzeContext): Integer;
function CfgMaxLocalVars(AContext: TAnalyzeContext): Integer;
function CfgMaxChildrenRecursive(AContext: TAnalyzeContext): Integer;
function CfgMinBlockLines(AContext: TAnalyzeContext): Integer;
function CfgMaxFileBytes(AContext: TAnalyzeContext): Integer;
function CfgEnabledKinds(AContext: TAnalyzeContext): TFindingKinds;
function CfgMinSeverity(AContext: TAnalyzeContext): TLeakSeverity;
function CfgMinConfidence(AContext: TAnalyzeContext): TFindingConfidence;
function CfgAutoDiscover(AContext: TAnalyzeContext): Boolean;
function CfgUIMaxDisplayedFindings(AContext: TAnalyzeContext): Integer;

implementation

function CtxFileTextCache(AContext: TAnalyzeContext): TFileTextCache;
begin
  if AContext <> nil then
    Result := AContext.FileTextCache
  else
    Result := nil;
end;

function CtxSymbolRefIndex(AContext: TAnalyzeContext): TSymbolReferenceIndex;
begin
  if AContext <> nil then
    Result := AContext.SymbolRefIndex
  else
    Result := nil;
end;

function CtxDfmRepoIndex(AContext: TAnalyzeContext): TDfmRepoIndex;
begin
  if AContext <> nil then
    Result := AContext.DfmRepoIndex
  else
    Result := nil;
end;

function CtxAstFileCache(AContext: TAnalyzeContext): TAstFileCache;
begin
  if AContext <> nil then
    Result := AContext.AstFileCache
  else
    Result := nil;
end;

function CtxTypeIndex(AContext: TAnalyzeContext): TTypeIndex;
begin
  if AContext <> nil then
    Result := AContext.TypeIndex
  else
    Result := nil;
end;

function CtxLeakyClasses(AContext: TAnalyzeContext): TStringList;
begin
  // Global-Fallback (nicht nil), damit AContext=nil das bisherige Verhalten von
  // IsLeakyType erhaelt (liest direkt uSCAConsts.LeakyClasses). uSCAConsts ist
  // im interface-uses -> der Global ist hier sichtbar.
  if (AContext <> nil) and (AContext.LeakyClasses <> nil) then
    Result := AContext.LeakyClasses
  else
    Result := uSCAConsts.LeakyClasses;
end;

// --- TD-1 Skalar-Config-Leser (Context-oder-Global-Fallback) ---------------

function CfgMaxBodyLines(AContext: TAnalyzeContext): Integer;
begin
  if AContext <> nil then Result := AContext.Config.MaxBodyLines
                     else Result := uSCAConsts.DetectorMaxBodyLines;
end;

function CfgMaxStatements(AContext: TAnalyzeContext): Integer;
begin
  if AContext <> nil then Result := AContext.Config.MaxStatements
                     else Result := uSCAConsts.DetectorMaxStatements;
end;

function CfgMaxNesting(AContext: TAnalyzeContext): Integer;
begin
  if AContext <> nil then Result := AContext.Config.MaxNesting
                     else Result := uSCAConsts.DetectorMaxNesting;
end;

function CfgMaxParams(AContext: TAnalyzeContext): Integer;
begin
  if AContext <> nil then Result := AContext.Config.MaxParams
                     else Result := uSCAConsts.DetectorMaxParams;
end;

function CfgMaxCyclomatic(AContext: TAnalyzeContext): Integer;
begin
  if AContext <> nil then Result := AContext.Config.MaxCyclomatic
                     else Result := uSCAConsts.DetectorMaxCyclomatic;
end;

function CfgMaxLineLength(AContext: TAnalyzeContext): Integer;
begin
  if AContext <> nil then Result := AContext.Config.MaxLineLength
                     else Result := uSCAConsts.DetectorMaxLineLength;
end;

function CfgMaxCaseBranches(AContext: TAnalyzeContext): Integer;
begin
  if AContext <> nil then Result := AContext.Config.MaxCaseBranches
                     else Result := uSCAConsts.DetectorMaxCaseBranches;
end;

function CfgMaxLocalVars(AContext: TAnalyzeContext): Integer;
begin
  if AContext <> nil then Result := AContext.Config.MaxLocalVars
                     else Result := uSCAConsts.DetectorMaxLocalVars;
end;

function CfgMaxChildrenRecursive(AContext: TAnalyzeContext): Integer;
begin
  if AContext <> nil then Result := AContext.Config.MaxChildrenRecursive
                     else Result := uSCAConsts.DetectorMaxChildrenRecursive;
end;

function CfgMinBlockLines(AContext: TAnalyzeContext): Integer;
begin
  if AContext <> nil then Result := AContext.Config.MinBlockLines
                     else Result := uSCAConsts.DetectorMinBlockLines;
end;

function CfgMaxFileBytes(AContext: TAnalyzeContext): Integer;
begin
  if AContext <> nil then Result := AContext.Config.MaxFileBytes
                     else Result := uSCAConsts.DetectorMaxFileBytes;
end;

function CfgEnabledKinds(AContext: TAnalyzeContext): TFindingKinds;
begin
  if AContext <> nil then Result := AContext.Config.EnabledKinds
                     else Result := uSCAConsts.DetectorEnabledKinds;
end;

function CfgMinSeverity(AContext: TAnalyzeContext): TLeakSeverity;
begin
  if AContext <> nil then Result := AContext.Config.MinSeverity
                     else Result := uSCAConsts.DetectorMinSeverity;
end;

function CfgMinConfidence(AContext: TAnalyzeContext): TFindingConfidence;
begin
  if AContext <> nil then Result := AContext.Config.MinConfidence
                     else Result := uSCAConsts.FindingMinConfidence;
end;

function CfgAutoDiscover(AContext: TAnalyzeContext): Boolean;
begin
  if AContext <> nil then Result := AContext.Config.AutoDiscover
                     else Result := uSCAConsts.AutoDiscoverCustomClasses;
end;

function CfgUIMaxDisplayedFindings(AContext: TAnalyzeContext): Integer;
begin
  if AContext <> nil then Result := AContext.Config.UIMaxDisplayedFindings
                     else Result := uSCAConsts.UIMaxDisplayedFindings;
end;

function TAnalyzeContext.TryGetStrippedText(const FileName: string;
  FillCh: Char; out Code: string; out LineFor: TArray<Integer>): Boolean;
var
  i : Integer;
begin
  Result := False;
  // Anderer Dateiname -> Miss (der Aufrufer rechnet und ruft Put, das die
  // alten Eintraege ersetzt). Exakter String-Vergleich reicht: innerhalb
  // eines Scans bekommt jeder Detektor denselben FileName-String.
  if FStripFile <> FileName then Exit;
  for i := 0 to High(FStripEntries) do
    if FStripEntries[i].FillCh = FillCh then
    begin
      Code    := FStripEntries[i].Code;
      LineFor := FStripEntries[i].LineFor;
      Exit(True);
    end;
end;

procedure TAnalyzeContext.PutStrippedText(const FileName: string;
  FillCh: Char; const Code: string; const LineFor: TArray<Integer>);
var
  i, n : Integer;
begin
  if FStripFile <> FileName then
  begin
    // Datei-Wechsel: NUR die aktuelle Datei halten (siehe Klassen-Kommentar).
    FStripEntries := nil;
    FStripFile    := FileName;
  end;
  // Vorhandenen FillCh-Slot ueberschreiben (defensiv - Aufrufer fragt vor
  // dem Put via TryGet, praktisch kommt der Fall also nicht vor).
  for i := 0 to High(FStripEntries) do
    if FStripEntries[i].FillCh = FillCh then
    begin
      FStripEntries[i].Code    := Code;
      FStripEntries[i].LineFor := LineFor;
      Exit;
    end;
  n := Length(FStripEntries);
  SetLength(FStripEntries, n + 1);
  FStripEntries[n].FillCh  := FillCh;
  FStripEntries[n].Code    := Code;
  FStripEntries[n].LineFor := LineFor;
end;

procedure TAnalyzeContext.SnapshotConfigFromGlobals;
// TD-1 (2026-07-06): 1:1-Kopie ALLER 16 Skalar-Config-Globals aus uSCAConsts.
// Reihenfolge/Feldnamen spiegeln TEngineScalarConfig. Aufruf-Zeitpunkt (direkt
// nach Create in ParseLeaks) garantiert Config == Globals -> byte-identisch.
begin
  Config.MaxBodyLines          := uSCAConsts.DetectorMaxBodyLines;
  Config.MaxStatements         := uSCAConsts.DetectorMaxStatements;
  Config.MaxNesting            := uSCAConsts.DetectorMaxNesting;
  Config.MaxParams             := uSCAConsts.DetectorMaxParams;
  Config.MaxCyclomatic         := uSCAConsts.DetectorMaxCyclomatic;
  Config.MaxLineLength         := uSCAConsts.DetectorMaxLineLength;
  Config.MaxCaseBranches       := uSCAConsts.DetectorMaxCaseBranches;
  Config.MaxLocalVars          := uSCAConsts.DetectorMaxLocalVars;
  Config.MaxChildrenRecursive  := uSCAConsts.DetectorMaxChildrenRecursive;
  Config.MinBlockLines         := uSCAConsts.DetectorMinBlockLines;
  Config.MaxFileBytes          := uSCAConsts.DetectorMaxFileBytes;
  Config.EnabledKinds          := uSCAConsts.DetectorEnabledKinds;
  Config.MinSeverity           := uSCAConsts.DetectorMinSeverity;
  Config.MinConfidence         := uSCAConsts.FindingMinConfidence;
  Config.AutoDiscover          := uSCAConsts.AutoDiscoverCustomClasses;
  Config.UIMaxDisplayedFindings := uSCAConsts.UIMaxDisplayedFindings;
end;

constructor TAnalyzeContext.Create;
begin
  inherited Create;
  // UnusedSuppression (Audit #2, 2026-07-05): Marker-Collection sofort
  // anlegen - der Main-Loop fuellt sie pro Datei (TSuppression.
  // CollectMarkersForScan). doOwnsValues: die TList<TSuppressionMarker>-
  // Werte sterben mit dem Dictionary. TIStringComparer.Ordinal: Pfad-Keys
  // case-insensitiv, damit z.B. ChangeFileExt-abgeleitete .dfm-Host-Pfade
  // nicht an Gross/Klein-Drift vorbeilaufen.
  SuppressionMarkers := TObjectDictionary<string, TList<TSuppressionMarker>>
    .Create([doOwnsValues], TIStringComparer.Ordinal);
  // TD-1 Inkrement 2c (2026-07-06): LeakyClasses-Klon. Settings MUESSEN 1:1
  // die des uSCAConsts-Globals sein (CreateEngineConfigLists) - sonst weichen
  // IndexOf/Add-Semantik (Case-Fold + Sortierung + Dup-Handling) ab und die
  // Membership-Pruefung driftet vom bisherigen Global-Verhalten weg.
  LeakyClasses := TStringList.Create;
  LeakyClasses.CaseSensitive := False;
  LeakyClasses.Sorted        := True;
  LeakyClasses.Duplicates    := dupIgnore;
end;

destructor TAnalyzeContext.Destroy;
begin
  // Reihenfolge wie bisher in ParseLeaks (Indizes vor AST-Cache).
  // FileTextCache + DetectorTimings bewusst NICHT freigeben.
  // SuppressionMarkers ist nil-sicher, wenn ParseLeaks das Dictionary per
  // Ownership-Transfer fuer die Post-Scan-Suppression uebernommen hat.
  FreeAndNil(SuppressionMarkers);
  // TD-1 Inkrement 2c: der LeakyClasses-Klon gehoert dem Context. Kein Bezug
  // zur Index/AST-Cache-Reihenfolge (er referenziert keine der Instanzen).
  FreeAndNil(LeakyClasses);
  FreeAndNil(DfmRepoIndex);
  FreeAndNil(SymbolRefIndex);
  // Track C: TypeIndex vor dem AstFileCache freigeben (nutzt ihn in Build).
  FreeAndNil(TypeIndex);
  FreeAndNil(AstFileCache);
  inherited;
end;

end.
