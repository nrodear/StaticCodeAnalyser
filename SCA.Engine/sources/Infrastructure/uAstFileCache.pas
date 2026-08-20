unit uAstFileCache;

// Repo-Scan-weiter Cache fuer geparste TAstNode-Trees.
//
// Hintergrund (tools/perf_analyse.md, Hot-Spot 🅐):
// Bei AnalyzeLeaksRecursive wird heute jede .pas drei mal geparst:
//   1. gDfmRepoIndex.Build   (Pre-Pass)
//   2. gSymbolRefIndex.Build (Pre-Pass)
//   3. Main-Loop (eigentliche Analyse)
//
// Mit diesem Cache wird pro Pfad genau einmal geparst. Der Cache lebt
// nur waehrend eines AnalyzeLeaksRecursive-Laufs - danach wird er von
// TStaticAnalyzer2 freigegeben.
//
// Ownership-Modell:
//   * Acquire(Path) liefert Root oder nil bei Parse-Fehler.
//   * Cache BESITZT die TAstNode-Instanzen - Caller darf sie NICHT
//     freigeben.
//   * Nach dem Main-Loop ruft TStaticAnalyzer2 Evict(Path), um Memory
//     fuer schon-fertige Files freizugeben. Ohne Evict bleiben alle
//     ASTs bis Cache.Free im Heap.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  System.SyncObjs,   // Perf Stufe 2 (2026-07-25): FLock fuer Parallel-Worker
  uAstNode, uParser2,
  uCrashDiag;        // auswertbarer Text statt roher RTL-Meldung (s. Acquire)

type
  TAstFileCache = class
  private
    // Perf Stufe 2 (2026-07-25): serialisiert FCache/FFailed UND die eine
    // FParser-Instanz (Blocker G2 aus Konzept_Performance25). Im Parallel-
    // Modus rufen Worker-Threads Acquire/Evict/GetFailMessage gleichzeitig;
    // nach den Pre-Index-Passes sind Acquire-Aufrufe praktisch immer Hits,
    // ein Miss-Parse unter dem Lock serialisiert also nur den Ausnahmefall.
    // Die zurueckgegebenen TAstNode-Baeume brauchen keinen Schutz: pro Datei
    // arbeitet genau EIN Worker, und Evict ruft nur der Besitzer-Worker
    // seiner eigenen Datei. Seriell ist der Lock unkontent (kostenneutral).
    FLock   : TCriticalSection;
    FParser : TParser2;
    // Key = LowerCase(ExpandFileName(Path)) - normalisiert damit
    // 'foo.pas', '.\foo.pas', 'C:\...\foo.pas' alle denselben Cache-Slot
    // teilen.
    FCache  : TObjectDictionary<string, TAstNode>;
    // Pfade die schon Parse-Fehler hatten - vermeidet Retry-Loops bei
    // dauerhaft kaputten Files. Value = Exception-Message fuer
    // Diagnose-Zwecke (siehe GetFailMessage).
    FFailed : TDictionary<string, string>;
    function Key(const FileName: string): string;
  public
    constructor Create;
    destructor Destroy; override;

    // Liefert geparstes Root oder nil bei Parse-Fehler. Cache besitzt
    // das Objekt - NICHT Free aufrufen.
    function Acquire(const FileName: string): TAstNode;

    // Wenn der letzte Acquire(FileName) nil zurueckgab, liefert das die
    // konkrete Parser-Exception-Message. Leer wenn kein Fehler vermerkt.
    function GetFailMessage(const FileName: string): string;

    // Cache-Eintrag fuer FileName aus dem Speicher entfernen (das AST
    // wird sofort freigegeben). Praktisch wenn der Main-Loop mit dem
    // File durch ist - so wird der Memory-Peak nicht kumulativ.
    procedure Evict(const FileName: string);

    procedure Clear;

    // Anzahl gecachter ASTs - praktisch fuer Diagnostik.
    function Count: Integer;
  end;

implementation

// noinspection-file CanBeClassMethod, CanBeStrictPrivate, ExceptionTooGeneral, ExceptOnException, FreeWithoutNil, NilComparison, PublicMemberWithoutDoc, TooLongLine, UnsortedUses, UnusedPublicMember
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

constructor TAstFileCache.Create;
begin
  inherited;
  FLock   := TCriticalSection.Create;   // Perf Stufe 2 (2026-07-25)
  FParser := TParser2.Create;
  // doOwnsValues: das Dictionary freed die TAstNode-Instanzen bei
  // Remove/Clear/Destroy.
  FCache  := TObjectDictionary<string, TAstNode>.Create([doOwnsValues]);
  FFailed := TDictionary<string, string>.Create;
end;

destructor TAstFileCache.Destroy;
begin
  FCache.Free;
  FFailed.Free;
  FParser.Free;
  FLock.Free;
  inherited;
end;

function TAstFileCache.Key(const FileName: string): string;
begin
  Result := LowerCase(ExpandFileName(FileName));
end;

function TAstFileCache.Acquire(const FileName: string): TAstNode;
var
  K : string;
  Existing : TAstNode;
begin
  Result := nil;
  K := Key(FileName);
  // Perf Stufe 2 (2026-07-25): kompletter Acquire (inkl. Miss-Parse mit der
  // einen FParser-Instanz) unter FLock - s. Klassen-Kommentar. Nach den
  // Pre-Index-Passes ist der Miss-Parse der seltene Ausnahmefall.
  FLock.Enter;
  try
    if FFailed.ContainsKey(K) then Exit;
    if FCache.TryGetValue(K, Existing) then Exit(Existing);
    // Erst-Parse - bei Fehler in Fail-Liste merken, damit kein Retry-Loop.
    // Die Exception-Message wird festgehalten, damit der Caller im
    // Cache-Pfad ueber GetFailMessage einen sinnvollen Log-Eintrag schreiben
    // kann (im Fallback-Pfad faengt der Caller die Exception direkt ab).
    try
      Result := FParser.ParseFile(FileName);
    except
      // Ein erschoepfter Stapel DARF NICHT verschluckt werden (2026-08-04):
      // die RTL
      // stellt die Guard-Page des Stapels nach einem abgefangenen Overflow
      // NICHT wieder her (System.pas/System.SysUtils.pas nachgelesen - kein
      // Gegenstueck zu _resetstkoflw). Ein 'weiter wie bisher' laeuft also
      // auf ungeschuetztem Stapel; der naechste tiefe Abstieg schreibt
      // wortlos in fremden Speicher. Der Korpus-Absturz vom 2026-08-04
      // (RIP UND RSP zerstoert, Schreibziel im schreibgeschuetzten .text)
      // ist exakt das Schadensbild solcher stillen Stapel-Korruption.
      // Durchreichen -> der Top-Level-Handler beendet den Scan geordnet
      // als 'Analyseabbruch' mit Exit-Code statt still weiterzulaufen.
      on EStackExhausted do raise;
      on E: Exception do
      begin
        // NICHT E.Message allein: das war 2026-08-04 der Grund, warum eine
        // Zugriffsverletzung auf genau einer Korpusdatei nicht auswertbar
        // war. Die RTL-Meldung nennt weder die Exception-Klasse noch eine
        // gegen eine Map-Datei aufloesbare Adresse, und ihre Modulangabe
        // kann schlicht falsch sein (s. Unit-Kopf uCrashDiag). Dieser
        // Fangpunkt ist der einzige Ort, an dem ein Parser-Absturz im
        // Cache-Pfad ueberhaupt sichtbar wird.
        FFailed.AddOrSetValue(K, DescribeException(E));
        Exit(nil);
      end;
    end;
    if Result <> nil then
      FCache.Add(K, Result)
    else
      FFailed.AddOrSetValue(K, 'Parser lieferte kein Ergebnis');
  finally
    FLock.Leave;
  end;
end;

function TAstFileCache.GetFailMessage(const FileName: string): string;
begin
  FLock.Enter;   // Perf Stufe 2 (2026-07-25)
  try
    if not FFailed.TryGetValue(Key(FileName), Result) then
      Result := '';
  finally
    FLock.Leave;
  end;
end;

procedure TAstFileCache.Evict(const FileName: string);
var
  K : string;
begin
  K := Key(FileName);
  FLock.Enter;   // Perf Stufe 2 (2026-07-25)
  try
    FCache.Remove(K);
  finally
    FLock.Leave;
  end;
  // Failed-Eintraege behalten - sonst koennte ein dauerhaft kaputter
  // Path mehrfach Re-Parsed werden.
end;

procedure TAstFileCache.Clear;
begin
  FLock.Enter;   // Perf Stufe 2 (2026-07-25)
  try
    FCache.Clear;
    FFailed.Clear;
  finally
    FLock.Leave;
  end;
end;

function TAstFileCache.Count: Integer;
begin
  FLock.Enter;   // Perf Stufe 2 (2026-07-25)
  try
    Result := FCache.Count;
  finally
    FLock.Leave;
  end;
end;

initialization

finalization

end.
