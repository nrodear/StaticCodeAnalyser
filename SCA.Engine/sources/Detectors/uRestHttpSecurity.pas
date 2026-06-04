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
  uAstNode, uSCAConsts, uMethodd12;

type
  TRestHttpSecurityDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.RegularExpressions, System.StrUtils,
  uFileTextCache, uDetectorUtils;

var
  // Module-Level Regex-Cache: Patterns sind konstant, kein Grund pro File
  // neu zu kompilieren. Lazy-Init in der ersten AnalyzeUnit-Invocation
  // (Initializer braeuchte sonst RegEx-Unit-Initialization-Order-Garantie).
  // Spart 4 Compilations x N Files pro Scan.
  CachedReHttp      : TRegEx;
  CachedReSecProto  : TRegEx;
  CachedReIgnoreCrt : TRegEx;
  CachedReVerifyNil : TRegEx;
  CachedReInit      : Boolean = False;

procedure EnsureRegexCacheBuilt;
begin
  if CachedReInit then Exit;
  CachedReHttp      := TRegEx.Create('''(http://[^''\s]+)''');
  CachedReSecProto  := TRegEx.Create('(?i)\bSecureProtocols\s*:=\s*\[\s*\]');
  CachedReIgnoreCrt := TRegEx.Create('(?i)\bIgnoreCertificateErrors\s*:=\s*True\b');
  CachedReVerifyNil := TRegEx.Create('(?i)\bOnVerifyPeer\s*:=\s*nil\b');
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

function LineForPos(const LineFor: TArray<Integer>; Pos: Integer): Integer;
begin
  if (Pos >= 1) and (Pos - 1 < Length(LineFor)) then
    Result := LineFor[Pos - 1] + 1
  else
    Result := 0;
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
  const FileName: string; Results: TObjectList<TLeakFinding>);
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
    LineNo := LineForPos(LineFor, AtPos);
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
  Lines := AcquireLines(FileName, Cached);
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
    CodeNoStr := TDetectorUtils.StripStringsAndComments(Lines, LineForUnused);

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
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
