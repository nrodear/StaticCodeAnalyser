unit uTestCustomRuleDetector;

// Tests fuer TCustomRuleDetector. Strategie: Rules direkt via AddRule
// registrieren, Source-String an AnalyzeFile geben, Findings pruefen.
// Spart YAML-Parser-Roundtrip in den meisten Tests (separat in
// uTestYamlSubsetParser abgedeckt).

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.IOUtils, System.Classes,
  System.RegularExpressions, System.Generics.Collections,
  uMethodd12, uSCAConsts, uCustomRuleDetector;

type
  [TestFixture]
  TTestCustomRuleDetector = class
  strict private
    function MakeRule(const ID: string; const Pattern: string;
      PatternType: TPatternType = ptSubstring;
      Severity: TLeakSeverity = lsWarning): TCustomRule;
    function CountByRule(Findings: TObjectList<TLeakFinding>;
      const RuleID: string): Integer;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;

    [Test] procedure SubstringPattern_Matches;
    [Test] procedure SubstringPattern_NoMatch;
    [Test] procedure WordPattern_OnlyMatchesFullWord;
    [Test] procedure RegexPattern_Matches;
    [Test] procedure InvalidRegex_ThrowsAtLoad;
    [Test] procedure FindingHasRuleIdAndKindCustomRule;
    [Test] procedure FindingHasCorrectLineNumber;
    [Test] procedure FileExclude_SkipsExcludedFiles;
    [Test] procedure FileInclude_OnlyScansIncludedFiles;
    [Test] procedure NoRules_NoFindings;
    [Test] procedure FullYamlRoundtrip_ViaTempFile;
  end;

implementation

{ ---- Helpers ---- }

procedure TTestCustomRuleDetector.Setup;
begin
  TCustomRuleDetector.ClearRules;
end;

procedure TTestCustomRuleDetector.TearDown;
begin
  TCustomRuleDetector.ClearRules;
end;

function TTestCustomRuleDetector.MakeRule(const ID, Pattern: string;
  PatternType: TPatternType; Severity: TLeakSeverity): TCustomRule;
begin
  Result := Default(TCustomRule);
  Result.ID          := ID;
  Result.Name        := ID + '-name';
  Result.Description := ID + '-desc';
  Result.Severity    := Severity;
  Result.Pattern     := Pattern;
  Result.PatternType := PatternType;
  Result.Target      := rtAny;
  Result.Message     := ID + '-msg';
  if PatternType = ptRegex then
    Result.PatternRegex := TRegEx.Create(Pattern, [roCompiled]);
end;

function TTestCustomRuleDetector.CountByRule(
  Findings: TObjectList<TLeakFinding>; const RuleID: string): Integer;
var F: TLeakFinding;
begin
  Result := 0;
  for F in Findings do
    if F.RuleID = RuleID then Inc(Result);
end;

{ ---- Tests ---- }

procedure TTestCustomRuleDetector.SubstringPattern_Matches;
var
  Findings : TObjectList<TLeakFinding>;
begin
  TCustomRuleDetector.AddRule(MakeRule('R001', 'TADOQuery'));
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    TCustomRuleDetector.AnalyzeFile('test.pas',
      'unit Foo;'#10'  q := TADOQuery.Create;'#10, Findings);
    Assert.AreEqual<Integer>(1, CountByRule(Findings, 'R001'));
  finally Findings.Free; end;
end;

procedure TTestCustomRuleDetector.SubstringPattern_NoMatch;
var
  Findings : TObjectList<TLeakFinding>;
begin
  TCustomRuleDetector.AddRule(MakeRule('R001', 'TADOQuery'));
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    TCustomRuleDetector.AnalyzeFile('test.pas',
      'unit Foo;'#10'  q := TFDQuery.Create;'#10, Findings);
    Assert.AreEqual<Integer>(0, CountByRule(Findings, 'R001'));
  finally Findings.Free; end;
end;

procedure TTestCustomRuleDetector.WordPattern_OnlyMatchesFullWord;
// Word-Pattern darf NICHT in 'Sleeper' / 'OverSleep' triggern.
var
  Findings : TObjectList<TLeakFinding>;
begin
  TCustomRuleDetector.AddRule(MakeRule('R002', 'Sleep', ptWord));
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    TCustomRuleDetector.AnalyzeFile('test.pas',
      'var Sleeper: TFoo;'#10'  Sleep(100);'#10'OverSleep := True;'#10,
      Findings);
    Assert.AreEqual<Integer>(1, CountByRule(Findings, 'R002'),
      'Nur das echte Sleep( als Wort - Sleeper / OverSleep nicht');
  finally Findings.Free; end;
end;

procedure TTestCustomRuleDetector.RegexPattern_Matches;
var
  Findings : TObjectList<TLeakFinding>;
begin
  TCustomRuleDetector.AddRule(MakeRule('R003', '\bDeprecated\w+\b', ptRegex));
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    TCustomRuleDetector.AnalyzeFile('test.pas',
      'DeprecatedFoo := 1;'#10'DeprecatedBar := 2;'#10'Other := 3;'#10,
      Findings);
    Assert.AreEqual<Integer>(2, CountByRule(Findings, 'R003'));
  finally Findings.Free; end;
end;

procedure TTestCustomRuleDetector.InvalidRegex_ThrowsAtLoad;
// Kaputter Regex muss schon beim YAML-Load auffallen, nicht erst zur
// AnalyzeFile-Zeit (sonst kommt der Fehler pro Datei).
const SRC =
  'rules:'#10+
  '  - id: R001'#10+
  '    pattern: "[unbalanced"'#10+
  '    pattern-type: regex'#10;
var
  TempFile : string;
begin
  TempFile := TPath.GetTempFileName;
  try
    TFile.WriteAllText(TempFile, SRC, TEncoding.UTF8);
    Assert.WillRaise(
      procedure begin TCustomRuleDetector.LoadFromYaml(TempFile) end,
      Exception,
      'Invalid regex muss beim Load eine Exception werfen');
  finally
    TFile.Delete(TempFile);
  end;
end;

procedure TTestCustomRuleDetector.FindingHasRuleIdAndKindCustomRule;
var
  Findings : TObjectList<TLeakFinding>;
  F        : TLeakFinding;
begin
  TCustomRuleDetector.AddRule(MakeRule('PROJ001', 'Foo'));
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    TCustomRuleDetector.AnalyzeFile('test.pas', 'x := Foo;'#10, Findings);
    Assert.AreEqual<Integer>(1, Findings.Count);
    F := Findings[0];
    Assert.AreEqual('PROJ001',     F.RuleID);
    Assert.AreEqual<TFindingKind>(fkCustomRule, F.Kind);
    Assert.AreEqual('PROJ001-msg', F.MissingVar);
  finally Findings.Free; end;
end;

procedure TTestCustomRuleDetector.FindingHasCorrectLineNumber;
var
  Findings : TObjectList<TLeakFinding>;
begin
  TCustomRuleDetector.AddRule(MakeRule('R001', 'XYZ'));
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    TCustomRuleDetector.AnalyzeFile('test.pas',
      'line1'#10+
      'line2 XYZ here'#10+
      'line3'#10+
      'line4 XYZ again'#10,
      Findings);
    Assert.AreEqual<Integer>(2, Findings.Count);
    Assert.AreEqual('2', Findings[0].LineNumber);
    Assert.AreEqual('4', Findings[1].LineNumber);
  finally Findings.Free; end;
end;

procedure TTestCustomRuleDetector.FileExclude_SkipsExcludedFiles;
var
  Rule     : TCustomRule;
  Findings : TObjectList<TLeakFinding>;
begin
  Rule := MakeRule('R001', 'XYZ');
  Rule.FileExclude := ['**/*Test*.pas'];
  TCustomRuleDetector.AddRule(Rule);
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    // Datei matcht Exclude -> kein Finding
    TCustomRuleDetector.AnalyzeFile('src/uMyTest.pas',
      'XYZ here'#10, Findings);
    Assert.AreEqual<Integer>(0, Findings.Count,
      'Excluded Datei darf KEIN Finding produzieren');
    // Andere Datei matcht nicht Exclude -> Finding kommt
    TCustomRuleDetector.AnalyzeFile('src/Production.pas',
      'XYZ here'#10, Findings);
    Assert.AreEqual<Integer>(1, Findings.Count);
  finally Findings.Free; end;
end;

procedure TTestCustomRuleDetector.FileInclude_OnlyScansIncludedFiles;
var
  Rule     : TCustomRule;
  Findings : TObjectList<TLeakFinding>;
begin
  Rule := MakeRule('R001', 'XYZ');
  Rule.FileInclude := ['src/production/**/*.pas'];
  TCustomRuleDetector.AddRule(Rule);
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    // Inkludiert: matcht
    TCustomRuleDetector.AnalyzeFile('src/production/foo.pas',
      'XYZ here'#10, Findings);
    Assert.AreEqual<Integer>(1, Findings.Count);
    // Nicht inkludiert: skip
    TCustomRuleDetector.AnalyzeFile('src/test/bar.pas',
      'XYZ here'#10, Findings);
    Assert.AreEqual<Integer>(1, Findings.Count,
      'Datei ausserhalb der Include-Globs muss ignoriert werden');
  finally Findings.Free; end;
end;

procedure TTestCustomRuleDetector.NoRules_NoFindings;
var
  Findings : TObjectList<TLeakFinding>;
begin
  // Keine Rules registriert -> AnalyzeFile darf nichts melden.
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    TCustomRuleDetector.AnalyzeFile('test.pas',
      'voller Pascal-Code'#10, Findings);
    Assert.AreEqual<Integer>(0, Findings.Count);
  finally Findings.Free; end;
end;

procedure TTestCustomRuleDetector.FullYamlRoundtrip_ViaTempFile;
// Vollstaendiger Roundtrip: YAML schreiben, parsen, Rule anwenden.
const SRC =
  'rules:'#10+
  '  - id: PROJ001'#10+
  '    name: "kein TADOQuery"'#10+
  '    severity: error'#10+
  '    pattern: "TADOQuery"'#10+
  '    pattern-type: substring'#10+
  '    message: "Use TFDQuery"'#10;
var
  TempFile : string;
  Findings : TObjectList<TLeakFinding>;
  F        : TLeakFinding;
begin
  TempFile := TPath.GetTempFileName;
  try
    TFile.WriteAllText(TempFile, SRC, TEncoding.UTF8);
    TCustomRuleDetector.LoadFromYaml(TempFile);
    Assert.AreEqual<Integer>(1, TCustomRuleDetector.RuleCount);

    Findings := TObjectList<TLeakFinding>.Create(True);
    try
      TCustomRuleDetector.AnalyzeFile('foo.pas',
        'q := TADOQuery.Create;'#10, Findings);
      Assert.AreEqual<Integer>(1, Findings.Count);
      F := Findings[0];
      Assert.AreEqual('PROJ001',    F.RuleID);
      Assert.AreEqual<TLeakSeverity>(lsError, F.Severity);
      Assert.AreEqual('Use TFDQuery', F.MissingVar);
    finally Findings.Free; end;
  finally
    TFile.Delete(TempFile);
  end;
end;

end.
