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
    [Test] procedure ControlCharInMessage_StillParses;
    // ---- Lauf-Diagnosen gehoeren nicht in einen Issue-Report -----------
    [Test] procedure FileReadError_ProducesNoIssueAndNoRule;
    [Test] procedure RealFindingsSurviveAlongsideReadError;
    // Herabgestufte Funde (Pfad-Ueberschreibung / Konfidenz), 2026-08-22
    [Test] procedure DowngradedFinding_IsNotExported;
    [Test] procedure UpgradedFinding_StaysExported;
    [Test] procedure DowngradedFinding_KeptWhenAsked;
    [Test] procedure EncodingFindingsAreNotSkipped;
    [Test] procedure OnlyReadErrors_ProducesValidEmptyReport;
  end;

implementation

uses
  uRuleCatalog;

const
  // Wiederholte Literale der Diagnose-Tests als Konstanten - sonst zaehlt
  // sie der eigene DuplicateString-Detektor.
  DIAG_FILE    = 'src\Kaputt.pas';
  GOOD_FILE    = 'src\Gut.pas';
  DIAG_MSG     = 'Datei nicht lesbar';
  KEY_RULES    = 'rules';
  KEY_ISSUES   = 'issues';
  MSG_NOT_JSON = 'Report ist kein gueltiges JSON-Object';

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
      Assert.AreEqual<Integer>(0, Root.GetValue<TJSONArray>('rules').Count);
      Assert.AreEqual<Integer>(0, Root.GetValue<TJSONArray>('issues').Count);
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
      Assert.AreEqual<Integer>(1, Root.GetValue<TJSONArray>('rules').Count);
      Assert.AreEqual<Integer>(1, Root.GetValue<TJSONArray>('issues').Count);
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
      Assert.AreEqual<Integer>(2, Root.GetValue<TJSONArray>('rules').Count,
        'rules should be deduped');
      Assert.AreEqual<Integer>(3, Root.GetValue<TJSONArray>('issues').Count);
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
      Assert.AreEqual<Integer>(42, Range.GetValue<Integer>('startLine'));
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
  Assert.AreEqual<Integer>(20, EffortMinutesFor(ftBug));
end;

procedure TTestExportSonarGeneric.EffortMinutesForCodeSmellIs10;
begin
  Assert.AreEqual<Integer>(10, EffortMinutesFor(ftCodeSmell));
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

procedure TTestExportSonarGeneric.ControlCharInMessage_StillParses;
// RFC 8259 verlangt fuer U+0000..U+001F ein Escape der Form \uXXXX. Ohne
// die Option EncodeBelow32 schrieb Format(2) solche Zeichen ROH heraus,
// und SonarQube bricht beim ERSTEN davon ab - dann faellt nicht ein Issue
// weg, sondern der GESAMTE Report.
//
// Der Fall ist real und war im Repo belegt (sca-findings.json:990):
// unsere EIGENE Quelle enthaelt 'edToken.PasswordChar := #0;', der Lexer
// loest das Char-Literal in ein echtes Zeichen auf (uLexer.pas:531), und
// der Detektor uebernimmt es unveraendert in die Meldung.
var
  Findings : TObjectList<TLeakFinding>;
  Json     : string;
  Val      : TJSONValue;
begin
  Val := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  // EIN try/finally statt zweier verschachtelter - der eigene Self-Scan
  // meldet NestedTry, und hier gibt es keinen Grund dafuer.
  try
    Findings.Add(MakeFinding(fkHardcodedSecret, 'src\A.pas', 1,
      'edToken.PasswordChar = ''' + #0 + ''''));
    Findings.Add(MakeFinding(fkMemoryLeak, 'src\B.pas', 2,
      'ESC ' + #27 + ' und Vertikaltabulator ' + #11));
    Json := TSonarGenericWriter.ToJsonString(Findings, '');
    Assert.IsTrue(Pos(#0, Json) = 0, 'rohes #0 steht im JSON');
    Assert.IsTrue(Pos(#27, Json) = 0, 'rohes ESC steht im JSON');
    Val := TJSONObject.ParseJSONValue(Json);
    Assert.IsNotNull(Val, 'JSON mit Steuerzeichen parst nicht');
  finally
    Val.Free;
    Findings.Free;
  end;
end;


{ ---- Lauf-Diagnosen ---- }

procedure TTestExportSonarGeneric.FileReadError_ProducesNoIssueAndNoRule;
// Beides zusammen ist der Punkt: ein rules[]-Eintrag ohne Issue waere eine
// Rausch-Regel im Repository, ein Issue ohne rules[]-Eintrag kann Sonar
// nicht koppeln. Der Test wird rot, sobald der Skip unter die
// Rules-Sammlung rutscht.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkFileReadError, DIAG_FILE, 0, DIAG_MSG));
    Root := TJSONObject.ParseJSONValue(
      TSonarGenericWriter.ToJsonString(Findings, '')) as TJSONObject;
    Assert.IsNotNull(Root, MSG_NOT_JSON);
    Assert.AreEqual<Integer>(0, Root.GetValue<TJSONArray>(KEY_ISSUES).Count);
    Assert.AreEqual<Integer>(0, Root.GetValue<TJSONArray>(KEY_RULES).Count);
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarGeneric.RealFindingsSurviveAlongsideReadError;
// Der Skip darf keinen Zustand verschieben: die echten Funde muessen
// vollstaendig durchkommen, die Diagnose-Regel nirgends auftauchen.
var
  Findings : TObjectList<TLeakFinding>;
  Json     : string;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkFileReadError, DIAG_FILE, 0, DIAG_MSG));
    Findings.Add(MakeFinding(fkMemoryLeak, GOOD_FILE, 12, 'leak'));
    Findings.Add(MakeFinding(fkFileReadError, 'src\Kaputt2.pas', 0, DIAG_MSG));
    Findings.Add(MakeFinding(fkSQLInjection, GOOD_FILE, 7, 'sql'));
    Json := TSonarGenericWriter.ToJsonString(Findings, '');
    Root := TJSONObject.ParseJSONValue(Json) as TJSONObject;
    Assert.IsNotNull(Root, MSG_NOT_JSON);
    Assert.AreEqual<Integer>(2, Root.GetValue<TJSONArray>(KEY_ISSUES).Count);
    Assert.AreEqual<Integer>(2, Root.GetValue<TJSONArray>(KEY_RULES).Count);
    Assert.AreEqual<Integer>(0, Pos('SCA006', Json),
      'SCA006 darf weder in issues noch in rules stehen');
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarGeneric.EncodingFindingsAreNotSkipped;
// SCA186/187 tragen denselben FindingType (ftFileError) wie der Lesefehler,
// sind aber echte Inhaltsbefunde. Ein Praedikat ueber FindingType statt
// ueber den Kind wuerde sie hier aus dem Export werfen.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkSourceInvalidUtf8, GOOD_FILE, 3, 'utf8'));
    Findings.Add(MakeFinding(fkSourceControlChar, DIAG_FILE, 4, 'ctrl'));
    Root := TJSONObject.ParseJSONValue(
      TSonarGenericWriter.ToJsonString(Findings, '')) as TJSONObject;
    Assert.IsNotNull(Root, MSG_NOT_JSON);
    Assert.AreEqual<Integer>(2, Root.GetValue<TJSONArray>(KEY_ISSUES).Count);
    Assert.AreEqual<Integer>(2, Root.GetValue<TJSONArray>(KEY_RULES).Count);
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarGeneric.OnlyReadErrors_ProducesValidEmptyReport;
// Sonar akzeptiert einen leeren Report - er muss aber gueltiges JSON
// bleiben und darf nicht zum Leerstring werden.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkFileReadError, DIAG_FILE, 0, DIAG_MSG));
    Findings.Add(MakeFinding(fkFileReadError, GOOD_FILE, 0, DIAG_MSG));
    Root := TJSONObject.ParseJSONValue(
      TSonarGenericWriter.ToJsonString(Findings, '')) as TJSONObject;
    Assert.IsNotNull(Root, MSG_NOT_JSON);
    Assert.AreEqual<Integer>(0, Root.GetValue<TJSONArray>(KEY_RULES).Count);
    Assert.AreEqual<Integer>(0, Root.GetValue<TJSONArray>(KEY_ISSUES).Count);
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarGeneric.DowngradedFinding_IsNotExported;
// Der Kern der Entscheidung von 2026-08-22: Sonar kann keine Severity je
// Fund. Ein herabgestufter Fund kaeme dort in voller Katalog-Schwere an und
// wuerde das Quality Gate reissen - das Gegenteil dessen, was die
// Herabstufung ausdruecken sollte. Also gar nicht erst exportieren.
// Wie beim Lesefehler gilt: WEDER Issue NOCH Regel, sonst bleibt ein toter
// rules[]-Eintrag stehen.
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Fnd := MakeFinding(fkMemoryLeak, 'src\Gen.pas', 12, 'list not freed');
    Fnd.Severity := lsHint;          // herabgestuft, Katalog sagt Error
    Findings.Add(Fnd);
    Root := TJSONObject.ParseJSONValue(
      TSonarGenericWriter.ToJsonString(Findings, '')) as TJSONObject;
    Assert.IsNotNull(Root, MSG_NOT_JSON);
    Assert.AreEqual<Integer>(0, Root.GetValue<TJSONArray>(KEY_ISSUES).Count,
      'herabgestufter Fund darf kein Issue erzeugen');
    Assert.AreEqual<Integer>(0, Root.GetValue<TJSONArray>(KEY_RULES).Count,
      'und auch keine Regel - sonst steht sie ohne Fund im Report');
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarGeneric.UpgradedFinding_StaysExported;
// Die Gegenrichtung, und der eigentliche Grund fuer den Rangfolge-Vergleich:
// poaSeverityError stuft HOCH. Ein blosser Ungleichheitsvergleich haette
// solche Funde mitverschluckt - genau das darf nicht passieren.
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Fnd := MakeFinding(fkDebugOutput, 'src\Foo.pas', 7, 'OutputDebugString');
    Fnd.Severity := lsError;         // hochgestuft, Katalog sagt Hint
    Findings.Add(Fnd);
    Root := TJSONObject.ParseJSONValue(
      TSonarGenericWriter.ToJsonString(Findings, '')) as TJSONObject;
    Assert.IsNotNull(Root, MSG_NOT_JSON);
    Assert.AreEqual<Integer>(1, Root.GetValue<TJSONArray>(KEY_ISSUES).Count,
      'hochgestufter Fund gehoert in den Report');
    Assert.AreEqual<Integer>(1, Root.GetValue<TJSONArray>(KEY_RULES).Count);
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarGeneric.DowngradedFinding_KeptWhenAsked;
// Der Schalter: wer die Herabstufung trotzdem im Report haben will, bekommt
// sie - dann eben mit der Katalog-Schwere, mehr gibt das Format nicht her.
var
  Findings : TObjectList<TLeakFinding>;
  Fnd      : TLeakFinding;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Fnd := MakeFinding(fkMemoryLeak, 'src\Gen.pas', 12, 'list not freed');
    Fnd.Severity := lsHint;
    Findings.Add(Fnd);
    Root := TJSONObject.ParseJSONValue(
      TSonarGenericWriter.ToJsonString(Findings, '', True)) as TJSONObject;
    Assert.IsNotNull(Root, MSG_NOT_JSON);
    Assert.AreEqual<Integer>(1, Root.GetValue<TJSONArray>(KEY_ISSUES).Count,
      'mit AKeepDowngraded muss der Fund drin sein');
  finally
    Root.Free;
    Findings.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExportSonarGeneric);

end.
