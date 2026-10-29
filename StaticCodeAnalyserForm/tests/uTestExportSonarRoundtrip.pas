unit uTestExportSonarRoundtrip;

// Tests fuer die Befunde der Sonar-Roundtrip-Pruefung vom 2026-10-29:
// Faelle, in denen ein formal gueltiger Report beim Import trotzdem Funde
// verliert oder den Scanner abbrechen laesst, weil er nicht zu den Dateien
// passt, die Sonar indexiert.
//
// Eigene Unit, weil uTestExportSonarGeneric an der GodClass-Schwelle steht
// (s. Kopf von uTestExportSonarTextRange). Die Faelle brauchen ECHTE
// Dateien - Sonar vergleicht gegen die Platte, also tut es der Export auch.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON,
  uMethodd12, uSCAConsts;

type
  [TestFixture]
  TTestExportSonarRoundtrip = class
  private
    FDir : string;
    procedure WriteBytes(const ARel: string; const ABytes: TBytes);
    function  Report(const AFindings: TObjectList<TLeakFinding>): TJSONObject;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    // Gross-/Kleinschreibung: Sonar vergleicht den Pfad exakt
    [Test] procedure FilePath_TakesCasingFromDisk;
    [Test] procedure FilePath_MissingFileKeepsSpelling;
    // Zeilen, die Sonar nicht kennt: Scanner-Abbruch statt Fund
    [Test] procedure BinaryFile_IssueOnFileLevel;
    [Test] procedure LineBeyondEof_IssueOnFileLevel;
    [Test] procedure EndLineBeyondEof_IsClamped;
    [Test] procedure LoneCr_CountsAsLineLikeSonar;
    [Test] procedure UnreadableFile_KeepsTextRange;
    // Custom-Regeln: YAML-Severity ist keine Herabstufung
    [Test] procedure CustomRuleHint_IsExportedWithLowImpact;
    [Test] procedure CustomRuleError_GetsHighImpactAndOwnName;
    // ... eine Pfad-Ueberschreibung aber sehr wohl
    [Test] procedure CustomRulePathDowngrade_StaysOutAndKeepsYamlImpact;
  end;

implementation

uses
  System.IOUtils,
  uExportSonarGeneric;

const
  KEY_ISSUES   = 'issues';
  KEY_PRIMARY  = 'primaryLocation';
  MSG_NOT_JSON = 'Report ist kein gueltiges JSON-Object';

function MakeFinding(AKind: TFindingKind; const AFile: string;
  ALine: Integer): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.SetKind(AKind);
  Result.FileName   := AFile;
  Result.LineNumber := IntToStr(ALine);
  Result.MissingVar := 'probe';
end;

function FirstIssue(ARoot: TJSONObject): TJSONObject;
begin
  Result := ARoot.GetValue<TJSONArray>(KEY_ISSUES).Items[0] as TJSONObject;
end;

function TextRangeOf(ARoot: TJSONObject): TJSONObject;
// nil, wenn das Issue auf Dateiebene steht.
var
  V : TJSONValue;
begin
  V := FirstIssue(ARoot).GetValue<TJSONObject>(KEY_PRIMARY).GetValue('textRange');
  if V is TJSONObject then
    Result := TJSONObject(V)
  else
    Result := nil;
end;

function FilePathOf(ARoot: TJSONObject): string;
begin
  Result := FirstIssue(ARoot).GetValue<TJSONObject>(KEY_PRIMARY)
              .GetValue<string>('filePath');
end;

procedure TTestExportSonarRoundtrip.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath,
    'sca_sonar_rt_' + TGUID.NewGuid.ToString.Replace('{', '').Replace('}', ''));
  TDirectory.CreateDirectory(FDir);
end;

procedure TTestExportSonarRoundtrip.TearDown;
begin
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

procedure TTestExportSonarRoundtrip.WriteBytes(const ARel: string;
  const ABytes: TBytes);
var
  Full : string;
begin
  Full := TPath.Combine(FDir, ARel);
  TDirectory.CreateDirectory(ExtractFilePath(Full));
  TFile.WriteAllBytes(Full, ABytes);
end;

function TTestExportSonarRoundtrip.Report(
  const AFindings: TObjectList<TLeakFinding>): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(
    TSonarGenericWriter.ToJsonString(AFindings, FDir)) as TJSONObject;
  Assert.IsNotNull(Result, MSG_NOT_JSON);
end;

{ ---- Gross-/Kleinschreibung ---- }

procedure TTestExportSonarRoundtrip.FilePath_TakesCasingFromDisk;
// Die Engine bildet den DFM-Namen aus dem Unit-Namen; auf der Platte heisst
// die Datei 'ABOUT.DFM'. Windows findet sie trotzdem, Sonar nicht - dort
// muss der filePath exakt der Verzeichnis-Schreibweise folgen, auch im
// Ordnerteil.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root := nil;
  WriteBytes(TPath.Combine('Forms', 'ABOUT.DFM'), TEncoding.ASCII.GetBytes(
    'object AboutBox: TAboutBox' + sLineBreak + 'end' + sLineBreak));
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkDfmDefaultName,
      TPath.Combine(TPath.Combine(FDir, 'FORMS'), 'ABOUT.dfm'), 1));
    Root := Report(Findings);
    Assert.AreEqual('Forms/ABOUT.DFM', FilePathOf(Root));
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.FilePath_MissingFileKeepsSpelling;
// Gibt es die Datei nicht (mehr), bleibt der Pfad wie er war - lieber den
// Fund unveraendert durchreichen als eine Schreibweise erfinden.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak,
      TPath.Combine(TPath.Combine(FDir, 'gibtsnicht'), 'Weg.PAS'), 3));
    Root := Report(Findings);
    Assert.AreEqual('gibtsnicht/Weg.PAS', FilePathOf(Root));
  finally
    Root.Free;
    Findings.Free;
  end;
end;

{ ---- Zeilen, die Sonar nicht kennt ---- }

procedure TTestExportSonarRoundtrip.BinaryFile_IssueOnFileLevel;
// Binaere DFM: die Engine zaehlt Zeilen der TEXT-Umwandlung, Sonar die der
// Binaerdatei. Eine Zeile dahinter laesst den Scanner abbrechen ("N is not a
// valid line for pointer"); und selbst eine Zeile innerhalb der Grenzen
// zeigt auf Binaermuell. Also Dateiebene: keine textRange.
//
// Zeile 1 mit Absicht: die Datei hat nach Sonar ZWEI Zeilen (ein $0A), der
// Fund liegt also in den Grenzen. Mit einer Zeile dahinter waere der Test
// auch ohne die NUL-Erkennung gruen (LineBeyondEof deckt jenen Zweig).
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root := nil;
  WriteBytes('Bin.dfm', TBytes.Create($FF, $0A, $00, Ord('T'), Ord('P'),
    Ord('F'), Ord('0'), $00, $01, $02));
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkDfmDefaultName, TPath.Combine(FDir, 'Bin.dfm'), 1));
    Root := Report(Findings);
    Assert.IsNull(TextRangeOf(Root), 'binaere Datei: Issue ohne textRange');
    Assert.AreEqual('Bin.dfm', FilePathOf(Root), 'der Fund selbst bleibt');
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.LineBeyondEof_IssueOnFileLevel;
// Zwei Zeilen nach Sonar ('a', 'b'), Fund auf Zeile 7.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root := nil;
  WriteBytes('Kurz.pas', TEncoding.ASCII.GetBytes('a'#13#10'b'));
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, TPath.Combine(FDir, 'Kurz.pas'), 7));
    Root := Report(Findings);
    Assert.IsNull(TextRangeOf(Root), 'Zeile hinter dem Dateiende: Dateiebene');
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.EndLineBeyondEof_IsClamped;
// Fuenf Zeilen nach Sonar (vier CRLF + 'e'), Fund 2..9: endLine wird 5.
var
  Findings : TObjectList<TLeakFinding>;
  F        : TLeakFinding;
  Root     : TJSONObject;
begin
  Root := nil;
  WriteBytes('Fuenf.pas', TEncoding.ASCII.GetBytes(
    'a'#13#10'b'#13#10'c'#13#10'd'#13#10'e'));
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    F := MakeFinding(fkLongMethod, TPath.Combine(FDir, 'Fuenf.pas'), 2);
    F.EndLine := 9;
    Findings.Add(F);
    Root := Report(Findings);
    Assert.IsNotNull(TextRangeOf(Root));
    Assert.AreEqual<Integer>(2, TextRangeOf(Root).GetValue<Integer>('startLine'));
    Assert.AreEqual<Integer>(5, TextRangeOf(Root).GetValue<Integer>('endLine'));
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.LoneCr_CountsAsLineLikeSonar;
// Sonar zaehlt ein einzelnes CR als Zeilenende: 'a'#13'b'#13'c' hat drei
// Zeilen, Zeile 3 ist gueltig und behaelt ihre textRange.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root := nil;
  WriteBytes('Cr.pas', TEncoding.ASCII.GetBytes('a'#13'b'#13'c'));
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, TPath.Combine(FDir, 'Cr.pas'), 3));
    Root := Report(Findings);
    Assert.IsNotNull(TextRangeOf(Root), 'Zeile 3 existiert nach Sonar-Zaehlung');
    Assert.AreEqual<Integer>(3, TextRangeOf(Root).GetValue<Integer>('startLine'));
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.UnreadableFile_KeepsTextRange;
// Ohne lesbare Datei weiss der Export nichts ueber ihre Zeilen - dann bleibt
// der Fund wie er ist (das ist auch der Fall aller Tests mit erfundenen
// Pfaden in uTestExportSonarGeneric).
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, TPath.Combine(FDir, 'Fehlt.pas'), 42));
    Root := Report(Findings);
    Assert.IsNotNull(TextRangeOf(Root));
    Assert.AreEqual<Integer>(42, TextRangeOf(Root).GetValue<Integer>('startLine'));
  finally
    Root.Free;
    Findings.Free;
  end;
end;

{ ---- Custom-Regeln ---- }

function CustomFinding(const AFile, ARuleID: string;
  ASeverity: TLeakSeverity): TLeakFinding;
// Wie uCustomRuleDetector: Kind per Feldzuweisung, Severity aus der YAML.
begin
  Result := MakeFinding(fkCustomRule, AFile, 4);
  Result.RuleID   := ARuleID;
  Result.Severity := ASeverity;
end;

function FirstRule(ARoot: TJSONObject): TJSONObject;
begin
  Result := ARoot.GetValue<TJSONArray>('rules').Items[0] as TJSONObject;
end;

function ImpactSeverityOf(ARule: TJSONObject): string;
begin
  Result := (ARule.GetValue<TJSONArray>('impacts').Items[0] as TJSONObject)
              .GetValue<string>('severity');
end;

procedure TTestExportSonarRoundtrip.CustomRuleHint_IsExportedWithLowImpact;
// Bis 2026-10-29 verglich IsDowngraded die YAML-Severity 'hint' mit dem
// Katalog-Platzhalter SCA023 (Warning) und warf den Fund still raus.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(CustomFinding(TPath.Combine(FDir, 'X.pas'), 'MINI001', lsHint));
    Root := Report(Findings);
    Assert.AreEqual<Integer>(1, Root.GetValue<TJSONArray>(KEY_ISSUES).Count,
      'Custom-Regel mit severity hint gehoert in den Report');
    Assert.AreEqual('MINI001', FirstRule(Root).GetValue<string>('id'));
    Assert.AreEqual('LOW', ImpactSeverityOf(FirstRule(Root)));
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.CustomRuleError_GetsHighImpactAndOwnName;
// 'error' kam bisher als MEDIUM des Platzhalters an, und alle Custom-Regeln
// hiessen in Sonar gleich.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
  Name     : string;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(CustomFinding(TPath.Combine(FDir, 'X.pas'), 'MINI002', lsError));
    Root := Report(Findings);
    Assert.AreEqual('HIGH', ImpactSeverityOf(FirstRule(Root)));
    Name := FirstRule(Root).GetValue<string>('name');
    Assert.IsTrue(Pos('MINI002', Name) > 0, 'Regelname nennt die ID: ' + Name);
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarRoundtrip.CustomRulePathDowngrade_StaysOutAndKeepsYamlImpact;
// YAML 'error', in generiertem Code per Pfad-Ueberschreibung auf Hint
// gesetzt (OverrideSeverity, wie uPathOverrides): das IST eine Herabstufung
// und bleibt ohne --sonar-keep-downgraded draussen. Mit dem Schalter steht
// der Fund als ERSTER in der Liste - die Regel muss trotzdem HIGH bleiben,
// sonst bestimmte ein einzelner Fund in generiertem Code die Schwere aller.
var
  Findings : TObjectList<TLeakFinding>;
  F        : TLeakFinding;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    F := CustomFinding(TPath.Combine(FDir, 'Gen.pas'), 'MINI003', lsError);
    F.OverrideSeverity(lsHint);
    Findings.Add(F);
    Findings.Add(CustomFinding(TPath.Combine(FDir, 'Hand.pas'), 'MINI003', lsError));

    Root := Report(Findings);
    Assert.AreEqual<Integer>(1, Root.GetValue<TJSONArray>(KEY_ISSUES).Count,
      'herabgestufter Custom-Fund bleibt draussen, der andere nicht');
    Assert.AreEqual('HIGH', ImpactSeverityOf(FirstRule(Root)));
    FreeAndNil(Root);

    Root := TJSONObject.ParseJSONValue(
      TSonarGenericWriter.ToJsonString(Findings, FDir, True)) as TJSONObject;
    Assert.IsNotNull(Root, MSG_NOT_JSON);
    Assert.AreEqual<Integer>(2, Root.GetValue<TJSONArray>(KEY_ISSUES).Count,
      'mit --sonar-keep-downgraded beide');
    Assert.AreEqual('HIGH', ImpactSeverityOf(FirstRule(Root)),
      'Impact aus der YAML-Severity, nicht aus dem herabgestuften ersten Fund');
  finally
    Root.Free;
    Findings.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExportSonarRoundtrip);

end.
