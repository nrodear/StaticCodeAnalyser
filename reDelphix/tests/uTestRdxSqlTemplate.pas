unit uTestRdxSqlTemplate;

// Tests fuer Rezept 5.2, die SQL-Vorlage zu SCA003 (uRdxSqlTemplate,
// Charge S1). Reine Textlogik - laufen unter DUnitX in Delphi und im
// FPC-Pruefstand. Die Fakten am Quelltext (Konstanten, FireDAC) setzen die
// Tests hier von Hand; ihre Nachweise pinnt uTestRdxSqlFacts.
//
// Die ersten sechs Tests standen bis Charge S1 in uTestRdxRecipes
// (SqlTemplate_*) mit ':p1'-Namen; die uebrigen waren gegen den Stand
// e788e0c7 rot (Nicos Fall: DDL, Konstante, Ziel ohne Query-Objekt).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxSqlTemplate = class
  public
    // ---- bis Charge S1 in uTestRdxRecipes ----
    [Test] procedure Assign_ValueParam_NamedFromOperand;
    [Test] procedure Call_TwoParams;
    [Test] procedure QuotedParam_Unquoted;
    [Test] procedure ArgumentRole_Blocked;
    [Test] procedure PlainStringTarget_CommentForm;
    [Test] procedure TabIndent_KeepsTabs;
    // ---- Charge S1: Position, Konstanten, Ziel, Namen ----
    [Test] procedure Nico_DdlWithConstant_Refused;
    [Test] procedure FromTable_Refused;
    [Test] procedure OrderByAndSelectList_Refused;
    [Test] procedure Constant_InlinedOrKept;
    [Test] procedure OnlyConstantsOrNoSqlText_Refused;
    [Test] procedure LikePercent_WholeStringIsParam;
    [Test] procedure InList_ElementsAndWholeList;
    [Test] procedure ExecSql_FireDacOverloadOrRefused;
    [Test] procedure PgCast_StaysAndIsNoPlaceholder;
    [Test] procedure NameCollision_Suffix;
    [Test] procedure IdentifierGlued_Refused;
    [Test] procedure Fragment_SelfAppendAndUnknownHead;
    [Test] procedure Limit_IntToStrUnwrapped_TopRefused;
    [Test] procedure Between_AndValue_ConditionRefused;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo, uRdxRecipes, uRdxSqlTemplate;

function Lit(const AText: string): TRdxPart;
begin
  Result := TRdxRecipes.MakePart(ROLE_LITERAL, AText, rvString);
end;

function Op(const AText: string): TRdxPart;
begin
  Result := TRdxRecipes.MakePart(ROLE_OPERAND, AText, rvUnknown);
end;

function Target(const AText: string): TRdxPart;
begin
  Result := TRdxRecipes.MakePart(ROLE_TARGET, AText);
end;

// Eine Anfrage ohne Fakten am Quelltext: Ziel aus Parts[0], Zuweisung.
function Req(const AParts: TRdxParts): TRdxSqlRequest;
begin
  Result := Default(TRdxSqlRequest);
  Result.Parts  := AParts;
  Result.Target := AParts[0].Text;
end;

function CallReq(const AParts: TRdxParts): TRdxSqlRequest;
begin
  Result := Req(AParts);
  Result.IsCall := True;
end;

// Konstante mit einfachem Wert bzw. mit stehendem Ausdruck am Part AIndex.
procedure SetConst(var AReq: TRdxSqlRequest; AIndex: Integer;
  AKind: TRdxSqlConstKind; const AValue: string);
begin
  if Length(AReq.Consts) < Length(AReq.Parts) then
    SetLength(AReq.Consts, Length(AReq.Parts));
  AReq.Consts[AIndex].Kind  := AKind;
  AReq.Consts[AIndex].Value := AValue;
end;

function Built(const AReq: TRdxSqlRequest): TRdxSqlTemplate;
begin
  BuildSqlTemplate(AReq, Result);
end;

// Gebaut; die Vorlage.
function Ok(const AReq: TRdxSqlRequest): string;
var
  R : TRdxSqlTemplate;
begin
  Assert.IsTrue(BuildSqlTemplate(AReq, R), R.Reason);
  Result := R.Text;
end;

// Abgelehnt; der Grund muss APart enthalten.
procedure AssertRefused(const AReq: TRdxSqlRequest; const APart: string);
var
  R : TRdxSqlTemplate;
begin
  Assert.IsFalse(BuildSqlTemplate(AReq, R), R.Text);
  Assert.AreEqual('', R.Text);
  Assert.IsTrue(Pos(APart, R.Reason) > 0, R.Reason);
end;

{ ---- bis Charge S1 in uTestRdxRecipes ---- }

procedure TTestRdxSqlTemplate.Assign_ValueParam_NamedFromOperand;
var
  R : TRdxSqlRequest;
begin
  R := Req([Target('Query.SQL.Text'),
    Lit('''SELECT * FROM users WHERE id = '''), Op('Id')]);
  R.Indent := '  ';
  Assert.AreEqual(
    '  Query.SQL.Text := ''SELECT * FROM users WHERE id = :Id'';' + sLineBreak +
    '  Query.ParamByName(''Id'').Value := Id;', Ok(R));
  Assert.AreEqual('1 Parameter, nichts wird geschrieben', SqlHintOf(Built(R)));
end;

procedure TTestRdxSqlTemplate.Call_TwoParams;
begin
  Assert.AreEqual(
    'Query.SQL.Add(''SELECT * FROM t WHERE a = :A AND b = :B'');' + sLineBreak +
    'Query.ParamByName(''A'').Value := A;' + sLineBreak +
    'Query.ParamByName(''B'').Value := B;',
    Ok(CallReq([Target('Query.SQL.Add'), Lit('''SELECT * FROM t WHERE a = '''),
      Op('A'), Lit(''' AND b = '''), Op('B')])));
end;

procedure TTestRdxSqlTemplate.QuotedParam_Unquoted;
var
  T : string;
begin
  // WHERE name=''' + Name + '''' -> der ganze SQL-String wird EIN
  // Parameter, ohne Quotes.
  T := Ok(Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM u WHERE name='''''''), Op('Name'), Lit('''''''''')]));
  Assert.IsTrue(Pos('WHERE name=:Name''', T) > 0, T);
  Assert.IsFalse(Pos(''':Name''', T) > 0, 'kein Parameter in Quotes');
  Assert.IsTrue(Pos('Q.ParamByName(''Name'').Value := Name;', T) > 0, T);
end;

procedure TTestRdxSqlTemplate.ArgumentRole_Blocked;
begin
  AssertRefused(CallReq([Target('ExecuteFmt'),
    TRdxRecipes.MakePart(ROLE_ARGUMENT, '''x'''),
    TRdxRecipes.MakePart(ROLE_ARGUMENT, '[a]')]), 'Argument');
end;

procedure TTestRdxSqlTemplate.PlainStringTarget_CommentForm;
var
  R : TRdxSqlRequest;
begin
  // SCA003 meldet auch einen String-Puffer: 'S.ParamByName' uebersetzte
  // nicht - die Bindung steht als klare Kommentarzeile da (bis Charge S1
  // '// <Query>.ParamByName', Pseudocode).
  R := Req([Target('S'), Lit('''SELECT * FROM t WHERE id='''), Op('FId')]);
  R.Indent := '  ';
  Assert.AreEqual(
    '  S := ''SELECT * FROM t WHERE id=:Id'';' + sLineBreak +
    '  // Parameter binden: ParamByName(''Id'').Value := FId;', Ok(R));
end;

procedure TTestRdxSqlTemplate.TabIndent_KeepsTabs;
var
  R : TRdxSqlRequest;
begin
  // Die Einrueckung kommt als Text: zwei Tabs bleiben zwei Tabs, auch vor
  // den ParamByName-Zeilen (Minor 31).
  R := Req([Target('Q.SQL.Text'), Lit('''SELECT * FROM t WHERE id='''),
    Op('Id')]);
  R.Indent := #9#9;
  Assert.AreEqual(
    #9#9'Q.SQL.Text := ''SELECT * FROM t WHERE id=:Id'';' + sLineBreak +
    #9#9'Q.ParamByName(''Id'').Value := Id;', Ok(R));
  // Gemischt bleibt gemischt; was kein Tab ist, wird ein Leerzeichen.
  Assert.AreEqual('  '#9, TRdxRecipes.IndentTextOf('  '#9));
  Assert.AreEqual('  '#9' ', TRdxRecipes.IndentTextOf('ab'#9'c'));
  Assert.AreEqual('', TRdxRecipes.IndentTextOf(''));
end;

{ ---- Charge S1 ---- }

procedure TTestRdxSqlTemplate.Nico_DdlWithConstant_Refused;
var
  R : TRdxSqlRequest;
begin
  // delphimvcframework EntGenTestsU.pas: bis Charge S1
  // 'CREATE TABLE :p1 (  id BIGSERIAL PRIMARY KEY, :p2)' mit
  // '// <Query>.ParamByName'. DDL hat keine Parameter - auch mit
  // nachgewiesener FireDAC-Verbindung und Konstante nicht.
  R := CallReq([Target('FConn.ExecSQL'), Lit('''CREATE TABLE '''),
    Op('TEST_TABLE_SOFTDEL'), Lit(''' ('''),
    Lit('''  id BIGSERIAL PRIMARY KEY, '''), Op('AColumnTypes'), Lit(''')''')]);
  SetConst(R, 2, sckLiteral, 'entgen_test_softdel');
  R.Binding := sbFireDacExecSql;
  AssertRefused(R, 'DDL/DCL (CREATE ...)');
  AssertRefused(R, 'Namen pruefen/Whitelist');
  // Ohne Nachweise ebenso - der Inhalt entscheidet vor dem Ziel.
  AssertRefused(CallReq(R.Parts), 'DDL/DCL (CREATE ...)');
  // ALTER/DROP/GRANT ebenso.
  AssertRefused(Req([Target('S'), Lit('''ALTER USER '''), Op('U'),
    Lit(''' IDENTIFIED BY '''), Op('P')]), 'DDL/DCL (ALTER ...)');
end;

procedure TTestRdxSqlTemplate.FromTable_Refused;
begin
  AssertRefused(Req([Target('Q.SQL.Text'), Lit('''SELECT * FROM '''),
    Op('Tbl')]), 'steht hinter ''from''');
  AssertRefused(Req([Target('Q.SQL.Text'), Lit('''INSERT INTO '''),
    Op('Tbl'), Lit(''' (a) VALUES (1)''')]), 'steht hinter ''into''');
  AssertRefused(Req([Target('Q.SQL.Text'), Lit('''UPDATE '''), Op('Tbl'),
    Lit(''' SET a = 1 WHERE id = 2''')]), 'steht hinter ''update''');
  // Nur der Wert ist Parameter - eine Tabelle davor sperrt die Vorlage
  // ganz (eine halbe Vorlage liesse die Injection stehen).
  AssertRefused(Req([Target('Q.SQL.Text'), Lit('''SELECT * FROM '''),
    Op('Tbl'), Lit(''' WHERE id = '''), Op('Id')]), 'Namen pruefen/Whitelist');
end;

procedure TTestRdxSqlTemplate.OrderByAndSelectList_Refused;
begin
  AssertRefused(Req([Target('S'), Lit('''SELECT * FROM t ORDER BY '''),
    Op('Col')]), 'steht hinter ''by''');
  AssertRefused(Req([Target('S'), Lit('''SELECT '''), Op('Cols'),
    Lit(''' FROM t''')]), 'steht hinter ''select''');
  // Spaltenliste eines INSERT: '(' hinter dem Tabellennamen.
  AssertRefused(Req([Target('S'), Lit('''INSERT INTO t ('''), Op('Cols'),
    Lit(''') VALUES (1)''')]), 'steht hinter ''(''');
  // Funktionsargument: kann eine Spalte sein.
  AssertRefused(Req([Target('S'), Lit('''SELECT MAX('''), Op('Col'),
    Lit(''') FROM t''')]), 'steht hinter ''(''');
end;

procedure TTestRdxSqlTemplate.Constant_InlinedOrKept;
var
  R : TRdxSqlRequest;
begin
  // Eine Konstante mit einfachem Wert kommt in den Text - auch an einer
  // Bezeichner-Position; nur der Wert wird Parameter.
  R := Req([Target('Q.SQL.Text'), Lit('''SELECT * FROM '''), Op('TBL_USERS'),
    Lit(''' WHERE id = '''), Op('Id')]);
  SetConst(R, 2, sckLiteral, 'users');
  Assert.AreEqual(
    'Q.SQL.Text := ''SELECT * FROM users WHERE id = :Id'';' + sLineBreak +
    'Q.ParamByName(''Id'').Value := Id;', Ok(R));
  Assert.AreEqual('1 Parameter, 1 Konstante(n) im Text, nichts wird geschrieben',
    SqlHintOf(Built(R)));
  // Ohne einfachen Wert bleibt die Verkettung stehen.
  SetConst(R, 2, sckKept, '');
  Assert.AreEqual(
    'Q.SQL.Text := ''SELECT * FROM '' + TBL_USERS + '' WHERE id = :Id'';'
    + sLineBreak + 'Q.ParamByName(''Id'').Value := Id;', Ok(R));
  // sLineBreak bleibt als Verkettung und ist im SQL Leerraum.
  Assert.AreEqual(
    'Q.SQL.Text := ''SELECT * FROM t'' + sLineBreak + ''WHERE id = :Id'';'
    + sLineBreak + 'Q.ParamByName(''Id'').Value := Id;',
    Ok(Req([Target('Q.SQL.Text'), Lit('''SELECT * FROM t'''), Op('sLineBreak'),
      Lit('''WHERE id = '''), Op('Id')])));
end;

procedure TTestRdxSqlTemplate.OnlyConstantsOrNoSqlText_Refused;
var
  R : TRdxSqlRequest;
begin
  R := Req([Target('S'), Lit('''DROP TABLE IF EXISTS '''), Op('TEST_TABLE')]);
  SetConst(R, 2, sckLiteral, 'entgen_test');
  AssertRefused(R, 'nur Konstanten - kein Injection-Risiko');
  SetConst(R, 2, sckKept, '');
  AssertRefused(R, 'nur Konstanten - kein Injection-Risiko');
  // LineEnding/sLineBreak sind Konstanten der RTL (Lazarus-Korpus:
  // ExecuteDirect('CREATE TABLE ..' + LineEnding + '-- ..')).
  AssertRefused(Req([Target('S'), Lit('''CREATE TABLE t'''), Op('LineEnding'),
    Lit('''-- x''')]), 'nur Konstanten');
  // Ohne SQL-Literal entsteht der Text anderswo (mORMot FormatUtf8,
  // HeidiSQL GetResults(..), Memo.Lines.Text + #13#10) - bis Charge S1
  // 'S := '':p1''' mit dem ganzen Aufruf als Wert.
  // noinspection SQLInjection (Testdaten: der Operand IST der Format-Aufruf)
  AssertRefused(Req([Target('sql'), Op('FormatUtf8(''CREATE INDEX %'', [a])')]),
    'kein SQL-Text in der Kette');
  AssertRefused(Req([Target('Q.SQL.Text'), Op('Memo.Lines.Text'), Lit('#13#10')]),
    'kein SQL-Text in der Kette');
end;

procedure TTestRdxSqlTemplate.LikePercent_WholeStringIsParam;
begin
  // '%' + X + '%' in einem SQL-String: der ganze String wird EIN Parameter,
  // sein Wert der zusammengesetzte Ausdruck.
  Assert.AreEqual(
    'Q.SQL.Text := ''SELECT * FROM t WHERE name LIKE :Name'';' + sLineBreak +
    'Q.ParamByName(''Name'').Value := ''%'' + AName + ''%'';',
    Ok(Req([Target('Q.SQL.Text'), Lit('''SELECT * FROM t WHERE name LIKE ''''%'''),
      Op('AName'), Lit('''%''''''')])));
  // Ohne Leerzeichen vor dem Quote: der Parameter bekommt eins.
  Assert.IsTrue(Pos('LIKE :Name', Ok(Req([Target('S'),
    Lit('''SELECT * FROM t WHERE name LIKE''''%'''), Op('AName'),
    Lit('''%''''''')]))) > 0);
  // Ein String an einer Bezeichner-Position bleibt gesperrt.
  AssertRefused(Req([Target('S'), Lit('''SELECT * FROM t WHERE x = DATE '''''''),
    Op('D'), Lit('''''''''')]), 'steht hinter ''date''');
end;

procedure TTestRdxSqlTemplate.InList_ElementsAndWholeList;
begin
  Assert.AreEqual(
    'S := ''DELETE FROM t WHERE id IN (:A, :B)'';' + sLineBreak +
    '// Parameter binden: ParamByName(''A'').Value := A;' + sLineBreak +
    '// Parameter binden: ParamByName(''B'').Value := B;',
    Ok(Req([Target('S'), Lit('''DELETE FROM t WHERE id IN ('''), Op('A'),
      Lit(''', '''), Op('B'), Lit(''')''')])));
  // Ein Operand allein in IN (...) kann eine ganze Liste sein ('1,2,3').
  AssertRefused(Req([Target('S'), Lit('''DELETE FROM t WHERE id IN ('''),
    Op('Ids'), Lit(''')''')]), 'die ganze IN-Liste');
  AssertRefused(Req([Target('S'), Lit('''INSERT INTO t VALUES ('''),
    Op('Vals'), Lit(''')''')]), 'die ganze VALUES-Liste');
  // IntToStr(x) ist EIN Wert.
  Assert.IsTrue(Pos('IN (:N)', Ok(Req([Target('S'),
    Lit('''DELETE FROM t WHERE id IN ('''), Op('IntToStr(N)'),
    Lit(''')''')]))) > 0);
end;

procedure TTestRdxSqlTemplate.ExecSql_FireDacOverloadOrRefused;
var
  R : TRdxSqlRequest;
begin
  R := CallReq([Target('FConn.ExecSQL'),
    Lit('''DELETE FROM t WHERE id = '''), Op('IntToStr(AId)'),
    Lit(''' AND name = '''''''), Op('Edit1.Text'), Lit('''''''''')]);
  R.Indent := '  ';
  // Ohne Nachweis: der Aufruf fuehrt den Text sofort aus, nichts bindet.
  AssertRefused(R, 'FConn.ExecSQL() bindet keine Parameter');
  // FireDAC nachgewiesen: TFDConnection.ExecSQL(ASQL, AParams).
  R.Binding := sbFireDacExecSql;
  Assert.AreEqual(
    '  FConn.ExecSQL(''DELETE FROM t WHERE id = :Id AND name = :Edit1Text'', '
    + '[AId, Edit1.Text]);', Ok(R));
  // Ein Platzhalter im Text macht die Reihenfolge der Werte unklar.
  R := CallReq([Target('FConn.ExecSQL'),
    Lit('''DELETE FROM t WHERE a = :a AND id = '''), Op('Id')]);
  R.Binding := sbFireDacExecSql;
  AssertRefused(R, 'schon den Platzhalter :a');
  // Andere Aufrufe ohne Query-Objekt ebenso.
  AssertRefused(CallReq([Target('Connection.Query'),
    Lit('''SELECT * FROM t WHERE id = '''), Op('Id')]), 'bindet keine Parameter');
end;

procedure TTestRdxSqlTemplate.PgCast_StaysAndIsNoPlaceholder;
begin
  // '::' ist ein PostgreSQL-Cast, kein Platzhalter (SCA199) - er bleibt,
  // und 'date' ist danach kein vergebener Name.
  Assert.AreEqual(
    'S := ''SELECT created::date FROM t WHERE day = :pDate'';' + sLineBreak +
    '// Parameter binden: ParamByName(''pDate'').Value := ADate;',
    Ok(Req([Target('S'), Lit('''SELECT created::date FROM t WHERE day = '''),
      Op('ADate')])));
  Assert.AreEqual<Integer>(0, Length(SqlPlaceholders('SELECT x::int, y := 1, z:1')));
end;

procedure TTestRdxSqlTemplate.NameCollision_Suffix;
var
  T : string;
begin
  // Ein vorhandener Platzhalter :Id (auch HINTER dem Operanden) und
  // derselbe Operand zweimal: Id2, Id3.
  T := Ok(Req([Target('Q.SQL.Text'), Lit('''SELECT * FROM t WHERE a = '''),
    Op('Id'), Lit(''' OR b = '''), Op('FId'), Lit(''' OR c = :id''')]));
  Assert.IsTrue(Pos('WHERE a = :Id2 OR b = :Id3 OR c = :id', T) > 0, T);
  Assert.IsTrue(Pos('Q.ParamByName(''Id2'').Value := Id;', T) > 0, T);
  Assert.IsTrue(Pos('Q.ParamByName(''Id3'').Value := FId;', T) > 0, T);
  // Ohne Pfad, der kein Aufrufkopf ist: der Aufrufkopf.
  Assert.IsTrue(Pos('WHERE a = :Get', Ok(Req([Target('S'),
    Lit('''SELECT * FROM t WHERE a = '''), Op('Get()[0]')]))) > 0);
end;

procedure TTestRdxSqlTemplate.IdentifierGlued_Refused;
begin
  AssertRefused(Req([Target('S'), Lit('''SELECT * FROM t WHERE col_'''),
    Op('X'), Lit(''' = 1''')]), 'ist Teil eines Bezeichners');
  AssertRefused(Req([Target('S'), Lit('''SELECT * FROM t WHERE a = '''),
    Op('X'), Lit('''_tmp''')]), 'ist Teil eines Bezeichners');
  AssertRefused(Req([Target('S'), Lit('''SELECT * FROM t WHERE a = s.'''),
    Op('X')]), 'ist Teil eines Bezeichners');
  AssertRefused(Req([Target('S'), Lit('''SELECT * FROM t WHERE "'''),
    Op('X'), Lit('''" = 1''')]), 'in einem gequoteten Namen');
  AssertRefused(Req([Target('S'), Lit('''SELECT * FROM t -- '''),
    Op('X')]), 'in einem SQL-Kommentar');
end;

procedure TTestRdxSqlTemplate.Fragment_SelfAppendAndUnknownHead;
begin
  // 'S := S + ..' - der bisherige Text bleibt stehen, ein WHERE/AND-
  // Bruchstueck darf Werte binden.
  Assert.AreEqual(
    'SQL := SQL + '' AND id = :Id'';' + sLineBreak +
    '// Parameter binden: ParamByName(''Id'').Value := Id;',
    Ok(Req([Target('SQL'), Op('SQL'), Lit(''' AND id = '''), Op('Id')])));
  // 'ENGINE=' in einem CREATE TABLE: ob '=' einen Wert erwartet, ist am
  // Bruchstueck nicht zu sehen.
  AssertRefused(Req([Target('SQL'), Op('SQL'), Lit('''ENGINE='''),
    Op('comboEngine.Text')]), 'Anweisungsart unbekannt (''engine'')');
  // Ein Operand ganz vorn ist kein Wert.
  AssertRefused(Req([Target('S'), Op('Prefix'), Lit(''' WHERE a = 1''')]),
    'steht am Anfang des SQL-Texts');
  // Mehrere Anweisungen: die zweite ist DDL.
  AssertRefused(Req([Target('S'), Lit('''SELECT 1; DROP TABLE '''),
    Op('T')]), 'DDL/DCL (DROP ...)');
  // Das Ziel weiter hinten ist ein Operand wie jeder (mORMot 'sql :=
  // ''insert into '' + sql + '' default values;''' - bis zur Korpusprobe
  // als "nur Konstanten" gewertet).
  AssertRefused(Req([Target('sql'), Lit('''insert into '''), Op('sql'),
    Lit(''' default values;''')]), 'steht hinter ''into''');
  // Direkt hinter dem bisherigen Text ist nicht sichtbar, ob ein Wert
  // folgt (HeidiSQL 'SQL := SQL + Column + ''='' + ..').
  AssertRefused(Req([Target('SQL'), Op('SQL'), Op('Column'), Lit('''=1''')]),
    'folgt direkt auf ''SQL''');
  // Beginnt der Text nicht mit einem Wort, ist er keine Anweisung
  // bekannter Art ('?select=' + X ist eine URL, mORMot).
  AssertRefused(Req([Target('u'), Lit('''?select='''), Op('X')]),
    'Anweisungsart unbekannt (''?'')');
end;

procedure TTestRdxSqlTemplate.Limit_IntToStrUnwrapped_TopRefused;
begin
  // IntToStr(x) bindet x (eine Zahl, kein Text) - LIMIT/OFFSET nehmen
  // Parameter.
  Assert.AreEqual(
    'Q.SQL.Text := ''SELECT * FROM t LIMIT :Count OFFSET :Skip'';' + sLineBreak +
    'Q.ParamByName(''Count'').Value := ACount;' + sLineBreak +
    'Q.ParamByName(''Skip'').Value := FSkip;',
    Ok(Req([Target('Q.SQL.Text'), Lit('''SELECT * FROM t LIMIT '''),
      Op('IntToStr(ACount)'), Lit(''' OFFSET '''), Op('SysUtils.IntToStr(FSkip)')])));
  // TOP (SQL Server ohne Klammern, Access) nimmt nur eine Zahl.
  AssertRefused(Req([Target('S'), Lit('''SELECT TOP '''), Op('N'),
    Lit(''' * FROM t''')]), 'steht hinter ''top''');
  // QuotedStr(x) bindet x - der Parameter braucht die Quotes nicht.
  Assert.IsTrue(Pos('ParamByName(''Name'').Value := Name;',
    Ok(Req([Target('S'), Lit('''SELECT * FROM t WHERE n = '''),
      Op('QuotedStr(Name)')]))) > 0);
end;

procedure TTestRdxSqlTemplate.Between_AndValue_ConditionRefused;
begin
  Assert.IsTrue(Pos('WHERE d BETWEEN :Min AND :Max', Ok(Req([Target('S'),
    Lit('''SELECT * FROM t WHERE d BETWEEN '''), Op('AMin'),
    Lit(''' AND '''), Op('AMax')]))) > 0);
  // Ein AND ohne BETWEEN verbindet Bedingungen - dahinter steht keine.
  AssertRefused(Req([Target('S'), Lit('''SELECT * FROM t WHERE a = 1 AND '''),
    Op('Cond')]), 'steht hinter ''and''');
  AssertRefused(Req([Target('S'), Lit('''SELECT * FROM t WHERE '''),
    Op('Cond')]), 'steht hinter ''where''');
end;

end.
