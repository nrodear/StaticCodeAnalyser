unit uRegExMatches;

interface

uses
  System.StrUtils, System.Classes, System.SysUtils, System.Generics.Collections,
  System.RegularExpressions,
  uMethodd12;

type
  TRegExMatches = class

    class function GetName(const line: string): string;
    class function IsCommentOf(const line: string;
      isStart: boolean = true): boolean;
    class function MatchString(searchStr: string; const line: string)
      : boolean; static;

    class function MatchOnlyString(searchStr: string; const line: string;
      out foundMatch: string): boolean; static;
    class function GetCodeOnly(const line: string): string;

    // Thread-sicherer Regex-Bezug fuer Detektoren mit EXPLIZITEN Optionen:
    // wie Cached, aber die TRegExOptions wandern mit in den Cache-Key und
    // in TRegEx.Create. Public, weil die Detector-Units ihre frueheren
    // unit-var-Caches hierher verlagert haben (2026-08-19, s. Cache-Kommentar).
    class function CachedEx(const pattern: string;
      AOptions: TRegExOptions): TRegEx; static;

  private
    class var FCache: TDictionary<string, TRegEx>;
    class function Cached(const pattern: string): TRegEx; static;
  end;

implementation

// noinspection-file ConcatToFormat, LocalConstantName, MissingUnitHeader, RedundantBoolean, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

// ---------------------------------------------------------------------------
// Regex-Cache: kompilierte TRegEx-Objekte werden einmalig erstellt und
// wiederverwendet. Spart ~90% der Kompilierzeit bei grossen Projekten.
//
// Thread-safety: Die Lazy-Init-Variante (`if not Assigned(FCache) then ...`)
// war race-anfaellig, sobald WatchMode-Worker und Main-Analyzer parallel
// laufen. Jetzt wird FCache schon im `initialization`-Block angelegt, und
// TryGetValue+Add sind durch TMonitor auf FCache serialisiert.
//
// Perf Stufe 2 (2026-07-25): der Cache-Key traegt zusaetzlich die Thread-ID.
// Grund: TRegEx ist ein Record um EINE geteilte TPerlRegEx-Instanz - ein
// gleichzeitiges Match() zweier Threads auf DEMSELBEN kompilierten Objekt
// mutiert dessen Subject/Offset-State (Race). Mit Thread-ID im Key bekommt
// jeder Worker-Thread seine eigene kompilierte Instanz pro Pattern; das
// Match-ERGEBNIS ist identisch, nur die Kompilierung faellt einmal pro
// Thread an. Seriell (ein Thread) verhaelt sich der Cache exakt wie vorher.
// OBERGRENZE (2026-08-01, T3-Backlog): die Annahme "Pool-Threads werden
// wiederverwendet" gilt fuer den CLI-Lauf, aber NICHT im IDE-Plugin. Dort
// startet TBulkScanWorker je Scan neue Threads; deren IDs kommen nie
// wieder, ihre Eintraege bleiben aber im Cache liegen. Ueber eine lange
// IDE-Sitzung waechst er unbegrenzt - jeder Eintrag haelt eine kompilierte
// TPerlRegEx-Instanz fest.
// Behandlung bewusst simpel: beim Ueberschreiten wird der GESAMTE Cache
// geleert statt eine LRU-Verwaltung einzubauen. Die Patternmenge ist klein
// und fest; nach dem Leeren kompiliert der naechste Zugriff neu, das ist
// einmalig und unmessbar gegenueber dem Scan. Eine Eviction einzelner
// Threads waere nur mit einer Liste lebender Thread-IDs korrekt - deutlich
// mehr Mechanik fuer denselben Effekt.
// CachedEx (2026-08-19): 11 Detector-Units hielten ihre kompilierten TRegEx
// in unit-vars (CachedReX + Init-Flag) - EINE geteilte TPerlRegEx-Instanz
// ueber alle Threads. Ein paralleles Match() zweier Threads mutierte deren
// Subject/Offsets (Beleg: 13 parallele Laeufe = 13 verschiedene SARIF-
// Hashes). Diese Units beziehen ihre Patterns jetzt hier ueber CachedEx;
// die TRegExOptions gehen mit in den Cache-Key, weil dasselbe Pattern mit
// anderen Optionen eine ANDERS kompilierte Engine ist.
// ---------------------------------------------------------------------------
const
  // ~50 Patterns (inkl. der 2026-08-19 zugezogenen Detector-Patterns)
  // x ~25 gleichzeitig gehaltene Thread-Generationen.
  CMaxCachedRegex = 1280;

class function TRegExMatches.CachedEx(const pattern: string;
  AOptions: TRegExOptions): TRegEx;
var
  CacheKey: string;
  Opt: TRegExOption;
  OptMask: Integer;
begin
  // Optionen als Ordinal-Bitmaske in den Key: '2|' = [roIgnoreCase],
  // '128|' = [roNotEmpty] (Default des Ein-Arg-TRegEx.Create), usw.
  OptMask := 0;
  for Opt := Low(TRegExOption) to High(TRegExOption) do
  begin
    if Opt in AOptions then
    begin
      OptMask := OptMask or (1 shl Ord(Opt));
    end;
  end;
  CacheKey := IntToStr(TThread.Current.ThreadID) + '|' + IntToStr(OptMask) +
    '|' + pattern;
  TMonitor.Enter(FCache);
  try
    if not FCache.TryGetValue(CacheKey, Result) then
    begin
      if FCache.Count >= CMaxCachedRegex then
        FCache.Clear;
      Result := TRegEx.Create(pattern, AOptions);
      FCache.Add(CacheKey, Result);
    end;
  finally
    TMonitor.Exit(FCache);
  end;
end;

class function TRegExMatches.Cached(const pattern: string): TRegEx;
begin
  // Historisches Verhalten der Helfer dieser Unit: [roIgnoreCase] ohne
  // roNotEmpty - unveraendert beibehalten (Byte-Identitaet der Matches).
  Result := CachedEx(pattern, [roIgnoreCase]);
end;

class function TRegExMatches.IsCommentOf(const line: string;
  isStart: boolean = true): boolean;
const
  regStart = '(?:\{\*|\(\*)';  // nur Block-Kommentar-Start, kein //
  regEnd = '\*\)|\*\}';
var
  match: TMatch;
  regPattern: string;
begin
  regPattern := regEnd;
  if isStart then
    regPattern := regStart;
  match := Cached(regPattern).Match(line.ToLower);
  Result := match.Success;
end;

class function TRegExMatches.MatchOnlyString(searchStr: string;
  const line: string; out foundMatch: string): boolean;
var
  match: TMatch;
begin
  match := Cached('^' + searchStr + '\s*$').Match(line.ToLower);
  foundMatch := match.Value;
  Result := match.Success;
end;

class function TRegExMatches.MatchString(searchStr: string;
  const line: string): boolean;
var
  match: TMatch;
begin
  match := Cached('^\s*(class\s+)?(' + searchStr + ')\s+\w+').Match(line.ToLower);
  Result := match.Success;
end;

class function TRegExMatches.GetName(const line: string): string;
const
  // Vorher: '[procedure|function|...]' war eine Character-Class und matchte
  // nur ein einzelnes Zeichen aus dem Set (p/r/o/...). Die '|'-Zeichen waren
  // bedeutungslos. -> Method-Names wurden falsch extrahiert. Jetzt Non-Capture-
  // Group mit echter Alternation.
  NamePattern =
    '(?:procedure|function|constructor|destructor|operator)\s+(?:\w+\.)?(\w+)\s*';
var
  match: TMatch;
begin
  match := Cached(NamePattern).Match(line.ToLower);
  if match.Success then
    Result := match.Groups[1].Value
  else
    Result := 'err:)';
end;

class function TRegExMatches.GetCodeOnly(const line: string): string;
const
  codePattern = '^(.*?)\s*(?=\/\/|\{\*|\(\*)|$';
var
  match: TMatch;
begin
  match := Cached(codePattern).Match(line);
  if match.Success then
    Result := match.Value
  else
    Result := line;
end;

initialization
  // Pre-Init des Caches: vermeidet Lazy-Init-Race wenn WatchMode-Worker
  // und Main-Analyzer parallel den ersten Cached(...) aufrufen.
  TRegExMatches.FCache := TDictionary<string, TRegEx>.Create;

finalization
  FreeAndNil(TRegExMatches.FCache);

end.
