unit uTestRdxGroupedDeclFix;

// Editorhilfe SCA076 GroupedDeclaration (uRdxGroupedDeclFix): 'A, B: T;' ->
// eine Zeile je Name. Die Faelle auf Text laufen ohne Parser und ohne
// Detektor (auch im FPC-Pruefstand); die Rundlaeufe mit dem ECHTEN Detektor
// stehen in der zweiten Fixture, nur Delphi (reDelphix.Test).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxGroupedDeclFix = class
  public
    [Test] procedure ThreeNames_OwnLines;
    [Test] procedure Spacing_Kept;
    [Test] procedure DottedType_And_String;
    [Test] procedure VarPrefix_Repeated;
    [Test] procedure ClassField_Split;
    [Test] procedure NewText_Uses_Lf_Span_Whole_Line;
    [Test] procedure Refuse_AnonymousTypes;
    [Test] procedure Refuse_Initializer_Absolute_Directive;
    [Test] procedure Refuse_Generic;
    [Test] procedure Refuse_Comment_String_Directive;
    [Test] procedure Refuse_MultiLine_And_TwoGroups;
    [Test] procedure Refuse_Prefix;
    [Test] procedure Refuse_ParameterList;
    [Test] procedure Refuse_CaseLabels;
    [Test] procedure Refuse_MovedLine_NoColumn;
    [Test] procedure Plan_Adapter;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxGroupedDeclFixDetector = class
  public
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_CatalogExample;
    [Test] procedure Detector_AnonymousType_NoHelp;
    [Test] procedure Detector_ParameterGroup_Silent;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  uMethodd12, uSCAConsts,
  uRdxBufferMath, uRdxCodeMap, uRdxRecipeRunner, uRdxText,
  uRdxGroupedDeclFix,
  uTestRdxTextKit   // Join, Apply
{$IFNDEF FPC}
  , System.Generics.Collections,
  uAstNode, uRuleCatalog, uGroupedDeclaration, uTestRdxDetectorKit
{$ENDIF}
  ;

// ---- Helfer ----

// Die Meldung wie der Detektor sie schreibt.
function GMsg(ACol: Integer): string;
begin
  Result := Format('Grouped declaration at column %d (`A, B: Type`) - split '
    + 'into one variable per line for clearer diffs and refactoring.', [ACol]);
end;

// Die Hilfe fuer Zeile ALine, Spalte ACol: neuer Text oder '' bei Ablehnung
// (AReason).
function Fix(const ASource: string; ALine: Integer; const AMessage: string;
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
    if TRdxGroupedDeclFix.Split(Map, ALine, AMessage, E, AReason) then
      Result := Apply(ASource, E);
  finally
    Map.Free;
    SL.Free;
  end;
end;

// Eine Zeile mitten in einer Unit (Zeile 4), Spalte ACol.
function FixLine(const ALine: string; ACol: Integer; out AReason: string): string;
begin
  Result := Fix(Join(['unit t;', 'interface', 'var', ALine, 'implementation',
    'end.']), 4, GMsg(ACol), AReason);
end;

// Der erwartete Text derselben Unit mit den Zeilen ALines an Stelle 4.
function UnitWith(const ALines: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'var']) + #13#10 + Join(ALines)
    + #13#10 + Join(['implementation', 'end.']);
end;

// Die Zeile ALine ohne Aenderung abgelehnt, mit dem Grund AReasonWant.
procedure AssertRefused(const ALine: string; ACol: Integer;
  const AReasonWant: string);
var
  R : string;
begin
  Assert.AreEqual('', FixLine(ALine, ACol, R), ALine);
  Assert.AreEqual(AReasonWant, R, ALine);
end;

// ---- Text ----

procedure TTestRdxGroupedDeclFix.ThreeNames_OwnLines;
var
  R : string;
begin
  Assert.AreEqual(
    UnitWith(['  A: Integer;', '  B: Integer;', '  C: Integer;']),
    FixLine('  A, B, C: Integer;', 3, R), R);
end;

procedure TTestRdxGroupedDeclFix.Spacing_Kept;
var
  R : string;
begin
  Assert.AreEqual(UnitWith(['  A : TFoo;  ', '  B : TFoo;  ']),
    FixLine('  A ,B : TFoo;  ', 3, R), R);
end;

procedure TTestRdxGroupedDeclFix.DottedType_And_String;
var
  R : string;
begin
  Assert.AreEqual(
    UnitWith(['  S1: System.Classes.TStringList;',
      '  S2: System.Classes.TStringList;']),
    FixLine('  S1, S2: System.Classes.TStringList;', 3, R), R);
  Assert.AreEqual(UnitWith(['  N: string;', '  M: string;']),
    FixLine('  N, M: string;', 3, R), R);
end;

procedure TTestRdxGroupedDeclFix.VarPrefix_Repeated;
var
  R : string;
begin
  // Ein Inline-var braucht das var je Variable, ein var-Abschnitt verkraftet
  // es.
  Assert.AreEqual(UnitWith(['var A: Integer;', 'var B: Integer;']),
    FixLine('var A, B: Integer;', 5, R), R);
  Assert.AreEqual(UnitWith(['  var A: Integer;', '  var B: Integer;']),
    FixLine('  var A, B: Integer;', 7, R), R);
end;

procedure TTestRdxGroupedDeclFix.ClassField_Split;
var
  R : string;
begin
  Assert.AreEqual(
    Join(['type', '  TFoo = class', '  private', '    FX: Integer;',
      '    FY: Integer;', '  end;']),
    Fix(Join(['type', '  TFoo = class', '  private', '    FX, FY: Integer;',
      '  end;']), 4, GMsg(5), R), R);
end;

procedure TTestRdxGroupedDeclFix.NewText_Uses_Lf_Span_Whole_Line;
var
  SL  : TStringList;
  F   : TLeakFinding;
  O   : TRdxFixOutcome;
begin
  SL := TStringList.Create;
  F := TLeakFinding.New('t.pas', '', 2, GMsg(3), fkGroupedDeclaration);
  try
    SL.Text := Join(['var', '  A, B: Integer;', 'begin']);
    O := PlanGroupedDeclaration(nil, SL, F, nil);
    Assert.IsTrue(O.Enabled, O.Reason);
    Assert.AreEqual<Integer>(1, Length(O.Edits));
    Assert.AreEqual('  A, B: Integer;', O.Edits[0].Expected);
    Assert.AreEqual('  A: Integer;'#10'  B: Integer;', O.Edits[0].NewText);
    // Die Zeile ab Spalte 1, nicht leer: der Bereich beginnt im Text.
    Assert.AreEqual<Integer>(2, O.Edits[0].Span.StartLine);
    Assert.AreEqual<Integer>(1, O.Edits[0].Span.StartCol);
    Assert.AreEqual<Integer>(2, O.Edits[0].Span.EndLine);
    Assert.AreEqual<Integer>(Length('  A, B: Integer;') + 1,
      O.Edits[0].Span.EndCol);
  finally
    F.Free;
    SL.Free;
  end;
end;

procedure TTestRdxGroupedDeclFix.Refuse_AnonymousTypes;
var
  Want : string;
begin
  // Je Name ein EIGENER Typ: 'A := B' scheiterte danach mit E2010.
  Want := _(R_GD_TYPE);
  AssertRefused('  A, B: record X: Integer; end;', 3, Want);
  AssertRefused('  A, B: array of Integer;', 3, Want);
  AssertRefused('  A, B: array[0..3] of Integer;', 3, Want);
  AssertRefused('  A, B: set of Byte;', 3, Want);
  AssertRefused('  A, B: ^Integer;', 3, Want);
  AssertRefused('  A, B: (sOne, sTwo);', 3, Want);
  AssertRefused('  A, B: string[20];', 3, Want);
  AssertRefused('  A, B: class', 3, Want);
end;

procedure TTestRdxGroupedDeclFix.Refuse_Initializer_Absolute_Directive;
var
  Want : string;
begin
  Want := _(R_GD_TYPE);
  AssertRefused('  A, B: Integer = 5;', 3, Want);
  AssertRefused('  A, B: Integer absolute X;', 3, Want);
  AssertRefused('  A, B: Integer platform;', 3, Want);
end;

procedure TTestRdxGroupedDeclFix.Refuse_Generic;
var
  Want : string;
begin
  Want := _(R_GD_TYPE);
  AssertRefused('  A, B: TDictionary<K, V>;', 3, Want);
  AssertRefused('  A, B: TList<Integer>;', 3, Want);
end;

procedure TTestRdxGroupedDeclFix.Refuse_Comment_String_Directive;
var
  Want : string;
  R    : string;
begin
  Want := _(R_GD_COMMENT);
  AssertRefused('  A, B: Integer; // zwei', 3, Want);
  AssertRefused('  A, B: Integer; { zwei }', 3, Want);
  AssertRefused('  A, B: Integer; (* zwei *)', 3, Want);
  AssertRefused('  {$IFDEF X} A, B: Integer; {$ENDIF}', 14, Want);
  // Die Zeile beginnt in einem Block-Kommentar: der Fund ist keiner.
  Assert.AreEqual('', Fix(Join(['{ Kommentar', '  A, B: Integer;', '}']), 2,
    GMsg(3), R));
  Assert.AreNotEqual('', R);
end;

procedure TTestRdxGroupedDeclFix.Refuse_MultiLine_And_TwoGroups;
var
  Want : string;
begin
  Want := _(R_GD_TYPE);
  AssertRefused('  A, B: Integer', 3, Want);
  AssertRefused('  A, B:', 3, Want);
  AssertRefused('  A, B: Integer; C, D: Integer;', 3, Want);
end;

procedure TTestRdxGroupedDeclFix.Refuse_Prefix;
var
  Want : string;
begin
  Want := _(R_GD_PREFIX);
  AssertRefused('  [Weak] A, B: TFoo;', 10, Want);
  AssertRefused('  private A, B: TFoo;', 11, Want);
  AssertRefused('  class var A, B: TFoo;', 13, Want);
  AssertRefused('  threadvar A, B: TFoo;', 13, Want);
  AssertRefused('procedure P; var A, B: Integer;', 18, Want);
end;

procedure TTestRdxGroupedDeclFix.Refuse_ParameterList;
var
  R : string;
begin
  // Die Klammer stammt aus einer Zeile davor; der Detektor meldet dort
  // nicht, die Hilfe verweigert eine verschobene Meldung.
  Assert.AreEqual('', Fix(Join(['procedure P(', '  A, B: Integer;',
    '  C: Integer);']), 2, GMsg(3), R));
  Assert.AreEqual(_(R_GD_PARAMS), R);
end;

procedure TTestRdxGroupedDeclFix.Refuse_CaseLabels;
var
  R : string;
begin
  Assert.AreEqual('', Fix(Join(['begin', '  case X of', '    cA, cB: Foo;',
    '  end;', 'end;']), 3, GMsg(5), R));
  Assert.AreEqual(_(R_GD_CASE), R);
  // Nach dem case-Ende ist es wieder eine Deklaration.
  Assert.AreEqual(Join(['begin', '  case X of', '    1: Foo;', '  end;',
    'var', '  A: Integer;', '  B: Integer;']),
    Fix(Join(['begin', '  case X of', '    1: Foo;', '  end;',
      'var', '  A, B: Integer;']), 6, GMsg(3), R), R);
end;

procedure TTestRdxGroupedDeclFix.Refuse_MovedLine_NoColumn;
var
  R : string;
  S : string;
begin
  S := Join(['var', '  A, B: Integer;', '  C: Integer;']);
  // Zeile verschoben: dort steht keine Gruppe mehr.
  Assert.AreEqual('', Fix(S, 3, GMsg(3), R));
  Assert.AreEqual(MsgMovedSuffix(_(R_GD_MOVED)), R);
  Assert.AreEqual('', Fix(S, 9, GMsg(3), R));
  Assert.AreEqual(MsgMovedSuffix(_(R_GD_MOVED)), R);
  // Spalte auf dem Komma, mitten im Wort und hinter dem Zeilenende.
  Assert.AreEqual('', Fix(S, 2, GMsg(4), R));
  Assert.AreEqual(MsgMovedSuffix(_(R_GD_MOVED)), R);
  Assert.AreEqual('', Fix('  AB, C: Integer;', 1, GMsg(4), R));
  Assert.AreEqual(MsgMovedSuffix(_(R_GD_MOVED)), R);
  Assert.AreEqual('', Fix(S, 2, GMsg(40), R));
  Assert.AreEqual(MsgMovedSuffix(_(R_GD_MOVED)), R);
  // Der Name steht nur in einem Kommentar.
  Assert.AreEqual('', Fix('// A, B: Integer;', 1, GMsg(4), R));
  Assert.AreEqual(MsgMovedSuffix(_(R_GD_MOVED)), R);
  // Ein Bezeichner allein ist keine Gruppe.
  Assert.AreEqual('', Fix('  A: Integer;', 1, GMsg(3), R));
  Assert.AreEqual(MsgMovedSuffix(_(R_GD_MOVED)), R);
  // Die Meldung nennt keine Spalte.
  Assert.AreEqual('', Fix(S, 2, 'Grouped declaration', R));
  Assert.AreEqual(MsgNoColumn, R);
end;

procedure TTestRdxGroupedDeclFix.Plan_Adapter;
var
  SL : TStringList;
  F  : TLeakFinding;
  O  : TRdxFixOutcome;
begin
  SL := TStringList.Create;
  F := TLeakFinding.New('t.pas', '', 2, GMsg(3), fkGroupedDeclaration);
  try
    SL.Text := Join(['var', '  A, B: Integer;', 'begin']);
    O := PlanGroupedDeclaration(nil, SL, F, nil);
    Assert.IsTrue(O.Enabled, O.Reason);
    // Ohne Datei keine Hilfe.
    O := PlanGroupedDeclaration(nil, nil, F, nil);
    Assert.IsFalse(O.Enabled);
    Assert.AreEqual<Integer>(0, Length(O.Edits));
    Assert.AreNotEqual('', O.Reason);
  finally
    F.Free;
    SL.Free;
  end;
end;

{$IFNDEF FPC}

// ---- echter Detektor ----

procedure RunGrouped(AKind: TFindingKind; Root: TAstNode; const Path: string;
  Results: TObjectList<TLeakFinding>);
begin
  TGroupedDeclarationDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('grp', ASource, fkGroupedDeclaration, RunGrouped);
end;

// Der Plan fuer einen Fund ueber den Adapter der Hilfe (PlanGroupedDeclaration,
// wie die Tabelle ihn aufruft).
function PlanFor(const ASource: string; const ASeen: TSeen): TRdxFixOutcome;
var
  SL : TStringList;
  F  : TLeakFinding;
begin
  SL := TStringList.Create;
  F := TLeakFinding.New('t.pas', '', ASeen.Line, ASeen.Msg,
    fkGroupedDeclaration);
  try
    SL.Text := ASource;
    Result := PlanGroupedDeclaration(nil, SL, F, nil);
  finally
    F.Free;
    SL.Free;
  end;
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt.
function FixAll(const ASource: string): string;
const
  MAX_PASSES = 10;
var
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
  Pass : Integer;
begin
  Result := ASource;
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

procedure TTestRdxGroupedDeclFixDetector.Detector_RoundTrip;
var
  Bad, Good : string;
begin
  Bad := Join(['unit t;', 'interface', 'type', '  TFoo = class', '  private',
    '    FX, FY: Integer;', '  end;', 'implementation', 'var',
    '  A, B, C: string;', 'procedure P;', 'var', '  I, J: Integer;',
    'begin', 'end;', 'end.']);
  Good := Join(['unit t;', 'interface', 'type', '  TFoo = class', '  private',
    '    FX: Integer;', '    FY: Integer;', '  end;', 'implementation', 'var',
    '  A: string;', '  B: string;', '  C: string;', 'procedure P;', 'var',
    '  I: Integer;', '  J: Integer;', 'begin', 'end;', 'end.']);
  Assert.AreEqual<Integer>(3, Length(Detect(Bad)));
  Assert.AreEqual(Good, FixAll(Bad));
  Assert.AreEqual<Integer>(0, Length(Detect(Good)));
end;

procedure TTestRdxGroupedDeclFixDetector.Detector_CatalogExample;
var
  Meta      : TRuleMeta;
  Cat       : string;
  First     : string;
  Bad, Good : string;
begin
  // Die erste Zeile des Katalog-Beispiels 'bad' ('var A, B, C: Integer;');
  // die zweite ('field ...') ist kein Delphi und gehoert nicht in die Unit.
  Meta := TRuleCatalog.GetRuleCanonical(fkGroupedDeclaration);
  Cat := CatalogText(Meta.BadExample);
  Assert.IsTrue(Pos('A, B, C: Integer;', Cat) > 0, Meta.BadExample);
  First := Copy(Cat, 1, Pos(#13#10, Cat) - 1);
  Bad := Join(['unit t;', 'interface', 'implementation', First, 'end.']);
  Good := Join(['unit t;', 'interface', 'implementation', 'var A: Integer;',
    'var B: Integer;', 'var C: Integer;', 'end.']);
  Assert.AreEqual<Integer>(1, Length(Detect(Bad)));
  Assert.AreEqual(Good, FixAll(Bad));
end;

procedure TTestRdxGroupedDeclFixDetector.Detector_AnonymousType_NoHelp;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // Der Detektor meldet 'P, Q: record' - die Hilfe lehnt ab (je Name ein
  // eigener Typ).
  Src := Join(['unit t;', 'interface', 'implementation', 'var',
    '  P, Q: record X: Integer; end;', 'end.']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen));
  O := PlanFor(Src, Seen[0]);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_GD_TYPE), O.Reason);
end;

procedure TTestRdxGroupedDeclFixDetector.Detector_ParameterGroup_Silent;
var
  Src : string;
begin
  // Gruppierte Parameter sind Stil der Signatur: der Detektor schweigt, die
  // Hilfe wird nie angeboten.
  Src := Join(['unit t;', 'interface', 'procedure P(X, Y: Integer);',
    'implementation', 'procedure P(X, Y: Integer);', 'begin', 'end;',
    'end.']);
  Assert.AreEqual<Integer>(0, Length(Detect(Src)));
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxGroupedDeclFix);
{$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxGroupedDeclFixDetector);
{$ENDIF}

end.
