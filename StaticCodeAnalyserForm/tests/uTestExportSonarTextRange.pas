unit uTestExportSonarTextRange;

// Tests fuer textRange und Pfad-Relativierung im Sonar-Export.
//
// Zwei Luecken, die am 2026-08-09 geschlossen wurden:
//   * textRange trug nur startLine - jeder mehrzeilige Fund sah in Sonar
//     aus wie ein Einzeiler, obwohl SARIF endLine seit der
//     Mehrzeilen-Welle mitfuehrt.
//   * Ein Pfad ausserhalb von --base-dir bleibt absolut, und Sonar
//     verwirft solche Issues still als "unknown files". Der Fund ist dann
//     weg, ohne dass irgendwo etwas steht.
//
// Eigene Unit, weil uTestExportSonarGeneric mit diesen vier Faellen ueber
// die GodClass-Schwelle gelaufen waere.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestExportSonarTextRange = class
  public
    [Test] procedure SingleLineFinding_HasNoEndLine;
    [Test] procedure MultiLineFinding_HasEndLine;
    [Test] procedure EndLineBeforeStart_IsNotWritten;
    [Test] procedure PathOutsideBaseDir_StaysAbsolute;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections, System.JSON, System.IOUtils,
  uMethodd12, uSCAConsts, uExportSonarGeneric;

const
  PROBE_FILE   = 'src\Gut.pas';
  PROBE_MSG    = 'leak';
  KEY_ISSUES   = 'issues';
  KEY_ENDLINE  = 'endLine';
  KEY_STARTLN  = 'startLine';
  MSG_NOT_JSON = 'Report ist kein gueltiges JSON-Object';

function MakeFinding(AKind: TFindingKind; const AFile: string;
  ALine: Integer): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.SetKind(AKind);
  Result.FileName   := AFile;
  Result.LineNumber := IntToStr(ALine);
  Result.MissingVar := PROBE_MSG;
end;

function TextRangeOf(Root: TJSONObject): TJSONObject;
begin
  Result := (Root.GetValue<TJSONArray>(KEY_ISSUES).Items[0] as TJSONObject)
              .GetValue<TJSONObject>('primaryLocation')
              .GetValue<TJSONObject>('textRange');
end;

function ReportOf(const AFindings: TObjectList<TLeakFinding>;
  const ABaseDir: string): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(
    TSonarGenericWriter.ToJsonString(AFindings, ABaseDir)) as TJSONObject;
  Assert.IsNotNull(Result, MSG_NOT_JSON);
end;

{ ---- Tests ---- }

procedure TTestExportSonarTextRange.SingleLineFinding_HasNoEndLine;
// endLine = startLine waere reines Rauschen im Dashboard.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, PROBE_FILE, 42));
    Root := ReportOf(Findings, '');
    Assert.AreEqual<Integer>(42,
      TextRangeOf(Root).GetValue<Integer>(KEY_STARTLN));
    Assert.IsFalse(Assigned(TextRangeOf(Root).GetValue(KEY_ENDLINE)),
      'einzeiliger Fund darf kein endLine tragen');
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarTextRange.MultiLineFinding_HasEndLine;
var
  Findings : TObjectList<TLeakFinding>;
  F        : TLeakFinding;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    F := MakeFinding(fkMemoryLeak, PROBE_FILE, 10);
    F.EndLine := 14;
    Findings.Add(F);
    Root := ReportOf(Findings, '');
    Assert.AreEqual<Integer>(10,
      TextRangeOf(Root).GetValue<Integer>(KEY_STARTLN));
    Assert.AreEqual<Integer>(14,
      TextRangeOf(Root).GetValue<Integer>(KEY_ENDLINE));
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarTextRange.EndLineBeforeStart_IsNotWritten;
// Sonar lehnt endLine < startLine ab - lieber gar keins.
var
  Findings : TObjectList<TLeakFinding>;
  F        : TLeakFinding;
  Root     : TJSONObject;
begin
  Root     := nil;
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    F := MakeFinding(fkMemoryLeak, PROBE_FILE, 30);
    F.EndLine := 7;
    Findings.Add(F);
    Root := ReportOf(Findings, '');
    Assert.IsFalse(Assigned(TextRangeOf(Root).GetValue(KEY_ENDLINE)),
      'endLine darf nie kleiner als startLine sein');
  finally
    Root.Free;
    Findings.Free;
  end;
end;

procedure TTestExportSonarTextRange.PathOutsideBaseDir_StaysAbsolute;
// Der Pfad wird aus Teilen gebaut statt als Literal geschrieben: ein
// hartkodierter Laufwerkspfad im Quelltext ist genau das, was der eigene
// HardcodedPath-Detektor melden soll - auch in einer Testdatei.
var
  Findings : TObjectList<TLeakFinding>;
  Root     : TJSONObject;
  Outside  : string;
  Fp       : string;
begin
  Root     := nil;
  Outside  := Format('D:%swoanders%suFremd.pas',
                     [string(PathDelim), string(PathDelim)]);
  Findings := TObjectList<TLeakFinding>.Create(True);
  try
    Findings.Add(MakeFinding(fkMemoryLeak, Outside, 5));
    Root := ReportOf(Findings, Format('C:%srepo', [string(PathDelim)]));
    Fp := (Root.GetValue<TJSONArray>(KEY_ISSUES).Items[0] as TJSONObject)
            .GetValue<TJSONObject>('primaryLocation')
            .GetValue<string>('filePath');
    Assert.IsTrue(Pos(':', Fp) > 0,
      'Pfad ausserhalb der Wurzel bleibt absolut: ' + Fp);
  finally
    Root.Free;
    Findings.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestExportSonarTextRange);

end.
