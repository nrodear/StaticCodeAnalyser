unit uTestDetectorUtils;

// Direkte Unit-Tests fuer die zentrale String-/Kommentar-Zustandsmaschine
// in TDetectorUtils (ScanCodeLine / StripStringsAndComments). Diese Logik
// war frueher in uFloatEquality und uNoSonarMarker dupliziert - jeder
// Drift dort war ein potenzieller False-Positive. Die Tests pinnen das
// Verhalten fest, damit beide Detektoren auf einer gepruefen Basis stehen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDetectorUtils = class
  public
    // ---- ScanCodeLine ----
    [Test] procedure PlainCode_NoCommentNoChange;
    [Test] procedure LineComment_TruncatedAndColReported;
    [Test] procedure StringLiteral_FilledNotComment;
    [Test] procedure SlashSlashInsideString_NotAComment;
    [Test] procedure BraceComment_Removed;
    [Test] procedure EscapedQuote_StringStaysOpen;
    [Test] procedure MultiLineBraceComment_StateCarried;
    [Test] procedure MultiLineParenStarComment_StateCarried;
    // ---- StripStringsAndComments ----
    [Test] procedure Strip_LineForCharMapsToSourceLine;
    [Test] procedure Strip_EmptyStringKeepsFollowingKeyword;
    [Test] procedure Strip_NewlinePerSourceLine;
    // ---- MergeAdjacentStringLiterals ----
    [Test] procedure Merge_SimpleConcat;
    [Test] procedure Merge_NoSpaceAroundPlus;
    [Test] procedure Merge_ChainedThreeLiterals;
    [Test] procedure Merge_EscapedQuotePreservedInsideLiteral;
    [Test] procedure Merge_PlusOutsideLiterals_Untouched;
    [Test] procedure Merge_NoLiterals_Unchanged;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uDetectorUtils;

{ ---- ScanCodeLine ---- }

procedure TTestDetectorUtils.PlainCode_NoCommentNoChange;
var
  State : TCommentScanState;
  Col   : Integer;
  R     : string;
begin
  State := Default(TCommentScanState);
  R := TDetectorUtils.ScanCodeLine('x := y + 1;', State, Col);
  Assert.AreEqual('x := y + 1;', R);
  Assert.AreEqual<Integer>(0, Col);
end;

procedure TTestDetectorUtils.LineComment_TruncatedAndColReported;
var
  State : TCommentScanState;
  Col   : Integer;
  R     : string;
begin
  State := Default(TCommentScanState);
  // 'DoStuff; // NOSONAR' -> '//' beginnt auf Spalte 10 (1-basiert).
  R := TDetectorUtils.ScanCodeLine('DoStuff; // NOSONAR', State, Col);
  Assert.AreEqual<Integer>(10, Col);
  Assert.IsTrue(R.StartsWith('DoStuff;'), 'Code vor // bleibt erhalten');
  Assert.AreEqual<Integer>(0, Pos('NOSONAR', R), 'Kommentartext darf nicht im Code sein');
end;

procedure TTestDetectorUtils.StringLiteral_FilledNotComment;
var
  State : TCommentScanState;
  Col   : Integer;
  R     : string;
begin
  State := Default(TCommentScanState);
  R := TDetectorUtils.ScanCodeLine('s := ''hello'';', State, Col);
  Assert.AreEqual<Integer>(0, Col, 'kein Zeilenkommentar');
  Assert.AreEqual<Integer>(0, Pos('hello', R), 'String-Inhalt wird ersetzt');
  Assert.IsTrue(Pos('~', R) > 0, 'Fuellzeichen steht fuer den String');
end;

procedure TTestDetectorUtils.SlashSlashInsideString_NotAComment;
var
  State : TCommentScanState;
  Col   : Integer;
  R     : string;
begin
  State := Default(TCommentScanState);
  // Das `//` steckt im String-Literal - es ist KEIN Zeilenkommentar.
  R := TDetectorUtils.ScanCodeLine('s := ''// not a comment'';', State, Col);
  Assert.AreEqual<Integer>(0, Col, '// im String ist kein Kommentar');
  Assert.AreEqual<Integer>(0, Pos('/', R), 'kein Slash bleibt uebrig (String gefuellt)');
end;

procedure TTestDetectorUtils.BraceComment_Removed;
var
  State : TCommentScanState;
  Col   : Integer;
  R     : string;
begin
  State := Default(TCommentScanState);
  R := TDetectorUtils.ScanCodeLine('a := 1; { note } b := 2;', State, Col);
  Assert.AreEqual<Integer>(0, Col);
  Assert.AreEqual<Integer>(0, Pos('note', R), 'Block-Kommentar entfernt');
  Assert.IsTrue(Pos('b := 2;', R) > 0, 'Code nach } bleibt erhalten');
  Assert.IsFalse(State.InBraceComment, 'Block auf derselben Zeile geschlossen');
end;

procedure TTestDetectorUtils.EscapedQuote_StringStaysOpen;
var
  State : TCommentScanState;
  Col   : Integer;
  R     : string;
begin
  State := Default(TCommentScanState);
  // 'it''s' ist EIN String mit verdoppeltem Apostroph - bleibt offen bis
  // zum echten Schluss-Quote. Danach ist ';' wieder Code.
  R := TDetectorUtils.ScanCodeLine('s := ''it''''s'';', State, Col);
  Assert.AreEqual<Integer>(0, Col);
  Assert.AreEqual<Integer>(0, Pos('it', R), 'String-Inhalt komplett ersetzt');
  Assert.IsTrue(R.EndsWith(';'), 'Code nach String wieder sichtbar');
end;

procedure TTestDetectorUtils.MultiLineBraceComment_StateCarried;
var
  State : TCommentScanState;
  Col   : Integer;
  R1, R2: string;
begin
  State := Default(TCommentScanState);
  R1 := TDetectorUtils.ScanCodeLine('code1 { open block', State, Col);
  Assert.IsTrue(State.InBraceComment, 'offener {-Block wird getragen');
  Assert.IsTrue(R1.StartsWith('code1'), 'Code vor { bleibt');

  R2 := TDetectorUtils.ScanCodeLine('still comment } code2;', State, Col);
  Assert.IsFalse(State.InBraceComment, 'Block auf Folgezeile geschlossen');
  Assert.AreEqual<Integer>(0, Pos('comment', R2), 'Kommentar-Rest entfernt');
  Assert.IsTrue(Pos('code2;', R2) > 0, 'Code nach } sichtbar');
end;

procedure TTestDetectorUtils.MultiLineParenStarComment_StateCarried;
var
  State : TCommentScanState;
  Col   : Integer;
  R2    : string;
begin
  State := Default(TCommentScanState);
  TDetectorUtils.ScanCodeLine('x := 1; (* open', State, Col);
  Assert.IsTrue(State.InParenComment, 'offener (*-Block wird getragen');

  R2 := TDetectorUtils.ScanCodeLine('inside *) y := 2;', State, Col);
  Assert.IsFalse(State.InParenComment, '(*-Block geschlossen');
  Assert.AreEqual<Integer>(0, Pos('inside', R2), 'Kommentar-Rest entfernt');
  Assert.IsTrue(Pos('y := 2;', R2) > 0, 'Code nach *) sichtbar');
end;

{ ---- StripStringsAndComments ---- }

procedure TTestDetectorUtils.Strip_LineForCharMapsToSourceLine;
var
  Lines   : TStringList;
  LineFor : TArray<Integer>;
  Code    : string;
  P       : Integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Add('x := ''abc'';');   // Zeile 0
    Lines.Add('// comment');      // Zeile 1
    Lines.Add('y := 1;');         // Zeile 2
    Code := TDetectorUtils.StripStringsAndComments(Lines, LineFor);

    Assert.AreEqual<NativeInt>(Length(Code), Length(LineFor),
      'pro Zeichen genau ein Zeilen-Mapping');
    Assert.AreEqual<Integer>(0, Pos('abc', Code), 'String-Inhalt ersetzt');
    Assert.AreEqual<Integer>(0, Pos('comment', Code), 'Zeilenkommentar entfernt');

    P := Pos('y', Code);
    Assert.IsTrue(P > 0, 'y vorhanden');
    Assert.AreEqual<Integer>(2, LineFor[P - 1], 'y stammt aus Quellzeile 2');
  finally
    Lines.Free;
  end;
end;

procedure TTestDetectorUtils.Strip_EmptyStringKeepsFollowingKeyword;
var
  Lines   : TStringList;
  LineFor : TArray<Integer>;
  Code    : string;
begin
  // Regression (vgl. uFloatEquality): `aValue = '' then` darf nach dem
  // Strippen NICHT als `aValue =   then` erscheinen, sonst kassiert eine
  // `[\w.]+`-Regex das Keyword `then` als RHS. Mit ~~ als Fueller bleibt
  // `then` ein eigenes Token und der Match scheitert korrekt am ersten ~.
  Lines := TStringList.Create;
  try
    Lines.Add('if aValue = '''' then Exit;');
    Code := TDetectorUtils.StripStringsAndComments(Lines, LineFor);
    Assert.IsTrue(Pos('~~', Code) > 0, 'leerer String wird zu Fuellzeichen');
    Assert.IsTrue(Pos('then', Code) > 0, 'Keyword then bleibt erhalten');
    Assert.AreEqual<Integer>(0, Pos('''', Code), 'keine Apostrophe mehr im Code');
  finally
    Lines.Free;
  end;
end;

procedure TTestDetectorUtils.Strip_NewlinePerSourceLine;
var
  Lines   : TStringList;
  LineFor : TArray<Integer>;
  Code    : string;
  i, NL   : Integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Add('a;');
    Lines.Add('b;');
    Lines.Add('c;');
    Code := TDetectorUtils.StripStringsAndComments(Lines, LineFor);
    NL := 0;
    for i := 1 to Length(Code) do
      if Code[i] = #10 then Inc(NL);
    Assert.AreEqual<Integer>(3, NL, 'ein #10 pro Quellzeile');
  finally
    Lines.Free;
  end;
end;

{ ---- MergeAdjacentStringLiterals ---- }

procedure TTestDetectorUtils.Merge_SimpleConcat;
// 'foo' + 'bar' -> 'foobar'  - der Klassiker.
const Source = '''foo'' + ''bar''';
const Expected = '''foobar''';
begin
  Assert.AreEqual(Expected,
    TDetectorUtils.MergeAdjacentStringLiterals(Source));
end;

procedure TTestDetectorUtils.Merge_NoSpaceAroundPlus;
// 'foo'+'bar' (kein Space) - exakt die Form die uSqlDangerousStatement
// im AST-Lowercase sieht und an der die WHERE-Erkennung scheiterte.
const Source = '''foo''+''bar''';
const Expected = '''foobar''';
begin
  Assert.AreEqual(Expected,
    TDetectorUtils.MergeAdjacentStringLiterals(Source));
end;

procedure TTestDetectorUtils.Merge_ChainedThreeLiterals;
// 'a' + 'b' + 'c' -> 'abc' - Kette wird bis zum Ende aufgeloest.
const Source = '''a'' + ''b'' + ''c''';
const Expected = '''abc''';
begin
  Assert.AreEqual(Expected,
    TDetectorUtils.MergeAdjacentStringLiterals(Source));
end;

procedure TTestDetectorUtils.Merge_EscapedQuotePreservedInsideLiteral;
// Verdoppelte Apostrophen ('') innerhalb des Literals duerfen NICHT als
// Literal-Ende interpretiert werden - sie sind ein Escape und bleiben
// als '' im Output. Quelle: 'a''b' + 'c' -> 'a''bc'.
const Source = '''a''''b'' + ''c''';
const Expected = '''a''''bc''';
begin
  Assert.AreEqual(Expected,
    TDetectorUtils.MergeAdjacentStringLiterals(Source));
end;

procedure TTestDetectorUtils.Merge_PlusOutsideLiterals_Untouched;
// '+' das nicht zwischen zwei Literalen steht (z.B. zwischen Literal
// und Variable) bleibt unangetastet - sonst wuerden wir Ausdruecke
// faelschlich zusammenkleben.
const Source = '''foo'' + xVar';
const Expected = '''foo'' + xVar';
begin
  Assert.AreEqual(Expected,
    TDetectorUtils.MergeAdjacentStringLiterals(Source));
end;

procedure TTestDetectorUtils.Merge_NoLiterals_Unchanged;
// Komplett ohne String-Literale - identitaet.
const Source = 'a + b + c';
const Expected = 'a + b + c';
begin
  Assert.AreEqual(Expected,
    TDetectorUtils.MergeAdjacentStringLiterals(Source));
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDetectorUtils);

end.
