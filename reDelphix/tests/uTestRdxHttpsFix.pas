unit uTestRdxHttpsFix;

// Editorhilfe SCA115 HttpInsteadOfHttps (uRdxHttpsFix): 'http://' ->
// 'https://' im Literal, das der Detektor meldet. Erste Fixture (FPC-
// tauglich): Textfaelle (Zeile, Meldung wie der Detektor sie schreibt) und
// die Testcode-Frage TestPathReason (rwE30, Baeume unter TEMP). Zweite
// Fixture (nur Delphi, reDelphix.Test): Rundlaeufe mit dem ECHTEN Detektor
// (TRestHttpSecurityDetector) samt Katalog-Beispiel und der Einstieg der
// Tabelle (Adapter PlanHttps). Die Hilfe aendert das Verhalten (E2) - die
// Gegenproben belegen, dass sie nur ein eindeutiges Netzziel anfasst.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxHttpsFix = class
  public
    // ---- Text ----
    [Test] procedure Replaces_SchemeOnly;
    [Test] procedure TwoUrls_OnlyTheReportedOne;
    [Test] procedure NonAsciiBefore_ColumnInCharacters;
    [Test] procedure Edit_IsMinimal;
    [Test] procedure Comment_NoHelp;
    [Test] procedure BlockComment_NoHelp;
    [Test] procedure MovedLine_NoHelp;
    [Test] procedure PartOfLongerString_NoHelp;
    [Test] procedure DoubledQuote_NoHelp;
    [Test] procedure SameUrlTwice_NoHelp;
    [Test] procedure LocalAndReservedHosts_NoHelp;
    [Test] procedure NamespaceUrls_NoHelp;
    [Test] procedure PortUserinfoIpv6Ip_NoHelp;
    [Test] procedure OddHosts_NoHelp;
    [Test] procedure NoUrlInMessage_NoHelp;
    // ---- Testcode (TestPathReason, rwE29/rwE30) ----
    [Test] procedure TestFolder_PathRules;
    [Test] procedure TestFolder_ExampleSources_Help;
    [Test] procedure TestFolder_TestUnit_NoHelp;
    [Test] procedure TestFolder_TestProject_NoHelp;
    [Test] procedure TestFolder_UnreadableOrTooDeep_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxHttpsDetector = class
  public
    // ---- echter Detektor ----
    [Test] procedure Detector_CatalogExample;
    [Test] procedure Detector_RoundTrip_SilencesFinding;
    [Test] procedure Detector_SilentWhereHelpRefuses;
    [Test] procedure Adapter_PlansLikeTheMap;
    // rwE29: in einem Testordner vergleicht ein Test die Adresse woertlich.
    [Test] procedure Adapter_TestFolder_NoHelp;
    // rwE30: Beispielquellen unter jvcl\tests bekommen die Hilfe.
    [Test] procedure Adapter_ExampleInTestFolder_Help;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uRestHttpSecurity,
  uRdxRecipeRunner, uRdxFixTable,
  uTestRdxDetectorKit,   // TSeen, DetectSource
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxHttpsFix,
  uRdxPaths,             // SetRdxRemoteDriveTest (Naht fuer das Netzlaufwerk)
  uTestRdxTextKit;       // Join, Apply, WriteText, NewTempDir, RemoveTree

const
  // Gruende der Hilfe (Teile der Texte in uRdxHttpsFix).
  WHY_MOVED     = 'nicht als eigenes Literal';
  WHY_AMBIGUOUS = 'mehrfach';
  WHY_INSIDE    = 'Kommentar oder String';
  WHY_NO_URL    = 'keine "http://"-Adresse';
  WHY_USERINFO  = 'Zugangsdaten, einen Port oder eine IPv6-Adresse';
  WHY_ODD       = 'kein fester Name';
  WHY_IP        = 'IP-Adresse';
  WHY_LOCAL     = 'lokaler oder interner Rechner';
  WHY_NAMESPACE = 'Namespace- oder Schema-Kennzeichen';
  EXAMPLE_URL   = 'http://api.contoso-shop.de/v1/users';
  EXAMPLE_HTTPS = 'https://api.contoso-shop.de/v1/users';
  FIRST_LINE    = 8;   // erste Anweisung in Wrap

// ---- Helfer ----

// Die Meldung des Detektors (uRestHttpSecurity) fuer AUrl.
function Msg(const AUrl: string): string;
begin
  Result := Format('Plaintext HTTP URL ''%s'' - prefer https:// for remote '
    + 'endpoints. MITM-readable; credentials, tokens and PII travel '
    + 'unencrypted. Suppress for ad-hoc dev URLs with '
    + '// noinspection HttpInsteadOfHttps', [AUrl]);
end;

// Anweisungen in einer Routine mit Url: string; die erste auf Zeile 8.
function Wrap(const AStatements: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', 'procedure P;',
    'var', '  Url: string;', 'begin']) + #13#10 + Join(AStatements)
    + #13#10 + Join(['end;', 'end.']);
end;

// Die Hilfe fuer die Meldung zu AUrl auf ALine: der neue Text oder '' mit
// dem Grund in AReason.
function Fix(const ASource: string; ALine: Integer; const AUrl: string;
  out AReason: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if TRdxHttpsFix.Https(Map, ALine, Msg(AUrl), E, AReason) then
      Result := Apply(ASource, E);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Keine Hilfe, mit AWhy im Grund.
procedure AssertRefused(const ASource: string; ALine: Integer;
  const AUrl, AWhy: string);
var
  R : string;
begin
  Assert.AreEqual('', Fix(ASource, ALine, AUrl, R), 'keine Hilfe');
  Assert.IsTrue(Pos(AWhy, R) > 0, R);
end;

// ---- Text ----

procedure TTestRdxHttpsFix.Replaces_SchemeOnly;
var
  R : string;
begin
  Assert.AreEqual(Wrap(['  Url := ''' + EXAMPLE_HTTPS + ''';']),
    Fix(Wrap(['  Url := ''' + EXAMPLE_URL + ''';']), FIRST_LINE, EXAMPLE_URL, R), R);
  // Pfad, Query und Gross-/Kleinschreibung des Rests bleiben.
  Assert.AreEqual(Wrap(['  Url := ''https://Api.Contoso-Shop.de/a?b=1&c=2#x'';']),
    Fix(Wrap(['  Url := ''http://Api.Contoso-Shop.de/a?b=1&c=2#x'';']),
      FIRST_LINE, 'http://Api.Contoso-Shop.de/a?b=1&c=2#x', R), R);
end;

procedure TTestRdxHttpsFix.TwoUrls_OnlyTheReportedOne;
var
  R : string;
begin
  Assert.AreEqual(
    Wrap(['  Url := ''http://a.contoso-shop.de/x'' + ''https://b.contoso-shop.de/y'';']),
    Fix(Wrap(['  Url := ''http://a.contoso-shop.de/x'' + ''http://b.contoso-shop.de/y'';']),
      FIRST_LINE, 'http://b.contoso-shop.de/y', R), R);
end;

procedure TTestRdxHttpsFix.NonAsciiBefore_ColumnInCharacters;
var
  R, Pre : string;
begin
  // Umlaut (U+00E4) vor dem Literal: die Spalte zaehlt Zeichen.
  Pre := '  Url := ''t' + Chr($E4) + 'st'' + ';
  Assert.AreEqual(Wrap([Pre + '''https://a.contoso-shop.de/x'';']),
    Fix(Wrap([Pre + '''http://a.contoso-shop.de/x'';']), FIRST_LINE,
      'http://a.contoso-shop.de/x', R), R);
end;

procedure TTestRdxHttpsFix.Edit_IsMinimal;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
  R   : string;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Wrap(['  Url := ''' + EXAMPLE_URL + ''';']);
    Map := TRdxCodeMap.Create(SL);
    Assert.IsTrue(TRdxHttpsFix.Https(Map, FIRST_LINE, Msg(EXAMPLE_URL), E, R), R);
    Assert.AreEqual('http://', E.Expected);
    Assert.AreEqual('https://', E.NewText);
    Assert.AreEqual<Integer>(FIRST_LINE, E.Span.StartLine);
    Assert.AreEqual<Integer>(11, E.Span.StartCol);   // hinter dem Quote bei Spalte 10
  finally
    Map.Free;
    SL.Free;
  end;
end;

procedure TTestRdxHttpsFix.Comment_NoHelp;
begin
  AssertRefused(Wrap(['  // Url := ''' + EXAMPLE_URL + ''';']), FIRST_LINE,
    EXAMPLE_URL, WHY_MOVED);
  AssertRefused(Wrap(['  Url := ''x''; // ''' + EXAMPLE_URL + '''']), FIRST_LINE,
    EXAMPLE_URL, WHY_MOVED);
  AssertRefused(Wrap(['  { Url := ''' + EXAMPLE_URL + ''' } Url := ''x'';']),
    FIRST_LINE, EXAMPLE_URL, WHY_MOVED);
end;

procedure TTestRdxHttpsFix.BlockComment_NoHelp;
begin
  // Die Zeile beginnt in einem Block-Kommentar.
  AssertRefused(Wrap(['  { Beispiel:', '  Url := ''' + EXAMPLE_URL + ''';',
    '  }']), FIRST_LINE + 1, EXAMPLE_URL, WHY_INSIDE);
end;

procedure TTestRdxHttpsFix.MovedLine_NoHelp;
begin
  // Der Fund meldete Zeile 8; dort steht inzwischen eine andere Anweisung.
  AssertRefused(Wrap(['  Url := ''x'';', '  Url := ''' + EXAMPLE_URL + ''';']),
    FIRST_LINE, EXAMPLE_URL, WHY_MOVED);
end;

procedure TTestRdxHttpsFix.PartOfLongerString_NoHelp;
begin
  AssertRefused(Wrap(['  Url := ''see ' + EXAMPLE_URL + ' now'';']), FIRST_LINE,
    EXAMPLE_URL, WHY_MOVED);
end;

procedure TTestRdxHttpsFix.DoubledQuote_NoHelp;
begin
  // 'x''http://...' ist EIN String mit einem Apostroph darin.
  AssertRefused(Wrap(['  Url := ''x''''' + EXAMPLE_URL + ''';']), FIRST_LINE,
    EXAMPLE_URL, WHY_MOVED);
end;

procedure TTestRdxHttpsFix.SameUrlTwice_NoHelp;
begin
  AssertRefused(Wrap(['  Url := ''' + EXAMPLE_URL + ''' + ''' + EXAMPLE_URL
    + ''';']), FIRST_LINE, EXAMPLE_URL, WHY_AMBIGUOUS);
end;

procedure TTestRdxHttpsFix.LocalAndReservedHosts_NoHelp;
const
  LOCALS: array[0..7] of string = ('http://localhost/x',
    'http://api.localhost/x', 'http://host.docker.internal/x',
    'http://example.com/x', 'http://www.example.org/x', 'http://a.test/x',
    'http://intranet/x', 'http://unix/x');
var
  U : string;
begin
  for U in LOCALS do
    AssertRefused(Wrap(['  Url := ''' + U + ''';']), FIRST_LINE, U, WHY_LOCAL);
end;

procedure TTestRdxHttpsFix.NamespaceUrls_NoHelp;
const
  SPACES: array[0..3] of string = ('http://www.w3.org/2001/XMLSchema',
    'http://schemas.xmlsoap.org/soap/envelope/',
    'http://tempuri.org/IService', 'http://a.contoso-shop.de/xmlns/typen');
var
  U : string;
begin
  for U in SPACES do
    AssertRefused(Wrap(['  Url := ''' + U + ''';']), FIRST_LINE, U, WHY_NAMESPACE);
  // Der Name links vom Literal sagt es auch.
  AssertRefused(Wrap(['  Url := ''x''; Xmlns := ''' + EXAMPLE_URL + ''';']),
    FIRST_LINE, EXAMPLE_URL, WHY_NAMESPACE);
end;

procedure TTestRdxHttpsFix.PortUserinfoIpv6Ip_NoHelp;
begin
  AssertRefused(Wrap(['  Url := ''http://api.contoso-shop.de:8080/x'';']),
    FIRST_LINE, 'http://api.contoso-shop.de:8080/x', WHY_USERINFO);
  AssertRefused(Wrap(['  Url := ''http://user:pw@api.contoso-shop.de/x'';']),
    FIRST_LINE, 'http://user:pw@api.contoso-shop.de/x', WHY_USERINFO);
  AssertRefused(Wrap(['  Url := ''http://[2a00:1450::1]/x'';']), FIRST_LINE,
    'http://[2a00:1450::1]/x', WHY_USERINFO);
  AssertRefused(Wrap(['  Url := ''http://192.168.1.153/api'';']), FIRST_LINE,
    'http://192.168.1.153/api', WHY_IP);
end;

procedure TTestRdxHttpsFix.OddHosts_NoHelp;
begin
  AssertRefused(Wrap(['  Url := ''http://%s/x'';']), FIRST_LINE, 'http://%s/x',
    WHY_ODD);
  AssertRefused(Wrap(['  Url := ''http://my_host.contoso-shop.de/x'';']),
    FIRST_LINE, 'http://my_host.contoso-shop.de/x', WHY_ODD);
end;

procedure TTestRdxHttpsFix.NoUrlInMessage_NoHelp;
var
  R : string;
  SL : TStringList;
  Map : TRdxCodeMap;
  E : TRdxEdit;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Wrap(['  Url := ''' + EXAMPLE_URL + ''';']);
    Map := TRdxCodeMap.Create(SL);
    Assert.IsFalse(TRdxHttpsFix.Https(Map, FIRST_LINE, 'Plaintext HTTP URL',
      E, R), 'keine Hilfe');
    Assert.IsTrue(Pos(WHY_NO_URL, R) > 0, R);
    // https ist schon da: kein 'http://'-Literal.
    Assert.IsFalse(TRdxHttpsFix.Https(Map, FIRST_LINE, Msg(EXAMPLE_HTTPS), E, R),
      'keine Hilfe');
    Assert.IsTrue(Pos(WHY_NO_URL, R) > 0, R);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// ---- Testcode (TestPathReason, rwE29/rwE30) ----

// Die Testcode-Frage fuer AFileName mit dem Unit-Text ASource ('': ohne
// Zeilen). Die Gruende pruefen die Tests nur an den zitierten Namen - die
// stehen in jeder Sprache gleich da.
function TestReason(const AFileName, ASource: string): string;
var
  SL : TStringList;
begin
  if ASource = '' then
    Exit(TRdxHttpsFix.TestPathReason(AFileName, nil));
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Result := TRdxHttpsFix.TestPathReason(AFileName, SL);
  finally
    SL.Free;
  end;
end;

// Eine Projektdatei: Programm AName mit den uses AUses.
function ProgramText(const AName, AUses: string): string;
begin
  Result := Join(['program ' + AName + ';', '', 'uses', '  ' + AUses + ';',
    '', 'begin', 'end.']);
end;

// jvcl\tests\archive\jvcl132\examples\JvLinkLabel\Main.pas:168
// (minimiert): eine Beispiel-Form, kein Test. Die Test-Merkmale im
// Kommentar und im String zaehlen nicht.
function ExampleFormUnit: string;
begin
  Result := Join(['unit Main;', 'interface', 'uses Windows, Forms;',
    '{ wie TestFramework: siehe DUnit }', 'implementation',
    'procedure TForm1.Click(Sender: TObject);', 'begin',
    '  Caption := ''TTestCase''; // [TestFixture]',
    '  OpenWebPage(''http://jvcl.sourceforge.net'');', 'end;', 'end.']);
end;

// jvcl\tests\restructured\source\JvHotLink.pas:52 (minimiert): die
// resourcestring im implementation-Teil einer Komponenten-Quelle.
function ComponentUnit: string;
begin
  Result := Join(['unit JvHotLink;', 'interface', 'uses Classes;',
    'implementation', 'resourcestring',
    '  RC_UrlSite = ''http://www.jvcl.org'';', 'end.']);
end;

// Eine Test-Unit mit AUses und AClass (z. B. 'class(TTestCase)').
function TestUnit(const AUses, ADecl: string): string;
begin
  Result := Join(['unit T;', 'interface', 'uses ' + AUses + ';', 'type',
    '  ' + ADecl, '  end;', 'implementation', 'end.']);
end;

// Ein Laufwerk ist ein Netzlaufwerk (Naht SetRdxRemoteDriveTest).
function EveryDriveRemote(const ADrive: string): Boolean;
begin
  Result := True;
end;

procedure TTestRdxHttpsFix.TestFolder_PathRules;
var
  R : string;
begin
  // Merkmal 1: die Datei liegt direkt im Testordner (Indy Bubbles\
  // boxtests\HTTPClient.pas:173); auch '...Tests' ist ein Testordner.
  R := TestReason('C:/x/Tests/a.pas', '');
  Assert.IsTrue(Pos('"Tests"', R) > 0, R);
  R := TestReason('C:\x\boxtests\HTTPClient.pas', '');
  Assert.IsTrue(Pos('"boxtests"', R) > 0, R);
  Assert.IsTrue(TestReason('C:\x\IntegrationTests\a.pas', '') <> '');
  // Merkmal 2: ein Verzeichnis darunter traegt 'test' im Namen
  // (delphimvcframework unittests\general\TestServer\
  // TestServerControllerU.pas:1334) - der Grund nennt beide. Bis rwE30
  // nannte er nur den Testordner (ohne Fix rot).
  R := TestReason(
    'D:\repo\unittests\general\TestServer\TestServerControllerU.pas', '');
  Assert.IsTrue(Pos('"TestServer"', R) > 0, R);
  Assert.IsTrue(Pos('"unittests"', R) > 0, R);
  // ... oder die Datei selbst (Indy Test\Protocols\IdTestHttp.pas: erbt
  // von TIdTest aus IdTest, nennt kein Framework).
  R := TestReason('D:\repo\Test\Protocols\IdTestHttp.pas', ExampleFormUnit);
  Assert.IsTrue(Pos('"IdTestHttp.pas"', R) > 0, R);
  // Kein Testordner: der Dateiname zaehlt nicht, 'TestServer' allein auch
  // nicht (der Testordner fehlt).
  Assert.AreEqual('', TestReason('C:\x\src\tests.pas', ''));
  Assert.AreEqual('', TestReason('C:\x\samples\TestServer\u.pas', ''));
end;

procedure TTestRdxHttpsFix.TestFolder_ExampleSources_Help;
var
  Root, Ex, Src : string;
begin
  // rwE30, Todo_SCA115 "Sperre unnoetig" (20 Stellen unter jvcl\tests):
  // Beispiele und Komponentenquellen ohne Test-Merkmal bekommen die Hilfe.
  // Bis rwE30 sperrte schon der Ordner 'tests' (ohne Fix rot).
  Root := NewTempDir('rdx_https_');
  try
    Ex := Root + 'tests\archive\jvcl132\examples\';
    ForceDirectories(Ex + 'JvLinkLabel');
    ForceDirectories(Root + 'tests\restructured\source');
    ForceDirectories(Root + 'tests\DUnit\source');
    WriteText(Ex + 'JvLinkLabel\Main.pas', ExampleFormUnit);
    WriteText(Ex + 'JvLinkLabel\JvLinkLabelDemo.dpr',
      ProgramText('JvLinkLabelDemo', 'Forms, Main'));
    WriteText(Ex + 'JVCLDemos.bpg', '#-- Projektgruppe');
    Src := Root + 'tests\restructured\source\JvHotLink.pas';
    WriteText(Src, ComponentUnit);
    // Gegenproben, die NICHT zaehlen: ein Testprojekt im Nachbarzweig
    // (jvcl\tests\DUnit) und eines ueber dem Testordner.
    WriteText(Root + 'tests\DUnit\source\JVCLTest.dpr',
      ProgramText('JVCLTest', 'TestFramework, GUITestRunner'));
    WriteText(Root + 'AllTests.dpr', ProgramText('AllTests', 'TestFramework'));
    Assert.AreEqual('', TestReason(Ex + 'JvLinkLabel\Main.pas',
      ExampleFormUnit));
    Assert.AreEqual('', TestReason(Src, ComponentUnit));
    // Ohne Zeilen (kein Text) entscheidet die Platte allein.
    Assert.AreEqual('', TestReason(Src, ''));
  finally
    RemoveTree(Root);
  end;
end;

procedure TTestRdxHttpsFix.TestFolder_TestUnit_NoHelp;
const
  PATH = 'C:\repo\tests\archive\x\u.pas';
var
  R : string;
begin
  // Merkmal 3: die Unit selbst ist Test-Code (vor jedem Plattenblick).
  // Bis rwE30 sperrte der Ordner mit einem Grund ohne Merkmal (ohne Fix
  // rot).
  R := TestReason(PATH, TestUnit('TestFramework', 'TT = class(TObject)'));
  Assert.IsTrue(Pos('"testframework"', R) > 0, R);
  R := TestReason(PATH, TestUnit('DUnitX.TestFramework', 'TT = class'));
  Assert.IsTrue(Pos('"dunitx.testframework"', R) > 0, R);
  R := TestReason(PATH, TestUnit('fpcunit, testregistry', 'TT = class'));
  Assert.IsTrue(Pos('"fpcunit"', R) > 0, R);
  R := TestReason(PATH, TestUnit('Classes', 'TT = class(TTestCase)'));
  Assert.IsTrue(Pos('"ttestcase"', R) > 0, R);
  R := TestReason(PATH, TestUnit('Classes', '[TestFixture] TT = class'));
  Assert.IsTrue(Pos('"testfixture"', R) > 0, R);
  R := TestReason(PATH, TestUnit('mormot.core.test', 'TT = class'));
  Assert.IsTrue(Pos('"mormot.core.test"', R) > 0, R);
  R := TestReason(PATH, TestUnit('Classes', 'TT = class(TSynTestCase)'));
  Assert.IsTrue(Pos('"tsyntestcase"', R) > 0, R);
  Assert.IsTrue(Pos('"tests"', R) > 0, R);
end;

procedure TTestRdxHttpsFix.TestFolder_TestProject_NoHelp;
var
  Root, Dir, R : string;
begin
  // Merkmal 4: ein Testprojekt neben der Datei oder darueber bis zum
  // Testordner. Bis rwE30 sperrte der Ordner mit einem Grund ohne Projekt
  // (ohne Fix rot).
  Root := NewTempDir('rdx_https_');
  try
    // cnwizards Test\Delphi\Program\AICoder\AICoderUnit.pas:299 - das
    // Projekt daneben heisst AICoderTest.dpr (kein Test-Framework).
    Dir := Root + 'Test\Delphi\Program\AICoder\';
    ForceDirectories(Dir);
    WriteText(Dir + 'AICoderTest.dpr', ProgramText('AICoderTest',
      'Forms, AICoderUnit'));
    WriteText(Dir + 'AICoderUnit.pas', ExampleFormUnit);
    R := TestReason(Dir + 'AICoderUnit.pas', ExampleFormUnit);
    Assert.IsTrue(Pos('"AICoderTest.dpr"', R) > 0, R);
    Assert.IsTrue(Pos('"Test"', R) > 0, R);
    // cnwizards Test\Lazarus\..\AICoder:282 - nur die .lpi zaehlt auch.
    Dir := Root + 'Test\Lazarus\Program\AICoder\';
    ForceDirectories(Dir);
    WriteText(Dir + 'AICoderTest.lpi', '<?xml version="1.0"?>');
    R := TestReason(Dir + 'AICoderUnit.pas', ExampleFormUnit);
    Assert.IsTrue(Pos('"AICoderTest.lpi"', R) > 0, R);
    // Ein Programm ohne 'test' im Namen, das ein Test-Framework nennt,
    // zwei Ebenen ueber der Datei (im Testordner).
    Dir := Root + 'tests\suite\';
    ForceDirectories(Dir + 'helpers\data');
    WriteText(Dir + 'Runner.dpr', ProgramText('Runner',
      'Forms, GUITestRunner'));
    R := TestReason(Dir + 'helpers\data\Data.pas', ExampleFormUnit);
    Assert.IsTrue(Pos('"Runner.dpr"', R) > 0, R);
  finally
    RemoveTree(Root);
  end;
end;

procedure TTestRdxHttpsFix.TestFolder_UnreadableOrTooDeep_NoHelp;
var
  Root, Dir, R : string;
  i            : Integer;
begin
  Root := NewTempDir('rdx_https_');
  try
    // Deckel MAX_PROJECT_READS (16 Koepfe): 16 Programme ohne Merkmal
    // lassen die Hilfe zu (ohne Fix rot), das siebzehnte sperrt mit dem
    // Grund des Testordners - ungelesen ist nicht bewiesen.
    Dir := Root + 'tests\many\';
    ForceDirectories(Dir);
    for i := 1 to 16 do
      WriteText(Dir + Format('Demo%.2d.dpr', [i]),
        ProgramText(Format('Demo%.2d', [i]), 'Forms'));
    Assert.AreEqual('', TestReason(Dir + 'u.pas', ExampleFormUnit));
    WriteText(Dir + 'Demo17.dpr', ProgramText('Demo17', 'Forms'));
    R := TestReason(Dir + 'u.pas', ExampleFormUnit);
    Assert.IsTrue(Pos('"tests"', R) > 0, R);
    // Ein Netzlaufwerk liest der Planer nicht: Sperre wie bisher.
    Dir := Root + 'tests\archive\x\';
    ForceDirectories(Dir);
    Assert.AreEqual('', TestReason(Dir + 'u.pas', ExampleFormUnit));
    SetRdxRemoteDriveTest(EveryDriveRemote);
    try
      R := TestReason(Dir + 'u.pas', ExampleFormUnit);
    finally
      SetRdxRemoteDriveTest(nil);
    end;
    Assert.IsTrue(Pos('"tests"', R) > 0, R);
  finally
    RemoveTree(Root);
  end;
  // Mehr als MAX_TEST_LEVELS (8) Verzeichnisse bis zum Testordner: Sperre.
  R := TestReason('C:\repo\tests\a\b\c\d\e\f\g\h\i\u.pas', ExampleFormUnit);
  Assert.IsTrue(Pos('"tests"', R) > 0, R);
end;

{$IFNDEF FPC}

{ ---- echter Detektor und Einstieg der Tabelle ---- }

procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TRestHttpSecurityDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_https_', ASource, fkHttpInsteadOfHttps,
    RunDetector);
end;

// Die Hilfe fuer den Fund ASeen ueber den Einstieg des Anbieters
// (uTestRdxDetectorKit.PlanFixIn: TRdxFixTable.FixFor mit dem
// Quellstellen-Dienst; bis zur Review Woche G06 eine eigene Kopie mit
// APlaces = nil - der Adapter braucht ihn nicht).
function PlanSeen(const ASource: string; const ASeen: TSeen): TRdxFixOutcome;
begin
  Result := PlanFixIn(ASource, 't.pas', fkHttpInsteadOfHttps, ASeen);
end;

// Dasselbe in der Form von TDetectFunc (FixAllWith).
function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := Detect(ASource);
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt - ueber den Einstieg des Anbieters
// (uTestRdxDetectorKit.FixAllWith, TRdxFixTable.FixFor; bis zur Review
// Woche G06 eine eigene Schleife).
function FixAll(const ASource: string): string;
begin
  Result := FixAllWith(ASource, fkHttpInsteadOfHttps, DetectKind);
end;

// ---- echter Detektor ----

procedure TTestRdxHttpsDetector.Detector_CatalogExample;
var
  Meta : TRuleMeta;
  Good : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkHttpInsteadOfHttps);
  Assert.IsTrue(Pos('http://', Meta.BadExample) > 0, Meta.BadExample);
  Assert.AreNotEqual(Meta.BadExample, Meta.GoodExample);
  Good := FixAll(Wrap(['  ' + Meta.BadExample]));
  Assert.AreEqual(Wrap(['  ' + Meta.GoodExample]), Good);
end;

procedure TTestRdxHttpsDetector.Detector_RoundTrip_SilencesFinding;
var
  Src, Done : string;
begin
  Src := Wrap(['  Url := ''http://a.contoso-shop.de/x'';',
    '  Url := ''http://b.contoso-shop.de/y'' + ''/z'';']);
  Assert.AreEqual<Integer>(2, Length(Detect(Src)), 'zwei Funde vorher');
  Done := FixAll(Src);
  Assert.AreEqual(Wrap(['  Url := ''https://a.contoso-shop.de/x'';',
    '  Url := ''https://b.contoso-shop.de/y'' + ''/z'';']), Done);
  Assert.AreEqual<Integer>(0, Length(Detect(Done)), 'der Detektor schweigt');
end;

procedure TTestRdxHttpsDetector.Detector_SilentWhereHelpRefuses;
var
  Src, U : string;
begin
  // Was der Detektor nicht meldet (localhost, Namespace), fasst die Hilfe
  // auch nicht an - und umgekehrt meldet er eine Adresse mit Port, die die
  // Hilfe ablehnt.
  Src := Wrap(['  Url := ''http://localhost/x'';',
    '  Url := ''http://www.w3.org/2001/XMLSchema'';']);
  Assert.AreEqual<Integer>(0, Length(Detect(Src)), 'Detektor schweigt');
  Src := Wrap(['  Url := ''http://api.contoso-shop.de:8080/x'';']);
  Assert.AreEqual<Integer>(1, Length(Detect(Src)), 'Detektor meldet');
  U := 'http://api.contoso-shop.de:8080/x';
  Assert.IsFalse(PlanSeen(Src, Detect(Src)[0]).Enabled, 'keine Hilfe');
  Assert.IsTrue(TRdxHttpsFix.UrlReason(U) <> '', 'Grund');
end;

procedure TTestRdxHttpsDetector.Adapter_PlansLikeTheMap;
var
  Finding : TLeakFinding;
  O       : TRdxFixOutcome;
begin
  Finding := TLeakFinding.New('t.pas', '', FIRST_LINE, Msg(EXAMPLE_URL),
    fkHttpInsteadOfHttps);
  try
    // Ohne Zeilen (keine Datei geoeffnet): keine Hilfe mit Grund.
    O := TRdxFixTable.FixFor(nil, nil, Finding, nil);
    Assert.IsFalse(O.Enabled);
    Assert.IsTrue(O.Reason <> '');
    Assert.AreEqual<Integer>(0, Length(O.Edits));
  finally
    Finding.Free;
  end;
  O := PlanSeen(Wrap(['  Url := ''' + EXAMPLE_URL + ''';']),
    Detect(Wrap(['  Url := ''' + EXAMPLE_URL + ''';']))[0]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(1, Length(O.Edits));
end;

procedure TTestRdxHttpsDetector.Adapter_TestFolder_NoHelp;
var
  Finding : TLeakFinding;
  O       : TRdxFixOutcome;
  Lines   : TStringList;
begin
  // delphimvcframework unittests\general\TestServer\
  // TestServerControllerU.pas:1334 (minimiert): die Adresse ist eine
  // Vorgabe, LiveServerTestU.pas vergleicht sie woertlich. Ohne Fix
  // angeboten (rot).
  Lines := TStringList.Create;
  try
    Lines.Text := Wrap(['  Url := ''' + EXAMPLE_URL + ''';']);
    Finding := TLeakFinding.New(
      'D:\repo\unittests\general\TestServer\TestServerControllerU.pas', '',
      FIRST_LINE, Msg(EXAMPLE_URL), fkHttpInsteadOfHttps);
    try
      O := TRdxFixTable.FixFor(nil, Lines, Finding, nil);
      Assert.IsFalse(O.Enabled, 'Testordner');
      Assert.IsTrue(Pos('"unittests"', O.Reason) > 0, O.Reason);
      Assert.AreEqual<Integer>(0, Length(O.Edits));
    finally
      Finding.Free;
    end;
    // Gegenprobe: dieselbe Zeile ausserhalb eines Testordners ('TestServer'
    // allein ist kein Testordner, der Dateiname zaehlt nicht).
    Finding := TLeakFinding.New('D:\repo\samples\TestServer\TestU.pas', '',
      FIRST_LINE, Msg(EXAMPLE_URL), fkHttpInsteadOfHttps);
    try
      O := TRdxFixTable.FixFor(nil, Lines, Finding, nil);
      Assert.IsTrue(O.Enabled, O.Reason);
    finally
      Finding.Free;
    end;
  finally
    Lines.Free;
  end;
  // Die Regel selbst: TestFolder_PathRules (erste Fixture).
end;

procedure TTestRdxHttpsDetector.Adapter_ExampleInTestFolder_Help;
var
  Root, Path : string;
  Finding    : TLeakFinding;
  O          : TRdxFixOutcome;
  Lines      : TStringList;
begin
  // rwE30, jvcl\tests\Globus\run\JvgCheckVersionInfoForm.pas:84
  // (minimiert): eine Form unter jvcl\tests ohne Test-Merkmal - der
  // Adapter bietet die Hilfe an (bis rwE30 gesperrt: ohne Fix rot).
  Root := NewTempDir('rdx_https_');
  Lines := TStringList.Create;
  try
    Path := Root + 'tests\Globus\run\JvgCheckVersionInfoForm.pas';
    ForceDirectories(ExtractFilePath(Path));
    Lines.Text := Wrap(['  Url := ''' + EXAMPLE_URL + ''';']);
    WriteText(Path, Lines.Text);
    Finding := TLeakFinding.New(Path, '', FIRST_LINE, Msg(EXAMPLE_URL),
      fkHttpInsteadOfHttps);
    try
      O := TRdxFixTable.FixFor(nil, Lines, Finding, nil);
      Assert.IsTrue(O.Enabled, O.Reason);
      Assert.AreEqual<Integer>(1, Length(O.Edits));
      // Gegenprobe: dieselbe Datei als DUnit-Test (uses TestFramework) -
      // gesperrt, der Grund nennt das Merkmal. Die Anweisung bleibt auf
      // FIRST_LINE (uses in der Zeile von implementation).
      Lines.Text := Join(['unit u;', 'interface',
        'implementation uses TestFramework;', 'procedure P;', 'var',
        '  Url: string;', 'begin', '  Url := ''' + EXAMPLE_URL + ''';',
        'end;', 'end.']);
      O := TRdxFixTable.FixFor(nil, Lines, Finding, nil);
      Assert.IsFalse(O.Enabled, 'Test-Unit');
      Assert.IsTrue(Pos('"testframework"', O.Reason) > 0, O.Reason);
      Assert.AreEqual<Integer>(0, Length(O.Edits));
    finally
      Finding.Free;
    end;
  finally
    Lines.Free;
    RemoveTree(Root);
  end;
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxHttpsFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxHttpsDetector);
  {$ENDIF}

end.
