unit uTestRdxLocalConstantNameFix;

// Editorhilfe SCA119 LocalConstantName (uRdxLocalConstantNameFix): der
// Planer auf Text (erste Fixture, FPC-tauglich) und der ECHTE Detektor
// (uNamingExt) auf dem echten AST (zweite Fixture, nur Delphi). Die
// Fixtures stehen in einer Unit mit implementation-Teil auf Zeile 3; die
// Routine 'Foo' beginnt auf Zeile 4, 'const' steht auf Zeile 5, die
// Konstante auf Zeile 6 (DECL_LINE).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxLocalConstantNameFix = class
  public
    // ---- Umformung ----
    [Test] procedure Simple_RenamesDeclarationAndUses;
    [Test] procedure UpperSnake_Conversions;
    [Test] procedure CaseOnly_OtherRoutineUntouched;
    [Test] procedure NestedRoutineUse_Renamed;
    [Test] procedure OtherRoutine_Untouched;
    [Test] procedure MemberAccess_Untouched;
    [Test] procedure CaseLabelAndArrayBound_Renamed;
    // ---- Gegenproben ----
    [Test] procedure NestedRedeclaration_NoHelp;
    [Test] procedure InlineOrAnonymousRedeclaration_NoHelp;
    [Test] procedure RecordConstantField_NoHelp;
    [Test] procedure With_NoHelp;
    [Test] procedure NewNameTaken_NoHelp;
    [Test] procedure UsedBeforeDeclaration_NoHelp;
    [Test] procedure CommentOrDirectiveInDeclaration_NoHelp;
    [Test] procedure DirectiveNamesConstant_NoHelp;
    [Test] procedure MovedLineOrOtherRoutine_NoHelp;
    [Test] procedure NotInConstSectionOfRoutine_NoHelp;
    [Test] procedure AlreadyUpperSnake_Stale;
    [Test] procedure NonAsciiName_NoHelp;
    [Test] procedure MessageWithoutName_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxLocalConstantNameDetector = class
  public
    [Test] procedure Detector_ReportsLineAndRoutine;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_CatalogExample_Fixed;
    [Test] procedure Detector_TypedConst_Renamed;
    [Test] procedure Detector_MethodOfClass_Renamed;
    [Test] procedure Detector_ShadowedInNested_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uNamingExt,
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxLocalConstantNameFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply

const
  DECL_LINE = 6;   // Zeile der Konstante in den Fixtures

// ---- Helfer ----

// Die Meldung des Detektors fuer die Konstante AName in ARoutine.
function Msg(const AName, ARoutine: string): string;
begin
  Result := Format('Local const %s in %s - consider UPPER_SNAKE_CASE '
    + '(MAX_RETRIES, BUFFER_SIZE) for numeric constants. Helps reader '
    + 'distinguish constants from variables at a glance.', [AName, ARoutine]);
end;

// Eine Unit: Zeilen 1-3 Kopf, interface und 'implementation', AImpl ab
// Zeile 4, dann 'end.'.
function UnitWith(const AImpl: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation']) + #13#10
    + Join(AImpl) + #13#10 + 'end.';
end;

// Der Planer fuer Zeile ALine mit AMessage: der neue Text, oder '' bei
// Ablehnung (AReason); den Plan in APlan.
function PlanWith(const ASource: string; ALine: Integer;
  const AMessage: string; out AReason: string;
  out APlan: TRdxLocalConstantNamePlan): string;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
  Ok  : Boolean;
begin
  Result := '';
  AReason := '';
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    try
      Ok := TRdxLocalConstantNameFix.RenameConstant(Map, ALine, AMessage,
        APlan, AReason);
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
  if Ok then
    Result := Apply(ASource, APlan.Edits);
end;

// Die Hilfe fuer 'MaxRetries in Foo' auf DECL_LINE muss gelten.
function Applied(const ASource: string): string;
var
  R : string;
  P : TRdxLocalConstantNamePlan;
begin
  Result := PlanWith(ASource, DECL_LINE, Msg('MaxRetries', 'Foo'), R, P);
  Assert.IsTrue(Result <> '', R);
end;

procedure AssertRefusedAt(const ASource: string; ALine: Integer;
  const AMessage, AReason: string);
var
  R : string;
  P : TRdxLocalConstantNamePlan;
begin
  Assert.AreEqual('', PlanWith(ASource, ALine, AMessage, R, P), 'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
  Assert.AreEqual<Integer>(0, Length(P.Edits), 'keine Ersetzung');
end;

// Die Hilfe fuer 'MaxRetries in Foo' auf DECL_LINE muss abgelehnt werden.
procedure AssertRefused(const ASource, AReason: string);
begin
  AssertRefusedAt(ASource, DECL_LINE, Msg('MaxRetries', 'Foo'), AReason);
end;

// 'MaxRetries' als ganzes Wort -> 'MAX_RETRIES' (fuer erwartete Texte).
function Snake(const S: string): string;
begin
  Result := StringReplace(S, 'MaxRetries', 'MAX_RETRIES', [rfReplaceAll]);
end;

// ---- Umformung ----

procedure TTestRdxLocalConstantNameFix.Simple_RenamesDeclarationAndUses;
var
  Src, Fixed : string;
  R          : string;
  P          : TRdxLocalConstantNamePlan;
begin
  Src := UnitWith(['procedure Foo;', 'const', '  MaxRetries = 3;', 'var',
    '  I: Integer;', 'begin', '  for I := 1 to MaxRetries do',
    '    Work(I, MaxRetries);', 'end;']);
  Fixed := PlanWith(Src, DECL_LINE, Msg('MaxRetries', 'Foo'), R, P);
  Assert.AreEqual(Snake(Src), Fixed, R);
  Assert.AreEqual<Integer>(3, Length(P.Edits), 'Deklaration und zwei Verweise');
  Assert.AreEqual('MaxRetries', P.Edits[0].Expected);
  Assert.AreEqual('MAX_RETRIES', P.Edits[0].NewText);
  Assert.AreEqual<Integer>(DECL_LINE, P.Edits[0].Span.StartLine);
  Assert.AreEqual<Integer>(3, P.Edits[0].Span.StartCol);
  Assert.AreEqual('MAX_RETRIES', P.Name, 'Name fuer den Menuetext');
end;

procedure TTestRdxLocalConstantNameFix.UpperSnake_Conversions;
begin
  Assert.AreEqual('MAX_RETRIES',
    TRdxLocalConstantNameFix.UpperSnakeOf('MaxRetries'));
  Assert.AreEqual('MAX_RETRIES',
    TRdxLocalConstantNameFix.UpperSnakeOf('maxRetries'));
  Assert.AreEqual('HTTP_PORT', TRdxLocalConstantNameFix.UpperSnakeOf('HTTPPort'));
  Assert.AreEqual('C_MAX', TRdxLocalConstantNameFix.UpperSnakeOf('cMax'));
  Assert.AreEqual('BASE64_LEN',
    TRdxLocalConstantNameFix.UpperSnakeOf('Base64Len'));
  Assert.AreEqual('UTF8_LEN', TRdxLocalConstantNameFix.UpperSnakeOf('utf8Len'));
  Assert.AreEqual('MAX_RETRIES',
    TRdxLocalConstantNameFix.UpperSnakeOf('Max_Retries'));
  Assert.AreEqual('MAX', TRdxLocalConstantNameFix.UpperSnakeOf('Max'));
end;

procedure TTestRdxLocalConstantNameFix.CaseOnly_OtherRoutineUntouched;
var
  Src, Fixed : string;
  R          : string;
  P          : TRdxLocalConstantNamePlan;
begin
  // 'Max' -> 'MAX' ist derselbe Bezeichner: Math.Max in Bar bleibt, wie es
  // ist, und sperrt nicht.
  Src := Join(['unit t;', 'interface', 'implementation', 'procedure Bar;',
    'begin', '  X := Max(1, 2);', 'end;', 'procedure Foo;', 'const',
    '  Max = 10;', 'begin', '  Y := Max;', 'end;', 'end.']);
  Fixed := PlanWith(Src, 10, Msg('Max', 'Foo'), R, P);
  Assert.AreEqual(Join(['unit t;', 'interface', 'implementation',
    'procedure Bar;', 'begin', '  X := Max(1, 2);', 'end;', 'procedure Foo;',
    'const', '  MAX = 10;', 'begin', '  Y := MAX;', 'end;', 'end.']),
    Fixed, R);
  Assert.AreEqual('MAX', P.Name);
end;

procedure TTestRdxLocalConstantNameFix.NestedRoutineUse_Renamed;
var
  Src : string;
begin
  // Die lokale Routine hinter der Konstante sieht sie - auch als Argument.
  Src := UnitWith(['procedure Foo;', 'const', '  MaxRetries = 3;',
    '  procedure Inner;', '  begin', '    Work(MaxRetries);', '  end;',
    'begin', '  Inner;', '  if Count > MaxRetries then', '    Stop;',
    'end;']);
  Assert.AreEqual(Snake(Src), Applied(Src));
end;

procedure TTestRdxLocalConstantNameFix.OtherRoutine_Untouched;
begin
  // Bar sieht die Konstante von Foo nicht: dort bleibt der Name.
  Assert.AreEqual(UnitWith(['procedure Foo;', 'const', '  MAX_RETRIES = 3;',
    'begin', '  Work(MAX_RETRIES);', 'end;', 'procedure Bar;', 'begin',
    '  Work(MaxRetries);', 'end;']),
    Applied(UnitWith(['procedure Foo;', 'const', '  MaxRetries = 3;',
      'begin', '  Work(MaxRetries);', 'end;', 'procedure Bar;', 'begin',
      '  Work(MaxRetries);', 'end;'])));
end;

procedure TTestRdxLocalConstantNameFix.MemberAccess_Untouched;
begin
  // 'Cfg.MaxRetries' ist ein Member, kein Verweis auf die Konstante.
  Assert.AreEqual(UnitWith(['procedure Foo(Cfg: TCfg);', 'const',
    '  MAX_RETRIES = 3;', 'begin', '  Cfg.MaxRetries := MAX_RETRIES;',
    'end;']),
    Applied(UnitWith(['procedure Foo(Cfg: TCfg);', 'const',
      '  MaxRetries = 3;', 'begin', '  Cfg.MaxRetries := MaxRetries;',
      'end;'])));
end;

procedure TTestRdxLocalConstantNameFix.CaseLabelAndArrayBound_Renamed;
var
  Src : string;
begin
  Src := UnitWith(['procedure Foo(K: Integer);', 'const', '  MaxRetries = 3;',
    '  Limit = MaxRetries * 2;', 'var', '  Buf: array[0..MaxRetries] of Byte;',
    'begin', '  case K of', '    MaxRetries: Stop;', '  end;', 'end;']);
  Assert.AreEqual(Snake(Src), Applied(Src));
end;

// ---- Gegenproben ----

procedure TTestRdxLocalConstantNameFix.NestedRedeclaration_NoHelp;
begin
  // Parameter einer lokalen Routine.
  AssertRefused(UnitWith(['procedure Foo;', 'const', '  MaxRetries = 3;',
    '  procedure Inner(MaxRetries: Integer);', '  begin',
    '    Work(MaxRetries);', '  end;', 'begin', '  Inner(MaxRetries);',
    'end;']), _(R_LCN_SHADOW, [7, 'MaxRetries']));
  // Konstante bzw. Variable einer lokalen Routine.
  AssertRefused(UnitWith(['procedure Foo;', 'const', '  MaxRetries = 3;',
    '  procedure Inner;', '  const', '    MaxRetries = 5;', '  begin',
    '  end;', 'begin', 'end;']), _(R_LCN_SHADOW, [9, 'MaxRetries']));
  AssertRefused(UnitWith(['procedure Foo;', 'const', '  MaxRetries = 3;',
    '  procedure Inner;', '  var', '    A, MaxRetries: Integer;', '  begin',
    '  end;', 'begin', 'end;']), _(R_LCN_SHADOW, [9, 'MaxRetries']));
end;

procedure TTestRdxLocalConstantNameFix.InlineOrAnonymousRedeclaration_NoHelp;
begin
  AssertRefused(UnitWith(['procedure Foo;', 'const', '  MaxRetries = 3;',
    'begin', '  var MaxRetries := 5;', 'end;']),
    _(R_LCN_SHADOW, [8, 'MaxRetries']));
  AssertRefused(UnitWith(['procedure Foo;', 'const', '  MaxRetries = 3;',
    'begin', '  Run(procedure(MaxRetries: Integer) begin end);', 'end;']),
    _(R_LCN_SHADOW, [8, 'MaxRetries']));
end;

procedure TTestRdxLocalConstantNameFix.RecordConstantField_NoHelp;
begin
  // Ein Feldname einer Record-Konstante ist kein Verweis.
  AssertRefused(UnitWith(['procedure Foo;', 'const', '  MaxRetries = 3;',
    '  Def: TPair = (MaxRetries: 1; Other: 2);', 'begin', 'end;']),
    _(R_LCN_SHADOW, [7, 'MaxRetries']));
end;

procedure TTestRdxLocalConstantNameFix.With_NoHelp;
begin
  AssertRefused(UnitWith(['procedure Foo(Cfg: TCfg);', 'const',
    '  MaxRetries = 3;', 'begin', '  with Cfg do', '    Work(MaxRetries);',
    'end;']), _(R_LCN_WITH, ['MaxRetries']));
end;

procedure TTestRdxLocalConstantNameFix.NewNameTaken_NoHelp;
begin
  // Auch in anderer Schreibweise und in einer anderen Routine.
  AssertRefused(UnitWith(['procedure Foo;', 'const', '  MaxRetries = 3;',
    'begin', 'end;', 'procedure Bar;', 'begin', '  Work(Max_Retries);',
    'end;']), _(R_LCN_TAKEN, ['MAX_RETRIES']));
end;

procedure TTestRdxLocalConstantNameFix.UsedBeforeDeclaration_NoHelp;
begin
  // Vor der Deklaration meint der Name etwas anderes (hier eine Konstante
  // der Unit).
  AssertRefusedAt(UnitWith(['procedure Foo;', 'const',
    '  Limit = MaxRetries;', '  MaxRetries = 3;', 'begin', 'end;']),
    DECL_LINE + 1, Msg('MaxRetries', 'Foo'),
    _(R_LCN_BEFORE, ['MaxRetries', DECL_LINE]));
end;

procedure TTestRdxLocalConstantNameFix.CommentOrDirectiveInDeclaration_NoHelp;
begin
  AssertRefused(UnitWith(['procedure Foo;', 'const',
    '  MaxRetries = { three } 3;', 'begin', 'end;']),
    _(R_LCN_COMMENT, ['MaxRetries']));
  AssertRefused(UnitWith(['procedure Foo;', 'const',
    '  MaxRetries = {$IFDEF X}3{$ELSE}4{$ENDIF};', 'begin', 'end;']),
    _(R_LCN_COMMENT, ['MaxRetries']));
end;

procedure TTestRdxLocalConstantNameFix.DirectiveNamesConstant_NoHelp;
begin
  AssertRefused(UnitWith(['procedure Foo;', 'const', '  MaxRetries = 3;',
    'begin', '  {$IF MaxRetries > 2}', '  Work;', '  {$IFEND}', 'end;']),
    _(R_LCN_DIRECTIVE, ['MaxRetries']));
end;

procedure TTestRdxLocalConstantNameFix.MovedLineOrOtherRoutine_NoHelp;
var
  Src : string;
begin
  Src := UnitWith(['procedure Foo;', 'const', '  MaxRetries = 3;', 'begin',
    '  Work(MaxRetries);', 'end;']);
  AssertRefusedAt(Src, DECL_LINE + 3, Msg('MaxRetries', 'Foo'),
    MsgMovedSuffix(_(R_LCN_MOVED, ['MaxRetries'])));
  // Die Meldung nennt eine andere Routine.
  AssertRefusedAt(Src, DECL_LINE, Msg('MaxRetries', 'Bar'),
    MsgMovedSuffix(_(R_LCN_OTHER_ROUTINE, ['Foo', 'Bar'])));
end;

procedure TTestRdxLocalConstantNameFix.NotInConstSectionOfRoutine_NoHelp;
begin
  // Eine Variable gleichen Namens ist keine Konstante.
  AssertRefused(UnitWith(['procedure Foo;', 'var',
    '  A: Integer; MaxRetries: Integer;', 'begin', 'end;']),
    _(R_LCN_NOT_CONST, ['MaxRetries']));
  // Eine Inline-Konstante im Rumpf meldet der Detektor nicht.
  AssertRefusedAt(UnitWith(['procedure Foo;', 'begin',
    '  const MaxRetries = 3;', 'end;']), DECL_LINE, Msg('MaxRetries', 'Foo'),
    _(R_LCN_NO_ROUTINE, ['MaxRetries']));
end;

procedure TTestRdxLocalConstantNameFix.AlreadyUpperSnake_Stale;
begin
  AssertRefusedAt(UnitWith(['procedure Foo;', 'const', '  MAX_RETRIES = 3;',
    'begin', 'end;']), DECL_LINE, Msg('MAX_RETRIES', 'Foo'),
    MsgStaleSuffix(_(R_LCN_STALE, ['MAX_RETRIES'])));
end;

procedure TTestRdxLocalConstantNameFix.NonAsciiName_NoHelp;
var
  Name : string;
begin
  Name := 'Gr' + #$00F6 + 'sse';
  AssertRefusedAt(UnitWith(['procedure Foo;', 'const', '  ' + Name + ' = 3;',
    'begin', 'end;']), DECL_LINE, Msg(Name, 'Foo'),
    _(R_LCN_NON_ASCII, [Name]));
end;

procedure TTestRdxLocalConstantNameFix.MessageWithoutName_NoHelp;
begin
  AssertRefusedAt(UnitWith(['procedure Foo;', 'const', '  MaxRetries = 3;',
    'begin', 'end;']), DECL_LINE, 'Local const MaxRetries',
    _(R_LCN_FORM));
end;

{$IFNDEF FPC}

{ ---- Detektor ---- }

// Die Funde der Art SCA119 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TNamingExtDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_constname_', ASource, fkLocalConstantName,
    RunDetector);
end;

// Die Hilfe fuer den ersten Fund des Detektors.
function PlanFirst(const ASource: string; out AReason: string): string;
var
  Seen : TArray<TSeen>;
  P    : TRdxLocalConstantNamePlan;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet einen Fund');
  Result := PlanWith(ASource, Seen[0].Line, Seen[0].Msg, AReason, P);
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt.
function FixAll(const ASource: string): string;
const
  MAX_PASSES = 10;
var
  Pass : Integer;
  R    : string;
begin
  Result := ASource;
  for Pass := 1 to MAX_PASSES do
  begin
    if Length(Detect(Result)) = 0 then
      Exit;
    Result := PlanFirst(Result, R);
    Assert.IsTrue(Result <> '', R);
  end;
  Assert.Fail('der Detektor schweigt auch nach zehn Durchlaeufen nicht');
end;

procedure TTestRdxLocalConstantNameDetector.Detector_ReportsLineAndRoutine;
var
  Seen    : TArray<TSeen>;
  Routine : string;
begin
  Seen := Detect(UnitWith(['procedure Foo;', 'const', '  MaxRetries = 3;',
    'begin', 'end;']));
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(DECL_LINE, Seen[0].Line, 'Zeile des Namens');
  Assert.AreEqual('MaxRetries',
    TRdxLocalConstantNameFix.ConstNameOf(Seen[0].Msg, Routine));
  Assert.AreEqual('Foo', Routine);
end;

procedure TTestRdxLocalConstantNameDetector.Detector_RoundTrip;
var
  Src, Fixed : string;
begin
  Src := UnitWith(['procedure Foo;', 'const', '  MaxRetries = 3;',
    '  BufferSize = 4096;', 'var', '  I: Integer;', 'begin',
    '  for I := 1 to MaxRetries do', '    Read(BufferSize);', 'end;']);
  Assert.AreEqual<Integer>(2, Length(Detect(Src)), 'zwei Funde');
  Fixed := FixAll(Src);
  Assert.AreEqual(UnitWith(['procedure Foo;', 'const', '  MAX_RETRIES = 3;',
    '  BUFFER_SIZE = 4096;', 'var', '  I: Integer;', 'begin',
    '  for I := 1 to MAX_RETRIES do', '    Read(BUFFER_SIZE);', 'end;']),
    Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxLocalConstantNameDetector.Detector_CatalogExample_Fixed;
var
  Meta      : TRuleMeta;
  Bad, Good : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkLocalConstantName);
  Assert.IsTrue(Pos('MaxRetries', Meta.BadExample) > 0, Meta.BadExample);
  // Der Katalog deutet den Rumpf mit '...' an - als Anweisung eingesetzt.
  Bad := StringReplace(CatalogText(Meta.BadExample), '...', 'Work;', []);
  Good := StringReplace(CatalogText(Meta.GoodExample), '...', 'Work;', []);
  Assert.AreEqual<Integer>(1, Length(Detect(UnitWith([Bad]))),
    'der Detektor meldet das Beispiel');
  Assert.AreEqual(UnitWith([Good]), FixAll(UnitWith([Bad])));
end;

procedure TTestRdxLocalConstantNameDetector.Detector_TypedConst_Renamed;
begin
  Assert.AreEqual(UnitWith(['procedure Foo;', 'const',
    '  BUFFER_SIZE: Integer = 4096;', 'begin', '  Read(BUFFER_SIZE);',
    'end;']),
    FixAll(UnitWith(['procedure Foo;', 'const',
      '  BufferSize: Integer = 4096;', 'begin', '  Read(BufferSize);',
      'end;'])));
end;

procedure TTestRdxLocalConstantNameDetector.Detector_MethodOfClass_Renamed;
var
  Src : string;
begin
  // Die Meldung nennt die Methode mit Klasse ('TFoo.Bar') - wie der Kopf.
  Src := Join(['unit t;', 'interface', 'type', '  TFoo = class',
    '    procedure Bar;', '  end;', 'implementation', 'procedure TFoo.Bar;',
    'const', '  MaxCount = 10;', 'begin', '  Work(MaxCount);', 'end;',
    'end.']);
  Assert.AreEqual(StringReplace(Src, 'MaxCount', 'MAX_COUNT', [rfReplaceAll]),
    FixAll(Src));
end;

procedure TTestRdxLocalConstantNameDetector.Detector_ShadowedInNested_NoHelp;
var
  R : string;
begin
  Assert.AreEqual('', PlanFirst(UnitWith(['procedure Foo;', 'const',
    '  MaxRetries = 3;', '  procedure Inner(MaxRetries: Integer);',
    '  begin', '  end;', 'begin', '  Inner(MaxRetries);', 'end;']), R));
  Assert.AreEqual(_(R_LCN_SHADOW, [7, 'MaxRetries']), R);
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxLocalConstantNameFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxLocalConstantNameDetector);
  {$ENDIF}

end.
