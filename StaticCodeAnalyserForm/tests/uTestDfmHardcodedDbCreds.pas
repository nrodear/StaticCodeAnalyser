unit uTestDfmHardcodedDbCreds;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDfmHardcodedDbCreds = class
  public
    // --- Treffer: Password als String-Literal ---
    [Test] procedure Test_AdoConnection_Password_Detected;
    [Test] procedure Test_FdConnection_Password_Detected;
    [Test] procedure Test_IbDatabase_Password_Detected;

    // --- Treffer: ConnectionString mit Password=/Pwd= ---
    [Test] procedure Test_ConnectionString_WithPasswordEq_Detected;
    [Test] procedure Test_ConnectionString_WithPwdEq_Detected;
    [Test] procedure Test_ConnectionString_CaseInsensitive;

    // --- Treffer: Params.Strings mit Password=/Pwd=/User_Password= ---
    // Jede Gegenprobe steht neben genau EINEM echten Eintrag, damit der
    // Test ohne den Params-Zweig rot ist (0 statt 1).
    [Test] procedure Test_FdParams_Password_Detected_OnItemLine;
    [Test] procedure Test_Params_PwdAndUserPassword_CaseInsensitive;
    [Test] procedure Test_Params_WrappedItem_IsJoined;
    [Test] procedure Test_Params_EmptyValue_NotDetected;
    [Test] procedure Test_Params_OtherKeys_NotDetected;
    [Test] procedure Test_Params_NonCredentialClass_NotDetected;

    // --- Beide gleichzeitig ---
    [Test] procedure Test_BothPasswordAndConnectionString_TwoFindings;

    // --- Nicht-Treffer ---
    [Test] procedure Test_EmptyPassword_NotDetected;
    [Test] procedure Test_ConnectionString_NoPassword_NotDetected;
    [Test] procedure Test_NonCredentialComponent_NotDetected; // TButton
    [Test] procedure Test_QueryClass_NotDetected;             // TADOQuery

    // --- Finding-Inhalt ---
    [Test] procedure Test_Finding_SeverityIsError;
    [Test] procedure Test_Finding_KindIsHardcodedDbCreds;
    [Test] procedure Test_Finding_MissingVarMentionsComponentAndClass;
  end;

  // Klassen-Whitelist 2026-10-24: JVCL-UIB und Lazarus-SQLdb (eigene
  // Fixture, die erste ist bei 20 Tests voll).
  [TestFixture]
  TTestDfmHardcodedDbCredsClasses = class
  public
    [Test] procedure Test_LazarusIBConnection_Password_Detected;
    [Test] procedure Test_JvUibDatabase_PasswordAndParams_TwoFindings;
    [Test] procedure Test_SqldbFamily_EmptyPasswordStaysSilent;
    [Test] procedure Test_UnlistedLazReportWrapper_NotDetected;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uDfmParser, uComponentGraph,
  uDfmHardcodedDbCreds;

function RunOn(const Src: string): TObjectList<TLeakFinding>;
var
  Parser : TDfmParser;
  Graph  : TComponentGraph;
begin
  Result := TObjectList<TLeakFinding>.Create(True);
  Parser := TDfmParser.Create;
  try
    Graph := Parser.ParseSource(Src);
    try
      TDfmHardcodedDbCredsDetector.Analyze(Graph, 'test.dfm', Result);
    finally
      Graph.Free;
    end;
  finally
    Parser.Free;
  end;
end;

function Count(F: TObjectList<TLeakFinding>; K: TFindingKind): Integer;
var Fnd: TLeakFinding;
begin
  Result := 0;
  for Fnd in F do
    if Fnd.Kind = K then Inc(Result);
end;

{ --- Password-Literal --- }

procedure TTestDfmHardcodedDbCreds.Test_AdoConnection_Password_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Conn: TADOConnection'#13#10 +
    '  Password = ''s3cret'''#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmHardcodedDbCreds));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedDbCreds.Test_FdConnection_Password_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Conn: TFDConnection'#13#10 +
    '  Password = ''pw'''#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmHardcodedDbCreds));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedDbCreds.Test_IbDatabase_Password_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Conn: TIBDatabase'#13#10 +
    '  Password = ''masterkey'''#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmHardcodedDbCreds));
  finally F.Free; end;
end;

{ --- ConnectionString --- }

procedure TTestDfmHardcodedDbCreds.Test_ConnectionString_WithPasswordEq_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Conn: TADOConnection'#13#10 +
    '  ConnectionString = ''Provider=X;User ID=u;Password=p;Data Source=db'''#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmHardcodedDbCreds));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedDbCreds.Test_ConnectionString_WithPwdEq_Detected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Conn: TADOConnection'#13#10 +
    '  ConnectionString = ''Driver=Y;UID=u;Pwd=p'''#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmHardcodedDbCreds));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedDbCreds.Test_ConnectionString_CaseInsensitive;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Conn: TADOConnection'#13#10 +
    '  ConnectionString = ''Server=X;password=secret'''#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmHardcodedDbCreds));
  finally F.Free; end;
end;

{ --- Params.Strings --- }

procedure TTestDfmHardcodedDbCreds.Test_FdParams_Password_Detected_OnItemLine;
// ShowcaseDemo uOrderForm.dfm: mehrzeilige String-Liste, Fund auf der
// Zeile des Password-Eintrags (4), nicht auf der 'Params.Strings'-Zeile (2).
// Wuerde der Splitter die Items verschmelzen, hiesse der Schluessel
// 'Database' und es gaebe keinen Fund.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object FDConnection1: TFDConnection'#13#10 +
    '  Params.Strings = ('#13#10 +
    '    ''Database=orders'''#13#10 +
    '    ''Password=Sommer2024!'''#13#10 +
    '    ''DriverID=PG'')'#13#10 +
    '  LoginPrompt = False'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmHardcodedDbCreds));
    Assert.AreEqual('4', F[0].LineNumber);
    Assert.Contains(F[0].MissingVar, 'Params.Strings');
  finally F.Free; end;
end;

procedure TTestDfmHardcodedDbCreds.Test_Params_PwdAndUserPassword_CaseInsensitive;
// IBX schreibt die Schluessel klein ('password=...'); Pwd= und
// User_Password= sind die Aliase anderer Treiber.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Db: TIBDatabase'#13#10 +
    '  Params.Strings = ('#13#10 +
    '    ''user_name=SYSDBA'''#13#10 +
    '    ''password=masterkey'')'#13#10 +
    'end'#13#10 +
    'object Sql: TSQLConnection'#13#10 +
    '  Params.Strings = ('#13#10 +
    '    ''PWD=a'' ''USER_PASSWORD=b'')'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(3, Count(F, fkDfmHardcodedDbCreds));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedDbCreds.Test_Params_WrappedItem_IsJoined;
// TWriter bricht lange Items mit ' +' um; die Teile sind EIN Eintrag.
// #39 ist ein Apostroph mitten im Wert.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Conn: TFDConnection'#13#10 +
    '  Params.Strings = ('#13#10 +
    '    ''Pass'' +'#13#10 +
    '      ''word=geh''#39''eim'')'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmHardcodedDbCreds));
    Assert.AreEqual('3', F[0].LineNumber);
  finally F.Free; end;
end;

procedure TTestDfmHardcodedDbCreds.Test_Params_EmptyValue_NotDetected;
// 'Password=' und 'Password=   ' tragen kein Klartext-Passwort; nur der
// Pwd-Eintrag mit Wert zaehlt.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Conn: TFDConnection'#13#10 +
    '  Params.Strings = ('#13#10 +
    '    ''Password='''#13#10 +
    '    ''Password=   '''#13#10 +
    '    ''Pwd=x'')'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmHardcodedDbCreds));
    Assert.AreEqual('5', F[0].LineNumber);
  finally F.Free; end;
end;

procedure TTestDfmHardcodedDbCreds.Test_Params_OtherKeys_NotDetected;
// Nur die exakten Schluessel zaehlen: 'Passwort', 'MyPassword', ein Item
// ohne '=' und ConnectionDef bleiben stumm.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Conn: TFDConnection'#13#10 +
    '  Params.Strings = ('#13#10 +
    '    ''ConnectionDef=Orders'''#13#10 +
    '    ''Passwort=x'''#13#10 +
    '    ''MyPassword=x'''#13#10 +
    '    ''Password'''#13#10 +
    '    ''User_Password=y'')'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmHardcodedDbCreds));
    Assert.Contains(F[0].MissingVar, 'User_Password=');
  finally F.Free; end;
end;

procedure TTestDfmHardcodedDbCreds.Test_Params_NonCredentialClass_NotDetected;
// Die Klassen-Whitelist gilt auch fuer Params: eine Query-Komponente
// steht nicht darauf.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Qry: TFDQuery'#13#10 +
    '  Params.Strings = ('#13#10 +
    '    ''password=masterkey'')'#13#10 +
    'end'#13#10 +
    'object Conn: TFDConnection'#13#10 +
    '  Params.Strings = ('#13#10 +
    '    ''Password=pw'')'#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmHardcodedDbCreds));
    Assert.Contains(F[0].MissingVar, 'TFDConnection');
  finally F.Free; end;
end;

procedure TTestDfmHardcodedDbCreds.Test_BothPasswordAndConnectionString_TwoFindings;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Conn: TADOConnection'#13#10 +
    '  Password = ''s3cret'''#13#10 +
    '  ConnectionString = ''Server=X;Password=q'''#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(2, Count(F, fkDfmHardcodedDbCreds));
  finally F.Free; end;
end;

{ --- Nicht-Treffer --- }

procedure TTestDfmHardcodedDbCreds.Test_EmptyPassword_NotDetected;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Conn: TADOConnection'#13#10 +
    '  Password = '''''#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmHardcodedDbCreds));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedDbCreds.Test_ConnectionString_NoPassword_NotDetected;
// ConnectionString ohne Password=/Pwd= ist OK (z.B. trusted connection).
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Conn: TADOConnection'#13#10 +
    '  ConnectionString = ''Provider=X;Integrated Security=SSPI'''#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmHardcodedDbCreds));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedDbCreds.Test_NonCredentialComponent_NotDetected;
// Eine Button-Komponente mit einer hypothetischen Password-Property
// (z.B. eine Custom-Komponente) loest NICHT aus - die Whitelist greift.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Btn: TButton'#13#10 +
    '  Password = ''s3cret'''#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmHardcodedDbCreds));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedDbCreds.Test_QueryClass_NotDetected;
// TADOQuery hat keinen Connection-Status, Passwoerter liegen auf der
// zugehoerigen Connection. Whitelist trifft daher absichtlich nicht.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Q: TADOQuery'#13#10 +
    '  Password = ''s3cret'''#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(0, Count(F, fkDfmHardcodedDbCreds));
  finally F.Free; end;
end;

{ --- Finding-Inhalt --- }

procedure TTestDfmHardcodedDbCreds.Test_Finding_SeverityIsError;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Conn: TADOConnection Password = ''s3cret'' end');
  try
    Assert.AreEqual(lsError, F[0].Severity);
  finally F.Free; end;
end;

procedure TTestDfmHardcodedDbCreds.Test_Finding_KindIsHardcodedDbCreds;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Conn: TADOConnection Password = ''s3cret'' end');
  try
    Assert.AreEqual(fkDfmHardcodedDbCreds, F[0].Kind);
  finally F.Free; end;
end;

procedure TTestDfmHardcodedDbCreds.Test_Finding_MissingVarMentionsComponentAndClass;
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Conn: TADOConnection Password = ''s3cret'' end');
  try
    Assert.Contains(F[0].MissingVar, 'Conn');
    Assert.Contains(F[0].MissingVar, 'TADOConnection');
    Assert.Contains(F[0].MissingVar, 'Password');
  finally F.Free; end;
end;

{ --- Klassen-Whitelist: JVCL-UIB und Lazarus-SQLdb --- }

procedure TTestDfmHardcodedDbCredsClasses.Test_LazarusIBConnection_Password_Detected;
// lazarus components/lazreport/samples/Demo_CrossTab/unit1.lfm
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object IBConnection1: TIBConnection'#13#10 +
    '  DatabaseName = ''employee'''#13#10 +
    '  Password = ''masterkey'''#13#10 +
    '  UserName = ''sysdba'''#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmHardcodedDbCreds));
    Assert.AreEqual('3', F[0].LineNumber);
  finally F.Free; end;
end;

procedure TTestDfmHardcodedDbCredsClasses.Test_JvUibDatabase_PasswordAndParams_TwoFindings;
// realworld jvcl/donations/UIB: dasselbe Passwort steht im Params-Eintrag
// UND in der PassWord-Property - zwei Klartext-Stellen, zwei Funde.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object DataBase: TJvUIBDataBase'#13#10 +
    '  Params.Strings = ('#13#10 +
    '    ''sql_dialect=3'''#13#10 +
    '    ''password=masterkey'''#13#10 +
    '    ''user_name=SYSDBA'')'#13#10 +
    '  UserName = ''SYSDBA'''#13#10 +
    '  PassWord = ''masterkey'''#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(2, Count(F, fkDfmHardcodedDbCreds));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedDbCredsClasses.Test_SqldbFamily_EmptyPasswordStaysSilent;
// ODBC haengt Params an den Connection-String (PWD= ist ein Credential),
// MySQL80 traegt die Password-Property; ein leeres Password der
// SQLite3-Verbindung bleibt stumm.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object Odbc: TODBCConnection'#13#10 +
    '  Params.Strings = ('#13#10 +
    '    ''PWD=geheim'')'#13#10 +
    'end'#13#10 +
    'object My: TMySQL80Connection'#13#10 +
    '  Password = ''root'''#13#10 +
    'end'#13#10 +
    'object Lite: TSQLite3Connection'#13#10 +
    '  Password = '''''#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(2, Count(F, fkDfmHardcodedDbCreds));
  finally F.Free; end;
end;

procedure TTestDfmHardcodedDbCredsClasses.Test_UnlistedLazReportWrapper_NotDetected;
// TLR_IBConnection (LazReport-Huelle) steht nicht auf der Liste; die
// TPQConnection daneben schon.
var F: TObjectList<TLeakFinding>;
begin
  F := RunOn(
    'object LR_IBConnection1: TLR_IBConnection'#13#10 +
    '  Password = ''masterkey'''#13#10 +
    'end'#13#10 +
    'object PQ: TPQConnection'#13#10 +
    '  Password = ''postgres'''#13#10 +
    'end');
  try
    Assert.AreEqual<Integer>(1, Count(F, fkDfmHardcodedDbCreds));
    Assert.Contains(F[0].MissingVar, 'TPQConnection');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDfmHardcodedDbCreds);
  TDUnitX.RegisterTestFixture(TTestDfmHardcodedDbCredsClasses);

end.
