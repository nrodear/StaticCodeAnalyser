unit uTestRdxClassMethodFix;

// Editorhilfe SCA148 CanBeClassMethod (uRdxClassMethodFix): der Planer auf
// Text (erste Fixture, FPC-tauglich) und - nur Delphi - der
// Einstieg der Tabelle (TRdxFixTable.FixFor via PlanFixIn/FixAllWith,
// Adapter PlanCanBeClassMethod: zwei Ersetzungen) mit dem ECHTEN Detektor
// (uCanBeClassMethod) auf dem echten AST (zweite Fixture).
// Die Fixtures sind Units mit einer Klasse TMath (UnitWith); die gemeldete
// Zeile ist die des Implementierungskopfs (LineStartingWith).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxClassMethodFix = class
  public
    // ---- Umformung ----
    [Test] procedure Function_BecomesStaticClassFunction;
    [Test] procedure Procedure_BecomesStaticClassProcedure;
    [Test] procedure NoSectionOrExplicitTObject_Becomes;
    [Test] procedure DirectiveAfterDeclaration_Kept;
    [Test] procedure MultiLineDeclaration_Becomes;
    [Test] procedure CallsElsewhere_StayValid;
    // ---- Gegenproben ----
    [Test] procedure MemberInBody_NoHelp;
    [Test] procedure SelfOrTObjectMember_NoHelp;
    [Test] procedure Heritage_NoHelp;
    [Test] procedure BlockingDirective_NoHelp;
    [Test] procedure PublishedOrTypeInfo_NoHelp;
    [Test] procedure PropertyAccessor_NoHelp;
    [Test] procedure MethodPointerUse_NoHelp;
    [Test] procedure Overload_NoHelp;
    [Test] procedure AlreadyClassOrConstructor_NoHelp;
    [Test] procedure MovedLineOrMessage_NoHelp;
    [Test] procedure ClassNotInFile_NoHelp;
    [Test] procedure GenericOrHelper_NoHelp;
    [Test] procedure NestedTypeDirectiveOrAttribute_NoHelp;
    [Test] procedure AsmBody_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxClassMethodDetector = class
  public
    // ---- Einstieg der Tabelle (Adapter PlanCanBeClassMethod) ----
    [Test] procedure Adapter_TwoEditsAndName;
    [Test] procedure Adapter_StaleFinding_NoHelp;
    // ---- echter Detektor ----
    [Test] procedure Detector_ReportsImplementationHeader;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_Procedure_RoundTrip;
    [Test] procedure Detector_CatalogExample_NoClass_NoHelp;
    [Test] procedure Detector_PropertyAccessor_NoHelp;
    [Test] procedure Detector_MethodPointer_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uCanBeClassMethod,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // TRdxFixTable.CaptionFor
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText, PlanFixIn
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxClassMethodFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply, LineOf, LineStartingWith, NewMap

const
  HEAD = '  TMath = class';
  DECL_ADD = '    function Add(A, B: Integer): Integer;';
  STATIC_ADD = '    class function Add(A, B: Integer): Integer; static;';
  IMPL_ADD: array[0..3] of string = ('function TMath.Add(A, B: Integer): '
    + 'Integer;', 'begin', '  Result := A + B;', 'end;');
  IMPL_ADD_CLASS: array[0..3] of string = ('class function TMath.Add(A, B: '
    + 'Integer): Integer;', 'begin', '  Result := A + B;', 'end;');
  ADD_HEAD = 'function TMath.Add';
  // Die Meldung des Detektors (uCanBeClassMethod).
  MSG_FMT = 'Method %s never accesses Self or instance fields - could be '
    + 'declared as `class function`';

// ---- Helfer ----

// Eine Unit: Typabschnitt mit AHead (Kopf der Klasse TMath, davor ggf.
// weitere Typzeilen), Rumpf ABody, '  end;', dann die Implementierungen.
function UnitWith(const AHead: string; const ABody,
  AImpl: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'type', AHead]) + #13#10
    + Join(ABody) + #13#10 + Join(['  end;', 'implementation']) + #13#10
    + Join(AImpl) + #13#10 + 'end.';
end;

// Dasselbe mit dem Rumpf ABody und den Implementierungen IMPL_ADD.
function AddUnit(const AHead: string; const ABody: array of string): string;
begin
  Result := UnitWith(AHead, ABody, IMPL_ADD);
end;

function MsgFor(const AFull: string): string;
begin
  Result := Format(MSG_FMT, [AFull]);
end;

// Der Planer fuer Zeile ALine und Meldung AMsg: der neue Text, oder '' bei
// Ablehnung (AReason).
function PlanAt(const ASource: string; ALine: Integer; const AMsg: string;
  out AReason: string): string;
var
  Map   : TRdxCodeMap;
  Edits : TArray<TRdxEdit>;
  Ok    : Boolean;
begin
  Result := '';
  AReason := '';
  Map := NewMap(ASource);
  try
    Ok := TRdxClassMethodFix.MakeStatic(Map, ALine, AMsg, Edits, AReason);
  finally
    Map.Free;
  end;
  if Ok then
    Result := Apply(ASource, Edits);
end;

// Der Planer fuer den Kopf, der mit AHeadStart beginnt, Meldung zu AFull.
function Plan(const ASource, AHeadStart, AFull: string;
  out AReason: string): string;
var
  Line : Integer;
begin
  Line := LineStartingWith(ASource, AHeadStart);
  Assert.IsTrue(Line > 0, 'Kopf ' + AHeadStart);
  Result := PlanAt(ASource, Line, MsgFor(AFull), AReason);
end;

// Die Hilfe muss gelten (sonst scheitert der Test mit dem Grund).
function Applied(const ASource: string; const AHeadStart: string = ADD_HEAD;
  const AFull: string = 'TMath.Add'): string;
var
  R : string;
begin
  Result := Plan(ASource, AHeadStart, AFull, R);
  Assert.IsTrue(Result <> '', R);
end;

procedure AssertRefused(const ASource, AReason: string;
  const AHeadStart: string = ADD_HEAD; const AFull: string = 'TMath.Add');
var
  R : string;
begin
  Assert.AreEqual('', Plan(ASource, AHeadStart, AFull, R), 'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
end;

// ---- Umformung ----

procedure TTestRdxClassMethodFix.Function_BecomesStaticClassFunction;
begin
  Assert.AreEqual(UnitWith(HEAD, ['  public', STATIC_ADD], IMPL_ADD_CLASS),
    Applied(AddUnit(HEAD, ['  public', DECL_ADD])));
end;

procedure TTestRdxClassMethodFix.Procedure_BecomesStaticClassProcedure;
begin
  Assert.AreEqual(
    UnitWith(HEAD, ['  public',
      '    class procedure Show(const S: string); static;'],
      ['class procedure TMath.Show(const S: string);', 'begin', '  WriteLn(S);',
      'end;']),
    Applied(UnitWith(HEAD, ['  public', '    procedure Show(const S: string);'],
      ['procedure TMath.Show(const S: string);', 'begin', '  WriteLn(S);',
      'end;']), 'procedure TMath.Show', 'TMath.Show'));
end;

procedure TTestRdxClassMethodFix.NoSectionOrExplicitTObject_Becomes;
begin
  // Ohne Abschnitt (Vorgabe public, kein {$M+}) und mit '(TObject)'.
  Assert.AreEqual(UnitWith(HEAD, [STATIC_ADD], IMPL_ADD_CLASS),
    Applied(AddUnit(HEAD, [DECL_ADD])));
  Assert.AreEqual(
    UnitWith('  TMath = class(TObject)', ['  public', STATIC_ADD],
      IMPL_ADD_CLASS),
    Applied(AddUnit('  TMath = class(TObject)', ['  public', DECL_ADD])));
  Assert.AreEqual(
    UnitWith('  TMath = class sealed', ['  private', STATIC_ADD],
      IMPL_ADD_CLASS),
    Applied(AddUnit('  TMath = class sealed', ['  private', DECL_ADD])));
end;

procedure TTestRdxClassMethodFix.DirectiveAfterDeclaration_Kept;
begin
  // 'static' kommt direkt hinter die Signatur, 'inline' bleibt dahinter.
  Assert.AreEqual(
    UnitWith(HEAD, ['  public',
      '    class function Add(A, B: Integer): Integer; static; inline;'],
      IMPL_ADD_CLASS),
    Applied(AddUnit(HEAD, ['  public',
      '    function Add(A, B: Integer): Integer; inline;'])));
end;

procedure TTestRdxClassMethodFix.MultiLineDeclaration_Becomes;
begin
  Assert.AreEqual(
    UnitWith(HEAD, ['  public', '    class function Add(A,',
      '      B: Integer): Integer; static;'], IMPL_ADD_CLASS),
    Applied(AddUnit(HEAD, ['  public', '    function Add(A,',
      '      B: Integer): Integer;'])));
end;

procedure TTestRdxClassMethodFix.CallsElsewhere_StayValid;
const
  RUN: array[0..8] of string = ('procedure TMath.Run;', 'var', '  M: TMath;',
    'begin', '  FTotal := Add(1, 2);', '  M.Add(3, 4);',
    '  FTotal := TMath.Add(5, 6) + 1;', '  if FTotal > 0 then M.Add(7, 8);',
    'end;');
  BODY_BEFORE: array[0..4] of string = ('  private', '    FTotal: Integer;',
    '  public', DECL_ADD, '    procedure Run;');
  BODY_AFTER: array[0..4] of string = ('  private', '    FTotal: Integer;',
    '  public', STATIC_ADD, '    procedure Run;');
var
  Src, Fixed : string;
begin
  // Aufrufe mit Klammern - bare, ueber ein Objekt, ueber die Klasse - und
  // eine Rekursion im eigenen Rumpf bleiben gueltig.
  Src := UnitWith(HEAD, BODY_BEFORE, ['function TMath.Add(A, B: Integer): '
    + 'Integer;', 'begin', '  if A > 0 then', '    Result := Add(A - 1, B) + 1',
    '  else', '    Result := B;', 'end;']);
  Src := StringReplace(Src, 'end.', Join(RUN) + #13#10 + 'end.', []);
  Fixed := Applied(Src);
  Assert.IsTrue(Pos(STATIC_ADD, Fixed) > 0, Fixed);
  Assert.IsTrue(Pos('class function TMath.Add(A, B: Integer)', Fixed) > 0,
    Fixed);
  Assert.AreEqual(Src, StringReplace(StringReplace(Fixed, STATIC_ADD, DECL_ADD,
    []), 'class function TMath.Add', 'function TMath.Add', []),
    'sonst bleibt alles');
  Assert.IsTrue(Pos(Join(BODY_AFTER), Fixed) > 0, Fixed);
end;

// ---- Gegenproben ----

procedure TTestRdxClassMethodFix.MemberInBody_NoHelp;
var
  Src : string;
begin
  // Feld ohne F-Konvention (der Detektor sieht es, die Hilfe auch).
  Src := UnitWith(HEAD, ['  private', '    Limit: Integer;', '  public',
    DECL_ADD], ['function TMath.Add(A, B: Integer): Integer;', 'begin',
    '  Result := A + B + Limit;', 'end;']);
  AssertRefused(Src, _(R_CM_MEMBER, ['Limit', LineOf(Src, 'A + B + Limit')]));
  // Konstante der Klasse und bare Geschwister-Methode.
  Src := UnitWith(HEAD, ['  public', '    const Base = 10;', DECL_ADD,
    '    procedure Reset;'], ['function TMath.Add(A, B: Integer): Integer;',
    'begin', '  Result := A + Base;', 'end;']);
  AssertRefused(Src, _(R_CM_MEMBER, ['Base', LineOf(Src, 'A + Base')]));
  Src := UnitWith(HEAD, ['  public', DECL_ADD, '    procedure Reset;'],
    ['function TMath.Add(A, B: Integer): Integer;', 'begin', '  Reset;',
    '  Result := A + B;', 'end;']);
  AssertRefused(Src, _(R_CM_MEMBER, ['Reset', LineOf(Src, '  Reset;')]));
end;

procedure TTestRdxClassMethodFix.SelfOrTObjectMember_NoHelp;
var
  Src : string;
begin
  Src := UnitWith(HEAD, ['  public', DECL_ADD],
    ['function TMath.Add(A, B: Integer): Integer;', 'begin',
    '  if Self = nil then Exit(0);', '  Result := A + B;', 'end;']);
  AssertRefused(Src, _(R_CM_MEMBER, ['Self', LineOf(Src, 'Self = nil')]));
  Src := UnitWith(HEAD, ['  public', DECL_ADD],
    ['function TMath.Add(A, B: Integer): Integer;', 'begin',
    '  Result := A + B + Length(ClassName);', 'end;']);
  AssertRefused(Src, _(R_CM_MEMBER, ['ClassName',
    LineOf(Src, 'Length(ClassName)')]));
end;

procedure TTestRdxClassMethodFix.Heritage_NoHelp;
begin
  AssertRefused(AddUnit('  TMath = class(TBase)', ['  public', DECL_ADD]),
    _(R_CM_HERITAGE, ['TBase']));
  AssertRefused(AddUnit('  TMath = class(TObject, IMath)',
    ['  public', DECL_ADD]), _(R_CM_HERITAGE, ['TObject, IMath']));
end;

procedure TTestRdxClassMethodFix.BlockingDirective_NoHelp;
begin
  AssertRefused(AddUnit(HEAD, ['  public',
    '    function Add(A, B: Integer): Integer; virtual;']),
    _(R_CM_DIRECTIVE, ['virtual']));
  AssertRefused(AddUnit(HEAD, ['  public',
    '    function Add(A, B: Integer): Integer; overload;']),
    _(R_CM_DIRECTIVE, ['overload']));
  AssertRefused(AddUnit(HEAD, ['  public',
    '    function Add(A, B: Integer): Integer; reintroduce;']),
    _(R_CM_DIRECTIVE, ['reintroduce']));
end;

procedure TTestRdxClassMethodFix.PublishedOrTypeInfo_NoHelp;
begin
  AssertRefused(AddUnit(HEAD, ['  published', DECL_ADD]), _(R_CM_PUBLISHED));
  // Ohne Abschnitt unter {$M+}: published.
  AssertRefused(StringReplace(AddUnit(HEAD, [DECL_ADD]), 'interface',
    'interface' + #13#10 + '{$M+}', []), _(R_CM_DEFAULT_VIS));
end;

procedure TTestRdxClassMethodFix.PropertyAccessor_NoHelp;
var
  Src : string;
begin
  Src := UnitWith(HEAD, ['  private', '    function GetSize: Integer;',
    '  public', '    property Size: Integer read GetSize;'],
    ['function TMath.GetSize: Integer;', 'begin', '  Result := 42;', 'end;']);
  AssertRefused(Src, _(R_CM_IN_CLASS, ['GetSize', LineOf(Src, 'read GetSize')]),
    'function TMath.GetSize', 'TMath.GetSize');
end;

procedure TTestRdxClassMethodFix.MethodPointerUse_NoHelp;

  // Die Unit mit Add und einer Methode Wire, deren Rumpf AStmt ist.
  function WithWire(const AStmt: string): string;
  begin
    Result := UnitWith(HEAD, ['  public', DECL_ADD, '    procedure Wire;'],
      ['function TMath.Add(A, B: Integer): Integer;', 'begin',
      '  Result := A + B;', 'end;', 'procedure TMath.Wire;', 'begin', AStmt,
      'end;']);
  end;

var
  Src : string;
begin
  Src := WithWire('  OnAdd := Add;');
  AssertRefused(Src, _(R_CM_POINTER, ['Add', LineOf(Src, 'OnAdd := Add')]));
  Src := WithWire('  Run(Self, Add);');
  AssertRefused(Src, _(R_CM_POINTER, ['Add', LineOf(Src, 'Run(Self, Add)')]));
  Src := WithWire('  P := @Add;');
  AssertRefused(Src, _(R_CM_POINTER, ['Add', LineOf(Src, '@Add')]));
  Src := WithWire('  Btn.OnClick := Obj.Add;');
  AssertRefused(Src, _(R_CM_POINTER, ['Add', LineOf(Src, 'Obj.Add')]));
end;

procedure TTestRdxClassMethodFix.Overload_NoHelp;
begin
  AssertRefused(UnitWith(HEAD, ['  public',
    '    function Add(A, B: Integer): Integer; overload;',
    '    function Add(A: Integer): Integer; overload;'],
    ['function TMath.Add(A, B: Integer): Integer;', 'begin',
    '  Result := A + B;', 'end;', 'function TMath.Add(A: Integer): Integer;',
    'begin', '  Result := A;', 'end;']), _(R_CM_IMPLS, [2, 'Add']));
end;

procedure TTestRdxClassMethodFix.AlreadyClassOrConstructor_NoHelp;
begin
  AssertRefused(UnitWith(HEAD, ['  public', STATIC_ADD], IMPL_ADD_CLASS),
    MsgStaleSuffix(_(R_CM_ALREADY)), 'class function TMath.Add');
  AssertRefused(UnitWith(HEAD, ['  public', '    constructor Create;'],
    ['constructor TMath.Create;', 'begin', 'end;']),
    _(R_CM_KIND, ['constructor']), 'constructor TMath.Create', 'TMath.Create');
end;

procedure TTestRdxClassMethodFix.MovedLineOrMessage_NoHelp;
var
  Src, R : string;
  Line   : Integer;
begin
  Src := AddUnit(HEAD, ['  public', DECL_ADD]);
  Line := LineStartingWith(Src, ADD_HEAD);
  Assert.AreEqual('', PlanAt(Src, Line - 1, MsgFor('TMath.Add'), R));
  Assert.AreEqual(MsgMovedSuffix(_(R_CM_NO_HEAD, ['TMath.Add'])), R,
    'Zeile davor');
  Assert.AreEqual('', PlanAt(Src, Line, MsgFor('TMath.Other'), R));
  Assert.AreEqual(MsgMovedSuffix(_(R_CM_NO_HEAD, ['TMath.Other'])), R,
    'anderer Name');
  Assert.AreEqual('', PlanAt(Src, Line, MsgFor('Add'), R));
  Assert.AreEqual(_(R_CM_MESSAGE), R, 'ohne Klasse');
  Assert.AreEqual('', PlanAt(Src, Line, 'x', R));
  Assert.AreEqual(_(R_CM_MESSAGE), R, 'fremde Meldung');
  Assert.AreEqual('', PlanAt(Src, Line, MsgFor('TOuter.TMath.Add'), R));
  Assert.AreEqual(_(R_CM_NESTED_NAME, ['TOuter.TMath.Add']), R, 'geschachtelt');
end;

procedure TTestRdxClassMethodFix.ClassNotInFile_NoHelp;
begin
  // Das Katalogbeispiel: nur die Implementierung.
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'function TMath.Add(A, B: Integer): Integer;', 'begin',
    '  Result := A + B;', 'end;', 'end.']), _(R_CM_NO_CLASS, ['TMath']));
  // Ein record ist keine Klasse.
  AssertRefused(AddUnit('  TMath = record', ['    function Add(A, B: Integer): '
    + 'Integer;']), _(R_CM_NO_CLASS, ['TMath']));
end;

procedure TTestRdxClassMethodFix.GenericOrHelper_NoHelp;
begin
  AssertRefused(UnitWith('  TMath<T> = class', ['  public', DECL_ADD],
    ['function TMath<T>.Add(A, B: Integer): Integer;', 'begin',
    '  Result := A + B;', 'end;']), _(R_CM_GENERIC), 'function TMath<T>.Add');
  AssertRefused(AddUnit('  TMath = class helper for TObject',
    ['  public', DECL_ADD]), _(R_CM_HELPER));
end;

procedure TTestRdxClassMethodFix.NestedTypeDirectiveOrAttribute_NoHelp;
begin
  AssertRefused(AddUnit(HEAD, ['  public', '    type TKind = Integer;',
    '  public', DECL_ADD]), _(R_CM_NESTED_TYPE));
  AssertRefused(AddUnit(HEAD, ['  public', '  {$IFDEF X}', DECL_ADD,
    '  {$ENDIF}']), _(R_CM_CLASS_DIRECTIVE));
  AssertRefused(AddUnit(HEAD, ['  public', '    [Test]', DECL_ADD]),
    _(R_CM_ATTR));
end;

procedure TTestRdxClassMethodFix.AsmBody_NoHelp;
begin
  AssertRefused(UnitWith(HEAD, ['  public', DECL_ADD],
    ['function TMath.Add(A, B: Integer): Integer;', 'asm', '  ADD EAX, EDX',
    'end;']), _(R_CM_ASM));
end;

{$IFNDEF FPC}

{ ---- Einstieg der Tabelle und echter Detektor ---- }

// Die Funde der Art SCA148 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TCanBeClassMethodDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_cbcm_', ASource, fkCanBeClassMethod, RunDetector);
end;

// Dasselbe in der Form TDetectFunc (FixAllWith).
function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_cbcm_', ASource, AKind, RunDetector);
end;

// Die Hilfe fuer Zeile und Meldung ueber den Einstieg der Tabelle
// (PlanFixIn: TRdxFixTable.FixFor, Adapter PlanCanBeClassMethod - zwei
// Ersetzungen, gesperrt ohne Ersetzungen, Name aus der Meldung).
function PlanVia(const ASource: string; ALine: Integer;
  const AMsg: string): TRdxFixOutcome;
var
  S : TSeen;
begin
  S := Default(TSeen);
  S.Line := ALine;
  S.Msg := AMsg;
  Result := PlanFixIn(ASource, 't.pas', fkCanBeClassMethod, S);
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
  Result := FixAllWith(ASource, fkCanBeClassMethod, DetectKind);
end;

procedure TTestRdxClassMethodDetector.Adapter_TwoEditsAndName;
var
  Src : string;
  O   : TRdxFixOutcome;
begin
  Src := AddUnit(HEAD, ['  public', DECL_ADD]);
  O := PlanVia(Src, LineStartingWith(Src, ADD_HEAD), MsgFor('TMath.Add'));
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual('Add', O.Name, 'Name fuer den Menuetext');
  Assert.AreEqual<Integer>(2, Length(O.Edits), 'Deklaration und Kopf');
  Assert.AreEqual('function Add(A, B: Integer): Integer;', O.Edits[0].Expected);
  Assert.AreEqual('class function Add(A, B: Integer): Integer; static;',
    O.Edits[0].NewText);
  Assert.AreEqual('function', O.Edits[1].Expected);
  Assert.AreEqual('class function', O.Edits[1].NewText);
  Assert.AreEqual<Integer>(LineStartingWith(Src, ADD_HEAD),
    O.Edits[1].Span.StartLine);
  Assert.IsFalse(O.ChangesBehavior, 'bedeutungsgleich (Tabellenzeile)');
  Assert.IsTrue(Pos('of object', O.Hint) > 0, O.Hint);
  Assert.IsTrue(Pos('Add', TRdxFixTable.CaptionFor(fkCanBeClassMethod, O)) > 0,
    'der Menuetext nennt die Methode');
end;

procedure TTestRdxClassMethodDetector.Adapter_StaleFinding_NoHelp;
var
  Src : string;
  O   : TRdxFixOutcome;
begin
  Src := AddUnit(HEAD, ['  public', DECL_ADD]);
  O := PlanVia(Src, LineStartingWith(Src, ADD_HEAD) + 1, MsgFor('TMath.Add'));
  Assert.IsFalse(O.Enabled, 'gesperrt');
  Assert.AreEqual(MsgMovedSuffix(_(R_CM_NO_HEAD, ['TMath.Add'])), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
  Assert.AreEqual('Add', O.Name, 'der Name steht auch gesperrt');
end;

procedure TTestRdxClassMethodDetector.Detector_ReportsImplementationHeader;
var
  Src  : string;
  Seen : TArray<TSeen>;
begin
  Src := AddUnit(HEAD, ['  public', DECL_ADD]);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(LineStartingWith(Src, ADD_HEAD), Seen[0].Line,
    'Zeile des Implementierungskopfs');
  Assert.IsTrue(Pos('Method TMath.Add never accesses Self', Seen[0].Msg) = 1,
    Seen[0].Msg);
end;

procedure TTestRdxClassMethodDetector.Detector_RoundTrip;
var
  Fixed : string;
begin
  Fixed := FixAll(AddUnit(HEAD, ['  public', DECL_ADD]));
  Assert.AreEqual(UnitWith(HEAD, ['  public', STATIC_ADD], IMPL_ADD_CLASS),
    Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)), 'der Detektor schweigt');
end;

procedure TTestRdxClassMethodDetector.Detector_Procedure_RoundTrip;
begin
  Assert.AreEqual(
    UnitWith(HEAD, ['  public',
      '    class procedure Show(const S: string); static;'],
      ['class procedure TMath.Show(const S: string);', 'begin', '  WriteLn(S);',
      'end;']),
    FixAll(UnitWith(HEAD, ['  public', '    procedure Show(const S: string);'],
      ['procedure TMath.Show(const S: string);', 'begin', '  WriteLn(S);',
      'end;'])));
end;

procedure TTestRdxClassMethodDetector.Detector_CatalogExample_NoClass_NoHelp;
var
  Meta : TRuleMeta;
  O    : TRdxFixOutcome;
begin
  // Das Katalogbeispiel nennt nur die Implementierung - ohne Klasse in der
  // Datei kennt die Hilfe die Member nicht.
  Meta := TRuleCatalog.GetRuleCanonical(fkCanBeClassMethod);
  Assert.IsTrue(Pos('TMath.Add', Meta.BadExample) > 0, Meta.BadExample);
  O := PlanFirst(Join(['unit t;', 'interface', 'implementation',
    CatalogText(Meta.BadExample), 'end.']));
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_CM_NO_CLASS, ['TMath']), O.Reason);
end;

procedure TTestRdxClassMethodDetector.Detector_PropertyAccessor_NoHelp;
var
  Src : string;
  O   : TRdxFixOutcome;
begin
  // Der Detektor prueft keine Accessoren - 'class ... static' als Getter
  // einer Objekt-Property uebersetzt nicht.
  Src := UnitWith(HEAD, ['  private', '    function GetSize: Integer;',
    '  public', '    property Size: Integer read GetSize;'],
    ['function TMath.GetSize: Integer;', 'begin', '  Result := 42;', 'end;']);
  O := PlanFirst(Src);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_CM_IN_CLASS, ['GetSize', LineOf(Src, 'read GetSize')]),
    O.Reason);
end;

procedure TTestRdxClassMethodDetector.Detector_MethodPointer_NoHelp;
var
  Src : string;
  O   : TRdxFixOutcome;
begin
  // Wire nutzt FOnAdd (Feld) und wird nicht gemeldet; Add schon - die
  // Zuweisung an den Methodenzeiger sperrt.
  Src := UnitWith('  TAddFunc = function(A, B: Integer): Integer of object;'
    + #13#10 + HEAD, ['  private', '    FOnAdd: TAddFunc;', '  public', DECL_ADD,
    '    procedure Wire;'], ['function TMath.Add(A, B: Integer): Integer;',
    'begin', '  Result := A + B;', 'end;', 'procedure TMath.Wire;', 'begin',
    '  FOnAdd := Add;', 'end;']);
  O := PlanFirst(Src);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_CM_POINTER, ['Add', LineOf(Src, 'FOnAdd := Add')]),
    O.Reason);
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxClassMethodFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxClassMethodDetector);
  {$ENDIF}

end.
