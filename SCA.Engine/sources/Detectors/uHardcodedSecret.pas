unit uHardcodedSecret;

// AST-basierter Detektor für hartcodierte Passwörter/Tokens (Sonar-Regel #5).
//
// Erkennt nkAssign-Knoten bei denen:
//   – der Variablenname ein sicherheitskritisches Schlüsselwort enthält
//     (password, token, secret, apikey, …)
//   – der zugewiesene Wert ein reines Stringliteral ist
//     (TypeRef beginnt mit ' und enthält kein '+'-Operator)
//
// Beispiele:
//   FPassword     := 'Xk9#pQz7Lm'       → Fehler
//   ApiToken      := 'sk-abc...'        → Fehler
//   ConnString    := 'Server=…;Pwd=x'  → Fehler
//   FPassword     := GetPassword()      → kein Befund (Funktionsaufruf)
//   FPassword     := FStoredPwd         → kein Befund (Variable)
//   FPassword     := 'changeme'         → kein Befund (Dummy-Beispielwert)
//   StartToken    := '{{'               → kein Befund (kein plausibler Wert)

interface

uses
  System.SysUtils, System.Generics.Collections,
  System.RegularExpressions,
  uAstNode, uSCAConsts, uMethodd12;

type
  THardcodedSecretDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
    class procedure AnalyzeMethod(MethodNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    class function IsSecretName(const Name: string): Boolean; static;
    class function IsStringLiteral(const TypeRef: string): Boolean; static;
    class function ConnectionStringHasPassword(const Literal: string): Boolean; static;
    // True wenn das LHS auf eine reine UI-Text-Property zeigt (Caption,
    // Hint, Title, ...). Solche Properties sind per Konvention beschreibende
    // Labels und tragen keine Credentials - 'Bearer Token:' an einer Label-
    // Caption ist ein Hinweis fuer das daneben liegende Eingabefeld, kein
    // hardcodiertes Secret. Match auf den LETZTEN Punkt-Segment, damit
    // 'Form1.lblToken.Caption' genauso gefiltert wird wie 'lblToken.Caption'.
    class function IsUITextProperty(const Name: string): Boolean; static;
    // True wenn das LHS-Segment ein META-Feld zum Secret ist statt das
    // Secret selbst - das Literal beschreibt eine HERKUNFT, REFERENZ,
    // ANZEIGE-EIGENSCHAFT, NAME etc., NICHT den Geheimwert.
    // Beispiele die diese Funktion zu False-Positives macht:
    //   Cfg.SourceToken      := 'env SONAR_TOKEN'   (Quell-Label)
    //   edToken.PasswordChar := '*'                 (VCL-Masken-Char)
    //   AuthHeader.TokenRef  := 'X-Auth-Token'      (Header-Name)
    // Pattern: das Secret-Keyword ist ein TEIL des Identifier-Namens,
    // entweder mit Meta-Prefix (Source/Stored/Cached) oder Meta-Suffix
    // (Char/Ref/Name/Length/Size/Mask/Header/Label/Caption/Hash).
    class function IsSecretMetaField(const Name: string): Boolean; static;
    // FP-Reduktion 2026-06-18 (Audit_ErrorDetectors E-2): erkennt Test-
    // Files anhand des Pfads (tests/, /utest, *test.pas etc.). Tests
    // enthalten per Definition keine produktiven Secrets - Mock-Tokens,
    // Fixture-Passwoerter etc. werden hier nicht geflaggt.
    class function IsTestFilePath(const AFileName: string): Boolean; static;
    // 2026-06-18 (Audit_ErrorDetectors E-2 P2): Pattern-Match auf
    // String-Inhalt. Findet Secrets unabhaengig vom Variablen-Namen -
    // 'FCfg := ''sk-prod-...''' wird erkannt obwohl FCfg kein Secret-
    // Keyword im Namen hat.
    //
    // Patterns sind so spezifisch dass Confidence = fcHigh angemessen:
    //   * AWS Access Key:   AKIA[0-9A-Z]{16}
    //   * GitHub PAT:       ghp_[A-Za-z0-9]{36}
    //   * GitHub fine-grained: github_pat_[A-Z]_[A-Za-z0-9]{82}
    //   * OpenAI Key:       sk-[A-Za-z0-9]{48} (auch sk-proj- / sk-org-)
    //   * JWT (3-Segment):  eyJ[A-Za-z0-9+/=_-]{10,}\.eyJ[A-Za-z0-9+/=_-]{10,}\.
    //   * Slack Bot/User:   xox[bps]-[A-Za-z0-9-]{20,}
    //   * Google API:       AIza[0-9A-Za-z_-]{35}
    //
    // True wenn StrLit eines der Patterns matched. AKind enthaelt einen
    // sprechenden Namen ('AWS Access Key' etc.) fuer die Finding-Message.
    class function IsKnownSecretPattern(const StrLit: string;
      out AKind: string): Boolean; static;
    // Snake-Upper-Const-Naming: nur Uppercase + Underscore + Digits.
    // Matched 'JWT_SECRET_HEADER', 'X_TOKEN', 'API_KEY', 'TOKEN_REF_DEFAULT' -
    // das sind in der Praxis Algorithmus-/Protokoll-Marker (JWT, REST-
    // Header, mORMot-Konstanten) oder Config-Sentinels, KEINE Secret-Werte.
    // 2026-06-19: Aus AnalyzeMethod (nested function) zu class-static
    // gezogen, damit ScanFieldsForSecrets denselben Filter anwenden kann -
    // Const-Sections triggerten sonst FPs auf z.B. `const TOKEN_REF =
    // 'ide-default';`.
    class function IsConstantNamingStyle(const FullName: string): Boolean; static;
    // FP-Gates (2026-07-04, Audit_RealWorldBugs Sektion 3.5 - 14 FP / 0 TP
    // auf dem 25-Repo-Korpus):
    // ExtractLiteralBody schaelt den Inhalt aus der Source-Form '...'
    // (QuoteStrLit-Format inkl. verdoppelter innerer Quotes). Bounds-safe;
    // liefert bei Nicht-Quote-Form den Eingabestring unveraendert zurueck.
    class function ExtractLiteralBody(const Literal: string): string; static;
    // FP-Gate (2026-07-04): template-delimiter / nul-char-init /
    // sentinel-value - Wert-Plausibilitaet. Ein plausibler Secret-Wert hat
    // einen Kern von >= 4 Zeichen und mindestens 3 alphanumerische Zeichen.
    // Killt '{{' / '}}' (Sempare-Template-Delimiter), #0 (Puffer-/Lexer-
    // Token-Reset, z.B. doublecmd fpsnumformat FToken := #0) und '#'
    // (mORMot SCRAM-Status-Sentinel in PasswordHashHexa).
    class function IsPlausibleSecretValue(const Literal: string): Boolean; static;
    // FP-Gate (2026-07-04): test-fixture - bekannte Dummy-/Beispielwerte
    // (case-insensitive, Trailing-Digits werden abgestreift: 'pass1' ->
    // 'pass'). Killt dokumentierte Demo-Credentials wie 'masterkey'
    // (Firebird-Default in mORMot extdb-bench), 'password', 'pass1'/'pass2'
    // (Demo-User in ThirdPartyDemos) und rein numerische PIN-Platzhalter
    // ('1234'). Echte Secrets sind praktisch nie woertlich 'pass'.
    class function IsDummySecretValue(const Literal: string): Boolean; static;
    // FP-Gate (Real-World-FP-Audit 2026-07-10): Wert-FORM statt LHS-Name.
    // Der Detektor keyed auf dem Identifier-Namen und flaggt jeden String -
    // aber viele Werte sind offensichtlich KEINE Secrets: URLs, Registry-/
    // Datei-Pfade, GUIDs, Format-Templates, Prompt-Labels und identifier-
    // artige Config-/Header-/Spalten-Namen. Liefert True (= unterdruecken)
    // fuer solche Wert-Formen. Bewusst FP-avers: ein zufaellig aussehendes
    // Secret ('Xk9#pQz7Lm') oder ein PEM-/SSH-Key matcht KEINE dieser Formen
    // und bleibt meldepflichtig (harte Secret-Marker werden vorab freigestellt).
    class function IsNonSecretValueShape(const Literal, LhsName: string): Boolean; static;
    // Hilfs-Praedikat zu IsNonSecretValueShape: Wert ist ein einzelnes
    // Identifier-Token (^[A-Za-z_][A-Za-z0-9_]*$, keine Spaces/Sonderzeichen).
    class function IsIdentifierLikeToken(const S: string): Boolean; static;
  end;

implementation

// noinspection-file BeginEndRequired, CanBeClassMethod, ConsecutiveSection, CyclomaticComplexity, GroupedDeclaration, RedundantJump, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

const
  SECRET_KW: array[0..11] of string = (
    'password', 'passwd', 'passwort',
    'pwd',                                  // gaengige Abkuerzung
    'secret',   'token',  'apikey',
    'api_key',  'privatekey', 'private_key',
    'connectionstring', 'credentials'
  );

class function THardcodedSecretDetector.IsSecretName(const Name: string): Boolean;
// Match an WORTGRENZEN beidseitig - sonst False-Positives:
//   * 'secretary' (links Boundary '-1', rechts 'a' = ident -> KEIN Match)
//   * 'tokenize'  (links Boundary '-1', rechts 'i' = ident -> KEIN Match)
//   * 'passwordless' wuerde noch matchen (rechts 'l' ist ident, linker
//     ist Anfang). Aber 'passwordless' ist semantisch trotzdem secret-
//     bezogen (Auth-Kontext) - akzeptabel.
//
// Erlaubte Linksseite (Match-Beginn):
//   - Anfang des Identifiers ('password', 'token')
//   - CamelCase-Boundary ('FPassword' - Match startet bei grossem 'P')
//   - Snake-Case-Boundary ('user_token' - Match nach '_')
//
// Erlaubte Rechtsseite (Match-Ende):
//   - Ende des Identifiers ('password', 'fpassword', 'user_token')
//   - CamelCase-Boundary ('PasswordHash' - 'H' nach 'd')
//   - Snake-Case-Boundary ('password_hash' - '_' nach 'd')
var
  NameLow    : string;
  Kw         : string;
  p, pRight  : Integer;
  LeftOK, RightOK : Boolean;
begin
  NameLow := Name.ToLower;
  for Kw in SECRET_KW do
  begin
    p := Pos(Kw, NameLow);
    if p = 0 then Continue;

    // LEFT boundary
    LeftOK :=
      (p = 1) or                                     // Identifier-Anfang
      (Name[p - 1] = '_') or                         // nach Underscore
      (CharInSet(Name[p], ['A'..'Z'])) or            // CamelCase
      (not CharInSet(Name[p - 1],                    // sonstige Nicht-Buchstaben
                     ['A'..'Z', 'a'..'z', '0'..'9']));
    if not LeftOK then Continue;

    // RIGHT boundary - Position direkt nach dem Match.
    pRight := p + Length(Kw);
    RightOK :=
      (pRight > Length(Name)) or                     // Identifier-Ende
      (Name[pRight] = '_') or                        // vor Underscore
      (CharInSet(Name[pRight], ['A'..'Z'])) or       // CamelCase-Beginn
      (not CharInSet(Name[pRight],                   // Nicht-Buchstaben
                     ['A'..'Z', 'a'..'z', '0'..'9']));
    if RightOK then Exit(True);
  end;
  Result := False;
end;

class function THardcodedSecretDetector.IsStringLiteral(const TypeRef: string): Boolean;
begin
  // Der Parser speichert Stringliterale mit umschließenden Quotes: 'wert'
  // Eine reine Literal-Zuweisung beginnt mit ' und enthält kein '+' (keine Konkatenation)
  Result := (Length(TypeRef) >= 2) and
            (TypeRef[1] = '''') and
            (Pos('+', TypeRef) = 0);
end;

class function THardcodedSecretDetector.ConnectionStringHasPassword(
  const Literal: string): Boolean;
var
  Low: string;
begin
  Low := Literal.ToLower;
  Result := (Pos('password=', Low) > 0) or (Pos('pwd=', Low) > 0) or
            (Pos('passwd=', Low) > 0);
end;

class function THardcodedSecretDetector.IsSecretMetaField(const Name: string): Boolean;
// Filtert LHS-Namen die zu einem META-Feld eines Secrets gehoeren statt zum
// Secret selbst. Heuristik: das letzte Punkt-Segment des qualifizierten
// Namens wird untersucht.
//
// META-PREFIX (vor dem Secret-Keyword):
//   Source, Stored, Cached, Initial, Default, Sample, Example, Last, Old
//   z.B. 'SourceToken' = 'Source' + 'Token' -> Quell-Label
//
// META-SUFFIX (nach dem Secret-Keyword):
//   Char, Ref, Name, Length, Size, Mask, Header, Label, Caption, Hash,
//   Field, Column, Url, Path
//   z.B. 'PasswordChar' = 'Password' + 'Char' -> VCL-Masken-Char
//        'TokenRef'     = 'Token'    + 'Ref'  -> Header-Name
//        'PasswordHash' = 'Password' + 'Hash' -> Hash-Wert, nicht Klartext
//
// Implementierung: matche das LETZTE Punkt-Segment komplett gegen
// "[Prefix]Keyword[Suffix]" mit Keyword aus SECRET_KW (case-insensitive).
const
  META_PREFIX: array[0..8] of string = (
    'source', 'stored', 'cached', 'initial',
    'default', 'sample', 'example', 'last', 'old'
  );
  META_SUFFIX: array[0..13] of string = (
    'char', 'ref', 'name', 'length', 'size', 'mask',
    'header', 'label', 'caption', 'hash', 'field',
    'column', 'url', 'path'
  );
var
  Bare, BareLow : string;
  DotPos        : Integer;
  Kw, Pre, Suf  : string;
  P             : Integer;
  Mid, MidLow   : string;
begin
  Result := False;
  Bare := Name;
  DotPos := -1;
  for var i := Length(Bare) downto 1 do
    if Bare[i] = '.' then begin DotPos := i; Break; end;
  if DotPos > 0 then Bare := Copy(Bare, DotPos + 1, MaxInt);
  if Bare = '' then Exit;
  BareLow := Bare.ToLower;

  for Kw in SECRET_KW do
  begin
    P := Pos(Kw, BareLow);
    if P = 0 then Continue;
    // Mid = der Teil VOR dem Keyword, MidLow = nach dem Keyword
    Mid := LowerCase(Copy(BareLow, 1, P - 1));               // Prefix-Kandidat
    MidLow := Copy(BareLow, P + Length(Kw), MaxInt);          // Suffix-Kandidat
    for Pre in META_PREFIX do
      if Mid = Pre then Exit(True);                           // PrefixKeyword
    for Suf in META_SUFFIX do
      if MidLow = Suf then Exit(True);                        // KeywordSuffix
  end;
end;

class function THardcodedSecretDetector.IsUITextProperty(const Name: string): Boolean;
// UI-Text-Properties tragen per Konvention beschreibende Labels, keine
// Credentials. Beispiel-False-Positive das diese Funktion verhindert:
//   lblToken.Caption := 'Bearer Token:';   (UI-Label fuer ein PasswordChar-Edit)
// Match auf das letzte Punkt-Segment des qualifizierten Namens.
const
  UI_PROPS: array[0..6] of string = (
    'caption', 'hint', 'texthint', 'title',
    'groupcaption',                     // TFrame.GroupCaption
    'displaylabel',                     // TField.DisplayLabel
    'showtext'                          // diverse Component-Props
  );
var
  Bare, P : string;
  DotPos  : Integer;
begin
  Result := False;
  Bare := Name;
  DotPos := -1;
  for var i := Length(Bare) downto 1 do
    if Bare[i] = '.' then begin DotPos := i; Break; end;
  if DotPos > 0 then Bare := Copy(Bare, DotPos + 1, MaxInt);
  Bare := Bare.ToLower;
  for P in UI_PROPS do
    if Bare = P then Exit(True);
end;

class function THardcodedSecretDetector.IsConstantNamingStyle(
  const FullName: string): Boolean;
// Letztes Segment nach Punkt-Qualifier (Self.FOO -> FOO). True wenn das
// Resultat ausschliesslich Uppercase + Underscore + Digits enthaelt UND
// mindestens ein Underscore vorhanden ist. Damit greift es bei
// 'TOKEN_REF_DEFAULT', 'JWT_SECRET_HEADER', 'X_TOKEN' - aber NICHT bei
// 'FToken' oder 'apiKey'.
var
  Bare : string;
  DotPos : Integer;
  HasUnderscore : Boolean;
  AllUpperOrDigit : Boolean;
  C : Char;
begin
  Result := False;
  Bare := FullName;
  DotPos := -1;
  for var i := Length(Bare) downto 1 do
    if Bare[i] = '.' then begin DotPos := i; Break; end;
  if DotPos > 0 then Bare := Copy(Bare, DotPos + 1, MaxInt);
  if Bare = '' then Exit;

  HasUnderscore := False;
  AllUpperOrDigit := True;
  for C in Bare do
  begin
    if C = '_' then HasUnderscore := True
    else if CharInSet(C, ['A'..'Z', '0'..'9']) then  // OK
    else
    begin
      AllUpperOrDigit := False;
      Break;
    end;
  end;
  Result := HasUnderscore and AllUpperOrDigit;
end;

const
  // FP-Gate (2026-07-04): test-fixture (Audit_RealWorldBugs 3.5) -
  // typische Beispiel-/Platzhalterwerte aus Demos, Benchmarks, Doku und
  // Tutorials. Match case-insensitive auf den kompletten Literal-Body,
  // zusaetzlich mit abgestreiften Trailing-Digits (pass1/pass2 -> pass,
  // test123 -> test). Bewusst NUR Komplett-Match, kein Substring -
  // 'realsecret' oder 'my-secret-key' bleiben meldepflichtig.
  DUMMY_SECRET_VALUES: array[0..47] of string = (
    'changeme', 'change_me', 'changeit',
    'password', 'passwort',  'passwd',  'pass', 'pwd', 'kennwort',
    'secret',   'geheim',    'geheimnis',
    'test',     'testing',   'demo',    'example', 'sample',
    'dummy',    'fake',      'mock',    'placeholder',
    'default',  'none',      'empty',   'unknown', 'undefined',
    'foo',      'bar',       'foobar',  'baz',
    'xxx',      'xxxx',      'xxxxx',
    'abc',      'abcd',      'abcde',
    'admin',    'administrator', 'root', 'guest', 'user',
    'letmein',  'qwerty',    'qwertz',  'asdf',
    'masterkey',                          // Firebird-Default (SYSDBA)
    'sesam',    'sesame'
  );

class function THardcodedSecretDetector.ExtractLiteralBody(
  const Literal: string): string;
// Schaelt den Inhalt aus der Parser-Source-Form eines Stringliterals:
// umschliessende ' ' entfernen, QuoteStrLit-verdoppelte innere Quotes
// wieder auf einfach reduzieren. Nicht-Quote-Formen (z.B. bereits
// getrimmte Werte) werden unveraendert durchgereicht.
begin
  Result := Literal;
  if (Length(Result) >= 2) and (Result[1] = '''') and
     (Result[Length(Result)] = '''') then
    Result := Copy(Result, 2, Length(Result) - 2)
  else if (Length(Result) >= 1) and (Result[1] = '''') then
    Result := Copy(Result, 2, MaxInt);
  Result := StringReplace(Result, '''''', '''', [rfReplaceAll]);
end;

class function THardcodedSecretDetector.IsPlausibleSecretValue(
  const Literal: string): Boolean;
// FP-Gate (2026-07-04): template-delimiter / nul-char-init / sentinel-value.
// Plausibel = Body >= 4 Zeichen UND >= 3 alphanumerische Zeichen (ASCII).
// Reine Sonderzeichen-/Steuerzeichen-Werte ('{{', '}}', '#', #0, '****')
// sind Delimiter, Sentinels oder Masken - keine Secrets. Jeder realistische
// Credential-Wert (Passwoerter, API-Keys, PEM-Header) erfuellt beide
// Kriterien locker.
var
  Body  : string;
  C     : Char;
  Alnum : Integer;
begin
  Body := ExtractLiteralBody(Literal);
  if Length(Body) < 4 then Exit(False);
  Alnum := 0;
  for C in Body do
    if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9']) then
    begin
      Inc(Alnum);
      if Alnum >= 3 then Exit(True);
    end;
  Result := False;
end;

class function THardcodedSecretDetector.IsDummySecretValue(
  const Literal: string): Boolean;
// FP-Gate (2026-07-04): test-fixture. Komplett-Match (case-insensitive)
// gegen DUMMY_SECRET_VALUES, einmal roh und einmal mit abgestreiften
// Trailing-Digits ('pass1' -> 'pass').
// Refinement (2026-07-04, Code-Review): (a) Trailing-Digit-Strip auf HOECHSTENS
// 2 Ziffern begrenzt, damit echte Credentials mit eingebetteten Zahlenfolgen
// ('admin2024' -> 'admin20', kein Dummy) nicht faelschlich unterdrueckt werden;
// (b) reine Ziffernwerte gelten nur bis Laenge 6 als PIN-Platzhalter ('1234'),
// laengere Ziffernfolgen koennen echte numerische Tokens/Passwoerter sein.
var
  Body, Stem : string;
  D          : string;
  i, Stripped: Integer;
  AllDigits  : Boolean;
begin
  Result := False;
  Body := LowerCase(Trim(ExtractLiteralBody(Literal)));
  if Body = '' then Exit;

  AllDigits := True;
  for i := 1 to Length(Body) do
    if not CharInSet(Body[i], ['0'..'9']) then
    begin
      AllDigits := False;
      Break;
    end;
  if AllDigits then
    Exit(Length(Body) <= 6);   // nur kurze reine Ziffern -> Platzhalter-PIN

  i := Length(Body);
  Stripped := 0;
  while (i >= 1) and (Stripped < 2) and CharInSet(Body[i], ['0'..'9']) do
  begin
    Dec(i);
    Inc(Stripped);
  end;
  Stem := Copy(Body, 1, i);

  for D in DUMMY_SECRET_VALUES do
    if (Body = D) or (Stem = D) then Exit(True);
end;

class function THardcodedSecretDetector.IsIdentifierLikeToken(
  const S: string): Boolean;
var
  i : Integer;
begin
  Result := False;
  if S = '' then Exit;
  if not CharInSet(S[1], ['A'..'Z', 'a'..'z', '_']) then Exit;
  for i := 2 to Length(S) do
    if not CharInSet(S[i], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then Exit;
  Result := True;
end;

class function THardcodedSecretDetector.IsNonSecretValueShape(
  const Literal, LhsName: string): Boolean;
// Real-World-FP-Audit 2026-07-10: Der Detektor triggert auf dem LHS-Namen
// (Password/Token/Key/...) und flaggt den zugewiesenen String ungeprueft.
// Diese Funktion prueft die WERT-Form: URL/Pfad (://, \), Format-Template
// (%s, =%), GUID, Prompt-Label (endet auf ':') und identifier-artige
// Config-/Header-/Spalten-Namen werden als Nicht-Secret unterdrueckt.
// Harte Secret-Marker (PEM-Bloecke, SSH-Keys) werden vorab freigestellt,
// damit eingebettete Service-Account-Keys (JSON mit '\n' + 'https://'-
// token_uri) NICHT faelschlich als Pfad/URL durchrutschen.
const
  KEY_SUFFIX: array[0..10] of string = (
    '_string', '_field', '_column', '_col', '_expr',
    '_name', '_type', '_id', '_ref', '_url', '_path'
  );
var
  Body, BodyTrim, BodyLow, LhsLow, Suf : string;
begin
  Result := True;   // optimistisch; am Ende False, wenn keine Form greift
  Body := ExtractLiteralBody(Literal);
  BodyTrim := Trim(Body);
  if BodyTrim = '' then Exit(False);
  BodyLow := Body.ToLower;

  // Harte Secret-Marker - NIEMALS unterdruecken (PEM/SSH-Keys). Schuetzt
  // eingebettete RSA-/Service-Account-Keys, die als JSON mit '\n' und
  // 'https://'-token_uri auftreten und sonst als Pfad/URL gelten wuerden.
  if (Pos('-----begin', BodyLow) > 0) or (Pos('private key', BodyLow) > 0) or
     (Pos('ssh-rsa', BodyLow) > 0) or (Pos('ssh-ed25519', BodyLow) > 0) then
    Exit(False);

  // (a) URL-Endpoint bzw. Registry-/Datei-Pfad - kein Geheimwert.
  //     'https://oauth2.googleapis.com/token', 'Software\Policies\...'
  if (Pos('://', Body) > 0) or (Pos('\', Body) > 0) then Exit;

  // (b) Format-Template mit Platzhalter - z.B. OAuth-Request-Body
  //     '...&assertion=%s'. Vorlagen, keine literalen Secrets.
  if (Pos('%s', Body) > 0) or (Pos('%d', Body) > 0) or
     (Pos('%u', Body) > 0) or (Pos('%g', Body) > 0) or
     (Pos('%x', Body) > 0) or (Pos('=%', Body) > 0) then Exit;

  // (c) GUID/IID-Literal (COM-Interface-Konstante) - kein Secret.
  if TRegEx.IsMatch(BodyTrim,
       '^\{?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}?$') then Exit;

  // (d) Prompt-/Feld-Label endet auf ':' - Protokoll-/UI-Beschriftung.
  //     'AskP: ', 'Hotkey: '. Echte Secrets enden praktisch nie auf ':'.
  if BodyTrim.EndsWith(':') then Exit;

  // (e) Identifier-artiger Wert = Config-Key / Header- / Spalten-Name,
  //     NICHT der Geheimwert. Nur unterdruecken, wenn der Wert zusaetzlich
  //     (i) selbst ein Secret-Keyword traegt ('UsePassword',
  //     'CurrentTokenHighlight'), ODER (ii) den LHS-Namen spiegelt
  //     ('challengePassword' in 'LN_pkcs9_challengePassword'), ODER (iii)
  //     auf einem Namens-/Spalten-Suffix endet ('authentication_string').
  //     Ein zufaelliges Secret ('Xk9pQz7Lm') erfuellt keine der drei
  //     Bedingungen und bleibt damit meldepflichtig.
  if IsIdentifierLikeToken(BodyTrim) then
  begin
    BodyLow := BodyTrim.ToLower;
    // (i) NUR fuer CamelCase-Config-/Property-Identifier (UsePassword,
    // challengePassword, CurrentTokenHighlight) - ein interior-Grossbuchstabe
    // kennzeichnet den Config-Namen. snake_case-Platzhalter-Secrets
    // (pw_secret, ak_secret, tk_secret) haben KEINEN interior-Cap und bleiben
    // meldepflichtig (Fix Test-Regression Secret_MultipleHits, 2026-07-11).
    var HasInteriorCap := False;
    for var Ci := 2 to Length(BodyTrim) do
      if CharInSet(BodyTrim[Ci], ['A'..'Z']) then
      begin HasInteriorCap := True; Break; end;
    if IsSecretName(BodyTrim) and HasInteriorCap then Exit;             // (i)
    LhsLow := LhsName.ToLower;
    if (Length(BodyTrim) >= 4) and (Pos(BodyLow, LhsLow) > 0) then Exit; // (ii)
    for Suf in KEY_SUFFIX do                                            // (iii)
      if BodyLow.EndsWith(Suf) then Exit;
  end;

  Result := False;
end;

class procedure THardcodedSecretDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
const
  MAX_VAL_LEN = 20;
var
  Assigns  : TList<TAstNode>;
  A        : TAstNode;
  F        : TLeakFinding;
  LitShort : string;
  PatKind  : string;
begin
  Assigns := MethodNode.FindAll(nkAssign);
  try
    for A in Assigns do
    begin
      // Pattern-Match-Pfad: Inhalt sieht aus wie AWS/GitHub/JWT/OpenAI...
      // Unabhaengig vom Variablen-Namen. Confidence fcHigh weil die
      // Patterns sehr spezifisch sind (Mindestlaenge + Prefix + Charset).
      if IsStringLiteral(A.TypeRef) and
         IsKnownSecretPattern(A.TypeRef, PatKind) then
      begin
        if Length(A.TypeRef) > MAX_VAL_LEN then
          LitShort := Copy(A.TypeRef, 1, MAX_VAL_LEN - 4) + '...'''
        else
          LitShort := A.TypeRef;
        Results.Add(TLeakFinding.New(FileName, MethodNode.Name, A.Line,
          PatKind + ' detected in literal: ' + A.Name + ' = ' + LitShort,
          fkHardcodedSecret, fcHigh));
        Continue;   // Name-basierter Pfad wuerde Doppel-Finding produzieren
      end;

      if not IsSecretName(A.Name)       then Continue;
      if not IsStringLiteral(A.TypeRef) then Continue;
      // Leeres Literal '' ist Initialisierung, kein hartcodiertes Secret.
      if A.TypeRef = '''''' then Continue;
      // Const-Naming-Style (UPPER_SNAKE) -> Algorithmus-Marker, kein Secret.
      // Beispiele: JWT_SECRET_HEADER, X_TOKEN, API_KEY_PREFIX.
      if IsConstantNamingStyle(A.Name) then Continue;
      // UI-Text-Property (Caption/Hint/Title/...) -> beschreibendes Label,
      // kein Credential-Wert. Filter fuer 'lblToken.Caption := ''Bearer Token:'''
      // und aehnliche UI-Pattern.
      if IsUITextProperty(A.Name) then Continue;
      // META-Feld (SourceToken, PasswordChar, TokenRef, PasswordHash, ...)
      // -> beschreibt HERKUNFT / REFERENZ / DARSTELLUNG eines Secrets,
      // nicht den Geheimwert selbst. Filter fuer
      //   Cfg.SourceToken      := 'env SONAR_TOKEN'
      //   edToken.PasswordChar := '*'
      if IsSecretMetaField(A.Name) then Continue;
      // FP-Gate (2026-07-04): template-delimiter / nul-char-init /
      // sentinel-value (Audit_RealWorldBugs 3.5) - Werte wie '{{', '}}',
      // '#' oder #0 sind Template-Delimiter, Status-Sentinels oder
      // Puffer-Terminierung, keine Secrets.
      if not IsPlausibleSecretValue(A.TypeRef) then Continue;
      // FP-Gate (2026-07-04): test-fixture (Audit_RealWorldBugs 3.5) -
      // dokumentierte Demo-/Platzhalterwerte ('masterkey', 'password',
      // 'pass1', ...) sind Beispiel-Credentials, keine echten Secrets.
      if IsDummySecretValue(A.TypeRef) then Continue;
      // FP-Gate (Real-World-FP-Audit 2026-07-10): Wert-FORM ist offensichtlich
      // kein Secret - URL/Pfad (://, \), Format-Template (%s), GUID, Label
      // (endet ':') oder identifier-artiger Config-/Header-/Spalten-Name.
      if IsNonSecretValueShape(A.TypeRef, A.Name) then Continue;
      // ConnectionString ohne Passwort-Anteil ist ein Template, kein Secret.
      if (Pos('connectionstring', A.Name.ToLower) > 0) and
         not ConnectionStringHasPassword(A.TypeRef) then Continue;

      // Literal-Wert auf MAX_VAL_LEN Zeichen kürzen
      if Length(A.TypeRef) > MAX_VAL_LEN then
        LitShort := Copy(A.TypeRef, 1, MAX_VAL_LEN - 4) + '...'''
      else
        LitShort := A.TypeRef;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := MethodNode.Name;
      F.LineNumber := IntToStr(A.Line);
      F.MissingVar := A.Name + ' = ' + LitShort;
      F.SetKind(fkHardcodedSecret);
      Results.Add(F);
    end;
  finally
    Assigns.Free;
  end;
end;

class function THardcodedSecretDetector.IsKnownSecretPattern(
  const StrLit: string; out AKind: string): Boolean;
// Lazy-Compile mit static-Local-Pattern - in einem Hot-Path waere ein
// Cache angebracht; hier wird die Func nur in der AnalyzeMethod-Schleife
// pro nkAssign gerufen, also vermutlich nicht hot genug fuer Premature-Opt.
// Regex-Compile bei jedem Aufruf akzeptabel weil die Pattern simpel sind.
//
// StrLit ist der Roh-RHS aus N.TypeRef, inklusive umschliessender ' '.
// Wir trimmen sie hier ein und matchen gegen den Body.
const
  // Mindestens 16 chars um Trivial-Strings ('test', 'abc') auszufiltern.
  MIN_SECRET_LEN = 16;
var
  Body : string;
  i, n : Integer;
begin
  Result := False;
  AKind  := '';
  if Length(StrLit) < MIN_SECRET_LEN + 2 then Exit;  // +2 fuer ' '
  // Body = Inhalt zwischen erstem und letztem ' Token. Vereinfacht: wenn
  // beginnt mit ' und endet mit ' -> Substring.
  if (StrLit[1] <> '''') or (StrLit[Length(StrLit)] <> '''') then Exit;
  Body := Copy(StrLit, 2, Length(StrLit) - 2);
  if Length(Body) < MIN_SECRET_LEN then Exit;
  // '' (Doppel-Quote als Escape) wuerde im Match meist nicht vorkommen
  // weil Secret-Tokens reine [A-Za-z0-9+/=_.-]-Sets sind. Defensive
  // Replacement nicht noetig.

  // AWS Access Key (always starts AKIA, 20 chars total)
  if TRegEx.IsMatch(Body, '^AKIA[0-9A-Z]{16}$') then
  begin AKind := 'AWS Access Key'; Exit(True); end;
  // GitHub Personal Access Token (classic, 40 chars)
  if TRegEx.IsMatch(Body, '^ghp_[A-Za-z0-9]{36}$') then
  begin AKind := 'GitHub Personal Access Token'; Exit(True); end;
  // GitHub fine-grained PAT
  if TRegEx.IsMatch(Body, '^github_pat_[A-Z0-9]{22}_[A-Za-z0-9_]{59,}$') then
  begin AKind := 'GitHub fine-grained Token'; Exit(True); end;
  // OpenAI API Key (sk-, sk-proj-, sk-org-)
  if TRegEx.IsMatch(Body,
       '^sk-(proj-|org-|svcacct-)?[A-Za-z0-9_-]{20,}$') then
  begin AKind := 'OpenAI API Key'; Exit(True); end;
  // Google API Key (AIza prefix, 39 chars total)
  if TRegEx.IsMatch(Body, '^AIza[0-9A-Za-z_-]{35}$') then
  begin AKind := 'Google API Key'; Exit(True); end;
  // Slack Bot/User/Workspace Token (xoxb-, xoxp-, xoxs-)
  if TRegEx.IsMatch(Body, '^xox[bps]-[A-Za-z0-9-]{20,}$') then
  begin AKind := 'Slack Token'; Exit(True); end;
  // JWT (3 Base64URL-segments getrennt durch Punkt; Header beginnt eyJ
  // weil { -> base64 = eyJ). Auch ohne Signatur-Segment akzeptiert
  // (manche use Cases haben 2-Segment-JWT).
  n := 0;
  for i := 1 to Length(Body) do if Body[i] = '.' then Inc(n);
  if (n in [1, 2]) and Body.StartsWith('eyJ') and
     TRegEx.IsMatch(Body, '^eyJ[A-Za-z0-9+/=_-]{10,}\.eyJ[A-Za-z0-9+/=_-]{10,}') then
  begin AKind := 'JWT Token'; Exit(True); end;
end;

class function THardcodedSecretDetector.IsTestFilePath(
  const AFileName: string): Boolean;
// Erkennt Test-Files anhand des Pfads. Convention-based:
//   tests/ test/ spec/ fixtures/ im Pfad
//   uTestXxx.pas / *test.pas / *tests.pas / *spec.pas Dateinamen
// FP-Reduktion (Audit_ErrorDetectors E-2): Mock-Secrets in Tests
// sind keine echten Secrets, sollen nicht geflaggt werden.
var
  Norm : string;
begin
  Norm := LowerCase(StringReplace(AFileName, '\', '/', [rfReplaceAll]));
  Result :=
    (Pos('/tests/',    Norm) > 0) or
    (Pos('/test/',     Norm) > 0) or
    (Pos('/spec/',     Norm) > 0) or
    (Pos('/fixtures/', Norm) > 0) or
    (Pos('/utest',     Norm) > 0) or    // uTestXxx.pas Konvention
    Norm.EndsWith('test.pas') or
    Norm.EndsWith('tests.pas') or
    Norm.EndsWith('spec.pas');
end;

// 2026-06-18 (Audit_ErrorDetectors E-2 Premium): nkField-Pass fuer
// Const-Sections und Class-Field-Initializer.
// uParser2 modelliert beides als nkField mit TypeRef-Format:
//   'Type=value'    (typisierte const oder field-init)
//   '=value'        (untypisierte const)
// Beispiele:
//   const DEFAULT_API_KEY = 'sk-prod-xxx';
//     -> nkField Name='DEFAULT_API_KEY' TypeRef='='sk-prod-xxx''
//   FFooKey: string = 'sk-prod-xxx';   (Class-Field-Init)
//     -> nkField Name='FFooKey' TypeRef='string='sk-prod-xxx''
// Wir extrahieren den Literal-Teil nach '=' und pruefen mit den
// gleichen Heuristiken wie AnalyzeMethod (Name-basiert + Pattern-Match).
procedure ScanFieldsForSecrets(Root: TAstNode; const FileName: string;
  Results: TObjectList<TLeakFinding>);
var
  Fields  : TList<TAstNode>;
  N       : TAstNode;
  TypeRef : string;
  EqPos   : Integer;
  Literal : string;
  PatKind : string;
  LitShort: string;
const
  MAX_VAL_LEN = 60;
begin
  Fields := Root.FindAll(nkField);
  try
    for N in Fields do
    begin
      TypeRef := N.TypeRef;
      EqPos := Pos('=', TypeRef);
      if EqPos < 1 then Continue;   // keine Initialisierung
      Literal := Trim(Copy(TypeRef, EqPos + 1, MaxInt));

      // Pattern-Match-Pfad: Wert sieht aus wie AWS/GitHub/JWT/OpenAI.
      // Unabhaengig vom Field-Namen. Confidence fcHigh.
      if THardcodedSecretDetector.IsKnownSecretPattern(Literal, PatKind) then
      begin
        if Length(Literal) > MAX_VAL_LEN then
          LitShort := Copy(Literal, 1, MAX_VAL_LEN - 4) + '...'''
        else
          LitShort := Literal;
        Results.Add(TLeakFinding.New(FileName, '', N.Line,
          PatKind + ' detected in const/field literal: ' + N.Name + ' = ' + LitShort,
          fkHardcodedSecret, fcHigh));
        Continue;
      end;

      // Name-basierter Pfad (analog AnalyzeMethod).
      if not THardcodedSecretDetector.IsSecretName(N.Name) then Continue;
      // Untypisierte Const: Literal muss String-Form haben (' Quote-prefix).
      if Literal = '' then Continue;
      if Literal[1] <> '''' then Continue;   // nicht-String-Initializer
      // Leere String-Init
      if Literal = '''''' then Continue;
      // Const-Naming-Style (UPPER_SNAKE) -> Algorithmus-Marker / Sentinel,
      // kein Secret. 2026-06-19: vorher nicht in diesem Pfad - dadurch FPs
      // auf z.B. `const TOKEN_REF_DEFAULT = 'ide-default';` in der
      // Sonar-Options-Page.
      if THardcodedSecretDetector.IsConstantNamingStyle(N.Name) then Continue;
      // META-Feld (SourceToken, TokenRef, PasswordHash, ...) - beschreibt
      // HERKUNFT / REFERENZ / DARSTELLUNG eines Secrets, nicht den Wert.
      if THardcodedSecretDetector.IsSecretMetaField(N.Name) then Continue;
      // FP-Gate (2026-07-04): template-delimiter / nul-char-init /
      // sentinel-value - Wert-Plausibilitaet analog AnalyzeMethod.
      if not THardcodedSecretDetector.IsPlausibleSecretValue(Literal) then Continue;
      // FP-Gate (2026-07-04): test-fixture - Dummy-Beispielwerte, z.B.
      // `cPassword = 'masterkey'` (mORMot extdb-bench, Firebird-Default).
      if THardcodedSecretDetector.IsDummySecretValue(Literal) then Continue;
      // FP-Gate (Real-World-FP-Audit 2026-07-10): Wert-FORM ist kein Secret
      // (URL/Pfad/GUID/Format-Template/Label/Config-Key-Name) - analog
      // AnalyzeMethod. Der Field-Name N.Name dient dem LHS-Spiegel-Check.
      if THardcodedSecretDetector.IsNonSecretValueShape(Literal, N.Name) then Continue;

      if Length(Literal) > MAX_VAL_LEN then
        LitShort := Copy(Literal, 1, MAX_VAL_LEN - 4) + '...'''
      else
        LitShort := Literal;
      Results.Add(TLeakFinding.New(FileName, '', N.Line,
        N.Name + ' = ' + LitShort, fkHardcodedSecret));
    end;
  finally
    Fields.Free;
  end;
end;

class procedure THardcodedSecretDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
begin
  // Test-Files komplett uebergehen. Mock-Tokens / Fixture-Passwoerter /
  // Test-Credentials sind per Definition keine produktiven Secrets.
  if IsTestFilePath(FileName) then Exit;
  // Pass 1: Const-Section + Class-Field-Initializer (nkField).
  ScanFieldsForSecrets(UnitNode, FileName, Results);
  // Pass 2: nkAssign innerhalb der Methoden (bestehender Pfad).
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
      AnalyzeMethod(M, FileName, Results);
  finally
    Methods.Free;
  end;
end;

end.
