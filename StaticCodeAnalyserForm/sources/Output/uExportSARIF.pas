unit uExportSARIF;

// SARIF v2.1.0 Export.
//
// SARIF (Static Analysis Results Interchange Format) ist der OASIS-Standard
// fuer Static-Analysis-Tool-Output. Wird nativ verarbeitet von:
//   * GitHub Code-Scanning (Findings als PR-Annotationen)
//   * Azure DevOps Pipelines
//   * Visual Studio Code (mit SARIF-Extension)
//   * SonarCloud / SonarQube (via Plugin)
//
// Schema-Referenz: https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html
// JSON-Schema:     https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json
//
// Output-Struktur (Minimal-Variante, alle Pflichtfelder):
//   runs[0].tool.driver { name, version, informationUri, rules[] }
//   runs[0].results[]   { ruleId, level, message, locations[], partialFingerprints }
//
// `partialFingerprints` ist optional aber HOCHEMPFOHLEN: GitHub nutzt das
// fuer Cross-Commit-Deduplizierung, damit Findings nicht doppelt erscheinen
// wenn ein File auf einer Branch in mehreren Commits vorkommt.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uMethodd12;

type
  TSARIFWriter = class
  public
    // Schreibt einen kompletten SARIF-Report nach FileName.
    //   AFindings   - die gefundenen Befunde (Caller behaelt Ownership)
    //   ABaseDir    - Wurzelverzeichnis fuer relative Datei-Pfade
    //                 (typisch: das --path-Argument). Pfade in den
    //                 Findings die NICHT mit ABaseDir beginnen, werden
    //                 als absolute Pfade ausgegeben (file:// URI).
    //   AToolVersion- Version-String fuer tool.driver.version
    //   AToolName   - Name-String fuer tool.driver.name
    class procedure WriteFile(const AFileName: string;
      const AFindings: TObjectList<TLeakFinding>;
      const ABaseDir, AToolVersion, AToolName: string); static;

    // Variante die direkt einen JSON-String liefert (fuer Tests).
    class function ToJsonString(
      const AFindings: TObjectList<TLeakFinding>;
      const ABaseDir, AToolVersion, AToolName: string): string; static;
  end;

implementation

uses
  System.IOUtils, System.JSON, System.Hash, System.StrUtils,
  uSCAConsts, uRuleCatalog;

{ ---- Helpers ---- }

function SeverityToSarifLevel(S: TLeakSeverity; K: TFindingKind): string;
// SARIF level: "error" | "warning" | "note" | "none".
// FileReadError ist immer Error (Tool kommt nicht weiter).
begin
  if K = fkFileReadError then Exit('error');
  case S of
    lsError   : Result := 'error';
    lsWarning : Result := 'warning';
    lsHint    : Result := 'note';
  else
    Result := 'warning';
  end;
end;

function MakeRelative(const AFileName, ABaseDir: string): string;
// Liefert AFileName relativ zu ABaseDir wenn moeglich, sonst unveraendert.
// Forward-Slashes (SARIF-Konvention, GitHub erwartet das fuer File-Annotation).
var
  Base, Full, Rel : string;
begin
  if (ABaseDir = '') or (AFileName = '') then
    Exit(StringReplace(AFileName, '\', '/', [rfReplaceAll]));
  Base := IncludeTrailingPathDelimiter(TPath.GetFullPath(ABaseDir));
  Full := TPath.GetFullPath(AFileName);
  if SameText(Copy(Full, 1, Length(Base)), Base) then
    Rel := Copy(Full, Length(Base) + 1, MaxInt)
  else
    Rel := Full;
  Result := StringReplace(Rel, '\', '/', [rfReplaceAll]);
end;

function ParseLineNumber(const S: string): Integer;
// LineNumber kommt im TLeakFinding als String - SARIF braucht Integer.
// Bei Parse-Fehler 1 (SARIF erlaubt nicht 0).
begin
  if not TryStrToInt(S, Result) or (Result < 1) then
    Result := 1;
end;

function FingerprintHash(const RuleID, RelPath: string; LineNo: Integer;
  const Message: string): string;
// SHA256 ueber RuleID + Pfad + Zeile + Message - GitHub nutzt das fuer
// Cross-Commit-Dedup. Identische Findings auf demselben Pfad/Zeile
// werden nicht doppelt angezeigt.
var
  Bytes : TBytes;
  Hash  : string;
begin
  Bytes := TEncoding.UTF8.GetBytes(
    RuleID + '|' + RelPath + '|' + IntToStr(LineNo) + '|' + Message);
  Hash := THashSHA2.GetHashString(TEncoding.UTF8.GetString(Bytes));
  Result := Hash;
end;

function BuildRulesArray: TJSONArray;
// runs[0].tool.driver.rules[] - alle Catalog-Eintraege als SARIF-Rules.
var
  Arr : TJSONArray;
begin
  Arr := TJSONArray.Create;

  TRuleCatalog.ForEach(
    procedure(M: TRuleMeta)
    var
      ROut   : TJSONObject;
      RShort : TJSONObject;
      RFull  : TJSONObject;
      RConf  : TJSONObject;
      RProp  : TJSONObject;
      Tags   : TJSONArray;
      S      : string;
    begin
      ROut := TJSONObject.Create;
      ROut.AddPair('id', M.ID);
      ROut.AddPair('name', IfThen(M.Name <> '', M.Name, KindName(M.Kind)));

      RShort := TJSONObject.Create;
      RShort.AddPair('text', IfThen(M.ShortDescription <> '',
                                    M.ShortDescription, M.Name));
      ROut.AddPair('shortDescription', RShort);

      if M.FullDescription <> '' then
      begin
        RFull := TJSONObject.Create;
        RFull.AddPair('text', M.FullDescription);
        ROut.AddPair('fullDescription', RFull);
      end;

      // Default-Configuration: Severity-Level
      RConf := TJSONObject.Create;
      RConf.AddPair('level',
        SeverityToSarifLevel(M.DefaultSeverity, M.Kind));
      ROut.AddPair('defaultConfiguration', RConf);

      // Properties: tags + cwe + owasp
      RProp := TJSONObject.Create;
      Tags := TJSONArray.Create;
      for S in M.Tags  do Tags.AddElement(TJSONString.Create(S));
      for S in M.CWE   do Tags.AddElement(TJSONString.Create(S));
      for S in M.OWASP do Tags.AddElement(TJSONString.Create(S));
      RProp.AddPair('tags', Tags);
      if M.DetectorUnit <> '' then
        RProp.AddPair('detectorUnit', M.DetectorUnit);
      if M.ConfigKey <> '' then
        RProp.AddPair('configKey', M.ConfigKey);
      ROut.AddPair('properties', RProp);

      // Help-URI: GitHub zeigt das im Detail-Panel - Anker auf konsoli-
      // dierte docs/rules.md (per-file SCA001.md generiert tools/gen-rules-
      // docs.py wenn Python verfuegbar; bis dahin Anker-Links).
      ROut.AddPair('helpUri', Format('%s/blob/main/docs/rules.md#%s',
        [TRuleCatalog.ToolUri, LowerCase(M.ID)]));

      Arr.AddElement(ROut);
    end);

  Result := Arr;
end;

function BuildResultsArray(const AFindings: TObjectList<TLeakFinding>;
  const ABaseDir: string): TJSONArray;
var
  Arr     : TJSONArray;
  F       : TLeakFinding;
  ResObj  : TJSONObject;
  MsgObj  : TJSONObject;
  Locs    : TJSONArray;
  Loc     : TJSONObject;
  PhysLoc : TJSONObject;
  ArtLoc  : TJSONObject;
  Region  : TJSONObject;
  FpObj   : TJSONObject;
  RelPath : string;
  LineNo  : Integer;
  Meta    : TRuleMeta;
  Msg     : string;
  RuleID  : string;
begin
  Arr := TJSONArray.Create;
  for F in AFindings do
  begin
    Meta    := TRuleCatalog.GetRule(F.Kind);
    RelPath := MakeRelative(F.FileName, ABaseDir);
    LineNo  := ParseLineNumber(F.LineNumber);
    Msg     := F.MissingVar;
    if Msg = '' then
      Msg := Meta.ShortDescription;
    // Custom-Rule-IDs (z.B. 'PROJ001') gewinnen gegen Catalog-Lookup -
    // sonst built-in Rule-ID aus dem Catalog.
    if F.RuleID <> '' then RuleID := F.RuleID
    else RuleID := Meta.ID;

    ResObj := TJSONObject.Create;
    ResObj.AddPair('ruleId', RuleID);
    ResObj.AddPair('level', SeverityToSarifLevel(F.Severity, F.Kind));

    MsgObj := TJSONObject.Create;
    MsgObj.AddPair('text', Msg);
    ResObj.AddPair('message', MsgObj);

    // physicalLocation/artifactLocation/region
    Region := TJSONObject.Create;
    Region.AddPair('startLine', TJSONNumber.Create(LineNo));

    ArtLoc := TJSONObject.Create;
    ArtLoc.AddPair('uri', RelPath);

    PhysLoc := TJSONObject.Create;
    PhysLoc.AddPair('artifactLocation', ArtLoc);
    PhysLoc.AddPair('region', Region);

    Loc := TJSONObject.Create;
    Loc.AddPair('physicalLocation', PhysLoc);

    Locs := TJSONArray.Create;
    Locs.AddElement(Loc);
    ResObj.AddPair('locations', Locs);

    // partialFingerprints fuer GitHub-Dedup
    FpObj := TJSONObject.Create;
    FpObj.AddPair('primaryLocationLineHash',
      FingerprintHash(RuleID, RelPath, LineNo, Msg));
    ResObj.AddPair('partialFingerprints', FpObj);

    Arr.AddElement(ResObj);
  end;
  Result := Arr;
end;

{ ---- Public API ---- }

class function TSARIFWriter.ToJsonString(
  const AFindings: TObjectList<TLeakFinding>;
  const ABaseDir, AToolVersion, AToolName: string): string;
var
  Root   : TJSONObject;
  Runs   : TJSONArray;
  Run    : TJSONObject;
  Tool   : TJSONObject;
  Driver : TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('$schema',
      'https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json');
    Root.AddPair('version', '2.1.0');

    Driver := TJSONObject.Create;
    Driver.AddPair('name',
      IfThen(AToolName <> '', AToolName, TRuleCatalog.ToolName));
    Driver.AddPair('version',
      IfThen(AToolVersion <> '', AToolVersion, TRuleCatalog.ToolVersion));
    if TRuleCatalog.ToolUri <> '' then
      Driver.AddPair('informationUri', TRuleCatalog.ToolUri);
    Driver.AddPair('rules', BuildRulesArray);

    Tool := TJSONObject.Create;
    Tool.AddPair('driver', Driver);

    Run := TJSONObject.Create;
    Run.AddPair('tool', Tool);
    Run.AddPair('results', BuildResultsArray(AFindings, ABaseDir));

    Runs := TJSONArray.Create;
    Runs.AddElement(Run);
    Root.AddPair('runs', Runs);

    Result := Root.Format(2); // pretty-printed, 2 spaces
  finally
    Root.Free;
  end;
end;

class procedure TSARIFWriter.WriteFile(const AFileName: string;
  const AFindings: TObjectList<TLeakFinding>;
  const ABaseDir, AToolVersion, AToolName: string);
var
  S : string;
begin
  S := ToJsonString(AFindings, ABaseDir, AToolVersion, AToolName);
  // UTF-8 ohne BOM (GitHub bevorzugt das, parser sind toleranter ohne).
  TFile.WriteAllText(AFileName, S, TEncoding.UTF8);
end;

end.
