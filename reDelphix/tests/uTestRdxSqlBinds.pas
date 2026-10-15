unit uTestRdxSqlBinds;

// Tests fuer die Nacharbeit des Code-Reviews an der SQL-Vorlage (Charge FB,
// uRdxSqlTemplate): kein Literal ueber 255 Elemente in der Vorlage (R2-02),
// eine Unit-Konstante ist in einer Methode mit fremdem Vorfahr nicht
// bewiesen - ein geerbtes Member gleichen Namens bindet vorher (R2-05) -
// und ein schon maskierter Wert wird nicht woertlich Parameter (R2-06).
// Reine Textlogik - laeuft in reDelphix.Test UND im FPC-Pruefstand. Nur die
// Schnittstelle, die es vor der Charge gab (BuildSqlTemplate, SqlConstOf,
// AddSqlFacts): jeder Test war gegen den Stand 4358b769 rot.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxSqlBinds = class
  public
    // R2-02: SQL-Literale von 197 und 84 Zeichen ergaben EIN Literal von 286.
    [Test] procedure LongSqlText_NoLiteralOver255;
    // R2-05: Unit-Konstante 'Caption' in TForm1 = class(TForm), in einem
    // Helper, in einer Klasse mit Vorfahr der Unit, in einem Record.
    [Test] procedure UnitConst_InForeignDescendant_NotProven;
    [Test] procedure UnitConst_InForeignDescendant_BecomesParameter;
    // R2-06: Maskierungen.
    [Test] procedure DoubledQuotes_InSqlString_BindRawValue;
    [Test] procedure AnsiQuotedStr_BindsRawValue;
    [Test] procedure OtherEscapes_Refused;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRefactorInfo, uRdxRecipes, uRdxCodeMap, uRdxSqlTemplate;

const
  // Elemente eines String-Literals bis Delphi 11 (E2056).
  LIMIT = 255;

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

// Zeilen mit CRLF verbunden (string.Join kennt FPC nicht).
function Join(const ALines: array of string): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(ALines) do
    begin
      if i > 0 then
        SB.Append(#13#10);
      SB.Append(ALines[i]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Die erste Zeile (1-basiert), die AText enthaelt; 0 ohne.
function LineOf(const ASource, AText: string): Integer;
var
  SL : TStringList;
  i  : Integer;
begin
  Result := 0;
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    for i := 0 to SL.Count - 1 do
      if Pos(AText, SL[i]) > 0 then
        Exit(i + 1);
  finally
    SL.Free;
  end;
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

// Wie der Laeufer (SqlRequestOf): alle Parts auf der Zeile mit AMarker,
// AddSqlFacts auf ASource, dann BuildSqlTemplate.
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

// Das Glied ASource dekodiert an AValues anhaengen - es muss ein Literal sein.
procedure AddDecoded(var AValues: TArray<string>; const ASource: string);
var
  V : string;
begin
  Assert.IsTrue(TRdxRecipes.DecodeLiteral(ASource, V), 'kein Literal: ' + ASource);
  SetLength(AValues, Length(AValues) + 1);
  AValues[High(AValues)] := V;
end;

// Die Glieder eines mit ' + ' verbundenen Literal-Ausdrucks, je dekodiert -
// zerlegt an ' + ' AUSSERHALB von Quotes (unabhaengig von SplitLongLiteral).
function PiecesOf(const AExpr: string): TArray<string>;
var
  i, Start : Integer;
  InQuote  : Boolean;
begin
  Result := nil;
  InQuote := False;
  Start := 1;
  i := 1;
  while i <= Length(AExpr) do
  begin
    if AExpr[i] = '''' then
      InQuote := not InQuote
    else if not InQuote and (Copy(AExpr, i, 3) = ' + ') then
    begin
      AddDecoded(Result, Copy(AExpr, Start, i - Start));
      Start := i + 3;
      Inc(i, 2);
    end;
    Inc(i);
  end;
  AddDecoded(Result, Copy(AExpr, Start, MaxInt));
end;

// Die Quelltext-Form eines Literals mit AValue Apostrophen ('''' fuer eins).
function Apos(ACount: Integer): string;
begin
  Result := StringOfChar('''', 2 * ACount + 2);
end;

// Eine Unit mit TForm1 = class(TForm), deren Methode Go die Anweisung
// ABody traegt, und der Unit-Konstante 'Caption = ''guest'''.
function FormUnit(const ABody: string): string;
begin
  Result := Join(['unit u;', 'interface', 'uses Vcl.Forms;', 'type',
    '  TForm1 = class(TForm)', '    procedure Go;', '  end;', 'implementation',
    'const', '  Caption = ''guest'';', 'procedure TForm1.Go;', 'begin',
    ABody, 'end;', 'end.']);
end;

{ ---- R2-02 ---- }

procedure TTestRdxSqlBinds.LongSqlText_NoLiteralOver255;
var
  Head, Tail, T, Expr : string;
  Values              : TArray<string>;
  i                   : Integer;
begin
  // Gegenpruefer fx\v02.pas: 'SQL-Vorlage: Eingabe-Literale 205/79,
  // laengstes Token im Ergebnis = 287'.
  // noinspection SQLInjection (Testdaten: ein langer SQL-Text fuer die Vorlage)
  Head := 'SELECT ' + StringOfChar('c', 170) + ' FROM t WHERE a = ';
  Tail := ' AND b IN (' + StringOfChar('d', 60) + ') ORDER BY 1';
  Assert.IsTrue(Length(Head) < LIMIT);
  T := Ok(Req([Target('Q.SQL.Text'), Lit('''' + Head + ''''), Op('X'),
    Lit('''' + Tail + '''')]));
  Assert.AreEqual('Q.SQL.Text := ', Copy(T, 1, 14), T);
  Expr := Copy(T, 15, Pos(';' + sLineBreak, T) - 15);
  Values := PiecesOf(Expr);
  Assert.IsTrue(Length(Values) >= 2, Expr);
  for i := 0 to High(Values) do
    Assert.IsTrue(Length(Values[i]) <= LIMIT,
      Format('Glied %d: %d Zeichen', [i, Length(Values[i])]));
  Assert.AreEqual(Head + ':X' + Tail, Values[0] + Values[1]);
end;

{ ---- R2-05 ---- }

procedure TTestRdxSqlBinds.UnitConst_InForeignDescendant_NotProven;
var
  Src : string;
begin
  // In TForm1.Go bindet 'Caption' an Self.Caption (TControl, andere Unit),
  // nicht an die Unit-Konstante - bis Charge FB 'nur Konstanten - kein
  // Injection-Risiko' (Gegenpruefer v05).
  Src := Join(['unit u;', 'interface', 'uses Vcl.Forms;', 'type',
    '  TForm1 = class(TForm)', '    procedure Go;', '  end;',
    '  TBase = class', '  end;', '  TChild = class(TBase)', '    procedure Go;',
    '  end;', '  TRec = record', '    procedure Go;', '  end;',
    '  TFormHelper = class helper for TForm', '    procedure Go2;', '  end;',
    'implementation', 'const', '  Caption = ''guest'';',
    'procedure TForm1.Go;', '  procedure Inner;', '  begin',
    '    S := ''I'' + Caption; // inner', '  end;', 'begin',
    '  S := ''A'' + Caption; // form', 'end;',
    'procedure TChild.Go;', 'begin', '  S := ''B'' + Caption; // child', 'end;',
    'procedure TRec.Go;', 'begin', '  S := ''C'' + Caption; // rec', 'end;',
    'procedure TFormHelper.Go2;', 'begin', '  S := ''D'' + Caption; // helper',
    'end;', 'procedure Free;', 'begin', '  S := ''E'' + Caption; // free',
    'end;', 'end.']);
  Assert.IsTrue(ConstIn(Src, 'Caption', '// form').Kind = sckNone, 'TForm1');
  Assert.IsTrue(ConstIn(Src, 'Caption', '// inner').Kind = sckNone,
    'lokale Routine der Methode');
  Assert.IsTrue(ConstIn(Src, 'Caption', '// helper').Kind = sckNone, 'Helper');
  Assert.AreEqual('guest', ConstIn(Src, 'Caption', '// child').Value,
    'Kette in der Unit');
  Assert.AreEqual('guest', ConstIn(Src, 'Caption', '// rec').Value, 'Record');
  Assert.AreEqual('guest', ConstIn(Src, 'Caption', '// free').Value,
    'freie Routine');
end;

procedure TTestRdxSqlBinds.UnitConst_InForeignDescendant_BecomesParameter;
var
  Src : string;
  T   : TRdxSqlTemplate;
begin
  // Bis Charge FB blieb 'Caption' als "mitgelesene Konstante" in der
  // Vorlage stehen - als sicher ausgewiesen, zur Laufzeit Self.Caption.
  Src := FormUnit('  Q.SQL.Text := ''SELECT * FROM users WHERE login = '''''' '
    + '+ Caption + '''''' AND id = '' + IntToStr(FId);');
  Assert.IsTrue(FactsBuilt(Src, 'Q.SQL.Text', Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM users WHERE login = '''''''), Op('Caption'),
    Lit(''''''' AND id = '''), Op('IntToStr(FId)')]), T), T.Reason);
  Assert.AreEqual('Q.SQL.Text := ''SELECT * FROM users WHERE login = :Caption '
    + 'AND id = :Id'';' + sLineBreak
    + 'Q.ParamByName(''Caption'').Value := Caption;' + sLineBreak
    + 'Q.ParamByName(''Id'').Value := FId;', T.Text);
  Assert.AreEqual('2 Parameter, nichts wird geschrieben', SqlHintOf(T));
end;

{ ---- R2-06 ---- }

procedure TTestRdxSqlBinds.DoubledQuotes_InSqlString_BindRawValue;
const
  SQL_HEAD = '''SELECT * FROM users WHERE login = ''''''';
  SQL_TAIL = '''''''''';
  EXPECTED = 'Q.SQL.Text := ''SELECT * FROM users WHERE login = :X'';';
var
  Operands : array[0..3] of string;
  i        : Integer;
begin
  // Gegenpruefer v06 E1: der Parameter trug O''Brien statt O'Brien.
  Operands[0] := 'StringReplace(X, ' + Apos(1) + ', ' + Apos(2)
    + ', [rfReplaceAll])';
  Operands[1] := 'SysUtils.StringReplace(X, ' + Apos(1) + ', ' + Apos(2)
    + ', [rfReplaceAll, rfIgnoreCase])';
  Operands[2] := 'ReplaceStr(X, ' + Apos(1) + ', ' + Apos(2) + ')';
  Operands[3] := 'X.Replace(' + Apos(1) + ', ' + Apos(2) + ')';
  for i := 0 to High(Operands) do
    Assert.AreEqual(EXPECTED + sLineBreak + 'Q.ParamByName(''X'').Value := X;',
      Ok(Req([Target('Q.SQL.Text'), Lit(SQL_HEAD), Op(Operands[i]),
      Lit(SQL_TAIL)])), Operands[i]);
end;

procedure TTestRdxSqlBinds.AnsiQuotedStr_BindsRawValue;
begin
  // Gegenpruefer v06 E2: der Parameter trug 'O''Brien' samt Quotes.
  Assert.AreEqual('Q.SQL.Text := ''SELECT * FROM users WHERE login = :X'';'
    + sLineBreak + 'Q.ParamByName(''X'').Value := X;',
    Ok(Req([Target('Q.SQL.Text'), Lit('''SELECT * FROM users WHERE login = '''),
    Op('AnsiQuotedStr(X, ' + Apos(1) + ')')])));
  // Ein anderes Quote-Zeichen ist kein SQL-String (Name, Dialekt).
  AssertRefused(Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM users WHERE login = '''),
    Op('AnsiQuotedStr(X, ''"'')')]), 'maskiert');
end;

procedure TTestRdxSqlBinds.OtherEscapes_Refused;
begin
  // Ein eigener Maskierer: sein Wert traegt Quotes bzw. Escapes.
  AssertRefused(Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM users WHERE login = '''),
    Op('Conn.EscapeString(X)')]), 'maskiert (EscapeString)');
  // QuotedStr IN einem SQL-String quotet doppelt.
  AssertRefused(Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM users WHERE login = '''''''), Op('QuotedStr(X)'),
    Lit('''''''''')]), 'maskiert (QuotedStr)');
  // Verdoppelte Apostrophe ausserhalb eines Strings: kein Rohwert.
  AssertRefused(Req([Target('Q.SQL.Text'),
    Lit('''SELECT * FROM users WHERE login = '''),
    Op('StringReplace(X, ' + Apos(1) + ', ' + Apos(2) + ', [rfReplaceAll])')]),
    'maskiert');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxSqlBinds);

end.
