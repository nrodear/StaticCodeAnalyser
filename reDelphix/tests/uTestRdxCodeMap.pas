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
// sieben ausgeschriebene Zaehlungen). Seit dem Review der Woche
// (2026-10-21) der einzige Unterschied von RangeText zu SpanText, TokenAt
// ausserhalb der Zeile, Direktiven nur aus Code heraus, Methoden
// generischer Klassen in DeclaresRoutine und die Helfer mit eigener Regel,
// die bis dahin nur Planer-Fixtures zufaellig beruehrten (SameIdent,
// HasIdentWord, MarkerReason, IncludeFileAt, IsRoutineHeadAfter,
// DirectiveBetween, TailIsComment/TailIsQuiet, CanAppendLine,
// LastCharBefore).
// Seit der Umstellung der Texte (Entscheid E29, Gruppe G5) sind die
// Rahmen von OneTokenReason und die Gruende von MarkerReason msgids -
// Reasons_FollowLanguage prueft en/fr, die anderen Tests laufen wie der
// Pruefstand in de.

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
    // Review Woche (G05-01, -13, -14, -17, -12/-22).
    [Test] procedure RangeText_ToleratesWhatSpanTextRefuses;
    [Test] procedure TokenAt_OutsideTheLine_NoToken;
    [Test] procedure Directives_NotInBlockComments_IncludeForms;
    [Test] procedure DeclaresRoutine_GenericClassMethod;
    [Test] procedure TextHelpers_IdentAndMarker;
    [Test] procedure RoutineHeadAfter_Predecessors;
    [Test] procedure LineHelpers_TailBetweenAndLastChar;
    // Umstellung E29 (Gruppe G5): die Gruende folgen der reDelphix-Sprache.
    [Test] procedure Reasons_FollowLanguage;
  end;

implementation

uses
  System.SysUtils, System.Classes,
  uDetectorUtils, uRdxCodeMap,
  uRefactorInfo,          // TRefactorSpan.Make
  uRefactorInfoBuilder,   // SpanText (die Gegenprobe zu RangeText)
  uRdxText,               // _, MsgMovedSuffix, Sprache der Gruende (E29)
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
  R   : string;
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
      // Der Rahmen ist seit der Umstellung E29 eine msgid, und 'traegt'
      // bekommt in de.po einen echten Umlaut - die Quelle bleibt ASCII: der
      // ganze Text gegen _() mit derselben msgid, der deutsche Wortlaut
      // ueber seine umlautfreien Teilstuecke.
      R := OneTokenOnLine(Map, 1, S, Hit);
      Assert.AreEqual(_('line %d carries %s - ambiguous', [1, '2-mal das Wort']),
        R);
      Assert.IsTrue(Pos('Zeile 1 tr', R) = 1, R);
      Assert.IsTrue(Pos(' 2-mal das Wort - mehrdeutig', R) > 0, R);
      // ManyArg kommt als %s ins Muster - Text aus der Meldung, auch mit
      // '%', steht nie im Muster selbst (Nachpruefung C1). Pos auf das
      // umlautfreie Ende: 'traegt' bekommt in de.po einen echten Umlaut.
      S.ManyFmt := '%d-mal %s';
      S.ManyArg := 'x 100%';
      Assert.IsTrue(Pos('2-mal x 100% - mehrdeutig',
        OneTokenOnLine(Map, 1, S, Hit)) > 0, 'ManyArg als %s im Muster');
      S.Arg := 'z';
      // Der Satz dieser Unit (umlautfrei) mit dem gemeinsamen Ende aus
      // uRdxText - 'pruefen' bekommt dort in de.po den echten Umlaut.
      Assert.AreEqual(MsgMovedSuffix('kein Treffer auf der gemeldeten Zeile'),
        OneTokenOnLine(Map, 1, S, Hit),
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

// ---- Review Woche (2026-10-21) ----

// Das erste Token AWord (klein) auf der Zeile ALine; Low = '' ohne.
function WordOn(AMap: TRdxCodeMap; ALine: Integer; const AWord: string): TRdxToken;
begin
  Result := NextToken(AMap, ALine, 1);
  while (Result.Low <> '') and (Result.Line = ALine) and (Result.Low <> AWord) do
    Result := After(AMap, Result);
  if (Result.Line <> ALine) or (Result.Low <> AWord) then
    Result := Default(TRdxToken);
end;

// G05-01: RangeText existiert nur, weil TRefactorInfoBuilder.SpanText ueber
// SpanFits einen Bereich ab einer LEEREN Zeile (der Rumpf hinter 'if A
// then' und einer Leerzeile, uRdxStructFixes.OwnLinesEdit) bzw. mit EndCol
// hinter dem Zeilenende als '' liefert. Dieser Unterschied war ungetestet:
// RangeText durch SpanText ersetzt, waere hier rot.
procedure TTestRdxCodeMap.RangeText_ToleratesWhatSpanTextRefuses;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  S   : TRefactorSpan;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Join(['  if A then', '', '    Foo;']);
    Map := TRdxCodeMap.Create(SL);
    S := TRefactorSpan.Make('t', 2, 1, 3, 9);
    Assert.AreEqual(#10'    Foo;', RangeText(Map, S),
      'die leere erste Zeile traegt ihren Teil leer bei');
    Assert.AreEqual('', TRefactorInfoBuilder.SpanText(SL, S),
      'Gegenprobe: SpanText verlangt StartCol <= Laenge der ersten Zeile');
    S := TRefactorSpan.Make('t', 1, 3, 3, 20);
    Assert.AreEqual('if A then'#10#10'    Foo;', RangeText(Map, S),
      'EndCol hinter dem Zeilenende: der Rest der Zeile');
    Assert.AreEqual('', TRefactorInfoBuilder.SpanText(SL, S),
      'Gegenprobe: SpanText verlangt EndCol - 1 <= Laenge der letzten Zeile');
    S := TRefactorSpan.Make('t', 1, 3, 3, 9);
    Assert.AreEqual('if A then'#10#10'    Foo;', RangeText(Map, S));
    Assert.AreEqual(TRefactorInfoBuilder.SpanText(SL, S), RangeText(Map, S),
      'passt der Bereich, liefern beide dasselbe');
  finally
    Map.Free;
    SL.Free;
  end;
end;

// G05-13: TokenAt/TokenEndingAt ausserhalb der Zeile - eine Spalte aus der
// Meldung hinter dem Zeilenende, eine leere Zeile (gegen b2538e20: AV).
procedure TTestRdxCodeMap.TokenAt_OutsideTheLine_NoToken;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  T   : TRdxToken;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Join(['ab;', '', 'c']);
    Map := TRdxCodeMap.Create(SL);
    Assert.AreEqual('ab', TokenAt(Map, 1, 1).Low);
    T := TokenAt(Map, 1, 4);
    Assert.AreEqual('', T.Low, 'hinter dem Zeilenende');
    Assert.AreEqual<Integer>(1, T.Line, 'Zeile wie gefragt');
    Assert.AreEqual<Integer>(4, T.Col, 'Spalte wie gefragt');
    Assert.AreEqual('', TokenAt(Map, 1, 0).Low, 'vor dem Zeilenanfang');
    Assert.AreEqual('', TokenAt(Map, 2, 1).Low, 'leere Zeile');
    Assert.AreEqual('', TokenAt(Map, 9, 1).Low, 'hinter dem Dateiende');
    Assert.AreEqual('', TokenEndingAt(Map, 2, 1).Low, 'leere Zeile');
    Assert.AreEqual('', TokenEndingAt(Map, 1, 9).Low, 'hinter dem Zeilenende');
    Assert.AreEqual('ab', TokenEndingAt(Map, 1, 2).Low);
    Assert.AreEqual(';', TokenEndingAt(Map, 1, 3).Low);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// G05-14: eine Direktive beginnt nur aus Code heraus - '{$' in '(* .. *)'
// und '(*$' in '{ .. }' sind Kommentartext (gegen b2538e20 rot: beide
// zaehlten, IncludeInLines fand das auskommentierte defs.inc). Dazu die
// Formen von IncludeFileAt (G05-22).
procedure TTestRdxCodeMap.Directives_NotInBlockComments_IncludeForms;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Join([
      '(* {$IFDEF VER150} *) a;',        // 1
      '{ alt: (*$I defs.inc*) } b;',     // 2
      '{$IFDEF X} c; {$ENDIF}',          // 3
      '(*$I y.inc*) d;',                 // 4
      '{$I ''a b.inc''}',                // 5
      '{$INCLUDE x.inc extra}',          // 6
      '{$I+} e;',                        // 7
      '// {$I z.inc}']);                 // 8
    Map := TRdxCodeMap.Create(SL);
    Assert.IsFalse(DirectiveInLines(Map, 1, 1), '{$ in (* *) ist Text');
    Assert.IsFalse(DirectiveInLines(Map, 2, 2), '(*$ in { } ist Text');
    Assert.AreEqual<Integer>(4, IncludeInLines(Map, 1, 8),
      'das erste Include aus Code heraus');
    Assert.IsTrue(DirectiveAt(Map, 3, 1));
    Assert.IsFalse(DirectiveAt(Map, 3, 2), 'nur am Oeffner');
    Assert.IsTrue(DirectiveAt(Map, 3, 15), 'die zweite auf der Zeile');
    Assert.IsFalse(DirectiveAt(Map, 8, 4), '{$ im //-Kommentar');
    Assert.AreEqual('y.inc', IncludeFileAt(Map, 4, 1), '(*$I x*)');
    Assert.AreEqual('a b.inc', IncludeFileAt(Map, 5, 1),
      'in Quotes, mit Leerzeichen');
    Assert.AreEqual('x.inc', IncludeFileAt(Map, 6, 1),
      '{$INCLUDE}, Text dahinter');
    Assert.AreEqual('', IncludeFileAt(Map, 7, 1), '{$I+} ist ein Schalter');
  finally
    Map.Free;
    SL.Free;
  end;
end;

// G05-17: NameAfter/DeclaresAfter ueber Typparameter - 'procedure
// TValidator<T>.Format' deklariert Format, nicht TValidator (gegen
// b2538e20 rot: Format und Run fehlten, TValidator galt als Routine).
procedure TTestRdxCodeMap.DeclaresRoutine_GenericClassMethod;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Join([
      'unit u;',                                           // 1
      'interface',                                         // 2
      'type',                                              // 3
      '  TValidator<T> = class',                           // 4
      '    procedure Check(const S: string);',             // 5
      '  end;',                                            // 6
      'implementation',                                    // 7
      'procedure TValidator<T>.Format(const S: string);',  // 8
      'begin',                                             // 9
      'end;',                                              // 10
      'function Make<T>(X: T): T;',                        // 11
      'begin',                                             // 12
      'end;',                                              // 13
      'procedure TOuter<T>.TInner<U>.Run;',                // 14
      'begin',                                             // 15
      'end;',                                              // 16
      'end.']);
    Map := TRdxCodeMap.Create(SL);
    Assert.AreEqual('format', NameAfter(Map, NextToken(Map, 8, 1)).Low);
    Assert.AreEqual('make', NameAfter(Map, NextToken(Map, 11, 1)).Low,
      'Typparameter der Routine selbst');
    Assert.AreEqual('run', NameAfter(Map, NextToken(Map, 14, 1)).Low,
      'zwei generische Glieder');
    Assert.IsTrue(DeclaresRoutine(Map, 'Format'), 'Methode einer generischen Klasse');
    Assert.IsTrue(DeclaresRoutine(Map, 'Run'), 'zwei generische Glieder');
    Assert.IsTrue(DeclaresRoutine(Map, 'Make'));
    Assert.IsTrue(DeclaresRoutine(Map, 'Check'));
    Assert.IsFalse(DeclaresRoutine(Map, 'TValidator'), 'nur Qualifizierer');
    Assert.IsFalse(DeclaresRoutine(Map, 'TInner'), 'nur Qualifizierer');
  finally
    Map.Free;
    SL.Free;
  end;
end;

// G05-22: SameIdent/HasIdentWord (Zeichen ueber #127 gelten als gleich,
// wenn beide darueber liegen) und MarkerReason ('XXX' nur gross, die
// Absichtsmarker in jeder Schreibweise und nur als Wort).
procedure TTestRdxCodeMap.TextHelpers_IdentAndMarker;
const
  UE    = #$00FC;
  UE_UP = #$00DC;
begin
  Assert.IsTrue(SameIdent('pr' + UE + 'fe', 'pr' + UE_UP + 'fe'),
    'ueber #127: gleich');
  Assert.IsFalse(SameIdent('pr' + UE + 'fe', 'prufe'), 'Umlaut gegen ASCII');
  Assert.IsFalse(SameIdent('pruefe', 'pr' + UE + 'fe'), 'andere Laenge');
  Assert.IsFalse(SameIdent('abc', 'abd'));
  Assert.IsTrue(HasIdentWord('x := pr' + UE_UP + 'fe(1);', 'pr' + UE + 'fe'),
    'als Wort, der Umlaut ohne Gross/klein');
  Assert.IsFalse(HasIdentWord('x := pr' + UE + 'fen;', 'pr' + UE + 'fe'),
    'Teil eines laengeren Worts');
  Assert.IsFalse(HasIdentWord('abc', ''), 'leerer Name');
  Assert.AreEqual('', MarkerReason('// nur ein Kommentar'));
  Assert.IsTrue(Pos('noinspection-Marker', MarkerReason('// noinspection X')) = 1);
  Assert.IsTrue(Pos('TODO im Bereich', MarkerReason('// todo: spaeter')) = 1,
    'jede Schreibweise');
  Assert.IsTrue(Pos('HACK im Bereich', MarkerReason('{ Hack: weg }')) = 1);
  Assert.AreEqual('', MarkerReason('// hackathon'), 'nur als Wort');
  Assert.IsTrue(Pos('XXX im Bereich', MarkerReason('// XXX pruefen')) = 1,
    'XXX gross');
  Assert.AreEqual('', MarkerReason('// xxx als Platzhalter'), 'xxx klein');
end;

// G05-22: die Negativliste NOT_HEAD_AFTER von IsRoutineHeadAfter mit allen
// acht Vorgaengern, die Bezeichner-Praefixe und die Positivfaelle; dazu
// dieselben Formen im Quelltext ueber IsRoutineHead.
procedure TTestRdxCodeMap.RoutineHeadAfter_Predecessors;
const
  NO_HEAD: array[0..10] of string = (':', '=', 'to', '(', ',', ':=', 'of',
    '[', '.', '&', '@');
  HEAD: array[0..4] of string = (';', 'class', ']', 'implementation', '');
var
  T, P : TRdxToken;
  S    : string;
  SL   : TStringList;
  Map  : TRdxCodeMap;
begin
  T := Default(TRdxToken);
  T.Low := 'procedure';
  P := Default(TRdxToken);
  for S in NO_HEAD do
  begin
    P.Low := S;
    Assert.IsFalse(IsRoutineHeadAfter(T, P), 'kein Kopf hinter ' + S);
  end;
  for S in HEAD do
  begin
    P.Low := S;
    Assert.IsTrue(IsRoutineHeadAfter(T, P), 'Kopf hinter "' + S + '"');
  end;
  T.Low := 'begin';
  P.Low := ';';
  Assert.IsFalse(IsRoutineHeadAfter(T, P), 'kein Routinenwort');
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Join([
      'type TRef = reference to procedure;',   // 1
      '  TArr = array of procedure;',          // 2
      'var P: procedure;',                     // 3
      'X := procedure begin end;',             // 4
      'Run(procedure begin end);',             // 5
      '[Weak] procedure Go;',                  // 6
      'class procedure Go2;']);                // 7
    Map := TRdxCodeMap.Create(SL);
    Assert.IsFalse(IsRoutineHead(Map, WordOn(Map, 1, 'procedure')), 'reference to');
    Assert.IsFalse(IsRoutineHead(Map, WordOn(Map, 2, 'procedure')), 'array of');
    Assert.IsFalse(IsRoutineHead(Map, WordOn(Map, 3, 'procedure')), 'Typ einer Variablen');
    Assert.IsFalse(IsRoutineHead(Map, WordOn(Map, 4, 'procedure')), 'anonym hinter :=');
    Assert.IsFalse(IsRoutineHead(Map, WordOn(Map, 5, 'procedure')), 'anonym in Klammern');
    Assert.IsTrue(IsRoutineHead(Map, WordOn(Map, 6, 'procedure')), 'hinter einem Attribut');
    Assert.IsTrue(IsRoutineHead(Map, WordOn(Map, 7, 'procedure')), 'class procedure');
  finally
    Map.Free;
    SL.Free;
  end;
end;

// G05-12/G05-22: TailIsComment zaehlt eine Direktive wie einen Kommentar,
// TailIsQuiet wie Code; CanAppendLine mit einer Folgezeile im Kommentar;
// DirectiveBetween ab dem Ende eines Tokens bzw. ab Dateianfang;
// LastCharBefore/FirstCharAfter ueber Zeilen, Direktiven und Kommentare
// hinweg, ein String zaehlt.
procedure TTestRdxCodeMap.LineHelpers_TailBetweenAndLastChar;
var
  SL     : TStringList;
  Map    : TRdxCodeMap;
  Li, Co : Integer;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := Join([
      'if A then {$IFDEF X}',         // 1: then 6..9, Direktive ab 11
      '  B;',                         // 2: B 3
      '{$ENDIF} C := ''x''; // k',    // 3: C 10, Quote 15/17, ; 18
      'D; { offen',                   // 4
      '  zu } E;',                    // 5: E 8
      'F; (* k *)',                   // 6
      '',                             // 7
      'G;']);                         // 8
    Map := TRdxCodeMap.Create(SL);
    Assert.IsTrue(TailIsComment(Map, 1, 9), 'die Direktive zaehlt wie Kommentar');
    Assert.IsFalse(TailIsQuiet(Map, 1, 9), 'TailIsQuiet: die Direktive ist Code');
    Assert.IsTrue(TailIsQuiet(Map, 6, 2), 'nur ein Kommentar dahinter');
    Assert.IsTrue(TailIsQuiet(Map, 3, 18), 'Leerraum und //-Kommentar');
    Assert.IsFalse(TailIsQuiet(Map, 3, 9), 'Code dahinter');
    Assert.IsTrue(CanAppendLine(Map, 6, 2));
    Assert.IsFalse(CanAppendLine(Map, 4, 2), 'die Folgezeile beginnt im Kommentar');
    Assert.IsTrue(DirectiveBetween(Map, TokenAt(Map, 1, 6), 2, 3), 'hinter then');
    Assert.IsFalse(DirectiveBetween(Map, Default(TRdxToken), 1, 11),
      'ab Dateianfang bis vor die Direktive');
    Assert.IsTrue(DirectiveBetween(Map, Default(TRdxToken), 1, 12));
    Assert.IsTrue(DirectiveBetween(Map, TokenAt(Map, 2, 3), 3, 10),
      'am Anfang der naechsten Zeile');
    Assert.IsFalse(DirectiveBetween(Map, TokenAt(Map, 3, 10), 4, 1),
      'der //-Kommentar ist keine');
    Assert.IsTrue(LastCharBefore(Map, TokenAt(Map, 2, 3), Li, Co));
    Assert.AreEqual('1:9', Format('%d:%d', [Li, Co]),
      'ueber die Direktive auf das n von then');
    Assert.IsTrue(LastCharBefore(Map, TokenAt(Map, 5, 8), Li, Co));
    Assert.AreEqual('4:2', Format('%d:%d', [Li, Co]), 'ueber den Kommentar');
    Assert.IsTrue(LastCharBefore(Map, TokenAt(Map, 3, 18), Li, Co));
    Assert.AreEqual('3:17', Format('%d:%d', [Li, Co]), 'ein String zaehlt');
    Assert.IsTrue(FirstCharAfter(Map, TokenAt(Map, 1, 6), Li, Co));
    Assert.AreEqual('2:3', Format('%d:%d', [Li, Co]));
    Assert.IsTrue(FirstCharAfter(Map, TokenAt(Map, 6, 2), Li, Co));
    Assert.AreEqual('8:1', Format('%d:%d', [Li, Co]), 'ueber die leere Zeile');
  finally
    Map.Free;
    SL.Free;
  end;
end;

procedure TTestRdxCodeMap.Reasons_FollowLanguage;
const
  // So uebergibt ein Aufrufer What und ManyFmt: schon uebersetzt.
  WHAT_NONE = 'no begin';
  MANY_FMT  = '%d begin';
var
  Old : string;
begin
  // Die Saetze von OneTokenReason und MarkerReason sind msgids (Entscheid
  // E29, Gruppe G5); AWhat und AManyFmt kommen schon uebersetzt vom
  // Aufrufer und gehen unveraendert hinein (ein zweites _() faende keine
  // msgid), AArg ebenso. fr nur ueber Teilstuecke ohne Akzent - die Quelle
  // bleibt ASCII.
  Old := RdxLanguageOverride;
  try
    SetRdxLanguageOverride('en');
    Assert.AreEqual('no begin on the reported line - line moved? Analyse the '
      + 'file again', OneTokenReason(3, 0, WHAT_NONE, MANY_FMT));
    Assert.AreEqual('line 3 carries 2 begin - ambiguous',
      OneTokenReason(3, 2, WHAT_NONE, MANY_FMT));
    Assert.AreEqual('line 3 carries 2 headers of x - ambiguous',
      OneTokenReason(3, 2, '', '%d headers %s', 'of x'), 'AArg als %s');
    Assert.AreEqual('noinspection marker in the range - it suppresses other '
      + 'findings', MarkerReason('// noinspection UnusedRoutine'));
    Assert.AreEqual('TODO in the range - an intent comment stays',
      MarkerReason('// todo: later'));
    Assert.AreEqual('XXX in the range - an intent comment stays',
      MarkerReason('// XXX'));
    SetRdxLanguageOverride('fr');
    Assert.AreEqual('la ligne 3 porte 2 begin - ambigu',
      OneTokenReason(3, 2, WHAT_NONE, MANY_FMT));
    Assert.IsTrue(Pos('x sur la ligne signal',
      OneTokenReason(3, 0, 'x', '')) = 1, 'fr: Satz dieser Unit');
  finally
    SetRdxLanguageOverride(Old);
  end;
  // Die Sprache des Laufs (de): der bisherige Wortlaut.
  Assert.AreEqual('TODO im Bereich - ein Absichtskommentar bleibt stehen',
    MarkerReason('// todo: later'));
  Assert.IsTrue(Pos('noinspection-Marker im Bereich - er unterdr',
    MarkerReason('// noinspection X')) = 1, 'de');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxCodeMap);

end.
