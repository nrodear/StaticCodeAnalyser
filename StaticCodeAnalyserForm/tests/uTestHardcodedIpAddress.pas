unit uTestHardcodedIpAddress;

// Tests fuer SCA200 HardcodedIpAddress (THardcodedIpAddressDetector).
//
// Die Grammatik-, Klassen- und Gate-Faelle im Detail laufen im FPC-
// Pruefstand gegen uIpAddressScan (168 Faelle, Scratchpad fpc-ip); hier
// steht der Detektor im echten Weg: Datei lesen, Kommentar-Strip, Zeile
// ueber LineFor, Testpfad-Gate, Pipeline mit Suppression und
// Konfidenzfilter, Katalogbeispiel.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

type
  [TestFixture]
  TTestHardcodedIpAddress = class
  public
    // ---- gemeldet ----
    [Test] procedure PrivateAddressInConstant_Reported;
    [Test] procedure PublicAddressAsArgument_Reported;
    [Test] procedure AddressInUrlWithPort_Reported;
    [Test] procedure IPv6Forms_Reported;
    [Test] procedure SmallPublicAddressWithHostWord_Reported;
    // ---- nicht gemeldet ----
    [Test] procedure SpecialPurposeAddresses_NoFinding;
    [Test] procedure NotAnAddress_NoFinding;
    [Test] procedure VersionAndOidContext_NoFinding;
    [Test] procedure RangeBounds_NoFinding;
    [Test] procedure Comments_NoFinding;
    // ---- Fundstelle und Menge ----
    [Test] procedure Finding_KindSeverityAndMessage;
    [Test] procedure MultiLineStatement_LineOfTheLiteral;
    [Test] procedure SameAddressTwiceInLine_OneFinding;
    [Test] procedure SameAddressOnTwoLines_TwoFindings;
    // ---- Testpfad, Pipeline, Katalog ----
    [Test] procedure TestDirectory_NoFinding;
    [Test] procedure Pipeline_ReportedAndSuppressible;
    [Test] procedure CatalogExample_BadReported_GoodClean;
  end;

implementation

uses
  System.IOUtils,
  uAstNode, uParser2, uRuleCatalog, uHardcodedIpAddress;

// Eine Unit mit ABody im Rumpf einer Routine.
function InUnit(const ABody: string): string;
begin
  Result :=
    'unit IpSample;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Run;'#13#10 +
    'begin'#13#10 +
    ABody + #13#10 +
    'end;'#13#10 +
    'end.';
end;

function IpCount(const ASource: string): Integer;
var
  F : TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(ASource);
  try
    Result := TFindingHelper.Count(F, fkHardcodedIpAddress);
  finally
    F.Free;
  end;
end;

// Detektor direkt auf einer Datei unter ARelPath (Testpfad-Gate braucht
// einen frei waehlbaren Pfad - FindingsOfFile schreibt immer nach Temp).
function IpCountAt(const ASource, ARelPath: string): Integer;
var
  Dir, Path : string;
  Parser    : TParser2;
  Root      : TAstNode;
  Res       : TObjectList<TLeakFinding>;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'sca_ip_' + TGuid.NewGuid.ToString);
  Path := TPath.Combine(Dir, ARelPath);
  TDirectory.CreateDirectory(ExtractFilePath(Path));
  TFile.WriteAllText(Path, ASource, TEncoding.UTF8);
  Res := TObjectList<TLeakFinding>.Create(True);
  try
    Parser := TParser2.Create;
    try
      Root := Parser.ParseFile(Path);
      try
        THardcodedIpAddressDetector.AnalyzeUnit(Root, Path, Res);
      finally
        Root.Free;
      end;
    finally
      Parser.Free;
    end;
    Result := TFindingHelper.Count(Res, fkHardcodedIpAddress);
  finally
    Res.Free;
    try TDirectory.Delete(Dir, True); except end;
  end;
end;

{ ---- gemeldet ---- }

procedure TTestHardcodedIpAddress.PrivateAddressInConstant_Reported;
begin
  Assert.AreEqual<Integer>(1, IpCount(
    'unit IpSample;'#13#10'interface'#13#10'const'#13#10 +
    '  SERVER_IP = ''10.20.30.40'';'#13#10'implementation'#13#10'end.'));
end;

procedure TTestHardcodedIpAddress.PublicAddressAsArgument_Reported;
begin
  Assert.AreEqual<Integer>(1, IpCount(InUnit('  Client.Connect(''203.12.34.56'', 80);')));
end;

procedure TTestHardcodedIpAddress.AddressInUrlWithPort_Reported;
begin
  // SCA115 meldet dieselbe Zeile (http) - beide Regeln, Entscheidung E4.
  Assert.AreEqual<Integer>(1, IpCount(InUnit(
    '  URL := ''http://192.168.1.153:3000/api'';')));
end;

procedure TTestHardcodedIpAddress.IPv6Forms_Reported;
begin
  Assert.AreEqual<Integer>(4, IpCount(InUnit(
    '  A := ''fd00::5'';'#13#10 +
    '  B := ''https://[2a00:1450::1]:443/x'';'#13#10 +
    '  C := ''::ffff:10.1.2.3'';'#13#10 +
    '  D := ''2a00:1450:4001:82a::200e'';')));
end;

procedure TTestHardcodedIpAddress.SmallPublicAddressWithHostWord_Reported;
begin
  // '8.8.8.8' hat Versionsform - mit 'Dns' im Code der Zeile ist es eine
  // Adresse, ohne nicht.
  Assert.AreEqual<Integer>(1, IpCount(InUnit('  DnsServer := ''8.8.8.8'';')));
  Assert.AreEqual<Integer>(0, IpCount(InUnit('  X := ''8.8.8.8'';')));
end;

{ ---- nicht gemeldet ---- }

procedure TTestHardcodedIpAddress.SpecialPurposeAddresses_NoFinding;
begin
  Assert.AreEqual<Integer>(0, IpCount(InUnit(
    '  A := ''127.0.0.1''; B := ''::1''; C := ''0.0.0.0''; D := ''::'';'#13#10 +
    '  E := ''255.255.255.255''; F := ''255.255.255.0'';'#13#10 +
    '  G := ''192.0.2.10''; H := ''198.51.100.7''; I := ''203.0.113.9'';'#13#10 +
    '  J := ''2001:db8::1''; K := ''3fff::1''; L := ''169.254.169.254'';'#13#10 +
    '  M := ''fe80::1%eth0''; N := ''224.0.0.251''; O := ''ff02::fb'';'#13#10 +
    '  P := ''198.18.0.1''; Q := ''240.0.0.1''; R := ''::ffff:127.0.0.1'';')));
end;

procedure TTestHardcodedIpAddress.NotAnAddress_NoFinding;
begin
  Assert.AreEqual<Integer>(0, IpCount(InUnit(
    '  A := ''1.2.3.4.5''; B := ''1.3.6.1.4.1.311''; C := ''v1.2.3.4'';'#13#10 +
    '  D := ''010.001.002.003''; E := ''256.1.1.1''; F := ''std::vector'';'#13#10 +
    '  G := ''12:30:45''; H := ''00:1A:2B:3C:4D:5E''; I := Format(''%d.%d.%d.%d'', [1, 2, 3, 4]);'#13#10 +
    '  J := ''dead::beef''; K := ''1.000.000.000''; L := ''Chrome/141.0.0.1'';')));
end;

procedure TTestHardcodedIpAddress.VersionAndOidContext_NoFinding;
begin
  Assert.AreEqual<Integer>(0, IpCount(InUnit(
    '  Ide.verProc := ''10.1.2.3'';'#13#10 +
    '  FileVersion := ''172.16.5.4'';'#13#10 +
    '  OidCommonName := ''2.5.4.3'';'#13#10 +
    '  szOID_Test := ''10.20.30.40'';')));
end;

procedure TTestHardcodedIpAddress.RangeBounds_NoFinding;
begin
  Assert.AreEqual<Integer>(0, IpCount(InUnit(
    '  Ranges[0] := ''10.0.0.0''; Ranges[1] := ''10.255.255.255'';'#13#10 +
    '  Net := ''192.168.0.0/16'';')));
end;

procedure TTestHardcodedIpAddress.Comments_NoFinding;
begin
  Assert.AreEqual<Integer>(0, IpCount(InUnit(
    '  // Host := ''10.20.30.40'';'#13#10 +
    '  { Host := ''10.20.30.41''; }'#13#10 +
    '  (* Host := ''10.20.30.42''; *)'#13#10 +
    '  X := 1; // 10.20.30.43')));
end;

{ ---- Fundstelle und Menge ---- }

procedure TTestHardcodedIpAddress.Finding_KindSeverityAndMessage;
var
  Src : string;
  F   : TObjectList<TLeakFinding>;
  X   : TLeakFinding;
begin
  Src := InUnit('  Host := ''10.20.30.40'';');
  F := TFindingHelper.FindingsOfFile(Src);
  try
    X := TFindingHelper.FirstOf(F, fkHardcodedIpAddress);
    Assert.IsNotNull(X, 'kein SCA200-Fund');
    Assert.AreEqual<Integer>(Ord(lsWarning), Ord(X.Severity), 'Severity');
    Assert.AreEqual(TFindingHelper.LineOf(Src, 'Host :='), X.LineNumber, 'Zeile');
    Assert.AreEqual('Hardcoded IP address ''10.20.30.40'' (private, RFC 1918) - ' +
      'move it to the configuration or use a host name', X.MissingVar);
  finally
    F.Free;
  end;
end;

procedure TTestHardcodedIpAddress.MultiLineStatement_LineOfTheLiteral;
var
  Src : string;
  F   : TObjectList<TLeakFinding>;
  X   : TLeakFinding;
begin
  Src := InUnit('  Client.Connect('#13#10'    ''10.20.30.40'','#13#10'    80);');
  F := TFindingHelper.FindingsOfFile(Src);
  try
    X := TFindingHelper.FirstOf(F, fkHardcodedIpAddress);
    Assert.IsNotNull(X, 'kein SCA200-Fund');
    Assert.AreEqual(TFindingHelper.LineOf(Src, '''10.20.30.40'''), X.LineNumber);
  finally
    F.Free;
  end;
end;

procedure TTestHardcodedIpAddress.SameAddressTwiceInLine_OneFinding;
begin
  Assert.AreEqual<Integer>(1, IpCount(InUnit(
    '  A := ''10.20.30.40''; B := ''10.20.30.40'';')));
end;

procedure TTestHardcodedIpAddress.SameAddressOnTwoLines_TwoFindings;
begin
  Assert.AreEqual<Integer>(2, IpCount(InUnit(
    '  A := ''10.20.30.40'';'#13#10'  B := ''10.20.30.40'';')));
end;

{ ---- Testpfad, Pipeline, Katalog ---- }

procedure TTestHardcodedIpAddress.TestDirectory_NoFinding;
const
  SRC = 'unit IpSample;'#13#10'interface'#13#10'const'#13#10 +
        '  SERVER_IP = ''10.20.30.40'';'#13#10'implementation'#13#10'end.';
begin
  Assert.AreEqual<Integer>(1, IpCount(SRC), 'Gegenprobe ausserhalb tests');
  Assert.AreEqual<Integer>(0, IpCountAt(SRC, 'tests\IpSample.pas'), 'tests\');
  Assert.AreEqual<Integer>(0, IpCountAt(SRC, 'src\uTestIpSample.pas'), 'uTest*.pas');
  Assert.AreEqual<Integer>(1, IpCountAt(SRC, 'src\IpSample.pas'), 'src\ meldet');
end;

procedure TTestHardcodedIpAddress.Pipeline_ReportedAndSuppressible;
var
  F : TObjectList<TLeakFinding>;
begin
  // Default-Konfidenz (fcMedium): SCA200 bleibt sichtbar.
  F := TFindingHelper.FindingsViaPipeline(InUnit('  Host := ''10.20.30.40'';'));
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedIpAddress), 'sichtbar');
  finally
    F.Free;
  end;
  F := TFindingHelper.FindingsViaPipeline(InUnit(
    '  // noinspection HardcodedIpAddress'#13#10'  Host := ''10.20.30.40'';'));
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedIpAddress), 'unterdrueckt');
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkUnusedSuppression), 'Marker verbraucht');
  finally
    F.Free;
  end;
end;

procedure TTestHardcodedIpAddress.CatalogExample_BadReported_GoodClean;
var
  Meta : TRuleMeta;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkHardcodedIpAddress);
  Assert.AreEqual('SCA200', Meta.ID);
  Assert.AreEqual<Integer>(1, IpCount(InUnit('  ' + Meta.BadExample)), Meta.BadExample);
  Assert.AreEqual<Integer>(0, IpCount(InUnit('  ' + Meta.GoodExample)), Meta.GoodExample);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestHardcodedIpAddress);

end.
