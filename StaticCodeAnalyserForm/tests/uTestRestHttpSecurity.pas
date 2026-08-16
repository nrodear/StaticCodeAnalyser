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
    // Real-World FP-Audit 2026-07-10 Regression (local-ipc-uri)
    [Test] procedure HttpUnixSocket_NotReported;
    [Test] procedure XmlNamespace_NotReported;
    // FP-Audit Stufe 2 (2026-08-16): reservierte Doku-/Test-Adressen
    [Test] procedure ReservedDocHosts_NotReported;
    [Test] procedure PrivateLanAddress_StillReported;
    [Test] procedure LookalikeLocalhost_StillReported;

    // DisabledTlsVerification
    [Test] procedure EmptySecureProtocols_Reported;
    [Test] procedure IgnoreCertificateErrors_Reported;
    [Test] procedure OnVerifyPeerNil_Reported;
  end;

implementation

// noinspection-file HttpInsteadOfHttps
// Saemtliche http://-Literale dieser Unit sind FIXTUREN fuer genau den
// Detektor, der sie meldet - sie beschreiben, was er sehen soll, und sind
// nie ein echter Endpunkt. Ohne die Unterdrueckung meldet der Self-Scan
// jede neue Testzeile als eigenen Sicherheitsbefund.

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestRestHttpSecurity.HttpRemoteUrl_Reported;
// Der Host war bis 2026-08-16 'api.example.com' - der ist seit FIX-1
// whitelisted (RFC 2606, fuer Doku reserviert). Ein Test darf nicht auf
// einem Host stehen, den die Regel bewusst ausnimmt, sonst zwingt er
// jemanden, die Whitelist wieder aufzumachen.
const SRC =
  'unit t; implementation'#13#10 +
  'const API_URL = ''http://api.contoso-shop.de/v1/users'';';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
      'genau 1 HttpInsteadOfHttps-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'http://api.contoso-shop.de'),
      TFindingHelper.FirstOf(F, fkHttpInsteadOfHttps).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.ReservedDocHosts_NotReported;
// FP-Audit Stufe 2 (2026-08-16): fuer Doku und Tests reservierte Adressen
// koennen gar kein erreichbarer Endpunkt sein - 11 von 47 Sample-FP waren
// Parser-Fixturen und Assertion-Erwartungswerte dieser Form.
const SRC =
  'unit t; implementation'#13#10 +
  'const U1 = ''http://example.com/path'';'#13#10 +
  'const U2 = ''http://www.example.org/x'';'#13#10 +
  'const U3 = ''http://192.0.2.10:8080/api'';'#13#10 +
  'const U4 = ''http://[2001:db8::1]/v1'';'#13#10 +
  'const U5 = ''http://myhost.test/api'';';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
    'RFC 2606/5737/3849-Adressen sind Fixturen, keine Endpunkte');
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.PrivateLanAddress_StillReported;
// WAECHTER: RFC1918 gehoert NICHT auf die Whitelist. Im Korpus belegt
// 'http://192.168.1.153:3000/api' echte REST-Aufrufe.
const SRC =
  'unit t; implementation'#13#10 +
  'const API = ''http://192.168.1.153:3000/api'';';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
    'ein LAN-Endpunkt ist ein echter Endpunkt');
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.LookalikeLocalhost_StillReported;
// WAECHTER fuer die neue Host-Extraktion: die alte Pos()-Pruefung liess
// 'http://localhost.evil.com' als localhost durchgehen.
const SRC =
  'unit t; implementation'#13#10 +
  'const API = ''http://localhost.evil.com/api'';';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
    'localhost.evil.com ist ein Fremdhost, kein Loopback');
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

procedure TTestRestHttpSecurity.HttpUnixSocket_NotReported;
// Real-World FP-Audit 2026-07-10 (mORMot mormot.net.sock.pas:5674): 'http://unix:'
// ist das synthetische Layout eines UNIX-Domain-Sockets (lokales IPC), kein
// Remote-Endpunkt - keine Plaintext-Netzwerk-MITM-Flaeche, kein Befund.
const SRC =
  'unit t; implementation'#13#10 +
  'const IPC = ''http://unix:/var/run/app.sock:/'';';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
    'http://unix: ist ein UNIX-Domain-Socket (lokales IPC), kein Remote-HTTP');
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
