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
//     "koennte", nicht "ist kein Netzaufruf";
//   * Testcode (TestPathReason, der Adapter fragt mit Dateiname und
//     Zeilen): ein Test vergleicht die Adresse oft woertlich - keine Hilfe;
//     ein Testordner allein macht noch keinen Testcode (rwE30, jvcl\tests).

interface

uses
  System.Classes,    // TStrings
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

    // Ist die Datei AFileName (Text ALines, nil erlaubt) Testcode? Dann der
    // Grund, sonst ''. Eine URL in Testcode ist meist eine Vorgabe, die ein
    // Test woertlich vergleicht - oft in einer ANDEREN Datei, die der
    // Planer nicht sieht, auch ueber die Laufzeit (rwE29, delphimvcframework
    // unittests\general\TestServer\TestServerControllerU.pas:1334/1522:
    // der Server liefert die Adresse, 'Assert.areEqual(''http://pippo.it/
    // 1234'', ..)' in TestClient\LiveServerTestU.pas schlug nach der
    // Ersetzung fehl). Nur eine Datei in einem Testordner (ein Verzeichnis
    // 'test', 'tests', 'unittest', 'unittests' oder auf '...tests' endend;
    // der naechste zur Datei zaehlt) kommt in Frage, und nur mit einem
    // Merkmal von Testcode (rwE30: unter jvcl\tests liegen Archiv-, Beispiel-
    // und Komponentenquellen - die Ordnerregel allein sperrte 20 Stellen
    // ohne Test):
    //   1. die Datei liegt direkt im Testordner (Indy Bubbles\boxtests);
    //   2. ein Verzeichnis darunter auf dem Weg zur Datei oder die Datei
    //      selbst traegt 'test' im Namen (unittests\general\TestServer,
    //      Indy Test\Protocols\IdTestHttp.pas - die Tests von Indy erben
    //      von TIdTest aus IdTest, die Unit nennt kein Framework);
    //   3. die Unit selbst ist Test-Code: Code (kein Kommentar, kein String)
    //      nennt eine Unit oder Basisklasse eines Test-Frameworks (DUnit,
    //      DUnitX, FPCUnit, mORMot: TestFramework, TTestCase, [TestFixture]
    //      ...; TEST_MARKS);
    //   4. im Verzeichnis der Datei oder darueber bis zum Testordner liegt
    //      ein Testprojekt: eine Projekt- oder Gruppendatei (.dpr .lpr .dpk
    //      .lpk .dproj .lpi .bpg .groupproj) mit 'test' im Namen
    //      (cnwizards Test\..\AICoder\AICoderTest.dpr) oder eine .dpr/.lpr,
    //      deren Kopf ein Test-Merkmal nennt.
    // Was der Planer nicht lesen kann, sperrt wie bisher mit dem Grund des
    // Testordners: ein Netzpfad (uRdxPaths.IsNetworkPath), mehr als
    // MAX_TEST_LEVELS Verzeichnisse bis zum Testordner, mehr als
    // MAX_DIR_ENTRIES Eintraege in einem davon, mehr als MAX_PROJECT_READS
    // Projektkoepfe oder ein Kopf, der sich nicht lesen laesst. Der Adapter
    // (uRdxFixTable.PlanHttps) fragt das mit Dateiname und Zeilen des Funds.
    class function TestPathReason(const AFileName: string;
      ALines: TStrings): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,   // PosEx, StartsStr, EndsStr (FPC-Pruefstand: keine
                     // String-Helfer)
  uRefactorInfo,     // TRefactorSpan.Make
  uRdxPaths,         // IsNetworkPath (TestPathReason liest nie aus dem Netz)
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
  // Testordner (TestPathReason), klein.
  TEST_DIRS: array[0..3] of string = ('test', 'tests', 'unittest',
    'unittests');
  // 'test' im Namen eines Verzeichnisses unter dem Testordner, der Datei
  // oder eines Projekts (TestServer, IdTestHttp.pas, AICoderTest.dpr) -
  // Merkmale 2 und 4.
  TEST_WORD = 'test';
  // Merkmale von Testcode, klein (Merkmal 3, in .dpr/.lpr-Koepfen 4): Units
  // von DUnit, DUnitX, FPCUnit und mORMot und ihre Basisklassen bzw. das
  // Attribut von DUnitX. Ganze Namen (HasMark): 'dunitx.testframework'
  // ueber 'testframework' hinter dem Punkt ist eigens genannt.
  TEST_MARKS: array[0..11] of string = ('testframework',
    'dunitx.testframework', 'fpcunit', 'testregistry', 'guitestrunner',
    'texttestrunner', 'consoletestrunner', 'mormot.core.test', 'syntests',
    'ttestcase', 'tsyntestcase', 'testfixture');
  // Projekt- und Gruppendateien (Merkmal 4), klein; nur die ersten beiden
  // (Programme) liest TestPathReason auch (PROJECT_HEAD_BYTES).
  PROJECT_EXTS: array[0..7] of string = ('.dpr', '.lpr', '.dpk', '.lpk',
    '.dproj', '.lpi', '.bpg', '.groupproj');
  READ_EXTS: array[0..1] of string = ('.dpr', '.lpr');
  // Deckel des Plattenblicks je Aufruf (Hauptthread, Menueaufbau): so viele
  // Verzeichnisse vom Ordner der Datei bis zum Testordner, so viele
  // Eintraege je Verzeichnis, so viele Projektkoepfe zu je so vielen Bytes.
  // Darueber hinaus sperrt TestPathReason - lieber keine Hilfe als eine,
  // die einen Test bricht.
  MAX_TEST_LEVELS    = 8;
  MAX_DIR_ENTRIES    = 4096;
  MAX_PROJECT_READS  = 16;
  PROJECT_HEAD_BYTES = 16384;
  // Merkmal 1 und alles, was der Planer nicht lesen kann.
  R_HTTPS_TEST_DIR = 'the file is in the test folder "%s" - a test may '
    + 'compare this address literally (also from another file); decide by '
    + 'hand';
  // Merkmal 2: %s das Verzeichnis bzw. die Datei, %s der Testordner.
  R_HTTPS_TEST_NAME = 'the name "%s" in the test folder "%s" marks test '
    + 'code - a test may compare this address literally (also from another '
    + 'file); decide by hand';
  // Merkmal 3: %s das Merkmal (klein, wie TEST_MARKS), %s der Testordner.
  R_HTTPS_TEST_UNIT = 'the unit is test code ("%s") in the test folder '
    + '"%s" - a test may compare this address literally; decide by hand';
  // Merkmal 4: %s die Projektdatei, %s der Testordner.
  R_HTTPS_TEST_PROJECT = 'the test project "%s" lies beside the file or '
    + 'above it in the test folder "%s" - a test may compare this address '
    + 'literally (also from another file); decide by hand';
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
    if (AHost = S) or EndsStr('.' + S, AHost) then
      Exit(True);
end;

function EndsWithAny(const AHost: string; const ASuffixes: array of string): Boolean;
var
  S : string;
begin
  Result := False;
  for S in ASuffixes do
    if EndsStr(S, AHost) then
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
  while EndsStr('.', Host) do
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

{ ---- Testcode (TestPathReason) ---- }

type
  // Was der Plattenblick in einem Verzeichnis fand (TestProjectIn).
  TTestDirLook = (tdNone, tdProject, tdUnread);

// Steht AMark (klein, auch mit Punkten: 'mormot.core.test') in ALow als
// ganzer Name? Davor kein Bezeichnerzeichen und kein Punkt ('x.ttestcase'
// ist ein anderer Name), dahinter kein Bezeichnerzeichen.
function HasMark(const ALow, AMark: string): Boolean;
var
  p, Stop : Integer;
begin
  Result := False;
  p := PosEx(AMark, ALow, 1);
  while p > 0 do
  begin
    Stop := p + Length(AMark);
    if ((p = 1) or not (IsIdentChar(ALow[p - 1]) or (ALow[p - 1] = '.')))
       and ((Stop > Length(ALow)) or not IsIdentChar(ALow[Stop])) then
      Exit(True);
    p := PosEx(AMark, ALow, p + 1);
  end;
end;

// Das erste Merkmal aus TEST_MARKS in ALow, sonst ''.
function TestMarkIn(const ALow: string): string;
var
  S : string;
begin
  Result := '';
  for S in TEST_MARKS do
    if HasMark(ALow, S) then
      Exit(S);
end;

// Das erste Merkmal aus TEST_MARKS im Code von ALines, sonst ''. Je Zeile
// Kommentare, Strings und Direktiven als Leerzeichen - ein Merkmal dort
// zaehlt nicht; die Merkmale stehen je in einer Zeile.
function CodeMarkIn(ALines: TStrings): string;
var
  Map  : TRdxCodeMap;
  L, c : Integer;
  Line : string;
begin
  Result := '';
  Map := TRdxCodeMap.Acquire(ALines);
  try
    for L := 1 to Map.LineCount do
    begin
      Line := Map.Raw(L);
      for c := 1 to Length(Line) do
        if not Map.IsCode(L, c) then
          Line[c] := ' ';
      Result := TestMarkIn(LowerCase(Line));
      if Result <> '' then
        Exit;
    end;
  finally
    TRdxCodeMap.Release(Map);
  end;
end;

// Der Kopf (die ersten PROJECT_HEAD_BYTES) der Datei APath klein; Bytes
// ueber 127 als Leerzeichen - die Merkmale sind ASCII, die Kodierung der
// Datei zaehlt nicht. False, wenn sie sich nicht lesen laesst.
function ProjectHead(const APath: string; out ALow: string): Boolean;
var
  FS    : TFileStream;
  Bytes : TBytes;
  i     : Integer;
begin
  Result := False;
  ALow := '';
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Bytes, PROJECT_HEAD_BYTES);
      SetLength(Bytes, FS.Read(Bytes[0], PROJECT_HEAD_BYTES));
    finally
      FS.Free;
    end;
  except
    on EStreamError do
      Exit;
  end;
  SetLength(ALow, Length(Bytes));
  for i := 0 to High(Bytes) do
    if Bytes[i] < 128 then
      ALow[i + 1] := Char(Bytes[i])
    else
      ALow[i + 1] := ' ';
  ALow := LowerCase(ALow);
  Result := True;
end;

// Merkmal 4 in EINEM Verzeichnis ADir (nicht rekursiv): eine Projekt- oder
// Gruppendatei mit 'test' im Namen bzw. eine .dpr/.lpr mit einem Test-
// Merkmal im Kopf - tdProject, ihr Name in AName. tdUnread, wenn ein
// Deckel erschoepft ist (MAX_DIR_ENTRIES, MAX_PROJECT_READS - AReads zaehlt
// ueber alle Verzeichnisse eines Aufrufs) oder ein Kopf sich nicht lesen
// laesst; tdNone sonst, auch fuer ein Verzeichnis, das es nicht gibt.
function TestProjectIn(const ADir: string; var AReads: Integer;
  out AName: string): TTestDirLook;
var
  SR       : TSearchRec;
  Entries  : Integer;
  Low, Ext : string;
  Head     : string;
begin
  Result := tdNone;
  AName := '';
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, SR) <> 0 then
    Exit;
  try
    Entries := 0;
    repeat
      Inc(Entries);
      if Entries > MAX_DIR_ENTRIES then
        Exit(tdUnread);
      if (SR.Attr and faDirectory) <> 0 then
        Continue;
      Low := LowerCase(SR.Name);
      Ext := ExtractFileExt(Low);
      if not InList(Ext, PROJECT_EXTS) then
        Continue;
      AName := SR.Name;
      if Pos(TEST_WORD, ChangeFileExt(Low, '')) > 0 then
        Exit(tdProject);
      if InList(Ext, READ_EXTS) then
      begin
        Inc(AReads);
        if (AReads > MAX_PROJECT_READS)
           or not ProjectHead(IncludeTrailingPathDelimiter(ADir) + SR.Name,
             Head) then
          Exit(tdUnread);
        if TestMarkIn(Head) <> '' then
          Exit(tdProject);
      end;
      AName := '';
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

// Die Glieder des Pfads AFileName, getrennt an '\' und '/' ('D:\a/b.pas'
// -> 'D:', 'a', 'b.pas'; leere Glieder bleiben).
function PathParts(const AFileName: string): TArray<string>;
var
  i, From : Integer;
begin
  Result := nil;
  From := 1;
  for i := 1 to Length(AFileName) + 1 do
    if (i > Length(AFileName)) or CharInSet(AFileName[i], ['\', '/']) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Copy(AFileName, From, i - From);
      From := i + 1;
    end;
end;

// Die Glieder AParts[0..ALast] als Pfad ('D:', 'a', 'b' -> 'D:\a\b').
function JoinedPath(const AParts: TArray<string>; ALast: Integer): string;
var
  i : Integer;
begin
  Result := AParts[0];
  for i := 1 to ALast do
    Result := Result + '\' + AParts[i];
end;

{ TRdxHttpsFix }

class function TRdxHttpsFix.TestPathReason(const AFileName: string;
  ALines: TStrings): string;
var
  Parts        : TArray<string>;
  i, Anchor    : Integer;
  Low, Mark    : string;
  Project      : string;
  Reads        : Integer;
begin
  Result := '';
  Parts := PathParts(AFileName);
  // Der Testordner: das Verzeichnis mit Testnamen, das der Datei am
  // naechsten liegt. Das letzte Glied ist die Datei selbst - nur
  // Verzeichnisse zaehlen.
  Anchor := -1;
  for i := 0 to High(Parts) - 1 do
  begin
    Low := LowerCase(Parts[i]);
    if InList(Low, TEST_DIRS)
       or ((Length(Low) > 5) and (Copy(Low, Length(Low) - 4, 5) = 'tests')) then
      Anchor := i;
  end;
  if Anchor < 0 then Exit;
  // 1. Die Datei liegt direkt im Testordner.
  if Anchor = High(Parts) - 1 then
    Exit(_(R_HTTPS_TEST_DIR, [Parts[Anchor]]));
  // 2. Ein Verzeichnis darunter oder die Datei traegt 'test' im Namen.
  for i := Anchor + 1 to High(Parts) do
    if Pos(TEST_WORD, LowerCase(Parts[i])) > 0 then
      Exit(_(R_HTTPS_TEST_NAME, [Parts[i], Parts[Anchor]]));
  // 3. Die Unit selbst ist Test-Code.
  if ALines <> nil then
  begin
    Mark := CodeMarkIn(ALines);
    if Mark <> '' then
      Exit(_(R_HTTPS_TEST_UNIT, [Mark, Parts[Anchor]]));
  end;
  // 4. Ein Testprojekt vom Verzeichnis der Datei aufwaerts bis zum
  // Testordner - nur von einer lokalen Platte und unter den Deckeln.
  if IsNetworkPath(AFileName) or (High(Parts) - Anchor > MAX_TEST_LEVELS) then
    Exit(_(R_HTTPS_TEST_DIR, [Parts[Anchor]]));
  Reads := 0;
  for i := High(Parts) - 1 downto Anchor do
    case TestProjectIn(JoinedPath(Parts, i), Reads, Project) of
      tdProject: Exit(_(R_HTTPS_TEST_PROJECT, [Project, Parts[Anchor]]));
      tdUnread:  Exit(_(R_HTTPS_TEST_DIR, [Parts[Anchor]]));
    end;
end;

class function TRdxHttpsFix.UrlReason(const AUrl: string): string;
begin
  Result := '';
  if not StartsStr(SCHEME_HTTP, AUrl) then
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
