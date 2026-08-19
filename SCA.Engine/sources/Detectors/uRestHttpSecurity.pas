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

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, DeepNesting, GroupedDeclaration, IfElseBegin, InsecureCryptoAlgorithm, LongMethod, RedundantBoolean, TooLongLine, UnsortedUses, UnusedLocalVar, UnusedParameter
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
    for M in Matches do
    begin
      Url := M.Groups[1].Value;
      // Loopback-, IPC- und Doku-/Test-Adressen: kein erreichbarer Endpunkt
      if IsNonRoutableOrReservedHost(Url) then Continue;
      // XML-Namespace-Whitelist (URL ist eine Identitaet, kein Call)
      if (Pos('xmlns', LowerCase(Url)) > 0) or
         (Pos('schemas',     LowerCase(Url)) > 0) or
         (Pos('w3.org',      LowerCase(Url)) > 0) or
         (Pos('xmlsoap.org', LowerCase(Url)) > 0) or
         (Pos('namespaces',  LowerCase(Url)) > 0) then Continue;
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
