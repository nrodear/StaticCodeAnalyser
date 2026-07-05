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
  uFileTextCache, uDetectorUtils;

var
  // Module-Level Regex-Cache: Patterns sind konstant, kein Grund pro File
  // neu zu kompilieren. Lazy-Init in der ersten AnalyzeUnit-Invocation
  // (Initializer braeuchte sonst RegEx-Unit-Initialization-Order-Garantie).
  // Spart Compilations x N Files pro Scan.
  CachedReHttp      : TRegEx;
  CachedReSecProto  : TRegEx;
  CachedReIgnoreCrt : TRegEx;
  CachedReVerifyNil : TRegEx;
  // 2026-06-18 (Audit-Kurzliste E-21): Indy-spezifische TLS-Disable.
  // TIdHTTP / TIdSSLIOHandlerSocketOpenSSL nutzen .SSLOptions.X-Pattern.
  CachedReIndyVerifyEmpty : TRegEx;   // SSLOptions.VerifyMode := []
  CachedReIndyOldProto    : TRegEx;   // SSLOptions.Method := sslvSSLv2/3/TLSv1
  CachedReSecProtoOld     : TRegEx;   // SecureProtocols := [sslv3] (THTTPClient)
  CachedReInit      : Boolean = False;

procedure EnsureRegexCacheBuilt;
begin
  if CachedReInit then Exit;
  CachedReHttp      := TRegEx.Create('''(http://[^''\s]+)''');
  CachedReSecProto  := TRegEx.Create('(?i)\bSecureProtocols\s*:=\s*\[\s*\]');
  CachedReIgnoreCrt := TRegEx.Create('(?i)\bIgnoreCertificateErrors\s*:=\s*True\b');
  CachedReVerifyNil := TRegEx.Create('(?i)\bOnVerifyPeer\s*:=\s*nil\b');
  // Indy-Patterns. Pfad-Variante `Foo.SSLOptions.X := …` per `\.` vor Marker.
  CachedReIndyVerifyEmpty := TRegEx.Create(
    '(?i)\.?\bSSLOptions\.VerifyMode\s*:=\s*\[\s*\]');
  // sslvSSLv2/3 sind formal abgeschaltet seit RFC 7568 (SSLv3 - POODLE)
  // bzw. RFC 6176 (SSLv2). sslvTLSv1 = TLS 1.0 ist seit ~2020 von allen
  // Browsern abgekuendigt. Wir flaggen alle drei.
  CachedReIndyOldProto    := TRegEx.Create(
    '(?i)\.?\bSSLOptions\.Method\s*:=\s*sslv(SSLv2|SSLv3|TLSv1)\b');
  // THTTPClient.SecureProtocols mit veraltetem Protokoll-Set.
  // SSL3 / TLS1 sind disallowed in modernen Stacks.
  CachedReSecProtoOld     := TRegEx.Create(
    '(?i)\bSecureProtocols\s*:=\s*\[[^]]*\b(SSL3|SSL2|TLS1)\b');
  CachedReInit      := True;
end;

function StripFileComments(Lines: TStringList; out LineForChar: TArray<Integer>): string;
var
  Buf            : TStringBuilder;
  i, n, j        : Integer;
  Line           : string;
  InBlk, InParen : Boolean;
  InStr          : Boolean;
  c              : Char;
  pClose         : Integer;
  Chars          : TList<Integer>;
begin
  Buf := TStringBuilder.Create;
  Chars := TList<Integer>.Create;
  try
    InBlk := False; InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i]; InStr := False; j := 1; n := Length(Line);
      while j <= n do
      begin
        if InBlk then
        begin
          pClose := PosEx('}', Line, j);
          if pClose = 0 then Break;
          InBlk := False; j := pClose + 1; Continue;
        end;
        if InParen then
        begin
          pClose := PosEx('*)', Line, j);
          if pClose = 0 then Break;
          InParen := False; j := pClose + 2; Continue;
        end;
        c := Line[j];
        if InStr then
        begin
          Buf.Append(c); Chars.Add(i);
          if c = '''' then
          begin
            if (j < n) and (Line[j + 1] = '''') then
            begin Buf.Append(''''); Chars.Add(i); Inc(j, 2); end
            else begin InStr := False; Inc(j); end;
          end else Inc(j);
          Continue;
        end;
        if c = '''' then
        begin Buf.Append(c); Chars.Add(i); InStr := True; Inc(j); Continue; end;
        if (c = '/') and (j < n) and (Line[j + 1] = '/') then Break;
        if c = '{' then
        begin
          pClose := PosEx('}', Line, j + 1);
          if pClose = 0 then begin InBlk := True; Break; end;
          j := pClose + 1; Continue;
        end;
        if (c = '(') and (j < n) and (Line[j + 1] = '*') then
        begin
          pClose := PosEx('*)', Line, j + 2);
          if pClose = 0 then begin InParen := True; Break; end;
          j := pClose + 2; Continue;
        end;
        Buf.Append(c); Chars.Add(i);
        Inc(j);
      end;
      Buf.Append(#10); Chars.Add(i);
    end;
    Result := Buf.ToString;
    LineForChar := Chars.ToArray;
  finally
    Chars.Free; Buf.Free;
  end;
end;

function IsLocalhost(const Url: string): Boolean;
// True wenn die URL klar auf den localhost-Stack zeigt - dann ist HTTP
// fuer Dev-Workflows legitim, kein Befund.
var
  L : string;
begin
  L := LowerCase(Url);
  Result :=
    (Pos('http://localhost',  L) > 0) or
    (Pos('http://127.',       L) > 0) or
    (Pos('http://[::1]',      L) > 0) or
    (Pos('http://0.0.0.0',    L) > 0) or
    (Pos('http://host.docker.internal', L) > 0);
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
  EnsureRegexCacheBuilt;
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    Code := StripFileComments(Lines, LineFor);
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
    Matches := CachedReHttp.Matches(Code);
    for M in Matches do
    begin
      Url := M.Groups[1].Value;
      // Localhost-Whitelist
      if IsLocalhost(Url) then Continue;
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
    Matches := CachedReSecProto.Matches(CodeNoStr);
    for M in Matches do
      Emit(fkDisabledTlsVerification,
        'SecureProtocols := [] disables all TLS protocols - the HTTP ' +
        'client may fall back to plaintext. Set explicit modern protocols ' +
        '(TLSv1_2, TLSv1_3) instead.',
        M.Index);

    // 2b) ...IgnoreCertificateErrors := True
    Matches := CachedReIgnoreCrt.Matches(CodeNoStr);
    for M in Matches do
      Emit(fkDisabledTlsVerification,
        'IgnoreCertificateErrors := True silently accepts any TLS ' +
        'certificate including self-signed and expired ones - MITM-' +
        'vulnerable. Use a proper trust store or pin the certificate ' +
        'fingerprint instead.',
        M.Index);

    // 2c) OnVerifyPeer := nil (oder leerer Handler) - heuristisch nur
    //     der nil-Match, weil leere Handler AST brauchen.
    Matches := CachedReVerifyNil.Matches(CodeNoStr);
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
    Matches := CachedReIndyVerifyEmpty.Matches(CodeNoStr);
    for M in Matches do
      Emit(fkDisabledTlsVerification,
        'Indy SSLOptions.VerifyMode := [] disables peer-certificate ' +
        'validation - any TLS endpoint is accepted unconditionally. ' +
        'Set at minimum [sslvrfPeer] and provide a CA cert (RootCertFile).',
        M.Index);

    // 2e) Indy: SSLOptions.Method := sslvSSLv2/3/TLSv1  (Audit 2026-06-18)
    //     Veraltete Protokoll-Versionen - POODLE (SSLv3) und alte TLS-
    //     Suiten sind seit Jahren disallowed.
    Matches := CachedReIndyOldProto.Matches(CodeNoStr);
    for M in Matches do
      Emit(fkDisabledTlsVerification,
        'Indy SSLOptions.Method set to deprecated TLS/SSL protocol ' +
        '(sslvSSLv2/sslvSSLv3 = broken; sslvTLSv1 = phased out 2020). ' +
        'Use sslvTLSv1_2 or sslvTLSv1_3 instead.',
        M.Index);

    // 2f) THTTPClient.SecureProtocols mit SSL3/SSL2/TLS1 in der Set.
    //     Andere Code-Basen (System.Net.HttpClient) nutzen das Set-Pattern.
    Matches := CachedReSecProtoOld.Matches(CodeNoStr);
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
