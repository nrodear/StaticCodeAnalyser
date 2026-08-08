unit uTestSonarTokenStorage;

// Tests fuer die Token-Ablage in analyser.ini [SonarTokens]:
// DPAPI-Roundtrip (Windows) und der 'PT:'-Klartext-Fallback.
//
// Eigene Unit statt eines zweiten Fixtures in uTestSonarConfig: dort war
// die Klasse mit diesen Tests auf 23 Methoden gewachsen und schlug im
// eigenen GodClass-Detektor auf, ein zweites Fixture in derselben Datei
// haette ClassPerFile ausgeloest. Der Schnitt ist ohnehin sachlich - hier
// geht es um die Speicherung, dort um die Quellen-Reihenfolge.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.IOUtils,
  {$IFDEF MSWINDOWS}Winapi.Windows,{$ENDIF}     // SetEnvironmentVariable
  uSonarConfig;

type
  [TestFixture]
  TTestSonarTokenStorage = class
  private
    FTempIni : string;
    FTempDir : string;
    procedure WriteIni(const Sections: array of string);
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;

    {$IFDEF MSWINDOWS}
    [Test] procedure DpapiTokenRoundtrip;
    [Test] procedure LoadTokenMissingEntryReturnsEmpty;
    [Test] procedure DpapiTokenIsNotFlaggedAsPlaintext;
    {$ENDIF}

    // ---- Klartext-Token ('PT:') muss sichtbar sein ----
    [Test] procedure PlaintextTokenIsFlagged;
    [Test] procedure PlaintextTokenMarksConfigSource;
  end;

implementation

uses
  System.NetEncoding;

const
  // Als Konstanten, nicht als Literale: DuplicateString zaehlt sonst jede
  // Wiederholung im eigenen Quelltext mit.
  TOKEN_REF    = 'test-key';
  SECRET_DPAPI = 'super-secret-42';
  SECRET_PLAIN = 'secret-in-the-clear';

function PlaintextEntry(const AToken: string): string;
// Baut einen [SonarTokens]-Wert im Non-Windows-Format nach: 'PT:' +
// Base64. Genau das, was StoreToken ohne DPAPI schreibt.
begin
  Result := 'PT:' + TNetEncoding.Base64.Encode(
    TEncoding.UTF8.GetBytes(AToken));
end;

procedure TTestSonarTokenStorage.WriteIni(const Sections: array of string);
// ASCII statt UTF-8: vermeidet ein BOM, so wie es echte INI-Tools tun.
var
  Lines : TStringList;
  S     : string;
begin
  Lines := TStringList.Create;
  try
    for S in Sections do
    begin
      Lines.Add(S);
    end;
    Lines.SaveToFile(FTempIni, TEncoding.ASCII);
  finally
    Lines.Free;
  end;
end;

procedure TTestSonarTokenStorage.Setup;
// Eigenes GUID-Verzeichnis pro Lauf: ein zweiter TestProject-Prozess hat
// hier schon einmal das Verzeichnis unter den Fuessen weggeloescht.
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'sca_sonar_tok_' +
    TGuid.NewGuid.ToString.Replace('{','').Replace('}',''));
  ForceDirectories(FTempDir);
  FTempIni := TPath.Combine(FTempDir, 'analyser.ini');
end;

procedure TTestSonarTokenStorage.TearDown;
begin
  if (FTempDir <> '') and TDirectory.Exists(FTempDir) then
  begin
    TDirectory.Delete(FTempDir, True);
  end;
end;

{$IFDEF MSWINDOWS}
procedure TTestSonarTokenStorage.DpapiTokenRoundtrip;
var
  Loaded : string;
begin
  TSonarConfigResolver.StoreToken(FTempIni, TOKEN_REF, SECRET_DPAPI);
  Loaded := TSonarConfigResolver.LoadToken(FTempIni, TOKEN_REF);
  Assert.AreEqual(SECRET_DPAPI, Loaded);
end;

procedure TTestSonarTokenStorage.LoadTokenMissingEntryReturnsEmpty;
var
  Loaded : string;
begin
  WriteIni(['[Sonar]', 'HostUrl=x']);
  Loaded := TSonarConfigResolver.LoadToken(FTempIni, 'does-not-exist');
  Assert.AreEqual('', Loaded);
end;

procedure TTestSonarTokenStorage.DpapiTokenIsNotFlaggedAsPlaintext;
var
  Loaded  : string;
  IsPlain : Boolean;
begin
  TSonarConfigResolver.StoreToken(FTempIni, TOKEN_REF, SECRET_DPAPI);
  Loaded := TSonarConfigResolver.LoadToken(FTempIni, TOKEN_REF, IsPlain);
  Assert.AreEqual(SECRET_DPAPI, Loaded);
  Assert.IsFalse(IsPlain, 'DPAPI entry must not be reported as plaintext');
end;
{$ENDIF}

procedure TTestSonarTokenStorage.PlaintextTokenIsFlagged;
// 'PT:' ist der Non-Windows-Fallback, wird aber auf JEDER Plattform
// gelesen. Wer eine solche INI mitbringt, muss das erfahren.
var
  Loaded  : string;
  IsPlain : Boolean;
begin
  WriteIni(['[SonarTokens]', 'k=' + PlaintextEntry(SECRET_PLAIN)]);
  Loaded := TSonarConfigResolver.LoadToken(FTempIni, 'k', IsPlain);
  Assert.AreEqual(SECRET_PLAIN, Loaded);
  Assert.IsTrue(IsPlain, 'PT: entry must be reported as plaintext');
end;

procedure TTestSonarTokenStorage.PlaintextTokenMarksConfigSource;
var
  Cli : TSonarCliOverrides;
  Cfg : TSonarConfig;
begin
  Cli := Default(TSonarCliOverrides);
  WriteIni(['[Sonar]', 'TokenRef=k',
            '[SonarTokens]', 'k=' + PlaintextEntry(SECRET_PLAIN)]);
  // Eine im Prozess gesetzte SONAR_TOKEN wuerde die INI ueberstimmen.
  SetEnvironmentVariable('SONAR_TOKEN', '');
  Cfg := TSonarConfigResolver.Resolve(Cli, FTempIni, '');
  Assert.AreEqual(SECRET_PLAIN, Cfg.Token);
  Assert.IsTrue(Cfg.TokenIsPlaintext, 'Resolve must carry the plaintext flag');
  Assert.Contains(Cfg.SourceToken, 'PLAINTEXT');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSonarTokenStorage);

end.
