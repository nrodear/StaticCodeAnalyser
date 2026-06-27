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
  uAstNode, uParser2;

type
  TAstFileCache = class
  private
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
  if FFailed.ContainsKey(K) then Exit;
  if FCache.TryGetValue(K, Existing) then Exit(Existing);
  // Erst-Parse - bei Fehler in Fail-Liste merken, damit kein Retry-Loop.
  // Die Exception-Message wird festgehalten, damit der Caller im
  // Cache-Pfad ueber GetFailMessage einen sinnvollen Log-Eintrag schreiben
  // kann (im Fallback-Pfad faengt der Caller die Exception direkt ab).
  try
    Result := FParser.ParseFile(FileName);
  except
    on E: Exception do
    begin
      FFailed.AddOrSetValue(K, E.Message);
      Exit(nil);
    end;
  end;
  if Result <> nil then
    FCache.Add(K, Result)
  else
    FFailed.AddOrSetValue(K, 'Parser lieferte kein Ergebnis');
end;

function TAstFileCache.GetFailMessage(const FileName: string): string;
begin
  if not FFailed.TryGetValue(Key(FileName), Result) then
    Result := '';
end;

procedure TAstFileCache.Evict(const FileName: string);
var
  K : string;
begin
  K := Key(FileName);
  FCache.Remove(K);
  // Failed-Eintraege behalten - sonst koennte ein dauerhaft kaputter
  // Path mehrfach Re-Parsed werden.
end;

procedure TAstFileCache.Clear;
begin
  FCache.Clear;
  FFailed.Clear;
end;

function TAstFileCache.Count: Integer;
begin
  Result := FCache.Count;
end;

initialization

finalization

end.
