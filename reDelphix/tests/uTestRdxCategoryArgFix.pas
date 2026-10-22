unit uTestRdxCategoryArgFix;

// Editorhilfe SCA181 AttributeCategoryWithoutString (uRdxCategoryArgFix):
// '[Category]' -> '[Category(''category'')]'. Die Faelle auf Text laufen ohne
// Parser und ohne Detektor; die Rundlaeufe mit dem ECHTEN Detektor
// (TAttributeCategoryWithoutStringDetector) ueber die Tabelle
// (TRdxFixTable.FixFor, Adapter PlanCategoryArg) stehen in einer
// eigenen Fixture hinter {$IFNDEF FPC}. Nur Delphi (reDelphix.Test): der
// Planer ist seit der Folgewelle G09-07 ohne Delphi-only-uses, die Unit
// steht trotzdem nicht im FPC-Pruefstand (build.sh) - dessen Runner kennt
// die Weichen nicht und nimmt keine zwei Fixtures je Unit; sie sind heute
// ohne Wirkung.
// Prueft: Hilfe mit Schreibweise und Blanks, gestapelte Attribute,
// Kommentar dahinter, der Bereich, und die Sperren - verschobene Zeile,
// Kommentar, Argument/Liste, weiterer Code auf der Zeile, kein Anker,
// Direktive.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxCategoryArgFix = class
  public
    // ---- Hilfe ----
    [Test] procedure Sca181_PlainAttribute_GetsPlaceholder;
    [Test] procedure Sca181_CaseAndBlanks_Kept;
    [Test] procedure Sca181_StackedAndAfterMethod_Helps;
    [Test] procedure Sca181_TrailingComment_Helps;
    [Test] procedure Sca181_Edit_OnlyNameAndBlanks;
    // ---- keine Hilfe ----
    [Test] procedure Sca181_Moved_NoHelp;
    [Test] procedure Sca181_HasArgument_NoHelp;
    [Test] procedure Sca181_ListOrGroup_NoHelp;
    [Test] procedure Sca181_CodeAfterAttribute_NoHelp;
    [Test] procedure Sca181_NoAnchor_NoHelp;
    [Test] procedure Sca181_Directive_NoHelp;
  end;

{$IFNDEF FPC}
  // Rundlaeufe mit dem ECHTEN Detektor (nur Delphi).
  [TestFixture]
  TTestRdxCategoryArgFixDetector = class
  public
    [Test] procedure Sca181_Detector_CatalogExample;
    [Test] procedure Sca181_Detector_TwoFindings_FixedOneByOne;
    [Test] procedure Sca181_Detector_ArgumentFormsNotReported;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uRuleCatalog, uAttributeCategoryWithoutString,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // TRdxFixTable.FixFor
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText
  {$ENDIF}
  uSCAConsts, uRdxBufferMath, uRdxCodeMap, uRdxCategoryArgFix,
  uRdxText,              // _() und die gemeinsamen Gruende (E29)
  uTestRdxTextKit;       // Join, Apply

const
  // Die Attributzeile in InClass(...): hinter 'public' (Zeile 5).
  ATTR_LINE = 6;
  {$IFNDEF FPC}
  FILE_NAME = 't.pas';
  {$ENDIF}

// ---- Helfer ----

// Der Grund einer verschobenen Stelle, in der Sprache der Tests.
function Moved: string;
begin
  Result := MsgMovedSuffix(_(R_CAT_MOVED));
end;

// ABody (Zeilen ab 6) in einer Klasse hinter 'public'.
function InClass(const ABody: string): string;
begin
  Result := Join(['unit t;', 'interface', 'type', '  TFoo = class',
    '  public']) + #13#10 + ABody + #13#10
    + Join(['  end;', 'implementation', 'end.']);
end;

// Die Hilfe fuer Zeile ALine: der neue Text oder '' bei Ablehnung (AReason).
function Fix(const ASource: string; ALine: Integer;
  out AReason: string): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
begin
  Result := '';
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    if TRdxCategoryArgFix.AddArgument(Map, ALine, '', E, AReason) then
      Result := Apply(ASource, E);
  finally
    Map.Free;
    SL.Free;
  end;
end;

procedure AssertFixed(const AExpected, ASource: string; ALine: Integer);
var
  Reason : string;
begin
  Assert.AreEqual(AExpected, Fix(ASource, ALine, Reason), Reason);
end;

procedure AssertRefused(const ASource: string; ALine: Integer;
  const AReason: string);
var
  Got : string;
begin
  Assert.AreEqual('', Fix(ASource, ALine, Got), 'keine Hilfe');
  Assert.AreEqual(AReason, Got);
end;

// ---- Hilfe ----

procedure TTestRdxCategoryArgFix.Sca181_PlainAttribute_GetsPlaceholder;
begin
  AssertFixed(
    InClass(Join(['    [Category(''category'')]', '    procedure Foo;'])),
    InClass(Join(['    [Category]', '    procedure Foo;'])),
    ATTR_LINE);
end;

procedure TTestRdxCategoryArgFix.Sca181_CaseAndBlanks_Kept;
begin
  // Der Detektor liest ohne Beachtung der Schreibweise und erlaubt Blanks vor
  // dem ']': beides bleibt, wie es steht.
  AssertFixed(
    InClass(Join(['    [category(''category'')]', '    procedure Foo;'])),
    InClass(Join(['    [category]', '    procedure Foo;'])),
    ATTR_LINE);
  AssertFixed(
    InClass(Join(['    [Category(''category'')  ]', '    procedure Foo;'])),
    InClass(Join(['    [Category  ]', '    procedure Foo;'])),
    ATTR_LINE);
end;

procedure TTestRdxCategoryArgFix.Sca181_StackedAndAfterMethod_Helps;
begin
  // Hinter einem anderen Attribut (davor ein ']').
  AssertFixed(
    InClass(Join(['    [Test]', '    [Category(''category'')]',
      '    procedure Foo;'])),
    InClass(Join(['    [Test]', '    [Category]', '    procedure Foo;'])),
    ATTR_LINE + 1);
  // Hinter einer Methode (davor ein ';').
  AssertFixed(
    InClass(Join(['    procedure A;', '    [Category(''category'')]',
      '    procedure B;'])),
    InClass(Join(['    procedure A;', '    [Category]', '    procedure B;'])),
    ATTR_LINE + 1);
end;

procedure TTestRdxCategoryArgFix.Sca181_TrailingComment_Helps;
begin
  AssertFixed(
    InClass(Join(['    [Category(''category'')] // langsam',
      '    procedure Foo;'])),
    InClass(Join(['    [Category] // langsam', '    procedure Foo;'])),
    ATTR_LINE);
  AssertFixed(
    InClass(Join(['    [Category(''category'')] { langsam }',
      '    procedure Foo;'])),
    InClass(Join(['    [Category] { langsam }', '    procedure Foo;'])),
    ATTR_LINE);
end;

procedure TTestRdxCategoryArgFix.Sca181_Edit_OnlyNameAndBlanks;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
  R   : string;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := InClass(Join(['    [Category ]', '    procedure Foo;']));
    Map := TRdxCodeMap.Create(SL);
    Assert.IsTrue(TRdxCategoryArgFix.AddArgument(Map, ATTR_LINE, '', E, R), R);
    // Vom 'C' bis vor das ']' - das '[' und das ']' bleiben unberuehrt.
    Assert.AreEqual<Integer>(ATTR_LINE, E.Span.StartLine);
    Assert.AreEqual<Integer>(6, E.Span.StartCol);
    Assert.AreEqual<Integer>(ATTR_LINE, E.Span.EndLine);
    Assert.AreEqual<Integer>(15, E.Span.EndCol);
    Assert.AreEqual('Category ', E.Expected);
    Assert.AreEqual('Category(''category'') ', E.NewText);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// ---- keine Hilfe ----

procedure TTestRdxCategoryArgFix.Sca181_Moved_NoHelp;
begin
  // Zeile verschoben: dort steht 'public'.
  AssertRefused(InClass(Join(['    [Category]', '    procedure Foo;'])),
    ATTR_LINE - 1, Moved);
  // Auskommentiert.
  AssertRefused(InClass(Join(['    // [Category]', '    procedure Foo;'])),
    ATTR_LINE, Moved);
  // In einem Block-Kommentar.
  AssertRefused(InClass(Join(['    {', '    [Category]', '    }',
    '    procedure Foo;'])), ATTR_LINE + 1, Moved);
  // Ein anderes Attribut, ein anderer Name.
  AssertRefused(InClass(Join(['    [Test]', '    procedure Foo;'])),
    ATTR_LINE, Moved);
  AssertRefused(InClass(Join(['    [CategoryX]', '    procedure Foo;'])),
    ATTR_LINE, Moved);
  // Ein Array-Index am Zeilenanfang einer Anweisung.
  AssertRefused(InClass(Join(['    Foo[Category]', '    procedure Foo;'])),
    ATTR_LINE, Moved);
end;

procedure TTestRdxCategoryArgFix.Sca181_HasArgument_NoHelp;
var
  Arg : string;
begin
  // Ein Argument - ob String, Konstante oder Zahl: nicht angefasst, die
  // Konstante koennte ein String sein (und der Detektor meldet sie nie).
  for Arg in ['()', '(''Slow'')', '(SLOW_CATEGORY)', '(5)', ' (''Slow'')'] do
    AssertRefused(
      InClass(Join(['    [Category' + Arg + ']', '    procedure Foo;'])),
      ATTR_LINE, _(R_CAT_ARG));
end;

procedure TTestRdxCategoryArgFix.Sca181_ListOrGroup_NoHelp;
begin
  // Eine Liste: '[Category, Test]' ist eine Gruppe mit weiterem Attribut.
  AssertRefused(
    InClass(Join(['    [Category, Test]', '    procedure Foo;'])),
    ATTR_LINE, _(R_CAT_ARG));
  // '[Test, Category]': der Detektor meldet es nie, die Zeile gilt als
  // verschoben.
  AssertRefused(
    InClass(Join(['    [Test, Category]', '    procedure Foo;'])),
    ATTR_LINE, Moved);
  // '[Test][Category]' meldet der Detektor: die Form, die die Hilfe nicht
  // anfasst - nicht "verschoben".
  AssertRefused(
    InClass(Join(['    [Test][Category]', '    procedure Foo;'])),
    ATTR_LINE, _(R_CAT_SHAPE));
end;

procedure TTestRdxCategoryArgFix.Sca181_CodeAfterAttribute_NoHelp;
begin
  AssertRefused(
    InClass(Join(['    [Category][Test]', '    procedure Foo;'])),
    ATTR_LINE, _(R_CAT_TAIL));
  AssertRefused(
    InClass(Join(['    [Category] procedure Foo;'])),
    ATTR_LINE, _(R_CAT_TAIL));
end;

procedure TTestRdxCategoryArgFix.Sca181_NoAnchor_NoHelp;
begin
  // Vor der Zeile steht ein Ausdruck: ein Index, kein Attribut.
  AssertRefused(
    InClass(Join(['    x := Foo', '    [Category]', '    ;'])),
    ATTR_LINE + 1, _(R_CAT_ANCHOR));
  // Am Dateianfang steht nichts davor.
  AssertRefused(Join(['[Category]', 'procedure Foo;']), 1, _(R_CAT_ANCHOR));
end;

procedure TTestRdxCategoryArgFix.Sca181_Directive_NoHelp;
begin
  // Eine Direktive zwischen dem Anker und der Zeile.
  AssertRefused(
    InClass(Join(['  {$IFDEF X}', '    [Category]', '    procedure Foo;',
      '  {$ENDIF}'])),
    ATTR_LINE + 1, _(R_CAT_DIRECTIVE));
  // Eine Direktive hinter dem Attribut.
  AssertRefused(
    InClass(Join(['    [Category] {$IFDEF X}', '    procedure Foo;',
      '  {$ENDIF}'])),
    ATTR_LINE, _(R_CAT_DIRECTIVE));
end;

{$IFNDEF FPC}

// ---- echter Detektor ----

// Der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TAttributeCategoryWithoutStringDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_catarg_', ASource,
    fkAttributeCategoryWithoutString, RunDetector);
end;

// Die Hilfe fuer den Fund ASeen ueber den Einstieg der Tabelle.
function PlanFor(const ASource: string; const ASeen: TSeen): TRdxFixOutcome;
var
  SL      : TStringList;
  Finding : TLeakFinding;
begin
  SL := TStringList.Create;
  Finding := TLeakFinding.New(FILE_NAME, '', ASeen.Line, ASeen.Msg,
    fkAttributeCategoryWithoutString);
  try
    SL.Text := ASource;
    Result := TRdxFixTable.FixFor(nil, SL, Finding, nil);
  finally
    Finding.Free;
    SL.Free;
  end;
end;

// Fund fuer Fund beheben, bis der Detektor schweigt; Zahl der Funde am
// Anfang in ACount.
function FixAll(const ASource: string; out ACount: Integer): string;
const
  MAX_PASSES = 10;
var
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
  Pass : Integer;
begin
  Result := ASource;
  ACount := Length(Detect(ASource));
  for Pass := 1 to MAX_PASSES do
  begin
    Seen := Detect(Result);
    if Length(Seen) = 0 then Exit;
    O := PlanFor(Result, Seen[0]);
    Assert.IsTrue(O.Enabled, Format('Zeile %d: %s', [Seen[0].Line, O.Reason]));
    Result := Apply(Result, O.Edits);
  end;
  Assert.Fail('der Detektor meldet nach 10 Runden noch');
end;

procedure TTestRdxCategoryArgFixDetector.Sca181_Detector_CatalogExample;
var
  Meta  : TRuleMeta;
  Bad   : string;
  Count : Integer;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkAttributeCategoryWithoutString);
  Bad := InClass(CatalogText(Meta.BadExample));
  Assert.AreEqual<Integer>(1, Length(Detect(Bad)),
    'der Detektor meldet das Beispiel');
  // Der Platzhalter statt des Namens 'Slow' des guten Beispiels.
  Assert.AreEqual(
    InClass(Join(['[Category(''category'')]', 'procedure Foo;'])),
    FixAll(Bad, Count));
  Assert.AreEqual<Integer>(1, Count);
end;

procedure TTestRdxCategoryArgFixDetector.Sca181_Detector_TwoFindings_FixedOneByOne;
var
  Count : Integer;
begin
  Assert.AreEqual(
    InClass(Join(['    [Test]', '    [Category(''category'')]',
      '    procedure A;', '    [category(''category'')]',
      '    procedure B;'])),
    FixAll(InClass(Join(['    [Test]', '    [Category]', '    procedure A;',
      '    [category]', '    procedure B;'])), Count));
  Assert.AreEqual<Integer>(2, Count);
end;

procedure TTestRdxCategoryArgFixDetector.Sca181_Detector_ArgumentFormsNotReported;
begin
  // Der Detektor meldet nur die Form ohne Argument - die Formen, die die
  // Hilfe nicht anfasst, sind nie ein Fund dieser Regel.
  Assert.AreEqual<Integer>(0, Length(Detect(InClass(Join(
    ['    [Category(''Slow'')]', '    procedure A;',
     '    [Category(SLOW_CATEGORY)]', '    procedure B;',
     '    [Category()]', '    procedure C;'])))));
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxCategoryArgFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxCategoryArgFixDetector);
  {$ENDIF}

end.
