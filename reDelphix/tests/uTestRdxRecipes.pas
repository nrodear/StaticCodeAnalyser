unit uTestRdxRecipes;

// Tests fuer die Rezepte (uRdxRecipes) und die Scope-Tabelle
// (uRdxScopeTable) des Moduls reDelphix. Reine Textlogik - laufen unter
// DUnitX in Delphi und im FPC-Pruefstand (reDelphix\tools\fpc-pruefstand).
//
// Was hier festgepinnt wird:
//   * Literal-Codec: Quelltext <-> Wert, Roundtrip, Fehlformen
//   * Format()-Bau nach der Kompilat-Regel (JudgeOperand, AH20): bewiesen /
//     laut Kompilat / gesperrt (Variant-Anzeichen, Zahl, Nicht-Unicode-
//     String, AnsiChar - deklariert wie als Cast), Char als string(x),
//     '%' -> '%%', Sperre fuer SQL-Text (SCA003), Sperre ohne Operand
//     im with-Block beweist kein Name etwas, IntToStr(x) wird nur %d/%u,
//     wenn der Core den Aufruf als RTL bewiesen hat
//   * SQL-Vorlage: Zuweisung und Aufruf, Parameter nie in Quotes, ohne
//     Query-Objekt als Kommentar, Einrueckung mit Tabs bleibt Tabs
//   * Fund-Abgleich: Ziel und '+'-Zahl aus den Meldungen von SCA044/SCA003,
//     die '+'-Zaehlung von SCA044 auf dem Knotentext
//   * uses: Schreibweise der Datei (nur Delphi-Scopes zaehlen, FPC-Weiche
//     -> Kurzname), Nachlauf hinter dem letzten Eintrag ('in'-Pfad,
//     Kommentar)
//   * Rahmenwerk-Erkennung und Scope-Aufloesung in Compiler-Reihenfolge,
//     System/Vcl projektabhaengig ungeraten; die echte data\unitscopes.txt
//     schreibt die Praefixe wie DCC_Namespace (Winapi, Vcl, Datasnap)

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
    [Test] procedure Format_NoLiteralOrAlreadyFormat_Blocked;
    // AH22 (Verifikations-Workflow): Literal-Quelltext erhalten, Leerraum
    // in Literalen, Variant-Quellen ohne Tell, Klammergruppe, Ansi bei
    // Unicode-Ziel.
    [Test] procedure Format_KeepsLiteralSource;
    [Test] procedure CollapseCode_KeepsLiterals;
    [Test] procedure Judge_VariantSourcesAndParenGroup;
    [Test] procedure Format_AnsiOperand_UnicodeTarget_Allowed;
    // Review 2026-10-07 Blocker 1: ein AnsiChar bleibt gesperrt, auch bei
    // Unicode-Ziel - Format castet ordinal statt per Codepage.
    [Test] procedure Format_AnsiCharOperand_UnicodeTarget_Blocked;
    [Test] procedure LooksLikeSql_NeedsVerbAndStructure;
    // Review 2026-10-07: Char als string(x) (Minor 10), Ansi-Cast wie
    // Deklaration (Minor 12), Zahl-Aufruf gesperrt (Minor 13).
    [Test] procedure Format_CharOperand_WrappedAsString;
    [Test] procedure Format_AnsiCharCast_UnicodeTarget_Blocked;
    [Test] procedure Format_VariantPlusNumericCall_Blocked;
    // Review 2026-10-07, strittige Minor 1 und 3: with-Block und eine
    // vom Core zurueckgenommene RTL-Annahme.
    [Test] procedure Judge_InWith_NamesProveNothing;
    [Test] procedure Format_IntToStrNotProvenByCore_StaysCall;
    // Fund-Abgleich (Minor 20) und '+'-Gegenprobe (strittiger Minor 2).
    [Test] procedure PlusCount_LikeScanConcat;
    [Test] procedure FindingTarget_Sca044AndSca003;

    // ---- SQL-Vorlage ---------------------------------------------------
    [Test] procedure QueryObject_Forms;
    [Test] procedure SqlTemplate_Assign;
    [Test] procedure SqlTemplate_Call;
    [Test] procedure SqlTemplate_QuotedParam_Unquoted;
    [Test] procedure SqlTemplate_ArgumentRole_Blocked;
    // Review 2026-10-07 Minor 24: String-Puffer statt Query-Objekt.
    [Test] procedure SqlTemplate_PlainStringTarget;
    // Minor 31: Tab-Einrueckung bleibt Tab-Einrueckung.
    [Test] procedure SqlTemplate_TabIndent_KeepsTabs;

    // ---- uses ----------------------------------------------------------
    [Test] procedure Framework_FromUnitNames;
    [Test] procedure HasUnit_ShortAndQualified;
    // uses-Klausel ergaenzen (AH19): Schreibweise der Datei, Sortierung
    // wie SCA142, Einfuegestelle.
    [Test] procedure UsesNameFor_FollowsFileStyle;
    // Minor 35: FPC-Weiche erkennen.
    [Test] procedure LineLooksFpcAware_Tells;
    // Minor 42 / strittiger Nit 5: wo hinter dem letzten Eintrag
    // angehaengt werden darf.
    [Test] procedure UsesTail_PathCommentSemicolon;
    [Test] procedure IsSortedUses_CompareText;
    [Test] procedure SortedInsertIndex_KeepsOrder_UnsortedGoesFront;
    [Test] procedure Scope_Load_IgnoresCommentsAndDedupes;
    [Test] procedure Scope_Resolve_VclAndFmx;
    [Test] procedure Scope_Resolve_CommonBeforeFramework;
    [Test] procedure Scope_Resolve_Unknown_NotGuessed;
    [Test] procedure Scope_Resolve_AlreadyQualified_IsFalse;
    // Review 2026-10-07 Minor 14: System.Skia gegen Vcl.Skia.
    [Test] procedure Scope_Resolve_VclVsSystem_Ambiguous_NotGuessed;
    // Review 2026-10-07 Nit 19: die eingecheckte Tabelle.
    [Test] procedure Scope_RealTable_PrefixSpelling;
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
  // Review 2026-10-07 Minor 12: Cast und RTL-Aufruf mit Ansi-Ergebnis
  // urteilen wie die Deklaration - nicht die Schreibweise entscheidet.
  Assert.IsTrue(JP('AnsiString(A)', rvUnknown) = ovAnsi, 'Cast auf AnsiString');
  Assert.IsTrue(JP('UTF8String(x)', rvUnknown) = ovAnsi);
  Assert.IsTrue(JP('RawByteString(x)', rvUnknown) = ovAnsi);
  Assert.IsTrue(JP('ShortString(x)', rvUnknown) = ovAnsi);
  Assert.IsTrue(JP('AnsiChar(b)', rvUnknown) = ovAnsi);
  Assert.IsTrue(JP('UTF8Encode(S)', rvUnknown) = ovAnsi, 'RawByteString-Ergebnis');
  Assert.IsTrue(JP('AnsiToUtf8(S)', rvUnknown) = ovAnsi);
  Assert.IsTrue(JP('SysUtils.Utf8ToAnsi(S)', rvUnknown) = ovAnsi);
  Assert.IsTrue(JP('Obj.UTF8Encode(S)', rvUnknown) = ovByCompiler,
    'Methode unbekannten Typs, nicht die RTL');
  Assert.IsTrue(JP('UTF8ToString(S)', rvUnknown) = ovString,
    'Unicode-Ergebnis bleibt String');
  // Minor 13: Aufrufe mit Zahl-Ergebnis sperren wie ein Zahl-Cast.
  Assert.IsTrue(JP('Length(Marker)', rvUnknown) = ovNonString, 'Length');
  Assert.IsTrue(JP('Ord(c)', rvUnknown) = ovNonString);
  Assert.IsTrue(JP('Round(x)', rvUnknown) = ovNonString);
  Assert.IsTrue(JP('StrToIntDef(s, 0)', rvUnknown) = ovNonString);
  Assert.IsTrue(JP('Obj.Length(x)', rvUnknown) = ovByCompiler,
    'Methode unbekannten Typs');
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
  // i.ToString bleibt %s: ein eigener Integer-Helper koennte anders
  // formatieren als IntToStr (AH22).
  Assert.AreEqual(
    'Format(''n=%d c=%u i=%s x=%s s=%s b=%s'', [n, c, i.ToString, IntToStr(x), IntToStr(a + b), b.ToString])',
    B.NewText);
  Assert.AreEqual<Integer>(2, B.Numeric);
  Assert.AreEqual<Integer>(6, B.Proven);
  Assert.AreEqual('%d', TRdxRecipes.IntegerSpec('byte'));
  Assert.AreEqual('%u', TRdxRecipes.IntegerSpec('uint64'));
  Assert.AreEqual('', TRdxRecipes.IntegerSpec('double'));
  Assert.AreEqual('x', TRdxRecipes.IntegerArgumentOf('IntToStr( x )'));
  Assert.AreEqual('', TRdxRecipes.IntegerArgumentOf('x.ToString()'), 'ToString bleibt %s');
  Assert.AreEqual('', TRdxRecipes.IntegerArgumentOf('IntToStr(x + 1)'));
  Assert.AreEqual('', TRdxRecipes.IntegerArgumentOf('Obj.Count.ToString'));
end;

procedure TTestRdxRecipes.Format_KeepsLiteralSource;
var
  Parts : TRdxParts;
  B     : TRdxFormatBuild;
begin
  // Die Literale werden Token fuer Token uebernommen: #$2103 bleibt als
  // Code stehen (in einer ANSI-Datei waere das rohe Zeichen verloren),
  // #13 bleibt dezimal, '' bleibt '', '%' wird '%%', #37 (= '%') wird ''%%''.
  Parts := [Lit('''Temp: '''), Op('T', rvString), Lit('#$2103'), Lit(''' at '''),
            Op('Place', rvString)];
  Assert.IsTrue(TRdxRecipes.BuildFormatCall(Parts, B), B.Reason);
  Assert.AreEqual('Format(''Temp: %s''#$2103'' at %s'', [T, Place])', B.NewText);
  Parts := [Lit('''a''#13#10''b'''), Op('T', rvString), Lit('#37'), Lit('''it''''s 5%''')];
  Assert.IsTrue(TRdxRecipes.BuildFormatCall(Parts, B), B.Reason);
  Assert.AreEqual('Format(''a''#13#10''b%s%%it''''s 5%%'', [T])', B.NewText);
  Parts := [Lit('#13#10'), Op('T', rvString)];
  Assert.IsTrue(TRdxRecipes.BuildFormatCall(Parts, B), B.Reason);
  Assert.AreEqual('Format(#13#10''%s'', [T])', B.NewText);
end;

procedure TTestRdxRecipes.CollapseCode_KeepsLiterals;
begin
  Assert.AreEqual('StringReplace(S, ''  '', '' '', [rfReplaceAll])',
    TRdxRecipes.CollapseCode('StringReplace(S,  ''  '',   '' '','#13#10'    [rfReplaceAll])'));
  Assert.AreEqual('Foo( a, b )', TRdxRecipes.CollapseCode('  Foo( a,'#9'b )  '),
    'Leerraum ausserhalb von Literalen wird zu einem Leerzeichen, nicht entfernt');
  Assert.AreEqual('''a''''b  c''', TRdxRecipes.CollapseCode('''a''''b  c'''),
    'Quote-Verdopplung und Leerraum im Literal bleiben');
  Assert.AreEqual('x', TRdxRecipes.CollapseCode('x'));
  Assert.AreEqual('', TRdxRecipes.CollapseCode('   '));
end;

procedure TTestRdxRecipes.Judge_VariantSourcesAndParenGroup;
var
  P : TRdxPart;
begin
  // String-indizierter Bezeichner: TDataSet.FieldValues (Variant).
  Assert.IsTrue(JP('DS[''Name'']', rvUnknown) = ovVariantRisk);
  Assert.IsTrue(JP('DS [ ''Name'' ]', rvUnknown) = ovVariantRisk);
  // Gegenstueck 'Items[i]' (Zahl-Index bleibt Kompilat): Judge_TextTells.
  Assert.IsTrue(JP('DS[''Name''].AsString', rvUnknown) = ovByCompiler, 'dahinter steht noch etwas');
  // Kopf-Bezeichner deklariert Variant: V.Name, V[0].
  P := TRdxRecipes.MakePart(ROLE_OPERAND, 'V.Name', rvUnknown);
  P.HeadResolved := 'variant';
  Assert.IsTrue(TRdxRecipes.JudgeOperand(P) = ovVariantRisk);
  P.HeadResolved := 'tobject';
  Assert.IsTrue(TRdxRecipes.JudgeOperand(P) = ovByCompiler);
  Assert.AreEqual('Obj', TRdxRecipes.HeadIdentOf('Obj.Items[i].Name'));
  Assert.AreEqual('Type', TRdxRecipes.HeadIdentOf('&Type.Name'));
  Assert.AreEqual('', TRdxRecipes.HeadIdentOf('(a + b)'));
  // Fuehrende Klammergruppe mit Member-Zugriff: Kompilat.
  Assert.IsTrue(TRdxRecipes.IsOperandShape('(Sender as TButton).Caption'));
  Assert.IsTrue(TRdxRecipes.IsOperandShape('(Items[i] as TFoo)[0]'));
  Assert.IsTrue(TRdxRecipes.IsOperandShape('(P)^.Name'));
  // Blosser Klammerausdruck '(a + b)': Shape_RejectsExpressions.
  Assert.IsFalse(TRdxRecipes.IsOperandShape('(a + b) c'));
  Assert.IsTrue(TRdxRecipes.IsOperandShape('Item.&Type'), '& hinter dem Punkt');
  Assert.IsTrue(JP('(Sender as TButton).Caption', rvUnknown) = ovByCompiler);
end;

procedure TTestRdxRecipes.Format_AnsiOperand_UnicodeTarget_Allowed;
var
  Parts : TRdxParts;
  B     : TRdxFormatBuild;
begin
  // Bei einem Unicode-Ziel wandelt Format den AnsiString-Operanden wie
  // die Zuweisung; ohne bekanntes Ziel bleibt die Sperre.
  Parts := [Lit('''a'''), TRdxRecipes.MakePart(ROLE_OPERAND, 'A', rvString, 'ansistring'),
            Lit('''b'''), Op('Name', rvString)];
  Assert.IsTrue(TRdxRecipes.BuildFormatCall(Parts, B, 'string'), B.Reason);
  Assert.AreEqual('Format(''a%sb%s'', [A, Name])', B.NewText);
  Assert.AreEqual<Integer>(2, B.Proven);
  Assert.IsTrue(TRdxRecipes.BuildFormatCall(Parts, B, 'widestring'), B.Reason);
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, B, ''));
  Assert.IsTrue(Pos('UnicodeString', B.Reason) > 0, B.Reason);
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, B, 'ansistring'));
end;

procedure TTestRdxRecipes.Format_AnsiCharOperand_UnicodeTarget_Blocked;
var
  Parts : TRdxParts;
  B     : TRdxFormatBuild;
begin
  // 'Preis: ' + ac + ' EUR' mit ac = #$80: die Verkettung ergibt das
  // Euro-Zeichen (Systemcodepage), Format('%s', [ac]) U+0080.
  Parts := [Lit('''Preis: '''),
            TRdxRecipes.MakePart(ROLE_OPERAND, 'ac', rvString, 'ansichar'),
            Lit(''' EUR''')];
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, B, 'unicodestring'));
  Assert.IsTrue(Pos('ansichar', B.Reason) > 0, B.Reason);
  Assert.IsTrue(Pos('Codepage', B.Reason) > 0, B.Reason);
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, B, 'widestring'));
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, B, ''));
end;

procedure TTestRdxRecipes.Format_CharOperand_WrappedAsString;
var
  Parts : TRdxParts;
  B     : TRdxFormatBuild;
begin
  // 'KEY=' + Value + Term mit Term = #0: die Verkettung endet auf #0,
  // Format('%s', [Term]) haengt bei vtWideChar ueber StrLen nichts an.
  // string(Term) laeuft ueber vtUnicodeString mit Laenge.
  Parts := [Target('S'), Lit('''KEY='''), Op('Value', rvString),
            TRdxRecipes.MakePart(ROLE_OPERAND, 'Term', rvString, 'char')];
  Assert.IsTrue(TRdxRecipes.BuildFormatCall(Parts, B), B.Reason);
  Assert.AreEqual('Format(''KEY=%s%s'', [Value, string(Term)])', B.NewText);
  Assert.AreEqual<Integer>(2, B.Proven, 'der Cast aendert die Herkunft nicht');
  // WideChar, Chr(...) und Char-Cast ebenso; ein Char UNBEKANNTEN Typs
  // ('S[i]') bleibt ohne Cast (bekannte Grenze). ByCompiler nennt den
  // Operanden wie geschrieben.
  Parts := [Lit('''a'''), TRdxRecipes.MakePart(ROLE_OPERAND, 'w', rvString, 'widechar'),
            Lit('''b'''), Op('Chr(0)', rvUnknown), Lit('''c'''), Op('Char(n)', rvUnknown),
            Lit('''d'''), Op('S[i]', rvUnknown)];
  Assert.IsTrue(TRdxRecipes.BuildFormatCall(Parts, B), B.Reason);
  Assert.AreEqual(
    'Format(''a%sb%sc%sd%s'', [string(w), string(Chr(0)), string(Char(n)), S[i]])',
    B.NewText);
  Assert.AreEqual<Integer>(2, Length(B.ByCompiler));
  Assert.AreEqual('Char(n)', B.ByCompiler[0]);
  // ShortString (vtString, ebenfalls ohne Laenge) - nur bei Unicode-Ziel
  // zugelassen, dann ebenso als string(x).
  Parts := [Lit('''a'''),
            TRdxRecipes.MakePart(ROLE_OPERAND, 'SS', rvString, 'shortstring'),
            Lit('''b''')];
  Assert.IsTrue(TRdxRecipes.BuildFormatCall(Parts, B, 'string'), B.Reason);
  Assert.AreEqual('Format(''a%sb'', [string(SS)])', B.NewText);
end;

procedure TTestRdxRecipes.Format_AnsiCharCast_UnicodeTarget_Blocked;
var
  Parts : TRdxParts;
  B     : TRdxFormatBuild;
begin
  // Der Cast 'AnsiChar(b)' ist derselbe Typ wie ein deklariertes
  // AnsiChar: auch bei Unicode-Ziel gesperrt (FormatBuf castet ordinal).
  Parts := [Lit('''Preis: '''), Op('AnsiChar(b)', rvUnknown), Lit(''' EUR''')];
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, B, 'unicodestring'));
  Assert.IsTrue(Pos('ansichar', B.Reason) > 0, B.Reason);
  Assert.IsTrue(Pos('Codepage', B.Reason) > 0, B.Reason);
  // Der Cast auf AnsiString wandelt bei Unicode-Ziel wie die Zuweisung
  // (vtAnsiString mit Codepage); ohne bekanntes Ziel bleibt er gesperrt.
  Parts := [Lit('''a'''), Op('AnsiString(A)', rvUnknown), Lit('''b''')];
  Assert.IsTrue(TRdxRecipes.BuildFormatCall(Parts, B, 'string'), B.Reason);
  Assert.AreEqual('Format(''a%sb'', [AnsiString(A)])', B.NewText);
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, B, ''));
  Assert.IsTrue(Pos('ansistring - Format liefert UnicodeString', B.Reason) > 0,
    B.Reason);
  // RTL-Aufruf mit Ansi-Ergebnis: ohne Typnamen nennt der Grund das
  // Ansi-Ergebnis.
  Parts := [Lit('''a'''), Op('UTF8Encode(S)', rvUnknown), Lit('''b''')];
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, B, ''));
  Assert.IsTrue(Pos('Ansi-Ergebnis', B.Reason) > 0, B.Reason);
end;

procedure TTestRdxRecipes.Format_VariantPlusNumericCall_Blocked;
var
  Parts : TRdxParts;
  B     : TRdxFormatBuild;
begin
  // 'a' + Obj.Data + Length(Marker) uebersetzt nur, wenn Obj.Data ein
  // Variant ist (ohne Anzeichen) - Format('a%s%s', [...]) wuerfe dann
  // EConvertError (vtInteger hinter %s).
  Parts := [Target('Text'), Lit('''a'''), Op('Obj.Data', rvUnknown),
            Op('Length(Marker)', rvUnknown)];
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, B));
  Assert.IsTrue(Pos('''Length(Marker)'': kein String', B.Reason) > 0, B.Reason);
end;

procedure TTestRdxRecipes.Judge_InWith_NamesProveNothing;
var
  P : TRdxPart;
begin
  // 'with Obj do r := ''a'' + ExtractFileName(F) + ...': der Name kann an
  // eine Methode von Obj binden. Ausserhalb bewiesen, im with-Block nur
  // noch laut Kompilat (strittiger Minor 1).
  P := TRdxRecipes.MakePart(ROLE_OPERAND, 'ExtractFileName(F)', rvUnknown);
  Assert.IsTrue(TRdxRecipes.JudgeOperand(P) = ovString, 'ausserhalb: RTL');
  P.InWith := True;
  Assert.IsTrue(TRdxRecipes.JudgeOperand(P) = ovByCompiler, 'RTL-Funktion im with');
  P := TRdxRecipes.MakePart(ROLE_OPERAND, 'sLineBreak', rvUnknown);
  P.InWith := True;
  Assert.IsTrue(TRdxRecipes.JudgeOperand(P) = ovByCompiler, 'RTL-Konstante im with');
  P := TRdxRecipes.MakePart(ROLE_OPERAND, 'Fn', rvUnknown, 'tfilename');
  P.InWith := True;
  Assert.IsTrue(TRdxRecipes.JudgeOperand(P) = ovByCompiler, 'Typ-Alias im with');
  // Was sperrt, sperrt auch im with-Block weiter.
  P := TRdxRecipes.MakePart(ROLE_OPERAND, 'A', rvUnknown, 'ansistring');
  P.InWith := True;
  Assert.IsTrue(TRdxRecipes.JudgeOperand(P) = ovAnsi);
  P := TRdxRecipes.MakePart(ROLE_OPERAND, 'V', rvUnknown, 'variant');
  P.InWith := True;
  Assert.IsTrue(TRdxRecipes.JudgeOperand(P) = ovVariantRisk);
  P := TRdxRecipes.MakePart(ROLE_OPERAND, 'Length(S)', rvUnknown);
  P.InWith := True;
  Assert.IsTrue(TRdxRecipes.JudgeOperand(P) = ovNonString);
  Assert.IsFalse(TRdxRecipes.MakePart(ROLE_OPERAND, 'x').InWith,
    'MakePart setzt InWith zurueck');
end;

procedure TTestRdxRecipes.Format_IntToStrNotProvenByCore_StaysCall;
var
  Parts : TRdxParts;
  B     : TRdxFormatBuild;
  P     : TRdxPart;
begin
  // Der Core liefert IntToStr(n) als rvString nur, wenn der Name die RTL
  // meint; deklariert die Unit 'function IntToStr(..): Variant', nimmt er
  // das zurueck (rvUnknown). Dann darf aus IntToStr(n) kein %d mit n
  // werden - die eigene Funktion formatiert vielleicht anders
  // (strittiger Minor 3). Der Aufruf bleibt stehen, laut Kompilat.
  Parts := [Lit('''n='''),
            TRdxRecipes.MakePart(ROLE_OPERAND, 'IntToStr(n)', rvUnknown, '', 'integer')];
  Assert.IsTrue(TRdxRecipes.BuildFormatCall(Parts, B), B.Reason);
  Assert.AreEqual('Format(''n=%s'', [IntToStr(n)])', B.NewText);
  Assert.AreEqual<Integer>(0, B.Numeric);
  Assert.AreEqual<Integer>(1, Length(B.ByCompiler));
  // Ebenso im with-Block, auch wenn der Core rvString meldet.
  P := TRdxRecipes.MakePart(ROLE_OPERAND, 'IntToStr(n)', rvString, '', 'integer');
  P.InWith := True;
  Parts := [Lit('''n='''), P];
  Assert.IsTrue(TRdxRecipes.BuildFormatCall(Parts, B), B.Reason);
  Assert.AreEqual('Format(''n=%s'', [IntToStr(n)])', B.NewText);
  Assert.AreEqual<Integer>(0, B.Numeric);
end;

procedure TTestRdxRecipes.PlusCount_LikeScanConcat;
begin
  // Die Zaehlung von SCA044 (ScanConcat) auf dem abgeflachten Knotentext.
  Assert.AreEqual<Integer>(3, TRdxRecipes.TopLevelPlusCount('''a''+Marker+''b''+Tag'));
  Assert.AreEqual<Integer>(1, TRdxRecipes.TopLevelPlusCount('''a+b''+x'), '+ im String');
  Assert.AreEqual<Integer>(1, TRdxRecipes.TopLevelPlusCount('''it''''s +''+x'), ''' im String');
  Assert.AreEqual<Integer>(2, TRdxRecipes.TopLevelPlusCount('Foo(a+b)+c[1+2]+d'),
    'Klammer- und Indextiefe');
  Assert.AreEqual<Integer>(1, TRdxRecipes.TopLevelPlusCount('a)+b'),
    'eine ueberzaehlige Klammer macht die Tiefe nicht negativ');
  Assert.AreEqual<Integer>(0, TRdxRecipes.TopLevelPlusCount('Format(''%s'', [x])'));
  Assert.AreEqual<Integer>(-1, TRdxRecipes.TopLevelPlusCount('  '));
end;

procedure TTestRdxRecipes.FindingTarget_Sca044AndSca003;
var
  T : string;
  P : Integer;
begin
  // SCA044 (uConcatToFormat): 'Concat (%d x ''+'') -> Format(...) %s'.
  Assert.IsTrue(TRdxRecipes.ConcatFindingTarget(
    'Concat (3 x ''+'') -> Format(...) Arr[]', T, P));
  Assert.AreEqual('Arr[]', T);
  Assert.AreEqual<Integer>(3, P);
  Assert.IsTrue(TRdxRecipes.ConcatFindingTarget(
    'Concat (12 x ''+'') -> Format(...) Self.FName', T, P));
  Assert.AreEqual('Self.FName', T);
  Assert.AreEqual<Integer>(12, P);
  Assert.IsFalse(TRdxRecipes.ConcatFindingTarget('etwas anderes', T, P));
  Assert.AreEqual('', T);
  Assert.AreEqual<Integer>(-1, P);
  Assert.IsFalse(TRdxRecipes.ConcatFindingTarget(
    'Concat (x x ''+'') -> Format(...) A', T, P), 'Zahl nicht lesbar');
  Assert.IsFalse(TRdxRecipes.ConcatFindingTarget(
    'Concat (3 x ''+'') -> Format(...) ', T, P), 'ohne Ziel');
  // SCA003 (uSQLInjection): Ziel, zwei Leerzeichen, Schaetzung.
  Assert.AreEqual('Query.SQL.Add()',
    TRdxRecipes.SqlFindingTarget('Query.SQL.Add()  [Fix 1/5 [*    ] (Trivial)]'));
  Assert.AreEqual('S', TRdxRecipes.SqlFindingTarget('S  [Fix 2/5 [**   ] (Leicht)]'));
  Assert.AreEqual('', TRdxRecipes.SqlFindingTarget('ohne Schaetzung'));
  // Vergleichsform: ein Aufruf zaehlt als 'Kopf()'.
  Assert.AreEqual('Q.SQL.Add()', TRdxRecipes.TargetKey('Q.SQL.Add(''x''+y)'));
  Assert.AreEqual('Q.SQL.Add()', TRdxRecipes.TargetKey('Q.SQL.Add ()'));
  Assert.AreEqual('Text', TRdxRecipes.TargetKey(' Text '));
  Assert.AreEqual('Arr[]', TRdxRecipes.TargetKey('Arr[]'));
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
  // Ansi als Cast, ohne Ziel (Vorgabe ''): gesperrt wie deklariert, der
  // Grund nennt den Cast-Typ (Minor 12). Der deklarierte AnsiString
  // ohne Ziel steht in Format_AnsiOperand_UnicodeTarget_Allowed.
  Parts := [Lit('''a'''), Op('RawByteString(R)', rvUnknown),
            Lit('''b'''), Op('Name', rvString)];
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, B));
  Assert.IsTrue(Pos('rawbytestring - Format liefert UnicodeString', B.Reason) > 0,
    B.Reason);
  Parts := [Lit('''a'''),
            TRdxRecipes.MakePart(ROLE_OPERAND, 'V', rvUnknown, 'variant'),
            Lit('''b'''), Op('Name', rvString)];
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, B));
  Assert.IsTrue(Pos('Variant', B.Reason) > 0, B.Reason);
  Parts := [Lit('''a'''), Op('Integer(x)', rvUnknown), Lit('''b'''), Op('Name', rvString)];
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, B));
  Assert.IsTrue(Pos('kein String', B.Reason) > 0, B.Reason);
end;

procedure TTestRdxRecipes.Format_NoLiteralOrAlreadyFormat_Blocked;
var
  Parts : TRdxParts;
  B     : TRdxFormatBuild;
begin
  // Nur Operanden: '%s%s' waere keine Verbesserung.
  Parts := [Target('s'), Op('Name', rvString), Op('Tag', rvString)];
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, B));
  Assert.IsTrue(Pos('kein Literal', B.Reason) > 0, B.Reason);
  // Ein Format() in der Kette: nicht noch eines darum bauen (der
  // zweite Lauf ueber 'X := Format(...)' baute sonst Format('%s', [Format(...)])).
  Parts := [Lit('''a'''), Op('Format(''%d'', [n])', rvUnknown), Lit('''b'''), Op('Name', rvString)];
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, B));
  Assert.IsTrue(Pos('schon Format', B.Reason) > 0, B.Reason);
  Parts := [Op('SysUtils.Format(''%d'', [n])', rvUnknown)];
  Assert.IsFalse(TRdxRecipes.BuildFormatCall(Parts, B));
  Assert.IsTrue(Pos('schon Format', B.Reason) > 0, B.Reason);
  Assert.IsFalse(TRdxRecipes.IsKnownStringFunc('Format(''%d'', [n])'),
    'Format steht nicht in der Liste bewiesener RTL-Funktionen');
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
  // Paar-Regel (Review 2026-10-07, Nit 6): das Strukturwort muss zum
  // Verb passen und dahinter stehen; DDL braucht das Objekt direkt.
  Assert.IsFalse(TRdxRecipes.LooksLikeSql('Update available from server'),
    'update braucht set');
  Assert.IsFalse(TRdxRecipes.LooksLikeSql('Create a table of contents'),
    'kein DDL-Objekt direkt hinter create');
  Assert.IsFalse(TRdxRecipes.LooksLikeSql('Create or open a file'),
    'or ohne DDL-Objekt');
  Assert.IsFalse(TRdxRecipes.LooksLikeSql('from t select'),
    'Strukturwort vor dem Verb');
  Assert.IsTrue(TRdxRecipes.LooksLikeSql('DELETE Orders WHERE id='));
  Assert.IsTrue(TRdxRecipes.LooksLikeSql('UPDATE  SET a= WHERE id='),
    'Tabelle als Operand');
  Assert.IsTrue(TRdxRecipes.LooksLikeSql('SELECT  FROM '));
  Assert.IsTrue(TRdxRecipes.LooksLikeSql('INSERT INTO  VALUES ('));
  Assert.IsTrue(TRdxRecipes.LooksLikeSql('MERGE INTO t'));
  // noinspection SqlDangerousStatement (Testdaten: LooksLikeSql muss DDL ohne Objektnamen als SQL erkennen)
  Assert.IsTrue(TRdxRecipes.LooksLikeSql('DROP TABLE '));
  // noinspection SqlDangerousStatement (Testdaten: LooksLikeSql muss DDL ohne Objektnamen als SQL erkennen)
  Assert.IsTrue(TRdxRecipes.LooksLikeSql('TRUNCATE TABLE '));
  Assert.IsTrue(TRdxRecipes.LooksLikeSql('CREATE OR REPLACE VIEW v'));
  Assert.IsTrue(TRdxRecipes.LooksLikeSql('create unique index ix on '));
  Assert.IsTrue(TRdxRecipes.LooksLikeSql('Select a file from '),
    'bekannte Grenze: gueltiges SQL mit Alias');
end;

{ ---- SQL-Vorlage ---- }

procedure TTestRdxRecipes.QueryObject_Forms;
begin
  Assert.AreEqual('Query', TRdxRecipes.QueryObjectOf('Query.SQL.Text'));
  Assert.AreEqual('FDQuery1', TRdxRecipes.QueryObjectOf('FDQuery1.SQL.Add'));
  Assert.AreEqual('Cmd', TRdxRecipes.QueryObjectOf('Cmd.CommandText'));
  Assert.AreEqual('Self.FQ', TRdxRecipes.QueryObjectOf('Self.FQ.SQL.Text'));
  Assert.AreEqual('DM.SQLQuery1', TRdxRecipes.QueryObjectOf('DM.SQLQuery1.SQL.Text'),
    'das Glied .SQL ganz, nicht der Anfang von .SQLQuery1');
  // Ein blosser Bezeichner kommt unveraendert zurueck - das ist KEIN
  // Query-Objekt; BuildSqlTemplate fragt deshalb HasQueryObject (Review
  // 2026-10-07, Minor 24; SqlTemplate_PlainStringTarget).
  Assert.AreEqual('SQLText', TRdxRecipes.QueryObjectOf('SQLText'));
  Assert.IsFalse(TRdxRecipes.HasQueryObject('SQLText'), 'String-Puffer');
  Assert.IsFalse(TRdxRecipes.HasQueryObject('Self.SQLText'), 'kein Glied .SQL');
  Assert.IsTrue(TRdxRecipes.HasQueryObject('Query.SQL.Text'));
  Assert.IsTrue(TRdxRecipes.HasQueryObject('FDQuery1.SQL.Add'));
  Assert.IsTrue(TRdxRecipes.HasQueryObject('Cmd.CommandText'));
end;

procedure TTestRdxRecipes.SqlTemplate_Assign;
var
  Parts    : TRdxParts;
  Template : string;
  Reason   : string;
begin
  Parts := [Target('Query.SQL.Text'),
            Lit('''SELECT * FROM users WHERE id = '''), Op('Id', rvUnknown)];
  Assert.IsTrue(TRdxRecipes.BuildSqlTemplate('Query.SQL.Text', False, Parts, '  ',
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
  Assert.IsTrue(TRdxRecipes.BuildSqlTemplate('Query.SQL.Add', True, Parts, '',
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
  Assert.IsTrue(TRdxRecipes.BuildSqlTemplate('Q.SQL.Text', False, Parts, '',
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
  Assert.IsFalse(TRdxRecipes.BuildSqlTemplate('ExecuteFmt', True, Parts, '',
    Template, Reason));
  Assert.IsTrue(Pos('Argument', Reason) > 0, Reason);
end;

procedure TTestRdxRecipes.SqlTemplate_PlainStringTarget;
var
  Parts    : TRdxParts;
  Template : string;
  Reason   : string;
begin
  // SCA003 meldet auch einen lokalen String-Puffer: 'S.ParamByName'
  // uebersetzte nicht - die Parameterzeilen werden Kommentar mit
  // Platzhalter, die SQL-Zeile bleibt.
  Parts := [Target('S'), Lit('''SELECT * FROM t WHERE id='''), Op('Id', rvUnknown)];
  Assert.IsTrue(TRdxRecipes.BuildSqlTemplate('S', False, Parts, '  ',
    Template, Reason), Reason);
  Assert.AreEqual(
    '  S := ''SELECT * FROM t WHERE id=:p1'';' + sLineBreak +
    '  // <Query>.ParamByName(''p1'').Value := Id;', Template);
end;

procedure TTestRdxRecipes.SqlTemplate_TabIndent_KeepsTabs;
var
  Parts    : TRdxParts;
  Template : string;
  Reason   : string;
begin
  // Die Einrueckung kommt als Text: zwei Tabs bleiben zwei Tabs, auch vor
  // den ParamByName-Zeilen (bis Minor 31 wurden es zwei Leerzeichen).
  Parts := [Target('Q.SQL.Text'), Lit('''SELECT * FROM t WHERE id='''),
            Op('Id', rvUnknown)];
  Assert.IsTrue(TRdxRecipes.BuildSqlTemplate('Q.SQL.Text', False, Parts, #9#9,
    Template, Reason), Reason);
  Assert.AreEqual(
    #9#9'Q.SQL.Text := ''SELECT * FROM t WHERE id=:p1'';' + sLineBreak +
    #9#9'Q.ParamByName(''p1'').Value := Id;', Template);
  // Gemischt bleibt gemischt; was kein Tab ist, wird ein Leerzeichen.
  Assert.AreEqual('  '#9, TRdxRecipes.IndentTextOf('  '#9));
  Assert.AreEqual('  '#9' ', TRdxRecipes.IndentTextOf('ab'#9'c'));
  Assert.AreEqual('', TRdxRecipes.IndentTextOf(''));
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
  // Ohne Vorbild oder mit einem Eintrag unter einem Delphi-Scope:
  // qualifiziert. (Keine 'System.SysUtils'/'System.Classes' im Test - der
  // FPC-Pruefstand schreibt diese Namen in den kopierten Quellen um.)
  Assert.AreEqual('System.Math', TRdxRecipes.UsesNameFor(nil, 'Math', 'System.Math'));
  Assert.AreEqual('System.Math',
    TRdxRecipes.UsesNameFor(['Classes', 'Winapi.Windows'], 'Math', 'System.Math'));
  Assert.AreEqual('System.Math',
    TRdxRecipes.UsesNameFor(['vcl.forms'], 'Math', 'System.Math'),
    'der Scope gilt ohne Beachtung der Schreibung');
  // Nur Kurznamen: der Kurzname, damit die Klausel einheitlich bleibt.
  Assert.AreEqual('Math',
    TRdxRecipes.UsesNameFor(['Classes', 'Windows'], 'Math', 'System.Math'));
  // Ein Punkt allein ist kein Delphi-Scope (Review 2026-10-07, Minor 35):
  // 'Generics.Collections' gibt es auch unter FPC, 'Rdx.Fake' ist eine
  // eigene Unit. Bis dahin pinnte dieser Test hier 'System.Math'.
  Assert.AreEqual('Math',
    TRdxRecipes.UsesNameFor(['Classes', 'Generics.Collections'], 'Math', 'System.Math'));
  Assert.AreEqual('Math',
    TRdxRecipes.UsesNameFor(['Rdx.Fake', 'Windows'], 'Math', 'System.Math'));
  Assert.IsTrue(TRdxRecipes.IsRtlScopedName('FMX.Types'));
  Assert.IsTrue(TRdxRecipes.IsRtlScopedName('Data.DB'));
  Assert.IsFalse(TRdxRecipes.IsRtlScopedName('Generics.Collections'));
  Assert.IsFalse(TRdxRecipes.IsRtlScopedName('MyLib.Utils'));
  Assert.IsFalse(TRdxRecipes.IsRtlScopedName('Windows'), 'kein Punkt');
  Assert.IsFalse(TRdxRecipes.IsRtlScopedName('.System'), 'leeres erstes Segment');
end;

procedure TTestRdxRecipes.LineLooksFpcAware_Tells;
begin
  Assert.IsTrue(TRdxRecipes.LineLooksFpcAware('{$IFDEF FPC}{$mode delphi}{$ENDIF}'));
  Assert.IsTrue(TRdxRecipes.LineLooksFpcAware('{$IFNDEF FPC}'));
  Assert.IsTrue(TRdxRecipes.LineLooksFpcAware('  {$IF DEFINED(FPC)}'));
  Assert.IsTrue(TRdxRecipes.LineLooksFpcAware('{$MODE ObjFPC}{$H+}'));
  Assert.IsTrue(TRdxRecipes.LineLooksFpcAware('(*$IFDEF FPC*)'));
  Assert.IsTrue(TRdxRecipes.LineLooksFpcAware('{$ifdef'#9'fpc}'), 'Tab statt Leerzeichen');
  Assert.IsFalse(TRdxRecipes.LineLooksFpcAware('unit FpcTools;'), 'nur Direktiven zaehlen');
  Assert.IsFalse(TRdxRecipes.LineLooksFpcAware('{$IFDEF MSWINDOWS}'));
  Assert.IsFalse(TRdxRecipes.LineLooksFpcAware('{$R *.res}'));
  Assert.IsFalse(TRdxRecipes.LineLooksFpcAware(''));
end;

procedure TTestRdxRecipes.UsesTail_PathCommentSemicolon;
begin
  // Das ';' folgt direkt: hinter dem Namen anhaengen.
  Assert.AreEqual<Integer>(0, TRdxRecipes.UsesTailLength(';'));
  Assert.AreEqual<Integer>(0, TRdxRecipes.UsesTailLength('  ;  // Rest'));
  // 'in'-Pfad (.dpr) und Formular-Kommentar gehoeren zum Eintrag - das
  // Anhaengen kommt hinter sie, die Liste bleibt sortiert (Minor 42).
  Assert.AreEqual<Integer>(Length(' in ''Forms.pas'''),
    TRdxRecipes.UsesTailLength(' in ''Forms.pas'';'));
  Assert.AreEqual<Integer>(Length(' in ''Main.pas'' {MainForm}'),
    TRdxRecipes.UsesTailLength(' in ''Main.pas'' {MainForm};'));
  Assert.AreEqual<Integer>(Length(' IN ''it''''s.pas'''),
    TRdxRecipes.UsesTailLength(' IN ''it''''s.pas'' ;'), 'Quote im Pfad, Gross-/Kleinschreibung');
  Assert.AreEqual<Integer>(Length(' {x} (* y *)'),
    TRdxRecipes.UsesTailLength(' {x} (* y *);'));
  Assert.AreEqual<Integer>(Length(' (**)'), TRdxRecipes.UsesTailLength(' (**);'));
  // Sonst nicht anhaengen (-1) - vor dem letzten Eintrag einfuegen.
  Assert.AreEqual<Integer>(-1, TRdxRecipes.UsesTailLength(' // Formulare'), 'Zeilenkommentar');
  Assert.AreEqual<Integer>(-1, TRdxRecipes.UsesTailLength(' in ''a.pas'''), 'kein ; auf der Zeile');
  Assert.AreEqual<Integer>(-1, TRdxRecipes.UsesTailLength(' {$IFDEF X};'), 'Direktive');
  Assert.AreEqual<Integer>(-1, TRdxRecipes.UsesTailLength(' (*$X*);'), 'Direktive (*$');
  Assert.AreEqual<Integer>(-1, TRdxRecipes.UsesTailLength(' {offen'), 'Kommentar offen');
  Assert.AreEqual<Integer>(-1, TRdxRecipes.UsesTailLength(' (*);'), '(*) oeffnet nur');
  Assert.AreEqual<Integer>(-1, TRdxRecipes.UsesTailLength(', B;'), 'noch ein Eintrag');
  Assert.AreEqual<Integer>(-1, TRdxRecipes.UsesTailLength(' in x;'), 'Pfad ohne Literal');
  Assert.AreEqual<Integer>(-1, TRdxRecipes.UsesTailLength(' inherited;'), 'kein Wort in');
  Assert.AreEqual<Integer>(-1, TRdxRecipes.UsesTailLength(''), 'Zeilenende');
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

procedure TTestRdxRecipes.Scope_Resolve_VclVsSystem_Ambiguous_NotGuessed;
var
  T      : TRdxScopeTable;
  Q, Why : string;
begin
  // 'Skia' ist mit der Vorgabe-Vorlage System.Skia, mit den SDI-/MDI-
  // Vorlagen (Vcl vor System) Vcl.Skia - ohne DCC_Namespace des Projekts
  // nicht entscheidbar.
  T := MakeTable(['skia=FMX.Skia;System.Skia;Vcl.Skia',
                  'sharecontract=System.Win.ShareContract;Vcl.ShareContract']);
  try
    Assert.IsFalse(T.Resolve('Skia', fwVcl, Q, Why));
    Assert.IsTrue(Pos('DCC_Namespace', Why) > 0, Why);
    Assert.IsFalse(T.Resolve('Skia', fwUnknown, Q, Why),
      'Rahmenwerk unbekannt: VCL moeglich');
    // Eine FMX-Datei hat kein Vcl in der Liste: System vor FMX wie bisher.
    Assert.IsTrue(T.Resolve('Skia', fwFmx, Q, Why), Why);
    Assert.AreEqual('System.Skia', Q);
    // System.Win steht in beiden Vorlagen vor Vcl - eindeutig.
    Assert.IsTrue(T.Resolve('ShareContract', fwVcl, Q, Why), Why);
    Assert.AreEqual('System.Win.ShareContract', Q);
  finally
    T.Free;
  end;
end;

// data\unitscopes.txt des Moduls, von der Exe und vom Arbeitsverzeichnis
// aus aufwaerts gesucht: reDelphix.Test laeuft unter Output\..., der
// FPC-Pruefstand in reDelphix\tools\fpc-pruefstand. '' = nicht gefunden.
function FindScopeFile: string;
const
  MAX_UP = 6;
var
  Starts : array[0..1] of string;
  Dir    : string;
  s, k   : Integer;
begin
  Starts[0] := ExtractFileDir(ParamStr(0));
  Starts[1] := GetCurrentDir;
  for s := Low(Starts) to High(Starts) do
  begin
    Dir := Starts[s];
    for k := 0 to MAX_UP do
    begin
      Result := IncludeTrailingPathDelimiter(Dir) + 'reDelphix' + PathDelim
        + 'data' + PathDelim + SCOPE_FILE_NAME;
      if FileExists(Result) then Exit;
      Result := IncludeTrailingPathDelimiter(Dir) + 'data' + PathDelim
        + SCOPE_FILE_NAME;
      if FileExists(Result) then Exit;
      Dir := ExtractFileDir(Dir);
    end;
  end;
  Result := '';
end;

// Der erste Kandidat, der mit einem Praefix in der Schreibung der
// Installationsdateien beginnt statt in der von DCC_Namespace (Gross/Klein
// zaehlt); '' wenn keiner.
function FirstFileSpelling(const ACands: TArray<string>): string;
const
  BAD: array[0..2] of string = ('WinAPI.', 'VCL.', 'DataSnap.');
var
  i, k : Integer;
begin
  Result := '';
  for k := 0 to High(ACands) do
    for i := Low(BAD) to High(BAD) do
      if Copy(ACands[k], 1, Length(BAD[i])) = BAD[i] then
        Exit(ACands[k]);
end;

procedure TTestRdxRecipes.Scope_RealTable_PrefixSpelling;
var
  T      : TRdxScopeTable;
  SL     : TStringList;
  Path   : string;
  Q, Why : string;
  Hit    : string;
  i      : Integer;
  P, Bad : Integer;
  First  : string;
begin
  // Die eingecheckte Tabelle (Review 2026-10-07, Nit 19): die Praefixe
  // stehen so da, wie DCC_Namespace sie schreibt - Winapi, Vcl, Datasnap -
  // und nicht wie manche Dateinamen der Installation (WinAPI.Foundation.pas).
  // Der Name landet woertlich in der uses-Klausel des Benutzers.
  Path := FindScopeFile;
  Assert.IsTrue(Path <> '', 'data\unitscopes.txt nicht gefunden');
  T  := TRdxScopeTable.Create;
  SL := TStringList.Create;
  try
    Assert.IsTrue(T.LoadFromFile(Path), Path);
    Assert.IsTrue(T.Resolve('Foundation', fwVcl, Q, Why), Why);
    Assert.AreEqual('Winapi.Foundation', Q);
    SL.LoadFromFile(Path);
    Bad   := 0;
    First := '';
    for i := 0 to SL.Count - 1 do
    begin
      P := Pos('=', SL[i]);
      if (P <= 1) or (Copy(TrimLeft(SL[i]), 1, 1) = '#') then Continue;
      Hit := FirstFileSpelling(T.Candidates(Copy(SL[i], 1, P - 1)));
      if Hit = '' then Continue;
      Inc(Bad);
      if First = '' then First := Hit;
    end;
    Assert.AreEqual<Integer>(0, Bad, 'Praefix in Datei-Schreibung, zuerst: ' + First);
  finally
    SL.Free;
    T.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxRecipes);

end.
