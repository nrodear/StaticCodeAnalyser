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
//   FPassword     := 'geheim123'        → Fehler
//   ApiToken      := 'sk-abc...'        → Fehler
//   ConnString    := 'Server=…;Pwd=x'  → Fehler
//   FPassword     := GetPassword()      → kein Befund (Funktionsaufruf)
//   FPassword     := FStoredPwd         → kein Befund (Variable)

interface

uses
  System.SysUtils, System.Generics.Collections,
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
  end;

implementation

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

class procedure THardcodedSecretDetector.AnalyzeMethod(MethodNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
const
  MAX_VAL_LEN = 20;

  // Snake-Upper-Const-Naming: nur Uppercase + Underscore + Digits.
  // Matched 'JWT_SECRET_HEADER', 'X_TOKEN', 'API_KEY' - das sind in der
  // Praxis Algorithmus-/Protokoll-Marker (mORMot, JWT, REST-Header), KEINE
  // Secret-Werte. False-Positive-Reduktion fuer mORMot-Codebase.
  function IsConstantNamingStyle(const FullName: string): Boolean;
  var
    Bare : string;
    DotPos : Integer;
    HasUnderscore : Boolean;
    AllUpperOrDigit : Boolean;
    C : Char;
  begin
    Result := False;
    // Letztes Segment nach Punkt-Qualifier (Self.FOO -> FOO)
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

var
  Assigns  : TList<TAstNode>;
  A        : TAstNode;
  F        : TLeakFinding;
  LitShort : string;
begin
  Assigns := MethodNode.FindAll(nkAssign);
  try
    for A in Assigns do
    begin
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

class procedure THardcodedSecretDetector.AnalyzeUnit(UnitNode: TAstNode;
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
