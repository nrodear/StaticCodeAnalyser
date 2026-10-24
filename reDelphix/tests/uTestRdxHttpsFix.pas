unit uTestRdxHttpsFix;

// Editorhilfe SCA115 HttpInsteadOfHttps (uRdxHttpsFix; nur Delphi,
// reDelphix.Test): 'http://' -> 'https://' im Literal, das der Detektor
// meldet. Textfaelle (Zeile, Meldung wie der Detektor sie schreibt) und
// Rundlaeufe mit dem ECHTEN Detektor (TRestHttpSecurityDetector) samt
// Katalog-Beispiel. Die Hilfe aendert das Verhalten (E2) - die Gegenproben
// belegen, dass sie nur ein eindeutiges Netzziel anfasst.

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
    // ---- echter Detektor ----
    [Test] procedure Detector_CatalogExample;
    [Test] procedure Detector_RoundTrip_SilencesFinding;
    [Test] procedure Detector_SilentWhereHelpRefuses;
    [Test] procedure Adapter_PlansLikeTheMap;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uRestHttpSecurity,
  uRdxBufferMath, uRdxCodeMap, uRdxRecipeRunner, uRdxFixTable, uRdxHttpsFix,
  uTestRdxDetectorKit,   // TSeen, DetectSource
  uTestRdxTextKit;       // Join, Apply

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
    Assert.AreEqual(FIRST_LINE, E.Span.StartLine);
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

// ---- echter Detektor ----

procedure TTestRdxHttpsFix.Detector_CatalogExample;
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

procedure TTestRdxHttpsFix.Detector_RoundTrip_SilencesFinding;
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

procedure TTestRdxHttpsFix.Detector_SilentWhereHelpRefuses;
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

procedure TTestRdxHttpsFix.Adapter_PlansLikeTheMap;
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

initialization
  TDUnitX.RegisterTestFixture(TTestRdxHttpsFix);

end.
