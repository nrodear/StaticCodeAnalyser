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
//
// NICHT exportiert werden Lauf-Diagnosen (fkFileReadError): weder als
// issue noch als rule. Sie sagen etwas ueber die Vollstaendigkeit des
// Laufs, nicht ueber den Quelltext, und niemand kann sie im Dashboard
// beheben - dort waren sie reines INFO-Rauschen. Unberuehrt bleiben
// Konsolen-Ausgabe, Exit-Code 4, HTML-Report und Health-Score; SARIF
// fuehrt sie zusaetzlich in invocations[].toolExecutionNotifications.
// Ein Lauf, der NUR Lesefehler hat, ergibt {"rules":[],"issues":[]} -
// gueltiges JSON, das Sonar akzeptiert.

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
    // Liefert die Anzahl der Issues, deren Pfad ausserhalb von ABaseDir lag
    // und deshalb absolut blieb - Sonar verwirft die still als "unknown
    // files", der Aufrufer sollte das melden.
    class function WriteFile(const AFileName: string;
      const AFindings: TObjectList<TLeakFinding>;
      const ABaseDir: string): Integer; static;

    // Variante die direkt einen JSON-String liefert (fuer Tests).
    class function ToJsonString(
      const AFindings: TObjectList<TLeakFinding>;
      const ABaseDir: string): string; static;
  end;

  // Helpers (public fuer Tests).
  function SeverityToSonarImpactSev(S: TLeakSeverity): string;
  function EffortMinutesFor(T: TFindingType): Integer;

implementation

// noinspection-file BeginEndRequired, CanBeStrictPrivate, ConsecutiveSection, DuplicateString, GroupedDeclaration, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.Classes,          // TStream/TFileStream/TStringStream fuer EmitReport
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

function FallbackSoftwareQuality(T: TFindingType): string;
// Software-Quality fuer den Fallback-Pfad (Catalog liefert keine impacts).
// Hotspot mappt auf SECURITY - Sonar trennt Hotspot vs. Vulnerability nur
// fuer eigene Detektoren; FileError/CodeDuplication auf MAINTAINABILITY.
begin
  case T of
    ftBug             : Result := 'RELIABILITY';
    ftVulnerability   : Result := 'SECURITY';
    ftSecurityHotspot : Result := 'SECURITY';
  else
    Result := 'MAINTAINABILITY';
  end;
end;

function FallbackCleanCodeAttribute(T: TFindingType): string;
// Clean-Code-Attribut fuer den Fallback-Pfad. Bewusst grob: die feine
// Zuordnung steht im Katalog, hier geht es nur darum, ein GUELTIGES
// Pflichtfeld zu liefern statt gar keins.
begin
  case T of
    ftBug             : Result := 'LOGICAL';
    ftVulnerability   : Result := 'TRUSTWORTHY';
    ftSecurityHotspot : Result := 'TRUSTWORTHY';
  else
    Result := 'CONVENTIONAL';
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

  // M.Impacts ist Field-Access auf den Catalog-Eintrag, nicht die lokale
  // Var Impacts - SCA166-Identifier-Recognition unterscheidet das nicht.
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
  end
  else
  begin
    // Fallback: Catalog hat keinen Impact-Eintrag fuer diese Rule - typisch
    // wenn rules/sca-rules.json beim Lauf nicht gefunden wurde und
    // LoadFallback eingesprungen ist. GENAU DAS ist der Auslieferungs-
    // zustand des Release-ZIPs (nur die EXE, kein rules/).
    //
    // Hier stand bis 2026-08-08 das Legacy-Feld 'type'. Das reicht NICHT:
    // gegen die echten Scanner-Engine-Validatoren geprueft lehnt SonarQube
    // den GESAMTEN Report ab - 10.7 mit "missing mandatory field
    // 'cleanCodeAttribute'", 2025.x mit "missing mandatory field
    // 'severity'". Von den getesteten Varianten validiert nur diese auf
    // ALLEN Engine-Generationen: dieselben MQR-Felder wie im Normalpfad,
    // nur aus FindingType/DefaultSeverity abgeleitet statt aus dem Katalog.
    Result.AddPair('cleanCodeAttribute',
      FallbackCleanCodeAttribute(M.FindingType));
    Impacts := TJSONArray.Create;
    IObj := TJSONObject.Create;
    IObj.AddPair('softwareQuality', FallbackSoftwareQuality(M.FindingType));
    IObj.AddPair('severity',        SeverityToSonarImpactSev(M.DefaultSeverity));
    Impacts.AddElement(IObj);
    Result.AddPair('impacts', Impacts);
  end;
end;

function BuildIssueObject(const F: TLeakFinding; const ARelPath: string;
  const M: TRuleMeta): TJSONObject;
// ARelPath statt ABaseDir: der Aufrufer hat MakeRelative ohnehin schon
// gerufen, um Pfade ausserhalb der Wurzel zu zaehlen. Zweimal relativieren
// hiesse zweimal TPath.GetFullPath pro Fund - genau die Arbeit, die P4
// aus dem Hot-Path entfernt hat.
var
  Loc, Range : TJSONObject;
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
  Loc.AddPair('filePath', ARelPath);

  Range := TJSONObject.Create;
  Range.AddPair('startLine', TJSONNumber.Create(LineNo));
  // endLine nur, wenn der Fund wirklich mehrzeilig ist. Sonar erlaubt
  // endLine < startLine nicht, und ein endLine = startLine waere reines
  // Rauschen. Gleiche Bedingung wie im SARIF-Pfad - dort kam sie mit der
  // Mehrzeilen-Welle, der Sonar-Report hatte sie nie und zeigte jeden
  // mehrzeiligen Fund als Einzeiler.
  if F.EndLine > LineNo then
    Range.AddPair('endLine', TJSONNumber.Create(F.EndLine));
  Loc.AddPair('textRange', Range);

  Result.AddPair('primaryLocation', Loc);
end;

function PathLeftAbsolute(const ARelPath: string): Boolean;
// True, wenn MakeRelative den Pfad NICHT relativieren konnte - die Datei
// liegt ausserhalb von --base-dir. Sonar verwirft solche Issues still als
// "unknown files"; der Fund ist dann weg, ohne dass irgendwo etwas steht.
// MakeRelative liefert Vorwaerts-Schraegstriche, ein absoluter Windows-Pfad
// beginnt also mit 'X:/' oder mit '//' (UNC).
begin
  Result := ((Length(ARelPath) >= 3) and (ARelPath[2] = ':')) or
            StartsStr('//', ARelPath);
end;

{ ---- TSonarGenericWriter ---- }

procedure WStr(AStream: TStream; const S: string);
// Rohe UTF-8-Bytes in den Stream. Kein BOM, keine Praeambel.
var
  B : TBytes;
begin
  B := TEncoding.UTF8.GetBytes(S);
  if Length(B) > 0 then AStream.WriteBuffer(B[0], Length(B));
end;

procedure WObj(AStream: TStream; AObj: TJSONObject);
// Serialisiert EIN Element und gibt es sofort frei.
//
// NICHT Format(2) und NICHT ToJSON([]) (2026-08-05): Format ruft ToChars mit
// LEEREN Options (System.JSON.pas:1609), und ToChars escaped Unicode-Escapes
// nur, wenn EncodeBelow32 gesetzt ist (:2629). Ohne die Option gehen #0..#7,
// #$B und #$E..#$1F ROH in die Datei - RFC 8259 verlangt fuer
// U+0000..U+001F aber Escaping, und SonarQube bricht beim ERSTEN solchen
// Zeichen ab. Nicht das eine Issue faellt dann weg, sondern der GESAMTE
// Report.
//
// Belegt im Repo: ein Fund aus unserer eigenen Quelle trug als Meldung
// "edToken.PasswordChar = '<U+0000>'" (aus 'edToken.PasswordChar := #0;').
// Der Lexer loest Char-Literale in echte Zeichen auf (uLexer.pas:531),
// uHardcodedSecret uebernimmt den Wert unveraendert. Ein einziges #0
// irgendwo im Kundencode genuegt.
begin
  try
    WStr(AStream, AObj.ToJSON([TJSONAncestor.TJSONOutputOption.EncodeBelow32]));
  finally
    AObj.Free;
  end;
end;

procedure EmitRules(AStream: TStream;
  const AFindings: TObjectList<TLeakFinding>);
// rules[] in der Reihenfolge des ersten Auftretens - genau die Reihenfolge,
// die der fruehere DOM-Aufbau erzeugte, weil der die Regeln waehrend der
// Issue-Schleife einsammelte.
var
  Seen   : TDictionary<string, Boolean>;
  F      : TLeakFinding;
  Meta   : TRuleMeta;
  RuleID : string;
  First  : Boolean;
begin
  Seen  := TDictionary<string, Boolean>.Create;
  First := True;
  try
    for F in AFindings do
    begin
      if F.Kind = fkFileReadError then Continue;
      Meta := TRuleCatalog.GetRule(F.Kind);
      if F.RuleID <> '' then RuleID := F.RuleID
      else RuleID := Meta.ID;
      if (RuleID = '') or Seen.ContainsKey(RuleID) then Continue;
      Seen.Add(RuleID, True);
      if not First then WStr(AStream, ',');
      First := False;
      // F.RuleID leer -> BuildRuleObject nimmt die Katalog-ID. Der frueher
      // hier stehende if/else war zwei Wege zum selben Aufruf.
      WObj(AStream, BuildRuleObject(Meta, F.RuleID));
    end;
  finally
    Seen.Free;
  end;
end;

function EmitIssues(AStream: TStream;
  const AFindings: TObjectList<TLeakFinding>;
  const ABaseDir: string): Integer;
// issues[]. Liefert die Anzahl der Pfade, die ausserhalb von ABaseDir lagen
// und deshalb absolut blieben.
var
  F       : TLeakFinding;
  Meta    : TRuleMeta;
  RelPath : string;
  First   : Boolean;
begin
  Result := 0;
  First  := True;
  for F in AFindings do
  begin
    if F.Kind = fkFileReadError then Continue;
    Meta    := TRuleCatalog.GetRule(F.Kind);
    RelPath := MakeRelative(F.FileName, ABaseDir);
    if PathLeftAbsolute(RelPath) then Inc(Result);
    if not First then WStr(AStream, ',');
    First := False;
    WObj(AStream, BuildIssueObject(F, RelPath, Meta));
  end;
end;

procedure EmitReport(AStream: TStream;
  const AFindings: TObjectList<TLeakFinding>;
  const ABaseDir: string; out AOutsideBase: Integer);
// Schreibt den kompletten Report direkt in AStream, ohne ihn vorher als
// Ganzes im Speicher zu halten.
//
// WARUM elementweise und nicht als eigener Emitter: die Escaping-Regeln der
// RTL sind nicht nachbaubar - TJSONObject escaped unter anderem den
// Schraegstrich (im Referenz-Report von 2026-08-09 nachgewiesen). Ein
// handgeschriebener Serialisierer haette gueltiges, aber ANDERES JSON
// erzeugt, und jeder Byte-Vergleich gegen aeltere Reports waere wertlos
// geworden. Deshalb serialisiert weiterhin TJSONObject jedes einzelne
// Element - im Speicher liegt nur noch EIN Issue statt aller. Das Geruest
// ist trivial und byte-identisch zum frueheren Root.ToJSON.
//
// Zwei Durchlaeufe ueber die Findings: der erste schreibt die Regeln, der
// zweite die Issues. Der Preis ist ein Enum-Vergleich und ein
// Katalog-Lookup pro Fund - gemessen an einem kompletten zweiten Abbild im
// Speicher ist das nichts.
begin
  WStr(AStream, '{"rules":[');
  EmitRules(AStream, AFindings);
  WStr(AStream, '],"issues":[');
  AOutsideBase := EmitIssues(AStream, AFindings, ABaseDir);
  WStr(AStream, ']}');
end;

class function TSonarGenericWriter.ToJsonString(
  const AFindings: TObjectList<TLeakFinding>;
  const ABaseDir: string): string;
// String-Variante fuer Tests und GUI-Pfade. Hier liegt der Report
// naturgemaess komplett im Speicher - das ist der Sinn eines Strings.
// Entscheidend ist, dass beide Wege DENSELBEN Emitter benutzen: sonst
// pruefen die Tests eine Ausgabe, die so nie in einer Datei landet.
var
  SS      : TStringStream;
  Dummy   : Integer;
begin
  SS := TStringStream.Create('', TEncoding.UTF8);
  try
    EmitReport(SS, AFindings, ABaseDir, Dummy);
    Result := SS.DataString;
  finally
    SS.Free;
  end;
end;

class function TSonarGenericWriter.WriteFile(const AFileName: string;
  const AFindings: TObjectList<TLeakFinding>;
  const ABaseDir: string): Integer;
// Liefert die Anzahl der Issues, deren Pfad NICHT relativiert werden konnte.
var
  FS  : TFileStream;
  Dir : string;
begin
  // Zielverzeichnis bei Bedarf anlegen - dieselbe Asymmetrie, ueber die der
  // SARIF-Pfad gestolpert ist: --sonar-export in einen frischen build/-Ordner
  // brach sonst hart ab.
  Dir := ExtractFilePath(AFileName);
  if (Dir <> '') and not TDirectory.Exists(Dir) then
    ForceDirectories(Dir);

  // Direkt in den Stream statt ueber ToJsonString: der Report entsteht damit
  // elementweise. Vorher lag er zweimal komplett im Speicher (einmal als
  // TJSONObject-Baum, einmal als String) - bei einem grossen Korpus ist das
  // genau die Klasse Problem, an der der 32-Bit-Build bei 2 GB abbricht.
  //
  // KEIN BOM (2026-08-08): RFC 8259 par.8.1 verbietet die Praeambel fuer
  // JSON-Austausch. SonarQube verzeiht sie, jedes jq/Node-Skript in der
  // Kette nicht. Wir schreiben rohe UTF-8-Bytes, also entsteht gar keine.
  FS := TFileStream.Create(AFileName, fmCreate);
  try
    EmitReport(FS, AFindings, ABaseDir, Result);
  finally
    FS.Free;
  end;
end;

end.
