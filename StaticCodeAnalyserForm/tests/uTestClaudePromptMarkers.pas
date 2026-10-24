unit uTestClaudePromptMarkers;

// Tests fuer uClaudePrompt, Review 2026-10-13: der Marker-Hinweis fuer
// Funde in Formdateien (.dfm kennt keinen Kommentar - der dateiweite
// Marker gehoert in die Schwester-Unit) und die Zaunlaenge der Markdown-
// Codebloecke (``` im Code darf den Block nicht schliessen). Eigene
// Fixture neben uTestClaudePrompt (Snippet-Cache), gleicher Temp-Aufbau.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.IOUtils,
  uSCAConsts, uMethodd12, uFixHint, uClaudePrompt;

type
  [TestFixture]
  TTestClaudePromptMarkers = class
  strict private
    FDir : string;   // eigenes Temp-Verzeichnis, TearDown raeumt ab
    function WriteFile(const AName, AText: string): string;
    function PromptFor(const APath: string; ALine: Integer; AKind: TFindingKind;
      const AHint: TFixHint): string;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure FormFile_SuggestsFileWideMarkerInPairedUnit;
    [Test] procedure FormFile_WithoutUnit_NamesPasBeside;
    // Lazarus-Form NACH dem Scan (ScanDialect wieder dlDelphi): bleibt
    // Formdatei, die .pp-Unit wird genannt (Review Woche G02-02).
    [Test] procedure LfmFile_DelphiDialect_SuggestsFileWideMarkerInPp;
    [Test] procedure PascalFile_KeepsLineMarker;
    [Test] procedure Snippet_WithBackticks_UsesLongerFence;
    [Test] procedure Snippet_Plain_UsesThreeBackticks;
    [Test] procedure Hint_WithBackticks_UsesLongerFence;
  end;

implementation

uses
  uStaticFiles;   // ScanDialect - der nach dem Scan zurueckgesetzte Dialekt

const
  // DFM-Fund: eine Kind-Konstante, die es gibt; der Hinweis haengt nur
  // am Dateinamen, nicht an der Regel.
  FORM_KIND = fkDfmHardcodedCaption;
  // Drei Backticks in einer Codezeile - Markdown-Hilfe als Literal.
  TRIPLE = '```';

procedure TTestClaudePromptMarkers.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath,
    'sca_promptmarker_' + TGUID.NewGuid.ToString.Trim(['{', '}']));
  TDirectory.CreateDirectory(FDir);
end;

procedure TTestClaudePromptMarkers.TearDown;
begin
  try
    if TDirectory.Exists(FDir) then
      TDirectory.Delete(FDir, True);
  // noinspection EmptyExcept
  except
    // Aufraeumen darf keinen Testlauf kippen (gesperrte Datei o.ae.).
  end;
end;

function TTestClaudePromptMarkers.WriteFile(const AName, AText: string): string;
begin
  Result := TPath.Combine(FDir, AName);
  TFile.WriteAllText(Result, AText, TEncoding.UTF8);
end;

function TTestClaudePromptMarkers.PromptFor(const APath: string; ALine: Integer;
  AKind: TFindingKind; const AHint: TFixHint): string;
var
  F : TLeakFinding;
begin
  F := TLeakFinding.New(APath, '', ALine, 'probe', AKind);
  try
    Result := TClaudePrompt.Build(F, AHint);
  finally
    F.Free;
  end;
end;

procedure TTestClaudePromptMarkers.FormFile_SuggestsFileWideMarkerInPairedUnit;
var
  Dfm, Prompt : string;
begin
  WriteFile('Unit1.pas', 'unit Unit1;'#13#10'interface'#13#10'implementation'#13#10'end.');
  Dfm := WriteFile('Unit1.dfm', 'object Form1: TForm1'#13#10'  Caption = ''Hallo'''#13#10'end');
  Prompt := PromptFor(Dfm, 2, FORM_KIND, Default(TFixHint));
  // Sprachunabhaengig: Marker und Unit-Name stehen in jeder Uebersetzung
  // woertlich in Code-Spans.
  Assert.IsTrue(Pos('`// noinspection-file DfmHardcodedCaption`', Prompt) > 0,
    'dateiweiter Marker: ' + Prompt);
  Assert.IsTrue(Pos('`Unit1.pas`', Prompt) > 0, 'Schwester-Unit genannt: ' + Prompt);
  Assert.AreEqual<Integer>(0, Pos('`// noinspection DfmHardcodedCaption`', Prompt),
    'keine Zeilenform fuer eine Formdatei');
end;

procedure TTestClaudePromptMarkers.FormFile_WithoutUnit_NamesPasBeside;
var
  Dfm, Prompt : string;
begin
  // Keine .pas daneben: der Hinweis nennt trotzdem den .pas-Namen - die
  // Unit entsteht ohnehin neben der Form.
  Dfm := WriteFile('Lonely.dfm', 'object Form1: TForm1'#13#10'end');
  Prompt := PromptFor(Dfm, 1, FORM_KIND, Default(TFixHint));
  Assert.IsTrue(Pos('`Lonely.pas`', Prompt) > 0, Prompt);
  Assert.IsTrue(Pos('`// noinspection-file DfmHardcodedCaption`', Prompt) > 0, Prompt);
end;

procedure TTestClaudePromptMarkers.LfmFile_DelphiDialect_SuggestsFileWideMarkerInPp;
var
  Lfm, Prompt : string;
  Alt         : TSourceDialect;
begin
  // Der Prompt entsteht nach dem Scan; Run hat ScanDialect dann auf den
  // Vorzustand dlDelphi zurueckgesetzt. Die .lfm ist trotzdem eine
  // Formdatei, ihre Unit hier die .pp (ohne .pas daneben).
  WriteFile('Form5.pp', 'unit Form5;'#13#10'interface'#13#10'implementation'#13#10'end.');
  Lfm := WriteFile('Form5.lfm', 'object Form5: TForm5'#13#10'  Caption = ''Hallo'''#13#10'end');
  Alt := TStaticFiles.ScanDialect;
  TStaticFiles.ScanDialect := dlDelphi;
  try
    Prompt := PromptFor(Lfm, 2, FORM_KIND, Default(TFixHint));
  finally
    TStaticFiles.ScanDialect := Alt;
  end;
  Assert.IsTrue(Pos('`// noinspection-file DfmHardcodedCaption`', Prompt) > 0,
    'dateiweiter Marker auch fuer die .lfm: ' + Prompt);
  Assert.IsTrue(Pos('`Form5.pp`', Prompt) > 0, '.pp-Unit genannt: ' + Prompt);
  Assert.AreEqual<Integer>(0, Pos('`// noinspection DfmHardcodedCaption`', Prompt),
    'keine Zeilenform fuer die Lazarus-Form');
end;

procedure TTestClaudePromptMarkers.PascalFile_KeepsLineMarker;
var
  Pas, Prompt : string;
begin
  Pas := WriteFile('Unit2.pas', 'unit Unit2;'#13#10'interface'#13#10'implementation'#13#10'end.');
  Prompt := PromptFor(Pas, 2, fkMemoryLeak, Default(TFixHint));
  Assert.IsTrue(Pos('`// noinspection MemoryLeak`', Prompt) > 0, Prompt);
  Assert.AreEqual<Integer>(0, Pos('noinspection-file', Prompt), 'Pascal: Zeilenform');
end;

procedure TTestClaudePromptMarkers.Snippet_WithBackticks_UsesLongerFence;
var
  Pas, Prompt : string;
begin
  // Zeile 2 traegt ``` - der Zaun muss laenger sein als jeder Backtick-
  // Lauf im Auszug (CommonMark 4.5), sonst endet der Block in Zeile 2.
  Pas := WriteFile('Unit3.pas',
    'unit Unit3;'#13#10 +
    '// Beispiel: ' + TRIPLE + 'pascal'#13#10 +
    'interface'#13#10'implementation'#13#10'end.');
  Prompt := PromptFor(Pas, 3, fkMemoryLeak, Default(TFixHint));
  Assert.IsTrue(Pos(#10'````pascal'#13#10, Prompt) > 0, 'Zaun mit vier Backticks: ' + Prompt);
  Assert.AreEqual<Integer>(0, Pos(#10'```pascal'#13#10, Prompt), 'kein Dreier-Zaun um den Auszug');
end;

procedure TTestClaudePromptMarkers.Snippet_Plain_UsesThreeBackticks;
var
  Pas, Prompt : string;
begin
  Pas := WriteFile('Unit4.pas', 'unit Unit4;'#13#10'interface'#13#10'implementation'#13#10'end.');
  Prompt := PromptFor(Pas, 2, fkMemoryLeak, Default(TFixHint));
  Assert.IsTrue(Pos(#10'```pascal'#13#10, Prompt) > 0, 'Dreier-Zaun ohne Backticks im Code: ' + Prompt);
  Assert.AreEqual<Integer>(0, Pos('````', Prompt), 'kein laengerer Zaun noetig');
end;

procedure TTestClaudePromptMarkers.Hint_WithBackticks_UsesLongerFence;
var
  Hint   : TFixHint;
  Prompt : string;
begin
  // Vorher/Nachher-Bloecke bekommen ihren Zaun je Block aus dem Inhalt.
  Hint := Default(TFixHint);
  Hint.Before := 'S := ''' + TRIPLE + TRIPLE + ''';';   // sechs Backticks am Stueck
  Hint.After  := 'S := Fence;';
  Prompt := PromptFor(TPath.Combine(FDir, 'Missing.pas'), 1, fkMemoryLeak, Hint);
  Assert.IsTrue(Pos(#10'```````pascal'#13#10, Prompt) > 0, 'Anti-Pattern: sieben Backticks: ' + Prompt);
  Assert.IsTrue(Pos(#10'```pascal'#13#10'S := Fence;', Prompt) > 0, 'Fix: Dreier-Zaun: ' + Prompt);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestClaudePromptMarkers);

end.
