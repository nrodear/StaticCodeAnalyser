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

initialization
  TDUnitX.RegisterTestFixture(TTestExportSonarRoundtrip);

end.
