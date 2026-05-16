unit uExportSonarGeneric;

// SonarQube Generic Issue Format Writer.
//
// Spec: https://docs.sonarsource.com/sonarqube-server/analyzing-source-code/
//       importing-external-issues/generic-issue-import-format
//
// Schreibt eine JSON-Datei mit zwei Top-Level-Arrays:
//   "rules":  Rule-Definitions inkl. cleanCodeAttribute + impacts (MQR-Mode)
//   "issues": pro Finding ein Eintrag mit ruleId + Location
//
// Wird vom sonar-scanner ueber sonar.externalIssuesReportPaths eingelesen.
// Sonar zeigt die Findings als "external_static-code-analyser:SCA001",
// neben Findings aus SonarDelphi / anderen externen Tools.
//
// SARIF parallel: in sonar-project.properties kann zusaetzlich
//   sonar.sarifReportPaths=sca-findings.sarif
// gesetzt werden - Sonar dedupliziert die beiden NICHT, also genau eine
// Quelle nutzen (uExportSARIF ODER diese Unit, nicht beide gleichzeitig).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uMethodd12, uSCAConsts;

const
  SONAR_ENGINE_ID = 'static-code-analyser';

type
  TSonarGenericWriter = class
  public
    // Schreibt einen kompletten Generic-Issue-Report nach FileName.
    //   AFindings - die gefundenen Befunde (Caller behaelt Ownership)
    //   ABaseDir  - Wurzelverzeichnis fuer relative Datei-Pfade.
    //               Sonar erwartet RELATIVE Pfade vom sonar.sources-Root.
    class procedure WriteFile(const AFileName: string;
      const AFindings: TObjectList<TLeakFinding>;
      const ABaseDir: string); static;

    // Variante die direkt einen JSON-String liefert (fuer Tests).
    class function ToJsonString(
      const AFindings: TObjectList<TLeakFinding>;
      const ABaseDir: string): string; static;
  end;

  // Helpers (public fuer Tests).
  function SeverityToSonarImpactSev(S: TLeakSeverity): string;
  function EffortMinutesFor(T: TFindingType): Integer;

implementation

uses
  System.IOUtils, System.JSON, System.StrUtils,
  uRuleCatalog;

{ ---- Helpers ---- }

function MakeRelative(const AFileName, ABaseDir: string): string;
// Mirrors uExportSARIF.MakeRelative: forward slashes, base-prefix-strip.
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
begin
  if not TryStrToInt(S, Result) or (Result < 1) then Result := 1;
end;

function SoftwareQualityName(Q: TSonarSoftwareQuality): string;
begin
  case Q of
    sqSecurity        : Result := 'SECURITY';
    sqReliability     : Result := 'RELIABILITY';
    sqMaintainability : Result := 'MAINTAINABILITY';
  else
    Result := 'MAINTAINABILITY';
  end;
end;

function ImpactSeverityName(S: TSonarImpactSeverity): string;
begin
  case S of
    isBlocker : Result := 'BLOCKER';
    isHigh    : Result := 'HIGH';
    isMedium  : Result := 'MEDIUM';
    isLow     : Result := 'LOW';
    isInfo    : Result := 'INFO';
  else
    Result := 'MEDIUM';
  end;
end;

function SeverityToSonarImpactSev(S: TLeakSeverity): string;
// Per-Finding Severity-Mapping. Wird nur als Fallback genutzt wenn die Rule
// keinen impacts-Array hat (sollte nach P2 nie passieren - der Test
// EveryFindingKindHasMqrMapping enforced das).
begin
  case S of
    lsError   : Result := 'HIGH';
    lsWarning : Result := 'MEDIUM';
    lsHint    : Result := 'LOW';
  else
    Result := 'MEDIUM';
  end;
end;

function EffortMinutesFor(T: TFindingType): Integer;
// Grobe Schaetzungen pro Sonar-Type. Bewusst konservativ - Sonar-Dashboards
// zeigen das als "Technical Debt", zu hohe Werte verzerren das Total.
begin
  case T of
    ftBug             : Result := 20;
    ftVulnerability   : Result := 30;
    ftSecurityHotspot : Result := 30;
    ftCodeSmell       : Result := 10;
    ftCodeDuplication : Result := 15;
    ftFileError       : Result := 0;
  else
    Result := 10;
  end;
end;

{ ---- Rule + Issue Builders ---- }

function BuildRuleObject(const M: TRuleMeta; const IdOverride: string): TJSONObject;
// IdOverride: bei Custom-Rule-Findings (F.RuleID gesetzt) muss die Rule-ID
// im Rules-Array zur Issue.ruleId passen, sonst kann Sonar die Eintraege
// nicht koppeln und ignoriert die MQR-Felder.
var
  Impacts : TJSONArray;
  IObj    : TJSONObject;
  I       : TSonarImpact;
begin
  Result := TJSONObject.Create;
  if IdOverride <> '' then
    Result.AddPair('id', IdOverride)
  else
    Result.AddPair('id', M.ID);
  Result.AddPair('name',         IfThen(M.Name <> '', M.Name, KindName(M.Kind)));
  Result.AddPair('description',  IfThen(M.FullDescription <> '',
                                         M.FullDescription, M.ShortDescription));
  Result.AddPair('engineId',     SONAR_ENGINE_ID);

  // MQR-Felder (P2: in jedem Catalog-Eintrag vorhanden)
  if M.CleanCodeAttribute <> '' then
    Result.AddPair('cleanCodeAttribute', M.CleanCodeAttribute);

  if Length(M.Impacts) > 0 then
  begin
    Impacts := TJSONArray.Create;
    for I in M.Impacts do
    begin
      IObj := TJSONObject.Create;
      IObj.AddPair('softwareQuality', SoftwareQualityName(I.SoftwareQuality));
      IObj.AddPair('severity',        ImpactSeverityName(I.Severity));
      Impacts.AddElement(IObj);
    end;
    Result.AddPair('impacts', Impacts);
  end;
end;

function BuildIssueObject(const F: TLeakFinding; const ABaseDir: string;
  const M: TRuleMeta): TJSONObject;
var
  Loc, Range, ResultObj : TJSONObject;
  RuleID : string;
  LineNo : Integer;
  Msg    : string;
begin
  // Custom-Rule-IDs (z.B. 'PROJ001') gewinnen gegen den Catalog-Lookup -
  // sonst die built-in ID aus dem Catalog.
  if F.RuleID <> '' then RuleID := F.RuleID
  else RuleID := M.ID;
  LineNo := ParseLineNumber(F.LineNumber);
  Msg := F.MissingVar;
  if Msg = '' then Msg := M.ShortDescription;

  Result := TJSONObject.Create;
  Result.AddPair('engineId', SONAR_ENGINE_ID);
  Result.AddPair('ruleId',   RuleID);

  if EffortMinutesFor(M.FindingType) > 0 then
    Result.AddPair('effortMinutes',
      TJSONNumber.Create(EffortMinutesFor(M.FindingType)));

  // primaryLocation - Pflichtfeld
  Loc := TJSONObject.Create;
  Loc.AddPair('message',  Msg);
  Loc.AddPair('filePath', MakeRelative(F.FileName, ABaseDir));

  Range := TJSONObject.Create;
  Range.AddPair('startLine', TJSONNumber.Create(LineNo));
  Loc.AddPair('textRange', Range);

  Result.AddPair('primaryLocation', Loc);
end;

{ ---- TSonarGenericWriter ---- }

class function TSonarGenericWriter.ToJsonString(
  const AFindings: TObjectList<TLeakFinding>;
  const ABaseDir: string): string;
var
  Root    : TJSONObject;
  Rules   : TJSONArray;
  Issues  : TJSONArray;
  F       : TLeakFinding;
  Meta    : TRuleMeta;
  Seen    : TDictionary<string, Boolean>;
  RuleID  : string;
begin
  Root   := TJSONObject.Create;
  Rules  := TJSONArray.Create;
  Issues := TJSONArray.Create;
  Seen   := TDictionary<string, Boolean>.Create;
  try
    // Issues + verwendete Rule-IDs sammeln
    for F in AFindings do
    begin
      Meta := TRuleCatalog.GetRule(F.Kind);
      Issues.AddElement(BuildIssueObject(F, ABaseDir, Meta));

      // Rule-Sammlung (deduped): bei Custom-Rules gewinnt F.RuleID
      if F.RuleID <> '' then RuleID := F.RuleID
      else RuleID := Meta.ID;
      if (RuleID <> '') and not Seen.ContainsKey(RuleID) then
      begin
        Seen.Add(RuleID, True);
        // Bei Custom-Rule (F.RuleID gesetzt, z.B. 'PROJ042') muss die
        // Rules-Array-ID dazu passen, sonst kann Sonar das Issue nicht zur
        // Rule koppeln. Override-ID nur weiterreichen wenn F.RuleID gesetzt
        // war - sonst gewinnt die Catalog-ID.
        if F.RuleID <> '' then
          Rules.AddElement(BuildRuleObject(Meta, F.RuleID))
        else
          Rules.AddElement(BuildRuleObject(Meta, ''));
      end;
    end;

    Root.AddPair('rules',  Rules);
    Root.AddPair('issues', Issues);
    Result := Root.Format(2);
  finally
    Root.Free;
    Seen.Free;
  end;
end;

class procedure TSonarGenericWriter.WriteFile(const AFileName: string;
  const AFindings: TObjectList<TLeakFinding>;
  const ABaseDir: string);
begin
  TFile.WriteAllText(AFileName, ToJsonString(AFindings, ABaseDir),
    TEncoding.UTF8);
end;

end.
