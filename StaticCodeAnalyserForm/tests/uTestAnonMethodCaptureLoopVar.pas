unit uTestAnonMethodCaptureLoopVar;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestAnonMethodCaptureLoopVar = class
  public
    [Test] procedure AnonProcCapturesLoopVar_Reported;
    [Test] procedure ForLoopWithoutAnonProc_NotReported;
    [Test] procedure AnonProcWithoutLoopVarRef_NotReported;
    [Test] procedure SyncClosureWithLoopVar_NotReported;
    [Test] procedure ShadowedLoopVar_NotReported;
    // --- Real-World-Audit 2026-07-31: Receiver-Vorspann ist keine Capture ---
    [Test] procedure LoopVarOnlyAsCallReceiver_NotReported;
    [Test] procedure LoopVarAsReceiverAndInClosureBody_Reported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestAnonMethodCaptureLoopVar.AnonProcCapturesLoopVar_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 9 do'#13#10 +
  '    TThread.CreateAnonymousThread(procedure begin WriteLn(i); end).Start;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkAnonMethodCaptureLoopVar) >= 1,
      'Anon-Proc in for-loop mit Loop-Var-Ref muss gemeldet werden');
  finally F.Free; end;
end;

procedure TTestAnonMethodCaptureLoopVar.ForLoopWithoutAnonProc_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i, j: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 9 do j := j + i;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAnonMethodCaptureLoopVar),
      'for-loop ohne anonymous-method ist kein Finding');
  finally F.Free; end;
end;

procedure TTestAnonMethodCaptureLoopVar.AnonProcWithoutLoopVarRef_NotReported;
// Anonymous-Proc im Loop aber OHNE Loop-Var-Referenz -> kein Capture-Bug.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 9 do'#13#10 +
  '    TThread.CreateAnonymousThread(procedure begin DoStuff; end).Start;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAnonMethodCaptureLoopVar),
      'Anon-Proc ohne Loop-Var-Ref ist kein Capture-Bug');
  finally F.Free; end;
end;

procedure TTestAnonMethodCaptureLoopVar.SyncClosureWithLoopVar_NotReported;
// FP-Fix (Real-World 2026-06-21): TThread.Synchronize laeuft BLOCKIEREND
// waehrend der Iteration - die Closure liest die Loop-Var beim korrekten
// Wert. Nur DEFERRED Closures (Thread/Queue) sind ein Capture-Bug.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 9 do'#13#10 +
  '    TThread.Synchronize(nil, procedure begin WriteLn(i); end);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAnonMethodCaptureLoopVar),
      'Synchronize-Closure laeuft synchron - kein Capture-Bug');
  finally F.Free; end;
end;

procedure TTestAnonMethodCaptureLoopVar.ShadowedLoopVar_NotReported;
// FP-Fix (Real-World 2026-06-21): die Loop-Var wird im Body als lokale
// Inline-Var neu deklariert -> die Closure referenziert das Local, nicht
// die captured Loop-Var.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 9 do'#13#10 +
  '  begin'#13#10 +
  '    var i := GetValue;'#13#10 +
  '    TThread.CreateAnonymousThread(procedure begin WriteLn(i); end).Start;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAnonMethodCaptureLoopVar),
      'Loop-Var im Body geshadowed - kein Capture-Bug');
  finally F.Free; end;
end;

procedure TTestAnonMethodCaptureLoopVar.LoopVarOnlyAsCallReceiver_NotReported;
// FP-Fix (Real-World-Audit 2026-07-31, Kastri DW.DelphiAST): die Loop-Var
// steht NUR als Aufruf-Empfaenger VOR dem anonymous-method-Literal
// (`LNode.Enumerate(ANodeType, function(...) ... end)`). Der Receiver wird
// sofort ausgewertet, der Closure-Rumpf referenziert die Loop-Var nie -
// keine Capture. Ohne das Gate meldet der Detektor hier einen Fund, weil
// Receiver und Closure im selben nkCall-Text stehen.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var LNode: TSyntaxNode;'#13#10 +
  'begin'#13#10 +
  '  for LNode in ChildNodes do'#13#10 +
  '    LNode.Enumerate(ANodeType, function(const ANode: TSyntaxNode): Boolean '#13#10 +
  '      begin Result := AHandler(ANode); end);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkAnonMethodCaptureLoopVar),
      'Loop-Var nur als Call-Receiver vor der Closure - keine Capture');
  finally F.Free; end;
end;

procedure TTestAnonMethodCaptureLoopVar.LoopVarAsReceiverAndInClosureBody_Reported;
// TP-Gegenprobe zum Receiver-Gate: dieselbe Receiver-Form, aber der
// Closure-RUMPF liest die Loop-Var zusaetzlich - das ist die echte
// (deferred) Capture und muss weiter gemeldet werden.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var LNode: TSyntaxNode;'#13#10 +
  'begin'#13#10 +
  '  for LNode in ChildNodes do'#13#10 +
  '    LNode.Enqueue(procedure '#13#10 +
  '      begin WriteLn(LNode.Text); end);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.IsTrue(TFindingHelper.Count(F, fkAnonMethodCaptureLoopVar) >= 1,
      'Loop-Var im Closure-Rumpf bleibt ein Capture-Bug');
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestAnonMethodCaptureLoopVar);

end.
