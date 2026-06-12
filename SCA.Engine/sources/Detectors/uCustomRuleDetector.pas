unit uCustomRuleDetector;

// Custom-Rule-Engine: liest team-/projekt-spezifische Regeln aus
// analyser-rules.yml und matcht sie als Pattern (Regex/Substring/Word)
// gegen Source-Code. Output identisch zu hardcoded Detektoren -
// erscheint in SARIF/HTML/JSON mit der Custom-Rule-ID (z.B. PROJ001).
//
// Strategie: zeilenweiser Scan mit optionalen Target-Filtern. AST-
// basiert waere praeziser aber overkill - die haeufigsten Use-Cases
// (verbotene Imports, deprecated APIs, Naming-Conventions) lassen
// sich mit Pattern-Matching gut abdecken.
//
// Aufruf-Reihenfolge:
// 1. TCustomRuleDetector.LoadFromYaml(filename)
// 2. TCustomRuleDetector.AnalyzeFile(filename, source, results)
// wird pro Datei aufgerufen, fuegt 0..N TLeakFindings an results an
// 3. TCustomRuleDetector.Clear (am Ende, oder beim naechsten Run)

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections,
  System.RegularExpressions,
  uSCAConsts, uMethodd12;

type
  TPatternType = (ptSubstring, ptRegex, ptWord);
  TRuleTarget = (rtAny, rtIdentifier, rtComment, rtStringLiteral);

  TCustomRule = record
    ID: string; // 'PROJ001'
    Name: string;
    Description: string;
    Severity: TLeakSeverity;
    Pattern: string; // raw pattern text
    PatternType: TPatternType;
    PatternRegex: TRegEx; // pre-compiled wenn PatternType=ptRegex
    Target: TRuleTarget;
    Message: string; // optional, fallback = Description
    FixHint: string; // optional
    FileInclude: TArray<string>; // Glob-Patterns ueber FullPath
    FileExclude: TArray<string>;
  end;

  TCustomRuleDetector = class
  strict private
    class var FRules: TList<TCustomRule>;
    class var FLoaded: Boolean;
    class function ParsePatternType(const S: string): TPatternType; static;
    class function ParseTarget(const S: string): TRuleTarget; static;
    class function ParseSeverity(const S: string): TLeakSeverity; static;
    class function FileMatchesGlobs(const FileName: string;
      const Globs: TArray<string>): Boolean; static;
    class function FileMatchesAny(const FileName: string;
      const Includes, Excludes: TArray<string>): Boolean; static;
  public
    // Im initialization/finalization gerufen - muss public sein damit Pascal
    // die Aufrufe aus dem Unit-Footer aufloesen kann.
    class procedure Init; static;
    class procedure Done; static;

    // Laed Rules aus YAML-Datei. Vorherige Rules werden ueberschrieben.
    // Wirft EYamlParseError oder Exception bei kaputter Datei.
    class procedure LoadFromYaml(const FileName: string); static;

    // Manuell befuellen (fuer Tests).
    class procedure ClearRules; static;
    class procedure AddRule(const ARule: TCustomRule); static;

    // Pro Datei aufrufen. Source = der komplette Datei-Text.
    // Findings werden an Results angehaengt (Caller besitzt die Liste).
    class procedure AnalyzeFile(const FileName, Source: string;
      Results: TObjectList<TLeakFinding>); overload; static;
    // Convenience-Overload: liest die Datei selbst. Bei IO-Fehler keine
    // Action (Custom-Rules sollen nicht zusaetzlich crashen wenn der
    // Hauptanalyzer schon gefailt ist).
    class procedure AnalyzeFile(const FileName: string;
      Results: TObjectList<TLeakFinding>); overload; static;

    class function RuleCount: Integer; static;
    class function HasRules: Boolean; static;
  end;

implementation

// noinspection-file ConcatToFormat, ExceptionTooGeneral, ExceptOnException, RaisingRawException
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.IOUtils, System.StrUtils,
  uYamlSubsetParser, uFileTextCache;

{ ---- Init / Done ---- }

class procedure TCustomRuleDetector.Init;
begin
  FRules := TList<TCustomRule>.Create;
  FLoaded := False;
end;

class procedure TCustomRuleDetector.Done;
begin
  FreeAndNil(FRules);
end;

class procedure TCustomRuleDetector.ClearRules;
begin
  FRules.Clear;
  FLoaded := False;
end;

class procedure TCustomRuleDetector.AddRule(const ARule: TCustomRule);
begin
  FRules.Add(ARule);
  FLoaded := True;
end;

class function TCustomRuleDetector.RuleCount: Integer;
begin
  Result := FRules.Count;
end;

class function TCustomRuleDetector.HasRules: Boolean;
begin
  Result := FRules.Count > 0;
end;

{ ---- YAML-Parsing ---- }

class function TCustomRuleDetector.ParsePatternType(const S: string)
  : TPatternType;
var
  L: string;
begin
  L := LowerCase(Trim(S));
  if L = 'regex' then
    Exit(ptRegex);
  if L = 'word' then
    Exit(ptWord);
  // Default + 'substring'
  Result := ptSubstring;
end;

class function TCustomRuleDetector.ParseTarget(const S: string): TRuleTarget;
var
  L: string;
begin
  L := LowerCase(Trim(S));
  if (L = 'identifier') then
    Exit(rtIdentifier);
  if (L = 'comment') then
    Exit(rtComment);
  if (L = 'string') or (L = 'string-literal') then
    Exit(rtStringLiteral);
  Result := rtAny;
end;

class function TCustomRuleDetector.ParseSeverity(const S: string)
  : TLeakSeverity;
var
  L: string;
begin
  L := LowerCase(Trim(S));
  if L = 'error' then
    Exit(lsError);
  if L = 'warning' then
    Exit(lsWarning);
  if L = 'hint' then
    Exit(lsHint);
  Result := lsWarning;
end;

class procedure TCustomRuleDetector.LoadFromYaml(const FileName: string);
var
  Root: TYamlNode;
  Rules: TYamlNode;
  i: Integer;
  Item: TYamlNode;
  R: TCustomRule;
begin
  ClearRules;
  Root := TYamlParser.ParseFile(FileName);
  try
    if Root.Kind <> yntMapping then
      raise EYamlParseError.Create('Top-Level muss Mapping sein');

    Rules := Root.GetChild('rules');
    if (Rules = nil) or (Rules.Kind <> yntSequence) then
      Exit;

    for i := 0 to Rules.ItemCount - 1 do
    begin
      Item := Rules.GetItem(i);
      if Item.Kind <> yntMapping then
        Continue;

      R := Default (TCustomRule);
      R.ID := Item.GetString('id');
      R.Name := Item.GetString('name');
      R.Description := Item.GetString('description');
      R.Severity := ParseSeverity(Item.GetString('severity', 'warning'));
      R.Pattern := Item.GetString('pattern');
      R.PatternType := ParsePatternType(Item.GetString('pattern-type',
        'substring'));
      R.Target := ParseTarget(Item.GetString('target', 'any'));
      R.Message := Item.GetString('message', R.Description);
      R.FixHint := Item.GetString('fix-hint');
      R.FileInclude := Item.GetSequenceStrings('file-include');
      R.FileExclude := Item.GetSequenceStrings('file-exclude');

      // Pflicht-Felder
      if (R.ID = '') or (R.Pattern = '') then
        Continue;

      // Regex pre-compilen damit RuntimeFehler im AnalyzeFile-Hot-Path
      // nicht jedes Match teurer machen.
      if R.PatternType = ptRegex then
      begin
        try
          R.PatternRegex := TRegEx.Create(R.Pattern, [roCompiled]);
        except
          on E: Exception do
            raise Exception.CreateFmt('Custom rule %s: invalid regex "%s": %s',
              [R.ID, R.Pattern, E.Message]);
        end;
      end;
      AddRule(R);
    end;
    FLoaded := True;
  finally
    Root.Free;
  end;
end;

{ ---- File-Matching ---- }

function GlobToRegexPattern(const Glob: string): string;
// Konvertiert ein Glob-Pattern zu einem aequivalenten Regex.
// Unterstuetzt:
// *   -> [^/]*    (alle Zeichen ausser Path-Separator)
// **  -> .*       (rekursiv: beliebige Anzahl Segmente, INKL. leer)
// **/ -> (.*/)?   (gebraeuchlich: '**/' am Anfang/in der Mitte =
// "in beliebiger Tiefe (auch direkt)")
// ?   -> [^/]     (genau ein Zeichen, kein Separator)
// .  +  (  )  |  [  ]  {  }  ^  $  \  -> escaped (regex-Metazeichen)
//
// System.Masks.MatchesMask unterstuetzt KEIN '**' - deshalb diese
// eigene Implementierung.
var
  i: Integer;
  C: Char;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create('^');
  try
    i := 1;
    while i <= Length(Glob) do
    begin
      C := Glob[i];
      case C of
        '*':
          if (i < Length(Glob)) and (Glob[i + 1] = '*') then
          begin
            // '**/' -> "(.*/)?"  (so src/**/foo matcht auch src/foo)
            // '**'  -> '.*'      (am Ende: alles weitere inkl. /)
            if (i + 2 <= Length(Glob)) and (Glob[i + 2] = '/') then
            begin
              SB.Append('(.*/)?');
              Inc(i, 3);
            end
            else
            begin
              SB.Append('.*');
              Inc(i, 2);
            end;
            Continue;
          end
          else
          begin
            SB.Append('[^/]*');
            Inc(i);
            Continue;
          end;
        '?':
          SB.Append('[^/]');
        '.', '+', '(', ')', '|', '[', ']', '{', '}', '^', '$', '\':
          begin
            SB.Append('\');
            SB.Append(C);
          end;
      else
        SB.Append(C);
      end;
      Inc(i);
    end;
    SB.Append('$');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TCustomRuleDetector.FileMatchesGlobs(const FileName: string;
  const Globs: TArray<string>): Boolean;
// Returns True wenn FileName auf MIN. EIN Glob matcht.
// Match erfolgt gegen FullPath (Forward-Slashes normalisiert).
// Konvertiert Glob -> Regex on-the-fly. Bei sehr vielen Files koennte
// eine pre-compiled Regex-Liste pro Rule die Performance verbessern -
// aktuell ist die Glob-Anzahl pro Rule jedoch klein (<10 typisch).
var
  Norm: string;
  G: string;
begin
  Norm := StringReplace(FileName, '\', '/', [rfReplaceAll]);
  for G in Globs do
    if TRegEx.IsMatch(Norm, GlobToRegexPattern(StringReplace(G, '\', '/',
      [rfReplaceAll]))) then
      Exit(True);
  Result := False;
end;

class function TCustomRuleDetector.FileMatchesAny(const FileName: string;
  const Includes, Excludes: TArray<string>): Boolean;
// Include leer  -> alle Dateien matchen (kein Restriktion)
// Include voll  -> nur Dateien die mindestens ein Include treffen
// Exclude voll  -> Dateien die ein Exclude treffen werden RAUSgefiltert
// (auch wenn sie ein Include treffen)
begin
  Result := True;
  if Length(Includes) > 0 then
    Result := FileMatchesGlobs(FileName, Includes);
  if Result and (Length(Excludes) > 0) and FileMatchesGlobs(FileName, Excludes)
  then
    Result := False;
end;

{ ---- Pattern-Matching ---- }

function MatchPattern(const Source: string; const R: TCustomRule;
  out Matches: TList<Integer>): Boolean;
// Liefert in Matches die Zeilennummern (1-basiert) wo das Pattern zutrifft.
// True wenn min. 1 Match.
var
  Lines: TArray<string>;
  i: Integer;
  Match: TMatch;
  WordRx: TRegEx;
begin
  Matches := TList<Integer>.Create;
  Lines := Source.Split([#13#10, #10, #13]);

  case R.PatternType of
    ptSubstring:
      for i := 0 to High(Lines) do
        if Pos(R.Pattern, Lines[i]) > 0 then
          Matches.Add(i + 1);

    ptWord:
      // Word-Match = Pattern als ganzes Wort, case-sensitive.
      // Implementiert via Regex \b<pattern>\b mit Pattern escaped.
      begin
        WordRx := TRegEx.Create('\b' + TRegEx.Escape(R.Pattern) + '\b',
          [roCompiled]);
        for i := 0 to High(Lines) do
          if WordRx.IsMatch(Lines[i]) then
            Matches.Add(i + 1);
      end;

    ptRegex:
      for i := 0 to High(Lines) do
      begin
        Match := R.PatternRegex.Match(Lines[i]);
        if Match.Success then
          Matches.Add(i + 1);
      end;
  end;

  Result := Matches.Count > 0;
end;

{ ---- Public AnalyzeFile ---- }

class procedure TCustomRuleDetector.AnalyzeFile(const FileName, Source: string;
  Results: TObjectList<TLeakFinding>);
// Strategie bewusst SIMPEL: zeilenweiser Pattern-Match. Target-Filtering
// (rtComment / rtStringLiteral / rtIdentifier) ist ein TODO fuer v0.9.x -
// fuer v0.9.0-MVP wirkt jedes Pattern auf den vollen Zeileninhalt.
// rtIdentifier wird approximiert via Word-Match - Caller kann pattern-type
// auf 'word' setzen wenn er nur ganze Identifier-Tokens treffen will.
var
  R: TCustomRule;
  Matches: TList<Integer>;
  LineNo: Integer;
  F: TLeakFinding;
begin
  if not HasRules then
    Exit;
  for R in FRules do
  begin
    if not FileMatchesAny(FileName, R.FileInclude, R.FileExclude) then
      Continue;
    if MatchPattern(Source, R, Matches) then
      try
        for LineNo in Matches do
        begin
          F := TLeakFinding.Create;
          F.FileName := FileName;
          F.MethodName := '';
          // Custom-Rules sind file-level, nicht method-level
          F.LineNumber := IntToStr(LineNo);
          F.MissingVar := IfThen(R.Message <> '', R.Message, R.Name);
          F.Severity := R.Severity;
          F.Kind := fkCustomRule;
          F.Confidence := KindDefaultConfidence(fkCustomRule);
          F.RuleID := R.ID;
          Results.Add(F);
        end;
      finally
        Matches.Free;
      end
    else
      Matches.Free;
  end;
end;

class procedure TCustomRuleDetector.AnalyzeFile(const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Source: string;
  Lines: TStringList;
  Cached: Boolean;
begin
  if not HasRules then
    Exit;
  // Cache-Pfad: wenn der Main-Loop schon ein gFileTextCache angelegt hat,
  // nutzen wir das (spart Disk-IO, perf_analyse.md Hot-Spot 🅑).
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then
    Exit;
  try
    Source := Lines.Text;
  finally
    ReleaseLines(Lines, Cached);
  end;
  AnalyzeFile(FileName, Source, Results);
end;

initialization

TCustomRuleDetector.Init;

finalization

TCustomRuleDetector.Done;

end.
