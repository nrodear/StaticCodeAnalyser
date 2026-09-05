unit uTestSetLengthAppendInLoop;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestSetLengthAppendInLoop = class
  public
    [Test] procedure ForLoopWithGrow_Reported;
    [Test] procedure WhileLoopWithGrow_Reported;
    [Test] procedure SetLengthOnceBeforeLoop_NotReported;
    [Test] procedure SetLengthOnDifferentArray_NotReported;
    [Test] procedure Finding_KindAndSeverity;
    // Real-World FP-Audit 2026-07-10 Regression (SCA157 rework: Guard A + C)
    [Test] procedure AppendInDifferentLooplessRoutine_NotReported;
    [Test] procedure RoomGuardedBlockGrowInLoop_NotReported;
    [Test] procedure UnguardedBlockGrowInLoop_Reported;
    // Real-World FP-Audit 2026-07-12 (Guard C: capacity-guarded Block-Grow,
    // Overflow-Formen '=' / '>=' / '>' / High())
    [Test] procedure CapacityGuardGeBlockGrow_NotReported;
    [Test] procedure CapacityGuardHighBlockGrow_NotReported;
    [Test] procedure CapacityGuardEqBlockGrow_NotReported;
    [Test] procedure CapacityGuardedGrowByOne_Reported;
    // Verify-Concern 2026-07-12: '<>' darf NICHT als Overflow-Guard zaehlen
    [Test] procedure NotEqualLenCheckBlockGrow_Reported;
    // --- Rumpfende-Gate (2026-09-05, Messung im Detektor-Kopf) ---
    [Test] procedure AfterForBodyEnd_NotReported;
    [Test] procedure AfterRepeatUntil_NotReported;
    // TP-Waechter fuer den else-Peek: '..end else SetLength(..)' ist
    // Teil des Schleifenstatements und MUSS Fund bleiben.
    [Test] procedure GrowInElseBranchOfLoopStatement_StillReported;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestSetLengthAppendInLoop.ForLoopWithGrow_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer; Dest: TArray<Integer>;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 9 do'#13#10 +
  '  begin'#13#10 +
  '    SetLength(Dest, Length(Dest) + 1);'#13#10 +
  '    Dest[High(Dest)] := i;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSetLengthAppendInLoop) >= 1);
  finally F.Free; end;
end;

procedure TTestSetLengthAppendInLoop.WhileLoopWithGrow_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var Buf: TArray<Byte>;'#13#10 +
  'begin'#13#10 +
  '  while More do'#13#10 +
  '  begin'#13#10 +
  '    SetLength(Buf, Length(Buf) + 1);'#13#10 +
  '    Buf[High(Buf)] := NextByte;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSetLengthAppendInLoop) >= 1);
  finally F.Free; end;
end;

procedure TTestSetLengthAppendInLoop.SetLengthOnceBeforeLoop_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo(Count: Integer);'#13#10 +
  'var i: Integer; Dest: TArray<Integer>;'#13#10 +
  'begin'#13#10 +
  '  SetLength(Dest, Count);'#13#10 +
  '  for i := 0 to Count - 1 do'#13#10 +
  '    Dest[i] := i;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSetLengthAppendInLoop));
  finally F.Free; end;
end;

procedure TTestSetLengthAppendInLoop.SetLengthOnDifferentArray_NotReported;
// SetLength(A, Length(B) + 1) - Detector verlangt das gleiche Array
// auf beiden Seiten; sonst ist es kein Append-Pattern.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer; A, B: TArray<Integer>;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 9 do'#13#10 +
  '    SetLength(A, Length(B) + 1);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSetLengthAppendInLoop));
  finally F.Free; end;
end;

procedure TTestSetLengthAppendInLoop.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Foo;'#13#10 +
  'var i: Integer; Dest: TArray<Integer>;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 9 do'#13#10 +
  '    SetLength(Dest, Length(Dest) + 1);'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkSetLengthAppendInLoop then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkSetLengthAppendInLoop finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

procedure TTestSetLengthAppendInLoop.AppendInDifferentLooplessRoutine_NotReported;
// Real-World FP-Audit 2026-07-10 (no-loop-lexical-window): das SetLength steht in
// einer eigenen, schleifen-losen Append-Prozedur; die naechste 'for'-Keyword im
// flachen 600-Zeichen-Fenster liegt in einer VORHERIGEN Routine. Guard A erkennt
// den Routine-Header dazwischen und unterdrueckt den FP (kein O(n*n)-Realloc).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure First;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to 9 do'#13#10 +
  '    DoSomething(i);'#13#10 +
  'end;'#13#10 +
  'procedure AppendField(const V: string);'#13#10 +
  'begin'#13#10 +
  '  SetLength(FArr, Length(FArr) + 1);'#13#10 +
  '  FArr[High(FArr)] := V;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSetLengthAppendInLoop),
    'SetLength in eigener schleifen-loser Routine ist kein Loop-Append');
  finally F.Free; end;
end;

procedure TTestSetLengthAppendInLoop.RoomGuardedBlockGrowInLoop_NotReported;
// Real-World FP-Audit 2026-07-10 (block-grow-guarded, MVCFramework HttpSys): der
// Realloc feuert nur wenn der freie Platz unter die Chunk-Groesse faellt
// ('if Length(Buf) - Written < 4096 then SetLength(Buf, Length(Buf) + 4096)') ->
// amortisiert O(n), kein O(n*n). Guard C unterdrueckt (gleiche Konstante in
// Bedingung UND Wachstum).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Grow(N: Integer);'#13#10 +
  'var i, Written: Integer; Buf: TArray<Byte>;'#13#10 +
  'begin'#13#10 +
  '  Written := 0;'#13#10 +
  '  for i := 0 to N - 1 do'#13#10 +
  '  begin'#13#10 +
  '    if Length(Buf) - Written < 4096 then'#13#10 +
  '      SetLength(Buf, Length(Buf) + 4096);'#13#10 +
  '    Buf[Written] := 0;'#13#10 +
  '    Inc(Written);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSetLengthAppendInLoop),
    'room-guarded Block-Grow ist amortisiert-linear, kein O(n*n)');
  finally F.Free; end;
end;

procedure TTestSetLengthAppendInLoop.UnguardedBlockGrowInLoop_Reported;
// TP-Guard (Todo_FP_SCA157): ungeguardetes Block-Grow reallociert JEDE Iteration
// -> weiterhin O(n*n), muss feuern. Grenzt den room-guarded-FP (Guard C) praezise
// vom echten Bug ab.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure BuildBuffer(N: Integer);'#13#10 +
  'var i: Integer; Buf: TArray<Byte>;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to N - 1 do'#13#10 +
  '  begin'#13#10 +
  '    SetLength(Buf, Length(Buf) + 256);'#13#10 +
  '    Buf[High(Buf)] := 0;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSetLengthAppendInLoop) >= 1,
    'ungeguardetes Block-Grow in Schleife bleibt O(n*n)-Fund');
  finally F.Free; end;
end;

procedure TTestSetLengthAppendInLoop.CapacityGuardGeBlockGrow_NotReported;
// Real-World FP-Audit 2026-07-12 (capacity-guarded Block-Grow, '>='-Overflow-Form,
// Alcinoe.Common): der Realloc feuert nur bei Kapazitaets-Ueberlauf
// 'if i >= Length(arr) then SetLength(arr, Length(arr)+100)' -> nur alle 100
// Iterationen = amortisiert O(n), kein O(n*n). Guard C matchte bisher nur die
// '<CHUNK'-Form; die '>='-Overflow-Form (Kapazitaet rechts) rutschte durch.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Grow(N: Integer);'#13#10 +
  'var i: Integer; arr: TArray<Byte>;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to N - 1 do'#13#10 +
  '  begin'#13#10 +
  '    if i >= Length(arr) then'#13#10 +
  '      SetLength(arr, Length(arr) + 100);'#13#10 +
  '    arr[i] := 0;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSetLengthAppendInLoop),
    'capacity-guarded Block-Grow (>=) ist amortisiert-linear, kein O(n*n)');
  finally F.Free; end;
end;

procedure TTestSetLengthAppendInLoop.CapacityGuardHighBlockGrow_NotReported;
// Real-World FP-Audit 2026-07-12 (capacity-guarded Block-Grow, High()-Form,
// Abbrevia AbCompnd-FAT): 'if i > High(arr) then SetLength(arr, Length(arr)+256)'
// - Realloc nur bei Index-Ueberlauf, in 256er-Bloecken = amortisiert-linear.
// Guard C erkennt jetzt auch die 'High(...)'-Kapazitaetsreferenz.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Grow(N: Integer);'#13#10 +
  'var i: Integer; arr: TArray<Byte>;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to N - 1 do'#13#10 +
  '  begin'#13#10 +
  '    if i > High(arr) then'#13#10 +
  '      SetLength(arr, Length(arr) + 256);'#13#10 +
  '    arr[i] := 0;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSetLengthAppendInLoop),
    'capacity-guarded Block-Grow (High/>) ist amortisiert-linear, kein O(n*n)');
  finally F.Free; end;
end;

procedure TTestSetLengthAppendInLoop.CapacityGuardEqBlockGrow_NotReported;
// Real-World FP-Audit 2026-07-12 (capacity-guarded Block-Grow, '='-Form, TES5Edit
// BSArch/frmMain): 'if Count = Length(arr) then SetLength(arr, Length(arr)+4096)'
// mit Count als Schreibposition - Realloc nur wenn voll, alle 4096 Elemente =
// amortisiert-linear. Guard C erkennt jetzt auch die '='-Overflow-Form.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Grow(N: Integer);'#13#10 +
  'var i, Count: Integer; arr: TArray<Byte>;'#13#10 +
  'begin'#13#10 +
  '  Count := 0;'#13#10 +
  '  for i := 0 to N - 1 do'#13#10 +
  '  begin'#13#10 +
  '    if Count = Length(arr) then'#13#10 +
  '      SetLength(arr, Length(arr) + 4096);'#13#10 +
  '    arr[Count] := 0;'#13#10 +
  '    Inc(Count);'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSetLengthAppendInLoop),
    'capacity-guarded Block-Grow (=) ist amortisiert-linear, kein O(n*n)');
  finally F.Free; end;
end;

procedure TTestSetLengthAppendInLoop.CapacityGuardedGrowByOne_Reported;
// TP-Gegenprobe (Real-World-FP-Audit 2026-07-12): ein Kapazitaets-Guard macht NUR
// Block-Grow (>1) amortisiert-linear. Wachstum um genau 1 reallociert trotz
// 'if i > High(arr) then' JEDE Iteration (High(arr) waechst mit i mit) -> bleibt
// O(n*n) und muss feuern. Grenzt die neue Guard-C-Erweiterung praezise vom echten
// Grow-by-1-Bug ab (GrowAmount='1' wird nicht als Kapazitaets-Guard akzeptiert).
const SRC =
  'unit t; implementation'#13#10 +
  'procedure BuildOne(N: Integer);'#13#10 +
  'var i: Integer; arr: TArray<Byte>;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to N - 1 do'#13#10 +
  '  begin'#13#10 +
  '    if i > High(arr) then'#13#10 +
  '      SetLength(arr, Length(arr) + 1);'#13#10 +
  '    arr[i] := 0;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSetLengthAppendInLoop) >= 1,
    'kapazitaets-geguardetes Grow-by-1 bleibt O(n*n)-Fund');
  finally F.Free; end;
end;

procedure TTestSetLengthAppendInLoop.NotEqualLenCheckBlockGrow_Reported;
// TP-Gegenprobe (Verify-Concern 2026-07-12): '<>' ist KEIN Overflow-/Kapazitaets-
// Guard. 'if x <> Length(arr) then SetLength(arr, Length(arr)+100)' schuetzt nicht
// vor Per-Iteration-Realloc -> muss weiter feuern. Sichert ab, dass die '(?<!<)>=?'-
// Lookbehind das '>' aus '<>' nicht faelschlich als Overflow-Vergleich matcht.
const SRC =
  'unit t; implementation'#13#10 +
  'procedure Grow(N: Integer);'#13#10 +
  'var i, x: Integer; arr: TArray<Byte>;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to N - 1 do'#13#10 +
  '  begin'#13#10 +
  '    if x <> Length(arr) then'#13#10 +
  '      SetLength(arr, Length(arr) + 100);'#13#10 +
  '    arr[i] := 0;'#13#10 +
  '  end;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try Assert.IsTrue(TFindingHelper.Count(F, fkSetLengthAppendInLoop) >= 1,
    '<> ist kein Kapazitaets-Guard - Block-Grow bleibt Fund');
  finally F.Free; end;
end;

procedure TTestSetLengthAppendInLoop.AfterForBodyEnd_NotReported;
// Korpus-Klasse (20 Zeilen in rw62, alle handgeprueft): Suchschleife,
// DANACH einmaliges Anhaengen - das klassische 'JoinGroup'-Muster
// (MVCFramework.WebSocket.Server:375), das der verworfene Guard B
// offen liess. Das Rumpfende ('end;' der for-Schleife) liegt beweisbar
// vor dem SetLength -> kein Fund. An der Exe vor dem Fix: gemeldet.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure JoinGroup(var Gruppen: TArray<string>; const Neu: string);'#13#10+
  'var I: Integer;'#13#10+
  'begin'#13#10+
  '  for I := 0 to Length(Gruppen) - 1 do'#13#10+
  '  begin'#13#10+
  '    if Gruppen[I] = Neu then'#13#10+
  '      Exit;'#13#10+
  '  end;'#13#10+
  '  SetLength(Gruppen, Length(Gruppen) + 1);'#13#10+
  '  Gruppen[Length(Gruppen) - 1] := Neu;'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSetLengthAppendInLoop),
      'Anhaengen NACH dem Schleifenrumpf ist kein O(n*n)-Realloc');
  finally F.Free; end;
end;

procedure TTestSetLengthAppendInLoop.AfterRepeatUntil_NotReported;
// Zweite Korpus-Form (UltimDBGrid:3457): repeat validiert eine Eingabe,
// das Anhaengen folgt NACH dem until - einmal pro Aufruf.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure Merke(var Liste: TArray<string>; Name: string);'#13#10+
  'begin'#13#10+
  '  repeat'#13#10+
  '    Name := Trim(Name);'#13#10+
  '  until Name <> '''';'#13#10+
  '  SetLength(Liste, Length(Liste) + 1);'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkSetLengthAppendInLoop),
      'Anhaengen nach until ist kein Realloc in der Schleife');
  finally F.Free; end;
end;

procedure TTestSetLengthAppendInLoop.GrowInElseBranchOfLoopStatement_StillReported;
// TP-WAECHTER, und der eigentliche Grund fuer den else-Peek des
// Scanners: 'for..do if..then begin..end else SetLength(..)' - das
// SetLength gehoert zum SCHLEIFENSTATEMENT (laeuft je Iteration).
// Ein Scanner, der am block-schliessenden end aufhoert, wuerde hier
// faelschlich gaten und einen echten O(n*n)-Fund kosten.
const SRC =
  'unit t;'#13#10+
  'interface'#13#10+
  'implementation'#13#10+
  'procedure Sammle(var A: TArray<Integer>; N: Integer);'#13#10+
  'var I: Integer;'#13#10+
  'begin'#13#10+
  '  for I := 0 to N do'#13#10+
  '    if I = 0 then'#13#10+
  '    begin'#13#10+
  '      A[0] := I;'#13#10+
  '    end'#13#10+
  '    else'#13#10+
  '      SetLength(A, Length(A) + 1);'#13#10+
  'end;'#13#10+
  'end.';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOfFile(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkSetLengthAppendInLoop),
      'Grow im else-Zweig des Schleifenstatements bleibt ein Fund');
  finally F.Free; end;
end;


initialization
  TDUnitX.RegisterTestFixture(TTestSetLengthAppendInLoop);


end.
