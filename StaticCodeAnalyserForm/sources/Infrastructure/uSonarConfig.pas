unit uSonarConfig;

// SonarQube / SonarCloud Integrations-Konfiguration.
//
// Vier Konfigurations-Quellen, Reihenfolge nach Prioritaet (hoechste zuerst):
//   1. CLI-Flags         (--sonar-host, --sonar-token, --sonar-project, ...)
//   2. Environment-Vars  (SONAR_HOST_URL, SONAR_TOKEN, SONAR_PROJECT_KEY,
//                         SONAR_ORGANIZATION, SONAR_BRANCH)
//   3. Project-Config    (sonar-project.properties im Projekt-Root)
//   4. User-INI          (analyser.ini Section [Sonar], Token in [SonarTokens]
//                         per DPAPI verschluesselt)
//
// Jede Quelle fuellt nur Felder die noch leer sind. Tools die Sonar nutzen
// (uConsoleRunner, IDE-Plugin) rufen TSonarConfig.Resolve auf und greifen
// auf das fertige Config-Record zu.
//
// Token-Speicherung (Windows): DPAPI per Current-User-Scope. Klartext-Token
// wird via CryptProtectData verschluesselt und als Hex-String in der
// [SonarTokens]-Section abgelegt. Nur der gleiche Windows-User auf demselben
// Rechner kann es entschluesseln - kein Replay-Risiko in Multi-User-Repos.
// Auf Non-Windows-Plattformen ist nur der Env-Var-Pfad supported (kein
// Klartext-INI).

interface

uses
  System.SysUtils, System.Classes, System.IniFiles;

type
  // Konfigurations-Record - das was nach Resolve() ueberall verwendet wird.
  TSonarConfig = record
    HostUrl       : string;   // z.B. 'https://sonar.company.com'
    Token         : string;   // Klartext nach Resolve() - NIE persistieren
    ProjectKey    : string;   // z.B. 'my-delphi-project'
    Organization  : string;   // optional, nur fuer SonarCloud
    Branch        : string;   // optional, default = leer = main
    SourceMapping : string;   // optional, Mapping Win-Pfade -> Container-Pfade
    Insecure      : Boolean;  // True = TLS-Cert-Warnung ignorieren (--sonar-insecure)

    // Diagnose: aus welchen Quellen kam jedes Feld? Wird vom Health-Check
    // ausgegeben damit User sieht "Token kam aus Env" vs "aus INI".
    SourceHostUrl    : string;
    SourceToken      : string;
    SourceProjectKey : string;

    // Validierung - was muss minimal gesetzt sein um Sonar zu kontaktieren?
    function IsValid: Boolean;
    function MissingFields: string;
  end;

  // Eine Stage aus dem Health-Check. Wird gerendert als
  // "[<Symbol>] <Description>" mit optionaler Detail-Zeile darunter.
  TSonarHealthStage = record
    Description : string;     // 'DNS resolution: sonar.company.com'
    Ok          : Boolean;
    DetailLine  : string;     // Erklaerung bei Fehler (auch Hint bei OK)
    DurationMs  : Integer;
  end;

  TSonarHealthResult = record
    Stages  : TArray<TSonarHealthStage>;
    Healthy : Boolean;        // True wenn alle Stages Ok=True
    Summary : string;         // 'Sonar connection healthy.' / 'Failed at: ...'
  end;

  // Argument-Bag fuer den CLI-Resolver (vermeidet hartes Dependency auf
  // uConsoleRunner.TCliArgs - dieser Test-und CLI-Mode-Layer ist Sonar-
  // unabhaengig).
  TSonarCliOverrides = record
    HostUrl    : string;
    Token      : string;
    ProjectKey : string;
    Branch     : string;
    Insecure   : Boolean;
    ConfigPath : string;      // alternativer analyser.ini-Pfad
  end;

  TSonarConfigResolver = class
  public
    // Haupt-Resolver - mergt die vier Quellen.
    //   CLI            - Werte aus --sonar-* Flags (leer-Strings = nicht gesetzt)
    //   AnalyserIniPath- Pfad zur analyser.ini; '' = Default
    //                    (%APPDATA%\StaticCodeAnalyser\analyser.ini)
    //   ProjectDir     - Pfad zum Projekt-Root (fuer sonar-project.properties);
    //                    '' = kein Project-File lesen
    class function Resolve(const CLI: TSonarCliOverrides;
      const AnalyserIniPath, ProjectDir: string): TSonarConfig; static;

    // Lese-Helper fuer Testbarkeit
    class procedure ReadFromIni(const FileName: string;
      var Cfg: TSonarConfig); static;
    class procedure ReadFromEnv(var Cfg: TSonarConfig); static;
    class procedure ReadFromProjectProps(const ProjectDir: string;
      var Cfg: TSonarConfig); static;

    // Token-Speicherung in der [SonarTokens]-Section. Klartext-Token wird
    // ueber DPAPI (Win) oder Plaintext-Fallback (non-Win) gespeichert.
    //   TokenRef        - Schluessel in [SonarTokens], z.B. 'sonar-test'
    //   PlainTextToken  - das eigentliche Token
    // Schreibt nichts wenn PlainTextToken leer.
    class procedure StoreToken(const FileName, TokenRef,
      PlainTextToken: string); static;

    // Liest ein Token aus [SonarTokens][TokenRef] und entschluesselt es.
    // Liefert '' bei fehlendem Eintrag oder Decrypt-Fehler.
    class function LoadToken(const FileName, TokenRef: string): string; static;

    // Default-INI-Pfad: %APPDATA%\StaticCodeAnalyser\analyser.ini
    class function DefaultIniPath: string; static;

    // Default-Pfad fuer sonar-project.properties relativ zu ProjectDir.
    class function ProjectPropsPath(const ProjectDir: string): string; static;
  end;

  // Health-Check - testet die Verbindung in Stufen.
  TSonarHealthCheck = class
  public
    // Fuehrt alle Stufen aus und liefert ein zusammengefasstes Ergebnis.
    // Stages werden in der Reihenfolge ausgefuehrt; bricht bei der ersten
    // fatalen Stufe ab (z.B. DNS-Fail -> kein Sinn mehr in HTTP-Versuchen).
    class function Run(const Cfg: TSonarConfig): TSonarHealthResult; static;

    // Rendert das Ergebnis als ASCII-Checklist (CLI-Output).
    class function FormatChecklist(const R: TSonarHealthResult): string; static;
  end;

implementation

uses
  System.IOUtils, System.NetEncoding, System.Net.HttpClient,
  System.Net.URLClient, System.JSON, System.Diagnostics, System.StrUtils,
  System.Generics.Collections
  {$IFDEF MSWINDOWS}, Winapi.Windows, Winapi.WinSock2{$ENDIF}
  ;

{ ---- DPAPI Helpers (Windows only) ---- }

{$IFDEF MSWINDOWS}
type
  DATA_BLOB = record
    cbData : DWORD;
    pbData : PByte;
  end;

const
  CRYPTPROTECT_UI_FORBIDDEN = $1;

function CryptProtectData(pDataIn: PDATA_BLOB; szDataDescr: PWideChar;
  pOptionalEntropy: PDATA_BLOB; pvReserved: Pointer;
  pPromptStruct: Pointer; dwFlags: DWORD;
  pDataOut: PDATA_BLOB): BOOL; stdcall; external 'crypt32.dll';

function CryptUnprotectData(pDataIn: PDATA_BLOB; ppszDataDescr: PPWideChar;
  pOptionalEntropy: PDATA_BLOB; pvReserved: Pointer;
  pPromptStruct: Pointer; dwFlags: DWORD;
  pDataOut: PDATA_BLOB): BOOL; stdcall; external 'crypt32.dll';

function LocalFree_(hMem: HLOCAL): HLOCAL; stdcall;
  external 'kernel32.dll' name 'LocalFree';

function DpapiProtect(const PlainText: string): TBytes;
// Verschluesselt UTF-8-Bytes mit DPAPI (Current-User-Scope). Liefert nil
// bei Fehler.
var
  InBlob, OutBlob : DATA_BLOB;
  Plain           : TBytes;
begin
  Result := nil;
  Plain := TEncoding.UTF8.GetBytes(PlainText);
  if Length(Plain) = 0 then Exit;
  InBlob.cbData := Length(Plain);
  InBlob.pbData := PByte(Plain);
  FillChar(OutBlob, SizeOf(OutBlob), 0);
  if not CryptProtectData(@InBlob, 'SCA-Sonar-Token', nil, nil, nil,
    CRYPTPROTECT_UI_FORBIDDEN, @OutBlob) then
    Exit;
  try
    SetLength(Result, OutBlob.cbData);
    Move(OutBlob.pbData^, Result[0], OutBlob.cbData);
  finally
    LocalFree_(HLOCAL(OutBlob.pbData));
  end;
end;

function DpapiUnprotect(const Cipher: TBytes): string;
// Entschluesselt DPAPI-Bytes zurueck zum Klartext. Liefert '' bei Fehler.
var
  InBlob, OutBlob : DATA_BLOB;
begin
  Result := '';
  if Length(Cipher) = 0 then Exit;
  InBlob.cbData := Length(Cipher);
  InBlob.pbData := PByte(Cipher);
  FillChar(OutBlob, SizeOf(OutBlob), 0);
  if not CryptUnprotectData(@InBlob, nil, nil, nil, nil,
    CRYPTPROTECT_UI_FORBIDDEN, @OutBlob) then
    Exit;
  try
    Result := TEncoding.UTF8.GetString(
      BytesOf(OutBlob.pbData, OutBlob.cbData));
  finally
    LocalFree_(HLOCAL(OutBlob.pbData));
  end;
end;
{$ENDIF}

function BytesToHex(const B: TBytes): string;
const
  HEX = '0123456789ABCDEF';
var
  i : Integer;
begin
  SetLength(Result, Length(B) * 2);
  for i := 0 to High(B) do
  begin
    Result[1 + i * 2]     := HEX[1 + (B[i] shr 4)];
    Result[1 + i * 2 + 1] := HEX[1 + (B[i] and $0F)];
  end;
end;

function HexToBytes(const S: string): TBytes;
var
  i, V : Integer;
  C    : Char;
begin
  if (Length(S) = 0) or (Length(S) mod 2 <> 0) then Exit(nil);
  SetLength(Result, Length(S) div 2);
  for i := 0 to High(Result) do
  begin
    C := S[1 + i * 2];
    if (C >= '0') and (C <= '9') then V := Ord(C) - Ord('0')
    else if (C >= 'A') and (C <= 'F') then V := Ord(C) - Ord('A') + 10
    else if (C >= 'a') and (C <= 'f') then V := Ord(C) - Ord('a') + 10
    else Exit(nil);
    V := V shl 4;
    C := S[1 + i * 2 + 1];
    if (C >= '0') and (C <= '9') then V := V or (Ord(C) - Ord('0'))
    else if (C >= 'A') and (C <= 'F') then V := V or (Ord(C) - Ord('A') + 10)
    else if (C >= 'a') and (C <= 'f') then V := V or (Ord(C) - Ord('a') + 10)
    else Exit(nil);
    Result[i] := V;
  end;
end;

{ ---- TSonarConfig ---- }

function TSonarConfig.IsValid: Boolean;
begin
  Result := (HostUrl <> '') and (Token <> '') and (ProjectKey <> '');
end;

function TSonarConfig.MissingFields: string;
var
  Parts : TStringList;
begin
  Parts := TStringList.Create;
  try
    if HostUrl    = '' then Parts.Add('sonar.host.url');
    if Token      = '' then Parts.Add('sonar.token');
    if ProjectKey = '' then Parts.Add('sonar.projectKey');
    Result := Parts.CommaText;
  finally
    Parts.Free;
  end;
end;

{ ---- TSonarConfigResolver ---- }

class function TSonarConfigResolver.DefaultIniPath: string;
var
  AppData : string;
begin
  AppData := GetEnvironmentVariable('APPDATA');
  if AppData = '' then Exit('');
  Result := IncludeTrailingPathDelimiter(AppData) +
            'StaticCodeAnalyser\analyser.ini';
end;

class function TSonarConfigResolver.ProjectPropsPath(
  const ProjectDir: string): string;
begin
  if ProjectDir = '' then Exit('');
  Result := IncludeTrailingPathDelimiter(ProjectDir) +
            'sonar-project.properties';
end;

function NormalizeHostUrl(const S: string): string;
// 'http://localhost:9000/' und 'http://localhost:9000' sind aequivalent -
// trailing slash entfernen damit '/api/system/status'-Concat sauber bleibt.
begin
  Result := Trim(S);
  while (Result <> '') and (Result[Length(Result)] = '/') do
    SetLength(Result, Length(Result) - 1);
end;

class procedure TSonarConfigResolver.ReadFromIni(const FileName: string;
  var Cfg: TSonarConfig);
var
  Ini      : TIniFile;
  TokenRef : string;
  Plain    : string;
begin
  if (FileName = '') or not TFile.Exists(FileName) then Exit;
  Ini := TIniFile.Create(FileName);
  try
    if Cfg.HostUrl = '' then
    begin
      Cfg.HostUrl := NormalizeHostUrl(Ini.ReadString('Sonar', 'HostUrl', ''));
      if Cfg.HostUrl <> '' then Cfg.SourceHostUrl := 'analyser.ini';
    end;
    if Cfg.ProjectKey = '' then
    begin
      Cfg.ProjectKey := Trim(Ini.ReadString('Sonar', 'ProjectKey', ''));
      if Cfg.ProjectKey <> '' then Cfg.SourceProjectKey := 'analyser.ini';
    end;
    if Cfg.Organization = '' then
      Cfg.Organization := Trim(Ini.ReadString('Sonar', 'Organization', ''));
    if Cfg.Branch = '' then
      Cfg.Branch := Trim(Ini.ReadString('Sonar', 'Branch', ''));
    if Cfg.SourceMapping = '' then
      Cfg.SourceMapping := Trim(Ini.ReadString('Sonar', 'SourceMapping', ''));
    // Insecure: any TRUE-source wins. CLI=True wird hier nicht ueberschrieben;
    // INI=True hebt einen Default=False auf.
    if not Cfg.Insecure then
      Cfg.Insecure := Ini.ReadBool('Sonar', 'Insecure', False);
    if Cfg.Token = '' then
    begin
      TokenRef := Trim(Ini.ReadString('Sonar', 'TokenRef', ''));
      if TokenRef <> '' then
      begin
        Plain := LoadToken(FileName, TokenRef);
        if Plain <> '' then
        begin
          Cfg.Token := Plain;
          Cfg.SourceToken := 'analyser.ini [SonarTokens]';
        end;
      end;
    end;
  finally
    Ini.Free;
  end;
end;

class procedure TSonarConfigResolver.ReadFromEnv(var Cfg: TSonarConfig);
var
  E : string;
begin
  if Cfg.HostUrl = '' then
  begin
    E := GetEnvironmentVariable('SONAR_HOST_URL');
    if E <> '' then begin Cfg.HostUrl := NormalizeHostUrl(E); Cfg.SourceHostUrl := 'env SONAR_HOST_URL'; end;
  end;
  if Cfg.Token = '' then
  begin
    E := GetEnvironmentVariable('SONAR_TOKEN');
    if E <> '' then begin Cfg.Token := E; Cfg.SourceToken := 'env SONAR_TOKEN'; end;
  end;
  if Cfg.ProjectKey = '' then
  begin
    E := GetEnvironmentVariable('SONAR_PROJECT_KEY');
    if E <> '' then begin Cfg.ProjectKey := E; Cfg.SourceProjectKey := 'env SONAR_PROJECT_KEY'; end;
  end;
  if Cfg.Organization = '' then
    Cfg.Organization := GetEnvironmentVariable('SONAR_ORGANIZATION');
  if Cfg.Branch = '' then
    Cfg.Branch := GetEnvironmentVariable('SONAR_BRANCH');
end;

class procedure TSonarConfigResolver.ReadFromProjectProps(
  const ProjectDir: string; var Cfg: TSonarConfig);
// Minimaler Properties-Parser: zeilenweise, '#' und '!' = Kommentar,
// 'key=value' oder 'key:value', Whitespace getrimmt.
var
  Path  : string;
  Lines : TStringList;
  S, K, V : string;
  EqPos : Integer;
begin
  Path := ProjectPropsPath(ProjectDir);
  if (Path = '') or not TFile.Exists(Path) then Exit;

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(Path, TEncoding.UTF8);
    for S in Lines do
    begin
      var Stripped := Trim(S);
      if (Stripped = '') or (Stripped[1] = '#') or (Stripped[1] = '!') then
        Continue;
      EqPos := Pos('=', Stripped);
      if EqPos = 0 then EqPos := Pos(':', Stripped);
      if EqPos = 0 then Continue;
      K := Trim(Copy(Stripped, 1, EqPos - 1));
      V := Trim(Copy(Stripped, EqPos + 1, MaxInt));

      if (Cfg.HostUrl = '') and SameText(K, 'sonar.host.url') then
      begin
        Cfg.HostUrl := NormalizeHostUrl(V);
        Cfg.SourceHostUrl := 'sonar-project.properties';
      end
      else if (Cfg.ProjectKey = '') and SameText(K, 'sonar.projectKey') then
      begin
        Cfg.ProjectKey := V;
        Cfg.SourceProjectKey := 'sonar-project.properties';
      end
      else if (Cfg.Organization = '') and SameText(K, 'sonar.organization') then
        Cfg.Organization := V
      else if (Cfg.Branch = '') and SameText(K, 'sonar.branch.name') then
        Cfg.Branch := V
      else if (Cfg.SourceMapping = '') and SameText(K, 'sonar.sourceMapping') then
        Cfg.SourceMapping := V;
      // sonar.token in sonar-project.properties wird NICHT gelesen -
      // Tokens gehoeren nicht ins Repo (kommt in VCS).
    end;
  finally
    Lines.Free;
  end;
end;

class function TSonarConfigResolver.Resolve(const CLI: TSonarCliOverrides;
  const AnalyserIniPath, ProjectDir: string): TSonarConfig;
var
  IniPath : string;
begin
  Result := Default(TSonarConfig);

  // 1. CLI hat hoechste Prioritaet
  if CLI.HostUrl <> '' then
  begin
    Result.HostUrl := NormalizeHostUrl(CLI.HostUrl);
    Result.SourceHostUrl := 'CLI --sonar-host';
  end;
  if CLI.Token <> '' then
  begin
    Result.Token := CLI.Token;
    Result.SourceToken := 'CLI --sonar-token';
  end;
  if CLI.ProjectKey <> '' then
  begin
    Result.ProjectKey := CLI.ProjectKey;
    Result.SourceProjectKey := 'CLI --sonar-project';
  end;
  if CLI.Branch <> '' then Result.Branch := CLI.Branch;
  Result.Insecure := CLI.Insecure;

  // 2. Env
  ReadFromEnv(Result);

  // 3. Project-Properties
  ReadFromProjectProps(ProjectDir, Result);

  // 4. User-INI
  IniPath := AnalyserIniPath;
  if IniPath = '' then IniPath := DefaultIniPath;
  ReadFromIni(IniPath, Result);
end;

class procedure TSonarConfigResolver.StoreToken(const FileName, TokenRef,
  PlainTextToken: string);
var
  Ini    : TIniFile;
  Cipher : TBytes;
  Hex    : string;
begin
  if (FileName = '') or (TokenRef = '') or (PlainTextToken = '') then Exit;

  {$IFDEF MSWINDOWS}
  Cipher := DpapiProtect(PlainTextToken);
  if Length(Cipher) = 0 then Exit;
  Hex := BytesToHex(Cipher);
  {$ELSE}
  // Non-Windows-Fallback: Plaintext + Marker. Sicherheits-Tradeoff dokumentiert
  // im Banner und in den Tests; CLI gibt eine WARNING aus.
  Hex := 'PT:' + TNetEncoding.Base64.Encode(
    TEncoding.UTF8.GetBytes(PlainTextToken));
  {$ENDIF}

  Ini := TIniFile.Create(FileName);
  try
    Ini.WriteString('SonarTokens', TokenRef, Hex);
  finally
    Ini.Free;
  end;
end;

class function TSonarConfigResolver.LoadToken(const FileName,
  TokenRef: string): string;
var
  Ini : TIniFile;
  Hex : string;
  Cipher : TBytes;
begin
  Result := '';
  if (FileName = '') or (TokenRef = '') or not TFile.Exists(FileName) then Exit;

  Ini := TIniFile.Create(FileName);
  try
    Hex := Trim(Ini.ReadString('SonarTokens', TokenRef, ''));
  finally
    Ini.Free;
  end;
  if Hex = '' then Exit;

  if StartsText('PT:', Hex) then
  begin
    // Non-Windows-Plaintext-Fallback
    try
      Result := TEncoding.UTF8.GetString(
        TNetEncoding.Base64.DecodeStringToBytes(Copy(Hex, 4, MaxInt)));
    except
      Result := '';
    end;
    Exit;
  end;

  {$IFDEF MSWINDOWS}
  Cipher := HexToBytes(Hex);
  if Length(Cipher) = 0 then Exit;
  Result := DpapiUnprotect(Cipher);
  {$ENDIF}
end;

{ ---- TSonarHealthCheck ---- }

function MakeStage(const Desc: string; Ok: Boolean;
  const Detail: string; DurMs: Integer): TSonarHealthStage;
begin
  Result.Description := Desc;
  Result.Ok          := Ok;
  Result.DetailLine  := Detail;
  Result.DurationMs  := DurMs;
end;

{$IFDEF MSWINDOWS}
function ResolveDnsToFirstIp(const Host: string; out Ip: string): Boolean;
// Minimal-DNS-Lookup via WinSock. Liefert die erste IPv4-Adresse als Text.
var
  WsaData : TWSAData;
  HostEnt : PHostEnt;
  H       : AnsiString;
  Addr    : PInAddr;
begin
  Result := False;
  Ip := '';
  if WSAStartup($0202, WsaData) <> 0 then Exit;
  try
    H := AnsiString(Host);
    HostEnt := gethostbyname(PAnsiChar(H));
    if HostEnt = nil then Exit;
    Addr := PInAddr(HostEnt.h_addr_list^);
    if Addr = nil then Exit;
    Ip := string(inet_ntoa(Addr^));
    Result := True;
  finally
    WSACleanup;
  end;
end;
{$ELSE}
function ResolveDnsToFirstIp(const Host: string; out Ip: string): Boolean;
begin
  Ip := '';
  Result := False;  // Non-Windows: skip DNS-Stage (HTTP-Layer wird's catchen)
end;
{$ENDIF}

function ExtractHost(const Url: string): string;
// 'https://sonar.company.com:9000/api/...' -> 'sonar.company.com'
var
  S : string;
  P : Integer;
begin
  S := Url;
  P := Pos('://', S);
  if P > 0 then Delete(S, 1, P + 2);
  P := Pos('/', S);
  if P > 0 then S := Copy(S, 1, P - 1);
  P := Pos(':', S);
  if P > 0 then S := Copy(S, 1, P - 1);
  Result := S;
end;

function HttpGet(const Url, Token: string; Insecure: Boolean;
  out StatusCode: Integer; out Body: string): Boolean;
// Einfacher HTTP-GET mit Bearer-Auth. Liefert True wenn der Request
// durchlief (auch bei 4xx/5xx); False bei Network-Layer-Fehler.
var
  Client : THTTPClient;
  Req    : IHTTPRequest;
  Resp   : IHTTPResponse;
begin
  Result := False;
  StatusCode := 0;
  Body := '';
  Client := THTTPClient.Create;
  try
    if Insecure then
      Client.SecureProtocols := [THTTPSecureProtocol.TLS11, THTTPSecureProtocol.TLS12, THTTPSecureProtocol.TLS13];
    Client.ConnectionTimeout := 5000;
    Client.ResponseTimeout   := 10000;
    Req := Client.GetRequest(sHTTPMethodGet, Url);
    if Token <> '' then
      Req.AddHeader('Authorization', 'Bearer ' + Token);
    Req.AddHeader('Accept', 'application/json');
    try
      Resp := Client.Execute(Req);
      StatusCode := Resp.StatusCode;
      Body := Resp.ContentAsString(TEncoding.UTF8);
      Result := True;
    except
      on E: Exception do
      begin
        Body := E.ClassName + ': ' + E.Message;
        Exit;
      end;
    end;
  finally
    Client.Free;
  end;
end;

class function TSonarHealthCheck.Run(const Cfg: TSonarConfig): TSonarHealthResult;
var
  Stages   : TList<TSonarHealthStage>;
  Stage    : TSonarHealthStage;
  Host, Ip : string;
  Status   : Integer;
  Body     : string;
  Sw       : TStopwatch;
  Ok       : Boolean;
  Url      : string;
begin
  Stages := TList<TSonarHealthStage>.Create;
  try
    Result.Healthy := True;

    // Stage 1: Required-Fields
    if not Cfg.IsValid then
    begin
      Stage := MakeStage('Required fields',
        False,
        'Missing: ' + Cfg.MissingFields,
        0);
      Stages.Add(Stage);
      Result.Healthy := False;
      Result.Summary := 'Configuration incomplete.';
      Result.Stages := Stages.ToArray;
      Exit;
    end;

    // Stage 2: DNS Resolution
    Host := ExtractHost(Cfg.HostUrl);
    Sw := TStopwatch.StartNew;
    Ok := ResolveDnsToFirstIp(Host, Ip);
    Sw.Stop;
    if Ok then
      Stage := MakeStage('DNS resolution: ' + Host + ' -> ' + Ip,
        True, '', Sw.ElapsedMilliseconds)
    else
      Stage := MakeStage('DNS resolution: ' + Host,
        False,
        'Host does not resolve. Check sonar.host.url and DNS connectivity.',
        Sw.ElapsedMilliseconds);
    Stages.Add(Stage);
    if not Ok then
    begin
      Result.Healthy := False;
      Result.Summary := 'DNS resolution failed.';
      Result.Stages := Stages.ToArray;
      Exit;
    end;

    // Stage 3: GET /api/system/status (kein Token noetig)
    Sw := TStopwatch.StartNew;
    Url := Cfg.HostUrl + '/api/system/status';
    Ok := HttpGet(Url, '', Cfg.Insecure, Status, Body);
    Sw.Stop;
    if Ok and (Status = 200) and (Pos('"UP"', Body) > 0) then
    begin
      Stage := MakeStage('HTTP /api/system/status: UP',
        True, '', Sw.ElapsedMilliseconds);
    end
    else if Ok and (Status = 200) and (Pos('"STARTING"', Body) > 0) then
    begin
      Stage := MakeStage('HTTP /api/system/status: STARTING',
        False, 'Server is starting up. Wait ~60s and retry.',
        Sw.ElapsedMilliseconds);
    end
    else if Ok then
    begin
      Stage := MakeStage(Format('HTTP /api/system/status: %d', [Status]),
        False, Copy(Body, 1, 200), Sw.ElapsedMilliseconds);
    end
    else
    begin
      Stage := MakeStage('HTTP /api/system/status',
        False, 'Connection error: ' + Body, Sw.ElapsedMilliseconds);
    end;
    Stages.Add(Stage);
    if not Stage.Ok then
    begin
      Result.Healthy := False;
      Result.Summary := 'Server status check failed.';
      Result.Stages := Stages.ToArray;
      Exit;
    end;

    // Stage 4: Token-Validierung
    Sw := TStopwatch.StartNew;
    Url := Cfg.HostUrl + '/api/authentication/validate';
    Ok := HttpGet(Url, Cfg.Token, Cfg.Insecure, Status, Body);
    Sw.Stop;
    if Ok and (Status = 200) and (Pos('"valid":true', Body) > 0) then
      Stage := MakeStage('Token validation: valid',
        True, '', Sw.ElapsedMilliseconds)
    else if Ok and (Status = 401) then
      Stage := MakeStage('Token validation: 401 Unauthorized',
        False, 'Token rejected. Check sonar.token / regenerate at User Profile > Security.',
        Sw.ElapsedMilliseconds)
    else if Ok then
      Stage := MakeStage(Format('Token validation: %d', [Status]),
        False, Copy(Body, 1, 200), Sw.ElapsedMilliseconds)
    else
      Stage := MakeStage('Token validation',
        False, 'Connection error: ' + Body, Sw.ElapsedMilliseconds);
    Stages.Add(Stage);
    if not Stage.Ok then
    begin
      Result.Healthy := False;
      Result.Summary := 'Token validation failed.';
      Result.Stages := Stages.ToArray;
      Exit;
    end;

    // Stage 5: Project-Lookup
    Sw := TStopwatch.StartNew;
    Url := Cfg.HostUrl + '/api/projects/search?projects=' +
           TNetEncoding.URL.Encode(Cfg.ProjectKey);
    Ok := HttpGet(Url, Cfg.Token, Cfg.Insecure, Status, Body);
    Sw.Stop;
    if Ok and (Status = 200) and (Pos('"key":"' + Cfg.ProjectKey + '"', Body) > 0) then
      Stage := MakeStage('Project access: ' + Cfg.ProjectKey + ' (visible)',
        True, '', Sw.ElapsedMilliseconds)
    else if Ok and (Status = 200) then
      Stage := MakeStage('Project access: ' + Cfg.ProjectKey + ' (not found)',
        False, 'Project does not exist or user lacks Browse permission. ' +
               'Create via Web-UI or POST /api/projects/create.',
        Sw.ElapsedMilliseconds)
    else if Ok and (Status = 403) then
      Stage := MakeStage('Project access: 403 Forbidden',
        False, 'Token lacks Browse permission for ' + Cfg.ProjectKey,
        Sw.ElapsedMilliseconds)
    else
      Stage := MakeStage(Format('Project access: %d', [Status]),
        False, Copy(Body, 1, 200), Sw.ElapsedMilliseconds);
    Stages.Add(Stage);

    Result.Stages := Stages.ToArray;
    Result.Healthy := True;
    for var SChk in Result.Stages do
      if not SChk.Ok then begin Result.Healthy := False; Break; end;
    if Result.Healthy then
      Result.Summary := 'Sonar connection healthy.'
    else
      Result.Summary := 'Sonar connection check failed.';
  finally
    Stages.Free;
  end;
end;

class function TSonarHealthCheck.FormatChecklist(
  const R: TSonarHealthResult): string;
var
  SB : TStringBuilder;
  S  : TSonarHealthStage;
  Sym: string;
begin
  SB := TStringBuilder.Create;
  try
    for S in R.Stages do
    begin
      if S.Ok then Sym := '[OK]' else Sym := '[FAIL]';
      SB.Append(Sym);
      SB.Append(' ');
      SB.AppendLine(S.Description);
      if S.DetailLine <> '' then
      begin
        SB.Append('     -> ');
        SB.AppendLine(S.DetailLine);
      end;
    end;
    if R.Summary <> '' then SB.AppendLine(R.Summary);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
