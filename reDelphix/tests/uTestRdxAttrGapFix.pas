unit uTestRdxAttrGapFix;

// Editorhilfe SCA183 AttributeMisalignment (uRdxAttrGapFix): die Leerzeilen
// zwischen einer Attributzeile und dem Element dahinter loeschen. Faelle
// auf Text (TRdxAttrGapFix.BlankGap) und drei Rundlaeufe mit dem ECHTEN
// Detektor (TAttributeMisalignmentDetector) und dem Planer der Tabelle
// (PlanAttrGap) - nur Delphi, reDelphix.Test (die Unit haengt am
// Quellstellen-Dienst des Cores wie uRdxFixTable).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxAttrGapFix = class
  public
    // ---- Hilfe ----
    [Test] procedure Gap_OneBlankLine_Deleted;
    [Test] procedure Gap_SeveralBlankLines_Deleted;
    [Test] procedure Gap_StackedAndAfterMethod_Deleted;
    [Test] procedure Gap_BeforeFieldTypeAndSameLineAttrs_Deleted;
    [Test] procedure Edit_SpansLines_OnlyBlankText;
    // ---- keine Hilfe ----
    [Test] procedure Refuse_NotAnAttributeLine;
    [Test] procedure Refuse_AttributeShape;
    [Test] procedure Refuse_NoGap;
    [Test] procedure Refuse_CommentOrNothingBehindGap;
    [Test] procedure Refuse_NotACarrier;
    [Test] procedure Refuse_NoAnchor;
    [Test] procedure Refuse_Directive;
    // ---- echter Detektor ----
    [Test] procedure Detector_CatalogExample;
    [Test] procedure Detector_ThreeFindings_FixedOneByOne;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog,
  uAttributeMisalignment,
  uRdxBufferMath, uRdxCodeMap, uRdxRecipeRunner, uRdxAttrGapFix,
  uTestRdxTextKit,       // Join, Apply
  uTestRdxDetectorKit;   // TSeen, DetectSource, CatalogText

const
  // Die Attributzeile in InClass(...): hinter 'public' (Zeile 5).
  ATTR_LINE = 6;
  FILE_NAME = 't.pas';
  // Teile der Gruende (uRdxAttrGapFix) - nur der Kern, nicht der ganze Text.
  R_MOVED     = 'keine Attributzeile';
  R_TARGET    = 'Attribut mit Ziel';
  R_TAIL      = 'hinter dem Attribut steht noch Text';
  R_MULTI     = 'Attribut ueber mehrere Zeilen';
  R_NO_GAP    = 'keine Leerzeile hinter dem Attribut';
  R_NOT_CODE  = 'Kommentar oder eine Direktive';
  R_NO_MEMBER = 'kein Code mehr';
  R_NOT_CARRY = 'keine Deklaration, die das Attribut tragen kann';
  R_NO_ANCHOR = 'kein Deklarationsende';
  R_DIRECTIVE = 'Compiler-Direktive';

// ---- Helfer ----

// Die Meldung des Detektors zu einem Attribut AName.
function MessageOf(const AName: string): string;
begin
  Result := 'Attribute [' + AName + '] with blank line before target member '
    + '- visually loose';
end;

// ABody (Zeilen ab 6) in einer Klasse hinter 'public'.
function InClass(const ABody: string): string;
begin
  Result := Join(['unit t;', 'interface', 'type', '  TFoo = class',
    '  public']) + #13#10 + ABody + #13#10
    + Join(['  end;', 'implementation', 'end.']);
end;

// Die Hilfe fuer Zeile ALine, Attribut AName: der neue Text oder '' bei
// Ablehnung (AReason).
function Fix(const ASource: string; ALine: Integer; const AName: string;
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
    if TRdxAttrGapFix.BlankGap(Map, ALine, MessageOf(AName), E, AReason) then
      Result := Apply(ASource, E);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Die Hilfe muss abgelehnt werden, mit APart im Grund.
procedure AssertRefused(const ASource: string; ALine: Integer;
  const AName, APart: string);
var
  Reason : string;
begin
  Assert.AreEqual('', Fix(ASource, ALine, AName, Reason), 'keine Hilfe');
  Assert.IsTrue(Pos(APart, Reason) > 0, Reason);
end;

procedure AssertFixed(const AExpected, ASource: string; ALine: Integer;
  const AName: string);
var
  Reason : string;
begin
  Assert.AreEqual(AExpected, Fix(ASource, ALine, AName, Reason), Reason);
end;

// ---- Hilfe ----

procedure TTestRdxAttrGapFix.Gap_OneBlankLine_Deleted;
begin
  AssertFixed(
    InClass(Join(['    [Test]', '    procedure Foo;'])),
    InClass(Join(['    [Test]', '', '    procedure Foo;'])),
    ATTR_LINE, 'Test');
end;

procedure TTestRdxAttrGapFix.Gap_SeveralBlankLines_Deleted;
begin
  // Leerzeichen und Tabulator zaehlen als leer, alle Zeilen bis zum Element.
  AssertFixed(
    InClass(Join(['    [Test]', '    procedure Foo;'])),
    InClass(Join(['    [Test]', '', '  ' + #9, '', '    procedure Foo;'])),
    ATTR_LINE, 'Test');
end;

procedure TTestRdxAttrGapFix.Gap_StackedAndAfterMethod_Deleted;
begin
  // Das zweite von zwei gestapelten Attributen (davor ein ']').
  AssertFixed(
    InClass(Join(['    [Test]', '    [Category(''a'')]', '    procedure Foo;'])),
    InClass(Join(['    [Test]', '    [Category(''a'')]', '',
      '    procedure Foo;'])),
    ATTR_LINE + 1, 'Category');
  // Hinter einer Methode (davor ein ';').
  AssertFixed(
    InClass(Join(['    procedure A;', '    [Test]', '    procedure B;'])),
    InClass(Join(['    procedure A;', '    [Test]', '', '    procedure B;'])),
    ATTR_LINE + 1, 'Test');
end;

procedure TTestRdxAttrGapFix.Gap_BeforeFieldTypeAndSameLineAttrs_Deleted;
begin
  AssertFixed(
    InClass(Join(['    [Foo]', '    FValue: Integer;'])),
    InClass(Join(['    [Foo]', '', '    FValue: Integer;'])),
    ATTR_LINE, 'Foo');
  AssertFixed(
    InClass(Join(['    [A][B(1)]', '    procedure Foo;'])),
    InClass(Join(['    [A][B(1)]', '', '    procedure Foo;'])),
    ATTR_LINE, 'A');
  // Attribut vor einer Typdeklaration (davor 'type').
  AssertFixed(
    Join(['unit t;', 'interface', 'type', '  [Foo]', '  TBar = class',
      '  end;', 'implementation', 'end.']),
    Join(['unit t;', 'interface', 'type', '  [Foo]', '', '  TBar = class',
      '  end;', 'implementation', 'end.']),
    4, 'Foo');
end;

procedure TTestRdxAttrGapFix.Edit_SpansLines_OnlyBlankText;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
  R   : string;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := InClass(Join(['    [Test]', '', ' ' + #9, '    procedure Foo;']));
    Map := TRdxCodeMap.Create(SL);
    Assert.IsTrue(TRdxAttrGapFix.BlankGap(Map, ATTR_LINE, MessageOf('Test'),
      E, R), R);
    // Vom letzten Zeichen der Attributzeile (SpanFits: kein Bereich ab
    // einer leeren Zeile) bis hinter die letzte Leerzeile; geschrieben
    // wird nur dieses Zeichen.
    Assert.AreEqual<Integer>(ATTR_LINE, E.Span.StartLine);
    Assert.AreEqual<Integer>(Length('    [Test]'), E.Span.StartCol);
    Assert.AreEqual<Integer>(ATTR_LINE + 2, E.Span.EndLine);
    Assert.AreEqual<Integer>(3, E.Span.EndCol);
    Assert.AreEqual(']' + #10 + '' + #10 + ' ' + #9, E.Expected);
    Assert.AreEqual(']', E.NewText);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// ---- keine Hilfe ----

procedure TTestRdxAttrGapFix.Refuse_NotAnAttributeLine;
begin
  // Zeile verschoben: dort steht 'public', und der Name passt nicht.
  AssertRefused(InClass(Join(['    [Test]', '', '    procedure Foo;'])),
    ATTR_LINE - 1, 'Test', R_MOVED);
  AssertRefused(InClass(Join(['    [Test]', '', '    procedure Foo;'])),
    ATTR_LINE, 'Other', R_MOVED);
  // Auskommentiert.
  AssertRefused(InClass(Join(['    // [Test]', '', '    procedure Foo;'])),
    ATTR_LINE, 'Test', R_MOVED);
  // In einem Block-Kommentar.
  AssertRefused(InClass(Join(['    {', '    [Test]', '', '    procedure Foo;',
    '    }'])), ATTR_LINE + 1, 'Test', R_MOVED);
end;

procedure TTestRdxAttrGapFix.Refuse_AttributeShape;
begin
  // Ein Ziel: haengt an keinem Element.
  AssertRefused(
    InClass(Join(['    [assembly: Foo]', '', '    procedure Foo;'])),
    ATTR_LINE, 'assembly', R_TARGET);
  AssertRefused(
    InClass(Join(['    [Result: Foo]', '', '    function Foo: Integer;'])),
    ATTR_LINE, 'Result', R_TARGET);
  // Ueber mehrere Zeilen.
  AssertRefused(
    InClass(Join(['    [Foo(1,', '', '    2)]', '    procedure Foo;'])),
    ATTR_LINE, 'Foo', R_MULTI);
  // Auch mit einem Kommentar hinter dem offenen Teil.
  AssertRefused(
    InClass(Join(['    [Foo(1, // a', '', '    2)]', '    procedure Foo;'])),
    ATTR_LINE, 'Foo', R_MULTI);
  // Kommentar hinter dem Attribut.
  AssertRefused(
    InClass(Join(['    [Test] // wichtig', '', '    procedure Foo;'])),
    ATTR_LINE, 'Test', R_TAIL);
end;

procedure TTestRdxAttrGapFix.Refuse_NoGap;
begin
  AssertRefused(InClass(Join(['    [Test]', '    procedure Foo;'])),
    ATTR_LINE, 'Test', R_NO_GAP);
end;

procedure TTestRdxAttrGapFix.Refuse_CommentOrNothingBehindGap;
begin
  // Kommentar hinter der Leerzeile: die Zeilen bleiben.
  AssertRefused(
    InClass(Join(['    [Test]', '', '    // Hinweis', '    procedure Foo;'])),
    ATTR_LINE, 'Test', R_NOT_CODE);
  AssertRefused(
    InClass(Join(['    [Test]', '', '    { Hinweis }', '    procedure Foo;'])),
    ATTR_LINE, 'Test', R_NOT_CODE);
  // Nichts mehr hinter den Leerzeilen.
  AssertRefused(Join(['unit t;', 'interface', 'type', '  TFoo = class',
    '  public', '    [Test]', '', '']), ATTR_LINE, 'Test', R_NO_MEMBER);
end;

procedure TTestRdxAttrGapFix.Refuse_NotACarrier;
begin
  AssertRefused(InClass(Join(['    [Test]', '', '  end;'])),
    ATTR_LINE, 'Test', R_NOT_CARRY);
  AssertRefused(InClass(Join(['    [Test]', '', '  private'])),
    ATTR_LINE, 'Test', R_NOT_CARRY);
  AssertRefused(InClass(Join(['    [Test]', '', '    x := 1;'])),
    ATTR_LINE, 'Test', R_NOT_CARRY);
end;

procedure TTestRdxAttrGapFix.Refuse_NoAnchor;
begin
  // Ein Set-Literal hinter '=' ist kein Attribut.
  AssertRefused(
    Join(['unit t;', 'interface', 'const', '  X =', '  [a, b]', '',
      '  procedure Foo;', 'implementation', 'end.']),
    5, 'a', R_NO_ANCHOR);
  // Am Dateianfang steht nichts davor.
  AssertRefused(Join(['[Test]', '', 'procedure Foo;']), 1, 'Test', R_NO_ANCHOR);
end;

procedure TTestRdxAttrGapFix.Refuse_Directive;
begin
  AssertRefused(
    InClass(Join(['  {$IFDEF X}', '    [Test]', '', '    procedure Foo;',
      '  {$ENDIF}'])),
    ATTR_LINE + 1, 'Test', R_DIRECTIVE);
end;

// ---- echter Detektor ----

// Der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TAttributeMisalignmentDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_attrgap_', ASource, fkAttributeMisalignment,
    RunDetector);
end;

// Die Hilfe fuer den Fund ASeen ueber den Planer der Tabelle.
function PlanFor(const ASource: string; const ASeen: TSeen): TRdxFixOutcome;
var
  SL      : TStringList;
  Finding : TLeakFinding;
begin
  SL := TStringList.Create;
  Finding := TLeakFinding.New(FILE_NAME, '', ASeen.Line, ASeen.Msg,
    fkAttributeMisalignment);
  try
    SL.Text := ASource;
    Result := PlanAttrGap(nil, SL, Finding, nil);
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

procedure TTestRdxAttrGapFix.Detector_CatalogExample;
var
  Meta  : TRuleMeta;
  Bad   : string;
  Count : Integer;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkAttributeMisalignment);
  Bad := InClass(CatalogText(Meta.BadExample));
  Assert.AreEqual<Integer>(1, Length(Detect(Bad)), 'der Detektor meldet das Beispiel');
  Assert.AreEqual(InClass(CatalogText(Meta.GoodExample)), FixAll(Bad, Count));
  Assert.AreEqual<Integer>(1, Count);
end;

procedure TTestRdxAttrGapFix.Detector_ThreeFindings_FixedOneByOne;
var
  Count : Integer;
begin
  Assert.AreEqual(
    InClass(Join(['    [A]', '    procedure X;', '    [B]',
      '    procedure Y;', '    [C]', '    procedure Z;'])),
    FixAll(InClass(Join(['    [A]', '', '    procedure X;', '    [B]', '', '',
      '    procedure Y;', '    [C]', ' ' + #9, '    procedure Z;'])), Count));
  Assert.AreEqual<Integer>(3, Count);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRdxAttrGapFix);

end.
