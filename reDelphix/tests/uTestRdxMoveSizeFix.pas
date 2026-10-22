unit uTestRdxMoveSizeFix;

// Editorhilfe SCA154 MoveSizeOfPointer (uRdxMoveSizeFix): der Planer auf
// Text, die Puffer-Argumente und ihr Typbeweis als reine Funktionen (erste
// Fixture, auch FPC), dazu der ECHTE Detektor (uMoveSizeOfPointer) auf dem
// echten AST ueber den Einstieg der Tabelle (TRdxFixTable.FixFor, Adapter
// PlanMoveSizeOfPointer; zweite Fixture, nur Delphi - bis zur Integration
// der Charge QF stand hier eine woertliche Kopie des Adapters). Die
// Fixtures der ersten stehen in 'procedure Foo', der Rumpf beginnt auf
// Zeile 6 (LINE).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxMoveSizeFix = class
  public
    // ---- Umformung ----
    [Test] procedure Move_BecomesTargetSize;
    [Test] procedure FillChar_BecomesTargetSize;
    [Test] procedure PointerRoutines_BecomeTargetSize;
    [Test] procedure Spelling_KeptFromSource;
    // ---- Puffer und Typbeweis (Bausteine des Adapters) ----
    [Test] procedure Operands_ExpectedTypes;
    [Test] procedure OperandReason_ProofAndRefusal;
    [Test] procedure ContextReason_With;
    // ---- Gegenproben ----
    [Test] procedure UnknownPointerType_NoHelp;
    [Test] procedure OwnTypeOrRoutine_NoHelp;
    [Test] procedure LengthNotJustSizeOf_NoHelp;
    [Test] procedure BufferNotOneVariable_NoHelp;
    [Test] procedure Qualified_NoHelp;
    [Test] procedure MovedOrAmbiguous_NoHelp;
    [Test] procedure CallOverTwoLines_NoHelp;
    [Test] procedure CommentInCall_NoHelp;
    [Test] procedure ArgumentCount_NoHelp;
    [Test] procedure WithBefore_NoHelp;
    [Test] procedure Message_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxMoveSizeDetector = class
  public
    // ---- echter Detektor ----
    [Test] procedure Detector_ReportsLineAndType;
    [Test] procedure Detector_RoundTrip;
    [Test] procedure Detector_FillCharVariable_Fixed;
    [Test] procedure Detector_ZeroMemoryPointer_Fixed;
    [Test] procedure Detector_CatalogExample_NoHelp;
    [Test] procedure Detector_PointerCopy_NoHelp;
    [Test] procedure Detector_UndeclaredBuffer_NoHelp;
    [Test] procedure Detector_IndexedBuffer_NoHelp;
    // ---- Adapter ----
    [Test] procedure Adapter_NoFile_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uEngineApi, uRuleCatalog,
  uMoveSizeOfPointer,
  uRdxRecipeRunner,      // TRdxFixOutcome, R_NO_FILE, UsesNamesOf
  uRdxFixTable,          // TRdxFixTable.FixFor
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText, FixAllWith
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxMoveSizeFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply, NewMap

const
  LINE = 6;   // erste Rumpfzeile von Wrap

// ---- Helfer ----

function Wrap(const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    'begin']) + #13#10 + Join(ABody) + #13#10 + Join(['end;', 'end.']);
end;

// Die Meldung des Detektors (uMoveSizeOfPointer).
function Msg(const ARoutine, APtr: string): string;
begin
  Result := Format('%s(...) uses SizeOf(%s) which is only pointer size '
    + '(4/8 bytes), not the buffer size', [ARoutine, APtr]);
end;

// Der Planer fuer Zeile ALine: der neue Text, oder '' bei Ablehnung.
function PlanAt(const ASource: string; ALine: Integer; const AMessage: string;
  out AReason: string): string;
var
  Map : TRdxCodeMap;
  E   : TRdxEdit;
  Ok  : Boolean;
begin
  Result := '';
  AReason := '';
  Map := NewMap(ASource);
  try
    Ok := TRdxMoveSizeFix.PointeeSize(Map, ALine, AMessage, E, AReason);
  finally
    Map.Free;
  end;
  if Ok then
    Result := Apply(ASource, E);
end;

function Applied(const ASource: string; ALine: Integer;
  const ARoutine, APtr: string): string;
var
  R : string;
begin
  Result := PlanAt(ASource, ALine, Msg(ARoutine, APtr), R);
  Assert.IsTrue(Result <> '', R);
end;

procedure AssertRefused(const ASource: string; ALine: Integer;
  const ARoutine, APtr, AReason: string);
var
  R : string;
begin
  Assert.AreEqual('', PlanAt(ASource, ALine, Msg(ARoutine, APtr), R),
    'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
end;

// Die Puffer-Argumente der Zeile ALine (Operands).
function OperandsAt(const ASource: string; ALine: Integer;
  const ARoutine, APtr: string): TArray<TRdxSizeOperand>;
var
  Map : TRdxCodeMap;
  R   : string;
begin
  Map := NewMap(ASource);
  try
    Assert.IsTrue(TRdxMoveSizeFix.Operands(Map, ALine, Msg(ARoutine, APtr),
      Result, R), R);
  finally
    Map.Free;
  end;
end;

// ---- Umformung ----

procedure TTestRdxMoveSizeFix.Move_BecomesTargetSize;
var
  Map : TRdxCodeMap;
  E   : TRdxEdit;
  R   : string;
begin
  Assert.AreEqual(Wrap(['  Move(Src^, Dst^, SizeOf(Integer));']),
    Applied(Wrap(['  Move(Src^, Dst^, SizeOf(PInteger));']), LINE, 'Move',
      'PInteger'));
  Assert.AreEqual(Wrap(['  Move(Src^, V, SizeOf(Byte));']),
    Applied(Wrap(['  Move(Src^, V, SizeOf(PByte));']), LINE, 'Move',
      'PByte'));
  // Die Ersetzung ist genau der Zeigertyp.
  Map := NewMap(Wrap(['  Move(Src^, Dst^, SizeOf(PInteger));']));
  try
    Assert.IsTrue(TRdxMoveSizeFix.PointeeSize(Map, LINE,
      Msg('Move', 'PInteger'), E, R), R);
  finally
    Map.Free;
  end;
  Assert.AreEqual('PInteger', E.Expected);
  Assert.AreEqual('Integer', E.NewText);
  Assert.AreEqual<Integer>(LINE, E.Span.StartLine);
  Assert.AreEqual<Integer>(27, E.Span.StartCol);
  Assert.AreEqual<Integer>(35, E.Span.EndCol);
end;

procedure TTestRdxMoveSizeFix.FillChar_BecomesTargetSize;
begin
  Assert.AreEqual(Wrap(['  FillChar(P^, SizeOf(Double), 0);']),
    Applied(Wrap(['  FillChar(P^, SizeOf(PDouble), 0);']), LINE, 'FillChar',
      'PDouble'));
  Assert.AreEqual(Wrap(['  FillChar(V, SizeOf(Int64), 0);']),
    Applied(Wrap(['  FillChar(V, SizeOf(PInt64), 0);']), LINE, 'FillChar',
      'PInt64'));
  Assert.AreEqual(Wrap(['  FillChar(C^, SizeOf(Char), #0);']),
    Applied(Wrap(['  FillChar(C^, SizeOf(PChar), #0);']), LINE, 'FillChar',
      'PChar'));
end;

procedure TTestRdxMoveSizeFix.PointerRoutines_BecomeTargetSize;
begin
  Assert.AreEqual(Wrap(['  ZeroMemory(P, SizeOf(Cardinal));']),
    Applied(Wrap(['  ZeroMemory(P, SizeOf(PCardinal));']), LINE, 'ZeroMemory',
      'PCardinal'));
  Assert.AreEqual(Wrap(['  CopyMemory(@A, Src, SizeOf(Word));']),
    Applied(Wrap(['  CopyMemory(@A, Src, SizeOf(PWord));']), LINE,
      'CopyMemory', 'PWord'));
end;

procedure TTestRdxMoveSizeFix.Spelling_KeptFromSource;
begin
  // Gross/klein der Meldung zaehlt nicht; der Zieltyp steht in der
  // Schreibweise der RTL.
  Assert.AreEqual(Wrap(['  move(src^, dst^, sizeof(Integer));']),
    Applied(Wrap(['  move(src^, dst^, sizeof(pinteger));']), LINE, 'move',
      'pinteger'));
  Assert.AreEqual(Wrap(['  Move(Src^, Dst^, SizeOf( WideChar ));']),
    Applied(Wrap(['  Move(Src^, Dst^, SizeOf( PWIDECHAR ));']), LINE, 'MOVE',
      'PWIDECHAR'));
end;

// ---- Puffer und Typbeweis ----

procedure TTestRdxMoveSizeFix.Operands_ExpectedTypes;
var
  Ops : TArray<TRdxSizeOperand>;
begin
  // Untypisiert: X^ ist der Zeiger, X das Element.
  Ops := OperandsAt(Wrap(['  Move(Src^, V, SizeOf(PInteger));']), LINE,
    'Move', 'PInteger');
  Assert.AreEqual<Integer>(2, Length(Ops));
  Assert.AreEqual('Src', Ops[0].Name);
  Assert.AreEqual('pinteger', Ops[0].Expected);
  Assert.AreEqual('PInteger', Ops[0].Shown);
  Assert.AreEqual('V', Ops[1].Name);
  Assert.AreEqual('integer', Ops[1].Expected);
  Assert.AreEqual('Integer', Ops[1].Shown);
  // Pointer-Parameter: X ist der Zeiger, @X das Element; nur die Puffer.
  Ops := OperandsAt(Wrap(['  CopyMemory(@A, P, SizeOf(PWord));']), LINE,
    'CopyMemory', 'PWord');
  Assert.AreEqual<Integer>(2, Length(Ops));
  Assert.AreEqual('A', Ops[0].Name);
  Assert.AreEqual('word', Ops[0].Expected);
  Assert.AreEqual('P', Ops[1].Name);
  Assert.AreEqual('pword', Ops[1].Expected);
  Ops := OperandsAt(Wrap(['  FillChar(P^, SizeOf(PDouble), 0);']), LINE,
    'FillChar', 'PDouble');
  Assert.AreEqual<Integer>(1, Length(Ops), 'der Fuellwert ist kein Puffer');
  Assert.AreEqual('pdouble', Ops[0].Expected);
end;

procedure TTestRdxMoveSizeFix.OperandReason_ProofAndRefusal;
var
  Op : TRdxSizeOperand;
begin
  Op.Name := 'Src';
  Op.Expected := 'pinteger';
  Op.Shown := 'PInteger';
  Assert.AreEqual('', TRdxMoveSizeFix.OperandReason(Op, 'pinteger'));
  Assert.AreEqual('', TRdxMoveSizeFix.OperandReason(Op, 'PInteger'),
    'Gross/klein egal');
  Assert.AreEqual(_(R_SIZE_UNKNOWN, ['Src', 'PInteger']),
    TRdxMoveSizeFix.OperandReason(Op, ''));
  Assert.AreEqual(_(R_SIZE_TYPE, ['Src', 'pbyte', 'PInteger']),
    TRdxMoveSizeFix.OperandReason(Op, 'pbyte'));
end;

procedure TTestRdxMoveSizeFix.ContextReason_With;
begin
  Assert.AreEqual('', TRdxMoveSizeFix.ContextReason(False));
  Assert.AreEqual(_(R_SIZE_WITH), TRdxMoveSizeFix.ContextReason(True));
end;

// ---- Gegenproben ----

procedure TTestRdxMoveSizeFix.UnknownPointerType_NoHelp;
begin
  // Ein eigener Typ, ein Zeiger auf einen Zeiger bzw. String (dort ist die
  // Zeigergroesse die Elementgroesse).
  AssertRefused(Wrap(['  Move(Src^, Dst^, SizeOf(PFoo));']), LINE, 'Move',
    'PFoo', _(R_SIZE_PTR, ['PFoo']));
  AssertRefused(Wrap(['  Move(Src^, Dst^, SizeOf(PPointer));']), LINE,
    'Move', 'PPointer', _(R_SIZE_PTR, ['PPointer']));
  AssertRefused(Wrap(['  Move(Src^, Dst^, SizeOf(PString));']), LINE,
    'Move', 'PString', _(R_SIZE_PTR, ['PString']));
end;

procedure TTestRdxMoveSizeFix.OwnTypeOrRoutine_NoHelp;
var
  Src : string;
begin
  AssertRefused(Join(['unit t;', 'interface', 'type',
    '  PInteger = ^TFoo;', 'implementation', 'procedure Foo;', 'begin',
    '  Move(Src^, Dst^, SizeOf(PInteger));', 'end;', 'end.']), 8, 'Move',
    'PInteger', _(R_SIZE_OWN_TYPE, ['PInteger']));
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'procedure Move(const A; var B; N: Integer);', 'begin', 'end;',
    'procedure Foo;', 'begin', '  Move(Src^, Dst^, SizeOf(PInteger));',
    'end;', 'end.']), 9, 'Move', 'PInteger',
    _(R_SIZE_OWN_ROUTINE, ['Move']));
  // Gegenprobe: eine Variable mit Anfangswert deklariert den Typ nicht.
  Src := Join(['unit t;', 'interface', 'var', '  G: PInteger = nil;',
    'implementation', 'procedure Foo;', 'begin',
    '  Move(Src^, Dst^, SizeOf(PInteger));', 'end;', 'end.']);
  Assert.AreEqual(StringReplace(Src, 'SizeOf(PInteger)', 'SizeOf(Integer)',
    []), Applied(Src, 8, 'Move', 'PInteger'));
end;

procedure TTestRdxMoveSizeFix.LengthNotJustSizeOf_NoHelp;
begin
  AssertRefused(Wrap(['  Move(Src^, Dst^, SizeOf(PInteger) + 1);']), LINE,
    'Move', 'PInteger', _(R_SIZE_FORM, ['PInteger']));
  AssertRefused(Wrap(['  Move(Src^, Dst^, Count * SizeOf(PInteger));']), LINE,
    'Move', 'PInteger', _(R_SIZE_FORM, ['PInteger']));
  // SizeOf steht im Fuellwert, nicht in der Laenge.
  AssertRefused(Wrap(['  FillChar(P^, 4, SizeOf(PInteger));']), LINE,
    'FillChar', 'PInteger', _(R_SIZE_FORM, ['PInteger']));
end;

procedure TTestRdxMoveSizeFix.BufferNotOneVariable_NoHelp;
begin
  AssertRefused(Wrap(['  Move(Buf[0], Dst^, SizeOf(PInteger));']), LINE,
    'Move', 'PInteger', _(R_SIZE_BUFFER, ['Buf[0]']));
  AssertRefused(Wrap(['  Move(Src^, R.Field, SizeOf(PInteger));']), LINE,
    'Move', 'PInteger', _(R_SIZE_BUFFER, ['R.Field']));
  // '@X' passt nur zu einem Pointer-Parameter, 'X^' nur zu untypisiert.
  AssertRefused(Wrap(['  FillChar(@V, SizeOf(PInteger), 0);']), LINE,
    'FillChar', 'PInteger', _(R_SIZE_BUFFER, ['@V']));
  AssertRefused(Wrap(['  ZeroMemory(P^, SizeOf(PInteger));']), LINE,
    'ZeroMemory', 'PInteger', _(R_SIZE_BUFFER, ['P^']));
  AssertRefused(Wrap(['  ZeroMemory(nil, SizeOf(PInteger));']), LINE,
    'ZeroMemory', 'PInteger', _(R_SIZE_BUFFER, ['nil']));
end;

procedure TTestRdxMoveSizeFix.Qualified_NoHelp;
begin
  AssertRefused(Wrap(['  System.Move(Src^, Dst^, SizeOf(PInteger));']), LINE,
    'Move', 'PInteger', _(R_SIZE_QUALIFIED, ['Move']));
  AssertRefused(Wrap(['  List.Move(Src^, Dst^, SizeOf(PInteger));']), LINE,
    'Move', 'PInteger', _(R_SIZE_QUALIFIED, ['Move']));
end;

procedure TTestRdxMoveSizeFix.MovedOrAmbiguous_NoHelp;
var
  Src : string;
begin
  Src := Wrap(['  Move(Src^, Dst^, SizeOf(PInteger));']);
  AssertRefused(Src, LINE + 1, 'Move', 'PInteger',
    MsgMovedSuffix(_(R_SIZE_MOVED, ['Move'])));
  AssertRefused(Src, 99, 'Move', 'PInteger',
    MsgMovedSuffix(_(R_SIZE_MOVED, ['Move'])));
  AssertRefused(Src, LINE, 'FillChar', 'PInteger',
    MsgMovedSuffix(_(R_SIZE_MOVED, ['FillChar'])));
  // Kommentar und String sind nie Code.
  AssertRefused(Wrap(['  // Move(Src^, Dst^, SizeOf(PInteger));']), LINE,
    'Move', 'PInteger', MsgMovedSuffix(_(R_SIZE_MOVED, ['Move'])));
  AssertRefused(Wrap(['  S := ''Move(Src^, Dst^, SizeOf(PInteger))'';']),
    LINE, 'Move', 'PInteger', MsgMovedSuffix(_(R_SIZE_MOVED, ['Move'])));
  AssertRefused(Wrap(['  Move(A^, B^, SizeOf(PInteger)); Move(C^, D^, '
    + 'SizeOf(PInteger));']), LINE, 'Move', 'PInteger',
    _(R_SIZE_MANY, ['Move']));
end;

procedure TTestRdxMoveSizeFix.CallOverTwoLines_NoHelp;
begin
  AssertRefused(Wrap(['  Move(Src^, Dst^,', '    SizeOf(PInteger));']), LINE,
    'Move', 'PInteger', _(R_SIZE_LINE, ['Move']));
end;

procedure TTestRdxMoveSizeFix.CommentInCall_NoHelp;
begin
  AssertRefused(Wrap(['  Move(Src^, {ziel} Dst^, SizeOf(PInteger));']), LINE,
    'Move', 'PInteger', _(R_SIZE_COMMENT, ['Move']));
  // Ein Kommentar hinter dem Aufruf stoert nicht.
  Assert.AreEqual(Wrap(['  Move(Src^, Dst^, SizeOf(Integer)); // ein Wert']),
    Applied(Wrap(['  Move(Src^, Dst^, SizeOf(PInteger)); // ein Wert']), LINE,
      'Move', 'PInteger'));
end;

procedure TTestRdxMoveSizeFix.ArgumentCount_NoHelp;
begin
  AssertRefused(Wrap(['  Move(Src^, SizeOf(PInteger));']), LINE, 'Move',
    'PInteger', _(R_SIZE_ARGS, ['Move', 3]));
  AssertRefused(Wrap(['  ZeroMemory(P, SizeOf(PInteger), 0);']), LINE,
    'ZeroMemory', 'PInteger', _(R_SIZE_ARGS, ['ZeroMemory', 2]));
end;

procedure TTestRdxMoveSizeFix.WithBefore_NoHelp;
begin
  AssertRefused(Wrap(['  with R do', '    Move(Src^, Dst^, SizeOf(PInteger));']),
    LINE + 1, 'Move', 'PInteger', _(R_SIZE_WITH));
end;

procedure TTestRdxMoveSizeFix.Message_NoHelp;
var
  R : string;
begin
  Assert.AreEqual('', PlanAt(Wrap(['  Move(Src^, Dst^, SizeOf(PInteger));']),
    LINE, 'x', R));
  Assert.AreEqual(_(R_SIZE_MSG), R);
  // Eine Routine, die der Detektor nicht meldet.
  AssertRefused(Wrap(['  Copy(Src^, Dst^, SizeOf(PInteger));']), LINE, 'Copy',
    'PInteger', _(R_SIZE_MSG));
  Assert.AreEqual('Integer', TRdxMoveSizeFix.TargetTypeOf(Msg('Move',
    'PInteger')));
  Assert.AreEqual('', TRdxMoveSizeFix.TargetTypeOf(Msg('Move', 'PFoo')));
  Assert.AreEqual('', TRdxMoveSizeFix.TargetTypeOf('x'));
  Assert.AreEqual('Char', TRdxMoveSizeFix.PointeeOf('PCHAR'));
  Assert.AreEqual('TDateTime', TRdxMoveSizeFix.PointeeOf('PDateTime'));
end;

{$IFNDEF FPC}

{ ---- Adapter und Detektor ---- }

// Die Funde der Art SCA154 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TMoveSizeOfPointerDetector.AnalyzeUnit(Root, Path, Results);
end;

// Dasselbe in der Form TDetectFunc (FixAllWith).
function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_movesize_', ASource, AKind, RunDetector);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectKind(ASource, fkMoveSizeOfPointer);
end;

// Die Hilfe fuer einen Fund ueber den Einstieg der Tabelle
// (TRdxFixTable.FixFor, Adapter PlanMoveSizeOfPointer); AOpen: mit
// geoeffnetem Quellstellen-Dienst. Eigener Lauf statt PlanFixIn
// (uTestRdxDetectorKit): Adapter_NoFile_NoHelp braucht einen Lauf ohne
// Datei.
function PlanSeen(const ASource: string; const ASeen: TSeen;
  AOpen: Boolean): TRdxFixOutcome;
var
  SL     : TStringList;
  Places : TSourcePlaces;
  F      : TLeakFinding;
begin
  SL := TStringList.Create;
  Places := TSourcePlaces.Create;
  F := TLeakFinding.New('t.pas', '', ASeen.Line, ASeen.Msg,
    fkMoveSizeOfPointer);
  try
    SL.Text := ASource;
    if AOpen then
    begin
      Assert.IsTrue(Places.OpenSource('t.pas', ASource), 'OpenSource');
      Result := TRdxFixTable.FixFor(Places, SL, F,
        TRdxRecipeRunner.UsesNamesOf(Places));
    end
    else
      Result := TRdxFixTable.FixFor(nil, SL, F, nil);
  finally
    F.Free;
    Places.Free;
    SL.Free;
  end;
end;

function PlanFirst(const ASource: string): TRdxFixOutcome;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet einen Fund');
  Result := PlanSeen(ASource, Seen[0], True);
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt (FixAllWith: PlanFixIn mit geoeffnetem Quellstellen-Dienst -
// wie PlanFirst).
function FixAll(const ASource: string): string;
begin
  Result := FixAllWith(ASource, fkMoveSizeOfPointer, DetectKind);
end;

// Eine Unit mit EINER Routine AHead; deren Rumpf beginnt auf Zeile 6.
function Routine(const AHead: string; const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', AHead, 'begin'])
    + #13#10 + Join(ABody) + #13#10 + Join(['end;', 'end.']);
end;

procedure TTestRdxMoveSizeDetector.Detector_ReportsLineAndType;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(Routine('procedure Foo(Src: PInteger; Dst: PInteger);',
    ['  Move(Src^, Dst^, SizeOf(PInteger));']));
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(LINE, Seen[0].Line, 'Zeile des Aufrufs');
  Assert.AreEqual('Integer', TRdxMoveSizeFix.TargetTypeOf(Seen[0].Msg),
    Seen[0].Msg);
end;

procedure TTestRdxMoveSizeDetector.Detector_RoundTrip;
var
  Fixed : string;
begin
  Fixed := FixAll(Routine('procedure Foo(Src: PInteger; Dst: PInteger);',
    ['  Move(Src^, Dst^, SizeOf(PInteger));']));
  Assert.AreEqual(Routine('procedure Foo(Src: PInteger; Dst: PInteger);',
    ['  Move(Src^, Dst^, SizeOf(Integer));']), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxMoveSizeDetector.Detector_FillCharVariable_Fixed;
begin
  Assert.AreEqual(Routine('procedure Foo(var V: Int64);',
    ['  FillChar(V, SizeOf(Int64), 0);']),
    FixAll(Routine('procedure Foo(var V: Int64);',
      ['  FillChar(V, SizeOf(PInt64), 0);'])));
end;

procedure TTestRdxMoveSizeDetector.Detector_ZeroMemoryPointer_Fixed;
begin
  Assert.AreEqual(Routine('procedure Foo(P: PDouble);',
    ['  ZeroMemory(P, SizeOf(Double));']),
    FixAll(Routine('procedure Foo(P: PDouble);',
      ['  ZeroMemory(P, SizeOf(PDouble));'])));
end;

procedure TTestRdxMoveSizeDetector.Detector_CatalogExample_NoHelp;
var
  Meta : TRuleMeta;
  O    : TRdxFixOutcome;
begin
  // Der Katalog nullt mit SizeOf(PInteger) ueber einen PByte - welches
  // Element gemeint ist, steht nicht fest.
  Meta := TRuleCatalog.GetRuleCanonical(fkMoveSizeOfPointer);
  Assert.IsTrue(Pos('FillChar(P^, SizeOf(PInteger), 0)', Meta.BadExample) > 0,
    Meta.BadExample);
  O := PlanFirst(Routine('procedure Foo(P: PByte);',
    ['  FillChar(P^, SizeOf(PInteger), 0);']));
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_SIZE_TYPE, ['P', 'pbyte', 'PInteger']), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

procedure TTestRdxMoveSizeDetector.Detector_PointerCopy_NoHelp;
var
  O : TRdxFixOutcome;
begin
  // Kopiert wird der Zeiger selbst - dort ist die Zeigergroesse richtig.
  O := PlanFirst(Routine('procedure Foo(Src: PInteger; Dst: PInteger);',
    ['  Move(Src, Dst, SizeOf(PInteger));']));
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_SIZE_TYPE, ['Src', 'pinteger', 'Integer']), O.Reason);
end;

procedure TTestRdxMoveSizeDetector.Detector_UndeclaredBuffer_NoHelp;
var
  O : TRdxFixOutcome;
begin
  // Src ist in der Unit nicht deklariert - der Typ ist nicht bewiesen.
  O := PlanFirst(Routine('procedure Foo(Dst: PInteger);',
    ['  Move(Src^, Dst^, SizeOf(PInteger));']));
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_SIZE_UNKNOWN, ['Src', 'PInteger']), O.Reason);
end;

procedure TTestRdxMoveSizeDetector.Detector_IndexedBuffer_NoHelp;
var
  O : TRdxFixOutcome;
begin
  O := PlanFirst(Routine('procedure Foo(Dst: PInteger);',
    ['  Move(Buf[0], Dst^, SizeOf(PInteger));']));
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_SIZE_BUFFER, ['Buf[0]']), O.Reason);
end;

procedure TTestRdxMoveSizeDetector.Adapter_NoFile_NoHelp;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
begin
  Src := Routine('procedure Foo(Src: PInteger; Dst: PInteger);',
    ['  Move(Src^, Dst^, SizeOf(PInteger));']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen));
  O := PlanSeen(Src, Seen[0], False);
  Assert.IsFalse(O.Enabled);
  Assert.AreEqual(R_NO_FILE, O.Reason);
  Assert.AreEqual('Integer', O.Name, 'Name auch ohne Datei');
  // Mit Datei: die Hilfe gilt.
  O := PlanSeen(Src, Seen[0], True);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual<Integer>(1, Length(O.Edits));
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxMoveSizeFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxMoveSizeDetector);
  {$ENDIF}

end.
