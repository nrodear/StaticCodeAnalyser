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
    [Test] procedure HostFromProjectPropsIsIgnored;
    [Test] procedure HostFromProjectPropsIgnoredWithoutOwnConfig;
    [Test] procedure EmptyCliFallsThrough;
    [Test] procedure MissingFieldsReportsAll;

    // ---- INI / Project-Properties Parsing ----
    [Test] procedure IniSonarSectionReadsAllFields;
    [Test] procedure ConfigPathFromRecordIsUsedAsFallback;
    [Test] procedure ProjectPropsIgnoresComments;
    [Test] procedure ProjectPropsBothEqualsAndColon;
    [Test] procedure ProjectPropsDoesNotReadToken;
    [Test] procedure UrlSanitizationStripsTrailingSlash;

    // ---- Diagnose (SourceXxx-Felder) ----
    [Test] procedure SourceTrackingPopulated;
    // Token-Speicherung (DPAPI, 'PT:'-Klartext) liegt in
    // uTestSonarTokenStorage - diese Fixture stand sonst bei 23 Methoden
    // im eigenen GodClass-Detektor.
  end;

implementation

uses
  System.IniFiles;

{ ---- Helpers ---- }

procedure TTestSonarConfig.WriteIni(const Sections: array of string);
// ASCII-Encoding statt UTF-8: vermeidet BOM-Prefix. TMemIniFile vertraegt
// das BOM zwar, aber ASCII bleibt portabel und matched genau das was
// echte Win32-INI-Tools (Notepad classic, INI-Editor) produzieren.
var
  Lines : TStringList;
  S     : string;
begin
  Lines := TStringList.Create;
  try
    for S in Sections do Lines.Add(S);
    Lines.SaveToFile(FTempIni, TEncoding.ASCII);
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
// FTempIni zeigt auf einen Pfad innerhalb des Test-Temp-Dirs - die Datei
// wird NICHT angelegt; WriteIni() macht das pro Test wenn der INI-Inhalt
// bewusst gesetzt wird.
//
// WICHTIG: Tests die Resolve aufrufen MUESSEN FTempIni (auch wenn leer)
// als AnalyserIniPath uebergeben, nicht ''. Sonst faellt Resolve auf
// DefaultIniPath = %APPDATA%\StaticCodeAnalyser\analyser.ini zurueck und
// liest die ECHTE User-INI inkl. DPAPI-Token - dann werden Tests instabil
// (Symptom: ProjectPropsDoesNotReadToken meldete einen echten squ_*-Token).
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
    Cfg := TSonarConfigResolver.Resolve(Cli, FTempIni, '');
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
// Anmerkung seit 2026-08-08: der Host kaeme aus der Repo-Datei ohnehin
// nicht mehr durch (s. HostFromProjectPropsIsIgnored). Die eigentliche
// Zusicherung dieses Tests ist deshalb die zweite: Env setzt den Host,
// und die Repo-Datei fuellt die uebrigen Felder auf.
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
    Cfg := TSonarConfigResolver.Resolve(Cli, FTempIni, FTempProject);
    Assert.AreEqual('https://from-env', Cfg.HostUrl,
      'env should beat project-props for HostUrl');
    Assert.AreEqual('proj-props', Cfg.ProjectKey,
      'project-props fills the rest');
  finally
    SetEnvironmentVariable('SONAR_HOST_URL', '');
  end;
end;

procedure TTestSonarConfig.ProjectPropsBeatsIni;
// Praezedenz fuer die Felder, die aus dem Repo kommen DUERFEN.
// Bis 2026-08-08 stand hier sonar.host.url und die Zusicherung
// 'project-props should beat INI' - genau das war die Luecke: eine
// Properties-Datei IM GESCANNTEN REPO konnte den Host des Nutzers
// ueberstimmen, waehrend der Token weiter aus dessen Env/INI kam. Der
// Host wird dort jetzt ignoriert (s. HostFromProjectPropsIsIgnored);
// fuer projectKey bleibt die Repo-Datei die naeherliegende Quelle.
var
  Cli : TSonarCliOverrides;
  Cfg : TSonarConfig;
begin
  Cli := Default(TSonarCliOverrides);
  WriteProjectProps('sonar.projectKey=key-from-props');
  WriteIni(['[Sonar]', 'ProjectKey=key-from-ini']);
  Cfg := TSonarConfigResolver.Resolve(Cli, FTempIni, FTempProject);
  Assert.AreEqual('key-from-props', Cfg.ProjectKey,
    'project-props should beat INI for projectKey');
end;

procedure TTestSonarConfig.HostFromProjectPropsIsIgnored;
// SICHERHEIT: sonar.host.url aus dem gescannten Repo darf den Host des
// Nutzers NICHT ueberstimmen - sonst geht dessen Token an einen
// fremdbestimmten Server (2026-08-08 mit Mitschnitt reproduziert).
// Dieselbe Begruendung, aus der sonar.token dort schon immer ignoriert
// wird. Der Wert bleibt zur Diagnose sichtbar.
var
  Cli : TSonarCliOverrides;
  Cfg : TSonarConfig;
begin
  Cli := Default(TSonarCliOverrides);
  WriteProjectProps('sonar.host.url=https://evil-from-props');
  WriteIni(['[Sonar]', 'HostUrl=https://trusted-from-ini']);
  Cfg := TSonarConfigResolver.Resolve(Cli, FTempIni, FTempProject);
  Assert.AreEqual('https://trusted-from-ini', Cfg.HostUrl,
    'die eigene Konfiguration gewinnt gegen die Repo-Datei');
  Assert.AreEqual('https://evil-from-props', Cfg.IgnoredRepoHost,
    'der ignorierte Repo-Host bleibt zur Diagnose sichtbar');
end;

procedure TTestSonarConfig.HostFromProjectPropsIgnoredWithoutOwnConfig;
// Auch ohne eigene Host-Konfiguration wird der Repo-Wert nicht
// uebernommen - sonst genuegte ein Klon plus SONAR_TOKEN, damit der
// Token an den vom Repo genannten Server geht.
var
  Cli : TSonarCliOverrides;
  Cfg : TSonarConfig;
begin
  Cli := Default(TSonarCliOverrides);
  WriteProjectProps('sonar.host.url=https://evil-from-props');
  WriteIni(['[Sonar]', 'ProjectKey=some-proj']);
  Cfg := TSonarConfigResolver.Resolve(Cli, FTempIni, FTempProject);
  Assert.AreEqual('', Cfg.HostUrl,
    'kein Host aus der Repo-Datei, auch wenn sonst keiner gesetzt ist');
  Assert.AreEqual('https://evil-from-props', Cfg.IgnoredRepoHost);
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
    'Branch=feature/x'
  ]);
  Cfg := TSonarConfigResolver.Resolve(Cli, FTempIni, '');
  Assert.AreEqual('https://full-ini',   Cfg.HostUrl);
  Assert.AreEqual('full-ini-proj',      Cfg.ProjectKey);
  Assert.AreEqual('acme',               Cfg.Organization);
  Assert.AreEqual('feature/x',          Cfg.Branch);
end;

procedure TTestSonarConfig.ConfigPathFromRecordIsUsedAsFallback;
// CLI.ConfigPath war gesetzt-aber-nie-gelesen: --sonar-config wirkte
// allein ueber den separaten Parameter. Ein Aufrufer, der nur den Record
// fuellt, wurde wortlos ignoriert.
var
  Cfg : TSonarConfig;
  Cli : TSonarCliOverrides;
begin
  Cli := Default(TSonarCliOverrides);
  Cli.ConfigPath := FTempIni;
  WriteIni(['[Sonar]', 'ProjectKey=from-record-path']);
  // AnalyserIniPath bewusst leer - nur der Record traegt den Pfad.
  Cfg := TSonarConfigResolver.Resolve(Cli, '', '');
  Assert.AreEqual('from-record-path', Cfg.ProjectKey);
end;

procedure TTestSonarConfig.ProjectPropsIgnoresComments;
// Prueft den PARSER (Kommentar- und Leerzeilen). Sonde ist projectKey -
// frueher stand hier sonar.host.url, der aber bewusst nicht mehr aus
// der Repo-Datei uebernommen wird und deshalb nichts mehr ueber den
// Parser aussagen wuerde.
var
  Cfg : TSonarConfig;
  Cli : TSonarCliOverrides;
begin
  Cli := Default(TSonarCliOverrides);
  WriteProjectProps(
    '# this is a comment' + sLineBreak +
    '! also a comment' + sLineBreak +
    '   ' + sLineBreak +
    'sonar.projectKey=commented-key');
  Cfg := TSonarConfigResolver.Resolve(Cli, FTempIni, FTempProject);
  Assert.AreEqual('commented-key', Cfg.ProjectKey);
end;

procedure TTestSonarConfig.ProjectPropsBothEqualsAndColon;
// Beide Trennzeichen der .properties-Syntax, ebenfalls an Feldern
// gesondet, die aus dem Repo gelesen werden duerfen.
var
  Cfg : TSonarConfig;
  Cli : TSonarCliOverrides;
begin
  Cli := Default(TSonarCliOverrides);
  WriteProjectProps(
    'sonar.projectKey:colon-syntax' + sLineBreak +
    'sonar.organization=mixed-syntax');
  Cfg := TSonarConfigResolver.Resolve(Cli, FTempIni, FTempProject);
  Assert.AreEqual('colon-syntax',  Cfg.ProjectKey);
  Assert.AreEqual('mixed-syntax',  Cfg.Organization);
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
  Cfg := TSonarConfigResolver.Resolve(Cli, FTempIni, FTempProject);
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
  Cfg := TSonarConfigResolver.Resolve(Cli, FTempIni, '');
  Assert.AreEqual('https://x.example.com:9000', Cfg.HostUrl);
end;

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
