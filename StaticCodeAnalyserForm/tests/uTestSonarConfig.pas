unit uTestSonarConfig;

// Tests fuer uSonarConfig - Resolver, DPAPI-Roundtrip, Project-Properties-
// Parser, URL-Sanitization. KEINE Tests die einen echten Sonar-Server
// brauchen (siehe uTestSonarHealthCheck mit Mock-HTTP-Server).

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.IOUtils,
  {$IFDEF MSWINDOWS}Winapi.Windows,{$ENDIF}     // SetEnvironmentVariable
  uSonarConfig;

type
  [TestFixture]
  TTestSonarConfig = class
  private
    FTempIni     : string;
    FTempProject : string;
    procedure WriteIni(const Sections: array of string);
    procedure WriteProjectProps(const Content: string);
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;

    // ---- Resolver-Reihenfolge ----
    [Test] procedure CliBeatsEnv;
    [Test] procedure EnvBeatsProjectProps;
    [Test] procedure ProjectPropsBeatsIni;
    [Test] procedure EmptyCliFallsThrough;
    [Test] procedure MissingFieldsReportsAll;

    // ---- INI / Project-Properties Parsing ----
    [Test] procedure IniSonarSectionReadsAllFields;
    [Test] procedure ProjectPropsIgnoresComments;
    [Test] procedure ProjectPropsBothEqualsAndColon;
    [Test] procedure ProjectPropsDoesNotReadToken;
    [Test] procedure UrlSanitizationStripsTrailingSlash;

    // ---- DPAPI Token-Roundtrip ----
    {$IFDEF MSWINDOWS}
    [Test] procedure DpapiTokenRoundtrip;
    [Test] procedure LoadTokenMissingEntryReturnsEmpty;
    {$ENDIF}

    // ---- Diagnose (SourceXxx-Felder) ----
    [Test] procedure SourceTrackingPopulated;
  end;

implementation

uses
  System.IniFiles;

{ ---- Helpers ---- }

procedure TTestSonarConfig.WriteIni(const Sections: array of string);
var
  Lines : TStringList;
  S     : string;
begin
  Lines := TStringList.Create;
  try
    for S in Sections do Lines.Add(S);
    Lines.SaveToFile(FTempIni, TEncoding.UTF8);
  finally
    Lines.Free;
  end;
end;

procedure TTestSonarConfig.WriteProjectProps(const Content: string);
begin
  TFile.WriteAllText(
    IncludeTrailingPathDelimiter(FTempProject) + 'sonar-project.properties',
    Content, TEncoding.UTF8);
end;

procedure TTestSonarConfig.Setup;
var
  Tmp : string;
begin
  Tmp := TPath.Combine(TPath.GetTempPath, 'sca_sonar_test_' +
    TGuid.NewGuid.ToString.Replace('{','').Replace('}',''));
  ForceDirectories(Tmp);
  FTempProject := Tmp;
  FTempIni := TPath.Combine(Tmp, 'analyser.ini');
end;

procedure TTestSonarConfig.TearDown;
begin
  if (FTempProject <> '') and TDirectory.Exists(FTempProject) then
    TDirectory.Delete(FTempProject, True);
end;

{ ---- Resolver-Reihenfolge ---- }

procedure TTestSonarConfig.CliBeatsEnv;
var
  Cli : TSonarCliOverrides;
  Cfg : TSonarConfig;
begin
  // Setup: Env haette anderen Wert
  Cli := Default(TSonarCliOverrides);
  Cli.HostUrl := 'https://from-cli';
  Cli.Token := 'tok-cli';
  Cli.ProjectKey := 'proj-cli';
  // Env-Vars setzen (werden im Test-Prozess gesehen)
  SetEnvironmentVariable('SONAR_HOST_URL', 'https://from-env');
  SetEnvironmentVariable('SONAR_TOKEN', 'tok-env');
  SetEnvironmentVariable('SONAR_PROJECT_KEY', 'proj-env');
  try
    Cfg := TSonarConfigResolver.Resolve(Cli, '', '');
    Assert.AreEqual('https://from-cli', Cfg.HostUrl);
    Assert.AreEqual('tok-cli', Cfg.Token);
    Assert.AreEqual('proj-cli', Cfg.ProjectKey);
  finally
    SetEnvironmentVariable('SONAR_HOST_URL', '');
    SetEnvironmentVariable('SONAR_TOKEN', '');
    SetEnvironmentVariable('SONAR_PROJECT_KEY', '');
  end;
end;

procedure TTestSonarConfig.EnvBeatsProjectProps;
var
  Cli : TSonarCliOverrides;
  Cfg : TSonarConfig;
begin
  Cli := Default(TSonarCliOverrides);
  WriteProjectProps(
    'sonar.host.url=https://from-props' + sLineBreak +
    'sonar.projectKey=proj-props');
  SetEnvironmentVariable('SONAR_HOST_URL', 'https://from-env');
  try
    Cfg := TSonarConfigResolver.Resolve(Cli, '', FTempProject);
    Assert.AreEqual('https://from-env', Cfg.HostUrl,
      'env should beat project-props for HostUrl');
    Assert.AreEqual('proj-props', Cfg.ProjectKey,
      'project-props fills the rest');
  finally
    SetEnvironmentVariable('SONAR_HOST_URL', '');
  end;
end;

procedure TTestSonarConfig.ProjectPropsBeatsIni;
var
  Cli : TSonarCliOverrides;
  Cfg : TSonarConfig;
begin
  Cli := Default(TSonarCliOverrides);
  WriteProjectProps('sonar.host.url=https://from-props');
  WriteIni(['[Sonar]', 'HostUrl=https://from-ini']);
  Cfg := TSonarConfigResolver.Resolve(Cli, FTempIni, FTempProject);
  Assert.AreEqual('https://from-props', Cfg.HostUrl,
    'project-props should beat INI');
end;

procedure TTestSonarConfig.EmptyCliFallsThrough;
var
  Cli : TSonarCliOverrides;
  Cfg : TSonarConfig;
begin
  Cli := Default(TSonarCliOverrides);
  WriteIni(['[Sonar]',
            'HostUrl=https://only-ini',
            'ProjectKey=only-ini-proj']);
  Cfg := TSonarConfigResolver.Resolve(Cli, FTempIni, '');
  Assert.AreEqual('https://only-ini', Cfg.HostUrl);
  Assert.AreEqual('only-ini-proj', Cfg.ProjectKey);
end;

procedure TTestSonarConfig.MissingFieldsReportsAll;
var
  Cfg : TSonarConfig;
begin
  Cfg := Default(TSonarConfig);
  Assert.IsFalse(Cfg.IsValid);
  Assert.Contains(Cfg.MissingFields, 'host');
  Assert.Contains(Cfg.MissingFields, 'token');
  Assert.Contains(Cfg.MissingFields, 'projectKey');
end;

{ ---- INI / Project-Properties Parsing ---- }

procedure TTestSonarConfig.IniSonarSectionReadsAllFields;
var
  Cfg : TSonarConfig;
  Cli : TSonarCliOverrides;
begin
  Cli := Default(TSonarCliOverrides);
  WriteIni([
    '[Sonar]',
    'HostUrl=https://full-ini',
    'ProjectKey=full-ini-proj',
    'Organization=acme',
    'Branch=feature/x',
    'SourceMapping=C:\src=>/work'
  ]);
  Cfg := TSonarConfigResolver.Resolve(Cli, FTempIni, '');
  Assert.AreEqual('https://full-ini',   Cfg.HostUrl);
  Assert.AreEqual('full-ini-proj',      Cfg.ProjectKey);
  Assert.AreEqual('acme',               Cfg.Organization);
  Assert.AreEqual('feature/x',          Cfg.Branch);
  Assert.AreEqual('C:\src=>/work',      Cfg.SourceMapping);
end;

procedure TTestSonarConfig.ProjectPropsIgnoresComments;
var
  Cfg : TSonarConfig;
  Cli : TSonarCliOverrides;
begin
  Cli := Default(TSonarCliOverrides);
  WriteProjectProps(
    '# this is a comment' + sLineBreak +
    '! also a comment' + sLineBreak +
    '   ' + sLineBreak +
    'sonar.host.url=https://commented-url');
  Cfg := TSonarConfigResolver.Resolve(Cli, '', FTempProject);
  Assert.AreEqual('https://commented-url', Cfg.HostUrl);
end;

procedure TTestSonarConfig.ProjectPropsBothEqualsAndColon;
var
  Cfg : TSonarConfig;
  Cli : TSonarCliOverrides;
begin
  Cli := Default(TSonarCliOverrides);
  WriteProjectProps(
    'sonar.host.url:https://colon-syntax' + sLineBreak +
    'sonar.projectKey=mixed-syntax');
  Cfg := TSonarConfigResolver.Resolve(Cli, '', FTempProject);
  Assert.AreEqual('https://colon-syntax', Cfg.HostUrl);
  Assert.AreEqual('mixed-syntax',         Cfg.ProjectKey);
end;

procedure TTestSonarConfig.ProjectPropsDoesNotReadToken;
// Tokens gehoeren NICHT in sonar-project.properties (commited in VCS).
// Selbst wenn jemand das eintraegt, ignoriert der Parser den Wert.
var
  Cfg : TSonarConfig;
  Cli : TSonarCliOverrides;
begin
  Cli := Default(TSonarCliOverrides);
  WriteProjectProps(
    'sonar.host.url=https://x' + sLineBreak +
    'sonar.token=secret-leaked-token');
  Cfg := TSonarConfigResolver.Resolve(Cli, '', FTempProject);
  Assert.AreEqual('', Cfg.Token,
    'Token from sonar-project.properties must be ignored');
end;

procedure TTestSonarConfig.UrlSanitizationStripsTrailingSlash;
var
  Cli : TSonarCliOverrides;
  Cfg : TSonarConfig;
begin
  Cli := Default(TSonarCliOverrides);
  Cli.HostUrl := 'https://x.example.com:9000///';
  Cli.Token := 't'; Cli.ProjectKey := 'p';
  Cfg := TSonarConfigResolver.Resolve(Cli, '', '');
  Assert.AreEqual('https://x.example.com:9000', Cfg.HostUrl);
end;

{ ---- DPAPI Roundtrip ---- }

{$IFDEF MSWINDOWS}
procedure TTestSonarConfig.DpapiTokenRoundtrip;
var
  Loaded : string;
begin
  TSonarConfigResolver.StoreToken(FTempIni, 'test-key', 'super-secret-42');
  Loaded := TSonarConfigResolver.LoadToken(FTempIni, 'test-key');
  Assert.AreEqual('super-secret-42', Loaded);
end;

procedure TTestSonarConfig.LoadTokenMissingEntryReturnsEmpty;
var
  Loaded : string;
begin
  WriteIni(['[Sonar]', 'HostUrl=x']);
  Loaded := TSonarConfigResolver.LoadToken(FTempIni, 'does-not-exist');
  Assert.AreEqual('', Loaded);
end;
{$ENDIF}

{ ---- Source-Tracking ---- }

procedure TTestSonarConfig.SourceTrackingPopulated;
var
  Cli : TSonarCliOverrides;
  Cfg : TSonarConfig;
begin
  Cli := Default(TSonarCliOverrides);
  Cli.HostUrl := 'https://cli-url';
  WriteIni(['[Sonar]', 'ProjectKey=ini-proj']);
  SetEnvironmentVariable('SONAR_TOKEN', 'env-token');
  try
    Cfg := TSonarConfigResolver.Resolve(Cli, FTempIni, '');
    Assert.Contains(Cfg.SourceHostUrl,    'CLI');
    Assert.Contains(Cfg.SourceToken,      'env');
    Assert.Contains(Cfg.SourceProjectKey, 'analyser.ini');
  finally
    SetEnvironmentVariable('SONAR_TOKEN', '');
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSonarConfig);

end.
