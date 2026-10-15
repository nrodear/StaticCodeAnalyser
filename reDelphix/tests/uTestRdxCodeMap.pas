unit uTestRdxCodeMap;

// Die Code-Sicht des Moduls (uRdxCodeMap) gegen die Regel des Cores
// (TDetectorUtils.ScanCodeLine): an Eingaben OHNE mehrzeilige Strings
// muessen die Spalte des '//'-Kommentars und der offene Block-Kommentar am
// Zeilenanfang uebereinstimmen - der Drift-Waechter fuer die zwei Kopien
// derselben Regel (Review reDelphiX nach Bereichen 2026-10-10, Minor 7).
// Dazu StartsInside, auf dem die Unterdrueck-Hilfen bauen (Major 1), und
// seit Charge R8 (2026-10-14) die geteilten Laeufe der Planer:
// Klammerabgleich (MatchClose, AfterClose), "genau ein Token auf der Zeile"
// (OneTokenOnLine), end-Bilanz (BlockEnd) und DirectiveInLines - bis dahin
// je Planer eine Kopie. Seit Charge H4c TokBefore/TokText (bis dahin je
// eine Kopie in uRdxRoutineFixes und uRdxTryFixes) und IsKeywordAt (kein
// Schluesselwort vor ':=' - benanntes OLE-Argument 'End := 1'). Seit
// Charge B2S-a die geteilten Helfer der Fix-Units QuotedText und
// ParenDelta (Review R3-05: bis dahin fuenf Kopien bzw. drei Kopien und
// sieben ausgeschriebene Zaehlungen).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxCodeMap = class
  public
    [Test] procedure AgreesWithScanCodeLine;
    [Test] procedure StartsInside_BlockComments;
    [Test] procedure StartsInside_MultiLineString;
    // Charge R8: die geteilten Laeufe der Planer.
    [Test] procedure MatchClose_Pairs;
    [Test] procedure MatchClose_LineLimit;
    [Test] procedure AfterClose_BehindOrEmpty;
    [Test] procedure OneTokenOnLine_NoneOneMany;
    [Test] procedure BlockEnd_NestedAndHook;
    [Test] procedure DirectiveInLines_NotInLineComment;
    // Charge H4c.
    [Test] procedure TokHelpers_AndKeywordAt;
    // Charge B2S-a.
    [Test] procedure SharedHelpers_QuotedTextAndParenDelta;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uDetectorUtils, uRdxCodeMap,
  uTestRdxTextKit;   // Join

// Zeile und Spalte eines Tokens als 'Z:S' - fuer kurze Vergleiche.
function Pos2(const T: TRdxToken): string;
begin
  Result := Format('%d:%d', [T.Line, T.Col]);
end;

// Praedikat fuer OneTokenOnLine: das Wort AArg.
function IsWordArg(AMap: TRdxCodeMap; const T: TRdxToken;
  const AArg: string): Boolean;
begin
  Result := T.Low = AArg;
end;

// Haken fuer BlockEnd: ein 'if' auf der obersten Ebene bricht ab.
function StopAtTopIf(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  ADepth: Integer): string;
begin
  Result := '';
  if (ADepth = 1) and (T.Low = 'if') then
    Result := 'if auf Tiefe 1';
end;

const
  // Je Eintrag eine Datei; keine ''' am Zeilenende (die kennt nur die
  // Code-Sicht).
  SAMPLES: array[0..9] of string = (
    'x := 1; // a'#13#10'y := ''//no''; // b',
    '{ a // b'#13#10'  c // d }'#13#10'e; // f',
    '(* x'#13#10' // y *) z // w',
    'a { b } c // d { e'#13#10'f',
    'S := ''it''''s // no'';  // yes',
    '{$IFDEF X} a // b'#13#10'{ multi'#13#10'line } c',
    'x := ''{''; // c'#13#10'y;',
    '// { oeffnet nicht'#13#10'code',
    '(* { *) a // b'#13#10'{ (* } x // y',
    'p(''a'', { k } ''b''); (* u'#13#10#13#10'v *) // w'
  );

procedure TTestRdxCodeMap.AgreesWithScanCodeLine;
var
  s, i    : Integer;
  SL      : TStringList;
  Map     : TRdxCodeMap;
  State   : TCommentScanState;
  Col     : Integer;
  Inside  : Boolean;
  Where   : string;
begin
  for s := Low(SAMPLES) to High(SAMPLES) do
  begin
    SL := TStringList.Create;
    try
      SL.Text := SAMPLES[s];
      Map := TRdxCodeMap.Create(SL);
      try
        State := Default(TCommentScanState);
        for i := 0 to SL.Count - 1 do
        begin
          Where := Format('Beispiel %d, Zeile %d: %s', [s, i + 1, SL[i]]);
          Inside := State.InBraceComment or State.InParenComment;
          TDetectorUtils.ScanCodeLine(SL[i], State, Col);
          Assert.AreEqual<Integer>(Col, Map.LineCommentCol(i + 1), Where);
          Assert.IsTrue(Inside = Map.StartsInside(i + 1), Where);
        end;
      finally
        Map.Free;
      end;
    finally
      SL.Free;
    end;
  end;
end;

procedure TTestRdxCodeMap.StartsInside_BlockComments;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  try
    SL.Text := 'a; { b'#13#10'c'#13#10'} d;'#13#10'(* e'#13#10'*) f;'#13#10'g;';
    Map := TRdxCodeMap.Create(SL);
    try
      Assert.IsFalse(Map.StartsInside(1));
      Assert.IsTrue(Map.StartsInside(2));
      Assert.IsTrue(Map.StartsInside(3), 'die schliessende Zeile beginnt noch darin');
      Assert.IsFalse(Map.StartsInside(4));
      Assert.IsTrue(Map.StartsInside(5));
      Assert.IsFalse(Map.StartsInside(6));
      Assert.IsFalse(Map.StartsInside(0), 'ausserhalb der Datei');
      Assert.IsFalse(Map.StartsInside(7), 'ausserhalb der Datei');
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
end;

procedure TTestRdxCodeMap.StartsInside_MultiLineString;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  try
    SL.Text := 'S := '''''''#13#10'  // kein Kommentar'#13#10'  '''''';'#13#10'x;';
    Map := TRdxCodeMap.Create(SL);
    try
      Assert.IsFalse(Map.StartsInside(1));
      Assert.IsTrue(Map.StartsInside(2));
      Assert.AreEqual<Integer>(0, Map.LineCommentCol(2), 'String, kein Kommentar');
      Assert.IsTrue(Map.StartsInside(3));
      Assert.IsFalse(Map.StartsInside(4));
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
end;

procedure TTestRdxCodeMap.MatchClose_Pairs;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  try
    SL.Text := Join(['a(b[c](d))e;', 'X<A, B<C>> := 1;', '(a']);
    Map := TRdxCodeMap.Create(SL);
    try
      Assert.AreEqual('1:10', Pos2(MatchClose(Map, TokenAt(Map, 1, 2))),
        '( ueber eine innere Gruppe hinweg');
      Assert.AreEqual('1:6', Pos2(MatchClose(Map, TokenAt(Map, 1, 4))), '[');
      Assert.AreEqual('1:9', Pos2(MatchClose(Map, TokenAt(Map, 1, 7))),
        'innere (');
      Assert.AreEqual('2:10', Pos2(MatchClose(Map, TokenAt(Map, 2, 2))),
        '< zaehlt nur < und >');
      Assert.AreEqual('', MatchClose(Map, TokenAt(Map, 1, 1)).Low,
        'kein Oeffner: leer');
      Assert.AreEqual('', MatchClose(Map, TokenAt(Map, 3, 1)).Low,
        'ohne Schluss: leer');
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
end;

procedure TTestRdxCodeMap.MatchClose_LineLimit;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  try
    SL.Text := Join(['(a', 'b', ')']);
    Map := TRdxCodeMap.Create(SL);
    try
      Assert.AreEqual('3:1', Pos2(MatchClose(Map, TokenAt(Map, 1, 1))),
        'ohne Grenze ueber Zeilen');
      Assert.AreEqual('3:1', Pos2(MatchClose(Map, TokenAt(Map, 1, 1), 2)),
        'Grenze 2 reicht bis Zeile 3');
      Assert.AreEqual('', MatchClose(Map, TokenAt(Map, 1, 1), 1).Low,
        'Grenze 1 endet vor Zeile 3');
      Assert.AreEqual('', MatchClose(Map, TokenAt(Map, 1, 1), 0).Low,
        'Grenze 0: nur die eigene Zeile');
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
end;

procedure TTestRdxCodeMap.AfterClose_BehindOrEmpty;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  try
    SL.Text := Join(['(a) b', '(c', '(d)']);
    Map := TRdxCodeMap.Create(SL);
    try
      Assert.AreEqual('b', AfterClose(Map, TokenAt(Map, 1, 1)).Low);
      Assert.AreEqual('', AfterClose(Map, TokenAt(Map, 2, 1)).Low,
        'ohne Schluss: leer, nicht das erste Token der Datei');
      Assert.AreEqual('', AfterClose(Map, TokenAt(Map, 3, 1)).Low,
        'Schluss am Dateiende: leer');
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
end;

procedure TTestRdxCodeMap.OneTokenOnLine_NoneOneMany;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  S   : TRdxLineSearch;
  Hit : TRdxToken;
begin
  SL := TStringList.Create;
  try
    SL.Text := Join(['x := 1; y := x; // z', 'z := 2;']);
    Map := TRdxCodeMap.Create(SL);
    try
      S := Default(TRdxLineSearch);
      S.Test    := IsWordArg;
      S.What    := 'kein Treffer';
      S.ManyFmt := '%d-mal das Wort';
      S.Arg := 'y';
      Assert.AreEqual('', OneTokenOnLine(Map, 1, S, Hit));
      Assert.AreEqual('1:9', Pos2(Hit));
      S.Arg := 'x';
      Assert.AreEqual('Zeile 1 traegt 2-mal das Wort - mehrdeutig',
        OneTokenOnLine(Map, 1, S, Hit));
      // ManyArg kommt als %s ins Muster - Text aus der Meldung, auch mit
      // '%', steht nie im Muster selbst (Nachpruefung C1). Pos auf das
      // umlautfreie Ende: 'traegt' bekommt in de.po einen echten Umlaut.
      S.ManyFmt := '%d-mal %s';
      S.ManyArg := 'x 100%';
      Assert.IsTrue(Pos('2-mal x 100% - mehrdeutig',
        OneTokenOnLine(Map, 1, S, Hit)) > 0, 'ManyArg als %s im Muster');
      S.Arg := 'z';
      Assert.AreEqual('kein Treffer auf der gemeldeten Zeile - Zeile '
        + 'verschoben? Datei neu pruefen', OneTokenOnLine(Map, 1, S, Hit),
        'ein z im Kommentar zaehlt nicht, Zeile 2 auch nicht');
      Assert.AreEqual('', Hit.Low, 'ohne Treffer leer');
      Assert.AreEqual('', OneTokenOnLine(Map, 2, S, Hit));
      Assert.AreEqual('2:1', Pos2(Hit));
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
end;

procedure TTestRdxCodeMap.BlockEnd_NestedAndHook;
var
  SL        : TStringList;
  Map       : TRdxCodeMap;
  EndTok, L : TRdxToken;
begin
  SL := TStringList.Create;
  try
    SL.Text := Join(['begin', '  if a then begin b; end;', '  &end := 1;',
      '  try c; finally d; end;', 'end;', 'begin', '  e;']);
    Map := TRdxCodeMap.Create(SL);
    try
      Assert.AreEqual('', BlockEnd(Map, TokenAt(Map, 1, 1), nil, EndTok, L));
      Assert.AreEqual('5:1', Pos2(EndTok),
        'innere Bloecke und der Bezeichner &end zaehlen nicht');
      Assert.AreEqual('4:24', Pos2(L), 'das Token vor dem end: das ";"');
      Assert.AreEqual('if auf Tiefe 1',
        BlockEnd(Map, TokenAt(Map, 1, 1), StopAtTopIf, EndTok, L),
        'der Haken bricht ab');
      Assert.AreEqual('', EndTok.Low, 'nach dem Abbruch leer');
      Assert.AreEqual('', BlockEnd(Map, TokenAt(Map, 6, 1), nil, EndTok, L),
        'ohne end: kein Grund ...');
      Assert.AreEqual('', EndTok.Low, '... aber auch kein end');
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
end;

procedure TTestRdxCodeMap.DirectiveInLines_NotInLineComment;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  try
    SL.Text := Join(['a; // {$IFDEF X}', 'b; {$IFDEF Y}', 'c; (*$ENDIF*)',
      'd;']);
    Map := TRdxCodeMap.Create(SL);
    try
      Assert.IsFalse(DirectiveInLines(Map, 1, 1),
        '{$ im //-Kommentar ist keine Direktive (wie DirectiveAt)');
      Assert.IsTrue(DirectiveInLines(Map, 1, 2));
      Assert.IsTrue(DirectiveInLines(Map, 3, 3), '(*$ zaehlt');
      Assert.IsFalse(DirectiveInLines(Map, 4, 4));
      Assert.IsFalse(DirectiveInLines(Map, 4, 1), 'leerer Bereich');
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
end;

procedure TTestRdxCodeMap.TokHelpers_AndKeywordAt;
var
  SL      : TStringList;
  Map     : TRdxCodeMap;
  A, B, E : TRdxToken;
begin
  SL := TStringList.Create;
  try
    SL.Text := Join(['R := Doc.Range(Start := 0, End := 1);', 'X.End; &End;',
      'end;']);
    Map := TRdxCodeMap.Create(SL);
    try
      A := TokenAt(Map, 1, 1);
      B := TokenAt(Map, 1, 6);
      Assert.IsTrue(TokBefore(A, B), 'gleiche Zeile, Spalte davor');
      Assert.IsFalse(TokBefore(B, A));
      Assert.IsFalse(TokBefore(A, A), 'dieselbe Stelle ist nicht davor');
      Assert.IsTrue(TokBefore(B, TokenAt(Map, 2, 1)), 'Zeile davor');
      Assert.AreEqual('Doc', TokText(Map, B), 'Gross/klein wie im Quelltext');
      E := TokenAt(Map, 1, 28);
      Assert.AreEqual('end', E.Low);
      Assert.IsTrue(IsKeywordAfter(E, Before(Map, E)),
        'IsKeywordAfter sieht das := dahinter nicht');
      Assert.IsFalse(IsKeywordAt(Map, E, Before(Map, E)),
        'End := 1 ist ein benanntes Argument');
      E := TokenAt(Map, 2, 3);
      Assert.IsFalse(IsKeywordAt(Map, E, Before(Map, E)), 'X.End');
      E := TokenAt(Map, 2, 9);
      Assert.IsFalse(IsKeywordAt(Map, E, Before(Map, E)), '&End');
      E := TokenAt(Map, 3, 1);
      Assert.IsTrue(IsKeywordAt(Map, E, Before(Map, E)), 'end;');
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
end;

procedure TTestRdxCodeMap.SharedHelpers_QuotedTextAndParenDelta;
var
  T : TRdxToken;
begin
  // QuotedText: der Text zwischen den ERSTEN beiden Zeichen, wie
  // geschrieben - so lasen ihn QuotedNameOf, BoundNameOf, KeywordOf,
  // SectionNameOf (dort danach klein) und TRdxMagicFixes.NumberOf.
  Assert.AreEqual('IFoo', QuotedText('Interface "IFoo" has no GUID', '"'));
  Assert.AreEqual('Strict Private',
    QuotedText('Empty `Strict Private` section', '`'), 'Gross/klein bleibt');
  Assert.AreEqual('', QuotedText('ohne Zeichen', '"'), 'keines');
  Assert.AreEqual('', QuotedText('nur "eines', '"'), 'nur eines');
  Assert.AreEqual('', QuotedText('leer "" dann "x"', '"'),
    'die ersten beiden umschliessen nichts');
  // ParenDelta: beide Klammerarten, '<' nicht.
  T := Default(TRdxToken);
  T.Low := '(';
  Assert.AreEqual<Integer>(1, ParenDelta(T), '(');
  T.Low := '[';
  Assert.AreEqual<Integer>(1, ParenDelta(T), '[');
  T.Low := ')';
  Assert.AreEqual<Integer>(-1, ParenDelta(T), ')');
  T.Low := ']';
  Assert.AreEqual<Integer>(-1, ParenDelta(T), ']');
  T.Low := '<';
  Assert.AreEqual<Integer>(0, ParenDelta(T), '< zaehlt nicht');
  T.Low := '';
  Assert.AreEqual<Integer>(0, ParenDelta(T), 'kein Token');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxCodeMap);

end.
