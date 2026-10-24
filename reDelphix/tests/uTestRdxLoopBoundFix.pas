unit uTestRdxLoopBoundFix;

// Editorhilfe LoopPastHighBound (uRdxLoopBoundFix, Charge A3 / Q2): der
// Planer auf Text mit allen Formen und Sperren (erste Fixture, auch FPC),
// dazu der ECHTE Detektor (uLoopPastHighBound) ueber den Einstieg der
// Tabelle (TRdxFixTable.FixFor, Adapter PlanLoopBound; zweite Fixture, nur
// Delphi): der Detektor meldet, die Hilfe wird angewandt, der Detektor
// schweigt danach. Die Faelle der ersten Fixture stehen im Rumpf von P ab
// Zeile 8 (LINE).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestRdxLoopBoundFix = class
  public
    // ---- Formen ----
    [Test] procedure Count_GetsMinusOne;
    [Test] procedure Count_ChainAndSpellingKept;
    [Test] procedure Length_Array_BecomesHigh;
    [Test] procedure LowLength_BecomesLowHigh;
    [Test] procedure Length_String_StartsAtOne;
    [Test] procedure HighPlusOne_Dropped;
    [Test] procedure StringPlusOne_Dropped;
    [Test] procedure InlineVarAndTypedVar;
    [Test] procedure RangeAfter_NamesTheNewRange;
    // ---- Sperren ----
    [Test] procedure Refuse_CountFromOne;
    [Test] procedure Refuse_TypeNotProven;
    [Test] procedure Refuse_StringHighPlusOne;
    [Test] procedure Refuse_DirectiveInHeadLine;
    [Test] procedure Refuse_HeadOverTwoLines;
    [Test] procedure Refuse_CommentInHead;
    [Test] procedure Refuse_OtherRangeOnLine;
    [Test] procedure Refuse_TwoHeadsOnLine;
    [Test] procedure Refuse_ForeignMessage;
  end;

{$IFNDEF FPC}
  [TestFixture]
  TTestRdxLoopBoundDetector = class
  public
    [Test] procedure Detector_Count_RoundTrip;
    [Test] procedure Detector_StringAndArray_RoundTrip;
    [Test] procedure Detector_HighPlusOneAndStringPlusOne_RoundTrip;
    [Test] procedure Detector_UnprovenCount_Fixed;
    [Test] procedure Detector_UnprovenLength_NoHelp;
    [Test] procedure Detector_CountFromOne_NoHelp;
    [Test] procedure Adapter_NameCaptionAndChanges;
    [Test] procedure Adapter_NoFile_NoHelp;
  end;
{$ENDIF}

implementation

uses
  System.SysUtils, System.Classes,
  {$IFNDEF FPC}
  System.Generics.Collections,
  uAstNode, uMethodd12, uSCAConsts, uLoopPastHighBound,
  uRdxRecipeRunner,      // TRdxFixOutcome
  uRdxFixTable,          // TRdxFixTable.FixFor, CaptionFor
  uTestRdxDetectorKit,   // TSeen, DetectSource, FixAllWith, AssertNoHelpWith
  {$ENDIF}
  uRdxBufferMath, uRdxCodeMap, uRdxLoopBoundFix,
  uRdxText,              // _(), MsgMovedSuffix
  uTestRdxTextKit;       // Join, Apply, NewMap

const
  LINE = 8;   // erste Rumpfzeile von InUnit
  // Die Raete des Detektors (uLoopBoundScan) woertlich.
  ADV_LAST = 'the last pass is out of range; the bound should be ';

// ---- Helfer ----

function InUnit(const ABody: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation',
    'procedure P(L: TStringList; const A: array of Integer; S: string);',
    'var', '  i: Integer;', 'begin']) + #13#10 + Join(ABody) + #13#10
    + Join(['end;', 'end.']);
end;

// Die Meldung wie der Detektor sie schreibt.
function Msg(const AVar, ALow, AHigh, AAccess, AAdvice: string): string;
begin
  Result := 'Loop past the last index: ' + AVar + ' := ' + ALow + ' to ' +
    AHigh + ' with ' + AAccess + ' - ' + AAdvice;
end;

// Der Planer fuer ALine: der neue Text oder '' mit dem Grund in AReason.
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
    Ok := TRdxLoopBoundFix.LastIndex(Map, ALine, AMessage, E, AReason);
  finally
    Map.Free;
  end;
  if Ok then
    Result := Apply(ASource, E);
end;

procedure AssertFixed(const ABefore, AAfter: array of string;
  const AMessage: string);
var
  Reason : string;
begin
  Assert.AreEqual(InUnit(AAfter), PlanAt(InUnit(ABefore), LINE, AMessage,
    Reason), Reason);
end;

procedure AssertRefused(const ABody: array of string; ALine: Integer;
  const AMessage, AWant: string);
var
  Reason : string;
begin
  Assert.AreEqual('', PlanAt(InUnit(ABody), ALine, AMessage, Reason),
    'keine Hilfe');
  Assert.AreEqual(AWant, Reason);
end;

{ ---- Formen ---- }

procedure TTestRdxLoopBoundFix.Count_GetsMinusOne;
begin
  AssertFixed(['  for i := 0 to L.Count do', '    WriteLn(L[i]);'],
    ['  for i := 0 to L.Count - 1 do', '    WriteLn(L[i]);'],
    Msg('i', '0', 'L.Count', 'L[i]', ADV_LAST + 'L.Count - 1'));
end;

procedure TTestRdxLoopBoundFix.Count_ChainAndSpellingKept;
begin
  // Kette, kleines 'count', Tabulator und Kommentar HINTER dem Kopf; der Rat
  // des Detektors schreibt 'Count' immer gross.
  AssertFixed(['  for I := 0 to Memo1.Lines.count do'#9'S := S + '
    + 'Memo1.Lines[I]; // alle'],
    ['  for I := 0 to Memo1.Lines.count - 1 do'#9'S := S + '
    + 'Memo1.Lines[I]; // alle'],
    Msg('I', '0', 'Memo1.Lines.count', 'Memo1.Lines[I]',
      ADV_LAST + 'Memo1.Lines.Count - 1'));
end;

procedure TTestRdxLoopBoundFix.Length_Array_BecomesHigh;
begin
  AssertFixed(['  for i := 0 to Length(A) do WriteLn(A[i]);'],
    ['  for i := 0 to High(A) do WriteLn(A[i]);'],
    Msg('i', '0', 'Length(A)', 'A[i]', ADV_LAST + 'High(A)'));
  // Die Schreibweise folgt dem Wort.
  AssertFixed(['  for i := 0 to length(A) do WriteLn(A[i]);'],
    ['  for i := 0 to high(A) do WriteLn(A[i]);'],
    Msg('i', '0', 'length(A)', 'A[i]', ADV_LAST + 'High(A)'));
end;

procedure TTestRdxLoopBoundFix.LowLength_BecomesLowHigh;
begin
  AssertFixed(['  for i := Low(A) to Length(A) do WriteLn(A[i]);'],
    ['  for i := Low(A) to High(A) do WriteLn(A[i]);'],
    Msg('i', 'Low(A)', 'Length(A)', 'A[i]', ADV_LAST + 'High(A)'));
end;

procedure TTestRdxLoopBoundFix.Length_String_StartsAtOne;
begin
  AssertFixed(['  for i := 0 to Length(S) do', '    WriteLn(S[i]);'],
    ['  for i := 1 to Length(S) do', '    WriteLn(S[i]);'],
    Msg('i', '0', 'Length(S)', 'S[i]',
      'strings start at 1; the loop should run 1 to Length(S)'));
end;

procedure TTestRdxLoopBoundFix.HighPlusOne_Dropped;
begin
  AssertFixed(['  for i := 0 to High(A) + 1 do WriteLn(A[i]);'],
    ['  for i := 0 to High(A) do WriteLn(A[i]);'],
    Msg('i', '0', 'High(A) + 1', 'A[i]', ADV_LAST + 'High(A)'));
  // Ohne Leerzeichen um '+': die Meldung schreibt den Kopf genormt.
  AssertFixed(['  for i := Low(A) to High(A)+1 do WriteLn(A[i]);'],
    ['  for i := Low(A) to High(A) do WriteLn(A[i]);'],
    Msg('i', 'Low(A)', 'High(A) + 1', 'A[i]', ADV_LAST + 'High(A)'));
end;

procedure TTestRdxLoopBoundFix.StringPlusOne_Dropped;
begin
  AssertFixed(['  for i := 1 to Length(S) + 1 do WriteLn(S[i]);'],
    ['  for i := 1 to Length(S) do WriteLn(S[i]);'],
    Msg('i', '1', 'Length(S) + 1', 'S[i]',
      'strings end at Length(S); the bound should be Length(S)'));
end;

procedure TTestRdxLoopBoundFix.InlineVarAndTypedVar;
begin
  AssertFixed(['  for var k := 0 to L.Count do WriteLn(L[k]);'],
    ['  for var k := 0 to L.Count - 1 do WriteLn(L[k]);'],
    Msg('k', '0', 'L.Count', 'L[k]', ADV_LAST + 'L.Count - 1'));
  AssertFixed(['  for var k: Integer := 0 to L.Count do WriteLn(L[k]);'],
    ['  for var k: Integer := 0 to L.Count - 1 do WriteLn(L[k]);'],
    Msg('k', '0', 'L.Count', 'L[k]', ADV_LAST + 'L.Count - 1'));
end;

procedure TTestRdxLoopBoundFix.RangeAfter_NamesTheNewRange;
begin
  Assert.AreEqual('0 to L.Count - 1', TRdxLoopBoundFix.RangeAfter(
    Msg('i', '0', 'L.Count', 'L[i]', ADV_LAST + 'L.Count - 1')));
  Assert.AreEqual('0 to high(A)', TRdxLoopBoundFix.RangeAfter(
    Msg('i', '0', 'length(A)', 'A[i]', ADV_LAST + 'High(A)')));
  Assert.AreEqual('1 to Length(S)', TRdxLoopBoundFix.RangeAfter(
    Msg('i', '0', 'Length(S)', 'S[i]',
      'strings start at 1; the loop should run 1 to Length(S)')));
  Assert.AreEqual('Low(A) to High(A)', TRdxLoopBoundFix.RangeAfter(
    Msg('i', 'Low(A)', 'High(A) + 1', 'A[i]', ADV_LAST + 'High(A)')));
  Assert.AreEqual('', TRdxLoopBoundFix.RangeAfter(
    Msg('i', '1', 'L.Count', 'L[i]', 'x')), 'ohne Hilfe kein Bereich');
end;

{ ---- Sperren ---- }

procedure TTestRdxLoopBoundFix.Refuse_CountFromOne;
begin
  AssertRefused(['  for i := 1 to L.Count do WriteLn(L[i]);'], LINE,
    Msg('i', '1', 'L.Count', 'L[i]', 'the last pass is out of range; index '
      + 'L[i - 1] or bound L.Count - 1'), _(R_LOOPB_FROM_ONE));
end;

procedure TTestRdxLoopBoundFix.Refuse_TypeNotProven;
begin
  AssertRefused(['  for i := 0 to Length(X) do WriteLn(X[i]);'], LINE,
    Msg('i', '0', 'Length(X)', 'X[i]', ADV_LAST + 'High(X) - for a string '
      + 'the loop should run 1 to Length(X)'), _(R_LOOPB_TYPE));
  AssertRefused(['  for i := 0 to High(X) + 1 do WriteLn(X[i]);'], LINE,
    Msg('i', '0', 'High(X) + 1', 'X[i]', ADV_LAST + 'High(X) - for a string '
      + 'the loop should run 1 to High(X)'), _(R_LOOPB_TYPE));
end;

procedure TTestRdxLoopBoundFix.Refuse_StringHighPlusOne;
begin
  AssertRefused(['  for i := 0 to High(S) + 1 do WriteLn(S[i]);'], LINE,
    Msg('i', '0', 'High(S) + 1', 'S[i]',
      'strings start at 1; the loop should run 1 to High(S)'),
    _(R_LOOPB_BOTH_ENDS));
end;

procedure TTestRdxLoopBoundFix.Refuse_DirectiveInHeadLine;
begin
  AssertRefused(['  for i := 0 to L.Count do {$IFDEF X} WriteLn(L[i]); '
    + '{$ENDIF}'], LINE,
    Msg('i', '0', 'L.Count', 'L[i]', ADV_LAST + 'L.Count - 1'),
    _(R_LOOPB_DIRECTIVE));
end;

procedure TTestRdxLoopBoundFix.Refuse_HeadOverTwoLines;
begin
  AssertRefused(['  for i := 0 to', '    L.Count do WriteLn(L[i]);'], LINE,
    Msg('i', '0', 'L.Count', 'L[i]', ADV_LAST + 'L.Count - 1'),
    _(R_LOOPB_LINES));
end;

procedure TTestRdxLoopBoundFix.Refuse_CommentInHead;
begin
  AssertRefused(['  for i := 0 to { alle } L.Count do WriteLn(L[i]);'], LINE,
    Msg('i', '0', 'L.Count', 'L[i]', ADV_LAST + 'L.Count - 1'),
    _(R_LOOPB_NONCODE));
end;

procedure TTestRdxLoopBoundFix.Refuse_OtherRangeOnLine;
begin
  // Schon korrigiert (oder die Zeile ist verschoben): kein passender Kopf.
  AssertRefused(['  for i := 0 to L.Count - 1 do WriteLn(L[i]);'], LINE,
    Msg('i', '0', 'L.Count', 'L[i]', ADV_LAST + 'L.Count - 1'),
    MsgMovedSuffix(_(R_LOOPB_OTHER)));
  AssertRefused(['  for i := 0 to L.Count do WriteLn(L[i]);'], LINE + 1,
    Msg('i', '0', 'L.Count', 'L[i]', ADV_LAST + 'L.Count - 1'),
    MsgMovedSuffix(_(R_LOOPB_OTHER)));
end;

procedure TTestRdxLoopBoundFix.Refuse_TwoHeadsOnLine;
begin
  AssertRefused(['  for i := 0 to L.Count do WriteLn(L[i]); '
    + 'for i := 0 to L.Count do WriteLn(L[i]);'], LINE,
    Msg('i', '0', 'L.Count', 'L[i]', ADV_LAST + 'L.Count - 1'),
    _(R_LOOPB_MANY, [2]));
end;

procedure TTestRdxLoopBoundFix.Refuse_ForeignMessage;
begin
  AssertRefused(['  for i := 0 to L.Count do WriteLn(L[i]);'], LINE,
    'Reversed for-range: 10 > 1 (use `downto`?) - for i := 10 to 1 do',
    _(R_LOOPB_MESSAGE));
end;

{$IFNDEF FPC}

{ ---- echter Detektor und Adapter ---- }

const
  // Wie InUnit, aber mit 'uses System.Classes;' - der Rumpf beginnt auf
  // Zeile 9.
  DLINE = 9;

function DUnit(const ABody: array of string): string;
begin
  Result := Join(['unit u;', 'interface', 'implementation',
    'uses System.Classes;',
    'procedure P(L: TStringList; const A: array of Integer; S: string);',
    'var', '  i: Integer;', 'begin']) + #13#10 + Join(ABody) + #13#10
    + Join(['end;', 'end.']);
end;

procedure RunDetector(AKind: TFindingKind; Root: TAstNode;
  const Path: string; Results: TObjectList<TLeakFinding>);
begin
  TLoopPastHighBoundDetector.AnalyzeUnit(Root, Path, Results);
end;

function DetectKind(const ASource: string; AKind: TFindingKind): TArray<TSeen>;
begin
  Result := DetectSource('rdx_loopbound_', ASource, AKind, RunDetector);
end;

function Detect(const ASource: string): TArray<TSeen>;
begin
  Result := DetectKind(ASource, fkLoopPastHighBound);
end;

function FixAll(const ASource: string): string;
begin
  Result := FixAllWith(ASource, fkLoopPastHighBound, DetectKind);
end;

procedure AssertRoundTrip(const ABefore, AAfter: array of string);
var
  Fixed : string;
begin
  Assert.IsTrue(Length(Detect(DUnit(ABefore))) > 0, 'der Detektor meldet');
  Fixed := FixAll(DUnit(ABefore));
  Assert.AreEqual(DUnit(AAfter), Fixed);
  Assert.AreEqual<Integer>(0, Length(Detect(Fixed)),
    'der Detektor schweigt danach');
end;

procedure TTestRdxLoopBoundDetector.Detector_Count_RoundTrip;
begin
  AssertRoundTrip(['  for i := 0 to L.Count do', '    WriteLn(L[i]);'],
    ['  for i := 0 to L.Count - 1 do', '    WriteLn(L[i]);']);
end;

procedure TTestRdxLoopBoundDetector.Detector_StringAndArray_RoundTrip;
begin
  AssertRoundTrip(['  for i := 0 to Length(S) do',
    '    if S[i] = ''x'' then Exit;',
    '  for i := 0 to Length(A) do WriteLn(A[i]);'],
    ['  for i := 1 to Length(S) do',
    '    if S[i] = ''x'' then Exit;',
    '  for i := 0 to High(A) do WriteLn(A[i]);']);
end;

procedure TTestRdxLoopBoundDetector.Detector_HighPlusOneAndStringPlusOne_RoundTrip;
begin
  AssertRoundTrip(['  for i := Low(A) to High(A) + 1 do WriteLn(A[i]);',
    '  for i := 1 to Length(S) + 1 do WriteLn(S[i]);'],
    ['  for i := Low(A) to High(A) do WriteLn(A[i]);',
    '  for i := 1 to Length(S) do WriteLn(S[i]);']);
end;

procedure TTestRdxLoopBoundDetector.Detector_UnprovenCount_Fixed;
var
  Seen : TArray<TSeen>;
begin
  // Lines ist nicht deklariert (Property eines fremden Vorfahren): Warning,
  // die Hilfe gilt trotzdem - Count - 1 ist die Grenze jeder 0-basierten
  // Liste.
  Seen := Detect(DUnit(['  for i := 0 to Lines.Count do WriteLn(Lines[i]);']));
  Assert.AreEqual<Integer>(1, Length(Seen));
  AssertRoundTrip(['  for i := 0 to Lines.Count do WriteLn(Lines[i]);'],
    ['  for i := 0 to Lines.Count - 1 do WriteLn(Lines[i]);']);
end;

procedure TTestRdxLoopBoundDetector.Detector_UnprovenLength_NoHelp;
begin
  AssertNoHelpWith(DUnit(['  for i := 0 to Length(Items) do '
    + 'WriteLn(Items[i]);']), fkLoopPastHighBound, _(R_LOOPB_TYPE),
    DetectKind);
end;

procedure TTestRdxLoopBoundDetector.Detector_CountFromOne_NoHelp;
begin
  AssertNoHelpWith(DUnit(['  for i := 1 to L.Count do WriteLn(L[i]);']),
    fkLoopPastHighBound, _(R_LOOPB_FROM_ONE), DetectKind);
end;

procedure TTestRdxLoopBoundDetector.Adapter_NameCaptionAndChanges;
var
  Src  : string;
  Seen : TArray<TSeen>;
  O    : TRdxFixOutcome;
  Cap  : string;
begin
  Src := DUnit(['  for i := 0 to L.Count do WriteLn(L[i]);']);
  Seen := Detect(Src);
  Assert.AreEqual<Integer>(1, Length(Seen));
  Assert.AreEqual<Integer>(DLINE, Seen[0].Line, 'Zeile des for');
  O := PlanFixIn(Src, 't.pas', fkLoopPastHighBound, Seen[0]);
  Assert.IsTrue(O.Enabled, O.Reason);
  Assert.AreEqual('0 to L.Count - 1', O.Name);
  Assert.IsTrue(O.ChangesBehavior, 'die Schleife laeuft einmal weniger');
  Assert.IsTrue(O.Hint <> '', 'fester Hinweis der Zeile');
  Cap := TRdxFixTable.CaptionFor(fkLoopPastHighBound, O);
  Assert.IsTrue(Pos('0 to L.Count - 1', Cap) > 0, Cap);
end;

procedure TTestRdxLoopBoundDetector.Adapter_NoFile_NoHelp;
var
  F : TLeakFinding;
  O : TRdxFixOutcome;
begin
  F := TLeakFinding.New('t.pas', '', DLINE,
    Msg('i', '0', 'L.Count', 'L[i]', ADV_LAST + 'L.Count - 1'),
    fkLoopPastHighBound);
  try
    O := TRdxFixTable.FixFor(nil, nil, F, nil);
  finally
    F.Free;
  end;
  Assert.IsFalse(O.Enabled);
  Assert.AreEqual(MsgNoFileOpen, O.Reason);
end;

{$ENDIF}

initialization
  TDUnitX.RegisterTestFixture(TTestRdxLoopBoundFix);
  {$IFNDEF FPC}
  TDUnitX.RegisterTestFixture(TTestRdxLoopBoundDetector);
  {$ENDIF}

end.
