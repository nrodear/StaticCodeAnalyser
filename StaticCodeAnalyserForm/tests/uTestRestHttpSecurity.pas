unit uTestRestHttpSecurity;

// Tests fuer TRestHttpSecurityDetector (SCA115-116).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRestHttpSecurity = class
  public
    // HttpInsteadOfHttps
    [Test] procedure HttpRemoteUrl_Reported;
    [Test] procedure HttpsRemoteUrl_NotReported;
    [Test] procedure HttpLocalhost_NotReported;
    [Test] procedure XmlNamespace_NotReported;

    // DisabledTlsVerification
    [Test] procedure EmptySecureProtocols_Reported;
    [Test] procedure IgnoreCertificateErrors_Reported;
    [Test] procedure OnVerifyPeerNil_Reported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestRestHttpSecurity.HttpRemoteUrl_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'const API_URL = ''http://api.example.com/v1/users'';';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
      'genau 1 HttpInsteadOfHttps-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'http://api.example.com'),
      TFindingHelper.FirstOf(F, fkHttpInsteadOfHttps).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.HttpsRemoteUrl_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'const API_URL = ''https://api.example.com/v1/users'';';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHttpInsteadOfHttps));
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.HttpLocalhost_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'const DEV_API = ''http://localhost:8080/api'';'#13#10 +
  'const LOCAL_API = ''http://127.0.0.1/api'';';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
    'Localhost-URLs sind in der Whitelist - kein Befund');
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.XmlNamespace_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'const NS = ''http://schemas.xmlsoap.org/soap/envelope/'';';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
    'XML-Namespace-URI ist eine Identitaet, kein Netz-Aufruf');
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.EmptySecureProtocols_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Client.SecureProtocols := [];'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDisabledTlsVerification),
      'genau 1 DisabledTls-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'SecureProtocols := []'),
      TFindingHelper.FirstOf(F, fkDisabledTlsVerification).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.IgnoreCertificateErrors_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Client.IgnoreCertificateErrors := True;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDisabledTlsVerification),
      'genau 1 DisabledTls-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'IgnoreCertificateErrors := True'),
      TFindingHelper.FirstOf(F, fkDisabledTlsVerification).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.OnVerifyPeerNil_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'begin'#13#10 +
  '  Client.OnVerifyPeer := nil;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkDisabledTlsVerification),
      'genau 1 DisabledTls-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'OnVerifyPeer := nil'),
      TFindingHelper.FirstOf(F, fkDisabledTlsVerification).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRestHttpSecurity);

end.
