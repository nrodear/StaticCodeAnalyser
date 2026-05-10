unit uTestExportSARIF;

// Tests fuer TSARIFWriter (Output/uExportSARIF.pas).
// Strategie: SARIF-Output erzeugen, dann mit System.JSON re-parsen
// und die Pflicht-Felder aus SARIF v2.1.0 verifizieren.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON,
  uMethodd12, uSCAConsts, uExportSARIF, uRuleCatalog;

type
  [TestFixture]
  TTestExportSARIF = class
  strict private
    function MakeFinding(K: TFindingKind; Sev: TLeakSeverity;
      const FileName: string; LineNo: Integer;
      const Msg: string): TLeakFinding;
    function ParseSARIF(const S: string): TJSONObject;
    function GetFirstResult(Root: TJSONObject): TJSONObject;
  public
    [Test] procedure SchemaUriPresent;
    [Test] procedure VersionIs210;
    [Test] procedure ToolDriverHasNameAndVersion;
    [Test] procedure RulesArrayContainsAllKinds;
    [Test] procedure ResultHasRuleIdAndLevel;
    [Test] procedure ResultLocationHasFileAndLine;
    [Test] procedure RelativePathsAreUsedWhenBaseDirSet;
    [Test] procedure FingerprintHashIsStable;
    [Test] procedure SeverityMapsCorrectly;
    [Test] procedure EmptyFindingsListProducesEmptyResults;
  end;

implementation

uses
  System.IOUtils, System.StrUtils;

{ ---- Helpers ---- }

function TTestExportSARIF.MakeFinding(K: TFindingKind; Sev: TLeakSeverity;
  const FileName: string; LineNo: Integer; const Msg: string): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.Kind       := K;
  Result.Severity   := Sev;
  Result.FileName   := FileName;
  Result.LineNumber := IntToStr(LineNo);
  Result.MissingVar := Msg;
  Result.MethodName := 'TestMethod';
end;

function TTestExportSARIF.ParseSARIF(const S: string): TJSONObject;
var
  V : TJSONValue;
begin
  V := TJSONObject.ParseJSONValue(S);
  Assert.IsTrue(V is TJSONObject, 'SARIF-Output ist kein gueltiges JSON-Object');
  Result := V as TJSONObject;
end;

function TTestExportSARIF.GetFirstResult(Root: TJSONObject): TJSONObject;
var
  Runs    : TJSONArray;
  Run     : TJSONObject;
  Results : TJSONArray;
begin
  Runs := Root.GetValue<TJSONArray>('runs');
  Assert.IsNotNull(Runs, 'runs[] fehlt');
  Assert.IsTrue(Runs.Count > 0, 'runs[] ist leer');
  Run := Runs.Items[0] as TJSONObject;
  Results := Run.GetValue<TJSONArray>('results');
  Assert.IsNotNull(Results, 'results[] fehlt');
  Assert.IsTrue(Results.Count > 0, 'results[] ist leer');
  Result := Results.Items[0] as TJSONObject;
end;

{ ---- Tests ---- }

procedure TTestExportSARIF.SchemaUriPresent;
var
  Findings : TObjectList<TLeakFinding>;
  S        : string;
  Root     : TJSONObject;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    S := TSARIFWriter.ToJsonString(Findings, '', '0.8.0', 'TestTool');
    Root := ParseSARIF(S);
    try
      Assert.Contains(Root.GetValue<string>('$schema', ''), 'sarif',
        '$schema fehlt oder zeigt nicht auf SARIF-Schema');
    finally
      Root.Free;
    end;
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSARIF.VersionIs210;
var
  Findings : TObjectList<TLeakFinding>;
  S        : string;
  Root     : TJSONObject;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    S := TSARIFWriter.ToJsonString(Findings, '', '0.8.0', 'TestTool');
    Root := ParseSARIF(S);
    try
      Assert.AreEqual('2.1.0', Root.GetValue<string>('version'),
        'SARIF-Version muss 2.1.0 sein');
    finally
      Root.Free;
    end;
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSARIF.ToolDriverHasNameAndVersion;
var
  Findings : TObjectList<TLeakFinding>;
  S        : string;
  Root     : TJSONObject;
  Run      : TJSONObject;
  Tool     : TJSONObject;
  Driver   : TJSONObject;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    S := TSARIFWriter.ToJsonString(Findings, '', '0.8.0', 'MyTool');
    Root := ParseSARIF(S);
    try
      Run    := (Root.GetValue<TJSONArray>('runs').Items[0] as TJSONObject);
      Tool   := Run.GetValue<TJSONObject>('tool');
      Driver := Tool.GetValue<TJSONObject>('driver');
      Assert.AreEqual('MyTool', Driver.GetValue<string>('name'));
      Assert.AreEqual('0.8.0',  Driver.GetValue<string>('version'));
    finally
      Root.Free;
    end;
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSARIF.RulesArrayContainsAllKinds;
// runs[0].tool.driver.rules[] muss min. fuer jeden TFindingKind einen
// Eintrag haben (kommt aus TRuleCatalog).
var
  Findings : TObjectList<TLeakFinding>;
  S        : string;
  Root     : TJSONObject;
  Run      : TJSONObject;
  Rules    : TJSONArray;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    S := TSARIFWriter.ToJsonString(Findings, '', '0.8.0', 'TestTool');
    Root := ParseSARIF(S);
    try
      Run := Root.GetValue<TJSONArray>('runs').Items[0] as TJSONObject;
      Rules := Run.GetValue<TJSONObject>('tool')
                  .GetValue<TJSONObject>('driver')
                  .GetValue<TJSONArray>('rules');
      Assert.AreEqual(Ord(High(TFindingKind)) - Ord(Low(TFindingKind)) + 1,
                      Rules.Count,
        'rules[] Anzahl entspricht nicht den TFindingKind-Werten');
    finally
      Root.Free;
    end;
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSARIF.ResultHasRuleIdAndLevel;
var
  Findings : TObjectList<TLeakFinding>;
  S        : string;
  Root     : TJSONObject;
  Res      : TJSONObject;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, lsError, 'src\Foo.pas', 42, 'list1'));
    S := TSARIFWriter.ToJsonString(Findings, '', '0.8.0', 'TestTool');
    Root := ParseSARIF(S);
    try
      Res := GetFirstResult(Root);
      Assert.AreEqual('SCA001', Res.GetValue<string>('ruleId'));
      Assert.AreEqual('error',  Res.GetValue<string>('level'));
      Assert.AreEqual('list1',  Res.GetValue<TJSONObject>('message')
                                    .GetValue<string>('text'));
    finally
      Root.Free;
    end;
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSARIF.ResultLocationHasFileAndLine;
var
  Findings : TObjectList<TLeakFinding>;
  S        : string;
  Root     : TJSONObject;
  Res      : TJSONObject;
  Loc      : TJSONObject;
  PhysLoc  : TJSONObject;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkSQLInjection, lsError,
      'src\Db.pas', 100, 'concat in WHERE'));
    S := TSARIFWriter.ToJsonString(Findings, '', '0.8.0', 'TestTool');
    Root := ParseSARIF(S);
    try
      Res := GetFirstResult(Root);
      Loc := (Res.GetValue<TJSONArray>('locations').Items[0] as TJSONObject);
      PhysLoc := Loc.GetValue<TJSONObject>('physicalLocation');
      Assert.AreEqual('src/Db.pas',
        PhysLoc.GetValue<TJSONObject>('artifactLocation')
               .GetValue<string>('uri'),
        'Forward-Slashes erwartet (SARIF-Konvention)');
      Assert.AreEqual<Integer>(100,
        (PhysLoc.GetValue<TJSONObject>('region')
                .GetValue<TJSONNumber>('startLine')).AsInt);
    finally
      Root.Free;
    end;
  finally
    Findings.Free;
  end;
end;

procedure TTestExportSARIF.RelativePathsAreUsedWhenBaseDirSet;
var
  Findings : TObjectList<TLeakFinding>;
  S        : string;
  Root     : TJSONObject;
  Uri      : string;
  TempDir  : string;
begin
  TempDir  := TPath.Combine(TPath.GetTempPath, 'sca-test-rel');
  TDirectory.CreateDirectory(TempDir);
  TDirectory.CreateDirectory(TPath.Combine(TempDir, 'src'));

  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, lsError,
      TPath.Combine(TempDir, 'src\Foo.pas'), 5, 'list'));
    S := TSARIFWriter.ToJsonString(Findings, TempDir, '0.8.0', 'T');
    Root := ParseSARIF(S);
    try
      Uri := (GetFirstResult(Root)
                .GetValue<TJSONArray>('locations').Items[0] as TJSONObject)
                .GetValue<TJSONObject>('physicalLocation')
                .GetValue<TJSONObject>('artifactLocation')
                .GetValue<string>('uri');
      Assert.AreEqual('src/Foo.pas', Uri,
        'Pfad sollte relativ zu BaseDir sein');
    finally
      Root.Free;
    end;
  finally
    Findings.Free;
    TDirectory.Delete(TempDir, True);
  end;
end;

procedure TTestExportSARIF.FingerprintHashIsStable;
// Selber Input -> selber Hash (deterministisch, fuer GitHub-Dedup).
var
  F1, F2   : TObjectList<TLeakFinding>;
  S1, S2   : string;
  Root1, Root2 : TJSONObject;
  H1, H2   : string;
begin
  F1 := TObjectList<TLeakFinding>.Create(True);
  F2 := TObjectList<TLeakFinding>.Create(True);
  try
    F1.Add(MakeFinding(fkNilDeref, lsWarning, 'src\X.pas', 7, 'obj'));
    F2.Add(MakeFinding(fkNilDeref, lsWarning, 'src\X.pas', 7, 'obj'));
    S1 := TSARIFWriter.ToJsonString(F1, '', '0.8.0', 'T');
    S2 := TSARIFWriter.ToJsonString(F2, '', '0.8.0', 'T');
    Root1 := ParseSARIF(S1);
    Root2 := ParseSARIF(S2);
    try
      H1 := GetFirstResult(Root1).GetValue<TJSONObject>('partialFingerprints')
                                 .GetValue<string>('primaryLocationLineHash');
      H2 := GetFirstResult(Root2).GetValue<TJSONObject>('partialFingerprints')
                                 .GetValue<string>('primaryLocationLineHash');
      Assert.IsNotEmpty(H1, 'Fingerprint fehlt');
      Assert.AreEqual(H1, H2,
        'Identische Findings muessen identische Fingerprints liefern');
    finally
      Root1.Free;
      Root2.Free;
    end;
  finally
    F1.Free;
    F2.Free;
  end;
end;

procedure TTestExportSARIF.SeverityMapsCorrectly;
type
  TCase = record Sev: TLeakSeverity; Expected: string; end;
const
  Cases: array[0..2] of TCase = (
    (Sev: lsError;   Expected: 'error'),
    (Sev: lsWarning; Expected: 'warning'),
    (Sev: lsHint;    Expected: 'note')
  );
var
  C        : TCase;
  Findings : TObjectList<TLeakFinding>;
  S        : string;
  Root     : TJSONObject;
begin
  for C in Cases do
  begin
    Findings := TObjectList<TLeakFinding>.Create(True);
    try
      Findings.Add(MakeFinding(fkLongMethod, C.Sev, 'a.pas', 1, 'm'));
      S := TSARIFWriter.ToJsonString(Findings, '', '0.8.0', 'T');
      Root := ParseSARIF(S);
      try
        Assert.AreEqual(C.Expected,
          GetFirstResult(Root).GetValue<string>('level'),
          Format('Severity %d -> %s erwartet', [Ord(C.Sev), C.Expected]));
      finally
        Root.Free;
      end;
    finally
      Findings.Free;
    end;
  end;
end;

procedure TTestExportSARIF.EmptyFindingsListProducesEmptyResults;
var
  Findings : TObjectList<TLeakFinding>;
  S        : string;
  Root     : TJSONObject;
  Run      : TJSONObject;
  Results  : TJSONArray;
begin
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    S := TSARIFWriter.ToJsonString(Findings, '', '0.8.0', 'T');
    Root := ParseSARIF(S);
    try
      Run := Root.GetValue<TJSONArray>('runs').Items[0] as TJSONObject;
      Results := Run.GetValue<TJSONArray>('results');
      Assert.AreEqual<Integer>(0, Results.Count,
        'Leere Findings-Liste -> leeres results[]');
    finally
      Root.Free;
    end;
  finally
    Findings.Free;
  end;
end;

end.
