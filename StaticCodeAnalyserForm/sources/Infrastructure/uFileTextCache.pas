unit uFileTextCache;

// Datei-Text-Cache fuer File-Scan-Detektoren (uTodoComment, uWithStatement,
// uReversedForRange, uLengthUnderflow, uTautologicalExpr, uDuplicateBlock,
// uCustomRuleDetector).
//
// Hintergrund (tools/perf_analyse.md Hot-Spot 🅑):
// Diese 7 Detektoren rufen jeweils Lines.LoadFromFile auf - pro .pas-Datei
// 7+ separate Disk-IO-Operationen + Encoding-Erkennung + TStringList-
// Allokationen. Mit diesem Cache wird pro Datei einmal eingelesen und
// alle Detektoren bedienen sich aus derselben TStringList.
//
// Ownership-Modell:
//   AcquireLines(FileName, out OwnedByCache) liefert eine TStringList.
//     * Wenn OwnedByCache=True (Cache-Pfad): nicht freigeben - der Cache
//       managed das Leben.
//     * Wenn OwnedByCache=False (Fallback): Caller MUSS Lines.Free
//       aufrufen wenn fertig.
//
//   Pragmatische Convenience: ReleaseLines(Lines, OwnedByCache) macht
//   genau das richtige - so kann der Caller einheitlich
//     Lines := AcquireLines(FileName, Cached); try ... finally
//       ReleaseLines(Lines, Cached); end;
//
// Lifecycle:
//   gFileTextCache wird beim Start jedes Files in der Main-Loop angelegt
//   und am Ende freigegeben. Pro File-Scope = pro Cache-Instanz.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TFileTextCache = class
  private
    FCache : TObjectDictionary<string, TStringList>;
    function Key(const FileName: string): string;
  public
    constructor Create;
    destructor Destroy; override;

    // Liefert TStringList fuer FileName. Cache besitzt die Liste -
    // NICHT freigeben. Nil bei Read-Fehler.
    function GetLines(const FileName: string): TStringList;

    procedure Clear;
  end;

var
  // Optional. Wenn nil (Tests, Single-File-Pfad), faellt AcquireLines auf
  // einen frischen LoadFromFile-Roundtrip zurueck.
  gFileTextCache : TFileTextCache = nil;

// Bequemer Wrapper fuer File-Scan-Detektoren - liefert Lines + Ownership-
// Flag. Caller-Muster:
//   var Lines: TStringList; Cached: Boolean;
//   Lines := AcquireLines(FileName, Cached);
//   if Lines = nil then Exit;
//   try
//     // ... use Lines ...
//   finally
//     ReleaseLines(Lines, Cached);
//   end;
function AcquireLines(const FileName: string;
  out OwnedByCache: Boolean): TStringList;

procedure ReleaseLines(Lines: TStringList; OwnedByCache: Boolean);

implementation

constructor TFileTextCache.Create;
begin
  inherited;
  FCache := TObjectDictionary<string, TStringList>.Create([doOwnsValues]);
end;

destructor TFileTextCache.Destroy;
begin
  FCache.Free;
  inherited;
end;

function TFileTextCache.Key(const FileName: string): string;
begin
  Result := LowerCase(ExpandFileName(FileName));
end;

function TFileTextCache.GetLines(const FileName: string): TStringList;
var
  K  : string;
  SL : TStringList;
begin
  Result := nil;
  K := Key(FileName);
  if FCache.TryGetValue(K, Result) then Exit;
  if not FileExists(FileName) then Exit;

  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(FileName, TEncoding.UTF8);
    except
      try
        SL.Clear;
        SL.LoadFromFile(FileName);
      except
        FreeAndNil(SL);
      end;
    end;
  except
    FreeAndNil(SL);
  end;

  if SL = nil then Exit;
  FCache.Add(K, SL);
  Result := SL;
end;

procedure TFileTextCache.Clear;
begin
  FCache.Clear;
end;

// --- Wrapper-Funktionen ---

function AcquireLines(const FileName: string;
  out OwnedByCache: Boolean): TStringList;
begin
  OwnedByCache := False;
  if Assigned(gFileTextCache) then
  begin
    Result := gFileTextCache.GetLines(FileName);
    if Result <> nil then
    begin
      OwnedByCache := True;
      Exit;
    end;
  end;

  // Fallback: lokaler Load
  if not FileExists(FileName) then Exit(nil);
  Result := TStringList.Create;
  try
    try
      Result.LoadFromFile(FileName, TEncoding.UTF8);
    except
      Result.Clear;
      try
        Result.LoadFromFile(FileName);
      except
        FreeAndNil(Result);
      end;
    end;
  except
    FreeAndNil(Result);
  end;
end;

procedure ReleaseLines(Lines: TStringList; OwnedByCache: Boolean);
begin
  if (Lines <> nil) and not OwnedByCache then
    Lines.Free;
end;

initialization

finalization
  if Assigned(gFileTextCache) then
    FreeAndNil(gFileTextCache);

end.
