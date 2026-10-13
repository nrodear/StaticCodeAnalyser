unit uTestIpAddressScanIni;

// Tests fuer uIpAddressScan (SCA201), Teil 4: ScanIniLines - Kommentar-
// und Sektionszeilen, Schluessel/Wert, die Gates mit Schluessel und
// Sektion als Kontext (Fliesstext-, Versions- und Host-Schluessel), die
// Meldetexte und die Laufzeit einer langen Zeile. Versioniert aus dem
// FPC-Pruefstand (Review 2026-10-13).

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.DateUtils,
  uIpAddressScan, uTestIpAddressScanKit;

type
  [TestFixture]
  TTestIpAddressScanIni = class
  public
    [Test] procedure Ini_Lines_SectionKeyAndReason;
    [Test] procedure Ini_Messages_CodeAndIni;
    [Test] procedure Ini_UncAndVersionKeys;
    [Test] procedure Ini_ProseKeys_TextKeyUnlessHost;
    [Test] procedure Ini_IPv6PrefixAndDedupe;
    [Test] procedure Ini_SectionHeadWithComment;
    [Test] procedure Ini_HostCompoundAndSection_RescueSmallNumber;
    [Test] procedure Ini_Ipv4Key_RescuesSmallNumber;
    [Test] procedure Ini_LongLine_StaysLinear;
  end;

implementation

const
  // 13 Zeilen, 8 Treffer (Zeile 1-basiert, Grund '' = melden).
  SAMPLE: array[0..12] of string = (
    '; Server=10.0.0.1',                                     // 1
    '# x=10.0.0.1',                                          // 2
    '[Database]',                                            // 3
    'Server=10.0.0.1 ; prod',                                // 4
    'FileVersion=1.2.3.4',                                   // 5
    'Host=127.0.0.1',                                        // 6
    'description=Returns 10.1.2.3 for the lookup',           // 7
    '[Servicos]',                                            // 8
    'ProRecepcionar=http://191.252.58.191:83/soap/INFSe',    // 9
    'Url=http://10.1.2.3/a, http://10.1.2.3/b',              // 10
    '10.20.30.40',                                           // 11
    '   ;  Proxy=10.9.9.9',                                  // 12
    'IP Address = 172.16.5.20');                             // 13

  LONG_LINE_ADDRESSES = 4000;
  LONG_LINE_BUDGET_MS = 2000;   // vor dem Zeiger in CountOtherFractions ~88 s

function SampleHits: TArray<TIniIpHit>;
var
  L : TStringList;
  i : Integer;
begin
  L := TStringList.Create;
  try
    for i := 0 to High(SAMPLE) do
      L.Add(SAMPLE[i]);
    Result := TIpAddressScan.ScanIniLines(L);
  finally
    L.Free;
  end;
end;

procedure CheckHit(const AHits: TArray<TIniIpHit>; AIndex, ALine: Integer;
  const AExpected: string);
// AExpected = 'Sektion/Schluessel:Text=Grund'.
var
  H : TIniIpHit;
begin
  Assert.IsTrue(AIndex <= High(AHits), Format('INI-Treffer %d fehlt (nur %d)',
    [AIndex, Length(AHits)]));
  H := AHits[AIndex];
  Assert.AreEqual<Integer>(ALine, H.Line, Format('Zeile von Treffer %d', [AIndex]));
  Assert.AreEqual(AExpected, H.Section + '/' + H.Key + ':' + H.Hit.Text + '=' + H.Reason,
    Format('Treffer %d', [AIndex]));
end;

procedure TTestIpAddressScanIni.Ini_Lines_SectionKeyAndReason;
var
  H : TArray<TIniIpHit>;
begin
  H := SampleHits;
  Assert.AreEqual<Integer>(8, Length(H), 'Trefferzahl');
  CheckHit(H, 0, 4, 'Database/Server:10.0.0.1=');
  CheckHit(H, 1, 5, 'Database/FileVersion:1.2.3.4=version');
  CheckHit(H, 2, 6, 'Database/Host:127.0.0.1=class');
  CheckHit(H, 3, 7, 'Database/description:10.1.2.3=text-key');
  CheckHit(H, 4, 9, 'Servicos/ProRecepcionar:191.252.58.191=');
  CheckHit(H, 5, 10, 'Servicos/Url:10.1.2.3=');
  CheckHit(H, 6, 11, 'Servicos/:10.20.30.40=');
  CheckHit(H, 7, 13, 'Servicos/IP Address:172.16.5.20=');
end;

procedure TTestIpAddressScanIni.Ini_Messages_CodeAndIni;
var
  H : TArray<TIniIpHit>;
begin
  // Meldetexte sind Fund-Identitaet (englisch, woertlich).
  H := SampleHits;
  Assert.AreEqual<Integer>(8, Length(H), 'Trefferzahl');
  Assert.AreEqual('IP address ''10.0.0.1'' (private, RFC 1918) in [Database] Server - ' +
    'an environment-specific address in a versioned configuration file; ' +
    'prefer a host name or a per-environment setting',
    TIpAddressScan.IniMessage(H[0]), 'IniMessage mit Schluessel');
  Assert.IsTrue(Pos(' in [Servicos] value - ', TIpAddressScan.IniMessage(H[6])) > 0,
    'IniMessage ohne Schluessel: ' + TIpAddressScan.IniMessage(H[6]));
  Assert.AreEqual('Hardcoded IP address ''191.252.58.191'' (public) - move it to ' +
    'the configuration or use a host name',
    TIpAddressScan.CodeMessage(H[4].Hit), 'CodeMessage');
end;

procedure TTestIpAddressScanIni.Ini_UncAndVersionKeys;
begin
  Assert.AreEqual('/Path:192.168.1.10=', IniGot(['Path=\\192.168.1.10\Daten']), 'UNC');
  Assert.AreEqual('/BuildServer:10.0.0.5=', IniGot(['BuildServer=10.0.0.5']), 'BuildServer');
  Assert.AreEqual('Server/Version:10.2.3.4=version',
    IniGot(['[Server]', 'Version=10.2.3.4']), '[Server] Version');
  Assert.AreEqual('Oracle/ServerVersion:12.2.0.1=version|Oracle/MinServerVersion:10.2.0.4=version',
    IniGot(['[Oracle]', 'ServerVersion=12.2.0.1', 'MinServerVersion=10.2.0.4']), 'ServerVersion');
  Assert.AreEqual('/Params:192.168.1.20=', IniGot(['Params=BuildServer=192.168.1.20']), 'Params');
  Assert.AreEqual('/ToolDir:2.1.0.5=product', IniGot(['ToolDir=C:\\Tools\\MyLib\\2.1.0.5']), 'ToolDir');
  Assert.AreEqual('/AppInfo:1.0.0.45=version', IniGot(['AppInfo=MyApp Version 1.0.0.45']), 'AppInfo');
end;

procedure TTestIpAddressScanIni.Ini_ProseKeys_TextKeyUnlessHost;
begin
  Assert.AreEqual('/HelpUrl:10.0.0.5=', IniGot(['HelpUrl=http://10.0.0.5:8080/help']), 'HelpUrl');
  Assert.AreEqual('/HelpServer:10.0.0.5=', IniGot(['HelpServer=10.0.0.5']), 'HelpServer');
  Assert.AreEqual('/Description:10.1.2.3=text-key',
    IniGot(['Description=Returns 10.1.2.3 for the lookup']), 'Description');
end;

procedure TTestIpAddressScanIni.Ini_IPv6PrefixAndDedupe;
begin
  Assert.AreEqual('/Endpoint:fd12:3456::=range-bound', IniGot(['Endpoint=fd12:3456::/48']), 'Praefix');
  Assert.AreEqual('/Hosts:10.0.0.5=', IniGot(['Hosts=srv-10.0.0.5,10.0.0.5']), 'Dedupe');
end;

procedure TTestIpAddressScanIni.Ini_SectionHeadWithComment;
begin
  Assert.AreEqual('Database/Server:10.20.30.40=',
    IniGot(['[A]', 'x=1', '[Database] ; prod', 'Server=10.20.30.40']), '; hinter dem Kopf');
  Assert.AreEqual('Database/Server:10.20.30.40=',
    IniGot(['[Database] # prod', 'Server=10.20.30.40']), '# hinter dem Kopf');
  Assert.AreEqual('/[x]:10.20.30.40=', IniGot(['[x]=10.20.30.40']), '[x]= ist ein Schluessel');
end;

procedure TTestIpAddressScanIni.Ini_HostCompoundAndSection_RescueSmallNumber;
begin
  Assert.AreEqual('/DNSSERVER:8.8.8.8=', IniGot(['DNSSERVER=8.8.8.8']), 'DNSSERVER');
  Assert.AreEqual('/nameserver:1.1.1.1=', IniGot(['nameserver=1.1.1.1']), 'nameserver');
  Assert.AreEqual('DNS/Primary:8.8.8.8=', IniGot(['[DNS]', 'Primary=8.8.8.8']), '[DNS]');
  Assert.AreEqual('Misc/Primary:8.8.8.8=small-number', IniGot(['[Misc]', 'Primary=8.8.8.8']), '[Misc]');
end;

procedure TTestIpAddressScanIni.Ini_Ipv4Key_RescuesSmallNumber;
begin
  // Review 2026-10-13: 'IPv4'/'IPv6' im Schluessel oder in der Sektion
  // ist das Host-Wort 'ip'.
  Assert.AreEqual('/IPv4:8.8.8.8=', IniGot(['IPv4=8.8.8.8']), 'IPv4=');
  Assert.AreEqual('IPv6/Primary:1.1.1.1=', IniGot(['[IPv6]', 'Primary=1.1.1.1']), '[IPv6]');
  Assert.AreEqual('/Fallback:1.1.1.1=small-number', IniGot(['Fallback=1.1.1.1']), 'Gegenprobe');
end;

procedure TTestIpAddressScanIni.Ini_LongLine_StaysLinear;
var
  SB   : TStringBuilder;
  Line : string;
  k    : Integer;
  T0   : TDateTime;
  Got  : string;
  Ms   : Int64;
begin
  // 4000 Adressen in einer Zeile: der Zeiger in CountOtherFractions haelt
  // die Zeile linear (vorher ~88 s, quadratische Suche je Bruch).
  SB := TStringBuilder.Create;
  try
    SB.Append('Blocked=');
    for k := 1 to LONG_LINE_ADDRESSES do
      SB.Append(Format('10.%d.%d.7,', [k div 250, k mod 250]));
    Line := SB.ToString;
  finally
    SB.Free;
  end;
  T0 := Now;
  Got := IniGot([Line]);
  Ms := MilliSecondsBetween(Now, T0);
  Assert.IsTrue(Ms < LONG_LINE_BUDGET_MS, Format('%d Adressen: %d ms', [LONG_LINE_ADDRESSES, Ms]));
  Assert.IsTrue(Length(Got) > 0, 'lange Zeile liefert Treffer');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestIpAddressScanIni);

end.
