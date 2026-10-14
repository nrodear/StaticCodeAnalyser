unit uTestIpAddressScanGrammar;

// Tests fuer uIpAddressScan (SCA200/SCA201), Teil 1: Grammatik der
// Kandidatensuche (FindAll), Kontext-Flags, die exakten Parser und die
// Wortteile. Bis zum 2026-10-13 lagen diese Faelle nur im Scratchpad des
// FPC-Pruefstands (iptest.pas, Review-Befund MAJOR) - hier versioniert,
// je [Test] eine Gruppe; die Meldung nennt den Fall.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes,
  uIpAddressScan, uTestIpAddressScanKit;

type
  [TestFixture]
  TTestIpAddressScanGrammar = class
  public
    [Test] procedure IPv4_DottedQuad_Found;
    [Test] procedure IPv4_NotAnAddress;
    [Test] procedure IPv6_Forms_Found;
    [Test] procedure IPv6_NotAnAddress;
    [Test] procedure Flags_UrlPortCidr;
    [Test] procedure Hit_StartAndLen;
    [Test] procedure ParseIPv4_ValueAndRejects;
    [Test] procedure ParseIPv6_Values;
    [Test] procedure ParseIPv6_Rejects;
    [Test] procedure WordParts_CamelAndUnderscore;
    [Test] procedure WordParts_Ipv4Ipv6_IsHostWordIp;
    // Gegen-Review Welle 1, Minor 10: 'IPv4' zaehlt nur am Wortanfang.
    [Test] procedure WordParts_IpvInsideWord_StaysOneWord;
  end;

implementation

const
  V4_FOUND: array[0..6] of TTextCase = (
    (Input: '192.168.12.42'; Expected: '192.168.12.42'),
    (Input: 'http://10.1.2.3:8080/api'; Expected: '10.1.2.3'),
    (Input: 'Server=172.16.0.5;Port=3050'; Expected: '172.16.0.5'),
    (Input: 'Database=192.168.1.5/3050:C:\db\x.fdb'; Expected: '192.168.1.5'),
    (Input: 'Listen on 10.0.0.1.'; Expected: '10.0.0.1'),
    (Input: '10.0.0.0/8'; Expected: '10.0.0.0'),
    (Input: 'a 10.1.2.3 b 10.1.2.4'; Expected: '10.1.2.3|10.1.2.4'));

  // Versionen, OIDs, fuehrende Nullen, Tausender, Platzhalter.
  V4_NONE: array[0..9] of TTextCase = (
    (Input: '1.2.3.4.5'; Expected: ''),
    (Input: '1.3.6.1.4.1.311'; Expected: ''),
    (Input: 'v1.2.3.4'; Expected: ''),
    (Input: '010.001.002.003'; Expected: ''),
    (Input: '1.000.000.000'; Expected: ''),
    (Input: '256.1.1.1'; Expected: ''),
    (Input: '1.2.3.4567'; Expected: ''),
    (Input: '%d.%d.%d.%d'; Expected: ''),
    (Input: '1.2.3'; Expected: ''),
    (Input: ''; Expected: ''));

  V6_FOUND: array[0..10] of TTextCase = (
    (Input: '::'; Expected: '::'),
    (Input: '::1'; Expected: '::1'),
    (Input: 'fe80::1%eth0'; Expected: 'fe80::1'),
    (Input: 'http://[fe80::1%25eth0]/health'; Expected: 'fe80::1'),
    (Input: 'http://[2001:db8::1]:8080/'; Expected: '2001:db8::1'),
    (Input: '::ffff:192.168.1.1'; Expected: '::ffff:192.168.1.1'),
    (Input: '2001:0DB8:85A3:0000:0000:8A2E:0370:7334'; Expected: '2001:0DB8:85A3:0000:0000:8A2E:0370:7334'),
    (Input: 'fd12:3456:789a:1::1'; Expected: 'fd12:3456:789a:1::1'),
    (Input: 'ff02::fb'; Expected: 'ff02::fb'),
    (Input: '3fff:0:1::5'; Expected: '3fff:0:1::5'),
    (Input: '1:2:3:4:5:6:7:8'; Expected: '1:2:3:4:5:6:7:8'));

  // Scope-Operatoren, Uhrzeiten, MAC/EUI-64, Hex ohne Dezimalziffer,
  // zu viele Gruppen, zwei '::', Trenner.
  V6_NONE: array[0..12] of TTextCase = (
    (Input: 'std::vector<int>'; Expected: ''),
    (Input: 'TFoo::Bar'; Expected: ''),
    (Input: '12:30:45'; Expected: ''),
    (Input: 'aa:bb:cc:dd:ee:ff'; Expected: ''),
    (Input: '00:1a:2b:ff:fe:3c:4d:5e'; Expected: ''),
    (Input: 'dead::beef'; Expected: ''),
    (Input: '1:2:3:4:5:6:7:8:9'; Expected: ''),
    (Input: '1::2::3'; Expected: ''),
    (Input: 'hh:nn:ss'; Expected: ''),
    (Input: '2026-10-09T12:30:45Z'; Expected: ''),
    (Input: 'Ab:Cd:Ef:01:23:45:67:89'; Expected: ''),
    (Input: 'x:=1'; Expected: ''),
    (Input: '(?::='; Expected: ''));

procedure CheckFindAll(const ACases: array of TTextCase);
var
  i : Integer;
begin
  for i := 0 to High(ACases) do
    Assert.AreEqual(ACases[i].Expected, HitsText(ACases[i].Input),
      'FindAll(' + ACases[i].Input + ')');
end;

function JoinWords(const AWords: TArray<string>): string;
// Jeder Teil mit ',' dahinter - so sieht man auch das letzte Wort enden.
var
  SB : TStringBuilder;
  W  : string;
begin
  SB := TStringBuilder.Create;
  try
    for W in AWords do
      SB.Append(W).Append(',');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TTestIpAddressScanGrammar.IPv4_DottedQuad_Found;
begin
  CheckFindAll(V4_FOUND);
end;

procedure TTestIpAddressScanGrammar.IPv4_NotAnAddress;
begin
  CheckFindAll(V4_NONE);
end;

procedure TTestIpAddressScanGrammar.IPv6_Forms_Found;
begin
  CheckFindAll(V6_FOUND);
end;

procedure TTestIpAddressScanGrammar.IPv6_NotAnAddress;
begin
  CheckFindAll(V6_NONE);
end;

procedure TTestIpAddressScanGrammar.Flags_UrlPortCidr;
var
  H : TArray<TIpHit>;
begin
  H := TIpAddressScan.FindAll('http://10.1.2.3:8080/api');
  Assert.IsTrue((Length(H) = 1) and H[0].InUrl and H[0].HasPort and not H[0].HasCidr,
    'Flags URL+Port');
  H := TIpAddressScan.FindAll('10.0.0.0/8');
  Assert.IsTrue((Length(H) = 1) and H[0].HasCidr and not H[0].HasPort, 'Flags CIDR');
  H := TIpAddressScan.FindAll('http://[2001:db8::1]:8080/');
  Assert.IsTrue((Length(H) = 1) and H[0].InUrl and H[0].HasPort and (H[0].Family = ifV6),
    'Flags v6 URL+Port');
end;

procedure TTestIpAddressScanGrammar.Hit_StartAndLen;
var
  H : TArray<TIpHit>;
begin
  H := TIpAddressScan.FindAll('x 10.1.2.3');
  Assert.IsTrue((Length(H) = 1) and (H[0].Start = 3) and (H[0].Len = 8), 'Start/Len');
end;

procedure TTestIpAddressScanGrammar.ParseIPv4_ValueAndRejects;
var
  V : Cardinal;
begin
  Assert.IsTrue(TIpAddressScan.TryParseIPv4('1.2.3.4', V) and (V = $01020304), 'v4 Wert');
  Assert.IsFalse(TIpAddressScan.TryParseIPv4('1.2.3.04', V), 'v4 fuehrende Null');
  Assert.IsFalse(TIpAddressScan.TryParseIPv4('1.2.3', V), 'v4 drei Teile');
  Assert.IsFalse(TIpAddressScan.TryParseIPv4(' 1.2.3.4', V), 'v4 Leerzeichen');
end;

procedure TTestIpAddressScanGrammar.ParseIPv6_Values;
var
  W : TIpv6Words;
begin
  Assert.IsTrue(TIpAddressScan.TryParseIPv6('1:2:3:4:5:6:7:8', W)
    and (W[0] = 1) and (W[7] = 8), 'v6 voll');
  Assert.IsTrue(TIpAddressScan.TryParseIPv6('1::8', W)
    and (W[0] = 1) and (W[7] = 8) and (W[3] = 0), 'v6 ::');
  Assert.IsTrue(TIpAddressScan.TryParseIPv6('::ffff:1.2.3.4', W)
    and (W[5] = $FFFF) and (W[6] = $0102) and (W[7] = $0304), 'v6 mapped');
  Assert.IsTrue(TIpAddressScan.TryParseIPv6('1:2:3:4:5:6:1.2.3.4', W)
    and (W[5] = 6) and (W[6] = $0102), 'v6 voll+v4');
end;

procedure TTestIpAddressScanGrammar.ParseIPv6_Rejects;
var
  W : TIpv6Words;
begin
  Assert.IsFalse(TIpAddressScan.TryParseIPv6('1:2:3:4:5:6:7:8:9', W), 'v6 9 Gruppen');
  Assert.IsFalse(TIpAddressScan.TryParseIPv6('1:2:3:4:5:6:7::8', W), 'v6 :: mit 8 Gruppen');
  Assert.IsFalse(TIpAddressScan.TryParseIPv6('12345::1', W), 'v6 5 Hex');
  Assert.IsFalse(TIpAddressScan.TryParseIPv6(':1::2', W), 'v6 fuehrendes :');
  Assert.IsFalse(TIpAddressScan.TryParseIPv6('1:2:3:4:5:6:7:1.2.3.4', W), 'v6 7+v4');
  Assert.IsFalse(TIpAddressScan.TryParseIPv6('::1.2.3', W), 'v6 v4-Rest unvollstaendig');
end;

procedure TTestIpAddressScanGrammar.WordParts_CamelAndUnderscore;
begin
  Assert.AreEqual('f,root,dns,net,add,',
    JoinWords(TIpAddressScan.WordParts('FRootDNS_NET.Add(')), 'FRootDNS_NET');
  Assert.AreEqual('lcl,version,sz,oid,dsalg,ip,address,ver,proc,',
    JoinWords(TIpAddressScan.WordParts('LCLVersion szOID_DSALG IPAddress verProc')), 'gemischt');
  Assert.AreEqual('servers,', JoinWords(TIpAddressScan.WordParts('SERVERS')), 'SERVERS');
end;

procedure TTestIpAddressScanGrammar.WordParts_Ipv4Ipv6_IsHostWordIp;
begin
  // Review 2026-10-13: die Camel-Regel zerlegte 'IPv4' in 'i' und 'pv' -
  // kein Host-Wort, 'LocalIPv4 := ''8.8.8.8''' verlor die Kleinzahl-Rettung.
  Assert.AreEqual('local,ip,', JoinWords(TIpAddressScan.WordParts('LocalIPv4')), 'LocalIPv4');
  Assert.AreEqual('ip,address,', JoinWords(TIpAddressScan.WordParts('IPv6Address')), 'IPv6Address');
  Assert.AreEqual('ip,', JoinWords(TIpAddressScan.WordParts('ipv4')), 'ipv4');
  Assert.AreEqual('ip,addr,', JoinWords(TIpAddressScan.WordParts('IPV4_ADDR')), 'IPV4_ADDR');
  Assert.AreEqual('server,ip,', JoinWords(TIpAddressScan.WordParts('ServerIpv6')), 'ServerIpv6');
  // kein Treffer: 'IPvoid' ist kein IPv4/IPv6, 'ipv' ohne Ziffer auch nicht
  Assert.AreEqual('i,pvoid,', JoinWords(TIpAddressScan.WordParts('IPvoid')), 'IPvoid');
  Assert.AreEqual('ipv,', JoinWords(TIpAddressScan.WordParts('ipv')), 'ipv');
end;

procedure TTestIpAddressScanGrammar.WordParts_IpvInsideWord_StaysOneWord;
begin
  // 'myipv4' ist EIN Wort 'myipv' (die Ziffer beendet es) - 'ip' entsteht
  // nur am Wortanfang oder hinter einem Camel-Bruch ('MyIPv4').
  Assert.AreEqual('myipv,', JoinWords(TIpAddressScan.WordParts('myipv4')), 'myipv4');
  Assert.AreEqual('my,ip,', JoinWords(TIpAddressScan.WordParts('MyIPv4')), 'MyIPv4');
  Assert.AreEqual('version,ip,', JoinWords(TIpAddressScan.WordParts('Version_IPv4')),
    'Version_IPv4');
  Assert.AreEqual('help,ip,', JoinWords(TIpAddressScan.WordParts('help_ipv4')),
    'help_ipv4');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestIpAddressScanGrammar);

end.
