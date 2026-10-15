unit uTestRdxSqlFacts;

// Tests fuer die Nachweise der SQL-Vorlage (uRdxSqlTemplate, Charge S1):
// Konstanten am Quelltext (SqlConstOf), FireDAC-Verbindung
// (FireDacConnectionProven), Parameternamen (SqlParamName), vorhandene
// Platzhalter (SqlPlaceholders) und AddSqlFacts. Ohne Parser - laeuft in
// reDelphix.Test UND im FPC-Pruefstand. Alles war gegen den Stand e788e0c7
// rot (die Nachweise gab es nicht, jeder Operand wurde ':pN').

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxSqlFacts = class
  public
    [Test] procedure Const_UnitLevel_LiteralValue;
    [Test] procedure Const_InterfaceSection_Visible;
    [Test] procedure Const_UpperCaseNameAlone_NotProven;
    [Test] procedure Const_ShadowedByParamOrField_NotProven;
    [Test] procedure Const_TypedConst_NotProven;
    [Test] procedure Const_NonSimpleValue_Kept;
    [Test] procedure Const_LocalOfOtherRoutine_NotVisible;
    [Test] procedure Const_DeclaredAfterUse_NotVisible;
    [Test] procedure Const_TwoBranches_SameOrDifferent;
    [Test] procedure FireDac_UsesAndTypeProven;
    [Test] procedure FireDac_OtherTypeOrNoUses_NotProven;
    [Test] procedure ExecSqlReceiver_Forms;
    [Test] procedure ParamName_FromOperand;
    [Test] procedure ParamName_ReservedAndFallback;
    [Test] procedure Placeholders_Sca199Rules;
    [Test] procedure AddSqlFacts_ConstsAndBinding;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRefactorInfo, uRdxRecipes, uRdxCodeMap, uRdxSqlTemplate,
  uTestRdxTextKit;   // Join, LineOf

// SqlConstOf(AName) an der Zeile mit AUse.
function ConstIn(const ASource, AName, AUse: string): TRdxSqlConst;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    Result := SqlConstOf(Map, AName, LineOf(ASource, AUse));
  finally
    Map.Free;
    SL.Free;
  end;
end;

function FireDacIn(const ASource, AReceiver: string;
  const AUses: array of string): Boolean;
var
  SL    : TStringList;
  Map   : TRdxCodeMap;
  Names : TArray<string>;
  i     : Integer;
begin
  SetLength(Names, Length(AUses));
  for i := 0 to High(AUses) do
    Names[i] := AUses[i];
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    Result := FireDacConnectionProven(Map, Names, AReceiver);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Eine Unit wie delphimvcframework EntGenTestsU.pas (Nicos Fall).
function EntGenUnit(const AConstLines: array of string;
  const ABody: string): string;
begin
  Result := Join(['unit EntGen;', 'interface', 'uses',
    '  FireDAC.Comp.Client;', 'type', '  TTest = class', '  private',
    '    FConn: TFDConnection;', '    procedure CreateTable(const AColumnTypes: string);',
    '  end;', 'implementation', 'const']) + #13#10 + Join(AConstLines) + #13#10
    + Join(['', 'procedure TTest.CreateTable(const AColumnTypes: string);',
    'begin', ABody, 'end;', '', 'end.']);
end;

const
  USE_LINE = '  FConn.ExecSQL(''CREATE TABLE '' + TEST_TABLE_SOFTDEL + ''('' + AColumnTypes + '')'');';

procedure TTestRdxSqlFacts.Const_UnitLevel_LiteralValue;
var
  C : TRdxSqlConst;
begin
  C := ConstIn(EntGenUnit(['  TEST_TABLE_AUDIT   = ''entgen_test_audit'';',
    '  TEST_TABLE_SOFTDEL = ''entgen_test_softdel'';'], USE_LINE),
    'TEST_TABLE_SOFTDEL', 'FConn.ExecSQL');
  Assert.IsTrue(C.Kind = sckLiteral, 'Konstante mit einfachem Literal');
  Assert.AreEqual('entgen_test_softdel', C.Value);
  // Gross/klein spielt keine Rolle.
  C := ConstIn(EntGenUnit(['  Test_Table_SoftDel = ''x'';'], USE_LINE),
    'TEST_TABLE_SOFTDEL', 'FConn.ExecSQL');
  Assert.AreEqual('x', C.Value);
end;

procedure TTestRdxSqlFacts.Const_InterfaceSection_Visible;
var
  Src : string;
begin
  Src := Join(['unit u;', 'interface', 'const', '  TBL = ''users'';',
    'procedure Run;', 'implementation', 'procedure Run;', 'var S: string;',
    'begin', '  S := ''SELECT * FROM '' + TBL;', 'end;', 'end.']);
  Assert.AreEqual('users', ConstIn(Src, 'TBL', 'S :=').Value);
end;

procedure TTestRdxSqlFacts.Const_UpperCaseNameAlone_NotProven;
begin
  // Ein Name in Grossbuchstaben ohne Deklaration in der Datei (aus einer
  // anderen Unit) beweist nichts.
  Assert.IsTrue(ConstIn(EntGenUnit(['  OTHER = ''y'';'], USE_LINE),
    'TEST_TABLE_SOFTDEL', 'FConn.ExecSQL').Kind = sckNone);
  Assert.IsTrue(ConstIn(EntGenUnit(['  OTHER = ''y'';'], USE_LINE),
    'AColumnTypes', 'FConn.ExecSQL').Kind = sckNone, 'Parameter');
end;

procedure TTestRdxSqlFacts.Const_ShadowedByParamOrField_NotProven;
var
  Src : string;
begin
  // Derselbe Name als Parameter einer anderen Routine bzw. als Feld:
  // welcher gemeint ist, sieht der Text nicht sicher.
  Src := Join(['unit u;', 'interface', 'implementation', 'const',
    '  TBL = ''users'';', 'procedure A(const TBL: string);', 'begin', 'end;',
    'procedure B;', 'var S: string;', 'begin',
    '  S := ''SELECT * FROM '' + TBL;', 'end;', 'end.']);
  Assert.IsTrue(ConstIn(Src, 'TBL', 'S :=').Kind = sckNone, 'Parameter');
  Src := Join(['unit u;', 'interface', 'type', '  TFoo = class',
    '    Tbl, Other: string;', '  end;', 'implementation', 'const',
    '  TBL = ''users'';', 'procedure B;', 'var S: string;', 'begin',
    '  S := ''SELECT * FROM '' + TBL;', 'end;', 'end.']);
  Assert.IsTrue(ConstIn(Src, 'TBL', 'S :=').Kind = sckNone, 'Feld in Liste');
end;

procedure TTestRdxSqlFacts.Const_TypedConst_NotProven;
begin
  // Eine typisierte Konstante ist mit {$J+} schreibbar.
  Assert.IsTrue(ConstIn(EntGenUnit(['  TEST_TABLE_SOFTDEL: string = ''x'';'],
    USE_LINE), 'TEST_TABLE_SOFTDEL', 'FConn.ExecSQL').Kind = sckNone);
end;

procedure TTestRdxSqlFacts.Const_NonSimpleValue_Kept;
begin
  Assert.IsTrue(ConstIn(EntGenUnit(['  TEST_TABLE_SOFTDEL = ''a'' + ''b'';'],
    USE_LINE), 'TEST_TABLE_SOFTDEL', 'FConn.ExecSQL').Kind = sckKept);
  Assert.IsTrue(ConstIn(EntGenUnit(['  OTHER = ''y'';',
    '  TEST_TABLE_SOFTDEL = OTHER;'], USE_LINE), 'TEST_TABLE_SOFTDEL',
    'FConn.ExecSQL').Kind = sckKept);
  // Steuerzeichen sind ein einfaches Literal.
  Assert.AreEqual('a'#13#10'b', ConstIn(EntGenUnit(
    ['  TEST_TABLE_SOFTDEL = ''a''#13#10''b'';'], USE_LINE),
    'TEST_TABLE_SOFTDEL', 'FConn.ExecSQL').Value);
end;

procedure TTestRdxSqlFacts.Const_LocalOfOtherRoutine_NotVisible;
var
  Src : string;
begin
  // A hat eine lokale Konstante TBL; in B meint TBL etwas anderes (eine
  // andere Unit) - dort ist sie nicht sichtbar.
  Src := Join(['unit u;', 'interface', 'implementation',
    'procedure A;', 'const', '  TBL = ''a_local'';', 'var S: string;',
    'begin', '  S := ''SELECT 1 FROM '' + TBL; // in A', 'end;', '',
    'procedure B;', 'var S: string;', 'begin',
    '  S := ''SELECT 2 FROM '' + TBL; // in B', 'end;', 'end.']);
  Assert.AreEqual('a_local', ConstIn(Src, 'TBL', '// in A').Value);
  Assert.IsTrue(ConstIn(Src, 'TBL', '// in B').Kind = sckNone);
end;

procedure TTestRdxSqlFacts.Const_DeclaredAfterUse_NotVisible;
var
  Src : string;
begin
  Src := Join(['unit u;', 'interface', 'implementation', 'procedure B;',
    'var S: string;', 'begin', '  S := ''SELECT * FROM '' + TBL;', 'end;',
    'const', '  TBL = ''users'';', 'end.']);
  Assert.IsTrue(ConstIn(Src, 'TBL', 'S :=').Kind = sckNone);
end;

procedure TTestRdxSqlFacts.Const_TwoBranches_SameOrDifferent;
begin
  Assert.AreEqual('t', ConstIn(EntGenUnit(['{$IFDEF PG}',
    '  TEST_TABLE_SOFTDEL = ''t'';', '{$ELSE}', '  TEST_TABLE_SOFTDEL = ''t'';',
    '{$ENDIF}'], USE_LINE), 'TEST_TABLE_SOFTDEL', 'FConn.ExecSQL').Value);
  Assert.IsTrue(ConstIn(EntGenUnit(['{$IFDEF PG}',
    '  TEST_TABLE_SOFTDEL = ''pg'';', '{$ELSE}', '  TEST_TABLE_SOFTDEL = ''fb'';',
    '{$ENDIF}'], USE_LINE), 'TEST_TABLE_SOFTDEL', 'FConn.ExecSQL').Kind = sckKept);
end;

procedure TTestRdxSqlFacts.FireDac_UsesAndTypeProven;
var
  Src : string;
begin
  Src := EntGenUnit(['  X = 1;'], USE_LINE);
  Assert.IsTrue(FireDacIn(Src, 'FConn', ['FireDAC.Comp.Client']));
  Assert.IsTrue(FireDacIn(Src, 'Self.FConn', ['System.SysUtils',
    'FireDAC.Comp.Client']), 'Self. davor');
  // Qualifizierter Typ und Liste 'A, B: T'.
  Src := Join(['unit u;', 'interface', 'var', '  C1, FConn: FireDAC.Comp.Client.TFDConnection;',
    'implementation', 'end.']);
  Assert.IsTrue(FireDacIn(Src, 'FConn', ['FireDAC.Comp.Client']));
end;

procedure TTestRdxSqlFacts.FireDac_OtherTypeOrNoUses_NotProven;
var
  Src : string;
begin
  Src := EntGenUnit(['  X = 1;'], USE_LINE);
  Assert.IsFalse(FireDacIn(Src, 'FConn', ['Data.DB']), 'ohne FireDAC.Comp.Client');
  Assert.IsFalse(FireDacIn(Src, 'Other', ['FireDAC.Comp.Client']),
    'nicht deklariert');
  Assert.IsFalse(FireDacIn(Src, 'DM.FConn', ['FireDAC.Comp.Client']),
    'kein blosser Bezeichner');
  // Ein zweites FConn mit anderem Typ (andere Klasse).
  Src := StringReplace(Src, '  end;', '  end;' + #13#10 + '  TOther = class'
    + #13#10 + '    FConn: TADOConnection;' + #13#10 + '  end;', []);
  Assert.IsFalse(FireDacIn(Src, 'FConn', ['FireDAC.Comp.Client']), 'zwei Typen');
end;

procedure TTestRdxSqlFacts.ExecSqlReceiver_Forms;
begin
  Assert.AreEqual('FConn', ExecSqlReceiverOf('FConn.ExecSQL'));
  Assert.AreEqual('Self.FConn', ExecSqlReceiverOf(' Self.FConn.execsql '));
  Assert.AreEqual('', ExecSqlReceiverOf('Q.SQL.Add'));
  Assert.AreEqual('', ExecSqlReceiverOf('ExecSQL'));
end;

procedure TTestRdxSqlFacts.ParamName_FromOperand;
begin
  Assert.AreEqual('ColumnTypes', SqlParamName('AColumnTypes'));
  Assert.AreEqual('Id', SqlParamName('FId'));
  Assert.AreEqual('Edit1Text', SqlParamName('Edit1.Text'));
  Assert.AreEqual('Id', SqlParamName('IntToStr(Id)'));
  Assert.AreEqual('Name', SqlParamName('Self.FName'));
  Assert.AreEqual('Edit1Text', SqlParamName('Trim(Edit1.Text)'));
  Assert.AreEqual('X', SqlParamName('''%'' + X + ''%'''));
  Assert.AreEqual('ObjItemsName', SqlParamName('Obj.Items[i].Name'));
  // Ein Kuerzel bleibt: ADOQuery1, FDQuery1.
  Assert.AreEqual('ADOQuery1Text', SqlParamName('ADOQuery1.Text'));
  Assert.AreEqual('FDQuery1Value', SqlParamName('FDQuery1.Value'));
  // Nur Buchstaben, Ziffern, '_' - ein Umlaut macht den Namen leer (dann
  // pN; Gegen-Review S1, Minor 3: bis Charge SQc 'Gre').
  Assert.AreEqual('', SqlParamName('Gr' + #$00F6 + 'e'));
end;

procedure TTestRdxSqlFacts.ParamName_ReservedAndFallback;
begin
  Assert.AreEqual('pDate', SqlParamName('ADate'));
  Assert.AreEqual('pLevel', SqlParamName('Level'));
  Assert.AreEqual('', SqlParamName('''abc'''));
  Assert.AreEqual('', SqlParamName('#13#10'));
  Assert.AreEqual<Integer>(30, Length(SqlParamName(StringOfChar('x', 50))));
end;

procedure TTestRdxSqlFacts.Placeholders_Sca199Rules;
var
  P : TArray<string>;
begin
  P := SqlPlaceholders('SELECT * FROM t WHERE a = :A AND b=:b_2 AND c::int = 1 '
    + 'AND d := 1 AND e = :1 AND f = '':no'' AND g = "x:no" AND :new.x = 1 '
    + 'AND t[1]:no AND 10:30 -- :incomment');
  Assert.AreEqual<Integer>(3, Length(P), 'a, b_2, incomment');
  Assert.AreEqual('a', P[0]);
  Assert.AreEqual('b_2', P[1]);
  Assert.AreEqual('incomment', P[2]);
end;

procedure TTestRdxSqlFacts.AddSqlFacts_ConstsAndBinding;
var
  Src : string;
  SL  : TStringList;
  Map : TRdxCodeMap;
  R   : TRdxSqlRequest;
  L   : Integer;
begin
  Src := EntGenUnit(['  TEST_TABLE_SOFTDEL = ''entgen_test_softdel'';'], USE_LINE);
  L := LineOf(Src, 'FConn.ExecSQL');
  R := Default(TRdxSqlRequest);
  R.Target := 'FConn.ExecSQL';
  R.IsCall := True;
  R.Parts := [TRdxRecipes.MakePart(ROLE_TARGET, 'FConn.ExecSQL'),
    TRdxRecipes.MakePart(ROLE_LITERAL, '''CREATE TABLE '''),
    TRdxRecipes.MakePart(ROLE_OPERAND, 'TEST_TABLE_SOFTDEL'),
    TRdxRecipes.MakePart(ROLE_OPERAND, 'AColumnTypes')];
  R.PartLines := [L, L, L, L];
  R.UsesNames := ['FireDAC.Comp.Client'];
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Src;
    Map := TRdxCodeMap.Create(SL);
    AddSqlFacts(Map, R);
    Assert.IsTrue(R.Consts[2].Kind = sckLiteral);
    Assert.AreEqual('entgen_test_softdel', R.Consts[2].Value);
    Assert.IsTrue(R.Consts[3].Kind = sckNone, 'Parameter der Routine');
    Assert.IsTrue(R.Binding = sbFireDacExecSql);
    // Im with-Block ist kein Name bewiesen.
    R.Consts := nil;
    R.Binding := sbByTarget;
    R.InWith := True;
    AddSqlFacts(Map, R);
    Assert.IsTrue(R.Consts[2].Kind = sckNone, 'with');
    Assert.IsTrue(R.Binding = sbByTarget, 'with');
  finally
    Map.Free;
    SL.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxSqlFacts);

end.
