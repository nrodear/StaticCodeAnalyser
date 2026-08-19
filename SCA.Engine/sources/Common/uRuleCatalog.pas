unit uRuleCatalog;

// Single Source of Truth fuer alle Detector-Rule-Metadaten. Liest
// rules/sca-rules.json beim ersten Zugriff (lazy) und stellt typisierte
// Lookups bereit.
//
// Verwendung:
//   Meta := TRuleCatalog.GetRuleCanonical(fkMemoryLeak);      // immer Englisch
//   Meta := TRuleCatalog.GetRule(fkMemoryLeak, 'de');         // Anzeige-Sprache
//   WriteLn(Meta.ID, ' ', Meta.Name);
//
// SPRACH-TRENNUNG (2026-08-19): GetRuleCanonical liefert IMMER die
// englischen Katalogtexte - SARIF, Sonar und alles andere, was Maschinen
// lesen, ruft ausschliesslich diese Seite (GitHub Code Scanning hasht den
// Meldetext in den Dedup-Fingerprint; eine Uebersetzung dort liesse jeden
// Alert als neu erscheinen). GetRule(K, Lang) legt die Felder eines
// Sprach-Overlays (rules/sca-rules.<lang>.json bzw. die einkompilierte
// Tabelle) UEBER DIE RECORD-KOPIE; FRules selbst bleibt englisch und wird
// nach dem Laden nie mutiert.
//
// Konsistenz: pro TFindingKind muss genau ein Eintrag in der JSON
// existieren - der Konsistenz-Test in uTestRuleCatalog stellt das sicher.
//
// File-Lookup-Reihenfolge (Details in FindRulesFile; die Overlays
// sca-rules.<lang>.json nutzen dieselbe Kette, nur ohne Schritt 1):
//   1. Pfad in TRuleCatalog.JsonFilePath (Override, NUR der Katalog)
//   2. Aufwaertswalk ab dem Exe-Verzeichnis, bis 8 Ebenen: rules\...
//   3. derselbe Walk ab dem Modul-Verzeichnis (HInstance) - im
//      IDE-Plugin das BPL-Verzeichnis, nicht bds.exe
//   4. %APPDATA%\StaticCodeAnalyser\rules\...
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

  // Uebersetzbare Textfelder einer Regel - der Inhalt eines Sprach-Overlays
  // (rules/sca-rules.<lang>.json, Schema sca-rules.overlay.schema.json).
  // Ein leeres Feld bedeutet: englischer Rueckfall, kein Fehler.
  TRuleTextOverlay = record
    Name             : string;
    ShortDescription : string;
    FullDescription  : string;
  end;

  // Rule-ID ('SCA001') -> uebersetzte Felder EINER Sprache. Jeder
  // Zugriff auf den Cache UND seine Maps laeuft unter
  // TMonitor(FOverlays) - Vertrag und Begruendung s. EnsureOverlay.
  TOverlayMap = TDictionary<string, TRuleTextOverlay>;

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
    // Overlay-Infrastruktur (2026-08-19). FResolvedJsonPath haelt fest, WO
    // der Katalog gefunden wurde - die Overlays suchen zuerst dort, damit
    // Katalog und Uebersetzung nicht aus zwei Ablagen kommen.
    // FCatalogVersion ist Root.version der JSON ('1.5') fuer die
    // basedOn-Drift-Warnung. FOverlays cached eine Map je Sprache,
    // Befuellung unter TMonitor, auch negativ (leere Map = "keine
    // Uebersetzung vorhanden", sonst greift jeder Fund auf die Platte).
    class var FResolvedJsonPath : string;
    class var FCatalogVersion   : string;
    class var FOverlays         : TObjectDictionary<string, TOverlayMap>;
    class procedure EnsureLoaded; static;
    class procedure LoadFromJsonFile(const FileName: string); static;
    class procedure LoadFallback; static;
    class function FindJsonFile: string; static;
    class function ParseSeverity(const S: string): TLeakSeverity; static;
    class function ParseFindingType(const S: string): TFindingType; static;
    class function ParseSoftwareQuality(const S: string): TSonarSoftwareQuality; static;
    class function ParseImpactSeverity(const S: string): TSonarImpactSeverity; static;
    class function AllKinds: TFindingKinds; static;
    class function MakeFallbackMeta(K: TFindingKind): TRuleMeta; static;
    class function FindRulesFile(const ARelName: string): string; static;
    class function FindOverlayFile(const ANorm: string): string; static;
    class function EnsureOverlay(const ANorm: string): TOverlayMap; static;
    class function LoadOverlayFile(const AFileName: string): TOverlayMap; static;
    class function EmbeddedOverlay(const ANorm: string): TOverlayMap; static;
    class procedure ApplyOverlayTo(var Meta: TRuleMeta; const ALang: string); static;
  public
    // Optional: Caller-seitig den Pfad ueberschreiben (z.B. Tests).
    // Muss VOR dem ersten GetRule-Call gesetzt werden.
    class property JsonFilePath: string read FJsonFilePath write FJsonFilePath;

    // Tool-Info aus JSON (fuer SARIF tool.driver-Block).
    class function ToolName    : string; static;
    class function ToolVersion : string; static;
    class function ToolUri     : string; static;

    // KANONISCH = immer Englisch. Fuer alles, was MASCHINEN lesen: SARIF,
    // Sonar, Baseline, Severity-Gates. Die Umbenennung (2026-08-19, vorher
    // GetRule) ist Absicht: die lokalisierte GetRule hat ZWEI Parameter,
    // damit beim Umbau JEDE Alt-Stelle zum Compile-Fehler wurde und einmal
    // bewusst kanonisch/lokalisiert entschieden ist. Eine GetRuleLocalized
    // DANEBEN haette den SARIF-Pfad still auf der falschen Seite gelassen.
    // Niemals nil - bei fehlendem Eintrag kommen Fallback-Werte.
    class function GetRuleCanonical(K: TFindingKind): TRuleMeta; static;

    // Kanonischer ID-Lookup (case-sensitive, 'SCA001'). False = unbekannt.
    class function GetRuleByIDCanonical(const ID: string; out Meta: TRuleMeta): Boolean; static;

    // LOKALISIERT fuer Anzeige-Publikum: die kanonische Regel mit den
    // Feldern des Sprach-Overlays darueber (Name, ShortDescription;
    // FullDescription nur, falls je uebersetzt). Fehlendes Overlay oder
    // Feld faellt still auf Englisch zurueck. Der Sprachcode laeuft durch
    // uLocalization.NormalizeLangCode ('de-DE' -> 'de') - dieselbe
    // Normalisierung wie SetLanguage, keine zweite. ABSICHTLICH kein
    // Default-Argument mit CurrentLanguage: SARIF/Sonar duerfen nie an
    // einer globalen Sprachvariablen haengen, und die Katalog-Tests
    // wuerden sonst reihenfolgeabhaengig gegen fremde Fixtures.
    class function GetRule(K: TFindingKind; const ALang: string): TRuleMeta; static;
    class function GetRuleByID(const ID, ALang: string; out Meta: TRuleMeta): Boolean; static;

    // Iteriere alle bekannten Rules (Reihenfolge = TFindingKind ordinal).
    // BLEIBT KANONISCH: einziger Massen-Konsument ist der SARIF-rules[]-
    // Block, und der muss englisch sein.
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

// noinspection-file AvoidOut, BeginEndRequired, GodClass, GroupedDeclaration, StringConcatInLoop, TodoComment, TooLongLine, UnsortedUses, UnusedPublicMember
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  Winapi.Windows,                  // OutputDebugString
  System.IOUtils, System.JSON,
  uLocalization;                   // NormalizeLangCode - EINE Normalisierung
                                   // fuer SetLanguage und Overlay-Lookup

const
  // 'name' liest der Tool-Block, jede Regel UND jedes Overlay -
  // drei Stellen, eine Konstante (DuplicateString-Schwelle).
  JSON_FLD_NAME = 'name';

type
  // Einkompilierte Katalog-Texte (2026-07-26). Traeger fuer
  // uRuleCatalogData.inc - siehe dortigen Kopf und MakeFallbackMeta.
  TRuleFallbackData = record
    RuleID    : string;
    Name      : string;
    ShortDesc : string;
    BadEx     : string;
    GoodEx    : string;
  end;

{$I uRuleCatalogData.inc}

type
  // Einkompilierte Overlay-Texte (2026-08-19). Traeger fuer
  // uRuleCatalogOverlay.inc - im IDE-Plugin der Normalfall, weil die BPL
  // die losen rules\-JSONs meist nicht findet (s. MakeFallbackMeta).
  TRuleOverlayData = record
    RuleID    : string;
    Name      : string;
    ShortDesc : string;
  end;

{$I uRuleCatalogOverlay.inc}

{ ---- Setup ---- }

class procedure TRuleCatalog.Init;
begin
  FRules     := TDictionary<TFindingKind, TRuleMeta>.Create;
  FRulesByID := TDictionary<string, TRuleMeta>.Create;
  FProfiles  := TDictionary<string, TFindingKinds>.Create;
  FOverlays  := TObjectDictionary<string, TOverlayMap>.Create([doOwnsValues]);
  FLoaded    := False;
end;

class procedure TRuleCatalog.Done;
begin
  FreeAndNil(FRules);
  FreeAndNil(FRulesByID);
  FreeAndNil(FProfiles);
  FreeAndNil(FOverlays);
end;

class procedure TRuleCatalog.Reload;
begin
  if Assigned(FRules)     then FRules.Clear;
  if Assigned(FRulesByID) then FRulesByID.Clear;
  if Assigned(FProfiles)  then FProfiles.Clear;
  // Overlays mitleeren - sonst schleppt ein Test (Setup ruft Reload) die
  // Sprach-Map des vorigen mit, und ein JsonFilePath-Wechsel wuerde
  // Katalog und Uebersetzung aus zwei Staenden mischen. UNTER dem
  // Monitor: Clear gibt die Maps frei (doOwnsValues), und der Leser
  // (ApplyOverlayTo) haelt denselben Monitor ueber Lookup UND
  // Anwendung - so zieht Reload keine Map unter einem laufenden
  // Zugriff weg (Use-after-free).
  if Assigned(FOverlays) then
  begin
    TMonitor.Enter(FOverlays);
    try
      FOverlays.Clear;
    finally
      TMonitor.Exit(FOverlays);
    end;
  end;
  FResolvedJsonPath := '';
  FCatalogVersion   := '';
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

class function TRuleCatalog.FindRulesFile(const ARelName: string): string;
// Sucht eine Katalog-Datei (relativer Name, z.B. 'rules\sca-rules.json'
// oder 'rules\sca-rules.de.json') in dieser Reihenfolge:
//   1. <Exe-Dir>             - ParamStr(0); im Standalone der Tool-Pfad,
//                              im IDE-Plugin aber bds.exe (greift selten).
//   2. <HInstance-Dir>       - GetModuleFileName(HInstance) liefert die
//                              PFADE DER LADENDEN DLL/BPL. Im IDE-Plugin
//                              ist das das Plugin-Verzeichnis - genau wo
//                              der User typischerweise rules\ daneben legt.
//   3. %APPDATA%\StaticCodeAnalyser\<ARelName>
//                            - portable + benutzerspezifisch, ueblicher
//                              Speicherort fuer das IDE-Plugin.
// Der FJsonFilePath-Override liegt bewusst NICHT hier, sondern in
// FindJsonFile - er gilt nur fuer den Katalog selbst.
// Walked vom BaseDir bis zu 8 Ebenen nach oben - deckt sowohl Release-Layouts
// (bin\..\rules) als auch tief geschachtelte Test-Layouts (tests\Win32\Debug
// braucht 4 Ebenen bis zum Repo-Root) ab. Stop bei Drive-Root (z.B. C:\).
var
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
      Cands.Add(TPath.Combine(Dir, ARelName));
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
                'StaticCodeAnalyser\' + ARelName
    else
      Result := '';
  end;

var
  C : string;
begin
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

class function TRuleCatalog.FindJsonFile: string;
// Der Katalog selbst: erst der Caller-Override (Tests!), dann dieselbe
// Kandidatenkette, die auch die Overlays benutzen. Der Override gilt
// BEWUSST nur fuer den Katalog - ein Test, der eine kaputte JSON
// unterschiebt, soll damit nicht zugleich die Overlays verstecken.
begin
  if (FJsonFilePath <> '') and TFile.Exists(FJsonFilePath) then
    Exit(FJsonFilePath);
  Result := FindRulesFile('rules\sca-rules.json');
end;

class procedure TRuleCatalog.EnsureLoaded;
var
  Path : string;
begin
  if FLoaded then Exit;
  Path := FindJsonFile;
  // Fundort merken - die Overlays suchen zuerst NEBEN dem gefundenen
  // Katalog, damit Uebersetzung und Katalog aus derselben Ablage kommen.
  FResolvedJsonPath := Path;
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

    // Katalogversion (Root-Ebene, '1.5') - Referenz fuer die
    // basedOn-Warnung der Sprach-Overlays.
    FCatalogVersion := Root.GetValue<string>('version', '');

    // Tool-Block
    Tool := FindObject(Root, 'tool');
    if Tool <> nil then
    begin
      FToolName    := Tool.GetValue<string>(JSON_FLD_NAME, 'StaticCodeAnalyser');
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
      Meta.Name             := RObj.GetValue<string>(JSON_FLD_NAME, KindName);
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

class function TRuleCatalog.MakeFallbackMeta(K: TFindingKind): TRuleMeta;
// Gemeinsamer Kern der Fallback-Metadaten (2026-07-04 dedupliziert aus
// LoadFallback + GetRule-Notfallpfad).
//
// 2026-07-26: Beispiele/Texte kommen jetzt aus der EINKOMPILIERTEN Tabelle
// RULE_CATALOG_DATA (uRuleCatalogData.inc, generiert aus rules/sca-rules.json).
// Vorher blieben BadExample/GoodExample hier LEER - und weil 19 Kinds
// (SCA167-SCA184, SCA194, u.a. SCA176) ihren Vorher/Nachher-Hinweis
// AUSSCHLIESSLICH ueber den Katalog beziehen (uFixHint-Fallback), zeigte das
// IDE-Plugin bei ihnen gar keinen Hinweis, sobald die JSON zur Laufzeit nicht
// gefunden wurde. Genau das ist im Plugin der Normalfall: die BPL liegt im
// Embarcadero-BPL-Verzeichnis, das Repo auf einem anderen Laufwerk - der
// 8-Ebenen-Aufwaertswalk der Pfadsuche kann die Datei dort nie erreichen.
//
// Defensiv: die Tabelle wird nur genutzt, wenn Index UND RuleID zum Kind
// passen. Bei Drift (neues Kind in der Enum-MITTE eingefuegt, .inc nicht
// regeneriert) faellt alles auf das alte Verhalten zurueck, statt falsche
// Texte zu zeigen.
var
  Idx : Integer;
begin
  Result := Default(TRuleMeta);
  Result.ID              := Format('SCA%.3d', [Ord(K) + 1]);
  Result.Kind            := K;
  Result.Name            := KindName(K);
  Result.DefaultSeverity := lsWarning;
  Result.FindingType     := KindFindingType(K);

  Idx := Ord(K);
  if (Idx >= Low(RULE_CATALOG_DATA)) and (Idx <= High(RULE_CATALOG_DATA))
     and SameText(RULE_CATALOG_DATA[Idx].RuleID, Result.ID) then
  begin
    if RULE_CATALOG_DATA[Idx].Name <> '' then
      Result.Name := RULE_CATALOG_DATA[Idx].Name;
    Result.ShortDescription := RULE_CATALOG_DATA[Idx].ShortDesc;
    Result.BadExample       := RULE_CATALOG_DATA[Idx].BadEx;
    Result.GoodExample      := RULE_CATALOG_DATA[Idx].GoodEx;
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
    Meta := MakeFallbackMeta(K);
    // ShortDescription: MakeFallbackMeta liefert sie seit 2026-07-26 aus der
    // einkompilierten Tabelle. Nur wenn die nichts hergibt (Drift-Guard hat
    // abgelehnt), auf den Kind-Namen zurueckfallen - vorher stand hier eine
    // unbedingte Zuweisung, die den Katalogtext ueberschrieben haette.
    if Meta.ShortDescription = '' then
      Meta.ShortDescription := KindName(K);
    FRules.AddOrSetValue(K, Meta);
    FRulesByID.AddOrSetValue(Meta.ID, Meta);
  end;

  // Bundled-Profile auch im Fallback-Mode anbieten - sonst zeigt der
  // Combo im IDE-Plugin nur "default" wenn die JSON nicht ladbar war.
  // Inhalte muessen mit rules/sca-rules.json profiles-Block synchron
  // bleiben - bei Aenderungen DORT auch hier nachziehen. Wie gut das
  // abgesichert ist, ist je Profil verschieden: fuer 'strict', 'default'
  // und 'style' pruefen die drei Profile*-Tests in uTestRuleCatalog auch
  // die MENGEN; fuer die uebrigen deckt ProfileNamesIncludesBundled nach
  // wie vor nur die Namen ab. Genau diese Luecke hat den C1-Beschluss am
  // 2026-08-02 hier zunaechst nicht ankommen lassen.
  // 'strict' ist das Profil, das ALLES bedeutet - hier und nur hier haengt
  // die Vollstaendigkeits-Zusage.
  FProfiles.AddOrSetValue('strict', AllKinds);
  // 'style' = die reinen Konventions-Regeln, die seit dem C1-Beschluss
  // (2026-08-02) nicht mehr im Default stecken: zusammen 48,1 % aller
  // Funde auf dem Referenzkorpus bei 0-4 % FP-Quote. Sie sind richtig,
  // aber sie sind das Erste, was ein Neuanwender sieht.
  //
  // fkIfElseBegin kam am 2026-08-03 dazu. Die Analyse vom 2026-08-01
  // nannte SIEBEN solche Regeln, C1 verschob sechs - diese blieb ohne
  // Grund liegen. Sie ist dieselbe Bauart wie fkBeginEndRequired
  // daneben: Code Smell, Hint, reine Frage der Schreibweise.
  FProfiles.AddOrSetValue('style',
    [fkPublicMemberWithoutDoc, fkNilComparison, fkBeginEndRequired,
     fkWithStatement, fkClassPerFile, fkDfmHardcodedCaption,
     fkIfElseBegin]);
  // 'default' = alles ausser 'style'. Bewusst als Differenz gebildet und
  // nicht als zweite Liste: so kann ein neues Kind hier gar nicht erst
  // durchfallen, und der Fallback bleibt automatisch synchron mit der
  // style-Menge darueber.
  FProfiles.AddOrSetValue('default',
    AllKinds - FProfiles['style']);
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
     fkDfmGodHandler,
     // Review 2026-07-30: beide Projekt-Hygiene-Kinds - die JSON fuehrte
     // NotIncludedInProject schon, der Fallback keines von beiden; seit
     // dem 194/195-Split verschwand ein per uses gezogener Orphan unter
     // diesem Profil sonst ersatzlos (Emit195=False frisst den Fund).
     fkNotIncludedInProject, fkUsedButNotInProject]);
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

class function TRuleCatalog.GetRuleCanonical(K: TFindingKind): TRuleMeta;
begin
  EnsureLoaded;
  if not FRules.TryGetValue(K, Result) then
  begin
    // Should not happen wenn LoadFallback alles fuellt.
    Result := MakeFallbackMeta(K);
  end;
end;

class function TRuleCatalog.GetRuleByIDCanonical(const ID: string;
  out Meta: TRuleMeta): Boolean;
begin
  EnsureLoaded;
  Result := FRulesByID.TryGetValue(ID, Meta);
end;

class function TRuleCatalog.GetRule(K: TFindingKind;
  const ALang: string): TRuleMeta;
begin
  Result := GetRuleCanonical(K);   // Record-KOPIE - FRules bleibt englisch
  ApplyOverlayTo(Result, ALang);
end;

class function TRuleCatalog.GetRuleByID(const ID, ALang: string;
  out Meta: TRuleMeta): Boolean;
begin
  Result := GetRuleByIDCanonical(ID, Meta);
  if Result then
    ApplyOverlayTo(Meta, ALang);
end;

{ ---- Sprach-Overlays (2026-08-19) ---- }

class procedure TRuleCatalog.ApplyOverlayTo(var Meta: TRuleMeta;
  const ALang: string);
// Legt die uebersetzten Felder UEBER die Kopie. Feldweise Rueckfaelle sind
// Vertrag (Overlay-Schema): ein leeres Feld heisst Englisch, kein Fehler.
var
  Ov    : TOverlayMap;
  Txt   : TRuleTextOverlay;
  ANorm : string;
begin
  ANorm := NormalizeLangCode(ALang);
  if (ANorm = '') or (ANorm = 'en') or not Assigned(FOverlays) then Exit;
  // Lookup UND Feld-Anwendung unter dem Monitor: Reload leert FOverlays
  // (doOwnsValues gibt die Maps frei) - ein sperrfreier TryGetValue auf
  // der zurueckgegebenen Map waere gegen ein paralleles Reload ein
  // Use-after-free. TMonitor ist reentrant, EnsureOverlay darf ihn
  // darunter erneut nehmen. Kosten: ein Dictionary-Get pro Anzeige-
  // Zugriff unter Lock - kein Scan-Pfad, das traegt.
  TMonitor.Enter(FOverlays);
  try
    Ov := EnsureOverlay(ANorm);
    if not Assigned(Ov) or not Ov.TryGetValue(Meta.ID, Txt) then Exit;
    if Txt.Name             <> '' then Meta.Name             := Txt.Name;
    if Txt.ShortDescription <> '' then Meta.ShortDescription := Txt.ShortDescription;
    if Txt.FullDescription  <> '' then Meta.FullDescription  := Txt.FullDescription;
  finally
    TMonitor.Exit(FOverlays);
  end;
end;

class function TRuleCatalog.EnsureOverlay(const ANorm: string): TOverlayMap;
// Ein Ladeversuch pro Sprache pro Prozess; auch "keine Uebersetzung"
// wird als LEERE Map gecacht (Negativ-Cache) - sonst griffe jeder Fund
// erneut auf die Platte. Rangfolge: lose Datei schlaegt einkompilierte
// Tabelle, dieselbe wie bei den externen .po-Dateien.
//
// Nebenlaeufigkeit: JEDER Zugriff auf FOverlays und seine Maps laeuft
// unter TMonitor(FOverlays) - der Leser (ApplyOverlayTo) genauso wie
// das Clear in Reload. Ein sperrfreier Lesepfad waere gegen Reload ein
// Use-after-free, denn doOwnsValues gibt die Maps beim Clear frei.
// Der Katalog selbst (FRules) kommt ohne Lock aus, weil ihn
// uStaticAnalyzer2.initialization (BuildAllDetectors ->
// GetRuleCanonical -> EnsureLoaded) einthreadig beim Prozessstart
// fuellt und danach nur noch liest - Reload rufen allein die Tests.
// Deshalb darf ein Sprachwechsel NIE FRules anfassen.
begin
  Result := nil;
  if (ANorm = '') or (ANorm = 'en') or not Assigned(FOverlays) then Exit;
  EnsureLoaded;   // FResolvedJsonPath muss stehen, bevor gesucht wird
  TMonitor.Enter(FOverlays);
  try
    if FOverlays.TryGetValue(ANorm, Result) then Exit;
    Result := LoadOverlayFile(FindOverlayFile(ANorm));
    if not Assigned(Result) then
      Result := EmbeddedOverlay(ANorm);
    if not Assigned(Result) then
      Result := TOverlayMap.Create;   // Negativ-Cache
    FOverlays.Add(ANorm, Result);
  finally
    TMonitor.Exit(FOverlays);
  end;
end;

class function TRuleCatalog.FindOverlayFile(const ANorm: string): string;
// Erst NEBEN dem gefundenen Katalog (dieselbe rules\-Ablage), dann die
// volle Kandidatenkette. Der JsonFilePath-Override zaehlt hier bewusst
// nicht (s. FindJsonFile).
var
  Kandidat : string;
begin
  if FResolvedJsonPath <> '' then
  begin
    Kandidat := Format('%ssca-rules.%s.json',
      [ExtractFilePath(FResolvedJsonPath), ANorm]);
    if TFile.Exists(Kandidat) then Exit(Kandidat);
  end;
  Result := FindRulesFile('rules\sca-rules.' + ANorm + '.json');
end;

function OverlayFromJson(Root: TJSONObject;
  const AFileName, ACatalogVersion: string): TOverlayMap;
// Feld-Extraktion aus dem geparsten Overlay; nil, wenn die Struktur
// nicht passt. Typfehler (GetValue<string> wirft) verlassen die
// Funktion per Exception - dann raeumt das except die halbe Map ab und
// re-raist; LoadOverlayFile uebersetzt jede Exception in nil.
// Eigene Funktion statt zweitem try in LoadOverlayFile: eine
// Schachtelung faellt unter die NestedTry-Regel des Self-Scans.
// UNIT-Funktion statt Klassenmethode: die Signatur braucht
// TJSONObject, und eine Deklaration in der Klasse zoege System.JSON
// in die interface-uses (E2003-Falle) - die Katalogversion kommt
// deshalb als Parameter, strict private ist hier unsichtbar.
var
  RulesO  : TJSONObject;
  RObj    : TJSONObject;
  V       : TJSONValue;
  BasedOn : string;
  i       : Integer;
  Pair    : TJSONPair;
  Txt     : TRuleTextOverlay;
begin
  Result := nil;
  // basedOn-Drift: Overlay TROTZDEM verwenden (veralteter Text ist
  // besser als keiner), aber sichtbar machen. Der harte Riegel
  // sitzt im CI (tools/rules_doc_gate.py prueft basedOn gegen die
  // Katalogversion und Fremd-IDs als Fehler). Bewusste Luecke: die
  // Warnung braucht BEIDE Versionen - laeuft der Katalog im
  // Fallback (Katalogversion leer), wird ein beliebig altes
  // Overlay stumm genutzt. Auch dann gilt: veralteter Text
  // schlaegt keinen Text.
  BasedOn := Root.GetValue<string>('basedOn', '');
  if (BasedOn <> '') and (ACatalogVersion <> '') and
     (BasedOn <> ACatalogVersion) then
    // noinspection DebugOutput
    // Diagnose-Kanal wie bei der Profil-Warnung in GetProfile:
    // die Engine hat keine UI, und ein veraltetes Overlay soll
    // sichtbar sein, ohne den Lauf zu stoeren.
    OutputDebugString(PChar(Format(
      'TRuleCatalog: Overlay %s basedOn=%s, Katalog=%s - Texte evtl. veraltet',
      [ExtractFileName(AFileName), BasedOn, ACatalogVersion])));
  V := Root.FindValue('rules');
  if not (V is TJSONObject) then Exit;
  RulesO := TJSONObject(V);
  Result := TOverlayMap.Create;
  try
    for i := 0 to RulesO.Count - 1 do
    begin
      Pair := RulesO.Pairs[i];
      if not (Pair.JsonValue is TJSONObject) then Continue;
      RObj := TJSONObject(Pair.JsonValue);
      Txt.Name             := RObj.GetValue<string>(JSON_FLD_NAME, '');
      Txt.ShortDescription := RObj.GetValue<string>('shortDescription', '');
      Txt.FullDescription  := RObj.GetValue<string>('fullDescription', '');
      Result.AddOrSetValue(Pair.JsonString.Value, Txt);
    end;
  except
    // Halbe Map einsammeln, Fehler weiterreichen - nicht verschlucken:
    // die nil-Uebersetzung ist Sache von LoadOverlayFile.
    FreeAndNil(Result);
    raise;
  end;
end;

class function TRuleCatalog.LoadOverlayFile(const AFileName: string): TOverlayMap;
// nil bei JEDEM Problem - der Aufrufer faellt auf die einkompilierte
// Tabelle zurueck. Explizit TEncoding.UTF8: ReadAllText ohne Encoding
// nimmt bei fehlendem BOM ANSI an - Mojibake in genau den Umlauten und
// Akzenten, die der Sinn des Features sind. Groessendeckel wie bei den
// externen .po-Dateien: die Overlays sind ~40 KB, alles jenseits von
// 4 MB ist keine Uebersetzung.
const
  MAX_OVERLAY_BYTES = 4 * 1024 * 1024;
var
  Json : TJSONValue;
begin
  Result := nil;
  if (AFileName = '') or not TFile.Exists(AFileName) then Exit;
  Json := nil;
  try
    if TFile.GetSize(AFileName) > MAX_OVERLAY_BYTES then Exit;
    Json := TJSONObject.ParseJSONValue(
      TFile.ReadAllText(AFileName, TEncoding.UTF8));
    if Json is TJSONObject then
      Result := OverlayFromJson(TJSONObject(Json), AFileName, FCatalogVersion);
  except
    // Breiter Fang mit Absicht: die lose Datei ist der dokumentierte
    // Editierweg fuer Uebersetzer - neben Lese- und Parse-Fehlern
    // werfen auch TYPfehler ("name": null, Objekt statt String) erst
    // in OverlayFromJson. Der Vertrag oben heisst "nil bei JEDEM
    // Problem": zurueck auf die einkompilierte Tabelle, statt den
    // Fehler in den Anzeigepfad durchzureichen. (Die halbe Map raeumt
    // OverlayFromJson vor dem re-raise selbst ab.)
    Result := nil;
  end;
  Json.Free;   // Exit oben laeuft nur VOR der Zuweisung (Json = nil)
end;

class function TRuleCatalog.EmbeddedOverlay(const ANorm: string): TOverlayMap;
// Einkompilierte Uebersetzungen aus uRuleCatalogOverlay.inc - im
// IDE-Plugin der Normalfall (die BPL findet die losen JSONs meist nicht,
// s. MakeFallbackMeta). Der Positions-Check unten faengt nur GROBE
// Verrutscher (Luecken, kaputte Generator-Ausgabe): eine STALE Tabelle
// nach einer Enum-Einfuegung in der Mitte besteht ihn, weil der
// Generator immer dicht durchnummeriert - sie truege dann den Text des
// ALTEN Kinds unter der neuen ID. Der wirksame Schutz dagegen sind der
// Konsistenz-Test KindOrdinalMatchesID plus das CI-Gate
// gen-rules-inc.py --check (beide .inc muessen byte-aktuell sein).

  function MapAus(const Tbl: array of TRuleOverlayData): TOverlayMap;
  var
    Idx : Integer;
    Txt : TRuleTextOverlay;
  begin
    Result := TOverlayMap.Create;
    for Idx := 0 to High(Tbl) do
      if SameText(Tbl[Idx].RuleID, Format('SCA%.3d', [Idx + 1])) then
      begin
        Txt.Name             := Tbl[Idx].Name;
        Txt.ShortDescription := Tbl[Idx].ShortDesc;
        Txt.FullDescription  := '';
        Result.AddOrSetValue(Tbl[Idx].RuleID, Txt);
      end;
  end;

begin
  if ANorm = 'de' then
    Result := MapAus(RULE_OVERLAY_DE)
  else if ANorm = 'fr' then
    Result := MapAus(RULE_OVERLAY_FR)
  else
    Result := nil;
end;

class procedure TRuleCatalog.ForEach(AProc: TProc<TRuleMeta>);
var
  K : TFindingKind;
begin
  EnsureLoaded;
  for K := Low(TFindingKind) to High(TFindingKind) do
    AProc(GetRuleCanonical(K));
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
