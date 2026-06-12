unit uSonarPull;

// SonarLint-Lookalike: laed existierende OPEN-Issues fuer eine Datei aus
// Sonar (Pull-Mode), parsed sie zu TLeakFinding-kompatiblen Eintraegen und
// liefert sie an die UI. Wird vom IDE-Plugin beim Oeffnen einer .pas
// aufgerufen damit der User sieht "was Sonar bereits ueber diese Datei
// weiss" - neben den lokal-erkannten SCA-Findings.
//
// Architektur:
//   * LRU-Cache pro (Project, File) mit 5-Min-TTL - verhindert API-Spam
//     beim haeufigen Tab-Wechsel
//   * Network-Fehler -> still failen, Status-Bar setzt "Sonar offline"
//   * Dedup-Hint: SCA-Finding + Sonar-Issue auf gleicher Datei+Zeile mit
//     einem RuleID-Mapping (siehe DEDUP_MAPPING) bekommen Suffix
//     "(already in Sonar)"

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uMethodd12, uSCAConsts;

type
  // Ein gepullter Sonar-Issue. Bewusst als RECORD und nicht als
  // TLeakFinding-Subklasse - die Felder ueberlappen nur zu 60% und der
  // Code-Pfad ist anders (kein Detector, keine MissingVar, keine Kind-
  // Klassifikation).
  TSonarPulledIssue = record
    Key       : string;         // 'AY3PnFr... ' Sonar-internes Issue
    Rule      : string;         // 'delph:RuleName' oder 'external_xy:...'
    FilePath  : string;         // relativ zum Project-Root (Sonar-Konvention)
    Line      : Integer;
    Message   : string;
    Severity  : string;         // 'BLOCKER'/'CRITICAL'/'MAJOR'/'MINOR'/'INFO'
    IsFromSonar : Boolean;      // immer True - Flag fuer UI-Marker-Farbe
  end;

  TSonarPullCacheEntry = record
    FetchedAt : TDateTime;
    Issues    : TArray<TSonarPulledIssue>;
  end;

  TSonarPullClient = class
  strict private
    FCache    : TDictionary<string, TSonarPullCacheEntry>;
    FOffline  : Boolean;            // letzter Request failed
    FLastError: string;
    function CacheKey(const ProjectKey, RelativePath: string): string;
    function CacheIsFresh(const E: TSonarPullCacheEntry): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    // Laed OPEN-Issues fuer eine Datei. Liefert ein leeres Array bei
    // Network-Error (kein Exception nach aussen) - FOffline + FLastError
    // setzen den Status fuer die UI.
    //   HostUrl, Token  - aus uSonarConfig.Resolve
    //   ProjectKey      - in Sonar registriertes Project
    //   RelativePath    - relativ zum Project-Root (forward slashes)
    function FetchIssues(const HostUrl, Token, ProjectKey,
      RelativePath: string): TArray<TSonarPulledIssue>;

    procedure InvalidateAll;
    procedure InvalidateFile(const ProjectKey, RelativePath: string);

    property Offline : Boolean read FOffline;
    property LastError : string read FLastError;
  end;

  // Dedup-Mapping: SCA-Kind -> moegliche Sonar-Rule-Praefixe. Wenn ein
  // SCA-Finding und ein Sonar-Issue dieselbe Datei+Zeile teilen UND
  // dieser Mapping-Eintrag matched, wird das SCA-Finding als "schon in
  // Sonar" markiert (UI-Suffix). Konservative Liste - lieber zu wenig
  // matchen als false-deduplizieren.
  TSonarDedupMatcher = class
  public
    class function MatchesKnownSonarRule(K: TFindingKind;
      const SonarRuleId: string): Boolean; static;
  end;

implementation

// noinspection-file ConcatToFormat, ExceptionTooGeneral, ExceptOnException, MultipleExit
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.Net.HttpClient, System.NetEncoding, System.JSON, System.DateUtils,
  System.StrUtils;

const
  CACHE_TTL_SEC = 5 * 60;
  PULL_TIMEOUT_MS = 6000;

{ TSonarPullClient }

constructor TSonarPullClient.Create;
begin
  inherited;
  FCache := TDictionary<string, TSonarPullCacheEntry>.Create;
  FOffline := False;
end;

destructor TSonarPullClient.Destroy;
begin
  FCache.Free;
  inherited;
end;

function TSonarPullClient.CacheKey(const ProjectKey, RelativePath: string): string;
begin
  Result := ProjectKey + '||' + LowerCase(RelativePath);
end;

function TSonarPullClient.CacheIsFresh(const E: TSonarPullCacheEntry): Boolean;
begin
  Result := SecondsBetween(Now, E.FetchedAt) < CACHE_TTL_SEC;
end;

procedure TSonarPullClient.InvalidateAll;
begin
  FCache.Clear;
end;

procedure TSonarPullClient.InvalidateFile(const ProjectKey,
  RelativePath: string);
begin
  FCache.Remove(CacheKey(ProjectKey, RelativePath));
end;

function ParseIssueObject(Obj: TJSONObject): TSonarPulledIssue;
var
  Comp : string;
  P    : Integer;
begin
  Result := Default(TSonarPulledIssue);
  Result.IsFromSonar := True;
  Result.Key      := Obj.GetValue<string>('key', '');
  Result.Rule     := Obj.GetValue<string>('rule', '');
  Result.Message  := Obj.GetValue<string>('message', '');
  Result.Severity := Obj.GetValue<string>('severity', 'MAJOR');
  Result.Line     := Obj.GetValue<Integer>('line', 0);

  // 'component' kommt als 'project-key:src/path/File.pas'. Wir ziehen den
  // Teil nach dem ersten ':' raus.
  Comp := Obj.GetValue<string>('component', '');
  P := Pos(':', Comp);
  if P > 0 then Result.FilePath := Copy(Comp, P + 1, MaxInt)
  else Result.FilePath := Comp;
end;

function TSonarPullClient.FetchIssues(const HostUrl, Token, ProjectKey,
  RelativePath: string): TArray<TSonarPulledIssue>;
var
  Key    : string;
  Entry  : TSonarPullCacheEntry;
  Client : THTTPClient;
  Req    : IHTTPRequest;
  Resp   : IHTTPResponse;
  Url    : string;
  Component : string;
  Json   : TJSONValue;
  Root   : TJSONObject;
  Issues : TJSONArray;
  L      : TList<TSonarPulledIssue>;
begin
  Result := nil;
  if (HostUrl = '') or (Token = '') or (ProjectKey = '') then Exit;

  Key := CacheKey(ProjectKey, RelativePath);
  if FCache.TryGetValue(Key, Entry) and CacheIsFresh(Entry) then
    // noinspection UninitVar
    // Entry.Issues ist Field-Access auf den Cache-Entry, nicht die lokale
    // Var Issues - SCA166-Identifier-Recognition unterscheidet das nicht.
    Exit(Entry.Issues);

  // Sonar's component-Param ist '<projectKey>:<relativePath>'
  Component := ProjectKey + ':' + StringReplace(RelativePath, '\', '/', [rfReplaceAll]);
  Url := Format('%s/api/issues/search?componentKeys=%s&statuses=OPEN&ps=500',
    [HostUrl, TNetEncoding.URL.Encode(Component)]);

  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := PULL_TIMEOUT_MS;
    Client.ResponseTimeout   := PULL_TIMEOUT_MS;
    Req := Client.GetRequest('GET', Url);
    Req.AddHeader('Authorization', 'Bearer ' + Token);
    Req.AddHeader('Accept', 'application/json');
    try
      Resp := Client.Execute(Req);
    except
      on E: Exception do
      begin
        FOffline := True;
        FLastError := E.Message;
        Exit(nil);
      end;
    end;
    if Resp.StatusCode <> 200 then
    begin
      FOffline := True;
      FLastError := Format('Sonar /api/issues/search returned %d', [Resp.StatusCode]);
      Exit(nil);
    end;
    FOffline := False;
    FLastError := '';

    Json := TJSONObject.ParseJSONValue(Resp.ContentAsString(TEncoding.UTF8));
    if (Json = nil) or not (Json is TJSONObject) then Exit(nil);
    try
      Root := Json as TJSONObject;
      Issues := Root.GetValue<TJSONArray>('issues');
      if Issues = nil then Exit(nil);

      L := TList<TSonarPulledIssue>.Create;
      try
        for var V in Issues do
          if V is TJSONObject then
            L.Add(ParseIssueObject(TJSONObject(V)));
        Result := L.ToArray;
      finally
        L.Free;
      end;
    finally
      Json.Free;
    end;

    Entry.FetchedAt := Now;
    Entry.Issues := Result;
    FCache.AddOrSetValue(Key, Entry);
  finally
    Client.Free;
  end;
end;

{ TSonarDedupMatcher }

class function TSonarDedupMatcher.MatchesKnownSonarRule(K: TFindingKind;
  const SonarRuleId: string): Boolean;
// Konservatives Mapping - nur Faelle wo wir SICHER sind dass beide Tools
// dasselbe Pattern erkennen.
//
// SonarDelphi-Rule-IDs siehe https://github.com/integrated-application-
// development/sonar-delphi - wir matchen nur per Substring.
var
  Lower : string;
begin
  Result := False;
  if SonarRuleId = '' then Exit;
  Lower := LowerCase(SonarRuleId);

  // Klammern um jeden Pos(...) > 0 sind PFLICHT - 'or' bindet in Delphi
  // staerker als '>' (bitweises OR auf Integers); ohne Klammern wird
  // 'Pos(x) > 0 or Pos(y) > 0' zu 'Pos(x) > (0 or Pos(y)) > 0' und
  // produziert E2008 Inkompatible Typen.
  case K of
    fkEmptyExcept:
      Result := (Pos('emptyexcept',    Lower) > 0);
    fkUnusedUses:
      Result := (Pos('unusedimport',   Lower) > 0)
             or (Pos('unuseduses',     Lower) > 0);
    fkTodoComment:
      Result := (Pos('todotag',        Lower) > 0)
             or (Pos('todocomment',    Lower) > 0);
    fkLongMethod:
      Result := (Pos('longmethod',     Lower) > 0)
             or (Pos('methodlength',   Lower) > 0);
    fkLongParamList:
      Result := (Pos('parametercount', Lower) > 0);
    fkCyclomaticComplexity:
      Result := (Pos('cyclomatic',     Lower) > 0);
    fkDeepNesting:
      Result := (Pos('nestedlevel',    Lower) > 0)
             or (Pos('nestingdepth',   Lower) > 0);
    fkWithStatement:
      Result := (Pos('withstatement',  Lower) > 0)
             or (Pos('withinstruction',Lower) > 0);
    fkMagicNumber:
      Result := (Pos('magicnumber',    Lower) > 0);
    fkDuplicateBlock:
      Result := (Pos('duplicat',       Lower) > 0);  // duplicated-blocks, etc.
    fkDeadCode:
      Result := (Pos('deadcode',       Lower) > 0)
             or (Pos('unreachable',    Lower) > 0);
  end;
end;

end.
