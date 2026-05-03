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

  private
    class var FCache: TDictionary<string, TRegEx>;
    class function Cached(const pattern: string): TRegEx; static;
  end;

implementation

// ---------------------------------------------------------------------------
// Regex-Cache: kompilierte TRegEx-Objekte werden einmalig erstellt und
// wiederverwendet. Spart ~90% der Kompilierzeit bei grossen Projekten.
// ---------------------------------------------------------------------------
class function TRegExMatches.Cached(const pattern: string): TRegEx;
begin
  if not Assigned(FCache) then
    FCache := TDictionary<string, TRegEx>.Create;
  if not FCache.TryGetValue(pattern, Result) then
  begin
    Result := TRegEx.Create(pattern, [roIgnoreCase]);
    FCache.Add(pattern, Result);
  end;
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
  NamePattern =
    '[procedure|function|constructor|destructor|operator]\s+(?:\w+\.)?(\w+)\s*';
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

finalization
  FreeAndNil(TRegExMatches.FCache);

end.
