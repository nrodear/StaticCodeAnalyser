unit uTestManagedResultUninit;

// Tests fuer SCA196 ManagedResultUninit (Variante 2: Result eines
// verwalteten Return-Typs wird gelesen, bevor es geschrieben wurde).
// Fallen-Matrix aus Todo_Detector_ManagedResultUninit_2026-08-07 par.6.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestManagedResultUninit = class
  public
    [Test] procedure DynArrayAppendWithoutInit_Reported;
    [Test] procedure DynArrayAppendAfterInit_NotReported;
    [Test] procedure SetLengthCountsAsInit_NotReported;
    [Test] procedure IndexWriteWithoutSetLength_Reported;
    [Test] procedure StringConcatWithoutInit_Reported;
    [Test] procedure TryGetValueCountsAsInit_NotReported;
    [Test] procedure ResultWordInsideStringLiteral_NotReported;
    [Test] procedure UnmanagedReturnType_NotReported;
    [Test] procedure AbsoluteResultAlias_NotReported;
    [Test] procedure InterfaceMethodCall_Reported_And_Sca121Silent;
    [Test] procedure ExitWithValueCountsAsInit_NotReported;
    [Test] procedure ExitReadingResult_Reported;
    [Test] procedure AddressOfResultCountsAsInit_NotReported;
    [Test] procedure RecordReturnType_NotReported;
    [Test] procedure Finding_KindAndSeverity;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12,
  uTestFindingHelper;

procedure TTestManagedResultUninit.DynArrayAppendWithoutInit_Reported;
// Kern-Pattern: Collector haengt an den ALTEN Aufrufer-Inhalt an.
const SRC =
  'unit t; implementation'#13#10 +
  'function CollectNames(L: TStrings): TArray<string>;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to L.Count - 1 do'#13#10 +
  '    Result := Result + [L[i]];'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninit.DynArrayAppendAfterInit_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'function CollectNames(L: TStrings): TArray<string>;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  Result := [];'#13#10 +
  '  for i := 0 to L.Count - 1 do'#13#10 +
  '    Result := Result + [L[i]];'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninit.SetLengthCountsAsInit_NotReported;
// Result als Call-Argument (var-Param) = Initialisierung.
const SRC =
  'unit t; implementation'#13#10 +
  'function MakeBuf(N: Integer): TBytes;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  SetLength(Result, N);'#13#10 +
  '  for i := 0 to N - 1 do'#13#10 +
  '    Result[i] := 0;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninit.IndexWriteWithoutSetLength_Reported;
// Element-Write in den alten/nil-Puffer des Aufrufers.
const SRC =
  'unit t; implementation'#13#10 +
  'function FirstByte(B: Byte): TBytes;'#13#10 +
  'begin'#13#10 +
  '  Result[0] := B;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninit.StringConcatWithoutInit_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'function JoinAll(L: TStrings): string;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 0 to L.Count - 1 do'#13#10 +
  '    Result := Result + L[i];'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninit.TryGetValueCountsAsInit_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'function Lookup(const Key: string): string;'#13#10 +
  'begin'#13#10 +
  '  if not FMap.TryGetValue(Key, Result) then'#13#10 +
  '    Result := Result + ''?'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninit.ResultWordInsideStringLiteral_NotReported;
// 'result' IN einem String-Literal ist kein Zugriff.
const SRC =
  'unit t; implementation'#13#10 +
  'function Banner: string;'#13#10 +
  'begin'#13#10 +
  '  Result := ''result: done'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninit.UnmanagedReturnType_NotReported;
// Integer-Result liegt in EAX - dafuer warnt W1035, nicht wir.
const SRC =
  'unit t; implementation'#13#10 +
  'function Total(N: Integer): Integer;'#13#10 +
  'var i: Integer;'#13#10 +
  'begin'#13#10 +
  '  for i := 1 to N do'#13#10 +
  '    Result := Result + i;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninit.AbsoluteResultAlias_NotReported;
// Writes laufen ueber den Alias - Methode wird komplett geskippt.
const SRC =
  'unit t; implementation'#13#10 +
  'function PackFlags: string;'#13#10 +
  'var S: string absolute Result;'#13#10 +
  'begin'#13#10 +
  '  S := ''x'';'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninit.InterfaceMethodCall_Reported_And_Sca121Silent;
// Kollisionsregel: SCA196 meldet, SCA121 bleibt fuer dieselbe Methode stumm
// (einziger Ueberlapp-Fall: Result wird NUR gelesen, nie geschrieben).
const SRC =
  'unit t; implementation'#13#10 +
  'function BrokenList: IStringList;'#13#10 +
  'begin'#13#10 +
  '  Result.Add(''x'');'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkManagedResultUninit));
    Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkRoutineResultUnassigned),
      'SCA121 muss stumm bleiben wo SCA196 feuert');
  finally F.Free; end;
end;

procedure TTestManagedResultUninit.ExitWithValueCountsAsInit_NotReported;
const SRC =
  'unit t; implementation'#13#10 +
  'function PickOne(Fast: Boolean): TArray<string>;'#13#10 +
  'begin'#13#10 +
  '  Exit(nil);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninit.ExitReadingResult_Reported;
const SRC =
  'unit t; implementation'#13#10 +
  'function WithTail(const S: string): TArray<string>;'#13#10 +
  'begin'#13#10 +
  '  Exit(Result + [S]);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(1, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninit.AddressOfResultCountsAsInit_NotReported;
// @Result -> Callee schreibt durch den Zeiger.
const SRC =
  'unit t; implementation'#13#10 +
  'function ReadBlob(Stream: TStream): TBytes;'#13#10 +
  'begin'#13#10 +
  '  FillBuffer(@Result);'#13#10 +
  '  Result := Result + [0];'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninit.RecordReturnType_NotReported;
// Records sind bewusst aus dem Typ-Gate raus (Feld-Writes = legitime
// Teil-Initialisierung).
const SRC =
  'unit t; implementation'#13#10 +
  'function MakePoint(X: Integer): TPoint;'#13#10 +
  'begin'#13#10 +
  '  Result.X := X;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninit.Finding_KindAndSeverity;
const SRC =
  'unit t; implementation'#13#10 +
  'function Collect(L: TStrings): TArray<string>;'#13#10 +
  'begin'#13#10 +
  '  Result := Result + [L[0]];'#13#10 +
  'end;';
var
  F   : TObjectList<TLeakFinding>;
  Fnd : TLeakFinding;
  Hit : TLeakFinding;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try
    Hit := nil;
    for Fnd in F do
      if Fnd.Kind = fkManagedResultUninit then begin Hit := Fnd; Break; end;
    Assert.IsNotNull(Hit, 'fkManagedResultUninit finding expected');
    Assert.AreEqual(lsWarning, Hit.Severity);
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestManagedResultUninit);

end.
