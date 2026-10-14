unit uTestIpAddressScanClasses;

// Tests fuer uIpAddressScan (SCA200/SCA201), Teil 2: die numerische
// Klassifikation nach der IANA-Registry (ClassifyV4/ClassifyV6),
// IsReportable und die Labels des Meldetexts. Versioniert aus dem FPC-
// Pruefstand (Review 2026-10-13), dazu der neue 2000::/3-Vertrag.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes,
  uIpAddressScan, uTestIpAddressScanKit;

type
  [TestFixture]
  TTestIpAddressScanClasses = class
  public
    [Test] procedure V4_PrivateCgnatPublic;
    [Test] procedure V4_LoopbackUnspecifiedBroadcastNetmask;
    [Test] procedure V4_IanaSpecialPurpose;
    [Test] procedure V6_Low96_UnspecifiedLoopbackMappedNat64;
    [Test] procedure V6_RegistryBlocks;
    [Test] procedure V6_OutsideGlobalUnicast_Reserved;
    // Gegen-Review Welle 1, Minor 10: die Raender von 2000::/3 und der
    // Dokumentationsblock 3fff::/20 - '1fff::1' liegt knapp darunter,
    // '2002::' (6to4) ist oeffentlich, auch mit Null-Interface-ID.
    [Test] procedure V6_GlobalUnicastEdges_Pinned;
    [Test] procedure IsReportable_OnlyPrivateCgnatPublic;
    [Test] procedure ClassLabel_UniqueLocalSiteLocalEmbedded;
  end;

implementation

const
  V4_REPORTABLE: array[0..9] of TTextCase = (
    (Input: '10.0.0.255'; Expected: 'private'),
    (Input: '10.1.2.3'; Expected: 'private'),
    (Input: '172.16.0.1'; Expected: 'private'),
    (Input: '172.31.255.1'; Expected: 'private'),
    (Input: '172.32.0.1'; Expected: 'public'),
    (Input: '192.168.0.1'; Expected: 'private'),
    (Input: '100.64.1.1'; Expected: 'cgnat'),
    (Input: '100.128.0.1'; Expected: 'public'),
    (Input: '198.20.0.1'; Expected: 'public'),
    (Input: '8.8.8.8'; Expected: 'public'));

  V4_LOCAL: array[0..6] of TTextCase = (
    (Input: '127.0.0.1'; Expected: 'loopback'),
    (Input: '0.0.0.0'; Expected: 'unspecified'),
    (Input: '0.1.2.3'; Expected: 'unspecified'),
    (Input: '255.255.255.255'; Expected: 'broadcast'),
    (Input: '255.255.255.0'; Expected: 'netmask'),
    (Input: '255.255.0.0'; Expected: 'netmask'),
    (Input: '255.255.0.1'; Expected: 'reserved'));

  V4_IANA: array[0..13] of TTextCase = (
    (Input: '169.254.169.254'; Expected: 'linklocal'),
    (Input: '198.18.0.1'; Expected: 'benchmark'),
    (Input: '198.19.255.1'; Expected: 'benchmark'),
    (Input: '224.0.0.251'; Expected: 'multicast'),
    (Input: '239.1.2.3'; Expected: 'multicast'),
    (Input: '240.0.0.1'; Expected: 'reserved'),
    (Input: '192.0.2.5'; Expected: 'documentation'),
    (Input: '198.51.100.7'; Expected: 'documentation'),
    (Input: '203.0.113.9'; Expected: 'documentation'),
    (Input: '192.0.0.9'; Expected: 'protocol'),
    (Input: '192.88.99.1'; Expected: 'protocol'),
    (Input: '192.31.196.1'; Expected: 'protocol'),
    (Input: '192.52.193.1'; Expected: 'protocol'),
    (Input: '192.175.48.1'; Expected: 'protocol'));

  // ::/96, ::ffff:0:0/96 und 64:ff9b::/96 nach der eingebetteten IPv4.
  V6_LOW96: array[0..8] of TTextCase = (
    (Input: '::'; Expected: 'unspecified'),
    (Input: '::1'; Expected: 'loopback'),
    (Input: '0:0:0:0:0:0:0:1'; Expected: 'loopback'),
    (Input: '::ffff:127.0.0.1'; Expected: 'loopback'),
    (Input: '::ffff:10.1.2.3'; Expected: 'private'),
    (Input: '::ffff:8.8.8.8'; Expected: 'public'),
    (Input: '::1.2.3.4'; Expected: 'reserved'),
    (Input: '64:ff9b::192.0.2.33'; Expected: 'documentation'),
    (Input: '64:ff9b::8.8.8.8'; Expected: 'public'));

  V6_BLOCKS: array[0..18] of TTextCase = (
    (Input: '2001:DB8::1'; Expected: 'documentation'),
    (Input: '2001:0db8::1'; Expected: 'documentation'),
    (Input: '2001:db8:0:0:1::1'; Expected: 'documentation'),
    (Input: '3fff::1'; Expected: 'documentation'),
    (Input: '3fff:fff::1'; Expected: 'documentation'),
    (Input: '3fff:1000::1'; Expected: 'public'),
    (Input: 'fc00::1'; Expected: 'private'),
    (Input: 'fd00::1'; Expected: 'private'),
    (Input: 'fec0::1'; Expected: 'private'),
    (Input: 'fe80::1'; Expected: 'linklocal'),
    (Input: 'febf::1'; Expected: 'linklocal'),
    (Input: 'ff02::1'; Expected: 'multicast'),
    (Input: 'ff15::1234'; Expected: 'multicast'),
    (Input: '64:ff9b:1::1'; Expected: 'protocol'),
    (Input: '2001::1'; Expected: 'protocol'),
    (Input: '2001:1ff::1'; Expected: 'protocol'),
    (Input: '100::1'; Expected: 'protocol'),
    (Input: '2001:200::1'; Expected: 'public'),
    (Input: '2a00:1450::1'; Expected: 'public'));

  // Review 2026-10-13: oeffentlich nur im Global-Unicast-Block 2000::/3
  // (RFC 4291 2.4); unzugewiesene Bloecke sind reserviert, nicht public.
  V6_UNASSIGNED: array[0..7] of TTextCase = (
    (Input: '4000::1'; Expected: 'reserved'),
    (Input: '8000::1'; Expected: 'reserved'),
    (Input: '1234::1'; Expected: 'reserved'),
    (Input: 'c000::1'; Expected: 'reserved'),
    (Input: 'e000::1'; Expected: 'reserved'),
    (Input: '0100:1::1'; Expected: 'reserved'),
    (Input: '2000::1'; Expected: 'public'),
    (Input: '3ffe::1'; Expected: 'public'));

procedure CheckV4(const ACases: array of TTextCase);
var
  i : Integer;
begin
  for i := 0 to High(ACases) do
    Assert.AreEqual(ACases[i].Expected, ClassNameV4(ACases[i].Input),
      'ClassifyV4(' + ACases[i].Input + ')');
end;

procedure CheckV6(const ACases: array of TTextCase);
var
  i : Integer;
begin
  for i := 0 to High(ACases) do
    Assert.AreEqual(ACases[i].Expected, ClassNameV6(ACases[i].Input),
      'ClassifyV6(' + ACases[i].Input + ')');
end;

procedure TTestIpAddressScanClasses.V4_PrivateCgnatPublic;
begin
  CheckV4(V4_REPORTABLE);
end;

procedure TTestIpAddressScanClasses.V4_LoopbackUnspecifiedBroadcastNetmask;
begin
  CheckV4(V4_LOCAL);
end;

procedure TTestIpAddressScanClasses.V4_IanaSpecialPurpose;
begin
  CheckV4(V4_IANA);
end;

procedure TTestIpAddressScanClasses.V6_Low96_UnspecifiedLoopbackMappedNat64;
begin
  CheckV6(V6_LOW96);
end;

procedure TTestIpAddressScanClasses.V6_RegistryBlocks;
begin
  CheckV6(V6_BLOCKS);
end;

procedure TTestIpAddressScanClasses.V6_OutsideGlobalUnicast_Reserved;
begin
  CheckV6(V6_UNASSIGNED);
end;

procedure TTestIpAddressScanClasses.V6_GlobalUnicastEdges_Pinned;
const
  EDGES: array[0..5] of TTextCase = (
    (Input: '1fff::1'; Expected: 'reserved'),        // knapp unter 2000::/3
    (Input: '2000::'; Expected: 'public'),           // untere Kante
    (Input: '2002::'; Expected: 'public'),           // 6to4, Interface-ID null
    (Input: '2002:c000:0204::1'; Expected: 'public'),
    (Input: '3fff::1'; Expected: 'documentation'),   // 3fff::/20
    (Input: '3fff:1000::1'; Expected: 'public'));    // hinter 3fff:0fff
begin
  CheckV6(EDGES);
end;

procedure TTestIpAddressScanClasses.IsReportable_OnlyPrivateCgnatPublic;
var
  C : TIpClass;
begin
  for C := Low(TIpClass) to High(TIpClass) do
    Assert.AreEqual(
      BoolToStr(C in [ipcPrivate, ipcCgnat, ipcPublic], True),
      BoolToStr(TIpAddressScan.IsReportable(C), True), 'IsReportable ' + CLS_NAMES[C]);
end;

procedure TTestIpAddressScanClasses.ClassLabel_UniqueLocalSiteLocalEmbedded;
begin
  Assert.AreEqual('unique local', LabelOf('fd00::5'), 'fd00::5');
  Assert.AreEqual('site-local', LabelOf('fec0::1:2'), 'fec0::1:2');
  Assert.AreEqual('private, RFC 1918', LabelOf('::ffff:10.1.2.3'), 'mapped');
  Assert.AreEqual('private, RFC 1918', LabelOf('64:ff9b::10.1.2.3'), 'NAT64');
  Assert.AreEqual('shared, RFC 6598', LabelOf('::ffff:100.64.1.2'), 'mapped CGNAT');
  Assert.AreEqual('public', LabelOf('2a00:1450::1'), 'public v6');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestIpAddressScanClasses);

end.
