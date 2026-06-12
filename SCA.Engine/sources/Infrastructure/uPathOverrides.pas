unit uPathOverrides;

// Per-Pfad-Filter / Severity-Override (siehe README "PathOverrides").
//
// Loest das "Test-Code-Noise"-Problem ohne Profile-Schwund: Findings auf
// bestimmten Pfaden werden runtergestuft oder komplett unterdrueckt,
// waehrend das Profile alle Detektoren scharf laesst.
//
// INI-Format (analyser.ini):
//
//   [PathOverrides]
//   ; Glob-Pattern (Forward- oder Backslashes; case-insensitive). Erste
//   ; Match-Zeile gewinnt. Aktions-Syntax (kommasepariert mehrere
//   ; Aktionen moeglich):
//   ;
//   ;   drop:*                 - Alle Findings auf diesem Pfad droppen
//   ;   drop:KindA,KindB,...   - Nur diese Kinds droppen
//   ;   severity:hint:Kind     - Severity downgrade fuer diese Kinds
//   ;   severity:warn:Kind     - "
//   ;   severity:error:Kind    - " (eskaliert nur falls niedriger)
//   ;
//   ; Beispiele:
//   tests\**.pas               = drop:*
//   **\test_*.pas              = drop:MissingFinally,MagicNumber
//   demos\legacy\**.pas        = drop:LongMethod,DeepNesting,CyclomaticComplexity
//   src\generated\**.pas       = severity:hint:*
//
// Apply-Reihenfolge im Analyzer-Pipeline:
//   1. Detector-Loop emittiert Findings
//   2. uSuppression.ApplyToFindings (// noinspection)
//   3. uPathOverrides.ApplyToFindings (diese Unit)
//
// Globs werden ueber System.Masks.TMask geprueft. Backslash <-> Slash
// werden normalisiert; `**` matcht beliebige Unterverzeichnis-Tiefe.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12;

type
  TPathOverrideAction = (poaDrop, poaSeverityHint, poaSeverityWarn, poaSeverityError);

  TPathOverrideRule = record
    Glob       : string;              // Original-Glob (zur Diagnose)
    Action     : TPathOverrideAction;
    Kinds      : TFindingKinds;       // leer = alle (Wildcard "*")
    KindsAll   : Boolean;             // True wenn "*"
  end;

  TPathOverrides = class
  public
    // Laed [PathOverrides]-Section aus analyser.ini.
    // Idempotent: vorhandene Rules werden ueberschrieben.
    class procedure Load(const IniPath: string); static;

    // Wendet alle Rules auf die Finding-Liste an. Findings auf
    // Match-Pfaden werden je nach Action entfernt oder die Severity
    // angepasst. Idempotent; mehrmaliger Aufruf ist sicher.
    class procedure ApplyToFindings(Findings: TObjectList<TLeakFinding>); static;

    // Manuelles Hinzufuegen (fuer Tests).
    class procedure AddRule(const Glob: string;
      Action: TPathOverrideAction; const Kinds: TFindingKinds;
      KindsAll: Boolean); static;

    // Komplett-Reset (Tests).
    class procedure Clear; static;

    // Anzahl Rules - hauptsaechlich fuer Tests / Diagnose.
    class function RuleCount: Integer; static;
  end;

implementation

// noinspection-file MultipleExit
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.Masks, System.StrUtils, System.IniFiles;

var
  GRules : TList<TPathOverrideRule> = nil;

function NormalizePath(const APath: string): string;
// Backslash-zu-Slash damit ein einziger Glob beide OS-Konventionen
// matched. Auch ToLower fuer case-insensitive Match (Windows-Default).
begin
  Result := LowerCase(StringReplace(APath, '\', '/', [rfReplaceAll]));
end;

function ParseAction(const Token: string; out Action: TPathOverrideAction;
  out KindsList: string): Boolean;
// Parsed "drop:..." / "severity:hint:..." / "severity:warn:..." /
// "severity:error:...".
var
  Parts : TArray<string>;
begin
  Result := False;
  Parts := Token.Split([':']);
  if Length(Parts) < 2 then Exit;

  if SameText(Parts[0], 'drop') then
  begin
    Action := poaDrop;
    KindsList := Parts[1];
    Exit(True);
  end;

  if SameText(Parts[0], 'severity') and (Length(Parts) >= 3) then
  begin
    if SameText(Parts[1], 'hint')  then Action := poaSeverityHint
    else if SameText(Parts[1], 'warn')  then Action := poaSeverityWarn
    else if SameText(Parts[1], 'error') then Action := poaSeverityError
    else Exit;
    KindsList := Parts[2];
    Exit(True);
  end;
end;

procedure ParseKindList(const Raw: string; out Kinds: TFindingKinds;
  out KindsAll: Boolean);
var
  Item    : string;
  Trimmed : string;
  K       : TFindingKind;
begin
  Kinds    := [];
  KindsAll := False;
  if Trim(Raw) = '*' then begin KindsAll := True; Exit; end;
  for Item in Raw.Split([',', ';']) do
  begin
    Trimmed := Trim(Item);
    if Trimmed = '' then Continue;
    if Trimmed = '*' then begin KindsAll := True; Exit; end;
    if KindFromName(Trimmed, K) then
      Include(Kinds, K);
    // Unbekannte Kinds werden still ignoriert - User-INI darf vorausschauend
    // Rules fuer noch-nicht-implementierte Detektoren enthalten.
  end;
end;

class procedure TPathOverrides.Load(const IniPath: string);
var
  Ini       : TMemIniFile;
  Section   : TStringList;
  KeyName   : string;
  RawValue  : string;
  Token     : string;
  Action    : TPathOverrideAction;
  KindsList : string;
  Rule      : TPathOverrideRule;
begin
  if GRules = nil then GRules := TList<TPathOverrideRule>.Create;
  GRules.Clear;
  if (IniPath = '') or not FileExists(IniPath) then Exit;

  Ini := TMemIniFile.Create(IniPath, TEncoding.UTF8);
  Section := TStringList.Create;
  try
    Ini.ReadSection('PathOverrides', Section);
    for KeyName in Section do
    begin
      RawValue := Ini.ReadString('PathOverrides', KeyName, '');
      if Trim(RawValue) = '' then Continue;

      // Mehrere Aktionen kommasepariert moeglich (z.B.
      //   path = drop:LongMethod,severity:hint:MissingFinally)
      // wird wegen Komma-Konflikt mit Kind-Liste komplexer - fuer MVP
      // erstmal NUR eine Aktion pro Pfad. Erste passende gewinnt.
      Token := Trim(RawValue);
      if not ParseAction(Token, Action, KindsList) then Continue;

      Rule.Glob   := KeyName;
      Rule.Action := Action;
      ParseKindList(KindsList, Rule.Kinds, Rule.KindsAll);
      GRules.Add(Rule);
    end;
  finally
    Section.Free;
    Ini.Free;
  end;
end;

function MatchesGlob(const Glob, Path: string): Boolean;
// `**` als Tiefen-Wildcard erfordert Sonder-Behandlung - System.Masks
// kennt nur `*` als single-segment-Wildcard. Trick: ersetze `**` durch
// einen Marker, dann `*` durch was-auch-immer, dann den Marker zurueck.
// Praktisch matcht der Code:
//   tests/**.pas  ->  tests/* gefolgt von .pas in beliebiger Tiefe
var
  GlobN, PathN : string;
begin
  GlobN := NormalizePath(Glob);
  PathN := NormalizePath(Path);

  // Heuristik: wenn `**` im Pattern -> nutze MatchesMask mit `*`
  //            das matcht segment-uebergreifend.
  if Pos('**', GlobN) > 0 then
    GlobN := StringReplace(GlobN, '**', '*', [rfReplaceAll]);

  try
    Result := MatchesMask(PathN, GlobN);
  except
    Result := False; // Defekt-Mask -> kein Match (defensiv)
  end;
end;

class procedure TPathOverrides.ApplyToFindings(Findings: TObjectList<TLeakFinding>);
var
  i    : Integer;
  F    : TLeakFinding;
  Rule : TPathOverrideRule;
  RuleHit : Boolean;
begin
  if (GRules = nil) or (GRules.Count = 0) then Exit;
  if Findings = nil then Exit;

  for i := Findings.Count - 1 downto 0 do  // rueckwaerts wegen Remove
  begin
    F := Findings[i];
    if F.FileName = '' then Continue;

    RuleHit := False;
    for Rule in GRules do
    begin
      if not MatchesGlob(Rule.Glob, F.FileName) then Continue;
      // Kinds-Filter
      if not Rule.KindsAll then
        if not (F.Kind in Rule.Kinds) then Continue;

      RuleHit := True;
      case Rule.Action of
        poaDrop:
          Findings.Delete(i);  // owns - das Objekt wird freigegeben
        poaSeverityHint:
          F.Severity := lsHint;
        poaSeverityWarn:
          F.Severity := lsWarning;
        poaSeverityError:
          F.Severity := lsError;
      end;
      Break; // Erste Match-Rule gewinnt
    end;
    if RuleHit and (Rule.Action = poaDrop) then Continue;
  end;
end;

class procedure TPathOverrides.AddRule(const Glob: string;
  Action: TPathOverrideAction; const Kinds: TFindingKinds; KindsAll: Boolean);
var
  Rule : TPathOverrideRule;
begin
  if GRules = nil then GRules := TList<TPathOverrideRule>.Create;
  Rule.Glob     := Glob;
  Rule.Action   := Action;
  Rule.Kinds    := Kinds;
  Rule.KindsAll := KindsAll;
  GRules.Add(Rule);
end;

class procedure TPathOverrides.Clear;
begin
  if Assigned(GRules) then GRules.Clear;
end;

class function TPathOverrides.RuleCount: Integer;
begin
  if Assigned(GRules) then Result := GRules.Count else Result := 0;
end;

initialization
  GRules := TList<TPathOverrideRule>.Create;

finalization
  FreeAndNil(GRules);

end.
