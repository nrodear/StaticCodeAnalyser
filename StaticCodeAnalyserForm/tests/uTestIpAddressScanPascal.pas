unit uTestIpAddressScanPascal;

// Tests fuer uIpAddressScan (SCA200), Teil 3: ScanPascalCode - Literale
// einer Zeile, die Kontext-Gates (Version, OID, Produktpfad, Bereichs-
// grenze, Kleinzahl, Zahlenkolonne) und die Dedupe je Zeile. Erwartung
// je Fall 'Text=Grund' ('' als Grund = melden). Versioniert aus dem FPC-
// Pruefstand (Review 2026-10-13) samt der beiden Reviews vom 2026-10-09.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes,
  uIpAddressScan, uTestIpAddressScanKit;

type
  [TestFixture]
  TTestIpAddressScanPascal = class
  public
    [Test] procedure Pascal_HostLiterals_Reported;
    [Test] procedure Pascal_VersionProductOid_Rejected;
    [Test] procedure Pascal_ClassAndRangeBound_Rejected;
    [Test] procedure Pascal_SmallNumber_WithoutHostWord;
    [Test] procedure Pascal_NumberSoup_NotInUrl;
    [Test] procedure Pascal_Dedupe_ReportedReplacesRejected;
    [Test] procedure Pascal_UncHead_IsHost;
    [Test] procedure Pascal_HostWordBeatsVersionWord;
    [Test] procedure Pascal_VersionWordBeforeNumber;
    [Test] procedure Pascal_VersionHead_StaysVersion;
    [Test] procedure Pascal_IPv6Prefix_RangeBound;
    [Test] procedure Pascal_EscapedPath_IsProduct;
    [Test] procedure Pascal_Ipv4Word_RescuesSmallNumber;
    [Test] procedure Pascal_Positions_QuoteOfTheLiteral;
    [Test] procedure Pascal_SameAddressTwoLines_TwoHits;
    // Gegen-Review Welle 1, Minor 10: das Host-Wort 'ip' aus 'IPv4'/'IPv6'
    // schlaegt das Versionswort daneben - Entscheid: so lassen (Build-
    // Server-Regel) und pinnen.
    [Test] procedure Pascal_IpvWordBeatsVersionWord_Pinned;
    // Dedupe ueber zwei Literale derselben Zeile: Pos zeigt auf das
    // Literal des GEMELDETEN Treffers; beide gemeldet / beide verworfen.
    [Test] procedure Pascal_DedupePos_OverTwoLiterals;
  end;

implementation

const
  HOSTS: array[0..13] of TTextCase = (
    (Input: '  Host := ''192.168.12.42'';'; Expected: '192.168.12.42='),
    (Input: '  FRootDNS_NET.Add(''209.92.33.150'');'; Expected: '209.92.33.150='),
    (Input: '  FRootDNS_NET.Add(''12.29.20.2'');'; Expected: '12.29.20.2='),
    (Input: '  x := ''http://1.2.3.4/'';'; Expected: '1.2.3.4='),
    (Input: '  URL = ''http://192.168.1.153:3000/api'';'; Expected: '192.168.1.153='),
    (Input: '  DnsServer := ''8.8.8.8'';'; Expected: '8.8.8.8='),
    (Input: '  Dns := ''1.1.1.1'';'; Expected: '1.1.1.1='),
    (Input: '  x := ''10.0.0.5'';'; Expected: '10.0.0.5='),
    (Input: '  S := ''it''''s 10.1.2.3'';'; Expected: '10.1.2.3='),
    (Input: '  T := ''TCP:192.168.0.31:9100'';'; Expected: '192.168.0.31='),
    (Input: '  V := ''::ffff:10.1.2.3'';'; Expected: '::ffff:10.1.2.3='),
    (Input: 'function GetLocalIpAddress(const Remote: RawUtf8 = ''8.8.8.8''): RawUtf8;'; Expected: '8.8.8.8='),
    (Input: '  fSubnetMask := ''192.168.1.1/24'';'; Expected: '192.168.1.1='),
    (Input: '  Resolver.Nameserver := ''8.8.8.8'';'; Expected: '8.8.8.8='));

  VERSION_OID: array[0..4] of TTextCase = (
    (Input: '  Ide.verProc := ''1.0.0.0'';'; Expected: '1.0.0.0=version'),
    (Input: '  s := ''Chrome/141.0.0.0'';'; Expected: '141.0.0.0=product'),
    (Input: '  p := ''OpenSSL\1.1.1.10\x86'';'; Expected: '1.1.1.10=product'),
    (Input: '  c := ''2.5.4.3'';'; Expected: '2.5.4.3=oid'),
    (Input: '  szOID_X = ''10.20.30.40'';'; Expected: '10.20.30.40=oid'));

  CLASS_RANGE: array[0..9] of TTextCase = (
    (Input: '  (''10.0.0.0'', ''10.255.255.255''),'; Expected: '10.0.0.0=range-bound|10.255.255.255=range-bound'),
    (Input: '  M := ''255.255.255.0'';'; Expected: '255.255.255.0=class'),
    (Input: '  L := ''127.0.0.1'';'; Expected: '127.0.0.1=class'),
    (Input: '  x := ''[::]'';'; Expected: '::=class'),
    (Input: '  x := ''a :: b'';'; Expected: ''),
    (Input: '  Doc := ''192.0.2.1'';'; Expected: '192.0.2.1=class'),
    (Input: '  C := ''c6AnyHost'' + ''::'';'; Expected: '::=class'),
    (Input: '  A := ''2001:db8::1''; B := ''fd00::5'';'; Expected: '2001:db8::1=class|fd00::5='),
    (Input: '  W := ''std::string'';'; Expected: ''),
    (Input: '  X := ''10.1.2.3'; Expected: ''));

  SMALL: array[0..3] of TTextCase = (
    (Input: '  x := ''1.2.3.4'';'; Expected: '1.2.3.4=small-number'),
    (Input: '  D := ''8.8.8.8''; E := ''8.8.8.8'';'; Expected: '8.8.8.8=small-number'),
    (Input: '  x := ''1.1.1.1'';'; Expected: '1.1.1.1=small-number'),
    (Input: '  FObserver.Notify(''1.2.3.4'');'; Expected: '1.2.3.4=small-number'));

  SOUP: array[0..2] of TTextCase = (
    (Input: '  Svg := ''1.5 2.5 10.1.2.3 3.5'';'; Expected: '10.1.2.3=number-soup'),
    (Input: '  U := ''http://10.0.0.5/geo?lat=48.13&lon=11.57'';'; Expected: '10.0.0.5='),
    (Input: '  U := ''http://10.0.0.5:8080/rest/1.0/items?v=2.1'';'; Expected: '10.0.0.5='));

  DEDUPE: array[0..1] of TTextCase = (
    (Input: '  Paths := ''srv-10.0.0.5,10.0.0.5'';'; Expected: '10.0.0.5='),
    (Input: '  D := ''10.0.0.5,srv-10.0.0.5'';'; Expected: '10.0.0.5='));

  UNC: array[0..2] of TTextCase = (
    (Input: '  BackupDir := ''\\192.168.10.5\Backup\'';'; Expected: '192.168.10.5='),
    (Input: '  ShellExecute(0, nil, ''\\10.20.30.40\share'', nil, nil, 0);'; Expected: '10.20.30.40='),
    (Input: '  S := ''net use \\10.0.0.5\share'';'; Expected: '10.0.0.5='));

  HOST_VS_VERSION: array[0..6] of TTextCase = (
    (Input: '  Conn.ConnectionString := BuildConnStr(''192.168.1.20'', 1433);'; Expected: '192.168.1.20='),
    (Input: '  FHttp.Get(BuildUrl(''10.0.0.5'', ''/api''));'; Expected: '10.0.0.5='),
    (Input: '  FirmwareServer := ''10.0.0.5'';'; Expected: '10.0.0.5='),
    (Input: '  FileVersion := ''172.16.5.4'';'; Expected: '172.16.5.4=version'),
    (Input: '  Cfg := ''BuildServer=10.0.0.5'';'; Expected: '10.0.0.5='),
    (Input: '  Cfg := ''FirmwareServer: 10.0.0.5'';'; Expected: '10.0.0.5='),
    (Input: '  Cfg := ''ReleaseHost 10.0.0.5'';'; Expected: '10.0.0.5='));

  VERSION_BEFORE: array[0..3] of TTextCase = (
    (Input: '  lblAbout.Caption := ''Version 2.1.0.45'';'; Expected: '2.1.0.45=version'),
    (Input: '  ShowMessage(''MyApp Build 3.2.1.200'');'; Expected: '3.2.1.200=version'),
    (Input: '  S := ''MyApp Build 3.2.1.200'';'; Expected: '3.2.1.200=version'),
    (Input: '  Msg := ''Connecting to 10.1.2.3'';'; Expected: '10.1.2.3='));

  // Versionswort als KOPF eines Bezeichners bleibt Version, auch mit
  // Host-Wort davor; 'observer'/'ghost' sind keine Hosts.
  VERSION_HEAD: array[0..6] of TTextCase = (
    (Input: '  ServerVersion := ''2.3.1.7'';'; Expected: '2.3.1.7=version'),
    (Input: '  if FServerInfo.Version < ''10.0.2.1'' then'; Expected: '10.0.2.1=version'),
    (Input: '  if Conn.ServerVersion >= ''12.2.0.1'' then'; Expected: '12.2.0.1=version'),
    (Input: '  MinServerVersion := ''19.3.0.1'';'; Expected: '19.3.0.1=version'),
    (Input: '  if HostVersion = ''3.1.0.4'' then'; Expected: '3.1.0.4=version'),
    (Input: '  FObserver.Version := ''2.1.0.45'';'; Expected: '2.1.0.45=version'),
    (Input: '  Ghost.Version := ''2.1.0.45'';'; Expected: '2.1.0.45=version'));

  V6_PREFIX: array[0..1] of TTextCase = (
    (Input: '  Net := ''fd12:3456::/48'';'; Expected: 'fd12:3456::=range-bound'),
    (Input: '  Addr := ''fd00::5/64'';'; Expected: 'fd00::5='));

  // '\\' mitten in einem escapten Pfad ist kein UNC-Kopf.
  ESCAPED: array[0..2] of TTextCase = (
    (Input: '  Dir := ''C:\\Tools\\MyLib\\2.1.0.5'';'; Expected: '2.1.0.5=product'),
    (Input: '  Json := ''{"lib":"C:\\deps\\OpenSSL\\1.1.1.10\\bin"}'';'; Expected: '1.1.1.10=product'),
    (Input: '  Re := ''C:\\Tools\\1.0.0.0'';'; Expected: '1.0.0.0=product'));

  // Review 2026-10-13: 'IPv4'/'IPv6' im Bezeichner ist das Host-Wort 'ip'.
  IPV_WORD: array[0..3] of TTextCase = (
    (Input: '  LocalIPv4 := ''8.8.8.8'';'; Expected: '8.8.8.8='),
    (Input: '  ipv6Fallback := ''1.1.1.1'';'; Expected: '1.1.1.1='),
    (Input: '  Ipv4Mask := ''255.255.255.0'';'; Expected: '255.255.255.0=class'),
    (Input: '  Local := ''8.8.8.8'';'; Expected: '8.8.8.8=small-number'));

procedure CheckPascal(const ACases: array of TTextCase);
var
  i : Integer;
begin
  for i := 0 to High(ACases) do
    Assert.AreEqual(ACases[i].Expected, PascalGot(ACases[i].Input),
      'ScanPascalCode(' + ACases[i].Input + ')');
end;

procedure TTestIpAddressScanPascal.Pascal_HostLiterals_Reported;
begin
  CheckPascal(HOSTS);
end;

procedure TTestIpAddressScanPascal.Pascal_VersionProductOid_Rejected;
begin
  CheckPascal(VERSION_OID);
end;

procedure TTestIpAddressScanPascal.Pascal_ClassAndRangeBound_Rejected;
begin
  CheckPascal(CLASS_RANGE);
end;

procedure TTestIpAddressScanPascal.Pascal_SmallNumber_WithoutHostWord;
begin
  CheckPascal(SMALL);
end;

procedure TTestIpAddressScanPascal.Pascal_NumberSoup_NotInUrl;
begin
  CheckPascal(SOUP);
end;

procedure TTestIpAddressScanPascal.Pascal_Dedupe_ReportedReplacesRejected;
begin
  // 'srv-10.0.0.5' ist ein Produktpraefix, '10.0.0.5' daneben eine
  // Adresse - der gemeldete Treffer ersetzt den verworfenen, in beiden
  // Reihenfolgen.
  CheckPascal(DEDUPE);
end;

procedure TTestIpAddressScanPascal.Pascal_UncHead_IsHost;
begin
  CheckPascal(UNC);
end;

procedure TTestIpAddressScanPascal.Pascal_HostWordBeatsVersionWord;
begin
  CheckPascal(HOST_VS_VERSION);
end;

procedure TTestIpAddressScanPascal.Pascal_VersionWordBeforeNumber;
begin
  CheckPascal(VERSION_BEFORE);
end;

procedure TTestIpAddressScanPascal.Pascal_VersionHead_StaysVersion;
begin
  CheckPascal(VERSION_HEAD);
end;

procedure TTestIpAddressScanPascal.Pascal_IPv6Prefix_RangeBound;
begin
  CheckPascal(V6_PREFIX);
end;

procedure TTestIpAddressScanPascal.Pascal_EscapedPath_IsProduct;
begin
  CheckPascal(ESCAPED);
end;

procedure TTestIpAddressScanPascal.Pascal_Ipv4Word_RescuesSmallNumber;
begin
  CheckPascal(IPV_WORD);
end;

procedure TTestIpAddressScanPascal.Pascal_IpvWordBeatsVersionWord_Pinned;
begin
  // 'Version_IPv4' zerlegt WordParts in 'version' und 'ip': das Host-Wort
  // hebelt das Versions-Gate aus (kein Versionskopf, Versionswort NEBEN
  // einem Host-Wort) und rettet die Kleinzahl - gemeldet. Gegenprobe ohne
  // 'ip': Version.
  Assert.AreEqual('1.2.3.4=',
    PascalGot('  Version_IPv4 := ''1.2.3.4'';'), 'Version_IPv4');
  Assert.AreEqual('1.2.3.4=version',
    PascalGot('  Version_V4 := ''1.2.3.4'';'), 'Version_V4');
  // 'myipv4' bleibt EIN Wort 'myipv' - 'IPv4' zaehlt nur am Wortanfang
  // (auch nach einem Camel-Bruch), nicht mitten im Wort.
  Assert.AreEqual('1.2.3.4=small-number',
    PascalGot('  myipv4 := ''1.2.3.4'';'), 'myipv4 ist kein Host-Wort');
end;

procedure TTestIpAddressScanPascal.Pascal_DedupePos_OverTwoLiterals;
var
  H    : TArray<TCodeIpHit>;
  Code : string;
begin
  // Gemeldet im ERSTEN Literal, verworfen (Produktpraefix) im zweiten:
  // der Eintrag bleibt beim ersten - Pos zeigt auf dessen Quote.
  Code := '  A := ''10.0.0.5''; B := ''srv-10.0.0.5'';';
  H := TIpAddressScan.ScanPascalCode(Code);
  // (Meldungen ohne das Wort "des" - SCA162 liest es als DES.)
  Assert.AreEqual<Integer>(1, Length(H), 'gemeldet/verworfen: ein Treffer');
  Assert.AreEqual('', H[0].Reason, 'gemeldet/verworfen: gemeldet');
  Assert.AreEqual<Integer>(8, H[0].Pos, 'gemeldet/verworfen: Quote vom ersten Literal');
  // Umgekehrt: der gemeldete Treffer im zweiten Literal ersetzt den
  // verworfenen - Pos wandert zum zweiten Literal.
  Code := '  A := ''srv-10.0.0.5''; B := ''10.0.0.5'';';
  H := TIpAddressScan.ScanPascalCode(Code);
  Assert.AreEqual<Integer>(1, Length(H), 'verworfen/gemeldet: ein Treffer');
  Assert.AreEqual('', H[0].Reason, 'verworfen/gemeldet: gemeldet');
  Assert.AreEqual<Integer>(29, H[0].Pos, 'verworfen/gemeldet: Quote vom zweiten Literal');
  // Beide gemeldet: ein Eintrag, der erste bleibt.
  Code := '  A := ''10.0.0.5''; B := ''10.0.0.5'';';
  H := TIpAddressScan.ScanPascalCode(Code);
  Assert.AreEqual<Integer>(1, Length(H), 'beide gemeldet: ein Treffer');
  Assert.AreEqual<Integer>(8, H[0].Pos, 'beide gemeldet: Quote vom ersten Literal');
  // Beide verworfen: ein Eintrag mit dem Grund vom ersten Literal.
  Code := '  A := ''srv-10.0.0.5''; B := ''app-10.0.0.5'';';
  H := TIpAddressScan.ScanPascalCode(Code);
  Assert.AreEqual<Integer>(1, Length(H), 'beide verworfen: ein Treffer');
  Assert.AreEqual('product', H[0].Reason, 'beide verworfen: Grund vom ersten Literal');
  Assert.AreEqual<Integer>(8, H[0].Pos, 'beide verworfen: Quote vom ersten Literal');
end;

procedure TTestIpAddressScanPascal.Pascal_Positions_QuoteOfTheLiteral;
var
  H    : TArray<TCodeIpHit>;
  Code : string;
begin
  Code := 'a := 1;'#10'  b := ''10.1.2.3'';'#10;
  H := TIpAddressScan.ScanPascalCode(Code);
  Assert.AreEqual<Integer>(1, Length(H), 'ein Treffer');
  Assert.IsTrue((Code[H[0].Pos] = '''') and (H[0].Pos > 8),
    'Pos zeigt auf das oeffnende Quote in Zeile 2');
end;

procedure TTestIpAddressScanPascal.Pascal_SameAddressTwoLines_TwoHits;
begin
  Assert.AreEqual<Integer>(2, Length(TIpAddressScan.ScanPascalCode(
    'a := ''10.1.2.3'';'#10'b := ''10.1.2.3'';')),
    'gleiche Adresse in zwei Zeilen = zwei Treffer');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestIpAddressScanPascal);

end.
