unit uTestRefactorInfoBuilder;

// Tests fuer uRefactorInfoBuilder (Konzept_Todo_RefactorInfo 2026-10-01,
// Inkrement 2): Anweisungsende, Flags, Einfuegepunkt, Bereichs-Hash und
// die spaltentreue Code-Sicht.
//
// Alle erwarteten Spalten werden mit Pos() aus der Testzeile BERECHNET,
// nicht von Hand gezaehlt - eine abgezaehlte Spalte ist die Art Zahl, die
// beim naechsten Umformatieren still falsch wird.
//
// Die Tests arbeiten auf einer TStringList und brauchen keine Datei. Den
// {$IFDEF}-Fall bauen sie mit einem Handbaum nach, genau so wie
// uParser2 die Marker ablegt (Root.Add(nkConditionalRange, .., Start, 0)
// mit TypeRef = Endzeile).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRefactorInfoBuilder = class
  public
    // ---- Anweisungsende (B1) ----
    [Test] procedure SingleLine_SpanIncludesSemicolon;
    [Test] procedure MultiLine_SpanEndsOnSecondLine;
    [Test] procedure SemicolonInString_IsIgnored;
    [Test] procedure SemicolonInComment_IsIgnored;
    [Test] procedure AnonymousMethod_InnerSemicolonsIgnored;
    [Test] procedure NoSemicolon_EndsBeforeElse;
    [Test] procedure NoSemicolon_EndsBeforeEnd;
    [Test] procedure MemberNamedLikeKeyword_IsNotTerminator;

    // ---- Liefern darf scheitern ----
    [Test] procedure StartOnWhitespace_ReturnsNil;
    [Test] procedure StartOutOfRange_ReturnsNil;
    [Test] procedure NilLines_ReturnsNil;
    [Test] procedure NoEndBeforeEof_ReturnsNil;
    [Test] procedure StartInsideParens_ReturnsNil;

    // ---- Flags (B5) ----
    [Test] procedure Flags_SingleLinePlain_Empty;
    [Test] procedure Flags_TrailingLineComment_NotInSpan;
    [Test] procedure Flags_BlockCommentAcrossLines;
    [Test] procedure Flags_InConditionalRange;
    [Test] procedure Flags_NilUnitNode_NoConditional;

    // ---- Einfuegepunkt (B6) ----
    [Test] procedure Insert_StatementAloneOnLine;
    [Test] procedure Insert_TabIndent_CountsCharacters;
    [Test] procedure Insert_CodeBeforeStatement_None;
    [Test] procedure Insert_CodeAfterStatement_None;
    [Test] procedure Insert_NoSemicolon_None;

    // ---- Hash (B7) ----
    [Test] procedure Hash_IsSha256Hex_AndMatchesHashOfSpan;
    [Test] procedure Hash_ChangesWithOneCharacterInSpan;
    [Test] procedure Hash_IgnoresTextOutsideSpan;

    // ---- Code-Sicht ----
    [Test] procedure CodeView_IsColumnTrue_StringsAreFill;
    [Test] procedure SpanText_MultiLine_JoinedWithLf;

    // ---- Vertrag ----
    [Test] procedure Builder_LeavesPartsEmptyAndFixSafeFalse;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uAstNode, uRefactorInfo, uRefactorInfoBuilder;

function MakeLines(const A: array of string): TStringList;
var
  S : string;
begin
  Result := TStringList.Create;
  for S in A do
    Result.Add(S);
end;

// Baut die Info fuer die Anweisung, die in Zeile ALine mit AStartText
// beginnt. Der Aufrufer gibt frei.
function BuildAt(ALines: TStringList; ALine: Integer;
  const AStartText: string; AUnit: TAstNode = nil): TRefactorInfo;
begin
  Result := TRefactorInfoBuilder.TryBuildForStatement(AUnit, ALines, ALine,
    Pos(AStartText, ALines[ALine - 1]));
end;

{ ---- Anweisungsende ---- }

procedure TTestRefactorInfoBuilder.SingleLine_SpanIncludesSemicolon;
const
  L1 = '  r := a + b;';
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines([L1]);
  try
    Info := BuildAt(Lines, 1, 'r :=');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual(ROLE_STATEMENT, Info.Span.Role);
      Assert.AreEqual<Integer>(1, Info.Span.StartLine);
      Assert.AreEqual<Integer>(Pos('r :=', L1), Info.Span.StartCol);
      Assert.AreEqual<Integer>(1, Info.Span.EndLine);
      Assert.AreEqual<Integer>(Pos(';', L1) + 1, Info.Span.EndCol,
        'EndCol zeigt hinter das Semikolon');
      Assert.AreEqual('r := a + b;',
        TRefactorInfoBuilder.SpanText(Lines, Info.Span));
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.MultiLine_SpanEndsOnSecondLine;
const
  L1 = '  x := a +';
  L2 = '       b;';
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines([L1, L2]);
  try
    Info := BuildAt(Lines, 1, 'x :=');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(2, Info.Span.EndLine);
      Assert.AreEqual<Integer>(Pos(';', L2) + 1, Info.Span.EndCol);
      Assert.IsTrue(rfMultiLine in Info.Flags);
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.SemicolonInString_IsIgnored;
const
  L1 = 's := ''a;b'' + c;';
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines([L1]);
  try
    Info := BuildAt(Lines, 1, 's :=');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(Length(L1) + 1, Info.Span.EndCol,
        'das Semikolon im Literal beendet die Anweisung nicht');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.SemicolonInComment_IsIgnored;
const
  L1 = 's := a {x;y} + c;';
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines([L1]);
  try
    Info := BuildAt(Lines, 1, 's :=');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(Length(L1) + 1, Info.Span.EndCol);
      Assert.IsTrue(rfHasComment in Info.Flags,
        'der Kommentar im Bereich wird gemeldet');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.AnonymousMethod_InnerSemicolonsIgnored;
const
  L1 = 'x := Run(procedure begin G; H; end);';
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines([L1]);
  try
    Info := BuildAt(Lines, 1, 'x :=');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(Length(L1) + 1, Info.Span.EndCol,
        'Semikola im Rumpf der anonymen Methode beenden nichts');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.NoSemicolon_EndsBeforeElse;
const
  L1 = '  if c then r := a + b';
  L2 = '  else r := d;';
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines([L1, L2]);
  try
    Info := BuildAt(Lines, 1, 'r :=');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(1, Info.Span.EndLine);
      Assert.AreEqual<Integer>(Length(L1) + 1, Info.Span.EndCol,
        'der Bereich endet hinter dem letzten Zeichen vor dem else');
      Assert.AreEqual('r := a + b',
        TRefactorInfoBuilder.SpanText(Lines, Info.Span));
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.NoSemicolon_EndsBeforeEnd;
const
  L1 = 'begin r := a + b end;';
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines([L1]);
  try
    Info := BuildAt(Lines, 1, 'r :=');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual('r := a + b',
        TRefactorInfoBuilder.SpanText(Lines, Info.Span));
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.MemberNamedLikeKeyword_IsNotTerminator;
const
  L1 = 'r := Obj.Until + 1;';
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines([L1]);
  try
    Info := BuildAt(Lines, 1, 'r :=');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(Length(L1) + 1, Info.Span.EndCol,
        'ein Wort hinter dem Punkt ist kein Schluesselwort');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

{ ---- Liefern darf scheitern ---- }

procedure TTestRefactorInfoBuilder.StartOnWhitespace_ReturnsNil;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['  r := a;']);
  try
    Info := TRefactorInfoBuilder.TryBuildForStatement(nil, Lines, 1, 1);
    try
      Assert.IsFalse(Assigned(Info),
        'die Startposition muss auf Code zeigen');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.StartOutOfRange_ReturnsNil;
var
  Lines : TStringList;
begin
  Lines := MakeLines(['r := a;']);
  try
    Assert.IsFalse(Assigned(
      TRefactorInfoBuilder.TryBuildForStatement(nil, Lines, 0, 1)));
    Assert.IsFalse(Assigned(
      TRefactorInfoBuilder.TryBuildForStatement(nil, Lines, 2, 1)));
    Assert.IsFalse(Assigned(
      TRefactorInfoBuilder.TryBuildForStatement(nil, Lines, 1, 0)));
    Assert.IsFalse(Assigned(
      TRefactorInfoBuilder.TryBuildForStatement(nil, Lines, 1, 99)));
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.NilLines_ReturnsNil;
begin
  Assert.IsFalse(Assigned(
    TRefactorInfoBuilder.TryBuildForStatement(nil, nil, 1, 1)));
end;

procedure TTestRefactorInfoBuilder.NoEndBeforeEof_ReturnsNil;
var
  Lines : TStringList;
begin
  Lines := MakeLines(['r := a +', '  b']);
  try
    Assert.IsFalse(Assigned(
      TRefactorInfoBuilder.TryBuildForStatement(nil, Lines, 1, 1)),
      'ohne Abschluss wird nichts beschrieben statt etwas Halbes');
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.StartInsideParens_ReturnsNil;
const
  L1 = 'Foo(a + b);';
var
  Lines : TStringList;
begin
  Lines := MakeLines([L1]);
  try
    Assert.IsFalse(Assigned(
      TRefactorInfoBuilder.TryBuildForStatement(nil, Lines, 1,
        Pos('a +', L1))),
      'eine schliessende Klammer ohne oeffnende: keine Anweisung');
  finally
    Lines.Free;
  end;
end;

{ ---- Flags ---- }

procedure TTestRefactorInfoBuilder.Flags_SingleLinePlain_Empty;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['  r := a + b;']);
  try
    Info := BuildAt(Lines, 1, 'r :=');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsTrue(Info.Flags = [], 'kein Flag bei der schlichten Form');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.Flags_TrailingLineComment_NotInSpan;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['  r := a + b; // Hinweis']);
  try
    Info := BuildAt(Lines, 1, 'r :=');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsFalse(rfHasComment in Info.Flags,
        'ein Kommentar HINTER dem Semikolon liegt nicht im Bereich');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.Flags_BlockCommentAcrossLines;
const
  L2 = '  noch Kommentar } b;';
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['  r := a + { beginnt hier', L2]);
  try
    Info := BuildAt(Lines, 1, 'r :=');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(2, Info.Span.EndLine);
      Assert.AreEqual<Integer>(Length(L2) + 1, Info.Span.EndCol);
      Assert.IsTrue(rfHasComment in Info.Flags);
      Assert.IsTrue(rfMultiLine in Info.Flags);
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.Flags_InConditionalRange;
var
  Lines : TStringList;
  Root  : TAstNode;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines([
    'a := 1;',
    '{$IFDEF X}',
    'b := 2;',
    '{$ENDIF}',
    'c := 3;']);
  Root := TAstNode.Create(nkUnit, '', 1, 1);
  try
    // So legt uParser2 die Marker ab: Line = Start, TypeRef = Ende.
    Root.Add(nkConditionalRange, '', 2, 0).TypeRef := '4';

    Info := BuildAt(Lines, 3, 'b :=', Root);
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsTrue(rfInConditional in Info.Flags,
        'Zeile 3 liegt im Bereich 2..4');
    finally
      Info.Free;
    end;

    Info := BuildAt(Lines, 5, 'c :=', Root);
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsFalse(rfInConditional in Info.Flags,
        'Zeile 5 liegt hinter dem Bereich');
    finally
      Info.Free;
    end;
  finally
    Root.Free;
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.Flags_NilUnitNode_NoConditional;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['{$IFDEF X}', 'b := 2;', '{$ENDIF}']);
  try
    Info := BuildAt(Lines, 2, 'b :=');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.IsFalse(rfInConditional in Info.Flags,
        'ohne Unit-Knoten gibt es keine Marker - das Flag bleibt aus');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

{ ---- Einfuegepunkt ---- }

procedure TTestRefactorInfoBuilder.Insert_StatementAloneOnLine;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['begin', '    r := a + b; // Hinweis', 'end;']);
  try
    Info := BuildAt(Lines, 2, 'r :=');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(3, Info.InsertLine,
        'eingefuegt wird VOR Zeile 3, also hinter der Anweisung');
      Assert.AreEqual<Integer>(4, Info.InsertIndent);
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.Insert_TabIndent_CountsCharacters;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines([#9#9'r := a + b;']);
  try
    Info := BuildAt(Lines, 1, 'r :=');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(2, Info.InsertLine);
      Assert.AreEqual<Integer>(2, Info.InsertIndent,
        'ein Tabulator ist EIN Zeichen');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.Insert_CodeBeforeStatement_None;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['begin r := a + b;']);
  try
    Info := BuildAt(Lines, 1, 'r :=');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(0, Info.InsertLine,
        'vor der Anweisung steht Code - kein Einfuegepunkt');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.Insert_CodeAfterStatement_None;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['r := a + b; s := c;']);
  try
    Info := BuildAt(Lines, 1, 'r :=');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(0, Info.InsertLine,
        'hinter der Anweisung steht Code - kein Einfuegepunkt');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.Insert_NoSemicolon_None;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['  r := a + b', 'end;']);
  try
    Info := BuildAt(Lines, 1, 'r :=');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(0, Info.InsertLine,
        'ohne Semikolon liesse sich dahinter keine Anweisung anhaengen');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

{ ---- Hash ---- }

procedure TTestRefactorInfoBuilder.Hash_IsSha256Hex_AndMatchesHashOfSpan;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['  r := a + b;']);
  try
    Info := BuildAt(Lines, 1, 'r :=');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(64, Length(Info.SpanHash),
        'SHA256 als Hex sind 64 Zeichen');
      Assert.AreEqual(Info.SpanHash,
        TRefactorInfoBuilder.HashOfSpan(Lines, Info.Span),
        'ein Konsument rechnet mit HashOfSpan denselben Wert nach');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.Hash_ChangesWithOneCharacterInSpan;
var
  Lines : TStringList;
  A, B  : TRefactorInfo;
begin
  Lines := MakeLines(['  r := a + b;']);
  try
    A := BuildAt(Lines, 1, 'r :=');
    try
      Lines[0] := '  r := a + c;';
      B := BuildAt(Lines, 1, 'r :=');
      try
        Assert.IsTrue(Assigned(A) and Assigned(B));
        Assert.AreNotEqual(A.SpanHash, B.SpanHash,
          'ein geaendertes Zeichen im Bereich aendert den Hash');
      finally
        B.Free;
      end;
    finally
      A.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.Hash_IgnoresTextOutsideSpan;
var
  Lines : TStringList;
  A, B  : TRefactorInfo;
begin
  Lines := MakeLines(['  r := a + b; // alt']);
  try
    A := BuildAt(Lines, 1, 'r :=');
    try
      Lines[0] := '      r := a + b; // neu und laenger';
      B := BuildAt(Lines, 1, 'r :=');
      try
        Assert.IsTrue(Assigned(A) and Assigned(B));
        Assert.AreEqual(A.SpanHash, B.SpanHash,
          'Einrueckung und Kommentar ausserhalb des Bereichs zaehlen nicht');
      finally
        B.Free;
      end;
    finally
      A.Free;
    end;
  finally
    Lines.Free;
  end;
end;

{ ---- Code-Sicht ---- }

procedure TTestRefactorInfoBuilder.CodeView_IsColumnTrue_StringsAreFill;
const
  L1 = '  r := ''ab'' + c; // x';
var
  Lines : TStringList;
  Info  : TRefactorInfo;
  View  : TArray<string>;
  Q     : Integer;
begin
  Lines := MakeLines([L1]);
  try
    Info := BuildAt(Lines, 1, 'r :=');
    try
      Assert.IsTrue(Assigned(Info));
      View := TRefactorInfoBuilder.CodeViewOf(Lines, Info.Span);
      Assert.AreEqual<Integer>(1, Length(View));
      Assert.AreEqual<Integer>(Info.Span.EndCol - 1, Length(View[0]),
        'die Sicht endet mit dem Bereich');
      Q := Pos('''', L1);
      Assert.AreEqual(StringOfChar(TRefactorInfoBuilder.VIEW_FILL, 4),
        Copy(View[0], Q, 4), 'das Literal samt Apostrophen ist ausgeblendet');
      Assert.AreEqual('c', Copy(View[0], Pos('c;', L1), 1),
        'Code steht in der Sicht an derselben Spalte wie in der Quelle');
      Assert.AreEqual('  ', Copy(View[0], 1, 2),
        'vor dem Bereich stehen Leerzeichen');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTestRefactorInfoBuilder.SpanText_MultiLine_JoinedWithLf;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['  x := a +', '    b +', '    c; // Rest']);
  try
    Info := BuildAt(Lines, 1, 'x :=');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual('x := a +'#10'    b +'#10'    c;',
        TRefactorInfoBuilder.SpanText(Lines, Info.Span));
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

{ ---- Vertrag ---- }

procedure TTestRefactorInfoBuilder.Builder_LeavesPartsEmptyAndFixSafeFalse;
var
  Lines : TStringList;
  Info  : TRefactorInfo;
begin
  Lines := MakeLines(['r := a + b;']);
  try
    Info := BuildAt(Lines, 1, 'r :=');
    try
      Assert.IsTrue(Assigned(Info));
      Assert.AreEqual<Integer>(0, Length(Info.Parts),
        'Teilbereiche sind Sache des Detektors');
      Assert.IsFalse(Info.FixSafe,
        'fix-sicher setzt nur der Detektor, nie der Builder');
    finally
      Info.Free;
    end;
  finally
    Lines.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRefactorInfoBuilder);

end.
