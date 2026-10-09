unit uTestHardcodedIpInConfig;

// Tests fuer SCA201 HardcodedIpInConfig und den Konfigurations-Durchlauf
// (Konzept_HardcodedIp 5.2): der Detektor selbst, die Engine-Wege (die
// .ini laeuft NIE als Pascal), die ';'/'#'-Marker in uSuppression und die
// Dateisammlung in TStaticFiles.
//
// KEIN ssRecursive: der rekursive Pfad ist im residenten Testprozess tabu
// (uTestEngineApi, Unit-Kopf). Die Sammlung wird ueber TryGetAllPasFiles
// direkt geprueft, die Engine ueber ssSingleFile, ssFileList und ssProject.
// (Review 2026-10-09: ein ssRecursive-Test war hier hineingeraten - ersetzt
// durch denselben Fall ueber ssFileList.)

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12, uEngineApi;

type
  [TestFixture]
  TTestHardcodedIpInConfig = class
  private
    FDir : string;
    function WriteFile(const ARelPath, AText: string): string;
    function Run(AScope: TScanScope; const APath: string;
      const AFiles: TArray<string>;
      const AProjectRoot: string = ''): TObjectList<TLeakFinding>;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    // ---- Detektor ----
    [Test] procedure Detector_ValueReported;
    [Test] procedure Detector_CommentsProseVersionLoopback_NoFinding;
    [Test] procedure Detector_TestDirectory_NoFinding;
    // ---- Engine ----
    [Test] procedure Engine_SingleIni_OnlyConfigFinding;
    [Test] procedure Engine_LineMarker_Suppresses;
    [Test] procedure Engine_HashFileMarker_Suppresses;
    [Test] procedure Engine_UnusedMarker_ReportsUnusedSuppression;
    [Test] procedure Engine_PascalMarkerInIni_NoEffect;
    [Test] procedure Engine_MixedFileList_PascalFindingsUnchanged;
    [Test] procedure Engine_Project_CollectsIniBelowRoot;
    [Test] procedure Engine_FileList_TestDirBesideUnitTree_NoFinding;
    [Test] procedure Engine_SingleIniProjectRoot_AnchorsTestGate;
    // ---- Sammlung, Marker-Text ----
    [Test] procedure StaticFiles_ConfigListSeparated;
    [Test] procedure StaticFiles_PlatformNameAboveRoot_Kept;
    [Test] procedure MarkerLineFor_IniUsesSemicolon;
    [Test] procedure ClaudePrompt_IniFinding_SuggestsSemicolonMarker;
  end;

implementation

uses
  System.IOUtils,
  uStaticFiles, uSuppression, uHardcodedIpInConfig, uClaudePrompt, uFixHint;

const
  INI_HEAD = '[Database]'#13#10;
  INI_SERVER = 'Server=10.20.30.40';
  MSG_SERVER = 'IP address ''10.20.30.40'' (private, RFC 1918) in [Database] ' +
    'Server - an environment-specific address in a versioned configuration ' +
    'file; prefer a host name or a per-environment setting';
  // Eine Unit mit einem sicheren SCA200-Fund (fuer den Listen-Vergleich).
  UNIT_SRC =
    'unit Unit1;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Run;'#13#10 +
    'begin'#13#10 +
    '  Host := ''10.9.8.7'';'#13#10 +
    'end;'#13#10 +
    'end.';

procedure TTestHardcodedIpInConfig.Setup;
begin
  uSCAConsts.ResetEngineConfigDefaults;
  FDir := TPath.Combine(TPath.GetTempPath, 'sca_ini_' + TGuid.NewGuid.ToString);
  TDirectory.CreateDirectory(FDir);
end;

procedure TTestHardcodedIpInConfig.TearDown;
begin
  uSCAConsts.ResetEngineConfigDefaults;
  if (FDir <> '') and TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

function TTestHardcodedIpInConfig.WriteFile(const ARelPath, AText: string): string;
begin
  Result := TPath.Combine(FDir, ARelPath);
  TDirectory.CreateDirectory(ExtractFilePath(Result));
  TFile.WriteAllText(Result, AText, TEncoding.UTF8);
end;

function TTestHardcodedIpInConfig.Run(AScope: TScanScope; const APath: string;
  const AFiles: TArray<string>; const AProjectRoot: string): TObjectList<TLeakFinding>;
var
  Req : TScanRequest;
  Ses : TAnalysisSession;
  Res : TScanResult;
begin
  Req := TScanRequest.Init;
  Req.Scope := AScope;
  Req.Path  := APath;
  Req.Files := AFiles;
  Req.SingleFileProjectRoot := AProjectRoot;
  Ses := TAnalysisSession.Create;
  try
    Res := Ses.Run(Req);
    try
      Result := Res.ReleaseFindings;
    finally
      Res.Free;
    end;
  finally
    Ses.Free;
  end;
end;

function CountKind(F: TObjectList<TLeakFinding>; K: TFindingKind): Integer;
var
  X : TLeakFinding;
begin
  Result := 0;
  for X in F do
    if X.Kind = K then Inc(Result);
end;

{ ---- Detektor ---- }

procedure TTestHardcodedIpInConfig.Detector_ValueReported;
var
  L   : TStringList;
  Res : TObjectList<TLeakFinding>;
begin
  L := TStringList.Create;
  Res := TObjectList<TLeakFinding>.Create(True);
  try
    L.Text := INI_HEAD + INI_SERVER;
    THardcodedIpInConfigDetector.AnalyzeFile(TPath.Combine(FDir, 'App.ini'), L, Res);
    Assert.AreEqual<Integer>(1, Res.Count);
    Assert.AreEqual<Integer>(Ord(fkHardcodedIpInConfig), Ord(Res[0].Kind));
    Assert.AreEqual('2', Res[0].LineNumber);
    Assert.AreEqual<Integer>(Ord(lsHint), Ord(Res[0].Severity));
    Assert.AreEqual(MSG_SERVER, Res[0].MissingVar);
  finally
    Res.Free;
    L.Free;
  end;
end;

procedure TTestHardcodedIpInConfig.Detector_CommentsProseVersionLoopback_NoFinding;
var
  L   : TStringList;
  Res : TObjectList<TLeakFinding>;
begin
  L := TStringList.Create;
  Res := TObjectList<TLeakFinding>.Create(True);
  try
    L.Text :=
      '; Server=10.0.0.1'#13#10 +
      '# Proxy=10.0.0.2'#13#10 +
      '[Help]'#13#10 +
      'description=Returns 10.1.2.3 for the lookup'#13#10 +
      'FileVersion=1.2.3.4'#13#10 +
      'Host=127.0.0.1'#13#10 +
      'Doc=192.0.2.10';
    THardcodedIpInConfigDetector.AnalyzeFile(TPath.Combine(FDir, 'App.ini'), L, Res);
    Assert.AreEqual<Integer>(0, Res.Count);
  finally
    Res.Free;
    L.Free;
  end;
end;

procedure TTestHardcodedIpInConfig.Detector_TestDirectory_NoFinding;
var
  L   : TStringList;
  Res : TObjectList<TLeakFinding>;
begin
  L := TStringList.Create;
  Res := TObjectList<TLeakFinding>.Create(True);
  try
    L.Text := INI_HEAD + INI_SERVER;
    THardcodedIpInConfigDetector.AnalyzeFile(
      TPath.Combine(FDir, 'tests\App.ini'), L, Res);
    Assert.AreEqual<Integer>(0, Res.Count);
  finally
    Res.Free;
    L.Free;
  end;
end;

{ ---- Engine ---- }

procedure TTestHardcodedIpInConfig.Engine_SingleIni_OnlyConfigFinding;
var
  Ini : string;
  F   : TObjectList<TLeakFinding>;
begin
  // Pascal-artiger Inhalt: liefe die .ini durch die Pascal-Pipeline, kaemen
  // Lese-/Stil-Funde (TodoComment, FileReadError ...).
  Ini := WriteFile('App.ini', INI_HEAD + INI_SERVER + #13#10 +
    'Text=begin x := 1; end;'#13#10'Comment=TODO later'#13#10);
  F := Run(ssSingleFile, Ini, nil);
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkHardcodedIpInConfig), 'SCA201');
    Assert.AreEqual<Integer>(1, F.Count, 'nichts sonst');
    Assert.AreEqual(MSG_SERVER, F[0].MissingVar);
  finally
    F.Free;
  end;
end;

procedure TTestHardcodedIpInConfig.Engine_LineMarker_Suppresses;
var
  Ini : string;
  F   : TObjectList<TLeakFinding>;
begin
  Ini := WriteFile('App.ini', INI_HEAD +
    '; noinspection HardcodedIpInConfig'#13#10 +
    '; Kommentar dazwischen zaehlt nicht als Ziel'#13#10 +
    INI_SERVER + #13#10);
  F := Run(ssSingleFile, Ini, nil);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkHardcodedIpInConfig), 'unterdrueckt');
    Assert.AreEqual<Integer>(0, CountKind(F, fkUnusedSuppression), 'Marker verbraucht');
  finally
    F.Free;
  end;
end;

procedure TTestHardcodedIpInConfig.Engine_HashFileMarker_Suppresses;
var
  Ini : string;
  F   : TObjectList<TLeakFinding>;
begin
  Ini := WriteFile('App.ini', '# noinspection-file HardcodedIpInConfig'#13#10 +
    INI_HEAD + INI_SERVER + #13#10 + 'Backup=10.20.30.41'#13#10);
  F := Run(ssSingleFile, Ini, nil);
  try
    Assert.AreEqual<Integer>(0, CountKind(F, fkHardcodedIpInConfig));
  finally
    F.Free;
  end;
end;

procedure TTestHardcodedIpInConfig.Engine_UnusedMarker_ReportsUnusedSuppression;
var
  Ini : string;
  F   : TObjectList<TLeakFinding>;
begin
  Ini := WriteFile('App.ini', INI_HEAD +
    '; noinspection HardcodedIpInConfig'#13#10 + 'Name=sales'#13#10);
  F := Run(ssSingleFile, Ini, nil);
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkUnusedSuppression));
  finally
    F.Free;
  end;
end;

procedure TTestHardcodedIpInConfig.Engine_PascalMarkerInIni_NoEffect;
var
  Ini : string;
  F   : TObjectList<TLeakFinding>;
begin
  // In einer .ini ist '//' kein Kommentar - der Marker wirkt nicht.
  Ini := WriteFile('App.ini', INI_HEAD +
    '// noinspection HardcodedIpInConfig'#13#10 + INI_SERVER + #13#10);
  F := Run(ssSingleFile, Ini, nil);
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkHardcodedIpInConfig));
  finally
    F.Free;
  end;
end;

// Kind/Zeile aller Funde einer Datei, sortiert.
function SignatureOf(F: TObjectList<TLeakFinding>; const AFile: string): string;
var
  SL : TStringList;
  X  : TLeakFinding;
begin
  SL := TStringList.Create;
  try
    for X in F do
      if SameText(X.FileName, AFile) then
        SL.Add(Format('%d:%s', [Ord(X.Kind), X.LineNumber]));
    SL.Sort;
    Result := SL.CommaText;
  finally
    SL.Free;
  end;
end;

procedure TTestHardcodedIpInConfig.Engine_MixedFileList_PascalFindingsUnchanged;
var
  Pas, Ini      : string;
  Alone, Mixed  : TObjectList<TLeakFinding>;
  X             : TLeakFinding;
begin
  Pas := WriteFile('Unit1.pas', UNIT_SRC);
  Ini := WriteFile('App.ini', INI_HEAD + INI_SERVER + #13#10);
  Alone := Run(ssFileList, FDir, [Pas]);
  try
    Mixed := Run(ssFileList, FDir, [Pas, Ini]);
    try
      Assert.AreEqual<Integer>(1, CountKind(Alone, fkHardcodedIpAddress), 'SCA200 in Unit1');
      Assert.AreEqual(SignatureOf(Alone, Pas), SignatureOf(Mixed, Pas),
        'die .ini aendert die Pascal-Funde nicht');
      for X in Mixed do
        if SameText(X.FileName, Ini) then
          Assert.AreEqual<Integer>(Ord(fkHardcodedIpInConfig), Ord(X.Kind),
            'in der .ini nur SCA201: ' + X.MissingVar);
      Assert.AreEqual<Integer>(1, CountKind(Mixed, fkHardcodedIpInConfig));
    finally
      Mixed.Free;
    end;
  finally
    Alone.Free;
  end;
end;

procedure TTestHardcodedIpInConfig.Engine_Project_CollectsIniBelowRoot;
const
  DPROJ_XML =
    '<?xml version="1.0" encoding="utf-8"?>'#13#10 +
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '  <ItemGroup>'#13#10 +
    '    <DCCReference Include="Unit1.pas"/>'#13#10 +
    '  </ItemGroup>'#13#10 +
    '</Project>'#13#10;
var
  Dproj, Ini : string;
  F          : TObjectList<TLeakFinding>;
begin
  WriteFile('Unit1.pas', UNIT_SRC);
  Ini := WriteFile('App.ini', INI_HEAD + INI_SERVER + #13#10);
  // Deploy-Kopie und die Analyser-Einstellungen werden nicht gelesen.
  WriteFile('Win32\Debug\App.ini', INI_HEAD + INI_SERVER + #13#10);
  WriteFile('analyser.ini', '[Sonar]'#13#10'HostUrl=http://10.20.30.40:9000'#13#10);
  Dproj := WriteFile('Fixture.dproj', DPROJ_XML);
  F := Run(ssProject, Dproj, nil);
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkHardcodedIpInConfig), 'nur App.ini');
    Assert.AreEqual<Integer>(1, CountKind(F, fkHardcodedIpAddress), 'Unit1 unveraendert');
  finally
    F.Free;
  end;
end;

procedure TTestHardcodedIpInConfig.Engine_FileList_TestDirBesideUnitTree_NoFinding;
var
  Pas, Tst, Cfg : string;
  F   : TObjectList<TLeakFinding>;
  X   : TLeakFinding;
begin
  // Die Unit liegt nur unter src - ihre Wurzel (der Anker der Pascal-
  // Gates) enthaelt tests\ nicht. Der Konfigurations-Durchlauf
  // verankert das Testpfad-Gate trotzdem darueber (ConfigAnchor).
  Pas := WriteFile('src\Unit1.pas', UNIT_SRC);
  Tst := WriteFile('tests\App.ini', INI_HEAD + INI_SERVER + #13#10);
  Cfg := WriteFile('config\App.ini', INI_HEAD + INI_SERVER + #13#10);
  F := Run(ssFileList, FDir, [Pas, Tst, Cfg]);
  try
    Assert.AreEqual<Integer>(1, CountKind(F, fkHardcodedIpInConfig), 'nur config\App.ini');
    for X in F do
      if X.Kind = fkHardcodedIpInConfig then
        Assert.IsTrue(SameText(X.FileName, Cfg), X.FileName);
  finally
    F.Free;
  end;
end;

procedure TTestHardcodedIpInConfig.Engine_SingleIniProjectRoot_AnchorsTestGate;
var
  Root, Ini       : string;
  Alone, WithRoot : TObjectList<TLeakFinding>;
begin
  // Projekt unter einem Ordner 'fixtures' (Kundenablage): ohne Projekt-
  // wurzel sieht das Testpfad-Gate den ganzen Pfad und schweigt; mit der
  // Wurzel (IDE "aktuelle Datei", Watch-Modus) zaehlt nur der Teil
  // darunter - wie bei den Units ueber die Index-Liste.
  Root := TPath.Combine(FDir, 'fixtures\Customer');
  Ini := WriteFile('fixtures\Customer\App.ini', INI_HEAD + INI_SERVER + #13#10);
  Alone := Run(ssSingleFile, Ini, nil);
  try
    WithRoot := Run(ssSingleFile, Ini, nil, Root);
    try
      Assert.AreEqual<Integer>(0, CountKind(Alone, fkHardcodedIpInConfig), 'voller Pfad: fixtures');
      Assert.AreEqual<Integer>(1, CountKind(WithRoot, fkHardcodedIpInConfig), 'Anker Projektwurzel');
    finally
      WithRoot.Free;
    end;
  finally
    Alone.Free;
  end;
end;

{ ---- Sammlung, Marker-Text ---- }

procedure TTestHardcodedIpInConfig.StaticFiles_ConfigListSeparated;
var
  Pas, Cfg, PasOnly : TStringList;
  Err               : string;
begin
  WriteFile('Unit1.pas', UNIT_SRC);
  WriteFile('App.ini', INI_SERVER);
  WriteFile('sub\Second.ini', INI_SERVER);
  WriteFile('analyser.ini', INI_SERVER);
  WriteFile('Win64\Release\App.ini', INI_SERVER);
  WriteFile('notes.txt', INI_SERVER);
  Cfg := TStringList.Create;
  Pas := nil;
  PasOnly := nil;
  try
    Pas := TStaticFiles.TryGetAllPasFiles(FDir, Err, nil, nil, Cfg);
    PasOnly := TStaticFiles.TryGetAllPasFiles(FDir, Err);
    Pas.Sort;
    PasOnly.Sort;
    Cfg.Sort;
    Assert.AreEqual(PasOnly.Text, Pas.Text, 'Pascal-Liste unveraendert');
    Assert.AreEqual<Integer>(1, Pas.Count, 'nur Unit1.pas');
    Assert.AreEqual<Integer>(2, Cfg.Count, 'App.ini + sub\Second.ini: ' + Cfg.CommaText);
    Assert.IsTrue(SameText(ExtractFileName(Cfg[0]), 'App.ini'), Cfg[0]);
    Assert.IsTrue(SameText(ExtractFileName(Cfg[1]), 'Second.ini'), Cfg[1]);
  finally
    PasOnly.Free;
    Pas.Free;
    Cfg.Free;
  end;
  Assert.IsTrue(TConfigFiles.IsConfigFile('C:\x\App.INI'));
  Assert.IsFalse(TConfigFiles.IsConfigFile('C:\x\analyser.ini'));
  Assert.IsFalse(TConfigFiles.IsConfigFile('C:\x\Unit1.pas'));
  Assert.IsTrue(TConfigFiles.IsInPlatformOutputDir('C:\p\Win32\Debug\App.ini'));
  Assert.IsFalse(TConfigFiles.IsInPlatformOutputDir('C:\p\config\App.ini'));
end;

procedure TTestHardcodedIpInConfig.StaticFiles_PlatformNameAboveRoot_Kept;
var
  Root, Err : string;
  Pas, Cfg  : TStringList;
begin
  // Ein Projekt UNTER einem Ordner 'Android' (Ablage nach Plattform): nur
  // Ordner unterhalb der Scanwurzel zaehlen als Ausgabeordner.
  WriteFile('Android\Kasse\App.ini', INI_SERVER);
  WriteFile('Android\Kasse\Win64\Release\App.ini', INI_SERVER);
  Root := TPath.Combine(FDir, 'Android\Kasse');
  Cfg := TStringList.Create;
  Pas := nil;
  try
    Pas := TStaticFiles.TryGetAllPasFiles(Root, Err, nil, nil, Cfg);
    Assert.AreEqual<Integer>(1, Cfg.Count, Cfg.CommaText);
    Assert.IsTrue(SameText(Cfg[0], TPath.Combine(Root, 'App.ini')), Cfg[0]);
  finally
    Pas.Free;
    Cfg.Free;
  end;
  Assert.IsFalse(TConfigFiles.IsInPlatformOutputDir('C:\Android\Kasse\App.ini', 0));
  Assert.IsTrue(TConfigFiles.IsInPlatformOutputDir(
    'C:\Android\Kasse\Win64\Release\App.ini', 2));
end;

procedure TTestHardcodedIpInConfig.MarkerLineFor_IniUsesSemicolon;
begin
  Assert.AreEqual('; noinspection HardcodedIpInConfig',
    TSuppression.MarkerLineFor('C:\p\App.ini', fkHardcodedIpInConfig));
  Assert.AreEqual('// noinspection HardcodedIpAddress',
    TSuppression.MarkerLineFor('C:\p\Unit1.pas', fkHardcodedIpAddress));
  // Regelkarten ohne Datei (Workbench, Regel-Info): Dateiart der Regel
  Assert.AreEqual('; noinspection HardcodedIpInConfig',
    TSuppression.MarkerTextFor(fkHardcodedIpInConfig));
  Assert.AreEqual('// noinspection HardcodedIpAddress',
    TSuppression.MarkerTextFor(fkHardcodedIpAddress));
end;

procedure TTestHardcodedIpInConfig.ClaudePrompt_IniFinding_SuggestsSemicolonMarker;
var
  Ini    : string;
  F      : TLeakFinding;
  Prompt : string;
begin
  // Sprachunabhaengig: der Marker steht in jeder Uebersetzung woertlich.
  Ini := WriteFile('App.ini', INI_HEAD + INI_SERVER + #13#10);
  F := TLeakFinding.New(Ini, '', 2, MSG_SERVER, fkHardcodedIpInConfig);
  try
    Prompt := TClaudePrompt.Build(F, Default(TFixHint));
  finally
    F.Free;
  end;
  Assert.IsTrue(Pos('`; noinspection HardcodedIpInConfig`', Prompt) > 0, Prompt);
  Assert.IsTrue(Pos('// noinspection', Prompt) = 0, Prompt);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestHardcodedIpInConfig);

end.
