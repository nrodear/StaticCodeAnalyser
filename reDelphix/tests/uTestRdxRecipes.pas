unit uTestRdxRecipes;

// Tests fuer die Rezepte (uRdxRecipes) und die Scope-Tabelle
// (uRdxScopeTable) des Moduls reDelphix. Reine Textlogik - laufen unter
// DUnitX in Delphi und im FPC-Pruefstand (reDelphix\tools\fpc-pruefstand).
//
// Was hier festgepinnt wird:
//   * Literal-Codec: Quelltext <-> Wert, Roundtrip, Fehlformen
//   * Format()-Bau: nur bei beweisbaren String-Operanden, '%' -> '%%',
//     Sperre fuer SQL-Text (SCA003), Sperre ohne Operand
//   * SQL-Vorlage: Zuweisung und Aufruf, Parameter nie in Quotes
//   * Rahmenwerk-Erkennung und Scope-Aufloesung in Compiler-Reihenfolge

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxRecipes = class
  public
    // ---- Literal-Codec -------------------------------------------------
    [Test] procedure Decode_PlainLiteral;
    [Test] procedure Decode_DoubledQuote;
    [Test] procedure Decode_ControlChars_DecAndHex;
    [Test] procedure Decode_Malformed_IsFalse;
    [Test] procedure Encode_QuoteAndControl;
    [Test] procedure Encode_Roundtrip;
    [Test] procedure Encode_Empty;

    // ---- Format() ------------------------------------------------------
    [Test] procedure Format_AllStringTerms_BuildsCall;
    [Test] procedure Format_PercentIsEscaped;
    [Test] procedure Format_ExpressionOperand_Blocked;
    [Test] procedure Format_SqlText_Blocked;
    [Test] procedure Format_NoOperand_Blocked;
    [Test] procedure Format_ArgumentRole_Blocked;
    // Kompilat-Regel (AH20): Form eines Operanden, Variant-Anzeichen,
    // RTL-Konstanten/-Funktionen, Herkunft der Argumente, %d/%u.
    [Test] procedure Shape_AcceptsOperandForms;
    [Test] procedure Shape_RejectsExpressions;
    [Test] procedure Judge_DeclaredTypes;
    [Test] procedure Judge_TextTells;
    [Test] procedure Format_ByCompiler_Listed;
    [Test] procedure Format_IntegerArgs_UseDAndU;
    [Test] procedure Format_VariantAndAnsi_Blocked;
    [Test] procedure LooksLikeSql_NeedsVerbAndStructure;

    // ---- SQL-Vorlage ---------------------------------------------------
    [Test] procedure QueryObject_Forms;
    [Test] procedure SqlTemplate_Assign;
    [Test] procedure SqlTemplate_Call;
    [Test] procedure SqlTemplate_QuotedParam_Unquoted;
    [Test] procedure SqlTemplate_ArgumentRole_Blocked;

    // ---- uses ----------------------------------------------------------
    [Test] procedure Framework_FromUnitNames;
    [Test] procedure HasUnit_ShortAndQualified;
    // uses-Klausel ergaenzen (AH19): Schreibweise der Datei, Sortierung
    // wie SCA142, Einfuegestelle.
    [Test] procedure UsesNameFor_FollowsFileStyle;
    [Test] procedure IsSortedUses_CompareText;
    [Test] procedure SortedInsertIndex_KeepsOrder_UnsortedGoesFront;
    [Test] procedure Scope_Load_IgnoresCommentsAndDedupes;
    [Test] procedure Scope_Resolve_VclAndFmx;
    [Test] procedure Scope_Resolve_CommonBeforeFramework;
    [Test] procedure Scope_Resolve_Unknown_NotGuessed;
    [Test] procedure Scope_Resolve_AlreadyQualified_IsFalse;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uRefactorInfo, uRdxRecipes, uRdxScopeTable;

function Lit(const AText: string): TRdxPart;
begin
  Result := TRdxRecipes.MakePart(ROLE_LITERAL, AText, rvString);
end;

function Op(const AText: string; AType: TRefactorValueType): TRdxPart;
begin
  Result := TRdxRecipes.MakePart(ROLE_OPERAND, AText, AType);
end;

function Target(const AText: string): TRdxPart;
begin
  Result := TRdxRecipes.MakePart(ROLE_TARGET, AText);
end;

// Urteil ueber einen Operanden mit Text, Core-Typklasse und deklariertem Typ.
function JP(const AText: string; AType: TRefactorValueType;
  const AResolved: string = ''): TRdxOperandVerdict;
begin
  Result := TRdxRecipes.JudgeOperand(
    TRdxRecipes.MakePart(ROLE_OPERAND, AText, AType, AResolved));
end;

function MakeTable(const ALines: array of string): TRdxScopeTable;
var
  SL : TStringList;
  i  : Integer;
begin
  Result := TRdxScopeTable.Create;
  SL := TStringList.Create;
  try
    for i := Low(ALines) to High(ALines) do
      SL.Add(ALines[i]);
    Result.LoadFromStrings(SL);
  finally
    SL.Free;
  end;
end;

{ ---- Literal-Codec ---- }

procedure TTestRdxRecipes.Decode_PlainLiteral;
var
  V : string;
begin
  Assert.IsTrue(TRdxRecipes.DecodeLiteral('''Hallo Welt''', V));
  Assert.AreEqual('Hallo Welt', V);
end;

procedure TTestRdxRecipes.Decode_DoubledQuote;
var
  V : string;
begin
  Assert.IsTrue(TRdxRecipes.DecodeLiteral('''it''''s''', V));
  Assert.AreEqual('it''s', V);
end;

procedure TTestRdxRecipes.Decode_ControlChars_DecAndHex;
var
  V : string;
begin
  Assert.IsTrue(TRdxRecipes.DecodeLiteral('''a''#13#10''b''', V));
  Assert.AreEqual('a'#13#10'b', V);
  Assert.IsTrue(TRdxRecipes.DecodeLiteral('#$41#$0a', V));
  Assert.AreEqual('A'#10, V);
end;

procedure TTestRdxRecipes.Decode_Malformed_IsFalse;
var
  V : string;
begin
  Assert.IsFalse(TRdxRecipes.DecodeLiteral('''offen', V), 'unbalanciert');
  Assert.IsFalse(TRdxRecipes.DecodeLiteral('Name', V), 'Bezeichner');
  Assert.IsFalse(TRdxRecipes.DecodeLiteral('#', V), 'leerer Zeichencode');
  Assert.IsFalse(TRdxRecipes.DecodeLiteral('''a'' + ''b''', V), 'Operator');
end;

procedure TTestRdxRecipes.Encode_QuoteAndControl;
begin
  Assert.AreEqual('''it''''s''', TRdxRecipes.EncodeLiteral('it''s'));
  Assert.AreEqual('''a''#13#10''b''', TRdxRecipes.EncodeLiteral('a'#13#10'b'));
  Assert.AreEqual('#9''x''', TRdxRecipes.EncodeLiteral(#9'x'));
end;

procedure TTestRdxRecipes.Encode_Roundtrip;
const
  Src = '''Preis: 5% ''''netto''''''#13#10''Ende''';
var
  V, V2 : string;
begin
  Assert.IsTrue(TRdxRecipes.DecodeLiteral(Src, V));
  Assert.IsTrue(TRdxRecipes.DecodeLiteral(TRdxRecipes.EncodeLiteral(V), V2));
  Assert.AreEqual(V, V2);
end;

procedure TTestRdxRecipes.Encode_Empty;
begin
  Assert.AreEqual('''''', TRdxRecipes.EncodeLiteral(''));
end;

{ ---- Format() ---- }

procedure TTestRdxRecipes.Format_AllStringTerms_BuildsCall;
var
  Parts    : TRdxParts;
  NewText  : string;
  Reason   : string;
begin
  Parts := [Target('r'), Lit('''Hallo '''), Op('IntToStr(x)', rvString),
            Lit(''', du bist '''), Op('Name.ToString', rvString)];
  Assert.IsTrue(TRdxRecipes.BuildFormatCall(Parts, NewText, Reason), Reason);
  Assert.AreEqual('Format(''Hallo %s, du bist %s'', [IntToStr(x), Name.ToString])',
    NewText);
end;

procedure TTestRdxRecipes.Format_PercentIsEscaped;
var
  Parts   : TRdxParts;
  NewText : string;
  Reason  : string;
begin
  Parts := [Lit('''Rabatt 5% fuer '''), Op('QuotedStr(N)', rvString)];
  Assert.IsTrue(TRdxRecipes.BuildFormatCall(Parts, NewText, Reason), Reason);
  Assert.AreEqual('Format(''Rabatt 5%% fuer %s'', [QuotedStr(N)])', NewText);
end;

procedure TTestRdxRecipes.Format_ExpressionOperand_Blocked;
var
  Parts   : TRdxParts;
  NewText : string;
  Reason  : string;
begin
  // Ein Klammerausdruck ist kein Operand - das Kompilat buergt nur fuer
  // Bezeichner, Member, Aufrufe, Index, Cast.
  Parts := [Lit('''a'''), Op('(Name + Tag)', rvUnknown), Lit('''b''')];
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, NewText, Reason));
  Assert.IsTrue(Pos('kein einfacher Operand', Reason) > 0, Reason);
  Assert.IsTrue(Pos('Name', Reason) > 0, 'der Operand steht im Grund');
end;

procedure TTestRdxRecipes.Shape_AcceptsOperandForms;
begin
  Assert.IsTrue(TRdxRecipes.IsOperandShape('Name'));
  Assert.IsTrue(TRdxRecipes.IsOperandShape('E.Message'));
  Assert.IsTrue(TRdxRecipes.IsOperandShape('Edit1.Text'));
  Assert.IsTrue(TRdxRecipes.IsOperandShape('Foo(a, b)'));
  Assert.IsTrue(TRdxRecipes.IsOperandShape('Items[i].Name'));
  Assert.IsTrue(TRdxRecipes.IsOperandShape('P^.Name'));
  Assert.IsTrue(TRdxRecipes.IsOperandShape('string(Buf)'));
  Assert.IsTrue(TRdxRecipes.IsOperandShape('x.ToString'));
  Assert.IsTrue(TRdxRecipes.IsOperandShape('TPath.Combine(Dir, ''a.txt'')'));
  Assert.IsTrue(TRdxRecipes.IsOperandShape('Q.FieldByName(''(x)'').AsString'),
    'Klammern im Literal zaehlen nicht');
  Assert.IsTrue(TRdxRecipes.IsOperandShape('&Type'));
  Assert.IsTrue(TRdxRecipes.IsOperandShape('Foo (a)'), 'Leerraum vor der Klammer');
  Assert.IsTrue(TRdxRecipes.IsOperandShape('Foo(a,'#13#10'  b)'), 'mehrzeiliger Aufruf');
end;

procedure TTestRdxRecipes.Shape_RejectsExpressions;
begin
  Assert.IsFalse(TRdxRecipes.IsOperandShape(''));
  Assert.IsFalse(TRdxRecipes.IsOperandShape('(a + b)'));
  Assert.IsFalse(TRdxRecipes.IsOperandShape('5'));
  Assert.IsFalse(TRdxRecipes.IsOperandShape('$FF'));
  Assert.IsFalse(TRdxRecipes.IsOperandShape('a and b'));
  Assert.IsFalse(TRdxRecipes.IsOperandShape('not x'));
  Assert.IsFalse(TRdxRecipes.IsOperandShape('[''a'']'));
  Assert.IsFalse(TRdxRecipes.IsOperandShape('-x'));
  Assert.IsFalse(TRdxRecipes.IsOperandShape('@x'));
  Assert.IsFalse(TRdxRecipes.IsOperandShape('a = b'));
  Assert.IsFalse(TRdxRecipes.IsOperandShape('Foo(a'), 'unbalanciert');
  Assert.IsFalse(TRdxRecipes.IsOperandShape('a.'), 'endet auf Punkt');
  Assert.IsFalse(TRdxRecipes.IsOperandShape('inherited Foo'));
end;

procedure TTestRdxRecipes.Judge_DeclaredTypes;
begin
  Assert.IsTrue(JP('Name', rvString, 'string') = ovString, 'deklariert string');
  Assert.IsTrue(JP('c', rvString, 'char') = ovString, 'Char nimmt %s');
  Assert.IsTrue(JP('n', rvNonString, 'integer') = ovNonString, 'deklariert integer');
  Assert.IsTrue(JP('A', rvString, 'ansistring') = ovAnsi,
    'AnsiString ist String, aber kein Unicode');
  Assert.IsTrue(JP('U', rvString, 'utf8string') = ovAnsi);
  Assert.IsTrue(JP('R', rvString, 'rawutf8') = ovAnsi);
  Assert.IsTrue(JP('V', rvUnknown, 'variant') = ovVariantRisk, 'deklariert Variant');
  Assert.IsTrue(JP('V', rvUnknown, 'olevariant') = ovVariantRisk);
  Assert.IsTrue(JP('Fn', rvUnknown, 'tfilename') = ovString, 'RTL-Alias auf string');
  Assert.IsTrue(JP('R', rvUnknown, 'tmyrec') = ovByCompiler,
    'fremder Typname: das Kompilat buergt');
end;

procedure TTestRdxRecipes.Judge_TextTells;
begin
  Assert.IsTrue(JP('E.Message', rvUnknown) = ovByCompiler);
  Assert.IsTrue(JP('Edit1.Text', rvUnknown) = ovByCompiler);
  Assert.IsTrue(JP('GetName(x)', rvUnknown) = ovByCompiler);
  Assert.IsTrue(JP('Items[i]', rvUnknown) = ovByCompiler);
  Assert.IsTrue(JP('sLineBreak', rvUnknown) = ovString, 'RTL-Konstante');
  Assert.IsTrue(JP('PathDelim', rvUnknown) = ovString);
  Assert.IsTrue(JP('ExtractFileName(F)', rvUnknown) = ovString,
    'RTL-Funktion mit String-Ergebnis');
  Assert.IsTrue(JP('SysUtils.ExtractFileName(F)', rvUnknown) = ovString);
  Assert.IsTrue(JP('TPath.Combine(A, B)', rvUnknown) = ovString);
  Assert.IsTrue(JP('Copy(S, 1, 3)', rvUnknown) = ovString);
  Assert.IsTrue(JP('Obj.ExtractFileName(F)', rvUnknown) = ovByCompiler,
    'Methode unbekannten Typs, nicht die RTL');
  Assert.IsTrue(JP('ExtractFileName(F).Trim', rvUnknown) = ovByCompiler,
    'die Klammer schliesst den Term nicht');
  Assert.IsTrue(JP('Q.FieldByName(''a'').Value', rvUnknown) = ovVariantRisk,
    '.Value kann Variant sein');
  Assert.IsTrue(JP('Null', rvUnknown) = ovVariantRisk);
  Assert.IsTrue(JP('True', rvUnknown) = ovVariantRisk,
    'nur hinter einem Variant uebersetzbar');
  Assert.IsTrue(JP('Variant(x)', rvUnknown) = ovVariantRisk);
  Assert.IsTrue(JP('Integer(x)', rvUnknown) = ovNonString, 'Zahl-Cast');
  Assert.IsTrue(JP('(a + b)', rvUnknown) = ovNoOperand);
  Assert.IsTrue(JP('5', rvUnknown) = ovNoOperand);
  Assert.IsTrue(JP('a and b', rvUnknown) = ovNoOperand);
end;

procedure TTestRdxRecipes.Format_ByCompiler_Listed;
var
  Parts : TRdxParts;
  B     : TRdxFormatBuild;
begin
  Parts := [Target('s'), Lit('''Fehler '''), Op('E.Message', rvUnknown),
            Lit(''' in '''), Op('Name', rvString), Lit(''' / '''),
            Op('sLineBreak', rvUnknown)];
  Assert.IsTrue(TRdxRecipes.BuildFormatCall(Parts, B), B.Reason);
  Assert.AreEqual('Format(''Fehler %s in %s / %s'', [E.Message, Name, sLineBreak])',
    B.NewText);
  Assert.AreEqual<Integer>(3, B.Operands);
  Assert.AreEqual<Integer>(2, B.Proven, 'Name (deklariert) und sLineBreak (RTL)');
  Assert.AreEqual<Integer>(1, Length(B.ByCompiler));
  Assert.AreEqual('E.Message', B.ByCompiler[0]);
  Assert.AreEqual<Integer>(0, B.Numeric);
end;

procedure TTestRdxRecipes.Format_IntegerArgs_UseDAndU;
var
  Parts : TRdxParts;
  B     : TRdxFormatBuild;
begin
  Parts := [Lit('''n='''),
            TRdxRecipes.MakePart(ROLE_OPERAND, 'IntToStr(n)', rvString, '', 'integer'),
            Lit(''' c='''),
            TRdxRecipes.MakePart(ROLE_OPERAND, 'IntToStr(c)', rvString, '', 'cardinal'),
            Lit(''' i='''),
            TRdxRecipes.MakePart(ROLE_OPERAND, 'i.ToString', rvString, '', 'int64'),
            Lit(''' x='''),
            TRdxRecipes.MakePart(ROLE_OPERAND, 'IntToStr(x)', rvString, '', ''),
            Lit(''' s='''),
            TRdxRecipes.MakePart(ROLE_OPERAND, 'IntToStr(a + b)', rvString, '', 'integer'),
            Lit(''' b='''),
            TRdxRecipes.MakePart(ROLE_OPERAND, 'b.ToString', rvString, '', 'boolean')];
  Assert.IsTrue(TRdxRecipes.BuildFormatCall(Parts, B), B.Reason);
  Assert.AreEqual(
    'Format(''n=%d c=%u i=%d x=%s s=%s b=%s'', [n, c, i, IntToStr(x), IntToStr(a + b), b.ToString])',
    B.NewText);
  Assert.AreEqual<Integer>(3, B.Numeric);
  Assert.AreEqual<Integer>(6, B.Proven);
  Assert.AreEqual('%d', TRdxRecipes.IntegerSpec('byte'));
  Assert.AreEqual('%u', TRdxRecipes.IntegerSpec('uint64'));
  Assert.AreEqual('', TRdxRecipes.IntegerSpec('double'));
  Assert.AreEqual('x', TRdxRecipes.IntegerArgumentOf('IntToStr( x )'));
  Assert.AreEqual('x', TRdxRecipes.IntegerArgumentOf('x.ToString()'));
  Assert.AreEqual('', TRdxRecipes.IntegerArgumentOf('IntToStr(x + 1)'));
  Assert.AreEqual('', TRdxRecipes.IntegerArgumentOf('Obj.Count.ToString'));
end;

procedure TTestRdxRecipes.Format_VariantAndAnsi_Blocked;
var
  Parts : TRdxParts;
  B     : TRdxFormatBuild;
begin
  Parts := [Lit('''a'''), Op('Q.FieldByName(''x'').Value', rvUnknown),
            Lit('''b'''), Op('Name', rvString)];
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, B));
  Assert.IsTrue(Pos('Variant', B.Reason) > 0, B.Reason);
  Parts := [Lit('''a'''),
            TRdxRecipes.MakePart(ROLE_OPERAND, 'A', rvString, 'ansistring'),
            Lit('''b'''), Op('Name', rvString)];
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, B));
  Assert.IsTrue(Pos('UnicodeString', B.Reason) > 0, B.Reason);
  Parts := [Lit('''a'''),
            TRdxRecipes.MakePart(ROLE_OPERAND, 'V', rvUnknown, 'variant'),
            Lit('''b'''), Op('Name', rvString)];
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, B));
  Assert.IsTrue(Pos('Variant', B.Reason) > 0, B.Reason);
  Parts := [Lit('''a'''), Op('Integer(x)', rvUnknown), Lit('''b'''), Op('Name', rvString)];
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, B));
  Assert.IsTrue(Pos('kein String', B.Reason) > 0, B.Reason);
end;

procedure TTestRdxRecipes.Format_SqlText_Blocked;
var
  Parts   : TRdxParts;
  NewText : string;
  Reason  : string;
begin
  Parts := [Lit('''SELECT * FROM t WHERE id = '''), Op('IntToStr(Id)', rvString)];
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, NewText, Reason));
  Assert.IsTrue(Pos('SCA003', Reason) > 0, Reason);
end;

procedure TTestRdxRecipes.Format_NoOperand_Blocked;
var
  Parts   : TRdxParts;
  NewText : string;
  Reason  : string;
begin
  Parts := [Lit('''a'''), Lit('''b''')];
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, NewText, Reason));
  Assert.IsTrue(Pos('Operand', Reason) > 0, Reason);
end;

procedure TTestRdxRecipes.Format_ArgumentRole_Blocked;
var
  Parts   : TRdxParts;
  NewText : string;
  Reason  : string;
begin
  Parts := [Target('Foo'), TRdxRecipes.MakePart(ROLE_ARGUMENT, 'a, b')];
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, NewText, Reason));
  Assert.IsTrue(Pos(ROLE_ARGUMENT, Reason) > 0, Reason);
end;

procedure TTestRdxRecipes.LooksLikeSql_NeedsVerbAndStructure;
begin
  Assert.IsTrue(TRdxRecipes.LooksLikeSql('select * from t where id='));
  Assert.IsTrue(TRdxRecipes.LooksLikeSql('DELETE FROM Orders'));
  Assert.IsTrue(TRdxRecipes.LooksLikeSql('update t set a='));
  Assert.IsFalse(TRdxRecipes.LooksLikeSql('Update available for '), 'Verb ohne Struktur');
  Assert.IsFalse(TRdxRecipes.LooksLikeSql('Copy from here to there'), 'Struktur ohne Verb');
  Assert.IsFalse(TRdxRecipes.LooksLikeSql('selected items: '), 'kein ganzes Wort');
end;

{ ---- SQL-Vorlage ---- }

procedure TTestRdxRecipes.QueryObject_Forms;
begin
  Assert.AreEqual('Query', TRdxRecipes.QueryObjectOf('Query.SQL.Text'));
  Assert.AreEqual('FDQuery1', TRdxRecipes.QueryObjectOf('FDQuery1.SQL.Add'));
  Assert.AreEqual('Cmd', TRdxRecipes.QueryObjectOf('Cmd.CommandText'));
  Assert.AreEqual('Self.FQ', TRdxRecipes.QueryObjectOf('Self.FQ.SQL.Text'));
  Assert.AreEqual('SQLText', TRdxRecipes.QueryObjectOf('SQLText'));
end;

procedure TTestRdxRecipes.SqlTemplate_Assign;
var
  Parts    : TRdxParts;
  Template : string;
  Reason   : string;
begin
  Parts := [Target('Query.SQL.Text'),
            Lit('''SELECT * FROM users WHERE id = '''), Op('Id', rvUnknown)];
  Assert.IsTrue(TRdxRecipes.BuildSqlTemplate('Query.SQL.Text', False, Parts, 2,
    Template, Reason), Reason);
  Assert.AreEqual(
    '  Query.SQL.Text := ''SELECT * FROM users WHERE id = :p1'';' + sLineBreak +
    '  Query.ParamByName(''p1'').Value := Id;', Template);
end;

procedure TTestRdxRecipes.SqlTemplate_Call;
var
  Parts    : TRdxParts;
  Template : string;
  Reason   : string;
begin
  Parts := [Target('Query.SQL.Add'),
            Lit('''SELECT * FROM t WHERE a = '''), Op('A', rvUnknown),
            Lit(''' AND b = '''), Op('B', rvUnknown)];
  Assert.IsTrue(TRdxRecipes.BuildSqlTemplate('Query.SQL.Add', True, Parts, 0,
    Template, Reason), Reason);
  Assert.AreEqual(
    'Query.SQL.Add(''SELECT * FROM t WHERE a = :p1 AND b = :p2'');' + sLineBreak +
    'Query.ParamByName(''p1'').Value := A;' + sLineBreak +
    'Query.ParamByName(''p2'').Value := B;', Template);
end;

procedure TTestRdxRecipes.SqlTemplate_QuotedParam_Unquoted;
var
  Parts    : TRdxParts;
  Template : string;
  Reason   : string;
begin
  // WHERE name=''' + Name + '''' -> der Parameter steht nicht in Quotes
  Parts := [Target('Q.SQL.Text'),
            Lit('''SELECT * FROM u WHERE name='''''''), Op('Name', rvUnknown),
            Lit('''''''''')];
  Assert.IsTrue(TRdxRecipes.BuildSqlTemplate('Q.SQL.Text', False, Parts, 0,
    Template, Reason), Reason);
  Assert.IsTrue(Pos('WHERE name=:p1''', Template) > 0, Template);
  Assert.IsFalse(Pos(''':p1''', Template) > 0, 'kein Parameter in Quotes');
end;

procedure TTestRdxRecipes.SqlTemplate_ArgumentRole_Blocked;
var
  Parts    : TRdxParts;
  Template : string;
  Reason   : string;
begin
  Parts := [Target('ExecuteFmt'), TRdxRecipes.MakePart(ROLE_ARGUMENT, '''x'''),
            TRdxRecipes.MakePart(ROLE_ARGUMENT, '[a]')];
  Assert.IsFalse(TRdxRecipes.BuildSqlTemplate('ExecuteFmt', True, Parts, 0,
    Template, Reason));
  Assert.IsTrue(Pos('Argument', Reason) > 0, Reason);
end;

{ ---- uses ---- }

procedure TTestRdxRecipes.Framework_FromUnitNames;
begin
  Assert.IsTrue(TRdxRecipes.DetectFramework(['System.Math', 'Vcl.Forms']) = fwVcl);
  Assert.IsTrue(TRdxRecipes.DetectFramework(['FMX.Types', 'SysUtils']) = fwFmx);
  Assert.IsTrue(TRdxRecipes.DetectFramework(['Vcl.Graphics', 'FMX.Graphics']) = fwBoth);
  Assert.IsTrue(TRdxRecipes.DetectFramework(['SysUtils', 'Classes']) = fwUnknown);
  Assert.IsTrue(TRdxRecipes.DetectFramework(nil) = fwUnknown);
end;

procedure TTestRdxRecipes.HasUnit_ShortAndQualified;
begin
  Assert.IsTrue(TRdxRecipes.HasUnit(['System.Math'], 'Math'));
  Assert.IsTrue(TRdxRecipes.HasUnit(['sysutils'], 'SysUtils'));
  Assert.IsFalse(TRdxRecipes.HasUnit(['System.Types'], 'Math'));
  Assert.IsFalse(TRdxRecipes.HasUnit(nil, 'Math'));
end;

procedure TTestRdxRecipes.UsesNameFor_FollowsFileStyle;
begin
  // Ohne Vorbild oder mit qualifizierten Eintraegen: qualifiziert.
  Assert.AreEqual('System.Math', TRdxRecipes.UsesNameFor(nil, 'Math', 'System.Math'));
  Assert.AreEqual('System.Math',
    TRdxRecipes.UsesNameFor(['Rdx.Fake', 'Windows'], 'Math', 'System.Math'));
  // Nur Kurznamen: der Kurzname, damit die Klausel einheitlich bleibt.
  Assert.AreEqual('Math',
    TRdxRecipes.UsesNameFor(['Classes', 'Windows'], 'Math', 'System.Math'));
end;

procedure TTestRdxRecipes.IsSortedUses_CompareText;
begin
  Assert.IsTrue(TRdxRecipes.IsSortedUses(nil));
  Assert.IsTrue(TRdxRecipes.IsSortedUses(['Classes']));
  Assert.IsTrue(TRdxRecipes.IsSortedUses(['classes', 'Windows']),
    'ohne Beachtung der Schreibung - wie SCA142');
  Assert.IsTrue(TRdxRecipes.IsSortedUses(['System.Classes', 'System.Math', 'Vcl.Forms']));
  Assert.IsFalse(TRdxRecipes.IsSortedUses(['Windows', 'Classes']));
  Assert.IsFalse(TRdxRecipes.IsSortedUses(['System.Math', 'System.Classes']));
end;

procedure TTestRdxRecipes.SortedInsertIndex_KeepsOrder_UnsortedGoesFront;
begin
  Assert.AreEqual<Integer>(0, TRdxRecipes.SortedInsertIndex(nil, 'System.Math'),
    'leere Liste: anhaengen = Index 0');
  Assert.AreEqual<Integer>(1,
    TRdxRecipes.SortedInsertIndex(['System.Classes', 'Vcl.Forms'], 'System.Math'));
  Assert.AreEqual<Integer>(0,
    TRdxRecipes.SortedInsertIndex(['System.Types'], 'System.Math'));
  Assert.AreEqual<Integer>(2,
    TRdxRecipes.SortedInsertIndex(['Classes', 'Forms'], 'Math'),
    'groesser als alle: anhaengen');
  Assert.AreEqual<Integer>(0,
    TRdxRecipes.SortedInsertIndex(['Windows', 'Classes'], 'Math'),
    'unsortiert: vorn');
end;

procedure TTestRdxRecipes.Scope_Load_IgnoresCommentsAndDedupes;
var
  T : TRdxScopeTable;
begin
  T := MakeTable(['# Kommentar', '', 'forms=FMX.Forms;Vcl.Forms',
                  'adsconst=Web.Win.ADSConst;Web.Win.AdsConst', 'kaputt']);
  try
    Assert.AreEqual<Integer>(2, T.Count);
    Assert.AreEqual<Integer>(2, Length(T.Candidates('Forms')));
    Assert.AreEqual<Integer>(1, Length(T.Candidates('AdsConst')),
      'Gross/Klein-Dubletten fallen zusammen');
    Assert.AreEqual<Integer>(0, Length(T.Candidates('nix')));
  finally
    T.Free;
  end;
end;

procedure TTestRdxRecipes.Scope_Resolve_VclAndFmx;
var
  T      : TRdxScopeTable;
  Q, Why : string;
begin
  T := MakeTable(['forms=FMX.Forms;Vcl.Forms']);
  try
    Assert.IsTrue(T.Resolve('Forms', fwVcl, Q, Why), Why);
    Assert.AreEqual('Vcl.Forms', Q);
    Assert.IsTrue(T.Resolve('Forms', fwFmx, Q, Why), Why);
    Assert.AreEqual('FMX.Forms', Q);
  finally
    T.Free;
  end;
end;

procedure TTestRdxRecipes.Scope_Resolve_CommonBeforeFramework;
var
  T      : TRdxScopeTable;
  Q, Why : string;
begin
  // 'Types' in einem FMX-Projekt ist System.Types: System steht in der
  // Scope-Liste VOR FMX.
  // (System.Math statt System.SysUtils: der FPC-Pruefstand schreibt den
  // Namen SysUtils in allen kopierten Quellen um.)
  T := MakeTable(['types=FMX.Types;System.Types', 'math=System.Math']);
  try
    Assert.IsTrue(T.Resolve('Types', fwFmx, Q, Why), Why);
    Assert.AreEqual('System.Types', Q);
    Assert.IsTrue(T.Resolve('Math', fwUnknown, Q, Why), Why);
    Assert.AreEqual('System.Math', Q);
  finally
    T.Free;
  end;
end;

procedure TTestRdxRecipes.Scope_Resolve_Unknown_NotGuessed;
var
  T      : TRdxScopeTable;
  Q, Why : string;
begin
  T := MakeTable(['forms=FMX.Forms;Vcl.Forms']);
  try
    Assert.IsFalse(T.Resolve('Forms', fwUnknown, Q, Why));
    Assert.IsTrue(Pos('Rahmenwerk', Why) > 0, Why);
    Assert.IsFalse(T.Resolve('Forms', fwBoth, Q, Why));
    Assert.IsFalse(T.Resolve('MyUnit', fwVcl, Q, Why));
    Assert.IsTrue(Pos('nicht in der Scope-Tabelle', Why) > 0, Why);
  finally
    T.Free;
  end;
end;

procedure TTestRdxRecipes.Scope_Resolve_AlreadyQualified_IsFalse;
var
  T      : TRdxScopeTable;
  Q, Why : string;
begin
  // Idempotenz: ein zweiter Lauf ueber eine schon expandierte Klausel
  // findet nichts mehr zu tun.
  T := MakeTable(['math=System.Math']);
  try
    Assert.IsFalse(T.Resolve('System.Math', fwVcl, Q, Why));
    Assert.IsTrue(Pos('bereits', Why) > 0, Why);
  finally
    T.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxRecipes);

end.
