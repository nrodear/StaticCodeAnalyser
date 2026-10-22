unit uTestRdxConsecutiveSectionFix;

// Editorhilfe SCA079 ConsecutiveSection (uRdxConsecutiveSectionFix): der
// Planer auf Text (erste Fixture, FPC-tauglich) und der ECHTE Detektor
// (uConsecutiveSection) auf dem echten AST ueber den Einstieg der Tabelle
// (TRdxFixTable.FixFor via PlanFixIn/FixAllWith, Adapter
// PlanConsecutiveSection - er setzt Name auch bei Ablehnung; zweite
// Fixture, nur Delphi). InIntf legt die Zeilen in den interface-Teil; die
// erste ist Zeile 3.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxConsecutiveSectionFix = class
  public
    // ---- Umformung ----
    [Test] procedure AloneKeyword_LineDeleted;
    [Test] procedure KeywordWithDeclaration_Reindented;
    [Test] procedure VarSectionsOfRoutine_Merged;
    [Test] procedure FirstSectionOnOwnLines_IndentTaken;
    [Test] procedure ClassSections_Merged;
    [Test] procedure DeclarationsWithParensAndTypes_Merged;
    [Test] procedure EmptyFirstSection_Merged;
    [Test] procedure ClassHeadBeforeFirstSection_Merged;
    // ---- Gegenproben ----
    [Test] procedure TypeSection_NoHelp;
    [Test] procedure NoKindInMessage_NoHelp;
    [Test] procedure MovedLine_NoHelp;
    [Test] procedure InlineDeclarations_NoHelp;
    [Test] procedure VisibilityBetween_NoHelp;
    [Test] procedure ClassVarOrThreadvar_NoHelp;
    [Test] procedure RoutineOrRecordBetween_NoHelp;
    [Test] procedure Directive_NoHelp;
    [Test] procedure Comment_NoHelp;
    [Test] procedure NoDeclaration_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxConsecutiveSectionDetector = class
  public
    [Test] procedure Detector_ReportsSecondKeyword;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_ThreeSections_AllMerged;
    [Test] procedure Detector_CatalogExample_Fixed;
    [Test] procedure Detector_InlineVars_NoHelp;
    [Test] procedure Detector_VisibilityBetween_NoHelp;
    [Test] procedure Table_StaleFinding_NoHelp;
    [Test] procedure Table_NameAndHint;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uConsecutiveSection,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText, PlanFixIn,
                         // FixAllWith
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxConsecutiveSectionFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply, NewMap

// ---- Helfer ----

// Die Zeilen im interface-Teil einer Unit; die erste ist Zeile 3.
function InIntf(const ALines: array of string): string;
begin
  Result := Join(['unit t;', 'interface']) + #13#10 + Join(ALines) + #13#10
    + Join(['implementation', 'end.']);
end;

// Die Meldung des Detektors fuer die Art AWord.
function MessageOf(const AWord: string): string;
begin
  Result := Format('Consecutive `%s` section - merge with the previous %s '
    + 'block (one section keyword should declare all of them).',
    [AWord, AWord]);
end;

// Der Planer fuer Zeile ALine mit der Meldung AMessage: der neue Text, oder
// '' bei Ablehnung (AReason).
function PlanMsg(const ASource: string; ALine: Integer;
  const AMessage: string; out AReason: string): string;
var
  Map : TRdxCodeMap;
  E   : TRdxEdit;
  Ok  : Boolean;
begin
  Result := '';
  AReason := '';
  Map := NewMap(ASource);
  try
    Ok := TRdxConsecutiveSectionFix.Merge(Map, ALine, AMessage, E, AReason);
  finally
    Map.Free;
  end;
  if Ok then
    Result := Apply(ASource, E);
end;

// Die Hilfe muss gelten (sonst scheitert der Test mit dem Grund).
function Fix(const ASource: string; ALine: Integer;
  const AWord: string): string;
var
  R : string;
begin
  Result := PlanMsg(ASource, ALine, MessageOf(AWord), R);
  Assert.IsTrue(Result <> '', R);
end;

procedure AssertRefused(const ASource: string; ALine: Integer;
  const AWord, AReason: string);
var
  R : string;
begin
  Assert.AreEqual('', PlanMsg(ASource, ALine, MessageOf(AWord), R),
    'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
end;

// ---- Umformung ----

procedure TTestRdxConsecutiveSectionFix.AloneKeyword_LineDeleted;
begin
  Assert.AreEqual(InIntf(['const', '  A = 1;', '  B = 2;']),
    Fix(InIntf(['const', '  A = 1;', 'const', '  B = 2;']), 5, 'const'));
  // Ein Kommentar hinter der letzten Deklaration des ersten Abschnitts
  // bleibt stehen - er steht nicht zwischen den Abschnitten.
  Assert.AreEqual(InIntf(['const', '  A = 1; // eins', '  B = 2;']),
    Fix(InIntf(['const', '  A = 1; // eins', 'const', '  B = 2;']), 5,
      'const'));
end;

procedure TTestRdxConsecutiveSectionFix.KeywordWithDeclaration_Reindented;
begin
  // Das Beispiel des Katalogs: B rueckt auf die Spalte von A.
  Assert.AreEqual(InIntf(['const A = 1;', '      B = 2;']),
    Fix(InIntf(['const A = 1;', 'const B = 2;']), 4, 'const'));
end;

procedure TTestRdxConsecutiveSectionFix.VarSectionsOfRoutine_Merged;
var
  Src : string;
begin
  // Der Deklarationsteil einer Routine - vor ihrem begin.
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    'var', '  A: Integer;', 'var', '  B: string;', 'begin', 'end;', 'end.']);
  Assert.AreEqual(Join(['unit t;', 'interface', 'implementation',
    'procedure Foo;', 'var', '  A: Integer;', '  B: string;', 'begin', 'end;',
    'end.']), Fix(Src, 7, 'var'));
end;

procedure TTestRdxConsecutiveSectionFix.FirstSectionOnOwnLines_IndentTaken;
begin
  Assert.AreEqual(InIntf(['var', '  A: Integer;', '  B: string;']),
    Fix(InIntf(['var', '  A: Integer;', 'var B: string;']), 5, 'var'));
end;

procedure TTestRdxConsecutiveSectionFix.ClassSections_Merged;
begin
  // Zwei const-Abschnitte unter derselben Sichtbarkeit.
  Assert.AreEqual(InIntf(['type', '  TFoo = class', '  private', '    const',
    '      A = 1;', '      B = 2;', '  end;']),
    Fix(InIntf(['type', '  TFoo = class', '  private', '    const',
      '      A = 1;', '    const', '      B = 2;', '  end;']), 8, 'const'));
end;

procedure TTestRdxConsecutiveSectionFix.DeclarationsWithParensAndTypes_Merged;
begin
  // Prozedurtypen (auch mit 'const' in der Parameterliste), 'of object',
  // eine Metaklasse und ein Wert in Klammern sind Deklarationen.
  Assert.AreEqual(InIntf(['var', '  F: procedure(const A: Integer);',
    '  H: procedure of object;', '  C: class of TObject;',
    '  P: TPoint = (X: 1; Y: 2);', '  B: Integer;']),
    Fix(InIntf(['var', '  F: procedure(const A: Integer);',
      '  H: procedure of object;', '  C: class of TObject;',
      '  P: TPoint = (X: 1; Y: 2);', 'var', '  B: Integer;']), 8, 'var'));
end;

procedure TTestRdxConsecutiveSectionFix.EmptyFirstSection_Merged;
begin
  Assert.AreEqual(InIntf(['var', '  A: Integer;']),
    Fix(InIntf(['var', 'var', '  A: Integer;']), 4, 'var'));
end;

procedure TTestRdxConsecutiveSectionFix.ClassHeadBeforeFirstSection_Merged;
begin
  // Das 'class' des Klassenkopfs ist kein 'class const'.
  Assert.AreEqual(InIntf(['type', '  TFoo = class', '  const A = 1;',
    '        B = 2;', '  end;']),
    Fix(InIntf(['type', '  TFoo = class', '  const A = 1;', '  const B = 2;',
      '  end;']), 6, 'const'));
end;

// ---- Gegenproben ----

procedure TTestRdxConsecutiveSectionFix.TypeSection_NoHelp;
begin
  AssertRefused(InIntf(['type', '  TA = Integer;', 'type', '  TB = Integer;']),
    5, 'type', _(R_CS_KIND, ['type']));
end;

procedure TTestRdxConsecutiveSectionFix.NoKindInMessage_NoHelp;
var
  R : string;
begin
  Assert.AreEqual('', PlanMsg(InIntf(['const', '  A = 1;', 'const',
    '  B = 2;']), 5, 'Consecutive section', R));
  Assert.AreEqual(_(R_CS_MSG), R);
end;

procedure TTestRdxConsecutiveSectionFix.MovedLine_NoHelp;
var
  Src, Moved : string;
begin
  Src := InIntf(['const', '  A = 1;', 'const', '  B = 2;']);
  Moved := MsgMovedSuffix(_(R_CS_MOVED, ['const']));
  AssertRefused(Src, 4, 'const', Moved);
  AssertRefused(Src, 99, 'const', Moved);
  // Die Meldung nennt eine andere Art als die Zeile.
  AssertRefused(Src, 5, 'var', MsgMovedSuffix(_(R_CS_MOVED, ['var'])));
  // Das Wort steht nur im Kommentar.
  AssertRefused(InIntf(['const', '  A = 1;', '// const', '  B = 2;']), 5,
    'const', Moved);
end;

procedure TTestRdxConsecutiveSectionFix.InlineDeclarations_NoHelp;
begin
  // Zwei Inline-Deklarationen ohne ':=' meldet der Detektor auch - sie sind
  // Anweisungen, Streichen braeche den Compiler.
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'procedure Foo;', 'begin', '  var A: Integer;', '  X := 1;',
    '  var B: Integer;', 'end;', 'end.']), 8, 'var', _(R_CS_INLINE));
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'initialization', '  var A: Integer;', '  var B: Integer;', 'end.']), 6,
    'var', _(R_CS_INLINE));
end;

procedure TTestRdxConsecutiveSectionFix.VisibilityBetween_NoHelp;
begin
  AssertRefused(InIntf(['type', '  TFoo = class', '  private',
    '    const A = 1;', '  public', '    const B = 2;', '  end;']), 8, 'const',
    _(R_CS_BETWEEN, ['public']));
end;

procedure TTestRdxConsecutiveSectionFix.ClassVarOrThreadvar_NoHelp;
begin
  // 'class var' dazwischen: C wuerde eine Klassenvariable.
  AssertRefused(InIntf(['type', '  TFoo = class', '  var', '    A: Integer;',
    '  class var', '    B: Integer;', '  var', '    C: Integer;', '  end;']),
    9, 'var', _(R_CS_CLASS_SECTION, ['var']));
  AssertRefused(InIntf(['var', '  A: Integer;', 'threadvar', '  T: Integer;',
    'var', '  B: Integer;']), 7, 'var', _(R_CS_BETWEEN, ['threadvar']));
  AssertRefused(InIntf(['const', '  A = 1;', 'resourcestring',
    '  S = ''x'';', 'const', '  B = 2;']), 7, 'const',
    _(R_CS_BETWEEN, ['resourcestring']));
end;

procedure TTestRdxConsecutiveSectionFix.RoutineOrRecordBetween_NoHelp;
begin
  AssertRefused(InIntf(['var', '  A: Integer;', 'procedure Foo;', 'var',
    '  B: Integer;']), 6, 'var', _(R_CS_BETWEEN, ['procedure']));
  AssertRefused(InIntf(['var', '  R: record A: Integer; end;', 'var',
    '  B: Integer;']), 5, 'var', _(R_CS_BETWEEN, ['end']));
end;

procedure TTestRdxConsecutiveSectionFix.Directive_NoHelp;
begin
  AssertRefused(InIntf(['const', '  A = 1;', '{$IFDEF X}', 'const', '  B = 2;',
    '{$ENDIF}']), 6, 'const', _(R_CS_DIRECTIVE));
end;

procedure TTestRdxConsecutiveSectionFix.Comment_NoHelp;
begin
  // Zwischen den Abschnitten, hinter und vor dem Schluesselwort.
  AssertRefused(InIntf(['const', '  A = 1;', '// Fehlertexte', 'const',
    '  B = 2;']), 6, 'const', _(R_CS_COMMENT));
  AssertRefused(InIntf(['const', '  A = 1;', 'const // Fehlertexte',
    '  B = 2;']), 5, 'const', _(R_CS_COMMENT));
  AssertRefused(InIntf(['const', '  A = 1;', '{ x } const', '  B = 2;']), 5,
    'const', _(R_CS_COMMENT));
end;

procedure TTestRdxConsecutiveSectionFix.NoDeclaration_NoHelp;
begin
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'procedure Foo;', 'const', '  A = 1;', 'const', 'begin', 'end;', 'end.']),
    7, 'const', _(R_CS_NO_DECL));
end;

{$IFNDEF FPC}

{ ---- Detektor ---- }

// Die Funde der Art SCA079 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TConsecutiveSectionDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_sec_', ASource, fkConsecutiveSection,
    RunDetector);
end;

// Detect in der Form TDetectFunc (FixAllWith).
function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_sec_', ASource, AKind, RunDetector);
end;

// Die Hilfe fuer einen Fund ueber den Einstieg der Tabelle (PlanFixIn:
// TRdxFixTable.FixFor, Adapter PlanConsecutiveSection).
function PlanSeen(const ASource: string; const ASeen: TSeen): TRdxFixOutcome;
begin
  Result := PlanFixIn(ASource, 't.pas', fkConsecutiveSection, ASeen);
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt (FixAllWith: ueber den Einstieg der Tabelle).
function FixAll(const ASource: string): string;
begin
  Result := FixAllWith(ASource, fkConsecutiveSection, DetectKind);
end;

// Die Hilfe fuer den ersten Fund des Detektors.
function PlanFirst(const ASource: string): TRdxFixOutcome;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet');
  Result := PlanSeen(ASource, Seen[0]);
end;

procedure TTestRdxConsecutiveSectionDetector.Detector_ReportsSecondKeyword;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(InIntf(['var', '  A: Integer;', 'var', '  B: Integer;']));
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(5, Seen[0].Line, 'Zeile des zweiten var');
  Assert.AreEqual('var', LowerCase(QuotedText(Seen[0].Msg, '`')), 'Art');
end;

procedure TTestRdxConsecutiveSectionDetector.Detector_RoundTrip;
var
  Fixed : string;
begin
  Fixed := FixAll(InIntf(['const', '  A = 1;', 'const', '  B = 2;']));
  Assert.AreEqual(InIntf(['const', '  A = 1;', '  B = 2;']), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)), 'der Detektor schweigt');
end;

procedure TTestRdxConsecutiveSectionDetector.Detector_ThreeSections_AllMerged;
var
  Src : string;
begin
  Src := InIntf(['var', '  A: Integer;', 'var', '  B: Integer;', 'var',
    '  C: Integer;']);
  Assert.AreEqual<Integer>(2, Length(Detect(Src)), 'zwei Funde');
  Assert.AreEqual(InIntf(['var', '  A: Integer;', '  B: Integer;',
    '  C: Integer;']), FixAll(Src));
end;

procedure TTestRdxConsecutiveSectionDetector.Detector_CatalogExample_Fixed;
var
  Meta  : TRuleMeta;
  Fixed : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkConsecutiveSection);
  Assert.IsTrue(Pos('const B', Meta.BadExample) > 0, Meta.BadExample);
  Fixed := FixAll(Join(['unit t;', 'interface']) + #13#10
    + CatalogText(Meta.BadExample) + #13#10 + Join(['implementation', 'end.']));
  // Das Beispiel steht einzeilig - B rueckt unter A.
  Assert.AreEqual(InIntf(['const A = 1;', '      B = 2;']), Fixed);
end;

procedure TTestRdxConsecutiveSectionDetector.Detector_InlineVars_NoHelp;
var
  O : TRdxFixOutcome;
begin
  O := PlanFirst(Join(['unit t;', 'interface', 'implementation',
    'procedure Foo;', 'begin', '  var A: Integer;', '  var B: Integer;',
    '  A := 1;', '  B := A;', 'end;', 'end.']));
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_CS_INLINE), O.Reason);
end;

procedure TTestRdxConsecutiveSectionDetector.Detector_VisibilityBetween_NoHelp;
var
  O : TRdxFixOutcome;
begin
  // 'public' setzt im Detektor nicht zurueck - die Hilfe sperrt.
  O := PlanFirst(InIntf(['type', '  TFoo = class', '  private',
    '    const A = 1;', '  public', '    const B = 2;', '  end;']));
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_CS_BETWEEN, ['public']), O.Reason);
end;

procedure TTestRdxConsecutiveSectionDetector.Table_StaleFinding_NoHelp;
var
  S : TSeen;
  O : TRdxFixOutcome;
begin
  S.Line := 4;
  S.Msg := MessageOf('var');
  S.Variant := '';
  O := PlanSeen(InIntf(['var', '  A: Integer;', 'var', '  B: Integer;']), S);
  Assert.IsFalse(O.Enabled, 'gesperrt');
  Assert.AreEqual(MsgMovedSuffix(_(R_CS_MOVED, ['var'])), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
  // Der Menuetext nennt die Art auch bei Ablehnung (Adapter).
  Assert.AreEqual('var', O.Name, 'Name gesperrt');
end;

procedure TTestRdxConsecutiveSectionDetector.Table_NameAndHint;
var
  O : TRdxFixOutcome;
begin
  // Angebot: Name = die Art aus der Meldung, Hinweis der Zeile,
  // bedeutungsgleich.
  O := PlanFirst(InIntf(['const', '  A = 1;', 'const', '  B = 2;']));
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual('const', O.Name, 'Name');
  Assert.AreEqual('gleiche Bedeutung - ein Schluesselwort deklariert beide '
    + 'Abschnitte', O.Hint);
  Assert.IsFalse(O.ChangesBehavior, 'bedeutungsgleich');
  // Abgelehnt (Inline-Deklarationen): Name trotzdem gesetzt.
  O := PlanFirst(Join(['unit t;', 'interface', 'implementation',
    'procedure Foo;', 'begin', '  var A: Integer;', '  var B: Integer;',
    '  A := 1;', '  B := A;', 'end;', 'end.']));
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual('var', O.Name, 'Name gesperrt');
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxConsecutiveSectionFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxConsecutiveSectionDetector);
  {$ENDIF}

end.
