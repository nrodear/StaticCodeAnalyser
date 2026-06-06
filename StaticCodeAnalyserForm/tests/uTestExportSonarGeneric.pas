unit uTestExportSonarGeneric;

// Tests fuer uExportSonarGeneric - Sonar Generic Issue Format Writer.
// Validiert JSON-Struktur gegen die Sonar-Spec.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON,
  uMethodd12, uSCAConsts, uExportSonarGeneric;

type
  [TestFixture]
  TTestExportSonarGeneric = class
  private
    function MakeFinding(Kind: TFindingKind; const Path: string;
      Line: Integer; const Msg: string): TLeakFinding;
  public
    [Test] procedure EmptyFindingsProducesEmptyArrays;
    [Test] procedure SingleFindingHasBothRuleAndIssue;
    [Test] procedure RulesAreDedupedAcrossMultipleFindings;
    [Test] procedure IssueHasEngineIdAndRuleId;
    [Test] procedure IssueHasPrimaryLocationWithTextRange;
    [Test] procedure RuleHasMqrFields;
    [Test] procedure FilePathIsRelativeToBaseDir;
    [Test] procedure EffortMinutesForBugIs20;
    [Test] procedure EffortMinutesForCodeSmellIs10;
    [Test] procedure CustomRuleIdOverridesCatalog;
    [Test] procedure JsonParsesAsValidJson;
  end;

implementation

uses
  uRuleCatalog;

function TTestExportSonarGeneric.MakeFinding(Kind: TFindingKind;
  const Path: string; Line: Integer; const Msg: string): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.SetKind(Kind);
  Result.FileName := Path;
  Result.LineNumber := IntToStr(Line);
  Result.MissingVar := Msg;
end;

procedure TTestExportSonarGeneric.EmptyFindingsProducesEmptyArrays;
var
  Findings : TObjectList<TLeakFinding>;
  Json     : string;
  Root     : TJSONObject;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Json := TSonarGenericWriter.ToJsonString(Findings, '');
    Root := TJSONObject.ParseJSONValue(Json) as TJSONObject;
    try
      Assert.IsNotNull(Root.GetValue<TJSONArray>('rules'));
      Assert.IsNotNull(Root.GetValue<TJSONArray>('issues'));
      Assert.AreEqual(0, Root.GetValue<TJSONArray>('rules').Count);
      Assert.AreEqual(0, Root.GetValue<TJSONArray>('issues').Count);
    finally
      Root.Free;
    end;
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSonarGeneric.SingleFindingHasBothRuleAndIssue;
var
  Findings : TObjectList<TLeakFinding>;
  Json     : string;
  Root     : TJSONObject;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\Foo.pas', 42, 'list1 not freed'));
    Json := TSonarGenericWriter.ToJsonString(Findings, '');
    Root := TJSONObject.ParseJSONValue(Json) as TJSONObject;
    try
      Assert.AreEqual(1, Root.GetValue<TJSONArray>('rules').Count);
      Assert.AreEqual(1, Root.GetValue<TJSONArray>('issues').Count);
    finally
      Root.Free;
    end;
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSonarGeneric.RulesAreDedupedAcrossMultipleFindings;
var
  Findings : TObjectList<TLeakFinding>;
  Json     : string;
  Root     : TJSONObject;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    // 3 Findings auf 2 verschiedene Kinds -> 2 Rules + 3 Issues
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\Foo.pas', 1, 'a'));
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\Foo.pas', 5, 'b'));
    Findings.Add(MakeFinding(fkNilDeref,   'src\Bar.pas', 9, 'c'));
    Json := TSonarGenericWriter.ToJsonString(Findings, '');
    Root := TJSONObject.ParseJSONValue(Json) as TJSONObject;
    try
      Assert.AreEqual(2, Root.GetValue<TJSONArray>('rules').Count,
        'rules should be deduped');
      Assert.AreEqual(3, Root.GetValue<TJSONArray>('issues').Count);
    finally
      Root.Free;
    end;
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSonarGeneric.IssueHasEngineIdAndRuleId;
var
  Findings : TObjectList<TLeakFinding>;
  Json     : string;
  Root     : TJSONObject;
  Issue    : TJSONObject;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkSQLInjection, 'src\X.pas', 7, 'msg'));
    Json := TSonarGenericWriter.ToJsonString(Findings, '');
    Root := TJSONObject.ParseJSONValue(Json) as TJSONObject;
    try
      Issue := Root.GetValue<TJSONArray>('issues').Items[0] as TJSONObject;
      Assert.AreEqual('static-code-analyser', Issue.GetValue<string>('engineId'));
      Assert.AreEqual('SCA003',               Issue.GetValue<string>('ruleId'));
    finally
      Root.Free;
    end;
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSonarGeneric.IssueHasPrimaryLocationWithTextRange;
var
  Findings : TObjectList<TLeakFinding>;
  Json     : string;
  Root     : TJSONObject;
  Issue    : TJSONObject;
  Loc      : TJSONObject;
  Range    : TJSONObject;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\Foo.pas', 42, 'msg'));
    Json := TSonarGenericWriter.ToJsonString(Findings, '');
    Root := TJSONObject.ParseJSONValue(Json) as TJSONObject;
    try
      Issue := Root.GetValue<TJSONArray>('issues').Items[0] as TJSONObject;
      Loc := Issue.GetValue<TJSONObject>('primaryLocation');
      Assert.IsNotNull(Loc);
      Assert.AreEqual('msg', Loc.GetValue<string>('message'));
      Assert.Contains(Loc.GetValue<string>('filePath'), 'Foo.pas');
      Range := Loc.GetValue<TJSONObject>('textRange');
      Assert.IsNotNull(Range);
      Assert.AreEqual(42, Range.GetValue<Integer>('startLine'));
    finally
      Root.Free;
    end;
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSonarGeneric.RuleHasMqrFields;
var
  Findings : TObjectList<TLeakFinding>;
  Json     : string;
  Root     : TJSONObject;
  Rule     : TJSONObject;
  Impacts  : TJSONArray;
  Impact   : TJSONObject;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\Foo.pas', 1, 'msg'));
    Json := TSonarGenericWriter.ToJsonString(Findings, '');
    Root := TJSONObject.ParseJSONValue(Json) as TJSONObject;
    try
      Rule := Root.GetValue<TJSONArray>('rules').Items[0] as TJSONObject;
      Assert.AreEqual('LAWFUL', Rule.GetValue<string>('cleanCodeAttribute'));
      Impacts := Rule.GetValue<TJSONArray>('impacts');
      Assert.AreEqual<Integer>(1, Impacts.Count);
      Impact := Impacts.Items[0] as TJSONObject;
      Assert.AreEqual('RELIABILITY', Impact.GetValue<string>('softwareQuality'));
      Assert.AreEqual('HIGH',        Impact.GetValue<string>('severity'));
    finally
      Root.Free;
    end;
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSonarGeneric.FilePathIsRelativeToBaseDir;
var
  Findings : TObjectList<TLeakFinding>;
  Json     : string;
  Root     : TJSONObject;
  Issue    : TJSONObject;
  FilePath : string;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak,
      'C:\repo\src\Foo.pas', 1, 'msg'));
    Json := TSonarGenericWriter.ToJsonString(Findings, 'C:\repo');
    Root := TJSONObject.ParseJSONValue(Json) as TJSONObject;
    try
      Issue := Root.GetValue<TJSONArray>('issues').Items[0] as TJSONObject;
      FilePath := Issue.GetValue<TJSONObject>('primaryLocation')
                       .GetValue<string>('filePath');
      Assert.AreEqual('src/Foo.pas', FilePath,
        'expected forward-slash relative path');
    finally
      Root.Free;
    end;
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSonarGeneric.EffortMinutesForBugIs20;
begin
  Assert.AreEqual(20, EffortMinutesFor(ftBug));
end;

procedure TTestExportSonarGeneric.EffortMinutesForCodeSmellIs10;
begin
  Assert.AreEqual(10, EffortMinutesFor(ftCodeSmell));
end;

procedure TTestExportSonarGeneric.CustomRuleIdOverridesCatalog;
var
  Findings : TObjectList<TLeakFinding>;
  Json     : string;
  Root     : TJSONObject;
  Issue    : TJSONObject;
  F        : TLeakFinding;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    F := MakeFinding(fkCustomRule, 'src\X.pas', 1, 'msg');
    F.RuleID := 'PROJ042';
    Findings.Add(F);
    Json := TSonarGenericWriter.ToJsonString(Findings, '');
    Root := TJSONObject.ParseJSONValue(Json) as TJSONObject;
    try
      Issue := Root.GetValue<TJSONArray>('issues').Items[0] as TJSONObject;
      Assert.AreEqual('PROJ042', Issue.GetValue<string>('ruleId'));
    finally
      Root.Free;
    end;
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSonarGeneric.JsonParsesAsValidJson;
// Sanity: das Output muss durch jeden JSON-Parser laufen.
var
  Findings : TObjectList<TLeakFinding>;
  Json     : string;
  Val      : TJSONValue;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak,  'src\A.pas',  1, 'm1'));
    Findings.Add(MakeFinding(fkSQLInjection,'src\B.pas',  2, 'm2'));
    Findings.Add(MakeFinding(fkLongMethod,  'src\C.pas', 99, 'm3'));
    Json := TSonarGenericWriter.ToJsonString(Findings, '');
    Val := TJSONObject.ParseJSONValue(Json);
    try
      Assert.IsNotNull(Val, 'Sonar JSON did not parse');
      Assert.IsTrue(Val is TJSONObject, 'top-level must be object');
    finally
      Val.Free;
    end;
  finally
    Findings.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExportSonarGeneric);

end.
