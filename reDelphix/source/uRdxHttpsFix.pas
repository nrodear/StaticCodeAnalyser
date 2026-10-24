unit uRdxHttpsFix;

// reDelphix - Editorhilfe SCA115 HttpInsteadOfHttps, OHNE ToolsAPI und ohne
// Parser (Konzept_Editorhilfen_Regelliste_2026-10-11):
//   'http://host/pfad' -> 'https://host/pfad' (nur das Schema).
// Die Hilfe AENDERT das Verhalten (E2): der Server muss https auf dem
// Standardport koennen, sonst scheitert der Aufruf. Darum bietet sie nur an,
// was eindeutig ein Netzaufruf an einen benannten Rechner ist; im Zweifel
// keine Hilfe (Grundsatz wie in uRdxLineFixes):
//   * der Detektor meldet die Zeile des Literals und nennt die URL in der
//     Meldung (Plaintext HTTP URL 'url' ...); die Hilfe sucht genau dieses
//     Literal in der Zeile - nicht gefunden (Zeile verschoben, Kommentar,
//     Teil eines laengeren Strings) oder zweimal (mehrdeutig): keine Hilfe;
//   * Port, Zugangsdaten, IP-Adresse, IPv6, Platzhalter im Host und ein
//     Host ohne Punkt (Intranet): https auf dem selben Port oder mit dem
//     selben Zertifikat ist dort nicht zu erwarten - keine Hilfe;
//   * localhost/Loopback und reservierte Doku-Hosts sind lokal, Namespace-
//     Hosts (w3.org, xmlsoap.org, ...) Identitaeten - keine Hilfe;
//   * ein Namespace-/Schema-Marker ('xmlns', 'namespace', 'schema', '/ns/')
//     irgendwo in der Adresse oder vor ihr auf der Zeile sperrt AUS
//     VORSICHT: der Detektor (uRestHttpSecurity, Voll-Review 2026-09-13)
//     meldet solche Adressen absichtlich als echte Endpunkte
//     ('.../schemas/v1/users', 'FSchemaEndpoint := ...'), die Hilfe kann
//     eine Kennung davon nicht unterscheiden. Der Grund sagt darum
//     "koennte", nicht "ist kein Netzaufruf".

interface

uses
  uRdxBufferMath,    // TRdxEdit
  uRdxCodeMap;       // TRdxCodeMap

type
  // Der Planer von SCA115 (Form TRdxMapPlanner, uRdxFixRunner).
  TRdxHttpsFix = class
  public
    // Das Schema des Literals aus der Meldung auf ALine: 'http://' ->
    // 'https://' (NewText), sonst der Grund.
    class function Https(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // Der Grund, warum die URL (ohne Anfuehrungszeichen) keine Hilfe
    // bekommt, oder '' - reine Textfrage ueber Schema und Host.
    class function UrlReason(const AUrl: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxText;          // _(), MsgMovedSuffix, MsgLineStartsInCommentOrString (E29)

const
  SPAN_115     = 'sca115';
  SCHEME_HTTP  = 'http://';
  SCHEME_HTTPS = 'https://';
  QUOTE_CHAR   = '''';
  // Hosts, die nie ein Fernziel sind.
  LOCAL_HOSTS: array[0..2] of string = ('localhost', 'host.docker.internal',
    'unix');
  LOCAL_SUFFIXES: array[0..5] of string = ('.localhost', '.example',
    '.test', '.invalid', '.local', '.internal');
  RESERVED_HOSTS: array[0..2] of string = ('example.com', 'example.net',
    'example.org');
  // Namespace- und Schema-Hosts; die Marker duerfen auch im Pfad stehen.
  NAMESPACE_HOSTS: array[0..4] of string = ('w3.org', 'xmlsoap.org',
    'tempuri.org', 'purl.org', 'opengis.net');
  NAMESPACE_MARKERS: array[0..3] of string = ('xmlns', 'namespace',
    'schema', '/ns/');
  NOT_PLAIN_MARKERS: array[0..2] of string = ('@', ':', '[');
  // Die Gruende als englische msgids (E29), uebersetzt mit _() aus uRdxText;
  // Deutsch und Franzoesisch in i18n/de.po und i18n/fr.po. Das Ende
  // ' - Zeile verschoben? ...' haengt MsgMovedSuffix an, 'die Zeile beginnt
  // in einem Kommentar oder String' ist MsgLineStartsInCommentOrString.
  R_HTTPS_NO_URL    = 'no "http://" address in the message';
  R_HTTPS_MOVED     = 'the address is not a literal of its own at the '
    + 'reported place';
  R_HTTPS_AMBIGUOUS = 'the address appears more than once on the line - '
    + 'ambiguous';
  R_HTTPS_NO_HOST   = 'no host name in the address';
  R_HTTPS_USERINFO  = 'the address contains credentials, a port or an IPv6 '
    + 'address - https would not simply work there';
  R_HTTPS_ODD_HOST  = 'the host name is not a fixed name (placeholder or '
    + 'special characters)';
  R_HTTPS_IP        = 'an IP address rarely has a matching certificate';
  R_HTTPS_LOCAL     = 'a local or internal host - not a safe remote target '
    + 'for https';
  R_HTTPS_NAMESPACE = 'namespace or schema marker in or before the address - '
    + 'could be an identifier rather than a network call, no help out of '
    + 'caution';

type
  THttpsKind = (hkOk, hkNoHost, hkUserInfo, hkOdd, hkIp, hkLocal, hkNamespace);

// Der Host der URL: nach dem Schema bis '/', '?' oder '#'; klein.
function HostOf(const AUrl: string): string;
var
  Rest : string;
  p    : Integer;
begin
  Rest := LowerCase(Copy(AUrl, Length(SCHEME_HTTP) + 1, MaxInt));
  p := 1;
  while (p <= Length(Rest)) and not CharInSet(Rest[p], ['/', '?', '#']) do
    Inc(p);
  Result := Copy(Rest, 1, p - 1);
end;

// AHost ist ein Name der Liste oder eine Subdomain davon ('a.example.com').
function UnderAny(const AHost: string; const ANames: array of string): Boolean;
var
  S : string;
begin
  Result := False;
  for S in ANames do
    if (AHost = S) or AHost.EndsWith('.' + S) then
      Exit(True);
end;

function EndsWithAny(const AHost: string; const ASuffixes: array of string): Boolean;
var
  S : string;
begin
  Result := False;
  for S in ASuffixes do
    if AHost.EndsWith(S) then
      Exit(True);
end;

function HasAny(const AText: string; const AMarkers: array of string): Boolean;
var
  S : string;
begin
  Result := False;
  for S in AMarkers do
    if Pos(S, AText) > 0 then
      Exit(True);
end;

// Nur Buchstaben, Ziffern, '-' und '.' im Host.
function PlainHost(const AHost: string): Boolean;
var
  i : Integer;
begin
  Result := AHost <> '';
  for i := 1 to Length(AHost) do
    if not CharInSet(AHost[i], ['a'..'z', '0'..'9', '-', '.']) then
      Exit(False);
end;

// Nur Ziffern und Punkte: eine IPv4-Adresse.
function LooksLikeIp(const AHost: string): Boolean;
var
  i : Integer;
begin
  Result := AHost <> '';
  for i := 1 to Length(AHost) do
    if not CharInSet(AHost[i], ['0'..'9', '.']) then
      Exit(False);
end;

function ClassifyUrl(const AUrl: string): THttpsKind;
var
  Host, Low : string;
begin
  Low := LowerCase(AUrl);
  Host := HostOf(AUrl);
  while Host.EndsWith('.') do
    Host := Copy(Host, 1, Length(Host) - 1);
  if Host = '' then
    Result := hkNoHost
  else if HasAny(Host, NOT_PLAIN_MARKERS) then
    Result := hkUserInfo
  else if not PlainHost(Host) then
    Result := hkOdd
  else if HasAny(Low, NAMESPACE_MARKERS) or UnderAny(Host, NAMESPACE_HOSTS) then
    Result := hkNamespace
  else if LooksLikeIp(Host) then
    Result := hkIp
  else if (Pos('.', Host) = 0) or InList(Host, LOCAL_HOSTS)
     or EndsWithAny(Host, LOCAL_SUFFIXES) or UnderAny(Host, RESERVED_HOSTS) then
    Result := hkLocal
  else
    Result := hkOk;
end;

{ ---- Treffer in der Zeile ---- }

// Beginnt bei APos ein eigenes String-Literal mit genau AUrl als Inhalt?
// Das oeffnende Quote ist der Anfang eines Strings (davor kein String), alle
// Zeichen und das schliessende Quote sind String, dahinter kein Quote.
function IsWholeLiteral(AMap: TRdxCodeMap; ALine, APos: Integer;
  const AL, AUrl: string): Boolean;
var
  Last, i : Integer;
begin
  Last := APos + Length(AUrl) + 1;   // das schliessende Quote
  Result := (Last <= Length(AL)) and (AL[APos] = QUOTE_CHAR)
    and (Copy(AL, APos + 1, Length(AUrl)) = AUrl) and (AL[Last] = QUOTE_CHAR)
    and ((APos = 1) or (AMap.ClassAt(ALine, APos - 1) <> 's'))
    and ((Last = Length(AL)) or (AL[Last + 1] <> QUOTE_CHAR));
  if not Result then Exit;
  for i := APos to Last do
    if AMap.ClassAt(ALine, i) <> 's' then
      Exit(False);
end;

// Zahl der eigenen Literale AUrl auf der Zeile; APos die erste Stelle.
function CountLiterals(AMap: TRdxCodeMap; ALine: Integer;
  const AL, AUrl: string; out APos: Integer): Integer;
var
  i : Integer;
begin
  Result := 0;
  APos := 0;
  for i := 1 to Length(AL) do
    if IsWholeLiteral(AMap, ALine, i, AL, AUrl) then
    begin
      if Result = 0 then APos := i;
      Inc(Result);
    end;
end;

{ TRdxHttpsFix }

class function TRdxHttpsFix.UrlReason(const AUrl: string): string;
begin
  Result := '';
  if not AUrl.StartsWith(SCHEME_HTTP) then
    Exit(_(R_HTTPS_NO_URL));
  case ClassifyUrl(AUrl) of
    hkNoHost:    Result := _(R_HTTPS_NO_HOST);
    hkUserInfo:  Result := _(R_HTTPS_USERINFO);
    hkOdd:       Result := _(R_HTTPS_ODD_HOST);
    hkIp:        Result := _(R_HTTPS_IP);
    hkLocal:     Result := _(R_HTTPS_LOCAL);
    hkNamespace: Result := _(R_HTTPS_NAMESPACE);
  end;
end;

class function TRdxHttpsFix.Https(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  L, Url : string;
  P, N   : Integer;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  Url := QuotedText(AMessage, QUOTE_CHAR);
  AReason := TRdxHttpsFix.UrlReason(Url);
  if AReason <> '' then Exit;
  if AMap.StartsInside(ALine) then
  begin
    AReason := MsgLineStartsInCommentOrString;
    Exit;
  end;
  L := AMap.Raw(ALine);
  N := CountLiterals(AMap, ALine, L, Url, P);
  if N = 0 then
    AReason := MsgMovedSuffix(_(R_HTTPS_MOVED))
  else if N > 1 then
    AReason := _(R_HTTPS_AMBIGUOUS)
  else if HasAny(LowerCase(Copy(L, 1, P - 1)), NAMESPACE_MARKERS) then
    AReason := _(R_HTTPS_NAMESPACE);
  if AReason <> '' then Exit;
  AEdit.Span := TRefactorSpan.Make(SPAN_115, ALine, P + 1, ALine,
    P + 1 + Length(SCHEME_HTTP));
  AEdit.Expected := SCHEME_HTTP;
  AEdit.NewText := SCHEME_HTTPS;
  Result := True;
end;

end.
