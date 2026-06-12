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
  // SonarQube MQR (Multi-Quality-Rating) Klassifikation. Die Werte werden
  // direkt aus rules/sca-rules.json (cleanCodeAttribute + impacts) geladen
  // und sind Voraussetzung fuer den Sonar Generic Issue Export. SARIF
  // kennt MQR nicht und ignoriert diese Felder.
  TSonarSoftwareQuality = (
    sqSecurity,         // Sicherheits-relevant (Injection, Creds, ...)
    sqReliability,      // Korrektheits-relevant (Crashes, Datenverlust)
    sqMaintainability   // Wartbarkeit (Lesbarkeit, Dead Code, Duplikation)
  );

  TSonarImpactSeverity = (
    isBlocker,          // Blockiert Release / Production
    isHigh,
    isMedium,
    isLow,
    isInfo              // Reine Info, kein Aufwands-Mass
  );

  TSonarImpact = record
    SoftwareQuality : TSonarSoftwareQuality;
    Severity        : TSonarImpactSeverity;
  end;

  TRuleMeta = record
    ID                 : string;        // 'SCA001'
    Kind               : TFindingKind;
    Name               : string;        // 'Object created without try/finally'
    ShortDescription   : string;
    FullDescription    : string;
    DefaultSeverity    : TLeakSeverity;
    FindingType        : TFindingType;
    Tags               : TArray<string>;
    CWE                : TArray<string>;
    OWASP              : TArray<string>;
    ConfigKey          : string;
    DetectorUnit       : string;
    GoodExample        : string;
    BadExample         : string;
    // SonarQube MQR-Felder. Leer/nil wenn Rule nicht gemappt - der
    // Sonar-Generic-Issue-Exporter (uExportSonarGeneric, TODO P1) faellt
    // dann auf Sonar-Defaults zurueck. Test in uTestRuleCatalog
    // EveryFindingKindHasMqrMapping enforced dass alle Kinds gemappt sind.
    CleanCodeAttribute : string;        // 'LAWFUL'/'LOGICAL'/'FOCUSED'/...
    Impacts            : TArray<TSonarImpact>;
  end;

  TRuleCatalog = class
  strict private
    class var FRules        : TDictionary<TFindingKind, TRuleMeta>;
    class var FRulesByID    : TDictionary<string, TRuleMeta>;
    class var FProfiles     : TDictionary<string, TFindingKinds>;
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
    class function ParseSoftwareQuality(const S: string): TSonarSoftwareQuality; static;
    class function ParseImpactSeverity(const S: string): TSonarImpactSeverity; static;
    class function AllKinds: TFindingKinds; static;
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

    // Liefert die Kind-Menge fuer ein Profile aus profiles.<Name> in der
    // JSON. '*' im Array expandiert zu allen TFindingKind-Werten, weitere
    // Eintraege nach '*' werden additiv hinzugefuegt. Unbekanntes Profile
    // -> liefert AllKinds (kein Filter) + OutputDebugString-Warnung.
    // 'default' liefert immer AllKinds, auch wenn nicht im JSON definiert.
    class function GetProfile(const Name: string): TFindingKinds; static;

    // Liste aller bekannten Profile-Namen (fuer UI-Dropdowns, Tests).
    class function ProfileNames: TArray<string>; static;

    // Manuell triggern (z.B. nach JsonFilePath-Aenderung). Ueblicherweise
    // nicht noetig - der erste GetRule-Call laed lazy.
    class procedure Reload; static;

    // Setup / Teardown (im initialization / finalization gerufen).
    class procedure Init; static;
    class procedure Done; static;
  end;

implementation

// noinspection-file GodClass, StringConcatInLoop
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  Winapi.Windows,                  // OutputDebugString
  System.IOUtils, System.JSON;

{ ---- Setup ---- }

class procedure TRuleCatalog.Init;
begin
  FRules     := TDictionary<TFindingKind, TRuleMeta>.Create;
  FRulesByID := TDictionary<string, TRuleMeta>.Create;
  FProfiles  := TDictionary<string, TFindingKinds>.Create;
  FLoaded    := False;
end;

class procedure TRuleCatalog.Done;
begin
  FreeAndNil(FRules);
  FreeAndNil(FRulesByID);
  FreeAndNil(FProfiles);
end;

class procedure TRuleCatalog.Reload;
begin
  if Assigned(FRules)     then FRules.Clear;
  if Assigned(FRulesByID) then FRulesByID.Clear;
  if Assigned(FProfiles)  then FProfiles.Clear;
  FLoaded := False;
  EnsureLoaded;
end;

class function TRuleCatalog.AllKinds: TFindingKinds;
var
  K : TFindingKind;
begin
  Result := [];
  for K := Low(TFindingKind) to High(TFindingKind) do
    Include(Result, K);
end;

{ ---- Loader ---- }

class function TRuleCatalog.FindJsonFile: string;
// Sucht in dieser Reihenfolge nach rules\sca-rules.json:
//   1. FJsonFilePath        (Caller-Override - hat Vorrang)
//   2. <Exe-Dir>             - ParamStr(0); im Standalone der Tool-Pfad,
//                              im IDE-Plugin aber bds.exe (greift selten).
//   3. <HInstance-Dir>       - GetModuleFileName(HInstance) liefert die
//                              PFADE DER LADENDEN DLL/BPL. Im IDE-Plugin
//                              ist das das Plugin-Verzeichnis - genau wo
//                              der User typischerweise rules\ daneben legt.
//   4. %APPDATA%\StaticCodeAnalyser\rules\sca-rules.json
//                            - portable + benutzerspezifisch, ueblicher
//                              Speicherort fuer das IDE-Plugin.
// Walked vom BaseDir bis zu 8 Ebenen nach oben - deckt sowohl Release-Layouts
// (bin\..\rules) als auch tief geschachtelte Test-Layouts (tests\Win32\Debug
// braucht 4 Ebenen bis zum Repo-Root) ab. Stop bei Drive-Root (z.B. C:\).
var
  // noinspection UninitVar
  // Cands wird nach Z248 erstellt, AddRoots/etc. greifen erst nach dem
  // Create darauf zu - SCA166 erkennt das Nested-Closure-Pattern nicht.
  Cands : TList<string>;

  procedure AddRoots(const BaseDir: string);
  var
    Dir, Parent : string;
    i           : Integer;
  begin
    if BaseDir = '' then Exit;
    Dir := IncludeTrailingPathDelimiter(BaseDir);
    for i := 0 to 8 do
    begin
      Cands.Add(TPath.Combine(Dir, 'rules\sca-rules.json'));
      // Eine Ebene hoch. TPath.GetFullPath kanonisiert die '..' und gibt
      // einen sauberen Pfad mit trailing slash zurueck. Bei Drive-Root
      // (C:\) liefert GetFullPath denselben Pfad - dann abbrechen.
      Parent := TPath.GetFullPath(Dir + '..\');
      if SameText(Parent, Dir) then Break;
      Dir := Parent;
    end;
  end;

  function ModuleDir: string;
  // Liefert das Verzeichnis der ladenden BPL/EXE. Im Standalone identisch
  // zu ParamStr(0); im IDE-Plugin abweichend (= Plugin-Pfad, nicht bds.exe).
  var
    Buf : array[0..MAX_PATH] of Char;
  begin
    if GetModuleFileName(HInstance, Buf, Length(Buf)) > 0 then
      Result := ExtractFilePath(Buf)
    else
      Result := '';
  end;

  function AppDataDir: string;
  // %APPDATA%\StaticCodeAnalyser\rules\ - duplizierbarer Pfad statt
  // uIgnoreList.ConfigDir Import (das wuerde Common-Cycle einfuehren).
  var
    AppData : array[0..MAX_PATH] of Char;
  begin
    if GetEnvironmentVariable('APPDATA', AppData, Length(AppData)) > 0 then
      Result := IncludeTrailingPathDelimiter(AppData) +
                'StaticCodeAnalyser\rules\sca-rules.json'
    else
      Result := '';
  end;

var
  C : string;
begin
  if (FJsonFilePath <> '') and TFile.Exists(FJsonFilePath) then
    Exit(FJsonFilePath);

  Cands := TList<string>.Create;
  try
    AddRoots(ExtractFilePath(ParamStr(0)));
    AddRoots(ModuleDir);
    C := AppDataDir;
    if C <> '' then Cands.Add(C);

    for C in Cands do
      if (C <> '') and TFile.Exists(C) then
        Exit(TPath.GetFullPath(C));
  finally
    Cands.Free;
  end;
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

  // Safe-Lookups: FindValue liefert nil bei fehlendem Key, GetValue<T>
  // wirft EJSONPathException. Letzteres hat den 'owasp not found'-Crash
  // produziert, weil die meisten Rules kein owasp-Feld haben.
  function FindObject(O: TJSONObject; const Name: string): TJSONObject;
  var V: TJSONValue;
  begin
    if O = nil then Exit(nil);
    V := O.FindValue(Name);
    if V is TJSONObject then Result := TJSONObject(V) else Result := nil;
  end;

  function FindArray(O: TJSONObject; const Name: string): TJSONArray;
  var V: TJSONValue;
  begin
    if O = nil then Exit(nil);
    V := O.FindValue(Name);
    if V is TJSONArray then Result := TJSONArray(V) else Result := nil;
  end;

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
  Profiles : TJSONObject;
  ProfPair : TJSONPair;
  ProfArr  : TJSONArray;
  ProfSet  : TFindingKinds;
  KK       : TFindingKind;
  Token    : string;
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
    Tool := FindObject(Root, 'tool');
    if Tool <> nil then
    begin
      FToolName    := Tool.GetValue<string>('name', 'StaticCodeAnalyser');
      FToolVersion := Tool.GetValue<string>('version', '0.0.0');
      FToolUri     := Tool.GetValue<string>('informationUri', '');
    end;

    Rules := FindArray(Root, 'rules');
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

      // Arrays (tags / cwe / owasp) - FindArray ist nil-safe, GetValue<T>
      // wuerde EJSONPathException werfen wenn der Key fehlt (z.B. die
      // meisten Rules haben kein owasp-Feld).
      Tags := TList<string>.Create;
      try
        ArrVal := FindArray(RObj, 'tags');
        if ArrVal <> nil then
          for var T in ArrVal do Tags.Add(T.Value);
        Meta.Tags := Tags.ToArray;

        Tags.Clear;
        ArrVal := FindArray(RObj, 'cwe');
        if ArrVal <> nil then
          for var T in ArrVal do Tags.Add(T.Value);
        Meta.CWE := Tags.ToArray;

        Tags.Clear;
        ArrVal := FindArray(RObj, 'owasp');
        if ArrVal <> nil then
          for var T in ArrVal do Tags.Add(T.Value);
        Meta.OWASP := Tags.ToArray;
      finally
        Tags.Free;
      end;

      // Examples (optional - Rules ohne examples haben kein 'examples'-Feld)
      Examples := FindObject(RObj, 'examples');
      if Examples <> nil then
      begin
        Meta.BadExample  := Examples.GetValue<string>('bad', '');
        Meta.GoodExample := Examples.GetValue<string>('good', '');
      end;

      // SonarQube MQR-Felder (cleanCodeAttribute + impacts). Optional in der
      // JSON - Rules ohne diese Felder bekommen leere Werte. Test
      // EveryFindingKindHasMqrMapping schreit wenn welche fehlen.
      Meta.CleanCodeAttribute := RObj.GetValue<string>('cleanCodeAttribute', '');
      ArrVal := FindArray(RObj, 'impacts');
      if ArrVal <> nil then
      begin
        SetLength(Meta.Impacts, ArrVal.Count);
        for var IxImp := 0 to ArrVal.Count - 1 do
        begin
          var IObj := ArrVal.Items[IxImp] as TJSONObject;
          if IObj = nil then Continue;
          Meta.Impacts[IxImp].SoftwareQuality :=
            ParseSoftwareQuality(IObj.GetValue<string>('softwareQuality', ''));
          Meta.Impacts[IxImp].Severity :=
            ParseImpactSeverity(IObj.GetValue<string>('severity', ''));
        end;
      end;

      FRules.AddOrSetValue(K, Meta);
      if Meta.ID <> '' then
        FRulesByID.AddOrSetValue(Meta.ID, Meta);
    end;

    // ---- Profile-Block (optional) ----
    // Format: "profiles": { "<name>": ["Kind1","Kind2","*","!Style", ...], ... }
    // Token-Semantik (Reihenfolge zaehlt - links nach rechts angewandt):
    //   * '*'                  expandiert zu allen Kinds
    //   * 'Kind'               fuegt Kind hinzu
    //   * '!Kind' bzw. '-Kind' entfernt Kind aus dem aktuellen Set
    // Beispiel "selftest-quiet": ["*","!BeginEndRequired","!TooLongLine"]
    // = "alle Detektoren AUSSER zwei Style-Regeln".
    // Unbekannte Kind-Tokens werden still ignoriert - kein Crash, der
    // Rest des Profils greift weiter. (Aelteres Tool, neueres JSON.)
    Profiles := FindObject(Root, 'profiles');
    if Profiles <> nil then
    begin
      for i := 0 to Profiles.Count - 1 do
      begin
        ProfPair := Profiles.Pairs[i];
        if not (ProfPair.JsonValue is TJSONArray) then Continue;
        ProfArr := ProfPair.JsonValue as TJSONArray;
        ProfSet := [];
        for var j := 0 to ProfArr.Count - 1 do
        begin
          Token := ProfArr.Items[j].Value;
          if Token = '*' then
            ProfSet := ProfSet + AllKinds
          else if (Length(Token) >= 2) and ((Token[1] = '!') or (Token[1] = '-')) and
                  KindFromName(Copy(Token, 2, MaxInt), KK) then
            Exclude(ProfSet, KK)
          else if KindFromName(Token, KK) then
            Include(ProfSet, KK);
          // unbekannte Tokens: still ignorieren - JSON kann Detector-Namen
          // enthalten die in einer aelteren Tool-Version noch fehlen.
        end;
        FProfiles.AddOrSetValue(ProfPair.JsonString.Value, ProfSet);
      end;
    end;
    // 'default' garantieren - falls die JSON ihn nicht hat, immer AllKinds.
    if not FProfiles.ContainsKey('default') then
      FProfiles.AddOrSetValue('default', AllKinds);
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

  // Bundled-Profile auch im Fallback-Mode anbieten - sonst zeigt der
  // Combo im IDE-Plugin nur "default" wenn die JSON nicht ladbar war.
  // Inhalte muessen mit rules/sca-rules.json profiles-Block synchron
  // bleiben - bei Aenderungen DORT auch hier nachziehen (der Test
  // ProfileNamesIncludesBundled deckt nur Namen, nicht Mengen ab).
  FProfiles.AddOrSetValue('default', AllKinds);
  FProfiles.AddOrSetValue('strict',  AllKinds);
  FProfiles.AddOrSetValue('ide-fast',
    [fkMemoryLeak, fkSQLInjection, fkHardcodedSecret, fkFormatMismatch,
     fkNilDeref, fkMissingFinally, fkDivByZero, fkDeadCode,
     fkDebugOutput, fkFileReadError,
     fkDfmHardcodedDbCreds, fkDfmDeadEvent, fkDfmDuplicateBinding,
     fkDfmSchemaMismatch, fkDfmCircularDataSource, fkDfmSqlFromUserInput,
     fkDfmRequiredFieldUnbound, fkDfmRequiredFieldNotVisible,
     fkDfmCrossFormCoupling, fkDfmActionMismatch]);
  FProfiles.AddOrSetValue('security',
    [fkSQLInjection, fkHardcodedSecret, fkHardcodedPath,
     fkDfmHardcodedDbCreds, fkDfmSqlFromUserInput]);
  FProfiles.AddOrSetValue('bugs-only',
    [fkMemoryLeak, fkFormatMismatch, fkNilDeref, fkDivByZero,
     fkSQLInjection, fkHardcodedSecret, fkFileReadError,
     fkDfmDuplicateBinding, fkDfmDeadEvent, fkDfmSchemaMismatch,
     fkDfmCircularDataSource, fkDfmRequiredFieldUnbound,
     fkDfmRequiredFieldNotVisible, fkDfmCrossFormCoupling,
     fkDfmActionMismatch]);
  FProfiles.AddOrSetValue('code-quality',
    [fkEmptyExcept, fkUnusedUses, fkMissingFinally, fkDeadCode,
     fkLongMethod, fkLongParamList, fkMagicNumber, fkDebugOutput,
     fkDeepNesting, fkTodoComment, fkEmptyMethod, fkCyclomaticComplexity,
     fkDuplicateString, fkDuplicateBlock,
     fkDfmDefaultName, fkDfmHardcodedCaption, fkDfmOrphanHandler,
     fkDfmEmptyBoundEvent, fkDfmFieldTypeMismatch, fkDfmTabOrderConflict,
     fkDfmForbiddenClass, fkDfmDbInUiForm, fkDfmLayerViolation,
     fkDfmGodHandler]);
  FProfiles.AddOrSetValue('dfm-only',
    [fkDfmDefaultName, fkDfmHardcodedCaption, fkDfmHardcodedDbCreds,
     fkDfmDuplicateBinding, fkDfmDeadEvent, fkDfmOrphanHandler,
     fkDfmEmptyBoundEvent, fkDfmSchemaMismatch, fkDfmCircularDataSource,
     fkDfmSqlFromUserInput, fkDfmRequiredFieldUnbound,
     fkDfmRequiredFieldNotVisible, fkDfmFieldTypeMismatch,
     fkDfmTabOrderConflict, fkDfmForbiddenClass, fkDfmDbInUiForm,
     fkDfmCrossFormCoupling, fkDfmLayerViolation, fkDfmGodHandler,
     fkDfmActionMismatch]);
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

class function TRuleCatalog.ParseSoftwareQuality(const S: string): TSonarSoftwareQuality;
// Case-insensitive Match auf den 3 SonarQube-MQR-Software-Quality-Werten.
// Default bei unbekanntem/leeren Wert: sqMaintainability (am breitesten
// anwendbar; Sonar wirft Unbekanntes ohnehin spaeter bei Import zurueck).
var
  L : string;
begin
  L := LowerCase(S);
  if L = 'security'         then Exit(sqSecurity);
  if L = 'reliability'      then Exit(sqReliability);
  if L = 'maintainability'  then Exit(sqMaintainability);
  Result := sqMaintainability;
end;

class function TRuleCatalog.ParseImpactSeverity(const S: string): TSonarImpactSeverity;
// Case-insensitive Match auf den 5 SonarQube-MQR-Severity-Werten. Default
// bei unbekanntem Wert: isMedium (entspricht Sonar-Default im MQR-Mode).
var
  L : string;
begin
  L := LowerCase(S);
  if L = 'blocker' then Exit(isBlocker);
  if L = 'high'    then Exit(isHigh);
  if L = 'medium'  then Exit(isMedium);
  if L = 'low'     then Exit(isLow);
  if L = 'info'    then Exit(isInfo);
  Result := isMedium;
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

class function TRuleCatalog.GetProfile(const Name: string): TFindingKinds;
// Unbekannte oder leere Namen liefern AllKinds (= kein Filter). 'default'
// ist garantiert vorhanden (siehe LoadFromJsonFile / LoadFallback).
var
  Lookup : string;
begin
  EnsureLoaded;
  Lookup := Trim(Name);
  if Lookup = '' then Exit(AllKinds);
  if not FProfiles.TryGetValue(Lookup, Result) then
  begin
    OutputDebugString(PChar(Format(
      'TRuleCatalog: profile "%s" nicht gefunden, fallback auf AllKinds',
      [Lookup])));
    Result := AllKinds;
  end;
end;

class function TRuleCatalog.ProfileNames: TArray<string>;
var
  K : string;
  L : TList<string>;
begin
  EnsureLoaded;
  L := TList<string>.Create;
  try
    for K in FProfiles.Keys do L.Add(K);
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

initialization
  TRuleCatalog.Init;
finalization
  TRuleCatalog.Done;

end.
