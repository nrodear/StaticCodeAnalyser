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

    // SCA115-FP-Paket (Autopsie 2026-08-27): fuenf Gates, je ein Drop-Fall
    // und mindestens eine TP-Gegenprobe.
    // GATE T - Testfixture-Unit ueber den INHALT
    [Test] procedure TestFixtureUnitByContent_NotReported;
    [Test] procedure TestFrameworkWithoutFixtureDecl_StillReported;
    [Test] procedure ShellExecuteInNonTestUnit_StillReported;
    // GATE M - OpenAPI-/Registry-Metadatenfeld links vom ':='
    [Test] procedure SwaggerMetadataUrls_NotReported;
    [Test] procedure HomeUrlAssignment_StillReported;
    // GATE D - enge Anzeige-/Log-Senke
    [Test] procedure DisplayAndLogSinks_NotReported;
    [Test] procedure DisplaySinkMultiLine_NotReported;
    [Test] procedure SinkClosedOnPreviousLine_StillReported;
    [Test] procedure NestedFetchInsideSink_StillReported;
    // GATE F - Host besteht nur aus Format-Platzhaltern
    [Test] procedure FormatPlaceholderHost_NotReported;
    [Test] procedure FormatPlaceholderInPath_StillReported;
    // GATE P - FQDN-Wurzelpunkt
    [Test] procedure FqdnRootDotReservedHost_NotReported;
    [Test] procedure FqdnRootDotForeignHost_StillReported;

    // DisabledTlsVerification
    [Test] procedure EmptySecureProtocols_Reported;
    [Test] procedure IgnoreCertificateErrors_Reported;
    [Test] procedure OnVerifyPeerNil_Reported;
  end;

implementation

// KEIN noinspection-Marker mehr noetig (Self-Scan 2026-08-28): saemtliche
// http://-Literale dieser Unit sind FIXTUREN fuer genau den Detektor, der
// sie meldet - frueher brauchte es dafuer ein 'noinspection-file
// HttpInsteadOfHttps'. Seit GATE T (Testfixture-Unit ueber den INHALT:
// Framework-Marker UND Fixture-Deklaration) erkennt der Detektor die Lage
// selbst, und unsere eigene Regel UnusedSuppression hat den Marker
// prompt als tot gemeldet. Er ist deshalb entfernt - ein Marker, der
// nichts unterdrueckt, ist genau der Befund, den diese Regel sucht.
// Faellt GATE T je weg, meldet der Self-Scan diese Datei wieder; dann
// gehoert der Marker zurueck, nicht vorsorglich.

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

// ===========================================================================
// SCA115-FP-Paket (Autopsie 2026-08-27): 176 Korpus-Funde = 110 FP / 66 TP.
// Je Gate ein Drop-Fall und mindestens eine TP-Gegenprobe. Die Fixturen
// benutzen absichtlich GENAU die Korpus-Zeilen, an denen die Gates hergeleitet
// wurden - wer eins aufweicht, sieht sofort welchen Beleg er verletzt.
// ===========================================================================

procedure TTestRestHttpSecurity.TestFixtureUnitByContent_NotReported;
// GATE T (52 Drops): eine Unit, die ein Testframework einbindet UND eine
// Fixture deklariert, enthaelt nur Eingabe-/Erwartungswerte. Vorbild:
// Alcinoe\Tests\DUnitX\_Source\ALDUnitXTestUrl.pas (allein 31 Funde).
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses DUnitX.TestFramework;'#13#10 +
  'type'#13#10 +
  '  [TestFixture]'#13#10 +
  '  TUrlTest = class'#13#10 +
  '  public'#13#10 +
  '    procedure ParsesHost;'#13#10 +
  '  end;'#13#10 +
  'implementation'#13#10 +
  'procedure TUrlTest.ParsesHost;'#13#10 +
  'begin'#13#10 +
  '  FUrl := ''http://api.contoso-shop.de/v1/users'';'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
    'Framework-Marker UND Fixture-Deklaration - das ist eine Testfixture-Unit');
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.TestFrameworkWithoutFixtureDecl_StillReported;
// WAECHTER fuer die UND-Verknuepfung in GATE T. Nachbau von
// mORMot2-master\ex\mvc-blog\MVCViewModel.pas: die Unit bindet
// mormot.core.test NUR wegen TSynTestCase.RandomTextParagraph ein (Demo-Daten)
// und ist selbst KEIN Test. Zeile 271 dort ist ein belegter TP. Mit dem
// Framework-Marker allein - ohne die geforderte Fixture-Deklaration - waere
// dieser Fund verloren.
const SRC =
  'unit t;'#13#10 +
  'interface'#13#10 +
  'uses mormot.core.test;'#13#10 +
  'implementation'#13#10 +
  'procedure Seed;'#13#10 +
  'begin'#13#10 +
  '  About := TSynTestCase.RandomTextParagraph(10, ''!'');'#13#10 +
  '  DotClearFlatImport(Orm, ''http://blog.synopse.info'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
      'ohne Fixture-Deklaration ist die Unit kein Test - Fund bleibt');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'DotClearFlatImport'),
      TFindingHelper.FirstOf(F, fkHttpInsteadOfHttps).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.ShellExecuteInNonTestUnit_StillReported;
// WAECHTER: eine Produktions-Unit ohne jeden Framework-Marker bleibt
// unangetastet - hier wird die URL wirklich geoeffnet.
const SRC =
  'unit t;'#13#10 +
  'implementation'#13#10 +
  'procedure OpenHomepage;'#13#10 +
  'begin'#13#10 +
  '  ShellExecute(0, ''open'', ''http://www.findicons.com'', nil, nil, 1);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
      'ShellExecute auf eine http-URL ist der Kernfall der Regel');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'ShellExecute'),
      TFindingHelper.FirstOf(F, fkHttpInsteadOfHttps).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.SwaggerMetadataUrls_NotReported;
// GATE M (27 Drops): der Wert landet im Swagger-Info-Block und beschreibt eine
// FREMDE Seite - dieses Programm ruft ihn nie ab. Belege:
// delphimvcframework\samples\swagger_doc\WebModuleMainU.pas:57,63 und
// ...\lib\swagdoc\Demos\SampleApi\Sample.SwagDoc.pas:72,78.
const SRC =
  'unit t;'#13#10 +
  'implementation'#13#10 +
  'procedure Cfg;'#13#10 +
  'begin'#13#10 +
  '  LSwagInfo.TermsOfService := ''http://www.apache.org/licenses/L2.txt'';'#13#10 +
  '  LSwagInfo.LicenseUrl := ''http://www.apache.org/licenses/L2'';'#13#10 +
  '  fSwagDoc.Info.License.Url := ''http://www.apache.org/licenses/L2b'';'#13#10 +
  '  Result.ContactUrl := ''http://www.danieleteti.it'';'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
    'OpenAPI-Metadatenfelder beschreiben eine Seite, sie rufen keine auf');
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.HomeUrlAssignment_StillReported;
// WAECHTER: die Feldliste in GATE M ist ABSCHLIESSEND. Homepage/HomeUrl darf
// NICHT dazu - cnwizards\Source\Utils\CnImageProviderFindIcons.pas:79 setzt
// 'HomeUrl := ''http://www.findicons.com''' und der Wert geht an OpenUrl.
const SRC =
  'unit t;'#13#10 +
  'implementation'#13#10 +
  'procedure GetProviderInfo;'#13#10 +
  'begin'#13#10 +
  '  HomeUrl := ''http://www.findicons.com'';'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
      'HomeUrl wird geoeffnet - kein Metadatenfeld');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'HomeUrl :='),
      TFindingHelper.FirstOf(F, fkHttpInsteadOfHttps).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.DisplayAndLogSinks_NotReported;
// GATE D (6 Drops): Text fuer Memo, Konsole, MessageBox oder Fortschritts-
// Callback geht nicht ins Netz. Alle vier Muster stammen 1:1 aus dem Korpus:
//   TES5Edit\xEdit\xeLogAnalyzerForm.pas:731,741,743  memoText.Lines.Add(
//   Dev-Cpp\...\SynGen\SynGenUnit.pas:765             Writeln(OutFile, ..
//   TES5Edit\Core\wbLOD.pas:3228                      wbProgressCallback(
const SRC =
  'unit t;'#13#10 +
  'implementation'#13#10 +
  'procedure Report;'#13#10 +
  'begin'#13#10 +
  '  memoText.Lines.Add(''http://www.creationkit.com/FAQ'');'#13#10 +
  '  Writeln(OutFile, ''http://www.mozilla.org/MPL/'');'#13#10 +
  '  ShowMessage(''http://www.contoso-help.de/hilfe'');'#13#10 +
  '  wbProgressCallback(''http://www.nexusmods.com/skyrim/mods/59721/'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
    'angezeigter/protokollierter Text ist kein Netzwerk-Aufruf');
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.DisplaySinkMultiLine_NotReported;
// GATE D greift auch, wenn die Senke eine Zeile frueher steht und ihre
// Klammer noch offen ist - genau dafuer wird die Vorzeile mitgelesen.
const SRC =
  'unit t;'#13#10 +
  'implementation'#13#10 +
  'procedure Report;'#13#10 +
  'begin'#13#10 +
  '  memoText.Lines.Add('#13#10 +
  '    ''http://www.creationkit.com/Papyrus'');'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
    'Fortsetzungszeile gehoert noch in die Argumentliste der Senke');
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.NestedFetchInsideSink_StillReported;
// Gegenpruefungs-MAJOR 2026-08-27: die URL steht zwar innerhalb der
// Anzeige-Senke, aber als Argument eines GESCHACHTELTEN Netz-Aufrufs -
// dort wird sehr wohl eine Verbindung aufgebaut. CallStillOpen verlangt
// deshalb Tiefe GENAU 1 (direktes Argument), nicht 'irgendwo in der
// Klammer'.
const SRC =
  'unit t;'#13#10 +
  'implementation'#13#10 +
  'procedure Run;'#13#10 +
  'begin'#13#10 +
  '  Memo1.Lines.Add(HttpClient.Get(''http://api.contoso.de/v1/secret''));'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
      'geschachtelter Get-Aufruf ist ein echter Endpunkt, keine Anzeige');
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.SinkClosedOnPreviousLine_StillReported;
// WAECHTER fuer die Klammer-Bedingung in GATE D: eine ABGESCHLOSSENE Senke in
// der Vorzeile darf den echten Endpunkt darunter nicht mitreissen. Ohne die
// Bedingung (nur "Senke steht in der Naehe") faellt dieser TP weg.
const SRC =
  'unit t;'#13#10 +
  'implementation'#13#10 +
  'procedure Run;'#13#10 +
  'begin'#13#10 +
  '  WriteLn(''fertig'');'#13#10 +
  '  ApiUrl := ''http://api.contoso-shop.de/v1'';'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
      'das WriteLn ist zu Ende - die Zuweisung darunter ist ein Endpunkt');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'ApiUrl :='),
      TFindingHelper.FirstOf(F, fkHttpInsteadOfHttps).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.FormatPlaceholderHost_NotReported;
// GATE F (4 Drops): der HOST ist nur ein Platzhalter - erst der Format-Aufruf
// entscheidet ueber Ziel und meist auch ueber das Schema. Belege:
//   delphimvcframework\sources\MVCFramework.Server.HttpSys.pas:292 'http://%s:%d/'
//   mORMot2-master\src\net\mormot.net.rtsphttp.pas:414              'http://%:%/%'
const SRC =
  'unit t;'#13#10 +
  'implementation'#13#10 +
  'procedure Bind;'#13#10 +
  'begin'#13#10 +
  '  Url := Format(''http://%s:%d/'', [Host, Port]);'#13#10 +
  '  Uri := FormatUtf8(''http://%:%/%'', [H, P, R]);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
    'eine URL, deren Host erst zur Laufzeit entsteht, ist kein Befund');
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.FormatPlaceholderInPath_StillReported;
// WAECHTER fuer die Praefix-Verankerung in GATE F: Platzhalter im PFAD sind
// ein echter Endpunkt - cnwizards\Source\Utils\CnImageProviderFindIcons.pas:110
// schickt genau diese URL durch TCnHTTP.GetString.
const SRC =
  'unit t;'#13#10 +
  'implementation'#13#10 +
  'procedure Search;'#13#10 +
  'begin'#13#10 +
  '  Url := Format(''http://findicons.com/search/%s?icons=%d'', [K, N]);'#13#10 +
  'end;'#13#10 +
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
      'der Host steht fest, nur der Pfad wird formatiert');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'findicons.com/search'),
      TFindingHelper.FirstOf(F, fkHttpInsteadOfHttps).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.FqdnRootDotReservedHost_NotReported;
// GATE P (1 Fund): 'example.com.' IST 'example.com' (RFC 1034 3.1, der letzte
// Punkt benennt die DNS-Wurzel). Ohne den Schnitt in ExtractHost rutschte
// Alcinoe\Tests\DUnitX\_Source\ALDUnitXTestUrl.pas:317 an der RFC-2606-Liste
// vorbei.
const SRC =
  'unit t; implementation'#13#10 +
  'const U = ''http://example.com./'';';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
    'der FQDN-Wurzelpunkt aendert den Host nicht');
  finally F.Free; end;
end;

procedure TTestRestHttpSecurity.FqdnRootDotForeignHost_StillReported;
// WAECHTER: der Wurzelpunkt-Schnitt ist eine Normalisierung, keine Whitelist -
// ein Fremdhost bleibt Fund.
const SRC =
  'unit t; implementation'#13#10 +
  'const U = ''http://api.contoso-shop.de./v1'';';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHttpInsteadOfHttps),
      'normalisiert bleibt api.contoso-shop.de ein erreichbarer Endpunkt');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'contoso-shop.de.'),
      TFindingHelper.FirstOf(F, fkHttpInsteadOfHttps).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
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
