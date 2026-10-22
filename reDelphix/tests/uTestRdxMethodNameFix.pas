unit uTestRdxMethodNameFix;

// Editorhilfe SCA106 MethodName (uRdxMethodNameFix): der Planer auf Text
// (erste Fixture) und der ECHTE Detektor (uMethodName) auf dem echten AST
// (zweite Fixture, nur Delphi). Den Adapter der Tabelle (PlanMethodName
// ueber TRdxFixFrame) traegt uRdxFixTable - die Rundlaeufe hier gehen ueber
// ihren Einstieg (TRdxFixTable.FixFor), wie der Anbieter.
// Die Standard-Unit (StdUnit) hat die Klasse TFoo ab Zeile 4, 'public' auf
// Zeile 5, die Deklaration auf Zeile 6 (DECL_LINE) und den Kopf der
// Implementierung auf Zeile 9 (IMPL_LINE).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxMethodNameFix = class
  public
    // ---- Umformung ----
    [Test] procedure DeclAndImpl_Capitalized;
    [Test] procedure ClassFunctionWithParams_Capitalized;
    [Test] procedure GenericClass_Capitalized;
    [Test] procedure NestedClass_Capitalized;
    [Test] procedure ImplAlreadyUpper_OnlyDeclaration;
    [Test] procedure CallsAndComments_Unchanged;
    [Test] procedure PublishedMethod_Capitalized;
    [Test] procedure OtherClassSameName_Untouched;
    // ---- Gegenproben ----
    [Test] procedure Overload_NoHelp;
    [Test] procedure ConditionalTwins_NoHelp;
    [Test] procedure NoImplementation_NoHelp;
    [Test] procedure TwoImplementations_NoHelp;
    [Test] procedure FreeRoutineRecordInterface_NoHelp;
    [Test] procedure MovedLine_NoHelp;
    [Test] procedure CommentOrString_NoHelp;
    [Test] procedure AlreadyCapitalized_NoHelp;
    [Test] procedure StringLiteral_NoHelp;
    [Test] procedure IncludeInClass_NoHelp;
    [Test] procedure MessageWithoutName_NoHelp;
    [Test] procedure ImplementationOnly_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxMethodNameDetector = class
  public
    [Test] procedure Detector_ReportsDeclarationLine;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_TwoMethods_BothFixed;
    [Test] procedure Detector_ImplSpelledDifferently_Fixed;
    [Test] procedure Detector_CatalogExample_InClass_Fixed;
    [Test] procedure Detector_CatalogExample_FreeRoutine_NoHelp;
    [Test] procedure Detector_Overload_NoHelp;
    [Test] procedure Table_NameAndTwoEdits;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uMethodName,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // TRdxFixTable.FixFor
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxMethodNameFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply, LineOf, NewMap

const
  // Die Meldung des Detektors (uMethodName), Name als Argument.
  MSG_FMT = 'Method `%s` should be PascalCase (start with uppercase letter).';
  DECL_LINE = 6;
  IMPL_LINE = 9;

// ---- Helfer ----

// Eine Unit mit der Klasse TFoo: AMembers ab Zeile 5, dahinter 'end;',
// implementation und AImpl.
function UnitWith(const AMembers, AImpl: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'type', '  TFoo = class']) + #13#10
    + Join(AMembers) + #13#10 + Join(['  end;', 'implementation']) + #13#10
    + Join(AImpl) + #13#10 + 'end.';
end;

// TFoo mit 'procedure ADecl;' unter public (Zeile 6) und der
// Implementierung 'procedure TFoo.AImpl;' (Zeile 9).
function StdUnit(const ADecl, AImpl: string): string;
begin
  Result := UnitWith(['  public', '    procedure ' + ADecl + ';'],
    ['procedure TFoo.' + AImpl + ';', 'begin', 'end;']);
end;

// Der Planer fuer Zeile ALine mit der Meldung AMessage.
function PlanOf(const ASource: string; ALine: Integer; const AMessage: string;
  out APlan: TRdxMethodNamePlan; out AReason: string): Boolean;
var
  Map : TRdxCodeMap;
begin
  Map := NewMap(ASource);
  try
    Result := TRdxMethodNameFix.Capitalize(Map, ALine, AMessage, APlan,
      AReason);
  finally
    Map.Free;
  end;
end;

// Die Hilfe fuer den Namen AName auf ALine muss gelten; der neue Text.
function Applied(const ASource: string; ALine: Integer;
  const AName: string): string;
var
  P : TRdxMethodNamePlan;
  R : string;
begin
  Assert.IsTrue(PlanOf(ASource, ALine, Format(MSG_FMT, [AName]), P, R), R);
  Result := Apply(ASource, P.Edits);
end;

// Keine Hilfe fuer den Namen AName auf ALine, Grund AReason.
procedure AssertRefused(const ASource: string; ALine: Integer;
  const AName, AReason: string);
var
  P : TRdxMethodNamePlan;
  R : string;
begin
  Assert.IsFalse(PlanOf(ASource, ALine, Format(MSG_FMT, [AName]), P, R),
    'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
  Assert.AreEqual<Integer>(0, Length(P.Edits), 'keine Ersetzung');
end;

// ---- Umformung ----

procedure TTestRdxMethodNameFix.DeclAndImpl_Capitalized;
var
  P : TRdxMethodNamePlan;
  R : string;
begin
  Assert.AreEqual(StdUnit('DoWork', 'DoWork'),
    Applied(StdUnit('doWork', 'doWork'), DECL_LINE, 'doWork'));
  // Zwei Ersetzungen in EINEM Plan, nur das Wort; der Name fuer den
  // Menuetext ist der neue.
  Assert.IsTrue(PlanOf(StdUnit('doWork', 'doWork'), DECL_LINE,
    Format(MSG_FMT, ['doWork']), P, R), R);
  Assert.AreEqual('DoWork', P.Name, 'Name fuer den Menuetext');
  Assert.AreEqual<Integer>(2, Length(P.Edits), 'Deklaration und Implementierung');
  Assert.AreEqual<Integer>(DECL_LINE, P.Edits[0].Span.StartLine);
  Assert.AreEqual<Integer>(IMPL_LINE, P.Edits[1].Span.StartLine);
  Assert.AreEqual('doWork', P.Edits[0].Expected);
  Assert.AreEqual('DoWork', P.Edits[0].NewText);
  Assert.AreEqual('doWork', P.Edits[1].Expected);
  Assert.AreEqual('DoWork', P.Edits[1].NewText);
end;

procedure TTestRdxMethodNameFix.ClassFunctionWithParams_Capitalized;
var
  Src : string;
begin
  // 'class' vor dem Routinenwort, Parameter und Rueckgabe.
  Src := UnitWith(['  public',
    '    class function calc(A, B: Integer): Integer;'],
    ['class function TFoo.calc(A, B: Integer): Integer;', 'begin',
     '  Result := A + B;', 'end;']);
  Assert.AreEqual(StringReplace(Src, 'calc(', 'Calc(', [rfReplaceAll]),
    Applied(Src, DECL_LINE, 'calc'));
end;

procedure TTestRdxMethodNameFix.GenericClass_Capitalized;
var
  Src : string;
begin
  Src := Join(['unit t;', 'interface', 'type', '  TFoo<T> = class',
    '  public', '    procedure doWork;', '  end;', 'implementation',
    'procedure TFoo<T>.doWork;', 'begin', 'end;', 'end.']);
  Assert.AreEqual(StringReplace(Src, 'doWork', 'DoWork', [rfReplaceAll]),
    Applied(Src, DECL_LINE, 'doWork'));
end;

procedure TTestRdxMethodNameFix.NestedClass_Capitalized;
var
  Src : string;
begin
  // Die Implementierung traegt beide Klassen ('TOuter.TInner.doWork').
  Src := Join(['unit t;', 'interface', 'type', '  TOuter = class',
    '  public', '    type', '      TInner = class', '      public',
    '        procedure doWork;', '      end;', '  end;', 'implementation',
    'procedure TOuter.TInner.doWork;', 'begin', 'end;', 'end.']);
  Assert.AreEqual(StringReplace(Src, 'doWork', 'DoWork', [rfReplaceAll]),
    Applied(Src, 9, 'doWork'));
end;

procedure TTestRdxMethodNameFix.ImplAlreadyUpper_OnlyDeclaration;
var
  P : TRdxMethodNamePlan;
  R : string;
begin
  // Delphi nimmt die Implementierung auch anders geschrieben an - beginnt
  // sie schon gross, bleibt es bei einer Ersetzung.
  Assert.AreEqual(StdUnit('DoWork', 'DoWork'),
    Applied(StdUnit('doWork', 'DoWork'), DECL_LINE, 'doWork'));
  Assert.IsTrue(PlanOf(StdUnit('doWork', 'DoWork'), DECL_LINE,
    Format(MSG_FMT, ['doWork']), P, R), R);
  Assert.AreEqual<Integer>(1, Length(P.Edits), 'nur die Deklaration');
  // Nur der erste Buchstabe: der Rest der Schreibweise bleibt.
  Assert.AreEqual(StdUnit('DoWork', 'Dowork'),
    Applied(StdUnit('doWork', 'dowork'), DECL_LINE, 'doWork'));
end;

procedure TTestRdxMethodNameFix.CallsAndComments_Unchanged;
begin
  // Aufrufe und Kommentare bleiben wie sie sind (Delphi bindet ohne
  // Gross/klein) - die Hilfe aendert nur die beiden Koepfe.
  Assert.AreEqual(
    UnitWith(['  public', '    procedure DoWork;', '    procedure Run;'],
      ['procedure TFoo.DoWork;', 'begin', 'end;', 'procedure TFoo.Run;',
       'begin', '  doWork; // doWork bleibt', '  Self.doWork;', 'end;']),
    Applied(
      UnitWith(['  public', '    procedure doWork;', '    procedure Run;'],
        ['procedure TFoo.doWork;', 'begin', 'end;', 'procedure TFoo.Run;',
         'begin', '  doWork; // doWork bleibt', '  Self.doWork;', 'end;']),
      DECL_LINE, 'doWork'));
end;

procedure TTestRdxMethodNameFix.PublishedMethod_Capitalized;
begin
  // published: eine Formdatei, die 'OnClick = doWork' bindet, bindet weiter
  // (TObject.MethodAddress vergleicht ohne Gross/klein) - keine Sperre.
  Assert.AreEqual(
    UnitWith(['  published', '    procedure DoWork;'],
      ['procedure TFoo.DoWork;', 'begin', 'end;']),
    Applied(UnitWith(['  published', '    procedure doWork;'],
      ['procedure TFoo.doWork;', 'begin', 'end;']), DECL_LINE, 'doWork'));
end;

procedure TTestRdxMethodNameFix.OtherClassSameName_Untouched;
var
  Src : string;
begin
  Src := Join(['unit t;', 'interface', 'type', '  TFoo = class', '  public',
    '    procedure doWork;', '  end;', '  TBar = class', '  public',
    '    procedure doWork;', '  end;', 'implementation',
    'procedure TFoo.doWork;', 'begin', 'end;', 'procedure TBar.doWork;',
    'begin', 'end;', 'end.']);
  // TFoo (Zeile 6) - TBar bleibt.
  Assert.AreEqual(Join(['unit t;', 'interface', 'type', '  TFoo = class',
    '  public', '    procedure DoWork;', '  end;', '  TBar = class',
    '  public', '    procedure doWork;', '  end;', 'implementation',
    'procedure TFoo.DoWork;', 'begin', 'end;', 'procedure TBar.doWork;',
    'begin', 'end;', 'end.']), Applied(Src, DECL_LINE, 'doWork'));
  // TBar (Zeile 10) - TFoo bleibt.
  Assert.AreEqual(Join(['unit t;', 'interface', 'type', '  TFoo = class',
    '  public', '    procedure doWork;', '  end;', '  TBar = class',
    '  public', '    procedure DoWork;', '  end;', 'implementation',
    'procedure TFoo.doWork;', 'begin', 'end;', 'procedure TBar.DoWork;',
    'begin', 'end;', 'end.']), Applied(Src, 10, 'doWork'));
end;

// ---- Gegenproben ----

procedure TTestRdxMethodNameFix.Overload_NoHelp;
begin
  AssertRefused(UnitWith(['  public', '    procedure doWork; overload;',
    '    procedure doWork(A: Integer); overload;'],
    ['procedure TFoo.doWork;', 'begin', 'end;',
     'procedure TFoo.doWork(A: Integer);', 'begin', 'end;']),
    DECL_LINE, 'doWork', _(R_MN_OVERLOAD, ['doWork']));
end;

procedure TTestRdxMethodNameFix.ConditionalTwins_NoHelp;
begin
  // Zwei Deklarationen ohne overload ($IFDEF-Zweige): welche gemeint ist,
  // weiss die Hilfe nicht.
  AssertRefused(UnitWith(['  public', '  {$IFDEF X}', '    procedure doWork;',
    '  {$ELSE}', '    procedure doWork;', '  {$ENDIF}'],
    ['procedure TFoo.doWork;', 'begin', 'end;']), DECL_LINE + 1, 'doWork',
    _(R_MN_DECLS, [2, 'doWork', 'TFoo']));
end;

procedure TTestRdxMethodNameFix.NoImplementation_NoHelp;
begin
  AssertRefused(UnitWith(['  public', '    procedure doWork; virtual; abstract;'],
    ['procedure Other;', 'begin', 'end;']), DECL_LINE, 'doWork',
    _(R_MN_NO_IMPL, ['TFoo', 'doWork']));
end;

procedure TTestRdxMethodNameFix.TwoImplementations_NoHelp;
begin
  AssertRefused(UnitWith(['  public', '    procedure doWork;'],
    ['{$IFDEF X}', 'procedure TFoo.doWork;', 'begin', 'end;', '{$ELSE}',
     'procedure TFoo.doWork;', 'begin', '  Beep;', 'end;', '{$ENDIF}']),
    DECL_LINE, 'doWork', _(R_MN_IMPLS, [2, 'TFoo', 'doWork']));
end;

procedure TTestRdxMethodNameFix.FreeRoutineRecordInterface_NoHelp;
var
  Src : string;
begin
  // Freie Routine: die Deklaration im interface-Teil und der Kopf im
  // implementation-Teil.
  Src := Join(['unit t;', 'interface', 'procedure doWork;', 'implementation',
    'procedure doWork;', 'begin', 'end;', 'end.']);
  AssertRefused(Src, 3, 'doWork', _(R_MN_NO_CLASS, ['doWork']));
  AssertRefused(Src, 5, 'doWork', _(R_MN_NO_CLASS, ['doWork']));
  // Methode eines records.
  AssertRefused(Join(['unit t;', 'interface', 'type', '  TRec = record',
    '    procedure doWork;', '  end;', 'implementation',
    'procedure TRec.doWork;', 'begin', 'end;', 'end.']), 5, 'doWork',
    _(R_MN_NO_CLASS, ['doWork']));
  // Methode eines Interfaces.
  AssertRefused(Join(['unit t;', 'interface', 'type', '  IFoo = interface',
    '    procedure doWork;', '  end;', 'implementation', 'end.']), 5, 'doWork',
    _(R_MN_NO_CLASS, ['doWork']));
end;

procedure TTestRdxMethodNameFix.MovedLine_NoHelp;
var
  Src : string;
begin
  Src := StdUnit('doWork', 'doWork');
  AssertRefused(Src, DECL_LINE - 1, 'doWork',
    MsgMovedSuffix(_(R_MN_NO_HEAD, ['doWork'])));
  AssertRefused(Src, DECL_LINE + 1, 'doWork',
    MsgMovedSuffix(_(R_MN_NO_HEAD, ['doWork'])));
  AssertRefused(Src, 99, 'doWork', MsgMovedSuffix(_(R_MN_NO_HEAD, ['doWork'])));
  AssertRefused(Src, 0, 'doWork', MsgMovedSuffix(_(R_MN_NO_HEAD, ['doWork'])));
  // Ein anderer Name auf der Zeile.
  AssertRefused(Src, DECL_LINE, 'doOther',
    MsgMovedSuffix(_(R_MN_NO_HEAD, ['doOther'])));
end;

procedure TTestRdxMethodNameFix.CommentOrString_NoHelp;
var
  Src : string;
begin
  // Kommentar und String sind nie Code.
  AssertRefused(UnitWith(['  public', '    // procedure doWork;',
    '    procedure Run;'], ['procedure TFoo.Run;', 'begin', 'end;']),
    DECL_LINE, 'doWork', MsgMovedSuffix(_(R_MN_NO_HEAD, ['doWork'])));
  AssertRefused(UnitWith(['  public', '    { procedure doWork; }',
    '    procedure Run;'], ['procedure TFoo.Run;', 'begin', 'end;']),
    DECL_LINE, 'doWork', MsgMovedSuffix(_(R_MN_NO_HEAD, ['doWork'])));
  Src := UnitWith(['  public', '    procedure Run;'],
    ['procedure TFoo.Run;', 'begin', '  S := ''procedure doWork;'';', 'end;']);
  AssertRefused(Src, LineOf(Src, 'S :='), 'doWork',
    MsgMovedSuffix(_(R_MN_NO_HEAD, ['doWork'])));
end;

procedure TTestRdxMethodNameFix.AlreadyCapitalized_NoHelp;
begin
  // Der Fund ist veraltet: die Deklaration beginnt schon gross.
  AssertRefused(StdUnit('DoWork', 'DoWork'), DECL_LINE, 'doWork',
    MsgStaleSuffix(_(R_MN_SPELLING, ['DoWork', 'doWork'])));
end;

procedure TTestRdxMethodNameFix.StringLiteral_NoHelp;
var
  Src : string;
begin
  // Aufruf per Name: ein Vergleich dort kann Gross/klein beachten.
  Src := UnitWith(['  public', '    procedure doWork;', '    procedure Run;'],
    ['procedure TFoo.doWork;', 'begin', 'end;', 'procedure TFoo.Run;',
     'begin', '  if MethodAddress(''doWork'') = nil then Exit;', 'end;']);
  AssertRefused(Src, DECL_LINE, 'doWork',
    _(R_MN_LITERAL, ['doWork', LineOf(Src, 'MethodAddress')]));
end;

procedure TTestRdxMethodNameFix.IncludeInClass_NoHelp;
begin
  AssertRefused(UnitWith(['  public', '    procedure doWork;',
    '    {$I more.inc}'], ['procedure TFoo.doWork;', 'begin', 'end;']),
    DECL_LINE, 'doWork', _(R_MN_INCLUDE, [DECL_LINE + 1]));
end;

procedure TTestRdxMethodNameFix.MessageWithoutName_NoHelp;
var
  P : TRdxMethodNamePlan;
  R : string;
begin
  Assert.IsFalse(PlanOf(StdUnit('doWork', 'doWork'), DECL_LINE,
    'Method should be PascalCase.', P, R));
  Assert.AreEqual(_(R_MN_NO_NAME), R);
  // Ein Name, der schon gross beginnt, ist kein Fund dieser Regel.
  AssertRefused(StdUnit('DoWork', 'DoWork'), DECL_LINE, 'DoWork',
    _(R_MN_NO_NAME));
end;

procedure TTestRdxMethodNameFix.ImplementationOnly_NoHelp;
begin
  // Ohne Deklaration davor meldet der Detektor den Kopf der Implementierung
  // (Klasse in einem Include).
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'procedure TFoo.doWork;', 'begin', 'end;', 'end.']), 4, 'doWork',
    _(R_MN_IMPL_ONLY, ['doWork']));
end;

{$IFNDEF FPC}

{ ---- Detektor ---- }

// Die Funde der Art SCA106 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TMethodNameDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_mn_', ASource, fkMethodName, RunDetector);
end;

// Die Hilfe fuer einen Fund ueber den Einstieg der Tabelle - wie der
// Anbieter; der Adapter braucht keinen Quellstellen-Dienst.
function TablePlan(const ASource: string; const ASeen: TSeen): TRdxFixOutcome;
var
  SL : TStringList;
  F  : TLeakFinding;
begin
  SL := TStringList.Create;
  F := TLeakFinding.New('t.pas', '', ASeen.Line, ASeen.Msg, fkMethodName);
  try
    SL.Text := ASource;
    Result := TRdxFixTable.FixFor(nil, SL, F, nil);
  finally
    F.Free;
    SL.Free;
  end;
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt - ueber die Tabelle (Zeile und Meldung aus dem Fund).
function FixAll(const ASource: string): string;
const
  MAX_PASSES = 10;
var
  Pass : Integer;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  Result := ASource;
  for Pass := 1 to MAX_PASSES do
  begin
    Seen := Detect(Result);
    if Length(Seen) = 0 then
      Exit;
    O := TablePlan(Result, Seen[0]);
    Assert.IsTrue(O.Enabled, Format('Zeile %d: %s', [Seen[0].Line, O.Reason]));
    Result := Apply(Result, O.Edits);
  end;
  Assert.Fail('der Detektor schweigt auch nach zehn Durchlaeufen nicht');
end;

// Der erste Fund des Detektors bekommt keine Hilfe, Grund AReason.
procedure AssertDetectorRefused(const ASource, AReason: string);
var
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet');
  O := TablePlan(ASource, Seen[0]);
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(AReason, O.Reason, 'Grund');
end;

procedure TTestRdxMethodNameDetector.Detector_ReportsDeclarationLine;
var
  Seen : TArray<TSeen>;
begin
  // EIN Fund fuer Deklaration und Implementierung, auf der Deklaration;
  // die Meldung traegt den Namen in Backticks.
  Seen := Detect(StdUnit('doWork', 'doWork'));
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(DECL_LINE, Seen[0].Line, 'Zeile der Deklaration');
  Assert.AreEqual(Format(MSG_FMT, ['doWork']), Seen[0].Msg);
  Assert.AreEqual('doWork', MethodNameOf(Seen[0].Msg));
end;

procedure TTestRdxMethodNameDetector.Detector_RoundTrip;
var
  Fixed : string;
begin
  Fixed := FixAll(StdUnit('doWork', 'doWork'));
  Assert.AreEqual(StdUnit('DoWork', 'DoWork'), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxMethodNameDetector.Detector_TwoMethods_BothFixed;
var
  Src : string;
begin
  Src := UnitWith(['  public', '    procedure doWork;',
    '    function getValue: Integer;'],
    ['procedure TFoo.doWork;', 'begin', 'end;',
     'function TFoo.getValue: Integer;', 'begin', '  Result := 0;', 'end;']);
  Assert.AreEqual<Integer>(2, Length(Detect(Src)), 'zwei Funde');
  Assert.AreEqual(UnitWith(['  public', '    procedure DoWork;',
    '    function GetValue: Integer;'],
    ['procedure TFoo.DoWork;', 'begin', 'end;',
     'function TFoo.GetValue: Integer;', 'begin', '  Result := 0;', 'end;']),
    FixAll(Src));
end;

procedure TTestRdxMethodNameDetector.Detector_ImplSpelledDifferently_Fixed;
var
  Src, Fixed : string;
begin
  // Die Implementierung 'dowork': Delphi nimmt sie an, der Detektor meldet
  // nur die Deklaration - ohne die zweite Ersetzung meldete er danach die
  // Implementierung.
  Src := StdUnit('doWork', 'dowork');
  Assert.AreEqual<Integer>(1, Length(Detect(Src)), 'ein Fund');
  Fixed := FixAll(Src);
  Assert.AreEqual(StdUnit('DoWork', 'Dowork'), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxMethodNameDetector.Detector_CatalogExample_InClass_Fixed;
var
  Meta : TRuleMeta;
  Src  : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkMethodName);
  Assert.IsTrue(Pos('doStuff', Meta.BadExample) > 0, Meta.BadExample);
  // Das Beispiel ('procedure doStuff;') als Methode von TFoo.
  Src := UnitWith(['  public', '    ' + CatalogText(Meta.BadExample)],
    ['procedure TFoo.doStuff;', 'begin', 'end;']);
  Assert.AreEqual<Integer>(1, Length(Detect(Src)), 'der Detektor meldet das Beispiel');
  Assert.AreEqual(StringReplace(Src, 'doStuff', 'DoStuff', [rfReplaceAll]),
    FixAll(Src));
end;

procedure TTestRdxMethodNameDetector.Detector_CatalogExample_FreeRoutine_NoHelp;
var
  Meta : TRuleMeta;
begin
  // Das Beispiel wortgetreu ist eine freie Routine - keine Hilfe (die
  // Hilfe deckt nur Methoden einer Klasse).
  Meta := TRuleCatalog.GetRuleCanonical(fkMethodName);
  AssertDetectorRefused(Join(['unit t;', 'interface',
    CatalogText(Meta.BadExample), 'implementation', 'procedure doStuff;',
    'begin', 'end;', 'end.']), _(R_MN_NO_CLASS, ['doStuff']));
end;

procedure TTestRdxMethodNameDetector.Detector_Overload_NoHelp;
begin
  // Der Detektor meldet die Ueberladungen EINMAL (Schluessel Klasse und
  // Name) - die Hilfe waehlt keine.
  AssertDetectorRefused(UnitWith(['  public', '    procedure doWork; overload;',
    '    procedure doWork(A: Integer); overload;'],
    ['procedure TFoo.doWork;', 'begin', 'end;',
     'procedure TFoo.doWork(A: Integer);', 'begin', 'end;']),
    _(R_MN_OVERLOAD, ['doWork']));
end;

procedure TTestRdxMethodNameDetector.Table_NameAndTwoEdits;
var
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  // Der Eintrag ueber die Tabelle: Name ist der neue Name (Menuetext),
  // Deklaration und Implementierung in einem Schritt, bedeutungsgleich.
  Seen := Detect(StdUnit('doWork', 'doWork'));
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  O := TablePlan(StdUnit('doWork', 'doWork'), Seen[0]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual('DoWork', O.Name);
  Assert.AreEqual<Integer>(2, Length(O.Edits), 'Deklaration und Implementierung');
  Assert.IsFalse(O.ChangesBehavior, 'nicht gekennzeichnet');
  Assert.IsTrue(O.Hint <> '', 'Hinweis der Zeile');
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxMethodNameFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxMethodNameDetector);
  {$ENDIF}

end.
