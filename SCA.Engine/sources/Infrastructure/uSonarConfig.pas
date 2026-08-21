unit uSonarConfig;

// SonarQube / SonarCloud Integrations-Konfiguration.
//
// Vier Konfigurations-Quellen, Reihenfolge nach Prioritaet (hoechste zuerst):
//   1. CLI-Flags         (--sonar-host, --sonar-token, --sonar-project, ...)
//   2. Environment-Vars  (SONAR_HOST_URL, SONAR_TOKEN, SONAR_PROJECT_KEY,
//                         SONAR_ORGANIZATION, SONAR_BRANCH)
//   3. Project-Config    (sonar-project.properties im Projekt-Root) -
//                         liefert NUR projectKey/organization/branch.
//                         Weder sonar.token NOCH
//                         sonar.host.url werden von hier uebernommen:
//                         die Datei liegt im gescannten Repo und ist
//                         damit fremdbestimmt (s. ReadFromProjectProps).
//   4. User-INI          (analyser.ini Section [Sonar], Token in [SonarTokens]
//                         per DPAPI verschluesselt)
//
// Jede Quelle fuellt nur Felder die noch leer sind. Tools die Sonar nutzen
// (uConsoleRunner, IDE-Plugin) rufen TSonarConfig.Resolve auf und greifen
// auf das fertige Config-Record zu.
//
// WER LIEST WAS - vor dem Anbauen weiterer Felder bitte lesen. Der Resolver
// laeuft NICHT bei jedem Sonar-Befehl: --sonar-export schreibt nur eine
// Datei und fasst dieses Record nie an. Konsumenten sind genau zwei:
//   * TSonarHealthCheck.Run  (--sonar-test, IDE 'Test Connection') -
//     benutzt HostUrl, Token, ProjectKey, Organization, Insecure.
//   * das --sonar-init-Template in uConsoleRunner - schreibt ProjectKey,
//     Organization und Branch in die sonar-project.properties.
// Ein Feld ohne Platz in dieser Liste ist tot, egal wie sauber es
// aufgeloest wird (2026-08-08 kostete das drei stille Attrappen).
//
// Token-Speicherung (Windows): DPAPI per Current-User-Scope. Der Token wird
// via CryptProtectData verschluesselt und als Hex-String in der
// [SonarTokens]-Section abgelegt. Nur derselbe Windows-User auf demselben
// Rechner kann ihn entschluesseln - eine kopierte analyser.ini ist woanders
// wertlos. Das ist Schutz DER RUHENDEN DATEI, kein Tresor: jeder Prozess,
// der unter diesem Konto laeuft, kann genauso entschluesseln. Wer das nicht
// will, nimmt SONAR_TOKEN aus der Umgebung.
//
// Non-Windows hat kein DPAPI; dort schreibt StoreToken einen mit 'PT:'
// markierten Base64-Klartext. Gelesen wird 'PT:' auf ALLEN Plattformen
// (eine mitgebrachte INI funktioniert also auch unter Windows) - deshalb
// meldet der Resolver solche Eintraege ueber TokenIsPlaintext, und die
// Konsumenten (CLI --sonar-test, IDE-Plugin) warnen sichtbar.

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
    Branch        : string;   // optional, landet in --sonar-init-Template
    Insecure      : Boolean;  // True = TLS-Cert-Warnung ignorieren (--sonar-insecure)

    // Diagnose: aus welchen Quellen kam jedes Feld? Wird vom Health-Check
    // ausgegeben damit User sieht "Token kam aus Env" vs "aus INI".
    SourceHostUrl    : string;
    SourceToken      : string;
    SourceProjectKey : string;

    // Gesetzt, wenn eine sonar-project.properties im GESCANNTEN Repo eine
    // sonar.host.url mitbringt: der Wert wird bewusst IGNORIERT (s.
    // ReadFromProjectProps), der Consumer soll den Nutzer aber darauf
    // hinweisen, damit eine legitime Repo-Konfiguration nicht raetselhaft
    // wirkungslos bleibt.
    IgnoredRepoHost  : string;

    // True, wenn der Token als 'PT:'-Klartext aus der INI kam (Non-Windows-
    // Fallback, wird aber ueberall gelesen). Der Konsument MUSS das sichtbar
    // machen - sonst haelt der Nutzer eine unverschluesselte Datei fuer
    // DPAPI-geschuetzt.
    TokenIsPlaintext : Boolean;

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
    // APlaintext meldet, dass der Eintrag ein 'PT:'-Klartext war.
    // Cross-project: vom IDE-Plugin (uIDESonarOptions) benutzt, daher public
    // belassen - der CanBePrivate-Detector sieht den Plugin-Code nicht.
    class function LoadToken(const FileName, TokenRef: string): string;
      overload; static;
    class function LoadToken(const FileName, TokenRef: string;
      out APlaintext: Boolean): string; overload; static;

    // Default-INI-Pfad: %APPDATA%\StaticCodeAnalyser\analyser.ini
    // Cross-project: vom IDE-Plugin benutzt, public belassen.
    class function DefaultIniPath: string; static;

    // Default-Pfad fuer sonar-project.properties relativ zu ProjectDir.
    // Cross-project: vom IDE-Plugin benutzt, public belassen.
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

// noinspection-file AvoidOut, BeginEndRequired, BooleanParam, CanBeClassMethod, CanBeStrictPrivate, CanBeUnitPrivate, ClassPerFile, ConcatToFormat, ConsecutiveSection, CyclomaticComplexity, DeepNesting, DigitGrouping, DuplicateString, ExceptionTooGeneral, ExceptOnException, GroupedDeclaration, IfElseBegin, LargeClass, LongMethod, LongParamList, MagicNumber, MultipleExit, NestedRoutine, NestedTry, NilComparison, RedundantJump, TooLongLine, TypeName, UnicodeToAnsiCast, UnsortedUses, UnusedParameter
// Long-form HTTP/Sonar-URL-Construction via Concat (lesbarer als Format
// fuer mehrteilige URL-Segmente). MultipleExit = guard-clauses fuer
// HTTP-Status/Network-Error-Pfade, idiomatisch fuer Network-Calls.

uses
  System.IOUtils, System.NetEncoding, System.Net.HttpClient,
  System.Net.URLClient, System.JSON, System.Diagnostics, System.StrUtils,
  System.Generics.Collections
  {$IFDEF MSWINDOWS}, Winapi.Windows, Winapi.WinSock2{$ENDIF},
  uRepoSettings;   // TCommentPreservingIni - Kommentare der analyser.ini erhalten

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
  Ini      : TMemIniFile;
  TokenRef : string;
  Plain    : string;
  IsPlain  : Boolean;
begin
  if (FileName = '') or not TFile.Exists(FileName) then Exit;
  // TMemIniFile statt TIniFile: liest UTF-8-BOM-Dateien (Notepad-Default
  // beim "Save as UTF-8") korrekt, ohne dass das BOM in die erste Section
  // bleedet und alle Reads den Default zurueckliefern.
  Ini := TMemIniFile.Create(FileName, TEncoding.UTF8);
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
    // [Sonar] SourceMapping wurde bis 2026-08-08 hier eingelesen und von
    // niemandem gelesen - der Export schreibt Pfade relativ zu --base-dir,
    // das ist der Hebel fuer Pfad-Umschreibung. Key ersatzlos entfernt;
    // bestehende INIs stoeren sich nicht an unbekannten Eintraegen.
    // Insecure: any TRUE-source wins. CLI=True wird hier nicht ueberschrieben;
    // INI=True hebt einen Default=False auf.
    if not Cfg.Insecure then
      Cfg.Insecure := Ini.ReadBool('Sonar', 'Insecure', False);
    if Cfg.Token = '' then
    begin
      TokenRef := Trim(Ini.ReadString('Sonar', 'TokenRef', ''));
      if TokenRef <> '' then
      begin
        Plain := LoadToken(FileName, TokenRef, IsPlain);
        if Plain <> '' then
        begin
          Cfg.Token := Plain;
          Cfg.TokenIsPlaintext := IsPlain;
          if IsPlain then
            Cfg.SourceToken := 'analyser.ini [SonarTokens], PLAINTEXT'
          else
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

      // sonar.host.url wird aus dieser Datei NICHT uebernommen. Sie liegt
      // IM gescannten Repository und ist damit fremdbestimmt: ein
      // geklontes Projekt konnte so den Host des Nutzers ueberstimmen,
      // waehrend der Token weiterhin aus dessen Env/INI kam - der Token
      // ging dann als 'Authorization: Bearer' an den vom Repo genannten
      // Server (2026-08-08 mit Mitschnitt reproduziert). Genau aus diesem
      // Grund wird sonar.token hier schon immer ignoriert; fuer den Host
      // gilt dieselbe Begruendung. Der sonar-scanner liest die Datei
      // ohnehin selbst - SCA braucht den Host nur fuer --sonar-test.
      if SameText(K, 'sonar.host.url') then
      begin
        if (Cfg.HostUrl = '') and (Cfg.IgnoredRepoHost = '') then
          Cfg.IgnoredRepoHost := V;
      end
      else if (Cfg.ProjectKey = '') and SameText(K, 'sonar.projectKey') then
      begin
        Cfg.ProjectKey := V;
        Cfg.SourceProjectKey := 'sonar-project.properties';
      end
      else if (Cfg.Organization = '') and SameText(K, 'sonar.organization') then
        Cfg.Organization := V
      else if (Cfg.Branch = '') and SameText(K, 'sonar.branch.name') then
        Cfg.Branch := V;
      // 'sonar.sourceMapping' war SCA-erfunden (kein echter Sonar-Key) und
      // hatte keinen Konsumenten - 2026-08-08 entfernt.
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
  // CLI.ConfigPath ist der Fallback, damit der Record selbsttragend ist:
  // bis 2026-08-08 setzte uConsoleRunner das Feld, Resolve las es nie, und
  // --sonar-config wirkte allein ueber den Parameter. Ein kuenftiger
  // Aufrufer, der nur den Record fuellt, waere wortlos ignoriert worden.
  // Der explizite Parameter behaelt Vorrang.
  IniPath := AnalyserIniPath;
  if IniPath = '' then IniPath := CLI.ConfigPath;
  if IniPath = '' then IniPath := DefaultIniPath;
  ReadFromIni(IniPath, Result);
end;

class procedure TSonarConfigResolver.StoreToken(const FileName, TokenRef,
  PlainTextToken: string);
var
  Ini    : TMemIniFile;
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
  //
  // EncodeBytesToString, NICHT Encode: die TBytes-Ueberladung von Encode
  // liefert wieder TBytes (System.NetEncoding:53) und nicht string. Bis
  // 2026-08-08 stand hier Encode - der Zweig haette auf JEDER
  // Nicht-Windows-Plattform mit E2010 gebrochen, gemerkt hat es niemand,
  // weil ihn hier nie ein Compiler zu sehen bekommt.
  Hex := 'PT:' + TNetEncoding.Base64.EncodeBytesToString(
    TEncoding.UTF8.GetBytes(PlainTextToken));
  {$ENDIF}

  // TMemIniFile haelt Writes in-memory bis UpdateFile aufgerufen wird.
  // Vorher: TIniFile schrieb sofort via WritePrivateProfileString - das
  // hat Win-Default-Encoding (typisch UTF-16 LE auf Win10+), kollidiert
  // dann mit unserem TMemIniFile-Reader. Beides UTF-8 ohne BOM via
  // TMemIniFile haelt die Datei konsistent.
  // TCommentPreservingIni statt TMemIniFile (2026-08-21): FileName ist in
  // aller Regel die analyser.ini, und die traegt zu jedem Schluessel einen
  // Erklaerblock. TMemIniFile.UpdateFile schreibt die Datei aus seinem
  // Speichermodell neu und kennt darin keine Kommentare - ein einziges
  // Token-Speichern haette die ganze Dokumentation geloescht. Das
  // Encoding-Argument von oben gilt unveraendert: UTF-8 ohne BOM, jetzt
  // vom Schreiber fest gesetzt.
  Ini := TCommentPreservingIni.Create(FileName);
  try
    Ini.WriteString('SonarTokens', TokenRef, Hex);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

class function TSonarConfigResolver.LoadToken(const FileName,
  TokenRef: string): string;
var
  Dummy : Boolean;
begin
  Result := LoadToken(FileName, TokenRef, Dummy);
end;

class function TSonarConfigResolver.LoadToken(const FileName,
  TokenRef: string; out APlaintext: Boolean): string;
var
  Ini : TMemIniFile;
  Hex : string;
  Cipher : TBytes;
begin
  Result := '';
  APlaintext := False;
  if (FileName = '') or (TokenRef = '') or not TFile.Exists(FileName) then Exit;

  Ini := TMemIniFile.Create(FileName, TEncoding.UTF8);
  try
    Hex := Trim(Ini.ReadString('SonarTokens', TokenRef, ''));
  finally
    Ini.Free;
  end;
  if Hex = '' then Exit;

  if StartsText('PT:', Hex) then
  begin
    // Non-Windows-Plaintext-Fallback. Auch unter Windows lesbar (kopierte
    // INI), deshalb wird der Aufrufer ueber APlaintext informiert.
    try
      Result := TEncoding.UTF8.GetString(
        TNetEncoding.Base64.DecodeStringToBytes(Copy(Hex, 4, MaxInt)));
      APlaintext := Result <> '';
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
    // noinspection StringTo8BitCast
    // gethostbyname ist WinSock-Legacy-API mit PAnsiChar; Cast ist intentional.
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

type
  // Traeger fuer den Zertifikats-Callback. OnValidateServerCertificate ist
  // ein 'of object'-Methodenzeiger - eine anonyme Methode laesst sich dort
  // NICHT zuweisen, deshalb dieses Miniobjekt.
  TInsecureCertAcceptor = class
    procedure AcceptAny(const Sender: TObject; const ARequest: TURLRequest;
      const Certificate: TCertificate; var Accepted: Boolean);
  end;

procedure TInsecureCertAcceptor.AcceptAny(const Sender: TObject;
  const ARequest: TURLRequest; const Certificate: TCertificate;
  var Accepted: Boolean);
begin
  Accepted := True;
end;

// ---- Antwort-Auswertung ----
// Die Stufen des Health-Checks haben ihre Antworten bis 2026-08-08 per
// Pos() im ROHTEXT geprueft ('"valid":true'). Damit entschied die
// Serialisierung ueber das Ergebnis: mit einem Leerzeichen hinter dem
// Doppelpunkt - wie es jeder pretty-printende Proxy oder ein Gateway
// liefert - scheiterte die Pruefung, ohne Leerzeichen gelang sie.
// Semantisch identische Antworten, entgegengesetztes Urteil. Deshalb
// hier echtes Parsen.
//
// (Zeilenkommentare mit Absicht: ein JSON-Beispiel im Text wuerde einen
//  geschweiften Blockkommentar an seiner schliessenden Klammer vorzeitig
//  beenden - Delphi schachtelt { } nicht.)

function JsonStrField(const Body, FieldName: string; out Value: string): Boolean;
// Liest ein String-Feld der obersten Ebene. False = kein gueltiges JSON
// oder Feld fehlt (der Aufrufer meldet dann den Rohtext als Detail).
var
  V : TJSONValue;
begin
  Result := False;
  Value  := '';
  V := TJSONObject.ParseJSONValue(Body);
  if V = nil then Exit;
  try
    if V is TJSONObject then
      Result := TJSONObject(V).TryGetValue<string>(FieldName, Value);
  finally
    V.Free;
  end;
end;

function JsonBoolFieldIsTrue(const Body, FieldName: string): Boolean;
var
  V : TJSONValue;
  B : Boolean;
begin
  Result := False;
  V := TJSONObject.ParseJSONValue(Body);
  if V = nil then Exit;
  try
    if (V is TJSONObject) and TJSONObject(V).TryGetValue<Boolean>(FieldName, B) then
      Result := B;
  finally
    V.Free;
  end;
end;

function JsonArrayHasKey(const Body, ArrayName, KeyValue: string): Boolean;
// Sucht in <ArrayName>[] ein Objekt mit "key" = KeyValue.
var
  V   : TJSONValue;
  Arr : TJSONArray;
  El  : TJSONValue;
  S   : string;
begin
  Result := False;
  V := TJSONObject.ParseJSONValue(Body);
  if V = nil then Exit;
  try
    if not (V is TJSONObject) then Exit;
    if not TJSONObject(V).TryGetValue<TJSONArray>(ArrayName, Arr) then Exit;
    for El in Arr do
      if (El is TJSONObject) and TJSONObject(El).TryGetValue<string>('key', S)
         and (S = KeyValue) then
        Exit(True);
  finally
    V.Free;
  end;
end;

function HttpGet(const Url, Token: string; Insecure: Boolean;
  out StatusCode: Integer; out Body: string): Boolean;
// Einfacher HTTP-GET mit Bearer-Auth. Liefert True wenn der Request
// durchlief (auch bei 4xx/5xx); False bei Network-Layer-Fehler.
var
  Client   : THTTPClient;
  Req      : IHTTPRequest;
  Resp     : IHTTPResponse;
  Acceptor : TInsecureCertAcceptor;
begin
  Result := False;
  StatusCode := 0;
  Body := '';
  Acceptor := nil;
  Client := THTTPClient.Create;
  try
    if Insecure then
    begin
      // Das ist der Zweck des Schalters: ein selbstsigniertes bzw. nicht
      // vertrauenswuerdiges Serverzertifikat akzeptieren. Bis 2026-08-08
      // stand hier NUR eine Protokoll-Liste (TLS11..TLS13) - die hat mit
      // Zertifikatsvertrauen nichts zu tun, der Schalter war also ein
      // No-op gegen selbstsignierte Server (gemessen: identische
      // ENetHTTPCertificateException mit und ohne Flag) und schaltete
      // nebenbei das abgekuendigte TLS 1.1 frei. Beides behoben: der
      // Vertrauens-Callback macht die Ausnahme, die Protokoll-Wahl
      // bleibt beim sicheren Plattform-Default.
      Acceptor := TInsecureCertAcceptor.Create;
      Client.OnValidateServerCertificate := Acceptor.AcceptAny;
    end;
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
    Acceptor.Free;   // erst NACH dem Client - er haelt den Callback
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
    var SrvStatus : string;
    JsonStrField(Body, 'status', SrvStatus);
    if Ok and (Status = 200) and SameText(SrvStatus, 'UP') then
    begin
      Stage := MakeStage('HTTP /api/system/status: UP',
        True, '', Sw.ElapsedMilliseconds);
    end
    else if Ok and (Status = 200) and SameText(SrvStatus, 'STARTING') then
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
    if Ok and (Status = 200) and JsonBoolFieldIsTrue(Body, 'valid') then
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

    // Stage 5: Project-Lookup.
    // Erste Stufe: /api/projects/search - liefert 200+leeres Array wenn das
    // Project nicht existiert, 403 wenn User keine Browse-Permission hat,
    // 200+Treffer wenn alles OK.
    // Fallback bei 403: /api/components/show - der unterscheidet sauber
    // zwischen 404 (Project existiert nicht) und 403 (existiert, aber kein
    // Zugriff). Dadurch kann die Fehlermeldung den User auf die richtige
    // Aktion fuehren (Project anlegen vs. Permission setzen).
    Sw := TStopwatch.StartNew;
    Url := Cfg.HostUrl + '/api/projects/search?projects=' +
           TNetEncoding.URL.Encode(Cfg.ProjectKey);
    // SonarCloud ist mandantenfaehig und verlangt den Organization-Key an
    // diesem Endpunkt; ohne ihn antwortet es 400 und der Check meldete
    // "Project not found" fuer ein existierendes Projekt. Bis 2026-08-08
    // wurde Cfg.Organization ueberall eingesammelt und nirgends benutzt -
    // das hier ist die einzige Stelle, an der er hingehoert.
    if Cfg.Organization <> '' then
      Url := Url + '&organization=' + TNetEncoding.URL.Encode(Cfg.Organization);
    Ok := HttpGet(Url, Cfg.Token, Cfg.Insecure, Status, Body);
    Sw.Stop;
    if Ok and (Status = 200) and
       JsonArrayHasKey(Body, 'components', Cfg.ProjectKey) then
      Stage := MakeStage('Project access: ' + Cfg.ProjectKey + ' (visible)',
        True, '', Sw.ElapsedMilliseconds)
    else if Ok and (Status = 200) then
      Stage := MakeStage('Project access: ' + Cfg.ProjectKey + ' (not found)',
        False, 'Project does not exist. Create at ' + Cfg.HostUrl +
               '/projects or POST /api/projects/create.',
        Sw.ElapsedMilliseconds)
    else if Ok and (Status = 403) then
    begin
      // Disambiguiere: /api/components/show liefert 404 fuer
      // "Project existiert nicht" und 403 fuer "existiert, aber kein
      // Zugriff". /projects/search wirft beides als 403 ueber den selben
      // Zaun.
      var ShowUrl    : string;
      var ShowStatus : Integer;
      var ShowBody   : string;
      var ShowOk     : Boolean;
      ShowUrl := Cfg.HostUrl + '/api/components/show?component=' +
                 TNetEncoding.URL.Encode(Cfg.ProjectKey);
      ShowOk := HttpGet(ShowUrl, Cfg.Token, Cfg.Insecure, ShowStatus, ShowBody);
      if ShowOk and (ShowStatus = 404) then
        Stage := MakeStage('Project access: ' + Cfg.ProjectKey + ' (not found)',
          False, 'Project does not exist on ' + Cfg.HostUrl + '. ' +
                 'Create at ' + Cfg.HostUrl + '/projects or POST ' +
                 '/api/projects/create?project=' + Cfg.ProjectKey,
          Sw.ElapsedMilliseconds)
      else if ShowOk and (ShowStatus = 200) then
        // ERFOLG, nicht Fehler: components/show mit 200 BEWEIST, dass der
        // Token das Projekt sehen darf. Die 403 davor kam von
        // /api/projects/search, das 'Administer System' verlangt - ein
        // ganz normaler projektgebundener Token bekommt sie immer.
        //
        // Bis 2026-08-08 meldete der Check hier trotzdem FAIL samt
        // Exit 99 und schickte den Betreiber los, eine Browse-Berechtigung
        // zu setzen, die nachweislich schon vorhanden war. Da
        // docs/sonar-setup.md Exit 0 als CI-Gate bewirbt, scheiterte
        // damit jede Pipeline, die sich korrekt an das
        // Least-Privilege-Prinzip haelt.
        Stage := MakeStage('Project access: ' + Cfg.ProjectKey +
          ' (visible; projects/search benoetigt Admin-Rechte)',
          True, '', Sw.ElapsedMilliseconds)
      else
        Stage := MakeStage('Project access: 403 Forbidden',
          False, 'Project ''' + Cfg.ProjectKey + ''' is not visible to ' +
                 'this token - either the project does not exist OR the ' +
                 'token user lacks Browse permission. Check ' + Cfg.HostUrl +
                 '/projects after logging in as the token owner.',
          Sw.ElapsedMilliseconds);
    end
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
