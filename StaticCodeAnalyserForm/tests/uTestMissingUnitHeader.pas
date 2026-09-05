unit uTestMissingUnitHeader;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestMissingUnitHeader = class
  public
    [Test] procedure NoHeader_Reported;
    [Test] procedure WithLineComment_NotReported;
    [Test] procedure WithBlockComment_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // AQL Hint-Tier 03.09.: eine Kommentar-Prosazeile wurde fuer die
    // unit-Klausel gehalten (pyscripter-Kopfvorlage).
    [Test] procedure CommentLineStartingWithUnit_FindingOnRealDecl;
    [Test] procedure ReallyNoHeader_StillReported;
    // --- Geltungsbereich-Gate (Produktentscheidung 2026-09-05) ---
    // Direkte Aufrufe mit ECHTEN Temp-Dateien, weil der Harness-
    // Platzhalterpfad keine Testsegmente traegt: /tests/ wird
    // uebersprungen, /src/ meldet weiter.
    [Test] procedure UnitInTestsDir_NotReported;
    [Test] procedure UnitInSrcDir_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  System.Generics.Collections,
  uSCAConsts, uMethodd12, uAstNode, uParser2, uMissingUnitHeader,
  uTestFindingHelper;

procedure TTestMissingUnitHeader.NoHeader_Reported;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkMissingUnitHeader) >= 1);
  finally F.Free; end;
end;

procedure TTestMissingUnitHeader.CommentLineStartingWithUnit_FindingOnRealDecl;
// Erkennerfehler (AQL Hint-Tier 03.09.): LineIsUnitDecl prueste nur das
// Praefix "unit " und traf damit die Prosazeile " Unit Name: X" der
// pyscripter-Kopfvorlage. Gemeldet wurde dann eine KOMMENTARZEILE als
// Ort der fehlenden Unit-Beschreibung.
//
// Der FUND selbst bleibt richtig: die Regel verlangt woertlich einen
// Kommentar ZWISCHEN "unit ...;" und "interface", und dort steht
// keiner - der Kopf liegt davor. Geprueft wird hier also die POSITION,
// nicht das Verschwinden. Vor dem Fix: Zeile 2 (Prosazeile), danach
// Zeile 6 (echte Klausel).
//
// Belege: pyscripter frmProjectExplorer.pas, uEditAppIntfs.pas.
const SRC =
  '{-------------------------------------------------------------'#13#10 +
  ' Unit Name: frmTest'#13#10 +
  ' Author:    someone'#13#10 +
  ' Purpose:   Verwaltet die Testansicht der Anwendung.'#13#10 +
  '-------------------------------------------------------------}'#13#10 +
  'unit frmTest;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMissingUnitHeader),
      'der Fund bleibt - zwischen Klausel und interface steht kein Kommentar');
    Assert.AreEqual('6', TFindingHelper.FirstOf(F, fkMissingUnitHeader).LineNumber,
      'gemeldet wird die ECHTE unit-Klausel, nicht die Kommentar-Prosazeile');
  finally F.Free; end;
end;

procedure TTestMissingUnitHeader.ReallyNoHeader_StillReported;
// WAECHTER: ohne jeden Kopf bleibt der Fund. Die verschaerfte
// Klausel-Erkennung darf die Regel nicht stumm machen.
const SRC =
  'unit frmLeer;'#13#10 +
  'interface'#13#10 +
  'implementation'#13#10 +
  'end.'#13#10;
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMissingUnitHeader),
    'ohne jeden Kopfkommentar bleibt der Fund');
  finally F.Free; end;
end;

procedure TTestMissingUnitHeader.WithLineComment_NotReported;
const SRC =
  'unit t;'#13#10 +
  ''#13#10 +
  '// Diese Unit macht XYZ.'#13#10 +
  ''#13#10 +
  'interface'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingUnitHeader));
  finally F.Free; end;
end;

procedure TTestMissingUnitHeader.WithBlockComment_NotReported;
const SRC =
  'unit t;'#13#10 +
  ''#13#10 +
  '{ Diese Unit macht XYZ }'#13#10 +
  ''#13#10 +
  'interface'#13#10 +
  'implementation end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingUnitHeader));
  finally F.Free; end;
end;

procedure TTestMissingUnitHeader.Finding_KindAndSeverity;
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'implementation end.';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkMissingUnitHeader then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkMissingUnitHeader finding expected');
    Assert.AreEqual(lsHint, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestMissingUnitHeader.UnitInTestsDir_NotReported;
// Gate-Probe mit echter Datei unter einem 'tests'-Segment. AContext =
// nil -> Scanwurzel '' -> dokumentiertes Alt-Verhalten (Segmente im
// GANZEN Pfad zaehlen) - genau dadurch ist das Gate hier testbar.
var
  Dir, Pfad : string;
  SL  : TStringList;
  F   : TObjectList<TLeakFinding>;
  Root: TAstNode;
  P   : TParser2;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'sca143_gate' + PathDelim + 'tests');
  ForceDirectories(Dir);
  Pfad := TPath.Combine(Dir, 'kopflos_a.pas');
  SL := TStringList.Create;
  try
    SL.Text := 'unit kopflos_a;'#13#10'interface'#13#10'implementation'#13#10'end.';
    SL.SaveToFile(Pfad, TEncoding.UTF8);
  finally SL.Free; end;
  F := TObjectList<TLeakFinding>.Create(True);
  P := TParser2.Create;
  try
    Root := P.ParseFile(Pfad);
    try
      TMissingUnitHeaderDetector.AnalyzeUnit(Root, Pfad, F);
      Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkMissingUnitHeader),
        'Testpfad-Segment /tests/ wird uebersprungen');
    finally Root.Free; end;
  finally P.Free; F.Free; end;
end;

procedure TTestMissingUnitHeader.UnitInSrcDir_StillReported;
// GEGENPROBE: identischer Inhalt unter /src/ meldet weiter - das Gate
// greift nur an den tplFixtureDir-Segmenten.
var
  Dir, Pfad : string;
  SL  : TStringList;
  F   : TObjectList<TLeakFinding>;
  Root: TAstNode;
  P   : TParser2;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'sca143_gate' + PathDelim + 'src');
  ForceDirectories(Dir);
  Pfad := TPath.Combine(Dir, 'kopflos_b.pas');
  SL := TStringList.Create;
  try
    SL.Text := 'unit kopflos_b;'#13#10'interface'#13#10'implementation'#13#10'end.';
    SL.SaveToFile(Pfad, TEncoding.UTF8);
  finally SL.Free; end;
  F := TObjectList<TLeakFinding>.Create(True);
  P := TParser2.Create;
  try
    Root := P.ParseFile(Pfad);
    try
      TMissingUnitHeaderDetector.AnalyzeUnit(Root, Pfad, F);
      Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkMissingUnitHeader),
        'ausserhalb der Testsegmente meldet SCA143 weiter');
    finally Root.Free; end;
  finally P.Free; F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestMissingUnitHeader);

end.
