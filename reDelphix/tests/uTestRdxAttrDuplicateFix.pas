unit uTestRdxAttrDuplicateFix;

// Editorhilfe SCA180 AttributeDuplicate (uRdxAttrDuplicateFix), nur Delphi
// (reDelphix.Test): der Planer auf Text, der Adapter in der Form der Tabelle
// und der ECHTE Detektor (uAttributeDuplicate). Der Fund steht auf der Zeile
// der Dublette, die Meldung nennt Name+Argumente und die erste Zeile. Die
// Fixtures stehen in einer Klasse (Zeile 6 ist die erste Zeile des Rumpfs).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxAttrDuplicateFix = class
  public
    // ---- Planer auf Text ----
    [Test] procedure SeparateLine_DeletesWholeLine;
    [Test] procedure SameLine_DeletesGroup;
    [Test] procedure EqualArguments_DeleteSecond;
    [Test] procedure DifferentArguments_NoHelp;
    [Test] procedure ChainOfAttributes_DeletesLastCopy;
    [Test] procedure BlankLineBetween_StillDeletes;
    [Test] procedure CodeCommentOrDirectiveBetween_NoHelp;
    [Test] procedure TextAfterAttribute_NoHelp;
    [Test] procedure AttributeWithTarget_NoHelp;
    [Test] procedure MultiLineOrBracketInString_NoHelp;
    [Test] procedure MovedLineOrBadMessage_NoHelp;
    [Test] procedure LastLineOfFile_NoHelp;
    [Test] procedure CommentedAttribute_NoHelp;
    [Test] procedure GroupAmongOthers_DeletesOnlyTheGroup;
    // ---- Adapter der Tabelle ----
    [Test] procedure Adapter_EnabledAndStale;
    // ---- echter Detektor ----
    [Test] procedure Detector_RoundTrip_SeparateLines;
    [Test] procedure Detector_RoundTrip_ArgumentsKept;
    [Test] procedure Detector_RoundTrip_SameLineTriple;
    [Test] procedure Detector_CatalogExample;
    [Test] procedure Detector_DifferentArguments_Silent;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog,
  uAttributeDuplicate,
  uRdxBufferMath, uRdxCodeMap, uRdxRecipeRunner, uRdxAttrDuplicateFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText
  uTestRdxTextKit;       // Join, Apply

const
  FIRST = 6;   // erste Zeile des Rumpfs in Wrap

// ---- Helfer ----

// Eine Klasse; der Rumpf beginnt auf Zeile 6.
function Wrap(const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'type', '  TFoo = class', '  public'])
    + #13#10 + Join(ABody) + #13#10 + Join(['  end;', 'implementation', 'end.']);
end;

// Die Meldung des Detektors (Name klein + Argumente, erste Zeile).
function Msg(const AKey: string; AFirstLine: Integer): string;
begin
  Result := 'Duplicate attribute [' + AKey + '] (first seen at line '
    + IntToStr(AFirstLine) + '). Identical attribute applied twice has no '
    + 'effect and is usually a copy-paste artefact.';
end;

function Moved: string;
begin
  Result := MsgMovedSuffix(_(R_DUP_MOVED));
end;

// Der Planer fuer Zeile ALine: der neue Text, oder '' bei Ablehnung
// (AReason).
function Plan(const ASource: string; ALine: Integer; const AMessage: string;
  out AReason: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
  Ok  : Boolean;
begin
  Result := '';
  AReason := '';
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    try
      Ok := TRdxAttrDuplicateFix.DeleteDuplicate(Map, ALine, AMessage, E,
        AReason);
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
  if Ok then
    Result := Apply(ASource, E);
end;

// Wie Plan, aber die Hilfe muss gelten (sonst scheitert der Test mit dem
// Grund).
function Applied(const ASource: string; ALine: Integer;
  const AMessage: string): string;
var
  R : string;
begin
  Result := Plan(ASource, ALine, AMessage, R);
  Assert.IsTrue(Result <> '', R);
end;

procedure AssertRefused(const ASource: string; ALine: Integer;
  const AMessage, AReason: string);
var
  R : string;
begin
  Assert.AreEqual('', Plan(ASource, ALine, AMessage, R), 'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
end;

// Die Funde der Art SCA180 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TAttributeDuplicateDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_attrdup_', ASource, fkAttributeDuplicate,
    RunDetector);
end;

// Die Hilfe fuer den ERSTEN Fund des Detektors, so wie die Tabelle sie ruft
// (Adapter), angewendet wie der Editor.
function FixOnce(const ASource: string): string;
var
  Seen : TArray<TSeen>;
  SL   : TStringList;
  F    : TLeakFinding;
  O    : TRdxFixOutcome;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet');
  SL := TStringList.Create;
  F := TLeakFinding.New('t.pas', '', Seen[0].Line, Seen[0].Msg,
    fkAttributeDuplicate);
  try
    SL.Text := ASource;
    O := PlanAttrDuplicate(nil, SL, F, nil);
  finally
    F.Free;
    SL.Free;
  end;
  Assert.IsTrue(O.Enabled, O.Reason);
  Result := Apply(ASource, O.Edits);
end;

// ---- Planer auf Text ----

procedure TTestRdxAttrDuplicateFix.SeparateLine_DeletesWholeLine;
begin
  Assert.AreEqual(Wrap(['  [Test]', '  procedure Foo;']),
    Applied(Wrap(['  [Test]', '  [Test]', '  procedure Foo;']), FIRST + 1,
      Msg('test', FIRST)));
end;

procedure TTestRdxAttrDuplicateFix.SameLine_DeletesGroup;
begin
  Assert.AreEqual(Wrap(['  [Inject]', '  FFoo: IFoo;']),
    Applied(Wrap(['  [Inject][Inject]', '  FFoo: IFoo;']), FIRST,
      Msg('inject', FIRST)));
  Assert.AreEqual(Wrap(['  [Inject]', '  FFoo: IFoo;']),
    Applied(Wrap(['  [Inject] [Inject]', '  FFoo: IFoo;']), FIRST,
      Msg('inject', FIRST)));
  // Leerzeichen hinter der Dublette gehen mit.
  Assert.AreEqual(Wrap(['  [Inject]', '  FFoo: IFoo;']),
    Applied(Wrap(['  [Inject][Inject]   ', '  FFoo: IFoo;']), FIRST,
      Msg('inject', FIRST)));
end;

procedure TTestRdxAttrDuplicateFix.EqualArguments_DeleteSecond;
const
  KEY = 'category(''smoke'')';
begin
  // Der Name wird ohne Beachtung der Schreibweise verglichen, die Argumente
  // genau; geloescht wird die spaetere Zeile.
  Assert.AreEqual(Wrap(['  [Category(''smoke'')]', '  procedure Foo;']),
    Applied(Wrap(['  [Category(''smoke'')]', '  [category(''smoke'')]',
      '  procedure Foo;']), FIRST + 1, Msg(KEY, FIRST)));
end;

procedure TTestRdxAttrDuplicateFix.DifferentArguments_NoHelp;
const
  KEY = 'category(''b'')';
begin
  // Der Detektor meldet das nie; steht die Meldung trotzdem da, traegt die
  // erste Zeile die Gruppe nicht.
  AssertRefused(Wrap(['  [Category(''a'')]', '  [Category(''b'')]',
    '  procedure Foo;']), FIRST + 1, Msg(KEY, FIRST), Moved);
  AssertRefused(Wrap(['  [Category(''a'')][Category(''b'')]',
    '  procedure Foo;']), FIRST, Msg(KEY, FIRST), Moved);
  // Die Argumente sind gross/klein genau.
  AssertRefused(Wrap(['  [Category(''A'')]', '  [Category(''a'')]',
    '  procedure Foo;']), FIRST + 1, Msg('category(''a'')', FIRST), Moved);
end;

procedure TTestRdxAttrDuplicateFix.ChainOfAttributes_DeletesLastCopy;
begin
  Assert.AreEqual(Wrap(['  [A]', '  [B]', '  procedure Foo;']),
    Applied(Wrap(['  [A]', '  [B]', '  [A]', '  procedure Foo;']), FIRST + 2,
      Msg('a', FIRST)));
end;

procedure TTestRdxAttrDuplicateFix.BlankLineBetween_StillDeletes;
begin
  Assert.AreEqual(Wrap(['  [A]', '', '  procedure Foo;']),
    Applied(Wrap(['  [A]', '', '  [A]', '  procedure Foo;']), FIRST + 2,
      Msg('a', FIRST)));
end;

procedure TTestRdxAttrDuplicateFix.CodeCommentOrDirectiveBetween_NoHelp;
var
  Between : string;
begin
  Between := _(R_DUP_BETWEEN);
  AssertRefused(Wrap(['  [A]', '  // erst A', '  [A]', '  procedure Foo;']),
    FIRST + 2, Msg('a', FIRST), Between);
  AssertRefused(Wrap(['  [A]', '  {$IFDEF X}', '  [A]', '  procedure Foo;']),
    FIRST + 2, Msg('a', FIRST), Between);
  AssertRefused(Wrap(['  [A]', '  FBar: Integer;', '  [A]',
    '  procedure Foo;']), FIRST + 2, Msg('a', FIRST), Between);
end;

procedure TTestRdxAttrDuplicateFix.TextAfterAttribute_NoHelp;
begin
  // Hinter der Dublette: Kommentar bzw. das Element selbst - die Hilfe
  // loescht ganze Zeilen oder reine Gruppen.
  AssertRefused(Wrap(['  [A]', '  [A] // zweite', '  procedure Foo;']),
    FIRST + 1, Msg('a', FIRST), _(R_DUP_TAIL));
  AssertRefused(Wrap(['  [A]', '  [A] procedure Foo;']), FIRST + 1,
    Msg('a', FIRST), _(R_DUP_TAIL));
  // Hinter dem ersten Treffer.
  AssertRefused(Wrap(['  [A] {c}', '  [A]', '  procedure Foo;']), FIRST + 1,
    Msg('a', FIRST), _(R_DUP_TAIL));
end;

procedure TTestRdxAttrDuplicateFix.AttributeWithTarget_NoHelp;
begin
  AssertRefused(Wrap(['  [Result: Foo]', '  [Result: Foo]',
    '  function X: Integer;']), FIRST + 1, Msg('result: Foo', FIRST),
    _(R_DUP_TARGET));
  // Ein ':' in den Argumenten ist kein Ziel.
  Assert.AreEqual(Wrap(['  [Fmt(''a:b'')]', '  procedure Foo;']),
    Applied(Wrap(['  [Fmt(''a:b'')]', '  [Fmt(''a:b'')]', '  procedure Foo;']),
      FIRST + 1, Msg('fmt(''a:b'')', FIRST)));
end;

procedure TTestRdxAttrDuplicateFix.MultiLineOrBracketInString_NoHelp;
begin
  AssertRefused(Wrap(['  [A]', '  [Category(', '    ''x'')]',
    '  procedure Foo;']), FIRST + 1, Msg('a', FIRST), _(R_DUP_COMPLEX));
  // Ein ']' im String liest der Detektor anders.
  AssertRefused(Wrap(['  [Category(''a]b'')]', '  [Category(''a]b'')]',
    '  procedure Foo;']), FIRST + 1, Msg('category(''a]b'')', FIRST),
    _(R_DUP_COMPLEX));
end;

procedure TTestRdxAttrDuplicateFix.MovedLineOrBadMessage_NoHelp;
var
  Src : string;
begin
  Src := Wrap(['  [Test]', '  [Test]', '  procedure Foo;']);
  // Zeile 8 ist der Routinenkopf, 99 gibt es nicht, die erste Zeile liegt
  // hinter der Dublette.
  AssertRefused(Src, FIRST + 2, Msg('test', FIRST), Moved);
  AssertRefused(Src, 99, Msg('test', FIRST), Moved);
  AssertRefused(Src, FIRST + 1, Msg('test', FIRST + 3), Moved);
  // Der Schluessel stimmt nicht (anderer Name).
  AssertRefused(Src, FIRST + 1, Msg('slow', FIRST), Moved);
  AssertRefused(Src, FIRST + 1, 'something else', _(R_DUP_MSG));
end;

procedure TTestRdxAttrDuplicateFix.LastLineOfFile_NoHelp;
begin
  AssertRefused(Join(['  [A]', '  [A]']), 2, Msg('a', 1), _(R_DUP_EOF));
end;

procedure TTestRdxAttrDuplicateFix.CommentedAttribute_NoHelp;
begin
  // Im Block-Kommentar und im Zeilenkommentar: kein Code.
  AssertRefused(Wrap(['  {', '  [Test]', '  [Test]', '  }',
    '  procedure Foo;']), FIRST + 2, Msg('test', FIRST + 1), Moved);
  AssertRefused(Wrap(['  // [Test]', '  // [Test]', '  procedure Foo;']),
    FIRST + 1, Msg('test', FIRST), Moved);
end;

procedure TTestRdxAttrDuplicateFix.GroupAmongOthers_DeletesOnlyTheGroup;
begin
  // Die Dublette steht vorn: Gruppe samt dem Leerraum dahinter.
  Assert.AreEqual(Wrap(['  [Test]', '  [Slow]', '  procedure Foo;']),
    Applied(Wrap(['  [Test]', '  [Test][Slow]', '  procedure Foo;']),
      FIRST + 1, Msg('test', FIRST)));
  // Die Dublette steht hinten, ein anderes Attribut dazwischen.
  Assert.AreEqual(Wrap(['  [A][B]', '  procedure Foo;']),
    Applied(Wrap(['  [A][B][A]', '  procedure Foo;']), FIRST,
      Msg('a', FIRST)));
end;

// ---- Adapter der Tabelle ----

procedure TTestRdxAttrDuplicateFix.Adapter_EnabledAndStale;
var
  SL      : TStringList;
  F, Old  : TLeakFinding;
  O, S    : TRdxFixOutcome;
begin
  SL := TStringList.Create;
  F := TLeakFinding.New('t.pas', '', FIRST + 1, Msg('test', FIRST),
    fkAttributeDuplicate);
  // Der Fund zeigt auf den Routinenkopf, dort steht keine Attributzeile.
  Old := TLeakFinding.New('t.pas', '', FIRST + 2, Msg('test', FIRST),
    fkAttributeDuplicate);
  try
    SL.Text := Wrap(['  [Test]', '  [Test]', '  procedure Foo;']);
    O := PlanAttrDuplicate(nil, SL, F, nil);
    S := PlanAttrDuplicate(nil, SL, Old, nil);
  finally
    Old.Free;
    F.Free;
    SL.Free;
  end;
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(0, O.Variant, 'Hauptweg ist Variant 0');
  Assert.IsFalse(O.ChangesBehavior, 'ohne Kennzeichnung');
  Assert.AreEqual<Integer>(1, Length(O.Edits), 'eine Ersetzung');
  Assert.AreEqual<Integer>(FIRST + 1, O.Edits[0].Span.StartLine, 'die Dublette');
  Assert.IsFalse(S.Enabled, 'gesperrt');
  Assert.AreEqual(Moved, S.Reason);
  Assert.AreEqual<Integer>(0, Length(S.Edits), 'keine Ersetzung');
end;

// ---- echter Detektor ----

procedure TTestRdxAttrDuplicateFix.Detector_RoundTrip_SeparateLines;
var
  Src, After : string;
begin
  Src := Wrap(['  [Test]', '  [Test]', '  procedure Foo;']);
  Assert.AreEqual<Integer>(1, Length(Detect(Src)), 'der Detektor meldet');
  After := FixOnce(Src);
  Assert.AreEqual(Wrap(['  [Test]', '  procedure Foo;']), After);
  Assert.AreEqual<Integer>(0, Length(Detect(After)), 'der Detektor schweigt danach');
end;

procedure TTestRdxAttrDuplicateFix.Detector_RoundTrip_ArgumentsKept;
var
  Src, After : string;
begin
  Src := Wrap(['  [Category(''smoke'')]', '  [Category(''smoke'')]',
    '  [Category(''slow'')]', '  procedure Foo;']);
  After := FixOnce(Src);
  Assert.AreEqual(Wrap(['  [Category(''smoke'')]', '  [Category(''slow'')]',
    '  procedure Foo;']), After);
  Assert.AreEqual<Integer>(0, Length(Detect(After)), 'der Detektor schweigt danach');
end;

procedure TTestRdxAttrDuplicateFix.Detector_RoundTrip_SameLineTriple;
var
  Src, After : string;
begin
  Src := Wrap(['  [Inject][Inject][Inject]', '  FFoo: IFoo;']);
  Assert.AreEqual<Integer>(2, Length(Detect(Src)), 'zwei Dubletten');
  After := FixOnce(FixOnce(Src));
  Assert.AreEqual(Wrap(['  [Inject]', '  FFoo: IFoo;']), After);
  Assert.AreEqual<Integer>(0, Length(Detect(After)), 'der Detektor schweigt danach');
end;

procedure TTestRdxAttrDuplicateFix.Detector_CatalogExample;
var
  Meta       : TRuleMeta;
  Src, After : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkAttributeDuplicate);
  Src := Join(['unit t;', 'interface', 'implementation',
    CatalogText(Meta.BadExample), 'end.']);
  Assert.AreEqual<Integer>(1, Length(Detect(Src)), 'der Detektor meldet das Beispiel');
  After := FixOnce(Src);
  // Danach steht das gute Beispiel des Katalogs da.
  Assert.AreEqual(Join(['unit t;', 'interface', 'implementation',
    CatalogText(Meta.GoodExample), 'end.']), After);
  Assert.AreEqual<Integer>(0, Length(Detect(After)), 'der Detektor schweigt danach');
end;

procedure TTestRdxAttrDuplicateFix.Detector_DifferentArguments_Silent;
begin
  // Verschiedene Argumente sind keine Dubletten: kein Fund, keine Hilfe.
  Assert.AreEqual<Integer>(0, Length(Detect(Wrap(['  [Category(''a'')]',
    '  [Category(''b'')]', '  procedure Foo;']))), 'kein Fund');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxAttrDuplicateFix);

end.
