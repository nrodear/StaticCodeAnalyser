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
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults,
  uSCAConsts,        // TSuppressionMarker (UnusedSuppression-Collection, 2026-07-05)
  uAstFileCache, uFileTextCache, uSymbolReferenceIndex, uDfmRepoIndex;

type
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
    // --- vom Context besessen (Destroy gibt frei) ---
    AstFileCache    : TAstFileCache;
    SymbolRefIndex  : TSymbolReferenceIndex;
    DfmRepoIndex    : TDfmRepoIndex;
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
end;

destructor TAnalyzeContext.Destroy;
begin
  // Reihenfolge wie bisher in ParseLeaks (Indizes vor AST-Cache).
  // FileTextCache + DetectorTimings bewusst NICHT freigeben.
  // SuppressionMarkers ist nil-sicher, wenn ParseLeaks das Dictionary per
  // Ownership-Transfer fuer die Post-Scan-Suppression uebernommen hat.
  FreeAndNil(SuppressionMarkers);
  FreeAndNil(DfmRepoIndex);
  FreeAndNil(SymbolRefIndex);
  FreeAndNil(AstFileCache);
  inherited;
end;

end.
