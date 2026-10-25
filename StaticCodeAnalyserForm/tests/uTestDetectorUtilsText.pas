unit uTestDetectorUtilsText;

// Direkttests fuer die Text-Helfer in TDetectorUtils, die bis zum Review
// Bereich C Engine-Kern (Major 13, 2026-10-14) nur ueber Detektoren
// geprueft waren: InStringLiteral, StripFileCommentsKeepStrings,
// SplitTopLevelArgs (seit 2026-10-14 mit eckigen Klammern) und die
// Wortgrenzen-Suchen, deren Wiederaufsetzen nach einem verworfenen
// Treffer quadratisch war (Start+1 statt i+1). Eigene Unit: die
// bestehende Fixture TTestDetectorUtils traegt schon 68 Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestDetectorUtilsText = class
  public
    [Test] procedure InStringLiteral_InsideAndOutside;
    [Test] procedure InStringLiteral_DoubledQuoteKeepsParity;
    [Test] procedure InStringLiteral_LineBoundaryResets;
    [Test] procedure StripFileCommentsKeepStrings_RemovesCommentsKeepsLiterals;
    [Test] procedure StripFileCommentsKeepStrings_LineMapFollowsSource;
    [Test] procedure SplitTopLevelArgs_ParensStringsAndBrackets;
    [Test] procedure FindWholeWordLower_SkipsPartialMatches_FindsLater;
    [Test] procedure FindWholeWordLower_FromOffset_AndNoMatch;
    [Test] procedure FindTokenBoundedLower_PunctuationEdges;
    [Test] procedure ContainsLowerAscii_SameAsPosOfLowerCase;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uDetectorUtils;

procedure TTestDetectorUtilsText.InStringLiteral_InsideAndOutside;
const
  Code = 'a := ''x'' + b;';
begin
  Assert.IsTrue(TDetectorUtils.InStringLiteral(Code, Pos('x', Code)),
    'x steht im Literal');
  Assert.IsFalse(TDetectorUtils.InStringLiteral(Code, Pos('b', Code)),
    'b steht hinter dem Literal');
  Assert.IsFalse(TDetectorUtils.InStringLiteral(Code, 1), 'Zeilenanfang');
end;

procedure TTestDetectorUtilsText.InStringLiteral_DoubledQuoteKeepsParity;
// 'it''s': das verdoppelte '' zaehlt als zwei und laesst die Paritaet
// unveraendert - das s steht weiter im Literal.
const
  Code = 'a := ''it''''s'' + b;';
begin
  Assert.IsTrue(TDetectorUtils.InStringLiteral(Code, Pos('s''', Code)),
    's liegt im Literal');
  Assert.IsFalse(TDetectorUtils.InStringLiteral(Code, Pos('b', Code)));
end;

procedure TTestDetectorUtilsText.InStringLiteral_LineBoundaryResets;
// Ein Pascal-Literal endet spaetestens am Zeilenende: die Zaehlung
// beginnt hinter dem letzten #10 neu.
const
  Code = 'a := ''x'#10'b := 1;';
begin
  Assert.IsTrue(TDetectorUtils.InStringLiteral(Code, Pos('x', Code)));
  Assert.IsFalse(TDetectorUtils.InStringLiteral(Code, Pos('b', Code)),
    'die offene Zeile davor zaehlt nicht mit');
end;

procedure TTestDetectorUtilsText.StripFileCommentsKeepStrings_RemovesCommentsKeepsLiterals;
var
  Lines   : TStringList;
  LineFor : TArray<Integer>;
  S       : string;
begin
  Lines := TStringList.Create;
  try
    Lines.Add('x := 1; // c');
    Lines.Add('{ block');
    Lines.Add('still } y := ''{'';');
    Lines.Add('(* p *) z;');
    S := TDetectorUtils.StripFileCommentsKeepStrings(Lines, LineFor);
    Assert.AreEqual('x := 1; '#10#10' y := ''{'';'#10' z;'#10, S,
      'Kommentare weg, Literal samt { bleibt, je Zeile ein #10');
    Assert.AreEqual<Integer>(Length(S), Length(LineFor),
      'ein Zeilenindex je Ergebnis-Zeichen');
  finally
    Lines.Free;
  end;
end;

procedure TTestDetectorUtilsText.StripFileCommentsKeepStrings_LineMapFollowsSource;
var
  Lines   : TStringList;
  LineFor : TArray<Integer>;
  S       : string;
  P       : Integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Add('{ a');
    Lines.Add('  b }');
    Lines.Add('q := 2;');
    S := TDetectorUtils.StripFileCommentsKeepStrings(Lines, LineFor);
    P := Pos('q', S);
    Assert.IsTrue(P > 0);
    Assert.AreEqual<Integer>(2, LineFor[P - 1], '0-basierter Quellzeilen-Index');
    Assert.AreEqual<Integer>(3, TDetectorUtils.LineForPos(LineFor, P),
      'LineForPos rechnet 1-basiert zurueck');
    Assert.AreEqual<Integer>(0, TDetectorUtils.LineForPos(LineFor, Length(S) + 5),
      'ausserhalb der Map: 0');
  finally
    Lines.Free;
  end;
end;

procedure TTestDetectorUtilsText.SplitTopLevelArgs_ParensStringsAndBrackets;
var
  Teile : TArray<string>;
begin
  Teile := TDetectorUtils.SplitTopLevelArgs('a, F(b, c), ''x,y'', [1, 2], d');
  Assert.AreEqual<Integer>(5, Length(Teile),
    'Kommata in Klammern, Literal und eckigen Klammern trennen nicht');
  Assert.AreEqual('a', Teile[0]);
  Assert.AreEqual(' F(b, c)', Teile[1], 'ungetrimmt, wie die Ursprungsfassung');
  Assert.AreEqual(' ''x,y''', Teile[2]);
  Assert.AreEqual(' [1, 2]', Teile[3]);
  Assert.AreEqual(' d', Teile[4]);
  Teile := TDetectorUtils.SplitTopLevelArgs('');
  Assert.AreEqual<Integer>(1, Length(Teile), 'leer -> ein leerer Teil');
end;

procedure TTestDetectorUtilsText.FindWholeWordLower_SkipsPartialMatches_FindsLater;
begin
  Assert.AreEqual<Integer>(4, TDetectorUtils.FindWholeWordLower('sql', 'my.sql='));
  Assert.AreEqual<Integer>(0, TDetectorUtils.FindWholeWordLower('sql', '.sqlnot'));
  // Drei verworfene Teiltreffer, dann der echte: das Wiederaufsetzen
  // hinter dem Treffer (i+1) liefert dasselbe wie das alte Start+1.
  Assert.AreEqual<Integer>(13,
    TDetectorUtils.FindWholeWordLower('ab', 'xab xab xab ab'));
  Assert.IsTrue(TDetectorUtils.ContainsWholeWordLower('ab', 'x ab'));
  Assert.IsFalse(TDetectorUtils.ContainsWholeWordLower('ab', 'xab'));
end;

procedure TTestDetectorUtilsText.FindWholeWordLower_FromOffset_AndNoMatch;
begin
  Assert.AreEqual<Integer>(4, TDetectorUtils.FindWholeWordLower('ab', 'ab ab', 2));
  Assert.AreEqual<Integer>(0, TDetectorUtils.FindWholeWordLower('ab', 'ab ab', 0),
    'AFrom < 1 liefert 0 (Kontrakt der WortPosAb-Kopie)');
  Assert.AreEqual<Integer>(0, TDetectorUtils.FindWholeWordLower('', 'ab'));
  Assert.AreEqual<Integer>(0, TDetectorUtils.FindWholeWordLower('abc', 'ab'));
  Assert.AreEqual<Integer>(0, TDetectorUtils.FindWholeWordLower('ab', 'xaby xaby'));
end;

procedure TTestDetectorUtilsText.FindTokenBoundedLower_PunctuationEdges;
begin
  Assert.AreEqual<Integer>(7, TDetectorUtils.FindTokenBoundedLower('.text', 'edpath.text'));
  Assert.AreEqual<Integer>(0, TDetectorUtils.FindTokenBoundedLower('.text', 'mediatype.text_a'));
  Assert.AreEqual<Integer>(4, TDetectorUtils.FindTokenBoundedLower('paramstr(', 'x:=paramstr(0)'));
  // Verworfener Treffer (rechts ein Ident-Zeichen), dann der echte.
  Assert.AreEqual<Integer>(16,
    TDetectorUtils.FindTokenBoundedLower('.text', 'a.text_b.text_c.text'));
end;

procedure TTestDetectorUtilsText.ContainsLowerAscii_SameAsPosOfLowerCase;
// Review Charge P: die Vorpruefungen von SCA-IntegerOverflow ('nt64',
// 'qword') und CollectFpcBindingTypeNames ('objc', 'cppclass') fragten
// Pos(.., LowerCase(Code)) > 0 - ContainsLowerAscii muss je Text dasselbe
// sagen, auch fuer Nicht-ASCII (LowerCase faltet nur A..Z: das tuerkische
// I mit Punkt U+0130 und das A mit Umlaut U+00C4 bleiben, wie sie sind).
const
  NEEDLES : array[0..4] of string = ('nt64', 'qword', 'objc', 'cppclass', '');
var
  Texts : array[0..11] of string;
  i, k  : Integer;
begin
  Texts[0]  := '';
  Texts[1]  := 'x: Int64;';
  Texts[2]  := 'X: UINT64;';
  Texts[3]  := 'nt64';                    // Treffer am Anfang = Ende
  Texts[4]  := 'q: QWord';                // Treffer am Ende
  Texts[5]  := 'nt6';                     // kuerzer als das Muster
  Texts[6]  := 'n t64 qwor d';            // getrennt - kein Treffer
  Texts[7]  := 'I' + Char($0130) + 'NT64'; // Grossbuchstaben ringsum, nach Nicht-ASCII
  Texts[8]  := Char($00C4) + 'NT64';
  Texts[9]  := 'ObjCClass CPPCLASS';
  Texts[10] := 'nnt64 qqword';            // Wiederaufsetzen nach Teiltreffer
  Texts[11] := 'N' + Char($0130) + '64 Q' + Char($00C4) + 'ORD';  // Nicht-ASCII im Muster-Platz
  for k := Low(NEEDLES) to High(NEEDLES) do
    for i := Low(Texts) to High(Texts) do
      Assert.AreEqual<Boolean>(Pos(NEEDLES[k], LowerCase(Texts[i])) > 0,
        TDetectorUtils.ContainsLowerAscii(Texts[i], NEEDLES[k]),
        Format('''%s'' in Text %d', [NEEDLES[k], i]));
  Assert.IsTrue(TDetectorUtils.ContainsLowerAscii('X: UINT64;', 'nt64'),
    'Gegenprobe: Grossschreibung trifft');
  Assert.IsFalse(TDetectorUtils.ContainsLowerAscii('n t64', 'nt64'),
    'Gegenprobe: Luecke trifft nicht');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestDetectorUtilsText);

end.
