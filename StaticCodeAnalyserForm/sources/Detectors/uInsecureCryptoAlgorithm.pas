unit uInsecureCryptoAlgorithm;

// Detektor: Verwendung schwacher / veralteter Krypto-Verfahren (SCA162).
//
// Sicherheitsbefund. Geflagged wird:
//   * Algorithmus-Namen als Stringliteral oder Variable:
//       'MD5', 'SHA1', 'DES', '3DES', 'RC4', 'TLS1.0', 'TLS1.1', 'SSL3.0',
//       'SSLv3'
//   * Bekannte Klassen-Wrapper:
//       THashMD5, THashSHA1, TIdHashMessageDigest5, TIdHashSHA1,
//       TDESCryptoServiceProvider, TRC4Cipher
//
// Hintergrund:
//   MD5  - Kollisionen seit 2004 (Wang et al.), nicht mehr fuer Signaturen.
//   SHA1 - chosen-prefix collision 2017 (SHAttered), RFC 6194 sunset 2011.
//   DES  - 56-bit Key, faktorisch brute-forceable seit '90s.
//   3DES - Sweet32 CBC-collision (CVE-2016-2183).
//   RC4  - statistische Biases, RFC 7465 prohibits in TLS.
//   TLS 1.0/1.1 - RFC 8996 deprecated, BEAST/POODLE/Lucky13.
//   SSLv3 - POODLE (CVE-2014-3566).
//
// Erkennung (AST-basiert, analog uSqlDangerousStatement):
//   * nkAssign: TypeRef wird gegen Token-Liste mit Wortgrenz-Match
//     gescannt - 'MD5Hash' matched NICHT (Right-Boundary 'H'), 'MD5'/'_MD5'
//     /'MD5,' schon.
//   * nkCall: Name wird gegen die gleiche Token-Liste UND eine zweite
//     Klassen-Wrapper-Liste (Substring-Match, da Klassennamen self-anchoring
//     sind) gescannt.
//
// Limitierungen:
//   * Algorithmus aus Config geladen ('algo := LoadCryptoAlgorithm') wird
//     nicht erkannt - Symbol-/Taint-Tabelle nicht vorhanden.
//   * False-Positives moeglich bei englischen Error-Messages
//     'MD5 hash failed' - akzeptabel, da Audit-relevante Strings ohnehin
//     in den Code-Review wandern.
//
// Severity: lsWarning, Type: ftVulnerability (siehe KIND_META).

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TInsecureCryptoAlgorithmDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    // True wenn ein schwacher Algorithmus-Token mit Wortgrenz-Match
    // gefunden wird. Liefert das Token in CANONICAL-Form (uppercase) zurueck.
    class function FindWeakAlgo(const Source: string; out Hit: string): Boolean; static;
    // True wenn ein bekannter Krypto-Klassen-Wrapper im Source vorkommt
    // (Substring-Match, da Klassennamen self-anchoring sind).
    class function FindWeakClass(const Source: string; out Hit: string): Boolean; static;
  end;

implementation

const
  // Algorithmus-Namen die als Stringliteral / Konstante / Identifier auftauchen.
  // Match-Methode: Wortgrenz, case-insensitive. Reihenfolge: laengste Token
  // zuerst, damit '3des'/'tripledes' nicht von 'des' geclobbert werden.
  WEAK_ALGO_TOKENS: array[0..9] of string = (
    'tripledes',  // 3DES alias
    'tls1.0', 'tls1.1', 'sslv3', 'ssl3',
    '3des',
    'md5', 'sha1', 'rc4',
    'des'
  );

  // Klassen-Wrapper: Substring-Match. Diese sind eindeutig (THashMD5 ist
  // niemals ein generischer Helper-Name).
  WEAK_CLASS_TOKENS: array[0..5] of string = (
    'thashmd5',                  // System.Hash.THashMD5
    'thashsha1',                 // System.Hash.THashSHA1
    'tidhashmessagedigest5',     // Indy TIdHashMessageDigest5
    'tidhashsha1',               // Indy TIdHashSHA1
    'tdescryptoserviceprovider', // .NET-Style
    'trc4cipher'                 // Diverse RC4-Wrapper
  );

class function TInsecureCryptoAlgorithmDetector.FindWeakAlgo(
  const Source: string; out Hit: string): Boolean;
// Wortgrenz-Match. Beispiele bei Source = "algo := 'MD5'":
//   Low = "algo := 'md5'"
//   Pos('md5', Low) = 10 (nach dem Apostroph)
//   Linker Char (Pos 9) = ''' -> nicht in [a-z0-9_] -> Left-Boundary OK
//   Rechter Char (Pos 13) = ''' -> nicht in [a-z0-9_] -> Right-Boundary OK
//   -> Hit = 'MD5'
//
// Bei "MD5Hash := ..." dagegen:
//   Pos('md5', 'md5hash := ...') = 1
//   PRight = 4, Char = 'h' -> in [a-z] -> kein Boundary -> kein Hit
var
  Low      : string;
  Tok      : string;
  P, PRight: Integer;
begin
  Result := False;
  Hit    := '';
  Low    := LowerCase(Source);

  for Tok in WEAK_ALGO_TOKENS do
  begin
    P := Pos(Tok, Low);
    while P > 0 do
    begin
      // Left boundary: Anfang oder Nicht-Ident-Char davor
      if (P = 1)
         or not CharInSet(Low[P - 1], ['a'..'z', '0'..'9', '_']) then
      begin
        PRight := P + Length(Tok);
        // Right boundary: Ende oder Nicht-Ident-Char danach.
        // Achtung Tokens wie 'tls1.0' enden auf '0' (digit) - der Punkt
        // im Token selbst wird mitgematcht; danach muss eine Nicht-Ident-
        // Grenze stehen (z.B. ''', ' ', ';', ')').
        if (PRight > Length(Low))
           or not CharInSet(Low[PRight], ['a'..'z', '0'..'9', '_']) then
        begin
          // Canonical-Form fuer User-Output. UpperCase ausser bei Token
          // mit '.' (TLS1.0 statt TLS1.0 - okay UpperCase eh idempotent).
          Hit := UpperCase(Tok);
          Exit(True);
        end;
      end;
      P := Pos(Tok, Low, P + 1);
    end;
  end;
end;

class function TInsecureCryptoAlgorithmDetector.FindWeakClass(
  const Source: string; out Hit: string): Boolean;
// Substring-Match. Klassennamen wie 'THashMD5' sind self-anchoring -
// niemand baut versehentlich 'XYthashmd5' als Identifier-Substring.
var
  Low : string;
  Tok : string;
begin
  Result := False;
  Hit    := '';
  Low    := LowerCase(Source);
  for Tok in WEAK_CLASS_TOKENS do
    if Pos(Tok, Low) > 0 then
    begin
      // Canonical-Casing aus der Liste rekonstruieren ist umstaendlich -
      // wir nehmen den Token aus dem Source (Original-Casing) zurueck.
      var P := Pos(Tok, Low);
      Hit := Copy(Source, P, Length(Tok));
      Exit(True);
    end;
end;

class procedure TInsecureCryptoAlgorithmDetector.AnalyzeMethod(
  MethodNode: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);

  procedure Report(const What, Context: string; Line: Integer);
  var F: TLeakFinding;
  begin
    F            := TLeakFinding.Create;
    F.FileName   := FileName;
    F.MethodName := MethodNode.Name;
    F.LineNumber := IntToStr(Line);
    F.MissingVar := Format(
      'Insecure crypto algorithm: %s used in %s', [What, Context]);
    F.SetKind(fkInsecureCryptoAlgorithm);
    Results.Add(F);
  end;

var
  Assigns, Calls : TList<TAstNode>;
  N              : TAstNode;
  Hit            : string;
  // Dedup auf (Line, Hit) damit ein einzelner 'Hash := THashMD5.Create' nicht
  // doppelt geflagged wird (einmal ueber nkAssign.TypeRef, einmal ueber
  // nkCall.Name). Key-Format: 'line|hit'.
  Seen           : TDictionary<string, Boolean>;
  Key            : string;
begin
  Seen := TDictionary<string, Boolean>.Create;
  try
    Assigns := MethodNode.FindAll(nkAssign);
    try
      for N in Assigns do
      begin
        // Erst Algorithmus-Token (in Literal/Identifier auf RHS)
        if FindWeakAlgo(N.TypeRef, Hit) then
        begin
          Key := IntToStr(N.Line) + '|' + LowerCase(Hit);
          if not Seen.ContainsKey(Key) then
          begin
            Seen.Add(Key, True);
            Report(Hit, N.Name, N.Line);
          end;
        end;
        // Dann Klassen-Wrapper (z.B. 'Hash := THashMD5.Create')
        if FindWeakClass(N.TypeRef, Hit) then
        begin
          Key := IntToStr(N.Line) + '|' + LowerCase(Hit);
          if not Seen.ContainsKey(Key) then
          begin
            Seen.Add(Key, True);
            Report(Hit, N.Name, N.Line);
          end;
        end;
      end;
    finally
      Assigns.Free;
    end;

    Calls := MethodNode.FindAll(nkCall);
    try
      for N in Calls do
      begin
        if FindWeakAlgo(N.Name, Hit) then
        begin
          Key := IntToStr(N.Line) + '|' + LowerCase(Hit);
          if not Seen.ContainsKey(Key) then
          begin
            Seen.Add(Key, True);
            Report(Hit, N.Name, N.Line);
          end;
        end;
        if FindWeakClass(N.Name, Hit) then
        begin
          Key := IntToStr(N.Line) + '|' + LowerCase(Hit);
          if not Seen.ContainsKey(Key) then
          begin
            Seen.Add(Key, True);
            Report(Hit, N.Name, N.Line);
          end;
        end;
      end;
    finally
      Calls.Free;
    end;
  finally
    Seen.Free;
  end;
end;

class procedure TInsecureCryptoAlgorithmDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
begin
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(M, FileName, Results);
  finally
    Methods.Free;
  end;
end;

end.
