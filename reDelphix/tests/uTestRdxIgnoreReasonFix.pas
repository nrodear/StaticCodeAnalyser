unit uTestRdxIgnoreReasonFix;

// Editorhilfe SCA179 AttributeIgnoreWithoutReason (uRdxIgnoreReasonFix):
// aus '[Ignore]' wird '[Ignore('reason')]'. Die Faelle auf Text laufen ohne
// Parser und ohne Detektor (TTestRdxIgnoreReasonFix); die Rundlaeufe mit dem
// ECHTEN Detektor ueber die Tabelle (TRdxFixTable.FixFor) stehen in
// einer eigenen Fixture hinter {$IFNDEF FPC} (TTestRdxIgnoreReasonDetector).
// Die ganze Unit ist nur Delphi (reDelphix.Test): der Adapter-Test der
// ersten Fixture ruft die Tabelle (TLeakFinding, uRdxFixTable).
// Der Planer ist seit der Folgewelle G09-07 ohne Delphi-only-uses (den
// Adapter traegt uRdxFixTable); die Unit steht trotzdem nicht im
// FPC-Pruefstand (build.sh) - dessen Runner kennt die {$IFNDEF FPC}-
// Weichen nicht, sie sind heute ohne Wirkung.
// Prueft: die Formen '[Ignore]', '[Ignore()]', Schreibweise und Leerraum, den
// Bereich (nur der Teil hinter dem Namen), und die Sperren - Gruppe, anderes
// Attribut davor, Argument, Kommentar, verschobene Zeile.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxIgnoreReasonFix = class
  public
    // ---- Hilfe ----
    [Test] procedure Add_Plain;
    [Test] procedure Add_EmptyParens;
    [Test] procedure Add_CaseAndBlanks;
    [Test] procedure Add_StackedBehindTest;
    [Test] procedure Add_OnlyTheNamedLine;
    [Test] procedure Edit_SpanIsTheTailBehindTheName;
    // ---- keine Hilfe ----
    [Test] procedure Refuse_GroupOrOtherAttribute;
    [Test] procedure Refuse_Argument;
    [Test] procedure Refuse_TailOrComment;
    [Test] procedure Refuse_MovedLine;
    [Test] procedure Refuse_OtherName;
    // ---- Planer der Tabelle ----
    [Test] procedure Plan_Adapter_EditsAndRefuses;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxIgnoreReasonDetector = class
  public
    [Test] procedure Detector_CatalogExample;
    [Test] procedure Detector_ThreeFormsFixedOneByOne;
    [Test] procedure Detector_ReportsGroup_HelpRefuses;
    [Test] procedure Detector_ReportsTrailingComment_HelpRefuses;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uRuleCatalog, uAttributeIgnoreWithoutReason,
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText
  {$ENDIF}
  uMethodd12, uSCAConsts, uRdxBufferMath, uRdxCodeMap, uRdxRecipeRunner,
  uRdxFixTable,
  uRdxIgnoreReasonFix,
  uRdxText,              // _() und die gemeinsamen Gruende (E29)
  uTestRdxTextKit;       // Join, Apply

const
  // Die Attributzeile in InClass(...): hinter 'public' (Zeile 5).
  ATTR_LINE = 6;
  FILE_NAME = 't.pas';

// ---- Helfer ----

// ABody (Zeilen ab 6) in einer Klasse hinter 'public'.
function InClass(const ABody: string): string;
begin
  Result := Join(['unit t;', 'interface', 'type', '  TFoo = class',
    '  public']) + #13#10 + ABody + #13#10
    + Join(['  end;', 'implementation', 'end.']);
end;

// Der Grund einer verschobenen Zeile, in der Sprache der Tests.
function Moved: string;
begin
  Result := MsgMovedSuffix(_(R_IGN_MOVED));
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
    if TRdxIgnoreReasonFix.AddReason(Map, ALine, '', E, AReason) then
      Result := Apply(ASource, E);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Die Zeile ALine von ABody (in InClass) wird zu AExpected.
procedure AssertFixed(const AExpected, ABody: string; ALine: Integer);
var
  Reason : string;
begin
  Assert.AreEqual(InClass(AExpected), Fix(InClass(ABody), ALine, Reason),
    Reason);
end;

// Keine Hilfe, mit dem Grund AReason.
procedure AssertRefused(const ASource: string; ALine: Integer;
  const AReason: string);
var
  Reason : string;
begin
  Assert.AreEqual('', Fix(ASource, ALine, Reason), 'keine Hilfe');
  Assert.AreEqual(AReason, Reason);
end;

// ---- Hilfe ----

procedure TTestRdxIgnoreReasonFix.Add_Plain;
begin
  AssertFixed(
    Join(['    [Ignore(''reason'')]', '    procedure Foo;']),
    Join(['    [Ignore]', '    procedure Foo;']), ATTR_LINE);
end;

procedure TTestRdxIgnoreReasonFix.Add_EmptyParens;
begin
  AssertFixed(
    Join(['    [Ignore(''reason'')]', '    procedure Foo;']),
    Join(['    [Ignore()]', '    procedure Foo;']), ATTR_LINE);
  // Leerraum in den Klammern (der Detektor meldet auch das).
  AssertFixed(
    Join(['    [Ignore(''reason'')]', '    procedure Foo;']),
    Join(['    [Ignore( )]', '    procedure Foo;']), ATTR_LINE);
end;

procedure TTestRdxIgnoreReasonFix.Add_CaseAndBlanks;
begin
  // Schreibweise des Namens und alles vor dem Namen bleibt.
  AssertFixed(
    Join(['    [ignore(''reason'')]', '    procedure Foo;']),
    Join(['    [ignore]', '    procedure Foo;']), ATTR_LINE);
  AssertFixed(
    Join(['    [ IGNORE(''reason'')]', '    procedure Foo;']),
    Join(['    [ IGNORE ]', '    procedure Foo;']), ATTR_LINE);
  AssertFixed(
    Join([#9 + '[Ignore(''reason'')]  ', '    procedure Foo;']),
    Join([#9 + '[Ignore]  ', '    procedure Foo;']), ATTR_LINE);
end;

procedure TTestRdxIgnoreReasonFix.Add_StackedBehindTest;
begin
  AssertFixed(
    Join(['    [Test]', '    [Ignore(''reason'')]', '    procedure Foo;']),
    Join(['    [Test]', '    [Ignore]', '    procedure Foo;']),
    ATTR_LINE + 1);
end;

procedure TTestRdxIgnoreReasonFix.Add_OnlyTheNamedLine;
begin
  // Zwei Methoden: nur die gemeldete Zeile aendert sich.
  AssertFixed(
    Join(['    [Ignore]', '    procedure A;', '    [Ignore(''reason'')]',
      '    procedure B;']),
    Join(['    [Ignore]', '    procedure A;', '    [Ignore]',
      '    procedure B;']),
    ATTR_LINE + 2);
end;

procedure TTestRdxIgnoreReasonFix.Edit_SpanIsTheTailBehindTheName;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  E   : TRdxEdit;
  R   : string;
begin
  SL := TStringList.Create;
  Map := nil;
  try
    SL.Text := InClass(Join(['    [Ignore ()]', '    procedure Foo;']));
    Map := TRdxCodeMap.Create(SL);
    Assert.IsTrue(TRdxIgnoreReasonFix.AddReason(Map, ATTR_LINE, '', E, R), R);
    // '[' steht auf Spalte 5, 'Ignore' auf 6..11, der Bereich ab Spalte 12
    // (Leerzeichen) bis hinter das ']' auf Spalte 15.
    Assert.AreEqual<Integer>(ATTR_LINE, E.Span.StartLine);
    Assert.AreEqual<Integer>(12, E.Span.StartCol);
    Assert.AreEqual<Integer>(ATTR_LINE, E.Span.EndLine);
    Assert.AreEqual<Integer>(16, E.Span.EndCol);
    Assert.AreEqual(' ()]', E.Expected);
    Assert.AreEqual('(''reason'')]', E.NewText);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// ---- keine Hilfe ----

procedure TTestRdxIgnoreReasonFix.Refuse_GroupOrOtherAttribute;
begin
  AssertRefused(InClass(Join(['    [Ignore, Test]', '    procedure Foo;'])),
    ATTR_LINE, _(R_IGN_SHAPE));
  AssertRefused(InClass(Join(['    [Test, Ignore]', '    procedure Foo;'])),
    ATTR_LINE, _(R_IGN_SHAPE));
  AssertRefused(InClass(Join(['    [Test][Ignore]', '    procedure Foo;'])),
    ATTR_LINE, _(R_IGN_SHAPE));
  AssertRefused(InClass(Join(['    [Ignore][Test]', '    procedure Foo;'])),
    ATTR_LINE, _(R_IGN_TAIL));
end;

procedure TTestRdxIgnoreReasonFix.Refuse_Argument;
begin
  AssertRefused(InClass(Join(['    [Ignore(''kaputt'')]', '    procedure Foo;'])),
    ATTR_LINE, _(R_IGN_SHAPE));
  AssertRefused(InClass(Join(['    [Ignore('''')]', '    procedure Foo;'])),
    ATTR_LINE, _(R_IGN_SHAPE));
  AssertRefused(InClass(Join(['    [Ignore(X)]', '    procedure Foo;'])),
    ATTR_LINE, _(R_IGN_SHAPE));
  // Klammer ueber mehrere Zeilen.
  AssertRefused(InClass(Join(['    [Ignore(', '    )]', '    procedure Foo;'])),
    ATTR_LINE, _(R_IGN_SHAPE));
end;

procedure TTestRdxIgnoreReasonFix.Refuse_TailOrComment;
begin
  AssertRefused(InClass(Join(['    [Ignore] // spaeter', '    procedure Foo;'])),
    ATTR_LINE, _(R_IGN_TAIL));
  AssertRefused(InClass(Join(['    [Ignore] { spaeter }', '    procedure Foo;'])),
    ATTR_LINE, _(R_IGN_TAIL));
  AssertRefused(InClass(Join(['    [Ignore]; x', '    procedure Foo;'])),
    ATTR_LINE, _(R_IGN_TAIL));
  // Kommentar im Attribut.
  AssertRefused(InClass(Join(['    [Ignore { x } ]', '    procedure Foo;'])),
    ATTR_LINE, _(R_IGN_SHAPE));
end;

procedure TTestRdxIgnoreReasonFix.Refuse_MovedLine;
begin
  // Die Zeile davor ('public'), die Zeile dahinter, ausserhalb der Datei.
  AssertRefused(InClass(Join(['    [Ignore]', '    procedure Foo;'])),
    ATTR_LINE - 1, Moved);
  AssertRefused(InClass(Join(['    [Ignore]', '    procedure Foo;'])),
    ATTR_LINE + 1, Moved);
  AssertRefused(InClass(Join(['    [Ignore]', '    procedure Foo;'])), 0, Moved);
  AssertRefused(InClass(Join(['    [Ignore]', '    procedure Foo;'])), 99, Moved);
  // Auskommentiert.
  AssertRefused(InClass(Join(['    // [Ignore]', '    procedure Foo;'])),
    ATTR_LINE, Moved);
  // In einem Block-Kommentar.
  AssertRefused(InClass(Join(['    {', '    [Ignore]', '    }',
    '    procedure Foo;'])), ATTR_LINE + 1, Moved);
  // Ein Array-Index ist kein Attribut (steht nicht am Zeilenanfang).
  AssertRefused(Join(['procedure P;', 'begin', '  X := A[Ignore];', 'end;']),
    3, Moved);
end;

procedure TTestRdxIgnoreReasonFix.Refuse_OtherName;
begin
  AssertRefused(InClass(Join(['    [Test]', '    procedure Foo;'])),
    ATTR_LINE, Moved);
  AssertRefused(InClass(Join(['    [IgnoreAttribute]', '    procedure Foo;'])),
    ATTR_LINE, _(R_IGN_SHAPE));
  AssertRefused(InClass(Join(['    []', '    procedure Foo;'])),
    ATTR_LINE, Moved);
end;

// ---- Planer der Tabelle ----

procedure TTestRdxIgnoreReasonFix.Plan_Adapter_EditsAndRefuses;
var
  SL      : TStringList;
  Finding : TLeakFinding;
  O       : TRdxFixOutcome;
  Src     : string;
begin
  SL := TStringList.Create;
  Finding := TLeakFinding.New(FILE_NAME, '', ATTR_LINE,
    '[Ignore] without reason message', fkAttributeIgnoreWithoutReason);
  try
    Src := InClass(Join(['    [Ignore]', '    procedure Foo;']));
    SL.Text := Src;
    O := TRdxFixTable.FixFor(nil, SL, Finding, nil);
    Assert.IsTrue(O.Enabled, O.Reason);
    Assert.AreEqual<Integer>(1, Length(O.Edits));
    Assert.AreEqual(
      InClass(Join(['    [Ignore(''reason'')]', '    procedure Foo;'])),
      Apply(Src, O.Edits));
    // Die Zeile ist verschoben: Grund, keine Ersetzung.
    Finding.LineNumber := IntToStr(ATTR_LINE + 1);
    O := TRdxFixTable.FixFor(nil, SL, Finding, nil);
    Assert.IsFalse(O.Enabled);
    Assert.AreEqual(Moved, O.Reason);
    // Ohne Quelltext keine Hilfe.
    O := TRdxFixTable.FixFor(nil, nil, Finding, nil);
    Assert.IsFalse(O.Enabled);
  finally
    Finding.Free;
    SL.Free;
  end;
end;

{$IFNDEF FPC}

// ---- Mit dem echten Detektor ----

// Der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TAttributeIgnoreWithoutReasonDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_s179_', ASource, fkAttributeIgnoreWithoutReason,
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
    fkAttributeIgnoreWithoutReason);
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

procedure TTestRdxIgnoreReasonDetector.Detector_CatalogExample;
var
  Meta  : TRuleMeta;
  Bad   : string;
  Count : Integer;
begin
  // Das Beispiel 'bad' des Katalogs: ein Fund; danach steht ein Grund in den
  // Klammern und der Detektor schweigt.
  Meta := TRuleCatalog.GetRuleCanonical(fkAttributeIgnoreWithoutReason);
  Bad := InClass(CatalogText(Meta.BadExample));
  Assert.AreEqual<Integer>(1, Length(Detect(Bad)), 'der Detektor meldet das Beispiel');
  Assert.AreEqual(
    InClass(Join(['[Ignore(''reason'')]', 'procedure SomeTest;'])),
    FixAll(Bad, Count));
  Assert.AreEqual<Integer>(1, Count);
end;

procedure TTestRdxIgnoreReasonDetector.Detector_ThreeFormsFixedOneByOne;
var
  Count : Integer;
begin
  Assert.AreEqual(
    InClass(Join(['    [Ignore(''reason'')]', '    procedure X;',
      '    [Ignore(''reason'')]', '    procedure Y;',
      '    [ignore(''reason'')]', '    procedure Z;'])),
    FixAll(InClass(Join(['    [Ignore]', '    procedure X;',
      '    [Ignore()]', '    procedure Y;',
      '    [ignore ]', '    procedure Z;'])), Count));
  Assert.AreEqual<Integer>(3, Count);
end;

procedure TTestRdxIgnoreReasonDetector.Detector_ReportsGroup_HelpRefuses;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // '[Test][Ignore]' beginnt mit '[' und der Regex findet '[Ignore]': der
  // Detektor meldet, die Hilfe fasst die Gruppe nicht an.
  Src := InClass(Join(['    [Test][Ignore]', '    procedure Foo;']));
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen));
  O := PlanFor(Src, Seen[0]);
  Assert.IsFalse(O.Enabled);
  Assert.AreEqual(_(R_IGN_SHAPE), O.Reason);
end;

procedure TTestRdxIgnoreReasonDetector.Detector_ReportsTrailingComment_HelpRefuses;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // Der Detektor strippt den Kommentar und meldet; die Hilfe laesst die
  // Zeile mit dem Kommentar in Ruhe.
  Src := InClass(Join(['    [Ignore] // spaeter', '    procedure Foo;']));
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen));
  O := PlanFor(Src, Seen[0]);
  Assert.IsFalse(O.Enabled);
  Assert.AreEqual(_(R_IGN_TAIL), O.Reason);
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxIgnoreReasonFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxIgnoreReasonDetector);
  {$ENDIF}

end.
