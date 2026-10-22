unit uTestRdxForRangeFix;

// Editorhilfe SCA046 ReversedForRange (uRdxForRangeFix) - nur Delphi,
// reDelphix.Test: die Planer auf Text (Hauptweg 'to' -> 'downto', zweiter
// Eintrag Grenzen tauschen) samt Gegenproben, dazu Rundlaeufe gegen den
// ECHTEN Detektor (uReversedForRange): der Detektor meldet, der Planer plant
// aus dem Fund (Zeile und Meldung), die Ersetzung wird angewandt, und
// derselbe Detektor schweigt danach. Die Planer werden hier direkt gerufen -
// die Zeile in uRdxFixTable kommt mit der Integration.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxForRangeFix = class
  public
    // ---- Planer auf Text ----
    [Test] procedure ToDownto_Literals;
    [Test] procedure ToDownto_NegativeBounds;
    [Test] procedure ToDownto_KeepsCaseOfTo;
    [Test] procedure ToDownto_InlineVarAndTabs;
    [Test] procedure ToDownto_OtherStatementsAndTrailingComment;
    [Test] procedure SwapBounds_Literals;
    [Test] procedure SwapBounds_NegativeAndSpacing;
    [Test] procedure Alt_IsSecondEntryWithHint;
    [Test] procedure Refuse_CommentOrStringInHead;
    [Test] procedure Refuse_NoHeadOnLine;
    [Test] procedure Refuse_OtherBoundsThanFinding;
    [Test] procedure Refuse_TwoHeadsOnLine;
    [Test] procedure Refuse_MessageWithoutBounds;
    [Test] procedure Refuse_HeadOverTwoLinesOrTyped;
    // ---- gegen den echten Detektor ----
    [Test] procedure Detector_CatalogExample_Downto;
    [Test] procedure Detector_CatalogExample_Swap;
    [Test] procedure Detector_MoreLoops_RoundTrip;
    [Test] procedure Detector_TwoHeadsOnOneLine_NoHelp;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uReversedForRange,
  uRdxForRangeFix, uRdxRecipeRunner, uRdxFixTable,
  uTestRdxDetectorKit,   // TSeen, DetectSource
  uTestRdxTextKit;       // Join, Apply

const
  // Die Faelle stehen im Rumpf von P, ab Zeile 8.
  BODY_LINE = 8;

// Die Meldung wie der Detektor sie schreibt.
function RevMsg(AFrom, ATo: Int64; const ASnippet: string): string;
begin
  Result := Format('Reversed for-range: %d > %d (use `downto`?) - %s',
    [AFrom, ATo, ASnippet]);
end;

// Eine Unit mit Routine P; ABody ist der Rumpf (erste Zeile = BODY_LINE).
function InUnit(const ABody: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation', 'procedure P;',
    'var', '  i, j: Integer;', 'begin']) + #13#10 + Join(ABody) + #13#10
    + Join(['end;', 'end.']);
end;

procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TReversedForRangeDetector.AnalyzeUnit(Root, Path, Results);
end;

function PlanAt(const ASource: string; ALine: Integer; const AMessage: string;
  AAlt: Boolean): TRdxFixOutcome;
var
  SL : TStringList;
  F  : TLeakFinding;
begin
  SL := TStringList.Create;
  F := TLeakFinding.New('t.pas', '', ALine, AMessage, fkReversedForRange);
  try
    SL.Text := ASource;
    if AAlt then
      Result := TRdxFixTable.AlternativeFixFor(nil, SL, F, nil)
    else
      Result := TRdxFixTable.FixFor(nil, SL, F, nil);
  finally
    F.Free;
    SL.Free;
  end;
end;

// Der Text nach der Hilfe; '' ohne Hilfe (dann steht der Grund in AOutcome).
function Fixed(const ASource: string; ALine: Integer; const AMessage: string;
  AAlt: Boolean; out AOutcome: TRdxFixOutcome): string;
begin
  AOutcome := PlanAt(ASource, ALine, AMessage, AAlt);
  Result := '';
  if AOutcome.Enabled then
    Result := Apply(ASource, AOutcome.Edits);
end;

// Dasselbe wie Detect einer Q/R-Unit in der Form von TDetectFunc
// (FixAllWith).
function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_forrange_', ASource, AKind, RunDetector);
end;

// Wie der Benutzer: Fund fuer Fund melden, die Hilfe (AAlt: den zweiten
// Eintrag) anwenden, bis der Detektor schweigt - ueber den Einstieg des
// Anbieters (uTestRdxDetectorKit.FixAllWith; bis zur Review Woche G06
// eine eigene Schleife).
function FixAll(const ASource: string; AAlt: Boolean): string;
begin
  Result := FixAllWith(ASource, fkReversedForRange, DetectKind, AAlt);
end;

{ ---- Planer auf Text ---- }

procedure TTestRdxForRangeFix.ToDownto_Literals;
var
  O : TRdxFixOutcome;
begin
  Assert.AreEqual(InUnit(['  for i := 10 downto 1 do Foo(i);']),
    Fixed(InUnit(['  for i := 10 to 1 do Foo(i);']), BODY_LINE,
      RevMsg(10, 1, 'for i := 10 to 1 do'), False, O), O.Reason);
  Assert.AreEqual<Integer>(0, O.Variant);
  Assert.AreEqual<Integer>(1, Length(O.Edits));
  // Der Kopf allein auf der Zeile, der Rumpf darunter.
  Assert.AreEqual(InUnit(['  for i := 3 downto 0 do', '    Foo(i);']),
    Fixed(InUnit(['  for i := 3 to 0 do', '    Foo(i);']), BODY_LINE,
      RevMsg(3, 0, 'for i := 3 to 0 do'), False, O), O.Reason);
end;

procedure TTestRdxForRangeFix.ToDownto_NegativeBounds;
var
  O : TRdxFixOutcome;
begin
  Assert.AreEqual(InUnit(['  for i := -5 downto -10 do Foo(i);']),
    Fixed(InUnit(['  for i := -5 to -10 do Foo(i);']), BODY_LINE,
      RevMsg(-5, -10, 'for i := -5 to -10 do'), False, O), O.Reason);
  Assert.AreEqual(InUnit(['  for i := 4 downto -1 do Foo(i);']),
    Fixed(InUnit(['  for i := 4 to -1 do Foo(i);']), BODY_LINE,
      RevMsg(4, -1, 'for i := 4 to -1 do'), False, O), O.Reason);
end;

procedure TTestRdxForRangeFix.ToDownto_KeepsCaseOfTo;
var
  O : TRdxFixOutcome;
begin
  Assert.AreEqual(InUnit(['  FOR I := 10 DOWNTO 1 DO Foo(I);']),
    Fixed(InUnit(['  FOR I := 10 TO 1 DO Foo(I);']), BODY_LINE,
      RevMsg(10, 1, 'FOR I := 10 TO 1 DO'), False, O), O.Reason);
  Assert.AreEqual(InUnit(['  For i := 10 Downto 1 Do Foo(i);']),
    Fixed(InUnit(['  For i := 10 To 1 Do Foo(i);']), BODY_LINE,
      RevMsg(10, 1, 'For i := 10 To 1 Do'), False, O), O.Reason);
end;

procedure TTestRdxForRangeFix.ToDownto_InlineVarAndTabs;
var
  O : TRdxFixOutcome;
begin
  Assert.AreEqual(InUnit(['  for var k := 10 downto 1 do Foo(k);']),
    Fixed(InUnit(['  for var k := 10 to 1 do Foo(k);']), BODY_LINE,
      RevMsg(10, 1, 'for var k := 10 to 1 do'), False, O), O.Reason);
  Assert.AreEqual(InUnit(['  for'#9'i :='#9'10'#9'downto'#9'1'#9'do Foo(i);']),
    Fixed(InUnit(['  for'#9'i :='#9'10'#9'to'#9'1'#9'do Foo(i);']), BODY_LINE,
      RevMsg(10, 1, 'for i := 10 to 1 do'), False, O), O.Reason);
end;

procedure TTestRdxForRangeFix.ToDownto_OtherStatementsAndTrailingComment;
var
  O : TRdxFixOutcome;
begin
  // Ein Kommentar HINTER dem Kopf und ein String im Rumpf stoeren nicht.
  Assert.AreEqual(InUnit(['  for i := 10 downto 1 do Foo(''to''); // 10 to 1']),
    Fixed(InUnit(['  for i := 10 to 1 do Foo(''to''); // 10 to 1']), BODY_LINE,
      RevMsg(10, 1, 'for i := 10 to 1 do'), False, O), O.Reason);
  // Eine Anweisung davor auf derselben Zeile.
  Assert.AreEqual(InUnit(['  j := 0; for i := 2 downto 1 do Inc(j);']),
    Fixed(InUnit(['  j := 0; for i := 2 to 1 do Inc(j);']), BODY_LINE,
      RevMsg(2, 1, 'for i := 2 to 1 do'), False, O), O.Reason);
end;

procedure TTestRdxForRangeFix.SwapBounds_Literals;
var
  O : TRdxFixOutcome;
begin
  Assert.AreEqual(InUnit(['  for i := 1 to 10 do Foo(i);']),
    Fixed(InUnit(['  for i := 10 to 1 do Foo(i);']), BODY_LINE,
      RevMsg(10, 1, 'for i := 10 to 1 do'), True, O), O.Reason);
  Assert.AreEqual(InUnit(['  for i := 0 to 3 do', '    Foo(i);']),
    Fixed(InUnit(['  for i := 3 to 0 do', '    Foo(i);']), BODY_LINE,
      RevMsg(3, 0, 'for i := 3 to 0 do'), True, O), O.Reason);
  Assert.AreEqual(InUnit(['  FOR I := 1 TO 10 DO Foo(I);']),
    Fixed(InUnit(['  FOR I := 10 TO 1 DO Foo(I);']), BODY_LINE,
      RevMsg(10, 1, 'FOR I := 10 TO 1 DO'), True, O), O.Reason);
end;

procedure TTestRdxForRangeFix.SwapBounds_NegativeAndSpacing;
var
  O : TRdxFixOutcome;
begin
  Assert.AreEqual(InUnit(['  for i := -10 to -5 do Foo(i);']),
    Fixed(InUnit(['  for i := -5 to -10 do Foo(i);']), BODY_LINE,
      RevMsg(-5, -10, 'for i := -5 to -10 do'), True, O), O.Reason);
  // Der Leerraum um das 'to' bleibt, wie er ist.
  Assert.AreEqual(InUnit(['  for i := 1  to'#9'10 do Foo(i);']),
    Fixed(InUnit(['  for i := 10  to'#9'1 do Foo(i);']), BODY_LINE,
      RevMsg(10, 1, 'for i := 10 to 1 do'), True, O), O.Reason);
end;

procedure TTestRdxForRangeFix.Alt_IsSecondEntryWithHint;
var
  Main, Alt : TRdxFixOutcome;
  Src       : string;
begin
  Src := InUnit(['  for i := 10 to 1 do Foo(i);']);
  Fixed(Src, BODY_LINE, RevMsg(10, 1, 'x'), False, Main);
  Fixed(Src, BODY_LINE, RevMsg(10, 1, 'x'), True, Alt);
  Assert.IsTrue(Main.Enabled and Alt.Enabled, Main.Reason + Alt.Reason);
  Assert.AreEqual<Integer>(0, Main.Variant);
  Assert.AreEqual<Integer>(1, Alt.Variant);
  Assert.IsTrue(Alt.ChangesBehavior);
  Assert.AreEqual('die Schleife lief bisher nie und zaehlt danach '
    + 'aufwaerts; war sie absichtlich abgeschaltet, ist das ein '
    + 'Eingriff', Alt.Hint);
  // Beide Eintraege lehnen auch gemeinsam ab; der Alt-Planer bleibt Variant 1.
  Fixed(InUnit(['  Foo(1);']), BODY_LINE, RevMsg(10, 1, 'x'), True, Alt);
  Assert.IsFalse(Alt.Enabled);
  Assert.AreEqual<Integer>(1, Alt.Variant);
  Assert.AreEqual<Integer>(0, Length(Alt.Edits));
end;

procedure TTestRdxForRangeFix.Refuse_CommentOrStringInHead;
var
  O : TRdxFixOutcome;
  Alt : Boolean;
  Msg : string;
begin
  Msg := RevMsg(10, 1, 'for i := 10 to 1 do');
  for Alt in [False, True] do
  begin
    // Kommentar mitten im Kopf (von der Meldung her ein Fund, am Text nicht
    // mehr sauber planbar).
    Assert.AreEqual('', Fixed(InUnit(['  for i := 10 {c} to 1 do Foo(i);']),
      BODY_LINE, Msg, Alt, O));
    Assert.IsTrue(Pos(R_FORRANGE_NONCODE, O.Reason) > 0, O.Reason);
    Assert.AreEqual('', Fixed(InUnit(['  for i := 10 to (* c *) 1 do Foo(i);']),
      BODY_LINE, Msg, Alt, O));
    Assert.IsTrue(Pos(R_FORRANGE_NONCODE, O.Reason) > 0, O.Reason);
    // Der Kopf steht nur in einem Kommentar bzw. String.
    Assert.AreEqual('', Fixed(InUnit(['  // for i := 10 to 1 do']), BODY_LINE,
      Msg, Alt, O));
    Assert.IsTrue(Pos(R_FORRANGE_WHAT, O.Reason) > 0, O.Reason);
    Assert.AreEqual('', Fixed(InUnit(['  S := ''for i := 10 to 1 do'';']),
      BODY_LINE, Msg, Alt, O));
    Assert.IsTrue(Pos(R_FORRANGE_WHAT, O.Reason) > 0, O.Reason);
    Assert.AreEqual('', Fixed(InUnit(['  { for i := 10 to 1 do }']), BODY_LINE,
      Msg, Alt, O));
    Assert.IsTrue(Pos(R_FORRANGE_WHAT, O.Reason) > 0, O.Reason);
  end;
end;

procedure TTestRdxForRangeFix.Refuse_NoHeadOnLine;
var
  O : TRdxFixOutcome;
  Msg : string;
begin
  Msg := RevMsg(10, 1, 'for i := 10 to 1 do');
  // Zeile verschoben: der Fund zeigt auf eine andere Zeile.
  Assert.AreEqual('', Fixed(InUnit(['  Foo(1);', '  for i := 10 to 1 do Foo(i);']),
    BODY_LINE, Msg, False, O));
  Assert.IsTrue(Pos(R_FORRANGE_WHAT, O.Reason) > 0, O.Reason);
  // Grenzen, die nicht umgekehrt sind, und Nicht-Literale.
  Assert.AreEqual('', Fixed(InUnit(['  for i := 1 to 10 do Foo(i);']),
    BODY_LINE, Msg, False, O));
  Assert.IsTrue(Pos(R_FORRANGE_WHAT, O.Reason) > 0, O.Reason);
  Assert.AreEqual('', Fixed(InUnit(['  for i := N to 1 do Foo(i);']),
    BODY_LINE, Msg, True, O));
  Assert.IsTrue(Pos(R_FORRANGE_WHAT, O.Reason) > 0, O.Reason);
  Assert.AreEqual('', Fixed(InUnit(['  for i := 10 to M do Foo(i);']),
    BODY_LINE, Msg, True, O));
  Assert.IsTrue(Pos(R_FORRANGE_WHAT, O.Reason) > 0, O.Reason);
  // Ein anderes Wort 'for' (Bezeichner) ist kein Kopf.
  Assert.AreEqual('', Fixed(InUnit(['  X.for := 10; Y := 1;']), BODY_LINE, Msg,
    False, O));
  Assert.IsTrue(Pos(R_FORRANGE_WHAT, O.Reason) > 0, O.Reason);
end;

procedure TTestRdxForRangeFix.Refuse_OtherBoundsThanFinding;
var
  O : TRdxFixOutcome;
begin
  // Die Zeile hat sich geaendert: ein umgekehrter Kopf, aber mit anderen
  // Werten als die Meldung nennt.
  Assert.AreEqual('', Fixed(InUnit(['  for i := 20 to 2 do Foo(i);']),
    BODY_LINE, RevMsg(10, 1, 'for i := 10 to 1 do'), False, O));
  Assert.AreEqual(R_FORRANGE_OTHER, O.Reason);
  Assert.AreEqual('', Fixed(InUnit(['  for i := 20 to 2 do Foo(i);']),
    BODY_LINE, RevMsg(10, 1, 'for i := 10 to 1 do'), True, O));
  Assert.AreEqual(R_FORRANGE_OTHER, O.Reason);
end;

procedure TTestRdxForRangeFix.Refuse_TwoHeadsOnLine;
var
  O : TRdxFixOutcome;
begin
  // Der Detektor meldet nur den ersten; welcher gemeint ist, bleibt unklar.
  Assert.AreEqual('', Fixed(
    InUnit(['  for i := 10 to 1 do Foo(i); for j := 20 to 2 do Bar(j);']),
    BODY_LINE, RevMsg(10, 1, 'for i := 10 to 1 do'), False, O));
  Assert.IsTrue(Pos(Format(R_FORRANGE_MANY, [2]), O.Reason) > 0, O.Reason);
end;

procedure TTestRdxForRangeFix.Refuse_MessageWithoutBounds;
var
  O : TRdxFixOutcome;
  Src : string;
begin
  Src := InUnit(['  for i := 10 to 1 do Foo(i);']);
  Assert.AreEqual('', Fixed(Src, BODY_LINE, 'etwas anderes', False, O));
  Assert.AreEqual(R_FORRANGE_BOUNDS, O.Reason);
  Assert.AreEqual('', Fixed(Src, BODY_LINE, 'Reversed for-range: x > y', True,
    O));
  Assert.AreEqual(R_FORRANGE_BOUNDS, O.Reason);
  Assert.AreEqual('', Fixed(Src, BODY_LINE, 'Reversed for-range: 10 > ', False,
    O));
  Assert.AreEqual(R_FORRANGE_BOUNDS, O.Reason);
  Assert.AreEqual('', Fixed(Src, BODY_LINE, 'Reversed for-range: 10', False, O));
  Assert.AreEqual(R_FORRANGE_BOUNDS, O.Reason);
end;

procedure TTestRdxForRangeFix.Refuse_HeadOverTwoLinesOrTyped;
var
  O : TRdxFixOutcome;
  Msg : string;
begin
  Msg := RevMsg(10, 1, 'for i := 10 to 1 do');
  // Der Kopf geht ueber zwei Zeilen (der Detektor meldet das nicht).
  Assert.AreEqual('', Fixed(InUnit(['  for i := 10 to 1', '    do Foo(i);']),
    BODY_LINE, Msg, False, O));
  Assert.IsTrue(Pos(R_FORRANGE_WHAT, O.Reason) > 0, O.Reason);
  Assert.AreEqual('', Fixed(InUnit(['  for i := 10', '    to 1 do Foo(i);']),
    BODY_LINE, Msg, True, O));
  Assert.IsTrue(Pos(R_FORRANGE_WHAT, O.Reason) > 0, O.Reason);
  // Mit Typangabe plant der Planer nicht.
  Assert.AreEqual('', Fixed(InUnit(['  for var k: Integer := 10 to 1 do Foo(k);']),
    BODY_LINE, Msg, False, O));
  Assert.IsTrue(Pos(R_FORRANGE_WHAT, O.Reason) > 0, O.Reason);
end;

{ ---- gegen den echten Detektor ---- }

// Das Katalog-Beispiel als Rumpf von P (Zeilenenden CRLF).
function CatalogBody(const AExample: string): string;
begin
  Result := InUnit(['  ' + StringReplace(CatalogText(AExample), #13#10,
    #13#10'  ', [rfReplaceAll])]);
end;

procedure TTestRdxForRangeFix.Detector_CatalogExample_Downto;
var
  Meta : TRuleMeta;
  Bad  : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkReversedForRange);
  Bad := CatalogBody(Meta.BadExample);
  Assert.AreEqual<Integer>(1, Length(DetectSource('rdx_forrange_', Bad,
    fkReversedForRange, RunDetector)), 'der Detektor meldet das Beispiel');
  Assert.AreEqual(CatalogBody(Meta.GoodExample), FixAll(Bad, False));
end;

procedure TTestRdxForRangeFix.Detector_CatalogExample_Swap;
var
  Meta : TRuleMeta;
  Fixd : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkReversedForRange);
  Fixd := FixAll(CatalogBody(Meta.BadExample), True);
  Assert.IsTrue(Pos('for i := 1 to 10 do', Fixd) > 0, Fixd);
  Assert.IsTrue(Pos('downto', Fixd) = 0, Fixd);
end;

procedure TTestRdxForRangeFix.Detector_MoreLoops_RoundTrip;
var
  Src : string;
begin
  Src := InUnit([
    '  for i := 10 to 1 do Foo(i);',
    '  for i := -5 to -10 do',
    '    Foo(i);',
    '  for var k := 3 to 0 do Foo(k);',
    '  FOR I := 7 TO 2 DO Foo(I);',
    '  for i := 1 to 10 do Foo(i);',
    '  for i := 10 downto 1 do Foo(i);']);
  Assert.AreEqual(InUnit([
    '  for i := 10 downto 1 do Foo(i);',
    '  for i := -5 downto -10 do',
    '    Foo(i);',
    '  for var k := 3 downto 0 do Foo(k);',
    '  FOR I := 7 DOWNTO 2 DO Foo(I);',
    '  for i := 1 to 10 do Foo(i);',
    '  for i := 10 downto 1 do Foo(i);']), FixAll(Src, False));
  Assert.AreEqual(InUnit([
    '  for i := 1 to 10 do Foo(i);',
    '  for i := -10 to -5 do',
    '    Foo(i);',
    '  for var k := 0 to 3 do Foo(k);',
    '  FOR I := 2 TO 7 DO Foo(I);',
    '  for i := 1 to 10 do Foo(i);',
    '  for i := 10 downto 1 do Foo(i);']), FixAll(Src, True));
end;

procedure TTestRdxForRangeFix.Detector_TwoHeadsOnOneLine_NoHelp;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  Src := InUnit(['  for i := 10 to 1 do Foo(i); for j := 20 to 2 do Bar(j);']);
  Seen := DetectSource('rdx_forrange_', Src, fkReversedForRange, RunDetector);
  Assert.AreEqual<Integer>(1, Length(Seen), 'der Detektor meldet nur den vorderen');
  Fixed(Src, Seen[0].Line, Seen[0].Msg, False, O);
  Assert.IsFalse(O.Enabled);
  Assert.IsTrue(Pos(Format(R_FORRANGE_MANY, [2]), O.Reason) > 0, O.Reason);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxForRangeFix);

end.
