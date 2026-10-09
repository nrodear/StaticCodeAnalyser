unit uIpAddressScan;

// SCA200 HardcodedIpAddress / SCA201 HardcodedIpInConfig - der reine Teil:
// Grammatik, Klassifikation, Kandidatensuche und Kontext-Gates. Kein AST,
// keine Datei, keine Engine-Globals - derselbe Code laeuft im FPC-
// Pruefstand (Muster uParamNameScan, SCA199).
//
// GRAMMATIK (strikt, Konzept_HardcodedIp_2026-10-09 Abschnitt 4.1)
//   IPv4  vier Dezimal-Oktette 0..255 ohne fuehrende Nullen (RFC 3986
//         dec-octet). Davor kein [0-9A-Za-z_.], danach kein [0-9A-Za-z_]
//         und kein '.Ziffer' - das toetet Versionen und OIDs mit mehr als
//         vier Teilen ('1.3.6.1.4.1'), 'v1.2.3.4' und Tausenderzahlen.
//   IPv6  RFC 4291 2.2: hoechstens ein '::', Gruppen 1..4 Hex, eingebettete
//         IPv4 am Ende, Zone '%...' und '[...]:port'. Links kein
//         Wortzeichen ('std::', 'TFoo::Bar'), mindestens eine Dezimalziffer
//         ('dead::beef'), nicht 8 Gruppen zu je 2 Hex ohne '::' (MAC,
//         EUI-64, Hexdump).
//
// KLASSEN werden NUMERISCH bestimmt, nie ueber String-Praefixe (Lehre der
// Sonar-Historie: Praefix-Listen driften, '2001:0db8::' entging SCA115).
// Gemeldet werden nur privat, CGNAT und oeffentlich; Loopback,
// unspezifiziert, Broadcast, Netzmaske, Link-Local, Dokumentation,
// IETF-Protokollbloecke, Benchmark, Multicast und Reserviert nicht.
//
// GATES (aus der Korpusmessung, Konzept 4.3) arbeiten auf WORTTEILEN
// (CamelCase/Unterstrich getrennt), nicht auf Teilstrings: 'VERS' in
// 'SERVERS' oder 'dll' in einem URL-Pfad unterdrueckten in der Messung
// echte Funde.

interface

uses
  System.SysUtils, System.Classes;

type
  TIpFamily = (ifNone, ifV4, ifV6);

  // Klasse einer Adresse. IsReportable: nur ipcPrivate, ipcCgnat,
  // ipcPublic.
  TIpClass = (ipcPrivate, ipcCgnat, ipcPublic, ipcLoopback, ipcUnspecified,
    ipcBroadcast, ipcNetmask, ipcLinkLocal, ipcDocumentation, ipcProtocol,
    ipcBenchmark, ipcMulticast, ipcReserved);

  TIpv6Words = array[0..7] of Word;

  // Eine Adresse in einem Text (String-Literal bzw. INI-Wert).
  TIpHit = record
    Start   : Integer;     // 1-basiert, erstes Zeichen der Adresse
    Len     : Integer;     // Laenge der Adresse (ohne Zone, Port, Praefix)
    Text    : string;      // die Adresse, wie sie dasteht (ohne Zone)
    Family  : TIpFamily;
    V4      : Cardinal;    // ifV4: die Adresse; ifV6: ggf. eingebettete IPv4
    V6      : TIpv6Words;  // ifV6
    Cls     : TIpClass;
    HasPort : Boolean;     // ':port' bzw. ']:port' direkt dahinter
    HasCidr : Boolean;     // '/n' direkt dahinter
    InUrl   : Boolean;     // '://', '://[' oder ein UNC-Kopf '\\' direkt davor
  end;

  // Eine Adresse in einem Pascal-String-Literal.
  TCodeIpHit = record
    Pos    : Integer;      // Position des oeffnenden Quotes im Code (1-basiert)
    Hit    : TIpHit;
    Reason : string;       // '' = melden, sonst der Verzichtsgrund
  end;

  // Eine Adresse in einer INI-Zeile.
  TIniIpHit = record
    Line    : Integer;     // 1-basiert
    Section : string;
    Key     : string;      // '' bei einer Zeile ohne '='
    Hit     : TIpHit;
    Reason  : string;      // '' = melden, sonst der Verzichtsgrund
  end;

  TIpAddressScan = class
  public
    // Exakte Formen (ganzer String).
    class function TryParseIPv4(const S: string; out V: Cardinal): Boolean; static;
    class function TryParseIPv6(const S: string; out W: TIpv6Words): Boolean; static;

    // Klasse einer Adresse; IPv4-mapped und NAT64 nach der eingebetteten
    // IPv4.
    class function ClassifyV4(V: Cardinal): TIpClass; static;
    class function ClassifyV6(const W: TIpv6Words): TIpClass; static;
    class function IsReportable(C: TIpClass): Boolean; static;
    // Lesbare Klasse fuer den Meldetext ('private, RFC 1918'). IPv6 privat:
    // fc00::/7 'unique local', fec0::/10 'site-local'; IPv4-mapped und
    // NAT64 nach der eingebetteten IPv4.
    class function ClassLabel(const AHit: TIpHit): string; static;

    // Alle Adressen in AText, in Textreihenfolge (Grammatik und Grenzen,
    // noch ohne Kontext-Gates). Eine IPv4 innerhalb einer IPv6 zaehlt nicht
    // extra.
    class function FindAll(const AText: string): TArray<TIpHit>; static;

    // Wortteile, klein: Buchstabenfolgen, an Nicht-Buchstaben und an
    // CamelCase-Uebergaengen getrennt ('FRootDNS_NET' -> f, root, dns, net).
    class function WordParts(const AText: string): TArray<string>; static;

    // Kontext-Gates fuer eine Adresse im Text AText; AContextWords sind die
    // Wortteile des Kontexts (Pascal: Code der Zeile ohne Literale; INI:
    // der Schluessel). '' = melden, sonst ein kurzer Grund. Die Scanner
    // rechnen die textweiten Teile einmal je Text, nicht je Adresse.
    class function JudgeHit(const AHit: TIpHit; const AText: string;
      const AContextWords: TArray<string>): string; static;

    // Pascal-Text OHNE Kommentare (TDetectorUtils.StripFileComments-
    // KeepStrings): alle Adressen in String-Literalen, je Zeile und
    // Adresse einmal.
    class function ScanPascalCode(const ACode: string): TArray<TCodeIpHit>; static;

    // INI-Zeilen: ';'/'#'-Zeilen und Sektionskoepfe zaehlen nicht, sonst
    // der Wert hinter dem ersten '=' (ohne '=' die ganze Zeile). Je Zeile
    // und Adresse einmal.
    class function ScanIniLines(ALines: TStrings): TArray<TIniIpHit>; static;

    // Meldetexte (englisch, Teil der Fund-Identitaet).
    class function CodeMessage(const AHit: TIpHit): string; static;
    class function IniMessage(const AHit: TIniIpHit): string; static;
  end;

implementation

const
  // Kontextwoerter (Wortteile, klein).
  HOST_WORDS: array[0..22] of string = (
    'host', 'hostname', 'server', 'servers', 'ip', 'ips', 'addr', 'address',
    'url', 'uri', 'dns', 'proxy', 'gateway', 'endpoint', 'bind', 'listen',
    'remote', 'peer', 'socket', 'smtp', 'connect', 'connection', 'tcp');
  VERSION_WORDS: array[0..9] of string = (
    'version', 'ver', 'vers', 'verproc', 'versao', 'build', 'revision',
    'release', 'assembly', 'firmware');
  // Komposita, die auf einen Host-Stamm enden ('nameserver', 'DNSSERVER',
  // 'localhost') - WordParts trennt sie nicht.
  HOST_STEMS: array[0..7] of string = (
    'server', 'host', 'dns', 'proxy', 'gateway', 'endpoint', 'address', 'addr');
  OID_WORDS: array[0..1] of string = ('oid', 'oids');
  // INI-Schluessel mit Fliesstext (HeidiSQL-Funktionsdoku u. ae.).
  TEXT_WORDS: array[0..13] of string = (
    'description', 'desc', 'help', 'hint', 'comment', 'comments', 'caption',
    'text', 'example', 'examples', 'note', 'notes', 'title', 'summary');

  // IPv4-Oktettgrenzen der Klassentabelle.
  OCTET_MAX = 255;
  MAX_OCTET_DIGITS = 3;
  V6_GROUPS = 8;          // 16-Bit-Gruppen einer IPv6-Adresse
  V4_TAIL_GROUPS = 2;     // eine eingebettete IPv4 belegt die letzten zwei
  SMALL_OCTET_MAX = 31;   // Versionsform: alle Oktette <= 31 ...
  SMALL_FIRST_MAX = 20;   // ... und das erste <= 20

  // Verzichtsgruende (Tests pruefen sie woertlich).
  R_CLASS   = 'class';
  R_OID     = 'oid';
  R_VERSION = 'version';
  R_PRODUCT = 'product';
  R_RANGE   = 'range-bound';
  R_SMALL   = 'small-number';
  R_SOUP    = 'number-soup';
  R_TEXTKEY = 'text-key';

{ ---- Zeichenklassen ---- }

function IsDigit(C: Char): Boolean;
begin
  Result := CharInSet(C, ['0'..'9']);
end;

function IsLetter(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z']);
end;

function IsUpper(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z']);
end;

function IsLower(C: Char): Boolean;
begin
  Result := CharInSet(C, ['a'..'z']);
end;

function IsWordChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

function IsHex(C: Char): Boolean;
begin
  Result := CharInSet(C, ['0'..'9', 'A'..'F', 'a'..'f']);
end;

// Zeichen einer IPv6-Kandidatenkette.
function IsV6RunChar(C: Char): Boolean;
begin
  Result := IsHex(C) or (C = ':') or (C = '.');
end;

function IsZoneChar(C: Char): Boolean;
begin
  Result := IsWordChar(C) or (C = '.') or (C = '-');
end;

function CharAt(const S: string; I: Integer): Char;
begin
  if (I >= 1) and (I <= Length(S)) then
    Result := S[I]
  else
    Result := #0;
end;

function InList(const AWord: string; const AList: array of string): Boolean;
var
  W : string;
begin
  Result := False;
  for W in AList do
    if W = AWord then
      Exit(True);
end;

function AnyInList(const AWords: TArray<string>; const AList: array of string): Boolean;
var
  W : string;
begin
  Result := False;
  for W in AWords do
    if InList(W, AList) then
      Exit(True);
end;

{ ---- Wachsende Arrays (Verdopplung statt SetLength je Element) ---- }

procedure AddHit(var A: TArray<TIpHit>; var N: Integer; const H: TIpHit);
begin
  if N = Length(A) then
    SetLength(A, 2 * N + 4);
  A[N] := H;
  Inc(N);
end;

procedure AddStr(var A: TArray<string>; var N: Integer; const S: string);
begin
  if N = Length(A) then
    SetLength(A, 2 * N + 4);
  A[N] := S;
  Inc(N);
end;

procedure AddCodeHit(var A: TArray<TCodeIpHit>; var N: Integer; const H: TCodeIpHit);
begin
  if N = Length(A) then
    SetLength(A, 2 * N + 4);
  A[N] := H;
  Inc(N);
end;

procedure AddIniHit(var A: TArray<TIniIpHit>; var N: Integer; const H: TIniIpHit);
begin
  if N = Length(A) then
    SetLength(A, 2 * N + 4);
  A[N] := H;
  Inc(N);
end;

{ ---- IPv4 ---- }

// Ein Dezimal-Oktett ab S[I]: 1..3 Ziffern, keine fuehrende Null, <= 255.
// AEnd zeigt hinter die letzte Ziffer.
function ReadOctet(const S: string; I: Integer; out AValue: Cardinal;
  out AEnd: Integer): Boolean;
var
  j : Integer;
begin
  Result := False;
  AValue := 0;
  j := I;
  while (j <= Length(S)) and IsDigit(S[j]) and (j - I <= MAX_OCTET_DIGITS) do
  begin
    AValue := AValue * 10 + Cardinal(Ord(S[j]) - Ord('0'));
    Inc(j);
  end;
  AEnd := j;
  if (j = I) or (j - I > MAX_OCTET_DIGITS) then Exit;
  if (j - I > 1) and (S[I] = '0') then Exit;   // fuehrende Null: oktal-mehrdeutig
  Result := AValue <= OCTET_MAX;
end;

// Vier Oktette ab S[I] (ohne Grenzpruefung). AEnd hinter der letzten Ziffer.
function ReadDottedQuad(const S: string; I: Integer; out V: Cardinal;
  out AEnd: Integer): Boolean;
var
  k, j : Integer;
  O    : Cardinal;
begin
  Result := False;
  V := 0;
  j := I;
  for k := 1 to 4 do
  begin
    if not ReadOctet(S, j, O, AEnd) then Exit;
    V := (V shl 8) or O;
    j := AEnd;
    if k < 4 then
    begin
      if CharAt(S, j) <> '.' then Exit;
      Inc(j);
    end;
  end;
  Result := True;
end;

class function TIpAddressScan.TryParseIPv4(const S: string; out V: Cardinal): Boolean;
var
  E : Integer;
begin
  Result := ReadDottedQuad(S, 1, V, E) and (E = Length(S) + 1);
end;

{ ---- IPv6 ---- }

// Teilt an ':' (leere Teile bleiben erhalten).
function SplitColon(const S: string): TArray<string>;
var
  i, Start, N : Integer;
begin
  Result := nil;
  N := 0;
  Start := 1;
  for i := 1 to Length(S) + 1 do
    if (i > Length(S)) or (S[i] = ':') then
    begin
      AddStr(Result, N, Copy(S, Start, i - Start));
      Start := i + 1;
    end;
  SetLength(Result, N);
end;

function IsH16(const G: string): Boolean;
var
  C : Char;
begin
  Result := (Length(G) >= 1) and (Length(G) <= 4);
  if not Result then Exit;
  for C in G do
    if not IsHex(C) then
      Exit(False);
end;

function H16Value(const G: string): Word;
begin
  Result := Word(StrToInt('$' + G));
end;

// Gruppenliste (ohne '::') nach W ab AFirst.
function FillGroups(const AGroups: TArray<string>; var W: TIpv6Words;
  AFirst: Integer): Boolean;
var
  i : Integer;
begin
  Result := True;
  for i := 0 to High(AGroups) do
  begin
    if not IsH16(AGroups[i]) then
      Exit(False);
    W[AFirst + i] := H16Value(AGroups[i]);
  end;
end;

// Teil vor der eingebetteten IPv4 (ohne deren ':'), oder S selbst.
// Teil vor der eingebetteten IPv4 (ohne deren ':'); AV4 = die IPv4.
// Nur fuer Texte mit '.'.
function SplitV4Tail(const S: string; out AHead: string; out AV4: Cardinal): Boolean;
var
  p : Integer;
begin
  AHead := S;
  AV4 := 0;
  p := LastDelimiter(':', S);
  if (p = 0) or not TIpAddressScan.TryParseIPv4(Copy(S, p + 1, MaxInt), AV4) then
    Exit(False);
  AHead := Copy(S, 1, p);
  // 'a:b::1.2.3.4' behaelt '::', 'a:...:f:1.2.3.4' verliert das letzte ':'
  if Copy(AHead, Length(AHead) - 1, 2) <> '::' then
    Delete(AHead, Length(AHead), 1);
  Result := True;
end;

// Gruppen mit '::' an APos: links und rechts davon, zusammen hoechstens
// ANeed - 1 ('::' steht fuer mindestens eine Nullgruppe, RFC 4291).
function FillCompressed(const AHead: string; APos, ANeed: Integer;
  var W: TIpv6Words): Boolean;
var
  LG, RG : TArray<string>;
begin
  Result := False;
  if Pos('::', Copy(AHead, APos + 2, MaxInt)) > 0 then Exit;   // zweites '::'
  LG := nil;
  RG := nil;
  if APos > 1 then LG := SplitColon(Copy(AHead, 1, APos - 1));
  if APos + 2 <= Length(AHead) then RG := SplitColon(Copy(AHead, APos + 2, MaxInt));
  if Length(LG) + Length(RG) > ANeed - 1 then Exit;
  Result := FillGroups(LG, W, 0) and FillGroups(RG, W, ANeed - Length(RG));
end;

class function TIpAddressScan.TryParseIPv6(const S: string; out W: TIpv6Words): Boolean;
var
  Head  : string;
  V4    : Cardinal;
  HasV4 : Boolean;
  Need  : Integer;
  p, i  : Integer;
  G     : TArray<string>;
begin
  Result := False;
  for i := 0 to 7 do W[i] := 0;
  if (S = '') or (Pos(':::', S) > 0) then Exit;
  Head := S;
  V4 := 0;
  HasV4 := Pos('.', S) > 0;
  Need := V6_GROUPS;
  if HasV4 then
  begin
    if not SplitV4Tail(S, Head, V4) then Exit;
    Need := V6_GROUPS - V4_TAIL_GROUPS;
  end;
  p := Pos('::', Head);
  if p > 0 then
    Result := FillCompressed(Head, p, Need, W)
  else
  begin
    G := SplitColon(Head);
    Result := (Length(G) = Need) and FillGroups(G, W, 0);
  end;
  if Result and HasV4 then
  begin
    W[6] := Word(V4 shr 16);
    W[7] := Word(V4 and $FFFF);
  end;
end;

{ ---- Klassen ---- }

type
  // Ein IPv4-Block der Klassentabelle.
  TV4Block = record
    A, B, C, D : Byte;
    Prefix     : Integer;
    Cls        : TIpClass;
  end;

  // Ein IPv6-Block: die ersten 64 Bit als Wert und Maske je Wort.
  TV6Block = record
    V0, V1, V2, V3 : Word;
    M0, M1, M2, M3 : Word;
    Cls            : TIpClass;
  end;

const
  // IANA IPv4 Special-Purpose Address Registry (RFC 6890) plus RFC 1918
  // und RFC 6598; der erste passende Block gewinnt. Broadcast und
  // Netzmasken prueft ClassifyV4 davor - 255.255.255.0 liegt in 240/4.
  V4_BLOCKS: array[0..17] of TV4Block = (
    (A:   0; B:   0; C:   0; D: 0; Prefix:  8; Cls: ipcUnspecified),
    (A: 127; B:   0; C:   0; D: 0; Prefix:  8; Cls: ipcLoopback),
    (A: 169; B: 254; C:   0; D: 0; Prefix: 16; Cls: ipcLinkLocal),
    (A: 192; B:   0; C:   2; D: 0; Prefix: 24; Cls: ipcDocumentation),
    (A: 198; B:  51; C: 100; D: 0; Prefix: 24; Cls: ipcDocumentation),
    (A: 203; B:   0; C: 113; D: 0; Prefix: 24; Cls: ipcDocumentation),
    (A: 192; B:   0; C:   0; D: 0; Prefix: 24; Cls: ipcProtocol),
    (A: 192; B:  31; C: 196; D: 0; Prefix: 24; Cls: ipcProtocol),
    (A: 192; B:  52; C: 193; D: 0; Prefix: 24; Cls: ipcProtocol),
    (A: 192; B:  88; C:  99; D: 0; Prefix: 24; Cls: ipcProtocol),
    (A: 192; B: 175; C:  48; D: 0; Prefix: 24; Cls: ipcProtocol),
    (A: 198; B:  18; C:   0; D: 0; Prefix: 15; Cls: ipcBenchmark),
    (A: 224; B:   0; C:   0; D: 0; Prefix:  4; Cls: ipcMulticast),
    (A: 240; B:   0; C:   0; D: 0; Prefix:  4; Cls: ipcReserved),
    (A:  10; B:   0; C:   0; D: 0; Prefix:  8; Cls: ipcPrivate),
    (A: 172; B:  16; C:   0; D: 0; Prefix: 12; Cls: ipcPrivate),
    (A: 192; B: 168; C:   0; D: 0; Prefix: 16; Cls: ipcPrivate),
    (A: 100; B:  64; C:   0; D: 0; Prefix: 10; Cls: ipcCgnat));

  // IANA IPv6 Special-Purpose Address Registry (RFC 6890); ::/96, ::ffff:0:0/96
  // und 64:ff9b::/96 behandelt ClassifyLow96 vorher. Erster Treffer gewinnt
  // (2001:db8::/32 vor 2001::/23).
  V6_BLOCKS: array[0..9] of TV6Block = (
    (V0: $2001; V1: $0DB8; V2: 0; V3: 0; M0: $FFFF; M1: $FFFF; M2: 0; M3: 0; Cls: ipcDocumentation),
    (V0: $3FFF; V1: $0000; V2: 0; V3: 0; M0: $FFFF; M1: $F000; M2: 0; M3: 0; Cls: ipcDocumentation),
    (V0: $2001; V1: $0000; V2: 0; V3: 0; M0: $FFFF; M1: $FE00; M2: 0; M3: 0; Cls: ipcProtocol),
    (V0: $0100; V1: $0000; V2: 0; V3: 0; M0: $FFFF; M1: $FFFF; M2: $FFFF; M3: $FFFF; Cls: ipcProtocol),
    (V0: $0064; V1: $FF9B; V2: 0; V3: 0; M0: $FFFF; M1: $FFFF; M2: 0; M3: 0; Cls: ipcProtocol),
    (V0: $FE80; V1: $0000; V2: 0; V3: 0; M0: $FFC0; M1: 0; M2: 0; M3: 0; Cls: ipcLinkLocal),
    (V0: $FC00; V1: $0000; V2: 0; V3: 0; M0: $FE00; M1: 0; M2: 0; M3: 0; Cls: ipcPrivate),
    (V0: $FEC0; V1: $0000; V2: 0; V3: 0; M0: $FFC0; M1: 0; M2: 0; M3: 0; Cls: ipcPrivate),
    (V0: $FF00; V1: $0000; V2: 0; V3: 0; M0: $FF00; M1: 0; M2: 0; M3: 0; Cls: ipcMulticast),
    (V0: $0000; V1: $0000; V2: 0; V3: 0; M0: $FF00; M1: 0; M2: 0; M3: 0; Cls: ipcReserved));

  CLASS_LABELS: array[TIpClass] of string = ('private, RFC 1918',
    'shared, RFC 6598', 'public', 'loopback', 'unspecified', 'broadcast',
    'netmask', 'link-local', 'documentation', 'protocol-assigned',
    'benchmarking', 'multicast', 'reserved');

function InV4Block(V: Cardinal; const B: TV4Block): Boolean;
var
  Net, Mask : Cardinal;
begin
  Net := (Cardinal(B.A) shl 24) or (Cardinal(B.B) shl 16) or (Cardinal(B.C) shl 8) or B.D;
  Mask := Cardinal($FFFFFFFF) shl (32 - B.Prefix);
  Result := (V and Mask) = (Net and Mask);
end;

// Zusammenhaengende Maske mit erstem Oktett 255 (255.255.255.0 usw.).
function IsNetmask(V: Cardinal): Boolean;
var
  Inv : Cardinal;
begin
  if (V shr 24) <> OCTET_MAX then
    Exit(False);
  Inv := not V;
  Result := (Inv and (Inv + 1)) = 0;
end;

class function TIpAddressScan.ClassifyV4(V: Cardinal): TIpClass;
var
  B : TV4Block;
begin
  if V = $FFFFFFFF then Exit(ipcBroadcast);
  if IsNetmask(V) then Exit(ipcNetmask);
  for B in V4_BLOCKS do
    if InV4Block(V, B) then
      Exit(B.Cls);
  Result := ipcPublic;
end;

function ZeroWords(const W: TIpv6Words; AFrom, ATo: Integer): Boolean;
var
  i : Integer;
begin
  Result := True;
  for i := AFrom to ATo do
    if W[i] <> 0 then
      Exit(False);
end;

function EmbeddedV4(const W: TIpv6Words): Cardinal;
begin
  Result := (Cardinal(W[6]) shl 16) or W[7];
end;

// Die ersten 96 Bit sind ::/96 (Unspezifiziert, Loopback, IPv4-kompatibel),
// ::ffff:0:0/96 (IPv4-mapped) oder 64:ff9b::/96 (NAT64)?
function ClassifyLow96(const W: TIpv6Words; out C: TIpClass): Boolean;
begin
  Result := True;
  if ZeroWords(W, 0, 5) then
  begin
    if ZeroWords(W, 6, 7) then C := ipcUnspecified
    else if (W[6] = 0) and (W[7] = 1) then C := ipcLoopback
    else C := ipcReserved;   // IPv4-kompatibel, veraltet (RFC 4291 2.5.5.1)
  end
  else if ZeroWords(W, 0, 4) and (W[5] = $FFFF) then
    C := TIpAddressScan.ClassifyV4(EmbeddedV4(W))
  else if (W[0] = $64) and (W[1] = $FF9B) and ZeroWords(W, 2, 5) then
    C := TIpAddressScan.ClassifyV4(EmbeddedV4(W))
  else
    Result := False;
end;

function InV6Block(const W: TIpv6Words; const B: TV6Block): Boolean;
begin
  Result := ((W[0] and B.M0) = B.V0) and ((W[1] and B.M1) = B.V1)
    and ((W[2] and B.M2) = B.V2) and ((W[3] and B.M3) = B.V3);
end;

class function TIpAddressScan.ClassifyV6(const W: TIpv6Words): TIpClass;
var
  B : TV6Block;
begin
  if ClassifyLow96(W, Result) then Exit;
  for B in V6_BLOCKS do
    if InV6Block(W, B) then
      Exit(B.Cls);
  Result := ipcPublic;
end;

class function TIpAddressScan.IsReportable(C: TIpClass): Boolean;
begin
  Result := C in [ipcPrivate, ipcCgnat, ipcPublic];
end;

class function TIpAddressScan.ClassLabel(const AHit: TIpHit): string;
begin
  if (AHit.Family = ifV6) and (AHit.Cls = ipcPrivate) then
  begin
    if (AHit.V6[0] and $FE00) = $FC00 then
      Exit('unique local');
    if (AHit.V6[0] and $FFC0) = $FEC0 then
      Exit('site-local');
  end;
  Result := CLASS_LABELS[AHit.Cls];
end;

{ ---- Kandidatensuche ---- }

// Laesst Satzzeichen am Ende einer IPv6-Kandidatenkette weg: '.' und ein
// einzelnes ':' (ein '::' bleibt).
function TrimRunEnd(const S: string; AStart: Integer; var AEnd: Integer): Boolean;
begin
  while AEnd > AStart do
  begin
    if S[AEnd - 1] = '.' then
      Dec(AEnd)
    else if (S[AEnd - 1] = ':') and ((AEnd - 2 < AStart) or (S[AEnd - 2] <> ':')) then
      Dec(AEnd)
    else
      Break;
  end;
  Result := AEnd > AStart;
end;

function CountChar(const S: string; C: Char): Integer;
var
  X : Char;
begin
  Result := 0;
  for X in S do
    if X = C then Inc(Result);
end;

function HasDecimalDigit(const S: string): Boolean;
var
  X : Char;
begin
  Result := False;
  for X in S do
    if IsDigit(X) then Exit(True);
end;

// 8 Gruppen zu je 2 Hex ohne '::' und ohne IPv4: MAC/EUI-64/Hexdump.
function LooksLikeHexBytes(const S: string): Boolean;
var
  G : TArray<string>;
  X : string;
begin
  Result := False;
  if (Pos('::', S) > 0) or (Pos('.', S) > 0) then Exit;
  G := SplitColon(S);
  if Length(G) <> 8 then Exit;
  for X in G do
    if Length(X) <> 2 then Exit;
  Result := True;
end;

// Hinter einer Adresse: Zone '%...' ueberspringen; liefert die Position
// danach.
function SkipZone(const S: string; AEnd: Integer): Integer;
begin
  Result := AEnd;
  if CharAt(S, Result) <> '%' then Exit;
  Inc(Result);
  while (Result <= Length(S)) and IsZoneChar(S[Result]) do
    Inc(Result);
end;

// '://' bzw. '://[' oder ein UNC-Kopf '\\' direkt davor - in allen drei
// Faellen ist die Adresse ein Host, keine Zahl.
function UrlBefore(const S: string; AStart: Integer): Boolean;
begin
  if (CharAt(S, AStart - 1) = '\') and (CharAt(S, AStart - 2) = '\') then
    Exit(CharAt(S, AStart - 3) <> '\');
  if CharAt(S, AStart - 1) = '[' then Dec(AStart);
  Result := (AStart > 3) and (Copy(S, AStart - 3, 3) = '://');
end;

function PortAfter(const S: string; AEnd: Integer): Boolean;
begin
  if CharAt(S, AEnd) = ']' then Inc(AEnd);
  Result := (CharAt(S, AEnd) = ':') and IsDigit(CharAt(S, AEnd + 1));
end;

function CidrAfter(const S: string; AEnd: Integer): Boolean;
begin
  if CharAt(S, AEnd) = ']' then Inc(AEnd);
  Result := (CharAt(S, AEnd) = '/') and IsDigit(CharAt(S, AEnd + 1));
end;

procedure FillContext(const S: string; var H: TIpHit; AAfter: Integer);
begin
  H.InUrl   := UrlBefore(S, H.Start);
  H.HasPort := PortAfter(S, AAfter);
  H.HasCidr := CidrAfter(S, AAfter);
end;

// IPv6-Kandidat in der Kette S[AStart..AEnd-1]; True = Treffer in H.
function TryV6Run(const S: string; AStart, AEnd: Integer; out H: TIpHit): Boolean;
var
  Run   : string;
  After : Integer;
begin
  Result := False;
  H := Default(TIpHit);
  if not TrimRunEnd(S, AStart, AEnd) then Exit;
  Run := Copy(S, AStart, AEnd - AStart);
  if CountChar(Run, ':') < 2 then Exit;
  if IsWordChar(CharAt(S, AStart - 1)) then Exit;          // std::, TFoo::Bar
  After := SkipZone(S, AEnd);
  if IsWordChar(CharAt(S, After)) then Exit;
  if (Run <> '::') and not HasDecimalDigit(Run) then Exit;  // dead::beef
  // '::' allein nur als ganzer Text oder '[::]' - sonst Trenner ('a :: b',
  // Regex '(?::=')
  if (Run = '::') and (Trim(S) <> '::')
     and not ((CharAt(S, AStart - 1) = '[') and (CharAt(S, After) = ']')) then
    Exit;
  if LooksLikeHexBytes(Run) then Exit;
  if not TIpAddressScan.TryParseIPv6(Run, H.V6) then Exit;
  H.Start  := AStart;
  H.Len    := Length(Run);
  H.Text   := Run;
  H.Family := ifV6;
  H.V4     := EmbeddedV4(H.V6);
  H.Cls    := TIpAddressScan.ClassifyV6(H.V6);
  FillContext(S, H, After);
  Result := True;
end;

// IPv4-Kandidat ab S[I]; True = Treffer in H, AEnd hinter der letzten
// Ziffer.
function TryV4At(const S: string; I: Integer; out H: TIpHit; out AEnd: Integer): Boolean;
var
  V : Cardinal;
begin
  Result := False;
  H := Default(TIpHit);
  AEnd := I + 1;
  if not ReadDottedQuad(S, I, V, AEnd) then Exit;
  if IsWordChar(CharAt(S, AEnd)) then Exit;
  if (CharAt(S, AEnd) = '.') and IsDigit(CharAt(S, AEnd + 1)) then Exit;
  H.Start  := I;
  H.Len    := AEnd - I;
  H.Text   := Copy(S, I, AEnd - I);
  H.Family := ifV4;
  H.V4     := V;
  H.Cls    := TIpAddressScan.ClassifyV4(V);
  FillContext(S, H, AEnd);
  Result := True;
end;

function InsideAny(const AHits: TArray<TIpHit>; ACount, APos: Integer): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := 0 to ACount - 1 do
    if (APos >= AHits[i].Start) and (APos < AHits[i].Start + AHits[i].Len) then
      Exit(True);
end;

// Alle IPv6-Ketten.
procedure CollectV6(const S: string; var AHits: TArray<TIpHit>; var N: Integer);
var
  i, j : Integer;
  H    : TIpHit;
begin
  i := 1;
  while i <= Length(S) do
  begin
    if not IsV6RunChar(S[i]) then
    begin
      Inc(i);
      Continue;
    end;
    j := i;
    while (j <= Length(S)) and IsV6RunChar(S[j]) do
      Inc(j);
    if TryV6Run(S, i, j, H) then
      AddHit(AHits, N, H);
    i := j;
  end;
end;

// Alle IPv4 ausserhalb der IPv6-Treffer.
procedure CollectV4(const S: string; var AHits: TArray<TIpHit>; var N: Integer);
var
  i, E, N6 : Integer;
  H        : TIpHit;
  Prev     : Char;
begin
  N6 := N;
  i := 1;
  while i <= Length(S) do
  begin
    Prev := CharAt(S, i - 1);
    if IsDigit(S[i]) and not IsWordChar(Prev) and (Prev <> '.')
       and not InsideAny(AHits, N6, i) and TryV4At(S, i, H, E) then
    begin
      AddHit(AHits, N, H);
      i := E;
    end
    else
      Inc(i);
  end;
end;

procedure SortByStart(var AHits: TArray<TIpHit>; N: Integer);
var
  i, j : Integer;
  T    : TIpHit;
begin
  for i := 1 to N - 1 do
  begin
    T := AHits[i];
    j := i - 1;
    while (j >= 0) and (AHits[j].Start > T.Start) do
    begin
      AHits[j + 1] := AHits[j];
      Dec(j);
    end;
    AHits[j + 1] := T;
  end;
end;

class function TIpAddressScan.FindAll(const AText: string): TArray<TIpHit>;
var
  N : Integer;
begin
  Result := nil;
  N := 0;
  if (Pos('.', AText) = 0) and (Pos(':', AText) = 0) then Exit;
  CollectV6(AText, Result, N);
  CollectV4(AText, Result, N);
  SortByStart(Result, N);
  SetLength(Result, N);
end;

{ ---- Wortteile ---- }

// Beginnt an S[I] ein neuer Wortteil? ('fooBar': 'B'; 'DNSServer': 'S')
function IsCamelBreak(const S: string; I: Integer): Boolean;
begin
  Result := IsUpper(S[I]) and
    (IsLower(CharAt(S, I - 1)) or
     (IsUpper(CharAt(S, I - 1)) and IsLower(CharAt(S, I + 1))));
end;

class function TIpAddressScan.WordParts(const AText: string): TArray<string>;
var
  i, Start, N : Integer;
begin
  Result := nil;
  N := 0;
  Start := 0;
  for i := 1 to Length(AText) + 1 do
  begin
    if (i <= Length(AText)) and IsLetter(AText[i]) then
    begin
      if Start = 0 then
        Start := i
      else if IsCamelBreak(AText, i) then
      begin
        AddStr(Result, N, LowerCase(Copy(AText, Start, i - Start)));
        Start := i;
      end;
    end
    else if Start > 0 then
    begin
      AddStr(Result, N, LowerCase(Copy(AText, Start, i - Start)));
      Start := 0;
    end;
  end;
  SetLength(Result, N);
end;

{ ---- Kontext-Gates ---- }

function Octet(V: Cardinal; AIndex: Integer): Cardinal;
begin
  Result := (V shr (8 * (3 - AIndex))) and $FF;
end;

// OID-Boegen, die syntaktisch eine IPv4 sein koennen (X.500 2.5.x.x,
// SNMP 1.3.6.x, OIW 1.3.14.x, Ed25519 1.3.101.x).
function IsOidArc(V: Cardinal): Boolean;
var
  A, B, C : Cardinal;
begin
  A := Octet(V, 0);
  B := Octet(V, 1);
  C := Octet(V, 2);
  Result := ((A = 2) and (B = 5))
    or ((A = 1) and (B = 3) and ((C = 6) or (C = 14) or (C = 101)));
end;

// Alle Oktette klein und das erste <= 20: die Form von Versionsnummern.
function IsSmallNumberForm(V: Cardinal): Boolean;
var
  k : Integer;
begin
  Result := Octet(V, 0) <= SMALL_FIRST_MAX;
  for k := 1 to 3 do
    Result := Result and (Octet(V, k) <= SMALL_OCTET_MAX);
end;

// Direkt davor 'Produkt/' (nicht '//'), '\' oder '-': Versions- oder
// Pfadsegment ('Chrome/141.0.0.0', 'OpenSSL\1.1.1.10', 'Lib-1.0.0.20').
// Ein UNC-Kopf '\\' ist InUrl und kommt hier nicht an.
function HasProductPrefix(const S: string; AStart: Integer): Boolean;
var
  P : Char;
begin
  P := CharAt(S, AStart - 1);
  Result := (P = '\') or (P = '-')
    or ((P = '/') and IsWordChar(CharAt(S, AStart - 2)));
end;

function EndsWithText(const AWord, ATail: string): Boolean;
begin
  Result := (Length(AWord) >= Length(ATail))
    and (Copy(AWord, Length(AWord) - Length(ATail) + 1, MaxInt) = ATail);
end;

// Host-Wort: ein Eintrag aus HOST_WORDS oder ein Kompositum auf einem
// Host-Stamm.
function AnyHostWord(const AWords: TArray<string>): Boolean;
var
  W, S : string;
begin
  Result := False;
  for W in AWords do
  begin
    if InList(W, HOST_WORDS) then
      Exit(True);
    for S in HOST_STEMS do
      if EndsWithText(W, S) then
        Exit(True);
  end;
end;

// Versionswort direkt vor der Zahl im Text ('Version 2.1.0.45',
// 'MyApp Build: 3.2.1.200').
function VersionWordBefore(const S: string; AStart: Integer): Boolean;
var
  i, E : Integer;
begin
  i := AStart - 1;
  while (i >= 1) and CharInSet(S[i], [' ', #9, ':', '=']) do
    Dec(i);
  E := i;
  while (i >= 1) and IsLetter(S[i]) do
    Dec(i);
  Result := (E > i)
    and AnyInList(TIpAddressScan.WordParts(Copy(S, i + 1, E - i)), VERSION_WORDS);
end;

// Versionsangabe: ein Versionswort direkt vor der Zahl, oder eines im
// Kontext ohne Host-Wort daneben ('BuildServer', 'FirmwareServer' sind
// Hosts, 'FileVersion' nicht).
function IsVersionContext(const AHit: TIpHit; const AText: string;
  const AWords: TArray<string>): Boolean;
begin
  Result := VersionWordBefore(AText, AHit.Start)
    or (AnyInList(AWords, VERSION_WORDS) and not AnyHostWord(AWords));
end;

// Weitere Dezimalbrueche im Text (ausserhalb der Adressen): >= 2 heisst
// Zahlenkolonne (SVG-Pfad, Messwerte), keine Adressangabe. AHits sind nach
// Start sortiert und ueberlappen nicht - ein Zeiger statt Suche je Bruch.
function CountOtherFractions(const S: string; const AHits: TArray<TIpHit>): Integer;
var
  i, j, k : Integer;
  Inside  : Boolean;
begin
  Result := 0;
  k := 0;
  i := 1;
  while i <= Length(S) do
  begin
    if not IsDigit(S[i]) or IsWordChar(CharAt(S, i - 1)) or (CharAt(S, i - 1) = '.') then
    begin
      Inc(i);
      Continue;
    end;
    j := i;
    while (j <= Length(S)) and (IsDigit(S[j])
          or ((S[j] = '.') and IsDigit(CharAt(S, j + 1)))) do
      Inc(j);
    while (k < Length(AHits)) and (AHits[k].Start + AHits[k].Len <= i) do
      Inc(k);
    Inside := (k < Length(AHits)) and (i >= AHits[k].Start);
    if not Inside and (Pos('.', Copy(S, i, j - i)) > 0) then
      Inc(Result);
    i := j;
  end;
end;

// Formgates ohne URL/Port: IPv4-Bereichsgrenze (.0/.255) und Kleinzahl,
// IPv6-Netzpraefix ('fd12:3456::/48' - Interface-ID null mit '/n'). Die
// Kleinzahl-Form gilt nur fuer oeffentliche Adressen ('1.2.3.4', '4.0.0.2'
// sind meist Versionen) - eine private '10.1.2.3' ist auch ohne Kontext
// eine Adresse; ein Host-Wort rettet sie.
function JudgeForm(const AHit: TIpHit; const AHostWords: TArray<string>): string;
var
  Last : Cardinal;
begin
  Result := '';
  if AHit.Family = ifV6 then
  begin
    if AHit.HasCidr and ZeroWords(AHit.V6, 4, 7) then
      Result := R_RANGE;
    Exit;
  end;
  Last := Octet(AHit.V4, 3);
  if (Last = 0) or (Last = OCTET_MAX) then
    Exit(R_RANGE);
  if (AHit.Cls = ipcPublic) and IsSmallNumberForm(AHit.V4)
     and not AnyHostWord(AHostWords) then
    Result := R_SMALL;
end;

// Die Gates in fester Reihenfolge. AWords: Kontext (Pascal: Code der Zeile
// ohne Literale; INI: Schluessel); AHostWords: dazu nur fuer die Host-
// Rettung der Kleinzahl (INI: auch die Sektion); AFractions: weitere
// Dezimalbrueche im Text. URL, UNC und Port machen die Adresse zum Host -
// dann greifen weder Versions-, Form- noch Zahlenkolonnen-Gate.
function Judge(const AHit: TIpHit; const AText: string;
  const AWords, AHostWords: TArray<string>; AFractions: Integer): string;
var
  Host : Boolean;
begin
  if not TIpAddressScan.IsReportable(AHit.Cls) then
    Exit(R_CLASS);
  if ((AHit.Family = ifV4) and IsOidArc(AHit.V4)) or AnyInList(AWords, OID_WORDS) then
    Exit(R_OID);
  Host := AHit.InUrl or AHit.HasPort;
  if not Host and IsVersionContext(AHit, AText, AWords) then
    Exit(R_VERSION);
  if HasProductPrefix(AText, AHit.Start) and not AHit.InUrl then
    Exit(R_PRODUCT);
  Result := '';
  if Host then Exit;
  Result := JudgeForm(AHit, AHostWords);
  if (Result = '') and (AFractions >= 2) then
    Result := R_SOUP;
end;

class function TIpAddressScan.JudgeHit(const AHit: TIpHit; const AText: string;
  const AContextWords: TArray<string>): string;
begin
  Result := Judge(AHit, AText, AContextWords, AContextWords,
    CountOtherFractions(AText, FindAll(AText)));
end;

{ ---- Pascal-Literale ---- }

// Ende eines Literals, das bei AQuote beginnt ('' ist ein Zeichen);
// 0, wenn es vor ALineEnd nicht schliesst.
function LiteralEnd(const S: string; AQuote, ALineEnd: Integer): Integer;
var
  k : Integer;
begin
  Result := 0;
  k := AQuote + 1;
  while k < ALineEnd do
  begin
    if S[k] = '''' then
    begin
      if (k + 1 < ALineEnd) and (S[k + 1] = '''') then
        Inc(k, 2)
      else
        Exit(k);
    end
    else
      Inc(k);
  end;
end;

// Je Zeile und Adresse ein Eintrag (ab AFrom); ein gemeldeter Treffer
// ersetzt einen frueheren verworfenen ('srv-10.0.0.5,10.0.0.5').
procedure MergeCodeHit(var A: TArray<TCodeIpHit>; var N: Integer; AFrom: Integer;
  const H: TCodeIpHit);
var
  i : Integer;
begin
  for i := AFrom to N - 1 do
    if A[i].Hit.Text = H.Hit.Text then
    begin
      if (A[i].Reason <> '') and (H.Reason = '') then
        A[i] := H;
      Exit;
    end;
  AddCodeHit(A, N, H);
end;

type
  // Ein Literal einer Zeile: Position des oeffnenden Quotes und Inhalt.
  TLiteral = record
    Quote : Integer;
    Body  : string;
  end;

// Literale der Zeile S[ALineStart..ALineEnd-1]; ACode = die Zeile mit
// Leerzeichen statt Literalen (fuer die Kontextwoerter).
function LiteralsOfLine(const S: string; ALineStart, ALineEnd: Integer;
  out ACode: string): TArray<TLiteral>;
var
  j, E, N, k : Integer;
  L          : TLiteral;
begin
  Result := nil;
  N := 0;
  ACode := '';
  // Die meisten Zeilen tragen kein Literal - dann keine Zeilenkopie.
  j := ALineStart;
  while (j < ALineEnd) and (S[j] <> '''') do
    Inc(j);
  if j >= ALineEnd then Exit;
  ACode := Copy(S, ALineStart, ALineEnd - ALineStart);
  j := ALineStart;
  while j < ALineEnd do
  begin
    if S[j] <> '''' then
    begin
      Inc(j);
      Continue;
    end;
    E := LiteralEnd(S, j, ALineEnd);
    if E = 0 then Break;                       // offen bis Zeilenende
    L.Quote := j;
    L.Body := StringReplace(Copy(S, j + 1, E - j - 1), '''''', '''', [rfReplaceAll]);
    if N = Length(Result) then SetLength(Result, 2 * N + 4);
    Result[N] := L;
    Inc(N);
    for k := j to E do
      ACode[k - ALineStart + 1] := ' ';
    j := E + 1;
  end;
  SetLength(Result, N);
end;

// Adressen eines Literals in die Trefferliste der Zeile (ab ALineFirst).
procedure AddLiteralHits(var A: TArray<TCodeIpHit>; var N: Integer;
  ALineFirst: Integer; const L: TLiteral; const AWords: TArray<string>);
var
  Hits : TArray<TIpHit>;
  Frac : Integer;
  H    : TIpHit;
  CH   : TCodeIpHit;
begin
  Hits := TIpAddressScan.FindAll(L.Body);
  if Hits = nil then Exit;
  Frac := CountOtherFractions(L.Body, Hits);
  for H in Hits do
  begin
    CH.Pos := L.Quote;
    CH.Hit := H;
    CH.Reason := Judge(H, L.Body, AWords, AWords, Frac);
    MergeCodeHit(A, N, ALineFirst, CH);
  end;
end;

class function TIpAddressScan.ScanPascalCode(const ACode: string): TArray<TCodeIpHit>;
var
  LineStart, LineEnd, N, LineFirst : Integer;
  Lits   : TArray<TLiteral>;
  Code   : string;
  Words  : TArray<string>;
  L      : TLiteral;
begin
  Result := nil;
  N := 0;
  LineStart := 1;
  while LineStart <= Length(ACode) do
  begin
    LineEnd := LineStart;
    while (LineEnd <= Length(ACode)) and (ACode[LineEnd] <> #10) do
      Inc(LineEnd);
    LineFirst := N;
    Lits := LiteralsOfLine(ACode, LineStart, LineEnd, Code);
    if Length(Lits) > 0 then
      Words := WordParts(Code);
    for L in Lits do
      AddLiteralHits(Result, N, LineFirst, L, Words);
    LineStart := LineEnd + 1;
  end;
  SetLength(Result, N);
end;

{ ---- INI ---- }

// Rest hinter einem Sektionskopf: leer oder ein Kommentar.
function IsIniTail(const ATail: string): Boolean;
begin
  Result := (ATail = '') or CharInSet(ATail[1], [';', '#']);
end;

// Zerlegt eine INI-Zeile; False bei Leer-, Kommentar- und Sektionszeilen
// (dann ggf. ASection neu).
function SplitIniLine(const ALine: string; var ASection: string;
  out AKey, AValue: string): Boolean;
var
  T : string;
  p : Integer;
begin
  Result := False;
  AKey := '';
  AValue := '';
  T := Trim(ALine);
  if (T = '') or (T[1] = ';') or (T[1] = '#') then Exit;
  // Sektionskopf bis zur ersten ']', dahinter hoechstens ein Kommentar
  // ('[Database] ; prod') - so liest auch GetPrivateProfileString.
  p := Pos(']', T);
  if (T[1] = '[') and (p > 0) and IsIniTail(Trim(Copy(T, p + 1, MaxInt))) then
  begin
    ASection := Trim(Copy(T, 2, p - 2));
    Exit;
  end;
  p := Pos('=', ALine);
  if p > 0 then
  begin
    AKey := Trim(Copy(ALine, 1, p - 1));
    AValue := Copy(ALine, p + 1, MaxInt);
  end
  else
    AValue := ALine;
  Result := True;
end;

// Wie MergeCodeHit, fuer INI-Zeilen.
procedure MergeIniHit(var A: TArray<TIniIpHit>; var N: Integer; AFrom: Integer;
  const H: TIniIpHit);
var
  i : Integer;
begin
  for i := AFrom to N - 1 do
    if A[i].Hit.Text = H.Hit.Text then
    begin
      if (A[i].Reason <> '') and (H.Reason = '') then
        A[i] := H;
      Exit;
    end;
  AddIniHit(A, N, H);
end;

function JoinParts(const A, B: TArray<string>): TArray<string>;
var
  i : Integer;
begin
  Result := nil;
  SetLength(Result, Length(A) + Length(B));
  for i := 0 to High(A) do
    Result[i] := A[i];
  for i := 0 to High(B) do
    Result[Length(A) + i] := B[i];
end;

// Eine INI-Adresse: die Gates, danach Fliesstext-Schluessel - ausser die
// Adresse ist ein Host (URL, Port, Host-Wort im Schluessel: 'HelpUrl=
// http://...:8080', 'HelpServer=...').
function IniReason(const AHit: TIpHit; const AValue: string;
  const AKeyWords, AHostWords: TArray<string>; AFractions: Integer): string;
begin
  Result := Judge(AHit, AValue, AKeyWords, AHostWords, AFractions);
  if (Result = '') and AnyInList(AKeyWords, TEXT_WORDS) and not AHit.InUrl
     and not AHit.HasPort and not AnyHostWord(AKeyWords) then
    Result := R_TEXTKEY;
end;

class function TIpAddressScan.ScanIniLines(ALines: TStrings): TArray<TIniIpHit>;
var
  i, N, LineFirst, Frac : Integer;
  Section, Key, Value : string;
  KeyWords, HostWords : TArray<string>;
  Hits     : TArray<TIpHit>;
  H        : TIpHit;
  IH       : TIniIpHit;
begin
  Result := nil;
  N := 0;
  Section := '';
  if ALines = nil then Exit;
  for i := 0 to ALines.Count - 1 do
  begin
    if not SplitIniLine(ALines[i], Section, Key, Value) then Continue;
    Hits := FindAll(Value);
    if Hits = nil then Continue;
    KeyWords := WordParts(Key);
    // Die Sektion rettet nur die Kleinzahl ('[DNS] Primary=8.8.8.8'); als
    // Versionskontext zaehlt sie nicht ('[Server] Version=...').
    HostWords := JoinParts(KeyWords, WordParts(Section));
    Frac := CountOtherFractions(Value, Hits);
    LineFirst := N;
    for H in Hits do
    begin
      IH.Line := i + 1;
      IH.Section := Section;
      IH.Key := Key;
      IH.Hit := H;
      IH.Reason := IniReason(H, Value, KeyWords, HostWords, Frac);
      MergeIniHit(Result, N, LineFirst, IH);
    end;
  end;
  SetLength(Result, N);
end;

{ ---- Meldetexte ---- }

class function TIpAddressScan.CodeMessage(const AHit: TIpHit): string;
begin
  Result := Format('Hardcoded IP address ''%s'' (%s) - move it to the ' +
    'configuration or use a host name', [AHit.Text, ClassLabel(AHit)]);
end;

class function TIpAddressScan.IniMessage(const AHit: TIniIpHit): string;
var
  Where : string;
begin
  if AHit.Key = '' then
    Where := 'value'
  else
    Where := AHit.Key;
  if AHit.Section <> '' then
    Where := '[' + AHit.Section + '] ' + Where;
  Result := Format('IP address ''%s'' (%s) in %s - an environment-specific ' +
    'address in a versioned configuration file; prefer a host name or a ' +
    'per-environment setting', [AHit.Hit.Text, ClassLabel(AHit.Hit), Where]);
end;

end.
