unit uRuleCatalog;

// Single Source of Truth fuer alle Detector-Rule-Metadaten. Liest
// rules/sca-rules.json beim ersten Zugriff (lazy) und stellt typisierte
// Lookups bereit.
//
// Verwendung:
//   Meta := TRuleCatalog.GetRule(fkMemoryLeak);
//   WriteLn(Meta.ID, ' ', Meta.Name);
//
// Konsistenz: pro TFindingKind muss genau ein Eintrag in der JSON
// existieren - der Konsistenz-Test in uTestRuleCatalog stellt das sicher.
//
// File-Lookup-Reihenfolge:
//   1. Pfad in TRuleCatalog.JsonFilePath (Caller kann ueberschreiben)
//   2. <Exe-Verzeichnis>/rules/sca-rules.json
//   3. <Exe-Verzeichnis>/../rules/sca-rules.json     (Tests / Dev-Build)
//   4. <Exe-Verzeichnis>/../../rules/sca-rules.json  (tieferer Build-Pfad)
// Wenn keine Datei gefunden wird: TRuleCatalog liefert minimale
// Fallback-Metadaten (ID = 'SCAxxx', Name = KindName) damit der Code
// nicht crashed - Tools wie SARIF-Export funktionieren weiter, nur
// ohne reichhaltige Beschreibungen.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts;

type
  TRuleMeta = record
    ID               : string;        // 'SCA001'
    Kind             : TFindingKind;
    Name             : string;        // 'Object created without try/finally'
    ShortDescription : string;
    FullDescription  : string;
    DefaultSeverity  : TLeakSeverity;
    FindingType      : TFindingType;
    Tags             : TArray<string>;
    CWE              : TArray<string>;
    OWASP            : TArray<string>;
    ConfigKey        : string;
    DetectorUnit     : string;
    GoodExample      : string;
    BadExample       : string;
  end;

  TRuleCatalog = class
  strict private
    class var FRules        : TDictionary<TFindingKind, TRuleMeta>;
    class var FRulesByID    : TDictionary<string, TRuleMeta>;
    class var FLoaded       : Boolean;
    class var FJsonFilePath : string;
    class var FToolName     : string;
    class var FToolVersion  : string;
    class var FToolUri      : string;
    class procedure EnsureLoaded; static;
    class procedure LoadFromJsonFile(const FileName: string); static;
    class procedure LoadFallback; static;
    class function FindJsonFile: string; static;
    class function ParseSeverity(const S: string): TLeakSeverity; static;
    class function ParseFindingType(const S: string): TFindingType; static;
  public
    // Optional: Caller-seitig den Pfad ueberschreiben (z.B. Tests).
    // Muss VOR dem ersten GetRule-Call gesetzt werden.
    class property JsonFilePath: string read FJsonFilePath write FJsonFilePath;

    // Tool-Info aus JSON (fuer SARIF tool.driver-Block).
    class function ToolName    : string; static;
    class function ToolVersion : string; static;
    class function ToolUri     : string; static;

    // Liefert Metadaten fuer einen Finding-Kind. Niemals nil - bei
    // fehlendem Catalog-Eintrag werden Fallback-Werte zurueckgegeben.
    class function GetRule(K: TFindingKind): TRuleMeta; static;

    // Lookup ueber die Rule-ID (case-sensitive, 'SCA001' etc.).
    // Returns False wenn unbekannt.
    class function GetRuleByID(const ID: string; out Meta: TRuleMeta): Boolean; static;

    // Iteriere alle bekannten Rules (Reihenfolge = TFindingKind ordinal).
    class procedure ForEach(AProc: TProc<TRuleMeta>); static;
    class function Count: Integer; static;

    // Manuell triggern (z.B. nach JsonFilePath-Aenderung). Ueblicherweise
    // nicht noetig - der erste GetRule-Call laed lazy.
    class procedure Reload; static;

    // Setup / Teardown (im initialization / finalization gerufen).
    class procedure Init; static;
    class procedure Done; static;
  end;

implementation

uses
  System.IOUtils, System.JSON;

{ ---- Setup ---- }

class procedure TRuleCatalog.Init;
begin
  FRules     := TDictionary<TFindingKind, TRuleMeta>.Create;
  FRulesByID := TDictionary<string, TRuleMeta>.Create;
  FLoaded    := False;
end;

class procedure TRuleCatalog.Done;
begin
  FreeAndNil(FRules);
  FreeAndNil(FRulesByID);
end;

class procedure TRuleCatalog.Reload;
begin
  if Assigned(FRules)     then FRules.Clear;
  if Assigned(FRulesByID) then FRulesByID.Clear;
  FLoaded := False;
  EnsureLoaded;
end;

{ ---- Loader ---- }

class function TRuleCatalog.FindJsonFile: string;
var
  ExeDir : string;
  Cands  : TArray<string>;
  C      : string;
begin
  if (FJsonFilePath <> '') and TFile.Exists(FJsonFilePath) then
    Exit(FJsonFilePath);

  ExeDir := ExtractFilePath(ParamStr(0));
  Cands := [
    TPath.Combine(ExeDir, 'rules\sca-rules.json'),
    TPath.Combine(TPath.Combine(ExeDir, '..'), 'rules\sca-rules.json'),
    TPath.Combine(TPath.Combine(ExeDir, '..\..'), 'rules\sca-rules.json'),
    TPath.Combine(TPath.Combine(ExeDir, '..\..\..'), 'rules\sca-rules.json')
  ];
  for C in Cands do
    if TFile.Exists(C) then
      Exit(TPath.GetFullPath(C));
  Result := '';
end;

class procedure TRuleCatalog.EnsureLoaded;
var
  Path : string;
begin
  if FLoaded then Exit;
  Path := FindJsonFile;
  if Path <> '' then
    LoadFromJsonFile(Path)
  else
    LoadFallback;
  FLoaded := True;
end;

class procedure TRuleCatalog.LoadFromJsonFile(const FileName: string);
var
  Json     : TJSONValue;
  Root     : TJSONObject;
  Tool     : TJSONObject;
  Rules    : TJSONArray;
  R        : TJSONValue;
  RObj     : TJSONObject;
  Meta     : TRuleMeta;
  K        : TFindingKind;
  KindName : string;
  ArrVal   : TJSONArray;
  Examples : TJSONObject;
  i        : Integer;
  Tags     : TList<string>;
begin
  Json := TJSONObject.ParseJSONValue(TFile.ReadAllText(FileName));
  if not (Json is TJSONObject) then
  begin
    LoadFallback;
    Exit;
  end;
  try
    Root := Json as TJSONObject;

    // Tool-Block
    Tool := Root.GetValue<TJSONObject>('tool');
    if Tool <> nil then
    begin
      FToolName    := Tool.GetValue<string>('name', 'StaticCodeAnalyser');
      FToolVersion := Tool.GetValue<string>('version', '0.0.0');
      FToolUri     := Tool.GetValue<string>('informationUri', '');
    end;

    Rules := Root.GetValue<TJSONArray>('rules');
    if Rules = nil then begin LoadFallback; Exit; end;

    for i := 0 to Rules.Count - 1 do
    begin
      R := Rules.Items[i];
      if not (R is TJSONObject) then Continue;
      RObj := R as TJSONObject;

      KindName := RObj.GetValue<string>('kind', '');
      if not KindFromName(KindName, K) then Continue; // unbekannter Kind -> skip

      Meta := Default(TRuleMeta);
      Meta.ID               := RObj.GetValue<string>('id', '');
      Meta.Kind             := K;
      Meta.Name             := RObj.GetValue<string>('name', KindName);
      Meta.ShortDescription := RObj.GetValue<string>('shortDescription', '');
      Meta.FullDescription  := RObj.GetValue<string>('fullDescription', '');
      Meta.DefaultSeverity  := ParseSeverity(RObj.GetValue<string>('defaultSeverity', ''));
      Meta.FindingType      := ParseFindingType(RObj.GetValue<string>('type', ''));
      Meta.ConfigKey        := RObj.GetValue<string>('configKey', '');
      Meta.DetectorUnit     := RObj.GetValue<string>('detectorUnit', '');

      // Arrays (tags / cwe / owasp)
      Tags := TList<string>.Create;
      try
        ArrVal := RObj.GetValue<TJSONArray>('tags');
        if ArrVal <> nil then
          for var T in ArrVal do Tags.Add(T.Value);
        Meta.Tags := Tags.ToArray;

        Tags.Clear;
        ArrVal := RObj.GetValue<TJSONArray>('cwe');
        if ArrVal <> nil then
          for var T in ArrVal do Tags.Add(T.Value);
        Meta.CWE := Tags.ToArray;

        Tags.Clear;
        ArrVal := RObj.GetValue<TJSONArray>('owasp');
        if ArrVal <> nil then
          for var T in ArrVal do Tags.Add(T.Value);
        Meta.OWASP := Tags.ToArray;
      finally
        Tags.Free;
      end;

      // Examples
      Examples := RObj.GetValue<TJSONObject>('examples');
      if Examples <> nil then
      begin
        Meta.BadExample  := Examples.GetValue<string>('bad', '');
        Meta.GoodExample := Examples.GetValue<string>('good', '');
      end;

      FRules.AddOrSetValue(K, Meta);
      if Meta.ID <> '' then
        FRulesByID.AddOrSetValue(Meta.ID, Meta);
    end;
  finally
    Json.Free;
  end;
end;

class procedure TRuleCatalog.LoadFallback;
// Wird gerufen wenn rules/sca-rules.json fehlt oder kaputt ist. Erzeugt
// Minimal-Metadaten pro TFindingKind aus KIND_META, damit der restliche
// Code (SARIF-Export, Reports) ohne Crash weiterlaeuft.
var
  K    : TFindingKind;
  Meta : TRuleMeta;
begin
  FToolName    := 'StaticCodeAnalyser';
  FToolVersion := '0.0.0';
  FToolUri     := 'https://github.com/nrodear/StaticCodeAnalyser';

  for K := Low(TFindingKind) to High(TFindingKind) do
  begin
    Meta := Default(TRuleMeta);
    Meta.ID               := Format('SCA%.3d', [Ord(K) + 1]);
    Meta.Kind             := K;
    Meta.Name             := KindName(K);
    Meta.ShortDescription := KindName(K);
    Meta.FullDescription  := '';
    Meta.DefaultSeverity  := lsWarning;
    Meta.FindingType      := KindFindingType(K);
    FRules.AddOrSetValue(K, Meta);
    FRulesByID.AddOrSetValue(Meta.ID, Meta);
  end;
end;

class function TRuleCatalog.ParseSeverity(const S: string): TLeakSeverity;
var
  L : string;
begin
  L := LowerCase(S);
  if L = 'error'   then Exit(lsError);
  if L = 'warning' then Exit(lsWarning);
  if L = 'hint'    then Exit(lsHint);
  Result := lsWarning; // default
end;

class function TRuleCatalog.ParseFindingType(const S: string): TFindingType;
var
  L : string;
begin
  L := LowerCase(S);
  if L = 'bug'                then Exit(ftBug);
  if L = 'code smell'         then Exit(ftCodeSmell);
  if L = 'vulnerability'      then Exit(ftVulnerability);
  if L = 'security hotspot'   then Exit(ftSecurityHotspot);
  if L = 'code duplication'   then Exit(ftCodeDuplication);
  if L = 'file error'         then Exit(ftFileError);
  Result := ftCodeSmell;
end;

{ ---- Public API ---- }

class function TRuleCatalog.GetRule(K: TFindingKind): TRuleMeta;
begin
  EnsureLoaded;
  if not FRules.TryGetValue(K, Result) then
  begin
    // Should not happen wenn LoadFallback alles fuellt.
    Result := Default(TRuleMeta);
    Result.ID   := Format('SCA%.3d', [Ord(K) + 1]);
    Result.Kind := K;
    Result.Name := KindName(K);
    Result.DefaultSeverity := lsWarning;
    Result.FindingType     := KindFindingType(K);
  end;
end;

class function TRuleCatalog.GetRuleByID(const ID: string;
  out Meta: TRuleMeta): Boolean;
begin
  EnsureLoaded;
  Result := FRulesByID.TryGetValue(ID, Meta);
end;

class procedure TRuleCatalog.ForEach(AProc: TProc<TRuleMeta>);
var
  K : TFindingKind;
begin
  EnsureLoaded;
  for K := Low(TFindingKind) to High(TFindingKind) do
    AProc(GetRule(K));
end;

class function TRuleCatalog.Count: Integer;
begin
  EnsureLoaded;
  Result := FRules.Count;
end;

class function TRuleCatalog.ToolName: string;
begin EnsureLoaded; Result := FToolName; end;

class function TRuleCatalog.ToolVersion: string;
begin EnsureLoaded; Result := FToolVersion; end;

class function TRuleCatalog.ToolUri: string;
begin EnsureLoaded; Result := FToolUri; end;

initialization
  TRuleCatalog.Init;
finalization
  TRuleCatalog.Done;

end.
