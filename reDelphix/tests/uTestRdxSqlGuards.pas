unit uTestRdxSqlGuards;

// Tests fuer die Nacharbeit des Gegen-Reviews der SQL-Vorlage (Charge SQc,
// uRdxSqlTemplate): die Fixtures des Pruefers (sql1/sql2/e2e) als Tests -
// Inline-Variable verdeckt die Konstante (Blocker), Sichtbarkeit ueber
// Routinen-, Block- und Klassengrenzen (Minor 5), der Name der Konstante
// bleibt stehen (Major 1), die DDL-Sperre gilt fuer den Rest des Texts und
// die Kette 'Q.SQL.Add' (Major 2, Verdacht a), ganze Liste in Quotes und
// Join-Bedingung (Minor 1), Namen (Minor 2, 3), Fehlablehnungen (Minor 10),
// ADO (Minor 11), LIMIT/OFFSET (Verdacht b), '?' (Verdacht c). Reine
// Textlogik - laeuft in reDelphix.Test UND im FPC-Pruefstand. Nur die
// Schnittstelle, die es vor der Charge gab (BuildSqlTemplate, SqlConstOf,
// AddSqlFacts, SqlParamName, SqlHintOf): jeder Test war gegen den Stand
// b1d16991 rot.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxSqlGuards = class
  public
    [Test] procedure Blocker_InlineVar_ShadowsConst;
    [Test] procedure Blocker_ForVar_ShadowsConst;
    [Test] procedure Blocker_OnHandlerVar_ShadowsConst;
    [Test] procedure Scope_NestedRoutineConst_NotInOuter;
    [Test] procedure Scope_InlineConst_NotProven;
    [Test] procedure Scope_ClassConst_OnlyInItsMethods;
    [Test] procedure Major1_ConstNameStays;
    [Test] procedure Major1_ConstCutOrGlued_Refused;
    [Test] procedure Major1_KeptConstBehindOperand_Refused;
    [Test] procedure Major2_DdlLock_RestOfText;
    [Test] procedure Major2_Chain_PreviousAddLines;
    [Test] procedure VerdachtA_Chain_NamesReserved;
    [Test] procedure Minor1_QuotedWholeList_Refused;
    [Test] procedure Minor1_JoinOn_BareOperandRefused;
    [Test] procedure Minor2_ReservedNamesAndLength;
    [Test] procedure Minor3_NonAsciiName_Fallback;
    [Test] procedure Minor10_CommentNationalCastValues;
    [Test] procedure Minor11_AdoParameters;
    [Test] procedure VerdachtB_LimitOffset_OnlyIntToStr;
    [Test] procedure VerdachtC_QuestionMark_Refused;
  end;

implementation

uses
  System.Classes,
  uRefactorInfo, uRdxRecipes, uRdxCodeMap, uRdxSqlTemplate,
  uTestRdxTextKit;   // Join, LineOf

// ---- Helfer ----

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

// Konstante mit einfachem Wert am Part AIndex.
procedure SetConst(var AReq: TRdxSqlRequest; AIndex: Integer;
  const AValue: string);
begin
  if Length(AReq.Consts) < Length(AReq.Parts) then
    SetLength(AReq.Consts, Length(AReq.Parts));
  AReq.Consts[AIndex].Kind  := sckLiteral;
  AReq.Consts[AIndex].Value := AValue;
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
  Assert.IsTrue(Pos(APart, R.Reason) > 0, R.Reason);
end;

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

// Wie der Laeufer (SqlRequestOf): die Anweisung AReq auf der Zeile mit
// AMarker (alle Parts dort), AddSqlFacts auf ASource, dann BuildSqlTemplate.
function FactsBuilt(const ASource, AMarker: string; const AReq: TRdxSqlRequest;
  out ATemplate: TRdxSqlTemplate): Boolean;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  R   : TRdxSqlRequest;
  i   : Integer;
begin
  R := AReq;
  SetLength(R.PartLines, Length(R.Parts));
  for i := 0 to High(R.Parts) do
    R.PartLines[i] := LineOf(ASource, AMarker);
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    AddSqlFacts(Map, R);
    Result := BuildSqlTemplate(R, ATemplate);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Ein Aufruf als Ziel ('Q.SQL.Add(..)').
function CallReq(const AParts: TRdxParts): TRdxSqlRequest;
begin
  Result := Req(AParts);
  Result.IsCall := True;
end;

// Eine Zuweisung mit dem uses-Namen AUse.
function UsesReq(const AParts: TRdxParts; const AUse: string): TRdxSqlRequest;
begin
  Result := Req(AParts);
  SetLength(Result.UsesNames, 1);
  Result.UsesNames[0] := AUse;
end;

function UnitWithBody(const AConsts, ABody: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation', 'const']) + #13#10
    + Join(AConsts) + #13#10 + Join(['procedure P;', 'begin']) + #13#10
    + Join(ABody) + #13#10 + Join(['end;', 'end.']);
end;

{ ---- Blocker: Inline-Variable verdeckt die Konstante ---- }

procedure TTestRdxSqlGuards.Blocker_InlineVar_ShadowsConst;
var
  Src : string;
  T   : TRdxSqlTemplate;
begin
  // e2e.pas des Pruefers: bis Charge SQc "nur Konstanten - kein
  // Injection-Risiko" - Name ist im Rumpf die Eingabe aus Edit1.Text.
  Src := UnitWithBody(['  Name = ''admin'';'], ['  var Name := Edit1.Text;',
    '  Q.SQL.Text := ''SELECT * FROM users WHERE name = '''''' + Name + '''''''';']);
  Assert.IsTrue(ConstIn(Src, 'Name', 'Q.SQL.Text').Kind = sckNone, 'var :=');
  Assert.IsTrue(FactsBuilt(Src, 'Q.SQL.Text', Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM users WHERE name = '''''''), Op('Name'),
    Lit('''''''''')]), T), T.Reason);
  Assert.AreEqual('Q.SQL.Text := ''SELECT * FROM users WHERE name = :Name'';'
    + sLineBreak + 'Q.ParamByName(''Name'').Value := Name;', T.Text);
  // Typisiert war sie schon vorher eine Deklaration (c23); dazu die
  // Schleifenvariable mit abgeleitetem Typ ab 0.
  Assert.IsTrue(ConstIn(UnitWithBody(['  I = ''1'';'], ['  for var I := 0 to 9 do',
    '    S := ''x'' + I;']), 'I', 'S :=').Kind = sckNone, 'for var :=');
end;

procedure TTestRdxSqlGuards.Blocker_ForVar_ShadowsConst;
var
  Src : string;
  T   : TRdxSqlTemplate;
begin
  // 'for var TBL in Tables': bis Charge SQc schrieb die Vorlage
  // 'FROM orders' fest (sql2 c06, e2e).
  Src := UnitWithBody(['  TBL = ''orders'';'], ['  for var TBL in Tables do',
    '    Q.SQL.Text := ''SELECT * FROM '' + TBL + '' WHERE id = '' + IntToStr(Id);']);
  Assert.IsTrue(ConstIn(Src, 'TBL', 'Q.SQL.Text').Kind = sckNone);
  Assert.IsFalse(FactsBuilt(Src, 'Q.SQL.Text', Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM '''), Op('TBL'), Lit(''' WHERE id = '''),
    Op('IntToStr(Id)')]), T), T.Text);
  Assert.IsTrue(Pos('steht hinter ''from''', T.Reason) > 0, T.Reason);
end;

procedure TTestRdxSqlGuards.Blocker_OnHandlerVar_ShadowsConst;
begin
  // 'on Msg: Exception do' deklariert Msg im Handler.
  Assert.IsTrue(ConstIn(UnitWithBody(['  Msg = ''x'';'], ['  try', '  except',
    '    on Msg: Exception do', '      S := ''SELECT '' + Msg;', '  end;']),
    'Msg', 'S :=').Kind = sckNone);
end;

{ ---- Minor 5: Sichtbarkeit ---- }

procedure TTestRdxSqlGuards.Scope_NestedRoutineConst_NotInOuter;
var
  Src : string;
begin
  // sql2 c02: NAME ist lokal in Inner - im Rumpf von Outer nicht sichtbar.
  Src := Join(['unit u;', 'interface', 'implementation', 'procedure Outer;',
    '  procedure Inner;', '  const', '    NAME = ''inner'';', '  begin',
    '    S := ''A'' + NAME; // in Inner', '  end;', 'begin',
    '  Q.SQL.Text := ''SELECT * FROM t WHERE x = '' + NAME; // in Outer',
    'end;', 'end.']);
  Assert.IsTrue(ConstIn(Src, 'NAME', '// in Outer').Kind = sckNone, 'Outer');
  Assert.AreEqual('inner', ConstIn(Src, 'NAME', '// in Inner').Value, 'Inner');
end;

procedure TTestRdxSqlGuards.Scope_InlineConst_NotProven;
begin
  // sql2 c07: die Inline-Konstante gilt nur in ihrem Block.
  Assert.IsTrue(ConstIn(Join(['unit u;', 'interface', 'implementation',
    'procedure P;', 'begin', '  if A then', '  begin', '    const NAME = ''blk'';',
    '  end;', '  Q.SQL.Text := ''SELECT * FROM t WHERE x = '' + NAME;', 'end;',
    'end.']), 'NAME', 'Q.SQL.Text').Kind = sckNone);
end;

procedure TTestRdxSqlGuards.Scope_ClassConst_OnlyInItsMethods;
var
  Src : string;
begin
  // HeidiSQL TTableKey.FULLTEXT: die Klassenkonstante galt bis Charge SQc
  // ueberall hinter ihrer Deklaration.
  Src := Join(['unit u;', 'interface', 'type', '  TKey<T> = class', '  const',
    '    FULLTEXT = ''FULLTEXT'';', '    procedure P;', '  end;',
    '  TOther = record', '    procedure Q;', '  end;', 'implementation',
    'procedure TKey<T>.P;', '  procedure Inner;', '  begin',
    '    S := ''A'' + FULLTEXT; // nested', '  end;', 'begin',
    '  S := ''B'' + FULLTEXT; // own', 'end;', 'procedure TOther.Q;', 'begin',
    '  S := ''C'' + FULLTEXT; // other', 'end;', 'procedure Free;', 'begin',
    '  S := ''D'' + FULLTEXT; // free', 'end;', 'end.']);
  Assert.AreEqual('FULLTEXT', ConstIn(Src, 'FULLTEXT', '// own').Value, 'eigene');
  Assert.AreEqual('FULLTEXT', ConstIn(Src, 'FULLTEXT', '// nested').Value,
    'verschachtelt in der eigenen');
  Assert.IsTrue(ConstIn(Src, 'FULLTEXT', '// other').Kind = sckNone, 'andere');
  Assert.IsTrue(ConstIn(Src, 'FULLTEXT', '// free').Kind = sckNone, 'frei');
end;

{ ---- Major 1: der Name der Konstante bleibt ---- }

procedure TTestRdxSqlGuards.Major1_ConstNameStays;
var
  R : TRdxSqlRequest;
  T : TRdxSqlTemplate;
begin
  R := Req([Target('Q.SQL.Text'), Lit('''DELETE FROM '''),
    Op('TEST_TABLE_SOFTDEL'), Lit(''' WHERE id = '''), Op('IntToStr(AId)')]);
  SetConst(R, 2, 'entgen_test_softdel');
  Assert.AreEqual('Q.SQL.Text := ''DELETE FROM '' + TEST_TABLE_SOFTDEL + '
    + ''' WHERE id = :Id'';' + sLineBreak + 'Q.ParamByName(''Id'').Value := AId;',
    Ok(R));
  BuildSqlTemplate(R, T);
  Assert.AreEqual('1 Parameter, 1 Konstante(n) mitgelesen, nichts wird '
    + 'geschrieben', SqlHintOf(T));
  // Der Wert wird gelesen: endet er auf '=', ist der Operand ein Wert.
  R := Req([Target('Q.SQL.Text'), Op('SQL_BASE'), Op('X')]);
  SetConst(R, 1, 'SELECT * FROM t WHERE a =');
  Assert.AreEqual('Q.SQL.Text := SQL_BASE + '':X'';' + sLineBreak
    + 'Q.ParamByName(''X'').Value := X;', Ok(R));
  // Endet er auf ein Wort und ein SQL-String wird Parameter, braucht der
  // Platzhalter ein Leerzeichen (':X' direkt hinter 'LIKE' ist keiner).
  R := Req([Target('Q.SQL.Text'), Op('SQL_BASE'), Lit('''''''%'''), Op('X'),
    Lit('''%''''''')]);
  SetConst(R, 1, 'SELECT * FROM t WHERE a LIKE');
  Assert.AreEqual('Q.SQL.Text := SQL_BASE + '' :X'';' + sLineBreak
    + 'Q.ParamByName(''X'').Value := ''%'' + X + ''%'';', Ok(R));
end;

procedure TTestRdxSqlGuards.Major1_ConstCutOrGlued_Refused;
var
  R : TRdxSqlRequest;
begin
  // Der Wert oeffnet den String, der Parameter wird - die Vorlage muesste
  // die Konstante zerschneiden.
  R := Req([Target('Q.SQL.Text'), Op('SQL_BASE'), Op('Name'), Lit('''''''''')]);
  SetConst(R, 1, 'SELECT * FROM t WHERE name = ''');
  AssertRefused(R, 'die Vorlage muesste sie zerschneiden');
  // ... bzw. schliesst ihn.
  R := Req([Target('Q.SQL.Text'), Lit('''SELECT * FROM t WHERE name = '''''''),
    Op('Name'), Op('QUOTE_AND')]);
  SetConst(R, 3, ''' AND b = 1');
  AssertRefused(R, 'die Vorlage muesste sie zerschneiden');
  // Innerhalb des Strings ohne Quote: ein Stueck des Werts.
  R := Req([Target('Q.SQL.Text'), Lit('''SELECT * FROM t WHERE n LIKE '''''''),
    Op('PCT'), Op('X'), Lit('''%''''''')]);
  SetConst(R, 2, '%');
  Assert.IsTrue(Pos('ParamByName(''X'').Value := PCT + X + ''%'';', Ok(R)) > 0);
end;

procedure TTestRdxSqlGuards.Major1_KeptConstBehindOperand_Refused;
var
  R : TRdxSqlRequest;
begin
  // Review Woche G01-01: const WHERE_ACTIVE = ' AND active = ' + '1' hat
  // keinen einfachen Wert (sckKept). Bis dahin zog der Lauf sie in den
  // Parameter: 'WHERE id = :Id' mit '.Value := IntToStr(Id) + WHERE_ACTIVE'
  // - der Filter fiel aus der Anweisung in die Daten.
  R := Req([Target('Q.SQL.Text'), Lit('''SELECT * FROM t WHERE id = '''),
    Op('IntToStr(Id)'), Op('WHERE_ACTIVE')]);
  SetLength(R.Consts, Length(R.Parts));
  R.Consts[3].Kind := sckKept;
  AssertRefused(R, 'steht direkt vor ''WHERE_ACTIVE''');
  // Zwei Operanden ohne SQL-Text dazwischen bleiben EIN Wert ...
  Assert.IsTrue(Pos('ParamByName(''A'').Value := A + B;', Ok(Req([
    Target('Q.SQL.Text'), Lit('''SELECT * FROM t WHERE a = '''), Op('A'),
    Op('B')]))) > 0);
  // ... und sLineBreak hinter dem Operanden ist Leerraum.
  Assert.IsTrue(Pos('WHERE id = :Id', Ok(Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM t WHERE id = '''), Op('Id'), Op('sLineBreak'),
    Lit('''ORDER BY id''')]))) > 0);
end;

{ ---- Major 2: DDL-Sperre fuer den Rest, die Kette ---- }

procedure TTestRdxSqlGuards.Major2_DdlLock_RestOfText;
begin
  // sql1 S25: der Rumpf einer Prozedur beginnt hinter ';'.
  AssertRefused(Req([Target('Q.SQL.Text'),
    Lit('''CREATE PROCEDURE p AS BEGIN SELECT 1; UPDATE t SET a = '''), Op('X'),
    Lit('''; END''')]), 'DDL/DCL (CREATE ...)');
  AssertRefused(Req([Target('Q.SQL.Text'),
    Lit('''CREATE TRIGGER tr FOR t BEFORE INSERT AS BEGIN NEW.a = 1; NEW.b = '''),
    Op('X'), Lit('''; END''')]), 'DDL/DCL (CREATE ...)');
  AssertRefused(Req([Target('Q.SQL.Text'),
    Lit('''EXECUTE BLOCK AS BEGIN UPDATE t SET a = '''), Op('X'),
    Lit('''; END''')]), 'prozeduraler Block (EXECUTE BLOCK ...)');
  AssertRefused(Req([Target('Q.SQL.Text'),
    Lit('''DECLARE n INTEGER; BEGIN UPDATE t SET a = '''), Op('X'),
    Lit('''; END;''')]), 'prozeduraler Block (DECLARE ...)');
  // Ohne DDL-Kopf bleibt die zweite Anweisung eine Anweisung.
  Assert.IsTrue(Pos('WHERE id = :Id', Ok(Req([Target('Q.SQL.Text'),
    Lit('''DELETE FROM a; DELETE FROM b WHERE id = '''), Op('Id')]))) > 0);
end;

procedure TTestRdxSqlGuards.Major2_Chain_PreviousAddLines;
var
  Src : string;
  T   : TRdxSqlTemplate;
begin
  // Die Zeile davor beginnt eine Sicht - das Bruchstueck gehoert zu ihr.
  Src := UnitWithBody(['  X0 = 0;'], ['  Q.SQL.Clear;', '  Q.SQL.Add(''CREATE VIEW v AS'');',
    '  Q.SQL.Add(''SELECT * FROM t WHERE a = '' + X); // here']);
  Assert.IsFalse(FactsBuilt(Src, '// here', CallReq([Target('Q.SQL.Add'),
    Lit('''SELECT * FROM t WHERE a = '''), Op('X')]), T), T.Text);
  Assert.IsTrue(Pos('DDL/DCL (CREATE ...)', T.Reason) > 0, T.Reason);
  // Clear beendet die Kette: was davor steht, zaehlt nicht.
  Src := UnitWithBody(['  X0 = 0;'], ['  Q.SQL.Add(''CREATE VIEW v AS'');',
    '  Q.SQL.Clear;', '  Q.SQL.Add(''SELECT * FROM t WHERE a = '' + X); // here']);
  Assert.IsTrue(FactsBuilt(Src, '// here', CallReq([Target('Q.SQL.Add'),
    Lit('''SELECT * FROM t WHERE a = '''), Op('X')]), T), T.Reason);
  // Die Zeile davor setzt die Anweisungsart: 'SET a = ' ist dann ein Wert
  // (sql1 S53 ohne Kette: "Anweisungsart unbekannt").
  Src := UnitWithBody(['  X0 = 0;'], ['  Q.SQL.Text := ''UPDATE t'';',
    '  Q.SQL.Add(''SET a = '' + X); // here']);
  Assert.IsTrue(FactsBuilt(Src, '// here', CallReq([Target('Q.SQL.Add'),
    Lit('''SET a = '''), Op('X')]), T), T.Reason);
  Assert.AreEqual('Q.SQL.Add(''SET a = :X'');' + sLineBreak
    + 'Q.ParamByName(''X'').Value := X;', T.Text);
end;

procedure TTestRdxSqlGuards.VerdachtA_Chain_NamesReserved;
var
  Src : string;
  T   : TRdxSqlTemplate;
begin
  // :Id steht schon in einer frueheren und :Id2 in einer spaeteren Zeile
  // derselben Kette - der neue Name ist Id3.
  Src := UnitWithBody(['  X0 = 0;'], ['  Q.SQL.Add(''SELECT * FROM t WHERE a = :Id'');',
    '  Q.SQL.Add(''AND b = '' + IntToStr(FId)); // here',
    '  Q.SQL.Add(''AND c = :Id2'');']);
  Assert.IsTrue(FactsBuilt(Src, '// here', CallReq([Target('Q.SQL.Add'),
    Lit('''AND b = '''), Op('IntToStr(FId)')]), T), T.Reason);
  Assert.AreEqual('Q.SQL.Add(''AND b = :Id3'');' + sLineBreak
    + 'Q.ParamByName(''Id3'').Value := FId;', T.Text);
end;

{ ---- Minor 1: ganze Liste in Quotes, Join-Bedingung ---- }

procedure TTestRdxSqlGuards.Minor1_QuotedWholeList_Refused;
begin
  // sql1 S20: wie der nackte Operand - Codes kann '1'',''2' sein.
  AssertRefused(Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM t WHERE code IN ('''''''), Op('Codes'),
    Lit(''''''')''')]), 'die ganze IN-Liste');
  AssertRefused(Req([Target('Q.SQL.Text'), Lit('''INSERT INTO t VALUES ('''''''),
    Op('Vals'), Lit(''''''')''')]), 'die ganze VALUES-Liste');
  // Ein Element unter mehreren bleibt ein Wert.
  Assert.IsTrue(Pos('IN (:A, ''''b'''')', Ok(Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM t WHERE code IN ('''''''), Op('A'),
    Lit(''''''', ''''b'''')''')]))) > 0);
end;

procedure TTestRdxSqlGuards.Minor1_JoinOn_BareOperandRefused;
begin
  // sql1 S24: in einer Join-Bedingung ist ein nackter Operand meist eine
  // Spalte.
  AssertRefused(Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM a JOIN b ON a.id = '''), Op('JoinColumn')]),
    'steht in einer Join-Bedingung (ON)');
  // IntToStr(x), QuotedStr(x) und ein SQL-String sind Werte.
  Assert.IsTrue(Pos('ON a.id = :Id', Ok(Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM a JOIN b ON a.id = '''), Op('IntToStr(Id)')]))) > 0);
  Assert.IsTrue(Pos('ON a.n = :Name', Ok(Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM a JOIN b ON a.n = '''''''), Op('Name'),
    Lit('''''''''')]))) > 0);
  // WHERE beendet die Join-Bedingung.
  Assert.IsTrue(Pos('WHERE a.x = :X', Ok(Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM a JOIN b ON a.id = b.id WHERE a.x = '''), Op('X')]))) > 0);
end;

{ ---- Minor 2, 3: Namen ---- }

procedure TTestRdxSqlGuards.Minor2_ReservedNamesAndLength;
var
  T : string;
begin
  // sql1 S27 und die Namensfaelle: Oracle ORA-01745.
  Assert.AreEqual('pRows', SqlParamName('Rows'));
  Assert.AreEqual('pStart', SqlParamName('AStart'));
  Assert.AreEqual('pValues', SqlParamName('Values'));
  Assert.AreEqual('pSysdate', SqlParamName('Sysdate'));
  Assert.AreEqual('pRownum', SqlParamName('Rownum'));
  Assert.AreEqual('pRow', SqlParamName('Row'));
  Assert.AreEqual('pOption', SqlParamName('FOption'));
  // Hoechstens 30 Zeichen - auch mit der Nummer einer Kollision.
  T := Ok(Req([Target('S'), Lit('''SELECT * FROM t WHERE a = '''),
    Op(StringOfChar('y', 40)), Lit(''' AND b = '''), Op(StringOfChar('y', 41))]));
  Assert.IsTrue(Pos(':' + StringOfChar('y', 29) + '2''', T) > 0, T);
end;

procedure TTestRdxSqlGuards.Minor3_NonAsciiName_Fallback;
var
  T : string;
begin
  // sql1 S28: 'Groesse' mit sz wurde ':Gre', 'Aepfel' mit Umlaut ':pfel'.
  Assert.AreEqual('', SqlParamName('Gr' + #$00DF + 'e'));
  T := Ok(Req([Target('Q.SQL.Text'), Lit('''SELECT * FROM t WHERE g = '''),
    Op('Gr' + #$00F6 + #$00DF + 'e'), Lit(''' AND x = '''), Op(#$00C4 + 'pfel')]));
  Assert.IsTrue(Pos('WHERE g = :p1 AND x = :p2', T) > 0, T);
end;

{ ---- Minor 10: Fehlablehnungen ---- }

procedure TTestRdxSqlGuards.Minor10_CommentNationalCastValues;
begin
  // sql1 S06: sLineBreak beendet den Zeilenkommentar.
  Assert.IsTrue(Pos('''WHERE id = :Id''', Ok(Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM t -- alle'''), Op('sLineBreak'), Lit('''WHERE id = '''),
    Op('Id')]))) > 0);
  // S19: QuotedStr(x) ist EIN Wert - auch allein in VALUES (..).
  Assert.IsTrue(Pos('VALUES (:Msg)', Ok(Req([Target('Q.SQL.Text'),
    Lit('''INSERT INTO log VALUES ('''), Op('QuotedStr(Msg)'), Lit(''')''')]))) > 0);
  // S21: N'..' - das N faellt mit dem String weg.
  Assert.IsTrue(Pos('WHERE name = :Name''', Ok(Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM t WHERE name = N'''''''), Op('Name'),
    Lit('''''''''')]))) > 0);
  // S22/S23: der PostgreSQL-Cast hinter dem Wert.
  Assert.IsTrue(Pos('WHERE d = :D::date', Ok(Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM t WHERE d = '''''''), Op('D'),
    Lit('''''''::date''')]))) > 0);
  Assert.IsTrue(Pos('WHERE id = :Id::int', Ok(Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM t WHERE id = '''), Op('Id'), Lit('''::int''')]))) > 0);
end;

{ ---- Minor 11: ADO ---- }

procedure TTestRdxSqlGuards.Minor11_AdoParameters;
var
  Src : string;
  T   : TRdxSqlTemplate;
begin
  // TADOQuery/TADOCommand kennen kein ParamByName (E2003) - nur
  // Parameters.ParamByName.
  Src := Join(['unit u;', 'interface', 'uses Data.Win.ADODB;', 'type',
    '  TForm1 = class', '    ADOQuery1: TADOQuery;', '    ADOCommand1: ADODB.TADOCommand;',
    '    procedure P;', '  end;', 'implementation', 'procedure TForm1.P;',
    'begin', '  ADOQuery1.SQL.Text := ''SELECT * FROM t WHERE a = '' + X; // q',
    '  ADOCommand1.CommandText := ''DELETE FROM t WHERE a = '' + X; // c',
    'end;', 'end.']);
  Assert.IsTrue(FactsBuilt(Src, '// q', UsesReq([Target('ADOQuery1.SQL.Text'),
    Lit('''SELECT * FROM t WHERE a = '''), Op('X')], 'Data.Win.ADODB'), T),
    T.Reason);
  Assert.IsTrue(Pos('ADOQuery1.Parameters.ParamByName(''X'').Value := X;',
    T.Text) > 0, T.Text);
  Assert.IsTrue(FactsBuilt(Src, '// c', UsesReq([Target('ADOCommand1.CommandText'),
    Lit('''DELETE FROM t WHERE a = '''), Op('X')], 'ADODB'), T), T.Reason);
  Assert.IsTrue(Pos('ADOCommand1.Parameters.ParamByName(''X'')', T.Text) > 0,
    T.Text);
  // Ohne ADO in uses nicht nachgewiesen: wie bisher.
  Assert.IsTrue(FactsBuilt(Src, '// q', UsesReq([Target('ADOQuery1.SQL.Text'),
    Lit('''SELECT * FROM t WHERE a = '''), Op('X')], 'Data.DB'), T),
    T.Reason);
  Assert.IsTrue(Pos('ADOQuery1.ParamByName(''X'')', T.Text) > 0, T.Text);
end;

{ ---- Verdacht b, c ---- }

procedure TTestRdxSqlGuards.VerdachtB_LimitOffset_OnlyIntToStr;
begin
  // sql1 S29/S42: ein Operand hinter LIMIT/OFFSET ist in Pascal ein Text.
  AssertRefused(Req([Target('Q.SQL.Text'), Lit('''SELECT * FROM t LIMIT '''),
    Op('S')]), 'hinter LIMIT ist ein Text');
  AssertRefused(Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM t ORDER BY id OFFSET '''), Op('N'),
    Lit(''' ROWS FETCH NEXT 10 ROWS ONLY''')]), 'hinter OFFSET ist ein Text');
  AssertRefused(Req([Target('Q.SQL.Text'), Lit('''SELECT * FROM t LIMIT '''''''),
    Op('S'), Lit('''''''''')]), 'hinter LIMIT ist ein Text');
  Assert.IsTrue(Pos('LIMIT :Count', Ok(Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM t LIMIT '''), Op('IntToStr(ACount)')]))) > 0);
end;

procedure TTestRdxSqlGuards.VerdachtC_QuestionMark_Refused;
begin
  // sql1 S26: '?' und ':X' mischen sich nicht.
  AssertRefused(Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM t WHERE a = ? AND b = '''), Op('X')]),
    'positionalen Platzhalter ''?''');
  // Ein '?' in einem SQL-String ist Text.
  Assert.IsTrue(Pos('AND b = :X', Ok(Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM t WHERE a = ''''?'''' AND b = '''), Op('X')]))) > 0);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxSqlGuards);

end.
