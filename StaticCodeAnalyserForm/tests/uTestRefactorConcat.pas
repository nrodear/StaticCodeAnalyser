unit uTestRefactorConcat;

// Tests fuer uRefactorConcat (Konzept_Todo_RefactorInfo 2026-10-01,
// Inkrement 3): Zerlegung einer Zuweisung mit '+'-Kette in Ziel, Literale
// und Operanden, die Fakten je Term und die FixSafe-Zusicherung.
//
// Geprueft wird ueber den TEXT der Teilbereiche (SpanText), nicht ueber
// abgezaehlte Spalten: stimmt der Text, stimmen Anfang und Ende.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRefactorConcat = class
  public
    // ---- Zerlegung (B2) ----
    [Test] procedure Describe_FourTerms_PartsInSourceOrder;
    [Test] procedure Describe_QualifiedTarget;
    [Test] procedure Describe_PlusInParens_IsNoSeparator;
    [Test] procedure Describe_EscapedQuote_StaysInLiteral;
    [Test] procedure Describe_ChainOverTwoLines;
    [Test] procedure Describe_NoSemicolon_LastTermEndsBeforeElse;
    [Test] procedure Describe_SingleTerm_ZeroPluses;

    // ---- Liefern darf scheitern ----
    [Test] procedure Describe_PlusCountMismatch_ReturnsNil;
    [Test] procedure Describe_NotAnAssignment_ReturnsNil;
    [Test] procedure Describe_InnerSemicolonOnDepthZero_ReturnsNil;

    // ---- Fakten je Term (B3) ----
    [Test] procedure Facts_ControlCharsBelongToLiteral;
    [Test] procedure Facts_VariableStaysUnknown;
    [Test] procedure Facts_KnownCallAndToStringAreString;

    // ---- FixSafe (B4) ----
    [Test] procedure FixSafe_AllTermsString_True;
    [Test] procedure FixSafe_MultiLineAlone_StaysTrue;
    [Test] procedure FixSafe_UnknownOperand_False;
    [Test] procedure FixSafe_CommentInSpan_False;
    // Review reDelphiX 2026-10-07, strittiger Major 1: eine Direktive
    // ZWISCHEN den Termen sperrt wie ein Kommentar, auch wenn jeder Term
    // fuer sich ein String ist.
    [Test] procedure FixSafe_InlineDirective_False;
    [Test] procedure FixSafe_InConditionalRange_False;
    [Test] procedure FixSafe_TopLevelOperator_False;

    // ---- Aufruf-Form (SCA003: Query.SQL.Add('...' + x)) ----
    [Test] procedure Call_SingleArgumentChain_Described;
    [Test] procedure Call_NestedCallInArgument_CommaIsNoSeparator;
    [Test] procedure Call_NoSemicolon_BeforeEnd;
    [Test] procedure Call_SeveralArguments_ReturnsNil;
    [Test] procedure Call_PartOfLargerExpression_ReturnsNil;
    [Test] procedure Call_NoParens_ReturnsNil;
    [Test] procedure Call_EmptyArgumentList_ReturnsNil;

    // ---- Aufruf mit mehreren Argumenten (ROLE_ARGUMENT) ----
    [Test] procedure CallArgs_ThreeArguments_Described;
    [Test] procedure CallArgs_NestedCommas_StayInsideArgument;
    [Test] procedure CallArgs_CommaInLiteral_Ignored;
    [Test] procedure CallArgs_PartOfLargerExpression_ReturnsNil;
    [Test] procedure CallArgs_EmptyOrMissingParens_ReturnsNil;

    // ---- Gegenprobe gegen den AST-Knoten ----
    [Test] procedure TargetMatches_IgnoresWhitespaceAndCase;
    [Test] procedure TargetMatches_OtherStatement_False;
    // AH22: der Knoten traegt jeden Index als '[]' (ParsePrimary) - ein
    // indiziertes Ziel blieb sonst unbeschreibbar.
    [Test] procedure TargetMatches_IndexedTarget_IgnoresIndex;

    // ---- Einzelfragen ----
    [Test] procedure IsLiteralView_Cases;
    [Test] procedure HasTopLevelOperator_Cases;
    [Test] procedure IsKnownStringCall_Cases;
    [Test] procedure EndsWithToString_Cases;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uAstNode, uRefactorInfo, uRefactorInfoBuilder, uRefactorConcat;

function MakeLines(const A: array of string): TStringList;
var
  S : string;
begin
  Result := TStringList.Create;
  for S in A do
    Result.Add(S);
end;

function DescribeAt(ALines: TStringList; ALine: Integer;
  const AStartText: string; AExpectedPlus: Integer = -1;
  AUnit: TAstNode = nil): TRefactorInfo;
begin
  Result := TRefactorConcat.TryDescribeAssign(AUnit, ALines, ALine,
    Pos(AStartText, ALines[ALine - 1]), AExpectedPlus);
end;

function PartText(ALines: TStringList; AInfo: TRefactorInfo;
  AIndex: Integer): string;
begin
  Result := TRefactorInfoBuilder.SpanText(ALines, AInfo.Parts[AIndex]);
end;

{ ---- Zerlegung ---- }

procedure TTestRefactorConcat.Describe_FourTerms_PartsInSourceOrder;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines([
    '  r := ''Hallo '' + Name + '', du bist '' + IntToStr(Age);']);
  try
    Info := DescribeAt(Lines, 1, 'r :=', 3);
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(5, Length(Info.Parts), 'Ziel + vier Terme');
      Assert.AreEqual(ROLE_TARGET, Info.Parts[0].Role);
      Assert.AreEqual('r', PartText(Lines, Info, 0));
      Assert.AreEqual(ROLE_LITERAL, Info.Parts[1].Role);
      Assert.AreEqual('''Hallo ''', PartText(Lines, Info, 1));
      Assert.AreEqual(ROLE_OPERAND, Info.Parts[2].Role);
      Assert.AreEqual('Name', PartText(Lines, Info, 2));
      Assert.AreEqual(ROLE_LITERAL, Info.Parts[3].Role);
      Assert.AreEqual(''', du bist ''', PartText(Lines, Info, 3));
      Assert.AreEqual(ROLE_OPERAND, Info.Parts[4].Role);
      Assert.AreEqual('IntToStr(Age)', PartText(Lines, Info, 4),
        'das abschliessende Semikolon gehoert zu keinem Term');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.Describe_QualifiedTarget;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['Self.Caption := ''a'' + b + ''c'' + d;']);
  try
    Info := DescribeAt(Lines, 1, 'Self.', 3);
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual('Self.Caption', PartText(Lines, Info, 0));
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.Describe_PlusInParens_IsNoSeparator;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['r := ''a'' + IntToStr(x + y) + Arr[i + 1];']);
  try
    Info := DescribeAt(Lines, 1, 'r :=', 2);
    try
      Assert.IsTrue(Assigned(Info), 'zwei Konkat-Plus, wie ScanConcat zaehlt');
      Assert.AreEqual<Integer>(4, Length(Info.Parts));
      Assert.AreEqual('IntToStr(x + y)', PartText(Lines, Info, 2));
      Assert.AreEqual('Arr[i + 1]', PartText(Lines, Info, 3));
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.Describe_EscapedQuote_StaysInLiteral;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  // Quelle:  r := 'it''s + x' + a + 'b''' + c;
  Lines := MakeLines(['r := ''it''''s + x'' + a + ''b'''''' + c;']);
  try
    Info := DescribeAt(Lines, 1, 'r :=', 3);
    try
      Assert.IsTrue(Assigned(Info),
        'das Plus im Literal ist kein Trenner');
      Assert.AreEqual('''it''''s + x''', PartText(Lines, Info, 1));
      Assert.AreEqual('a', PartText(Lines, Info, 2));
      Assert.AreEqual('''b''''''', PartText(Lines, Info, 3));
      Assert.AreEqual('c', PartText(Lines, Info, 4));
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.Describe_ChainOverTwoLines;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines([
    '  r := ''a'' + b +',
    '       ''c'' + d;']);
  try
    Info := DescribeAt(Lines, 1, 'r :=', 3);
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsTrue(rfMultiLine in Info.Flags);
      Assert.AreEqual<Integer>(1, Info.Parts[2].StartLine);
      Assert.AreEqual<Integer>(2, Info.Parts[3].StartLine);
      Assert.AreEqual('''c''', PartText(Lines, Info, 3));
      Assert.AreEqual('d', PartText(Lines, Info, 4));
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.Describe_NoSemicolon_LastTermEndsBeforeElse;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines([
    '  if c then r := ''a'' + b + ''c'' + d',
    '  else r := '''';']);
  try
    Info := DescribeAt(Lines, 1, 'r :=', 3);
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual('d', PartText(Lines, Info, 4));
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.Describe_SingleTerm_ZeroPluses;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['r := a;']);
  try
    Info := DescribeAt(Lines, 1, 'r :=', 0);
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(2, Length(Info.Parts));
      Assert.AreEqual('a', PartText(Lines, Info, 1));
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

{ ---- Liefern darf scheitern ---- }

procedure TTestRefactorConcat.Describe_PlusCountMismatch_ReturnsNil;
var
  Lines : TStringList;
begin
  Lines := MakeLines(['r := ''a'' + b + ''c'' + d;']);
  try
    Assert.IsFalse(Assigned(DescribeAt(Lines, 1, 'r :=', 5)),
      'zwei Zaehlungen, die sich widersprechen: nichts liefern');
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.Describe_NotAnAssignment_ReturnsNil;
var
  Lines : TStringList;
begin
  Lines := MakeLines(['Foo(''a'' + b + ''c'' + d);']);
  try
    Assert.IsFalse(Assigned(DescribeAt(Lines, 1, 'Foo')),
      'ohne := ist es keine Zuweisung');
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.Describe_InnerSemicolonOnDepthZero_ReturnsNil;
var
  Lines : TStringList;
begin
  Lines := MakeLines(['p := procedure begin x := ''a'' + b; end;']);
  try
    Assert.IsFalse(Assigned(DescribeAt(Lines, 1, 'p :=')),
      'ein Rumpf auf der rechten Seite ist keine einfache Kette');
  finally
    Lines.Free;
  end;
end;

{ ---- Fakten je Term ---- }

procedure TTestRefactorConcat.Facts_ControlCharsBelongToLiteral;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['r := ''a''#13#10 + b + #9 + c + #$0D''x'';']);
  try
    Info := DescribeAt(Lines, 1, 'r :=', 4);
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual(ROLE_LITERAL, Info.Parts[1].Role);
      Assert.AreEqual('''a''#13#10', PartText(Lines, Info, 1));
      Assert.AreEqual(ROLE_LITERAL, Info.Parts[3].Role, '#9 allein');
      Assert.AreEqual(ROLE_LITERAL, Info.Parts[5].Role, '#$0D vor dem Literal');
      Assert.IsTrue(Info.Parts[5].ValueType = rvString);
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.Facts_VariableStaysUnknown;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['r := ''a'' + Name + ''c'' + Obj.Caption;']);
  try
    Info := DescribeAt(Lines, 1, 'r :=', 3);
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsTrue(Info.Parts[2].ValueType = rvUnknown,
        'ohne Typaufloesung ist eine Variable unbekannt');
      Assert.IsTrue(Info.Parts[4].ValueType = rvUnknown);
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.Facts_KnownCallAndToStringAreString;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines([
    'r := ''a'' + IntToStr(x) + SysUtils.QuotedStr(s) + n.ToString + ''z'';']);
  try
    Info := DescribeAt(Lines, 1, 'r :=', 4);
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsTrue(Info.Parts[2].ValueType = rvString, 'IntToStr(x)');
      Assert.IsTrue(Info.Parts[3].ValueType = rvString, 'SysUtils.QuotedStr(s)');
      Assert.IsTrue(Info.Parts[4].ValueType = rvString, 'n.ToString');
      Assert.AreEqual(ROLE_OPERAND, Info.Parts[2].Role);
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

{ ---- FixSafe ---- }

procedure TTestRefactorConcat.FixSafe_AllTermsString_True;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['r := ''a'' + IntToStr(x) + ''b'' + QuotedStr(s);']);
  try
    Info := DescribeAt(Lines, 1, 'r :=', 3);
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsTrue(Info.FixSafe);
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.FixSafe_MultiLineAlone_StaysTrue;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines([
    'r := ''a'' + IntToStr(x) +',
    '  ''b'' + QuotedStr(s);']);
  try
    Info := DescribeAt(Lines, 1, 'r :=', 3);
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsTrue(rfMultiLine in Info.Flags);
      Assert.IsTrue(Info.FixSafe,
        'ein Zeilenumbruch allein macht die Kette nicht unsicher');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.FixSafe_UnknownOperand_False;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['r := ''a'' + IntToStr(x) + ''b'' + Name;']);
  try
    Info := DescribeAt(Lines, 1, 'r :=', 3);
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsFalse(Info.FixSafe, 'ein unbekannter Operand genuegt');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.FixSafe_CommentInSpan_False;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines([
    'r := ''a'' + IntToStr(x) {wichtig} + ''b'' + QuotedStr(s);']);
  try
    Info := DescribeAt(Lines, 1, 'r :=', 3);
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsTrue(rfHasComment in Info.Flags);
      Assert.IsFalse(Info.FixSafe, 'der Kommentar ginge verloren');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.FixSafe_InlineDirective_False;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  // Direktive und Literale ohne Leerraum dazwischen: gesperrt wird ueber
  // rfHasComment, nicht ueber die Art der Terme.
  Lines := MakeLines([
    'r := ''a'' + {$IFDEF X}''b''{$ELSE}''c''{$ENDIF};']);
  try
    Info := DescribeAt(Lines, 1, 'r :=', 1);
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(3, Length(Info.Parts), 'Ziel + zwei Terme');
      Assert.IsTrue(rfHasComment in Info.Flags);
      Assert.IsFalse(Info.FixSafe,
        'beim Ersetzen ginge ein Zweig der Direktive verloren');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.FixSafe_InConditionalRange_False;
var
  Lines : TStringList;
  Root  : TAstNode;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines([
    '{$IFDEF X}',
    'r := ''a'' + IntToStr(x) + ''b'' + QuotedStr(s);',
    '{$ENDIF}']);
  Root := TAstNode.Create(nkUnit, '', 1, 1);
  try
    Root.Add(nkConditionalRange, '', 1, 0).TypeRef := '3';
    Info := DescribeAt(Lines, 2, 'r :=', 3, Root);
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsTrue(rfInConditional in Info.Flags);
      Assert.IsFalse(Info.FixSafe);
    finally
      Info.Free;
    end;
  finally
    Root.Free;
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.FixSafe_TopLevelOperator_False;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  // Die rechte Seite ist ein VERGLEICH, keine reine Kette: der letzte
  // "Term" ist  IntToStr(y) = s.
  Lines := MakeLines(['b := ''a'' + IntToStr(x) + ''b'' + IntToStr(y) = s;']);
  try
    Info := DescribeAt(Lines, 1, 'b :=', 3);
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsTrue(Info.Parts[4].ValueType = rvUnknown);
      Assert.IsFalse(Info.FixSafe);
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

{ ---- Aufruf-Form ---- }

function DescribeCallAt(ALines: TStringList; ALine: Integer;
  const AStartText: string): TRefactorInfo;
begin
  Result := TRefactorConcat.TryDescribeCall(nil, ALines, ALine,
    Pos(AStartText, ALines[ALine - 1]));
end;

procedure TTestRefactorConcat.Call_SingleArgumentChain_Described;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines([
    'begin',
    '  Q.SQL.Add(''SELECT * FROM t WHERE id = '' + IdStr);',
    'end;']);
  try
    Info := DescribeCallAt(Lines, 2, 'Q.SQL');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(3, Length(Info.Parts));
      Assert.AreEqual(ROLE_TARGET, Info.Parts[0].Role);
      Assert.AreEqual('Q.SQL.Add', PartText(Lines, Info, 0),
        'das Ziel ist der Aufrufkopf');
      Assert.AreEqual(ROLE_LITERAL, Info.Parts[1].Role);
      Assert.AreEqual('''SELECT * FROM t WHERE id = ''',
        PartText(Lines, Info, 1));
      Assert.AreEqual(ROLE_OPERAND, Info.Parts[2].Role);
      Assert.AreEqual('IdStr', PartText(Lines, Info, 2),
        'die schliessende Klammer gehoert nicht zum Term');
      Assert.AreEqual<Integer>(3, Info.InsertLine,
        'Einfuegepunkt hinter dem Aufruf');
      Assert.AreEqual<Integer>(2, Info.InsertIndent);
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.Call_NestedCallInArgument_CommaIsNoSeparator;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['Q.Add(''a'' + F(x, y) + ''b'');']);
  try
    Info := DescribeCallAt(Lines, 1, 'Q.Add');
    try
      Assert.IsTrue(Assigned(Info),
        'das Komma liegt eine Ebene tiefer und trennt keine Argumente');
      Assert.AreEqual<Integer>(4, Length(Info.Parts));
      Assert.AreEqual('F(x, y)', PartText(Lines, Info, 2));
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.Call_NoSemicolon_BeforeEnd;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['begin Q.Add(''a'' + b) end;']);
  try
    Info := DescribeCallAt(Lines, 1, 'Q.Add');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual('b', PartText(Lines, Info, 2));
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.Call_SeveralArguments_ReturnsNil;
var
  Lines : TStringList;
begin
  Lines := MakeLines(['ExecuteFmt(''SELECT % FROM %'', [a, b]);']);
  try
    Assert.IsFalse(Assigned(DescribeCallAt(Lines, 1, 'ExecuteFmt')),
      'mehrere Argumente sind keine einzelne Kette');
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.Call_PartOfLargerExpression_ReturnsNil;
var
  Lines : TStringList;
begin
  Lines := MakeLines(['if Q.Exec(''a'' + b) then Foo;']);
  try
    Assert.IsFalse(Assigned(DescribeCallAt(Lines, 1, 'Q.Exec')),
      'hinter der Klammer steht mehr als ein Semikolon');
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.Call_NoParens_ReturnsNil;
var
  Lines : TStringList;
begin
  Lines := MakeLines(['Refresh;']);
  try
    Assert.IsFalse(Assigned(DescribeCallAt(Lines, 1, 'Refresh')));
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.Call_EmptyArgumentList_ReturnsNil;
var
  Lines : TStringList;
begin
  Lines := MakeLines(['Refresh();']);
  try
    Assert.IsFalse(Assigned(DescribeCallAt(Lines, 1, 'Refresh')));
  finally
    Lines.Free;
  end;
end;

{ ---- Aufruf mit mehreren Argumenten ---- }

function DescribeCallArgsAt(ALines: TStringList; ALine: Integer;
  const AStartText: string): TRefactorInfo;
begin
  Result := TRefactorConcat.TryDescribeCallArgs(nil, ALines, ALine,
    Pos(AStartText, ALines[ALine - 1]));
end;

procedure TTestRefactorConcat.CallArgs_ThreeArguments_Described;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['  ExecuteFmt(''SELECT % FROM %'', [a, b], x);']);
  try
    Info := DescribeCallArgsAt(Lines, 1, 'ExecuteFmt');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(4, Length(Info.Parts), 'Kopf + drei Argumente');
      Assert.AreEqual(ROLE_TARGET, Info.Parts[0].Role);
      Assert.AreEqual('ExecuteFmt', PartText(Lines, Info, 0));
      Assert.AreEqual(ROLE_ARGUMENT, Info.Parts[1].Role);
      Assert.AreEqual('''SELECT % FROM %''', PartText(Lines, Info, 1));
      Assert.AreEqual('[a, b]', PartText(Lines, Info, 2),
        'das Komma in den eckigen Klammern trennt kein Argument');
      Assert.AreEqual('x', PartText(Lines, Info, 3));
      Assert.IsFalse(Info.FixSafe, 'ohne Zerlegung ist nichts bewiesen');
      Assert.AreEqual<Integer>(2, Info.InsertLine);
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.CallArgs_NestedCommas_StayInsideArgument;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['F(G(a, b), c);']);
  try
    Info := DescribeCallArgsAt(Lines, 1, 'F(');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(3, Length(Info.Parts));
      Assert.AreEqual('G(a, b)', PartText(Lines, Info, 1));
      Assert.AreEqual('c', PartText(Lines, Info, 2));
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.CallArgs_CommaInLiteral_Ignored;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['F(''a, b'', c);']);
  try
    Info := DescribeCallArgsAt(Lines, 1, 'F(');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(3, Length(Info.Parts));
      Assert.AreEqual('''a, b''', PartText(Lines, Info, 1));
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.CallArgs_PartOfLargerExpression_ReturnsNil;
var
  Lines : TStringList;
begin
  Lines := MakeLines(['if F(a, b) then X;']);
  try
    Assert.IsFalse(Assigned(DescribeCallArgsAt(Lines, 1, 'F(')),
      'hinter der Klammer steht mehr als ein Semikolon');
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.CallArgs_EmptyOrMissingParens_ReturnsNil;
var
  Lines : TStringList;
begin
  Lines := MakeLines(['F();', 'Refresh;', 'F(, a);']);
  try
    Assert.IsFalse(Assigned(DescribeCallArgsAt(Lines, 1, 'F(')),
      'leere Argumentliste');
    Assert.IsFalse(Assigned(DescribeCallArgsAt(Lines, 2, 'Refresh')),
      'keine Klammer');
    Assert.IsFalse(Assigned(DescribeCallArgsAt(Lines, 3, 'F(')),
      'leeres erstes Argument');
  finally
    Lines.Free;
  end;
end;

{ ---- Gegenprobe ---- }

procedure TTestRefactorConcat.TargetMatches_IgnoresWhitespaceAndCase;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['Query . SQL.Text := ''a'' + b;']);
  try
    Info := DescribeAt(Lines, 1, 'Query');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsTrue(TRefactorConcat.TargetMatches(Lines, Info,
        'query.sql.text'),
        'der Knoten traegt das Ziel als zusammengefuegte Token');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.TargetMatches_IndexedTarget_IgnoresIndex;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['StatusBar1.Panels[ 1 ].Text := ''a'' + b;']);
  try
    Info := DescribeAt(Lines, 1, 'StatusBar1');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsTrue(TRefactorConcat.TargetMatches(Lines, Info,
        'StatusBar1.Panels[].Text'), 'Knotenform mit leerem Index');
      Assert.IsTrue(TRefactorConcat.TargetMatches(Lines, Info,
        'statusbar1.panels[1].text'), 'Index im Vergleichstext wird ebenso ausgeblendet');
      Assert.IsFalse(TRefactorConcat.TargetMatches(Lines, Info,
        'StatusBar1.Panels'), 'ein anderes Ziel bleibt falsch');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorConcat.TargetMatches_OtherStatement_False;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['Other.Text := ''a'' + b;']);
  try
    Info := DescribeAt(Lines, 1, 'Other');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsFalse(TRefactorConcat.TargetMatches(Lines, Info,
        'Query.SQL.Text'));
      Assert.IsFalse(TRefactorConcat.TargetMatches(Lines, Info, ''),
        'ein leerer Erwartungswert passt nie');
      Assert.IsFalse(TRefactorConcat.TargetMatches(Lines, nil, 'x'));
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

{ ---- Einzelfragen ---- }

procedure TTestRefactorConcat.IsLiteralView_Cases;
begin
  Assert.IsTrue(TRefactorConcat.IsLiteralView('~~~~'));
  Assert.IsTrue(TRefactorConcat.IsLiteralView('~~~#13#10'));
  Assert.IsTrue(TRefactorConcat.IsLiteralView('#$0D'));
  Assert.IsTrue(TRefactorConcat.IsLiteralView('#9~~'));
  Assert.IsFalse(TRefactorConcat.IsLiteralView(''), 'leer');
  Assert.IsFalse(TRefactorConcat.IsLiteralView('#'), '# ohne Ziffern');
  Assert.IsFalse(TRefactorConcat.IsLiteralView('abc'), 'Bezeichner');
  Assert.IsFalse(TRefactorConcat.IsLiteralView('a'),
    'ein Bezeichner aus Hex-Buchstaben ist kein Literal');
  Assert.IsFalse(TRefactorConcat.IsLiteralView('~~ ~~'),
    'zwei Literale mit Leerraum dazwischen sind kein EIN Literal');
end;

procedure TTestRefactorConcat.HasTopLevelOperator_Cases;
begin
  Assert.IsTrue(TRefactorConcat.HasTopLevelOperator('a = b'));
  Assert.IsTrue(TRefactorConcat.HasTopLevelOperator('a div b'));
  Assert.IsTrue(TRefactorConcat.HasTopLevelOperator('not a'));
  Assert.IsTrue(TRefactorConcat.HasTopLevelOperator('a - b'));
  Assert.IsFalse(TRefactorConcat.HasTopLevelOperator('F(a = b)'),
    'in Klammern zaehlt es nicht');
  Assert.IsFalse(TRefactorConcat.HasTopLevelOperator('Arr[i - 1]'));
  Assert.IsFalse(TRefactorConcat.HasTopLevelOperator('Obj.Mod'),
    'hinter dem Punkt ist es ein Member');
  Assert.IsFalse(TRefactorConcat.HasTopLevelOperator('p^.Name'));
  Assert.IsFalse(TRefactorConcat.HasTopLevelOperator('Android'),
    'ein Wort, das mit and BEGINNT, ist kein Operator');
end;

procedure TTestRefactorConcat.IsKnownStringCall_Cases;
begin
  Assert.IsTrue(TRefactorConcat.IsKnownStringCall('IntToStr(a)'));
  Assert.IsTrue(TRefactorConcat.IsKnownStringCall(' Trim( s ) '));
  Assert.IsTrue(TRefactorConcat.IsKnownStringCall('SysUtils.IntToStr(F(a))'));
  Assert.IsTrue(TRefactorConcat.IsKnownStringCall('System.SysUtils.QuotedStr(s)'));
  Assert.IsFalse(TRefactorConcat.IsKnownStringCall('IntToStr(a).Foo'),
    'die Klammer schliesst den Term nicht ab');
  Assert.IsFalse(TRefactorConcat.IsKnownStringCall('MyFunc(a)'));
  Assert.IsFalse(TRefactorConcat.IsKnownStringCall('Obj.Trim(s)'),
    'Methode eines unbekannten Typs');
  Assert.IsFalse(TRefactorConcat.IsKnownStringCall('IntToStr'));
  Assert.IsFalse(TRefactorConcat.IsKnownStringCall('(a)'));
end;

procedure TTestRefactorConcat.EndsWithToString_Cases;
begin
  Assert.IsTrue(TRefactorConcat.EndsWithToString('n.ToString'));
  Assert.IsTrue(TRefactorConcat.EndsWithToString('List[i].Count.ToString()'));
  Assert.IsTrue(TRefactorConcat.EndsWithToString('n.tostring '));
  Assert.IsFalse(TRefactorConcat.EndsWithToString('ToString'),
    'ohne Empfaenger ist es irgendeine Routine');
  Assert.IsFalse(TRefactorConcat.EndsWithToString('n.ToString(fmt)'));
  Assert.IsFalse(TRefactorConcat.EndsWithToString('n.ToStringList'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRefactorConcat);

end.
