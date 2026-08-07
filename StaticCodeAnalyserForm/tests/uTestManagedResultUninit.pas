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

  // FP-Sturm-Fixes nach der ersten Korpus-Messung 2026-08-07 (1985
  // FnName-FPs + 37 ShortString + 5 TDynArray + 1 ALL-CAPS) - eigene
  // Fixture, damit keine der beiden Klassen die GodClass-Schwelle reisst.
  [TestFixture]
  TTestManagedResultUninitAlias = class
  public
    [Test] procedure RecursiveDelegation_NotReported;
    [Test] procedure InheritedSameName_NotReported;
    [Test] procedure QualifiedSameNameCall_NotReported;
    [Test] procedure ForeignResultField_NotReported;
    [Test] procedure BareFnNameOnRhs_IsRecursiveCall_NotReported;
    [Test] procedure ShortStringLengthByteIdiom_NotReported;
    [Test] procedure TDynArrayRecordInit_NotReported;
    [Test] procedure AllCapsPseudoInterface_NotReported;
    // 2. Korpus-Messung (105 Funde, 10/15 FP) - Runde-2-Mechanismen:
    [Test] procedure OverloadDelegation_NotReported;
    [Test] procedure IfdefTwinAssign_NotReported;
    [Test] procedure ApiBufferFillViaAddressOf_NotReported;
    [Test] procedure AnonymousInnerResult_NotReported;
    [Test] procedure QualifiedExitArgSameName_NotReported;
  end;

implementation

// noinspection-file ClassPerFile
// Zwei thematisch zusammengehoerige Fixtures (Kern-Matrix + FnName-Alias-
// Faelle) in einer Unit - gleiche Konvention wie uTestDuplicate u.a.

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

procedure TTestManagedResultUninitAlias.RecursiveDelegation_NotReported;
// Korpus-FP-Klasse 1 (dominant): `Result := GetPlainText(A, B)` in
// GetPlainText - Rekursion/Overload-Delegation, kein Result-Alias.
const SRC =
  'unit t; implementation'#13#10 +
  'function GetText(A: Integer): string;'#13#10 +
  'begin'#13#10 +
  '  Result := GetText(A, True);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninitAlias.InheritedSameName_NotReported;
// Korpus-FP-Klasse 2: `Result := inherited GetAsString;` - Parent-Aufruf.
const SRC =
  'unit t; implementation'#13#10 +
  'function GetAsString: string;'#13#10 +
  'begin'#13#10 +
  '  Result := inherited GetAsString;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninitAlias.QualifiedSameNameCall_NotReported;
// Korpus-FP-Klasse 3: `Result := FOld.GetTitle;` - gleichnamige Methode
// eines ANDEREN Objekts.
const SRC =
  'unit t; implementation'#13#10 +
  'function GetTitle: string;'#13#10 +
  'begin'#13#10 +
  '  Result := FOldService.GetTitle;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninitAlias.ForeignResultField_NotReported;
// `FTask.Result` ist ein FELD eines fremden Objekts, kein Result-Zugriff.
const SRC =
  'unit t; implementation'#13#10 +
  'function GetVal: string;'#13#10 +
  'begin'#13#10 +
  '  Result := FTask.Result;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninitAlias.BareFnNameOnRhs_IsRecursiveCall_NotReported;
// Delphi-Semantik: der nackte Function-Name ist im AUSDRUCKSKONTEXT ein
// (rekursiver) AUFRUF, nie der Result-Alias - der Alias existiert nur
// als Zuweisungsziel links vom ':='. `Acc` auf der RHS ruft Acc auf.
const SRC =
  'unit t; implementation'#13#10 +
  'function Acc(L: TStrings): string;'#13#10 +
  'begin'#13#10 +
  '  Acc := Acc + L[0];'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninitAlias.OverloadDelegation_NotReported;
// 2. Korpus-Messung: `Result := Put;` ruft die parameterlose
// Ueberladung auf (MVCFramework/HeidiSQL-Idiom) - reiner Write.
const SRC =
  'unit t; implementation'#13#10 +
  'function TClientX.Put(const aResource: string): IRestResponse;'#13#10 +
  'begin'#13#10 +
  '  AddBody(aResource);'#13#10 +
  '  Result := Put;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninitAlias.IfdefTwinAssign_NotReported;
// IFDEF-Zwilling ohne Semikolon: der Parser behaelt beide Zweige, die
// zweite Zuweisung landet als Text in der RHS der ersten - Artefakt,
// kein Lesen (JvBDEReg/mormot-HttpGet-Muster).
const SRC =
  'unit t; implementation'#13#10 +
  'function GetValue: string;'#13#10 +
  'begin'#13#10 +
  '  if Cond then'#13#10 +
  '{$IFDEF WIN32}'#13#10 +
  '    Result := Format(''(%s)'', [A])'#13#10 +
  '{$ELSE}'#13#10 +
  '    Result := Format(''(%s)'', [B])'#13#10 +
  '{$ENDIF}'#13#10 +
  '  else'#13#10 +
  '    Result := C;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninitAlias.ApiBufferFillViaAddressOf_NotReported;
// `Result[0] := Char(Api(@Result[1], N))` - die API fuellt den Puffer
// durch den Zeiger, das Laengen-Element begrenzt darauf (JvFileUtil).
const SRC =
  'unit t; implementation'#13#10 +
  'function GetWindowsDir: string;'#13#10 +
  'begin'#13#10 +
  '  Result[0] := Char(GetWindowsDirectory(@Result[1], 254));'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninitAlias.AnonymousInnerResult_NotReported;
// Das `Result` in einer EINGEBETTETEN anonymen Methode gehoert ihr
// selbst (TDelegatedComparer-Idiom) - kein Lesen des aeusseren Result.
const SRC =
  'unit t; implementation'#13#10 +
  'function BuildParams: TArray<string>;'#13#10 +
  'begin'#13#10 +
  '  lComparer := TDelegatedComparer<string>.Create('#13#10 +
  '    function(const L, R: string): Integer'#13#10 +
  '    begin'#13#10 +
  '      Result := CompareText(L, R);'#13#10 +
  '    end);'#13#10 +
  '  SetLength(Result, 0);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninitAlias.QualifiedExitArgSameName_NotReported;
// `Exit(FWebSession.SessionId)` in der Function SessionId: der Selektor
// hinter dem Punkt (auch mit Token-Spaces 'x . y') gehoert dem fremden
// Objekt - kein Result-Lesen (MVCFramework TWebContext.SessionId).
const SRC =
  'unit t; implementation'#13#10 +
  'function SessionId: string;'#13#10 +
  'begin'#13#10 +
  '  if Assigned(FWebSession) then'#13#10 +
  '    Exit(FWebSession.SessionId);'#13#10 +
  '  Result := ExtractFromRequest(fRequest);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninitAlias.ShortStringLengthByteIdiom_NotReported;
// `Result[0] := AnsiChar(Len)` setzt bei ShortString das Laengenbyte -
// das IST die Initialisierung (mormot/DCU32-Idiom, 37 Korpus-FPs).
const SRC =
  'unit t; implementation'#13#10 +
  'function PackByte(B: Byte): ShortString;'#13#10 +
  'begin'#13#10 +
  '  Result[0] := AnsiChar(1);'#13#10 +
  '  Result[1] := AnsiChar(B);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninitAlias.TDynArrayRecordInit_NotReported;
// mormots TDynArray ist ein RECORD-Wrapper (kein dynamisches Array) -
// `Result.Init(...)` ist legitime Initialisierung. Der *DynArray-
// Suffix-Match nimmt 'TDynArray' exakt aus.
const SRC =
  'unit t; implementation'#13#10 +
  'function Wrap(T: Pointer): TDynArray;'#13#10 +
  'begin'#13#10 +
  '  Result.Init(T, FValue);'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

procedure TTestManagedResultUninitAlias.AllCapsPseudoInterface_NotReported;
// ICONMETRICS/IMAGEINFO & Co. sind Windows-API-RECORDS in ALL-CAPS -
// die I+Grossbuchstabe-Interface-Heuristik nimmt Voll-Versalien aus.
const SRC =
  'unit t; implementation'#13#10 +
  'function GetMetrics: ICONMETRICS;'#13#10 +
  'begin'#13#10 +
  '  Result.iIconSpacing := 4;'#13#10 +
  'end;';
var F: TObjectList<TLeakFinding>;
begin
  F := TFindingHelper.FindingsOf(SRC);
  try Assert.AreEqual<Integer>(0, TFindingHelper.Count(F, fkManagedResultUninit));
  finally F.Free; end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestManagedResultUninit);
  TDUnitX.RegisterTestFixture(TTestManagedResultUninitAlias);

end.
