unit uTestRdxConcatWrap;

// Code-Aktion ohne Fund "Verkettungen im Formatter-Bereich nach jedem '+'
// umbrechen" (ckWrapConcat; uRdxConcatWrap, Bereich ueber
// uRdxFormatterMarkerFix.MarkerRegionAt) ueber den Laeufer am Caret
// (uRdxContextRunner.Run), auf Text, ohne Parser - reDelphix.Test UND
// FPC-Pruefstand. Der Caret steht als CARET_MARK '{^}' im Text
// (uTestRdxTextKit.CaretOf). Jede Erwartung ist von Hand geschrieben und
// byte-genau verglichen (AssertText: auch Gross/Klein); die Beispiele
// SQL-Zuweisung, SQL.Add und Tab-Einzug sind die des Konzepts.
// Drei Fixtures auf Text: Angebot (Ergebnistext, Hinweis, Idempotenz,
// CRLF), Sperre (ausgegraut, Grund exakt mit _()), kein Eintrag (kein
// Bereich am Caret - jeweils mit der Gegenprobe, dass dieselbe Anweisung in
// einem intakten Bereich angeboten wird - bzw. kein Kandidat in einem
// gefundenen Bereich). Nur Delphi (letzte Fixture): die Bereichsbilanz
// gegen den echten Detektor SCA206 und der Menuetext ueber
// uRdxFixTable.ContextCaption.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxConcatWrap = class
  public
    [Test] procedure Wrap_SqlAssign;
    [Test] procedure Wrap_SqlAdd_QuotedStr_IntToStr;
    [Test] procedure Wrap_ConstDecl;
    [Test] procedure Wrap_InlineVar;
    [Test] procedure Wrap_SelfAppend;
    [Test] procedure Wrap_ExecSqlWithParams;
    [Test] procedure Wrap_NestedPlusStays;
    [Test] procedure Wrap_CharConstants;
    [Test] procedure Wrap_StringWithPlusAndQuotes;
    [Test] procedure Wrap_TrailingBlanksInLiteralStay;
    [Test] procedure Wrap_NoBlankAroundPlus;
    [Test] procedure Wrap_TabIndent;
    [Test] procedure Wrap_IndentIndependentOfTarget;
    [Test] procedure Wrap_PartlyWrapped;
    [Test] procedure Wrap_TrailingComment;
    [Test] procedure Wrap_CrLf;
    [Test] procedure Wrap_WholeRegion_TwoStatements;
    [Test] procedure Wrap_CaretOnMarkerLine;
    [Test] procedure Wrap_Idempotent;
    [Test] procedure Wrap_SkippedCountInHint;
    [Test] procedure Wrap_CaptionGerman;
    [Test] procedure Wrap_BranchWithoutSemicolon;
    [Test] procedure Wrap_RegionStartsInsideCall;
  end;

  [TestFixture]
  TTestRdxConcatWrapRefused = class
  public
    [Test] procedure Wrap_CommentInChain_Refused;
    [Test] procedure Wrap_DirectiveInChain_Refused;
    [Test] procedure Wrap_TwoStatementsOnLine_Refused;
    [Test] procedure Wrap_LeadingPlusStyle_Refused;
    [Test] procedure Wrap_MultiLineString_Refused;
    [Test] procedure Wrap_SuppressionComment_Refused;
    [Test] procedure Wrap_ReasonOfNearestRefused;
  end;

  [TestFixture]
  TTestRdxConcatWrapNoEntry = class
  public
    [Test] procedure Wrap_OutsideRegion_NoEntry;
    [Test] procedure Wrap_UnclosedStart_NoEntry;
    [Test] procedure Wrap_MalformedMarker_NoEntry;
    [Test] procedure Wrap_OrphanEnd_NoEntry;
    [Test] procedure Wrap_NestedStart_RegionEndsAtFirstEnd;
    [Test] procedure Wrap_MarkerInStringOrComment_NoEntry;
    [Test] procedure Wrap_NumbersOnly_NoEntry;
    [Test] procedure Wrap_UnaryPlus_NoEntry;
    [Test] procedure Wrap_TwoChainsInOneCall_NoEntry;
    [Test] procedure Wrap_StatementCrossesMarker_NoEntry;
    [Test] procedure Wrap_RegionOnlyComments_NoEntry;
    [Test] procedure Wrap_MarkerBehindBlockComment_NoEntry;
    [Test] procedure Wrap_ControlStatement_NoEntry;
  end;

{$IFNDEF FPC}
  // Bilanz gegen den ECHTEN Detektor und der Menuetext ueber die Tabelle
  // (nur Delphi).
  [TestFixture]
  TTestRdxConcatWrapDetector = class
  public
    [Test] procedure Region_MatchesDetector;
    [Test] procedure Caption_ViaContextCaption;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode,              // TAstNode
  uMethodd12,            // TLeakFinding
  uSCAConsts,            // TFindingKind, fkFormatterMarker
  uFormatterMarker,      // TFormatterMarkerDetector
  uRdxFixTable,          // ContextCaption
  uTestRdxDetectorKit,   // TSeen, DetectSource
  {$ENDIF}
  uFindingActions,       // TEditorContext
  uRdxBufferMath,        // TRdxEdit
  uRdxCodeMap,           // TRdxCodeMap
  uRdxContextRunner,     // Run, CaptionOf, ckWrapConcat
  uRdxConcatWrap,        // R_CW_*
  uRdxFormatterMarkerFix, // MarkerRegionAt
  uRdxText,              // _
  uTestRdxTextKit;       // Join, JoinWith, Apply, CaretOf, LineOf, NewMap

// ---- Helfer ----

// Byte-genauer Vergleich (auch Gross/Klein) mit beiden Texten in der
// Meldung.
procedure AssertText(const AExpected, AActual: string; const AWhat: string = '');
begin
  Assert.IsTrue(AExpected = AActual, AWhat + ' erwartet <' + AExpected
    + '>, erhalten <' + AActual + '>');
end;

// Die Eintraege am Caret ALine/ACol.
function RunPos(const ASource: string;
  ALine, ACol: Integer): TArray<TRdxContextOutcome>;
var
  SL : TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Result := TRdxContextRunner.Run(SL,
      TEditorContext.At('C:\rdx_ctx_wrap_none\u.pas', ALine, ACol));
  finally
    SL.Free;
  end;
end;

// Dasselbe am Caret von AMarked (CARET_MARK); ASource ohne Marke.
function RunAt(const AMarked: string;
  out ASource: string): TArray<TRdxContextOutcome>;
var
  Line, Col : Integer;
begin
  ASource := AMarked;
  Assert.IsTrue(CaretOf(ASource, Line, Col), 'Caret-Marke fehlt');
  Result := RunPos(ASource, Line, Col);
end;

// Wie viele Eintraege ckWrapConcat in AList; der letzte in AOut.
function CountWrap(const AList: TArray<TRdxContextOutcome>;
  out AOut: TRdxContextOutcome): Integer;
var
  O : TRdxContextOutcome;
begin
  Result := 0;
  AOut := Default(TRdxContextOutcome);
  for O in AList do
    if O.Kind = ckWrapConcat then
    begin
      Inc(Result);
      AOut := O;
    end;
end;

// Genau EIN Eintrag ckWrapConcat am Caret von AMarked.
function WrapAt(const AMarked: string; out ASource: string): TRdxContextOutcome;
begin
  Assert.AreEqual<Integer>(1, CountWrap(RunAt(AMarked, ASource), Result),
    'ein Eintrag: ' + ASource);
end;

// Der Text nach dem freigegebenen Eintrag am Caret von AMarked.
function Wrapped(const AMarked: string): string;
var
  O   : TRdxContextOutcome;
  Src : string;
begin
  O := WrapAt(AMarked, Src);
  Assert.IsTrue(O.Enabled, 'freigegeben: ' + O.Reason);
  Assert.AreEqual('', O.Reason);
  Assert.IsTrue(O.Hint <> '', 'Hinweis');
  Assert.IsFalse(O.ChangesBehavior, 'bedeutungsgleich');
  Assert.AreEqual('', O.Name, 'kein Name');
  Result := Apply(Src, O.Edits);
end;

// Kein Eintrag ckWrapConcat am Caret von AMarked.
procedure AssertNone(const AMarked, AWhat: string);
var
  Src : string;
  O   : TRdxContextOutcome;
begin
  Assert.AreEqual<Integer>(0, CountWrap(RunAt(AMarked, Src), O), AWhat);
end;

// Genau ein gesperrter Eintrag mit dem Grund AReason.
procedure AssertRefused(const AMarked, AReason: string);
var
  Src : string;
  O   : TRdxContextOutcome;
begin
  O := WrapAt(AMarked, Src);
  Assert.IsFalse(O.Enabled, 'gesperrt: ' + Src);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
  Assert.AreEqual('', O.Hint, 'kein Hinweis');
  AssertText(AReason, O.Reason);
end;

// Eine Unit mit der Prozedur P, deren Rumpf ein Formatter-Bereich mit den
// Zeilen ABody ist (Zeile 6 '{(*}', ABody ab Zeile 7).
function Region(const ABody: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation', 'procedure P;',
    'begin', '  {(*}']) + #13#10 + Join(ABody) + #13#10
    + Join(['  {*)}', 'end;', 'end.']);
end;

// Findet MarkerRegionAt fuer Zeile ALine von ASource einen Bereich? (Der
// Pfad "Kandidat im Bereich" ist erreicht.)
function RegionFound(const ASource: string; ALine: Integer): Boolean;
var
  Map            : TRdxCodeMap;
  SL, SC, EL, EC : Integer;
begin
  Map := NewMap(ASource);
  try
    Result := TRdxFormatterMarkerFix.MarkerRegionAt(Map, ALine, SL, SC, EL,
      EC);
  finally
    Map.Free;
  end;
end;

// Kein Eintrag fuer die Anweisung AStmt in AMarked (Caret davor), aber in
// einem intakten Bereich wird dieselbe Anweisung angeboten: der Bereich,
// nicht die Anweisung, schliesst sie aus.
procedure AssertNoRegion(const AMarked, AStmt, AWhat: string);
var
  Src : string;
  O   : TRdxContextOutcome;
begin
  AssertNone(AMarked, AWhat);
  O := WrapAt(Region(['  {^}' + AStmt]), Src);
  Assert.IsTrue(O.Enabled, 'Gegenprobe im Bereich: ' + AWhat);
end;

const
  // Die Kontroll-Anweisung der Tests ohne Kandidat (AssertNoCandidate), mit
  // Caret, und ihr Ergebnis.
  CTL_AT      = '  {^}Ctl := ''k'' + ''l'';';
  CTL         = '  Ctl := ''k'' + ''l'';';
  CTL_WRAPPED = '  Ctl := ''k'' +'#13#10'    ''l'';';

// Kein Eintrag fuer AMarked (Caret im Rumpf eines Bereichs), obwohl der
// Bereich am Caret gefunden wird. Gegenprobe: AControlled ist derselbe Text
// mit der Kontroll-Anweisung CTL_AT im selben Bereich - angeboten wird genau
// sie (der Hinweis zaehlt eine Anweisung, keine gesperrte), alles andere
// bleibt byte-gleich.
procedure AssertNoCandidate(const AMarked, AControlled, AWhat: string);
var
  Src       : string;
  Line, Col : Integer;
  O         : TRdxContextOutcome;
begin
  Src := AMarked;
  Assert.IsTrue(CaretOf(Src, Line, Col), 'Caret-Marke fehlt');
  Assert.IsTrue(RegionFound(Src, Line), 'Bereich gefunden: ' + AWhat);
  AssertNone(AMarked, AWhat);
  O := WrapAt(AControlled, Src);
  Assert.IsTrue(O.Enabled, 'Kontrolle: ' + O.Reason);
  Assert.IsTrue(Pos('Anweisungen: 1, ausgelassen: 0', O.Hint) > 0,
    'Kontrolle: ' + AWhat + ': ' + O.Hint);
  AssertText(StringReplace(Src, CTL, CTL_WRAPPED, []), Apply(Src, O.Edits),
    'Kontrolle: ' + AWhat);
end;

// AssertNoCandidate fuer den Rumpf ABody (Zeilen mit CRLF, die erste mit
// zwei Zeichen Einzug) eines Bereichs (Region): Caret hinter dem Einzug der
// ersten Zeile; die Kontrolle steht hinter ABody.
procedure AssertBodyNoCandidate(const ABody, AWhat: string);
begin
  AssertNoCandidate(Region(['  {^}' + Copy(ABody, 3, MaxInt)]),
    Region([ABody, CTL_AT]), AWhat);
end;

{ ---- Angebot ---- }

// Beispiel 11.1 des Konzepts: SQL-Text als Zuweisung.
procedure TTestRdxConcatWrap.Wrap_SqlAssign;
begin
  AssertText(Join(['procedure TKundenDM.LadeAktiveKunden;', 'begin',
    '  {(*}',
    '  qryKunden.SQL.Text := ''SELECT k.Id, k.Name, k.Ort '' +',
    '    ''FROM Kunden k '' +',
    '    ''WHERE k.Aktiv = 1 '' +',
    '    ''ORDER BY k.Name'';',
    '  {*)}', '  qryKunden.Open;', 'end;']),
    Wrapped(Join(['procedure TKundenDM.LadeAktiveKunden;', 'begin',
    '  {(*}',
    '  qryKunden.SQL.Text := ''SELECT k.Id, k.Name, k.Ort '' + ''FROM '
      + 'Kunden k '' + ''WHERE k.Aktiv = 1 '' + ''ORDER BY k.Name'';{^}',
    '  {*)}', '  qryKunden.Open;', 'end;'])));
end;

// Beispiel 11.2: Kette in SQL.Add( - Einzug + 2, nicht unter der Klammer;
// das '+' in IntToStr(..) und das Komma in FormatDateTime(..) bleiben, ');'
// steht hinter dem letzten Operanden.
procedure TTestRdxConcatWrap.Wrap_SqlAdd_QuotedStr_IntToStr;
begin
  AssertText(Region(['  Query.SQL.Add(''UPDATE Kunden SET Ort = '' +',
    '    QuotedStr(AOrt) +',
    '    '', Stand = '' +',
    '    QuotedStr(FormatDateTime(''yyyy-mm-dd'', Date)) +',
    '    '' WHERE Id = '' +',
    '    IntToStr(AId + FOffset) +',
    '    '';'');']),
    Wrapped(Region(['  {^}Query.SQL.Add(''UPDATE Kunden SET Ort = '' + '
      + 'QuotedStr(AOrt) + '', Stand = '' + QuotedStr(FormatDateTime('
      + '''yyyy-mm-dd'', Date)) + '' WHERE Id = '' + IntToStr(AId + FOffset) '
      + '+ '';'');'])));
end;

// E8: Konstanten (auch typisiert) im const-Abschnitt einer Unit.
procedure TTestRdxConcatWrap.Wrap_ConstDecl;
begin
  AssertText(Join(['unit u;', 'interface', 'const', '  {(*}',
    '  SQL_X = ''SELECT '' +', '    ''FROM t'';',
    '  SQL_Y: string = ''a'' +', '    ''b'';',
    '  {*)}', 'implementation', 'end.']),
    Wrapped(Join(['unit u;', 'interface', 'const', '  {(*}',
    '  {^}SQL_X = ''SELECT '' + ''FROM t'';',
    '  SQL_Y: string = ''a'' + ''b'';',
    '  {*)}', 'implementation', 'end.'])));
  // Der Abschnittskopf im Bereich gehoert zu keiner Anweisung: der Einzug
  // ist der der Konstante.
  AssertText(Join(['unit u;', 'interface', '{(*}', 'const',
    '  SQL_Z = ''a'' +', '    ''b'';', '{*)}', 'implementation', 'end.']),
    Wrapped(Join(['unit u;', 'interface', '{(*}', 'const',
    '  {^}SQL_Z = ''a'' + ''b'';', '{*)}', 'implementation', 'end.'])));
end;

// Inline-Variable: 'var' beginnt die Anweisung, ihr Einzug zaehlt.
procedure TTestRdxConcatWrap.Wrap_InlineVar;
begin
  AssertText(Region(['  var S: string := ''a'' +', '    ''b'' +',
    '    ''c'';']),
    Wrapped(Region(['  {^}var S: string := ''a'' + ''b'' + ''c'';'])));
end;

// Selbst-Anhaengen: 'S +' bleibt auf der ersten Zeile.
procedure TTestRdxConcatWrap.Wrap_SelfAppend;
begin
  AssertText(Region(['  S := S +', '    ''AND a '' +', '    ''AND b'';']),
    Wrapped(Region(['  {^}S := S + ''AND a '' + ''AND b'';'])));
end;

// Die Kette im ersten Argument; ', [Id]);' bleibt am Ende.
procedure TTestRdxConcatWrap.Wrap_ExecSqlWithParams;
begin
  AssertText(Region(['  FDConn.ExecSQL(''a '' +', '    ''b'', [Id]);']),
    Wrapped(Region(['  {^}FDConn.ExecSQL(''a '' + ''b'', [Id]);'])));
end;

// '+' tiefer als die Kettenebene gehoert zum Operanden; eine Kette in
// einem Aufruf hinter ':=' liegt auf dessen Klammerebene.
procedure TTestRdxConcatWrap.Wrap_NestedPlusStays;
begin
  AssertText(Region(['  S := IntToStr(A + B) +', '    ''x'' +',
    '    Copy(S, P + 1, 2) +', '    (B + C);']),
    Wrapped(Region(['  {^}S := IntToStr(A + B) + ''x'' + Copy(S, P + 1, 2) '
      + '+ (B + C);'])));
  AssertText(Region(['  S := Trim(''a'' +', '    ''b'');']),
    Wrapped(Region(['  {^}S := Trim(''a'' + ''b'');'])));
end;

// Zeichenkonstanten: '#13#10' und 'a'#13'b' sind je EIN Operand.
procedure TTestRdxConcatWrap.Wrap_CharConstants;
begin
  AssertText(Region(['  S := ''a'' +', '    #13#10 +', '    ''b'';',
    '  T := ''a''#13''b'' +', '    C;']),
    Wrapped(Region(['  {^}S := ''a'' + #13#10 + ''b'';',
    '  T := ''a''#13''b'' + C;'])));
  // Nur ein Zeichenliteral als Literal der Kette.
  AssertText(Region(['  S := X +', '    #9;']),
    Wrapped(Region(['  {^}S := X + #9;'])));
end;

// '+' und Apostrophe IN Strings werden nie angefasst.
procedure TTestRdxConcatWrap.Wrap_StringWithPlusAndQuotes;
begin
  AssertText(Region(['  S := ''x+y'' +', '    ''it''''s '' +',
    '    ''ok'';']),
    Wrapped(Region(['  {^}S := ''x+y'' + ''it''''s '' + ''ok'';'])));
end;

// Das Blank am Ende des Literals gehoert zum Wert.
procedure TTestRdxConcatWrap.Wrap_TrailingBlanksInLiteralStay;
begin
  AssertText(Region(['  S := ''FROM t '' +', '    ''WHERE'';']),
    Wrapped(Region(['  {^}S := ''FROM t '' + ''WHERE'';'])));
end;

// Links vom '+' bleibt der Text, wie er ist (kein Normalisieren).
procedure TTestRdxConcatWrap.Wrap_NoBlankAroundPlus;
begin
  AssertText(Region(['  S := ''a''+', '    ''b'';']),
    Wrapped(Region(['  {^}S := ''a''+''b'';'])));
end;

// Beispiel 11.3: der Einzug aus Tabs bleibt woertlich, dahinter genau zwei
// Leerzeichen.
procedure TTestRdxConcatWrap.Wrap_TabIndent;
begin
  AssertText(Region([#9#9'qryKunden.SQL.Text := ''SELECT '' +',
    #9#9'  ''FROM t'';']),
    Wrapped(Region([#9#9'{^}qryKunden.SQL.Text := ''SELECT '' + ''FROM t'';'])));
end;

// Ein langes Ziel und ein Tab vor ':=' verschieben die Einrueckung nicht.
procedure TTestRdxConcatWrap.Wrap_IndentIndependentOfTarget;
begin
  AssertText(Region(['  FDQueryKundenUndAuftraege.SQL.Text'#9':= ''a'' +',
    '    ''b'';']),
    Wrapped(Region(['  {^}FDQueryKundenUndAuftraege.SQL.Text'#9':= ''a'' + '
      + '''b'';'])));
end;

// Schon umbrochene Zeilen bleiben byte-gleich; eine Fortsetzungszeile mit
// zwei Operanden bricht mit IHREM Einzug.
procedure TTestRdxConcatWrap.Wrap_PartlyWrapped;
begin
  AssertText(Region(['  S := ''a'' +', '      ''b'' +', '      ''c'' +',
    '    ''d'';']),
    Wrapped(Region(['  {^}S := ''a'' +', '      ''b'' + ''c'' +',
    '    ''d'';'])));
end;

// Ein '//'-Kommentar wandert ans Ende der letzten neuen Zeile.
procedure TTestRdxConcatWrap.Wrap_TrailingComment;
begin
  AssertText(Region(['  S := ''a'' +', '    ''b''; // Kunden']),
    Wrapped(Region(['  {^}S := ''a'' + ''b''; // Kunden'])));
  // Ein '//'-Kommentar auf einer Zeile mitten in der Kette sperrt nicht.
  AssertText(Region(['  S := ''a'' + // erster Teil', '    ''b'' +',
    '    ''c'';']),
    Wrapped(Region(['  {^}S := ''a'' + // erster Teil', '    ''b'' + ''c'';'])));
end;

// NewText traegt #10, geschrieben wird das Zeilenende des Puffers.
procedure TTestRdxConcatWrap.Wrap_CrLf;
var
  O   : TRdxContextOutcome;
  Src : string;
begin
  O := WrapAt(Region(['  {^}S := ''a'' + ''b'';']), Src);
  Assert.AreEqual<Integer>(1, Length(O.Edits));
  Assert.IsTrue(Pos(#10, O.Edits[0].NewText) > 0, 'Umbruch als #10');
  Assert.IsTrue(Pos(#13, O.Edits[0].NewText) = 0, 'kein #13 im neuen Text');
  AssertText(Region(['  S := ''a'' +', '    ''b'';']), Apply(Src, O.Edits),
    'CRLF');
  // Ein Puffer mit LF bleibt LF.
  O := WrapAt(JoinWith(#10, ['begin', '  {(*}', '  {^}S := ''a'' + ''b'';',
    '  {*)}', 'end;']), Src);
  AssertText(JoinWith(#10, ['begin', '  {(*}', '  S := ''a'' +', '    ''b'';',
    '  {*)}', 'end;']), Apply(Src, O.Edits), 'LF');
end;

// E5: alle Kandidaten des Bereichs in EINEM Eintrag (ein Undo-Schritt).
procedure TTestRdxConcatWrap.Wrap_WholeRegion_TwoStatements;
var
  O   : TRdxContextOutcome;
  Src : string;
begin
  O := WrapAt(Region(['  {^}S := ''a'' + ''b'';', '  Foo;',
    '  T := ''c'' + D + ''e'';']), Src);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(2, Length(O.Edits), 'eine Ersetzung je Zeile');
  AssertText(Region(['  S := ''a'' +', '    ''b'';', '  Foo;',
    '  T := ''c'' +', '    D +', '    ''e'';']), Apply(Src, O.Edits));
end;

// Der Caret auf der Zeile des Start- bzw. End-Markers zaehlt zum Bereich.
procedure TTestRdxConcatWrap.Wrap_CaretOnMarkerLine;
const
  WANT: array[0..4] of string = ('begin', '  {(*}', '  S := ''a'' +',
    '    ''b'';', '  {*)}');
begin
  AssertText(Join(WANT), Wrapped(Join(['begin', '  {^}{(*}',
    '  S := ''a'' + ''b'';', '  {*)}'])), 'Start');
  AssertText(Join(WANT), Wrapped(Join(['begin', '  {(*}',
    '  S := ''a'' + ''b'';', '  {*)}{^}'])), 'Ende');
end;

// Nach der Anwendung steht hinter keinem '+' der Kette mehr ein Operand:
// kein Eintrag mehr.
procedure TTestRdxConcatWrap.Wrap_Idempotent;
var
  Once : string;
  O    : TRdxContextOutcome;
begin
  Once := Wrapped(Region(['  {^}Query.SQL.Add(''UPDATE t SET a = '' + '
    + 'QuotedStr(A) + '' WHERE Id = '' + IntToStr(Id));',
    '  S := ''x'' + ''y'';']));
  Assert.AreEqual<Integer>(0, CountWrap(RunPos(Once, 7, 3), O),
    'zweiter Lauf: ' + Once);
  Assert.IsTrue(RegionFound(Once, 7), 'der Bereich steht noch');
end;

// Ein gesperrter und ein freier Kandidat: freigegeben, der Hinweis zaehlt
// beide; nur der freie aendert sich.
procedure TTestRdxConcatWrap.Wrap_SkippedCountInHint;
var
  O    : TRdxContextOutcome;
  Src  : string;
  Map  : TRdxCodeMap;
  Plan : TRdxWrapPlan;
begin
  O := WrapAt(Region(['  {^}T := ''a'' + ''b''; U := ''c'';',
    '  S := ''x'' + ''y'';']), Src);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.IsTrue(Pos('gleiche Bedeutung', O.Hint) = 1, O.Hint);
  Assert.IsTrue(Pos('Anweisungen: 1, ausgelassen: 1', O.Hint) > 0, O.Hint);
  AssertText(Region(['  T := ''a'' + ''b''; U := ''c'';', '  S := ''x'' +',
    '    ''y'';']), Apply(Src, O.Edits));
  // Der Planer selbst: ein Grund nur ohne umbrochene Anweisung. Das Innere
  // des Bereichs (Region): Zeile 6 hinter '  {(*}' (Spalte 7) bis zum '{'
  // von '  {*)}' in Zeile 9 (Spalte 3); Caret auf Zeile 7.
  Map := NewMap(Src);
  try
    Assert.IsTrue(TRdxConcatWrap.PlanRange(Map, 6, 7, 9, 3, 7, Plan));
    Assert.AreEqual<Integer>(1, Plan.Wrapped);
    Assert.AreEqual<Integer>(1, Plan.Skipped);
    Assert.AreEqual('', Plan.Reason, 'kein Grund neben einem Angebot');
  finally
    Map.Free;
  end;
end;

procedure TTestRdxConcatWrap.Wrap_CaptionGerman;
var
  O : TRdxContextOutcome;
begin
  O := Default(TRdxContextOutcome);
  O.Kind := ckWrapConcat;
  AssertText('Verkettungen im Formatter-Bereich nach jedem "+" umbrechen',
    TRdxContextRunner.CaptionOf(O));
end;

// Eine Anweisung ohne ';' vor else: das Literal am Ende der Kette steht im
// Spalt vor dem else - es zaehlt.
procedure TTestRdxConcatWrap.Wrap_BranchWithoutSemicolon;
begin
  AssertText(Region(['  if A then', '    S := X +', '      ''y''', '  else',
    '    S := '''';']),
    Wrapped(Region(['  {^}if A then', '    S := X + ''y''', '  else',
    '    S := '''';'])));
end;

// Der Bereich beginnt mitten in einem Aufruf: dessen Rest zaehlt nicht, die
// Anweisungen danach schon (die ueberzaehlige ')' bricht die Zerlegung
// nicht).
procedure TTestRdxConcatWrap.Wrap_RegionStartsInsideCall;
begin
  AssertText(Join(['begin', '  Foo(A,', '  {(*}', '    ''x'' + B);',
    '  S := ''a'' +', '    ''b'';', '  {*)}', 'end;']),
    Wrapped(Join(['begin', '  Foo(A,', '  {(*}', '    ''x'' + B);',
    '  {^}S := ''a'' + ''b'';', '  {*)}', 'end;'])));
end;

{ ---- Sperre ---- }

procedure TTestRdxConcatWrapRefused.Wrap_CommentInChain_Refused;
begin
  AssertRefused(Region(['  {^}S := ''x'' + { Kommentar } ''y'';']),
    _(R_CW_COMMENT));
  AssertRefused(Region(['  {^}S := ''x'' + (* alt *) ''y'' + ''z'';']),
    _(R_CW_COMMENT));
end;

procedure TTestRdxConcatWrapRefused.Wrap_DirectiveInChain_Refused;
begin
  AssertRefused(Region(['  {^}S := ''a'' + {$IFDEF X} ''b'' + {$ENDIF} '
    + '''c'';']), _(R_CW_COMMENT));
end;

procedure TTestRdxConcatWrapRefused.Wrap_TwoStatementsOnLine_Refused;
begin
  AssertRefused(Region(['  {^}T := ''a'' + ''b''; U := ''c'';']),
    _(R_CW_TWO_STATEMENTS));
  AssertRefused(Region(['  {^}begin S := ''a'' + ''b''; end;']),
    _(R_CW_TWO_STATEMENTS));
  AssertRefused(Region(['  {^}if A then S := ''a'' + ''b'';']),
    _(R_CW_TWO_STATEMENTS));
end;

procedure TTestRdxConcatWrapRefused.Wrap_LeadingPlusStyle_Refused;
begin
  AssertRefused(Region(['  {^}S := ''a'' + ''b''', '    + ''c'';']),
    _(R_CW_LEADING_PLUS));
end;

procedure TTestRdxConcatWrapRefused.Wrap_MultiLineString_Refused;
begin
  AssertRefused(Region(['  {^}S := ''''''', '    abc',
    '    '''''' + ''x'' + ''y'';']), _(R_CW_MULTI_LINE));
  // Als letzter Operand vor else (ohne ';'): der String steht hinter dem
  // letzten Token der Anweisung.
  AssertRefused(Region(['  if A then', '    {^}S := X + ''''''', '    abc',
    '    ''''''', '  else', '    S := '''';']), _(R_CW_MULTI_LINE));
end;

procedure TTestRdxConcatWrapRefused.Wrap_SuppressionComment_Refused;
begin
  AssertRefused(Region(['  {^}S := ''a'' + ''b''; // noinspection '
    + 'DuplicateString']), _(R_CW_SUPPRESSION));
  AssertRefused(Region(['  {^}S := ''a'' + ''b''; // NOSONAR']),
    _(R_CW_SUPPRESSION));
  AssertRefused(Region(['  {^}S := ''a'' + ''b''; { noinspection All }']),
    _(R_CW_SUPPRESSION));
end;

// Alle Kandidaten gesperrt: der Grund des Caret-naechsten (6.3), bei
// gleichem Abstand der erste.
procedure TTestRdxConcatWrapRefused.Wrap_ReasonOfNearestRefused;
begin
  AssertRefused(Region(['  {^}S := ''a'' + { k } ''b'';', '  Foo;',
    '  T := ''a'' + ''b''; U := 1;']), _(R_CW_COMMENT));
  AssertRefused(Region(['  S := ''a'' + { k } ''b'';', '  Foo;',
    '  {^}T := ''a'' + ''b''; U := 1;']), _(R_CW_TWO_STATEMENTS));
  AssertRefused(Region(['  S := ''a'' + { k } ''b'';', '  {^}Foo;',
    '  T := ''a'' + ''b''; U := 1;']), _(R_CW_COMMENT));
end;

{ ---- Kein Eintrag ---- }

// E7: ausserhalb eines Bereichs nie - auch nicht neben einem Bereich.
procedure TTestRdxConcatWrapNoEntry.Wrap_OutsideRegion_NoEntry;
begin
  AssertNoRegion(Join(['begin', '  {^}S := ''SELECT * '' + ''FROM Kunden'';',
    '  {(*}', '  T := 1;', '  {*)}', 'end;']),
    'S := ''SELECT * '' + ''FROM Kunden'';', 'vor dem Bereich');
  AssertNoRegion(Join(['begin', '  {(*}', '  T := 1;', '  {*)}',
    '  {^}S := ''a'' + ''b'';', 'end;']), 'S := ''a'' + ''b'';',
    'hinter dem Bereich');
end;

// F1: ein Start ohne Ende ist kein Bereich.
procedure TTestRdxConcatWrapNoEntry.Wrap_UnclosedStart_NoEntry;
begin
  AssertNoRegion(Join(['begin', '  {(*}', '  {^}S := ''a'' + ''b'';',
    'end;']), 'S := ''a'' + ''b'';', 'F1');
end;

// F4 (E6): erst die Hilfe "Marker exakt schreiben".
procedure TTestRdxConcatWrapNoEntry.Wrap_MalformedMarker_NoEntry;
begin
  AssertNoRegion(Join(['begin', '  { (*}', '  {^}S := ''a'' + ''b'';',
    '  {*)}', 'end;']), 'S := ''a'' + ''b'';', 'F4 am Start');
  AssertNoRegion(Join(['begin', '  {(*}', '  {^}S := ''a'' + ''b'';',
    '  {*) }', 'end;']), 'S := ''a'' + ''b'';', 'F4 am Ende');
  // Der falsch geschriebene Start schaltet wie im Detektor: der exakte
  // dahinter ist ein zweiter Start (F3) und oeffnet nichts.
  AssertNoRegion(Join(['begin', '  { (*}', '  {(*}', '  {^}S := ''a'' + ''b'';',
    '  {*)}', 'end;']), 'S := ''a'' + ''b'';', 'F4-Start vor exaktem Start');
end;

// F2: ein Ende ohne Start schliesst nichts.
procedure TTestRdxConcatWrapNoEntry.Wrap_OrphanEnd_NoEntry;
begin
  AssertNoRegion(Join(['begin', '  {^}S := ''a'' + ''b'';', '  {*)}',
    'end;']), 'S := ''a'' + ''b'';', 'F2');
end;

// F3: der zweite Start oeffnet nichts, das erste Ende schliesst - dahinter
// kein Bereich mehr; davor der ganze Bereich.
procedure TTestRdxConcatWrapNoEntry.Wrap_NestedStart_RegionEndsAtFirstEnd;
var
  O   : TRdxContextOutcome;
  Src : string;
begin
  AssertNone(Join(['begin', '  {(*}', '  S := ''a'' + ''b'';', '  {(*}',
    '  T := ''c'' + ''d'';', '  {*)}', '  {^}U := ''e'' + ''f'';', '  {*)}',
    'end;']), 'hinter dem ersten Ende');
  O := WrapAt(Join(['begin', '  {(*}', '  {^}S := ''a'' + ''b'';', '  {(*}',
    '  T := ''c'' + ''d'';', '  {*)}', '  U := ''e'' + ''f'';', '  {*)}',
    'end;']), Src);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(2, Length(O.Edits), 'S und T, nicht U');
end;

// Marker in String und Kommentar sind keine Marker.
procedure TTestRdxConcatWrapNoEntry.Wrap_MarkerInStringOrComment_NoEntry;
begin
  AssertNoRegion(Join(['begin', '  X := ''{(*}'';', '  (* {(*} *)',
    '  // {(*}', '  {^}S := ''a'' + ''b'';', '  // {*)}', '  Y := ''{*)}'';',
    'end;']), 'S := ''a'' + ''b'';', 'Marker in String/Kommentar');
end;

// Ohne String- oder Zeichenliteral ist es keine Verkettung.
procedure TTestRdxConcatWrapNoEntry.Wrap_NumbersOnly_NoEntry;
begin
  AssertNoCandidate(Region(['  {^}Summe := A + B + C;',
    '  X := Foo(''a'') + Bar;']),
    Region(['  Summe := A + B + C;', '  X := Foo(''a'') + Bar;', CTL_AT]),
    'nur Zahlen/Aufrufe');
end;

// Ein unaeres '+' ist kein Umbruchpunkt (Text-Sicht: der Compiler lehnte
// '+''a''' ab, die Aktion entscheidet nur am Token davor).
procedure TTestRdxConcatWrapNoEntry.Wrap_UnaryPlus_NoEntry;
begin
  AssertNoCandidate(Region(['  {^}S := + ''a'';', '  X := +5;']),
    Region(['  S := + ''a'';', '  X := +5;', CTL_AT]), 'unaer');
  // Neben einem binaeren '+' bleibt das unaere am Operanden.
  AssertText(Region(['  S := ''a'' +', '    +1;']),
    Wrapped(Region(['  {^}S := ''a'' + +1;'])));
end;

// G3: zwei Ketten in verschiedenen Argumenten.
procedure TTestRdxConcatWrapNoEntry.Wrap_TwoChainsInOneCall_NoEntry;
begin
  AssertNoCandidate(Region(['  {^}F(''a'' + ''b'', ''c'' + ''d'');']),
    Region(['  F(''a'' + ''b'', ''c'' + ''d'');', CTL_AT]), 'zwei Argumente');
  AssertNoCandidate(Region(['  {^}S := F(''a'' + ''b'') + G(''c'' + ''d'');',
    '  T := [''a'' + ''b''];']),
    Region(['  S := F(''a'' + ''b'') + G(''c'' + ''d'');',
    '  T := [''a'' + ''b''];', CTL_AT]),
    'kein Literal auf der Kettenebene, Menge');
end;

// Eine Anweisung, die einen Marker kreuzt, gehoert nicht ganz zum Bereich.
procedure TTestRdxConcatWrapNoEntry.Wrap_StatementCrossesMarker_NoEntry;
begin
  AssertNoCandidate(Join(['begin', '  {(*}', '  {^}S := ''a'' + ''b'' +',
    '  {*)}', '    ''c'';', 'end;']),
    Join(['begin', '  {(*}', CTL_AT, '  S := ''a'' + ''b'' +', '  {*)}',
    '    ''c'';', 'end;']), 'kreuzt das Ende');
  // Der Rest hinter ':=' saehe fuer sich wie ein Aufruf aus.
  AssertNoCandidate(Join(['begin', '  S :=', '  {(*}',
    '  {^}F(''b'' + ''c'');', '  {*)}', 'end;']),
    Join(['begin', '  S :=', '  {(*}', '  F(''b'' + ''c'');', CTL_AT,
    '  {*)}', 'end;']), 'beginnt vor dem Start');
end;

// Der typische Bereich des Korpus: ein JCF-Lizenzkopf, nur Kommentar.
procedure TTestRdxConcatWrapNoEntry.Wrap_RegionOnlyComments_NoEntry;
const
  HEAD: array[0..3] of string = ('(*-------------------------------------',
    ' Delphi Code formatter source code ''a'' + ''b'' + ''c''',
    '-------------------------------------*)', '{*)}');
begin
  AssertNoCandidate('{^}{(*}' + #13#10 + Join(HEAD) + #13#10
    + Join(['unit u;', 'interface', 'implementation', 'end.']),
    '{(*}' + #13#10 + CTL_AT + #13#10 + Join(HEAD) + #13#10
    + Join(['unit u;', 'interface', 'implementation', 'end.']), 'Lizenzkopf');
end;

// Ein Ende hinter dem Schluss eines Block-Kommentars sieht der Zeilenlauf
// nicht (die Zeile beginnt im Kommentar) - der Detektor schon: dort endet
// der Bereich vor S. Ohne sichere Bilanz gibt es keinen Bereich.
procedure TTestRdxConcatWrapNoEntry.Wrap_MarkerBehindBlockComment_NoEntry;
begin
  AssertNoRegion(Join(['begin', '  {(*}', '  T := 1;', '  (* alt',
    '  *) {*)}', '  {^}S := ''a'' + ''b'';', '  {*)}', 'end;']),
    'S := ''a'' + ''b'';', 'Ende hinter Block-Kommentar');
end;

// Bedingungen, Routinenkoepfe, anonyme Methoden und asm sind keine
// Zuweisung, keine Konstante und kein Aufruf.
procedure TTestRdxConcatWrapNoEntry.Wrap_ControlStatement_NoEntry;
const
  HEAD = 'procedure Foo(const A: string = ''a'' + ''b'');';
begin
  AssertBodyNoCandidate(Join(['  if Pos(''a'' + B, S) > 0 then', '    Foo;',
    '  while Pos(''a'' + B, S) > 0 do', '    Foo;', '  repeat', '    Foo;',
    '  until Pos(''a'' + B, S) > 0;']), 'Bedingung');
  AssertBodyNoCandidate(Join(['  TThread.Queue(nil, procedure begin',
    '    S := ''a'' + ''b'';', '  end);']), 'anonyme Methode');
  AssertBodyNoCandidate(Join(['  asm', '    MOV EAX, 1;',
    '    DD Foo(''a'' + ''b'')', '  end;']), 'asm');
  AssertNoCandidate(Join(['unit u;', 'interface', '{(*}', '{^}' + HEAD,
    '{*)}', 'implementation', 'end.']),
    Join(['unit u;', 'interface', '{(*}', HEAD, CTL_AT, '{*)}',
    'implementation', 'end.']), 'Routinenkopf');
end;

{$IFNDEF FPC}

// ---- Mit dem echten Detektor ----

procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TFormatterMarkerDetector.AnalyzeUnit(Root, Path, Results);
end;

// Eine Unit mit ABody im interface-Teil (ab Zeile 3).
function InUnit(const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface']) + #13#10 + Join(ABody) + #13#10
    + Join(['implementation', '', 'end.']);
end;

// Meldet der Detektor in ASeen etwas auf Zeile ALine?
function FindingOn(const ASeen: TArray<TSeen>; ALine: Integer): Boolean;
var
  F : TSeen;
begin
  Result := False;
  for F in ASeen do
    if F.Line = ALine then
      Exit(True);
end;

// Das Markerpaar in den Rumpfzeilen AStart..AEnd (1-basiert, AEnd 0 = ohne
// Ende) ist genau dann ein Bereich der Aktion, wenn der Detektor an keinem
// der beiden Marker etwas meldet - und AIntact sagt, welcher Fall es ist.
procedure CheckPair(const ABody: array of string; AStart, AEnd: Integer;
  AIntact: Boolean; const AWhat: string);
var
  S              : string;
  Seen           : TArray<TSeen>;
  Map            : TRdxCodeMap;
  SL, SC, EL, EC : Integer;
  Quiet, Has     : Boolean;
begin
  S := InUnit(ABody);
  Seen := DetectSource('rdx_cw_', S, fkFormatterMarker, RunDetector);
  Quiet := (AEnd > 0) and not FindingOn(Seen, AStart + 2)
    and not FindingOn(Seen, AEnd + 2);
  Map := NewMap(S);
  try
    Has := TRdxFormatterMarkerFix.MarkerRegionAt(Map, AStart + 2, SL, SC, EL,
      EC);
  finally
    Map.Free;
  end;
  Assert.IsTrue(Quiet = AIntact, AWhat + ': Detektor');
  Assert.IsTrue(Has = AIntact, AWhat + ': Bereich');
  if Has then
  begin
    Assert.AreEqual<Integer>(AStart + 2, SL, AWhat + ': Startzeile');
    Assert.AreEqual<Integer>(AEnd + 2, EL, AWhat + ': Endzeile');
  end;
end;

procedure TTestRdxConcatWrapDetector.Region_MatchesDetector;
begin
  CheckPair(['{(*}', 'const X = 1;', '{*)}'], 1, 3, True, 'intakt');
  CheckPair(['{ (*}', 'const X = 1;', '{*)}'], 1, 3, False, 'F4 Start');
  CheckPair(['{(*}', 'const X = 1;', '{*) }'], 1, 3, False, 'F4 Ende');
  CheckPair(['{(*}', 'const X = 1;'], 1, 0, False, 'F1');
  CheckPair(['const X = 1;', '{*)}'], 2, 2, False, 'F2');
  CheckPair(['{(*}', '{(*}', 'const X = 1;', '{*)}'], 1, 4, True,
    'F3 im Paar');
  CheckPair(['{(*}', '{*) }', 'const X = 1;', '{*)}'], 1, 2, False,
    'F4-Ende schliesst, F2 dahinter');
  CheckPair(['{ (*}', '{(*}', 'const X = 1;', '{*)}'], 2, 4, False,
    'F4-Start oeffnet, der exakte ist F3');
  // Das Ende hinter einem Block-Kommentar zaehlt der Detektor (F2 am
  // letzten Ende); die Aktion hat ohne sichere Bilanz keinen Bereich.
  CheckPair(['{(*}', '(* alt', '*) {*)}', 'const X = 1;', '{*)}'], 1, 5,
    False, 'Ende hinter Block-Kommentar');
end;

procedure TTestRdxConcatWrapDetector.Caption_ViaContextCaption;
var
  O : TRdxContextOutcome;
begin
  O := Default(TRdxContextOutcome);
  O.Kind := ckWrapConcat;
  Assert.AreEqual(TRdxContextRunner.CaptionOf(O),
    TRdxFixTable.ContextCaption(O));
  AssertText('Verkettungen im Formatter-Bereich nach jedem "+" umbrechen',
    TRdxFixTable.ContextCaption(O));
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxConcatWrap);
  TDUnitX.RegisterTestFixture(TTestRdxConcatWrapRefused);
  TDUnitX.RegisterTestFixture(TTestRdxConcatWrapNoEntry);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxConcatWrapDetector);
  {$ENDIF}

end.
