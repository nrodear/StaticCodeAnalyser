unit uRestHttpSecurity;

// REST/HTTP-Security-Detektor-Familie (SCA115-116).
//
//   * fkHttpInsteadOfHttps      - 'http://'-Stringliteral fuer Remote-URL
//                                  -> Plaintext-Connect, MITM-Risiko
//   * fkDisabledTlsVerification  - aktiv deaktivierte TLS-Pruefung
//                                  (.SecureProtocols := [],
//                                   .IgnoreCertificateErrors := True, ...)
//
// Lexisch (URL-Literale + Property-Assignment-Pattern).
// Localhost/127.0.0.1/::1 sind keine Findings - Dev-Workflows brauchen die.
//
// fkHttpInsteadOfHttps traegt seit dem FP-Paket 2026-08-27 fuenf weitere
// Gates (P/F/M/D/T) - Herleitung und Korpus-Zahlen stehen im Block direkt
// ueber TFixtureVerdict. fkDisabledTlsVerification ist davon NICHT beruehrt.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TRestHttpSecurityDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, InsecureCryptoAlgorithm, LongMethod, NestedRoutine, RedundantBoolean, TooLongLine, UnsortedUses, UnusedLocalVar, UnusedParameter
// InsecureCryptoAlgorithm: dieser Detektor enthaelt SSL3/TLS1/MD5/SHA1 als
// eigene Detection-Patterns - Self-Match, kein realer Krypto-Einsatz.
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions, System.StrUtils,
  uFileTextCache, uDetectorUtils, uRegExMatches;

const
  // Thread-Fix (2026-08-19): die frueheren unit-vars (CachedReX + Init-Flag)
  // teilten EINE kompilierte TPerlRegEx-Instanz ueber alle Threads; ein
  // paralleles Match mutierte deren Subject/Offsets. Die Patterns kommen
  // jetzt pro Thread aus TRegExMatches.CachedEx; [roNotEmpty] entspricht
  // exakt dem Default des alten Ein-Arg-TRegEx.Create.
  RE_HTTP_URL = '''(http://[^''\s]+)''';
  RE_SEC_PROTO_EMPTY = '(?i)\bSecureProtocols\s*:=\s*\[\s*\]';
  RE_IGNORE_CERT = '(?i)\bIgnoreCertificateErrors\s*:=\s*True\b';
  RE_VERIFY_PEER_NIL = '(?i)\bOnVerifyPeer\s*:=\s*nil\b';
  // 2026-06-18 (Audit-Kurzliste E-21): Indy-spezifische TLS-Disable.
  // TIdHTTP / TIdSSLIOHandlerSocketOpenSSL nutzen .SSLOptions.X-Pattern.
  // Pfad-Variante `Foo.SSLOptions.X := ...` per `\.` vor Marker.
  RE_INDY_VERIFY_EMPTY = '(?i)\.?\bSSLOptions\.VerifyMode\s*:=\s*\[\s*\]';
  // sslvSSLv2/3 sind formal abgeschaltet seit RFC 7568 (SSLv3 - POODLE)
  // bzw. RFC 6176 (SSLv2). sslvTLSv1 = TLS 1.0 ist seit ~2020 von allen
  // Browsern abgekuendigt. Wir flaggen alle drei.
  RE_INDY_OLD_PROTO = '(?i)\.?\bSSLOptions\.Method\s*:=\s*sslv(SSLv2|SSLv3|TLSv1)\b';
  // THTTPClient.SecureProtocols mit veraltetem Protokoll-Set.
  // SSL3 / TLS1 sind disallowed in modernen Stacks.
  RE_SEC_PROTO_OLD = '(?i)\bSecureProtocols\s*:=\s*\[[^]]*\b(SSL3|SSL2|TLS1)\b';

function ExtractHost(const Url: string): string;
// Host einer 'http://[userinfo@]host[:port]/pfad'-URL: lowercase, ohne Port,
// IPv6-Literal ohne die eckigen Klammern. Ersetzt die frueheren
// Pos()-Substring-Pruefungen, die 'http://localhost.evil.com' als localhost
// durchgehen liessen (FP-Audit Stufe 2, 2026-08-16).
var
  L : string;
  p : Integer;
begin
  L := LowerCase(Url);
  if L.StartsWith('http://') then
    L := Copy(L, Length('http://') + 1, MaxInt);
  // Pfad / Query / Fragment abschneiden
  for p := 1 to Length(L) do
    if CharInSet(L[p], ['/', '?', '#']) then
    begin
      L := Copy(L, 1, p - 1);
      Break;
    end;
  // userinfo abschneiden
  p := LastDelimiter('@', L);
  if p > 0 then L := Copy(L, p + 1, MaxInt);
  // IPv6-Literal: alles zwischen den Klammern ist der Host
  if L.StartsWith('[') then
  begin
    p := Pos(']', L);
    if p > 1 then
      Result := Copy(L, 2, p - 2)
    else
      Result := Copy(L, 2, MaxInt);
    Exit;
  end;
  // Port abschneiden
  p := Pos(':', L);
  if p > 0 then L := Copy(L, 1, p - 1);
  // GATE P (SCA115-FP-Paket 2026-08-27, 1 Fund): FQDN-Wurzelpunkt abschneiden.
  // 'example.com.' IST 'example.com' - der abschliessende Punkt benennt die
  // DNS-Wurzel (RFC 1034 3.1) und gehoert nicht zum Namen. Ohne den Schnitt
  // rutschte der Host an JEDER Host-Regel unten vorbei, die auf Gleichheit
  // oder Suffix prueft. Beleg:
  //   Alcinoe\Tests\DUnitX\_Source\ALDUnitXTestUrl.pas:317
  //     'http://example.com./' -> Host war 'example.com.', damit weder
  //     = 'example.com' noch EndsWith('.example.com') -> Fund trotz RFC 2606.
  // Korrektheits-, kein Volumenargument: der Schnitt steht NACH dem IPv6-Zweig
  // (der Exit't vorher) und nach dem Port, damit 'host.:8080' genauso greift.
  while L.EndsWith('.') do
    L := Copy(L, 1, Length(L) - 1);
  Result := L;
end;

function IsNonRoutableOrReservedHost(const Url: string): Boolean;
// True wenn der Host gar kein erreichbarer Remote-Endpunkt sein KANN:
// Loopback/lokales IPC, oder eine der fuer Doku und Tests reservierten
// Adressen. In beiden Faellen gibt es keine MITM-Flaeche - eine
// https-Empfehlung waere sinnlos.
//
// Die Doku-/Test-Bereiche kamen 2026-08-16 dazu: 11 von 47 Sample-FP waren
// Parser-Fixturen und Assertion-Erwartungswerte mit example.com (RFC 2606),
// 192.0.2.x (RFC 5737) oder [2001:db8::1] (RFC 3849).
//
// RFC1918 (10/8, 172.16/12, 192.168/16) steht BEWUSST NICHT hier: im Korpus
// belegt 'http://192.168.1.153:3000/api' echte REST-Aufrufe (TP).
var
  H : string;
begin
  H := ExtractHost(Url);
  Result :=
    // --- Loopback / lokales IPC ---
    (H = 'localhost') or H.EndsWith('.localhost') or
    H.StartsWith('127.') or
    (H = '::1') or
    (H = '0.0.0.0') or
    (H = 'host.docker.internal') or
    // mORMot's synthetisches 'http://unix:/pfad' bezeichnet einen
    // UNIX-Domain-Socket (lokales IPC), keinen Remote-Endpunkt.
    (H = 'unix') or
    // --- fuer Doku und Tests reserviert ---
    // RFC 2606: example.com/.net/.org samt Subdomains, TLDs .example/
    // .test/.invalid
    (H = 'example.com') or (H = 'example.net') or (H = 'example.org') or
    H.EndsWith('.example.com') or H.EndsWith('.example.net') or
    H.EndsWith('.example.org') or
    H.EndsWith('.example') or H.EndsWith('.test') or H.EndsWith('.invalid') or
    // RFC 5737: TEST-NET-1/2/3
    H.StartsWith('192.0.2.') or H.StartsWith('198.51.100.') or
    H.StartsWith('203.0.113.') or
    // RFC 3849: IPv6-Dokumentationspraefix
    H.StartsWith('2001:db8:') or
    // link-local (RFC 3927 / RFC 4291). ACHTUNG - die Begruendung ist
    // NICHT 'nicht routbar': auf dem lokalen Segment ist eine
    // link-local-Adresse sehr wohl erreichbar und damit MITM-faehig.
    // Genau dieses Argument wurde fuer RFC1918 bewusst VERWORFEN, weil
    // 'http://192.168.1.153:3000/api' im Korpus ein belegter echter
    // Endpunkt ist. Hier gilt ein anderer Grund: eine link-local-Adresse
    // in einem QUELLTEXT-LITERAL ist eine Parser-Fixture oder ein
    // Diagnose-Beispiel - ein Deployment gegen fe80:: braucht einen
    // Zonenindex und 169.254 entsteht nur bei fehlgeschlagenem DHCP.
    // Restrisiko benannt: wer doch so deployt, verliert den Fund.
    H.StartsWith('169.254.') or H.StartsWith('fe80:');
end;

// ===========================================================================
// SCA115-FP-Paket (Autopsie 2026-08-27)
// ---------------------------------------------------------------------------
// Vollklassifikation ALLER SCA115-Funde auf dem Realworld-Korpus (rw16):
// 176 Funde = 110 FP / 66 TP, also 62,5% FP. Ursache: der Detektor bewertete
// ausschliesslich das LITERAL. Er kannte weder die Rolle der URL im Aufruf
// noch, ob sie ueberhaupt je eine Netzwerk-Senke erreicht.
//
// Die vier Gates unten (plus GATE P oben in ExtractHost) schliessen genau die
// gezaehlten FP-Klassen. Nachgerechnet mit einer Emulation ueber denselben
// Korpus: 177 Basis-Funde -> 87 verbleibend (T 52, M 27, D 6, F 4, P 1). Die
// Emulation zaehlt einen Basis-Fund mehr als rw16 (Dateiliste), die Drop-Zahl
// je Gate deckt sich mit der Autopsie.
//
// BEWUSST NICHT GEBAUT - am Korpus widerlegt:
//   * Pfad-Gate ueber /test/- und /demo/-Segmente: traefe 116 Funde, davon
//     28 BELEGTE TPs. Der Korpus legt echten Navigations-Code unter /tests/
//     und /demos/ ab (Alcinoe\Archive\Demos\ALButton\_source\Unit1.pas oeffnet
//     'http://static.arkadia.com/...' wirklich).
//   * Lizenz-Host-Whitelist (mozilla.org & Co.): kostet 4 TPs fuer 3 Drops.
//   * Konfidenz-Demote statt Drop: SCA115 ist Security-Hotspot; der
//     Auslieferungs-Default-Filter greift dort anders - ein Demote waere ein
//     No-Op. uSCAConsts bleibt deshalb unangetastet.
// ===========================================================================

type
  // Tri-State fuer das dateiweite Testfixture-Urteil (GATE T). Der Wert wird
  // LAZY berechnet - erst wenn ein http-Treffer alle billigeren Guards
  // ueberlebt hat - und dann fuer die restlichen Treffer derselben Datei
  // gemerkt. Wuerde er vor der Match-Schleife berechnet, liefe der Scan ueber
  // den ganzen Dateitext auch fuer die ~99% Dateien OHNE einen einzigen
  // http-Treffer: ein Perf-Rueckschritt fuer null zusaetzliche Wirkung.
  TFixtureVerdict = (fvUnknown, fvNo, fvYes);

function IsTestFixtureUnitBody(const CodeNoStr: string): Boolean;
// GATE T (52 Drops): die Datei IST eine Testfixture-Unit - jedes URL-Literal
// darin ist Eingabe- oder Erwartungswert eines Testfalls, kein Endpunkt.
//
// Geprueft wird der INHALT, nicht der Pfad: das Pfad-Gate ist am Korpus
// widerlegt (28 belegte TPs unter /tests/ und /demos/, s. Kopf oben).
//
// Die UND-Verknuepfung aus (a) Framework-Marker und (b) Fixture-Deklaration
// ist ZWINGEND. Mit (a) allein faellt
//   mORMot2-master\ex\mvc-blog\MVCViewModel.pas
// herein: die Unit bindet mormot.core.test NUR wegen
// TSynTestCase.RandomTextParagraph ein (Demo-Daten), ist selbst aber kein
// Test - Zeile 271 ('http://blog.synopse.info' an DotClearFlatImport) ist ein
// belegter TP. Sie hat KEINE der (b)-Deklarationen und bleibt damit Fund.
//
// Gearbeitet wird auf CodeNoStr (String-Inhalte sind mit '~' aufgefuellt).
// Damit kann kein Marker aus einem String-Literal stammen - weder aus einer
// Fixture in einem Code-Generator noch aus den Musterlisten dieser Unit
// selbst (Self-Match).
//
// Whitespace-Varianten ('class (TTestCase)') werden bewusst NICHT erkannt:
// im Korpus sind das 4 Dateien, alle ohne ein einziges http-Literal - 0
// Wirkung. Die Richtung des Fehlers ist ausserdem die sichere: ein nicht
// erkanntes Fixture behaelt seinen FP, es geht kein TP verloren.
const
  // (a) Framework-Marker. 'DUnitX.TestFramework' steht als Leitfall zuerst,
  //     obwohl 'DUnitX' es lexisch subsumiert - die Liste soll die
  //     uses-Eintraege benennen, nicht minimal sein.
  FRAMEWORK_MARKERS : array[0..3] of string = (
    'dunitx.testframework', 'dunitx', 'testframework', 'mormot.core.test');
  // (b) Fixture-Deklaration. 'class(tsyntests' ist bewusst ein PRAEFIX:
  //     mORMot leitet auch von TSynTestsLogged ab
  //     (mORMot2-master\ex\extdb-bench\PerfTestCases.pas:218).
  FIXTURE_DECLS : array[0..4] of string = (
    'tdunitx.registertestfixture', '[testfixture]',
    'class(ttestcase)', 'class(tsyntestcase)', 'class(tsyntests');
var
  L      : string;
  Marker : string;
  HasFw  : Boolean;
begin
  Result := False;
  L := LowerCase(CodeNoStr);
  HasFw := False;
  for Marker in FRAMEWORK_MARKERS do
    if Pos(Marker, L) > 0 then
    begin
      HasFw := True;
      Break;
    end;
  if not HasFw then Exit;
  for Marker in FIXTURE_DECLS do
    if Pos(Marker, L) > 0 then Exit(True);
end;

function IsFormatPlaceholderHost(const Url: string): Boolean;
// GATE F (4 Drops): der HOST der URL besteht nur aus einem Format-Platzhalter.
// So eine Zeichenkette geht nie als URL raus - erst der Format-Aufruf
// entscheidet ueber das Ziel, und in aller Regel gleich mit ueber das Schema.
// Belege:
//   delphimvcframework\sources\MVCFramework.Server.HttpSys.pas:292
//     'http://%s:%d/'   (Format)
//   mORMot2-master\src\net\mormot.net.rtsphttp.pas:414
//     'http://%:%/%'    (mORMot FormatUtf8, '%' ohne Konversionszeichen)
//
// Die Verankerung am ANFANG ist zwingend. Platzhalter im PFAD sind ein echter
// Endpunkt - cnwizards\Source\Utils\CnImageProviderFindIcons.pas:110 baut
// 'http://findicons.com/search/%s%s?icons=%d...' und schickt es durch
// TCnHTTP.GetString: ein TP, der bei unverankertem Muster verloren ginge.
const
  // Das Schema steht bewusst OHNE das '%' in der Konstanten: 'http://' allein
  // kann der eigene Detektor-Regex nicht treffen (er verlangt mindestens ein
  // Zeichen HINTER dem Schema und davor das Apostroph), 'http://%' dagegen
  // schon - diese Unit wuerde sich sonst selbst melden.
  SCHEME = 'http://';
var
  Rest : string;
begin
  Result := False;
  Rest := LowerCase(Url);
  if not Rest.StartsWith(SCHEME) then Exit;
  Rest := Copy(Rest, Length(SCHEME) + 1, MaxInt);
  // Verankert: das '%' MUSS das erste Zeichen des Hosts sein; danach steht ein
  // Konversionszeichen (Delphi Format / mORMot FormatUtf8) oder direkt der
  // Trenner zum Port bzw. zum Pfad.
  Result := (Length(Rest) >= 2) and (Rest[1] = '%') and
            CharInSet(Rest[2], ['s', 'd', 'u', 'g', 'x', 'e', 'z', ':', '/']);
end;

function LineStartBefore(const Code: string; APos: Integer): Integer;
// 1-basierter Index des ersten Zeichens der Zeile, in der APos liegt.
// 'Code' kommt aus StripFileCommentsKeepStrings: kommentarfrei, pro Quellzeile
// GENAU ein #10, keine #13 - der Rueckwaertslauf bis #10 ist damit exakt.
var
  S : Integer;
begin
  S := APos - 1;
  while (S >= 1) and (Code[S] <> #10) do Dec(S);
  Result := S + 1;
end;

function PrevNonBlankLineStart(const Code: string; ALineStart: Integer): Integer;
// 1-basierter Startindex der letzten NICHT leeren Zeile vor ALineStart;
// 0 wenn es keine gibt. Fuer mehrzeilige Aufrufe (GATE D).
var
  E, S : Integer;
begin
  Result := 0;
  E := ALineStart - 1;              // das #10, das die Vorzeile beendet
  while E >= 1 do
  begin
    S := LineStartBefore(Code, E);
    if Trim(Copy(Code, S, E - S)) <> '' then Exit(S);
    E := S - 1;
  end;
end;

function CallStillOpen(const Code: string; AParenPos, AStop: Integer): Boolean;
// True, wenn die runde Klammer an AParenPos bis AStop-1 NICHT wieder
// geschlossen wurde - die Position AStop steht dann noch in IHRER
// Argumentliste.
//
// Gezaehlt wird die Tiefe, nicht die Bilanz: sobald sie einmal auf 0
// zurueckfaellt, ist der Aufruf zu Ende, auch wenn danach eine ANDERE
// Klammer aufgeht. Mit einer blossen Bilanz wuerde
//     Writeln(OutFile, 'a');   ShowMessage('http://x');
// beim Writeln-Treffer +1 -1 +1 = 1 ergeben und den Aufruf faelschlich
// als offen melden.
//
// Pascal-String-Literale werden UEBERSPRUNGEN: 'Code' enthaelt sie im
// Original, und eine Klammer im Text eines Literals ist keine Klammer des
// Aufrufs.
var
  i, Depth : Integer;
begin
  Depth := 0;
  i := AParenPos;
  while i < AStop do
  begin
    case Code[i] of
      '''':
        begin
          Inc(i);
          while i < AStop do
          begin
            if Code[i] = #10 then Break;        // Literal endet am Zeilenende
            if Code[i] = '''' then
            begin
              if (i + 1 < AStop) and (Code[i + 1] = '''') then Inc(i)
              else Break;                       // schliessendes Apostroph
            end;
            Inc(i);
          end;
        end;
      '(' : Inc(Depth);
      ')' :
        begin
          Dec(Depth);
          if Depth <= 0 then Exit(False);
        end;
    end;
    Inc(i);
  end;
  // Gegenpruefung 2026-08-27 (MAJOR): '= 1', nicht '> 0'. Sonst gilt das
  // Literal auch dann als Anzeige-Argument, wenn es in einem GESCHACHTELTEN
  // Aufruf innerhalb der Senke steht - 'Memo.Lines.Add(HttpClient.Get(
  // ''http://api/secret''))' waere gedroppt worden, obwohl dort wirklich
  // eine Verbindung aufgebaut wird. Tiefe 1 heisst: direktes Argument der
  // Senke. Am Korpus messneutral (T 52 / M 27 / D 6 / F 4 unveraendert).
  Result := Depth = 1;
end;

function IsDisplayOrLogSinkArgument(const Code: string;
  AFrom, AUrlPos: Integer): Boolean;
// GATE D (6 Drops): das URL-Literal ist ARGUMENT einer engen Anzeige-/Log-
// Senke. Was in ein Memo, auf die Konsole, in eine MessageBox oder in einen
// Fortschritts-Callback geschrieben wird, geht nicht ins Netz - es ist Text
// fuer den Benutzer. Belege:
//   Dev-Cpp\Source\VCL\SynEdit\SynGen\SynGenUnit.pas:765     Writeln(OutFile,..
//   HeidiSQL\components\synedit\SynGen\SynGenUnit.pas:774    Writeln(FOutFile,..
//   TES5Edit\Core\wbLOD.pas:3228                             wbProgressCallback(
//   TES5Edit\xEdit\xeLogAnalyzerForm.pas:731,741,743         memoText.Lines.Add(
//
// Die Musterliste ist ABSCHLIESSEND und eng. Ein generisches 'Add(' ist
// AUSDRUECKLICH NICHT drin - das faengt jede Liste, auch die der URLs, die ein
// Downloader danach abarbeitet.
//
// Geprueft wird nicht "Senke steht irgendwo in der Naehe", sondern "das
// Literal steht IN ihrer Argumentliste": zur gefundenen Senke wird geprueft,
// ob ihre oeffnende Klammer bis zum Literal noch offen ist (CallStillOpen).
// Ohne diese Bedingung wuerde
//     WriteLn('fertig');
//     Url := 'http://echter.endpunkt/api';
// den TP darunter mitreissen - die Vorzeile wird ja mitgelesen, damit
// Fortsetzungen wie 'memoText.Lines.Add(' + Zeilenumbruch + Literal greifen.
// Am Korpus ist die Bedingung messneutral (6 Drops mit und ohne, alle sechs
// stehen einzeilig); sie ist reiner TP-Schutz.
//
// 'Code' laesst String-Literale stehen - deshalb die Pflichtpruefung
// TDetectorUtils.InStringLiteral auf jeden Senken-Treffer: ein 'writeln('
// im Text eines Literals ist kein Aufruf.
const
  SINKS : array[0..2] of string = (
    '.lines.add(', 'writeln(', 'showmessage(');
  // Praefix-Pflicht: der Callback heisst im Korpus 'wbProgressCallback'. Ein
  // nacktes 'ProgressCallback(' waere zu weit - das kann auch ein Aufruf sein,
  // der die URL zum Herunterladen weiterreicht.
  PROGRESS = 'progresscallback(';
var
  SpanLow : string;
  S       : string;
  p       : Integer;

  function StillOpenAt(APatEnd: Integer): Boolean;
  // APatEnd = 1-basierter Index der '(' des Musters IN SpanLow.
  begin
    Result := CallStillOpen(Code, AFrom + APatEnd - 1, AUrlPos);
  end;

begin
  Result := False;
  if AUrlPos <= AFrom then Exit;
  SpanLow := LowerCase(Copy(Code, AFrom, AUrlPos - AFrom));
  for S in SINKS do
  begin
    p := Pos(S, SpanLow);
    while p > 0 do
    begin
      // p + Length(S) - 1 zeigt auf die '(' des Musters.
      if (not TDetectorUtils.InStringLiteral(Code, AFrom + p - 1)) and
         StillOpenAt(p + Length(S) - 1) then Exit(True);
      p := PosEx(S, SpanLow, p + 1);
    end;
  end;
  p := Pos(PROGRESS, SpanLow);
  while p > 1 do
  begin
    if CharInSet(SpanLow[p - 1], ['a'..'z', '0'..'9', '_']) and
       (not TDetectorUtils.InStringLiteral(Code, AFrom + p - 1)) and
       StillOpenAt(p + Length(PROGRESS) - 1) then Exit(True);
    p := PosEx(PROGRESS, SpanLow, p + 1);
  end;
end;

function IsMetadataUrlAssignment(const LinePrefix: string): Boolean;
// GATE M (27 Drops): links vom ':=' steht ein OpenAPI-/Registry-Metadatenfeld.
// Der Wert wird in ein Dokument geschrieben (Swagger-Info-Block) und beschreibt
// eine fremde Seite - er wird von diesem Programm nie abgerufen. Belege (alle
// 27 Funde verteilen sich auf diese vier Feldnamen):
//   delphimvcframework\samples\swagger_doc\WebModuleMainU.pas:57,63
//     LSwagInfo.TermsOfService := / LSwagInfo.LicenseUrl :=
//   delphimvcframework\lib\swagdoc\Demos\SampleApi\Sample.SwagDoc.pas:72,78
//     fSwagDoc.Info.TermsOfService := / fSwagDoc.Info.License.Url :=
//   delphimvcframework\samples\swagger_api_versioning_primer\WebModuleU.pas:40,52
//     Result.ContactUrl :=
//
// Die Liste ist ABSCHLIESSEND. Sie darf NICHT um Homepage/HomeUrl/AboutBox
// erweitert werden: 'HomeUrl := ''http://www.findicons.com''' in
// cnwizards\Source\Utils\CnImageProviderFindIcons.pas:79 ist ein TP - der Wert
// geht an OpenUrl und wird tatsaechlich aufgerufen.
//
// 'registryname' hat im Korpus NULL Treffer (die 27 kommen restlos aus den
// vier Feldern oben) und steht hier auf Ansage des Pakets mit; er ist die
// einzige unbelegte Zeile der Liste.
//
// Geprueft wird das Feld als unmittelbares Zuweisungsziel (Zeilenrest endet
// auf '<feld> :='), nicht als Vorkommen irgendwo in der Zeile.
const
  META_FIELDS : array[0..6] of string = (
    'termsofservice', 'licenseurl', 'licenceurl', 'license.url',
    'licence.url', 'contacturl', 'registryname');
var
  L   : string;
  Fld : string;
begin
  Result := False;
  L := LowerCase(LinePrefix).TrimRight;
  if not L.EndsWith(':=') then Exit;
  L := Copy(L, 1, Length(L) - 2).TrimRight;
  for Fld in META_FIELDS do
    if L.EndsWith(Fld) then Exit(True);
end;

class procedure TRestHttpSecurityDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines       : TStringList;
  Cached      : Boolean;
  Code        : string;          // strings KEPT - used by URL matcher
  CodeNoStr   : string;          // strings filled with '~' - used by TLS matcher
  LineFor     : TArray<Integer>;
  Matches     : TMatchCollection;
  M           : TMatch;
  LineNo      : Integer;
  F           : TLeakFinding;
  Url         : string;
  LStart      : Integer;         // Zeilenanfang des aktuellen Treffers
  PrevStart   : Integer;         // Zeilenanfang der Vorzeile (0 = keine)
  FixtureUnit : TFixtureVerdict; // GATE T - lazy, einmal pro Datei
  ReHttp      : TRegEx;
  ReSecProto  : TRegEx;
  ReIgnoreCrt : TRegEx;
  ReVerifyNil : TRegEx;
  ReIndyVerifyEmpty : TRegEx;
  ReIndyOldProto    : TRegEx;
  ReSecProtoOld     : TRegEx;

  procedure Emit(K: TFindingKind; const Detail: string; AtPos: Integer);
  begin
    LineNo := TDetectorUtils.LineForPos(LineFor, AtPos);
    if LineNo <= 0 then LineNo := 1;
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := '';
    F.LineNumber := IntToStr(LineNo);
    F.MissingVar := Detail;
    F.SetKind(K);
    Results.Add(F);
  end;

begin
  ReHttp      := TRegExMatches.CachedEx(RE_HTTP_URL, [roNotEmpty]);
  ReSecProto  := TRegExMatches.CachedEx(RE_SEC_PROTO_EMPTY, [roNotEmpty]);
  ReIgnoreCrt := TRegExMatches.CachedEx(RE_IGNORE_CERT, [roNotEmpty]);
  ReVerifyNil := TRegExMatches.CachedEx(RE_VERIFY_PEER_NIL, [roNotEmpty]);
  ReIndyVerifyEmpty := TRegExMatches.CachedEx(RE_INDY_VERIFY_EMPTY, [roNotEmpty]);
  ReIndyOldProto    := TRegExMatches.CachedEx(RE_INDY_OLD_PROTO, [roNotEmpty]);
  ReSecProtoOld     := TRegExMatches.CachedEx(RE_SEC_PROTO_OLD, [roNotEmpty]);
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    Code := TDetectorUtils.StripFileCommentsKeepStringsCached(Lines, LineFor, AContext, FileName);
    // Zweite Sicht: Strings + Kommentare entfernt (Strings mit '~' aufgefuellt,
    // Laenge erhalten). Verwendet von den TLS-Property-Patterns, damit die
    // Quickfix-Templates in uFixHint.pas, die SecureProtocols := [] als
    // Pascal-String-Literal enthalten, KEIN Self-Match mehr produzieren.
    // LineFor wird verworfen, weil StripFileComments + StripStringsAndComments
    // Kommentare identisch entfernen und String-Bereiche die Laenge nicht
    // veraendern - die LineFor-Mapping ist fuer beide Sichten identisch.
    var LineForUnused: TArray<Integer>;
    // Perf (2026-07-05): P1-strip-cache - geteilter Strip via Context-Cache.
    CodeNoStr := TDetectorUtils.StripStringsAndCommentsCached(
      Lines, LineForUnused, AContext, FileName);

    // 1) 'http://...' Stringliteral - aber NICHT XML-Namespace und NICHT
    //    Localhost. Match auf das gesamte URL-Literal bis whitespace
    //    oder ' (closing quote). NUTZT Code (mit Strings), nicht CodeNoStr.
    Matches := ReHttp.Matches(Code);
    FixtureUnit := fvUnknown;
    for M in Matches do
    begin
      Url := M.Groups[1].Value;
      // Loopback-, IPC- und Doku-/Test-Adressen: kein erreichbarer Endpunkt
      // (enthaelt GATE P, den FQDN-Wurzelpunkt-Schnitt in ExtractHost)
      if IsNonRoutableOrReservedHost(Url) then Continue;
      // XML-Namespace-Whitelist (URL ist eine Identitaet, kein Call)
      if (Pos('xmlns', LowerCase(Url)) > 0) or
         (Pos('schemas',     LowerCase(Url)) > 0) or
         (Pos('w3.org',      LowerCase(Url)) > 0) or
         (Pos('xmlsoap.org', LowerCase(Url)) > 0) or
         (Pos('namespaces',  LowerCase(Url)) > 0) then Continue;
      // --- SCA115-FP-Paket 2026-08-27, Reihenfolge = aufsteigende Kosten ---
      // GATE F: Host ist nur ein Format-Platzhalter (reiner String-Vergleich)
      if IsFormatPlaceholderHost(Url) then Continue;
      // Zeilenschnitt fuer GATE M und GATE D: 'Code' ist kommentarfrei und
      // zeilenerhaltend, M.Index ist 1-basiert.
      LStart := LineStartBefore(Code, M.Index);
      // GATE M: OpenAPI-/Registry-Metadatenfeld links vom ':='
      if IsMetadataUrlAssignment(Copy(Code, LStart, M.Index - LStart)) then
        Continue;
      // GATE D: das Literal ist Argument einer engen Anzeige-/Log-Senke.
      // Der Blick beginnt eine nicht-leere Zeile frueher, damit mehrzeilige
      // Aufrufe (Senke offen, Literal in der Folgezeile) mitgefasst sind.
      PrevStart := PrevNonBlankLineStart(Code, LStart);
      if PrevStart = 0 then PrevStart := LStart;
      if IsDisplayOrLogSinkArgument(Code, PrevStart, M.Index) then Continue;
      // GATE T: die Datei ist eine Testfixture-Unit. Teuerster Guard, deshalb
      // LAZY und pro Datei nur EINMAL gerechnet - Dateien ohne ueberlebenden
      // http-Treffer zahlen ihn gar nicht.
      if FixtureUnit = fvUnknown then
      begin
        if IsTestFixtureUnitBody(CodeNoStr) then
          FixtureUnit := fvYes
        else
          FixtureUnit := fvNo;
      end;
      if FixtureUnit = fvYes then Continue;
      Emit(fkHttpInsteadOfHttps,
        Format('Plaintext HTTP URL ''%s'' - prefer https:// for remote ' +
               'endpoints. MITM-readable; credentials, tokens and PII ' +
               'travel unencrypted. Suppress for ad-hoc dev URLs with ' +
               '// noinspection HttpInsteadOfHttps',
               [Url]),
        M.Index);
    end;

    // 2a) ...SecureProtocols := [];   NUTZT CodeNoStr (kein Self-Match in Templates).
    Matches := ReSecProto.Matches(CodeNoStr);
    for M in Matches do
      Emit(fkDisabledTlsVerification,
        'SecureProtocols := [] disables all TLS protocols - the HTTP ' +
        'client may fall back to plaintext. Set explicit modern protocols ' +
        '(TLSv1_2, TLSv1_3) instead.',
        M.Index);

    // 2b) ...IgnoreCertificateErrors := True
    Matches := ReIgnoreCrt.Matches(CodeNoStr);
    for M in Matches do
      Emit(fkDisabledTlsVerification,
        'IgnoreCertificateErrors := True silently accepts any TLS ' +
        'certificate including self-signed and expired ones - MITM-' +
        'vulnerable. Use a proper trust store or pin the certificate ' +
        'fingerprint instead.',
        M.Index);

    // 2c) OnVerifyPeer := nil (oder leerer Handler) - heuristisch nur
    //     der nil-Match, weil leere Handler AST brauchen.
    Matches := ReVerifyNil.Matches(CodeNoStr);
    for M in Matches do
      Emit(fkDisabledTlsVerification,
        'OnVerifyPeer := nil short-circuits the TLS certificate-validation ' +
        'callback. Anything served over TLS is accepted unconditionally. ' +
        'Implement a real verification handler or leave the default in place.',
        M.Index);

    // 2d) Indy: SSLOptions.VerifyMode := []  (Audit E-Kurzliste 2026-06-18)
    //     TIdSSLIOHandlerSocketOpenSSL akzeptiert dann jedes Zertifikat -
    //     gleicher Effekt wie OnVerifyPeer:=nil, aber idiomatischer in
    //     Indy-Code.
    Matches := ReIndyVerifyEmpty.Matches(CodeNoStr);
    for M in Matches do
      Emit(fkDisabledTlsVerification,
        'Indy SSLOptions.VerifyMode := [] disables peer-certificate ' +
        'validation - any TLS endpoint is accepted unconditionally. ' +
        'Set at minimum [sslvrfPeer] and provide a CA cert (RootCertFile).',
        M.Index);

    // 2e) Indy: SSLOptions.Method := sslvSSLv2/3/TLSv1  (Audit 2026-06-18)
    //     Veraltete Protokoll-Versionen - POODLE (SSLv3) und alte TLS-
    //     Suiten sind seit Jahren disallowed.
    Matches := ReIndyOldProto.Matches(CodeNoStr);
    for M in Matches do
      Emit(fkDisabledTlsVerification,
        'Indy SSLOptions.Method set to deprecated TLS/SSL protocol ' +
        '(sslvSSLv2/sslvSSLv3 = broken; sslvTLSv1 = phased out 2020). ' +
        'Use sslvTLSv1_2 or sslvTLSv1_3 instead.',
        M.Index);

    // 2f) THTTPClient.SecureProtocols mit SSL3/SSL2/TLS1 in der Set.
    //     Andere Code-Basen (System.Net.HttpClient) nutzen das Set-Pattern.
    Matches := ReSecProtoOld.Matches(CodeNoStr);
    for M in Matches do
      Emit(fkDisabledTlsVerification,
        'SecureProtocols includes deprecated SSL/TLS version (SSL2/SSL3/TLS1) ' +
        '- vulnerable to POODLE / BEAST / weak-cipher attacks. Limit the ' +
        'set to TLSv1_2 and TLSv1_3.',
        M.Index);
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
