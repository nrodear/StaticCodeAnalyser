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

initialization
  TDUnitX.RegisterTestFixture(TTestDfmHardcodedDbCreds);

end.
