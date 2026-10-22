unit uTestRdxAlwaysTrueFix;

// Editorhilfe SCA150 BoolAlwaysTrue (uRdxAlwaysTrueFix): der Planer auf Text
// (erste Fixture, auch im FPC-Pruefstand) und - nur Delphi - der Einstieg
// der Tabelle (TRdxFixTable.FixFor via PlanFixIn/FixAllWith, Adapter
// PlanBoolAlwaysTrue) mit dem ECHTEN Detektor (uBoolAlwaysTrue) auf dem
// echten AST (zweite Fixture). Die Fixtures stehen
// in einer Routine 'Foo(const S: string)'; ihr Rumpf beginnt auf Zeile 6
// (BODY).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxAlwaysTrueFix = class
  public
    // ---- Umformung ----
    [Test] procedure SimpleThen_BecomesStatement;
    [Test] procedure ElseBranch_Dropped;
    [Test] procedure BeginEndBlock_Kept;
    [Test] procedure BlockWithElse_ThenBlockKept;
    [Test] procedure MirrorForm_BecomesStatement;
    [Test] procedure QualifiedArgument_BecomesStatement;
    [Test] procedure StringAtBranchEnd_Kept;
    [Test] procedure NestedIf_DanglingElseDropped;
    [Test] procedure CommentsOutsideOrInsideBranch_Kept;
    [Test] procedure AnonymousMethodArgument_BecomesStatement;
    // ---- Gegenproben ----
    [Test] procedure AlwaysFalse_NoHelp;
    [Test] procedure UnknownMessage_NoHelp;
    [Test] procedure MovedLineCommentOrString_NoHelp;
    [Test] procedure TwoOnLine_NoHelp;
    [Test] procedure ArgumentNotPlainName_NoHelp;
    [Test] procedure NotWholeIfCondition_NoHelp;
    [Test] procedure ConditionalExpression_NoHelp;
    [Test] procedure BranchNotSimple_NoHelp;
    [Test] procedure CommentInRemovedPart_NoHelp;
    [Test] procedure Directive_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxAlwaysTrueDetector = class
  public
    // ---- Einstieg der Tabelle (Adapter PlanBoolAlwaysTrue) ----
    [Test] procedure Adapter_OneEditWithoutBehaviorChange;
    [Test] procedure Adapter_StaleFinding_NoHelp;
    // ---- echter Detektor ----
    [Test] procedure Detector_ReportsLineAndForm;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_ElseAndBlock_BothFixed;
    [Test] procedure Detector_MirrorForm_RoundTrip;
    [Test] procedure Detector_CatalogExample_TrueFixedFalseKept;
    [Test] procedure Detector_FalseForm_NoHelp;
    [Test] procedure Detector_DecimalLiteral_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uBoolAlwaysTrue,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // TRdxFixTable.CaptionFor
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText, PlanFixIn
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxAlwaysTrueFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply, NewMap

const
  BODY = 6;   // erste Rumpfzeile von Wrap
  // Die Meldungen des Detektors (uBoolAlwaysTrue, MissingVar).
  GE_MSG = MSG_LEN_GE + ' (Length is never negative)';
  ZLE_MSG = MSG_ZERO_LE + ' (Length is never negative)';
  LT_MSG = MSG_LEN_LT + ' (Length is never negative)';
  ZGT_MSG = MSG_ZERO_GT + ' (Length is never negative)';

// ---- Helfer ----

// Eine Unit mit EINER Routine Foo(S); der Rumpf ab Zeile 6.
function Wrap(const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation',
    'procedure Foo(const S: string);', 'begin']) + #13#10 + Join(ABody)
    + #13#10 + Join(['end;', 'end.']);
end;

// Der Planer fuer Zeile ALine und Meldung AMsg: der neue Text, oder '' bei
// Ablehnung (AReason).
function PlanAt(const ASource: string; ALine: Integer; const AMsg: string;
  out AReason: string): string;
var
  Map : TRdxCodeMap;
  E   : TRdxEdit;
  Ok  : Boolean;
begin
  Result := '';
  AReason := '';
  Ok := False;
  Map := NewMap(ASource);
  try
    Ok := TRdxAlwaysTrueFix.ResolveIf(Map, ALine, AMsg, E, AReason);
  finally
    Map.Free;
  end;
  if Ok then
    Result := Apply(ASource, E);
end;

// Die Hilfe muss gelten (sonst scheitert der Test mit dem Grund).
function Applied(const ASource: string; ALine: Integer;
  const AMsg: string = GE_MSG): string;
var
  R : string;
begin
  Result := PlanAt(ASource, ALine, AMsg, R);
  Assert.IsTrue(Result <> '', R);
end;

procedure AssertRefused(const ASource: string; ALine: Integer;
  const AMsg, AReason: string);
var
  R : string;
begin
  Assert.AreEqual('', PlanAt(ASource, ALine, AMsg, R), 'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
end;

// Wie AssertRefused fuer eine Zeile im Rumpf von Wrap mit der Meldung der
// immer wahren Form 'Length(..) >= 0'.
procedure AssertLineRefused(const ALine, AReason: string);
begin
  AssertRefused(Wrap([ALine]), BODY, GE_MSG, AReason);
end;

// ---- Umformung ----

procedure TTestRdxAlwaysTrueFix.SimpleThen_BecomesStatement;
begin
  Assert.AreEqual(Wrap(['  DoStuff;']),
    Applied(Wrap(['  if Length(S) >= 0 then DoStuff;']), BODY));
  // In Klammern und in Grossbuchstaben.
  Assert.AreEqual(Wrap(['  DoStuff;']),
    Applied(Wrap(['  if (Length(S) >= 0) then DoStuff;']), BODY));
  Assert.AreEqual(Wrap(['  DoStuff;']),
    Applied(Wrap(['  IF LENGTH(S) >= 0 THEN DoStuff;']), BODY));
end;

procedure TTestRdxAlwaysTrueFix.ElseBranch_Dropped;
begin
  Assert.AreEqual(Wrap(['  A;']),
    Applied(Wrap(['  if Length(S) >= 0 then A else B;']), BODY));
  // Ueber Zeilen: der else-Zweig lief nie und geht mit.
  Assert.AreEqual(Wrap(['  A;']),
    Applied(Wrap(['  if Length(S) >= 0 then', '    A', '  else', '    B;']),
      BODY));
end;

procedure TTestRdxAlwaysTrueFix.BeginEndBlock_Kept;
begin
  // Der Block bleibt als Verbundanweisung stehen - gleiche Bedeutung.
  Assert.AreEqual(Wrap(['  begin', '    A;', '    B;', '  end;']),
    Applied(Wrap(['  if Length(S) >= 0 then', '  begin', '    A;', '    B;',
      '  end;']), BODY));
end;

procedure TTestRdxAlwaysTrueFix.BlockWithElse_ThenBlockKept;
begin
  Assert.AreEqual(Wrap(['  begin A; end;']),
    Applied(Wrap(['  if Length(S) >= 0 then begin A; end else begin B; end;']),
      BODY));
end;

procedure TTestRdxAlwaysTrueFix.MirrorForm_BecomesStatement;
begin
  Assert.AreEqual(Wrap(['  A;']),
    Applied(Wrap(['  if 0 <= Length(S) then A;']), BODY, ZLE_MSG));
end;

procedure TTestRdxAlwaysTrueFix.QualifiedArgument_BecomesStatement;
begin
  Assert.AreEqual(Wrap(['  A;']),
    Applied(Wrap(['  if Length(Self.FName) >= 0 then A;']), BODY));
  Assert.AreEqual(Wrap(['  A;']),
    Applied(Wrap(['  if Length(List.Items) >= 0 then A;']), BODY));
end;

procedure TTestRdxAlwaysTrueFix.StringAtBranchEnd_Kept;
begin
  // Der Token-Leser ueberspringt Strings - das Ende des Zweigs ist das
  // letzte Zeichen vor dem ';', auch ein Quote.
  Assert.AreEqual(Wrap(['  S := ''x;y'';']),
    Applied(Wrap(['  if Length(S) >= 0 then S := ''x;y'';']), BODY));
  Assert.AreEqual(Wrap(['  W(''a'');']),
    Applied(Wrap(['  if Length(S) >= 0 then W(''a'') else W(''b'');']), BODY));
end;

procedure TTestRdxAlwaysTrueFix.NestedIf_DanglingElseDropped;
begin
  // Das else gehoert zum inneren if (dem gemeldeten).
  Assert.AreEqual(Wrap(['  if A then X;']),
    Applied(Wrap(['  if A then if Length(S) >= 0 then X else Y;']), BODY));
  Assert.AreEqual(Wrap(['  if A then', '    Y', '  else X;']),
    Applied(Wrap(['  if A then', '    Y', '  else if Length(S) >= 0 then X;']),
      BODY + 2));
end;

procedure TTestRdxAlwaysTrueFix.CommentsOutsideOrInsideBranch_Kept;
begin
  // Hinter dem ';' und im Block bleibt ein Kommentar stehen.
  Assert.AreEqual(Wrap(['  DoStuff;   // always']),
    Applied(Wrap(['  if Length(S) >= 0 then DoStuff;   // always']), BODY));
  Assert.AreEqual(Wrap(['  begin', '    A; // keep', '  end;']),
    Applied(Wrap(['  if Length(S) >= 0 then', '  begin', '    A; // keep',
      '  end;']), BODY));
end;

procedure TTestRdxAlwaysTrueFix.AnonymousMethodArgument_BecomesStatement;
begin
  // In Klammern stoert weder ';' noch begin..end.
  Assert.AreEqual(Wrap(['  Run(procedure begin X; end);']),
    Applied(Wrap(['  if Length(S) >= 0 then Run(procedure begin X; end);']),
      BODY));
end;

// ---- Gegenproben ----

procedure TTestRdxAlwaysTrueFix.AlwaysFalse_NoHelp;
begin
  AssertRefused(Wrap(['  if Length(S) < 0 then A;']), BODY, LT_MSG,
    _(R_AT_FALSE));
  AssertRefused(Wrap(['  if 0 > Length(S) then A else B;']), BODY, ZGT_MSG,
    _(R_AT_FALSE));
end;

procedure TTestRdxAlwaysTrueFix.UnknownMessage_NoHelp;
begin
  AssertRefused(Wrap(['  if Length(S) >= 0 then A;']), BODY, 'always True',
    _(R_AT_FORM));
end;

procedure TTestRdxAlwaysTrueFix.MovedLineCommentOrString_NoHelp;
var
  Moved : string;
begin
  Moved := MsgMovedSuffix(_(R_AT_MOVED, [CODE_LEN_GE]));
  AssertRefused(Wrap(['  if Length(S) >= 0 then A;', '  B;']), BODY + 1,
    GE_MSG, Moved);
  AssertLineRefused('  // if Length(S) >= 0 then A;', Moved);
  AssertLineRefused('  W(''if Length(S) >= 0 then A'');', Moved);
  AssertLineRefused('  if X.Length(S) >= 0 then A;', Moved);
  // Die Meldung nennt die Spiegelform, die Zeile traegt die andere.
  AssertRefused(Wrap(['  if Length(S) >= 0 then A;']), BODY, ZLE_MSG,
    MsgMovedSuffix(_(R_AT_MOVED, [CODE_ZERO_LE])));
end;

procedure TTestRdxAlwaysTrueFix.TwoOnLine_NoHelp;
begin
  AssertLineRefused('  if Length(A) >= 0 then if Length(B) >= 0 then X;',
    _(R_AT_MANY, [CODE_LEN_GE]));
end;

procedure TTestRdxAlwaysTrueFix.ArgumentNotPlainName_NoHelp;
begin
  AssertLineRefused('  if Length(GetS()) >= 0 then A;', _(R_AT_ARG));
  AssertLineRefused('  if Length(S + T) >= 0 then A;', _(R_AT_ARG));
  AssertLineRefused('  if Length(''abc'') >= 0 then A;', _(R_AT_ARG));
  AssertLineRefused('  if Length(L[0]) >= 0 then A;', _(R_AT_ARG));
end;

procedure TTestRdxAlwaysTrueFix.NotWholeIfCondition_NoHelp;
begin
  AssertLineRefused('  if (Length(S) >= 0) and B then A;', _(R_AT_NOT_IF));
  AssertLineRefused('  if B and (Length(S) >= 0) then A;', _(R_AT_NOT_IF));
  AssertLineRefused('  while Length(S) >= 0 do A;', _(R_AT_NOT_IF));
  AssertLineRefused('  repeat A; until Length(S) >= 0;', _(R_AT_NOT_IF));
  AssertLineRefused('  B := Length(S) >= 0;', _(R_AT_NOT_IF));
  // Was der Detektor auch meldet, aber nicht immer wahr ist.
  AssertLineRefused('  if Length(S) >= 0.5 then A;', _(R_AT_NOT_IF));
  AssertLineRefused('  if Length(S) >= 0 + N then A;', _(R_AT_NOT_IF));
  AssertRefused(Wrap(['  if 1.0 <= Length(S) then A;']), BODY, ZLE_MSG,
    _(R_AT_NOT_IF));
end;

procedure TTestRdxAlwaysTrueFix.ConditionalExpression_NoHelp;
begin
  // Delphi 13: 'if' als bedingter Ausdruck - keine Anweisung.
  AssertLineRefused('  X := if Length(S) >= 0 then 1 else 2;', _(R_AT_EXPR));
end;

procedure TTestRdxAlwaysTrueFix.BranchNotSimple_NoHelp;
begin
  AssertLineRefused('  if Length(S) >= 0 then if B then X;',
    _(R_AT_BRANCH, ['then']));
  AssertLineRefused('  if Length(S) >= 0 then for I := 1 to 2 do X;',
    _(R_AT_BRANCH, ['then']));
  AssertLineRefused('  if Length(S) >= 0 then;', _(R_AT_BRANCH, ['then']));
  AssertLineRefused('  if Length(S) >= 0 then else X;',
    _(R_AT_BRANCH, ['then']));
  AssertLineRefused('  if Length(S) >= 0 then P := procedure begin X; end;',
    _(R_AT_BRANCH, ['then']));
  AssertLineRefused('  if Length(S) >= 0 then X else case K of 1: Y; end;',
    _(R_AT_BRANCH, ['else']));
  // Hinter dem Block folgt keine Anweisungsgrenze.
  AssertLineRefused('  if Length(S) >= 0 then begin A; end B;', _(R_AT_TAIL));
end;

procedure TTestRdxAlwaysTrueFix.CommentInRemovedPart_NoHelp;
begin
  AssertLineRefused('  if Length(S) {x} >= 0 then A;', _(R_AT_COMMENT));
  AssertLineRefused('  if Length(S) >= 0 then A {x} else B;', _(R_AT_COMMENT));
  AssertLineRefused('  if Length(S) >= 0 then A else { x } B;',
    _(R_AT_COMMENT));
  AssertRefused(Wrap(['  if Length(S) >= 0 then // c', '    A;']), BODY,
    GE_MSG, _(R_AT_COMMENT));
end;

procedure TTestRdxAlwaysTrueFix.Directive_NoHelp;
begin
  AssertRefused(Wrap(['  if Length(S) >= 0 then', '  {$IFDEF X}', '    A',
    '  {$ELSE}', '    B', '  {$ENDIF};']), BODY, GE_MSG, _(R_AT_DIRECTIVE));
  AssertLineRefused('  if Length(S) >= 0 then A; {$IFDEF X}',
    _(R_AT_DIRECTIVE));
end;

{$IFNDEF FPC}

{ ---- Einstieg der Tabelle und echter Detektor ---- }

// Die Funde der Art SCA150 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TBoolAlwaysTrueDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_bat_', ASource, fkBoolAlwaysTrue, RunDetector);
end;

// Dasselbe in der Form TDetectFunc (FixAllWith).
function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_bat_', ASource, AKind, RunDetector);
end;

// Die Hilfe fuer Zeile und Meldung ueber den Einstieg der Tabelle
// (PlanFixIn: TRdxFixTable.FixFor, Adapter PlanBoolAlwaysTrue).
function PlanVia(const ASource: string; ALine: Integer;
  const AMsg: string): TRdxFixOutcome;
var
  S : TSeen;
begin
  S := Default(TSeen);
  S.Line := ALine;
  S.Msg := AMsg;
  Result := PlanFixIn(ASource, 't.pas', fkBoolAlwaysTrue, S);
end;

// Die Hilfe fuer den ersten Fund des Detektors.
function PlanFirst(const ASource: string): TRdxFixOutcome;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet einen Fund');
  Result := PlanVia(ASource, Seen[0].Line, Seen[0].Msg);
end;

// Fund fuer Fund ueber die Tabelle, nach jeder Ersetzung neu gemeldet, bis
// der Detektor schweigt (FixAllWith).
function FixAll(const ASource: string): string;
begin
  Result := FixAllWith(ASource, fkBoolAlwaysTrue, DetectKind);
end;

procedure TTestRdxAlwaysTrueDetector.Adapter_OneEditWithoutBehaviorChange;
var
  O : TRdxFixOutcome;
begin
  O := PlanVia(Wrap(['  if Length(S) >= 0 then DoStuff;']), BODY, GE_MSG);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(1, Length(O.Edits), 'eine Ersetzung');
  Assert.AreEqual('if Length(S) >= 0 then DoStuff', O.Edits[0].Expected);
  Assert.AreEqual('DoStuff', O.Edits[0].NewText);
  Assert.AreEqual<Integer>(BODY, O.Edits[0].Span.StartLine);
  Assert.AreEqual<Integer>(3, O.Edits[0].Span.StartCol);
  // Tabellenzeile: bedeutungsgleich (Changes: False), Hinweis der Zeile,
  // Menuetext ohne Platzhalter.
  Assert.IsFalse(O.ChangesBehavior);
  Assert.IsTrue(Pos('else-Zweig', O.Hint) > 0, O.Hint);
  Assert.AreEqual(_('Remove the always-true condition'),
    TRdxFixTable.CaptionFor(fkBoolAlwaysTrue, O));
end;

procedure TTestRdxAlwaysTrueDetector.Adapter_StaleFinding_NoHelp;
var
  O : TRdxFixOutcome;
begin
  // Der Fund zeigt auf Zeile 7, dort steht kein Vergleich.
  O := PlanVia(Wrap(['  if Length(S) >= 0 then A;', '  B;']), BODY + 1, GE_MSG);
  Assert.IsFalse(O.Enabled, 'gesperrt');
  Assert.AreEqual(MsgMovedSuffix(_(R_AT_MOVED, [CODE_LEN_GE])), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

procedure TTestRdxAlwaysTrueDetector.Detector_ReportsLineAndForm;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(Wrap(['  B := 1;', '  if Length(S) >= 0 then DoStuff;']));
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(BODY + 1, Seen[0].Line, 'Zeile des Vergleichs');
  Assert.IsTrue(Pos(MSG_LEN_GE, Seen[0].Msg) > 0, Seen[0].Msg);
end;

procedure TTestRdxAlwaysTrueDetector.Detector_RoundTrip;
var
  Fixed : string;
begin
  Fixed := FixAll(Wrap(['  if Length(S) >= 0 then DoStuff;']));
  Assert.AreEqual(Wrap(['  DoStuff;']), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)), 'der Detektor schweigt');
end;

procedure TTestRdxAlwaysTrueDetector.Detector_ElseAndBlock_BothFixed;
var
  Src : string;
begin
  Src := Wrap(['  if Length(S) >= 0 then A else B;', '  if Length(S) >= 0 then',
    '  begin', '    C;', '  end;']);
  Assert.AreEqual<Integer>(2, Length(Detect(Src)), 'zwei Funde');
  Assert.AreEqual(Wrap(['  A;', '  begin', '    C;', '  end;']), FixAll(Src));
end;

procedure TTestRdxAlwaysTrueDetector.Detector_MirrorForm_RoundTrip;
begin
  Assert.AreEqual(Wrap(['  A;']),
    FixAll(Wrap(['  if 0 <= Length(S) then A else B;'])));
end;

procedure TTestRdxAlwaysTrueDetector.Detector_CatalogExample_TrueFixedFalseKept;
var
  Meta  : TRuleMeta;
  Src   : string;
  O     : TRdxFixOutcome;
  Fixed : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkBoolAlwaysTrue);
  Assert.IsTrue(Pos('Length(s) >= 0', Meta.BadExample) > 0, Meta.BadExample);
  Src := Join(['unit t;', 'interface', 'implementation',
    'procedure Foo(const s: string);', 'begin', CatalogText(Meta.BadExample),
    'end;', 'end.']);
  Assert.AreEqual<Integer>(2, Length(Detect(Src)), 'True- und False-Form');
  // Erst die immer wahre Form (der erste Fund) ...
  O := PlanFirst(Src);
  Assert.IsTrue(O.Enabled, O.Reason);
  Fixed := Apply(Src, O.Edits);
  Assert.IsTrue(Pos('DoStuff;   // <- always True', Fixed) > 0, Fixed);
  Assert.AreEqual<Integer>(0, Pos('if Length(s) >= 0', Fixed), Fixed);
  // ... die immer falsche bleibt (Entscheidung des Menschen).
  O := PlanFirst(Fixed);
  Assert.IsFalse(O.Enabled, 'keine Hilfe fuer die False-Form');
  Assert.AreEqual(_(R_AT_FALSE), O.Reason);
end;

procedure TTestRdxAlwaysTrueDetector.Detector_FalseForm_NoHelp;
var
  O : TRdxFixOutcome;
begin
  O := PlanFirst(Wrap(['  if 0 > Length(S) then A;']));
  Assert.IsFalse(O.Enabled);
  Assert.AreEqual(_(R_AT_FALSE), O.Reason);
end;

procedure TTestRdxAlwaysTrueDetector.Detector_DecimalLiteral_NoHelp;
var
  O : TRdxFixOutcome;
begin
  // Der Detektor meldet 'Length(S) >= 0.5' ('\b' vor dem Punkt) - nicht
  // immer wahr; die Hilfe lehnt ab.
  O := PlanFirst(Wrap(['  if Length(S) >= 0.5 then A;']));
  Assert.IsFalse(O.Enabled);
  Assert.AreEqual(_(R_AT_NOT_IF), O.Reason);
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxAlwaysTrueFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxAlwaysTrueDetector);
  {$ENDIF}

end.
