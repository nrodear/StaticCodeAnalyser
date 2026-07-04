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
  System.SysUtils, System.Generics.Collections,
  uAstFileCache, uFileTextCache, uSymbolReferenceIndex, uDfmRepoIndex;

type
  TAnalyzeContext = class
  public
    // --- vom Context besessen (Destroy gibt frei) ---
    AstFileCache    : TAstFileCache;
    SymbolRefIndex  : TSymbolReferenceIndex;
    DfmRepoIndex    : TDfmRepoIndex;
    // --- nur referenziert (Destroy fasst sie NICHT an) ---
    FileTextCache   : TFileTextCache;
    DetectorTimings : TDictionary<string, TPair<Int64, Integer>>;

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

destructor TAnalyzeContext.Destroy;
begin
  // Reihenfolge wie bisher in ParseLeaks (Indizes vor AST-Cache).
  // FileTextCache + DetectorTimings bewusst NICHT freigeben.
  FreeAndNil(DfmRepoIndex);
  FreeAndNil(SymbolRefIndex);
  FreeAndNil(AstFileCache);
  inherited;
end;

end.
