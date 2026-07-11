unit uTestHardcodedSecret;

// Tests fuer den THardcodedSecretDetector (Basis und Erweiterungen).

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestSrcBuilder,
  uTestFindingHelper;

type
  // ---- HardcodedSecret (THardcodedSecretDetector) ------------------------------------
  [TestFixture]
  TTestHardcodedSecret = class
  public
    [Test] procedure Secret_PasswordAssignedLiteral_ReportsError;
    [Test] procedure Secret_TokenAssignedLiteral_ReportsError;
    [Test] procedure Secret_ApiKeyAssignedLiteral_ReportsError;
    [Test] procedure Secret_AssignFromFunction_NoFinding;
    [Test] procedure Secret_AssignFromVariable_NoFinding;
    [Test] procedure Secret_NonSecretVarWithLiteral_NoFinding;
    // CamelCase/Snake-Case-Wortgrenzen (IsSecretName-Refactor)
    [Test] procedure Secret_SecretarySubstring_NoFinding;
    [Test] procedure Secret_UserTokenSnakeCase_ReportsError;
    // Leeres Literal ist Initialisierung, kein Secret
    [Test] procedure Secret_EmptyLiteral_NoFinding;
    // ConnectionString ohne Password-Anteil ist kein Secret
    [Test] procedure Secret_ConnStringNoPassword_NoFinding;
    [Test] procedure Secret_ConnStringWithPassword_ReportsError;
  end;

  // ---- HardcodedSecret Erweiterungen -------------------------------------------------
  [TestFixture]
  TTestHardcodedSecretExt = class
  public
    [Test] procedure Secret_PwdLowercaseAssign_ReportsError;
    [Test] procedure Secret_SecretAssignedLiteral_ReportsError;
    [Test] procedure Secret_PrivateKeyAssignedLiteral_ReportsError;
    [Test] procedure Secret_NormalStringNoSecretName_NoFinding;
    // ---- Severity / Finding-Inhalt / Multi-Hit -------------------------------
    [Test] procedure Secret_Finding_KindAndSeverity;
    [Test] procedure Secret_Finding_MissingVarMentionsVarAndLiteralSnippet;
    [Test] procedure Secret_MultipleHitsInSameMethod_AllReported;
    // ---- Const-Naming-Style Skip (mORMot-FP-Fix) ----------------------------
    [Test] procedure Secret_UpperSnakeConst_NotReported;
    [Test] procedure Secret_QualifiedUpperSnake_NotReported;
    [Test] procedure Secret_MixedCaseField_StillReported;
    // Real-World-FP-Audit 2026-07-10 (e-i): CamelCase-Config-Name als Wert
    [Test] procedure Secret_CamelCaseConfigValue_NotReported;
    // ---- FP-Gates 2026-07-04 (Audit_RealWorldBugs 3.5: 14 FP / 0 TP) --------
    // Wert-Plausibilitaet: kein Fund bei Werten ohne alphanumerischen Kern
    [Test] procedure Secret_TemplateDelimiterValue_NoFinding;
    [Test] procedure Secret_NulCharInitValue_NoFinding;
    [Test] procedure Secret_SentinelCharValue_NoFinding;
    // Dummy-Wert-Liste: bekannte Beispiel-/Platzhalterwerte
    [Test] procedure Secret_DummyFixtureValues_NoFinding;
    [Test] procedure Secret_ConstDummyValue_NoFinding;
    [Test] procedure Secret_PureDigitsValue_NoFinding;
    // Gegenprobe: realistischer Wert muss weiter feuern
    [Test] procedure Secret_RealisticPassword_StillReported;
    // Refinement 2026-07-04 (Code-Review): Trailing-Digit-Strip max. 2 +
    // Reinzahl-Regel nur bis Laenge 6 -> echte Credentials feuern weiter
    [Test] procedure Secret_EmbeddedYearValue_StillReported;
    [Test] procedure Secret_LongNumericValue_StillReported;
    // --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---
    [Test] procedure Secret_UrlEndpointValue_NotReported;
    [Test] procedure Secret_ServiceAccountKeyWithUrl_StillReported;
    // --- Real-World FP-Audit 2026-07-12 (OID-Konstante) ---
    [Test] procedure Secret_OidDottedNumericValue_NotReported;
  end;

implementation

{ ---- HardcodedSecret ---- }

procedure TTestHardcodedSecret.Secret_PasswordAssignedLiteral_ReportsError;
// Testwert 2026-07-04 von 'geheim123' auf realistischen Wert geaendert:
// 'geheim' (+Trailing-Digits) faellt jetzt unter die Dummy-Wert-Liste
// (FP-Gate test-fixture, Audit_RealWorldBugs 3.5).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  FPassword := ''Xk9#pQz7Lm'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedSecret),
      'Passwort-Literal – Error');
  finally F.Free; end;
end;

procedure TTestHardcodedSecret.Secret_TokenAssignedLiteral_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  ApiToken := ''sk-abc123xyz'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedSecret),
      'Token-Literal – Error');
  finally F.Free; end;
end;

procedure TTestHardcodedSecret.Secret_ApiKeyAssignedLiteral_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  APIKey := ''MY-SECRET-KEY'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedSecret),
      'API-Key-Literal – Error');
  finally F.Free; end;
end;

procedure TTestHardcodedSecret.Secret_AssignFromFunction_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  FPassword := GetPasswordFromVault();'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedSecret),
      'Passwort aus Funktion – kein Befund');
  finally F.Free; end;
end;

procedure TTestHardcodedSecret.Secret_AssignFromVariable_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init(const PWD: string);'#13#10+
  'begin'#13#10+
  '  FPassword := PWD;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedSecret),
      'Passwort aus Parameter – kein Befund');
  finally F.Free; end;
end;

procedure TTestHardcodedSecret.Secret_EmptyLiteral_NoFinding;
// Reproduziert den FixHint-Falschpositiv: 'mPasswort := '''''' ist eine
// Initialisierung auf leer und semantisch das Gegenteil eines Secrets.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  mPasswort := '''';'#13#10+
  '  FToken    := '''';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedSecret),
      'Leeres Stringliteral darf nicht als Secret gemeldet werden');
  finally F.Free; end;
end;

procedure TTestHardcodedSecret.Secret_NonSecretVarWithLiteral_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  Title := ''Willkommen'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedSecret),
      'Normaler String-Literal - kein Befund');
  finally F.Free; end;
end;

procedure TTestHardcodedSecret.Secret_SecretarySubstring_NoFinding;
// 'secretary' enthaelt 'secret' als Substring, ist aber semantisch nichts
// Sicherheitskritisches. Vor dem CamelCase/Snake-Boundary-Refactor in
// IsSecretName haette die naive Pos-Suche faelschlich getriggert.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  secretary := ''Frau Mueller'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedSecret),
      '"secretary" darf nicht als Secret-Pattern matchen');
  finally F.Free; end;
end;

procedure TTestHardcodedSecret.Secret_UserTokenSnakeCase_ReportsError;
// Snake-Case-Boundary: 'user_token' enthaelt 'token' nach Underscore -
// gilt als Wortgrenze und MUSS gemeldet werden.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  user_token := ''sk-abcdef'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkHardcodedSecret) >= 1,
      '"user_token" muss als Secret-Variable erkannt werden');
  finally F.Free; end;
end;

procedure TTestHardcodedSecret.Secret_ConnStringNoPassword_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  FConnectionString := ''Server=localhost;Database=test;'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedSecret),
      'ConnectionString ohne Passwort-Anteil darf nicht gemeldet werden');
  finally F.Free; end;
end;

procedure TTestHardcodedSecret.Secret_ConnStringWithPassword_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  FConnectionString := ''Server=localhost;Database=test;Password=secret123;'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedSecret),
      'ConnectionString mit Password= muss als Secret gemeldet werden');
  finally F.Free; end;
end;

// =============================================================================
// HardcodedSecret-Erweiterungen
// =============================================================================

procedure TTestHardcodedSecretExt.Secret_PwdLowercaseAssign_ReportsError;
// Testwert 2026-07-04: 'geheim123' -> realistischer Wert (Dummy-Liste, s.o.).
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var pwd: string;'#13#10+
  'begin pwd := ''Xk9#pQz7Lm''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedSecret),
      'genau 1 HardcodedSecret-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'pwd := '),
      TFindingHelper.FirstOf(F, fkHardcodedSecret).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_SecretAssignedLiteral_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var secret: string;'#13#10+
  'begin secret := ''abc123def456''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedSecret),
      'genau 1 HardcodedSecret-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'secret := '),
      TFindingHelper.FirstOf(F, fkHardcodedSecret).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_PrivateKeyAssignedLiteral_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var private_key: string;'#13#10+
  'begin private_key := ''-----BEGIN RSA''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedSecret),
      'genau 1 HardcodedSecret-Fund erwartet');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'private_key := '),
      TFindingHelper.FirstOf(F, fkHardcodedSecret).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_NormalStringNoSecretName_NoFinding;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var msg: string;'#13#10+
  'begin msg := ''hallo''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedSecret));
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_Finding_KindAndSeverity;
// Testwert 2026-07-04: 'geheim123' -> realistischer Wert (Dummy-Liste, s.o.).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin FPassword := ''Xk9#pQz7Lm''; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkHardcodedSecret then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit, 'fkHardcodedSecret finding expected');
    Assert.AreEqual(fkHardcodedSecret, Hit.Kind);
    Assert.AreEqual(lsError, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_Finding_MissingVarMentionsVarAndLiteralSnippet;
// MissingVar enthaelt Name + Literal-Snippet ('FPassword = "Xk9#pQz7Lm"').
// Testwert 2026-07-04: 'geheim123' -> realistischer Wert (Dummy-Liste, s.o.).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin FPassword := ''Xk9#pQz7Lm''; end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkHardcodedSecret then
      begin
        Hit := Fnd;
        Break;
      end;
    Assert.IsNotNull(Hit);
    Assert.Contains(Hit.MissingVar, 'FPassword');
    Assert.Contains(Hit.MissingVar, 'Xk9#pQz7Lm');
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_MultipleHitsInSameMethod_AllReported;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  FPassword := ''pw_secret'';'#13#10+
  '  FApiKey   := ''ak_secret'';'#13#10+
  '  FToken    := ''tk_secret'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(3, TFindingHelper.Count(F, fkHardcodedSecret));
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_UpperSnakeConst_NotReported;
// JWT_SECRET_HEADER ist eine Const-Naming-Konvention (Algorithmus-Marker,
// kein echter Secret). uHardcodedSecret muss das skippen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure Init;'#13#10+
  'begin'#13#10+
  '  JWT_SECRET_HEADER := ''JWT'';'#13#10+
  '  X_TOKEN := ''XTKN'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedSecret),
    'UPPER_SNAKE-Identifier sind Const-Marker, kein Secret');
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_QualifiedUpperSnake_NotReported;
// Self.X_PASSWORD darf genauso geskippt werden (Qualifier wird strippen)
const SRC =
  'unit t; implementation'#13#10+
  'procedure Init;'#13#10+
  'begin Self.JWT_PASSWORD_KEY := ''JWTPW''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedSecret));
  finally F.Free; end;
end;

// =============================================================================
// FP-Gates 2026-07-04 (Audit_RealWorldBugs 3.5: 14 FP / 0 TP auf 25 Repos)
// =============================================================================

procedure TTestHardcodedSecretExt.Secret_TemplateDelimiterValue_NoFinding;
// FP-Klasse template-delimiter (MVCFramework.View.Renderers.Sempare.pas:80/81):
// StartToken/EndToken sind Lexer-Delimiter der Template-Engine. Werte ohne
// alphanumerischen Kern ('{{', '}}') sind keine plausiblen Secrets.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Configure;'#13#10+
  'begin'#13#10+
  '  StartToken := ''{{'';'#13#10+
  '  EndToken := ''}}'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedSecret),
      'Template-Delimiter ohne alphanumerischen Kern darf nicht gemeldet werden');
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_NulCharInitValue_NoFinding;
// FP-Klasse nul-char-init (doublecmd ftpfunc.pas:287, fpsnumformat.pas:3556):
// #0-Zuweisungen terminieren Puffer bzw. resetten Parser-Token-Zeichen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Reset;'#13#10+
  'begin'#13#10+
  '  FToken := #0;'#13#10+
  '  APassword[1] := #0;'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedSecret),
      '#0-Steuerzeichen ist Puffer-/Lexer-Reset, kein Secret');
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_SentinelCharValue_NoFinding;
// FP-Klasse sentinel-value (mormot.rest.client.pas:1407):
// PasswordHashHexa := '#' ist ein Statusflag fuer erfolgreiche SCRAM-Auth.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.MarkAuth;'#13#10+
  'begin'#13#10+
  '  PasswordHashHexa := ''#'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedSecret),
      'Einzelzeichen-Sentinel ist ein Statusflag, kein Secret');
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_DummyFixtureValues_NoFinding;
// FP-Klasse test-fixture (mORMot PerfTestCases.pas:393/734, 35-sessions
// server.pas:56/65): dokumentierte Demo-Credentials. 'pass1' greift ueber
// den Trailing-Digit-Strip ('pass1' -> 'pass').
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Setup;'#13#10+
  'begin'#13#10+
  '  DBPassword := ''password'';'#13#10+
  '  PasswordPlain := ''pass1'';'#13#10+
  '  FMasterPwd := ''masterkey'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedSecret),
      'Bekannte Dummy-/Beispielwerte duerfen nicht gemeldet werden');
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_ConstDummyValue_NoFinding;
// Dummy-Wert-Gate muss auch im nkField-Pfad (Const-Section) greifen -
// Korpus-FP: `cPassword = 'masterkey'` (Firebird-Default in extdb-bench).
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'const cPassword = ''masterkey'';'#13#10+
  'implementation'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedSecret),
      'Dummy-Wert in Const-Section darf nicht gemeldet werden');
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_PureDigitsValue_NoFinding;
// Rein numerische Kurzwerte ('1234') sind PIN-Platzhalter aus Beispielen.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  FPassword := ''1234'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedSecret),
      'Rein numerischer Platzhalter darf nicht gemeldet werden');
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_RealisticPassword_StillReported;
// Gegenprobe zu den Wert-Gates: ein realistischer Wert (>= 4 Zeichen,
// alphanumerischer Kern, kein Dummy-Listen-Treffer) muss weiter feuern -
// auch wenn er auf eine Ziffer endet (Trailing-Digit-Strip darf nur
// Listen-Staemme treffen, keine echten Werte).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  FPassword := ''Tr0ub4dor&3'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedSecret),
      'Realistischer Secret-Wert muss trotz Wert-Gates gemeldet werden');
    Assert.AreEqual(TFindingHelper.LineOf(SRC, 'FPassword := '),
      TFindingHelper.FirstOf(F, fkHardcodedSecret).LineNumber,
      'Fund muss auf der Trigger-Zeile liegen');
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_MixedCaseField_StillReported;
// Standard-Field-Naming (FPassword) muss weiter flagged werden.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin FPassword := ''realsecret''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedSecret),
    'Mixed-Case-Field ist echte Secret-Zuweisung');
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_CamelCaseConfigValue_NotReported;
// Real-World-FP-Audit 2026-07-10 (e-i): ein CamelCase-Config-/Property-Name als
// WERT ('UsePassword') ist kein Geheimwert -> unterdrueckt. Gegenstueck zu
// Secret_MultipleHits (snake_case 'pw_secret' bleibt Fund, kein interior-Cap).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin FPassword := ''UsePassword''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedSecret),
    'CamelCase-Config-Name als Wert ist kein Secret');
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_EmbeddedYearValue_StillReported;
// Refinement-Gegenprobe (2026-07-04, Code-Review): ein echter Credential mit
// eingebetteter Jahreszahl ('admin2024') darf NICHT vom Trailing-Digit-Strip
// (max. 2 Ziffern -> 'admin20') auf den Dummy-Stamm 'admin' reduziert und
// damit faelschlich unterdrueckt werden.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  FPassword := ''admin2024'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedSecret),
      'Credential mit eingebetteter Jahreszahl darf nicht als Dummy gelten');
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_LongNumericValue_StillReported;
// Refinement-Gegenprobe: eine lange reine Ziffernfolge (> 6) ist kein
// PIN-Platzhalter mehr, sondern ein moegliches numerisches Token/Passwort.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  FPassword := ''1234567890123456'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkHardcodedSecret),
      'Lange reine Ziffernfolge (>6) darf nicht als PIN-Platzhalter gelten');
  finally F.Free; end;
end;


// --- Real-World FP-Audit 2026-07-10 Regression (Welle 1+2) ---

procedure TTestHardcodedSecretExt.Secret_UrlEndpointValue_NotReported;
// Real-World-FP-Audit 2026-07-10/11 (IsNonSecretValueShape, Zweig a):
// CEF4Delphi uCEFOAuth2Helper.pas:136 - der Wert ist der oeffentliche Google-
// Token-ENDPOINT 'https://oauth2.googleapis.com/token', KEIN Token-Wert. Der
// '://'-Zweig unterdrueckt URL-/Pfad-Werte, obwohl der LHS-Name ein Secret-
// Keyword ('token') traegt. LHS 'FAccessToken' passiert IsSecretName und
// entkommt IsSecretMetaField (Suffix '' ist kein Meta-Suffix), erreicht also
// das WERT-Form-Gate, das hier greift. Gegenstueck unten: eingebetteter
// Service-Account-Key mit URL bleibt Fund (harte Secret-Marker zuerst).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  FAccessToken := ''https://oauth2.googleapis.com/token'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedSecret),
      'URL-Endpoint-Wert (://) ist kein Secret und darf nicht gemeldet werden');
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_ServiceAccountKeyWithUrl_StillReported;
// Gegenprobe zum URL-Zweig (a), Real-World-FP-Audit 2026-07-10/11:
// Alcinoe ALFmxNotificationService Main.pas:112 - ein eingebetteter Service-
// Account-Key enthaelt ZWAR eine token_uri-URL ('https://...'), ist aber ueber
// den PEM-Marker '-----BEGIN PRIVATE KEY-----' ein echter Geheimwert. In
// IsNonSecretValueShape werden die HARTEN Secret-Marker VOR dem '://'-Pfad-
// zweig freigestellt (Zeilen 475-477 laufen vor 481) -> der Fund bleibt
// bestehen und wird nicht faelschlich als URL geschluckt. Distinkt zu
// Secret_PrivateKeyAssignedLiteral (blanker PEM ohne URL, stresst die
// Zweig-Reihenfolge nicht).
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  FPrivateKey := ''https://oauth2.googleapis.com/token -----BEGIN PRIVATE KEY-----MIIEvQABC'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkHardcodedSecret) >= 1,
      'Eingebetteter PEM-Key mit token_uri-URL muss trotz :// weiter gemeldet werden');
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_OidDottedNumericValue_NotReported;
// Real-World-FP-Audit 2026-07-12 (IsNonSecretValueShape, Zweig c2):
// szOID_RSA_challengePwd / szOID_TIMESTAMP_TOKEN (Alcinoe.WinApi.WinCrypt.pas)
// tragen 'pwd'/'token' im NAMEN, der Wert ist aber eine ASN.1-OID (reine
// Punkt-getrennte Ziffernfolge) - niemals ein Geheimwert. Der LHS 'FTokenOid'
// passiert IsSecretName, der Wert '1.2.840...' wird durch die neue OID-Klausel
// als Nicht-Secret erkannt.
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  FTokenOid := ''1.2.840.113549.1.9.7'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkHardcodedSecret),
      'ASN.1-OID (dotted-numeric) ist kein Secret und darf nicht gemeldet werden');
  finally F.Free; end;
end;
end.
