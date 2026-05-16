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
  end;

implementation

{ ---- HardcodedSecret ---- }

procedure TTestHardcodedSecret.Secret_PasswordAssignedLiteral_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin'#13#10+
  '  FPassword := ''geheim123'';'#13#10+
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual(1, TFindingHelper.Count(F, fkHardcodedSecret),
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
    Assert.AreEqual(1, TFindingHelper.Count(F, fkHardcodedSecret),
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
    Assert.AreEqual(1, TFindingHelper.Count(F, fkHardcodedSecret),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkHardcodedSecret),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkHardcodedSecret),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkHardcodedSecret),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkHardcodedSecret),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkHardcodedSecret),
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
    Assert.AreEqual(0, TFindingHelper.Count(F, fkHardcodedSecret),
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
    Assert.AreEqual(1, TFindingHelper.Count(F, fkHardcodedSecret),
      'ConnectionString mit Password= muss als Secret gemeldet werden');
  finally F.Free; end;
end;

// =============================================================================
// HardcodedSecret-Erweiterungen
// =============================================================================

procedure TTestHardcodedSecretExt.Secret_PwdLowercaseAssign_ReportsError;
const SRC =
  'unit t; implementation'#13#10+
  'procedure Foo;'#13#10+
  'var pwd: string;'#13#10+
  'begin pwd := ''geheim123''; end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkHardcodedSecret) >= 1);
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
  try Assert.IsTrue(TFindingHelper.Count(F, fkHardcodedSecret) >= 1);
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
  try Assert.IsTrue(TFindingHelper.Count(F, fkHardcodedSecret) >= 1);
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkHardcodedSecret));
  finally F.Free; end;
end;

procedure TTestHardcodedSecretExt.Secret_Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin FPassword := ''geheim123''; end;';
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
// MissingVar enthaelt Name + Literal-Snippet ('FPassword = "geheim123"').
const SRC =
  'unit t; implementation'#13#10+
  'procedure TFoo.Init;'#13#10+
  'begin FPassword := ''geheim123''; end;';
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
    Assert.Contains(Hit.MissingVar, 'geheim');
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
  try Assert.AreEqual(3, TFindingHelper.Count(F, fkHardcodedSecret));
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkHardcodedSecret),
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
  try Assert.AreEqual(0, TFindingHelper.Count(F, fkHardcodedSecret));
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
  try Assert.AreEqual(1, TFindingHelper.Count(F, fkHardcodedSecret),
    'Mixed-Case-Field ist echte Secret-Zuweisung');
  finally F.Free; end;
end;

end.
