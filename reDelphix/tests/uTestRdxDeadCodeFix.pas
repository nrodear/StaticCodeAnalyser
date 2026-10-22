unit uTestRdxDeadCodeFix;

// Editorhilfe SCA011 DeadCode (uRdxDeadCodeFix): der Planer auf Text
// (erste Fixture, FPC-tauglich) und der ECHTE Detektor (uDeadCode) auf dem
// echten AST mit MapFix wie der Adapter der Tabelle (zweite Fixture, nur
// Delphi). Die Fixtures stehen in einer Routine 'Foo', deren Rumpf auf
// Zeile 5 beginnt; seine erste Anweisung steht auf Zeile 6 (BODY).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxDeadCodeFix = class
  public
    // ---- Umformung ----
    [Test] procedure ExitThenCall_Deleted;
    [Test] procedure SeveralAndNested_Deleted;
    [Test] procedure RaiseMultiLine_Deleted;
    [Test] procedure ExitWithValue_Deleted;
    [Test] procedure BreakInLoop_Deleted;
    [Test] procedure ContinueInRepeat_StopsAtUntil;
    [Test] procedure TryParts_StopAtExceptAndFinally;
    [Test] procedure NestedBlock_OnlyItsTail;
    [Test] procedure BlankLines_Kept;
    [Test] procedure CaseAndTryInRange_Deleted;
    [Test] procedure LineCountAndTerminator;
    // ---- Gegenproben ----
    [Test] procedure Comment_NoHelp;
    [Test] procedure LabelOrTypedDecl_NoHelp;
    [Test] procedure Directive_NoHelp;
    [Test] procedure ConditionalTerminator_NoHelp;
    [Test] procedure Moved_NoHelp;
    [Test] procedure SameLineEnd_NoHelp;
    [Test] procedure Shadowed_NoHelp;
    [Test] procedure Asm_NoHelp;
    [Test] procedure ElseOrNoEnd_NoHelp;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxDeadCodeDetector = class
  public
    [Test] procedure Detector_ReportsFirstDeadLine;
    [Test] procedure Detector_RoundTripExit;
    [Test] procedure Detector_RoundTripRaiseInTry;
    [Test] procedure Detector_RoundTripBreak;
    [Test] procedure Detector_CatalogExample_Fixed;
    [Test] procedure Detector_ParkedWithComment_NoHelp;
    [Test] procedure Detector_TwoBlocks_BothFixed;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uRuleCatalog, uDeadCode,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixRunner,         // MapFix (wie der Adapter der Tabelle)
  uTestRdxDetectorKit,   // TSeen, DetectSource, CatalogText
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxDeadCodeFix,
  uRdxText,              // _() und die gemeinsamen Gruende
  uTestRdxTextKit;       // Join, Apply

const
  BODY = 6;   // erste Rumpfzeile von Wrap

// ---- Helfer ----

// Eine Unit mit EINER Routine Foo; Rumpf ab Zeile 6.
function Wrap(const ABody: array of string): string;
begin
  Result := Join(['unit t;', 'interface', 'implementation', 'procedure Foo;',
    'begin']) + #13#10 + Join(ABody) + #13#10 + Join(['end;', 'end.']);
end;

// Die Meldung des Detektors zum Terminator ATerm ('Exit', 'raise' ...).
function Msg(const ATerm: string): string;
begin
  Result := 'Dead code after ' + ATerm;
end;

// Der Planer fuer Zeile ALine: True mit der Ersetzung, sonst der Grund.
function PlanEdit(const ASource: string; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  SL  : TStringList;
  Map : TRdxCodeMap;
begin
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Map := TRdxCodeMap.Create(SL);
    try
      Result := TRdxDeadCodeFix.DeleteDeadCode(Map, ALine, AMessage, AEdit,
        AReason);
    finally
      Map.Free;
    end;
  finally
    SL.Free;
  end;
end;

// Der neue Text, oder '' bei Ablehnung (AReason).
function Plan(const ASource: string; ALine: Integer; const ATerm: string;
  out AReason: string): string;
var
  E : TRdxEdit;
begin
  Result := '';
  if PlanEdit(ASource, ALine, Msg(ATerm), E, AReason) then
    Result := Apply(ASource, E);
end;

// Die Hilfe muss gelten (sonst scheitert der Test mit dem Grund).
function Applied(const ASource: string; ALine: Integer;
  const ATerm: string): string;
var
  R : string;
begin
  Result := Plan(ASource, ALine, ATerm, R);
  Assert.IsTrue(Result <> '', R);
end;

procedure AssertRefused(const ASource: string; ALine: Integer;
  const ATerm, AReason: string);
var
  R : string;
begin
  Assert.AreEqual('', Plan(ASource, ALine, ATerm, R), 'keine Hilfe');
  Assert.AreEqual(AReason, R, 'Grund');
end;

// ---- Umformung ----

procedure TTestRdxDeadCodeFix.ExitThenCall_Deleted;
begin
  Assert.AreEqual(Wrap(['  Exit;']),
    Applied(Wrap(['  Exit;', '  WriteLn(''never reached'');']), BODY + 1,
      'Exit'));
end;

procedure TTestRdxDeadCodeFix.SeveralAndNested_Deleted;
begin
  // Alles bis zum end der Liste - samt if/else und Schleife darin.
  Assert.AreEqual(Wrap(['  Foo;', '  Exit;']),
    Applied(Wrap(['  Foo;', '  Exit;', '  Bar;', '  if A then', '  begin',
      '    Baz;', '  end', '  else', '    Qux;', '  for I := 1 to 3 do',
      '    Run(I);']), BODY + 2, 'Exit'));
end;

procedure TTestRdxDeadCodeFix.RaiseMultiLine_Deleted;
begin
  // Der raise geht ueber zwei Zeilen; die Klammern trennen die Anweisung.
  Assert.AreEqual(
    Wrap(['  raise EFoo.Create(''a'' +', '    ''b'');']),
    Applied(Wrap(['  raise EFoo.Create(''a'' +', '    ''b'');',
      '  Cleanup;']), BODY + 2, 'raise'));
end;

procedure TTestRdxDeadCodeFix.ExitWithValue_Deleted;
var
  Src : string;
begin
  // Ein vertauschtes Paar wie in der Stichprobe (MVCFramework.JWT).
  Src := Join(['unit t;', 'interface', 'implementation',
    'function Foo: Boolean;', 'begin', '  Exit(Check(A, B));',
    '  Error := 1;', 'end;', 'end.']);
  Assert.AreEqual(Join(['unit t;', 'interface', 'implementation',
    'function Foo: Boolean;', 'begin', '  Exit(Check(A, B));', 'end;',
    'end.']), Applied(Src, BODY + 1, 'Exit'));
end;

procedure TTestRdxDeadCodeFix.BreakInLoop_Deleted;
begin
  Assert.AreEqual(
    Wrap(['  for I := 1 to 3 do', '  begin', '    Break;', '  end;']),
    Applied(Wrap(['  for I := 1 to 3 do', '  begin', '    Break;',
      '    Foo(I);', '  end;']), BODY + 3, 'Break'));
end;

procedure TTestRdxDeadCodeFix.ContinueInRepeat_StopsAtUntil;
begin
  Assert.AreEqual(
    Wrap(['  repeat', '    Continue;', '  until A;']),
    Applied(Wrap(['  repeat', '    Continue;', '    Foo;', '  until A;']),
      BODY + 2, 'Continue'));
end;

procedure TTestRdxDeadCodeFix.TryParts_StopAtExceptAndFinally;
begin
  Assert.AreEqual(
    Wrap(['  try', '    Exit;', '  finally', '    Bar;', '  end;']),
    Applied(Wrap(['  try', '    Exit;', '    Foo;', '  finally', '    Bar;',
      '  end;']), BODY + 2, 'Exit'));
  Assert.AreEqual(
    Wrap(['  try', '    raise E;', '  except', '    on X: Exception do',
      '      Bar;', '  end;']),
    Applied(Wrap(['  try', '    raise E;', '    Foo;', '  except',
      '    on X: Exception do', '      Bar;', '  end;']), BODY + 2, 'raise'));
end;

procedure TTestRdxDeadCodeFix.NestedBlock_OnlyItsTail;
begin
  // Das Exit steht im inneren Block - Bar dahinter laeuft.
  Assert.AreEqual(
    Wrap(['  if A then', '  begin', '    Exit;', '  end;', '  Bar;']),
    Applied(Wrap(['  if A then', '  begin', '    Exit;', '    Foo;', '  end;',
      '  Bar;']), BODY + 3, 'Exit'));
end;

procedure TTestRdxDeadCodeFix.BlankLines_Kept;
begin
  // Leerzeilen vor und hinter dem toten Code bleiben, die dazwischen gehen.
  Assert.AreEqual(Wrap(['  Exit;', '', '']),
    Applied(Wrap(['  Exit;', '', '  Foo;', '', '  Bar;', '']), BODY + 2,
      'Exit'));
end;

procedure TTestRdxDeadCodeFix.CaseAndTryInRange_Deleted;
begin
  // case-Werte und der Typ eines on-Handlers sind keine Marken.
  Assert.AreEqual(Wrap(['  Exit;']),
    Applied(Wrap(['  Exit;', '  case A of', '    1: Foo;',
      '    2: begin Bar; end;', '  else', '    Baz;', '  end;', '  try',
      '    Qux;', '  except', '    on E: Exception do', '      Log(E);',
      '  end;']), BODY + 1, 'Exit'));
end;

procedure TTestRdxDeadCodeFix.LineCountAndTerminator;
var
  E : TRdxEdit;
  R : string;
begin
  // Drei Zeilen (die Leerzeile dazwischen zaehlt mit) - der Name im
  // Menuetext.
  Assert.IsTrue(PlanEdit(Wrap(['  Exit;', '  Foo;', '', '  Bar;']), BODY + 1,
    Msg('Exit'), E, R), R);
  Assert.AreEqual<Integer>(3, TRdxDeadCodeFix.LineCountOf(E));
  Assert.AreEqual('exit', TRdxDeadCodeFix.TerminatorOf(Msg('Exit')));
  Assert.AreEqual('continue', TRdxDeadCodeFix.TerminatorOf(Msg('Continue')));
  Assert.AreEqual('', TRdxDeadCodeFix.TerminatorOf(Msg('Halt')));
  Assert.AreEqual('', TRdxDeadCodeFix.TerminatorOf('Dead code'));
end;

// ---- Gegenproben ----

procedure TTestRdxDeadCodeFix.Comment_NoHelp;
begin
  // Hinter dem Terminator, als eigene Zeile, am Ende einer toten Zeile -
  // er dokumentiert oft geparkten Code.
  AssertRefused(Wrap(['  Exit; // alt:', '  Foo;']), BODY + 1, 'Exit',
    _(R_DEAD_COMMENT));
  AssertRefused(Wrap(['  Exit;', '  Foo;', '  // Bar;', '  Baz;']), BODY + 1,
    'Exit', _(R_DEAD_COMMENT));
  AssertRefused(Wrap(['  Exit;', '  Foo; { x }']), BODY + 1, 'Exit',
    _(R_DEAD_COMMENT));
end;

procedure TTestRdxDeadCodeFix.LabelOrTypedDecl_NoHelp;
begin
  // Eine Marke macht den Rest per goto erreichbar.
  AssertRefused(Wrap(['  Exit;', '  Foo;', 'Fin:', '  Bar;']), BODY + 1,
    'Exit', _(R_DEAD_COLON));
  AssertRefused(Wrap(['  Exit;', '  var X: Integer := 1;']), BODY + 1, 'Exit',
    _(R_DEAD_COLON));
  // Gegenprobe: ein Doppelpunkt in Klammern ist ein Format.
  Assert.AreEqual(Wrap(['  Exit;']),
    Applied(Wrap(['  Exit;', '  WriteLn(X:5:2);']), BODY + 1, 'Exit'));
end;

procedure TTestRdxDeadCodeFix.Directive_NoHelp;
begin
  AssertRefused(Wrap(['  Exit;', '  {$IFDEF X}', '  Foo;', '  {$ENDIF}']),
    BODY + 2, 'Exit', _(R_DEAD_DIRECTIVE));
  AssertRefused(Wrap(['  Exit;', '  Foo;', '  {$R+}']), BODY + 1, 'Exit',
    _(R_DEAD_DIRECTIVE));
end;

procedure TTestRdxDeadCodeFix.ConditionalTerminator_NoHelp;
begin
  // Hinter then/else ist der Terminator bedingt - der Code danach laeuft.
  AssertRefused(Wrap(['  if A then Exit;', '  Foo;']), BODY + 1, 'Exit',
    _(R_DEAD_CONDITIONAL, ['Exit', 'then']));
  AssertRefused(Wrap(['  if A then Foo else', '    raise E;', '  Bar;']),
    BODY + 2, 'raise', _(R_DEAD_CONDITIONAL, ['raise', 'else']));
end;

procedure TTestRdxDeadCodeFix.Moved_NoHelp;
var
  Src : string;
begin
  Src := Wrap(['  Exit;', '  Foo;']);
  // Davor steht kein Terminator bzw. ein anderer als in der Meldung.
  AssertRefused(Wrap(['  Bar;', '  Foo;']), BODY + 1, 'Exit',
    MsgMovedSuffix(_(R_DEAD_NOT_AFTER, ['exit'])));
  AssertRefused(Src, BODY + 1, 'raise',
    MsgMovedSuffix(_(R_DEAD_NOT_AFTER, ['raise'])));
  // Die Zeile des Terminators selbst, die des end, hinter der Datei.
  AssertRefused(Src, BODY, 'Exit',
    MsgMovedSuffix(_(R_DEAD_NOT_AFTER, ['exit'])));
  AssertRefused(Src, BODY + 2, 'Exit', MsgMovedSuffix(_(R_DEAD_MOVED)));
  AssertRefused(Src, 99, 'Exit', MsgMovedSuffix(_(R_DEAD_MOVED)));
  // Ohne bzw. mit unbekanntem Terminator in der Meldung.
  AssertRefused(Src, BODY + 1, 'Halt', _(R_DEAD_NO_TERM));
end;

procedure TTestRdxDeadCodeFix.SameLineEnd_NoHelp;
begin
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'procedure Foo;', 'begin', '  Exit;', '  Foo; end;', 'end.']), BODY + 1,
    'Exit', _(R_DEAD_SAME_LINE));
end;

procedure TTestRdxDeadCodeFix.Shadowed_NoHelp;
begin
  // Ein eigenes Exit bzw. ein Parameter Continue: der "Terminator" ist ein
  // Aufruf bzw. kein Sprung.
  AssertRefused(Join(['unit t;', 'interface', 'procedure Exit;',
    'implementation', 'procedure Foo;', 'begin', '  Exit;', '  Bar;', 'end;',
    'end.']), 8, 'Exit', _(R_DEAD_SHADOW, ['Exit']));
  AssertRefused(Join(['unit t;', 'interface', 'implementation',
    'procedure Foo(var Continue: Boolean);', 'begin', '  while A do',
    '  begin', '    Continue;', '    Bar;', '  end;', 'end;', 'end.']), 9,
    'Continue', _(R_DEAD_SHADOW, ['Continue']));
end;

procedure TTestRdxDeadCodeFix.Asm_NoHelp;
begin
  AssertRefused(Wrap(['  Exit;', '  asm', '    nop', '  end;']), BODY + 1,
    'Exit', _(R_DEAD_ASM));
end;

procedure TTestRdxDeadCodeFix.ElseOrNoEnd_NoHelp;
begin
  // Ein else ohne if der toten Anweisung, eine Liste ohne Ende.
  AssertRefused(Wrap(['  Exit;', '  Foo', '  else', '  Bar;']), BODY + 1,
    'Exit', _(R_DEAD_ELSE));
  AssertRefused(Join(['program p;', 'begin', '  Exit;', '  Foo;']), 4, 'Exit',
    _(R_DEAD_NO_END));
end;

{$IFNDEF FPC}

{ ---- Detektor ---- }

// Die Funde der Art SCA011 - der echte Detektor auf dem echten AST.
procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TDeadCodeDetector.AnalyzeUnit(Root, Path, Results);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectSource('rdx_dead_', ASource, fkDeadCode, RunDetector);
end;

// Die Hilfe fuer den ersten Fund des Detektors ueber MapFix - so ruft sie
// der Adapter der Tabelle.
function PlanFirst(const ASource: string; out ASeen: TSeen): TRdxFixOutcome;
var
  Seen : TArray<TSeen>;
  SL   : TStringList;
begin
  Seen := Detect(ASource);
  Assert.IsTrue(Length(Seen) > 0, 'der Detektor meldet einen Fund');
  ASeen := Seen[0];
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    Result := MapFix(SL, ASeen.Line, ASeen.Msg,
      TRdxDeadCodeFix.DeleteDeadCode);
  finally
    SL.Free;
  end;
end;

// Fund fuer Fund, nach jeder Ersetzung neu gemeldet, bis der Detektor
// schweigt.
function FixAll(const ASource: string): string;
const
  MAX_PASSES = 10;
var
  Pass : Integer;
  O    : TRdxFixOutcome;
  S    : TSeen;
begin
  Result := ASource;
  for Pass := 1 to MAX_PASSES do
  begin
    if Length(Detect(Result)) = 0 then
      Exit;
    O := PlanFirst(Result, S);
    Assert.IsTrue(O.Enabled, O.Reason);
    Result := Apply(Result, O.Edits);
  end;
  Assert.Fail('der Detektor schweigt auch nach zehn Durchlaeufen nicht');
end;

procedure TTestRdxDeadCodeDetector.Detector_ReportsFirstDeadLine;
var
  Seen : TArray<TSeen>;
begin
  Seen := Detect(Wrap(['  Exit;', '  WriteLn(''never reached'');',
    '  Foo;']));
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund je Block');
  Assert.AreEqual<Integer>(BODY + 1, Seen[0].Line, 'erste tote Anweisung');
  Assert.AreEqual('Dead code after Exit', Seen[0].Msg);
end;

procedure TTestRdxDeadCodeDetector.Detector_RoundTripExit;
var
  Fixed : string;
begin
  Fixed := FixAll(Wrap(['  Exit;', '  WriteLn(''never reached'');',
    '  Foo;']));
  Assert.AreEqual(Wrap(['  Exit;']), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxDeadCodeDetector.Detector_RoundTripRaiseInTry;
var
  Src  : string;
  Seen : TArray<TSeen>;
begin
  Src := Wrap(['  try', '    raise EFoo.Create(''x'');', '    Foo;',
    '  finally', '    Bar;', '  end;']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual<Integer>(BODY + 2, Seen[0].Line, 'Foo');
  Assert.AreEqual('Dead code after raise', Seen[0].Msg);
  Assert.AreEqual(Wrap(['  try', '    raise EFoo.Create(''x'');', '  finally',
    '    Bar;', '  end;']), FixAll(Src));
end;

procedure TTestRdxDeadCodeDetector.Detector_RoundTripBreak;
var
  Src  : string;
  Seen : TArray<TSeen>;
begin
  Src := Wrap(['  for I := 1 to 3 do', '  begin', '    Break;', '    Foo(I);',
    '  end;']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen), 'ein Fund');
  Assert.AreEqual('Dead code after Break', Seen[0].Msg);
  Assert.AreEqual(Wrap(['  for I := 1 to 3 do', '  begin', '    Break;',
    '  end;']), FixAll(Src));
end;

procedure TTestRdxDeadCodeDetector.Detector_CatalogExample_Fixed;
var
  Meta : TRuleMeta;
  Src  : string;
begin
  Meta := TRuleCatalog.GetRuleCanonical(fkDeadCode);
  Assert.IsTrue(Pos('Exit;', Meta.BadExample) > 0, Meta.BadExample);
  Src := Wrap([CatalogText(Meta.BadExample)]);
  Assert.AreEqual<Integer>(1, Length(Detect(Src)),
    'der Detektor meldet das Beispiel');
  Assert.AreEqual(Wrap(['Exit;']), FixAll(Src));
end;

procedure TTestRdxDeadCodeDetector.Detector_ParkedWithComment_NoHelp;
var
  S : TSeen;
  O : TRdxFixOutcome;
begin
  // Der Detektor sieht keine Kommentare - die Hilfe sperrt.
  O := PlanFirst(Wrap(['  Exit; // alt:', '  Foo;']), S);
  Assert.AreEqual<Integer>(BODY + 1, S.Line, 'Foo');
  Assert.IsFalse(O.Enabled, 'keine Hilfe');
  Assert.AreEqual(_(R_DEAD_COMMENT), O.Reason);
  Assert.AreEqual<Integer>(0, Length(O.Edits), 'keine Ersetzung');
end;

procedure TTestRdxDeadCodeDetector.Detector_TwoBlocks_BothFixed;
var
  Src : string;
begin
  // Je Block ein Fund: hinter dem Exit im inneren Block und hinter dem
  // raise im aeusseren.
  Src := Wrap(['  if A then', '  begin', '    Exit;', '    Foo;', '  end;',
    '  raise E;', '  Bar;']);
  Assert.AreEqual<Integer>(2, Length(Detect(Src)), 'zwei Funde');
  Assert.AreEqual(Wrap(['  if A then', '  begin', '    Exit;', '  end;',
    '  raise E;']), FixAll(Src));
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxDeadCodeFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxDeadCodeDetector);
  {$ENDIF}

end.
